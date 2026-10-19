-- NOYA professional operating mode (Adam, 18 Oct 2026), part 2: outreach capacity and priorities, the daily data integrity
-- check, the admin system-health read, HQ Advisor v2 (five daily recommendations) and the improvement loop
-- (OBSERVE -> DIAGNOSE -> RECOMMEND -> ADAM APPROVES -> APPLY -> MEASURE). Additive; nothing is deleted.

-- ---------------------------------------------------------------- 1. Capacity (section 14) and priorities (section 9)
-- At least 5 high-quality new email sends per working day; draft supply matches Adam's review capacity; 8-10 a day is a later
-- test, never straight back to 15. LinkedIn is the fallback, so open LinkedIn / Instagram drafts are capped at 5.
update public.system_config set value = jsonb_build_object('floor', 5, 'target', 8, 'cycle_days', 3, 'cycle_floor', 15, 'cycle_target', 24,
    'set_by', 'Adam, 18 Oct 2026 (section 14)', 'previous', value),
  note = 'Planned touches per working day: 8 drafts so that at least 5 high-quality new emails can be sent after review. Test 8-10 sends later, never straight back to 15+.', updated_at = now()
 where key = 'daily_touch_target' and (value->>'target')::int <> 8;
update public.system_config set value = value || jsonb_build_object('max_unsent_email_drafts', 10, 'max_open_social_drafts', 5,
    'weekly_new_sends_target', jsonb_build_array(25, 30), 'scaling_capacity_drafts_per_day', jsonb_build_array(6, 8),
    'note', 'Email is the primary cold channel. Draft supply matches Adam''s review capacity: at most 10 unsent email drafts (two days at 5 a day) and 5 open LinkedIn / Instagram fallbacks (Adam, 18 Oct 2026).',
    'previous_caps', jsonb_build_object('max_unsent_email_drafts', value->'max_unsent_email_drafts', 'max_open_social_drafts', value->'max_open_social_drafts')),
  updated_at = now()
 where key = 'email_reserve' and (value->>'max_unsent_email_drafts')::int <> 10;
update public.system_config set value = value || jsonb_build_object('email_topup_per_day', 3, 'previous_email_topup_per_day', value->'email_topup_per_day'), updated_at = now()
 where key = 'planner_options' and (value->>'email_topup_per_day')::int <> 3;
update public.system_config set value = jsonb_build_object(
    'note', 'NEW outreaches actually sent per working week (Mon-Fri, Cairo), email first: at least 5 a day (Adam, 18 Oct 2026). Directors keep at least buffer_weeks of untouched qualified prospects with a decision maker.',
    'total', jsonb_build_array(25, 30), 'buffer_weeks', 2,
    'by_director', jsonb_build_object('BRANDS', jsonb_build_array(8, 10), 'WEDDINGS', jsonb_build_array(6, 7), 'MEDIA', jsonb_build_array(1, 2),
                                      'TRAVEL', jsonb_build_array(4, 5), 'HOSPITALITY', jsonb_build_array(3, 4), 'SPORTS', jsonb_build_array(2, 3),
                                      'PRIVATE', jsonb_build_array(1, 2), 'CORPORATE', jsonb_build_array(0, 1)),
    'previous', value), updated_at = now()
 where key = 'weekly_send_targets' and value->'total' <> jsonb_build_array(25, 30);
update public.system_config set value = value || jsonb_build_object('priority_lanes', jsonb_build_array('BRANDS', 'WEDDINGS', 'MEDIA', 'TRAVEL', 'HOSPITALITY', 'SPORTS', 'PRIVATE', 'CORPORATE')),
  updated_at = now() where key = 'email_first';
-- Director order on every HQ screen follows Adam's priority list; member / founder communities are opportunistic.
update public.agent_registry r set sort = x.s from (values ('BRANDS', 1), ('WEDDINGS', 2), ('MEDIA', 3), ('TRAVEL', 4), ('HOSPITALITY', 5),
  ('SPORTS', 6), ('PRIVATE', 7), ('CORPORATE', 8), ('EGYPT', 9)) x(k, s) where r.key = x.k and r.sort <> x.s;

