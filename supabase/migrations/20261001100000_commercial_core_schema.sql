-- NOYA commercial core — schema.
-- Signal → opportunity → company → people → relationship → service → angle → outreach → conversation
-- → proposal / partnership → project → revenue → expansion. One shared CRM; existing tables are extended,
-- nothing is duplicated. Every system-generated fact carries provenance.
--
-- Provenance vocabulary (used everywhere):
--   VERIFIED            confirmed by a first-party check (e.g. Hunter-verified email, Gmail thread)
--   SOURCE_BACKED       stated by a cited public source (source_url kept)
--   INFERRED            derived by rules or AI from stored text; needs a human glance
--   NEEDS_VERIFICATION  plausible but unconfirmed
--   MANUALLY_CONFIRMED  entered or confirmed by a NOYA team member in HQ

-- ---------------------------------------------------------------- team & ownership
create table if not exists public.team_members (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  email text,
  roles text[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.team_members enable row level security;
insert into public.team_members (name, email, roles)
values ('Adam', 'noya@noyaconcierge.com', array['CEO', 'SALES', 'PARTNERSHIPS', 'SDR', 'EVENTS', 'OPERATIONS', 'ACCOUNT_MANAGEMENT', 'REVOPS'])
on conflict (name) do nothing;

-- Which team member currently holds each commercial role (one person may hold all of them today).
create table if not exists public.role_routing (
  role text primary key check (role in ('CEO', 'SALES', 'PARTNERSHIPS', 'SDR', 'EVENTS', 'OPERATIONS', 'ACCOUNT_MANAGEMENT', 'REVOPS')),
  member_name text not null references public.team_members(name) on update cascade,
  updated_at timestamptz not null default now()
);
alter table public.role_routing enable row level security;
insert into public.role_routing (role, member_name)
select r, 'Adam' from unnest(array['CEO', 'SALES', 'PARTNERSHIPS', 'SDR', 'EVENTS', 'OPERATIONS', 'ACCOUNT_MANAGEMENT', 'REVOPS']) r
on conflict (role) do nothing;

create or replace function public.owner_for_role(p_role text)
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select member_name from role_routing where role = p_role), (select member_name from role_routing where role = 'CEO'), 'Adam')
$$;

-- Owner names were written two ways by the workflows ("Adam" / "Adam Elshazly"): one team member.
update public.opportunities set owner = 'Adam' where owner in ('Adam Elshazly', 'adam', 'Adam E');

