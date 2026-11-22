-- NOYA daily acquisition policy (Adam, 22 Nov 2026), implemented inside the existing OS.
--
-- What this adds (no HQ redesign, no new architecture):
--   * daily_outreach_queue / daily_outreach_runs: Today's 25, Reserve, Needs contact and Needs draft, built from what the existing stack
--     already produces (W18 drafts in outreach_candidates, approved Gmail drafts in outbound_emails, the route cache, the CRM).
--   * outreach_queue_build(): the 11 send-ready gates, one company / one route, DNC, warm work excluded from the cold queue, strongest mix
--     guided (never forced) by acquisition_engine.portfolio_guide. pg_cron: MORNING build before the Cairo business day, hourly TOPUP.
--   * hq_outreach_lanes() / hq_outreach_draft(): small, admin-gated light reads for HQ Outreach (no global snapshot).
--   * Send ramp 5 -> 10 -> 15 -> 20 -> 25 a day, released only while SPF, DKIM and DMARC pass and bounce, reputation and complaint
--     signals are clean. The allowance is advice for Adam's manual sending: nothing here sends, drafts or creates an email or task.
--   * outreach_learning: clean-cohort ledger (dimensions + delivered / bounce / reply / positive / meeting / brief / proposal / win / revenue)
--     and learned ranking weights that switch on only after 20 clean sends per cell.
--
-- Applied to production in parts on 22 Nov 2026 (daily_acquisition_policy_part_a, _part_b, _part_c, _builder_person_route, _builder_fast,
-- _lanes_trim, outreach_lanes_follow_up_rule_text); this file is the consolidated final state.
--
-- Safety: every function here only reads the CRM and writes its own queue, run, ramp-state and ledger rows. No function inserts into
-- outbound_emails, tasks or message_drafts, calls Gmail, or changes an opportunity. Idempotent (create or replace / if not exists).

-- 0. Email authentication vocabulary. HQ reads gate = PASS / CLOSED; a check recorded as OPEN is stored as PASS.
create or replace function public.email_auth_normalise() returns trigger
 language plpgsql set search_path to 'public'
as $$
begin
  if new.key = 'email_authentication' and new.value->'last_live_check'->>'gate' = 'OPEN' then
    new.value := jsonb_set(new.value, '{last_live_check,gate}', '"PASS"'::jsonb);
  end if;
  return new;
end $$;
create or replace trigger system_config_email_auth_normalise
  before insert or update on public.system_config for each row when (new.key = 'email_authentication')
  execute function public.email_auth_normalise();
update public.system_config set value = value where key = 'email_authentication';

create or replace function public.email_auth_state() returns jsonb
 language sql stable security definer set search_path to 'public'
as $$
  select jsonb_build_object('spf', c->>'spf', 'dkim', c->>'dkim', 'dmarc', c->>'dmarc', 'checked_at', c->>'at', 'gate', c->>'gate',
           'pass', coalesce(c->>'spf', '') ~* '^PASS' and coalesce(c->>'dkim', '') ~* '^PASS' and coalesce(c->>'dmarc', '') ~* '^PASS',
           'fresh', coalesce(nullif(c->>'at', '')::timestamptz > now() - interval '8 days', false))
    from (select value->'last_live_check' c from system_config where key = 'email_authentication') x
$$;

-- 1. Commercial coverage: 36 streams -> the 13 categories Adam named; categories -> the portfolio guide groups (a guide, never a quota).
create table if not exists public.outreach_categories (
  code text primary key,
  label text not null,
  guide_group text not null,
  sort smallint not null
);
alter table public.outreach_categories enable row level security;
insert into public.outreach_categories (code, label, guide_group, sort) values
  ('TRAVEL_ADVISORS_DMC', 'Luxury travel agencies / advisors / DMCs', 'travel_concierge_dmc', 1),
  ('CLUBS_FOUNDERS', 'Private members clubs / founder networks', 'clubs_founder_investor', 2),
  ('WEDDINGS_EVENTS', 'Wedding planners / private events', 'weddings_private_events', 3),
  ('AGENCIES', 'Marketing / PR / creative / experiential agencies', 'marketing_pr_experiential_consultancy', 4),
  ('CONSULTANCIES', 'Consultancies / advisory firms', 'marketing_pr_experiential_consultancy', 5),
  ('BRANDS', 'Brands', 'brands', 6),
  ('FOOTBALL_SPORTS', 'Football / sports management', 'football_talent_celebrity_mgmt', 7),
  ('TALENT_MGMT', 'Celebrity / talent management', 'football_talent_celebrity_mgmt', 8),
  ('PRIVATE_CLIENT_MULTIPLIERS', 'Private client multipliers / family offices', 'hospitality_private_client_sourcing_other', 9),
  ('CORPORATE_EXEC_LANDING', 'Corporate / executive landing', 'corporate_executive_landing', 10),
  ('HOTELS_RESIDENCES', 'Hotels / branded residences', 'hospitality_private_client_sourcing_other', 11),
  ('RETREATS_OFFSITES', 'Retreats / offsites', 'corporate_executive_landing', 12),
  ('SOURCING', 'Sourcing / collectibles', 'hospitality_private_client_sourcing_other', 13)
on conflict (code) do update set label = excluded.label, guide_group = excluded.guide_group, sort = excluded.sort;

create table if not exists public.outreach_coverage (
  stream_code text primary key references public.commercial_streams(code),
  category text not null references public.outreach_categories(code)
);
alter table public.outreach_coverage enable row level security;
insert into public.outreach_coverage (stream_code, category) values
  ('TRAVEL_ADVISORS', 'TRAVEL_ADVISORS_DMC'), ('CONCIERGE_COMPANIES', 'TRAVEL_ADVISORS_DMC'), ('DMC_WHITE_LABEL', 'TRAVEL_ADVISORS_DMC'),
  ('PRIVATE_CLUBS', 'CLUBS_FOUNDERS'),
  ('WEDDINGS', 'WEDDINGS_EVENTS'), ('PRIVATE_CELEBRATIONS', 'WEDDINGS_EVENTS'),
  ('PR_AGENCIES', 'AGENCIES'), ('EXPERIENTIAL_AGENCIES', 'AGENCIES'), ('MEDIA_PRODUCTION', 'AGENCIES'), ('FILM_TV', 'AGENCIES'), ('CREATOR_TRIPS', 'AGENCIES'),
  ('FASHION_LUXURY', 'BRANDS'), ('BEAUTY', 'BRANDS'), ('FRAGRANCE', 'BRANDS'), ('JEWELLERY_WATCHES', 'BRANDS'), ('LUXURY_AUTOMOTIVE', 'BRANDS'),
  ('STREETWEAR', 'BRANDS'), ('PRODUCT_LAUNCHES', 'BRANDS'),
  ('ATHLETES_FOOTBALL', 'FOOTBALL_SPORTS'), ('SPORT_ENTERTAINMENT_EVENTS', 'FOOTBALL_SPORTS'),
  ('CELEBRITY_ENTERTAINMENT', 'TALENT_MGMT'),
  ('PRIVATE_CLIENTS', 'PRIVATE_CLIENT_MULTIPLIERS'),
  ('EXECUTIVE_LANDING', 'CORPORATE_EXEC_LANDING'), ('GLOBAL_MOBILITY', 'CORPORATE_EXEC_LANDING'), ('EXECUTIVE_SEARCH', 'CORPORATE_EXEC_LANDING'),
  ('CORPORATE_TRAVEL', 'CORPORATE_EXEC_LANDING'), ('CORPORATE_EVENTS', 'CORPORATE_EXEC_LANDING'), ('INCENTIVES', 'CORPORATE_EXEC_LANDING'),
  ('EXECUTIVE_HOSPITALITY', 'CORPORATE_EXEC_LANDING'),
  ('HOTELS', 'HOTELS_RESIDENCES'), ('RESORTS', 'HOTELS_RESIDENCES'), ('VILLAS', 'HOTELS_RESIDENCES'), ('BRANDED_RESIDENCES', 'HOTELS_RESIDENCES'),
  ('RETREATS', 'RETREATS_OFFSITES'), ('LEADERSHIP_OFFSITES', 'RETREATS_OFFSITES'),
  ('SOURCING', 'SOURCING')
on conflict (stream_code) do update set category = excluded.category;

-- Consultancies and family offices are identified by the company type (no stream of their own); otherwise the stream decides.
create or replace function public.outreach_category(p_stream text, p_company_type text) returns text
 language sql stable set search_path to 'public'
as $$
  select case when coalesce(p_company_type, '') ~* '(family.?office|wealth manag|private bank)' then 'PRIVATE_CLIENT_MULTIPLIERS'
              when coalesce(p_company_type, '') ~* 'consult' and coalesce(p_company_type, '') !~* '(wedding|event plan)' then 'CONSULTANCIES'
              else (select category from outreach_coverage where stream_code = p_stream) end
$$;

-- Truthful route source type: where the address was actually found. Never upgrades a Clay or Instagram address.
create or replace function public.outreach_source_type(p_src_type text, p_src_url text, p_website text, p_provider text) returns text
 language sql immutable
