-- =====================================================================================================
-- NOYA Marketing OS — Phase 1 / migration 3: API (public.mos_*), worker roles, lockdown, schedules
--
-- * Humans (console) call mos_* functions as `authenticated`; each function checks gov.members.
-- * Workers use dedicated Postgres roles, never the service key:
--     mos_agent       may only PROPOSE drafts
--     mos_executor    may only claim / report APPROVED executions
--     mos_monitor     may only DISABLE switches and raise D4 PAUSE requests
--     mos_dispatcher  may only read / mark the alert outbox
--   Workers authenticate with a JWT whose role claim is one of these (minted from the project JWT secret).
-- * Every refusal is returned as {ok:false, reason} and its audit row is COMMITTED.
-- =====================================================================================================

do $$
declare r text;
begin
  foreach r in array array['mos_agent','mos_executor','mos_monitor','mos_dispatcher'] loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I nologin noinherit', r);
    end if;
  end loop;
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    execute 'grant mos_agent, mos_executor, mos_monitor, mos_dispatcher to authenticator';
  end if;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Refusal helper: audit (committed) + optional safety event / alert
-- -----------------------------------------------------------------------------------------------------

create or replace function gov.refuse(p_actor_type text, p_actor text, p_tool text, p_action text, p_target_type text,
                                      p_target_id text, p_reason text, p_correlation uuid default null,
                                      p_safety_kind text default null, p_platform text default null, p_sha text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
begin
  perform gov.audit(p_actor_type, p_actor, p_tool, p_action, p_target_type, p_target_id, 'refused', p_reason,
                    null, p_correlation, p_platform, p_sha, null, 'refused');
  if p_safety_kind is not null then
    perform gov.safety_event(p_safety_kind, case when p_safety_kind = 'approval_bypass_attempt' then 'critical' else 'warning' end,
                             p_actor_type, p_actor, p_action || ' refused: ' || p_reason,
                             jsonb_build_object('target', p_target_type || ':' || coalesce(p_target_id, ''), 'tool', p_tool),
                             null,
                             case when p_safety_kind = 'approval_bypass_attempt' then 'approval_bypass_attempt' end);
  end if;
  return jsonb_build_object('ok', false, 'reason', p_reason);
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Drafting (humans and agents)
-- -----------------------------------------------------------------------------------------------------

create or replace function gov.create_request(p_actor_type text, p_actor text, p_action_type text, p_target_ref text,
                                              p_title text, p_rationale text, p_payload jsonb,
                                              p_spend_delta bigint, p_currency text)
returns gov.approval_requests language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare r gov.approval_requests; p gov.permission_registry;
begin
  select * into p from gov.permission_registry where action_type = p_action_type;
  insert into gov.approval_requests (action_type, integration_code, target_ref, title, rationale, current_version,
                                     spend_delta_minor, currency, requested_by_type, requested_by)
  values (p_action_type, p.integration_code, p_target_ref, p_title, p_rationale, 1,
          coalesce(p_spend_delta, 0), p_currency, p_actor_type, p_actor)
  returning * into r;
  insert into gov.approval_versions (request_id, version, payload, action_type, integration_code, target_ref, created_by_type, created_by)
  values (r.id, 1, p_payload, p_action_type, p.integration_code, p_target_ref, p_actor_type, p_actor);
  return r;
end $$;

create or replace function public.mos_create_draft(p_action_type text, p_target_ref text, p_title text, p_rationale text,
                                                   p_payload jsonb, p_spend_delta_minor bigint default 0, p_currency text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare who text := gov.actor(); r gov.approval_requests;
begin
  if not gov.has_role('editor') then
    return gov.refuse('human', who, 'mos_create_draft', 'request.create', 'gov.approval_requests', null, 'editor role required', null, 'unauthorised_attempt');
  end if;
  if not exists (select 1 from gov.permission_registry where action_type = p_action_type) then
    return gov.refuse('human', who, 'mos_create_draft', 'request.create', 'gov.approval_requests', null, 'unknown action type ' || coalesce(p_action_type, 'null'));
  end if;
  if p_payload is null or coalesce(trim(p_title), '') = '' or coalesce(trim(p_rationale), '') = '' or coalesce(trim(p_target_ref), '') = '' then
    return gov.refuse('human', who, 'mos_create_draft', 'request.create', 'gov.approval_requests', null, 'payload, title, rationale and target are required');
  end if;
  r := gov.create_request('human', who, p_action_type, p_target_ref, p_title, p_rationale, p_payload, p_spend_delta_minor, p_currency);
  perform gov.audit('human', who, 'mos_create_draft', 'request.create', 'gov.approval_requests', r.id::text, 'ok', null, null,
                    r.correlation_id, r.integration_code, gov.sha256_jsonb(p_payload));
  return jsonb_build_object('ok', true, 'request_id', r.id, 'version', 1, 'payload_sha256', gov.sha256_jsonb(p_payload));
end $$;

-- Agents may only create drafts (optionally submitted) for the action types in their may_request list.
create or replace function public.mos_agent_propose(p_agent text, p_action_type text, p_target_ref text, p_title text,
                                                    p_rationale text, p_payload jsonb, p_submit boolean default true)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare s gov.service_identities; r gov.approval_requests;
begin
  select * into s from gov.service_identities where code = p_agent and kind = 'agent' and active;
  if s.code is null then
    return gov.refuse('agent', coalesce(p_agent, 'unknown'), 'mos_agent_propose', 'request.propose', 'gov.approval_requests', null,
                      'not an active agent identity', null, 'approval_bypass_attempt');
  end if;
  if not (p_action_type = any (s.may_request)) then
    return gov.refuse('agent', p_agent, 'mos_agent_propose', 'request.propose', 'gov.approval_requests', null,
                      'agent may not propose ' || coalesce(p_action_type, 'null'), null, 'approval_bypass_attempt');
  end if;
  r := gov.create_request('agent', p_agent, p_action_type, p_target_ref, p_title, p_rationale, p_payload, 0, null);
  if p_submit then update gov.approval_requests set status = 'submitted' where id = r.id returning * into r; end if;
  perform gov.audit('agent', p_agent, 'mos_agent_propose', 'request.propose', 'gov.approval_requests', r.id::text, 'ok',
                    case when p_submit then 'submitted for approval' else 'draft' end, null, r.correlation_id, r.integration_code,
                    gov.sha256_jsonb(p_payload));
  return jsonb_build_object('ok', true, 'request_id', r.id, 'status', r.status);
end $$;

-- An edit creates a new version. If the request was submitted or approved, every approval is invalidated.
create or replace function public.mos_edit_draft(p_request_id uuid, p_payload jsonb, p_note text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare who text := gov.actor(); r gov.approval_requests; n int;
begin
  if not gov.has_role('editor') then
    return gov.refuse('human', who, 'mos_edit_draft', 'request.edit', 'gov.approval_requests', p_request_id::text, 'editor role required', null, 'unauthorised_attempt');
  end if;
  select * into r from gov.approval_requests where id = p_request_id for update;
  if not found then
    return gov.refuse('human', who, 'mos_edit_draft', 'request.edit', 'gov.approval_requests', p_request_id::text, 'request not found');
  end if;
  if r.status not in ('draft','submitted','approved','rejected','revoked','expired') then
    return gov.refuse('human', who, 'mos_edit_draft', 'request.edit', 'gov.approval_requests', r.id::text,
                      'cannot edit a request that is ' || r.status, r.correlation_id);
  end if;
  with inv as (
    update gov.approvals set invalidated_at = now(), invalidated_reason = 'edited to version ' || (r.current_version + 1)
     where request_id = r.id and invalidated_at is null and revoked_at is null
    returning 1)
  select count(*) into n from inv;
  insert into gov.approval_versions (request_id, version, payload, action_type, integration_code, target_ref, created_by_type, created_by, note)
  values (r.id, r.current_version + 1, p_payload, r.action_type, r.integration_code, r.target_ref, 'human', who, p_note);
  update gov.approval_requests set current_version = r.current_version + 1, status = 'draft'
   where id = r.id returning * into r;
  update gov.execution_requests set status = 'cancelled', status_reason = 'approval invalidated by edit', finished_at = now()
   where request_id = r.id and status = 'queued';
  perform gov.audit('human', who, 'mos_edit_draft', case when n > 0 then 'approval.invalidated' else 'request.edit' end,
                    'gov.approval_requests', r.id::text, 'ok', case when n > 0 then n || ' approval(s) invalidated by edit' end,
                    jsonb_build_object('version', r.current_version), r.correlation_id, r.integration_code, gov.sha256_jsonb(p_payload));
  return jsonb_build_object('ok', true, 'version', r.current_version, 'status', r.status, 'approvals_invalidated', n,
                            'payload_sha256', gov.sha256_jsonb(p_payload));
end $$;

create or replace function public.mos_submit(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare who text := gov.actor(); r gov.approval_requests;
begin
  if not gov.has_role('editor') then
    return gov.refuse('human', who, 'mos_submit', 'request.submit', 'gov.approval_requests', p_request_id::text, 'editor role required', null, 'unauthorised_attempt');
  end if;
  update gov.approval_requests set status = 'submitted' where id = p_request_id and status = 'draft' returning * into r;
  if not found then
    return gov.refuse('human', who, 'mos_submit', 'request.submit', 'gov.approval_requests', p_request_id::text, 'request is not a draft');
  end if;
  perform gov.audit('human', who, 'mos_submit', 'request.submit', 'gov.approval_requests', r.id::text, 'ok', null,
                    jsonb_build_object('version', r.current_version), r.correlation_id, r.integration_code);
  return jsonb_build_object('ok', true, 'status', r.status, 'version', r.current_version);
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Decisions, revocation, execution request
-- -----------------------------------------------------------------------------------------------------

create or replace function public.mos_decide(p_request_id uuid, p_version int, p_seen_sha256 text, p_decision text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare who text := gov.actor(); role text := gov.current_member_role(); r gov.approval_requests; v gov.approval_versions;
        p gov.permission_registry; a gov.approvals; t text := 'mos_decide';
begin
  if gov.role_rank(role) < gov.role_rank('approver') then
    return gov.refuse('human', who, t, 'approval.decide', 'gov.approval_requests', p_request_id::text, 'approver role required', null, 'unauthorised_attempt');
  end if;
  if p_decision not in ('approve','reject') then
    return gov.refuse('human', who, t, 'approval.decide', 'gov.approval_requests', p_request_id::text, 'decision must be approve or reject');
  end if;
  select * into r from gov.approval_requests where id = p_request_id for update;
  if not found then
    return gov.refuse('human', who, t, 'approval.decide', 'gov.approval_requests', p_request_id::text, 'request not found');
  end if;
  select * into p from gov.permission_registry where action_type = r.action_type;
  select * into v from gov.approval_versions where request_id = r.id and version = r.current_version;
  if r.status <> 'submitted' then
    return gov.refuse('human', who, t, 'approval.decide', 'gov.approval_requests', r.id::text, 'request is ' || r.status || ', not submitted', r.correlation_id);
  end if;
  if p_version is distinct from r.current_version or p_seen_sha256 is distinct from v.payload_sha256 then
    return gov.refuse('human', who, t, 'approval.decide', 'gov.approval_requests', r.id::text,
                      'the content changed since it was shown; reload and review the current version', r.correlation_id, null, r.integration_code, p_seen_sha256);
  end if;
  if p_decision = 'approve' and gov.role_rank(role) < gov.role_rank(p.min_approver_role) then
    return gov.refuse('human', who, t, 'approval.decide', 'gov.approval_requests', r.id::text, 'needs ' || p.min_approver_role || ' approval', r.correlation_id);
  end if;
  if p_decision = 'approve' and p.mode = 'blocked' then
    return gov.refuse('human', who, t, 'approval.decide', 'gov.approval_requests', r.id::text, 'permission blocks ' || r.action_type || ': ' || p.reason, r.correlation_id);
  end if;
  if r.requested_by_type = 'human' and lower(r.requested_by) = lower(who) and role <> 'owner' then
    return gov.refuse('human', who, t, 'approval.decide', 'gov.approval_requests', r.id::text, 'you cannot approve your own request', r.correlation_id);
  end if;
  if p_decision = 'reject' and coalesce(trim(p_note), '') = '' then
    return gov.refuse('human', who, t, 'approval.decide', 'gov.approval_requests', r.id::text, 'a note is required to reject', r.correlation_id);
  end if;

  insert into gov.approvals (request_id, version, version_id, payload_sha256, action_type, integration_code, target_ref,
                             decision, actor_type, actor_user_id, actor_email, actor_role, note, expires_at)
  values (r.id, v.version, v.id, v.payload_sha256, r.action_type, r.integration_code, v.target_ref,
          p_decision, 'human', auth.uid(), who, role, p_note, now() + p.approval_ttl)
  returning * into a;
  update gov.approval_requests set status = case when p_decision = 'approve' then 'approved' else 'rejected' end
   where id = r.id returning * into r;
  perform gov.audit('human', who, t, 'approval.' || p_decision, 'gov.approval_requests', r.id::text, 'ok', p_note,
                    jsonb_build_object('version', v.version, 'expires_at', a.expires_at), r.correlation_id,
                    r.integration_code, v.payload_sha256, a.id, p_decision);
  return jsonb_build_object('ok', true, 'status', r.status, 'approval_id', a.id, 'expires_at', a.expires_at);
end $$;

create or replace function public.mos_revoke_approval(p_request_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare who text := gov.actor(); r gov.approval_requests; a gov.approvals; t text := 'mos_revoke_approval';
begin
  if not gov.has_role('owner') then
    return gov.refuse('human', who, t, 'approval.revoke', 'gov.approval_requests', p_request_id::text, 'owner role required', null, 'unauthorised_attempt');
  end if;
  if coalesce(trim(p_reason), '') = '' then
    return gov.refuse('human', who, t, 'approval.revoke', 'gov.approval_requests', p_request_id::text, 'a reason is required');
  end if;
  select * into r from gov.approval_requests where id = p_request_id for update;
  a := gov.valid_approval(p_request_id);
  if r.id is null or a.id is null or r.status <> 'approved' then
    return gov.refuse('human', who, t, 'approval.revoke', 'gov.approval_requests', p_request_id::text, 'no revocable approval (request ' || coalesce(r.status, 'missing') || ')');
  end if;
  update gov.approvals set revoked_at = now(), revoked_by = who, revoke_reason = p_reason where id = a.id;
  update gov.approval_requests set status = 'revoked' where id = r.id;
  update gov.execution_requests set status = 'cancelled', status_reason = 'approval revoked', finished_at = now()
   where approval_id = a.id and status = 'queued';
  perform gov.audit('human', who, t, 'approval.revoke', 'gov.approval_requests', r.id::text, 'ok', p_reason, null,
                    r.correlation_id, r.integration_code, a.payload_sha256, a.id, 'revoke');
  return jsonb_build_object('ok', true, 'status', 'revoked');
end $$;

-- The owner's "run it" step: queues one execution bound to the approval's nonce. Every gate is checked first.
create or replace function public.mos_request_execution(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare who text := gov.actor(); r gov.approval_requests; g record; a gov.approvals; e gov.execution_requests; t text := 'mos_request_execution';
begin
  if not gov.has_role('owner') then
    return gov.refuse('human', who, t, 'execution.request', 'gov.approval_requests', p_request_id::text, 'owner role required', null, 'unauthorised_attempt');
  end if;
  select * into r from gov.approval_requests where id = p_request_id for update;
  if not found then
    return gov.refuse('human', who, t, 'execution.request', 'gov.approval_requests', p_request_id::text, 'request not found');
  end if;
  if exists (select 1 from gov.execution_requests where request_id = r.id and status in ('queued','claimed','succeeded')) then
    return gov.refuse('human', who, t, 'execution.request', 'gov.approval_requests', r.id::text, 'already queued or executed', r.correlation_id);
  end if;
  select * into g from gov.gate(r.id);
  if not g.ok then
    return gov.refuse('human', who, t, 'execution.request', 'gov.approval_requests', r.id::text, g.reason, r.correlation_id, null, r.integration_code);
  end if;
  select * into a from gov.approvals where id = g.approval_id;
  if exists (select 1 from gov.execution_requests where approval_id = a.id) then
    return gov.refuse('human', who, t, 'execution.request', 'gov.approval_requests', r.id::text, 'approval already used (replay refused)', r.correlation_id, 'approval_bypass_attempt');
  end if;
  insert into gov.execution_requests (request_id, approval_id, version, payload_sha256, action_type, integration_code, target_ref, idempotency_key, requested_by)
  values (r.id, a.id, a.version, a.payload_sha256, r.action_type, r.integration_code, a.target_ref, a.nonce, who)
  returning * into e;
  perform gov.audit('human', who, t, 'execution.request', 'gov.execution_requests', e.id::text, 'ok', null, null,
                    r.correlation_id, r.integration_code, a.payload_sha256, a.id);
  return jsonb_build_object('ok', true, 'execution_id', e.id, 'idempotency_key', e.idempotency_key);
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Executors (role mos_executor only)
-- -----------------------------------------------------------------------------------------------------

create or replace function public.mos_executor_claim(p_executor text, p_execution_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare s gov.service_identities; e gov.execution_requests; g record; v gov.approval_versions; t text := 'mos_executor_claim';
begin
  select * into s from gov.service_identities where code = p_executor and kind = 'executor' and active;
  select * into e from gov.execution_requests where id = p_execution_id for update skip locked;
  if not found then
    return gov.refuse('executor', coalesce(p_executor, 'unknown'), t, 'execution.claim', 'gov.execution_requests', p_execution_id::text,
                      'execution not available (missing or being claimed by another worker)');
  end if;
  if s.code is null or not (e.action_type = any (s.may_execute)) then
    return gov.refuse('executor', coalesce(p_executor, 'unknown'), t, 'execution.claim', 'gov.execution_requests', e.id::text,
                      'identity may not execute ' || e.action_type, null, 'approval_bypass_attempt', e.integration_code, e.payload_sha256);
  end if;
  if e.status <> 'queued' then
    return gov.refuse('executor', p_executor, t, 'execution.claim', 'gov.execution_requests', e.id::text,
                      'execution is ' || e.status || ' (duplicate refused)', null, null, e.integration_code, e.payload_sha256);
  end if;
  select * into g from gov.gate(e.request_id);
  if not g.ok or g.approval_id is distinct from e.approval_id then
    update gov.execution_requests set status = 'refused', status_reason = coalesce(g.reason, 'approval changed'), finished_at = now() where id = e.id;
    return gov.refuse('executor', p_executor, t, 'execution.claim', 'gov.execution_requests', e.id::text,
                      coalesce(case when g.ok then 'approval no longer matches this execution' end, g.reason),
                      null, null, e.integration_code, e.payload_sha256);
  end if;
  select * into v from gov.approval_versions where request_id = e.request_id and version = e.version;
  if v.payload_sha256 <> e.payload_sha256 then
    update gov.execution_requests set status = 'refused', status_reason = 'payload hash mismatch', finished_at = now() where id = e.id;
    return gov.refuse('executor', p_executor, t, 'execution.claim', 'gov.execution_requests', e.id::text, 'payload hash mismatch', null,
                      'approval_bypass_attempt', e.integration_code, e.payload_sha256);
  end if;
  update gov.execution_requests set status = 'claimed', claimed_by = p_executor, claimed_at = now() where id = e.id;
  update gov.approval_requests set status = 'executing' where id = e.request_id;
  perform gov.audit('executor', p_executor, t, 'execution.claim', 'gov.execution_requests', e.id::text, 'ok', null, null, null,
                    e.integration_code, e.payload_sha256, e.approval_id);
  return jsonb_build_object('ok', true, 'execution_id', e.id, 'action_type', e.action_type, 'target_ref', e.target_ref,
                            'integration_code', e.integration_code, 'idempotency_key', e.idempotency_key, 'payload', v.payload,
                            'payload_sha256', v.payload_sha256);
end $$;

create or replace function public.mos_executor_report(p_executor text, p_execution_id uuid, p_success boolean, p_dry_run boolean,
                                                      p_external_ref text default null, p_external_url text default null,
                                                      p_result jsonb default null, p_error text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare e gov.execution_requests; t text := 'mos_executor_report'; fails int;
begin
  select * into e from gov.execution_requests where id = p_execution_id for update;
  if not found or e.status <> 'claimed' or e.claimed_by is distinct from p_executor then
    return gov.refuse('executor', coalesce(p_executor, 'unknown'), t, 'execution.report', 'gov.execution_requests', p_execution_id::text,
                      'execution is not claimed by this executor');
  end if;
  insert into gov.execution_results (execution_request_id, outcome, dry_run, executor, external_ref, external_url, result, error)
  values (e.id, case when p_success then 'succeeded' else 'failed' end, p_dry_run, p_executor, p_external_ref, p_external_url, p_result, p_error);
  update gov.execution_requests set status = case when p_success then 'succeeded' else 'failed' end, finished_at = now() where id = e.id;
  update gov.approval_requests set status = case when p_success then 'executed' else 'failed' end where id = e.request_id;
  perform gov.audit('executor', p_executor, t, 'execution.' || case when p_success then 'succeeded' else 'failed' end,
                    'gov.execution_requests', e.id::text, case when p_success then 'ok' else 'error' end, p_error,
                    jsonb_build_object('dry_run', p_dry_run, 'external_ref', p_external_ref, 'result', p_result), null,
                    e.integration_code, e.payload_sha256, e.approval_id);
  if not p_success then
    perform gov.safety_event('executor_failure', 'warning', 'executor', p_executor, 'Execution failed: ' || coalesce(p_error, 'unknown'),
                             jsonb_build_object('execution_id', e.id));
    select count(*) into fails from gov.safety_events where kind = 'executor_failure' and occurred_at > now() - interval '1 hour';
    if fails >= 3 then perform gov.trip('monitor.safety', 'executor_failures', jsonb_build_object('failures_last_hour', fails)); end if;
  end if;
  return jsonb_build_object('ok', true, 'status', case when p_success then 'succeeded' else 'failed' end);
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Kill switches
-- -----------------------------------------------------------------------------------------------------

-- Disable: cancels queued work that the switch governs (risk-reducing pauses are kept).
create or replace function gov.disable_switch(p_key text, p_actor_type text, p_actor text, p_reason text, p_tripwire text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare old_state text; n int;
begin
  select state into old_state from gov.kill_switches where key = p_key for update;
  if not found then return gov.refuse(p_actor_type, p_actor, 'disable_switch', 'kill_switch.disable', 'gov.kill_switches', p_key, 'unknown kill switch'); end if;
  update gov.kill_switches set state = 'disabled', changed_by = p_actor, changed_at = now(), reason = p_reason, tripped_by = p_tripwire where key = p_key;
  with c as (
    update gov.execution_requests e set status = 'cancelled', status_reason = 'kill switch ' || p_key || ' disabled', finished_at = now()
      from gov.permission_registry p
     where p.action_type = e.action_type and e.status = 'queued' and not p.risk_reducing
       and (p_key in ('global','integration.external_writes') or p.kill_switch_key = p_key)
    returning 1)
  select count(*) into n from c;
  perform gov.audit(p_actor_type, p_actor, 'disable_switch', 'kill_switch.disable', 'gov.kill_switches', p_key, 'ok', p_reason,
                    jsonb_build_object('from', old_state, 'executions_cancelled', n, 'tripwire', p_tripwire));
  perform gov.safety_event(case when p_tripwire is null then 'kill_switch_disabled' else 'kill_switch_triggered' end,
                           case when p_tripwire is null then 'warning' else 'critical' end,
                           p_actor_type, p_actor,
                           'Kill switch ' || p_key || ' disabled' || coalesce(' by tripwire ' || p_tripwire, '') || ': ' || p_reason,
                           jsonb_build_object('executions_cancelled', n), p_key,
                           case when p_tripwire is not null or old_state = 'enabled' then 'kill_switch_triggered' end);
  return jsonb_build_object('ok', true, 'key', p_key, 'state', 'disabled', 'executions_cancelled', n);
end $$;

create or replace function public.mos_kill_switch_disable(p_key text, p_reason text default 'Disabled from the console')
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
begin
  if not gov.has_role('approver') then
    return gov.refuse('human', gov.actor(), 'mos_kill_switch_disable', 'kill_switch.disable', 'gov.kill_switches', p_key, 'approver role required', null, 'unauthorised_attempt');
  end if;
  return gov.disable_switch(p_key, 'human', gov.actor(), p_reason);
end $$;

create or replace function public.mos_kill_switch_disable_all(p_reason text default 'Stop everything')
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare k text; n int := 0;
begin
  if not gov.has_role('approver') then
    return gov.refuse('human', gov.actor(), 'mos_kill_switch_disable_all', 'kill_switch.disable_all', 'gov.kill_switches', 'all', 'approver role required', null, 'unauthorised_attempt');
  end if;
  for k in select key from gov.kill_switches where state = 'enabled' loop
    perform gov.disable_switch(k, 'human', gov.actor(), p_reason); n := n + 1;
  end loop;
  perform gov.audit('human', gov.actor(), 'mos_kill_switch_disable_all', 'kill_switch.disable_all', 'gov.kill_switches', 'all', 'ok', p_reason,
                    jsonb_build_object('switches_disabled', n));
  return jsonb_build_object('ok', true, 'switches_disabled', n);
end $$;

-- Enable: owner only, typed phrase, reason; paid switches require a confirmed daily cap.
create or replace function public.mos_kill_switch_enable(p_key text, p_reason text, p_typed_confirmation text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare who text := gov.actor(); old_state text; t text := 'mos_kill_switch_enable';
begin
  if not gov.has_role('owner') then
    return gov.refuse('human', who, t, 'kill_switch.enable', 'gov.kill_switches', p_key, 'owner role required', null, 'unauthorised_attempt');
  end if;
  if p_typed_confirmation is distinct from ('ENABLE ' || p_key) then
    return gov.refuse('human', who, t, 'kill_switch.enable', 'gov.kill_switches', p_key, 'type exactly: ENABLE ' || p_key);
  end if;
  if coalesce(trim(p_reason), '') = '' then
    return gov.refuse('human', who, t, 'kill_switch.enable', 'gov.kill_switches', p_key, 'a reason is required');
  end if;
  if p_key = 'organic.linkedin_adam' then
    return gov.refuse('human', who, t, 'kill_switch.enable', 'gov.kill_switches', p_key, 'Adam''s personal LinkedIn is never automated');
  end if;
  select state into old_state from gov.kill_switches where key = p_key for update;
  if not found then return gov.refuse('human', who, t, 'kill_switch.enable', 'gov.kill_switches', p_key, 'unknown kill switch'); end if;
  if p_key like 'paid.%' and not exists (
       select 1 from gov.budget_caps b where b.active and b.period = 'day' and b.platform_native_cap_confirmed
          and b.integration_code = replace(p_key, 'paid.', '')) then
    return gov.refuse('human', who, t, 'kill_switch.enable', 'gov.kill_switches', p_key,
                      'set a daily cap and confirm the platform''s own spending limit first');
  end if;
  perform set_config('mos.owner_enable', 'yes', true);
  update gov.kill_switches set state = 'enabled', changed_by = who, changed_at = now(), reason = p_reason, tripped_by = null where key = p_key;
  perform set_config('mos.owner_enable', '', true);
  perform gov.audit('human', who, t, 'kill_switch.enable', 'gov.kill_switches', p_key, 'ok', p_reason, jsonb_build_object('from', old_state));
  perform gov.safety_event('kill_switch_enabled', 'info', 'human', who, 'Kill switch ' || p_key || ' enabled: ' || p_reason, null, p_key);
  return jsonb_build_object('ok', true, 'key', p_key, 'state', 'enabled');
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Monitors (role mos_monitor only): disable and D4 pause. Never enable, resume, activate or increase.
-- -----------------------------------------------------------------------------------------------------

create or replace function gov.safety_pause(p_monitor text, p_action_type text, p_target_ref text, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare p gov.permission_registry; r gov.approval_requests; v gov.approval_versions; a gov.approvals; e gov.execution_requests; t text := 'safety_pause';
begin
  select * into p from gov.permission_registry where action_type = p_action_type;
  if p.action_type is null or not p.auto_safety_allowed or not p.risk_reducing
     or coalesce((select value from gov.configuration where key = 'safety.auto_pause_ads'), 'false'::jsonb) <> 'true'::jsonb then
    perform gov.safety_event('automatic_action_refused', 'critical', 'monitor', p_monitor,
                             'Automatic ' || coalesce(p_action_type, 'null') || ' refused: only PAUSE may be automatic (D4)',
                             jsonb_build_object('target', p_target_ref), null, 'approval_bypass_attempt');
    return gov.refuse('monitor', p_monitor, t, 'safety.pause', 'gov.permission_registry', p_action_type,
                      'automatic systems may only pause (D4)');
  end if;
  r := gov.create_request('monitor', p_monitor, p_action_type, p_target_ref, 'Safety pause: ' || p_target_ref, p_reason,
                          jsonb_build_object('action', 'pause', 'target', p_target_ref, 'reason', p_reason), 0, null);
  update gov.approval_requests set status = 'submitted' where id = r.id;
  select * into v from gov.approval_versions where request_id = r.id and version = 1;
  insert into gov.approvals (request_id, version, version_id, payload_sha256, action_type, integration_code, target_ref,
                             decision, actor_type, actor_email, actor_role, note, expires_at)
  values (r.id, 1, v.id, v.payload_sha256, p_action_type, r.integration_code, p_target_ref,
          'approve', 'policy', 'policy:D4-safety-pause', 'policy', p_reason, now() + interval '1 hour')
  returning * into a;
  update gov.approval_requests set status = 'approved' where id = r.id;
  insert into gov.execution_requests (request_id, approval_id, version, payload_sha256, action_type, integration_code, target_ref, idempotency_key, requested_by)
  values (r.id, a.id, 1, a.payload_sha256, p_action_type, r.integration_code, p_target_ref, a.nonce, p_monitor)
  returning * into e;
  perform gov.audit('policy', 'policy:D4-safety-pause', t, 'safety.pause', 'gov.execution_requests', e.id::text, 'ok', p_reason,
                    null, r.correlation_id, r.integration_code, a.payload_sha256, a.id, 'approve');
  perform gov.safety_event('automatic_pause_raised', 'critical', 'monitor', p_monitor, 'Automatic PAUSE raised for ' || p_target_ref || ': ' || p_reason,
                           jsonb_build_object('execution_id', e.id), p.kill_switch_key);
  return jsonb_build_object('ok', true, 'execution_id', e.id);
end $$;

create or replace function gov.trip(p_monitor text, p_tripwire text, p_detail jsonb default null, p_pause_targets text[] default '{}')
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare tw gov.tripwires; res jsonb; tgt text; paused int := 0; pause_type text;
begin
  select * into tw from gov.tripwires where code = p_tripwire and enabled;
  if not found then return gov.refuse('monitor', p_monitor, 'trip', 'kill_switch.trip', 'gov.tripwires', p_tripwire, 'unknown or disabled tripwire'); end if;
  res := gov.disable_switch(tw.kill_switch_key, 'monitor', p_monitor, 'Tripwire: ' || tw.description, tw.code);
  if tw.notify_kind <> 'kill_switch_triggered' then
    perform gov.safety_event(case tw.notify_kind when 'spend_cap_breach' then 'spend_cap_breach' when 'unknown_publishing' then 'unknown_publishing'
                                                 when 'audit_chain_failure' then 'audit_chain_failure' else 'unexpected_external_write' end,
                             'critical', 'monitor', p_monitor, tw.description, p_detail, tw.kill_switch_key, tw.notify_kind);
  end if;
  if tw.pause_ads then
    pause_type := replace(tw.kill_switch_key, 'paid.', '') || '.pause';
    foreach tgt in array coalesce(p_pause_targets, '{}') loop
      if (gov.safety_pause(p_monitor, pause_type, tgt, 'Tripwire ' || tw.code) ->> 'ok')::boolean then paused := paused + 1; end if;
    end loop;
  end if;
  return res || jsonb_build_object('tripwire', tw.code, 'pauses_raised', paused);
end $$;

create or replace function public.mos_monitor_trip(p_monitor text, p_tripwire text, p_detail jsonb default null, p_pause_targets text[] default '{}')
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
begin
  if not exists (select 1 from gov.service_identities where code = p_monitor and kind = 'monitor' and active) then
    return gov.refuse('monitor', coalesce(p_monitor, 'unknown'), 'mos_monitor_trip', 'kill_switch.trip', 'gov.tripwires', p_tripwire,
                      'not an active monitor identity', null, 'approval_bypass_attempt');
  end if;
  return gov.trip(p_monitor, p_tripwire, p_detail, p_pause_targets);
end $$;

create or replace function public.mos_monitor_safety_pause(p_monitor text, p_action_type text, p_target_ref text, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
begin
  if not exists (select 1 from gov.service_identities where code = p_monitor and kind = 'monitor' and active) then
    return gov.refuse('monitor', coalesce(p_monitor, 'unknown'), 'mos_monitor_safety_pause', 'safety.pause', 'gov.permission_registry', p_action_type,
                      'not an active monitor identity', null, 'approval_bypass_attempt');
  end if;
  return gov.safety_pause(p_monitor, p_action_type, p_target_ref, p_reason);
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Expiry and health (cron and console)
-- -----------------------------------------------------------------------------------------------------

create or replace function gov.expire_approvals()
returns int language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare n int;
begin
  with x as (
    update gov.approval_requests r set status = 'expired'
     where r.status = 'approved' and (gov.valid_approval(r.id)).id is null
       and not exists (select 1 from gov.approvals a where a.request_id = r.id and a.revoked_at is not null and a.version = r.current_version)
    returning r.id)
  select count(*) into n from x;
  update gov.execution_requests e set status = 'cancelled', status_reason = 'approval expired', finished_at = now()
   from gov.approvals a where a.id = e.approval_id and e.status = 'queued' and a.expires_at <= now();
  if n > 0 then
    perform gov.audit('system', 'cron', 'expire_approvals', 'approval.expire', 'gov.approval_requests', null, 'ok', n || ' approval(s) expired');
  end if;
  return n;
end $$;

create or replace function gov.run_health_checks(p_actor text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov, ops
as $$
declare out jsonb := '[]'::jsonb; bad bigint; n int; m int;
begin
  select bad_seq into bad from gov.verify_audit_chain();
  insert into ops.system_health (check_code, status, detail) values ('audit_chain', case when bad is null then 'ok' else 'fail' end,
         jsonb_build_object('first_bad_seq', bad, 'rows', (select count(*) from gov.audit_log)));
  if bad is not null and not exists (select 1 from gov.safety_events where kind = 'audit_chain_failure' and occurred_at > now() - interval '1 day') then
    perform gov.trip('monitor.health', 'audit_chain_broken', jsonb_build_object('first_bad_seq', bad));
  end if;

  select count(*) into n from pg_tables where schemaname in ('gov','ops') and not rowsecurity;
  insert into ops.system_health (check_code, status, detail) values ('rls_coverage', case when n = 0 then 'ok' else 'fail' end,
         jsonb_build_object('tables_without_rls', n, 'tables', (select count(*) from pg_tables where schemaname in ('gov','ops'))));

  select count(*) into n from pg_tables where schemaname = 'public';
  insert into ops.system_health (check_code, status, detail) values ('no_public_tables', case when n = 0 then 'ok' else 'warn' end,
         jsonb_build_object('public_tables', n));

  select count(*) into n from gov.kill_switches where state = 'enabled';
  insert into ops.system_health (check_code, status, detail) values ('kill_switches', 'ok', jsonb_build_object('enabled', n, 'total', (select count(*) from gov.kill_switches)));

  select count(*) into n from gov.integration_registry where status = 'read_write';
  select count(*) into m from gov.integration_registry where status = 'error';
  insert into ops.system_health (check_code, status, detail) values ('integrations', case when m > 0 then 'warn' else 'ok' end,
         jsonb_build_object('read_write', n, 'error', m));

  select count(*) into n from gov.notifications where status in ('pending','failed') and created_at < now() - interval '15 minutes' and not is_test;
  insert into ops.system_health (check_code, status, detail) values ('alert_backlog',
         case when n = 0 then 'ok' when coalesce((select value from gov.configuration where key = 'alerts.enabled'), 'false') = 'true'::jsonb then 'fail' else 'warn' end,
         jsonb_build_object('undelivered_over_15_min', n, 'dispatcher_enabled', (select value from gov.configuration where key = 'alerts.enabled')));

  delete from ops.system_health where checked_at < now() - interval '30 days';
  select jsonb_agg(jsonb_build_object('check', check_code, 'status', status, 'detail', detail, 'checked_at', checked_at) order by check_code)
    into out from (select distinct on (check_code) * from ops.system_health order by check_code, checked_at desc) h;
  perform gov.audit('system', p_actor, 'run_health_checks', 'health.check', 'ops.system_health', null, 'info', null,
                    jsonb_build_object('failing', (select count(*) from jsonb_array_elements(out) x where x ->> 'status' = 'fail')));
  return out;
end $$;

create or replace function public.mos_health_check()
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
begin
  if not gov.has_role('viewer') then
    return gov.refuse('human', gov.actor(), 'mos_health_check', 'health.check', 'ops.system_health', null, 'member role required', null, 'unauthorised_attempt');
  end if;
  return jsonb_build_object('ok', true, 'checks', gov.run_health_checks(gov.actor()));
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Alerts: test alert (owner) and dispatcher (role mos_dispatcher)
-- -----------------------------------------------------------------------------------------------------

create or replace function public.mos_queue_test_alert()
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare v uuid;
begin
  if not gov.has_role('owner') then
    return gov.refuse('human', gov.actor(), 'mos_queue_test_alert', 'alert.test', 'gov.notifications', null, 'owner role required', null, 'unauthorised_attempt');
  end if;
  insert into gov.notifications (kind, severity, subject, body, is_test)
  values ('test', 'info', '[TEST] NOYA Marketing OS alert channel',
          'This is a TEST of the NOYA Marketing OS critical-alert channel. No incident has occurred and no action is required.', true)
  returning id into v;
  perform gov.audit('human', gov.actor(), 'mos_queue_test_alert', 'alert.test', 'gov.notifications', v::text, 'ok');
  return jsonb_build_object('ok', true, 'notification_id', v);
end $$;

create or replace function public.mos_dispatcher_claim(p_dispatcher text, p_limit int default 10)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare owner_email text; rows jsonb;
begin
  if not exists (select 1 from gov.service_identities where code = p_dispatcher and kind = 'dispatcher' and active) then
    return gov.refuse('dispatcher', coalesce(p_dispatcher, 'unknown'), 'mos_dispatcher_claim', 'alert.claim', 'gov.notifications', null, 'not an active dispatcher');
  end if;
  if coalesce((select value from gov.configuration where key = 'alerts.enabled'), 'false') <> 'true'::jsonb then
    return jsonb_build_object('ok', true, 'notifications', '[]'::jsonb, 'note', 'alerts.enabled is false');
  end if;
  select email into owner_email from gov.members where role = 'owner' and active;
  with picked as (
    select id from gov.notifications where status in ('pending','failed') and attempts < 5
     order by (severity = 'critical') desc, created_at limit greatest(1, least(p_limit, 50)) for update skip locked),
  upd as (
    update gov.notifications n set status = 'sending', attempts = attempts + 1 from picked where n.id = picked.id returning n.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'subject', subject, 'body', body, 'severity', severity, 'is_test', is_test, 'to', owner_email)), '[]')
    into rows from upd;
  return jsonb_build_object('ok', true, 'notifications', rows);
end $$;

create or replace function public.mos_dispatcher_result(p_dispatcher text, p_notification_id uuid, p_sent boolean,
                                                        p_provider_message_id text default null, p_error text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
begin
  if not exists (select 1 from gov.service_identities where code = p_dispatcher and kind = 'dispatcher' and active) then
    return gov.refuse('dispatcher', coalesce(p_dispatcher, 'unknown'), 'mos_dispatcher_result', 'alert.result', 'gov.notifications', p_notification_id::text, 'not an active dispatcher');
  end if;
  update gov.notifications set status = case when p_sent then 'sent' else 'failed' end, provider_message_id = p_provider_message_id,
         last_error = p_error, sent_at = case when p_sent then now() end
   where id = p_notification_id and status = 'sending';
  if not found then
    return gov.refuse('dispatcher', p_dispatcher, 'mos_dispatcher_result', 'alert.result', 'gov.notifications', p_notification_id::text, 'notification is not being sent');
  end if;
  perform gov.audit('dispatcher', p_dispatcher, 'mos_dispatcher_result', case when p_sent then 'alert.sent' else 'alert.failed' end,
                    'gov.notifications', p_notification_id::text, case when p_sent then 'ok' else 'error' end, p_error,
                    jsonb_build_object('provider_message_id', p_provider_message_id));
  return jsonb_build_object('ok', true);
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Agent runs (role mos_agent) and safety acknowledgement (owner)
-- -----------------------------------------------------------------------------------------------------

create or replace function public.mos_agent_run_start(p_agent text, p_trigger text default 'schedule')
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov, ops
as $$
declare a ops.agents; v uuid;
begin
  select * into a from ops.agents where code = p_agent;
  if a.code is null then
    return gov.refuse('agent', coalesce(p_agent, 'unknown'), 'mos_agent_run_start', 'agent.run', 'ops.agent_runs', null, 'unknown agent');
  end if;
  insert into ops.agent_runs (agent_code, trigger, status, finished_at, summary)
  values (p_agent, p_trigger, case when a.enabled then 'running' else 'skipped_paused' end,
          case when a.enabled then null else now() end, case when a.enabled then null else a.paused_reason end)
  returning id into v;
  return jsonb_build_object('ok', a.enabled, 'run_id', v, 'reason', case when a.enabled then null else 'agent disabled: ' || coalesce(a.paused_reason, '') end);
end $$;

create or replace function public.mos_agent_run_finish(p_agent text, p_run_id uuid, p_status text, p_summary text,
                                                       p_tokens_in int default null, p_tokens_out int default null,
                                                       p_cost_usd numeric default null, p_error text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov, ops
as $$
begin
  update ops.agent_runs set status = p_status, summary = p_summary, tokens_in = p_tokens_in, tokens_out = p_tokens_out,
         cost_usd = p_cost_usd, error = p_error, finished_at = now()
   where id = p_run_id and agent_code = p_agent and status = 'running' and p_status in ('succeeded','failed','skipped_budget');
  if not found then
    return gov.refuse('agent', coalesce(p_agent, 'unknown'), 'mos_agent_run_finish', 'agent.run', 'ops.agent_runs', p_run_id::text, 'run is not running for this agent');
  end if;
  perform gov.audit('agent', p_agent, 'mos_agent_run_finish', 'agent.run.' || p_status, 'ops.agent_runs', p_run_id::text,
                    case when p_status = 'failed' then 'error' else 'ok' end, p_error, jsonb_build_object('cost_usd', p_cost_usd));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.mos_acknowledge_safety_event(p_event_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov
as $$
begin
  if not gov.has_role('owner') then
    return gov.refuse('human', gov.actor(), 'mos_acknowledge_safety_event', 'safety.acknowledge', 'gov.safety_events', p_event_id::text, 'owner role required', null, 'unauthorised_attempt');
  end if;
  update gov.safety_events set acknowledged_at = now(), acknowledged_by = gov.actor() where id = p_event_id and acknowledged_at is null;
  if not found then
    return gov.refuse('human', gov.actor(), 'mos_acknowledge_safety_event', 'safety.acknowledge', 'gov.safety_events', p_event_id::text, 'not found or already acknowledged');
  end if;
  perform gov.audit('human', gov.actor(), 'mos_acknowledge_safety_event', 'safety.acknowledge', 'gov.safety_events', p_event_id::text, 'ok');
  return jsonb_build_object('ok', true);
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Console snapshot (read-only, members only)
-- -----------------------------------------------------------------------------------------------------

create or replace function public.mos_console_snapshot()
returns jsonb language plpgsql security definer set search_path = pg_catalog, gov, ops
as $$
declare role text := gov.current_member_role();
begin
  if gov.role_rank(role) < gov.role_rank('viewer') then
    return gov.refuse('human', gov.actor(), 'mos_console_snapshot', 'console.read', 'console', null, 'not a Marketing OS member', null, 'unauthorised_attempt');
  end if;
  return jsonb_build_object(
    'ok', true,
    'generated_at', now(),
    'viewer', jsonb_build_object('email', gov.actor(), 'role', role),
    'system', jsonb_build_object(
       'product', (select value from gov.configuration where key = 'product'),
       'phase', (select value from gov.configuration where key = 'phase'),
       'external_execution', case when gov.switches_allow(null) then 'ARMED' else 'DISABLED' end,
       'open_critical', (select count(*) from gov.safety_events where severity = 'critical' and acknowledged_at is null),
       'pending_approvals', (select count(*) from gov.approval_requests where status in ('submitted','approved'))),
    'kill_switches', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'scope', scope, 'label', label, 'state', state,
                        'changed_by', changed_by, 'changed_at', changed_at, 'reason', reason, 'tripped_by', tripped_by)
                        order by case scope when 'global' then 0 when 'integration' then 1 when 'organic' then 2 else 3 end, key), '[]') from gov.kill_switches),
    'pending_approvals', (select coalesce(jsonb_agg(x order by x->>'updated_at' desc), '[]') from (
        select jsonb_build_object('id', r.id, 'title', r.title, 'action_type', r.action_type, 'target', r.target_ref, 'status', r.status,
               'version', r.current_version, 'requested_by', r.requested_by, 'updated_at', r.updated_at,
               'payload_sha256', (select payload_sha256 from gov.approval_versions v where v.request_id = r.id and v.version = r.current_version),
               'expires_at', (gov.valid_approval(r.id)).expires_at) x
          from gov.approval_requests r where r.status in ('draft','submitted','approved') order by r.updated_at desc limit 50) q),
    'audit', (select coalesce(jsonb_agg(x order by (x->>'seq')::bigint desc), '[]') from (
        select jsonb_build_object('seq', seq, 'at', occurred_at, 'actor_type', actor_type, 'actor', actor_id, 'tool', tool, 'action', action,
               'target', target_type || coalesce(':' || target_id, ''), 'platform', target_platform, 'result', result, 'reason', reason,
               'payload_sha256', payload_sha256, 'correlation_id', correlation_id) x
          from gov.audit_log order by seq desc limit 40) q),
    'audit_chain', jsonb_build_object('rows', (select count(*) from gov.audit_log), 'first_bad_seq', (select bad_seq from gov.verify_audit_chain())),
    'integrations', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'category', category, 'status', status,
                        'phase', phase, 'verified_at', verified_at, 'credential_ref', credential_ref, 'notes', notes) order by phase, code), '[]') from gov.integration_registry),
    'health', (select coalesce(jsonb_agg(jsonb_build_object('check', check_code, 'status', status, 'detail', detail, 'checked_at', checked_at) order by check_code), '[]')
                 from (select distinct on (check_code) * from ops.system_health order by check_code, checked_at desc) h),
    'agents', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'enabled', enabled, 'paused_reason', paused_reason, 'schedule', schedule) order by name), '[]') from ops.agents),
    'agent_runs', (select coalesce(jsonb_agg(x order by x->>'started_at' desc), '[]') from (
        select jsonb_build_object('agent', agent_code, 'started_at', started_at, 'status', status, 'summary', summary, 'cost_usd', cost_usd) x
          from ops.agent_runs order by started_at desc limit 20) q),
    'security', (select coalesce(jsonb_agg(x order by x->>'at' desc), '[]') from (
        select jsonb_build_object('id', id, 'at', occurred_at, 'kind', kind, 'severity', severity, 'source', source_type || ':' || source_id,
               'summary', summary, 'acknowledged', acknowledged_at is not null) x
          from gov.safety_events order by occurred_at desc limit 30) q),
    'notifications', (select coalesce(jsonb_agg(x order by x->>'at' desc), '[]') from (
        select jsonb_build_object('at', created_at, 'kind', kind, 'severity', severity, 'subject', subject, 'status', status, 'is_test', is_test) x
          from gov.notifications order by created_at desc limit 15) q),
    'configuration', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'value', value, 'description', description) order by key), '[]') from gov.configuration),
    'secrets', (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'stored_in', stored_in, 'access', access, 'integration', integration_code, 'is_set', is_set) order by name), '[]') from gov.secrets_registry)
  );
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Lockdown
-- -----------------------------------------------------------------------------------------------------

