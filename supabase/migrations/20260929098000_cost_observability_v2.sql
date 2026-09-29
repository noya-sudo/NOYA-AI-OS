-- Cost observability v2: adds the usage that is now countable from real records.
--   hunter_checks        -- Hunter finder+verifier pairs logged by Workflow 05 (contact_email_verifications)
--   reply_ai_calls       -- Workflow 13 reply classifications (one AI call per inbound reply, gmail_sync_ledger)
--   brief_runs           -- Workflow 11 CEO briefs generated (ceo_reports; one AI call each, or none if degraded)
-- Still not counted: 05 drafting calls, 09 and 10a-c AI calls, Hunter calls inside discovery
-- departments. Money stays UNKNOWN until a unit price from a real invoice is entered in
-- system_config.unit_costs.

create or replace view public.cost_observability
with (security_invoker = true) as
with d as (
  select (recorded_at at time zone 'Africa/Cairo')::date as day,
         coalesce((metrics->>'serper_searches')::numeric, 0) as serper,
         coalesce((metrics->>'firecrawl_calls')::numeric, 0) as firecrawl,
         coalesce((metrics->>'ai_calls_estimated')::numeric, 0) as ai_calls
  from public.department_run_metrics
), x as (
  select (checked_at at time zone 'Africa/Cairo')::date as day, 'HUNTER' as k from public.contact_email_verifications
  union all
  select (received_at at time zone 'Africa/Cairo')::date, 'REPLY_AI' from public.gmail_sync_ledger where kind = 'INBOUND_REPLY'
  union all
  select (generated_at at time zone 'Africa/Cairo')::date, 'BRIEF' from public.ceo_reports where generated_at is not null
), today as (select (now() at time zone 'Africa/Cairo')::date as t), w as (
  select 'TODAY' as period,
         (select sum(serper) from d, today where day = t) as serper_searches,
         (select sum(firecrawl) from d, today where day = t) as firecrawl_calls,
         (select sum(ai_calls) from d, today where day = t) as ai_calls_discovery,
         (select count(*) from x, today where k = 'HUNTER' and day = t) as hunter_checks,
         (select count(*) from x, today where k = 'REPLY_AI' and day = t) as reply_ai_calls,
         (select count(*) from x, today where k = 'BRIEF' and day = t) as brief_runs
  union all
  select '7_DAYS',
         (select sum(serper) from d, today where day > t - 7),
         (select sum(firecrawl) from d, today where day > t - 7),
         (select sum(ai_calls) from d, today where day > t - 7),
         (select count(*) from x, today where k = 'HUNTER' and day > t - 7),
         (select count(*) from x, today where k = 'REPLY_AI' and day > t - 7),
         (select count(*) from x, today where k = 'BRIEF' and day > t - 7)
  union all
  select '30_DAY_PROJECTION',
         round(coalesce((select sum(serper) from d, today where day > t - 7), 0) / 7 * 30),
         round(coalesce((select sum(firecrawl) from d, today where day > t - 7), 0) / 7 * 30),
         round(coalesce((select sum(ai_calls) from d, today where day > t - 7), 0) / 7 * 30),
         round((select count(*) from x, today where k = 'HUNTER' and day > t - 7)::numeric / 7 * 30),
         round((select count(*) from x, today where k = 'REPLY_AI' and day > t - 7)::numeric / 7 * 30),
         round((select count(*) from x, today where k = 'BRIEF' and day > t - 7)::numeric / 7 * 30)
), p as (select value v from public.system_config where key = 'unit_costs')
select w.period,
       coalesce(w.serper_searches, 0) as serper_searches,
       coalesce(w.firecrawl_calls, 0) as firecrawl_calls,
       coalesce(w.ai_calls_discovery, 0) as ai_calls_discovery,
       case when (select v->>'serper_per_search_usd' from p) is null then 'UNKNOWN'
            else round(coalesce(w.serper_searches, 0) * (select (v->>'serper_per_search_usd')::numeric from p), 2)::text end as search_cost_usd,
       case when (select v->>'firecrawl_per_call_usd' from p) is null then 'UNKNOWN'
            else round(coalesce(w.firecrawl_calls, 0) * (select (v->>'firecrawl_per_call_usd')::numeric from p), 2)::text end as research_cost_usd,
       case when (select v->>'ai_gateway_per_call_usd' from p) is null then 'UNKNOWN'
            else round((coalesce(w.ai_calls_discovery, 0) + coalesce(w.reply_ai_calls, 0) + coalesce(w.brief_runs, 0))
                       * (select (v->>'ai_gateway_per_call_usd')::numeric from p), 2)::text end as ai_cost_usd,
       case when (select v->>'hunter_per_call_usd' from p) is null then 'UNKNOWN'
            else round(coalesce(w.hunter_checks, 0) * 2 * (select (v->>'hunter_per_call_usd')::numeric from p), 2)::text end as contact_data_cost_usd,
       'Counts are ACTUAL: discovery from department_run_metrics (02/03/04/06/08); Hunter from contact_email_verifications (05, finder+verifier pairs); reply AI from gmail_sync_ledger (13); briefs from ceo_reports (11). Not yet counted: 05 drafting, 09, 10a-c, Hunter inside discovery. Money is UNKNOWN until unit prices are entered from invoices.' as note,
       coalesce(w.hunter_checks, 0) as hunter_checks,
       coalesce(w.reply_ai_calls, 0) as reply_ai_calls,
       coalesce(w.brief_runs, 0) as brief_runs
from w;

revoke all on public.cost_observability from anon, authenticated;
