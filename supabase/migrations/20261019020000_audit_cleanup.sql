-- System audit and safe cleanup (professional operating mode, 19 Oct 2026). Applied live in two parts:
-- run_log_discovery_only and helper_functions_fixed_search_path. Nothing is deleted.
--
-- Data steps taken the same day (one-off, recorded here rather than replayed):
--   select ops_email_intel_test_finish('EF-COHORT-1008')
--       closed the 8 Oct email cohort test: 60 "after" snapshots written next to the "before" ones, and the
--       email_intel_test tag cleared, so workflow 23 no longer prefers that old test set over the live,
--       work-order-ranked gap queue (it held 0 open items, so nothing changed in practice).
--   update system_services set used_by = ... where service in ('Hunter', 'n8n Cloud')
--       Hunter is used by 24 and 25 (05 is paused); n8n runs workflows 00-25.

-- 1. Run log: only n8n department runs count as discovery runs. The integrity check logged one row to
--    department_run_metrics on 18 Oct before that insert was removed; that row stays (evidence) but no longer
--    makes Research Intelligence look as if it ran at 23:55 (Agents page, Operations discovery signal,
--    the Research run list and System health). Real department runs are named "NN - ...".
do $do$
declare
  v_fn regprocedure;
  v_src text;
  i int;
  j jsonb;
  v_jobs jsonb := jsonb_build_array(
    jsonb_build_object('fn', 'director_last_run(text)', 'pairs', jsonb_build_array(
      'select max(recorded_at) x from department_run_metrics union all',
      'select max(recorded_at) x from department_run_metrics where workflow_name ~ ''^[0-9]'' union all')),
    jsonb_build_object('fn', 'hq_overview()', 'pairs', jsonb_build_array(
      '''last'', (select max(recorded_at) from department_run_metrics),',
      '''last'', (select max(recorded_at) from department_run_metrics where workflow_name ~ ''^[0-9]''),',
      '(select max(recorded_at) > now() - interval ''30 hours'' from department_run_metrics)',
      '(select max(recorded_at) > now() - interval ''30 hours'' from department_run_metrics where workflow_name ~ ''^[0-9]'')')),
    jsonb_build_object('fn', 'hq_health()', 'pairs', jsonb_build_array(
      'max(recorded_at) last from department_run_metrics group by 1',
      'max(recorded_at) last from department_run_metrics where workflow_name ~ ''^[0-9]'' group by 1')),
    jsonb_build_object('fn', 'support_detail(text)', 'pairs', jsonb_build_array(
      '(select count(*) from department_run_metrics where recorded_at > now() - interval ''7 days'')',
      '(select count(*) from department_run_metrics where recorded_at > now() - interval ''7 days'' and workflow_name ~ ''^[0-9]'')',
      'from department_run_metrics r where r.recorded_at > now() - interval ''7 days'')',
      'from department_run_metrics r where r.recorded_at > now() - interval ''7 days'' and r.workflow_name ~ ''^[0-9]'')'))
  );
begin
  for j in select * from jsonb_array_elements(v_jobs) loop
    v_fn := (j->>'fn')::regprocedure;
    v_src := pg_get_functiondef(v_fn);
    for i in 0 .. jsonb_array_length(j->'pairs') / 2 - 1 loop
      if (length(v_src) - length(replace(v_src, j->'pairs'->>(2*i), ''))) / length(j->'pairs'->>(2*i)) <> 1 then
        raise exception 'anchor % in % does not match exactly once', i, v_fn;
      end if;
      v_src := replace(v_src, j->'pairs'->>(2*i), j->'pairs'->>(2*i+1));
    end loop;
    execute v_src;
  end loop;
end $do$;

-- 2. Security advisor: 49 helper functions had no fixed search_path (lint 0011). All are invoker-rights
--    text/rule helpers or triggers; none is SECURITY DEFINER. Pinned to the search path they already ran
--    with, so behaviour is unchanged. Measured cost: background snapshots about 7-8% slower (directors
--    18.0 s to 19.3 s, advisor 8.1 s to 8.8 s), because SQL helpers with a SET clause are no longer inlined.
do $do$
declare r record;
begin
  for r in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prokind = 'f'
              and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))
  loop
    execute format('alter function %s set search_path = public, extensions', r.fn);
  end loop;
end $do$;
