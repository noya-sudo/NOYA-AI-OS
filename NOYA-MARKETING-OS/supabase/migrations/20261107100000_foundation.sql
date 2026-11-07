-- =====================================================================================================
-- NOYA Marketing OS — Phase 1 / migration 1: foundation
-- Target: the separate "NOYA Marketing OS" Supabase project. NEVER the NOYA HQ project.
--
-- Identities, audit (hash chain), configuration, integration / permission / secrets registries, kill switches.
-- Private schemas: gov (governance) and ops (operations). Nothing here is exposed to the Data API; the console and
-- workers call SECURITY DEFINER functions named public.mos_* (migration 3).
-- =====================================================================================================

create schema if not exists gov;
create schema if not exists ops;
revoke all on schema gov, ops from public, anon, authenticated;

-- -----------------------------------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------------------------------

create or replace function gov.sha256_jsonb(p jsonb)
returns text language sql immutable set search_path = pg_catalog
as $$ select encode(sha256(convert_to(coalesce(p, 'null'::jsonb)::text, 'UTF8')), 'hex') $$;

-- Replace the value of any key that looks like a credential, recursively. Applied before anything is logged.
create or replace function gov.redact(p jsonb)
returns jsonb language plpgsql immutable set search_path = pg_catalog, gov
as $$
declare k text; v jsonb; out jsonb;
begin
  if p is null then return null; end if;
  if jsonb_typeof(p) = 'object' then
    out := '{}'::jsonb;
    for k, v in select * from jsonb_each(p) loop
      if k ~* '(secret|token|password|passwd|authorization|api[_-]?key|access[_-]?key|private[_-]?key|cookie|session|signature)' then
        out := out || jsonb_build_object(k, '[REDACTED]');
      else
        out := out || jsonb_build_object(k, gov.redact(v));
      end if;
    end loop;
    return out;
  elsif jsonb_typeof(p) = 'array' then
    return coalesce((select jsonb_agg(gov.redact(e)) from jsonb_array_elements(p) e), '[]'::jsonb);
  end if;
  return p;
end $$;

create or replace function gov.role_rank(p_role text)
returns int language sql immutable set search_path = pg_catalog
as $$ select case p_role when 'viewer' then 1 when 'analyst' then 2 when 'editor' then 3
                        when 'approver' then 4 when 'owner' then 5 else 0 end $$;

create or replace function gov.immutable_row()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin raise exception '%.% is append-only (% refused)', tg_table_schema, tg_table_name, tg_op using errcode = '42501'; end $$;

create or replace function gov.touch_updated_at()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin new.updated_at := now(); return new; end $$;

-- -----------------------------------------------------------------------------------------------------
-- Identities
-- -----------------------------------------------------------------------------------------------------

create table gov.members (
  user_id   uuid primary key references auth.users(id),
  email     text not null unique,
  role      text not null check (role in ('owner','approver','editor','analyst','viewer')),
  active    boolean not null default true,
  added_by  text not null,
  added_at  timestamptz not null default now()
);
comment on table gov.members is 'Humans allowed into Marketing OS. Adam is the sole owner and sole approver (D5).';
create unique index members_single_owner on gov.members ((true)) where role = 'owner' and active;

create table gov.service_identities (
  code         text primary key,
  kind         text not null check (kind in ('agent','executor','monitor','dispatcher')),
  description  text not null,
  may_request  text[] not null default '{}',   -- action types an agent may PROPOSE (as a draft)
  may_execute  text[] not null default '{}',   -- action types an executor may EXECUTE (approved only)
  active       boolean not null default false,
  created_at   timestamptz not null default now(),
  check (kind = 'executor' or cardinality(may_execute) = 0),
  check (kind = 'agent' or cardinality(may_request) = 0)
);
comment on table gov.service_identities is
  'Non-human actors. Agents propose; executors (no LLM) execute approved work; monitors stop things; dispatchers send alerts.';

