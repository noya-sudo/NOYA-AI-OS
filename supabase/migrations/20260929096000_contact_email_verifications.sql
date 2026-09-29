-- Verified email -> canonical CRM contact, from STRUCTURED provider evidence only.
--
-- Replaces 20260929095000 (which copied a VERIFIED address out of the draft text's
-- OUTREACH_READY_JSON line). Draft text is never a source of truth for a recipient.
--
-- contact_email_verifications is an append-only evidence log: one row per provider check
-- (Hunter email-finder + email-verifier), written by Workflow 05 straight from the provider
-- response. It is not a CRM table; contacts stays canonical. A BEFORE INSERT trigger applies
-- a row to contacts only when ALL of these hold:
--   * provider status = valid AND result = deliverable AND not accept-all (catch-all = RISKY)
--   * the address is a person's address, not a company inbox
--   * first AND last name are known
--   * the email's registrable domain = the company's website registrable domain
--   * the canonical contact is the same person (same company, same first + last name)
--   * the contact has no email yet (or already has this exact email) -- never overwrites
--   * the contact is not do-not-contact
-- If no contact exists for that named person at that company, one is created from the
-- verified identity. Every row records its outcome, so skipped results stay visible.

create table if not exists public.contact_email_verifications (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  company_id uuid references public.companies(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  contact_id uuid references public.contacts(id) on delete set null,  -- caller's hint; identity is re-checked
  first_name text,
  last_name text,
  position text,
  email text not null,
  provider text not null,                 -- HUNTER
  provider_status text,                   -- verifier data.status: valid / invalid / accept_all / webmail / disposable / unknown
  provider_result text,                   -- verifier data.result: deliverable / undeliverable / risky
  provider_score smallint,                -- verifier data.score
  finder_score smallint,                  -- finder data.score
  accept_all boolean,
  provider_verification_date date,        -- provider's own verification.date
  checked_at timestamptz not null,        -- when the workflow received the verifier response
  source_workflow text not null,
  source_execution text,
  evidence_sources jsonb,                 -- provider 'sources' (public pages where the address was seen)
  outcome text,                           -- set by trigger
  applied_contact_id uuid references public.contacts(id) on delete set null
);
create index if not exists contact_email_verifications_email_idx on public.contact_email_verifications (lower(email));
create index if not exists contact_email_verifications_contact_idx on public.contact_email_verifications (applied_contact_id);
alter table public.contact_email_verifications enable row level security;
revoke all on public.contact_email_verifications from anon, authenticated;

-- Company inboxes: widen the local-part rule (e.g. sponsorshipenquiries@ was read as a person).
create or replace function public.email_kind(p_email text)
returns text language sql immutable as $$
  select case
    when p_email is null or p_email !~ '@' then null
    when lower(split_part(p_email, '@', 1)) ~ '^(info|hello|hi|contact|contactus|enquiries|enquiry|inquiries|inquiry|partnerships?|partners|events?|press|pr|media|newbusiness|new\.business|business|sales|bookings?|reservations?|office|team|admin|marketing|concierge|membership|members|support|help|general|reception|careers|jobs|hr|studio|mail|weddings?|sponsorship)$'
      or lower(split_part(p_email, '@', 1)) ~ '(enquir|inquir|sponsor|partnership|membership|reservation|booking|concierge)'
      then 'OFFICIAL_COMPANY_INBOX'
    else 'DIRECT_PERSON_EMAIL'
  end
$$;

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
  -- Link the opportunity to this contact only if it has none, and mirror the recipient.
  update opportunities set contact_id = v_contact.id
   where id = new.opportunity_id and contact_id is null;
  update opportunities set contact_email = v_email, email_status = 'VERIFIED'
   where contact_id = v_contact.id
     and (contact_email is null or btrim(contact_email) = '' or lower(btrim(contact_email)) = v_email);
  return new;
end $$;

drop trigger if exists trg_apply_contact_email_verification on public.contact_email_verifications;
create trigger trg_apply_contact_email_verification
before insert on public.contact_email_verifications
for each row execute function public.apply_contact_email_verification();

-- Retire the draft-text sync.
drop trigger if exists trg_sync_contact_from_outreach_ready on public.tasks;
drop function if exists public.sync_contact_from_outreach_ready();

-- Backfill the two results the draft-text sync had copied, from the real provider responses
-- in Workflow 05 execution 628 (Hunter finder + verifier, 29 Sep 2026). The trigger re-checks
-- identity and domain and replaces the weaker provenance note.
insert into public.contact_email_verifications
  (company_id, opportunity_id, contact_id, first_name, last_name, position, email, provider, provider_status,
   provider_result, provider_score, finder_score, accept_all, provider_verification_date, checked_at,
   source_workflow, source_execution, evidence_sources)
select c.id, o.id, k.id, v.first_name, v.last_name, v.position, v.email, 'HUNTER', 'valid', 'deliverable', 100,
       v.finder_score, false, v.vdate, v.checked_at, '05 - NOYA Sales & Outreach Department v1', '628', v.sources
from (values
  ('YKONE Middle East', 'Magali', 'Rady', 'Regional Managing Director', 'magali@ykone.com', 98, date '2026-09-04',
   timestamptz '2026-09-29 16:05:52.466+00',
   '[{"domain":"linkedin.com","uri":"https://www.google.com/search?q=site:linkedin.com%20magali%20rady%20ykone","extracted_on":"2025-08-06","last_seen_on":"2026-08-26","still_on_page":true},{"domain":"job.techtunity.com","uri":"https://job.techtunity.com/2022/04/khaleej-times-jobs-in-dubai-across-uae.html","extracted_on":"2026-08-19","last_seen_on":"2026-08-19","still_on_page":true}]'::jsonb),
  ('MCI Middle East', 'Alexander', 'John', 'Regional Director of Business Development', 'alexander.john@wearemci.com', 97, date '2026-09-29',
   timestamptz '2026-09-29 16:06:27.021+00',
   '[{"domain":"linkedin.com","uri":"https://www.google.com/search?q=site:linkedin.com%20alexander%20john%20wearemci","extracted_on":"2025-01-10","last_seen_on":"2026-08-07","still_on_page":true},{"domain":"wearemci.com","uri":"https://wearemci.com/ar-ae/about-us/mci-middle-east","extracted_on":"2024-11-28","last_seen_on":"2024-11-28","still_on_page":true}]'::jsonb)
) as v(company, first_name, last_name, position, email, finder_score, vdate, checked_at, sources)
join public.companies c on c.name = v.company
left join public.contacts k on k.company_id = c.id and k.first_name = v.first_name and k.last_name = v.last_name
left join lateral (select id from public.opportunities where company_id = c.id order by (contact_id = k.id) desc nulls last, created_at limit 1) o on true
where not exists (select 1 from public.contact_email_verifications x where x.email = v.email and x.source_execution = '628');

-- Role labels stored as a person's name ("Partnerships Team", "Marketing Team", "Membership Team")
-- are company inboxes, not people. Clear the fake name; keep the role and the published inbox.
update public.contacts
   set notes = concat_ws(E'\n', notes, 'Data repair 29 Sep 2026: role label "' || concat_ws(' ', first_name, last_name) || '" was stored as a person name; cleared (company inbox, no named person).'),
       first_name = null, last_name = null
 where first_name ~* '^(partnerships?|marketing|membership|members|events?|press|sales|info|general|reservations?|concierge|admin|team|enquiries|bookings?)$'
   and (last_name is null or last_name ~* '^(team|department|office|desk|inbox)$');
update public.opportunities
   set contact_first_name = null, contact_last_name = null
 where contact_first_name ~* '^(partnerships?|marketing|membership|members|events?|press|sales|info|general|reservations?|concierge|admin|team|enquiries|bookings?)$'
   and (contact_last_name is null or contact_last_name ~* '^(team|department|office|desk|inbox)$');

-- Provenance and false-VERIFIED audit (deterministic). quality_issue must be null for every
-- VERIFIED address; a non-null value is a false or unsupported VERIFIED.
create or replace view public.contact_email_provenance
with (security_invoker = true) as
select k.id as contact_id, co.name as company, k.first_name, k.last_name, k.email, k.email_status,
       email_kind(k.email) as email_kind,
       case
         when coalesce(btrim(k.email), '') = '' then 'NO_EMAIL'
         when k.email_status <> 'VERIFIED' then 'NOT_VERIFIED'
         when v.id is not null then 'PROVIDER_VERIFIED_LOGGED'
         when k.email_source_url ~* '^https?://' then 'PUBLISHED_ON_OFFICIAL_SOURCE'
         else 'LEGACY_PROVIDER_VERIFIED_NO_STORED_EVIDENCE'
       end as provenance,
       v.provider, v.provider_status, v.provider_result, v.provider_score, v.checked_at, v.source_workflow,
       v.source_execution, k.email_source_url, k.source as contact_source,
       case
         when k.email_status <> 'VERIFIED' then null
         when k.email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then 'MALFORMED_EMAIL'
         when split_part(lower(k.email), '@', 2) ~ '^(gmail|googlemail|yahoo|hotmail|outlook|icloud|aol|live|msn|proton|protonmail)\.' then 'WEBMAIL_MARKED_VERIFIED'
         when exists (select 1 from contact_email_verifications x
                       where lower(x.email) = lower(btrim(k.email)) and x.outcome like 'LOGGED_NOT_VERIFIED%'
                         and x.checked_at > coalesce(v.checked_at, '-infinity'::timestamptz)) then 'LATEST_PROVIDER_CHECK_NOT_VALID'
         when coalesce(co.website, '') <> '' and co.website !~* '(instagram\.com|linkedin\.com|facebook\.com|linktr\.ee|tiktok\.com)'
              and registrable_domain(split_part(k.email, '@', 2)) <> registrable_domain(co.website) then 'EMAIL_DOMAIN_NOT_COMPANY_DOMAIN'
         else null
       end as quality_issue
from contacts k
left join companies co on co.id = k.company_id
left join lateral (
  select * from contact_email_verifications x
   where x.applied_contact_id = k.id and lower(x.email) = lower(btrim(k.email))
     and x.outcome in ('APPLIED_NEW_EMAIL', 'CONFIRMED_EXISTING_EMAIL', 'CREATED_CONTACT')
   order by x.checked_at desc limit 1
) v on true;
revoke all on public.contact_email_provenance from anon, authenticated;
