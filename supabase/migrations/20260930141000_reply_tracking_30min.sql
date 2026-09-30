-- Reply tracking (workflow 13) now runs every 30 minutes instead of 15 (Adam, 30 Sep 2026).
-- Safe: its Gmail search starts from a fixed go-live date and each message is handled once by its
-- Gmail id, so a longer interval delays a reply by at most ~15 extra minutes and misses nothing.
-- The health signal allows one missed run before turning red (75 minutes).

do $$
declare d text;
begin
  d := pg_get_functiondef('public.hq_overview()'::regprocedure);
  d := replace(d, $x$last_run_at > now() - interval '45 minutes' from gmail_sync_state$x$, $x$last_run_at > now() - interval '75 minutes' from gmail_sync_state$x$);
  d := replace(d, $x$'runs every 15 min; stale after 45 min'$x$, $x$'runs every 30 min; stale after 75 min'$x$);
  if d not like '%stale after 75 min%' then raise exception 'hq_overview patch failed'; end if;
  execute d;
end $$;

-- Cost register: Adam's decisions of 30 Sep 2026. No plan changes, no new paid tools.
update public.system_services set
  scale_risk = 'Plan is usually priced by executions. Reply tracking now ~1,440 runs a month (every 30 min); history sync ~180; drafting ~60 plus requests; discovery and briefs on top.',
  downgrade_note = 'Done 30 Sep 2026: reply tracking moved from every 15 to every 30 minutes (~1,440 fewer runs a month). Do not change or upgrade the plan until the real allowance and cost are known (Adam to send Settings → Usage and plan).',
  updated_at = now()
where service = 'n8n Cloud';

update public.system_services set
  downgrade_note = 'Do not increase search volume until the plan and monthly allowance are confirmed (Adam to confirm the account email). Lower the throttle if replies do not justify it.',
  updated_at = now()
where service = 'Serper';

insert into public.system_services (service, purpose, used_by, owner, current_plan, cost_type, monthly_cost, currency, usage_cost, usage_limit,
  breaks_if_removed, alternative, credentials_location, verified, verification_note, status, scale_risk, downgrade_note)
select 'Google Cloud (noya@)', 'Adam''s own Google Cloud account; no NOYA workflow uses it', 'None', 'Adam',
  'Free trial (started 26 Sep 2026)', 'USAGE_LIMITED', 0, null, null, 'Free-trial credit',
  'Nothing — no NOYA workflow depends on it', 'n/a', 'Google Cloud console (Adam)', true,
  'Google email to noya@, 26 Sep 2026: "Welcome to your Google Cloud Free Trial". Confirmed as Adam''s on 30 Sep 2026.',
  'ACTIVE', 'None today. Do not add any dependency on it without a clear reason and Adam''s approval.', 'Leave as is.'
where not exists (select 1 from public.system_services where service = 'Google Cloud (noya@)');

insert into approval_audit (action, result, actor, detail)
values ('REPLY_TRACKING_CADENCE', 'OK', 'system (Adam''s decision, 30 Sep 2026)',
        jsonb_build_object('workflow', '13', 'from_minutes', 15, 'to_minutes', 30, 'health_stale_after_minutes', 75,
                           'manual_run', 'n8n → workflow 13 → Manual Sync (unchanged)'));
