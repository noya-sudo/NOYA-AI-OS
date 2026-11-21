-- HQ V4 read-only database checks (21 Nov 2026). Run as one statement (Supabase SQL editor or MCP execute_sql).
-- Returns one row per check with ok = true/false and the observed value. Changes nothing.
with
streams as (select count(*) n, count(distinct pillar) pillars, min(c) min_per_pillar, max(c) max_per_pillar
              from (select pillar, count(*) over (partition by pillar) c from commercial_streams where active) x),
opp as (select count(*) filter (where status not in ('ARCHIVED','LOST')) live,
               count(*) filter (where status not in ('ARCHIVED','LOST') and primary_stream is null) no_stream,
               count(*) filter (where status not in ('ARCHIVED','LOST') and primary_stream = 'UNCLASSIFIED') unclassified,
               count(*) filter (where primary_stream is not null and primary_stream not in (select code from commercial_streams)) orphan_stream
          from opportunities),
routes as (select count(*) rows_, count(*) filter (where is_primary) primary_rows,
                  (select count(*) from (select company_id from hq_route_cache where is_primary and company_id is not null group by company_id having count(*) > 1) d) dup_primary,
                  count(*) filter (where canonical not in ('VALID_VERIFIED','PUBLIC_NAMED_EMAIL','PUBLIC_BUSINESS_EMAIL_INSTAGRAM','PUBLIC_PROFESSIONAL_EMAIL','MANAGEMENT_EMAIL','AGENT_EMAIL',
                                                          'CLAY_WORK_EMAIL','OFFICIAL_PUBLISHED_INBOX','ACCEPT_ALL_RISKY','PUBLIC_UNVERIFIED','UNKNOWN','INVALID','NOT_FOUND')) bad_canonical,
                  max(computed_at) computed_at
             from hq_route_cache),
fns as (select p.proname, has_function_privilege('anon', p.oid, 'execute') anon_x, has_function_privilege('authenticated', p.oid, 'execute') auth_x
          from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('hq_today','hq_opportunities','hq_streams','hq_email_summary','hq_email_routes','hq_ceo_action','hq_route_cache_refresh','opportunity_apply_taxonomy','opportunity_taxonomy')),
rls as (select c.relname, c.relrowsecurity from pg_class c where c.relnamespace = 'public'::regnamespace
          and c.relname in ('commercial_streams','commercial_services','hq_route_cache','ceo_actions','seasonal_windows','hq_read_cache')),
sent_bounce as (select count(*) filter (where o.status = 'READY' and exists (select 1 from interactions i where i.opportunity_id = o.id and i.direction = 'OUTBOUND'
                                          and i.channel = 'EMAIL' and i.occurred_at > now() - interval '30 days')) ready_but_emailed
                  from opportunities o),
checks(name, ok, observed) as (
  select '36 active streams across 4 pillars, none empty', s.n = 36 and s.pillars = 4 and s.min_per_pillar >= 1, jsonb_build_object('streams', s.n, 'pillars', s.pillars, 'min_per_pillar', s.min_per_pillar, 'max_per_pillar', s.max_per_pillar) from streams s
  union all select 'Every live opportunity has a canonical stream', o.no_stream = 0, jsonb_build_object('live', o.live, 'no_stream', o.no_stream, 'unclassified', o.unclassified) from opp o
  union all select 'No opportunity points at an unknown stream', o.orphan_stream = 0, jsonb_build_object('orphans', o.orphan_stream) from opp o
  union all select 'One primary route per company', r.dup_primary = 0, jsonb_build_object('companies_with_2plus', r.dup_primary, 'primary_rows', r.primary_rows) from routes r
  union all select 'Every route has a canonical state', r.bad_canonical = 0, jsonb_build_object('bad', r.bad_canonical) from routes r
  union all select 'Route cache refreshed within 30 minutes', r.computed_at > now() - interval '30 minutes', jsonb_build_object('computed_at', r.computed_at) from routes r
  union all select 'Anon cannot execute any HQ read or write', not bool_or(f.anon_x), jsonb_object_agg(f.proname, f.anon_x) from fns f
  union all select 'Authenticated can run the five reads and hq_ceo_action only', bool_and(case when f.proname in ('hq_route_cache_refresh','opportunity_apply_taxonomy','opportunity_taxonomy') then not f.auth_x else f.auth_x end),
                   jsonb_object_agg(f.proname, f.auth_x) from fns f
  union all select 'RLS on every new table', bool_and(r.relrowsecurity), jsonb_object_agg(r.relname, r.relrowsecurity) from rls r
  union all select 'No opportunity left READY after an email went out (30 days)', b.ready_but_emailed = 0, jsonb_build_object('ready_but_emailed', b.ready_but_emailed) from sent_bounce b
)
select name, ok, observed from checks;
