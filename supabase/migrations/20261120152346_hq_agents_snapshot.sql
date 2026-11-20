-- 20 Nov production fix: hq_agents takes ~23 s, longer than the 8 s request limit for signed-in users, so the Agents screen
-- always failed live. It is now served from the background snapshot cache like the other heavy CEO reads.
create or replace function public.hq_cache_key_ok(p_key text)
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select p_key in ('ceo', 'network', 'advisor', 'directors', 'execution', 'command', 'health', 'integrity', 'agents')
      or (p_key like 'director:%' and exists (select 1 from agent_registry r where r.key = substr(p_key, 10) and r.v3_role is not null));
$function$;

create or replace function public.hq_cache_build(p_key text)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v jsonb; t0 timestamptz := clock_timestamp(); v_claims text;
begin
  if not hq_cache_key_ok(p_key) then raise exception 'unknown HQ cache key %', p_key; end if;
  if not pg_try_advisory_xact_lock(hashtext('hq_cache:' || p_key)) then return null; end if;
  select json_build_object('sub', a.user_id, 'email', a.email, 'role', 'authenticated')::text into v_claims
    from hq_admins a order by a.email limit 1;
  perform set_config('request.jwt.claims', v_claims, true);
  begin
    v := case p_key
      when 'ceo' then hq_ceo_dashboard()
      when 'network' then hq_network()
      when 'advisor' then hq_advisor()
      when 'directors' then hq_directors() - 'email_desk' - 'email_gaps' - 'radar' - 'email_report'
      when 'execution' then hq_execution()
      when 'command' then hq_command()
      when 'health' then hq_health()
      when 'integrity' then integrity_check(false)
      when 'agents' then hq_agents()
      else hq_director(substr(p_key, 10)) end;
    insert into hq_read_cache (key, payload, built_at, build_ms)
    values (p_key, v, clock_timestamp(), (extract(epoch from clock_timestamp() - t0) * 1000)::int)
    on conflict (key) do update set payload = excluded.payload, built_at = excluded.built_at, build_ms = excluded.build_ms;
    return v;
  exception when others then
    insert into hq_read_cache (key, last_error, last_error_at) values (p_key, left(sqlerrm, 500), clock_timestamp())
    on conflict (key) do update set last_error = excluded.last_error, last_error_at = excluded.last_error_at;
    return null;
  end;
end $function$;

select cron.schedule('hq-cache-agents', '7-59/10 * * * *', $$select public.hq_cache_build('agents')$$)
where not exists (select 1 from cron.job where jobname = 'hq-cache-agents');
