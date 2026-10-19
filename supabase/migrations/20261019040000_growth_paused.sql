-- Growth Director paused (Adam, 19 Oct 2026: "Pause it until marketing reporting becomes commercially
-- relevant. No Windsor upgrade."). Workflows 10a, 10b and 10c were unpublished in n8n the same day; 10d
-- (website enquiry intake) stays live. A paused agent is shown as Paused, never as late or in error.
alter table agent_registry add column if not exists paused_reason text;

update agent_registry
   set paused_reason = 'Paused by Adam on 19 Oct until marketing reporting becomes commercially relevant. Workflows 10a, 10b and 10c are switched off in n8n. Website enquiries (10d) still run.'
 where key = 'GROWTH';

do $do$
declare
  v_src text;
  i int;
  v_pairs text[];
begin
  v_src := pg_get_functiondef('directors_snapshot()'::regprocedure);
  v_pairs := array[
    $a$case when exists (select 1 from jsonb_array_elements(b.list) x where jsonb_typeof(x) = 'object' and (x->>'hard')::boolean) then 'BLOCKED'$a$,
    $a$case when exists (select 1 from agent_registry ar where ar.key = d.key and ar.paused_reason is not null) then 'PAUSED'
           when exists (select 1 from jsonb_array_elements(b.list) x where jsonb_typeof(x) = 'object' and (x->>'hard')::boolean) then 'BLOCKED'$a$,
    $a$'next_focus', coalesce(d.current_work, d.focus)$a$,
    $a$'next_focus', coalesce((select ar.paused_reason from agent_registry ar where ar.key = d.key), d.current_work, d.focus)$a$,
    $a$when 'BLOCKED' then 'Blocked'$a$,
    $a$when 'PAUSED' then 'Paused'
                                     when 'BLOCKED' then 'Blocked'$a$,
    $a$where status in ('WORKING', 'SCHEDULED'))$a$,
    $a$where status in ('WORKING', 'SCHEDULED', 'PAUSED'))$a$];
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if (length(v_src) - length(replace(v_src, v_pairs[2*i-1], ''))) / length(v_pairs[2*i-1]) <> 1 then
      raise exception 'directors_snapshot anchor % does not match exactly once', i;
    end if;
    v_src := replace(v_src, v_pairs[2*i-1], v_pairs[2*i]);
  end loop;
  execute v_src;

  v_src := pg_get_functiondef('hq_health()'::regprocedure);
  v_pairs := array[
    $a$'on_schedule', lr is not null and lr > now() - make_interval(hours => r.max_gap_hours::int)$a$,
    $a$'paused', r.paused_reason is not null, 'on_schedule', r.paused_reason is not null or (lr is not null and lr > now() - make_interval(hours => r.max_gap_hours::int))$a$];
  if (length(v_src) - length(replace(v_src, v_pairs[1], ''))) / length(v_pairs[1]) <> 1 then
    raise exception 'hq_health anchor does not match exactly once';
  end if;
  execute replace(v_src, v_pairs[1], v_pairs[2]);
end $do$;
