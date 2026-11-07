-- SUPERSEDED for the control plane by supabase/migrations/ (Phase 1). Kept for history and for the
-- marketing domain designs (0002), which are promoted phase by phase.
-- =====================================================================================================
-- NOYA Marketing OS: marketing domains (PROPOSED)
--
-- STATUS: PROPOSAL ONLY. Not a migration, not applied anywhere. Requires 0001_governance.sql.
--
-- Schemas:
--   brand      voice rules, asset library with usage rights
--   intel      watched sources, signals, research briefs
--   content    pillars, content items, immutable versions, QA checks, publications
--   paid       media plans, mirrored platform entities, daily spend
--   analytics  metric snapshots, UTM links, attribution touchpoints
--   leads      inbound leads, qualification, the HQ hand-off outbox, HQ outcomes
--   ops        agent registry and agent runs (cost and activity)
--
-- Nothing here can reach the outside world. External effects only happen through gov.action_requests.
-- =====================================================================================================

create schema if not exists brand;
create schema if not exists intel;
create schema if not exists content;
create schema if not exists paid;
create schema if not exists analytics;
create schema if not exists leads;
create schema if not exists ops;

-- Shared trigger: immutable rows (versions, snapshots of what a human approved).
create or replace function gov.immutable_row()
returns trigger language plpgsql
as $$ begin raise exception '%.% rows are immutable (% refused)', tg_table_schema, tg_table_name, tg_op using errcode = '42501'; end $$;

create or replace function gov.touch_updated_at()
returns trigger language plpgsql
as $$ begin new.updated_at := now(); return new; end $$;

-- -----------------------------------------------------------------------------------------------------
-- BRAND
-- -----------------------------------------------------------------------------------------------------

create table brand.voice_rules (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null check (kind in ('principle','do','dont','banned_phrase','claim_rule','format_rule')),
  channel       text check (channel in ('instagram','linkedin_page','website','email','paid')),  -- null = every channel
  rule          text not null,
  example_good  text,
  example_bad   text,
  severity      text not null default 'warn' check (severity in ('block','warn')),
  active        boolean not null default true,
  created_by    text not null,
  created_at    timestamptz not null default now()
);
comment on table brand.voice_rules is
  'NOYA voice as checkable rules: refined, understated, concise, never desperate, no luxury cliches. Brand Guardian checks every version against these.';

create table brand.assets (
  id                   uuid primary key default gen_random_uuid(),
  storage_path         text not null unique,            -- Supabase Storage path in a private bucket
  sha256               text not null,
  kind                 text not null check (kind in ('image','video','logo','font','document','audio')),
  title                text not null,
  source               text not null check (source in ('noya_owned','partner_supplied','licensed','creator','guest','ai_generated')),
  owner_party          text,                            -- who holds copyright (hotel, photographer, NOYA)
  rights_status        text not null default 'unknown' check (rights_status in ('cleared','restricted','pending','expired','unknown')),
  usage_scope          text[] not null default '{}',    -- subset of {organic, paid, print, website, press}
  credit_line          text,
  rights_expires_at    date,
  rights_evidence_url  text,                            -- email / contract proving permission
  people_identifiable  boolean not null default false,
  release_on_file      boolean not null default false,  -- model / guest release for identifiable people
  location             text,
  tags                 text[] not null default '{}',
  created_by           text not null,
  created_at           timestamptz not null default now(),
  check (rights_status <> 'cleared' or rights_evidence_url is not null or source = 'noya_owned'),
  check (not people_identifiable or release_on_file or rights_status <> 'cleared')
);
comment on table brand.assets is
  'Every image and video, with who owns it and where it may be used. Content cannot be approved with an asset that is not cleared for that use. Client and guest imagery needs a release.';

-- -----------------------------------------------------------------------------------------------------
-- INTELLIGENCE
-- -----------------------------------------------------------------------------------------------------