-- ---------------------------------------------------------------- 2. Daily data integrity check
-- Every check reports a count and up to five examples. p_apply only performs safe, deterministic corrections (today: owner
-- name variants of the same person). Everything else is reported for review, never "fixed" by guessing. The result is kept in
-- hq_read_cache('integrity'); it is deliberately not written to department_run_metrics, which is the agents' run log.
create or replace function public.integrity_check(p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb := '[]'::jsonb; n int; s jsonb; v_fixed int := 0; v_canon text := owner_for_role('CEO'); v_out jsonb; t0 timestamptz := clock_timestamp();
  v_cmd jsonb := coalesce((select payload from hq_read_cache where key = 'command'), '{}'::jsonb);
begin
  -- helper pattern: count, sample, append
  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('domain', account_domain, 'names', names) x, row_number() over () rn from company_account_duplicates) q;
  v := v || jsonb_build_object('key', 'DUPLICATE_COMPANIES', 'label', 'Duplicate companies (same web domain)', 'severity', 'WARN', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('email', e, 'contacts', c) x, row_number() over () rn from (
      select lower(email) e, count(*) c from contacts where coalesce(email, '') <> '' and coalesce(notes, '') not like '%MERGED_INTO:%' group by 1 having count(*) > 1) d) q;
  v := v || jsonb_build_object('key', 'DUPLICATE_CONTACTS', 'label', 'Contacts sharing one email address', 'severity', 'WARN', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('company', c.name, 'open_routes', z.k) x, row_number() over () rn from (
      select company_id, count(*) k from outreach_candidates where not dry_run and status in ('READY', 'REVIEW_REQUIRED', 'APPROVED') group by 1 having count(*) > 1) z
      join companies c on c.id = z.company_id) q;
  v := v || jsonb_build_object('key', 'MULTIPLE_COLD_ROUTES', 'label', 'Companies with more than one open cold message', 'severity', 'WARN', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('company', c.name, 'channel', oc.channel, 'since', oc.created_at::date) x, row_number() over (order by oc.created_at) rn
      from outreach_candidates oc join companies c on c.id = oc.company_id
     where not oc.dry_run and oc.status in ('READY', 'REVIEW_REQUIRED') and oc.channel = 'EMAIL' and oc.created_at < now() - interval '7 days') q;
  v := v || jsonb_build_object('key', 'STUCK_APPROVALS', 'label', 'Email drafts waiting for review over 7 days', 'severity', 'WARN', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select x, row_number() over () rn from (
      select jsonb_build_object('to', ob.to_email, 'status', ob.status, 'since', ob.updated_at) x from outbound_emails ob
       where (ob.status in ('QUEUED', 'CLAIMED') and ob.updated_at < now() - interval '2 hours') or (ob.status = 'DRAFTED' and ob.gmail_draft_id is null)
      union all
      select jsonb_build_object('company', c.name, 'status', oc.status, 'since', oc.updated_at) from outreach_candidates oc join companies c on c.id = oc.company_id
       where not oc.dry_run and oc.status = 'APPROVED' and oc.updated_at < now() - interval '2 hours'
         and not exists (select 1 from outbound_emails ob where ob.candidate_id = oc.id and ob.status in ('DRAFTED', 'SENT'))) u) q;
  v := v || jsonb_build_object('key', 'MISSING_GMAIL_DRAFTS', 'label', 'Approved emails without a Gmail draft', 'severity', 'ERROR', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('to', to_email, 'id', id) x, row_number() over () rn from outbound_emails where status = 'SENT' and sent_at is null) q;
  v := v || jsonb_build_object('key', 'SENT_WITHOUT_TIMESTAMP', 'label', 'Sent emails without a send time', 'severity', 'ERROR', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('company', c.name, 'reply', max(i.occurred_at)::date) x, row_number() over () rn
      from interactions i join companies c on c.id = i.company_id
     where i.direction = 'INBOUND' and i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM') and i.occurred_at > now() - interval '90 days'
       and not exists (select 1 from opportunities o where o.company_id = i.company_id) group by c.name) q;
  v := v || jsonb_build_object('key', 'REPLY_WITHOUT_OPPORTUNITY', 'label', 'Replies with no opportunity', 'severity', 'WARN', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('company', o->>'company', 'stage', o->>'label', 'missing', o->'missing') x, row_number() over () rn
      from jsonb_array_elements(coalesce(v_cmd->'opportunities', '[]'::jsonb)) o
     where o->>'stage' in ('REPLIED', 'POSITIVE') and (o->'missing' ? 'NO_NEXT_ACTION' or o->'missing' ? 'NO_DATE')) q;
  v := v || jsonb_build_object('key', 'REPLY_WITHOUT_NEXT_ACTION', 'label', 'Replies with no next action and date (REPLY -> NOTHING)', 'severity', 'ERROR', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('company', o->>'company', 'missing', o->'missing') x, row_number() over () rn
      from jsonb_array_elements(coalesce(v_cmd->'opportunities', '[]'::jsonb)) o
     where o->>'stage' = 'MEETING' and (o->'missing' ? 'NO_NEXT_ACTION' or o->'missing' ? 'NO_DATE')) q;
  v := v || jsonb_build_object('key', 'MEETING_WITHOUT_NEXT_ACTION', 'label', 'Meetings with no next action and date (MEETING -> NOTHING)', 'severity', 'ERROR', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('company', o->>'company', 'stage', o->>'label', 'due', o->>'next_action_due') x, row_number() over () rn
      from jsonb_array_elements(coalesce(v_cmd->'opportunities', '[]'::jsonb)) o where o->'missing' ? 'OVERDUE') q;
  v := v || jsonb_build_object('key', 'LIVE_OPPORTUNITY_OVERDUE', 'label', 'Live opportunities past their next-action date', 'severity', 'WARN', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('company', c.name, 'won_at', o.won_at::date) x, row_number() over () rn from opportunities o join companies c on c.id = o.company_id
     where o.status = 'WON' and not exists (select 1 from projects p where p.opportunity_id = o.id or p.company_id = o.company_id)) q;
  v := v || jsonb_build_object('key', 'WON_WITHOUT_PROJECT', 'label', 'Won opportunities with no project', 'severity', 'ERROR', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('company', c.name, 'won_at', o.won_at::date) x, row_number() over () rn from opportunities o join companies c on c.id = o.company_id
     where o.status = 'WON' and not exists (select 1 from revenue r where r.opportunity_id = o.id or r.company_id = o.company_id)) q;
  v := v || jsonb_build_object('key', 'WON_WITHOUT_REVENUE', 'label', 'Won opportunities with no revenue record', 'severity', 'ERROR', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('project', name, 'status', status) x, row_number() over () rn from projects
     where status in ('CONFIRMED', 'PLANNING', 'LIVE') and nullif(btrim(owner), '') is null) q;
  v := v || jsonb_build_object('key', 'PROJECT_WITHOUT_OWNER', 'label', 'Active projects with no owner', 'severity', 'ERROR', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select x, row_number() over () rn from (
      select jsonb_build_object('project', p.name, 'status', p.status) x from projects p
       where p.status in ('DELIVERED', 'CLOSED') and not exists (select 1 from revenue r where r.project_id = p.id or (r.company_id = p.company_id and r.payment_status <> 'CANCELLED'))
      union all
      select jsonb_build_object('revenue', coalesce(r.client_name, r.description), 'status', r.payment_status, 'paid', coalesce((select sum(y.amount) from revenue_payments y where y.revenue_id = r.id), 0), 'amount', r.amount)
        from revenue r where r.payment_status = 'PAID' and coalesce((select sum(y.amount) from revenue_payments y where y.revenue_id = r.id), 0) < r.amount) u) q;
  v := v || jsonb_build_object('key', 'PAID_WITHOUT_REVENUE', 'label', 'Delivered work with no revenue, or paid records without payments', 'severity', 'ERROR', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('company', c.name, 'since', oc.created_at::date) x, row_number() over (order by oc.created_at) rn
      from outreach_candidates oc join companies c on c.id = oc.company_id left join tasks t on t.id = oc.task_id
     where not oc.dry_run and oc.status in ('READY', 'REVIEW_REQUIRED') and oc.created_at < now() - interval '14 days'
       and coalesce(t.revalidated_at, oc.created_at) < now() - interval '14 days') q;
  v := v || jsonb_build_object('key', 'EXPIRED_DRAFTS', 'label', 'Drafts older than 14 days and not revalidated', 'severity', 'WARN', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('task', left(title, 80), 'due', due_at::date) x, row_number() over (order by due_at) rn from tasks
     where status = 'OPEN' and task_type = 'OUTREACH_FOLLOW_UP' and due_at < now() - interval '2 days') q;
  v := v || jsonb_build_object('key', 'OVERDUE_FOLLOW_UPS', 'label', 'Follow-ups more than 2 days overdue', 'severity', 'WARN', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('since', min(created_at)::date, 'open', count(*)) x, 1 rn from tasks
     where status in ('OPEN', 'IN_PROGRESS') and title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY)'
    having count(*) > coalesce((select (value->>'max_open_social_drafts')::int from system_config where key = 'email_reserve'), 20)) q;
  v := v || jsonb_build_object('key', 'SOCIAL_DRAFTS_OVER_CAP', 'label', 'Open LinkedIn / Instagram fallbacks above the cap', 'severity', 'WARN',
    'count', coalesce((select (s->0->>'open')::int), 0), 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('output', so.case_slug, 'document', so.evidence->'attachment'->>'document', 'version', so.evidence->'attachment'->>'version') x, row_number() over () rn
      from studio_outputs so
     where so.status = 'PREPARED' and so.evidence->'attachment'->>'document' is not null
       and not exists (select 1 from studio_documents d where d.slug = so.evidence->'attachment'->>'document' and d.version = (so.evidence->'attachment'->>'version')::int
                         and d.content->>'sha256' = so.evidence->'attachment'->>'document_sha256'
                         and d.status = coalesce(so.evidence->'attachment'->>'document_status', d.status))) q;
  v := v || jsonb_build_object('key', 'STUDIO_ATTACHMENT_MISMATCH', 'label', 'Studio drafts whose attachment no longer matches the document record', 'severity', 'ERROR', 'count', n, 'sample', s);

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('owner', owner, 'opportunities', count(*)) x, 1 rn from opportunities
     where owner is not null and owner <> v_canon and lower(split_part(owner, ' ', 1)) = lower(v_canon) group by owner) q;
  if p_apply and n > 0 then
    update opportunities set owner = v_canon where owner is not null and owner <> v_canon and lower(split_part(owner, ' ', 1)) = lower(v_canon);
    get diagnostics v_fixed = row_count;
  end if;
  v := v || jsonb_build_object('key', 'OWNER_NAME_VARIANTS', 'label', 'Opportunity owner written two ways for the same person', 'severity', 'INFO', 'count', case when v_fixed > 0 then 0 else n end,
    'sample', s, 'auto_fixed', v_fixed, 'fix', 'Owner set to "' || v_canon || '" (the CEO in role routing). Safe: same person, one canonical name.');

  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), '[]') into n, s from (
    select jsonb_build_object('task', left(title, 90), 'since', created_at::date) x, row_number() over (order by created_at) rn from tasks
     where status in ('OPEN', 'IN_PROGRESS') and (task_type ilike '%ALERT%' or task_type = 'SYSTEM_FAILURE') and created_at > now() - interval '7 days') q;
  v := v || jsonb_build_object('key', 'WORKFLOW_FAILURES_7D', 'label', 'Workflow failure alerts in the last 7 days', 'severity', 'ERROR', 'count', n, 'sample', s);

  v_out := jsonb_build_object('generated_at', now(), 'applied', p_apply, 'checks', v,
    'issues', (select count(*) from jsonb_array_elements(v) c where (c->>'count')::int > 0),
    'errors', (select count(*) from jsonb_array_elements(v) c where (c->>'count')::int > 0 and c->>'severity' = 'ERROR'),
    'auto_fixed', v_fixed, 'build_ms', (extract(epoch from clock_timestamp() - t0) * 1000)::int);
  if p_apply then
    insert into hq_read_cache (key, payload, built_at, build_ms) values ('integrity', v_out, now(), (v_out->>'build_ms')::int)
    on conflict (key) do update set payload = excluded.payload, built_at = excluded.built_at, build_ms = excluded.build_ms;
  end if;
  return v_out;
