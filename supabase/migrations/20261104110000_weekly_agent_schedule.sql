-- 4 Nov 2026 production fix: Media & Culture showed ERROR ("Missed its schedule") although workflow 21 ran on time.
-- Workflow 21 was cut to Mondays 11:30 Cairo on 30 Oct; agent_registry still said daily 11:30, and the schedule helpers
-- only understood daily times. A schedule entry may now carry a weekday prefix ("Mon 11:30"); plain "HH:MM" stays daily.

create or replace function public.agent_prev_run(p_times text[], p_every integer)
 returns timestamp with time zone language sql stable set search_path to 'public', 'extensions'
as $function$
  select case
    when p_every is not null then date_trunc('hour', now()) + make_interval(mins => p_every * floor(extract(minute from now()) / p_every)::int)
    else (select max(ts) from (
            select ((v.d + (case when t ~ '^[A-Za-z]{3} ' then substr(t, 5) else t end)::time) at time zone 'Africa/Cairo') ts
              from unnest(p_times) t, generate_series(0, 7) g,
                   lateral (select (now() at time zone 'Africa/Cairo')::date - g as d) v
             where t !~ '^[A-Za-z]{3} ' or to_char(v.d, 'Dy') = initcap(substr(t, 1, 3))) x
           where ts <= now()) end
$function$;

create or replace function public.agent_next_run(p_times text[], p_every integer)
 returns timestamp with time zone language sql stable set search_path to 'public', 'extensions'
as $function$
  select case
    when p_every is not null then date_trunc('hour', now()) + make_interval(mins => p_every * (floor(extract(minute from now()) / p_every)::int + 1))
    else (select min(ts) from (
            select ((v.d + (case when t ~ '^[A-Za-z]{3} ' then substr(t, 5) else t end)::time) at time zone 'Africa/Cairo') ts
              from unnest(p_times) t, generate_series(0, 7) g,
                   lateral (select (now() at time zone 'Africa/Cairo')::date + g as d) v
             where t !~ '^[A-Za-z]{3} ' or to_char(v.d, 'Dy') = initcap(substr(t, 1, 3))) x
           where ts > now()) end
$function$;

update agent_registry set schedule = array['Mon 11:30'] where key = 'MEDIA' and schedule = array['11:30'];
-- The ERROR status also reads max_gap_hours (26 h for a daily run): a weekly run needs a week plus a margin.
update agent_registry set max_gap_hours = 170 where key = 'MEDIA' and max_gap_hours = 26;