as $$
  select case
    when p_src_type in ('INSTAGRAM', 'INSTAGRAM_PROFILE') or coalesce(p_src_url, '') ~* 'instagram\.com' then 'INSTAGRAM_PUBLIC'
    when p_src_type = 'CLAY' then 'CLAY'
    when coalesce(p_src_url, '') ~* 'fifa\.com' then 'FIFA_AGENT_REGISTER'
    when p_src_type = 'LINKEDIN' or coalesce(p_src_url, '') ~* 'linkedin\.com' then 'LINKEDIN'
    when p_src_type in ('OFFICIAL_SITE', 'PARTNERSHIP_PAGE') then 'OFFICIAL_WEBSITE'
    when p_src_type in ('PRESS', 'INTERVIEW') then 'PRESS'
    when p_src_type in ('MEDIA_KIT', 'SPEAKER_PAGE') then 'PUBLIC_DOCUMENT'
    when p_src_type = 'SEARCH_RESULT' then 'WEB_SEARCH'
    when p_src_type = 'MANUAL' then 'ADAM'
    when p_src_type = 'PROVIDER' or (p_provider is not null and coalesce(p_src_url, '') = '') then 'VERIFICATION_PROVIDER'
    when coalesce(p_src_url, '') ~ '^https?://' and length(split_part(regexp_replace(lower(coalesce(p_website, '')), '^https?://(www\.)?', ''), '/', 1)) > 3
         and position(split_part(regexp_replace(lower(p_website), '^https?://(www\.)?', ''), '/', 1) in lower(p_src_url)) > 0 then 'OFFICIAL_WEBSITE'
    when coalesce(p_src_url, '') ~ '^https?://' then 'WEB'
  end
$$;

create or replace function public.outreach_role_bucket(p text) returns text
 language sql immutable
as $$
  select case
    when p is null or btrim(p) = '' then 'TEAM_OR_UNKNOWN'
    when p ~* '(founder|owner)' then 'FOUNDER_OWNER'
    when p ~* '(\mceo\M|chief|president|\mcoo\M|\mcmo\M|\mcco\M|managing director|\mmd\M|general manager|\mgm\M|managing partner)' then 'C_SUITE_MD'
    when p ~* '(talent|artist|player|football|athlete|\magent\M|representation)' then 'AGENT_MANAGEMENT'
    when p ~* '(director|head of|\mvp\M|vice president|partner)' then 'DIRECTOR_HEAD'
    when p ~* '(assistant|\mpa\M|\mea\M|office manager|chief of staff)' then 'ASSISTANT_GATEKEEPER'
    when p ~* '(manager|lead|planner|producer|curator|coordinator)' then 'MANAGER_LEAD'
    else 'OTHER' end
$$;

create or replace function public.outreach_angle_bucket(t text) returns text
 language sql immutable
as $$
  select case
    when t is null or btrim(t) = '' then 'UNSPECIFIED'
    when t ~* '(referral|white.?label|preferred partner|partnership|commission|reciprocal)' then 'PARTNERSHIP_MODEL'
    when t ~* '(shoot|campaign|activation|launch|creator|influencer|production|film)' then 'BRAND_PROJECT'
    when t ~* '(wedding|celebration|anniversary|birthday)' then 'PRIVATE_EVENT'
    when t ~* '(retreat|offsite|off-site|incentive|summit|conference|delegation)' then 'GROUP_PROGRAMME'
    when t ~* '(member|club|community|founder)' then 'COMMUNITY_EXPERIENCE'
    when t ~* '(athlete|player|talent|artist|celebrit)' then 'TALENT_DESK'
    when t ~* '(relocat|landing|executive|mobility)' then 'EXECUTIVE_LANDING'
    when t ~* '(egypt|cairo|giza|nile|red sea|luxor|aswan|sahel|gouna)' then 'EGYPT_GROUND'
    else 'OTHER' end
$$;

-- Regional timing (acquisition_engine.regional_timing): Egypt / GCC work Sun-Thu; UK, Europe and the rest Mon-Fri. Saturday: none.
create or replace function public.outreach_market_open(p_market text, p_dow int) returns boolean
 language sql immutable
as $$
  select case when p_dow = 6 then false
              when coalesce(p_market, 'UNKNOWN') in ('EGYPT', 'GCC') then p_dow between 0 and 4
              else p_dow between 1 and 5 end
$$;

-- 2. The queue and its daily run record.
create table if not exists public.daily_outreach_queue (
  id uuid primary key default gen_random_uuid(),
  run_date date not null,
  lane text not null check (lane in ('TODAY', 'RESERVE', 'NEEDS_CONTACT', 'NEEDS_DRAFT')),
  rank integer,
  state text not null default 'QUEUED' check (state in ('QUEUED', 'REBUILDING', 'SENT', 'DROPPED')),
  state_reason text,
  state_at timestamptz,
  mode text,
  opportunity_id uuid not null references public.opportunities(id),
  company_id uuid references public.companies(id),
  contact_id uuid,
  route_contact_id uuid,
  candidate_id uuid,
  task_id uuid,
  outbound_email_id uuid,
  category text,
  stream text,
  market text,
  person text,
  position text,
  company text,
  project_idea text,
  why_now text,
  route_email text,
  route_canonical text,
  route_label text,
  route_source_url text,
  route_source_type text,
  confidence text check (confidence in ('HIGH', 'MEDIUM', 'LOW')),
  draft_subject text,
  draft_excerpt text,
  draft_status text,
  gmail_draft_id text,
  next_action text,
  gates jsonb not null,
  failed text[] not null default '{}',
  score numeric,
  score_parts jsonb,
  sendable_today boolean,
  send_window text,
  dims jsonb,
  first_built_at timestamptz not null default now(),
  built_at timestamptz not null default now(),
  unique (run_date, opportunity_id),
  -- Today's 25 and the Reserve only ever hold records that passed all 11 gates.
  constraint daily_outreach_queue_ready_gates check (lane not in ('TODAY', 'RESERVE') or cardinality(failed) = 0)
);
-- One company, one active route: a company appears at most once among the day's live Today / Reserve rows.
create unique index if not exists daily_outreach_queue_one_route
  on public.daily_outreach_queue (run_date, company_id) where lane in ('TODAY', 'RESERVE') and state = 'QUEUED';
create index if not exists daily_outreach_queue_lane on public.daily_outreach_queue (run_date, lane, state, rank);
alter table public.daily_outreach_queue enable row level security;

create table if not exists public.daily_outreach_runs (
  run_date date primary key,
  morning_at timestamptz,
  built_at timestamptz not null default now(),
  mode text,
  runs integer not null default 0,
  duration_ms integer,
  funnel jsonb,
  by_category jsonb,
  gate_failures jsonb,
  shortfall integer,
  bottleneck text
);
alter table public.daily_outreach_runs enable row level security;

-- 3. Clean-cohort learning ledger: one row per cold first touch (the first outbound email of an opportunity, before any inbound).
create table if not exists public.outreach_learning (
  opportunity_id uuid primary key references public.opportunities(id),
  company_id uuid,
  contact_id uuid,
  sent_at timestamptz not null,
  cohort text not null check (cohort in ('CLEAN', 'PRE_AUTH', 'EXCLUDED_21_NOV')),
  queue_id uuid,
  dims_source text not null default 'DERIVED' check (dims_source in ('QUEUE', 'DERIVED')),
  stream text, category text, account_type text, dm_role text, source text, route_type text, hypothesis text, angle text,
  delivered boolean not null default false,
  bounced boolean not null default false,
  replied boolean not null default false,
  positive boolean not null default false,
  meeting boolean not null default false,
  brief boolean not null default false,
  proposal boolean not null default false,
  won boolean not null default false,
  revenue numeric,
  first_reply_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.outreach_learning enable row level security;

create or replace function public.outreach_learning_refresh() returns jsonb
 language plpgsql security definer set search_path to 'public' set statement_timeout to '50s'
as $$
declare v_start date := coalesce(nullif((select value->>'clean_cohort_start' from system_config where key = 'email_authentication'), '')::date, date '2026-11-22');
        n int;
begin
  with ft as (
    select distinct on (i.opportunity_id) i.opportunity_id, i.contact_id, i.occurred_at sent_at
      from interactions i
     where i.direction = 'OUTBOUND' and i.channel = 'EMAIL' and i.opportunity_id is not null
     order by i.opportunity_id, i.occurred_at),
  cold as (
    select f.*, o.company_id from ft f join opportunities o on o.id = f.opportunity_id
     where coalesce(o.relationship_type, 'COLD') <> 'PARTNER'
       and not exists (select 1 from interactions j left join opportunities oj on oj.id = j.opportunity_id
                        where (j.company_id = o.company_id or oj.company_id = o.company_id) and j.direction = 'INBOUND' and j.occurred_at < f.sent_at)),
  src as (
    select c.opportunity_id, c.company_id, coalesce(c.contact_id, o.contact_id) contact_id, c.sent_at,
           o.primary_stream, o.project_type_canon, o.angle o_angle, o.description, o.status, o.proposal_value, o.client_budget, o.contracted_value, o.won_at,
           co.company_type, co.commercial_class, co.website, k.position, k.email_source_type, k.email_source_url, k.email_verification_provider,
           r.canonical, q.id q_id, q.dims
      from cold c join opportunities o on o.id = c.opportunity_id
      left join companies co on co.id = c.company_id
      left join contacts k on k.id = coalesce(c.contact_id, o.contact_id)
      left join hq_route_cache r on r.opportunity_id = c.opportunity_id
      left join lateral (select q.id, q.dims from daily_outreach_queue q
                          where q.opportunity_id = c.opportunity_id and q.run_date <= (c.sent_at at time zone 'Africa/Cairo')::date
                          order by q.run_date desc, q.built_at desc limit 1) q on true),
  outc as (
    select s.*,
      exists (select 1 from gmail_sync_ledger l where l.opportunity_id = s.opportunity_id and l.classification = 'BOUNCE' and l.received_at >= s.sent_at) bounced,
      least((select min(l.received_at) from gmail_sync_ledger l where l.opportunity_id = s.opportunity_id and l.received_at >= s.sent_at
              and l.classification in ('POSITIVE', 'NEEDS_INFO', 'MEETING_REQUEST', 'NOT_NOW', 'REFERRAL', 'DECLINED', 'UNKNOWN')),
            (select min(i.occurred_at) from interactions i where i.opportunity_id = s.opportunity_id and i.direction = 'INBOUND' and i.occurred_at >= s.sent_at
              and not exists (select 1 from gmail_sync_ledger l where l.interaction_id = i.id and l.classification in ('BOUNCE', 'OUT_OF_OFFICE'))
              and coalesce(i.subject, '') !~* '(undeliverable|delivery status notification|mail delivery|automatic reply|out of office)')) reply_at,
      exists (select 1 from gmail_sync_ledger l where l.opportunity_id = s.opportunity_id and l.received_at >= s.sent_at
               and l.classification in ('POSITIVE', 'MEETING_REQUEST', 'REFERRAL', 'NEEDS_INFO')) l_pos,
      exists (select 1 from gmail_sync_ledger l where l.opportunity_id = s.opportunity_id and l.received_at >= s.sent_at and l.classification = 'MEETING_REQUEST') l_meet
      from src s)
  insert into outreach_learning as t (opportunity_id, company_id, contact_id, sent_at, cohort, queue_id, dims_source,
                                     stream, category, account_type, dm_role, source, route_type, hypothesis, angle,
                                     delivered, bounced, replied, positive, meeting, brief, proposal, won, revenue, first_reply_at, updated_at)
  select x.opportunity_id, x.company_id, x.contact_id, x.sent_at,
         case when (x.sent_at at time zone 'Africa/Cairo')::date = date '2026-11-21' then 'EXCLUDED_21_NOV'
              when (x.sent_at at time zone 'Africa/Cairo')::date >= v_start then 'CLEAN' else 'PRE_AUTH' end,
         x.q_id, case when x.q_id is not null then 'QUEUE' else 'DERIVED' end,
         coalesce(x.dims->>'stream', x.primary_stream),
         coalesce(x.dims->>'category', outreach_category(x.primary_stream, x.company_type)),
         coalesce(x.dims->>'account_type', x.commercial_class, x.company_type),
         coalesce(x.dims->>'dm_role', outreach_role_bucket(x.position)),
         coalesce(x.dims->>'source', outreach_source_type(x.email_source_type, x.email_source_url, x.website, x.email_verification_provider)),
         coalesce(x.dims->>'route_type', x.canonical),
         coalesce(x.dims->>'hypothesis', x.project_type_canon),
         coalesce(x.dims->>'angle', outreach_angle_bucket(coalesce(x.o_angle, x.description))),
         not x.bounced and x.sent_at < now() - interval '24 hours',
         x.bounced, x.reply_at is not null,
         x.l_pos or x.status in ('INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON'),
         x.l_meet or x.status in ('CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON'),
         x.client_budget is not null or x.status in ('PROPOSAL', 'NEGOTIATION', 'WON'),
         x.proposal_value is not null or x.status in ('PROPOSAL', 'NEGOTIATION', 'WON'),
         x.status = 'WON' or x.won_at is not null,
         x.contracted_value, x.reply_at, now()
    from outc x
  on conflict (opportunity_id) do update set
    company_id = excluded.company_id, contact_id = excluded.contact_id, sent_at = excluded.sent_at, cohort = excluded.cohort,
    queue_id = excluded.queue_id, dims_source = excluded.dims_source, stream = excluded.stream, category = excluded.category,
    account_type = excluded.account_type, dm_role = excluded.dm_role, source = excluded.source, route_type = excluded.route_type,
    hypothesis = excluded.hypothesis, angle = excluded.angle, delivered = excluded.delivered, bounced = excluded.bounced,
    replied = excluded.replied, positive = excluded.positive, meeting = excluded.meeting, brief = excluded.brief,
    proposal = excluded.proposal, won = excluded.won, revenue = excluded.revenue, first_reply_at = excluded.first_reply_at, updated_at = now();
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'rows', n, 'clean', (select count(*) from outreach_learning where cohort = 'CLEAN'));
end $$;

