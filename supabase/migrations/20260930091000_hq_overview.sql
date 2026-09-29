-- NOYA HQ — CEO Overview V1 (30 Sep 2026).
--
-- Additive: the live dashboard keeps using hq_dashboard(); nothing existing changes.
--   system_blockers                 data-backed blockers panel (not hardcoded UI text)
--   hq_overview()                   one read for the Overview screen, computed server-side so
--                                   every figure is a query over CRM records (ids returned
--                                   for drill-down; UNKNOWN is never turned into 0)
--   hq_task_action(task, action..)  COMPLETE / SNOOZE / ASSIGN an ordinary task, audited.
--                                   Outreach approval tasks are refused: they go through the
--                                   approval flow (hq_approve_draft / hq_hold / hq_reject).
-- All functions check hq_admins exactly like the existing hq_* functions.

-- ---------------------------------------------------------------- blockers
create table if not exists public.system_blockers (
  id uuid primary key default gen_random_uuid(),
  blocker_key text not null unique,
  title text not null,
  impact text not null,
  owner_action text not null,
  severity text not null check (severity in ('BLOCKER', 'RISK', 'INFO')),
  status text not null default 'OPEN' check (status in ('OPEN', 'RESOLVED')),
  evidence text,
  source text not null,
  detected_at timestamptz not null default now(),
  resolved_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.system_blockers enable row level security;
revoke all on public.system_blockers from anon, authenticated;

insert into public.system_blockers (blocker_key, title, impact, owner_action, severity, evidence, source, detected_at) values
  ('AI_GATEWAY_ALLOWANCE_UNKNOWN',
   'n8n AI gateway credit allowance and price unknown',
   'AI runs on n8n AI gateway credits. The monthly allowance and per-call price are not exposed, so AI cost stays UNKNOWN and the budget cannot be enforced in money.',
   'Confirm the AI credits included in the n8n plan, or add an own Gemini/OpenAI key as an independent backup.',
   'RISK', 'cost_observability.ai_cost_usd = UNKNOWN; system_config.unit_costs.ai_gateway_per_call_usd is null',
   'Commercial engine final gate 29 Sep 2026', '2026-09-29 18:20:00+00'),
  ('ANTHROPIC_TOPUP_NOT_APPLIED',
   'Anthropic top-up not reaching the n8n key (premium tier only)',
   'Only the manual premium tier (Claude Sonnet 4.6) is affected. No automatic path depends on Anthropic.',
   'Check the Anthropic org/workspace the n8n key belongs to and apply credit there, or leave premium unused.',
   'INFO', 'Anthropic returned "credit balance too low" on 28-29 Sep; 00b reports it as PREMIUM_OPTIONAL; task 7d8d18b0',
   '00b provider health', '2026-09-29 09:00:00+00'),
  ('WINDSOR_ACCOUNT_LIMIT',
   'Windsor free plan: 3 accounts connected, 1 allowed',
   'Workflows 10a/10b receive no Instagram/paid-media data, so marketing performance is stale.',
   'Disconnect 2 Windsor accounts or upgrade the Windsor plan.',
   'RISK', 'Windsor returned its free-plan notice in 10a on 29 Sep; bogus media row removed',
   '10a organic content', '2026-09-29 15:00:00+00')
on conflict (blocker_key) do nothing;

-- ---------------------------------------------------------------- overview
create or replace function public.hq_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_admin text := hq_admin_email();
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_eod timestamptz := ((v_today + 1)::timestamp at time zone 'Africa/Cairo');
  v jsonb;
begin
  with
  opp as (
    select o.*, coalesce(c.name, o.company_name) as company,
           nullif(btrim(concat_ws(' ', k.first_name, k.last_name)), '') as person
    from opportunities o
    left join companies c on c.id = o.company_id
    left join contacts k on k.id = o.contact_id
  ),
  open_t as (
    select t.*, op.company as opp_company, op.person, op.priority as opp_priority,
           op.estimated_value, op.currency, op.status as opp_status, op.next_action as opp_next_action,
           coalesce(op.company, co.name) as company_name
    from tasks t
    left join opp op on op.id = t.opportunity_id
    left join companies co on co.id = t.company_id
    where t.status in ('OPEN', 'IN_PROGRESS')
  ),
  last_out as (
    select distinct on (opportunity_id) * from outbound_emails order by opportunity_id, created_at desc
  ),
  reply_tasks as (select distinct task_id from gmail_sync_ledger where task_id is not null),
  actions as (
    -- P1: a prospect replied / asked for a meeting
    select case when t.task_type = 'MEETING_ACTION' or t.id in (select task_id from reply_tasks) then 'P1' else 'P2' end as prio,
           case when t.task_type = 'MEETING_ACTION' then 'MEETING' else 'REPLY' end as kind,
           t.title as action, t.company_name as company, t.person, 'Workflow 13 (Gmail reply)' as source,
           t.due_at, t.opportunity_id, t.id as task_id, t.task_type, t.status,
           t.estimated_value, t.currency, coalesce(t.opp_next_action, '') as next_action, 'inbox' as go,
           t.opp_priority
    from open_t t where t.task_type in ('MEETING_ACTION', 'REPLY_ACTION', 'HUMAN_REVIEW', 'PROPOSAL_ACTION')
    union all
    -- P1: website enquiry waiting for Adam
    select 'P1', 'WEBSITE', t.title, t.company_name, t.person, 'Workflow 10d (website)', t.due_at, t.opportunity_id, t.id,
           t.task_type, t.status, t.estimated_value, t.currency, coalesce(t.opp_next_action, ''), 'website', t.opp_priority
    from open_t t where t.created_by ilike '10d%' or t.task_type ilike '%ENQUIR%'
    union all
    select 'P1', 'WEBSITE', 'Review new website enquiry ' || coalesce(w.reference, ''), coalesce(w.company_name, w.full_name), w.full_name,
           'Workflow 10d (website)', w.created_at, w.created_opportunity_id, null, null, w.status, null, null, '', 'website', 100
    from website_enquiries w
    where w.status = 'NEW' and w.created_at > now() - interval '14 days'
    union all
    -- P1: production failure raised by workflows 00 / 00b (low-priority notices are blockers, not actions)
    select 'P1', 'SYSTEM', t.title, null, null, coalesce(t.created_by, 'System'), t.due_at, null, t.id, t.task_type, t.status,
           null, null, '', 'system', 100
    from open_t t where (t.task_type = 'SYSTEM_FAILURE' or t.task_type ilike '%ALERT%') and coalesce(t.priority, 0) >= 50
    union all
    -- P1: proposal / negotiation open
    select 'P1', 'PROPOSAL', 'Proposal outstanding — ' || o.status, o.company, o.person, 'CRM stage', null, o.id, null, null, o.status,
           o.estimated_value, o.currency, coalesce(o.next_action, ''), 'pipeline', o.priority
    from opp o where o.status in ('PROPOSAL', 'NEGOTIATION')
    union all
    -- P1: invoice pending for more than 30 days
    select 'P1', 'PAYMENT', 'Payment pending ' || r.currency || ' ' || r.amount, o.company, null, 'Revenue', r.created_at, r.opportunity_id,
           null, null, r.payment_status, null, null, '', 'finance', 100
    from revenue r left join opp o on o.id = r.opportunity_id
    where r.payment_status = 'PENDING' and r.created_at < now() - interval '30 days'
    union all
    -- P2: approved Gmail draft not yet sent
    select 'P2', 'SEND_DRAFT', 'Send the approved draft from Gmail', o.company, o.person, 'Workflow 12 (Gmail draft)', lo.completed_at,
           o.id, null, null, lo.status, o.estimated_value, o.currency, coalesce(o.next_action, ''), 'outreach', o.priority
    from last_out lo join opp o on o.id = lo.opportunity_id where lo.status = 'DRAFTED'
    union all
    -- P2: outreach ready for approval (verified recipient, nothing in flight, not held/rejected)
    select 'P2', 'APPROVE', 'Approve outreach' || case when opportunity_is_human_only(t.opportunity_id) then ' (Adam personal)' else '' end,
           t.company_name, t.person, 'Workflow 05 (draft)', t.due_at, t.opportunity_id, t.id, t.task_type, t.status,
           t.estimated_value, t.currency, coalesce(t.opp_next_action, ''), 'outreach', t.opp_priority
    from open_t t
    where t.task_type = 'SALES_OUTREACH_APPROVAL'
      and outbound_recipient_block_reason((select contact_id from opportunities where id = t.opportunity_id)) is null
      and not exists (select 1 from last_out lo where lo.opportunity_id = t.opportunity_id)
      and not exists (select 1 from approval_queue_state q where q.opportunity_id = t.opportunity_id)
    union all
    -- P2: follow-up due today or overdue
    select 'P2', 'FOLLOW_UP', t.title, t.company_name, t.person, 'Workflow 13 (follow-up)', t.due_at, t.opportunity_id, t.id,
           t.task_type, t.status, t.estimated_value, t.currency, coalesce(t.opp_next_action, ''), 'tasks', t.opp_priority
    from open_t t where t.task_type = 'OUTREACH_FOLLOW_UP' and t.due_at < v_eod
    union all
    -- P2: LinkedIn / Instagram message ready (Adam sends by hand)
    select 'P2', case when t.title like 'LINKEDIN%' then 'LINKEDIN' else 'INSTAGRAM' end, t.title, t.company_name, t.person,
           'Workflow 05 (channel routing)', t.due_at, t.opportunity_id, t.id, t.task_type, t.status,
           t.estimated_value, t.currency, coalesce(t.opp_next_action, ''), 'outreach', t.opp_priority
    from open_t t where t.task_type in ('CONTACT_RESOLUTION', 'CONTACT_RESEARCH')
      and (t.title like 'LINKEDIN MESSAGE READY%' or t.title like 'INSTAGRAM DM READY%')
    union all
    -- P3: approval tasks already converted to manual LinkedIn / warm-path actions (email not sendable)
    select 'P3', 'MANUAL_ACTION', t.title, t.company_name, t.person, 'Adam review 28 Sep', t.due_at, t.opportunity_id, t.id,
           t.task_type, t.status, t.estimated_value, t.currency, coalesce(t.opp_next_action, ''), 'outreach', t.opp_priority
    from open_t t
    where t.task_type = 'SALES_OUTREACH_APPROVAL'
      and outbound_recipient_block_reason((select contact_id from opportunities where id = t.opportunity_id)) is not null
      and not exists (select 1 from last_out lo where lo.opportunity_id = t.opportunity_id)
    union all
    -- P3: anything else of Adam's that is overdue (contact research is agent work, not listed)
    select 'P3', 'OVERDUE', t.title, t.company_name, t.person, coalesce(t.created_by, 'Task'), t.due_at, t.opportunity_id, t.id,
           t.task_type, t.status, t.estimated_value, t.currency, coalesce(t.opp_next_action, ''), 'tasks', t.opp_priority
    from open_t t
    where t.due_at < now()
      and t.task_type not in ('MEETING_ACTION', 'REPLY_ACTION', 'HUMAN_REVIEW', 'PROPOSAL_ACTION', 'SALES_OUTREACH_APPROVAL',
                              'OUTREACH_FOLLOW_UP', 'CONTACT_RESOLUTION', 'CONTACT_RESEARCH', 'OUTREACH_READY', 'SYSTEM_FAILURE')
      and t.task_type not ilike '%ALERT%' and coalesce(t.created_by, '') not ilike '10d%'
  ),
  ranked as (
    select a.*, row_number() over (order by a.prio, a.due_at nulls last, a.opp_priority desc nulls last) as rn
    from actions a
  ),
  active as (select * from opp where status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM')),
  inbound as (
    select l.*, o.company, o.person, o.status as opp_status, t.title as task_title, t.status as task_status
    from gmail_sync_ledger l left join opp o on o.id = l.opportunity_id left join tasks t on t.id = l.task_id
    where l.kind = 'INBOUND_REPLY'
  ),
  money_by_cur as (
    select currency,
      sum(amount) filter (where payment_status = 'PAID') as collected,
      count(*) filter (where payment_status = 'PART_PAID') as part_paid_records,
      sum(amount) filter (where payment_status = 'PENDING') as outstanding
    from revenue group by currency
  ),
  pipe_by_cur as (
    select currency, sum(estimated_value) as est, count(*) as with_value
    from active where estimated_value is not null group by currency
  )
  select jsonb_build_object(
    'generated_at', now(),
    'admin', v_admin,
    'today', v_today,
    'actions', coalesce((select jsonb_agg(jsonb_build_object(
        'prio', r.prio, 'kind', r.kind, 'action', r.action, 'company', r.company, 'person', r.person,
        'source', r.source, 'due_at', r.due_at, 'overdue', (r.due_at < now()), 'opportunity_id', r.opportunity_id,
        'task_id', r.task_id, 'task_type', r.task_type, 'status', r.status,
        'value', r.estimated_value, 'currency', r.currency, 'value_label', case when r.estimated_value is null then 'UNKNOWN' else 'ESTIMATE' end,
        'next_action', r.next_action, 'go', r.go) order by r.rn) from ranked r), '[]'::jsonb),
    'scorecard', jsonb_build_object(
      'active_opportunities', jsonb_build_object('n', (select count(*) from active),
        'def', 'opportunities not WON / LOST / ARCHIVED / LONG_TERM'),
      'stages', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from opp group by status) s), '{}'::jsonb),
      'in_conversation', jsonb_build_object('n', (select count(*) from opp where status in ('CONTACTED', 'FOLLOW_UP', 'INTERESTED')),
        'def', 'status CONTACTED / FOLLOW_UP / INTERESTED'),
      'call_required', jsonb_build_object('n', (select count(*) from opp where status = 'CALL_REQUIRED'),
        'ids', coalesce((select jsonb_agg(id) from opp where status = 'CALL_REQUIRED'), '[]'::jsonb), 'def', 'status CALL_REQUIRED'),
      'proposals', jsonb_build_object('n', (select count(*) from opp where status in ('PROPOSAL', 'NEGOTIATION')),
        'def', 'status PROPOSAL / NEGOTIATION'),
      'won', jsonb_build_object('n', (select count(*) from opp where status = 'WON'), 'def', 'status WON'),
      'approvals_ready', jsonb_build_object('n', (select count(*) from actions where kind = 'APPROVE'),
        'def', 'open SALES_OUTREACH_APPROVAL, verified recipient, nothing in flight'),
      'positive_replies_7d', jsonb_build_object('n', (select count(*) from inbound where received_at > now() - interval '7 days'
          and classification in ('POSITIVE', 'MEETING_REQUEST', 'NEEDS_INFO', 'REFERRAL')),
        'def', 'gmail_sync_ledger replies classified POSITIVE / MEETING_REQUEST / NEEDS_INFO / REFERRAL, last 7 days'),
      'website_7d', jsonb_build_object('n', (select count(*) from website_enquiries where created_at > now() - interval '7 days'),
        'total', (select count(*) from website_enquiries), 'def', 'website_enquiries created in the last 7 days'),
      'overdue_tasks', jsonb_build_object('n', (select count(*) from tasks where status in ('OPEN', 'IN_PROGRESS') and due_at < now()),
        'def', 'OPEN / IN_PROGRESS tasks past due (WAITING = parked, excluded)')),
    'money', jsonb_build_object(
      'revenue_records', (select count(*) from revenue),
      'by_currency', coalesce((select jsonb_agg(jsonb_build_object('currency', currency, 'collected', collected,
          'part_paid_records', part_paid_records, 'outstanding', outstanding)) from money_by_cur), '[]'::jsonb),
      'won_deals', (select count(*) from opp where status = 'WON'),
      'pipeline_estimate', coalesce((select jsonb_agg(jsonb_build_object('currency', currency, 'amount', est, 'opportunities', with_value))
          from pipe_by_cur), '[]'::jsonb),
      'pipeline_unknown_value', (select count(*) from active where estimated_value is null),
      'note', 'Collected = revenue PAID (ACTUAL). Outstanding = revenue PENDING. Part-paid amounts are UNKNOWN until the finance phase records amount paid. Pipeline = sum of estimated_value on active opportunities (ESTIMATE, never revenue). Currencies are never added together.'),
    'replies', coalesce((select jsonb_agg(jsonb_build_object(
        'received_at', i.received_at, 'classification', i.classification, 'from', i.detail->>'from',
        'subject', i.detail->>'subject', 'summary', i.detail->>'summary', 'company', i.company, 'person', i.person,
        'opportunity_id', i.opportunity_id, 'opp_status', i.opp_status, 'task_title', i.task_title, 'task_status', i.task_status,
        'thread_id', i.gmail_thread_id, 'deterministic', i.classification in ('BOUNCE', 'OUT_OF_OFFICE'))
        order by i.received_at desc) from inbound i where i.received_at > now() - interval '14 days'), '[]'::jsonb),
    'website', coalesce((select jsonb_agg(jsonb_build_object(
        'reference', w.reference, 'created_at', w.created_at, 'status', w.status, 'lead_type', w.lead_type,
        'name', w.full_name, 'company', w.company_name, 'destination', w.destination,
        'date_from', w.date_from, 'date_to', w.date_to, 'guests', w.guests, 'opportunity_id', w.created_opportunity_id)
        order by w.created_at desc) from website_enquiries w where w.created_at > now() - interval '30 days'), '[]'::jsonb),
    'system', jsonb_build_object(
      'failures', coalesce((select jsonb_agg(jsonb_build_object('title', title, 'created_at', created_at, 'task_id', id))
          from tasks where status in ('OPEN', 'IN_PROGRESS') and (task_type = 'SYSTEM_FAILURE' or task_type ilike '%ALERT%')
          and coalesce(priority, 0) >= 50), '[]'::jsonb),
      'blockers', coalesce((select jsonb_agg(jsonb_build_object('key', blocker_key, 'title', title, 'impact', impact,
          'owner_action', owner_action, 'severity', severity, 'evidence', evidence, 'source', source, 'detected_at', detected_at)
          order by case severity when 'BLOCKER' then 0 when 'RISK' then 1 else 2 end) from system_blockers where status = 'OPEN'), '[]'::jsonb),
      'signals', jsonb_build_array(
        jsonb_build_object('name', 'Gmail sync (13)', 'last', (select last_run_at from gmail_sync_state where id = 1),
          'ok', coalesce((select last_run_at > now() - interval '45 minutes' from gmail_sync_state where id = 1), false),
          'rule', 'runs every 15 min; stale after 45 min'),
        jsonb_build_object('name', 'Daily CEO brief (11)',
          'last', (select generated_at from ceo_reports where report_type = 'DAILY' order by generated_at desc limit 1),
          'ok', coalesce((select generated_at > now() - interval '30 hours' and delivery_status = 'DELIVERED'
                 from ceo_reports where report_type = 'DAILY' order by generated_at desc limit 1), false),
          'rule', 'delivered within 30 h',
          'detail', (select delivery_status from ceo_reports where report_type = 'DAILY' order by generated_at desc limit 1)),
        jsonb_build_object('name', 'Outbound drafts (12)', 'last', (select max(created_at) from outbound_emails),
          'ok', not exists (select 1 from outbound_emails where (status in ('APPROVED', 'PROCESSING') and created_at < now() - interval '10 minutes')
                  or (status = 'FAILED' and updated_at > now() - interval '7 days')),
          'rule', 'no stuck or failed draft in 7 days'),
        jsonb_build_object('name', 'Discovery (02/03/04/06/08)', 'last', (select max(recorded_at) from department_run_metrics),
          'ok', coalesce((select max(recorded_at) > now() - interval '30 hours' from department_run_metrics), false),
          'rule', 'a discovery run logged within 30 h')),
      'cost_today', (select to_jsonb(c) from cost_observability c where period = 'TODAY'))
  ) into v;
  return v;
