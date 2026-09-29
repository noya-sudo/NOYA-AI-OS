-- Data repair: the 28 Sep curated research import (run_id CHATGPT_RESEARCH_2026_09_28)
-- shifted the contact columns by one: next_action held the first name,
-- contact_first_name held the surname and contact_last_name held the role.
-- The shift is structural (it is identical on every affected row and matches the
-- company names "Alice Wilkes Design" and "Sarah Haywood"), so the repair moves the
-- values back; it never adds a name that was not in the import.
-- Rows with only a target role and no person get the role moved to next_action and
-- no contact. Ambiguous rows (two first names, no surnames) get no contact.
-- Emails stay NOT_FOUND: nothing here is verified.

begin;

-- 1. Named people: next_action = first name, first_name = surname, last_name = role.
with fix as (
  select id, next_action as fn, contact_first_name as ln, contact_last_name as pos, suggested_approach
  from opportunities
  where run_id = 'CHATGPT_RESEARCH_2026_09_28'
    and contact_first_name is not null
    and next_action ~ '^[A-Z][a-zA-Z-]+$'
    and contact_last_name ~* '(founder|director|ceo|partner|head|manager|president)'
)
update opportunities o
set contact_first_name = fix.fn,
    contact_last_name  = fix.ln,
    contact_position   = fix.pos,
    next_action = 'Confirm the channel for ' || fix.fn || ' ' || fix.ln || ' (' || fix.pos || ') from public sources, then prepare outreach for Adam to send. ' || coalesce(fix.suggested_approach, ''),
    updated_at = now()
from fix where o.id = fix.id;

-- 2. Double Culture Films: first name only, surname never captured.
update opportunities
set contact_first_name = 'Sofiane', contact_last_name = null,
    contact_position = 'Founder / Executive Producer',
    next_action = 'Resolve the surname and channel for Sofiane (Founder / Executive Producer) from public sources, then prepare outreach for Adam to send.',
    updated_at = now()
where id = 'ce94f2ce-f8cb-40dc-a47d-5d01c52f2d7b' and next_action = 'Sofiane';

-- 3. Summits: two founders named only by first name. No single contact is recorded.
update opportunities
set contact_first_name = null, contact_last_name = null, contact_position = null,
    next_action = 'Founders publicly named as Lukas and Jonas (surnames unverified). Resolve the right founder and channel, then email a concrete 6-7 day Egypt founder-cohort concept.',
    updated_at = now()
where id = 'fcfcbfc3-4860-4713-94f6-c82a4ddf9fe5' and next_action = 'Lukas & Jonas';

-- 4. Target role only, no person.
update opportunities
set next_action = 'Target role: ' || contact_last_name || '. Resolve a named decision-maker from public sources, then prepare outreach for Adam to send.',
    contact_last_name = null,
    updated_at = now()
where run_id = 'CHATGPT_RESEARCH_2026_09_28'
  and contact_first_name is null
  and contact_last_name is not null
  and next_action is null;

-- 5. Task descriptions that swallowed the shifted name.
update tasks set description = replace(description, 'Deep-researched 28 Sep. Sofiane ', 'Deep-researched 28 Sep. Founder / Executive Producer: Sofiane (surname unresolved). '), updated_at = now()
where id = '404e9e8f-9c56-4c68-9324-aeecf16b7236' and description like 'Deep-researched 28 Sep. Sofiane %';
update tasks set description = replace(description, 'Deep-researched 28 Sep. Lukas & Jonas ', 'Deep-researched 28 Sep. Founders Lukas and Jonas (surnames unverified). '), updated_at = now()
where id = 'f7c8bda2-a609-46bf-9268-bced70d363c4' and description like 'Deep-researched 28 Sep. Lukas & Jonas %';

-- 6. YKONE: a personal LinkedIn profile was stored as the company page.
update companies set linkedin = null, updated_at = now()
where id = '70b2d127-6704-4bf5-86cb-852e783c8d05' and linkedin = 'https://ae.linkedin.com/in/magalirady';

-- 7. Contacts for every named person, linked to the opportunity. One per company.
with named as (
  select o.id opp_id, o.company_id, o.contact_first_name fn, o.contact_last_name ln, o.contact_position pos,
         o.contact_linkedin_url li, c.country, c.city
  from opportunities o join companies c on c.id = o.company_id
  where o.run_id like 'CHATGPT_%2026_09_28' and o.contact_id is null and o.contact_first_name is not null
    and not exists (select 1 from contacts x where x.company_id = o.company_id)
), ins as (
  insert into contacts (company_id, first_name, last_name, position, email_status, linkedin, country, city,
                        source, confidence, status, do_not_contact, notes)
  select company_id, fn, ln, pos, 'NOT_FOUND', li, country, city,
         'CHATGPT_DEEP_RESEARCH_2026_09_28', 60, 'NEW', false,
         'Name and role from the 28 Sep curated research import (column shift repaired 29 Sep). Email not found; channel to confirm before any outreach.'
  from named
  returning id, company_id
)
update opportunities o set contact_id = ins.id, updated_at = now()
from ins where o.company_id = ins.company_id and o.run_id like 'CHATGPT_%2026_09_28' and o.contact_id is null;

-- 8. A contact-resolution task wherever the opportunity has no named person and no open task.
insert into tasks (company_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status)
select o.company_id, o.id, 'RESOLVE CONTACT — ' || o.company_name, o.next_action, 'CONTACT_RESEARCH', 'SYSTEM', 'DATA_REPAIR_2026_09_29', o.priority, 'OPEN'
from opportunities o
where o.run_id like 'CHATGPT_%2026_09_28' and o.contact_id is null
  and not exists (select 1 from tasks t where t.opportunity_id = o.id and t.status in ('OPEN','IN_PROGRESS','WAITING'));

commit;