-- Learned ranking weights: positive-reply rate per dimension value relative to the clean-cohort average, smoothed, clamped to 0.75-1.35,
-- and only for cells with at least 20 clean sends older than three days. Below that the ranking is not touched.
create or replace function public.outreach_learning_weights() returns jsonb
 language sql stable security definer set search_path to 'public'
as $$
  with base as (select * from outreach_learning where cohort = 'CLEAN' and sent_at < now() - interval '3 days'),
  tot as (select count(*) n, count(*) filter (where positive) p from base),
  cells as (
    select d.dim, d.val, count(*) n, count(*) filter (where b.positive) p
      from base b
      cross join lateral (values ('category', b.category), ('route_type', b.route_type), ('dm_role', b.dm_role), ('source', b.source),
                                 ('angle', b.angle), ('stream', b.stream), ('account_type', b.account_type), ('hypothesis', b.hypothesis)) d(dim, val)
     where d.val is not null group by 1, 2)
  select jsonb_build_object('min_sample', 20, 'clean_sends', t.n, 'clean_positive', t.p,
           'weights', coalesce((select jsonb_object_agg(c.dim || ':' || c.val,
                                  round(least(1.35, greatest(0.75, ((c.p + 1.0) / (c.n + 10)) / ((t.p + 1.0) / (t.n + 10))))::numeric, 3))
                                  from cells c where c.n >= 20), '{}'::jsonb))
    from tot t
$$;

-- 4. Send ramp. State lives in system_config.send_ramp_state; the decision is a pure function so it can be tested without touching data.
insert into public.system_config (key, value, note) values ('send_ramp_state', jsonb_build_object(
  'stages', jsonb_build_array(5, 10, 15, 20, 25), 'stage', 0, 'stage_since', '2026-11-22', 'days_per_stage', 3,
  'max_bounce_rate', 0.03, 'min_sends_for_rate', 20,
  'flags', jsonb_build_object('reputation_warning', false, 'spam_complaints', 0, 'provider_throttling', false, 'suspicious_activity', false,
                              'unexpected_mass_sending', false, 'checked_at', null, 'note', 'Set by the daily operating check from Gmail / Postmaster evidence only.'),
  'stopped', null, 'history', '[]'::jsonb),
  'Acquisition policy 22 Nov 2026: actual cold first-touch sends a day, 5 -> 10 -> 15 -> 20 -> 25, advanced by outreach_ramp_review() only on clean signals. Advice for Adam''s manual sending; nothing sends automatically.')
on conflict (key) do nothing;

create or replace function public.outreach_ramp_decide(p_state jsonb, p_auth jsonb, p_health jsonb) returns jsonb
 language plpgsql immutable
as $$
declare v_stages int[]; v_stage int; v_reasons text[] := '{}';
        v_sends int := coalesce((p_health->>'clean_sends')::int, 0); v_b int := coalesce((p_health->>'clean_bounces')::int, 0);
        v_max numeric := coalesce((p_state->>'max_bounce_rate')::numeric, 0.03); v_min int := coalesce((p_state->>'min_sends_for_rate')::int, 20);
begin
  v_stages := array(select jsonb_array_elements_text(coalesce(p_state->'stages', '[5,10,15,20,25]'::jsonb))::int);
  if coalesce(array_length(v_stages, 1), 0) = 0 then v_stages := array[5, 10, 15, 20, 25]; end if;
  v_stage := least(greatest(coalesce((p_state->>'stage')::int, 0), 0), array_length(v_stages, 1) - 1);
  if not coalesce((p_auth->>'pass')::boolean, false) then v_reasons := v_reasons || 'SPF, DKIM and DMARC must all pass'::text; end if;
  if not coalesce((p_auth->>'fresh')::boolean, false) then v_reasons := v_reasons || 'Authentication re-check due (last check older than 8 days)'::text; end if;
  if (v_sends >= v_min and v_b::numeric / v_sends > v_max) or (v_sends < v_min and v_b > 1) then
    v_reasons := v_reasons || ('Bounces above the limit: ' || v_b || ' of ' || v_sends || ' clean sends'); end if;
  if coalesce((p_health->>'bounces_3d')::int, 0) >= 2 then v_reasons := v_reasons || 'Bounce spike: 2 or more bounces in 3 days'::text; end if;
  if coalesce((p_state->'flags'->>'reputation_warning')::boolean, false) then v_reasons := v_reasons || 'Reputation warning recorded'::text; end if;
  if coalesce((p_state->'flags'->>'spam_complaints')::int, 0) > 0 then v_reasons := v_reasons || 'Spam complaint recorded'::text; end if;
  if coalesce((p_state->'flags'->>'provider_throttling')::boolean, false) then v_reasons := v_reasons || 'Provider throttling recorded'::text; end if;
  if coalesce((p_state->'flags'->>'suspicious_activity')::boolean, false) then v_reasons := v_reasons || 'Suspicious account activity recorded'::text; end if;
  if coalesce((p_state->'flags'->>'unexpected_mass_sending')::boolean, false) then v_reasons := v_reasons || 'Unexpected mass sending recorded'::text; end if;
  if coalesce(p_state->>'stopped', '') <> '' then v_reasons := v_reasons || ('Stopped: ' || (p_state->>'stopped')); end if;
  return jsonb_build_object('stage', v_stage + 1, 'stages', to_jsonb(v_stages), 'cap', v_stages[v_stage + 1],
           'allowed', case when cardinality(v_reasons) = 0 then v_stages[v_stage + 1] else 0 end,
           'status', case when cardinality(v_reasons) = 0 then 'ACTIVE' else 'STOPPED' end, 'reasons', to_jsonb(v_reasons));
end $$;

-- Live health inputs: clean-cohort sends / bounces (ledger) and today's cold first touches (straight from interactions, so it is current).
create or replace function public.outreach_send_health() returns jsonb
 language sql stable security definer set search_path to 'public'
