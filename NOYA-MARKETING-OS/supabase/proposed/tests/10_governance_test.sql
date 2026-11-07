-- Behavioural checks for 0001_governance.sql. Run on a throwaway local Postgres after 00_supabase_stub.sql,
-- 0001 and 0002. Every block raises if a safety property does not hold. See ../README.md.
\set ON_ERROR_STOP on
set client_min_messages = warning;

-- Fixtures: Adam (owner), an editor, a channel account, a draft Instagram request raised by an agent.
insert into auth.users values ('00000000-0000-0000-0000-00000000000a', 'adam@example.test'),
                              ('00000000-0000-0000-0000-00000000000e', 'editor@example.test');
insert into gov.members (user_id, email, role, added_by) values
  ('00000000-0000-0000-0000-00000000000a', 'adam@example.test', 'owner', 'test'),
  ('00000000-0000-0000-0000-00000000000e', 'editor@example.test', 'editor', 'test');
insert into gov.service_identities (code, kind, description, may_request, may_execute, active) values
  ('agent.content_strategist', 'agent', 'test agent', '{instagram.publish_media}', '{}', true),
  ('executor.publisher', 'executor', 'test executor', '{}', '{instagram.publish_media}', true);

create temp table ctx (k text primary key, v text);
grant all on ctx to authenticated, service_role;

do $$
declare ch uuid; rq uuid;
begin
  -- A connection cannot be claimed without evidence.
  begin
    insert into gov.channel_accounts (platform, handle, connection_status) values ('instagram', '@fake', 'read_write');
    raise exception 'FAIL: claimed a connection without evidence';
  exception when check_violation then null; end;

  insert into gov.channel_accounts (platform, handle, connection_status, verified_at, verified_by, verification_evidence, credential_ref)
  values ('instagram', '@noya_test', 'read_write', now(), 'test', '{"call":"GET /me","http_status":200}', 'TEST_CREDENTIAL')
  returning id into ch;

  insert into gov.action_requests (action_type, channel_account_id, payload, rationale, requested_by_type, requested_by, idempotency_key)
  values ('instagram.publish_media', ch, '{"caption":"Cairo, quietly."}', 'test', 'agent', 'agent.content_strategist', 'k1')
  returning id into rq;
  insert into ctx values ('rq', rq::text), ('ch', ch::text);
end $$;

-- Helpers: act as a signed-in member; assert a refusal that left a 'blocked' audit row.
create or replace function pg_temp.as_member(p_uid text, p_email text) returns void language sql
as $$ select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'email', p_email)::text, false) $$;

create or replace function pg_temp.expect_refused(p_res jsonb, p_label text, p_reason_like text default '%') returns void
language plpgsql as $$
begin
  if coalesce((p_res ->> 'ok')::boolean, true) then raise exception 'FAIL: % was allowed', p_label; end if;
  if p_res ->> 'reason' not like p_reason_like then raise exception 'FAIL: % refused for the wrong reason: %', p_label, p_res ->> 'reason'; end if;
  if not exists (select 1 from gov.audit_log where result = 'blocked' and reason = p_res ->> 'reason') then
    raise exception 'FAIL: refusal of % left no audit row', p_label;
  end if;
end $$;

create or replace function pg_temp.rq() returns uuid language sql as $$ select v::uuid from ctx where k = 'rq' $$;
create or replace function pg_temp.sha(p uuid) returns text language sql as $$ select payload_sha256 from gov.action_requests where id = p $$;

-- 1. Editors can submit but cannot approve.
do $$
begin
  perform pg_temp.as_member('00000000-0000-0000-0000-00000000000e', 'editor@example.test');
  if not (api.submit_for_approval(pg_temp.rq()) ->> 'ok')::boolean then raise exception 'FAIL: editor could not submit'; end if;
  perform pg_temp.expect_refused(api.decide(pg_temp.rq(), 'approve', pg_temp.sha(pg_temp.rq())), 'editor approval', 'approver role required');
end $$;

-- 2. Approving a payload you did not see is refused.
do $$
begin
  perform pg_temp.as_member('00000000-0000-0000-0000-00000000000a', 'adam@example.test');
  perform pg_temp.expect_refused(api.decide(pg_temp.rq(), 'approve', 'not-the-hash'), 'stale approval', 'the payload changed%');
