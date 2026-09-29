-- HQ Overview refinements found in the V1 visual check (30 Sep 2026):
--   1. A reply-type task not raised by workflow 13 (e.g. created on Adam's instruction) shows its
--      real creator as the source instead of "Workflow 13".
--   2. Queue ranking within a priority: meetings/replies first, then drafts to send, follow-ups,
--      approvals, LinkedIn, Instagram; then commercial priority; then due date.
--   3. The model architecture comes from system_config.ai_model_routing (data-backed, no UI text).
-- Applied as text substitutions on the function created in 20260930091000 so the two stay in step.
do $$
declare d text;
begin
  d := pg_get_functiondef('public.hq_overview()'::regprocedure);
  d := replace(d, $x$'Workflow 13 (Gmail reply)' as source$x$,
    $x$case when t.id in (select task_id from reply_tasks) then 'Workflow 13 (Gmail reply)' else coalesce(t.created_by, 'Task') end as source$x$);
  d := replace(d, $x$row_number() over (order by a.prio, a.due_at nulls last, a.opp_priority desc nulls last)$x$,
    $x$row_number() over (order by a.prio,
      case a.kind when 'MEETING' then 0 when 'REPLY' then 1 when 'WEBSITE' then 1 when 'PROPOSAL' then 1 when 'PAYMENT' then 1
        when 'SYSTEM' then 2 when 'SEND_DRAFT' then 2 when 'FOLLOW_UP' then 3 when 'APPROVE' then 4 when 'LINKEDIN' then 5
        when 'INSTAGRAM' then 6 else 7 end,
      a.opp_priority desc nulls last, a.due_at nulls last)$x$);
  d := replace(d, $x$'cost_today', (select to_jsonb(c) from cost_observability c where period = 'TODAY'))$x$,
    $x$'models', (select jsonb_build_object('routing', value, 'note', note) from system_config where key = 'ai_model_routing'),
      'cost_today', (select to_jsonb(c) from cost_observability c where period = 'TODAY'))$x$);
  if d not like '%coalesce(t.created_by, ''Task'') end as source%' or d not like '%when ''INSTAGRAM'' then 6%' or d not like '%''models''%' then
    raise exception 'hq_overview refinement did not apply cleanly';
  end if;
  execute d;
end $$;