as $$
  with d as (select ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo' day_start),
  st as (select value s from system_config where key = 'send_ramp_state'),
  ft_today as (
    select i.opportunity_id from interactions i join opportunities o on o.id = i.opportunity_id, d
     where i.direction = 'OUTBOUND' and i.channel = 'EMAIL' and i.occurred_at >= d.day_start
       and not exists (select 1 from interactions j where j.opportunity_id = i.opportunity_id and j.direction = 'OUTBOUND' and j.channel = 'EMAIL'
                        and j.occurred_at < i.occurred_at - interval '1 minute')
       and not exists (select 1 from interactions j where j.company_id = o.company_id and j.direction = 'INBOUND' and j.occurred_at < i.occurred_at)
     group by i.opportunity_id),
  out_today as (select count(*) n from interactions i, d where i.direction = 'OUTBOUND' and i.channel = 'EMAIL' and i.occurred_at >= d.day_start)
  select jsonb_build_object(
    'clean_sends', (select count(*) from outreach_learning where cohort = 'CLEAN'),
    'clean_bounces', (select count(*) from outreach_learning where cohort = 'CLEAN' and bounced),
    'bounces_3d', (select count(*) from outreach_learning where cohort = 'CLEAN' and bounced and sent_at > now() - interval '3 days'),
    'first_touches_today', (select count(*) from ft_today),
    'follow_ups_today', greatest((select n from out_today) - (select count(*) from ft_today), 0),
    'days_at_stage', (select count(distinct (l.sent_at at time zone 'Africa/Cairo')::date) from outreach_learning l, st
                       where l.cohort = 'CLEAN' and (l.sent_at at time zone 'Africa/Cairo')::date >= coalesce(nullif(st.s->>'stage_since', '')::date, date '2026-11-22')))
$$;

create or replace function public.outreach_act_now_count() returns integer
 language sql stable security definer set search_path to 'public'
as $$
  with covered as (select unnest(array_append(related_company_ids, company_id)) cid from ceo_actions where status in ('OPEN', 'WAITING'))
  select ((select count(*) from ceo_actions where status = 'OPEN')
        + (select count(distinct g.company_id) from gmail_history_threads g join companies c on c.id = g.company_id left join opportunities o on o.id = g.opportunity_id
            where g.relevant and g.last_direction = 'INBOUND' and g.last_inbound_at > now() - interval '14 days'
              and coalesce(g.hq_status, '') <> 'DISMISSED' and coalesce(c.relationship_status, '') <> 'supplier'
              and (o.id is null or o.status in ('INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON'))
              and not exists (select 1 from covered v where v.cid = g.company_id))
        + (select count(*) from website_enquiries w join opportunities o on o.id = w.created_opportunity_id
            where w.created_at > now() - interval '14 days' and o.status in ('NEW', 'RESEARCHING', 'READY')
              and not exists (select 1 from covered v where v.cid = w.matched_company_id)))::int
$$;

-- Today's allowance for Adam: stage cap if every signal is clean, else 0 with the reasons; send windows spread through the day.
create or replace function public.outreach_send_allowance() returns jsonb
 language plpgsql stable security definer set search_path to 'public'
as $$
declare st jsonb; au jsonb; h jsonb; dc jsonb; v_now timestamp := now() at time zone 'Africa/Cairo'; v_dow int; v_rem int;
        v_from timestamp; v_to timestamp; v_slots jsonb := '[]'::jsonb; v_markets jsonb; v_warm int; v_mode text;
begin
  select value into st from system_config where key = 'send_ramp_state';
  au := email_auth_state(); h := outreach_send_health();
  dc := outreach_ramp_decide(coalesce(st, '{}'::jsonb), coalesce(au, '{}'::jsonb), h);
  v_dow := extract(dow from v_now)::int;
  v_markets := case v_dow when 6 then '[]'::jsonb when 0 then '["EGYPT","GCC"]'::jsonb when 5 then '["UK","EUROPE","NORTH_AMERICA","REST_OF_WORLD","GLOBAL"]'::jsonb
                    else '["EGYPT","GCC","UK","EUROPE","NORTH_AMERICA","REST_OF_WORLD","GLOBAL"]'::jsonb end;
  v_mode := case when v_dow = 6 then 'NON_BUSINESS_DAY' else dc->>'status' end;
  v_rem := case when v_mode = 'ACTIVE' then greatest((dc->>'allowed')::int - coalesce((h->>'first_touches_today')::int, 0), 0) else 0 end;
  v_from := greatest(v_now, date_trunc('day', v_now) + interval '10 hours');
  v_to := date_trunc('day', v_now) + interval '16 hours 30 minutes';
  if v_rem > 0 and v_from < v_to then
    select coalesce(jsonb_agg(to_char(t - make_interval(mins => (extract(minute from t)::int % 5)), 'HH24:MI') order by g), '[]'::jsonb) into v_slots
      from generate_series(1, v_rem) g cross join lateral (select v_from + (v_to - v_from) * ((g - 0.5) / v_rem) t) x;
  end if;
  v_warm := outreach_act_now_count();
  return jsonb_build_object(
    'mode', v_mode, 'stage', dc->'stage', 'stages', dc->'stages', 'daily_cap', case when v_mode = 'ACTIVE' then dc->'allowed' else to_jsonb(0) end,
    'stage_cap', dc->'cap', 'sent_today', coalesce((h->>'first_touches_today')::int, 0), 'follow_ups_today', coalesce((h->>'follow_ups_today')::int, 0),
    'remaining', v_rem, 'slots', v_slots, 'slot_zone', 'Cairo', 'markets_today', v_markets, 'reasons', dc->'reasons',
    'auth', au, 'health', h, 'flags', st->'flags', 'warm_pending', v_warm,
    'days_per_stage', coalesce((st->>'days_per_stage')::int, 3),
    'rule', 'Nothing is sent automatically. Approving creates an unsent Gmail draft; Adam sends it himself, spread through the day. Warm work comes first.');
end $$;

-- Daily ramp review (cron, before the morning build): step back on a stop signal; advance after days_per_stage clean send days.
create or replace function public.outreach_ramp_review() returns jsonb
 language plpgsql security definer set search_path to 'public'
as $$
declare st jsonb; au jsonb; h jsonb; dc jsonb; v_stage int; v_max int; v_new int; v_why text;
begin
  perform outreach_learning_refresh();
  select value into st from system_config where key = 'send_ramp_state' for update;
  if st is null then return jsonb_build_object('ok', false, 'reason', 'NO_RAMP_STATE'); end if;
  au := email_auth_state(); h := outreach_send_health(); dc := outreach_ramp_decide(st, au, h);
  v_stage := coalesce((st->>'stage')::int, 0); v_max := jsonb_array_length(st->'stages') - 1; v_new := v_stage;
  if dc->>'status' = 'STOPPED' then
    if exists (select 1 from jsonb_array_elements_text(dc->'reasons') r where r ~* '^(Bounce|Spam|Reputation|Provider|Suspicious|Unexpected)') and v_stage > 0 then
      v_new := v_stage - 1; v_why := 'Stepped back: ' || (select string_agg(r, '; ') from jsonb_array_elements_text(dc->'reasons') r);
    end if;
  elsif coalesce((h->>'days_at_stage')::int, 0) >= coalesce((st->>'days_per_stage')::int, 3) and v_stage < v_max then
    v_new := v_stage + 1; v_why := 'Advanced after ' || (h->>'days_at_stage') || ' clean send days with clean signals';
  end if;
  if v_new <> v_stage then
    update system_config set value = jsonb_set(jsonb_set(jsonb_set(value, '{stage}', to_jsonb(v_new)), '{stage_since}', to_jsonb(((now() at time zone 'Africa/Cairo')::date)::text)),
                                              '{history}', coalesce(value->'history', '[]'::jsonb) || jsonb_build_object('at', now(), 'from', v_stage + 1, 'to', v_new + 1, 'why', v_why)),
                             updated_at = now()
     where key = 'send_ramp_state';
  end if;
  return jsonb_build_object('ok', true, 'stage_before', v_stage + 1, 'stage_after', v_new + 1, 'decision', dc, 'why', v_why);
end $$;

-- 5. The builder. MORNING rebuilds the day; TOPUP (hourly) keeps Today's membership, marks Adam's manual sends, drops records that no
-- longer pass (a reply arrived, DNC, hold) and refills only the vacated places from Reserve. Never creates drafts, emails or tasks.
create or replace function public.outreach_queue_build(p_mode text default 'MORNING') returns jsonb
 language plpgsql security definer set search_path to 'public' set statement_timeout to '55s'
as $$
declare
  v_date date := (now() at time zone 'Africa/Cairo')::date;
  v_dow int := extract(dow from (now() at time zone 'Africa/Cairo'))::int;
  v_day_start timestamptz := ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo';
  v_t0 timestamptz := clock_timestamp();
  v_cfg jsonb; v_floor int; v_guide jsonb; v_w jsonb; v_sent_today int; v_slots int; v_marked int;
  v_funnel jsonb; v_cat jsonb; v_fail jsonb; v_today int; v_bottleneck text;
begin
  p_mode := upper(coalesce(p_mode, 'MORNING'));
  if p_mode not in ('MORNING', 'TOPUP') then raise exception 'outreach_queue_build: mode must be MORNING or TOPUP'; end if;
  if not pg_try_advisory_xact_lock(hashtext('outreach_queue_build')) then return jsonb_build_object('ok', false, 'reason', 'BUSY'); end if;
  select value into v_cfg from system_config where key = 'acquisition_engine';
  v_floor := coalesce((v_cfg->>'send_ready_floor')::int, 25);
  v_guide := coalesce(v_cfg->'portfolio_guide', '{}'::jsonb);
  v_w := coalesce(outreach_learning_weights()->'weights', '{}'::jsonb);

  -- 1. Adam's manual sends since the start of the Cairo day stay in the queue as SENT (never rebuilt, never re-offered).
  update daily_outreach_queue q set state = 'SENT', state_at = now(), state_reason = 'First touch sent by Adam from Gmail'
   where q.run_date = v_date and q.state = 'QUEUED'
     and (exists (select 1 from interactions i where i.opportunity_id = q.opportunity_id and i.direction = 'OUTBOUND' and i.channel = 'EMAIL' and i.occurred_at >= v_day_start)
          or exists (select 1 from outbound_emails e where e.opportunity_id = q.opportunity_id and e.status = 'SENT' and coalesce(e.sent_at, e.updated_at) >= v_day_start));
  get diagnostics v_marked = row_count;
  select count(*) into v_sent_today from daily_outreach_queue where run_date = v_date and lane = 'TODAY' and state = 'SENT';
  v_slots := greatest(v_floor - v_sent_today, 0);

  -- 2. Evaluate the live cold universe once against the 11 gates.
  create temp table _e on commit drop as
  with cand as (
    select distinct on (oc.opportunity_id) oc.opportunity_id, oc.id cand_id, oc.contact_id cand_contact, oc.route_contact_id, oc.status cand_status,
           oc.qa_status, oc.first_pass_ok, oc.subject cand_subject, oc.draft cand_draft, oc.why_now cand_why, oc.angle cand_angle, oc.task_id, oc.created_at cand_created
      from outreach_candidates oc
     where not oc.dry_run and oc.channel = 'EMAIL' and oc.opportunity_id is not null and oc.status in ('READY', 'APPROVED', 'REVIEW_REQUIRED', 'HOLD', 'PLANNED')
     order by oc.opportunity_id, (oc.status = 'APPROVED') desc, (oc.status = 'READY') desc, oc.updated_at desc),
  ob as (
    select distinct on (e.opportunity_id) e.opportunity_id, e.id ob_id, e.gmail_draft_id, e.subject ob_subject, e.body ob_body
      from outbound_emails e where e.status in ('QUEUED', 'CLAIMED', 'DRAFTED') and e.opportunity_id is not null
     order by e.opportunity_id, e.created_at desc),
  -- Conflict lookups, computed once (set-based) instead of per account.
  touched as (
    select x.company_id, max(x.at) last_out from (
      select i.company_id, i.occurred_at at from interactions i where i.direction = 'OUTBOUND' and i.company_id is not null
      union all
      select oi.company_id, i.occurred_at from interactions i join opportunities oi on oi.id = i.opportunity_id where i.direction = 'OUTBOUND'
      union all
      select e.company_id, coalesce(e.sent_at, e.created_at) from outbound_emails e where e.status = 'SENT' and e.company_id is not null) x
     group by x.company_id),
  sent_to as (select distinct lower(coalesce(e.sent_to_email, e.to_email)) em from outbound_emails e where e.status = 'SENT' and coalesce(e.sent_to_email, e.to_email) is not null),
  live_other as (select o2.company_id, o2.id from opportunities o2 where o2.status in ('CONTACTED', 'FOLLOW_UP', 'INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION')),
  base as (
    select o.id opportunity_id, o.company_id, o.status, o.priority, o.primary_stream, o.market, o.project_type_canon, o.commercial_trigger, o.reason,
           o.angle o_angle, o.description, o.next_action, o.created_at o_created,
           c.name cname, c.website, c.instagram cinsta, c.linkedin clinked, c.outreach_hold_until, c.company_type, c.commercial_class, c.relationship_status crel,
           cd.cand_id, cd.cand_contact, cd.route_contact_id, cd.cand_status, cd.qa_status, cd.first_pass_ok, cd.cand_subject, cd.cand_draft, cd.cand_why,
           cd.cand_angle, cd.task_id, cd.cand_created, ob.ob_id, ob.gmail_draft_id, ob.ob_subject, ob.ob_body,
           coalesce(cd.cand_contact, o.contact_id) person_id
      from opportunities o join companies c on c.id = o.company_id
      left join cand cd on cd.opportunity_id = o.id left join ob on ob.opportunity_id = o.id
     where o.status in ('NEW', 'RESEARCHING', 'READY') and coalesce(o.relationship_type, 'COLD') = 'COLD'
       and c.merged_into is null and coalesce(c.universe_status, '') not in ('EXCLUDED', 'PARKED')),
  -- The route is the PERSON's route (contact_email_route on the decision maker, exactly as the route cache and W18 evaluate it); when it
  -- resolves to a company inbox, provenance and DNC are read from that inbox contact too. A candidate with no person but a planned company
  -- inbox counts only when that inbox is an official, sourced, non-excluded commercial inbox.
  routed as (
    select b.*, k.first_name, k.last_name, k.position, k.identity_status, k.do_not_contact k_dnc, k.source_url k_src, k.linkedin k_li,
           k.email_source_type k_src_type, k.lead_type k_lead, k.email_status k_status,
           kr.id route_id, kr.do_not_contact kr_dnc, kr.email_status kr_status, kr.email_source_type kr_src_type, kr.email_source_url kr_src_url,
           kr.email_verification_provider kr_provider, rt.r
      from base b
      left join contacts k on k.id = b.person_id
      left join contacts ri on ri.id = b.route_contact_id and b.person_id is null
      left join hq_route_cache h on h.opportunity_id = b.opportunity_id and h.contact_id = b.person_id
      cross join lateral (select case
                                   -- The 10-minute route cache already holds this person's route; recompute only inbox routes (to know which inbox).
                                   when b.person_id is not null and h.opportunity_id is not null
                                        and coalesce(h.raw_state, '') not in ('OFFICIAL_PUBLISHED_INBOX', 'VERIFIED_INBOX', 'VERIFIED_GENERAL')
                                     then jsonb_build_object('state', h.raw_state, 'email', h.email, 'source_url', h.source_url)
                                   when b.person_id is not null then contact_email_route(b.person_id)
                                   when ri.id is not null and ri.route_type = 'COMPANY_INBOX' and ri.email is not null and coalesce(ri.email_source_url, '') ~ '^https?://'
                                        and coalesce(email_local_class(ri.email), '') <> 'EXCLUDED' and coalesce(ri.email_status, '') <> 'INVALID'
                                     then jsonb_build_object('state', 'OFFICIAL_PUBLISHED_INBOX', 'email', ri.email, 'source_url', ri.email_source_url, 'inbox_id', ri.id)
                                   else jsonb_build_object('state', 'NO_PERSON') end r) rt
      left join contacts kr on kr.id = coalesce(case when rt.r->>'inbox_id' ~ '^[0-9a-f-]{36}$' then (rt.r->>'inbox_id')::uuid end, b.person_id)),
  canon as (
    select x.*, case when x.person_id is null and x.r->>'state' = 'OFFICIAL_PUBLISHED_INBOX' then 'OFFICIAL_PUBLISHED_INBOX'
                     else route_canonical(x.r->>'state', x.k_src_type, x.k_lead, x.k_status) end canonical,
           nullif(btrim(x.r->>'email'), '') email,
           coalesce(nullif(x.r->>'source_url', ''), nullif(x.kr_src_url, '')) src_url,
           nullif(btrim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '')), '') person,
           coalesce(nullif(btrim(x.ob_body), ''), x.cand_draft) draft_text, coalesce(nullif(btrim(x.ob_subject), ''), x.cand_subject) draft_subject,
           coalesce(nullif(btrim(x.cand_why), ''), nullif(btrim(x.commercial_trigger), ''), nullif(btrim(x.reason), '')) why_now,
           coalesce(nullif(btrim(x.cand_angle), ''), nullif(btrim(x.o_angle), ''), nullif(btrim(x.description), '')) project_idea,
           split_part(regexp_replace(lower(coalesce(x.cname, '')), '^(the|la|le|el|al)\s+', ''), ' ', 1) ptoken
      from routed x),
  typed as (
    select y.*, outreach_source_type(y.kr_src_type, y.src_url, y.website, y.kr_provider) src_type,
           outreach_category(y.primary_stream, y.company_type) category
      from canon y),
  gated as (
    select t.*,
      ((t.website is not null or t.cinsta is not null or t.clinked is not null)
        and ((t.person is not null and (t.identity_status = 'CONFIRMED' or (t.identity_status is null and coalesce(t.k_src, t.k_li, '') <> '')))
             or (t.person is null and t.canonical = 'OFFICIAL_PUBLISHED_INBOX'))) g1,
      (t.website is not null or t.cinsta is not null or t.clinked is not null) account_ok,
      exists (select 1 from commercial_streams s where s.code = t.primary_stream and s.active) g2,
      length(coalesce(t.why_now, '')) >= 25 g3,
      length(coalesce(t.project_idea, '')) >= 25 g4,
      ((t.person is not null and coalesce(role_score(t.position), 0) > 0 and coalesce(t.position, '') !~* '(intern|student|trainee|volunteer|scout|recruit)')
        or (t.person is null and t.canonical = 'OFFICIAL_PUBLISHED_INBOX')) g5,
      (t.canonical in ('VALID_VERIFIED', 'PUBLIC_NAMED_EMAIL', 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM', 'PUBLIC_PROFESSIONAL_EMAIL', 'MANAGEMENT_EMAIL', 'AGENT_EMAIL',
                       'CLAY_WORK_EMAIL', 'OFFICIAL_PUBLISHED_INBOX')
        and t.email is not null and coalesce(email_local_class(t.email), '') <> 'EXCLUDED'
        and split_part(lower(t.email), '@', 1) !~ '^(support|help|helpdesk|careers?|jobs|hr|recruit(ment|ing)?|privacy|legal|dpo|gdpr|reservations?|bookings?|no-?reply|abuse|billing|accounts|invoices?|webmaster)$'
        and coalesce(t.kr_status, '') <> 'INVALID') g6,
      (coalesce(t.src_url, '') ~ '^https?://' or t.kr_src_type in ('CLAY', 'PROVIDER') or t.kr_provider is not null) g7,
      (coalesce(t.canonical, 'UNKNOWN') not in ('UNKNOWN', 'NOT_FOUND', 'INVALID') and t.src_type is not null) g8,
      ((t.cand_status = 'APPROVED' or (t.cand_status = 'READY' and t.qa_status in ('PASS', 'HUMAN_REVIEWED')) or t.ob_id is not null)
        and length(coalesce(t.draft_text, '')) >= 200 and coalesce(t.draft_text, '') !~* '(\{\{|\[name\]|\[company\]|lorem ipsum)'
        and (t.ob_id is not null or t.cand_created > now() - interval '30 days')
        and ((length(t.ptoken) >= 3 and position(t.ptoken in lower(t.draft_text)) > 0)
             or (length(coalesce(t.first_name, '')) >= 2 and position(lower(t.first_name) in lower(t.draft_text)) > 0))) g9,
      length(btrim(coalesce(t.next_action, ''))) > 5 g10,
      (not coalesce(t.k_dnc, false) and not coalesce(t.kr_dnc, false)
        and coalesce(t.outreach_hold_until, '-infinity'::timestamptz) < now()
        and coalesce(t.commercial_class, '') <> 'SUPPLIER'
        and lower(coalesce(t.crel, '')) not in ('supplier', 'client', 'partner', 'do not contact', 'do_not_contact')
        and t.cand_status is distinct from 'HOLD'
        and relationship_state(t.company_id) = 'COLD'
        and not exists (select 1 from live_other lo where lo.company_id = t.company_id and lo.id <> t.opportunity_id)
        and not exists (select 1 from touched tc where tc.company_id = t.company_id and tc.last_out > now() - interval '180 days')
        and (t.email is null or not exists (select 1 from sent_to s where s.em = lower(t.email)))
        and (length(coalesce(t.commercial_trigger, '')) > 20 or not exists (select 1 from touched tc where tc.company_id = t.company_id))) g11
      from typed t),
  scored as (
    select g.*,
      (g.g1 and g.g2 and g.g3 and g.g4 and g.g5 and g.g6 and g.g7 and g.g8 and g.g9 and g.g10 and g.g11) ready,
      array_remove(array[case when not g.g1 then 'real_account_person' end, case when not g.g2 then 'stream' end, case when not g.g3 then 'commercial_reason' end,
                         case when not g.g4 then 'project_hypothesis' end, case when not g.g5 then 'decision_maker' end, case when not g.g6 then 'contact_route' end,
                         case when not g.g7 then 'provenance' end, case when not g.g8 then 'route_classification' end, case when not g.g9 then 'personalised_draft' end,
                         case when not g.g10 then 'next_action' end, case when not g.g11 then 'no_conflict' end], null) failed,
      round(coalesce(g.priority, 50) * 0.5, 1) s_base,
      case g.canonical when 'VALID_VERIFIED' then 15 when 'PUBLIC_NAMED_EMAIL' then 14 when 'MANAGEMENT_EMAIL' then 12 when 'AGENT_EMAIL' then 12
                       when 'PUBLIC_PROFESSIONAL_EMAIL' then 11 when 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM' then 9 when 'OFFICIAL_PUBLISHED_INBOX' then 5
                       when 'CLAY_WORK_EMAIL' then 4 else 0 end s_route,
      least(coalesce(role_score(g.position), 0), 5) * 2 s_role,
      case when length(coalesce(g.commercial_trigger, '')) > 20 then 8 else 0 end s_trigger,
      case when g.cand_status = 'APPROVED' or g.ob_id is not null then 6 when g.first_pass_ok then 4 when g.cand_status = 'READY' then 2 else 0 end s_draft,
      case when g.o_created > now() - interval '7 days' then 3 else 0 end s_fresh,
      case when outreach_market_open(g.market, v_dow) then 2 else 0 end s_market,
      coalesce((select exp(sum(ln((v_w->>k)::numeric))) from unnest(array['category:' || coalesce(g.category, ''), 'route_type:' || coalesce(g.canonical, ''),
                 'dm_role:' || outreach_role_bucket(g.position), 'source:' || coalesce(g.src_type, ''), 'angle:' || outreach_angle_bucket(g.project_idea),
                 'stream:' || coalesce(g.primary_stream, '')]) k where v_w ? k), 1) w_learn,
      (select oc.guide_group from outreach_categories oc where oc.code = g.category) guide_group
      from gated g)
  select s.*, round((s.s_base + s.s_route + s.s_role + s.s_trigger + s.s_draft + s.s_fresh + s.s_market) * s.w_learn, 2) raw from scored s;

  -- 3. Rank: one route per company, then the portfolio guide as a soft diminishing factor (strongest mix, not equal quotas).
  create temp table _rk on commit drop as
  with rdy as (select e.*, row_number() over (partition by e.company_id order by e.raw desc, e.opportunity_id) rn_co from _e e where e.ready),
  div as (select r.*, row_number() over (partition by coalesce(r.guide_group, 'other') order by r.raw desc, r.opportunity_id) k_grp from rdy r where r.rn_co = 1),
  adj as (select d.*, round(d.raw * case when d.k_grp <= coalesce((v_guide->>d.guide_group)::int, 2) then 1
                                         else power(0.88, d.k_grp - coalesce((v_guide->>d.guide_group)::int, 2)) end, 2) adj,
                 exists (select 1 from daily_outreach_queue q where q.run_date = v_date and q.opportunity_id = d.opportunity_id
                          and q.lane = 'TODAY' and q.state = 'QUEUED') was_today
            from div d)
  select a.*, row_number() over (order by (p_mode = 'TOPUP' and a.was_today) desc, a.adj desc, a.opportunity_id) pos from adj a;

  create temp table _lanes on commit drop as
  select 'TODAY'::text lane, r.pos::int rnk, r.opportunity_id, r.adj score_final from _rk r where r.pos <= v_slots
  union all
  select 'RESERVE', r.pos::int, r.opportunity_id, r.adj from _rk r where r.pos > v_slots and r.pos <= v_slots + 100
  union all
  select 'NEEDS_DRAFT', z.rn::int, z.opportunity_id, z.raw from (
    select e.opportunity_id, e.raw, row_number() over (order by e.raw desc, e.opportunity_id) rn
      from (select e1.*, row_number() over (partition by e1.company_id order by e1.raw desc, e1.opportunity_id) rn_co
              from _e e1 where not e1.ready and e1.failed = array['personalised_draft']) e
     where e.rn_co = 1 and e.company_id not in (select company_id from _rk)) z where z.rn <= 60
  union all
  select 'NEEDS_CONTACT', z.rn::int, z.opportunity_id, z.raw from (
    select e.opportunity_id, e.raw, row_number() over (order by e.raw desc, e.opportunity_id) rn
      from (select e1.*, row_number() over (partition by e1.company_id order by e1.raw desc, e1.opportunity_id) rn_co
              from _e e1 where not e1.ready and e1.account_ok and e1.g2 and e1.g3 and e1.g4 and e1.g10 and e1.g11
               and (not e1.g1 or not e1.g5 or not e1.g6 or not e1.g7 or not e1.g8)) e
     where e.rn_co = 1 and e.company_id not in (select company_id from _rk)
       and e.company_id not in (select e2.company_id from _e e2 where not e2.ready and e2.failed = array['personalised_draft'])) z where z.rn <= 60;

  -- 4. Write: rebuild the day's live rows in place (SENT rows are never touched; rows that no longer qualify are DROPPED with history).
  update daily_outreach_queue set state = 'REBUILDING' where run_date = v_date and state = 'QUEUED';
  insert into daily_outreach_queue as q (run_date, lane, rank, state, state_at, mode, opportunity_id, company_id, contact_id, route_contact_id, candidate_id, task_id,
         outbound_email_id, category, stream, market, person, position, company, project_idea, why_now, route_email, route_canonical, route_label,
         route_source_url, route_source_type, confidence, draft_subject, draft_excerpt, draft_status, gmail_draft_id, next_action, gates, failed,
         score, score_parts, sendable_today, send_window, dims, built_at)
  select v_date, l.lane, l.rnk, 'QUEUED', now(), p_mode, e.opportunity_id, e.company_id, e.person_id, e.route_id, e.cand_id, e.task_id,
         e.ob_id, e.category, e.primary_stream, e.market, e.person, e.position, e.cname, left(e.project_idea, 600), left(e.why_now, 600),
         e.email, e.canonical, route_label(e.canonical), e.src_url, e.src_type,
         case when e.canonical in ('UNKNOWN', 'NOT_FOUND', 'INVALID') or e.canonical is null then null
              when e.canonical = 'VALID_VERIFIED' then 'HIGH'
              when e.canonical in ('PUBLIC_NAMED_EMAIL', 'MANAGEMENT_EMAIL', 'AGENT_EMAIL') and coalesce(e.src_url, '') ~ '^https?://' then 'HIGH'
              when e.canonical = 'CLAY_WORK_EMAIL' or e.canonical = 'ACCEPT_ALL_RISKY' or e.canonical = 'PUBLIC_UNVERIFIED' then 'LOW'
              else 'MEDIUM' end,
         e.draft_subject, left(regexp_replace(coalesce(e.draft_text, ''), '\s+', ' ', 'g'), 280),
         case when e.gmail_draft_id is not null then 'GMAIL_DRAFT' when e.ob_id is not null then 'APPROVED_PENDING_GMAIL'
              when e.cand_status = 'APPROVED' then 'APPROVED' when e.cand_status = 'READY' then 'READY_FOR_REVIEW'
              when e.cand_status = 'REVIEW_REQUIRED' then 'NEEDS_EDIT' when e.cand_status = 'PLANNED' then 'PLANNED_TONIGHT'
              when e.cand_status = 'HOLD' then 'HELD' else 'NONE' end,
         e.gmail_draft_id, e.next_action,
         jsonb_build_object('real_account_person', e.g1, 'stream', e.g2, 'commercial_reason', e.g3, 'project_hypothesis', e.g4, 'decision_maker', e.g5,
                            'contact_route', e.g6, 'provenance', e.g7, 'route_classification', e.g8, 'personalised_draft', e.g9, 'next_action', e.g10, 'no_conflict', e.g11),
         e.failed, l.score_final,
         jsonb_build_object('base', e.s_base, 'route', e.s_route, 'role', e.s_role, 'signal', e.s_trigger, 'draft', e.s_draft, 'fresh', e.s_fresh,
                            'market', e.s_market, 'learning', round(e.w_learn::numeric, 3), 'raw', e.raw),
         outreach_market_open(e.market, v_dow),
         case when outreach_market_open(e.market, v_dow) then 'Today'
              else (select to_char(v_date + d, 'Dy DD Mon') from generate_series(1, 7) d where outreach_market_open(e.market, extract(dow from v_date + d)::int) order by d limit 1) end,
         jsonb_build_object('stream', e.primary_stream, 'category', e.category, 'account_type', coalesce(e.commercial_class, e.company_type),
                            'dm_role', case when e.person is null then 'TEAM_INBOX' else outreach_role_bucket(e.position) end,
                            'source', e.src_type, 'route_type', e.canonical, 'hypothesis', e.project_type_canon, 'angle', outreach_angle_bucket(e.project_idea)),
         now()
    from _lanes l join _e e on e.opportunity_id = l.opportunity_id
  on conflict (run_date, opportunity_id) do update set
    lane = excluded.lane, rank = excluded.rank, state = 'QUEUED', state_reason = null, state_at = now(), mode = excluded.mode,
    company_id = excluded.company_id, contact_id = excluded.contact_id, route_contact_id = excluded.route_contact_id, candidate_id = excluded.candidate_id,
    task_id = excluded.task_id, outbound_email_id = excluded.outbound_email_id, category = excluded.category, stream = excluded.stream, market = excluded.market,
    person = excluded.person, position = excluded.position, company = excluded.company, project_idea = excluded.project_idea, why_now = excluded.why_now,
    route_email = excluded.route_email, route_canonical = excluded.route_canonical, route_label = excluded.route_label, route_source_url = excluded.route_source_url,
    route_source_type = excluded.route_source_type, confidence = excluded.confidence, draft_subject = excluded.draft_subject, draft_excerpt = excluded.draft_excerpt,
    draft_status = excluded.draft_status, gmail_draft_id = excluded.gmail_draft_id, next_action = excluded.next_action, gates = excluded.gates,
    failed = excluded.failed, score = excluded.score, score_parts = excluded.score_parts, sendable_today = excluded.sendable_today,
    send_window = excluded.send_window, dims = excluded.dims, built_at = now()
  where q.state <> 'SENT';
  update daily_outreach_queue set state = 'DROPPED', state_at = now(), state_reason = 'No longer meets every gate (' || lower(p_mode) || ' check)'
   where run_date = v_date and state = 'REBUILDING';

  -- 5. Funnel, coverage and gate record for the day (small: counts only).
  select count(*) into v_today from daily_outreach_queue where run_date = v_date and lane = 'TODAY' and state in ('QUEUED', 'SENT');
  select jsonb_build_object(
           'considered', count(*),
           'screened', count(*) filter (where account_ok and g2 and g3 and g11),
           'researched', count(*) filter (where account_ok and g2 and g3 and g11 and g4 and g5 and g6 and g7 and g8),
           'ready', count(*) filter (where ready),
           'ready_unique_companies', (select count(*) from _rk),
           'today', v_today, 'today_sent', v_sent_today,
           'reserve', (select count(*) from _lanes where lane = 'RESERVE'),
           'needs_draft', (select count(*) from _lanes where lane = 'NEEDS_DRAFT'),
           'needs_contact', (select count(*) from _lanes where lane = 'NEEDS_CONTACT'),
           'new_accounts_24h', (select count(*) from companies where created_at > now() - interval '24 hours'),
           'new_opportunities_24h', (select count(*) from opportunities where created_at > now() - interval '24 hours'),
           'targets', coalesce(v_cfg->'funnel_targets', '{}'::jsonb)),
         jsonb_build_object('real_account_person', count(*) filter (where not g1), 'stream', count(*) filter (where not g2),
           'commercial_reason', count(*) filter (where not g3), 'project_hypothesis', count(*) filter (where not g4),
           'decision_maker', count(*) filter (where not g5), 'contact_route', count(*) filter (where not g6), 'provenance', count(*) filter (where not g7),
           'route_classification', count(*) filter (where not g8), 'personalised_draft', count(*) filter (where not g9),
           'next_action', count(*) filter (where not g10), 'no_conflict', count(*) filter (where not g11))
    into v_funnel, v_fail from _e;
  select coalesce(jsonb_object_agg(c.code, jsonb_build_object('label', c.label, 'considered', coalesce(x.considered, 0), 'ready', coalesce(x.ready, 0),
                                                              'today', coalesce(t.today, 0))), '{}'::jsonb) into v_cat
    from outreach_categories c
    left join (select category, count(*) considered, count(*) filter (where ready) ready from _e group by category) x on x.category = c.code
    left join (select category, count(*) today from daily_outreach_queue where run_date = v_date and lane = 'TODAY' and state in ('QUEUED', 'SENT') group by category) t on t.category = c.code;
  -- Bottleneck: the gate that most often stops accounts that are otherwise screened (real account, stream, reason, no conflict).
  select k into v_bottleneck from (
    select k, count(*) n from _e e cross join lateral unnest(e.failed) k
     where e.account_ok and e.g2 and e.g3 and e.g11 and not e.ready group by k order by count(*) desc limit 1) b;

  insert into daily_outreach_runs as r (run_date, morning_at, built_at, mode, runs, duration_ms, funnel, by_category, gate_failures, shortfall, bottleneck)
  values (v_date, case when p_mode = 'MORNING' then now() end, now(), p_mode, 1, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int,
          v_funnel, v_cat, v_fail, greatest(v_floor - v_today, 0), v_bottleneck)
  on conflict (run_date) do update set morning_at = coalesce(case when p_mode = 'MORNING' then now() end, r.morning_at), built_at = now(), mode = p_mode,
    runs = r.runs + 1, duration_ms = excluded.duration_ms, funnel = excluded.funnel, by_category = excluded.by_category,
    gate_failures = excluded.gate_failures, shortfall = excluded.shortfall, bottleneck = excluded.bottleneck;

  return jsonb_build_object('ok', true, 'date', v_date, 'mode', p_mode, 'marked_sent', v_marked, 'funnel', v_funnel, 'gate_failures', v_fail,
                            'shortfall', greatest(v_floor - v_today, 0), 'bottleneck', v_bottleneck,
                            'duration_ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
end $$;

-- 6. HQ light reads (admin-gated, small payloads: one lane per call, excerpts only, full draft on demand).
create or replace function public.hq_outreach_lanes(p_lane text default 'TODAY', p_limit integer default 25, p_offset integer default 0) returns jsonb
 language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); v_today date := (now() at time zone 'Africa/Cairo')::date; v_date date; v_run daily_outreach_runs%rowtype;
        v_items jsonb := '[]'::jsonb; v_total int := 0; v_counts jsonb; v_extra jsonb := '{}'::jsonb; v_learn jsonb; v_t jsonb;