create table intel.sources (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('competitor','hotel','destination','publication','creator','platform','event_calendar','website')),
  name        text not null,
  url         text,
  platform    text,
  handle      text,
  why_watch   text not null,
  cadence     text not null default 'weekly' check (cadence in ('daily','weekly','monthly','manual')),
  profile     jsonb not null default '{}'::jsonb,   -- competitors: positioning, price signals, channels
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (kind, name)
);

create table intel.signals (
  id                  uuid primary key default gen_random_uuid(),
  source_id           uuid references intel.sources(id),
  kind                text not null check (kind in ('opening','event','trend','competitor_move','press','partnership','audience','platform_change','seasonal')),
  title               text not null,
  summary             text not null,
  url                 text,
  observed_at         timestamptz not null default now(),
  relevant_until      date,
  evidence            jsonb not null default '[]'::jsonb,     -- [{url, quote, retrieved_at}]
  confidence          text not null check (confidence in ('verified','inferred','unverified')),
  relevance           smallint not null check (relevance between 0 and 100),
  recommended_action  text,
  status              text not null default 'new' check (status in ('new','reviewed','actioned','dismissed')),
  created_by          text not null,                          -- agent code or member email
  created_at          timestamptz not null default now()
);
create index signals_status on intel.signals (status, relevance desc);

create table intel.research_briefs (
  id            uuid primary key default gen_random_uuid(),
  question      text not null,
  requested_by  text not null,
  status        text not null default 'queued' check (status in ('queued','running','done','failed','cancelled')),
  findings_md   text,
  decision      text,                                         -- the "so what": recommendation or action
  sources       jsonb not null default '[]'::jsonb,
  cost_usd      numeric(10,4),
  created_at    timestamptz not null default now(),
  completed_at  timestamptz
);

-- -----------------------------------------------------------------------------------------------------
-- CONTENT
-- -----------------------------------------------------------------------------------------------------

create table content.pillars (
  code          text primary key,             -- e.g. 'egypt_insider', 'access', 'properties', 'journal', 'b2b_proof'
  name          text not null,
  description   text not null,
  target_share  numeric(4,3) check (target_share between 0 and 1),
  active        boolean not null default true
);

