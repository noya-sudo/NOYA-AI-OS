-- Refinement of 20260929096000: when a provider-verified named person is found, point the
-- opportunity at them if it currently has no contact or only an unnamed placeholder (e.g. a
-- company inbox row). Otherwise the draft would greet the person while HQ resolved the recipient
-- to the inbox. A named contact is never replaced.

create or replace function public.apply_contact_email_verification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(new.email));
  v_company public.companies%rowtype;
  v_contact public.contacts%rowtype;
  v_status text;
  v_prov text;
begin
  new.email := v_email;
  new.provider := upper(btrim(new.provider));

  v_status := case
    when lower(coalesce(new.provider_status, '')) = 'valid'
         and lower(coalesce(new.provider_result, '')) = 'deliverable'
         and coalesce(new.accept_all, false) = false then 'VERIFIED'
    when lower(coalesce(new.provider_status, '')) = 'invalid'
         or lower(coalesce(new.provider_result, '')) = 'undeliverable' then 'INVALID'
    when lower(coalesce(new.provider_status, '')) in ('accept_all', 'webmail', 'disposable', 'unknown')
         or lower(coalesce(new.provider_result, '')) = 'risky'
         or coalesce(new.accept_all, false) then 'RISKY'
    else 'UNVERIFIED'
  end;
  if v_status <> 'VERIFIED' then
    new.outcome := 'LOGGED_NOT_VERIFIED:' || v_status;
    return new;
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    new.outcome := 'SKIPPED:MALFORMED_EMAIL'; return new;
  end if;
  if email_kind(v_email) <> 'DIRECT_PERSON_EMAIL' then
    new.outcome := 'SKIPPED:COMPANY_INBOX_NOT_A_PERSON'; return new;
  end if;
  if coalesce(btrim(new.first_name), '') = '' or coalesce(btrim(new.last_name), '') = '' then
    new.outcome := 'SKIPPED:NO_FULL_NAME'; return new;
  end if;

  select * into v_company from companies where id = new.company_id;
  if v_company.id is null then
    new.outcome := 'SKIPPED:NO_COMPANY'; return new;
  end if;
  if coalesce(btrim(v_company.website), '') = ''
     or registrable_domain(split_part(v_email, '@', 2)) <> registrable_domain(v_company.website) then
    new.outcome := 'SKIPPED:DOMAIN_NOT_COMPANY_DOMAIN'; return new;
  end if;

  v_prov := 'hunter:email-verifier status=valid result=deliverable score=' || coalesce(new.provider_score::text, '?')
         || ' checked_at=' || to_char(new.checked_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
         || ' workflow=' || new.source_workflow || coalesce(' exec=' || new.source_execution, '')
         || ' log=' || new.id;

  -- Same person, same company. The caller's contact_id is only a tie-breaker.
  select * into v_contact from contacts k
   where k.company_id = new.company_id
     and lower(btrim(k.first_name)) = lower(btrim(new.first_name))
     and lower(btrim(coalesce(k.last_name, ''))) = lower(btrim(new.last_name))
   order by (k.id = new.contact_id) desc nulls last, k.created_at
   limit 1;

  if v_contact.id is null then
    insert into contacts (company_id, first_name, last_name, position, email, email_status, email_source_url,
                          source, confidence, status, do_not_contact)
    values (new.company_id, btrim(new.first_name), btrim(new.last_name), nullif(btrim(coalesce(new.position, '')), ''),
            v_email, 'VERIFIED', v_prov, new.source_workflow, 70, 'NEW', false)
    returning * into v_contact;
    new.outcome := 'CREATED_CONTACT';
  elsif v_contact.do_not_contact or v_contact.status = 'DO_NOT_CONTACT' then
    new.applied_contact_id := v_contact.id;
    new.outcome := 'SKIPPED:DO_NOT_CONTACT'; return new;
  elsif coalesce(btrim(v_contact.email), '') = '' then
    update contacts set email = v_email, email_status = 'VERIFIED', email_source_url = v_prov where id = v_contact.id;
    new.outcome := 'APPLIED_NEW_EMAIL';
  elsif lower(btrim(v_contact.email)) = v_email then
    update contacts
       set email_status = 'VERIFIED',
           email_source_url = case when email_source_url is null or email_source_url like 'WF05 contact resolution%'
                                        or email_source_url like 'hunter:%' then v_prov else email_source_url end
     where id = v_contact.id;
    new.outcome := 'CONFIRMED_EXISTING_EMAIL';
  else
    -- Never overwrite a different address automatically; the log row is the evidence for Adam.
    new.applied_contact_id := v_contact.id;
    new.outcome := 'SKIPPED:CONTACT_HAS_DIFFERENT_EMAIL'; return new;
  end if;

  new.applied_contact_id := v_contact.id;
  -- Point the opportunity at this verified person if it has no contact, or only an unnamed
  -- placeholder (e.g. a company inbox row). Never re-point away from a named person.
  update opportunities o set contact_id = v_contact.id
   where o.id = new.opportunity_id
     and (o.contact_id is null
          or exists (select 1 from contacts p where p.id = o.contact_id
                      and coalesce(btrim(p.first_name), '') = ''));
  update opportunities set contact_email = v_email, email_status = 'VERIFIED'
   where contact_id = v_contact.id
     and (contact_email is null or btrim(contact_email) = '' or lower(btrim(contact_email)) = v_email);
  return new;
end $$;