do $$
declare t record; f record;
begin
  for t in select schemaname, tablename from pg_tables where schemaname in ('gov','ops') loop
    execute format('alter table %I.%I enable row level security', t.schemaname, t.tablename);
    execute format('alter table %I.%I force row level security', t.schemaname, t.tablename);
    execute format('revoke all on %I.%I from public', t.schemaname, t.tablename);
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('revoke all on %I.%I from anon, authenticated, service_role', t.schemaname, t.tablename);
    end if;
    execute format('revoke all on %I.%I from mos_agent, mos_executor, mos_monitor, mos_dispatcher', t.schemaname, t.tablename);
  end loop;
  for f in select p.oid::regprocedure as sig, n.nspname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('gov','ops') or (n.nspname = 'public' and p.proname like 'mos\_%') loop
    execute format('revoke all on function %s from public', f.sig);
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('revoke all on function %s from anon, authenticated, service_role', f.sig);
    end if;
  end loop;
end $$;

-- FORCE RLS applies to the table owner too; SECURITY DEFINER functions run as the owner, so give the owner
-- (and only the owner) a permissive policy. No other role has privileges on these tables at all.
do $$
declare t record;
begin
  for t in select schemaname, tablename, tableowner from pg_tables where schemaname in ('gov','ops') loop
    execute format('create policy owner_only on %I.%I to %I using (true) with check (true)', t.schemaname, t.tablename, t.tableowner);
  end loop;