create table content.items (
  id                 uuid primary key default gen_random_uuid(),
  pillar             text references content.pillars(code),
  channel            text not null check (channel in ('instagram','linkedin_page','linkedin_adam','website','newsletter','paid')),
  format             text not null check (format in ('post','carousel','reel','story','article','document','ad')),
  title              text not null,
  objective          text not null check (objective in ('awareness','engagement','enquiry','partnership','proof','recruit_partner')),
  status             text not null default 'idea' check (status in
                       ('idea','brief','drafting','in_review','changes_requested','approved','scheduled','published','archived','rejected')),
  planned_for        timestamptz,
  brief              text,
  source_signal_id   uuid references intel.signals(id),
  owner              text not null,
  current_version    int,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index items_calendar on content.items (planned_for) where status in ('approved','scheduled');
create trigger items_touch before update on content.items for each row execute function gov.touch_updated_at();
comment on column content.items.channel is
  'linkedin_adam = drafts for Adam''s personal profile; always posted by Adam by hand (LinkedIn offers no permitted automation for it).';

create table content.versions (
  id           uuid primary key default gen_random_uuid(),
  item_id      uuid not null references content.items(id),
  version      int not null,
  caption      text,
  body         text,
  hashtags     text[] not null default '{}',
  asset_ids    uuid[] not null default '{}',
  alt_text     text,
  cta          text,
  utm_link_id  uuid,
  created_by   text not null,
  created_at   timestamptz not null default now(),
  sha256       text not null,
  unique (item_id, version)
);
create trigger versions_immutable before update or delete on content.versions
  for each row execute function gov.immutable_row();

create table content.checks (
  id           uuid primary key default gen_random_uuid(),
  version_id   uuid not null references content.versions(id),
  check_kind   text not null check (check_kind in
                 ('brand_voice','banned_phrase','claims','asset_rights','platform_rules','privacy','accessibility','factual')),
  result       text not null check (result in ('pass','warn','fail')),
  findings     jsonb not null default '[]'::jsonb,
  checked_by   text not null,
  checked_at   timestamptz not null default now()
);
create index checks_version on content.checks (version_id);

create table content.publications (
  id                  uuid primary key default gen_random_uuid(),
  item_id             uuid not null references content.items(id),
  version_id          uuid not null references content.versions(id),
  channel_account_id  uuid references gov.channel_accounts(id),
  method              text not null check (method in ('manual','api')),
  action_request_id   uuid references gov.action_requests(id),
  external_id         text,
  permalink           text,
  published_at        timestamptz not null,
  recorded_by         text not null,
  created_at          timestamptz not null default now(),
  check (method = 'manual' or action_request_id is not null),
  unique (channel_account_id, external_id)
);
comment on table content.publications is
  'What actually went live. Manual posts by Adam are recorded too, so analytics and the unknown-post tripwire stay correct.';

-- -----------------------------------------------------------------------------------------------------
-- PAID MEDIA
-- -----------------------------------------------------------------------------------------------------

create table paid.media_plans (
  id                     uuid primary key default gen_random_uuid(),
  name                   text not null,
  platform               text not null check (platform in ('meta_ads','linkedin_ads','google_ads')),
  objective              text not null,
  audience               jsonb not null default '{}'::jsonb,
  proposed_daily_minor   bigint check (proposed_daily_minor > 0),
  proposed_total_minor   bigint check (proposed_total_minor > 0),
  currency               text not null check (currency ~ '^[A-Z]{3}$'),
  starts_on              date,
  ends_on                date,
  success_metric         text not null,                 -- e.g. 'qualified enquiries', not 'reach'
  target_cost_per_result_minor bigint,
  kill_criteria          text not null,                 -- when we stop, written before we start
  rationale              text not null,
  status                 text not null default 'draft' check (status in ('draft','in_review','approved','rejected','live','ended','archived')),
  created_by             text not null,
  created_at             timestamptz not null default now()
);
comment on table paid.media_plans is
  'A plan is a proposal. Approving a plan spends nothing: each platform change is still its own action request.';

create table paid.entities (
  id                   uuid primary key default gen_random_uuid(),
  plan_id              uuid references paid.media_plans(id),
  channel_account_id   uuid not null references gov.channel_accounts(id),
  level                text not null check (level in ('campaign','ad_set','ad')),
  parent_id            uuid references paid.entities(id),
  platform_id          text,                            -- null until created on the platform
  name                 text not null,
  status_platform      text,                            -- as last read from the platform
  daily_budget_minor   bigint,
  lifetime_budget_minor bigint,
  currency             text check (currency is null or currency ~ '^[A-Z]{3}$'),
  spec                 jsonb not null default '{}'::jsonb,
  last_synced_at       timestamptz,
  created_at           timestamptz not null default now(),
  unique (channel_account_id, level, platform_id)
);

create table paid.spend_daily (
  entity_id     uuid not null references paid.entities(id),
  day           date not null,
  spend_minor   bigint not null default 0,
  currency      text not null,
  impressions   bigint,
  clicks        bigint,
  results       bigint,
  result_type   text,
  source        text not null,                          -- 'meta_insights', 'linkedin_analytics', ...
  synced_at     timestamptz not null default now(),
  primary key (entity_id, day)
);

-- -----------------------------------------------------------------------------------------------------
-- ANALYTICS & ATTRIBUTION
-- -----------------------------------------------------------------------------------------------------

create table analytics.utm_links (
  id               uuid primary key default gen_random_uuid(),
  slug             text not null unique,
  destination_url  text not null,
  utm_source       text not null,
  utm_medium       text not null,
  utm_campaign     text not null,
  utm_content      text,
  content_item_id  uuid references content.items(id),
  paid_entity_id   uuid references paid.entities(id),
  created_by       text not null,
  created_at       timestamptz not null default now()
);

create table analytics.metric_snapshots (
  id                  uuid primary key default gen_random_uuid(),
  channel_account_id  uuid references gov.channel_accounts(id),
  subject_type        text not null check (subject_type in ('account','content','paid_entity','page','site')),
  subject_ref         text not null,                    -- publication id, paid entity id, URL path, account id
  metric              text not null,                    -- 'reach', 'saves', 'profile_visits', 'followers', 'sessions', ...
  value               numeric not null,
  period_start        date not null,
  period_end          date not null,
  source              text not null check (source in ('instagram_graph','linkedin_community','meta_ads','linkedin_ads','google_ads','ga4','search_console','windsor','manual')),
  captured_at         timestamptz not null default now(),
  unique (subject_type, subject_ref, metric, period_start, period_end, source)
);

create table analytics.touchpoints (
  id               uuid primary key default gen_random_uuid(),
  lead_id          uuid not null,                       -- leads.inbound(id); FK added below
  occurred_at      timestamptz not null,
  channel          text not null,
  touch_type       text not null check (touch_type in ('first','assist','last','self_reported')),
  utm_link_id      uuid references analytics.utm_links(id),
  content_item_id  uuid references content.items(id),
  paid_entity_id   uuid references paid.entities(id),
  evidence         text
);

-- -----------------------------------------------------------------------------------------------------
-- LEADS and the HQ hand-off
-- -----------------------------------------------------------------------------------------------------

create table leads.inbound (
  id                  uuid primary key default gen_random_uuid(),
  received_at         timestamptz not null,
  channel             text not null check (channel in
                        ('instagram_dm','instagram_comment','linkedin_message','linkedin_comment','website_form','email','paid_lead_form','referral','event')),
  channel_account_id  uuid references gov.channel_accounts(id),
  excerpt             text,                              -- minimum needed to qualify; not the whole thread
  person_name         text,
  handle              text,
  email               text,
  phone               text,
  company             text,
  country             text,
  lawful_basis        text not null default 'enquiry' check (lawful_basis in ('enquiry','consent','legitimate_interest_b2b')),
  status              text not null default 'new' check (status in
                        ('new','triaged','nurture','qualified','handed_off','not_relevant','spam','do_not_contact')),
  dedupe_key          text,                              -- normalised email / handle hash
  retention_until     date not null default (current_date + 365),
  created_by          text not null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index inbound_status on leads.inbound (status, received_at desc);
create index inbound_dedupe on leads.inbound (dedupe_key) where dedupe_key is not null;
create trigger inbound_touch before update on leads.inbound for each row execute function gov.touch_updated_at();

alter table analytics.touchpoints
  add constraint touchpoints_lead_fk foreign key (lead_id) references leads.inbound(id);

create table leads.qualifications (
  id                uuid primary key default gen_random_uuid(),
  lead_id           uuid not null references leads.inbound(id),
  segment           text not null check (segment in
                      ('private_client','corporate','travel_trade','brand_production','agency','press_creator','other')),
  service_interest  text[] not null default '{}',
  destination       text,
  timing            text,
  party_size        int,
  budget_signal     text not null default 'unknown' check (budget_signal in ('stated','inferred','unknown')),
  budget_band       text,
  is_decision_maker boolean,
  gates             jsonb not null,                       -- {"identifiable":true,"reachable":true,"real_need":true,"fit":true,"timing":true}
  fit_score         smallint not null check (fit_score between 0 and 100),
  intent_score      smallint not null check (intent_score between 0 and 100),
  verdict           text not null check (verdict in ('qualified','nurture','not_relevant')),
  evidence          text not null,
  assessed_by       text not null,                        -- agent code or member email
  assessed_at       timestamptz not null default now()
);
comment on table leads.qualifications is
  'Only a verdict of qualified, with every gate true, can become an HQ hand-off. Creator and press enquiries without revenue stay in Marketing OS.';

create table leads.hq_handoffs (
  id                  uuid primary key default gen_random_uuid(),
  lead_id             uuid not null references leads.inbound(id),
  qualification_id    uuid not null references leads.qualifications(id),
  contract_version    text not null default 'v1',
  payload             jsonb not null,                     -- docs/hq-handoff-contract.md, nothing more
  payload_sha256      text not null,
  action_request_id   uuid references gov.action_requests(id),
  status              text not null default 'prepared' check (status in
                        ('prepared','pending_approval','approved','delivered','acknowledged','rejected_by_hq','failed','withdrawn')),
  hq_reference        text,                               -- HQ's id for the opportunity, returned on acknowledgement
  delivered_at        timestamptz,
  acknowledged_at     timestamptz,
  hq_outcome          text check (hq_outcome in ('open','won','lost','duplicate','invalid')),
  outcome_value_minor bigint,
  outcome_currency    text,
  outcome_at          timestamptz,
  created_at          timestamptz not null default now()
);
create unique index hq_handoffs_one_live on leads.hq_handoffs (lead_id)
  where status not in ('rejected_by_hq','failed','withdrawn');

create or replace function leads.hq_handoffs_guard()
returns trigger language plpgsql
as $$
declare q leads.qualifications;
begin
  select * into q from leads.qualifications where id = new.qualification_id;
  if q.verdict <> 'qualified' or q.lead_id <> new.lead_id
     or not (q.gates ?& array['identifiable','reachable','real_need','fit','timing'])
     or exists (select 1 from jsonb_each(q.gates) g where g.value <> 'true'::jsonb) then
    raise exception 'only a qualified lead with every gate passed can be handed to HQ';
  end if;
  new.payload_sha256 := gov.sha256_jsonb(new.payload);
  return new;
end $$;
create trigger hq_handoffs_guard before insert or update of payload, qualification_id on leads.hq_handoffs
  for each row execute function leads.hq_handoffs_guard();

-- -----------------------------------------------------------------------------------------------------
-- OPS: agents and runs
-- -----------------------------------------------------------------------------------------------------

create table ops.agents (
  code               text primary key references gov.service_identities(code),
  name               text not null,
  department         text not null check (department in ('brand','intelligence','content','community','paid','analytics','leads')),
  purpose            text not null,
  model_tier         text not null check (model_tier in ('economy','standard','premium')),
  tools              text[] not null default '{}',     -- read tools only; write tools do not exist for agents
  schedule           text,                             -- cron, or null for on demand
  daily_cost_cap_usd numeric(8,2) not null default 1.00,
  enabled            boolean not null default false,
  paused_reason      text,
  created_at         timestamptz not null default now()
);

create table ops.agent_runs (
  id              uuid primary key default gen_random_uuid(),
  agent_code      text not null references ops.agents(code),
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  status          text not null default 'running' check (status in
                    ('running','succeeded','failed','skipped_budget','skipped_paused')),
  trigger         text not null check (trigger in ('schedule','manual','event')),
  summary         text,                                -- analysed result, not raw output
  output_refs     jsonb not null default '[]'::jsonb,  -- [{table, id}]
  tokens_in       int,
  tokens_out      int,
  cost_usd        numeric(10,4),
  error           text,
  correlation_id  uuid not null default gen_random_uuid()
);
create index agent_runs_agent on ops.agent_runs (agent_code, started_at desc);

-- -----------------------------------------------------------------------------------------------------
-- Lock down every domain table: RLS on, no direct access for anon/authenticated. The console reads
-- through api.* functions (added per phase), exactly like NOYA HQ.
-- -----------------------------------------------------------------------------------------------------

do $$
declare t record;
begin
  for t in select schemaname, tablename from pg_tables
           where schemaname in ('brand','intel','content','paid','analytics','leads','ops') loop
    execute format('alter table %I.%I enable row level security', t.schemaname, t.tablename);
    execute format('revoke all on %I.%I from public, anon, authenticated', t.schemaname, t.tablename);
  end loop;
end $$;

revoke all on schema brand, intel, content, paid, analytics, leads, ops from public, anon, authenticated;
grant usage on schema brand, intel, content, paid, analytics, leads, ops to service_role;
