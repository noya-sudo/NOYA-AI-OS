-- =====================================================================================================
-- NOYA Marketing OS: governance control plane (PROPOSED)
--
-- STATUS: PROPOSAL ONLY. This file is NOT a migration. It has not been applied to any database.
-- It is meant for a NEW, SEPARATE Supabase project. It never runs against the NOYA HQ project.
--
-- What it gives us:
--   1. Members and roles (who may draft, approve and arm).
--   2. Action types and permission policies (every external write is classified; default = approval).
--   3. Action requests and approvals (propose -> approve -> execute, bound to a payload hash).
--   4. System controls = the kill switch (installed HALTED, fail-closed).
--   5. Budget caps and tripwires (ad-spend guard rails).
--   6. Channel accounts that cannot claim a connection without evidence.
--   7. Secrets registry (names and locations only, never values).
--   8. Append-only, hash-chained audit log + external call log.
--
-- Conventions:
--   * Tables live in private schemas (gov, ...). The browser never touches tables.
--   * The browser calls only functions in schema `api`, granted to `authenticated`.
--   * Executors (n8n) call only `api.executor_*`, granted to `service_role`.
--   * Money is stored in minor units (pence / cents / piastres) as bigint, with an ISO currency code.
-- =====================================================================================================

-- No extensions needed: sha256() and gen_random_uuid() are built into Postgres 13+.

create schema if not exists gov;
create schema if not exists api;

revoke all on schema gov from public, anon, authenticated;
revoke all on schema api from public, anon;
grant usage on schema api to authenticated, service_role;
grant usage on schema gov to service_role;

-- -----------------------------------------------------------------------------------------------------
-- 0. Helpers
-- -----------------------------------------------------------------------------------------------------

-- Stable SHA-256 of a jsonb value. jsonb::text is deterministic in Postgres (keys are normalised).
create or replace function gov.sha256_jsonb(p jsonb)
returns text language sql immutable
as $$ select encode(sha256(convert_to(coalesce(p, 'null'::jsonb)::text, 'UTF8')), 'hex') $$;

-- Recursively replaces the value of any key that looks like a secret. Used before anything is logged.
create or replace function gov.redact(p jsonb)
returns jsonb language plpgsql immutable
as $$
declare
  k text; v jsonb; out jsonb;
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
  else
    return p;
  end if;
end $$;

create or replace function gov.role_rank(p_role text)
returns int language sql immutable
as $$
  select case p_role
    when 'viewer'   then 1
    when 'analyst'  then 2
    when 'editor'   then 3
    when 'approver' then 4
    when 'owner'    then 5
    else 0 end
$$;

-- -----------------------------------------------------------------------------------------------------
-- 1. Members and service identities
-- -----------------------------------------------------------------------------------------------------

create table gov.members (
  user_id     uuid primary key references auth.users(id),
  email       text not null unique,
  role        text not null check (role in ('owner','approver','editor','analyst','viewer')),
  active      boolean not null default true,
  added_by    text not null,
  added_at    timestamptz not null default now()
);
comment on table gov.members is
  'Humans allowed into the Marketing Console. Role decides what they may draft, approve or arm. Adam is the only owner at install.';

-- Exactly one owner while the system is young; relaxing this is a deliberate migration.
create unique index members_single_owner on gov.members ((true)) where role = 'owner' and active;

create table gov.service_identities (
  code                  text primary key,            -- e.g. 'agent.content_strategist', 'executor.publisher'
  kind                  text not null check (kind in ('agent','executor','monitor')),
  description           text not null,
  may_request           text[] not null default '{}', -- action types this identity may PROPOSE
  may_execute           text[] not null default '{}', -- action types this identity may EXECUTE (executors only)
  active                boolean not null default false,
  created_at            timestamptz not null default now(),
  check (kind = 'executor' or cardinality(may_execute) = 0)  -- agents and monitors can never execute
);
comment on table gov.service_identities is
  'Non-human actors. Agents (LLM) may propose; only executors (deterministic code, no LLM) may execute, and only approved requests.';

