-- Final data-quality pass (29 Sep 2026). Deterministic; every change is derived from data
-- already in the CRM. No contact, email, role or company is invented.

-- 1. Channel rule: Instagram is a primary channel only for Instagram-native accounts. Banks,
--    wealth, law, consulting and investment firms never route to Instagram (same rule as
--    Workflow 05's draft builder). They fall to LinkedIn or contact resolution instead.
create or replace view public.outreach_readiness
with (security_invoker = true) as
with opp as (
  select o.*, c.name as company, c.instagram as company_instagram, c.linkedin as company_linkedin,
         c.website as company_website, c.notes as company_notes,
         commercial_vertical(o.opportunity_type, coalesce(o.company_type, c.company_type)) as vertical,
         (coalesce(o.company_type, c.company_type, '') || ' ' || coalesce(o.opportunity_type, ''))
           ~* '(BANK|WEALTH|LAW|LEGAL|CONSULT|INVEST|FAMILY.OFFICE|FINANCIAL|INSURANCE|ASSET.MANAGEMENT|PRIVATE.EQUITY)' as formal_sector
  from opportunities o
  join companies c on c.id = o.company_id
  where o.status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM')
    and coalesce(c.notes, '') not like '%MERGED_INTO:%'
), ct as (
  select opp.id as opportunity_id,
         coalesce(nullif(trim(k.first_name || ' ' || coalesce(k.last_name, '')), ''), nullif(trim(coalesce(opp.contact_first_name, '') || ' ' || coalesce(opp.contact_last_name, '')), '')) as contact_name,
         coalesce(k.position, opp.contact_position) as contact_role,
         coalesce(k.email, opp.contact_email) as email,
         coalesce(k.email_status, opp.email_status, 'UNKNOWN') as email_status,
         coalesce(k.linkedin, opp.contact_linkedin_url) as linkedin,
         coalesce(k.instagram, opp.instagram_url, opp.company_instagram) as instagram,
         coalesce(k.do_not_contact, false) as do_not_contact
  from opp left join contacts k on k.id = opp.contact_id
), task as (
  select distinct on (t.opportunity_id) t.opportunity_id, t.id as task_id, t.task_type, t.status as task_status, t.title,
         try_jsonb(substring(t.description from 'OUTREACH_READY_JSON: (\{[^\n]*\})')) as ready
  from tasks t
  where t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
    and t.task_type in ('SALES_OUTREACH_APPROVAL', 'CONTACT_RESOLUTION', 'CONTACT_RESEARCH', 'OUTREACH_FOLLOW_UP', 'REPLY_ACTION')
  order by t.opportunity_id,
           (t.description like '%OUTREACH_READY_JSON:%') desc,
           case t.task_type when 'REPLY_ACTION' then 0 when 'SALES_OUTREACH_APPROVAL' then 1 when 'OUTREACH_FOLLOW_UP' then 2 else 3 end,
           t.updated_at desc
), last_touch as (
  select opportunity_id, max(occurred_at) filter (where direction = 'OUTBOUND') as last_outbound_at,
         max(occurred_at) filter (where direction = 'INBOUND') as last_inbound_at
  from interactions group by 1
), next_fu as (
  select opportunity_id, min(due_at) as next_follow_up_at
  from tasks where status = 'OPEN' and task_type = 'OUTREACH_FOLLOW_UP' group by 1
)
select
  opp.id as opportunity_id, opp.company_id, opp.company, opp.vertical, opp.opportunity_type,
  opp.status as opportunity_status, opp.priority,
  case when opp.estimated_value is null then 'UNKNOWN' else 'MODEL_ESTIMATE' end as value_label,
  opp.estimated_value, opp.currency,
  ct.contact_name, ct.contact_role, ct.email, ct.email_status, email_kind(ct.email) as email_kind,
  ct.linkedin, ct.instagram,
  -- Same rule as Workflow 05's draft builder; 05's recorded choice wins when present.
  case
    when ct.do_not_contact then 'DO_NOT_CONTACT'
    when task.ready->>'primary_channel' is not null then task.ready->>'primary_channel'
    when ct.email_status = 'VERIFIED' and email_kind(ct.email) = 'DIRECT_PERSON_EMAIL' then 'EMAIL'
    when ct.contact_name is not null and ct.linkedin ~* 'linkedin\.com/in/' then 'LINKEDIN'
    when ct.instagram is not null and not opp.formal_sector then 'INSTAGRAM'
    when ct.email_status = 'VERIFIED' and email_kind(ct.email) = 'OFFICIAL_COMPANY_INBOX' then 'EMAIL_COMPANY_INBOX'
    else 'CONTACT_RESOLUTION'
  end as primary_channel,
  array_remove(array[
    case when ct.email_status = 'VERIFIED' then 'EMAIL' end,
    case when ct.linkedin ~* 'linkedin\.com/in/' then 'LINKEDIN' end,
    case when ct.instagram is not null then 'INSTAGRAM' end
  ], null) as available_channels,
  task.task_id, task.task_type, task.task_status,
  task.ready->>'email_subject' as ready_email_subject,
  task.ready->>'email_body' as ready_email,
  task.ready->>'linkedin_message' as ready_linkedin,
  task.ready->>'instagram_dm' as ready_instagram,
  task.ready->>'email_style' as email_style,
  task.ready->>'personalisation_evidence' as personalisation_evidence,
  task.ready->>'follow_up_plan' as follow_up_plan,
  lt.last_outbound_at, lt.last_inbound_at, nf.next_follow_up_at,
  coalesce(opp.reason, '') as why_now_evidence,
  opp.next_action, opp.run_id as source
from opp
join ct on ct.opportunity_id = opp.id
left join task on task.opportunity_id = opp.id
left join last_touch lt on lt.opportunity_id = opp.id
left join next_fu nf on nf.opportunity_id = opp.id;

revoke all on public.outreach_readiness from anon, authenticated;

-- 2. Duplicate open contact tasks: where a curated CONTACT_RESEARCH task and Workflow 05's
--    CONTACT_RESOLUTION task are both open on one opportunity, keep 05's task (it carries the
--    ready outreach), append the curated research notes to it, and cancel the curated one.
with dup as (
  select k.id as keep_id, d.id as drop_id, d.description as drop_desc, d.title as drop_title
  from tasks k
  join tasks d on d.opportunity_id = k.opportunity_id and d.id <> k.id
  where k.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and d.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
    and k.task_type = 'CONTACT_RESOLUTION' and k.description like '%OUTREACH_READY_JSON:%'
    and d.task_type = 'CONTACT_RESEARCH'
), keep as (
  update tasks t
     set description = t.description || E'\n\n--- ORIGINAL RESEARCH NOTES ---\n' || coalesce(dup.drop_desc, '')
    from dup where t.id = dup.keep_id and t.description not like '%--- ORIGINAL RESEARCH NOTES ---%'
  returning t.id
)
update tasks t
   set status = 'CANCELLED',
       description = coalesce(t.description, '') || E'\n\nMERGED 29 Sep 2026 into task ' || dup.keep_id
                     || ' (Workflow 05 outreach-ready task for the same opportunity). Research notes copied there.'
  from dup where t.id = dup.drop_id;

