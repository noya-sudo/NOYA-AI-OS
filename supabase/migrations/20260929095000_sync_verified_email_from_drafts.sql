-- Keep the CRM consistent with Workflow 05's contact resolution.
-- 05 resolves and verifies an email (Serper -> Hunter finder -> Hunter verifier) and
-- writes it into the draft's OUTREACH_READY_JSON line, but it did not write it back to
-- the contact row. HQ approval reads the recipient from contacts.email, so a verified
-- draft could not be approved.
-- This trigger copies a VERIFIED direct-person email from the draft to the linked
-- contact ONLY when the contact has no email yet. It never overwrites an existing email,
-- never copies UNVERIFIED/RISKY/inbox addresses, and records its source.

create or replace function public.sync_contact_from_outreach_ready()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ready jsonb;
  v_contact_id uuid;
begin
  if new.description is null or new.description not like '%OUTREACH_READY_JSON:%' then
    return new;
  end if;
  v_ready := try_jsonb(substring(new.description from 'OUTREACH_READY_JSON: (\{[^\n]*\})'));
  if v_ready is null
     or coalesce(v_ready->>'email_status', '') <> 'VERIFIED'
     or coalesce(v_ready->>'email_kind', '') <> 'DIRECT_PERSON_EMAIL'
     or coalesce(v_ready->>'email', '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return new;
  end if;

  v_contact_id := coalesce(new.contact_id, (select contact_id from opportunities where id = new.opportunity_id));
  if v_contact_id is null then
    return new;
  end if;

  update contacts
     set email = lower(btrim(v_ready->>'email')),
         email_status = 'VERIFIED',
         email_source_url = coalesce(email_source_url, 'WF05 contact resolution (Hunter verifier) ' || to_char(now(), 'YYYY-MM-DD')),
         updated_at = now()
   where id = v_contact_id
     and (email is null or btrim(email) = '')
     and coalesce(do_not_contact, false) = false
     -- same person only: the draft's named contact must match this contact's first name
     and lower(btrim(first_name)) = lower(split_part(btrim(coalesce(v_ready->>'contact_name', '')), ' ', 1));
  if not found then
    return new;
  end if;

  update opportunities
     set contact_email = lower(btrim(v_ready->>'email')), email_status = 'VERIFIED', updated_at = now()
   where id = new.opportunity_id
     and (contact_email is null or btrim(contact_email) = '');

  return new;
end $$;

drop trigger if exists trg_sync_contact_from_outreach_ready on public.tasks;
create trigger trg_sync_contact_from_outreach_ready
after insert or update of description on public.tasks
for each row execute function public.sync_contact_from_outreach_ready();

-- Backfill: re-fire for open drafts written before the trigger existed.
update public.tasks set description = description
where status in ('OPEN', 'IN_PROGRESS', 'WAITING') and description like '%OUTREACH_READY_JSON:%';