end;
$$;

-- ---------------------------------------------------------------- task actions
create or replace function public.hq_task_action(p_task_id uuid, p_action text, p_until date default null,
                                                 p_assignee text default null, p_note text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_admin text := hq_admin_email();
  v_task tasks%rowtype;
  v_action text := upper(coalesce(p_action, ''));
begin
  select * into v_task from tasks where id = p_task_id for update;
  if v_task.id is null then return jsonb_build_object('ok', false, 'reason', 'TASK_NOT_FOUND'); end if;
  if v_task.status not in ('OPEN', 'IN_PROGRESS', 'WAITING') then
    return jsonb_build_object('ok', false, 'reason', 'TASK_NOT_OPEN');
  end if;
  if v_task.task_type = 'SALES_OUTREACH_APPROVAL' and v_action = 'COMPLETE' then
    return jsonb_build_object('ok', false, 'reason', 'USE_APPROVAL_FLOW');
  end if;

  if v_action = 'COMPLETE' then
    update tasks set status = 'COMPLETED', completed_at = now(),
           description = coalesce(description, '') || E'\n\nCompleted in HQ by ' || v_admin || ' ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon YYYY HH24:MI') || ' Cairo'
                         || coalesce('. Note: ' || hq_trim(p_note), '')
     where id = p_task_id;
  elsif v_action = 'SNOOZE' then
    if p_until is null or p_until <= (now() at time zone 'Africa/Cairo')::date or p_until > (now() at time zone 'Africa/Cairo')::date + 90 then
      return jsonb_build_object('ok', false, 'reason', 'INVALID_DATE');
    end if;
    update tasks set due_at = (p_until::timestamp + time '09:00') at time zone 'Africa/Cairo',
           description = coalesce(description, '') || E'\n\nSnoozed in HQ to ' || to_char(p_until, 'DD Mon YYYY') || ' by ' || v_admin
                         || coalesce('. Note: ' || hq_trim(p_note), '')
     where id = p_task_id;
  elsif v_action = 'ASSIGN' then
    if hq_trim(p_assignee) is null or length(p_assignee) > 80 then
      return jsonb_build_object('ok', false, 'reason', 'ASSIGNEE_REQUIRED');
    end if;
    update tasks set assigned_to = hq_trim(p_assignee) where id = p_task_id;
  else
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION');
  end if;

  insert into approval_audit (opportunity_id, action, result, actor, detail)
  values (v_task.opportunity_id, 'TASK_' || v_action, 'OK', v_admin,
          jsonb_build_object('task_id', p_task_id, 'task_type', v_task.task_type, 'title', v_task.title,
                             'until', p_until, 'assignee', p_assignee, 'note', p_note));
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.hq_overview() from public, anon;
revoke all on function public.hq_task_action(uuid, text, date, text, text) from public, anon;
grant execute on function public.hq_overview() to authenticated;
grant execute on function public.hq_task_action(uuid, text, date, text, text) to authenticated;
