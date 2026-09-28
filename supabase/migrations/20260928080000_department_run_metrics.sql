-- Usage and funnel counts per department run (cost observability + discovery diagnostics).
-- Append-only, one row per n8n execution, written by a fail-safe final node in each
-- discovery department. Counts only: no money is estimated here (cost_ledger stays
-- the place for real spend). Needed because the counts otherwise live only inside
-- n8n execution data and are lost from reporting.

create table if not exists public.department_run_metrics (
  id uuid primary key default gen_random_uuid(),
  workflow_id text not null,
  workflow_name text,
  run_id text not null,
  recorded_at timestamptz not null default now(),
  metrics jsonb not null default '{}'::jsonb,
  unique (workflow_id, run_id)
);

alter table public.department_run_metrics enable row level security;
revoke all on public.department_run_metrics from anon, authenticated;

-- Daily yield view: qualification yield per department from the stored counts.
create or replace view public.discovery_yield_daily
with (security_invoker = true) as
select
  (recorded_at at time zone 'Africa/Cairo')::date as run_date,
  workflow_name,
  count(*) as runs,
  sum(coalesce((metrics->>'candidates_found')::int, 0)) as candidates_found,
  sum(coalesce((metrics->>'known_skipped')::int, 0)) as known_companies_skipped,
  sum(coalesce((metrics->>'deep_researched')::int, 0)) as deep_researched,
  sum(coalesce((metrics->>'wrong_entity_type')::int, 0)) as wrong_entity_type,
  sum(coalesce((metrics->>'failed_noya_fit')::int, 0)) as failed_noya_fit,
  sum(coalesce((metrics->>'failed_signal')::int, 0)) as failed_signal,
  sum(coalesce((metrics->>'qualified')::int, 0)) as qualified,
  sum(coalesce((metrics->>'serper_searches')::int, 0)) as serper_searches,
  sum(coalesce((metrics->>'firecrawl_calls')::int, 0)) as firecrawl_calls,
  case when sum(coalesce((metrics->>'deep_researched')::int, 0)) > 0
       then round(sum(coalesce((metrics->>'qualified')::int, 0))::numeric / sum(coalesce((metrics->>'deep_researched')::int, 0)), 2)
  end as qualification_yield
from public.department_run_metrics
group by 1, 2;

revoke all on public.discovery_yield_daily from anon, authenticated;