end $$;

grant execute on function public.mos_create_draft(text, text, text, text, jsonb, bigint, text) to authenticated;
grant execute on function public.mos_edit_draft(uuid, jsonb, text)                              to authenticated;
grant execute on function public.mos_submit(uuid)                                               to authenticated;
grant execute on function public.mos_decide(uuid, int, text, text, text)                        to authenticated;
grant execute on function public.mos_revoke_approval(uuid, text)                                to authenticated;
grant execute on function public.mos_request_execution(uuid)                                    to authenticated;
grant execute on function public.mos_kill_switch_disable(text, text)                            to authenticated;
grant execute on function public.mos_kill_switch_disable_all(text)                              to authenticated;
grant execute on function public.mos_kill_switch_enable(text, text, text)                       to authenticated;
grant execute on function public.mos_health_check()                                             to authenticated;
grant execute on function public.mos_queue_test_alert()                                         to authenticated;
grant execute on function public.mos_acknowledge_safety_event(uuid)                             to authenticated;
grant execute on function public.mos_console_snapshot()                                         to authenticated;

grant execute on function public.mos_agent_propose(text, text, text, text, text, jsonb, boolean) to mos_agent;
grant execute on function public.mos_agent_run_start(text, text)                                 to mos_agent;
grant execute on function public.mos_agent_run_finish(text, uuid, text, text, int, int, numeric, text) to mos_agent;
grant execute on function public.mos_executor_claim(text, uuid)                                  to mos_executor;
grant execute on function public.mos_executor_report(text, uuid, boolean, boolean, text, text, jsonb, text) to mos_executor;
grant execute on function public.mos_monitor_trip(text, text, jsonb, text[])                     to mos_monitor;
grant execute on function public.mos_monitor_safety_pause(text, text, text, text)                to mos_monitor;
grant execute on function public.mos_dispatcher_claim(text, int)                                 to mos_dispatcher;
grant execute on function public.mos_dispatcher_result(text, uuid, boolean, text, text)          to mos_dispatcher;
grant usage on schema public to mos_agent, mos_executor, mos_monitor, mos_dispatcher;

-- -----------------------------------------------------------------------------------------------------
-- Schedules (pg_cron on Supabase; skipped where unavailable, e.g. local checks)
-- -----------------------------------------------------------------------------------------------------

do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron unavailable here (%); schedules not created', sqlerrm;
  end;
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.schedule('mos-expire-approvals', '*/15 * * * *', 'select gov.expire_approvals()');
    perform cron.schedule('mos-health-checks', '7 * * * *', 'select gov.run_health_checks(''cron'')');
  end if;
end $$;

-- Initial health snapshot.
do $$ begin perform gov.run_health_checks('migration'); end $$;