end $$;

-- ---------------------------------------------------------------- 3. Admin system health (More / Admin only; never on CEO screens)
create or replace function public.hq_health()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  select jsonb_build_object(
    'generated_at', now(),
    'supabase', jsonb_build_object('database_mb', round(pg_database_size(current_database()) / 1048576.0),
      'cron', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'active', j.active,
                  'last_ok', (select max(d.start_time) from cron.job_run_details d where d.jobid = j.jobid and d.status = 'succeeded'),
                  'failed_7d', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.status = 'failed' and d.start_time > now() - interval '7 days'))
                  order by j.jobid), '[]'::jsonb) from cron.job j),
      'backups', 'Managed by Supabase, not readable from the database.'),
    'snapshots', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'age_min', round(extract(epoch from now() - built_at) / 60), 'build_ms', build_ms,
                    'error', last_error, 'error_at', last_error_at) order by key), '[]'::jsonb) from hq_read_cache),
    'agents', (select coalesce(jsonb_agg(jsonb_build_object('key', r.key, 'name', r.name, 'workflows', r.workflows, 'last_run', lr,
                 'max_gap_hours', r.max_gap_hours, 'on_schedule', lr is not null and lr > now() - make_interval(hours => r.max_gap_hours::int)) order by r.sort), '[]'::jsonb)
                 from (select r.*, director_last_run(r.key) lr from agent_registry r where r.v3_role is not null) r),
    'workflow_runs', (select coalesce(jsonb_agg(jsonb_build_object('workflow', workflow_name, 'runs_7d', n, 'last', last) order by workflow_name), '[]'::jsonb)
                        from (select workflow_name, count(*) filter (where recorded_at > now() - interval '7 days') n, max(recorded_at) last from department_run_metrics group by 1) x),
    'failures', (select coalesce(jsonb_agg(jsonb_build_object('title', left(title, 120), 'type', task_type, 'at', created_at) order by created_at desc), '[]'::jsonb)
                   from tasks where status in ('OPEN', 'IN_PROGRESS') and (task_type ilike '%ALERT%' or task_type = 'SYSTEM_FAILURE')),
    'gmail', (select jsonb_build_object('mailbox', mailbox, 'last_sync', last_run_at, 'on_schedule', last_run_at > now() - interval '2 hours', 'summary', last_run_summary)
                from gmail_sync_state order by id limit 1),
    'gmail_history', (select jsonb_build_object('last_import', last_run_at, 'on_schedule', last_run_at > now() - interval '6 hours', 'error', last_error)
                        from gmail_backfill_state order by last_run_at desc nulls last limit 1),
    'hunter', (select value - 'raw' from system_config where key = 'hunter_account'),
    'serper', (select jsonb_build_object('balance', balance, 'at', recorded_at) from provider_balances where provider = 'SERPER' order by recorded_at desc limit 1),
    'ai', jsonb_build_object(
      'by_workflow_7d', (select coalesce(jsonb_agg(jsonb_build_object('workflow', workflow, 'ok', ok, 'error', err, 'rate_limited', rl, 'usd', usd, 'last', last,
                            'rate_limited_pct', round(100.0 * rl / nullif(ok + err + rl, 0))) order by workflow), '[]'::jsonb)
                          from (select workflow, count(*) filter (where status = 'OK') ok, count(*) filter (where status = 'ERROR') err,
                                       count(*) filter (where status = 'RATE_LIMITED') rl, round(sum(est_cost_usd), 3) usd, max(at) last
                                  from ai_usage where at > now() - interval '7 days' group by 1) x),
      'usd_30d', (select round(coalesce(sum(est_cost_usd), 0), 2) from ai_usage where at > now() - interval '30 days'),
      'budget', (select value from system_config where key = 'ai_budget')),
    'studio', jsonb_build_object('documents', (select count(*) from studio_documents), 'last_recorded', (select max(created_at) from studio_documents),
      'outputs', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from studio_outputs group by 1) x),
      'renderer', 'Chromium in the build environment (studio/render.mjs), rendered on demand, not a hosted service.'),
    'blockers', (select coalesce(jsonb_agg(jsonb_build_object('key', blocker_key, 'title', title, 'severity', severity, 'owner_action', owner_action, 'since', detected_at)), '[]'::jsonb)
                   from system_blockers where status <> 'RESOLVED'),
    'integrity', (select payload from hq_read_cache where key = 'integrity'))
  into v;
  return v;
