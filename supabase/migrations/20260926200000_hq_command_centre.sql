-- NOYA CEO Command Centre (hq.noyaconcierge.com) - server-side layer.
--
-- The browser only ever holds the publishable key and Adam's own login token.
-- It can call exactly these hq_* functions and nothing else:
--   hq_dashboard()                               read everything the dashboard shows
--   hq_save_draft(opp, subject, body, note)      EDIT: new approved version, original kept
--   hq_approve_draft(opp, version)               APPROVE & DRAFT: gates + workflow 12 (draft only)
--   hq_redispatch(outbound_id)                   retry the workflow 12 hand-off if it was lost
--   hq_hold(opp, review_date, reason)            HOLD
--   hq_reject(opp, reason)                       REJECT
-- Every one of them checks hq_admins (bound to the auth user id) and writes approval_audit.
-- There is no send path here: APPROVE & SEND is deliberately not exposed in this phase.

create extension if not exists pg_net with schema extensions;

create table if not exists public.hq_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  created_at timestamptz not null default now()
);

-- Versioned outreach copy. Version 1 is the untouched workflow 05 draft; every
-- edit adds a version, so the original is never lost.
create table if not exists public.outreach_drafts (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.opportunities(id),
  version int not null check (version >= 1),
  subject text not null check (length(btrim(subject)) between 1 and 200),
  body text not null check (length(btrim(body)) between 1 and 8000),
  follow_up_plan text,
  source text not null check (source in ('WF05_ORIGINAL', 'ADAM_EDIT')),
  source_task_id uuid references public.tasks(id),
  edit_note text,
  created_by text not null,
  created_at timestamptz not null default now(),
  unique (opportunity_id, version)
);

create table if not exists public.approval_queue_state (
  opportunity_id uuid primary key references public.opportunities(id),
  state text not null check (state in ('HOLD', 'REJECTED')),
  review_at date,
  reason text,
  decided_by text not null,
  decided_at timestamptz not null default now()
);

alter table public.hq_admins enable row level security;
alter table public.outreach_drafts enable row level security;
alter table public.approval_queue_state enable row level security;
revoke all on public.hq_admins, public.outreach_drafts, public.approval_queue_state from anon, authenticated;

-- ---------------------------------------------------------------- helpers

create or replace function public.hq_admin_email()
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select a.email into v_email
  from hq_admins a
  where a.user_id = auth.uid()
    and lower(a.email) = lower(coalesce(auth.jwt()->>'email', ''));
  if v_email is null then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return v_email;
end;
$$;

create or replace function public.hq_trim(p text)
returns text
language sql
immutable
as $$ select nullif(regexp_replace(coalesce(p, ''), '^\s+|\s+$', '', 'g'), '') $$;

-- Structured fields from the workflow 05 draft stored in the approval task.
create or replace function public.hq_parse_draft(p text)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'subject', hq_trim(substring(p from '--- EMAIL ---\nSubject: ([^\n]*)')),
    'body', hq_trim(substring(p from '--- EMAIL ---\nSubject: [^\n]*\n(.*?)\n+--- FOLLOW-UP 1')),
    'follow_up_plan', hq_trim(substring(p from '(--- FOLLOW-UP 1.*?)\n+--- LINKEDIN')),
    'why_now', hq_trim(substring(p from '\nWhy now: ([^\n]*)')),
    'why_noya', hq_trim(substring(p from '\nWhy NOYA: ([^\n]*)')),
    'signal', hq_trim(substring(p from '\nSignal: ([^\n]*)')),
    'primary_angle', hq_trim(substring(p from '\nPrimary angle: ([^\n]*)')),
    'outreach_mode', hq_trim(substring(p from '\nOutreach mode: ([^\n]*)')),
    'recommended_channel', hq_trim(substring(p from '\nRecommended channel: ([^\n]*)')),
    'human_only_reason', hq_trim(substring(p from '\nWhy Adam should personally handle this: ([^\n]*)')),
    'originating_department', hq_trim(substring(p from '\nOriginating department: ([^\n]*)'))
  );