-- 3. HQ usability: open Workflow 05 contact tasks whose own OUTREACH_READY_JSON says the
--    primary channel is LINKEDIN or INSTAGRAM with a message ready now lead with that message
--    (HQ shows the first 900 characters) and say so in the title. Adam sends by hand.
--    Company accounts only.
with r as (
  select t.id, t.title, t.description, try_jsonb(substring(t.description from 'OUTREACH_READY_JSON: (\{[^\n]*\})')) as j,
         c.name as company
  from tasks t left join companies c on c.id = t.company_id
  where t.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and t.task_type in ('CONTACT_RESOLUTION', 'CONTACT_RESEARCH')
    and t.company_id is not null  -- person-led (celebrity / individual) approaches stay Adam's personal call
    and t.description like '%OUTREACH_READY_JSON:%'
    and t.description not like 'LINKEDIN MESSAGE READY%' and t.description not like 'INSTAGRAM DM READY%'
), m as (
  select r.*, case when j->>'primary_channel' = 'LINKEDIN' and coalesce(j->>'linkedin_message', '') <> '' then 'LINKEDIN'
                   when j->>'primary_channel' = 'INSTAGRAM' and coalesce(j->>'instagram_dm', '') <> '' then 'INSTAGRAM' end as ch
  from r
)
update tasks t
   set title = case m.ch when 'LINKEDIN' then 'LINKEDIN MESSAGE READY -- ' else 'INSTAGRAM DM READY -- ' end || coalesce(m.company, ''),
       description = concat_ws(E'\n',
         case m.ch when 'LINKEDIN' then 'LINKEDIN MESSAGE READY' else 'INSTAGRAM DM READY' end || ' -- ADAM SENDS MANUALLY (never automated)',
         'Company: ' || coalesce(m.company, ''),
         'To: ' || coalesce(m.j->>'contact_name', case m.ch when 'INSTAGRAM' then 'account owner' else '' end)
               || coalesce(' -- ' || (m.j->>'contact_role'), ''),
         'Profile: ' || coalesce(case m.ch when 'LINKEDIN' then m.j->>'linkedin' else m.j->>'instagram' end, ''),
         'Why now: ' || coalesce(m.j->>'why_now', ''),
         'Quality gate: ' || coalesce(m.j->>'quality_gate', ''),
         '',
         '--- MESSAGE ---',
         case m.ch when 'LINKEDIN' then m.j->>'linkedin_message' else m.j->>'instagram_dm' end,
         '',
         'After sending: mark this task done and note the send date (follow-up due about 4 days later). One channel only: no email or other channel in parallel.',
         '',
         m.description)
  from m where t.id = m.id and m.ch is not null;

-- 4. READY means ready to act. An opportunity marked READY with no usable channel (no named
--    contact, no verified email, no LinkedIn profile, no Instagram-native route) goes back to
--    RESEARCHING so it is not counted as ready. Its open task is left as it is.
update opportunities o
   set status = 'RESEARCHING',
       next_action = 'Resolve a named decision-maker and a usable channel (no contact on file). Was READY with no usable channel; corrected 29 Sep 2026.'
  from outreach_readiness r
 where r.opportunity_id = o.id and o.status = 'READY' and r.primary_channel = 'CONTACT_RESOLUTION';