end $$;

-- ---------------------------------------------------------------- 4. Improvement loop (task_type IMPROVEMENT)
-- spec: key, area, observe, diagnose, recommend, change {type CONFIG|ACTION|MANUAL, ...}, measure {metric, baseline}, state.
-- Approve applies a CONFIG change (only if the value is still what the recommendation saw) or a whitelisted ACTION; MANUAL
-- changes are recorded for the System to carry out. Measurement compares the metric 7 days after it was applied.
create or replace function public.ops_metric(p_key text)
returns numeric language sql stable security definer set search_path = public as $$
  select case p_key
    when 'EMAIL_SENDS_7D' then (select count(*)::numeric from interactions i where i.direction = 'OUTBOUND' and i.channel = 'EMAIL' and i.occurred_at > now() - interval '7 days'
                                  and not exists (select 1 from interactions e where e.company_id = i.company_id and e.channel = 'EMAIL' and e.direction = 'OUTBOUND'
                                                   and e.occurred_at < i.occurred_at and e.occurred_at > i.occurred_at - interval '120 days'))
    when 'OPEN_SOCIAL_DRAFTS' then (select count(*)::numeric from tasks where status in ('OPEN', 'IN_PROGRESS') and title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY)')
    when 'OPEN_EMAIL_DRAFTS' then (select count(*)::numeric from outreach_candidates oc join tasks t on t.id = oc.task_id
                                     where not oc.dry_run and oc.channel = 'EMAIL' and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING'))
    when 'OVERDUE_FOLLOW_UPS' then (select count(*)::numeric from tasks where status = 'OPEN' and task_type = 'OUTREACH_FOLLOW_UP' and due_at < now())
    when 'W18_RATE_LIMITED_PCT_7D' then (select round(100.0 * count(*) filter (where status = 'RATE_LIMITED') / nullif(count(*), 0)) from ai_usage where workflow = '18' and at > now() - interval '7 days')
    when 'UNCLASSIFIED_REPLIES_30D' then (select count(*)::numeric from interactions where direction = 'INBOUND' and channel = 'EMAIL' and occurred_at > now() - interval '30 days'
                                            and coalesce(summary, '') like 'UNKNOWN: Classifier unavailable%')
    end
$$;

create or replace function public.improvement_upsert(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id from tasks where task_type = 'IMPROVEMENT' and spec->>'key' = p->>'key'
     and (status in ('OPEN', 'IN_PROGRESS') or (status = 'CANCELLED' and updated_at > now() - interval '30 days')) limit 1;
  if v_id is not null then return v_id; end if;
  insert into tasks (title, description, task_type, assigned_to, created_by, priority, status, spec)
  values ('RECOMMENDATION -- ' || (p->>'title'), p->>'recommend', 'IMPROVEMENT', 'Adam', 'HQ Advisor', coalesce((p->>'priority')::int, 60), 'OPEN',
          p || jsonb_build_object('state', 'RECOMMENDED', 'observed_at', now(),
               'measure', coalesce(p->'measure', '{}'::jsonb) || jsonb_build_object('baseline', ops_metric(p->'measure'->>'metric'), 'baseline_at', now())))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.hq_recommendation_action(p_id uuid, p_action text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); t tasks%rowtype; c jsonb; v_cur jsonb; v_res jsonb := '{}'::jsonb; v_n int := 0; r record;
begin
  select * into t from tasks where id = p_id and task_type = 'IMPROVEMENT';
  if t.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if t.status <> 'OPEN' then return jsonb_build_object('ok', false, 'reason', 'ALREADY_DECIDED'); end if;
  if upper(p_action) = 'DECLINE' then
    update tasks set status = 'CANCELLED', updated_at = now(),
           spec = spec || jsonb_build_object('state', 'DECLINED', 'decided_at', now(), 'decided_by', v_admin, 'note', hq_trim(p_note)) where id = p_id;
    perform hq_audit('RECOMMENDATION_DECLINED', null, jsonb_build_object('task_id', p_id, 'key', t.spec->>'key'));
    return jsonb_build_object('ok', true, 'state', 'DECLINED');
  end if;
  if upper(p_action) <> 'APPROVE' then return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION'); end if;
  c := t.spec->'change';
  if c->>'type' = 'CONFIG' then
    if c->>'config_key' not in ('daily_touch_target', 'acquisition_mix', 'email_reserve', 'planner_options', 'weekly_send_targets') then
      return jsonb_build_object('ok', false, 'reason', 'CONFIG_KEY_NOT_ALLOWED'); end if;
    select value into v_cur from system_config where key = c->>'config_key';
    if c ? 'expect' and v_cur @> (c->'expect') is not true then return jsonb_build_object('ok', false, 'reason', 'CONFIG_CHANGED_SINCE_RECOMMENDED', 'current', v_cur); end if;
    update system_config set value = value || (c->'set'), updated_at = now(), note = coalesce(note, '') || ' | ' || (t.spec->>'title') || ' (approved by Adam ' || to_char(now(), 'DD Mon') || ')'
     where key = c->>'config_key';
    v_res := jsonb_build_object('before', v_cur, 'set', c->'set');
  elsif c->>'type' = 'ACTION' and c->>'action' = 'PARK_SOCIAL_EXCESS' then
    for r in select oc.id cid, t2.id tid from tasks t2 left join outreach_candidates oc on oc.task_id = t2.id
              where t2.status in ('OPEN', 'IN_PROGRESS') and t2.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY)'
              order by t2.created_at desc offset greatest(coalesce((c->>'keep')::int, 5), 0) loop
      update tasks set status = 'CANCELLED', updated_at = now(),
             description = 'Parked ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon') || ' (Adam approved: LinkedIn is the fallback, keep the newest ' || coalesce(c->>'keep', '5') || '). Re-open from HQ if wanted.' || chr(10) || coalesce(description, '')
       where id = r.tid;
      if r.cid is not null then update outreach_candidates set status = 'HOLD', hold_reason = 'PARKED_SOCIAL_FALLBACK_CAP', updated_at = now() where id = r.cid; end if;
      v_n := v_n + 1;
    end loop;
    v_res := jsonb_build_object('parked', v_n);
  elsif c->>'type' = 'ACTION' and c->>'action' = 'CLOSE_STALE_FOLLOW_UPS' then
    update tasks set status = 'CANCELLED', updated_at = now(),
           description = 'Closed ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon') || ': no reply and more than ' || coalesce(c->>'days', '14') || ' days overdue (Adam approved). The company can be approached again later.' || chr(10) || coalesce(description, '')
     where status = 'OPEN' and task_type = 'OUTREACH_FOLLOW_UP' and due_at < now() - make_interval(days => coalesce((c->>'days')::int, 14));
    get diagnostics v_n = row_count;
    v_res := jsonb_build_object('closed', v_n);
  elsif c->>'type' <> 'MANUAL' then
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_CHANGE');
  end if;
  update tasks set status = 'IN_PROGRESS', updated_at = now(),
         spec = spec || jsonb_build_object('state', case when c->>'type' = 'MANUAL' then 'APPROVED' else 'APPLIED' end, 'decided_at', now(), 'decided_by', v_admin,
                                           'applied_at', case when c->>'type' <> 'MANUAL' then now() end, 'result', v_res, 'note', hq_trim(p_note))
   where id = p_id;
  perform hq_audit('RECOMMENDATION_APPROVED', null, jsonb_build_object('task_id', p_id, 'key', t.spec->>'key', 'result', v_res));
  return jsonb_build_object('ok', true, 'state', case when c->>'type' = 'MANUAL' then 'APPROVED' else 'APPLIED' end, 'result', v_res);
