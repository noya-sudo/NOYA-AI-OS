-- Outreach readiness: one row per open opportunity with the commercial vertical,
-- the ONE primary channel, and the ready messages Workflow 05 prepared.
-- Deterministic (no AI): channel routing is a rule, not a model decision.
--
-- Channel rule (one primary channel per account; the rest are fallback only):
--   VERIFIED direct personal email          -> EMAIL
--   named person with a LinkedIn profile     -> LINKEDIN
--   Instagram-native business / founder      -> INSTAGRAM
--   VERIFIED official company/partner inbox  -> EMAIL_COMPANY_INBOX
--   otherwise                                -> CONTACT_RESOLUTION (nothing to send yet)
--
-- Ready messages are read from the open outreach task: Workflow 05 appends one line
-- "OUTREACH_READY_JSON: {...}" to the task description. No shadow CRM table.

create or replace function public.commercial_vertical(p_opportunity_type text, p_company_type text)
returns text language sql immutable as $$
  select case
    when coalesce(p_company_type,'') ~* '(MEMBER|COMMUNITY|CLUB)' or coalesce(p_opportunity_type,'') ~* 'MEMBER' then 'MEMBER_COMMUNITIES'
    when coalesce(p_company_type,'') ~* 'WEDDING' or coalesce(p_opportunity_type,'') ~* 'WEDDING' then 'WEDDINGS_PRIVATE_EVENTS'
    when coalesce(p_company_type,'') ~* '(CONCIERGE|TRAVEL_PARTNER|TRAVEL_ADVISOR|TRAVEL_AGENCY|DMC|DESTINATION_PARTNER)'
      or coalesce(p_opportunity_type,'') ~* '(CONCIERGE|TRAVEL_TRADE|WHITE_LABEL|REFERRAL|DESTINATION_PARTNER)' then 'DESTINATION_CONCIERGE_PARTNERS'
    when coalesce(p_company_type,'') ~* '(CORPORATE|EVENT_AGENCY|FAMILY_OFFICE|BANK|WEALTH|LAW|CONSULT|INVEST)'
      or coalesce(p_opportunity_type,'') ~* '(CORPORATE|RETREAT|EXECUTIVE|INCENTIVE|FAMILY_OFFICE|PRIVATE_BANK)' then 'CORPORATE_EVENTS'
    when coalesce(p_company_type,'') ~* '(HOTEL|RESORT|HOSPITALITY)' or coalesce(p_opportunity_type,'') ~* 'HOTEL' then 'HOTELS_CONTENT'
    when coalesce(p_company_type,'') ~* '(BRAND|PRODUCTION|AGENCY|PR_|CREATIVE|FASHION|BEAUTY|AUTOMOTIVE|LUXURY|MEDIA)'
      or coalesce(p_opportunity_type,'') ~* '(BRAND|PRODUCTION|CAMPAIGN|SHOOT|ACTIVATION|CREATOR_TRIP|LAUNCH)' then 'BRAND_PRODUCTION'
    when coalesce(p_company_type,'') ~* '(TALENT|CREATOR|ATHLETE|SPORT|PUBLIC_FIGURE)' or coalesce(p_opportunity_type,'') ~* '(TALENT|SPORT)' then 'TALENT_SUPPORT'
    else 'OTHER'
  end
$$;

create or replace function public.try_jsonb(p text)
returns jsonb language plpgsql immutable as $$
begin
  return p::jsonb;
exception when others then
  return null;
end $$;

create or replace function public.email_kind(p_email text)
returns text language sql immutable as $$
  select case
    when p_email is null or p_email !~ '@' then null
    when lower(split_part(p_email, '@', 1)) ~ '^(info|hello|contact|enquiries|enquiry|inquiries|partnerships?|partners|events|press|pr|media|newbusiness|new\.business|sales|bookings?|reservations|office|team|admin|marketing|concierge|membership|members)$'
      then 'OFFICIAL_COMPANY_INBOX'
    else 'DIRECT_PERSON_EMAIL'
  end
$$;

create or replace view public.outreach_readiness
with (security_invoker = true) as
with opp as (
  select o.*, c.name as company, c.instagram as company_instagram, c.linkedin as company_linkedin,
         c.website as company_website, c.notes as company_notes,
         commercial_vertical(o.opportunity_type, coalesce(o.company_type, c.company_type)) as vertical
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
    when ct.instagram is not null then 'INSTAGRAM'
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

-- One account, one sequence: companies that have more than one open outreach task
-- on different channels or opportunities. Should always be empty.
create or replace view public.account_sequence_conflicts
with (security_invoker = true) as
select t.company_id, c.name as company, count(*) as open_outreach_tasks,
       array_agg(t.task_type || ':' || t.title order by t.created_at) as tasks
from tasks t join companies c on c.id = t.company_id
where t.status = 'OPEN' and t.task_type in ('SALES_OUTREACH_APPROVAL', 'OUTREACH_FOLLOW_UP')
group by 1, 2
having count(*) > 1;
revoke all on public.account_sequence_conflicts from anon, authenticated;
