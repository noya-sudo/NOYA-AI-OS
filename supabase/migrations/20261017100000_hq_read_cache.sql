-- NOYA HQ production fix (17 Oct 2026): the Agents page (and, under load, every HQ screen) failed with
-- "canceling statement due to statement timeout".
--
-- Cause, from pg_stat_statements (mean of the calls that finished; the timed-out ones are not even counted):
--   hq_ceo_dashboard 7.1 s · hq_advisor 6.9 s · hq_director 5.9 s · hq_directors 4.1 s · hq_outreach_desk 3.7 s · hq_network 3.5 s
-- against an 8 s statement_timeout for the authenticated role. HQ fired ~14 of these reads in parallel on every page load,
-- again every 60 s, again after every button press, and every 5 s for two minutes after an approval. On a small database
-- the parallel reads compete for CPU and all cross 8 s together. directors_snapshot, director_detail, hq_advisor and
-- director_channel_health each re-run outreach_desk(), so one Agents load computed the desk three or four times.
--
-- Fix (no architecture change): the heavy CEO reads are computed in the background by pg_cron and served from a snapshot
-- table, so a page load reads stored JSON in milliseconds. The live functions are unchanged and remain the source of truth;
-- the desk (hq_outreach_desk) stays live because approvals must show at once. The client loads in waves and polls lightly.

create table if not exists public.hq_read_cache (
  key text primary key,
  payload jsonb,
  built_at timestamptz,
  build_ms int,
  last_error text,
  last_error_at timestamptz
);
alter table public.hq_read_cache enable row level security;
revoke all on table public.hq_read_cache from public, anon, authenticated;
comment on table public.hq_read_cache is 'Background snapshots of the heavy HQ reads (hq_cache_build). Read only through hq_cached(); no client access.';

-- Which keys exist: the five CEO reads plus one per Director / specialist page.
create or replace function public.hq_cache_key_ok(p_key text)
returns boolean language sql stable security definer set search_path = public as $$
  select p_key in ('ceo', 'network', 'advisor', 'directors', 'execution')
      or (p_key like 'director:%' and exists (select 1 from agent_registry r where r.key = substr(p_key, 10) and r.v3_role is not null));
$$;
revoke all on function public.hq_cache_key_ok(text) from public, anon, authenticated;

-- Build one snapshot. Runs the existing admin-gated read as the HQ admin (the same claims a browser session carries),
-- stores the result and how long it took. A failure keeps the previous snapshot and records the error for diagnostics.
create or replace function public.hq_cache_build(p_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb; t0 timestamptz := clock_timestamp(); v_claims text;
begin
  if not hq_cache_key_ok(p_key) then raise exception 'unknown HQ cache key %', p_key; end if;
  if not pg_try_advisory_xact_lock(hashtext('hq_cache:' || p_key)) then return null; end if;  -- already building
  select json_build_object('sub', a.user_id, 'email', a.email, 'role', 'authenticated')::text into v_claims
    from hq_admins a order by a.email limit 1;
  perform set_config('request.jwt.claims', v_claims, true);
  begin
    v := case p_key
      when 'ceo' then hq_ceo_dashboard()
      when 'network' then hq_network()
      when 'advisor' then hq_advisor()
      when 'directors' then hq_directors() - 'email_desk' - 'email_gaps' - 'radar' - 'email_report'  -- 665 KB the Agents page never shows (the classic view reads hq_agents)
      when 'execution' then hq_execution()
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
end $$;
revoke all on function public.hq_cache_build(text) from public, anon, authenticated;

-- Background refresh. 'core' every 5 minutes (Dashboard, Agents, Relationships, Advisor); 'directors' refreshes the three
-- oldest Director pages each run, so every page is at most ~30 minutes old without one long burst.
create or replace function public.hq_cache_refresh(p_group text)
returns int language plpgsql security definer set search_path = public as $$
declare k text; n int := 0;
begin
  if p_group = 'core' then
    foreach k in array array['directors', 'ceo', 'advisor', 'network', 'execution'] loop
      if hq_cache_build(k) is not null then n := n + 1; end if;
    end loop;
  elsif p_group = 'directors' then
    for k in select 'director:' || r.key from agent_registry r left join hq_read_cache c on c.key = 'director:' || r.key
              where r.v3_role is not null order by c.built_at nulls first, r.sort limit 3 loop
      if hq_cache_build(k) is not null then n := n + 1; end if;
    end loop;
  else
    raise exception 'unknown HQ cache group %', p_group;
  end if;
  return n;
end $$;
revoke all on function public.hq_cache_refresh(text) from public, anon, authenticated;

-- The browser read: admin-gated, returns the stored snapshot with its age. A key that has never been built is
-- built once on the spot (the background job builds everything within five minutes of deployment).
create or replace function public.hq_cached(p_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); c hq_read_cache%rowtype; v jsonb;
begin
  if not hq_cache_key_ok(p_key) then return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_KEY'); end if;
  select * into c from hq_read_cache where key = p_key;
  if c.payload is null then
    v := hq_cache_build(p_key);
    if v is null then return jsonb_build_object('ok', false, 'reason', 'NOT_READY'); end if;
    return v || jsonb_build_object('_cache', jsonb_build_object('built_at', now(), 'age_s', 0));
  end if;
  return c.payload || jsonb_build_object('_cache', jsonb_build_object('built_at', c.built_at, 'age_s', extract(epoch from now() - c.built_at)::int));
end $$;
revoke all on function public.hq_cached(text) from public, anon;
grant execute on function public.hq_cached(text) to authenticated;

-- Admin diagnostics (More / Admin → System): snapshot ages, build times and the last error, raw. Never on CEO screens.
create or replace function public.hq_cache_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  return jsonb_build_object('generated_at', now(),
    'items', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'built_at', built_at, 'age_s', extract(epoch from now() - built_at)::int,
                         'build_ms', build_ms, 'last_error', last_error, 'last_error_at', last_error_at) order by key) from hq_read_cache), '[]'::jsonb),
    'jobs', coalesce((select jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'active', j.active,
                         'last_status', (select d.status from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1),
                         'last_run', (select d.start_time from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1)))
                      from cron.job j where j.jobname like 'hq-cache-%'), '[]'::jsonb));
end $$;
revoke all on function public.hq_cache_status() from public, anon;
grant execute on function public.hq_cache_status() to authenticated;

-- Schedules (idempotent).
do $s$
begin
  perform cron.unschedule(jobid) from cron.job where jobname in ('hq-cache-core', 'hq-cache-directors');
  perform cron.schedule('hq-cache-core', '*/5 * * * *', $c$select public.hq_cache_refresh('core')$c$);
  perform cron.schedule('hq-cache-directors', '2-59/5 * * * *', $c$select public.hq_cache_refresh('directors')$c$);
end $s$;