begin
  p_lane := upper(coalesce(p_lane, 'TODAY')); p_limit := least(greatest(coalesce(p_limit, 25), 1), 50); p_offset := greatest(coalesce(p_offset, 0), 0);
  if p_lane not in ('ACT_NOW', 'TODAY', 'RESERVE', 'NEEDS_CONTACT', 'FOLLOW_UPS', 'REPLIES') then
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_LANE');
  end if;
  select max(run_date) into v_date from daily_outreach_runs where run_date <= v_today;
  select * into v_run from daily_outreach_runs where run_date = v_date;

  select jsonb_build_object(
    'act_now', outreach_act_now_count(),
    'today', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'TODAY' and state = 'QUEUED'),
    'today_sent', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'TODAY' and state = 'SENT'),
    'reserve', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'RESERVE' and state = 'QUEUED'),
    'needs_contact', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'NEEDS_CONTACT' and state = 'QUEUED'),
    'needs_draft', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'NEEDS_DRAFT' and state = 'QUEUED'),
    'follow_ups', (select count(*) from opportunities where status in ('CONTACTED', 'FOLLOW_UP') and next_action_due is not null and next_action_due <= current_date + 2),
    'replies', (select count(*) from gmail_history_threads g where g.relevant and g.last_direction = 'INBOUND' and g.last_inbound_at > now() - interval '14 days'
                 and coalesce(g.hq_status, '') <> 'DISMISSED')) into v_counts;

  if p_lane in ('TODAY', 'RESERVE', 'NEEDS_CONTACT') then
    select count(*) into v_total from daily_outreach_queue q where q.run_date = v_date and q.lane = p_lane and q.state in ('QUEUED', 'SENT');
    select coalesce(jsonb_agg(j order by o1, o2, o3), '[]'::jsonb) into v_items from (
      select (q.state <> 'QUEUED') o1, (not coalesce(q.sendable_today, false)) o2, q.rank o3,
             jsonb_build_object('id', q.id, 'rank', q.rank, 'state', q.state, 'opportunity_id', q.opportunity_id, 'company_id', q.company_id,
               'person', q.person, 'position', q.position, 'company', q.company, 'stream', q.stream, 'stream_label', st.label,
               'category', q.category, 'category_label', oc.label, 'market', q.market, 'project_idea', left(q.project_idea, 280), 'why_now', left(q.why_now, 280),
               'route_email', q.route_email, 'route_canonical', q.route_canonical, 'route_label', q.route_label, 'route_source_type', q.route_source_type,
               'route_source_url', q.route_source_url, 'confidence', q.confidence, 'draft_subject', q.draft_subject, 'draft_excerpt', q.draft_excerpt,
               'draft_status', q.draft_status, 'has_gmail_draft', q.gmail_draft_id is not null, 'task_id', q.task_id, 'next_action', left(q.next_action, 200),
               'next_step', case q.draft_status
                              when 'GMAIL_DRAFT' then 'Send the unsent Gmail draft yourself, in a send window'
                              when 'APPROVED_PENDING_GMAIL' then 'Approved: the unsent Gmail draft is being created'
                              when 'APPROVED' then 'Approved: create the unsent Gmail draft from the approval desk'
                              when 'READY_FOR_REVIEW' then 'Review the draft in the approval desk; approving creates an unsent Gmail draft'
                              when 'NEEDS_EDIT' then 'Draft failed the quality gate: edit and re-check before approval'
                              when 'PLANNED_TONIGHT' then 'W18 drafts this account tonight'
                              else case when q.lane = 'NEEDS_CONTACT' then 'Find the right person and a sourced professional route' else 'Prepare a personalised draft' end end,
               'failed', to_jsonb(q.failed), 'score', q.score, 'sendable_today', q.sendable_today, 'send_window', q.send_window) j
        from daily_outreach_queue q left join commercial_streams st on st.code = q.stream left join outreach_categories oc on oc.code = q.category
       where q.run_date = v_date and q.lane = p_lane and q.state in ('QUEUED', 'SENT')
       order by (q.state <> 'QUEUED'), (not coalesce(q.sendable_today, false)), q.rank limit p_limit offset p_offset) s;
  elsif p_lane = 'ACT_NOW' then
    v_t := hq_today();
    v_items := coalesce(v_t->'actions', '[]'::jsonb); v_total := jsonb_array_length(v_items) + coalesce((v_t->>'actions_more')::int, 0);
    v_extra := jsonb_build_object('more', coalesce((v_t->>'actions_more')::int, 0));
  elsif p_lane = 'FOLLOW_UPS' then
    select count(*) into v_total from opportunities o where o.status in ('CONTACTED', 'FOLLOW_UP') and o.next_action_due is not null and o.next_action_due <= current_date + 2;
    select coalesce(jsonb_agg(j order by d, p desc), '[]'::jsonb) into v_items from (
      select o.next_action_due d, coalesce(o.priority, 0) p,
             jsonb_build_object('opportunity_id', o.id, 'company_id', o.company_id, 'company', coalesce(c.name, o.company_name),
               'person', nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), ''), 'position', k.position,
               'stream_label', st.label, 'status', o.status, 'due_on', o.next_action_due, 'next_action', left(o.next_action, 240),
               'last_sent', (select max(i.occurred_at) from interactions i where i.opportunity_id = o.id and i.direction = 'OUTBOUND')) j
        from opportunities o left join companies c on c.id = o.company_id left join contacts k on k.id = o.contact_id
        left join commercial_streams st on st.code = o.primary_stream
       where o.status in ('CONTACTED', 'FOLLOW_UP') and o.next_action_due is not null and o.next_action_due <= current_date + 2
       order by o.next_action_due, coalesce(o.priority, 0) desc limit p_limit offset p_offset) s;
    v_extra := jsonb_build_object('held_21_nov', (select count(distinct a.opportunity_id) from approval_audit a join opportunities o on o.id = a.opportunity_id
                                                  where a.action = 'COLD_FOLLOW_UP_HOLD' and o.status in ('CONTACTED', 'FOLLOW_UP') and o.next_action_due is null),
                                  'hold_rule', 'Decision A: held until SPF and DKIM pass. Both pass since 22 Nov, so each gets one authenticated follow-up only where there is a reason, prepared as an unsent draft for you and counted apart from new first touches.');
  else -- REPLIES
    select count(*) into v_total from gmail_history_threads g where g.relevant and g.last_direction = 'INBOUND' and g.last_inbound_at > now() - interval '14 days'
       and coalesce(g.hq_status, '') <> 'DISMISSED';
    select coalesce(jsonb_agg(j order by t desc), '[]'::jsonb) into v_items from (
      select g.last_inbound_at t,
             jsonb_build_object('thread_id', g.gmail_thread_id, 'company_id', g.company_id, 'company', c.name, 'opportunity_id', g.opportunity_id,
               'subject', left(g.subject, 160), 'summary', left(g.summary, 240), 'last_inbound_at', g.last_inbound_at, 'status', o.status,
               'supplier', coalesce(c.relationship_status, '') = 'supplier',
               'classification', (select l.classification from gmail_sync_ledger l where l.gmail_thread_id = g.gmail_thread_id order by l.received_at desc nulls last limit 1),
               'url', 'https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#all/' || g.gmail_thread_id) j
        from gmail_history_threads g left join companies c on c.id = g.company_id left join opportunities o on o.id = g.opportunity_id
       where g.relevant and g.last_direction = 'INBOUND' and g.last_inbound_at > now() - interval '14 days' and coalesce(g.hq_status, '') <> 'DISMISSED'
       order by g.last_inbound_at desc limit p_limit offset p_offset) s;
  end if;

  select jsonb_build_object('clean_sends', count(*) filter (where cohort = 'CLEAN'), 'clean_bounced', count(*) filter (where cohort = 'CLEAN' and bounced),
           'clean_replied', count(*) filter (where cohort = 'CLEAN' and replied), 'clean_positive', count(*) filter (where cohort = 'CLEAN' and positive),
           'clean_meetings', count(*) filter (where cohort = 'CLEAN' and meeting), 'clean_wins', count(*) filter (where cohort = 'CLEAN' and won),
           'excluded_21_nov', count(*) filter (where cohort = 'EXCLUDED_21_NOV'),
           'weights_active', (select count(*) from jsonb_object_keys(coalesce(outreach_learning_weights()->'weights', '{}'::jsonb))))
    into v_learn from outreach_learning;
  return jsonb_build_object('ok', true, 'lane', p_lane, 'date', v_date, 'built_at', v_run.built_at, 'morning_at', v_run.morning_at,
           'stale', v_date is distinct from v_today, 'counts', v_counts, 'allowance', outreach_send_allowance(),
           'funnel', v_run.funnel, 'coverage', v_run.by_category, 'shortfall', v_run.shortfall, 'bottleneck', v_run.bottleneck,
           'learning', v_learn, 'items', v_items, 'total', v_total, 'limit', p_limit, 'offset', p_offset, 'extra', v_extra);
