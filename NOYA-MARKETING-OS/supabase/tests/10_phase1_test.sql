-- NOYA Marketing OS — Phase 1 behavioural tests.
-- Run on a throwaway Postgres after 00_supabase_stub.sql and supabase/migrations/*.sql (see scripts/test-db.sh).
-- Each numbered block raises 'FAIL: ...' if a safety property does not hold, and prints PASS otherwise.
\set ON_ERROR_STOP on
set client_min_messages = notice;

-- ---------------------------------------------------------------- fixtures
insert into auth.users values ('00000000-0000-0000-0000-00000000000a', 'owner@example.test'),
                              ('00000000-0000-0000-0000-00000000000e', 'editor@example.test'),
                              ('00000000-0000-0000-0000-0000000000ff', 'stranger@example.test');
insert into gov.members (user_id, email, role, added_by) values
  ('00000000-0000-0000-0000-00000000000a', 'owner@example.test', 'owner', 'test'),
  ('00000000-0000-0000-0000-00000000000e', 'editor@example.test', 'editor', 'test');
update gov.service_identities set active = true where code in ('agent.content_strategist','agent.paid_media_analyst','executor.publisher','executor.ads','dispatcher.resend');

create table public.t_ctx (k text primary key, v text);
grant all on public.t_ctx to authenticated, mos_agent, mos_executor, mos_monitor, mos_dispatcher;

create function public.t_as(p_uid text, p_email text) returns void language sql
as $$ select set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'email', p_email, 'role', 'authenticated')::text end, false) $$;
create function public.t_owner() returns void language sql as $$ select public.t_as('00000000-0000-0000-0000-00000000000a', 'owner@example.test') $$;
create function public.t_editor() returns void language sql as $$ select public.t_as('00000000-0000-0000-0000-00000000000e', 'editor@example.test') $$;
create function public.t_get(p text) returns uuid language sql as $$ select v::uuid from public.t_ctx where k = p $$;
create function public.t_put(p text, v text) returns void language sql as $$ insert into public.t_ctx values (p, v) on conflict (k) do update set v = excluded.v $$;
create function public.t_sha(p_req uuid) returns text language sql security definer
as $$ select v.payload_sha256 from gov.approval_versions v join gov.approval_requests r on r.id = v.request_id and v.version = r.current_version where r.id = p_req $$;
create function public.t_status(p_req uuid) returns text language sql security definer as $$ select status from gov.approval_requests where id = p_req $$;
create function public.t_ver(p_req uuid) returns int language sql security definer as $$ select current_version from gov.approval_requests where id = p_req $$;
-- Assert a refusal whose audit row was committed.
create function public.t_refused(p_res jsonb, p_label text, p_like text default '%') returns void language plpgsql security definer
as $$
begin
  if coalesce((p_res ->> 'ok')::boolean, true) then raise exception 'FAIL: % was allowed: %', p_label, p_res; end if;
  if (p_res ->> 'reason') not like p_like then raise exception 'FAIL: % refused for the wrong reason: %', p_label, p_res ->> 'reason'; end if;
  if not exists (select 1 from gov.audit_log where result = 'refused' and reason = p_res ->> 'reason') then
    raise exception 'FAIL: refusal of % was not audited', p_label;
  end if;
end $$;
create function public.t_ok(p_res jsonb, p_label text) returns jsonb language plpgsql
as $$ begin if not coalesce((p_res ->> 'ok')::boolean, false) then raise exception 'FAIL: % refused: %', p_label, p_res; end if; return p_res; end $$;
create function public.t_pass(p text) returns void language plpgsql as $$ begin raise notice 'PASS  %', p; end $$;
-- Test helpers only (t_*). The mos_* grants are exactly those of the migration and are not touched here.
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 't\_%' loop
    execute format('grant execute on function %s to authenticated, mos_agent, mos_executor, mos_monitor, mos_dispatcher', f.sig);
  end loop;
end $$;

-- Simulate a verified connection (in production this is written only after a logged verification call).
create function public.t_connect(p_code text) returns void language sql security definer
as $$ update gov.integration_registry set status = 'read_write', verified_at = now(),
         verification_evidence = '{"test":true,"call":"GET /me","http_status":200}' where code = p_code $$;

-- =====================================================================================================
-- 01 Initial state: every kill switch disabled; no integration writable; no public tables
do $$ begin
  if exists (select 1 from gov.kill_switches where state <> 'disabled') then raise exception 'FAIL: a kill switch did not initialise disabled'; end if;
  if (select count(*) from gov.kill_switches) <> 8 then raise exception 'FAIL: expected 8 kill switches'; end if;
  if exists (select 1 from gov.integration_registry where status in ('read_only','read_write')) then raise exception 'FAIL: an integration claims a connection'; end if;
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename <> 't_ctx') then raise exception 'FAIL: public tables exist'; end if;
  perform public.t_pass('01 initial state: 8 switches disabled, nothing connected, no public tables');
end $$;

-- 02 A connection cannot be fabricated
do $$ begin
  begin
    update gov.integration_registry set status = 'read_write' where code = 'instagram';
    raise exception 'FAIL: connection claimed without evidence';
  exception when check_violation then null; end;
  perform public.t_pass('02 connection status needs verification evidence');
end $$;

-- 03 Unauthorised users are refused, and the refusal is committed
do $$ begin
  perform public.t_as('00000000-0000-0000-0000-0000000000ff', 'stranger@example.test');
  perform public.t_refused(public.mos_console_snapshot(), 'stranger snapshot', 'not a Marketing OS member');
  perform public.t_refused(public.mos_create_draft('instagram.publish_media', '@noya', 't', 'r', '{}'), 'stranger draft', 'editor role required');
  perform public.t_as(null, null);
  perform public.t_refused(public.mos_kill_switch_enable('global', 'x', 'ENABLE global'), 'anonymous enable', 'owner role required');
  if not exists (select 1 from gov.safety_events where kind = 'unauthorised_attempt') then raise exception 'FAIL: no safety event for unauthorised attempt'; end if;
  perform public.t_pass('03 unauthorised users refused and audited');
end $$;

-- 04 Browser roles cannot touch tables or worker functions
do $$ begin
  set local role anon;
  begin perform public.mos_console_snapshot(); raise exception 'FAIL: anon executed snapshot'; exception when insufficient_privilege then null; end;
  reset role;
  set local role authenticated;
  begin perform 1 from gov.approval_requests limit 1; raise exception 'FAIL: authenticated read a table'; exception when insufficient_privilege then null; end;
  begin perform public.mos_executor_claim('executor.publisher', gen_random_uuid()); raise exception 'FAIL: authenticated called executor'; exception when insufficient_privilege then null; end;
  reset role;
  perform public.t_pass('04 browser roles: no table access, no worker functions');
end $$;

-- 05 Editor drafts and submits; editor cannot approve or execute
do $$ declare res jsonb; begin
  perform public.t_editor();
  res := public.t_ok(public.mos_create_draft('instagram.publish_media', '@noyaconcierge', 'Aswan at first light', 'Pillar: Egypt insider', '{"caption":"Aswan, before the heat."}'), 'editor draft');
  perform public.t_put('r1', res ->> 'request_id');
  perform public.t_ok(public.mos_submit(public.t_get('r1')), 'editor submit');
  perform public.t_refused(public.mos_decide(public.t_get('r1'), 1, public.t_sha(public.t_get('r1')), 'approve'), 'editor approve', 'approver role required');
  perform public.t_refused(public.mos_request_execution(public.t_get('r1')), 'editor execute', 'owner role required');
  perform public.t_pass('05 editor can draft and submit, cannot approve or execute');
end $$;

-- 06 Approval bound to what was seen: stale hash / wrong version refused
do $$ begin
  perform public.t_owner();
  perform public.t_refused(public.mos_decide(public.t_get('r1'), 1, 'deadbeef', 'approve'), 'stale hash', 'the content changed since%');
  perform public.t_refused(public.mos_decide(public.t_get('r1'), 2, public.t_sha(public.t_get('r1')), 'approve'), 'wrong version', 'the content changed since%');
  perform public.t_pass('06 approval must match the exact version and payload hash seen');
end $$;

-- 07 Owner approves; execution still refused while kill switches are disabled
do $$ declare res jsonb; begin
  perform public.t_owner();
  res := public.t_ok(public.mos_decide(public.t_get('r1'), 1, public.t_sha(public.t_get('r1')), 'approve', 'Good'), 'owner approve');
  perform public.t_put('a1', res ->> 'approval_id');
  perform public.t_refused(public.mos_request_execution(public.t_get('r1')), 'execute while disabled', 'kill switch disabled%');
  if exists (select 1 from gov.execution_requests) then raise exception 'FAIL: something was queued'; end if;
  perform public.t_pass('07 approved work cannot execute while kill switches are disabled');
end $$;

-- 08 An edit after approval invalidates the approval
do $$ declare res jsonb; g record; begin
  perform public.t_editor();
  res := public.t_ok(public.mos_edit_draft(public.t_get('r1'), '{"caption":"Aswan, before the heat. Edited."}', 'tweak'), 'edit after approval');
  if (res ->> 'approvals_invalidated')::int <> 1 or res ->> 'status' <> 'draft' or (res ->> 'version')::int <> 2 then
    raise exception 'FAIL: edit did not invalidate approval: %', res;
  end if;
  select * into g from gov.gate(public.t_get('r1'));
  if g.ok or g.reason <> 'approval invalidated by an edit' then raise exception 'FAIL: gate after edit said %', g.reason; end if;
  perform public.t_pass('08 content edit after approval invalidates it (version 2, back to draft)');
end $$;

-- 09 Owner-only enable with typed phrase; Adam personal LinkedIn can never be enabled; paid needs caps
do $$ begin
  perform public.t_editor();
  perform public.t_refused(public.mos_kill_switch_enable('global', 'x', 'ENABLE global'), 'editor enable', 'owner role required');
  perform public.t_owner();
  perform public.t_refused(public.mos_kill_switch_enable('global', 'x', 'enable'), 'enable without phrase', 'type exactly%');
  perform public.t_refused(public.mos_kill_switch_enable('organic.linkedin_adam', 'x', 'ENABLE organic.linkedin_adam'), 'enable personal LinkedIn', '%never automated');
  perform public.t_refused(public.mos_kill_switch_enable('paid.meta_ads', 'x', 'ENABLE paid.meta_ads'), 'enable paid without cap', 'set a daily cap%');
  perform public.t_pass('09 enabling: owner + typed phrase; personal LinkedIn never; paid needs confirmed caps');
end $$;

-- 10 Full path: resubmit v2, approve, enable, connect, queue, claim (executor role), report
do $$ declare res jsonb; begin
  perform public.t_editor();
  perform public.t_ok(public.mos_submit(public.t_get('r1')), 'resubmit v2');
  perform public.t_owner();
  res := public.t_ok(public.mos_decide(public.t_get('r1'), 2, public.t_sha(public.t_get('r1')), 'approve'), 'approve v2');
  perform public.t_put('a2', res ->> 'approval_id');
  perform public.t_ok(public.mos_kill_switch_enable('global', 'test', 'ENABLE global'), 'enable global');
  perform public.t_ok(public.mos_kill_switch_enable('integration.external_writes', 'test', 'ENABLE integration.external_writes'), 'enable writes');
  perform public.t_ok(public.mos_kill_switch_enable('organic.instagram', 'test', 'ENABLE organic.instagram'), 'enable instagram');
  perform public.t_refused(public.mos_request_execution(public.t_get('r1')), 'execute without connection', 'integration instagram is not_connected%');
  perform public.t_connect('instagram');
  res := public.t_ok(public.mos_request_execution(public.t_get('r1')), 'queue execution');
  perform public.t_put('e1', res ->> 'execution_id');
  perform public.t_refused(public.mos_request_execution(public.t_get('r1')), 'queue twice', 'already queued or executed');
  perform public.t_pass('10 full path to queued; double-queue refused');
end $$;

-- 11 Agents cannot execute: no privilege on executor functions, and an agent identity is refused by the executor path
do $$ declare res jsonb; begin
  set local role mos_agent;
  begin perform public.mos_executor_claim('executor.publisher', public.t_get('e1')); raise exception 'FAIL: agent role reached executor'; exception when insufficient_privilege then null; end;
  begin perform public.mos_decide(public.t_get('r1'), 2, 'x', 'approve'); raise exception 'FAIL: agent role reached decide'; exception when insufficient_privilege then null; end;
  begin perform public.mos_kill_switch_enable('global', 'x', 'ENABLE global'); raise exception 'FAIL: agent role reached enable'; exception when insufficient_privilege then null; end;
  begin perform 1 from gov.execution_requests; raise exception 'FAIL: agent role read a table'; exception when insufficient_privilege then null; end;
  res := public.mos_agent_propose('agent.content_strategist', 'meta_ads.activate', 'act_1', 'Activate', 'x', '{}');
  reset role;
  perform public.t_refused(res, 'agent proposing spend', 'agent may not propose meta_ads.activate');
  set local role mos_executor;
  res := public.mos_executor_claim('agent.content_strategist', public.t_get('e1'));
  reset role;
  perform public.t_refused(res, 'agent identity on executor path', 'identity may not execute%');
  if not exists (select 1 from gov.safety_events where kind = 'approval_bypass_attempt') then raise exception 'FAIL: bypass attempt not flagged'; end if;
  if not exists (select 1 from gov.notifications where kind = 'approval_bypass_attempt') then raise exception 'FAIL: bypass attempt not alerted'; end if;
  perform public.t_pass('11 agents cannot execute, approve or enable; bypass attempts flagged and alerted');
end $$;

-- 12 Agents can propose within their list (draft/submitted only)
do $$ declare res jsonb; begin
  set local role mos_agent;
  res := public.mos_agent_propose('agent.content_strategist', 'instagram.publish_media', '@noyaconcierge', 'Red Sea', 'Season', '{"caption":"Red Sea, January."}');
  reset role;
  perform public.t_ok(res, 'agent propose');
  if public.t_status((res ->> 'request_id')::uuid) <> 'submitted' then raise exception 'FAIL: agent proposal not submitted'; end if;
  perform public.t_put('r_agent', res ->> 'request_id');
  perform public.t_pass('12 agent proposals land as submitted drafts awaiting Adam');
end $$;

-- 13 Executor claims once; duplicates refused; report; replay refused
do $$ declare res jsonb; begin
  set local role mos_executor;
  res := public.mos_executor_claim('executor.publisher', public.t_get('e1'));
  reset role;
  perform public.t_ok(res, 'claim');
  if res ->> 'payload_sha256' <> public.t_sha(public.t_get('r1')) then raise exception 'FAIL: claimed payload differs from approved version'; end if;
  set local role mos_executor;
  res := public.mos_executor_claim('executor.publisher', public.t_get('e1'));
  reset role;
  perform public.t_refused(res, 'duplicate claim', 'execution is claimed (duplicate refused)');
  set local role mos_executor;
  res := public.mos_executor_report('executor.publisher', public.t_get('e1'), true, true, 'dry-run-1', null, '{"note":"dry run","access_token":"abc"}');
  reset role;
  perform public.t_ok(res, 'report');
  if public.t_status(public.t_get('r1')) <> 'executed' then raise exception 'FAIL: request not executed'; end if;
  if (select result ->> 'access_token' from gov.execution_results where execution_request_id = public.t_get('e1')) <> '[REDACTED]' then raise exception 'FAIL: token not redacted'; end if;
  perform public.t_owner();
  perform public.t_refused(public.mos_request_execution(public.t_get('r1')), 'replay after execution', 'already queued or executed');
  begin
    insert into gov.execution_requests (request_id, approval_id, version, payload_sha256, action_type, integration_code, target_ref, idempotency_key, requested_by)
    select request_id, approval_id, version, payload_sha256, action_type, integration_code, target_ref, gen_random_uuid(), 'attacker' from gov.execution_requests where id = public.t_get('e1');
    raise exception 'FAIL: second execution for the same approval inserted';
  exception when unique_violation then null; end;
  set local role mos_executor;
  res := public.mos_executor_report('executor.publisher', public.t_get('e1'), true, true);
  reset role;
  perform public.t_refused(res, 'second report', 'execution is not claimed by this executor');
  perform public.t_pass('13 single claim, duplicate claim refused, replay refused (one approval = one execution)');
end $$;

-- 14 Mutation after approval is impossible at the storage layer
do $$ begin
  begin update gov.approval_versions set payload = '{"caption":"swapped"}' where request_id = public.t_get('r1'); raise exception 'FAIL: version mutated'; exception when insufficient_privilege then null; end;
  begin update gov.approvals set payload_sha256 = 'x' where id = public.t_get('a2'); raise exception 'FAIL: approval mutated'; exception when insufficient_privilege then null; end;
  begin update gov.approvals set expires_at = now() + interval '1 year' where id = public.t_get('a2'); raise exception 'FAIL: approval extended'; exception when insufficient_privilege then null; end;
  begin update gov.execution_requests set payload_sha256 = 'x' where id = public.t_get('e1'); raise exception 'FAIL: execution mutated'; exception when insufficient_privilege then null; end;
  begin delete from gov.approval_requests where id = public.t_get('r1'); raise exception 'FAIL: request deleted'; exception when insufficient_privilege then null; end;
  begin update gov.approval_requests set status = 'approved' where id = public.t_get('r1'); raise exception 'FAIL: executed request reopened'; exception when insufficient_privilege then null; end;
  perform public.t_pass('14 versions, approvals, executions frozen; terminal states cannot be reopened');
end $$;

-- 15 Revoked approval: execution refused; revocation after queueing cancels the queued execution
do $$ declare res jsonb; r uuid; begin
  perform public.t_owner();
  r := (public.t_ok(public.mos_create_draft('instagram.publish_story', '@noyaconcierge', 'Story', 'x', '{"frame":1}'), 'draft') ->> 'request_id')::uuid;
  perform public.t_ok(public.mos_submit(r), 'submit');
  perform public.t_ok(public.mos_decide(r, 1, public.t_sha(r), 'approve'), 'approve');
  res := public.t_ok(public.mos_request_execution(r), 'queue');
  perform public.t_ok(public.mos_revoke_approval(r, 'Changed my mind'), 'revoke');
  if (select status from gov.execution_requests where id = (res ->> 'execution_id')::uuid) <> 'cancelled' then raise exception 'FAIL: queued execution not cancelled'; end if;
  set local role mos_executor;
  res := public.mos_executor_claim('executor.publisher', (res ->> 'execution_id')::uuid);
  reset role;
  perform public.t_refused(res, 'claim after revoke', 'execution is cancelled%');
  perform public.t_refused(public.mos_request_execution(r), 'execute after revoke', 'approval revoked');
  perform public.t_pass('15 revoked approvals cannot execute; queued work cancelled');
end $$;

-- 16 Expired approval refused, and the expiry job marks it (two transactions: now() is fixed within one)
do $$ declare r uuid; begin
  update gov.permission_registry set approval_ttl = interval '1 millisecond' where action_type = 'instagram.reply_comment';
  perform public.t_owner();
  r := (public.t_ok(public.mos_create_draft('instagram.reply_comment', '@guest', 'Reply', 'x', '{"text":"Thank you."}'), 'draft') ->> 'request_id')::uuid;
  perform public.t_ok(public.mos_submit(r), 'submit');
  perform public.t_ok(public.mos_decide(r, 1, public.t_sha(r), 'approve'), 'approve');
  perform public.t_put('r_exp', r::text);
end $$;
select pg_sleep(0.05);
do $$ declare r uuid := public.t_get('r_exp'); n int; begin
  perform public.t_owner();
  perform public.t_refused(public.mos_request_execution(r), 'execute after expiry', 'approval expired');
  n := gov.expire_approvals();
  if n < 1 or public.t_status(r) <> 'expired' then raise exception 'FAIL: expiry job did not mark it'; end if;
  update gov.permission_registry set approval_ttl = interval '24 hours' where action_type = 'instagram.reply_comment';
  perform public.t_pass('16 expired approvals refused and marked expired');
end $$;

-- 17 Disabling a kill switch cancels queued work; claim then refused
do $$ declare res jsonb; r uuid; e uuid; begin
  perform public.t_owner();
  r := (public.t_ok(public.mos_create_draft('instagram.publish_media', '@noyaconcierge', 'Luxor', 'x', '{"caption":"Luxor."}'), 'draft') ->> 'request_id')::uuid;
  perform public.t_ok(public.mos_submit(r), 'submit');
  perform public.t_ok(public.mos_decide(r, 1, public.t_sha(r), 'approve'), 'approve');
  e := (public.t_ok(public.mos_request_execution(r), 'queue') ->> 'execution_id')::uuid;
  res := public.t_ok(public.mos_kill_switch_disable('organic.instagram', 'test stop'), 'disable');
  if (res ->> 'executions_cancelled')::int <> 1 then raise exception 'FAIL: queued work not cancelled: %', res; end if;
  set local role mos_executor;
  res := public.mos_executor_claim('executor.publisher', e);
  reset role;
  perform public.t_refused(res, 'claim after kill switch', 'execution is cancelled%');
  perform public.t_pass('17 kill switch cancels queued work; no execution after disable');
end $$;

-- 18 The system cannot re-enable itself
do $$ declare res jsonb; begin
  set local role mos_monitor;
  begin perform public.mos_kill_switch_enable('organic.instagram', 'x', 'ENABLE organic.instagram'); raise exception 'FAIL: monitor reached enable'; exception when insufficient_privilege then null; end;
  res := public.mos_monitor_trip('monitor.safety', 'unknown_publication', '{"post":"x"}');
  reset role;
  perform public.t_ok(res, 'monitor trip');
  if gov.switch_enabled('global') then raise exception 'FAIL: global still enabled after trip'; end if;
  begin
    update gov.kill_switches set state = 'enabled' where key = 'global';   -- even a direct write (superuser) is refused
    raise exception 'FAIL: switch enabled outside the owner function';
  exception when insufficient_privilege then null; end;
  if not exists (select 1 from gov.notifications where kind = 'unknown_publishing') then raise exception 'FAIL: unknown publishing not alerted'; end if;
  perform public.t_pass('18 monitors can only disable; nothing but the owner function can enable');
end $$;

-- 19 D4: automatic PAUSE allowed; automatic spend increase / activation refused
do $$ declare res jsonb; e uuid; begin
  perform public.t_connect('meta_ads');
  set local role mos_monitor;
  res := public.mos_monitor_safety_pause('monitor.safety', 'meta_ads.activate', 'act_123', 'try to activate');
  reset role;
  perform public.t_refused(res, 'automatic activate', 'automatic systems may only pause (D4)');
  set local role mos_monitor;
  res := public.mos_monitor_safety_pause('monitor.safety', 'meta_ads.increase_budget', 'act_123', 'try to increase');
  reset role;
  perform public.t_refused(res, 'automatic increase', 'automatic systems may only pause (D4)');
  set local role mos_monitor;
  res := public.mos_monitor_safety_pause('monitor.safety', 'meta_ads.pause', 'campaign_42', 'spend velocity');
  reset role;
  e := (public.t_ok(res, 'automatic pause') ->> 'execution_id')::uuid;
  -- paid.meta_ads and global are disabled, yet a pause is still executable (risk-reducing).
  set local role mos_executor;
  res := public.mos_executor_claim('executor.ads', e);
  reset role;
  perform public.t_ok(res, 'claim pause while switches disabled');
  perform public.t_pass('19 D4: automatic pause allowed even when halted; automatic activate/increase refused');
end $$;

-- 20 Spend tripwire disables paid switch and raises pauses for listed campaigns
do $$ declare res jsonb; begin
  set local role mos_monitor;
  res := public.mos_monitor_trip('monitor.safety', 'meta_spend_over_daily_cap', '{"spend":12000,"cap":10000}', array['campaign_1','campaign_2']);
  reset role;
  perform public.t_ok(res, 'spend trip');
  if (res ->> 'pauses_raised')::int <> 2 then raise exception 'FAIL: expected 2 pauses: %', res; end if;
  if not exists (select 1 from gov.notifications where kind = 'spend_cap_breach') then raise exception 'FAIL: spend breach not alerted'; end if;
  perform public.t_pass('20 spend cap tripwire: paid switch disabled, 2 pauses raised, alert queued');
end $$;

-- 21 Money-moving actions cannot be approved in Phase 1
do $$ declare r uuid; begin
  perform public.t_owner();
  r := (public.t_ok(public.mos_create_draft('meta_ads.increase_budget', 'campaign_1', 'Scale', 'x', '{"daily":5000}', 2000, 'GBP'), 'draft') ->> 'request_id')::uuid;
  perform public.t_ok(public.mos_submit(r), 'submit');
  perform public.t_refused(public.mos_decide(r, 1, public.t_sha(r), 'approve'), 'approve spend increase', 'permission blocks meta_ads.increase_budget%');
  perform public.t_pass('21 spend increases blocked by permission even for the owner');
end $$;

-- 22 Alerts: test messages are labelled; dispatcher sends nothing while alerts are disabled
do $$ declare res jsonb; begin
  perform public.t_owner();
  perform public.t_ok(public.mos_queue_test_alert(), 'queue test alert');
  if not exists (select 1 from gov.notifications where is_test and subject like '[TEST]%') then raise exception 'FAIL: test alert not labelled'; end if;
  begin insert into gov.notifications (kind, severity, subject, body, is_test) values ('test', 'info', 'unlabelled', 'x', true); raise exception 'FAIL: unlabelled test accepted';
  exception when check_violation then null; end;
  set local role mos_dispatcher;
  res := public.mos_dispatcher_claim('dispatcher.resend', 10);
  reset role;
  if jsonb_array_length(res -> 'notifications') <> 0 then raise exception 'FAIL: dispatcher claimed while disabled'; end if;
  perform public.t_pass('22 alerts: [TEST] labelling enforced; nothing dispatched while alerts disabled');
end $$;

-- 23 Console snapshot shows every panel to the owner
do $$ declare s jsonb; k text; begin
  perform public.t_owner();
  s := public.t_ok(public.mos_console_snapshot(), 'snapshot');
  foreach k in array array['system','kill_switches','pending_approvals','audit','audit_chain','integrations','health','agents','agent_runs','security','notifications','configuration','secrets'] loop
    if not s ? k then raise exception 'FAIL: snapshot missing %', k; end if;
  end loop;
  if jsonb_array_length(s -> 'kill_switches') <> 8 then raise exception 'FAIL: snapshot switches'; end if;
  perform public.t_ok(public.mos_health_check(), 'health check');
  perform public.t_pass('23 console snapshot complete; health check runs');
end $$;

-- 24 Audit: append-only, refusals committed, chain verifies, timezone-safe, tampering detected
do $$ declare n int; bad bigint; begin
  begin update gov.audit_log set reason = 'x' where seq = 1; raise exception 'FAIL: audit updated'; exception when insufficient_privilege then null; end;
  begin delete from gov.audit_log where seq = 1; raise exception 'FAIL: audit deleted'; exception when insufficient_privilege then null; end;
  select count(*) into n from gov.audit_log where result = 'refused';
  if n < 20 then raise exception 'FAIL: expected >= 20 committed refusals, got %', n; end if;
  if exists (select 1 from gov.verify_audit_chain()) then raise exception 'FAIL: chain broken'; end if;
  set local timezone = 'Africa/Cairo';
  if exists (select 1 from gov.verify_audit_chain()) then raise exception 'FAIL: chain depends on time zone'; end if;
  set local timezone = 'Pacific/Auckland';
  if exists (select 1 from gov.verify_audit_chain()) then raise exception 'FAIL: chain depends on time zone'; end if;
  perform public.t_pass(format('24a audit append-only; %s refusals committed; chain intact in UTC, Cairo, Auckland', n));
end $$;

do $$ declare bad bigint; begin
  alter table gov.audit_log disable trigger audit_log_no_update;
  update gov.audit_log set reason = 'rewritten history' where seq = 5;
  alter table gov.audit_log enable trigger audit_log_no_update;
  select bad_seq into bad from gov.verify_audit_chain();
  if bad is distinct from 5 then raise exception 'FAIL: tampering not detected (got %)', bad; end if;
  raise notice 'PASS  24b superuser tampering detected at seq %', bad;
  raise exception 'rollback-tamper';
exception when others then
  if sqlerrm <> 'rollback-tamper' then raise; end if;
end $$;

-- 25 Every required audit field is present on execution rows
do $$ begin
  if not exists (select 1 from gov.audit_log where action = 'execution.succeeded' and actor_type = 'executor' and tool is not null
                   and target_platform = 'instagram' and payload_sha256 is not null and approval_id is not null) then
    raise exception 'FAIL: execution audit row missing fields';
  end if;
  if not exists (select 1 from gov.audit_log where action = 'approval.approve' and decision = 'approve' and payload_sha256 is not null and correlation_id is not null) then
    raise exception 'FAIL: approval audit row missing fields';
  end if;
  perform public.t_pass('25 audit rows carry actor, tool, target, platform, payload hash, approval, decision, correlation');
end $$;

select 'PHASE 1 DATABASE TESTS: ALL PASSED' as result;