end $$;

-- 3. The payload is frozen once submitted (direct writes are blocked by trigger, even for the service role).
do $$
begin
  begin
    update gov.action_requests set payload = '{"caption":"edited after review"}' where id = pg_temp.rq();
    raise exception 'FAIL: payload changed after submission';
  exception when insufficient_privilege then null; end;
end $$;

-- 4. Owner approves. Still cannot run: confirmation pending, and the kill switch is installed halted.
do $$
declare g record;
begin
  perform pg_temp.as_member('00000000-0000-0000-0000-00000000000a', 'adam@example.test');
  if (api.decide(pg_temp.rq(), 'approve', pg_temp.sha(pg_temp.rq())) ->> 'status') <> 'approved' then raise exception 'FAIL: not approved'; end if;
  select * into g from gov.can_execute(pg_temp.rq());
  if g.ok or g.reason <> 'awaiting execution confirmation' then raise exception 'FAIL: expected confirmation gate, got %', g.reason; end if;
  perform pg_temp.expect_refused(api.confirm_execution(pg_temp.rq()), 'queue while halted', 'kill switch%');
  if (select confirmed_at from gov.action_requests where id = pg_temp.rq()) is not null then
    raise exception 'FAIL: a refused confirmation was left recorded';
  end if;
end $$;

-- 5. Arming needs the owner, a reason and the typed phrase. Then it queues; then halting blocks it.
do $$
declare st text; res jsonb;
begin
  perform pg_temp.as_member('00000000-0000-0000-0000-00000000000e', 'editor@example.test');
  perform pg_temp.expect_refused(api.kill_switch_arm('global', 'test', 'ARM global'), 'editor arming', 'owner role required');

  perform pg_temp.as_member('00000000-0000-0000-0000-00000000000a', 'adam@example.test');
  perform pg_temp.expect_refused(api.kill_switch_arm('global', 'test', 'arm'), 'arming without phrase', 'type exactly%');

  perform api.kill_switch_arm('global', 'test run', 'ARM global');
  perform api.kill_switch_arm('publish.instagram', 'test run', 'ARM publish.instagram');
  if (api.confirm_execution(pg_temp.rq()) ->> 'status') <> 'queued' then raise exception 'FAIL: expected queued'; end if;

  res := api.kill_switch_halt('global', 'test halt');
  select status into st from gov.action_requests where id = pg_temp.rq();
  if st <> 'blocked' or (res ->> 'requests_blocked')::int <> 1 then raise exception 'FAIL: halt did not block queued work (%/%)', st, res; end if;
end $$;

-- 6. Re-arming does not resume blocked work: a blocked request is terminal.
do $$
begin
  perform pg_temp.as_member('00000000-0000-0000-0000-00000000000a', 'adam@example.test');
  perform api.kill_switch_arm('global', 'test re-arm', 'ARM global');
  perform pg_temp.expect_refused(api.confirm_execution(pg_temp.rq()), 'resume blocked work', 'request is blocked%');
end $$;

-- 7. Full happy path, then the executor's own re-check, and an executor that is not allowed.
do $$
declare rq uuid; res jsonb;
begin
  perform pg_temp.as_member('00000000-0000-0000-0000-00000000000a', 'adam@example.test');
  insert into gov.action_requests (action_type, channel_account_id, payload, rationale, requested_by_type, requested_by, idempotency_key, status)
  values ('instagram.publish_media', (select v::uuid from ctx where k = 'ch'), '{"caption":"Aswan at first light."}', 'test', 'agent', 'agent.content_strategist', 'k2', 'pending_approval')
  returning id into rq;
  perform api.decide(rq, 'approve', pg_temp.sha(rq));
  perform api.confirm_execution(rq);

  perform pg_temp.expect_refused(api.executor_claim('executor.unknown', rq), 'unknown executor', 'executor not allowed%');

  res := api.executor_claim('executor.publisher', rq);
  if (res -> 'request' ->> 'status') <> 'executing' then raise exception 'FAIL: claim did not move to executing: %', res; end if;
  res := api.executor_report('executor.publisher', rq, true, true, 'dry-run-123', null, '{"note":"dry run","access_token":"abc"}');
  if res ->> 'status' <> 'succeeded' or res -> 'result' ->> 'access_token' <> '[REDACTED]' then raise exception 'FAIL: report or redaction: %', res; end if;
