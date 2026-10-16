-- HQ freeze (Adam, 16 Oct 2026): Hunter stays on Free until the 27 Oct reset test.
-- 1. The decision lives in system_config.hunter_decision; the Advisor reads its wording from there,
--    so the post-reset verdict needs a config change, not a code change.
-- 2. The Advisor no longer recommends a paid upgrade (bottleneck note and the allocate action).
-- 3. Priority lanes follow Adam's order: Brands, Weddings, Travel, NOYA Private, Hospitality, Corporate (then Private Membership).
-- Nothing here changes routing, queues or caps: Free caps stay 8 checks and 2 lookups a day, with the 5-check reserve.

insert into public.system_config (key, value) values ('hunter_decision', jsonb_build_object(
  'decision', 'STAY_FREE_UNTIL_RESET_TEST',
  'decided_by', 'Adam', 'decided_at', '2026-10-16', 'reset_date', '2026-10-27',
  'rule', 'No paid Hunter upgrade is recommended until the 27 Oct reset test shows Free is insufficient. Research, qualification, public email discovery and correct-person research continue; the verification queue builds in priority order; the final reserve is not spent.',
  'priority', jsonb_build_array('BRANDS', 'WEDDINGS', 'TRAVEL', 'SPORTS', 'HOSPITALITY', 'CORPORATE'),
  'bottleneck_note', 'Hunter stays on Free until the 27 Oct reset test, so this queue waits in priority order.',
  'allocate_action', 'Hunter stays on Free until the 27 Oct reset test (Adam, 16 Oct). Keep public email and correct-person research moving; the verification queue is ranked for the reset.',
  'test_plan', jsonb_build_object(
    'when', 'first run after the 27 Oct allowance reset is visible in hunter_account',
    'budget_credits', 45, 'reserve_credits', 5,
    'finder_lookups', 20, 'verifications', 50,
    'order', 'live ranked queues: Brands, Weddings, Travel, NOYA Private, Hospitality, Corporate',
    'report', jsonb_build_array('verification attempts', 'Finder attempts', 'credits consumed', 'VALID', 'RISKY', 'INVALID', 'new EMAIL READY', 'results by Director', 'remaining qualified verification backlog', 'days until credits exhausted at the observed rate', 'IS FREE ENOUGH or IS STARTER ECONOMICALLY JUSTIFIED, with evidence'))))
on conflict (key) do update set value = excluded.value;

update public.system_config set value = jsonb_set(value, '{plan_note}', to_jsonb('Adam, 16 Oct: Hunter stays on Free until the 27 Oct reset test; no paid upgrade is recommended before those numbers are in (see hunter_decision). Caps follow the live plan in hunter_account.'::text))
 where key = 'email_verification';
update public.system_config set value = jsonb_set(value, '{priority_lanes}', '["BRANDS","WEDDINGS","TRAVEL","SPORTS","HOSPITALITY","CORPORATE","PRIVATE"]'::jsonb)
 where key = 'email_first';

do $p$
declare d text := pg_get_functiondef('public.hq_advisor'::regproc); n0 int;
begin
  -- the Hunter decision, read once
  d := replace(d, $o$v_hunter jsonb := (select value from system_config where key = 'hunter_account');$o$,
                  $n$v_hunter jsonb := (select value from system_config where key = 'hunter_account');
        v_hdec jsonb := coalesce((select value from system_config where key = 'hunter_decision'), '{}'::jsonb);$n$);
  -- bottleneck action: no upgrade prompt
  d := replace(d, $o$': on Hunter Free that is 8 checks a day; Starter lifts it to 40.'$o$,
                  $n$': ' || coalesce(v_hdec->>'bottleneck_note', 'on Hunter Free that is 8 checks a day.')$n$);
  -- allocate action: the decision, not an upgrade
  n0 := length(d);
  d := regexp_replace(d, $re$'Upgrade Hunter to Starter[^\n]*\n\s*\|\| case when v_finder_n > 0 then[^\n]*\n\s*\|\| '; point it at ' \|\| advisor_agent_label\(v_cov\.key\) \|\| ' first\.'$re$,
                  $n$coalesce(v_hdec->>'allocate_action', 'Hunter stays on Free until the next allowance reset.') || ' ' || advisor_agent_label(v_cov.key) || ' goes first.'$n$);
  if strpos(d, 'Starter') > 0 or strpos(d, 'v_hdec jsonb') = 0 or length(d) = n0 then
    raise exception 'hq_advisor patch did not apply cleanly';
  end if;
  execute d;
end $p$;

-- 4. Production defect, 16 Oct: gemini-3.1-flash-lite answered 503 ("high demand") all day and every discovery
--    workflow's "backup" model pointed at the same model, so qualification produced nothing (candidates were kept as
--    NOT_EVALUATED_PROVIDER_FAILURE, never as commercial rejections). n8n now uses gemini-3.5-flash-lite as the real
--    fallback in 02-08, and as the model for 09, 19, 21 and 23; the health probe (00b) checks 3.5. Config records follow.
update public.system_config set value = value
    || jsonb_build_object('backup', 'models/gemini-3.5-flash-lite',
                          'research', 'models/gemini-3.5-flash-lite',
                          'note', '16 Oct: 3.1 Flash-Lite overloaded (503). Discovery 02-08: 3.1 first for entity extraction, 3.5 Flash-Lite fallback and qualification. 09, 19, 21, 23 and the health probe: 3.5 Flash-Lite. Drafting (18): Gemini 3 Flash.')
 where key = 'ai_model_routing';
update public.system_config set value = value
    || jsonb_build_object('models/gemini-3.5-flash-lite', jsonb_build_object('in', 0.30, 'out', 2.50),
                          'source', 'ai.google.dev/gemini-api/docs/pricing (3.1 and 3 Flash checked 7 Oct; 3.5 Flash-Lite checked 16 Oct 2026); output price includes thinking tokens')
 where key = 'ai_pricing';
update public.system_config set value = jsonb_set(value, '{research}', '"models/gemini-3.5-flash-lite"'::jsonb)
 where key = 'drafting_model';