create or replace function gov.current_member_role()
returns text language sql stable security definer set search_path = pg_catalog, gov
as $$
  select m.role from gov.members m
  where m.user_id = auth.uid()
    and lower(m.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and m.active
$$;

create or replace function gov.has_role(p_min text)
returns boolean language sql stable security definer set search_path = pg_catalog, gov
as $$ select gov.role_rank(gov.current_member_role()) >= gov.role_rank(p_min) $$;

create or replace function gov.actor()
returns text language sql stable set search_path = pg_catalog
as $$ select coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'anonymous') $$;

-- -----------------------------------------------------------------------------------------------------
-- Audit log: append-only, hash-chained, redacted
-- -----------------------------------------------------------------------------------------------------

-- seq is assigned inside the chain trigger, AFTER the chain lock is taken, so numbering order = chain order
-- even with concurrent writers (an identity default would be drawn before the lock and could interleave).
create sequence gov.audit_log_seq;
create table gov.audit_log (
  seq              bigint primary key,
  id               uuid not null default gen_random_uuid() unique,
  occurred_at      timestamptz not null default clock_timestamp(),
  actor_type       text not null check (actor_type in ('human','agent','executor','monitor','dispatcher','system','policy')),
  actor_id         text not null,
  tool             text,                 -- the function / workflow / agent tool that acted
  action           text not null,
  target_type      text not null,
  target_id        text,
  target_platform  text,
  payload_sha256   text,
  approval_id      uuid,
  decision         text,
  result           text not null check (result in ('ok','refused','error','info')),
  reason           text,
  correlation_id   uuid,
  detail           jsonb,
  prev_hash        text,
  row_hash         text not null
);
comment on table gov.audit_log is
  'Every decision, execution and refusal. Refusals are committed (functions return them instead of raising). Each row hashes the previous one.';
create index audit_log_target on gov.audit_log (target_type, target_id, seq desc);
create index audit_log_action on gov.audit_log (action, occurred_at desc);
create index audit_log_result on gov.audit_log (result, occurred_at desc);
create index audit_log_correlation on gov.audit_log (correlation_id) where correlation_id is not null;

