-- RPC privilege hardening (7 Oct 2026).
-- Supabase grants EXECUTE on new public functions to anon and authenticated by default. A sweep found SECURITY DEFINER
-- functions with no hq_admin_email() gate that the publishable key could call: ops helpers that change tasks, queue and
-- scorecard reads, and the inner metric functions. HQ calls only the gated hq_* functions, and n8n uses the service role,
-- so nothing legitimate loses access. hq_execution gets its admin gate back (it was dropped in 20261008100000) and now also
-- returns the daily action queue and the growth scorecard.

-- ops helpers (change data)
revoke all on function public.ops_task_set(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.ops_review_downgrade(text, text) from public, anon, authenticated;
revoke all on function public.ops_release_rate_limited() from public, anon, authenticated;
revoke all on function public.ops_chatgpt_email_provenance() from public, anon, authenticated;
revoke all on function public.ops_w19_downgrade_hbs() from public, anon, authenticated;
revoke all on function public.ops_fix_gym_draft() from public, anon, authenticated;

-- reads used by workflows or inside hq_execution only
revoke all on function public.daily_action_queue(int) from public, anon, authenticated;
revoke all on function public.growth_scorecard(timestamptz) from public, anon, authenticated;
revoke all on function public.serper_usage(int) from public, anon, authenticated;
revoke all on function public.revalidation_queue(int) from public, anon, authenticated;
revoke all on function public.creative_concept_queue(int) from public, anon, authenticated;
revoke all on function public.prospect_angle_prefix(uuid) from public, anon, authenticated;
revoke all on function public.relationship_state(uuid) from public, anon, authenticated;
revoke all on function public.company_warm_route(uuid) from public, anon, authenticated;
revoke all on function public.company_reach(uuid) from public, anon, authenticated;
revoke all on function public.agent_performance(int) from public, anon, authenticated;
revoke all on function public.commercial_learning(int) from public, anon, authenticated;
revoke all on function public.commercial_today() from public, anon, authenticated;
revoke all on function public.commercial_weekly_metrics(int) from public, anon, authenticated;
revoke all on function public.growth_cycle_report(timestamptz) from public, anon, authenticated;
revoke all on function public.hunter_roi() from public, anon, authenticated;
revoke all on function public.queue_health() from public, anon, authenticated;

-- trigger functions (cannot be called as RPCs, revoked for hygiene; triggers do not check EXECUTE when they fire)
do $$
declare r record;
begin
  for r in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosecdef and p.prorettype = 'trigger'::regtype
              and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')) loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

create or replace function public.hq_execution()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  return jsonb_build_object('queue', queue_health(), 'weekly', commercial_weekly_metrics(6), 'hunter', hunter_roi(),
    'today', commercial_today(), 'ai_budget', ai_budget_status(), 'engine', engine_metrics(current_date - 30, current_date, null),
    'cycle', growth_cycle_report(now() - interval '3 days') - 'runs', 'agents_week', agent_performance(1),
    'actions', daily_action_queue(20), 'scorecard', growth_scorecard(now() - interval '3 days'));
end $$;
revoke all on function public.hq_execution() from public, anon;
grant execute on function public.hq_execution() to authenticated;