end $$;

-- MEASURE: 7 days after a change was applied, record the metric against its baseline and close the loop.
create or replace function public.improvements_refresh()
returns integer language plpgsql security definer set search_path = public as $$
declare t record; n int := 0;
begin
  for t in select id, spec from tasks where task_type = 'IMPROVEMENT' and status = 'IN_PROGRESS' and spec->>'state' = 'APPLIED'
            and (spec->>'applied_at')::timestamptz < now() - interval '7 days' loop
    update tasks set status = 'COMPLETED', completed_at = now(), updated_at = now(),
           spec = spec || jsonb_build_object('state', 'MEASURED', 'measured_at', now(),
                  'measure', (spec->'measure') || jsonb_build_object('after', ops_metric(spec->'measure'->>'metric'))) where id = t.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------- 5. HQ Advisor v2: five daily recommendations
-- 1 What you should do · 2 Biggest bottleneck · 3 Best opportunity · 4 Agent to correct · 5 What should stop. The allocation
-- recommendation is weekly ('weekly_allocation'), not a daily slot.
create or replace function public.advisor_slots(p_obs jsonb, p_waste jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare o jsonb := '[]'::jsonb; a jsonb; b jsonb; tg jsonb; op jsonb; v_rl numeric; v_social int; v_cap int; v_email int; v_down_key text; v_down_name text; v_down_lr timestamptz; v_fu int; v_w jsonb;
begin
  select x into a from jsonb_array_elements(p_obs) x where x->>'kind' = 'ATTENTION' limit 1;
  select x into b from jsonb_array_elements(p_obs) x where x->>'kind' = 'BOTTLENECK' limit 1;
  select x into tg from jsonb_array_elements(p_obs) x where x->>'kind' = 'TARGET' limit 1;
  select x into op from jsonb_array_elements(p_obs) x where x->>'kind' = 'OPPORTUNITY' limit 1;
  v_email := ops_metric('OPEN_EMAIL_DRAFTS')::int;
  if a is not null then o := o || (a || jsonb_build_object('title', 'WHAT YOU SHOULD DO', 'slot', 1)); end if;
  -- the bottleneck: Adam's sending when drafts are waiting, otherwise contact / verification capacity
  if tg is not null and v_email >= 5 then
    o := o || (tg || jsonb_build_object('kind', 'BOTTLENECK', 'title', 'BIGGEST BOTTLENECK', 'slot', 2,
               'meaning', v_email || ' email drafts are already waiting for review, so sending is the limit, not supply. Five good sends a day is the standard.'));
  elsif b is not null then o := o || (b || jsonb_build_object('title', 'BIGGEST BOTTLENECK', 'slot', 2));
  elsif tg is not null then o := o || (tg || jsonb_build_object('kind', 'BOTTLENECK', 'title', 'BIGGEST BOTTLENECK', 'slot', 2)); end if;
  if op is not null then o := o || (op || jsonb_build_object('title', 'BEST OPPORTUNITY', 'slot', 3)); end if;
  -- the agent to correct: a Director not running on schedule, then the Outreach Writer's provider failures, then a lane with sends and no replies
  select r.key, r.name, director_last_run(r.key) into v_down_key, v_down_name, v_down_lr from agent_registry r
   where r.v3_role is not null and r.key not in ('PARTNERSHIPS', 'GROWTH')
     and coalesce(director_last_run(r.key), '-infinity'::timestamptz) < now() - make_interval(hours => r.max_gap_hours::int)
   order by r.sort limit 1;
  v_rl := ops_metric('W18_RATE_LIMITED_PCT_7D');
  if exists (select 1 from tasks where status in ('OPEN', 'IN_PROGRESS') and task_type = 'SYSTEM_FAILURE_ALERT' and title like '%18 - NOYA%' and created_at > now() - interval '48 hours') then
    o := o || jsonb_build_object('kind', 'CORRECTION', 'title', 'AGENT TO CORRECT', 'slot', 4, 'tab', 'system', 'director', 'WRITER',
      'situation', 'The Outreach Writer failed in the last 48 hours: its drafting model was unavailable.',
      'meaning', 'No new email drafts are written while it fails. Drafts already waiting are unaffected.',
      'action', 'Give the Writer a backup model for when its main one is down. The System makes the change once the workflow connection is restored (details in Admin, System health).');
  elsif v_down_key is not null then
    o := o || jsonb_build_object('kind', 'CORRECTION', 'title', 'AGENT TO CORRECT', 'slot', 4, 'tab', 'system', 'director', v_down_key,
      'situation', v_down_name || ' has not run on schedule since ' || coalesce(to_char(v_down_lr at time zone 'Africa/Cairo', 'DD Mon HH24:MI'), 'it was registered') || '.',
      'meaning', 'Work orders and research for this Director wait until it runs again.', 'action', 'Details are in Admin, System health.');
  elsif coalesce(v_rl, 0) >= 20 then
    o := o || jsonb_build_object('kind', 'CORRECTION', 'title', 'AGENT TO CORRECT', 'slot', 4, 'tab', 'system', 'director', 'WRITER',
      'situation', 'The Outreach Writer was rate-limited on ' || v_rl || '% of its calls this week.',
      'meaning', 'Rate-limited drafts fall back to a weaker model or wait a day.', 'action', 'Draft supply is now capped to review capacity (8 a day), which keeps calls under the limit.');
  elsif jsonb_array_length(coalesce(p_waste, '[]')) > 0 then
    select x into v_w from jsonb_array_elements(p_waste) x where x->>'text' ~ 'no reply yet' limit 1;
    v_w := coalesce(v_w, p_waste->0);
    o := o || jsonb_build_object('kind', 'CORRECTION', 'title', 'AGENT TO CORRECT', 'slot', 4, 'tab', 'agents', 'director', v_w->>'director',
      'situation', v_w->>'text', 'meaning', 'Effort here is not turning into conversations yet.', 'action', 'Review the targeting and angle before more volume goes to this lane.');
  end if;
  -- what should stop
  select coalesce((value->>'max_open_social_drafts')::int, 20) into v_cap from system_config where key = 'email_reserve';
  v_social := ops_metric('OPEN_SOCIAL_DRAFTS')::int; v_fu := ops_metric('OVERDUE_FOLLOW_UPS')::int;
  if v_social > v_cap then
    o := o || jsonb_build_object('kind', 'STOP', 'title', 'WHAT SHOULD STOP', 'slot', 5, 'tab', 'desk',
      'situation', v_social || ' LinkedIn / Instagram fallback messages are waiting to be sent by hand (cap ' || v_cap || ').',
      'meaning', 'LinkedIn is the fallback channel. A growing hand-send pile hides the emails that matter.',
      'action', 'No new fallbacks are prepared above the cap. Approve parking the oldest so only the newest ' || v_cap || ' remain.');
  elsif v_fu > 10 then
    o := o || jsonb_build_object('kind', 'STOP', 'title', 'WHAT SHOULD STOP', 'slot', 5, 'tab', 'desk',
      'situation', v_fu || ' follow-ups are overdue.', 'meaning', 'New first messages pile up behind unanswered follow-ups.',
      'action', 'Clear the follow-ups on live lanes first, or approve closing those more than 14 days overdue.');
  elsif v_email > 10 then
    o := o || jsonb_build_object('kind', 'STOP', 'title', 'WHAT SHOULD STOP', 'slot', 5, 'tab', 'desk',
      'situation', v_email || ' email drafts are waiting for review.', 'meaning', 'Drafting beyond review capacity wastes AI calls and drafts go stale.',
      'action', 'New drafting pauses until the queue is below 10. Review the oldest first.');
  end if;
  return o;
end $$;

-- Patch the Advisor's return: the five slots replace the ranked list; the allocation item moves to 'weekly_allocation'.
create or replace function pg_temp.patch(p_fn regprocedure, p_pairs text[]) returns void language plpgsql as $$
declare d text := pg_get_functiondef(p_fn); i int; n int;
begin
  for i in 1 .. array_length(p_pairs, 1) / 2 loop
    n := (length(d) - length(replace(d, p_pairs[2 * i - 1], ''))) / length(p_pairs[2 * i - 1]);
    if n <> 1 then raise exception 'patch % #%: expected 1 match, found %', p_fn, i, n; end if;
    d := replace(d, p_pairs[2 * i - 1], p_pairs[2 * i]);
  end loop;
  execute d;
end $$;
select pg_temp.patch('public.hq_advisor()'::regprocedure, array[
  '''observations'', coalesce((select jsonb_agg(o order by (o->>''rank'')::int) from jsonb_array_elements(v_obs) o), ''[]''::jsonb),',
  '''observations'', advisor_slots(v_obs, v_waste),
    ''weekly_allocation'', (select o from jsonb_array_elements(v_obs) o where o->>''kind'' = ''ALLOCATE'' limit 1),']);

-- The command read carries the open recommendations and the latest integrity summary for the Advisor panel.
select pg_temp.patch('public.hq_command()'::regprocedure, array[
  '''directors'', (select jsonb_agg(jsonb_build_object(''key'', r.key, ''name'', r.name) order by r.sort) from agent_registry r where r.v3_role = ''DIRECTOR'' and r.kind = ''ACQUISITION''))',
  '''directors'', (select jsonb_agg(jsonb_build_object(''key'', r.key, ''name'', r.name) order by r.sort) from agent_registry r where r.v3_role = ''DIRECTOR'' and r.kind = ''ACQUISITION''),
    ''recommendations'', coalesce((select jsonb_agg(jsonb_build_object(''id'', t.id, ''title'', t.spec->>''title'', ''area'', t.spec->>''area'', ''state'', t.spec->>''state'',
        ''observe'', t.spec->>''observe'', ''diagnose'', t.spec->>''diagnose'', ''recommend'', t.spec->>''recommend'', ''change'', t.spec->''change'', ''measure'', t.spec->''measure'',
        ''result'', t.spec->''result'', ''decided_at'', t.spec->>''decided_at'', ''created_at'', t.created_at)
        order by (t.status = ''OPEN'') desc, t.priority desc nulls last, t.created_at desc)
      from tasks t where t.task_type = ''IMPROVEMENT'' and (t.status in (''OPEN'', ''IN_PROGRESS'') or t.updated_at > now() - interval ''14 days'')), ''[]''::jsonb),
    ''integrity'', (select jsonb_build_object(''generated_at'', payload->''generated_at'', ''issues'', payload->''issues'', ''errors'', payload->''errors'') from hq_read_cache where key = ''integrity''))']);

-- ---------------------------------------------------------------- 6. Cache keys and schedules
create or replace function public.hq_cache_key_ok(p_key text)
returns boolean language sql stable security definer set search_path = public as $$
  select p_key in ('ceo', 'network', 'advisor', 'directors', 'execution', 'command', 'health', 'integrity')
      or (p_key like 'director:%' and exists (select 1 from agent_registry r where r.key = substr(p_key, 10) and r.v3_role is not null));
$$;
select pg_temp.patch('public.hq_cache_build(text)'::regprocedure, array[
  'when ''command'' then hq_command()',
  'when ''command'' then hq_command()
      when ''health'' then hq_health()
      when ''integrity'' then integrity_check(false)']);

revoke all on function public.integrity_check(boolean), public.hq_health(), public.ops_metric(text), public.improvement_upsert(jsonb),
  public.hq_recommendation_action(uuid, text, text), public.improvements_refresh(), public.advisor_slots(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.hq_recommendation_action(uuid, text, text) to authenticated;

-- 05:10 Cairo daily integrity (03:10 UTC); system health every 15 minutes; improvement measurement daily.
select cron.schedule('integrity-daily', '10 3 * * *', 'select public.integrity_check(true)');
select cron.schedule('hq-health', '4,19,34,49 * * * *', 'select public.hq_cache_build(''health'')');
select cron.schedule('improvements-measure', '20 3 * * *', 'select public.improvements_refresh()');

-- ---------------------------------------------------------------- 7. Recommendations awaiting Adam (seeded 19 Oct 2026, data as of that day)
-- Each is one Approve / Decline in HQ. ACTION changes run on approval; MANUAL ones are carried out by the System afterwards.
select public.improvement_upsert(jsonb_build_object('key', 'PARK_SOCIAL_EXCESS_2026_10', 'title', 'Park the LinkedIn / Instagram backlog, keep the newest 5', 'area', 'Outreach volume', 'priority', 80,
  'observe', '69 LinkedIn and Instagram fallback messages are waiting to be sent by hand. The oldest is from 8 Sep, the newest from 10 Oct.',
  'diagnose', 'Email is the primary cold channel and LinkedIn the fallback. The pile grew when the planner prepared a fallback for every company without an email route, faster than anyone could send by hand.',
  'recommend', 'Park the 64 oldest (reversible: each can be re-opened from HQ) and keep the newest 5. New fallbacks are already capped at 5 open.',
  'change', jsonb_build_object('type', 'ACTION', 'action', 'PARK_SOCIAL_EXCESS', 'keep', 5),
  'measure', jsonb_build_object('metric', 'OPEN_SOCIAL_DRAFTS')));
select public.improvement_upsert(jsonb_build_object('key', 'CLOSE_STALE_FOLLOW_UPS_2026_10', 'title', 'Close follow-ups more than 14 days overdue', 'area', 'Follow-up cadence', 'priority', 70,
  'observe', '25 first follow-ups are overdue, the oldest since 30 Sep. 9 are more than 14 days overdue.',
  'diagnose', 'A follow-up to a cold contact loses its point after two weeks, and the overdue list hides the live conversations on the dashboard.',
  'recommend', 'Close the follow-ups more than 14 days overdue as no reply (the company can be approached again later with a new reason). Keep the more recent ones and send them this week.',
  'change', jsonb_build_object('type', 'ACTION', 'action', 'CLOSE_STALE_FOLLOW_UPS', 'days', 14),
  'measure', jsonb_build_object('metric', 'OVERDUE_FOLLOW_UPS')));
select public.improvement_upsert(jsonb_build_object('key', 'REPLY_CLASSIFIER_GEMINI', 'title', 'Move the reply classifier from Anthropic to Gemini', 'area', 'AI cost and reliability', 'priority', 75,
  'observe', 'Since 5 Oct every reply has been saved as unsorted: the reply sorter still uses an AI provider (Anthropic) whose account has no credit.',
  'diagnose', 'Every other agent already runs on Gemini. The reply sorter was never moved, so replies are detected but not sorted into positive, meeting request, not now and so on.',
  'recommend', 'Move the reply sorter to Gemini with the same instructions. No new subscription and no top-up. The System makes the change once the workflow connection is restored.',
  'change', jsonb_build_object('type', 'MANUAL', 'system_action', 'Edit workflow 13 Classify Reply node to the Gemini endpoint already used by workflows 19 and 23.'),
  'measure', jsonb_build_object('metric', 'UNCLASSIFIED_REPLIES_30D')));
select public.improvement_upsert(jsonb_build_object('key', 'REPO_PRIVATE', 'title', 'Make the NOYA code repository private', 'area', 'Security', 'priority', 65,
  'observe', 'The GitHub repository noya-sudo/noya-ai-os is public. It holds no keys and no client PDFs, but it describes the system and names some companies in documentation.',
  'diagnose', 'Nothing requires it to be public. Private removes the exposure at no cost.',
  'recommend', 'Make the repository private. The System changes the setting at its next session after your approval.',
  'change', jsonb_build_object('type', 'MANUAL', 'system_action', 'Set repository visibility to private.'),
  'measure', jsonb_build_object('metric', null)));

-- ---------------------------------------------------------------- 8. Consistency fixes found while testing (19 Oct)
-- (a) hq_ceo_dashboard counted a company whose opportunities are all closed (declined, lost, archived or long term) as a live
--     conversation because it had once replied; the command read parks it. Both now use one rule: closed opportunities park a
--     company unless a positive reply or a meeting is live.
-- (b) A two-way mailbox conversation whose domain matches no CRM company is invisible to the funnel; the integrity check lists it.
create or replace function pg_temp.patch(p_fn regprocedure, p_pairs text[]) returns void language plpgsql as $$
declare d text := pg_get_functiondef(p_fn); i int; n int;
begin
  for i in 1 .. array_length(p_pairs, 1) / 2 loop
    n := (length(d) - length(replace(d, p_pairs[2 * i - 1], ''))) / length(p_pairs[2 * i - 1]);
    if n <> 1 then raise exception 'patch % #%: expected 1 match, found %', p_fn, i, n; end if;
    d := replace(d, p_pairs[2 * i - 1], p_pairs[2 * i]);
  end loop;
  execute d;
end $$;
select pg_temp.patch('public.hq_ceo_dashboard()'::regprocedure, array[
  'when any_opp and not open_opp and not replied then 0',
  'when any_opp and not open_opp and not (meeting or positive) then 0']);
select pg_temp.patch('public.integrity_check(boolean)'::regprocedure, array[
  '  v := v || jsonb_build_object(''key'', ''REPLY_WITHOUT_OPPORTUNITY'', ''label'', ''Replies with no opportunity'', ''severity'', ''WARN'', ''count'', n, ''sample'', s)',
  '  v := v || jsonb_build_object(''key'', ''REPLY_WITHOUT_OPPORTUNITY'', ''label'', ''Replies with no opportunity'', ''severity'', ''WARN'', ''count'', n, ''sample'', s)' || chr(59) || '
  select count(*), coalesce(jsonb_agg(x) filter (where rn <= 5), ''[]'') into n, s from (
    select jsonb_build_object(''domain'', registrable_domain(t.counterpart_domains[1]), ''subject'', left(t.subject, 80), ''last'', t.last_at::date) x, row_number() over (order by t.last_at desc) rn
      from gmail_history_threads t
     where t.company_id is null and t.inbound > 0 and t.outbound > 0 and coalesce(t.relevant, true) and coalesce(t.hq_status, '''') <> ''DISMISSED''
       and t.last_at > now() - interval ''60 days''
       and registrable_domain(t.counterpart_domains[1]) !~ ''^(gmail|googlemail|hotmail|outlook|live|yahoo|icloud|aol|proton|protonmail|me|msn)\.''
       and not exists (select 1 from companies c where registrable_domain(c.website) = registrable_domain(t.counterpart_domains[1]))) q' || chr(59) || '
  v := v || jsonb_build_object(''key'', ''CONVERSATION_WITHOUT_COMPANY'', ''label'', ''Two-way mailbox conversations not linked to a CRM company (60 days)'', ''severity'', ''WARN'', ''count'', n, ''sample'', s)']);

-- ---------------------------------------------------------------- 9. HQ writes refresh the command snapshot at once
-- A work order, an opportunity plan, a recommendation decision or a revenue import shows on the dashboard immediately instead of
-- after the next 5-minute refresh. A failed refresh never fails the write.
create or replace function public.hq_command_touch()
returns void language plpgsql security definer set search_path = public as $$
begin
  perform hq_cache_build('command');
exception when others then
  null;
end $$;
revoke all on function public.hq_command_touch() from public, anon, authenticated;
select pg_temp.patch('public.hq_work_order(text,text,text,text,integer,date,text)'::regprocedure, array[
  'perform hq_audit(''WORK_ORDER_ISSUED''', 'perform hq_command_touch()' || chr(59) || ' perform hq_audit(''WORK_ORDER_ISSUED''']);
select pg_temp.patch('public.hq_work_order_action(uuid,text,text)'::regprocedure, array[
  'perform hq_audit(''WORK_ORDER_'' || upper(p_action)', 'perform hq_command_touch()' || chr(59) || ' perform hq_audit(''WORK_ORDER_'' || upper(p_action)']);
select pg_temp.patch('public.hq_opportunity_plan(uuid,text,date,text,text,boolean)'::regprocedure, array[
  'perform hq_audit(''OPPORTUNITY_PLAN''', 'perform hq_command_touch()' || chr(59) || ' perform hq_audit(''OPPORTUNITY_PLAN''']);
select pg_temp.patch('public.hq_recommendation_action(uuid,text,text)'::regprocedure, array[
  'perform hq_audit(''RECOMMENDATION_DECLINED''', 'perform hq_command_touch()' || chr(59) || ' perform hq_audit(''RECOMMENDATION_DECLINED''',
  'perform hq_audit(''RECOMMENDATION_APPROVED''', 'perform hq_command_touch()' || chr(59) || ' perform hq_audit(''RECOMMENDATION_APPROVED''']);
select pg_temp.patch('public.hq_revenue_import(jsonb,boolean)'::regprocedure, array[
  'perform hq_audit(''REVENUE_HISTORICAL_IMPORT''', 'perform hq_command_touch()' || chr(59) || ' perform hq_audit(''REVENUE_HISTORICAL_IMPORT''']);
