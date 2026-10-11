-- 11 Oct 2026, after the efficiency pass (no architecture change).
-- 1. Media Director false "missed its schedule": workflow 21 runs daily but logged nothing when it had no target, so HQ showed
--    ERROR. Every run now upserts system_config 'heartbeat_w21' (n8n "Log Run" node; kept out of department_run_metrics, which
--    the Discovery health check reads). agent_last_run('MEDIA') reads it. A genuinely stalled workflow still shows ERROR after
--    max_gap_hours.
-- 2. Hunter credit order (Adam, 11 Oct): Brands, Weddings, Travel, NOYA Private, Hospitality, Corporate; unlisted lanes after.
do $patch$
declare d text; n text; f text;
begin
  d := pg_get_functiondef('public.agent_last_run(text)'::regprocedure);
  n := replace(d, $a$    select max(x) into v_ts from (select max("at") x from ai_usage where workflow = '21' union all select max(created_at) from creative_concepts) s;
    v_basis := 'Last concept work';$a$,
                  $a$    -- every workflow 21 run logs a heartbeat (11 Oct): a run with nothing to process is a run, not a missed schedule
    select max(x) into v_ts from (select max("at") x from ai_usage where workflow = '21' union all select max(created_at) from creative_concepts
                                  union all select (value->>'at')::timestamptz from system_config where key = 'heartbeat_w21') s;
    v_basis := 'Last run (concept work or an empty run)';$a$);
  if n = d then raise exception 'agent_last_run pattern not found'; end if;
  execute n;

  foreach f in array array['public.email_verification_queue(integer)', 'public.email_finder_queue(integer)'] loop
    d := pg_get_functiondef(f::regprocedure);
    n := replace(d, $a$array['BRANDS', 'WEDDINGS', 'TRAVEL', 'SPORTS', 'HOSPITALITY', 'PRIVATE', 'CORPORATE', 'MEDIA', 'EGYPT']$a$,
                    $a$array['BRANDS', 'WEDDINGS', 'TRAVEL', 'SPORTS', 'HOSPITALITY', 'CORPORATE', 'PRIVATE', 'MEDIA', 'EGYPT']$a$);
    if n = d then raise exception 'order pattern not found in %', f; end if;
    execute n;
  end loop;
end $patch$;