-- UTC rendering keeps the hash independent of the session time zone.
create or replace function gov.audit_row_hash(r gov.audit_log)
returns text language sql immutable set search_path = pg_catalog
as $$
  select encode(sha256(convert_to(concat_ws('|',
    coalesce(r.prev_hash, 'GENESIS'), r.id::text,
    to_char(r.occurred_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'),
    r.actor_type, r.actor_id, coalesce(r.tool, ''), r.action, r.target_type, coalesce(r.target_id, ''),
    coalesce(r.target_platform, ''), coalesce(r.payload_sha256, ''), coalesce(r.approval_id::text, ''),
    coalesce(r.decision, ''), r.result, coalesce(r.reason, ''), coalesce(r.correlation_id::text, ''),
    coalesce(r.detail::text, '')), 'UTF8')), 'hex')
$$;

create or replace function gov.audit_log_chain()
returns trigger language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare prev text;
begin
  perform pg_advisory_xact_lock(hashtext('gov.audit_log'));   -- linear chain, no forks
  select row_hash into prev from gov.audit_log order by seq desc limit 1;
  new.seq         := nextval('gov.audit_log_seq');
  new.occurred_at := clock_timestamp();
  new.detail      := gov.redact(new.detail);
  new.prev_hash   := prev;
  new.row_hash    := gov.audit_row_hash(new);
  return new;
end $$;

create trigger audit_log_chain before insert on gov.audit_log for each row execute function gov.audit_log_chain();
create trigger audit_log_no_update before update or delete on gov.audit_log for each row execute function gov.immutable_row();
create trigger audit_log_no_truncate before truncate on gov.audit_log for each statement execute function gov.immutable_row();

create or replace function gov.audit(
  p_actor_type text, p_actor_id text, p_tool text, p_action text, p_target_type text, p_target_id text,
  p_result text, p_reason text default null, p_detail jsonb default null, p_correlation uuid default null,
  p_platform text default null, p_payload_sha256 text default null, p_approval_id uuid default null, p_decision text default null)
returns uuid language plpgsql security definer set search_path = pg_catalog, gov
as $$
declare v uuid;
begin
  insert into gov.audit_log (actor_type, actor_id, tool, action, target_type, target_id, target_platform, payload_sha256,
                             approval_id, decision, result, reason, correlation_id, detail, row_hash)
  values (p_actor_type, p_actor_id, p_tool, p_action, p_target_type, p_target_id, p_platform, p_payload_sha256,
          p_approval_id, p_decision, p_result, p_reason, p_correlation, p_detail, 'pending')
  returning id into v;
  return v;
end $$;

-- Empty result = intact. Otherwise the first broken row.
create or replace function gov.verify_audit_chain()
returns table (bad_seq bigint, problem text) language plpgsql stable security definer set search_path = pg_catalog, gov
as $$
declare r gov.audit_log; prev text := null;
begin
  for r in select * from gov.audit_log order by seq loop
    if r.prev_hash is distinct from prev then
      bad_seq := r.seq; problem := 'prev_hash does not match the previous row'; return next; return;
    end if;
    if r.row_hash <> gov.audit_row_hash(r) then
      bad_seq := r.seq; problem := 'row_hash does not match the row content'; return next; return;
    end if;
    prev := r.row_hash;
  end loop;
end $$;

create table gov.external_call_log (
  id                    uuid primary key default gen_random_uuid(),
  occurred_at           timestamptz not null default now(),
  actor_id              text not null,
  execution_request_id  uuid,
  integration_code      text not null,
  direction             text not null check (direction in ('read','write')),
  method                text not null,
  endpoint              text not null,
  http_status           int,
  platform_object_id    text,
  dry_run               boolean not null,
  duration_ms           int,
  cost_usd              numeric(12,6),
  request_summary       jsonb,
  response_summary      jsonb,
  error                 text
);
create index external_call_log_exec on gov.external_call_log (execution_request_id) where execution_request_id is not null;

create or replace function gov.external_call_log_guard()
returns trigger language plpgsql set search_path = pg_catalog, gov
as $$
begin
  if new.endpoint ~* '[?&](access_token|token|key|signature)=' then
    raise exception 'endpoint must not carry credentials in its query string';
  end if;
  new.request_summary := gov.redact(new.request_summary);
  new.response_summary := gov.redact(new.response_summary);
  return new;
end $$;
create trigger external_call_log_guard before insert on gov.external_call_log for each row execute function gov.external_call_log_guard();
create trigger external_call_log_no_update before update or delete on gov.external_call_log for each row execute function gov.immutable_row();

-- -----------------------------------------------------------------------------------------------------
-- Configuration (non-secret only)
-- -----------------------------------------------------------------------------------------------------

create table gov.configuration (
  key          text primary key,
  value        jsonb not null,
  description  text not null,
  updated_by   text not null default 'migration',
  updated_at   timestamptz not null default now(),
  check (key !~* '(secret|token|password|api[_-]?key|private)')   -- configuration never holds credentials
);
comment on table gov.configuration is 'Non-secret settings. Credentials live in Supabase / n8n secret stores; see gov.secrets_registry.';

insert into gov.configuration (key, value, description) values
  ('product',                    '"NOYA Marketing OS"',  'Product name'),
  ('phase',                      '1',                    'Current implementation phase'),
  ('environment',                '"production"',         'Database environment label'),
  ('external_execution',         '"disabled"',           'Informational. Real gating is kill switches + approvals + verified integrations + executor env flags'),
  ('approval_ttl_default',       '"24 hours"',           'Default approval lifetime when a permission does not set one'),
  ('alerts.channel',             '"resend"',             'Critical alerts channel (D6). Dispatcher not yet connected'),
  ('alerts.recipient',           '"owner"',              'Alerts go to the active owner member (Adam). No address is stored here'),
  ('alerts.enabled',             'false',                'Dispatcher sends pending notifications only when true'),
  ('ai.monthly_budget_usd',      '30',                   'Marketing OS AI budget, separate from HQ (D7)'),
  ('safety.auto_pause_ads',      'true',                 'D4: critical tripwires may automatically PAUSE ads. Never resume, activate or increase');

-- -----------------------------------------------------------------------------------------------------
-- Kill switches. All initialise DISABLED (= nothing may execute).
-- -----------------------------------------------------------------------------------------------------

create table gov.kill_switches (
  key          text primary key,
  scope        text not null check (scope in ('global','organic','paid','integration')),
  label        text not null,
  state        text not null default 'disabled' check (state in ('disabled','enabled')),
  changed_by   text not null default 'migration',
  changed_at   timestamptz not null default now(),
  reason       text not null default 'Initialised disabled. Only the owner can enable, with a typed confirmation.',
  tripped_by   text
);
comment on table gov.kill_switches is
  'enabled = execution allowed. Non-risk-reducing actions need global + integration.external_writes + their own switch enabled. Automatic systems can only disable.';

insert into gov.kill_switches (key, scope, label) values
  ('global',                       'global',      'Everything'),
  ('organic.instagram',            'organic',     'Instagram (NOYA)'),
  ('organic.linkedin_adam',        'organic',     'LinkedIn — Adam personal (manual only; never automated)'),
  ('organic.linkedin_noya',        'organic',     'LinkedIn — NOYA Company Page'),
  ('paid.meta_ads',                'paid',        'Meta Ads'),
  ('paid.linkedin_ads',            'paid',        'LinkedIn Ads'),
  ('integration.external_writes',  'integration', 'All external writes'),
  ('integration.hq_handoff',       'integration', 'Hand-off of qualified opportunities to NOYA HQ');

-- Only an owner function may enable a switch. It sets a transaction-local flag that this trigger requires.
create or replace function gov.kill_switch_guard()
returns trigger language plpgsql set search_path = pg_catalog, gov
as $$
begin
  if new.state = 'enabled' and old.state = 'disabled'
     and coalesce(current_setting('mos.owner_enable', true), '') <> 'yes' then
    raise exception 'kill switch % can only be enabled by the owner function', new.key using errcode = '42501';
  end if;
  return new;
end $$;
create trigger kill_switch_guard before update on gov.kill_switches for each row execute function gov.kill_switch_guard();
create trigger kill_switch_no_delete before delete on gov.kill_switches for each row execute function gov.immutable_row();

create or replace function gov.switch_enabled(p_key text)
returns boolean language sql stable security definer set search_path = pg_catalog, gov
as $$ select coalesce((select state = 'enabled' from gov.kill_switches where key = p_key), false) $$;

-- Fail-closed: a missing key reads as disabled.
create or replace function gov.switches_allow(p_key text)
returns boolean language sql stable security definer set search_path = pg_catalog, gov
as $$ select gov.switch_enabled('global') and gov.switch_enabled('integration.external_writes')
          and (p_key is null or gov.switch_enabled(p_key)) $$;

-- -----------------------------------------------------------------------------------------------------
-- Integration registry (connected / prepared / planned connectors). No connection without evidence.
-- -----------------------------------------------------------------------------------------------------

create table gov.integration_registry (
  code                   text primary key,
  name                   text not null,
  category               text not null check (category in ('internal','ai','alerts','organic','paid','analytics','research','bridge','devops')),
  status                 text not null default 'planned' check (status in
                           ('planned','prepared','not_connected','read_only','read_write','internal','revoked','error')),
  kill_switch_key        text references gov.kill_switches(key),
  credential_ref         text,             -- NAME of the secret (n8n credential / Supabase secret). Never a value.
  granted_scopes         text[] not null default '{}',
  verified_at            timestamptz,
  verification_evidence  jsonb,
  phase                  smallint not null,
  notes                  text,
  updated_at             timestamptz not null default now(),
  check (status not in ('read_only','read_write') or (verified_at is not null and verification_evidence is not null))
);
comment on table gov.integration_registry is
  'Every connector, including future ones. read_only / read_write require a recorded verification call, so a connection can never be fabricated.';
create trigger integration_registry_touch before update on gov.integration_registry for each row execute function gov.touch_updated_at();

insert into gov.integration_registry (code, name, category, status, kill_switch_key, credential_ref, phase, notes) values
  ('supabase',        'Supabase (this project)',            'internal',  'internal',      null,                           null,                        1, 'Marketing OS database. Separate from NOYA HQ'),
  ('resend_alerts',   'Resend — critical alerts',           'alerts',    'prepared',      null,                           'MOS_RESEND_API_KEY',        1, 'D6. Outbox + dispatcher prepared; separate key from HQ email'),
  ('anthropic',       'Claude API (Marketing OS budget)',   'ai',        'not_connected', null,                           'MOS_ANTHROPIC_API_KEY',     2, 'D7. Separate key/workspace from HQ'),
  ('firecrawl',       'Firecrawl (research, read)',         'research',  'planned',       null,                           'MOS_FIRECRAWL_API_KEY',     3, null),
  ('serper',          'Serper (research, read)',            'research',  'planned',       null,                           'MOS_SERPER_API_KEY',        3, 'HQ standing decision: no volume increase until plan confirmed'),
  ('instagram',       'Instagram — NOYA',                   'organic',   'not_connected', 'organic.instagram',            'MOS_IG_READ_TOKEN',         5, 'Write token only from Phase 7'),
  ('linkedin_noya',   'LinkedIn — NOYA Company Page',       'organic',   'not_connected', 'organic.linkedin_noya',        'MOS_LINKEDIN_READ_TOKEN',   5, 'Depends on LinkedIn Community Management API approval'),
  ('linkedin_adam',   'LinkedIn — Adam personal',           'organic',   'not_connected', 'organic.linkedin_adam',        null,                        4, 'Never automated. Drafts only; Adam posts by hand'),
  ('meta_ads',        'Meta Ads',                           'paid',      'not_connected', 'paid.meta_ads',                'MOS_META_ADS_READ_TOKEN',   5, 'Write token only from Phase 8'),
  ('linkedin_ads',    'LinkedIn Ads',                       'paid',      'planned',       'paid.linkedin_ads',            null,                        8, null),
  ('ga4',             'Google Analytics 4',                 'analytics', 'planned',       null,                           'MOS_GA4_SERVICE_ACCOUNT',   5, 'Read only'),
  ('search_console',  'Google Search Console',              'analytics', 'planned',       null,                           null,                        5, 'Read only'),
  ('hq_handoff',      'NOYA HQ hand-off',                   'bridge',    'planned',       'integration.hq_handoff',       'MOS_HQ_HANDOFF_SIGNING_SECRET', 6, 'Needs a separately approved HQ intake. Qualified opportunities only'),
  ('github',          'GitHub repository noya-marketing-os','devops',    'planned',       null,                           null,                        1, 'Repo creation not available to the build session; code lives in NOYA-AI-OS/NOYA-MARKETING-OS until migrated');

create table gov.secrets_registry (
  name             text primary key,
  purpose          text not null,
  stored_in        text not null check (stored_in in ('supabase_edge_secrets','supabase_vault','n8n_credentials','github_actions','local_only')),
  access           text not null check (access in ('read','write','send','admin')),
  integration_code text references gov.integration_registry(code),
  is_set           boolean not null default false,   -- set by an operator once the secret exists; the value is never here
  owner            text not null default 'Adam',
  last_rotated_at  timestamptz,
  rotate_every     interval,
  notes            text
);
comment on table gov.secrets_registry is 'Names and locations of credentials. Deliberately has no column that could hold a value.';

insert into gov.secrets_registry (name, purpose, stored_in, access, integration_code, rotate_every) values
  ('MOS_RESEND_API_KEY',            'Send critical alerts to Adam (send-only key, alerts domain)', 'supabase_edge_secrets', 'send',  'resend_alerts', interval '180 days'),
  ('MOS_ANTHROPIC_API_KEY',         'Agents (separate budget from HQ)',                             'n8n_credentials',       'read',  'anthropic',     interval '180 days'),
  ('MOS_SUPABASE_SERVICE_ROLE_KEY', 'Workers (n8n) calling mos_* worker functions',                 'n8n_credentials',       'admin', 'supabase',      interval '180 days'),
  ('MOS_IG_READ_TOKEN',             'Instagram insights / comments (read)',                         'n8n_credentials',       'read',  'instagram',     interval '180 days'),
  ('MOS_META_ADS_READ_TOKEN',       'Meta Ads insights (read)',                                     'n8n_credentials',       'read',  'meta_ads',      interval '180 days'),
  ('MOS_LINKEDIN_READ_TOKEN',       'LinkedIn Page analytics (read)',                               'n8n_credentials',       'read',  'linkedin_noya', interval '180 days'),
  ('MOS_HQ_HANDOFF_SIGNING_SECRET', 'HMAC for hand-offs to HQ intake',                              'n8n_credentials',       'write', 'hq_handoff',    interval '90 days');

-- -----------------------------------------------------------------------------------------------------
-- Permission registry: every external action the system can ever request
-- -----------------------------------------------------------------------------------------------------

create table gov.permission_registry (
  action_type           text primary key,
  integration_code      text not null references gov.integration_registry(code),
  kill_switch_key       text not null references gov.kill_switches(key),
  description           text not null,
  mode                  text not null check (mode in ('blocked','approval_required')),
  min_approver_role     text not null default 'owner' check (min_approver_role in ('approver','owner')),
  approval_ttl          interval not null default interval '24 hours',
  moves_money           boolean not null default false,
  risk_reducing         boolean not null default false,
  auto_safety_allowed   boolean not null default false,   -- D4: a monitor may raise this without human approval
  reason                text not null,
  updated_by            text not null default 'migration',
  updated_at            timestamptz not null default now(),
  check (not (moves_money and risk_reducing)),
  check (not auto_safety_allowed or (risk_reducing and action_type like '%.pause'))   -- automatic = pause only, ever
);
comment on table gov.permission_registry is
  'There is no automatic mode. The only exception is D4: monitors may PAUSE ads. Money-moving actions start blocked.';

insert into gov.permission_registry (action_type, integration_code, kill_switch_key, description, mode, approval_ttl, moves_money, risk_reducing, auto_safety_allowed, reason) values
  ('instagram.publish_media',     'instagram',     'organic.instagram',      'Publish a post / carousel / reel',          'approval_required', '48 hours', false, false, false, 'Public publishing needs Adam'),
  ('instagram.publish_story',     'instagram',     'organic.instagram',      'Publish a story',                           'approval_required', '24 hours', false, false, false, 'Public publishing needs Adam'),
  ('instagram.delete_media',      'instagram',     'organic.instagram',      'Delete a published post',                   'approval_required', '24 hours', false, false, false, 'Irreversible'),
  ('instagram.reply_comment',     'instagram',     'organic.instagram',      'Reply to a comment',                        'approval_required', '24 hours', false, false, false, 'External communication'),
  ('instagram.send_dm',           'instagram',     'organic.instagram',      'Send a direct message',                     'approval_required', '24 hours', false, false, false, 'External communication'),
  ('instagram.hide_comment',      'instagram',     'organic.instagram',      'Hide a spam / abusive comment',             'approval_required', '24 hours', false, true,  false, 'Risk-reducing, still approved in v1'),
  ('linkedin_noya.publish_post',  'linkedin_noya', 'organic.linkedin_noya',  'Publish on the NOYA Company Page',          'approval_required', '48 hours', false, false, false, 'Public publishing needs Adam'),
  ('linkedin_noya.reply_comment', 'linkedin_noya', 'organic.linkedin_noya',  'Reply on the Company Page',                 'approval_required', '24 hours', false, false, false, 'External communication'),
  ('linkedin_adam.publish_post',  'linkedin_adam', 'organic.linkedin_adam',  'Post on Adam''s personal profile',          'blocked',           '24 hours', false, false, false, 'Never automated: Adam posts by hand'),
  ('meta_ads.create_paused',      'meta_ads',      'paid.meta_ads',          'Create campaign/ad set/ad PAUSED (no spend)','approval_required', '4 hours',  false, false, false, 'Builds at zero spend'),
  ('meta_ads.activate',           'meta_ads',      'paid.meta_ads',          'Activate / resume',                         'blocked',           '4 hours',  true,  false, false, 'Moves money: blocked until Phase 8'),
  ('meta_ads.increase_budget',    'meta_ads',      'paid.meta_ads',          'Increase a budget',                         'blocked',           '4 hours',  true,  false, false, 'Moves money: blocked until Phase 8'),
  ('meta_ads.edit_targeting',     'meta_ads',      'paid.meta_ads',          'Change audience / bidding',                 'blocked',           '4 hours',  true,  false, false, 'Can raise spend: blocked until Phase 8'),
  ('meta_ads.decrease_budget',    'meta_ads',      'paid.meta_ads',          'Decrease a budget',                         'approval_required', '4 hours',  false, true,  false, 'Risk-reducing'),
  ('meta_ads.pause',              'meta_ads',      'paid.meta_ads',          'Pause campaign / ad set / ad',              'approval_required', '4 hours',  false, true,  true,  'Risk-reducing; D4 automatic safety pause allowed'),
  ('linkedin_ads.create_paused',  'linkedin_ads',  'paid.linkedin_ads',      'Create campaign PAUSED / DRAFT',            'approval_required', '4 hours',  false, false, false, 'Builds at zero spend'),
  ('linkedin_ads.activate',       'linkedin_ads',  'paid.linkedin_ads',      'Activate a campaign',                       'blocked',           '4 hours',  true,  false, false, 'Moves money: blocked until Phase 8'),
  ('linkedin_ads.increase_budget','linkedin_ads',  'paid.linkedin_ads',      'Increase a budget',                         'blocked',           '4 hours',  true,  false, false, 'Moves money: blocked until Phase 8'),
  ('linkedin_ads.decrease_budget','linkedin_ads',  'paid.linkedin_ads',      'Decrease a budget',                         'approval_required', '4 hours',  false, true,  false, 'Risk-reducing'),
  ('linkedin_ads.pause',          'linkedin_ads',  'paid.linkedin_ads',      'Pause a campaign',                          'approval_required', '4 hours',  false, true,  true,  'Risk-reducing; D4 automatic safety pause allowed'),
  ('hq.handoff_opportunity',      'hq_handoff',    'integration.hq_handoff', 'Deliver a qualified opportunity to NOYA HQ','approval_required', '24 hours', false, false, false, 'Only bridge to HQ; Adam approves each one');

create table gov.budget_caps (
  id                            uuid primary key default gen_random_uuid(),
  integration_code              text not null references gov.integration_registry(code),
  period                        text not null check (period in ('day','month')),
  cap_minor                     bigint not null check (cap_minor > 0),
  currency                      text not null check (currency ~ '^[A-Z]{3}$'),
  platform_native_cap_confirmed boolean not null default false,
  set_by                        text not null,
  reason                        text not null,
  active                        boolean not null default true,
  created_at                    timestamptz not null default now()
);
create unique index budget_caps_one_active on gov.budget_caps (integration_code, period) where active;