$$;

-- The draft currently shown for approval: latest edit, else the workflow 05 original.
create or replace function public.hq_current_draft(p_opportunity_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with t as (
    select id, description from tasks
    where opportunity_id = p_opportunity_id and task_type = 'SALES_OUTREACH_APPROVAL'
      and description like '%--- EMAIL ---%'
    order by created_at desc limit 1
  ), d as (
    select * from outreach_drafts where opportunity_id = p_opportunity_id
    order by version desc limit 1
  )
  select case
    when exists (select 1 from d) then
      (select hq_parse_draft(coalesce((select description from t), '')) || jsonb_build_object(
        'version', d.version, 'subject', d.subject, 'body', d.body,
        'follow_up_plan', coalesce(d.follow_up_plan, hq_parse_draft(coalesce((select description from t), ''))->>'follow_up_plan'),
        'source', d.source, 'edited_at', d.created_at, 'edited_by', d.created_by,
        'original_subject', (select subject from outreach_drafts where opportunity_id = p_opportunity_id and version = 1),
        'source_task_id', (select id from t)) from d)
    when exists (select 1 from t) then
      (select hq_parse_draft(t.description) || jsonb_build_object('version', 1, 'source', 'WF05_ORIGINAL',
        'source_task_id', t.id) from t)
    else null
  end;
$$;

-- --------------------------------------------------------------- read API

create or replace function public.hq_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_admin text := hq_admin_email();
  v jsonb;
begin
  with
  last_out as (
    select distinct on (opportunity_id) *
    from outbound_emails order by opportunity_id, created_at desc
  ),
  replies as (
    select l.opportunity_id, count(*) filter (where l.classification not in ('OUT_OF_OFFICE', 'UNRELATED', 'BOUNCE')) as n,
      max(l.received_at) as last_at,
      (array_agg(l.classification order by l.received_at desc))[1] as last_class
    from gmail_sync_ledger l where l.kind = 'INBOUND_REPLY' and l.opportunity_id is not null
    group by l.opportunity_id
  ),
  approval_opps as (
    select distinct t.opportunity_id from tasks t
    where t.task_type = 'SALES_OUTREACH_APPROVAL' and t.opportunity_id is not null
  ),
  approvals as (
    select o.id, o.company_name, o.opportunity_type, o.status, o.approval_status, o.priority,
      o.estimated_value, o.currency, o.probability, o.next_action, o.updated_at, o.reason,
      c.id as contact_id, nullif(btrim(concat_ws(' ', c.first_name, c.last_name)), '') as contact_name,
      c.position as contact_position, c.email as contact_email, c.email_status, c.do_not_contact,
      outbound_recipient_block_reason(o.contact_id) as block_reason,
      opportunity_is_human_only(o.id) as human_only,
      hq_current_draft(o.id) as draft,
      q.state as queue_state, q.review_at, q.reason as queue_reason,
      lo.id as outbound_id, lo.status as outbound_status, lo.mode as outbound_mode, lo.gmail_draft_id,
      lo.gmail_message_id, lo.gmail_thread_id, lo.sent_at, lo.sent_via, lo.error as outbound_error,
      lo.created_at as outbound_created_at, lo.completed_at as outbound_completed_at,
      r.n as reply_count, r.last_class,
      case
        when q.state = 'REJECTED' or o.approval_status = 'REJECTED' then 'REJECTED'
        when r.n > 0 then 'REPLIED'
        when lo.status = 'SENT' then 'SENT'
        when lo.status = 'DRAFTED' then 'DRAFT_CREATED'
        when lo.status in ('APPROVED', 'PROCESSING') then 'APPROVED'
        when q.state = 'HOLD' then 'ON_HOLD'
        when lo.status = 'FAILED' then 'FAILED'
        when lo.status = 'DISCARDED' then 'DRAFT_DISCARDED'
        else 'PENDING_APPROVAL'
      end as loop_stage
    from opportunities o
    join approval_opps ao on ao.opportunity_id = o.id
    left join contacts c on c.id = o.contact_id
    left join approval_queue_state q on q.opportunity_id = o.id
    left join last_out lo on lo.opportunity_id = o.id
    left join replies r on r.opportunity_id = o.id
  ),
  task_rows as (
    select t.id, t.title, t.task_type, t.status, t.priority, t.due_at, t.completed_at, t.created_at,
      t.assigned_to, t.created_by, t.opportunity_id, o.company_name, left(t.description, 900) as description
    from tasks t left join opportunities o on o.id = t.opportunity_id
    where t.status <> 'CANCELLED' or t.updated_at > now() - interval '7 days'
    order by t.created_at desc limit 400
  ),
  completions as (
    select 'Approved outreach drafted' as what, 'Workflow 12 (Adam approval)' as agent, oe.completed_at as at,
      op.company_name as company, 'Draft waiting in noya@ Gmail Drafts' as result,
      'Gmail draft ' || coalesce(oe.gmail_draft_id, '?') as evidence, 'Adam: review and send from Gmail' as next_action,
      false as revenue_impacting
    from outbound_emails oe join opportunities op on op.id = oe.opportunity_id
    where oe.mode = 'DRAFT' and oe.completed_at is not null and oe.status in ('DRAFTED', 'SENT')
    union all
    select 'Outreach email sent', case oe.sent_via when 'MANUAL_GMAIL' then 'Adam (Gmail) - logged by workflow 13' else 'Workflow 12' end,
      coalesce(oe.sent_at, oe.completed_at), op.company_name, 'Sent to ' || coalesce(oe.sent_to_email, oe.to_email),
      'Gmail message ' || coalesce(oe.gmail_message_id, '?'), op.next_action, true
    from outbound_emails oe join opportunities op on op.id = oe.opportunity_id where oe.status = 'SENT'
    union all
    select 'Reply received: ' || l.classification, 'Workflow 13', l.received_at, op.company_name,
      coalesce(l.detail->>'summary', ''), 'Gmail message ' || l.gmail_message_id, op.next_action,
      l.classification in ('POSITIVE', 'MEETING_REQUEST', 'NEEDS_INFO', 'REFERRAL')
    from gmail_sync_ledger l join opportunities op on op.id = l.opportunity_id
    where l.kind = 'INBOUND_REPLY' and l.classification in ('POSITIVE', 'MEETING_REQUEST', 'NEEDS_INFO', 'REFERRAL', 'NOT_NOW', 'DECLINED', 'UNKNOWN')
    union all
    select 'Verified decision-maker found', coalesce(ct.source, 'research agents'), ct.created_at,
      co.name, nullif(btrim(concat_ws(' ', ct.first_name, ct.last_name, '-', ct.position)), '-'),
      'Email ' || ct.email || ' (VERIFIED)', 'Prepare approved outreach', false
    from contacts ct left join companies co on co.id = ct.company_id
    where ct.email_status = 'VERIFIED' and ct.email not ilike '%noyaconcierge.com'
    union all
    select 'Contact resolution completed', coalesce(t.assigned_to, 'Adam'), t.completed_at, op.company_name,
      t.title, 'Task ' || t.id, op.next_action, false
    from tasks t left join opportunities op on op.id = t.opportunity_id
    where t.status = 'COMPLETED' and t.completed_at is not null and t.task_type = 'CONTACT_RESOLUTION'
    union all
    select 'Website enquiry qualified', 'Workflow 10d', coalesce(w.processed_at, w.created_at),
      coalesce(w.company_name, w.full_name), w.lead_type, 'Enquiry ' || coalesce(w.reference, w.submission_id),
      'Respond to enquiry', true
    from website_enquiries w where w.status = 'ROUTED'
    union all
    select 'Revenue received', 'Finance', coalesce(rv.received_at, rv.updated_at), op.company_name,
      rv.currency || ' ' || rv.amount || ' ' || coalesce(rv.revenue_type, ''), coalesce('Invoice ' || rv.invoice_reference, 'Revenue ' || rv.id),
      null, true
    from revenue rv left join opportunities op on op.id = rv.opportunity_id where rv.payment_status in ('PAID', 'PART_PAID')
    union all
    select 'Deal won', 'CRM', op.updated_at, op.company_name, op.opportunity_type, 'Opportunity status WON', op.next_action, true
    from opportunities op where op.status = 'WON'
    union all
    select 'Proposal stage reached', 'CRM', op.updated_at, op.company_name, op.opportunity_type, 'Opportunity status PROPOSAL', op.next_action, true
    from opportunities op where op.status = 'PROPOSAL'
  )
  select jsonb_build_object(
    'generated_at', now(),
    'admin', v_admin,
    'approvals', coalesce((select jsonb_agg(to_jsonb(a) order by
        case a.loop_stage when 'PENDING_APPROVAL' then 0 when 'APPROVED' then 1 when 'DRAFT_CREATED' then 2 else 3 end,
        (a.block_reason is null) desc, a.priority desc nulls last) from approvals a), '[]'::jsonb),
    'opportunities', coalesce((select jsonb_agg(jsonb_build_object(
        'id', o.id, 'company_name', o.company_name, 'opportunity_type', o.opportunity_type, 'status', o.status,
        'approval_status', o.approval_status, 'priority', o.priority, 'estimated_value', o.estimated_value,
        'currency', o.currency, 'probability', o.probability, 'next_action', o.next_action,
        'contact_name', nullif(btrim(concat_ws(' ', c.first_name, c.last_name)), ''), 'contact_position', c.position,
        'email_status', c.email_status, 'updated_at', o.updated_at, 'created_at', o.created_at)
        order by o.priority desc nulls last)
      from opportunities o left join contacts c on c.id = o.contact_id), '[]'::jsonb),
    'revenue', jsonb_build_object(
      'actual', coalesce((select jsonb_agg(jsonb_build_object('currency', currency, 'amount', s)) from
        (select currency, sum(amount) s from revenue where payment_status in ('PAID', 'PART_PAID') group by currency) x), '[]'::jsonb),
      'invoiced_unpaid', coalesce((select jsonb_agg(jsonb_build_object('currency', currency, 'amount', s)) from
        (select currency, sum(amount) s from revenue where payment_status = 'PENDING' group by currency) x), '[]'::jsonb),
      'rows', (select count(*) from revenue)),
    'tasks', coalesce((select jsonb_agg(to_jsonb(t)) from task_rows t), '[]'::jsonb),
    'completions', coalesce((select jsonb_agg(to_jsonb(c) order by c.at desc) from completions c
        where c.at > now() - interval '45 days'), '[]'::jsonb),
    'inbound', coalesce((select jsonb_agg(jsonb_build_object(
        'message_id', l.gmail_message_id, 'thread_id', l.gmail_thread_id, 'received_at', l.received_at,
        'classification', l.classification, 'confidence', l.confidence, 'match_method', l.match_method,
        'outcome', l.outcome, 'from', l.detail->>'from', 'subject', l.detail->>'subject',
        'summary', l.detail->>'summary', 'company_name', op.company_name, 'opportunity_id', l.opportunity_id,
        'task_id', l.task_id, 'task_title', t.title, 'task_status', t.status, 'task_description', left(t.description, 4000),
        'opportunity_status', op.status, 'next_action', op.next_action) order by l.received_at desc)
      from gmail_sync_ledger l left join opportunities op on op.id = l.opportunity_id left join tasks t on t.id = l.task_id
      where l.kind = 'INBOUND_REPLY' and l.received_at > now() - interval '90 days'), '[]'::jsonb),
    'enquiries', coalesce((select jsonb_agg(jsonb_build_object(
        'reference', w.reference, 'created_at', w.created_at, 'status', w.status, 'lead_type', w.lead_type,
        'name', w.full_name, 'company', w.company_name, 'destination', w.destination, 'budget', w.budget,
        'message', left(w.message, 600)) order by w.created_at desc)
      from website_enquiries w where w.created_at > now() - interval '60 days'), '[]'::jsonb),
    'marketing', jsonb_build_object(
      'content', coalesce((select jsonb_agg(to_jsonb(x)) from (
        select media_date, media_type, category, destination, left(caption, 140) caption, reach, views, saved, shares,
          interaction_rate, save_rate from content_performance order by media_date desc nulls last limit 12) x), '[]'::jsonb),
      'paid', coalesce((select jsonb_agg(to_jsonb(x)) from (
        select campaign, ad_name, sum(spend) spend, sum(impressions) impressions, sum(clicks) clicks,
          case when sum(impressions) > 0 then round(100 * sum(clicks) / sum(impressions), 2) end ctr,
          max(recommendation) recommendation, max(date) last_date
        from paid_media_performance where date > current_date - 30 group by campaign, ad_name order by sum(spend) desc limit 12) x), '[]'::jsonb)),
    'intelligence', jsonb_build_object(
      'signals', coalesce((select jsonb_agg(to_jsonb(x)) from (
        select title, intelligence_type, destination, left(summary, 400) summary, potential_opportunity, revenue_potential,
          relevance_score, status, source_url, discovered_at from intelligence order by discovered_at desc nulls last limit 15) x), '[]'::jsonb),
      'competitors', coalesce((select jsonb_agg(to_jsonb(x)) from (
        select competitor_name, competitor_category, left(why_it_matters, 300) why_it_matters, recommended_action,
          relevance_score, source_url, discovered_at from competitor_intelligence
        where status in ('NEW', 'REVIEWED') order by discovered_at desc limit 10) x), '[]'::jsonb)),
    'health', jsonb_build_object(
      'gmail_sync_last_run', (select last_run_at from gmail_sync_state where id = 1),
      'gmail_sync_summary', (select last_run_summary from gmail_sync_state where id = 1),
      'gmail_sync_go_live', (select go_live_at from gmail_sync_state where id = 1),
      'last_daily_brief', (select jsonb_build_object('generated_at', generated_at, 'delivery_status', delivery_status)
        from ceo_reports where report_type = 'DAILY' order by generated_at desc limit 1),
      'last_weekly_brief', (select jsonb_build_object('generated_at', generated_at, 'delivery_status', delivery_status)
        from ceo_reports where report_type = 'WEEKLY' order by generated_at desc limit 1),
      'outbound_stuck', (select count(*) from outbound_emails where status in ('APPROVED', 'PROCESSING') and created_at < now() - interval '10 minutes'),
      'outbound_failed_7d', (select count(*) from outbound_emails where status = 'FAILED' and updated_at > now() - interval '7 days'),
      'open_alerts', coalesce((select jsonb_agg(jsonb_build_object('title', title, 'created_at', created_at, 'priority', priority))
        from tasks where status in ('OPEN', 'IN_PROGRESS') and (task_type ilike '%ALERT%' or task_type = 'SYSTEM_FAILURE')), '[]'::jsonb)),
    'brief', jsonb_build_object(
      'daily', (select jsonb_build_object('generated_at', generated_at, 'delivery_status', delivery_status, 'text', report_text)
        from ceo_reports where report_type = 'DAILY' order by generated_at desc limit 1),
      'weekly', (select jsonb_build_object('generated_at', generated_at, 'delivery_status', delivery_status, 'text', report_text)
        from ceo_reports where report_type = 'WEEKLY' order by generated_at desc limit 1))
  ) into v;
  return v;
end;
$$;

-- -------------------------------------------------------------- write API

create or replace function public.hq_save_draft(p_opportunity_id uuid, p_subject text, p_body text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin text := hq_admin_email();
  v_cur jsonb;
  v_next int;
begin
  perform 1 from opportunities where id = p_opportunity_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'OPPORTUNITY_NOT_FOUND'); end if;
  if exists (select 1 from outbound_emails where opportunity_id = p_opportunity_id
             and status in ('APPROVED', 'PROCESSING', 'DRAFTED', 'SENT')) then
    return jsonb_build_object('ok', false, 'reason', 'ALREADY_APPROVED');
  end if;
  if coalesce(btrim(p_subject), '') = '' or coalesce(btrim(p_body), '') = ''
     or length(p_subject) > 200 or length(p_body) > 8000 then
    return jsonb_build_object('ok', false, 'reason', 'INVALID_CONTENT');
  end if;

  v_cur := hq_current_draft(p_opportunity_id);
  if v_cur is null then return jsonb_build_object('ok', false, 'reason', 'NO_DRAFT'); end if;

  if not exists (select 1 from outreach_drafts where opportunity_id = p_opportunity_id) then
    insert into outreach_drafts (opportunity_id, version, subject, body, follow_up_plan, source, source_task_id, created_by)
    values (p_opportunity_id, 1, v_cur->>'subject', v_cur->>'body', v_cur->>'follow_up_plan', 'WF05_ORIGINAL',
      (v_cur->>'source_task_id')::uuid, 'workflow 05');
  end if;
  select max(version) + 1 into v_next from outreach_drafts where opportunity_id = p_opportunity_id;

  insert into outreach_drafts (opportunity_id, version, subject, body, follow_up_plan, source, source_task_id, edit_note, created_by)
  values (p_opportunity_id, v_next, btrim(p_subject), btrim(p_body), v_cur->>'follow_up_plan', 'ADAM_EDIT',
    (v_cur->>'source_task_id')::uuid, left(p_note, 500), v_admin);

  insert into approval_audit (opportunity_id, action, result, actor, detail)
  values (p_opportunity_id, 'EDIT', 'SAVED', v_admin,
    jsonb_build_object('version', v_next, 'previous_subject', v_cur->>'subject', 'subject', btrim(p_subject), 'note', p_note));

  return jsonb_build_object('ok', true, 'version', v_next);
end;
$$;

create or replace function public.hq_dispatch_outbound(p_outbound_id uuid, p_actor text)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req bigint;
begin
  select net.http_post(
    url := 'https://noyaprivate.app.n8n.cloud/webhook/noya-outbound-execute',
    body := jsonb_build_object('outbound_id', p_outbound_id),
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 30000) into v_req;
  insert into approval_audit (outbound_email_id, opportunity_id, action, result, actor, detail)
  select p_outbound_id, opportunity_id, 'DISPATCH_TO_WORKFLOW_12', 'QUEUED', p_actor, jsonb_build_object('pg_net_request_id', v_req)
  from outbound_emails where id = p_outbound_id;
  return v_req;
end;
$$;

create or replace function public.hq_approve_draft(p_opportunity_id uuid, p_version int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin text := hq_admin_email();
  v_existing outbound_emails%rowtype;
  v_cur jsonb;
  v_attempt int;
  v_res jsonb;
  v_req bigint;
begin
  perform 1 from opportunities where id = p_opportunity_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'OPPORTUNITY_NOT_FOUND'); end if;

  if exists (select 1 from approval_queue_state where opportunity_id = p_opportunity_id and state = 'REJECTED')
     or exists (select 1 from opportunities where id = p_opportunity_id and approval_status = 'REJECTED') then
    insert into approval_audit (opportunity_id, action, result, actor, detail)
    values (p_opportunity_id, 'APPROVE_DRAFT', 'BLOCKED', v_admin, jsonb_build_object('reason', 'REJECTED'));
    return jsonb_build_object('ok', false, 'reason', 'REJECTED');
  end if;

  -- One draft per approval: anything already in flight, drafted or sent is final.
  select * into v_existing from outbound_emails
  where opportunity_id = p_opportunity_id and status in ('APPROVED', 'PROCESSING', 'DRAFTED', 'SENT')
  order by created_at desc limit 1;
  if found then
    insert into approval_audit (opportunity_id, outbound_email_id, action, result, actor, detail)
    values (p_opportunity_id, v_existing.id, 'APPROVE_DRAFT', 'DUPLICATE_IGNORED', v_admin,
      jsonb_build_object('existing_status', v_existing.status));
    return jsonb_build_object('ok', false, 'reason', 'ALREADY_PROCESSED', 'outbound_id', v_existing.id,
      'status', v_existing.status);
  end if;

  v_cur := hq_current_draft(p_opportunity_id);
  if v_cur is null or coalesce(v_cur->>'subject', '') = '' or coalesce(v_cur->>'body', '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'NO_DRAFT');
  end if;
  if (v_cur->>'version')::int <> p_version then
    return jsonb_build_object('ok', false, 'reason', 'DRAFT_CHANGED_REFRESH', 'current_version', (v_cur->>'version')::int);
  end if;

  select count(*) into v_attempt from outbound_emails where opportunity_id = p_opportunity_id;

  -- All recipient gates (exists, VERIFIED, not do-not-contact) live in outbound_approve.
  v_res := outbound_approve(p_opportunity_id, 'DRAFT', v_cur->>'subject', v_cur->>'body', v_admin,
    'hq-' || p_opportunity_id || '-v' || p_version || '-a' || v_attempt,
    'Approved in CEO Command Centre (draft v' || p_version || ')');
  if not coalesce((v_res->>'ok')::boolean, false) then
    return v_res;
  end if;

  delete from approval_queue_state where opportunity_id = p_opportunity_id and state = 'HOLD';
  update tasks set status = 'CANCELLED', updated_at = now()
  where opportunity_id = p_opportunity_id and task_type = 'APPROVAL_HOLD' and status in ('OPEN', 'IN_PROGRESS', 'WAITING');

  v_req := hq_dispatch_outbound((v_res->>'outbound_id')::uuid, v_admin);
  return v_res || jsonb_build_object('dispatched', true, 'pg_net_request_id', v_req, 'draft_version', p_version);
end;
$$;

create or replace function public.hq_redispatch(p_outbound_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin text := hq_admin_email();
  v_row outbound_emails%rowtype;
begin
  select * into v_row from outbound_emails where id = p_outbound_id;
  if not found or v_row.mode <> 'DRAFT' or v_row.status <> 'APPROVED' or v_row.created_at > now() - interval '2 minutes' then
    return jsonb_build_object('ok', false, 'reason', 'NOT_ELIGIBLE');
  end if;
  return jsonb_build_object('ok', true, 'pg_net_request_id', hq_dispatch_outbound(p_outbound_id, v_admin));
end;
$$;

create or replace function public.hq_hold(p_opportunity_id uuid, p_review_date date default null, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin text := hq_admin_email();
  v_company text;
  v_task uuid;
begin
  select company_name into v_company from opportunities where id = p_opportunity_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'OPPORTUNITY_NOT_FOUND'); end if;
  if exists (select 1 from outbound_emails where opportunity_id = p_opportunity_id
             and status in ('APPROVED', 'PROCESSING', 'DRAFTED', 'SENT')) then
    return jsonb_build_object('ok', false, 'reason', 'ALREADY_APPROVED');
  end if;
  if p_review_date is not null and (p_review_date < current_date or p_review_date > current_date + 365) then
    return jsonb_build_object('ok', false, 'reason', 'INVALID_DATE');
  end if;

  insert into approval_queue_state (opportunity_id, state, review_at, reason, decided_by)
  values (p_opportunity_id, 'HOLD', p_review_date, left(p_reason, 500), v_admin)
  on conflict (opportunity_id) do update set state = 'HOLD', review_at = excluded.review_at,
    reason = excluded.reason, decided_by = excluded.decided_by, decided_at = now();

  update opportunities set next_action = 'On hold' || coalesce(' until ' || to_char(p_review_date, 'DD Mon YYYY'), '') ||
    coalesce(' - ' || left(p_reason, 120), ''), updated_at = now()
  where id = p_opportunity_id;

  update tasks set due_at = coalesce(p_review_date::timestamptz, due_at), description = coalesce(left(p_reason, 500), description), updated_at = now()
  where opportunity_id = p_opportunity_id and task_type = 'APPROVAL_HOLD' and status in ('OPEN', 'IN_PROGRESS', 'WAITING')
  returning id into v_task;
  if v_task is null then
    insert into tasks (opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
    values (p_opportunity_id, 'REVIEW HELD OUTREACH -- ' || coalesce(v_company, 'opportunity'),
      coalesce(left(p_reason, 500), 'Held by Adam in the CEO Command Centre.'), 'APPROVAL_HOLD', 'Adam', 'CEO Command Centre',
      50, 'WAITING', coalesce(p_review_date::timestamptz, now() + interval '14 days'))
    returning id into v_task;
  end if;

  insert into approval_audit (opportunity_id, action, result, actor, detail)
  values (p_opportunity_id, 'HOLD', 'HELD', v_admin,
    jsonb_build_object('review_at', p_review_date, 'reason', p_reason, 'task_id', v_task));
  return jsonb_build_object('ok', true, 'task_id', v_task);
end;
$$;

create or replace function public.hq_reject(p_opportunity_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin text := hq_admin_email();
begin
  if coalesce(btrim(p_reason), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'REASON_REQUIRED');
  end if;
  perform 1 from opportunities where id = p_opportunity_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'OPPORTUNITY_NOT_FOUND'); end if;
  if exists (select 1 from outbound_emails where opportunity_id = p_opportunity_id
             and status in ('APPROVED', 'PROCESSING', 'DRAFTED', 'SENT')) then
    return jsonb_build_object('ok', false, 'reason', 'ALREADY_APPROVED');
  end if;

  insert into approval_queue_state (opportunity_id, state, reason, decided_by)
  values (p_opportunity_id, 'REJECTED', left(p_reason, 500), v_admin)
  on conflict (opportunity_id) do update set state = 'REJECTED', review_at = null,
    reason = excluded.reason, decided_by = excluded.decided_by, decided_at = now();

  update opportunities set approval_status = 'REJECTED', next_action = 'Outreach rejected by Adam: ' || left(p_reason, 200),
    updated_at = now()
  where id = p_opportunity_id;

  update tasks set status = 'CANCELLED', updated_at = now()
  where opportunity_id = p_opportunity_id and task_type in ('SALES_OUTREACH_APPROVAL', 'APPROVAL_HOLD')
    and status in ('OPEN', 'IN_PROGRESS', 'WAITING');

  insert into approval_audit (opportunity_id, action, result, actor, detail)
  values (p_opportunity_id, 'REJECT', 'REJECTED', v_admin, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true);
end;
$$;

-- ------------------------------------------------------------- privileges

revoke all on function public.hq_admin_email() from public, anon, authenticated;
revoke all on function public.hq_parse_draft(text) from public, anon, authenticated;
revoke all on function public.hq_trim(text) from public, anon, authenticated;
revoke all on function public.hq_current_draft(uuid) from public, anon, authenticated;
revoke all on function public.hq_dispatch_outbound(uuid, text) from public, anon, authenticated;
revoke all on function public.hq_dashboard() from public, anon;
revoke all on function public.hq_save_draft(uuid, text, text, text) from public, anon;
revoke all on function public.hq_approve_draft(uuid, int) from public, anon;
revoke all on function public.hq_redispatch(uuid) from public, anon;
revoke all on function public.hq_hold(uuid, date, text) from public, anon;
revoke all on function public.hq_reject(uuid, text) from public, anon;
grant execute on function public.hq_dashboard() to authenticated;
grant execute on function public.hq_save_draft(uuid, text, text, text) to authenticated;
grant execute on function public.hq_approve_draft(uuid, int) to authenticated;
grant execute on function public.hq_redispatch(uuid) to authenticated;
grant execute on function public.hq_hold(uuid, date, text) to authenticated;
grant execute on function public.hq_reject(uuid, text) to authenticated;