-- Signed-in member's role, or null. Matches on both user id and email (same pattern as HQ).
create or replace function gov.current_member_role()
returns text language sql stable security definer set search_path = gov, pg_temp
as $$
  select m.role
  from gov.members m
  where m.user_id = auth.uid()
    and lower(m.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and m.active
$$;

-- -----------------------------------------------------------------------------------------------------
-- 2. Audit log (append-only, hash-chained)
-- -----------------------------------------------------------------------------------------------------

create table gov.audit_log (
  seq             bigint generated always as identity primary key,
  id              uuid not null default gen_random_uuid() unique,
  occurred_at     timestamptz not null default clock_timestamp(),
  actor_type      text not null check (actor_type in ('human','agent','executor','monitor','system')),
  actor_id        text not null,                 -- user id / email, or service identity code
  action          text not null,                 -- e.g. 'action_request.approve', 'kill_switch.engage'
  entity_type     text not null,                 -- e.g. 'gov.action_requests'
  entity_id       text,
  result          text not null check (result in ('ok','blocked','error','info')),
  reason          text,
  correlation_id  uuid,                          -- ties together one agent run / one request lifecycle
  before_state    jsonb,
  after_state     jsonb,
  detail          jsonb,
  prev_hash       text,
  row_hash        text not null
);
comment on table gov.audit_log is
  'Append-only record of every decision and state change, including blocked attempts. Each row hashes the previous row; gov.verify_audit_chain() detects tampering.';

create index audit_log_entity on gov.audit_log (entity_type, entity_id, seq desc);
create index audit_log_action on gov.audit_log (action, occurred_at desc);
create index audit_log_correlation on gov.audit_log (correlation_id) where correlation_id is not null;

-- Hash of one audit row, chained to the previous row. Timestamps are rendered in UTC so the result
-- does not depend on the session's TimeZone setting.
create or replace function gov.audit_row_hash(r gov.audit_log)
returns text language sql immutable
as $$
  select encode(sha256(convert_to(
    coalesce(r.prev_hash, 'GENESIS') || '|' || r.id::text || '|' ||
    to_char(r.occurred_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US') || '|' ||
    r.actor_type || '|' || r.actor_id || '|' || r.action || '|' || r.entity_type || '|' ||
    coalesce(r.entity_id, '') || '|' || r.result || '|' || coalesce(r.reason, '') || '|' ||
    coalesce(r.before_state::text, '') || '|' || coalesce(r.after_state::text, '') || '|' ||
    coalesce(r.detail::text, ''), 'UTF8')), 'hex')
$$;

create or replace function gov.audit_log_chain()
returns trigger language plpgsql security definer set search_path = gov, pg_temp
as $$
declare prev text;
begin
  -- Serialise writers so the chain has no forks. Volume is low (hundreds of rows a day), so this is cheap.
  perform pg_advisory_xact_lock(hashtext('gov.audit_log'));
  select row_hash into prev from gov.audit_log order by seq desc limit 1;
  new.occurred_at  := clock_timestamp();
  new.before_state := gov.redact(new.before_state);
  new.after_state  := gov.redact(new.after_state);
  new.detail       := gov.redact(new.detail);
  new.prev_hash    := prev;
  new.row_hash     := gov.audit_row_hash(new);
  return new;
end $$;

create trigger audit_log_chain before insert on gov.audit_log
  for each row execute function gov.audit_log_chain();

create or replace function gov.audit_log_immutable()
returns trigger language plpgsql
as $$ begin raise exception 'gov.audit_log is append-only (% refused)', tg_op using errcode = '42501'; end $$;

create trigger audit_log_no_update before update or delete on gov.audit_log
  for each row execute function gov.audit_log_immutable();
create trigger audit_log_no_truncate before truncate on gov.audit_log
  for each statement execute function gov.audit_log_immutable();

revoke all on gov.audit_log from public, anon, authenticated;
revoke update, delete, truncate on gov.audit_log from service_role;

create or replace function gov.audit(
  p_actor_type text, p_actor_id text, p_action text, p_entity_type text, p_entity_id text,
  p_result text, p_reason text default null, p_before jsonb default null, p_after jsonb default null,
  p_detail jsonb default null, p_correlation uuid default null)
returns uuid language plpgsql security definer set search_path = gov, pg_temp
as $$
declare v_id uuid;
begin
  insert into gov.audit_log (actor_type, actor_id, action, entity_type, entity_id, result, reason,
                             before_state, after_state, detail, correlation_id, row_hash)
  values (p_actor_type, p_actor_id, p_action, p_entity_type, p_entity_id, p_result, p_reason,
          p_before, p_after, p_detail, p_correlation, 'pending')
  returning id into v_id;
  return v_id;
end $$;

-- Returns nothing when the chain is intact; otherwise the first broken row.
create or replace function gov.verify_audit_chain()
returns table (bad_seq bigint, problem text) language plpgsql stable security definer set search_path = gov, pg_temp
as $$
declare r gov.audit_log; prev text := null; expect text;
begin
  for r in select * from gov.audit_log order by seq loop
    if r.prev_hash is distinct from prev then
      bad_seq := r.seq; problem := 'prev_hash does not match previous row'; return next; return;
    end if;
    expect := gov.audit_row_hash(r);
    if r.row_hash <> expect then
      bad_seq := r.seq; problem := 'row_hash does not match row content'; return next; return;
    end if;
    prev := r.row_hash;
  end loop;
end $$;

-- Every external HTTP call an executor or reader makes. Metadata only; bodies are summarised and redacted.
create table gov.external_call_log (
  id                 uuid primary key default gen_random_uuid(),
  occurred_at        timestamptz not null default now(),
  actor_id           text not null,             -- service identity code
  action_request_id  uuid,                      -- null for read-only calls
  platform           text not null,             -- 'instagram', 'meta_ads', 'linkedin', 'ga4', 'anthropic', ...
  direction          text not null check (direction in ('read','write')),
  method             text not null,
  endpoint           text not null,             -- path only; never a query string carrying a token
  http_status        int,
  platform_object_id text,
  dry_run            boolean not null,
  duration_ms        int,
  cost_usd           numeric(12,6),
  request_summary    jsonb,
  response_summary   jsonb,
  error              text
);
create index external_call_log_request on gov.external_call_log (action_request_id) where action_request_id is not null;
create index external_call_log_platform on gov.external_call_log (platform, occurred_at desc);

create or replace function gov.external_call_log_redact()
returns trigger language plpgsql
as $$
begin
  new.request_summary  := gov.redact(new.request_summary);
  new.response_summary := gov.redact(new.response_summary);
  if new.endpoint ~ '[?&](access_token|token|key|signature)=' then
    raise exception 'endpoint must not carry credentials in its query string';
  end if;
  return new;
end $$;
create trigger external_call_log_redact before insert on gov.external_call_log
  for each row execute function gov.external_call_log_redact();
create trigger external_call_log_no_update before update or delete on gov.external_call_log
  for each row execute function gov.audit_log_immutable();

-- -----------------------------------------------------------------------------------------------------
-- 3. System controls (the kill switch). Installed HALTED. Fail-closed.
-- -----------------------------------------------------------------------------------------------------

create table gov.system_controls (
  key          text primary key,
  scope        text not null check (scope in ('global','publish','engagement','spend','handoff','email')),
  state        text not null default 'halted' check (state in ('halted','armed')),
  description  text not null,
  changed_by   text not null default 'install',
  changed_at   timestamptz not null default now(),
  reason       text not null default 'Installed halted. Nothing external runs until the owner arms it.',
  tripped_by   text                               -- tripwire code when a monitor halted it
);
comment on table gov.system_controls is
  'Kill switch. An external action runs only if BOTH global and its own control are armed. Halting cancels queued work; re-arming never resumes it.';

insert into gov.system_controls (key, scope, description) values
  ('global',                'global',     'Master switch for every external write'),
  ('publish.instagram',     'publish',    'Publishing to Instagram'),
  ('publish.linkedin_page', 'publish',    'Publishing to the NOYA LinkedIn Company Page'),
  ('publish.website',       'publish',    'Publishing to the NOYA website / journal'),
  ('engagement.instagram',  'engagement', 'Replies, comments and DMs on Instagram'),
  ('engagement.linkedin',   'engagement', 'Replies and comments on LinkedIn'),
  ('spend.meta',            'spend',      'Any Meta (Facebook / Instagram) ads change'),
  ('spend.linkedin',        'spend',      'Any LinkedIn ads change'),
  ('spend.google',          'spend',      'Any Google Ads change'),
  ('handoff.hq',            'handoff',    'Delivering qualified opportunities to NOYA HQ'),
  ('email.marketing',       'email',      'Marketing email to external recipients');

create table gov.kill_switch_events (
  id                   uuid primary key default gen_random_uuid(),
  control_key          text not null references gov.system_controls(key),
  from_state           text not null,
  to_state             text not null,
  actor_type           text not null,
  actor_id             text not null,
  reason               text not null,
  tripwire_code        text,
  requests_blocked     int not null default 0,
  occurred_at          timestamptz not null default now()
);

create or replace function gov.control_armed(p_key text)
returns boolean language sql stable security definer set search_path = gov, pg_temp
as $$
  -- Fail-closed: a missing row reads as halted.
  select coalesce((select state = 'armed' from gov.system_controls where key = 'global'), false)
     and coalesce((select state = 'armed' from gov.system_controls where key = p_key), false)
$$;

create table gov.tripwires (
  code          text primary key,
  description   text not null,
  control_key   text not null references gov.system_controls(key),
  metric        text not null,
  comparator    text not null check (comparator in ('>','>=','<','<=','=','detected')),
  threshold     numeric,
  window_size   interval,
  enabled       boolean not null default true
);
comment on table gov.tripwires is
  'Conditions a monitor checks. When one fires, the monitor calls gov.trip(), which halts the control. Tripwires can halt; they can never arm.';

insert into gov.tripwires (code, description, control_key, metric, comparator, threshold, window_size) values
  ('spend_over_daily_cap',      'Platform-reported spend today exceeds the daily cap',                    'spend.meta',            'spend_vs_daily_cap_ratio', '>=', 1.0,  interval '1 day'),
  ('spend_velocity',            'More than 40% of the daily cap spent within one hour',                   'spend.meta',            'hourly_spend_ratio',       '>',  0.4,  interval '1 hour'),
  ('unknown_campaign_change',   'A campaign / budget changed on the platform without a matching request', 'spend.meta',            'unmatched_platform_change','detected', null, interval '1 hour'),
  ('unknown_post_detected',     'A post appeared on a NOYA account that this system did not record',      'global',                'unmatched_publication',    'detected', null, interval '1 hour'),
  ('executor_failures',         'Three or more executor failures within one hour',                        'global',                'executor_failures',        '>=', 3,    interval '1 hour'),
  ('audit_chain_broken',        'gov.verify_audit_chain() returned a broken row',                         'global',                'audit_chain_break',        'detected', null, null),
  ('token_scope_changed',       'A platform token gained scopes it did not have when registered',         'global',                'token_scope_drift',        'detected', null, null);

-- -----------------------------------------------------------------------------------------------------
-- 4. Channel accounts. A connection cannot be claimed without verification evidence.
-- -----------------------------------------------------------------------------------------------------

create table gov.channel_accounts (
  id                     uuid primary key default gen_random_uuid(),
  platform               text not null check (platform in
                           ('instagram','linkedin_page','meta_ads','linkedin_ads','google_ads','ga4','search_console','website','email')),
  handle                 text not null,               -- '@noyaconcierge', 'NOYA Concierge (Company Page)'
  external_id            text,                        -- platform's own id, once verified
  connection_status      text not null default 'not_connected'
                           check (connection_status in ('not_connected','read_only','read_write','revoked','error')),
  verified_at            timestamptz,
  verified_by            text,
  verification_evidence  jsonb,                       -- e.g. {"call":"GET /me","http_status":200,"external_call_log_id":"..."}
  granted_scopes         text[] not null default '{}',
  credential_ref         text,                        -- NAME of the n8n credential. Never the secret.
  notes                  text,
  created_at             timestamptz not null default now(),
  unique (platform, handle),
  check (connection_status in ('not_connected','revoked') or (verified_at is not null and verification_evidence is not null))
);
comment on table gov.channel_accounts is
  'NOYA''s own accounts. Status starts not_connected. read_only / read_write require a recorded verification call, so the system cannot claim a connection it does not have.';

-- -----------------------------------------------------------------------------------------------------
-- 5. Budget caps (ad spend). Required before any spend control may be armed.
-- -----------------------------------------------------------------------------------------------------

create table gov.budget_caps (
  id                            uuid primary key default gen_random_uuid(),
  channel_account_id            uuid not null references gov.channel_accounts(id),
  period                        text not null check (period in ('day','month')),
  cap_minor                     bigint not null check (cap_minor > 0),
  currency                      text not null check (currency ~ '^[A-Z]{3}$'),
  platform_native_cap_confirmed boolean not null default false,  -- Adam confirmed the platform's own account spending limit is set
  set_by                        text not null,
  reason                        text not null,
  active                        boolean not null default true,
  created_at                    timestamptz not null default now()
);
create unique index budget_caps_one_active on gov.budget_caps (channel_account_id, period) where active;

-- -----------------------------------------------------------------------------------------------------
-- 6. Secrets registry: names and locations, NEVER values.
-- -----------------------------------------------------------------------------------------------------

create table gov.secrets_registry (
  name             text primary key,                 -- matches docs/environment.md
  purpose          text not null,
  stored_in        text not null check (stored_in in
                     ('n8n_credentials','supabase_edge_secrets','supabase_vault','cloudflare','github_actions','local_only')),
  access           text not null check (access in ('read','write','admin')),
  scopes           text[] not null default '{}',
  owner            text not null default 'Adam',
  created_at       timestamptz not null default now(),
  last_rotated_at  timestamptz,
  rotate_every     interval,
  notes            text
);
comment on table gov.secrets_registry is
  'Where each credential lives and what it can do. There is deliberately no column that could hold a secret value.';

-- -----------------------------------------------------------------------------------------------------
-- 7. Action types and permission policies
-- -----------------------------------------------------------------------------------------------------

create table gov.action_types (
  code            text primary key,
  domain          text not null check (domain in ('publish','engagement','spend','handoff','email')),
  description     text not null,
  is_external     boolean not null default true,
  moves_money     boolean not null default false,  -- starts or increases spend exposure
  risk_reducing   boolean not null default false,  -- pause / lower budget / hide: allowed while a control is halted (still needs approval)
  reversible      boolean not null,
  risk_tier       smallint not null check (risk_tier between 2 and 5),
  control_key     text not null references gov.system_controls(key),
  check (not (moves_money and risk_reducing))
);
comment on table gov.action_types is
  'Every external write the system can ever request. Anything not listed here cannot be requested or executed.';

insert into gov.action_types (code, domain, description, moves_money, risk_reducing, reversible, risk_tier, control_key) values
  -- Publishing (public, reputational)
  ('instagram.publish_media',      'publish',    'Publish a feed post, carousel or reel to Instagram',      false, false, false, 3, 'publish.instagram'),
  ('instagram.publish_story',      'publish',    'Publish a story to Instagram',                            false, false, false, 3, 'publish.instagram'),
  ('instagram.delete_media',       'publish',    'Delete a published Instagram post',                       false, false, false, 3, 'publish.instagram'),
  ('linkedin_page.publish_post',   'publish',    'Publish a post on the NOYA LinkedIn Company Page',        false, false, false, 3, 'publish.linkedin_page'),
  ('linkedin_page.delete_post',    'publish',    'Delete a post on the NOYA LinkedIn Company Page',         false, false, false, 3, 'publish.linkedin_page'),
  ('website.publish_article',      'publish',    'Publish or update a journal article on the website',      false, false, true,  3, 'publish.website'),
  -- Engagement (one-to-one, external people)
  ('instagram.reply_comment',      'engagement', 'Reply publicly to a comment on Instagram',                false, false, false, 2, 'engagement.instagram'),
  ('instagram.send_dm',            'engagement', 'Send a direct message on Instagram',                      false, false, false, 3, 'engagement.instagram'),
  ('instagram.hide_comment',       'engagement', 'Hide an abusive or spam comment',                         false, true,  true,  2, 'engagement.instagram'),
  ('linkedin_page.reply_comment',  'engagement', 'Reply to a comment on a Company Page post',               false, false, false, 2, 'engagement.linkedin'),
  -- Paid media (money)
  ('meta_ads.create_paused',       'spend',      'Create campaign / ad set / ad in PAUSED state (no spend)',false, false, true,  3, 'spend.meta'),
  ('meta_ads.activate',            'spend',      'Activate or resume a campaign, ad set or ad',             true,  false, true,  5, 'spend.meta'),
  ('meta_ads.increase_budget',     'spend',      'Increase a daily or lifetime budget',                     true,  false, true,  5, 'spend.meta'),
  ('meta_ads.edit_targeting',      'spend',      'Change audience, placements or bidding',                  true,  false, true,  4, 'spend.meta'),
  ('meta_ads.edit_creative',       'spend',      'Change the creative or copy of a live ad',                false, false, true,  4, 'spend.meta'),
  ('meta_ads.decrease_budget',     'spend',      'Decrease a budget',                                       false, true,  true,  4, 'spend.meta'),
  ('meta_ads.pause',               'spend',      'Pause a campaign, ad set or ad',                          false, true,  true,  4, 'spend.meta'),
  ('linkedin_ads.create_paused',   'spend',      'Create a LinkedIn campaign in PAUSED / DRAFT state',      false, false, true,  3, 'spend.linkedin'),
  ('linkedin_ads.activate',        'spend',      'Activate a LinkedIn campaign',                            true,  false, true,  5, 'spend.linkedin'),
  ('linkedin_ads.increase_budget', 'spend',      'Increase a LinkedIn campaign budget',                     true,  false, true,  5, 'spend.linkedin'),
  ('linkedin_ads.pause',           'spend',      'Pause a LinkedIn campaign',                               false, true,  true,  4, 'spend.linkedin'),
  ('google_ads.activate',          'spend',      'Enable a Google Ads campaign',                            true,  false, true,  5, 'spend.google'),
  ('google_ads.increase_budget',   'spend',      'Increase a Google Ads budget',                            true,  false, true,  5, 'spend.google'),
  ('google_ads.pause',             'spend',      'Pause a Google Ads campaign',                             false, true,  true,  4, 'spend.google'),
  -- Cross-system
  ('hq.handoff_opportunity',       'handoff',    'Deliver a qualified opportunity to NOYA HQ',              false, false, false, 3, 'handoff.hq'),
  -- Email
  ('email.send_marketing',         'email',      'Send a marketing email to external recipients',           false, false, false, 4, 'email.marketing');

create table gov.permission_policies (
  id                    uuid primary key default gen_random_uuid(),
  action_type           text not null references gov.action_types(code),
  mode                  text not null check (mode in ('blocked','approval_required','auto_within_limits')),
  min_approver_role     text not null default 'owner' check (min_approver_role in ('approver','owner')),
  approvals_required    smallint not null default 1 check (approvals_required between 1 and 3),
  approval_ttl          interval not null default interval '24 hours',
  confirm_at_execution  boolean not null default true,   -- a second, explicit "run it now" after approval
  limits                jsonb not null default '{}'::jsonb,
  set_by                text not null,
  reason                text not null,
  active_from           timestamptz not null default now(),
  expires_at            timestamptz,
  superseded_at         timestamptz,
  check (mode <> 'auto_within_limits' or expires_at is not null)   -- autonomy is always time-boxed
);
create unique index permission_policies_one_active on gov.permission_policies (action_type) where superseded_at is null;

-- Money-moving actions can never be automatic. Changing that is a schema migration, not a setting.
create or replace function gov.permission_policies_guard()
returns trigger language plpgsql
as $$
begin
  if new.mode = 'auto_within_limits'
     and exists (select 1 from gov.action_types t where t.code = new.action_type and t.moves_money) then
    raise exception 'money-moving action % cannot be automatic', new.action_type using errcode = '42501';
  end if;
  return new;
end $$;
create trigger permission_policies_guard before insert or update on gov.permission_policies
  for each row execute function gov.permission_policies_guard();

-- Install defaults: every external write needs Adam. Spend that moves money is BLOCKED outright until Phase 8.
insert into gov.permission_policies (action_type, mode, min_approver_role, approval_ttl, confirm_at_execution, set_by, reason)
select t.code,
       case when t.moves_money or t.domain = 'email' then 'blocked' else 'approval_required' end,
       'owner',
       case when t.domain = 'spend' then interval '4 hours' when t.domain = 'publish' then interval '48 hours' else interval '24 hours' end,
       true,
       'install',
       'Default at install: every external write needs owner approval; money-moving and marketing email are blocked until their phase.'
from gov.action_types t;

create or replace function gov.active_policy(p_action_type text)
returns gov.permission_policies language sql stable security definer set search_path = gov, pg_temp
as $$
  select p.* from gov.permission_policies p
  where p.action_type = p_action_type and p.superseded_at is null
    and p.active_from <= now() and (p.expires_at is null or p.expires_at > now())
$$;

-- -----------------------------------------------------------------------------------------------------
-- 8. Action requests and approvals: propose -> approve -> (confirm) -> execute
-- -----------------------------------------------------------------------------------------------------

create table gov.action_requests (
  id                    uuid primary key default gen_random_uuid(),
  action_type           text not null references gov.action_types(code),
  channel_account_id    uuid references gov.channel_accounts(id),
  subject_type          text,                       -- e.g. 'content.items', 'paid.entities', 'leads.hq_handoffs'
  subject_id            uuid,
  payload               jsonb not null,             -- exactly what the executor will send
  payload_sha256        text not null,              -- computed by trigger, never trusted from the caller
  spend_delta_minor     bigint not null default 0,  -- increase in daily spend exposure, if any
  currency              text check (currency is null or currency ~ '^[A-Z]{3}$'),
  rationale             text not null,
  requested_by_type     text not null check (requested_by_type in ('human','agent','system')),
  requested_by          text not null,
  status                text not null default 'draft' check (status in (
                          'draft','pending_approval','changes_requested','approved','queued','executing',
                          'succeeded','failed','rejected','expired','cancelled','blocked')),
  status_reason         text,
  not_before            timestamptz,
  approval_expires_at   timestamptz,
  confirmed_at          timestamptz,
  confirmed_by          text,
  idempotency_key       text not null unique,
  dry_run               boolean not null default true,  -- false only when the executor runs in production with writes enabled
  external_ref          text,
  external_url          text,
  result                jsonb,
  error                 text,
  correlation_id        uuid not null default gen_random_uuid(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index action_requests_status on gov.action_requests (status, created_at);
create index action_requests_subject on gov.action_requests (subject_type, subject_id);

create or replace function gov.action_requests_guard()
returns trigger language plpgsql
as $$
declare allowed boolean;
begin
  if tg_op = 'INSERT' then
    new.payload_sha256 := gov.sha256_jsonb(new.payload);
    if new.status not in ('draft','pending_approval') then
      raise exception 'a new request must start as draft or pending_approval';
    end if;
    return new;
  end if;

  -- The payload is frozen once it leaves draft. To change it, cancel and raise a new request.
  if old.status <> 'draft' and (new.payload is distinct from old.payload
                                or new.action_type is distinct from old.action_type
                                or new.channel_account_id is distinct from old.channel_account_id
                                or new.spend_delta_minor is distinct from old.spend_delta_minor) then
    raise exception 'payload of request % is frozen (status %)', old.id, old.status using errcode = '42501';
  end if;
  new.payload_sha256 := gov.sha256_jsonb(new.payload);

  if new.status is distinct from old.status then
    allowed := case old.status
      when 'draft'             then new.status in ('pending_approval','cancelled')
      when 'pending_approval'  then new.status in ('approved','rejected','changes_requested','cancelled','expired','blocked')
      when 'changes_requested' then new.status in ('cancelled')
      when 'approved'          then new.status in ('queued','cancelled','expired','blocked')
      when 'queued'            then new.status in ('executing','cancelled','blocked','expired')
      when 'executing'         then new.status in ('succeeded','failed')
      else false end;  -- succeeded, failed, rejected, expired, cancelled, blocked are terminal
    if not allowed then
      raise exception 'illegal status change % -> % on request %', old.status, new.status, old.id using errcode = '42501';
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger action_requests_guard before insert or update on gov.action_requests
  for each row execute function gov.action_requests_guard();
create trigger action_requests_no_delete before delete on gov.action_requests
  for each row execute function gov.audit_log_immutable();

create table gov.approvals (
  id                  uuid primary key default gen_random_uuid(),
  action_request_id   uuid not null references gov.action_requests(id),
  decision            text not null check (decision in ('approve','reject','request_changes')),
  approver_user_id    uuid not null,
  approver_email      text not null,
  approver_role       text not null,
  payload_sha256      text not null,      -- the exact payload the human saw
  note                text,
  created_at          timestamptz not null default now(),
  unique (action_request_id, approver_user_id)
);
create trigger approvals_no_update before update or delete on gov.approvals
  for each row execute function gov.audit_log_immutable();

-- The single gate. Executors and the console both call it; the executor calls it again immediately before the API call.
create or replace function gov.can_execute(p_request_id uuid)
returns table (ok boolean, reason text) language plpgsql stable security definer set search_path = gov, pg_temp
as $$
declare
  r   gov.action_requests;
  t   gov.action_types;
  p   gov.permission_policies;
  ch  gov.channel_accounts;
  n   int;
  cap bigint;
begin
  select * into r from gov.action_requests where id = p_request_id;
  if not found then ok := false; reason := 'request not found'; return next; return; end if;
  select * into t from gov.action_types where code = r.action_type;
  p := gov.active_policy(r.action_type);

  if p.id is null              then ok := false; reason := 'no active policy (fail-closed)'; return next; return; end if;
  if p.mode = 'blocked'        then ok := false; reason := 'policy blocks ' || r.action_type; return next; return; end if;
  if r.status not in ('approved','queued') then
    ok := false; reason := 'status is ' || r.status; return next; return;
  end if;
  if r.payload_sha256 <> gov.sha256_jsonb(r.payload) then
    ok := false; reason := 'payload hash mismatch'; return next; return;
  end if;

  if p.mode = 'approval_required' then
    select count(*) into n from gov.approvals a
     where a.action_request_id = r.id and a.decision = 'approve'
       and a.payload_sha256 = r.payload_sha256
       and gov.role_rank(a.approver_role) >= gov.role_rank(p.min_approver_role);
    if n < p.approvals_required then
      ok := false; reason := format('%s of %s approvals on this exact payload', n, p.approvals_required); return next; return;
    end if;
    if exists (select 1 from gov.approvals a where a.action_request_id = r.id and a.decision <> 'approve') then
      ok := false; reason := 'a reviewer rejected or asked for changes'; return next; return;
    end if;
    if r.approval_expires_at is null or r.approval_expires_at <= now() then
      ok := false; reason := 'approval expired'; return next; return;
    end if;
    if p.confirm_at_execution and r.confirmed_at is null then
      ok := false; reason := 'awaiting execution confirmation'; return next; return;
    end if;
  end if;

  -- Kill switch. Risk-reducing actions (pause, lower budget, hide) may still run while halted.
  if not t.risk_reducing and not gov.control_armed(t.control_key) then
    ok := false; reason := 'kill switch: ' || t.control_key || ' or global is halted'; return next; return;
  end if;

  if r.not_before is not null and r.not_before > now() then
    ok := false; reason := 'scheduled for ' || r.not_before::text; return next; return;
  end if;

  if r.channel_account_id is not null then
    select * into ch from gov.channel_accounts where id = r.channel_account_id;
    if ch.connection_status <> 'read_write' then
      ok := false; reason := 'channel account is ' || coalesce(ch.connection_status, 'missing') || ', not read_write'; return next; return;
    end if;
  elsif t.domain in ('publish','engagement','spend') then
    ok := false; reason := 'no channel account on request'; return next; return;
  end if;

  if t.moves_money then
    select cap_minor into cap from gov.budget_caps
     where channel_account_id = r.channel_account_id and period = 'day' and active and platform_native_cap_confirmed;
    if cap is null then
      ok := false; reason := 'no active daily cap with platform-native cap confirmed'; return next; return;
    end if;
    if r.spend_delta_minor > cap then
      ok := false; reason := 'spend change exceeds the daily cap'; return next; return;
    end if;
    -- Phase 8 adds: projected platform spend + spend_delta_minor <= cap, from paid.spend_daily.
  end if;

  ok := true; reason := 'all gates passed'; return next;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- 9. API: console functions (authenticated) and executor / monitor functions (service_role)
--
-- Every function returns jsonb {ok, reason, ...}. A refusal is NOT raised as an error: raising would roll
-- back the audit row, and blocked attempts must stay on record. Only unexpected faults raise.
-- -----------------------------------------------------------------------------------------------------

create or replace function gov.actor()
returns text language sql stable
as $$ select coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'anonymous') $$;

create or replace function gov.refuse(p_actor_type text, p_actor text, p_action text, p_entity_type text,
                                      p_entity_id text, p_reason text, p_correlation uuid default null)
returns jsonb language plpgsql security definer set search_path = gov, pg_temp
as $$
begin
  perform gov.audit(p_actor_type, p_actor, p_action, p_entity_type, p_entity_id, 'blocked', p_reason,
                    null, null, null, p_correlation);
  return jsonb_build_object('ok', false, 'reason', p_reason);
end $$;

create or replace function gov.has_role(p_min text)
returns boolean language sql stable security definer set search_path = gov, pg_temp
as $$ select gov.role_rank(gov.current_member_role()) >= gov.role_rank(p_min) $$;

create or replace function api.submit_for_approval(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = gov, pg_temp
as $$
declare r gov.action_requests; who text := gov.actor();
begin
  if not gov.has_role('editor') then
    return gov.refuse('human', who, 'action_request.submit', 'gov.action_requests', p_request_id::text, 'editor role required');
  end if;
  update gov.action_requests set status = 'pending_approval' where id = p_request_id and status = 'draft' returning * into r;
  if not found then
    return gov.refuse('human', who, 'action_request.submit', 'gov.action_requests', p_request_id::text, 'request is not a draft');
  end if;
  perform gov.audit('human', who, 'action_request.submit', 'gov.action_requests', r.id::text, 'ok',
                    null, null, jsonb_build_object('status', r.status, 'payload_sha256', r.payload_sha256), null, r.correlation_id);
  return jsonb_build_object('ok', true, 'status', r.status, 'payload_sha256', r.payload_sha256);
end $$;

create or replace function api.decide(p_request_id uuid, p_decision text, p_seen_sha256 text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = gov, pg_temp
as $$
declare
  r gov.action_requests; p gov.permission_policies; role text := gov.current_member_role(); who text := gov.actor(); n int;
  act text := 'action_request.decide';
begin
  if gov.role_rank(role) < gov.role_rank('approver') then
    return gov.refuse('human', who, act, 'gov.action_requests', p_request_id::text, 'approver role required');
  end if;
  if p_decision not in ('approve','reject','request_changes') then
    return gov.refuse('human', who, act, 'gov.action_requests', p_request_id::text, 'unknown decision ' || coalesce(p_decision, 'null'));
  end if;
  select * into r from gov.action_requests where id = p_request_id for update;
  if not found then
    return gov.refuse('human', who, act, 'gov.action_requests', p_request_id::text, 'request not found');
  end if;
  p := gov.active_policy(r.action_type);

  if r.status <> 'pending_approval' then
    return gov.refuse('human', who, act, 'gov.action_requests', r.id::text, 'request is ' || r.status || ', not pending_approval', r.correlation_id);
  end if;
  if p_seen_sha256 is distinct from r.payload_sha256 then
    return gov.refuse('human', who, act, 'gov.action_requests', r.id::text, 'the payload changed since it was shown; reload and review again', r.correlation_id);
  end if;
  if p_decision = 'approve' and gov.role_rank(role) < gov.role_rank(coalesce(p.min_approver_role, 'owner')) then
    return gov.refuse('human', who, act, 'gov.action_requests', r.id::text, 'this action needs ' || coalesce(p.min_approver_role, 'owner') || ' approval', r.correlation_id);
  end if;
  -- Segregation of duties: only the owner may approve a request they raised themselves.
  if r.requested_by_type = 'human' and lower(r.requested_by) = lower(who) and role <> 'owner' then
    return gov.refuse('human', who, act, 'gov.action_requests', r.id::text, 'you cannot approve your own request', r.correlation_id);
  end if;
  if p_decision in ('reject','request_changes') and coalesce(trim(p_note), '') = '' then
    return gov.refuse('human', who, act, 'gov.action_requests', r.id::text, 'a note is required to reject or request changes', r.correlation_id);
  end if;
  if exists (select 1 from gov.approvals where action_request_id = r.id and approver_user_id = auth.uid()) then
    return gov.refuse('human', who, act, 'gov.action_requests', r.id::text, 'you already decided on this request', r.correlation_id);
  end if;

  insert into gov.approvals (action_request_id, decision, approver_user_id, approver_email, approver_role, payload_sha256, note)
  values (r.id, p_decision, auth.uid(), who, role, r.payload_sha256, p_note);

  if p_decision = 'reject' then
    update gov.action_requests set status = 'rejected', status_reason = p_note where id = r.id returning * into r;
  elsif p_decision = 'request_changes' then
    update gov.action_requests set status = 'changes_requested', status_reason = p_note where id = r.id returning * into r;
  else
    select count(*) into n from gov.approvals where action_request_id = r.id and decision = 'approve';
    if n >= coalesce(p.approvals_required, 1) then
      update gov.action_requests
         set status = 'approved', approval_expires_at = now() + coalesce(p.approval_ttl, interval '24 hours')
       where id = r.id returning * into r;
    end if;
  end if;

  perform gov.audit('human', who, 'action_request.' || p_decision, 'gov.action_requests', r.id::text, 'ok',
                    p_note, null, jsonb_build_object('status', r.status, 'payload_sha256', r.payload_sha256), null, r.correlation_id);
  return jsonb_build_object('ok', true, 'status', r.status, 'approval_expires_at', r.approval_expires_at);
end $$;

-- Second click, at the moment Adam wants it to go. Runs every gate first.
create or replace function api.confirm_execution(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = gov, pg_temp
as $$
declare r gov.action_requests; g record; who text := gov.actor(); act text := 'action_request.confirm';
begin
  if not gov.has_role('approver') then
    return gov.refuse('human', who, act, 'gov.action_requests', p_request_id::text, 'approver role required');
  end if;
  select * into r from gov.action_requests where id = p_request_id for update;
  if not found or r.status <> 'approved' then
    return gov.refuse('human', who, act, 'gov.action_requests', p_request_id::text,
                      'request is ' || coalesce(r.status, 'missing') || ', not approved', r.correlation_id);
  end if;
  update gov.action_requests set confirmed_at = now(), confirmed_by = who where id = r.id;
  select * into g from gov.can_execute(r.id);
  if not g.ok then
    update gov.action_requests set confirmed_at = null, confirmed_by = null where id = r.id;
    return gov.refuse('human', who, act, 'gov.action_requests', r.id::text, g.reason, r.correlation_id);
  end if;
  update gov.action_requests set status = 'queued' where id = r.id returning * into r;
  perform gov.audit('human', who, act, 'gov.action_requests', r.id::text, 'ok', null, null, null, null, r.correlation_id);
  return jsonb_build_object('ok', true, 'status', r.status);
end $$;

-- Executor: claim one queued request. Re-runs every gate inside the same transaction, just before the API call.
create or replace function api.executor_claim(p_executor text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = gov, pg_temp
as $$
declare r gov.action_requests; g record; s gov.service_identities; act text := 'action_request.claim';
begin
  select * into s from gov.service_identities where code = p_executor and kind = 'executor' and active;
  select * into r from gov.action_requests where id = p_request_id for update skip locked;
  if not found then
    return gov.refuse('executor', p_executor, act, 'gov.action_requests', p_request_id::text, 'request not available');
  end if;
  if s.code is null or not (r.action_type = any (s.may_execute)) then
    return gov.refuse('executor', p_executor, act, 'gov.action_requests', r.id::text,
                      'executor not allowed to run ' || r.action_type, r.correlation_id);
  end if;
  if r.status <> 'queued' then
    return gov.refuse('executor', p_executor, act, 'gov.action_requests', r.id::text, 'status is ' || r.status, r.correlation_id);
  end if;
  select * into g from gov.can_execute(r.id);
  if not g.ok then
    return gov.refuse('executor', p_executor, act, 'gov.action_requests', r.id::text, g.reason, r.correlation_id);
  end if;
  update gov.action_requests set status = 'executing' where id = r.id returning * into r;
  perform gov.audit('executor', p_executor, act, 'gov.action_requests', r.id::text, 'ok', null, null, null, null, r.correlation_id);
  return jsonb_build_object('ok', true, 'request', to_jsonb(r));
end $$;

create or replace function api.executor_report(p_executor text, p_request_id uuid, p_success boolean, p_dry_run boolean,
                                               p_external_ref text default null, p_external_url text default null,
                                               p_result jsonb default null, p_error text default null)
returns jsonb language plpgsql security definer set search_path = gov, pg_temp
as $$
declare r gov.action_requests;
begin
  update gov.action_requests
     set status = case when p_success then 'succeeded' else 'failed' end,
         dry_run = p_dry_run, external_ref = p_external_ref, external_url = p_external_url,
         result = gov.redact(p_result), error = p_error
   where id = p_request_id and status = 'executing'
  returning * into r;
  if not found then
    return gov.refuse('executor', p_executor, 'action_request.report', 'gov.action_requests', p_request_id::text, 'request is not executing');
  end if;
  perform gov.audit('executor', p_executor, 'action_request.' || case when p_success then 'succeeded' else 'failed' end,
                    'gov.action_requests', r.id::text, case when p_success then 'ok' else 'error' end, p_error,
                    null, jsonb_build_object('external_ref', p_external_ref, 'dry_run', p_dry_run), p_result, r.correlation_id);
  return jsonb_build_object('ok', true, 'status', r.status, 'result', r.result);
end $$;

-- Kill switch: halt. Approved / queued work under the control is blocked and must be re-approved later.
create or replace function gov.halt(p_key text, p_actor_type text, p_actor_id text, p_reason text, p_tripwire text default null)
returns jsonb language plpgsql security definer set search_path = gov, pg_temp
as $$
declare old_state text; n int := 0;
begin
  select state into old_state from gov.system_controls where key = p_key for update;
  if not found then
    return gov.refuse(p_actor_type, p_actor_id, 'kill_switch.halt', 'gov.system_controls', p_key, 'unknown control');
  end if;
  update gov.system_controls set state = 'halted', changed_by = p_actor_id, changed_at = now(),
         reason = p_reason, tripped_by = p_tripwire where key = p_key;

  with hit as (
    update gov.action_requests ar set status = 'blocked', status_reason = 'kill switch: ' || p_key
     where ar.status in ('approved','queued')
       and (p_key = 'global' or exists (select 1 from gov.action_types t where t.code = ar.action_type and t.control_key = p_key))
       and not exists (select 1 from gov.action_types t where t.code = ar.action_type and t.risk_reducing)
    returning 1)
  select count(*) into n from hit;

  insert into gov.kill_switch_events (control_key, from_state, to_state, actor_type, actor_id, reason, tripwire_code, requests_blocked)
  values (p_key, old_state, 'halted', p_actor_type, p_actor_id, p_reason, p_tripwire, n);
  perform gov.audit(p_actor_type, p_actor_id, 'kill_switch.halt', 'gov.system_controls', p_key, 'ok', p_reason,
                    jsonb_build_object('state', old_state), jsonb_build_object('state', 'halted', 'requests_blocked', n),
                    jsonb_build_object('tripwire', p_tripwire));
  return jsonb_build_object('ok', true, 'control', p_key, 'state', 'halted', 'requests_blocked', n);
end $$;

-- Any approver may halt. Halting is always allowed; it never needs a second person.
create or replace function api.kill_switch_halt(p_key text default 'global', p_reason text default 'Halted from the console')
returns jsonb language plpgsql security definer set search_path = gov, pg_temp
as $$
begin
  if not gov.has_role('approver') then
    return gov.refuse('human', gov.actor(), 'kill_switch.halt', 'gov.system_controls', p_key, 'approver role required');
  end if;
  return gov.halt(p_key, 'human', gov.actor(), p_reason);
end $$;

-- Monitors call this when a tripwire fires. A tripwire can halt; nothing automatic can ever arm.
create or replace function api.monitor_trip(p_monitor text, p_tripwire text, p_detail jsonb default null)
returns jsonb language plpgsql security definer set search_path = gov, pg_temp
as $$
declare tw gov.tripwires;
begin
  select * into tw from gov.tripwires where code = p_tripwire and enabled;
  if not found then
    return gov.refuse('monitor', p_monitor, 'kill_switch.trip', 'gov.tripwires', p_tripwire, 'unknown or disabled tripwire');
  end if;
  return gov.halt(tw.control_key, 'monitor', p_monitor,
                  'Tripwire: ' || tw.description || coalesce(' ' || p_detail::text, ''), p_tripwire);
end $$;

-- Arm: owner only, typed confirmation, reason required, spend controls need caps first.
create or replace function api.kill_switch_arm(p_key text, p_reason text, p_typed_confirmation text)
returns jsonb language plpgsql security definer set search_path = gov, pg_temp
as $$
declare who text := gov.actor(); old_state text; act text := 'kill_switch.arm';
begin
  if not gov.has_role('owner') then
    return gov.refuse('human', who, act, 'gov.system_controls', p_key, 'owner role required');
  end if;
  if p_typed_confirmation is distinct from ('ARM ' || p_key) then
    return gov.refuse('human', who, act, 'gov.system_controls', p_key, 'type exactly: ARM ' || p_key);
  end if;
  if coalesce(trim(p_reason), '') = '' then
    return gov.refuse('human', who, act, 'gov.system_controls', p_key, 'a reason is required');
  end if;
  select state into old_state from gov.system_controls where key = p_key for update;
  if not found then
    return gov.refuse('human', who, act, 'gov.system_controls', p_key, 'unknown control');
  end if;
  if p_key like 'spend.%' and not exists (
      select 1 from gov.budget_caps b join gov.channel_accounts a on a.id = b.channel_account_id
       where b.active and b.period = 'day' and b.platform_native_cap_confirmed
         and a.platform = case p_key when 'spend.meta' then 'meta_ads' when 'spend.linkedin' then 'linkedin_ads' else 'google_ads' end) then
    return gov.refuse('human', who, act, 'gov.system_controls', p_key,
                      'set a daily cap and confirm the platform''s own spending limit before arming ' || p_key);
  end if;
  update gov.system_controls set state = 'armed', changed_by = who, changed_at = now(), reason = p_reason, tripped_by = null
   where key = p_key;
  insert into gov.kill_switch_events (control_key, from_state, to_state, actor_type, actor_id, reason)
  values (p_key, old_state, 'armed', 'human', who, p_reason);
  perform gov.audit('human', who, act, 'gov.system_controls', p_key, 'ok', p_reason,
                    jsonb_build_object('state', old_state), jsonb_build_object('state', 'armed'));
  return jsonb_build_object('ok', true, 'control', p_key, 'state', 'armed');
end $$;

-- Change a permission policy. Owner only. Leaving approval_required needs the action code typed back.
create or replace function api.set_policy(p_action_type text, p_mode text, p_reason text, p_typed_confirmation text,
                                          p_expires_at timestamptz default null, p_limits jsonb default '{}'::jsonb,
                                          p_min_approver_role text default 'owner', p_approvals_required smallint default 1,
                                          p_approval_ttl interval default interval '24 hours', p_confirm_at_execution boolean default true)
returns jsonb language plpgsql security definer set search_path = gov, pg_temp
as $$
declare old gov.permission_policies; new_p gov.permission_policies; who text := gov.actor(); act text := 'policy.set';
begin
  if not gov.has_role('owner') then
    return gov.refuse('human', who, act, 'gov.permission_policies', p_action_type, 'owner role required');
  end if;
  if coalesce(trim(p_reason), '') = '' then
    return gov.refuse('human', who, act, 'gov.permission_policies', p_action_type, 'a reason is required');
  end if;
  if p_mode <> 'approval_required' and p_typed_confirmation is distinct from p_action_type then
    return gov.refuse('human', who, act, 'gov.permission_policies', p_action_type,
                      'type the action code (' || p_action_type || ') to confirm leaving approval_required');
  end if;
  begin
    select * into old from gov.permission_policies where action_type = p_action_type and superseded_at is null for update;
    update gov.permission_policies set superseded_at = now() where id = old.id;
    insert into gov.permission_policies (action_type, mode, min_approver_role, approvals_required, approval_ttl,
                                         confirm_at_execution, limits, set_by, reason, expires_at)
    values (p_action_type, p_mode, p_min_approver_role, p_approvals_required, p_approval_ttl,
            p_confirm_at_execution, p_limits, who, p_reason, p_expires_at)
    returning * into new_p;
  exception when others then
    -- e.g. money-moving action made automatic, or an auto mode without an expiry. Nothing changed.
    return gov.refuse('human', who, act, 'gov.permission_policies', p_action_type, sqlerrm);
  end;
  perform gov.audit('human', who, act, 'gov.permission_policies', p_action_type, 'ok', p_reason, to_jsonb(old), to_jsonb(new_p));
  return jsonb_build_object('ok', true, 'policy', to_jsonb(new_p));
end $$;

-- Expire stale approvals. Scheduled every 15 minutes (pg_cron) once the project exists.
create or replace function gov.expire_approvals()
returns int language plpgsql security definer set search_path = gov, pg_temp
as $$
declare n int;
begin
  with x as (
    update gov.action_requests set status = 'expired', status_reason = 'approval window passed'
     where status in ('approved','queued') and approval_expires_at <= now()
    returning id)
  select count(*) into n from x;
  if n > 0 then
    perform gov.audit('system', 'gov.expire_approvals', 'action_request.expire', 'gov.action_requests', null, 'ok',
                      n || ' approvals expired');
  end if;
  return n;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- 10. Lock down
-- -----------------------------------------------------------------------------------------------------

do $$
declare t record;
begin
  for t in select schemaname, tablename from pg_tables where schemaname = 'gov' loop
    execute format('alter table %I.%I enable row level security', t.schemaname, t.tablename);
    execute format('revoke all on %I.%I from public, anon, authenticated', t.schemaname, t.tablename);
  end loop;
end $$;

revoke all on all functions in schema gov from public, anon, authenticated;
revoke all on all functions in schema api from public, anon, authenticated;

grant execute on function api.submit_for_approval(uuid)                         to authenticated;
grant execute on function api.decide(uuid, text, text, text)                    to authenticated;
grant execute on function api.confirm_execution(uuid)                           to authenticated;
grant execute on function api.kill_switch_halt(text, text)                      to authenticated;
grant execute on function api.kill_switch_arm(text, text, text)                 to authenticated;
grant execute on function api.set_policy(text, text, text, text, timestamptz, jsonb, text, smallint, interval, boolean) to authenticated;

grant execute on function api.executor_claim(text, uuid)                                         to service_role;
grant execute on function api.executor_report(text, uuid, boolean, boolean, text, text, jsonb, text) to service_role;
grant execute on function api.monitor_trip(text, text, jsonb)                                    to service_role;
