-- 9 Nov 2026: production defect fix.
-- The twice-daily Gmail history ingest (n8n "Ingest To CRM" -> gmail_history_ingest -> gmail_history_apply_outreach)
-- failed on 8 Nov 19:10 and 9 Nov 07:10 Cairo: it tried to open an OUTREACH_FOLLOW_UP task for an opportunity
-- that already had an open follow-up created by another path (follow_up_second_step), which violates
-- tasks_one_open_outreach_follow_up and aborted the whole batch, so Adam's sends were not recorded.
-- Fix: the insert skips quietly when an open follow-up already exists, and the task count reflects real inserts.
-- Idempotent patch of the live function (same pattern as earlier patches).
do $patch$
declare
  v_def text;
  v_old text := E'        ((current_date + 1)::timestamp + time ''09:00'') at time zone ''Africa/Cairo'');\n      v_tasks := v_tasks + 1;';
  v_new text := E'        ((current_date + 1)::timestamp + time ''09:00'') at time zone ''Africa/Cairo'')\n      on conflict do nothing;  -- 9 Nov: another open follow-up for this opportunity must not abort the whole Gmail ingest\n      get diagnostics v_n = row_count;\n      v_tasks := v_tasks + v_n;';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'gmail_history_apply_outreach';
  if strpos(v_def, v_old) = 0 then
    if strpos(v_def, 'abort the whole Gmail ingest') > 0 then return; end if;
    raise exception 'anchor not found in gmail_history_apply_outreach';
  end if;
  execute replace(v_def, v_old, v_new);
end
$patch$;
