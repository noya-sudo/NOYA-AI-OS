-- HQ V4 read-only database checks (21 Nov 2026; acceptance pass added seasonal, tool scout, partnerships, merge and cold-hold checks).
-- Run as one statement (Supabase SQL editor or MCP execute_sql).
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
          and c.relname in ('commercial_streams','commercial_services','hq_route_cache','ceo_actions','seasonal_windows','hq_read_cache','tool_scout','partnership_agreements','company_merges')),
sent_bounce as (select count(*) filter (where o.status = 'READY' and exists (select 1 from interactions i where i.opportunity_id = o.id and i.direction = 'OUTBOUND'
                                          and i.channel = 'EMAIL' and i.occurred_at > now() - interval '30 days')) ready_but_emailed
                  from opportunities o),
seas as (select count(*) filter (where starts_on is not null and (source_url is null or last_verified_at is null)) unsourced,
                count(*) filter (where starts_on is not null) dated,
                exists (select 1 from pg_constraint where conname = 'seasonal_windows_source_required') has_rule from seasonal_windows),
scout as (select count(*) filter (where coalesce(array_length(evidence_urls, 1), 0) = 0) no_evidence,
                 count(*) filter (where price_model is not null and (price_source_url is null or price_verified_at is null)) unsourced_price,
                 (select count(*) from pg_constraint where conname in ('tool_scout_evidence','tool_scout_price_sourced','tool_scout_decision_recorded')) rules from tool_scout),
pa as (select count(*) filter (where exclusivity = 'EXCLUSIVE' and exclusivity_approved_at is null) unapproved_exclusive,
              count(*) filter (where status = 'SIGNED' and (signed_at is null or signed_note is null)) unrecorded_signed,
              count(*) filter (where status in ('TERM_SHEET_PREPARED','LEGAL_REVIEW','SENT','SIGNED') and term_sheet is null) missing_sheet,
              (select count(*) from pg_constraint where conname in ('pa_exclusivity_needs_adam','pa_signed_recorded','pa_term_sheet_present')) rules from partnership_agreements),
mrg as (select count(*) merges,
               (select count(*) from contacts c join company_merges m on m.dup_id = c.company_id) + (select count(*) from opportunities o join company_merges m on m.dup_id = o.company_id)
                 + (select count(*) from interactions i join company_merges m on m.dup_id = i.company_id) + (select count(*) from tasks t join company_merges m on m.dup_id = t.company_id)
                 + (select count(*) from gmail_history_threads g join company_merges m on m.dup_id = g.company_id) refs_on_dups,
               (select count(*) from company_merges m join companies c on c.id = m.dup_id and c.merged_into = m.keep_id) dups_retained,
               (select count(*) from approval_audit where action = 'COMPANY_MERGE') audited from company_merges),
hold as (select coalesce((select value->'last_live_check'->>'gate' from system_config where key = 'email_authentication'), 'UNKNOWN') gate,
                (select count(*) from opportunities o where o.status in ('CONTACTED','FOLLOW_UP') and o.next_action_due is not null
                   and exists (select 1 from approval_audit a where a.opportunity_id = o.id and a.action = 'COLD_FOLLOW_UP_HOLD')) held_with_date),
fns2 as (select p.proname, has_function_privilege('anon', p.oid, 'execute') anon_x, has_function_privilege('authenticated', p.oid, 'execute') auth_x
           from pg_proc p where p.pronamespace = 'public'::regnamespace
            and p.proname in ('hq_seasons','hq_tool_scout','hq_tool_scout_decide','hq_partnerships','hq_prepare_term_sheet','hq_partnership_status','company_merge')),
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
  union all select 'Seasonal: no source = no date (rule present, no unsourced dated window)', x.has_rule and x.unsourced = 0, jsonb_build_object('dated', x.dated, 'unsourced', x.unsourced) from seas x
  union all select 'Tool scout: every recommendation has evidence; any price is sourced (3 rules)', x.rules = 3 and x.no_evidence = 0 and x.unsourced_price = 0, jsonb_build_object('rules', x.rules) from scout x
  union all select 'Partnerships: exclusivity needs Adam, signed needs a record, term sheet before review (3 rules)', x.rules = 3 and x.unapproved_exclusive = 0 and x.unrecorded_signed = 0 and x.missing_sheet = 0, jsonb_build_object('rules', x.rules) from pa x
  union all select 'Merge: history retained (no references left on merged duplicates; duplicates kept; every merge audited)', x.refs_on_dups = 0 and x.dups_retained = x.merges and x.audited >= x.merges, jsonb_build_object('merges', x.merges, 'refs_on_dups', x.refs_on_dups) from mrg x
  union all select 'Cold follow-up hold: no held cohort opportunity carries a follow-up date while the gate is closed', x.gate = 'PASS' or x.held_with_date = 0, jsonb_build_object('gate', x.gate, 'held_with_date', x.held_with_date) from hold x
  union all select 'New functions: anon none; company_merge internal only', not bool_or(f.anon_x) and bool_and(case when f.proname = 'company_merge' then not f.auth_x else f.auth_x end), jsonb_object_agg(f.proname, f.auth_x) from fns2 f
)
select name, ok, observed from checks;
