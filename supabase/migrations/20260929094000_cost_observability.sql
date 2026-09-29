-- Cost observability: usage counts per category for TODAY, the last 7 days and a 30-day
-- projection (7-day average x 30). Money is only computed where a unit price has been
-- entered in system_config.unit_costs from a real invoice or plan; otherwise UNKNOWN.
-- Nothing here estimates provider spend that has not been priced.

insert into public.system_config (key, value, note) values
  ('unit_costs',
   '{"serper_per_search_usd": null, "firecrawl_per_call_usd": null, "hunter_per_call_usd": null, "ai_gateway_per_call_usd": null}',
   'Fill from real invoices/plans only. null = UNKNOWN. AI calls run on n8n AI gateway credits (Gemini 3.1 Flash-Lite, GPT-5 mini); the per-call credit price is not exposed to NOYA.')
on conflict (key) do nothing;

create or replace view public.cost_observability
with (security_invoker = true) as
with d as (
  select (recorded_at at time zone 'Africa/Cairo')::date as day,
         coalesce((metrics->>'serper_searches')::numeric, 0) as serper,
         coalesce((metrics->>'firecrawl_calls')::numeric, 0) as firecrawl,
         coalesce((metrics->>'ai_calls_estimated')::numeric, 0) as ai_calls
  from public.department_run_metrics
), w as (
  select 'TODAY' as period,
         sum(serper) filter (where day = (now() at time zone 'Africa/Cairo')::date) as serper_searches,
         sum(firecrawl) filter (where day = (now() at time zone 'Africa/Cairo')::date) as firecrawl_calls,
         sum(ai_calls) filter (where day = (now() at time zone 'Africa/Cairo')::date) as ai_calls_discovery
  from d
  union all
  select '7_DAYS',
         sum(serper) filter (where day > (now() at time zone 'Africa/Cairo')::date - 7),
         sum(firecrawl) filter (where day > (now() at time zone 'Africa/Cairo')::date - 7),
         sum(ai_calls) filter (where day > (now() at time zone 'Africa/Cairo')::date - 7)
  from d
  union all
  select '30_DAY_PROJECTION',
         round(coalesce(sum(serper) filter (where day > (now() at time zone 'Africa/Cairo')::date - 7), 0) / 7 * 30),
         round(coalesce(sum(firecrawl) filter (where day > (now() at time zone 'Africa/Cairo')::date - 7), 0) / 7 * 30),
         round(coalesce(sum(ai_calls) filter (where day > (now() at time zone 'Africa/Cairo')::date - 7), 0) / 7 * 30)
  from d
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
            else round(coalesce(w.ai_calls_discovery, 0) * (select (v->>'ai_gateway_per_call_usd')::numeric from p), 2)::text end as ai_cost_usd,
       'UNKNOWN'::text as contact_data_cost_usd,
       'Counts are ACTUAL from department_run_metrics (discovery 02/03/04/06/08). AI calls in 05, 09, 10a-c, 11 and 13 are not yet counted. Money is UNKNOWN until unit prices are entered from invoices.' as note
from w;

revoke all on public.cost_observability from anon, authenticated;

-- Funnel by vertical and channel (ACTUAL counts only; small samples are not conclusions).
create or replace view public.commercial_funnel
with (security_invoker = true) as
select r.vertical, r.primary_channel,
       count(*) as open_accounts,
       count(*) filter (where r.contact_name is not null) as contacts_resolved,
       count(*) filter (where r.ready_email is not null or r.ready_linkedin is not null or r.ready_instagram is not null) as outreach_ready,
       count(*) filter (where r.last_outbound_at is not null) as outreach_sent,
       count(*) filter (where r.last_inbound_at is not null) as replied,
       count(*) filter (where r.opportunity_status in ('CALL_REQUIRED', 'INTERESTED')) as meetings_or_interest,
       count(*) filter (where r.opportunity_status in ('PROPOSAL', 'NEGOTIATION')) as proposals
from public.outreach_readiness r
group by 1, 2;

revoke all on public.commercial_funnel from anon, authenticated;
