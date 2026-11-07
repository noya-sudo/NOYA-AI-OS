-- =====================================================================================================
-- NOYA Marketing OS — Phase 1 / migration 2: approval engine, safety, notifications, operations
--
-- DRAFT -> SUBMITTED -> APPROVED -> EXECUTED
--   * Every edit creates an immutable version. An edit after submission/approval invalidates the approval.
--   * An approval is bound to: request, version, payload SHA-256, actor, target platform, action type,
--     decided_at, expires_at, and a single-use nonce.
--   * Execution needs a valid approval, enabled kill switches, a verified read_write integration, an allowed
--     executor, and (for money) a confirmed cap. One approval = at most one execution (replay-proof).
-- =====================================================================================================

-- -----------------------------------------------------------------------------------------------------
-- Approval requests and immutable versions
-- -----------------------------------------------------------------------------------------------------

create table gov.approval_requests (
  id                 uuid primary key default gen_random_uuid(),
  action_type        text not null references gov.permission_registry(action_type),
  integration_code   text not null references gov.integration_registry(code),
  target_ref         text not null,                 -- account handle, campaign id, HQ, ...
  title              text not null,
  rationale          text not null,
  status             text not null default 'draft' check (status in
                       ('draft','submitted','approved','executing','executed','failed','rejected','revoked','expired','cancelled')),
  current_version    int not null default 0,
  spend_delta_minor  bigint not null default 0,
  currency           text check (currency is null or currency ~ '^[A-Z]{3}$'),
  requested_by_type  text not null check (requested_by_type in ('human','agent','monitor')),
  requested_by       text not null,
  correlation_id     uuid not null default gen_random_uuid(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index approval_requests_status on gov.approval_requests (status, updated_at desc);

create table gov.approval_versions (
  id                uuid primary key default gen_random_uuid(),
  request_id        uuid not null references gov.approval_requests(id),
  version           int not null check (version >= 1),
  payload           jsonb not null,
  payload_sha256    text not null,
  action_type       text not null,
  integration_code  text not null,
  target_ref        text not null,
  created_by_type   text not null,
  created_by        text not null,
  note              text,
  created_at        timestamptz not null default now(),
  unique (request_id, version)
);

create or replace function gov.approval_versions_hash()
returns trigger language plpgsql set search_path = pg_catalog, gov
as $$ begin new.payload_sha256 := gov.sha256_jsonb(new.payload); return new; end $$;
create trigger approval_versions_hash before insert on gov.approval_versions for each row execute function gov.approval_versions_hash();
create trigger approval_versions_immutable before update or delete on gov.approval_versions for each row execute function gov.immutable_row();

-- Status machine and frozen fields.
create or replace function gov.approval_requests_guard()
returns trigger language plpgsql set search_path = pg_catalog, gov
as $$
declare ok boolean;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then raise exception 'a request starts as draft'; end if;
    return new;
  end if;
  if new.action_type is distinct from old.action_type or new.integration_code is distinct from old.integration_code
     or new.requested_by is distinct from old.requested_by or new.correlation_id is distinct from old.correlation_id then
    raise exception 'identity fields of request % are frozen', old.id using errcode = '42501';
  end if;
  if new.status is distinct from old.status then
    ok := case old.status
      when 'draft'     then new.status in ('submitted','cancelled')
      when 'submitted' then new.status in ('approved','rejected','draft','cancelled')
      when 'approved'  then new.status in ('executing','draft','revoked','expired','cancelled')
      when 'executing' then new.status in ('executed','failed')
      when 'revoked'   then new.status in ('draft','cancelled')
      when 'expired'   then new.status in ('draft','cancelled')
      when 'rejected'  then new.status in ('draft','cancelled')
      else false end;   -- executed, failed, cancelled are terminal
    if not ok then
      raise exception 'illegal status change % -> % on request %', old.status, new.status, old.id using errcode = '42501';
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger approval_requests_guard before insert or update on gov.approval_requests
  for each row execute function gov.approval_requests_guard();
create trigger approval_requests_no_delete before delete on gov.approval_requests for each row execute function gov.immutable_row();

-- -----------------------------------------------------------------------------------------------------
-- Approvals (decisions). Only revocation / invalidation may be written afterwards, once.
-- -----------------------------------------------------------------------------------------------------

create table gov.approvals (
  id                  uuid primary key default gen_random_uuid(),
  request_id          uuid not null references gov.approval_requests(id),
  version             int not null,
  version_id          uuid not null references gov.approval_versions(id),
  payload_sha256      text not null,
  action_type         text not null,
  integration_code    text not null,
  target_ref          text not null,
  decision            text not null check (decision in ('approve','reject')),
  actor_type          text not null check (actor_type in ('human','policy')),
  actor_user_id       uuid,
  actor_email         text not null,
  actor_role          text not null,
  note                text,
  decided_at          timestamptz not null default now(),
  expires_at          timestamptz not null,
  nonce               uuid not null default gen_random_uuid() unique,
  revoked_at          timestamptz,
  revoked_by          text,
  revoke_reason       text,
  invalidated_at      timestamptz,
  invalidated_reason  text,
  check (actor_type = 'human' or (decision = 'approve' and actor_email like 'policy:%'))
);
create index approvals_request on gov.approvals (request_id, decided_at desc);

create or replace function gov.approvals_guard()
returns trigger language plpgsql set search_path = pg_catalog, gov
as $$
begin
  if tg_op = 'DELETE' then raise exception 'approvals are never deleted' using errcode = '42501'; end if;
  if (to_jsonb(new) - array['revoked_at','revoked_by','revoke_reason','invalidated_at','invalidated_reason'])
     is distinct from (to_jsonb(old) - array['revoked_at','revoked_by','revoke_reason','invalidated_at','invalidated_reason']) then
    raise exception 'an approval decision cannot be changed' using errcode = '42501';
  end if;
  if (old.revoked_at is not null and new.revoked_at is distinct from old.revoked_at)
     or (old.invalidated_at is not null and new.invalidated_at is distinct from old.invalidated_at) then
    raise exception 'revocation / invalidation is final' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger approvals_guard before update or delete on gov.approvals for each row execute function gov.approvals_guard();

-- The single valid approval for a request's CURRENT version, or nothing.
create or replace function gov.valid_approval(p_request_id uuid)
returns gov.approvals language sql stable security definer set search_path = pg_catalog, gov
as $$
  select a.* from gov.approvals a
  join gov.approval_requests r on r.id = a.request_id
  join gov.approval_versions v on v.id = a.version_id
  where a.request_id = p_request_id
    and a.decision = 'approve'
    and a.version = r.current_version
    and v.version = r.current_version
    and a.payload_sha256 = v.payload_sha256
    and v.payload_sha256 = gov.sha256_jsonb(v.payload)
    and a.action_type = r.action_type and a.integration_code = r.integration_code and a.target_ref = v.target_ref
    and a.revoked_at is null and a.invalidated_at is null
    and a.expires_at > now()
  order by a.decided_at desc
  limit 1
$$;

-- -----------------------------------------------------------------------------------------------------
-- Execution requests and results
-- -----------------------------------------------------------------------------------------------------

create table gov.execution_requests (
  id                uuid primary key default gen_random_uuid(),
  request_id        uuid not null references gov.approval_requests(id),
  approval_id       uuid not null unique references gov.approvals(id),   -- one approval, one execution: no replay
  version           int not null,
  payload_sha256    text not null,
  action_type       text not null,
  integration_code  text not null,
  target_ref        text not null,
  idempotency_key   uuid not null unique,                                -- the approval nonce, passed to the platform
  status            text not null default 'queued' check (status in ('queued','claimed','succeeded','failed','refused','cancelled')),
  requested_by      text not null,
  requested_at      timestamptz not null default now(),
  claimed_by        text,
  claimed_at        timestamptz,
  finished_at       timestamptz,
  status_reason     text
);
create index execution_requests_status on gov.execution_requests (status, requested_at);
create unique index execution_requests_one_live_per_request on gov.execution_requests (request_id)
  where status in ('queued','claimed','succeeded');

create or replace function gov.execution_requests_guard()
returns trigger language plpgsql set search_path = pg_catalog, gov
as $$
declare ok boolean;
begin
  if tg_op = 'DELETE' then raise exception 'execution requests are never deleted' using errcode = '42501'; end if;
  if (to_jsonb(new) - array['status','claimed_by','claimed_at','finished_at','status_reason'])
     is distinct from (to_jsonb(old) - array['status','claimed_by','claimed_at','finished_at','status_reason']) then
    raise exception 'execution request % is frozen', old.id using errcode = '42501';
  end if;
  if new.status is distinct from old.status then
    ok := case old.status
      when 'queued'  then new.status in ('claimed','refused','cancelled')
      when 'claimed' then new.status in ('succeeded','failed')
      else false end;
    if not ok then
      raise exception 'illegal execution status % -> %', old.status, new.status using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger execution_requests_guard before update or delete on gov.execution_requests
  for each row execute function gov.execution_requests_guard();

create table gov.execution_results (
  id                    uuid primary key default gen_random_uuid(),
  execution_request_id  uuid not null references gov.execution_requests(id),
  outcome               text not null check (outcome in ('succeeded','failed')),
  dry_run               boolean not null,
  executor              text not null,
  external_ref          text,
  external_url          text,
  result                jsonb,
  error                 text,
  recorded_at           timestamptz not null default now()
);
create unique index execution_results_one_per_request on gov.execution_results (execution_request_id);

create or replace function gov.execution_results_redact()
returns trigger language plpgsql set search_path = pg_catalog, gov
as $$ begin new.result := gov.redact(new.result); return new; end $$;
create trigger execution_results_redact before insert on gov.execution_results for each row execute function gov.execution_results_redact();
create trigger execution_results_immutable before update or delete on gov.execution_results for each row execute function gov.immutable_row();

-- -----------------------------------------------------------------------------------------------------
-- The gate
-- -----------------------------------------------------------------------------------------------------

-- Everything except the execution row itself: used before queuing and again at claim.
create or replace function gov.gate(p_request_id uuid)
returns table (ok boolean, reason text, approval_id uuid) language plpgsql stable security definer set search_path = pg_catalog, gov
as $$
declare
  r   gov.approval_requests;
  p   gov.permission_registry;
  a   gov.approvals;
  i   gov.integration_registry;
  cap bigint;
begin
  select * into r from gov.approval_requests where id = p_request_id;
  if not found then ok := false; reason := 'request not found'; return next; return; end if;
  select * into p from gov.permission_registry where action_type = r.action_type;
  if not found then ok := false; reason := 'action type not registered (fail-closed)'; return next; return; end if;

  a := gov.valid_approval(r.id);
  if a.id is null then
    ok := false;
    reason := case
      when exists (select 1 from gov.approvals x where x.request_id = r.id and x.revoked_at is not null and x.version = r.current_version) then 'approval revoked'
      when exists (select 1 from gov.approvals x where x.request_id = r.id and x.version = r.current_version and x.decision = 'approve' and x.expires_at <= now()) then 'approval expired'
      when exists (select 1 from gov.approvals x where x.request_id = r.id and x.invalidated_at is not null) then 'approval invalidated by an edit'
      else 'no valid approval for the current version' end;
    return next; return;
  end if;
  approval_id := a.id;

  -- Policy approvals exist only for D4 safety pauses.
  if a.actor_type = 'policy' and not p.auto_safety_allowed then
    ok := false; reason := 'automatic approval not allowed for ' || r.action_type; return next; return;
  end if;
  if a.actor_type = 'human' and gov.role_rank(a.actor_role) < gov.role_rank(p.min_approver_role) then
    ok := false; reason := 'approver role below ' || p.min_approver_role; return next; return;
  end if;
  if p.mode = 'blocked' and not (a.actor_type = 'policy' and p.auto_safety_allowed) then
    ok := false; reason := 'permission blocks ' || r.action_type; return next; return;
  end if;
  if r.status not in ('approved','executing') then
    ok := false; reason := 'request is ' || r.status; return next; return;
  end if;

  -- Kill switches. Risk-reducing actions (pause, lower budget, hide) are never blocked by a disabled switch.
  if not p.risk_reducing and not gov.switches_allow(p.kill_switch_key) then
    ok := false; reason := 'kill switch disabled (global, integration.external_writes or ' || p.kill_switch_key || ')';
    return next; return;
  end if;

  select * into i from gov.integration_registry where code = r.integration_code;
  if i.status <> 'read_write' then
    ok := false; reason := 'integration ' || r.integration_code || ' is ' || i.status || ', not read_write'; return next; return;
  end if;

  if p.moves_money then
    select cap_minor into cap from gov.budget_caps
     where integration_code = r.integration_code and period = 'day' and active and platform_native_cap_confirmed;
    if cap is null then ok := false; reason := 'no confirmed daily cap'; return next; return; end if;
    if r.spend_delta_minor > cap then ok := false; reason := 'spend change exceeds the daily cap'; return next; return; end if;
  end if;

  ok := true; reason := 'all gates passed'; return next;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Safety events and notifications (Resend outbox)
-- -----------------------------------------------------------------------------------------------------

create table gov.safety_events (
  id               uuid primary key default gen_random_uuid(),
  occurred_at      timestamptz not null default now(),
  kind             text not null check (kind in (
                     'kill_switch_disabled','kill_switch_enabled','kill_switch_triggered','automatic_pause_raised',
                     'automatic_action_refused','approval_bypass_attempt','unauthorised_attempt','unexpected_external_write',
                     'unknown_publishing','spend_cap_breach','audit_chain_failure','executor_failure','health_check_failed')),
  severity         text not null check (severity in ('critical','warning','info')),
  source_type      text not null,
  source_id        text not null,
  summary          text not null,
  detail           jsonb,
  kill_switch_key  text references gov.kill_switches(key),
  acknowledged_at  timestamptz,
  acknowledged_by  text
);
create index safety_events_recent on gov.safety_events (occurred_at desc);
create index safety_events_open on gov.safety_events (severity) where acknowledged_at is null;

create or replace function gov.safety_events_guard()
returns trigger language plpgsql set search_path = pg_catalog, gov
as $$
begin
  if tg_op = 'DELETE' then raise exception 'safety events are never deleted' using errcode = '42501'; end if;
  if (to_jsonb(new) - array['acknowledged_at','acknowledged_by']) is distinct from (to_jsonb(old) - array['acknowledged_at','acknowledged_by']) then
    raise exception 'safety events are immutable except acknowledgement' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger safety_events_guard before update or delete on gov.safety_events for each row execute function gov.safety_events_guard();

create table gov.notifications (
  id                   uuid primary key default gen_random_uuid(),
  created_at           timestamptz not null default now(),
  kind                 text not null check (kind in ('kill_switch_triggered','unexpected_external_write','approval_bypass_attempt',
                                                     'audit_chain_failure','spend_cap_breach','unknown_publishing','test')),
  severity             text not null check (severity in ('critical','warning','info')),
  subject              text not null,
  body                 text not null,
  recipient            text not null default 'owner' check (recipient = 'owner'),   -- resolved at send time; no addresses stored
  is_test              boolean not null default false,
  status               text not null default 'pending' check (status in ('pending','sending','sent','failed','suppressed')),
  attempts             int not null default 0,
  provider             text not null default 'resend',
  provider_message_id  text,
  last_error           text,
  sent_at              timestamptz,
  safety_event_id      uuid references gov.safety_events(id),
  check (not is_test or subject like '[TEST]%'),
  check (is_test or kind <> 'test')
);
create index notifications_pending on gov.notifications (created_at) where status in ('pending','failed');

create or replace function gov.safety_event(p_kind text, p_severity text, p_source_type text, p_source_id text, p_summary text,
                                            p_detail jsonb default null, p_switch text default null, p_notify text default null)
returns uuid language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare v uuid;
begin
  insert into gov.safety_events (kind, severity, source_type, source_id, summary, detail, kill_switch_key)
  values (p_kind, p_severity, p_source_type, p_source_id, p_summary, gov.redact(p_detail), p_switch)
  returning id into v;
  if p_notify is not null then
    insert into gov.notifications (kind, severity, subject, body, safety_event_id)
    values (p_notify, p_severity,
            '[NOYA Marketing OS] ' || upper(p_severity) || ': ' || p_summary,
            p_summary || E'\n\nSource: ' || p_source_type || ' / ' || p_source_id ||
            E'\nWhen: ' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS "UTC"') ||
            E'\nEvent: ' || v::text || E'\n\nOpen the Marketing OS console for details. No action has been resumed automatically.',
            v);
  end if;
  return v;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- Tripwires (monitors) — can only disable / pause
-- -----------------------------------------------------------------------------------------------------

create table gov.tripwires (
  code             text primary key,
  description      text not null,
  kill_switch_key  text not null references gov.kill_switches(key),
  notify_kind      text not null,
  pause_ads        boolean not null default false,      -- D4: also raise automatic PAUSE requests
  enabled          boolean not null default true
);
insert into gov.tripwires (code, description, kill_switch_key, notify_kind, pause_ads) values
  ('meta_spend_over_daily_cap',     'Meta spend today reached the daily cap',                       'paid.meta_ads',               'spend_cap_breach',          true),
  ('meta_spend_velocity',           'Over 40% of the Meta daily cap spent within one hour',         'paid.meta_ads',               'spend_cap_breach',          true),
  ('meta_unknown_change',           'A Meta campaign / budget changed with no matching request',    'paid.meta_ads',               'unexpected_external_write', true),
  ('linkedin_spend_over_daily_cap', 'LinkedIn Ads spend today reached the daily cap',               'paid.linkedin_ads',           'spend_cap_breach',          true),
  ('unknown_publication',           'A post appeared on a NOYA account that Marketing OS did not record', 'global',                'unknown_publishing',        false),
  ('unexpected_external_write',     'An external write happened without a matching execution',     'integration.external_writes', 'unexpected_external_write', false),
  ('executor_failures',             'Three or more executor failures within one hour',              'global',                      'kill_switch_triggered',     false),
  ('audit_chain_broken',            'Audit chain verification failed',                              'global',                      'audit_chain_failure',       false),
  ('token_scope_changed',           'A platform token gained scopes it was not registered with',    'global',                      'kill_switch_triggered',     false);

-- -----------------------------------------------------------------------------------------------------
-- Operations: agents, agent runs, system health
-- -----------------------------------------------------------------------------------------------------

create table ops.agents (
  code                text primary key references gov.service_identities(code),
  name                text not null,
  department          text not null,
  purpose             text not null,
  model_tier          text not null check (model_tier in ('economy','standard','premium')),
  schedule            text,
  daily_cost_cap_usd  numeric(8,2) not null default 1.00,
  enabled             boolean not null default false,
  paused_reason       text default 'Not built yet (Phase 1)',
  created_at          timestamptz not null default now()
);

create table ops.agent_runs (
  id              uuid primary key default gen_random_uuid(),
  agent_code      text not null references gov.service_identities(code),
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  status          text not null default 'running' check (status in ('running','succeeded','failed','skipped_budget','skipped_paused')),
  trigger         text not null check (trigger in ('schedule','manual','event','test')),
  summary         text,
  output_refs     jsonb not null default '[]'::jsonb,
  tokens_in       int,
  tokens_out      int,
  cost_usd        numeric(10,4),
  error           text,
  correlation_id  uuid not null default gen_random_uuid()
);
create index agent_runs_recent on ops.agent_runs (started_at desc);

create table ops.system_health (
  id          uuid primary key default gen_random_uuid(),
  check_code  text not null,
  status      text not null check (status in ('ok','warn','fail')),
  detail      jsonb,
  checked_at  timestamptz not null default now()
);
create index system_health_recent on ops.system_health (check_code, checked_at desc);

-- Seed identities (all inactive except where stated). Agents never get may_execute (check constraint).
insert into gov.service_identities (code, kind, description, may_request, may_execute, active) values
  ('agent.content_strategist', 'agent',      'Plans and drafts organic content',             '{instagram.publish_media,instagram.publish_story,linkedin_noya.publish_post}', '{}', false),
  ('agent.community_triage',   'agent',      'Classifies comments / DMs, drafts replies',    '{instagram.reply_comment,instagram.send_dm,instagram.hide_comment,linkedin_noya.reply_comment}', '{}', false),
  ('agent.paid_media_analyst', 'agent',      'Proposes plans and risk-reducing ad changes',  '{meta_ads.create_paused,meta_ads.pause,meta_ads.decrease_budget,linkedin_ads.create_paused,linkedin_ads.pause,linkedin_ads.decrease_budget}', '{}', false),
  ('agent.lead_qualifier',     'agent',      'Qualifies leads, prepares HQ hand-offs',       '{hq.handoff_opportunity}', '{}', false),
  ('agent.brand_guardian',     'agent',      'Checks drafts against brand rules',            '{}', '{}', false),
  ('agent.intelligence',       'agent',      'Signals and research',                         '{}', '{}', false),
  ('agent.analytics',          'agent',      'Analytics and attribution',                    '{}', '{}', false),
  ('executor.publisher',       'executor',   'Publishes approved organic posts (Phase 7)',   '{}', '{instagram.publish_media,instagram.publish_story,instagram.delete_media,linkedin_noya.publish_post}', false),
  ('executor.engagement',      'executor',   'Sends approved replies (Phase 7)',             '{}', '{instagram.reply_comment,instagram.send_dm,instagram.hide_comment,linkedin_noya.reply_comment}', false),
  ('executor.ads',             'executor',   'Runs approved ad changes (Phase 8)',           '{}', '{meta_ads.create_paused,meta_ads.activate,meta_ads.increase_budget,meta_ads.edit_targeting,meta_ads.decrease_budget,meta_ads.pause,linkedin_ads.create_paused,linkedin_ads.activate,linkedin_ads.increase_budget,linkedin_ads.decrease_budget,linkedin_ads.pause}', false),
  ('executor.hq_courier',      'executor',   'Delivers approved hand-offs to HQ (Phase 6)',  '{}', '{hq.handoff_opportunity}', false),
  ('monitor.safety',           'monitor',    'Evaluates tripwires; can only disable / pause','{}', '{}', true),
  ('monitor.health',           'monitor',    'Scheduled health checks',                      '{}', '{}', true),
  ('dispatcher.resend',        'dispatcher', 'Sends critical alerts via Resend',             '{}', '{}', false);

insert into ops.agents (code, name, department, purpose, model_tier, schedule) values
  ('agent.brand_guardian',     'Brand Guardian',          'brand',        'Voice, claims, rights checks',           'economy',  null),
  ('agent.intelligence',       'Intelligence Analyst',    'intelligence', 'Signals and research briefs',            'standard', 'daily 07:00'),
  ('agent.content_strategist', 'Content Strategist',      'content',      'Calendar and drafts',                    'standard', 'weekly Mon'),
  ('agent.community_triage',   'Community Triage',        'community',    'Comment / DM classification',            'economy',  'every 2h'),
  ('agent.paid_media_analyst', 'Paid Media Analyst',      'paid',         'Plans and optimisation proposals',       'standard', 'daily'),
  ('agent.analytics',          'Analytics & Attribution', 'analytics',    'Weekly review, cost per qualified lead', 'standard', 'weekly Mon'),
  ('agent.lead_qualifier',     'Lead Qualifier',          'leads',        'Five-gate qualification',                'standard', 'daily 18:00');
