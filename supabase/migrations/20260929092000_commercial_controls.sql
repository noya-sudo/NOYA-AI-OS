-- Commercial controls: one central config row set, the conversion backlog, and the
-- context every discovery department reads before spending research calls.
--
-- system_config holds operating thresholds (discovery throttle, AI budget, model
-- routing) so they change in one place instead of in eleven workflows.
-- discovery_context() is what 02/03/04/06 call right before "Merge & Cap":
--   * known_domains: registrable domains already in the CRM, so a re-discovered
--     company (or a subdomain of one) never takes a paid research slot;
--   * backlog + research_cap: when Adam already has too much to convert, broad
--     discovery slows down or pauses. Conversion first.

create table if not exists public.system_config (
  key text primary key,
  value jsonb not null,
  note text,
  updated_at timestamptz not null default now()
);
alter table public.system_config enable row level security;
revoke all on public.system_config from anon, authenticated;

insert into public.system_config (key, value, note) values
  ('discovery_throttle',
   '{"normal_research_cap": 4, "reduced_research_cap": 2, "paused_research_cap": 0, "reduce_at_backlog": 30, "pause_at_backlog": 50}',
   'Backlog = open outreach approvals + open contact research/resolution + open follow-ups + overdue tasks.'),
  ('ai_budget',
   '{"monthly_budget_usd": 30, "premium_share_limit": 0.10, "log_at": 0.5, "warn_at": 0.75, "restrict_premium_at": 0.9, "cheap_only_at": 1.0}',
   'PROPOSED default budget (not confirmed by Adam). Budget guardrails. Premium model use is restricted first; CRM, Gmail sync and tasks never stop on budget.'),
  ('ai_model_routing',
   '{"primary": "models/gemini-3.1-flash-lite", "backup": "gpt-5-mini", "drafting": "gpt-5-mini", "premium": "claude-sonnet-4-6", "provider_path": "n8n AI gateway credits for Gemini/OpenAI; Anthropic account key for premium only"}',
   'Tier 0 deterministic SQL/JS first; Tier 1 low-cost model; Tier 2 premium only on escalation.')
on conflict (key) do nothing;

create or replace view public.commercial_backlog
with (security_invoker = true) as
select
  count(*) filter (where task_type = 'SALES_OUTREACH_APPROVAL' and status = 'OPEN') as approval_ready,
  count(*) filter (where task_type in ('CONTACT_RESEARCH', 'CONTACT_RESOLUTION') and status = 'OPEN') as contact_blocked,
  count(*) filter (where task_type = 'OUTREACH_FOLLOW_UP' and status = 'OPEN') as follow_ups_open,
  count(*) filter (where status = 'OPEN' and due_at < now()
                   and task_type not in ('PROVIDER_HEALTH_ALERT', 'SYSTEM_ALERT', 'SYSTEM_FAILURE_ALERT')) as overdue
from public.tasks;
revoke all on public.commercial_backlog from anon, authenticated;

create or replace function public.discovery_context()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with b as (select * from commercial_backlog),
  cfg as (select value v from system_config where key = 'discovery_throttle'),
  tot as (select (approval_ready + contact_blocked + follow_ups_open + overdue) as n from b),
  dom as (
    select array_agg(distinct d) as ds from (
      select registrable_domain(website) d from companies where website is not null
      union
      select registrable_domain(split_part(email, '@', 2)) from contacts where email like '%@%'
    ) x where d is not null
  )
  select jsonb_build_object(
    'known_domains', coalesce((select to_jsonb(ds) from dom), '[]'::jsonb),
    'backlog', (select to_jsonb(b) from b) || jsonb_build_object('total', (select n from tot)),
    'throttle_level', case
        when (select n from tot) >= ((select v from cfg)->>'pause_at_backlog')::int then 'PAUSED'
        when (select n from tot) >= ((select v from cfg)->>'reduce_at_backlog')::int then 'REDUCED'
        else 'NORMAL' end,
    'research_cap', case
        when (select n from tot) >= ((select v from cfg)->>'pause_at_backlog')::int then ((select v from cfg)->>'paused_research_cap')::int
        when (select n from tot) >= ((select v from cfg)->>'reduce_at_backlog')::int then ((select v from cfg)->>'reduced_research_cap')::int
        else ((select v from cfg)->>'normal_research_cap')::int end,
    'generated_at', now()
  );
$$;
revoke all on function public.discovery_context() from public, anon, authenticated;
grant execute on function public.discovery_context() to service_role;