end $$;

-- 8. Money cannot be automatic, and spend cannot be armed without a confirmed cap.
do $$
begin
  perform pg_temp.as_member('00000000-0000-0000-0000-00000000000a', 'adam@example.test');
  perform pg_temp.expect_refused(api.set_policy('meta_ads.activate', 'auto_within_limits', 'test', 'meta_ads.activate', now() + interval '1 day'),
                                 'automatic spend', '%cannot be automatic%');
  if (select mode from gov.permission_policies where action_type = 'meta_ads.activate' and superseded_at is null) <> 'blocked' then
    raise exception 'FAIL: refused policy change still altered the policy';
  end if;
  perform pg_temp.expect_refused(api.kill_switch_arm('spend.meta', 'test', 'ARM spend.meta'), 'spend without cap', 'set a daily cap%');
end $$;

-- 9. Monitors can halt through a tripwire.
do $$
declare st text;
begin
  perform api.monitor_trip('monitor.test', 'executor_failures', '{"failures":3}');
  select state into st from gov.system_controls where key = 'global';
  if st <> 'halted' then raise exception 'FAIL: tripwire did not halt'; end if;
end $$;

-- 10. The audit log is append-only and its chain verifies.
do $$
declare n int;
begin
  begin
    update gov.audit_log set reason = 'tampered' where seq = 1;
    raise exception 'FAIL: audit row updated';
  exception when insufficient_privilege then null; end;
  begin
    delete from gov.audit_log where seq = 1;
    raise exception 'FAIL: audit row deleted';
  exception when insufficient_privilege then null; end;
  select count(*) into n from gov.verify_audit_chain();
  if n <> 0 then raise exception 'FAIL: audit chain broken'; end if;
  select count(*) into n from gov.audit_log;
  if n < 10 then raise exception 'FAIL: expected a full audit trail, got % rows', n; end if;
end $$;

-- 11. Browser roles cannot read tables directly.
do $$
begin
  set local role authenticated;
  begin
    perform 1 from gov.action_requests limit 1;
    raise exception 'FAIL: authenticated read a governance table';
  exception when insufficient_privilege then null; end;
  reset role;
end $$;

-- 12. An HQ hand-off needs a qualified lead with every gate passed.
do $$
declare l uuid; q uuid;
begin
  insert into leads.inbound (received_at, channel, excerpt, created_by) values (now(), 'instagram_dm', 'test', 'test') returning id into l;
  insert into leads.qualifications (lead_id, segment, gates, fit_score, intent_score, verdict, evidence, assessed_by)
  values (l, 'private_client', '{"identifiable":true,"reachable":true,"real_need":true,"fit":true,"timing":false}', 80, 70, 'qualified', 'test', 'test')
  returning id into q;
  begin
    insert into leads.hq_handoffs (lead_id, qualification_id, payload) values (l, q, '{}');
    raise exception 'FAIL: hand-off with a failed gate';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
end $$;

-- 13. The chain verifies in any session time zone, and detects tampering by someone who bypasses the triggers.
do $$
declare n int; bad bigint;
begin
  set local timezone = 'Africa/Cairo';
  select count(*) into n from gov.verify_audit_chain();
  if n <> 0 then raise exception 'FAIL: chain depends on session time zone'; end if;

  alter table gov.audit_log disable trigger audit_log_no_update;   -- simulates a superuser edit
  update gov.audit_log set reason = 'rewritten history' where seq = 3;
  alter table gov.audit_log enable trigger audit_log_no_update;
  select bad_seq into bad from gov.verify_audit_chain();
  if bad is distinct from 3 then raise exception 'FAIL: tampering not detected (got %)', bad; end if;
  raise exception 'rollback-tamper';   -- undo the simulated edit
exception when others then
  if sqlerrm <> 'rollback-tamper' then raise; end if;
end $$;

select 'ALL GOVERNANCE CHECKS PASSED' as result;