-- ---------------------------------------------------------------- commercial library
create table if not exists public.commercial_products (
  code text primary key,
  name text not null,
  summary text not null,
  owner_role text not null default 'SALES',
  target_segments text[] not null default '{}',
  ideal_client text,
  buyer_roles text[] not null default '{}',
  trigger_events text[] not null default '{}',
  client_problems text[] not null default '{}',
  solution text,
  included_services text[] not null default '{}',
  proof_points text[] not null default '{}',
  partner_types text[] not null default '{}',
  outreach_angles text[] not null default '{}',
  email_template jsonb,          -- {subject, body}; placeholders in {{double_braces}}
  dm_template text,
  call_points text[] not null default '{}',
  objections jsonb not null default '[]',        -- [{objection, response}]
  proposal_template text,
  follow_up_sequence jsonb not null default '[]', -- [{day, channel, purpose, message}]
  upsells text[] not null default '{}',
  recurring_potential text,
  public boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.commercial_products enable row level security;

create table if not exists public.commercial_playbooks (
  code text primary key,
  name text not null,
  trigger_desc text not null,
  categories text[] not null default '{}',       -- signal categories this playbook answers
  keywords text[] not null default '{}',         -- lower-case regex fragments matched against the signal text
  priority smallint not null default 50,         -- tie-break when several playbooks match (higher wins)
  track text not null default 'SALES' check (track in ('SALES', 'PARTNERSHIP', 'EVENT')),
  owner_role text not null default 'SALES',
  ideal_prospect text,
  decision_roles text[] not null default '{}',
  product_codes text[] not null default '{}',
  value_proposition text,
  services text[] not null default '{}',
  research_questions text[] not null default '{}',
  outreach_approach text,
  follow_up_sequence jsonb not null default '[]',
  proposal_type text,
  objections jsonb not null default '[]',
  proof_required text[] not null default '{}',
  upsells text[] not null default '{}',
  partnership_potential text,
  target_orgs jsonb not null default '[]',       -- [{org_role, why, product, track}] — one event, several commercial targets
  updated_at timestamptz not null default now()
);
alter table public.commercial_playbooks enable row level security;

-- ---------------------------------------------------------------- intelligence (signals) — extend the table workflow 09 writes
alter table public.intelligence add column if not exists stage text not null default 'WATCH'
  check (stage in ('WATCH', 'RESEARCH', 'QUALIFIED', 'ACTIVE', 'DISMISSED'));
alter table public.intelligence add column if not exists category text
  check (category in ('SPORTS', 'EVENTS', 'HOSPITALITY', 'BRANDS', 'PRODUCTION', 'CORPORATE', 'PRIVATE_UHNW', 'ENTERTAINMENT', 'WEDDINGS', 'TRAVEL', 'REAL_ESTATE', 'LUXURY_GOODS', 'OTHER'));
alter table public.intelligence add column if not exists region text check (region in ('EGYPT', 'UK', 'EUROPE', 'MIDDLE_EAST', 'GLOBAL'));
alter table public.intelligence add column if not exists event_date date;
alter table public.intelligence add column if not exists event_end date;
alter table public.intelligence add column if not exists playbook_code text references public.commercial_playbooks(code) on update cascade;
alter table public.intelligence add column if not exists product_codes text[] not null default '{}';
alter table public.intelligence add column if not exists services text[] not null default '{}';
alter table public.intelligence add column if not exists commercial_angle text;
alter table public.intelligence add column if not exists problem_noya_solves text;
alter table public.intelligence add column if not exists decision_roles text[] not null default '{}';
alter table public.intelligence add column if not exists owner text;
alter table public.intelligence add column if not exists next_action text;
alter table public.intelligence add column if not exists next_action_due date;
alter table public.intelligence add column if not exists provenance text not null default 'INFERRED'
  check (provenance in ('VERIFIED', 'SOURCE_BACKED', 'INFERRED', 'NEEDS_VERIFICATION', 'MANUALLY_CONFIRMED'));
alter table public.intelligence add column if not exists analysed_at timestamptz;
alter table public.intelligence add column if not exists analysis_model text;
alter table public.intelligence add column if not exists analysis jsonb;        -- raw structured analysis, kept for traceability
alter table public.intelligence add column if not exists dismissed_reason text;
alter table public.intelligence add column if not exists stage_changed_at timestamptz;
alter table public.intelligence add column if not exists captured_by text;      -- 'workflow 09' / 'HQ (Adam)' / ...

-- Organisations involved in a signal (organiser, sponsor, brand, agency, hotel, ...). One event, many targets.
create table if not exists public.signal_organisations (
  id uuid primary key default gen_random_uuid(),
  signal_id uuid not null references public.intelligence(id) on delete cascade,
  company_id uuid references public.companies(id) on delete set null,
  org_name text not null,
  org_role text not null default 'OTHER' check (org_role in ('ORGANISER', 'PROMOTER', 'SPONSOR', 'BRAND', 'AGENCY', 'PR', 'HOTEL', 'VENUE', 'OPERATOR',
                                                           'DEVELOPER', 'PRODUCTION', 'TALENT_AGENCY', 'TEAM', 'GOVERNMENT', 'OTHER')),
  evidence text,                 -- the phrase in the source that names them
  source_url text,
  provenance text not null default 'INFERRED' check (provenance in ('VERIFIED', 'SOURCE_BACKED', 'INFERRED', 'NEEDS_VERIFICATION', 'MANUALLY_CONFIRMED')),
  created_at timestamptz not null default now()
);
create unique index if not exists signal_organisations_uniq on public.signal_organisations (signal_id, lower(org_name), org_role);
alter table public.signal_organisations enable row level security;

-- ---------------------------------------------------------------- opportunities — commercial fields + money you can defend
alter table public.opportunities add column if not exists signal_id uuid references public.intelligence(id) on delete set null;
alter table public.opportunities add column if not exists product_code text references public.commercial_products(code) on update cascade;
alter table public.opportunities add column if not exists playbook_code text references public.commercial_playbooks(code) on update cascade;
alter table public.opportunities add column if not exists track text not null default 'SALES' check (track in ('SALES', 'PARTNERSHIP', 'EVENT'));
alter table public.opportunities add column if not exists target_role text;       -- their role around the signal (ORGANISER, SPONSOR, ...)
alter table public.opportunities add column if not exists commercial_trigger text;
alter table public.opportunities add column if not exists angle text;
alter table public.opportunities add column if not exists next_action_due date;
alter table public.opportunities add column if not exists source_partner_id uuid;  -- partnership that generated it (FK added below)
alter table public.opportunities add column if not exists client_budget numeric;
alter table public.opportunities add column if not exists proposal_value numeric;
alter table public.opportunities add column if not exists contracted_value numeric;
alter table public.opportunities add column if not exists value_evidence text;
alter table public.opportunities add column if not exists legacy_ai_estimate numeric;     -- AI guesses kept for audit, never shown as money
alter table public.opportunities add column if not exists legacy_ai_probability smallint;
alter table public.opportunities add column if not exists score_override smallint check (score_override between 0 and 100);
alter table public.opportunities add column if not exists score_override_reason text;
alter table public.opportunities add column if not exists score_override_by text;
alter table public.opportunities add column if not exists score_override_at timestamptz;
alter table public.opportunities add column if not exists provenance text not null default 'INFERRED'
  check (provenance in ('VERIFIED', 'SOURCE_BACKED', 'INFERRED', 'NEEDS_VERIFICATION', 'MANUALLY_CONFIRMED'));
alter table public.opportunities add column if not exists won_at timestamptz;
create index if not exists opportunities_signal_idx on public.opportunities (signal_id);
create unique index if not exists opportunities_signal_target_uniq on public.opportunities (signal_id, company_id, coalesce(product_code, ''))
  where signal_id is not null and company_id is not null;

alter table public.companies add column if not exists legacy_ai_estimate numeric;

-- NO FAKE PIPELINE. estimated_value is now *derived*: contracted value, else proposal value, else a budget the
-- client stated — each needs written evidence. Anything else a workflow writes (an AI guess) is moved to
-- legacy_ai_estimate and never shown as money. probability is never stored. Existing readers of
-- estimated_value (HQ, workflow 11 brief) therefore only ever see defensible numbers.
create or replace function public.opportunity_money_guard()
returns trigger language plpgsql as $$
begin
  if new.estimated_value is not null and new.estimated_value is distinct from coalesce(new.contracted_value, new.proposal_value, new.client_budget) then
    new.legacy_ai_estimate := new.estimated_value;
  end if;
  if new.probability is not null then new.legacy_ai_probability := new.probability; new.probability := null; end if;
  if coalesce(new.contracted_value, new.proposal_value, new.client_budget) is not null and nullif(btrim(coalesce(new.value_evidence, '')), '') is null then
    raise exception 'VALUE_NEEDS_EVIDENCE' using hint = 'A budget, proposal or contract value needs written evidence (who said it, where).';
  end if;
  new.estimated_value := coalesce(new.contracted_value, new.proposal_value, new.client_budget);
  if new.status = 'WON' and (tg_op = 'INSERT' or old.status is distinct from 'WON') then new.won_at := coalesce(new.won_at, now()); end if;
  return new;
end $$;
drop trigger if exists opportunity_money_guard on public.opportunities;
create trigger opportunity_money_guard before insert or update on public.opportunities
  for each row execute function public.opportunity_money_guard();

create or replace function public.company_money_guard()
returns trigger language plpgsql as $$
begin
  if new.estimated_value is not null then new.legacy_ai_estimate := new.estimated_value; new.estimated_value := null; end if;
  return new;
end $$;
drop trigger if exists company_money_guard on public.companies;
create trigger company_money_guard before insert or update on public.companies
  for each row execute function public.company_money_guard();

-- Apply the guard to what is already stored (values kept in legacy columns, audited).
insert into public.approval_audit (action, result, actor, detail)
select 'NO_FAKE_PIPELINE', 'OK', 'system (commercial core)',
       jsonb_build_object('opportunities_with_ai_value', count(*) filter (where estimated_value is not null),
                          'ai_value_total', sum(estimated_value), 'with_ai_probability', count(*) filter (where probability is not null),
                          'note', 'AI estimates moved to legacy_ai_estimate / legacy_ai_probability; not shown as pipeline.')
from public.opportunities;
update public.opportunities set updated_at = updated_at where estimated_value is not null or probability is not null;
update public.companies set updated_at = updated_at where estimated_value is not null;

-- Track: partnership pursuits vs direct sales (one CRM, different playbooks and owners).
update public.opportunities set track = 'PARTNERSHIP'
 where track = 'SALES' and (opportunity_type ~* 'partner|white_label|introduction channel|member_community|concierge_partnership');

-- ---------------------------------------------------------------- partnerships — extend company_relationships (was empty)
alter table public.company_relationships add column if not exists partner_class text check (partner_class in ('SUPPLY', 'DISTRIBUTION'));
alter table public.company_relationships add column if not exists partner_category text;
alter table public.company_relationships add column if not exists stage text not null default 'TARGET'
  check (stage in ('TARGET', 'QUALIFIED', 'CONTACTED', 'CONVERSATION', 'VALUE_EXCHANGE', 'PROPOSED', 'PILOT', 'ACTIVE', 'PRODUCTIVE', 'STRATEGIC', 'DORMANT', 'LOST'));
alter table public.company_relationships add column if not exists geography text;
alter table public.company_relationships add column if not exists provides_noya text;
alter table public.company_relationships add column if not exists noya_provides text;
alter table public.company_relationships add column if not exists commercial_terms text;
alter table public.company_relationships add column if not exists preferred_rates text;
alter table public.company_relationships add column if not exists commission_structure text;
alter table public.company_relationships add column if not exists exclusivity text;
alter table public.company_relationships add column if not exists services text[] not null default '{}';
alter table public.company_relationships add column if not exists next_action text;
alter table public.company_relationships add column if not exists next_action_due date;
alter table public.company_relationships add column if not exists stage_evidence text;
alter table public.company_relationships add column if not exists provenance text not null default 'MANUALLY_CONFIRMED'
  check (provenance in ('VERIFIED', 'SOURCE_BACKED', 'INFERRED', 'NEEDS_VERIFICATION', 'MANUALLY_CONFIRMED'));
alter table public.company_relationships add column if not exists updated_at timestamptz not null default now();
create unique index if not exists company_relationships_partner_uniq on public.company_relationships (company_id, partner_class) where partner_class is not null;
do $$ begin
  alter table public.opportunities add constraint opportunities_source_partner_fk foreign key (source_partner_id) references public.company_relationships(id) on delete set null;
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------- operations — projects (won work) and their items
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid unique references public.opportunities(id) on delete set null,
  company_id uuid references public.companies(id) on delete set null,
  signal_id uuid references public.intelligence(id) on delete set null,
  name text not null,
  project_type text,
  destination text,
  starts_on date,
  ends_on date,
  status text not null default 'CONFIRMED' check (status in ('CONFIRMED', 'PLANNING', 'LIVE', 'DELIVERED', 'CLOSED', 'CANCELLED')),
  brief text,
  attendees int,
  owner text,
  currency text,
  client_charge numeric,          -- what the client pays (from the contract)
  supplier_cost numeric,          -- sum NOYA pays suppliers (entered as confirmed)
  gross_profit numeric generated always as (client_charge - supplier_cost) stored,
  feedback text,
  delivered_at timestamptz,
  provenance text not null default 'MANUALLY_CONFIRMED' check (provenance in ('VERIFIED', 'SOURCE_BACKED', 'INFERRED', 'NEEDS_VERIFICATION', 'MANUALLY_CONFIRMED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.projects enable row level security;

create table if not exists public.project_items (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  item_type text not null check (item_type in ('GUEST', 'VIP', 'FLIGHT', 'HOTEL', 'VILLA', 'TRANSFER', 'RESTAURANT', 'VENUE', 'ENTERTAINMENT',
                                               'PRODUCTION', 'SECURITY', 'SUPPLIER', 'SCHEDULE', 'APPROVAL', 'RUN_OF_SHOW', 'ISSUE', 'FEEDBACK', 'OTHER')),
  title text not null,
  detail text,
  supplier_company_id uuid references public.companies(id) on delete set null,
  starts_at timestamptz,
  status text not null default 'OPEN' check (status in ('OPEN', 'CONFIRMED', 'DONE', 'ISSUE', 'CANCELLED')),
  cost numeric,
  charge numeric,
  currency text,
  owner text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists project_items_project_idx on public.project_items (project_id);
alter table public.project_items enable row level security;

alter table public.tasks add column if not exists project_id uuid references public.projects(id) on delete set null;
alter table public.tasks add column if not exists signal_id uuid references public.intelligence(id) on delete set null;
alter table public.revenue add column if not exists project_id uuid references public.projects(id) on delete set null;

-- ---------------------------------------------------------------- relationship graph — only from real records
create table if not exists public.relationship_edges (
  id uuid primary key default gen_random_uuid(),
  from_type text not null check (from_type in ('PERSON', 'COMPANY', 'EVENT', 'OPPORTUNITY', 'PROJECT', 'DESTINATION', 'SERVICE', 'TEAM_MEMBER')),
  from_id uuid, from_label text not null,
  relation text not null check (relation in ('WORKS_AT', 'WORKS_WITH', 'INTRODUCED', 'REFERRED', 'PARTNER_OF_NOYA', 'CLIENT_OF_NOYA', 'SPONSORS',
                                             'ORGANISES', 'INVOLVED_IN', 'SUPPLIES', 'KNOWS', 'EMAILED', 'DELIVERED_FOR')),
  to_type text not null check (to_type in ('PERSON', 'COMPANY', 'EVENT', 'OPPORTUNITY', 'PROJECT', 'DESTINATION', 'SERVICE', 'TEAM_MEMBER')),
  to_id uuid, to_label text not null,
  evidence_source text not null check (evidence_source in ('EMAIL', 'CRM', 'LINKEDIN', 'NOTE', 'PROJECT', 'SOURCE', 'MANUAL')),
  evidence_ref text,
  provenance text not null default 'MANUALLY_CONFIRMED' check (provenance in ('VERIFIED', 'SOURCE_BACKED', 'INFERRED', 'NEEDS_VERIFICATION', 'MANUALLY_CONFIRMED')),
  created_by text,
  created_at timestamptz not null default now()
);
create unique index if not exists relationship_edges_uniq on public.relationship_edges (from_type, coalesce(from_id::text, lower(from_label)), relation, to_type, coalesce(to_id::text, lower(to_label)));
alter table public.relationship_edges enable row level security;

-- ---------------------------------------------------------------- configurable score weights (sum 100)
insert into public.system_config (key, value)
values ('opportunity_score_weights', '{"strategic_fit": 25, "timing": 20, "service_fit": 20, "access": 15, "commercial_evidence": 10, "source_confidence": 10}'::jsonb)
on conflict (key) do nothing;