end $$;

-- One prepared draft, on demand (the lanes read carries only a 280-character excerpt).
create or replace function public.hq_outreach_draft(p_id uuid) returns jsonb
 language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); q daily_outreach_queue%rowtype; v_subject text; v_body text; v_msg text;
begin
  select * into q from daily_outreach_queue where id = p_id;
  if q.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  select e.subject, e.body, e.gmail_message_id into v_subject, v_body, v_msg from outbound_emails e where e.id = q.outbound_email_id;
  if v_body is null then select oc.subject, oc.draft into v_subject, v_body from outreach_candidates oc where oc.id = q.candidate_id; end if;
  return jsonb_build_object('ok', true, 'id', q.id, 'company', q.company, 'person', q.person, 'to', q.route_email, 'route_label', q.route_label,
           'route_source_type', q.route_source_type, 'route_source_url', q.route_source_url, 'subject', v_subject, 'body', v_body,
           'draft_status', q.draft_status, 'task_id', q.task_id,
           'gmail_draft_url', case when v_msg is not null then gmail_draft_url(v_msg) end,
           'rule', 'Unsent. Approving in the desk creates an unsent Gmail draft; Adam sends it himself.');
end $$;

-- 7. Grants: two admin reads for HQ; everything else internal (cron and the daily operating check only).
revoke all on function public.hq_outreach_lanes(text, integer, integer) from public, anon;
revoke all on function public.hq_outreach_draft(uuid) from public, anon;
grant execute on function public.hq_outreach_lanes(text, integer, integer) to authenticated;
grant execute on function public.hq_outreach_draft(uuid) to authenticated;
revoke all on function public.outreach_queue_build(text) from public, anon, authenticated;
revoke all on function public.outreach_learning_refresh() from public, anon, authenticated;
revoke all on function public.outreach_learning_weights() from public, anon, authenticated;
revoke all on function public.outreach_ramp_review() from public, anon, authenticated;
revoke all on function public.outreach_send_allowance() from public, anon, authenticated;
revoke all on function public.outreach_send_health() from public, anon, authenticated;
revoke all on function public.outreach_act_now_count() from public, anon, authenticated;
revoke all on function public.email_auth_state() from public, anon, authenticated;
revoke all on function public.email_auth_normalise() from public, anon, authenticated;

-- 8. Schedule (pg_cron runs in UTC; Cairo is UTC+2 in winter, UTC+3 in summer). Business days Sun-Fri: Egypt / GCC Sun-Thu, UK / EU Mon-Fri.
--    05:20 Cairo ramp review -> 05:30 MORNING build (after W18's nightly drafting 21:00-23:30, W13 hourly Gmail sync, the 10-minute route
--    cache) -> hourly TOPUP 07:50-17:50 Cairo -> ledger refresh hourly at :41.
select cron.schedule('outreach-ramp-review', '20 3 * * 0-5', $c$select public.outreach_ramp_review()$c$);
select cron.schedule('outreach-queue-morning', '30 3 * * 0-5', $c$select public.outreach_queue_build('MORNING')$c$);
select cron.schedule('outreach-queue-topup', '50 5-15 * * 0-5', $c$select public.outreach_queue_build('TOPUP')$c$);
select cron.schedule('outreach-learning', '41 * * * *', $c$select public.outreach_learning_refresh()$c$);
