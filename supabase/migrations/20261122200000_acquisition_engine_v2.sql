-- NOYA acquisition engine v2 (Adam, 22 Nov 2026): discovery + route quality + portfolio balance + scale, on top of the 22 Nov
-- acquisition policy. Extends what works (W18 drafting, the morning build / hourly top-ups, the learning ledger, the route cache, the
-- Gmail reconciliation); replaces nothing.
--
--   * Eight commercial families over the 13 categories, with Adam's morning inventory guide and a 25 % portfolio cap on READY.
--   * Inventory targets: 75 READY (range 60-80), 100 RESERVE, 150 NEEDS CONTACT, 100 NEEDS DRAFT.
--   * Multi-channel best route: EMAIL, public commercial FORM, LINKEDIN or INSTAGRAM message. One account, one active cold route.
--   * 14 READY gates (adds strong commercial fit, a separate duplicate-company gate and research currency).
--   * contact_forms: the form route type (discovery by W27 from the company's own pages, classification, field-by-field prepared copy,
--     REVIEW -> APPROVE in HQ, submission only after Adam's approval, submission log).
--   * Failed-draft repair (a failed draft is not a failed account), credit budgeting, engine health, director accountability,
--     bounded self-correction, and the discovery query matrix.
--
-- Safety: nothing here sends or submits. hq_form_action records Adam's approval only; a form is submitted later by the operating
-- agent and recorded with form_submission_record. No cold email is created or sent. Idempotent.

-- 1. Commercial families (Adam's morning inventory guide: not quotas; quality wins).
create table if not exists public.outreach_families (
  code text primary key,
  label text not null,
  target_min integer not null,
  target_max integer not null,
  multiplier boolean not null default false,
  sort smallint not null
);
alter table public.outreach_families enable row level security;
insert into public.outreach_families (code, label, target_min, target_max, multiplier, sort) values
  ('TRAVEL_DMC', 'Travel / DMC / concierge', 10, 12, true, 1),
  ('CLUBS_NETWORKS', 'Private clubs / networks', 8, 10, true, 2),
  ('AGENCIES_CONSULTANCIES', 'Agencies / consultancies', 12, 15, true, 3),
  ('BRANDS', 'Brands', 10, 12, false, 4),
  ('FOOTBALL_TALENT', 'Football / talent / sports', 10, 12, true, 5),
  ('WEDDINGS_EVENTS', 'Weddings / events', 7, 10, false, 6),
  ('CORPORATE_EXECUTIVE', 'Corporate / executive', 6, 8, true, 7),
  ('HOSPITALITY_PRIVATE', 'Hospitality / private / sourcing', 0, 10, false, 8)
on conflict (code) do update set label = excluded.label, target_min = excluded.target_min, target_max = excluded.target_max,
  multiplier = excluded.multiplier, sort = excluded.sort;

alter table public.outreach_categories add column if not exists family text references public.outreach_families(code);
update public.outreach_categories set family = case code
  when 'TRAVEL_ADVISORS_DMC' then 'TRAVEL_DMC' when 'CLUBS_FOUNDERS' then 'CLUBS_NETWORKS'
  when 'AGENCIES' then 'AGENCIES_CONSULTANCIES' when 'CONSULTANCIES' then 'AGENCIES_CONSULTANCIES' when 'BRANDS' then 'BRANDS'
  when 'FOOTBALL_SPORTS' then 'FOOTBALL_TALENT' when 'TALENT_MGMT' then 'FOOTBALL_TALENT' when 'WEDDINGS_EVENTS' then 'WEDDINGS_EVENTS'
  when 'CORPORATE_EXEC_LANDING' then 'CORPORATE_EXECUTIVE' when 'RETREATS_OFFSITES' then 'CORPORATE_EXECUTIVE'
  else 'HOSPITALITY_PRIVATE' end;

-- 2. Engine settings (inside the existing acquisition_engine record).
update public.system_config set value = value || jsonb_build_object(
  'send_ready_floor', 75,
  'send_ready_floor_previous', coalesce(value->'send_ready_floor', '25'::jsonb),
  'inventory', jsonb_build_object('ready_target', 75, 'ready_range', jsonb_build_array(60, 80), 'reserve_target', 100,
                                  'needs_contact_target', 150, 'needs_draft_target', 100, 'family_cap_share', 0.25,
                                  'family_cap_overrides', '{}'::jsonb, 'min_families', 6,
                                  'note', 'READY capacity, not a send quota. Actual sends follow send_ramp_state.'),
  'route_ranking', jsonb_build_array('WARM', 'NAMED_EMAIL', 'MANAGEMENT_AGENT', 'VALIDATED_WORK_EMAIL', 'INSTAGRAM_BUSINESS_EMAIL',
                                     'COMMERCIAL_FORM', 'CLAY_WORK_EMAIL', 'OFFICIAL_INBOX', 'GENERAL_FORM', 'LINKEDIN', 'INSTAGRAM_DM'),
  'route_research', jsonb_build_object('batch_per_run', 30, 'max_batch', 60, 'revisit_days', 30, 'max_pages_per_site', 6),
  'draft_repair', jsonb_build_object('per_night', 30, 'max_per_night', 50, 'max_repairs_per_draft', 2),
  'v2_decided', 'Adam, 22 Nov 2026: final autonomous acquisition engine. 60-80 READY a day (75 default), 75-100 reserve, 100-150 needs-contact; forms are a route type; no cold auto-send; no auto form submission.')
where key = 'acquisition_engine';

-- 3. Public commercial forms as a route type.
create table if not exists public.contact_forms (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  opportunity_id uuid references public.opportunities(id),
  url text not null,
  form_type text not null check (form_type in ('CONTACT', 'PARTNERSHIP', 'SUPPLIER_VENDOR', 'NEW_BUSINESS', 'TRAVEL_ADVISOR', 'AGENCY_ENQUIRY',
    'GROUP_EVENT', 'MEMBERSHIP_PARTNERSHIP', 'PRESS_PRODUCTION', 'BRAND_PARTNERSHIP', 'WHOLESALE_COMMERCIAL', 'CORPORATE_ENQUIRY',
    'RESIDENCE_OWNER', 'NON_COMMERCIAL')),
  target_team text,
  fields jsonb not null default '[]'::jsonb,
  required_fields text[] not null default '{}',
  max_message_chars integer,
  attachments_allowed boolean not null default false,
  captcha text not null default 'UNKNOWN' check (captcha in ('NONE', 'RECAPTCHA', 'HCAPTCHA', 'TURNSTILE', 'OTHER', 'UNKNOWN')),
  login_required boolean not null default false,
  source_url text not null,
  discovered_by text not null default 'W27',
  discovered_at timestamptz not null default now(),
  verified_at timestamptz not null default now(),
  status text not null default 'DISCOVERED' check (status in ('DISCOVERED', 'QUALIFIED', 'REJECTED', 'PREPARED', 'APPROVED', 'SUBMITTED', 'FAILED', 'SUPERSEDED')),
  reject_reason text,
  prepared_subject text,
  prepared_message text,
  prepared_fields jsonb,
  prepared_at timestamptz,
  prepared_by text,
  qa_status text,
  qa_issues jsonb,
  approved_at timestamptz,
  approved_note text,
  submitted_at timestamptz,
  submitted_content jsonb,
  confirmation_text text,
  reference text,
  next_follow_up_on date,
  updated_at timestamptz not null default now(),
  unique (company_id, url),
  constraint contact_forms_prepared_copy check (status not in ('PREPARED', 'APPROVED', 'SUBMITTED') or (prepared_message is not null and prepared_at is not null)),
  constraint contact_forms_approval_first check (status <> 'SUBMITTED' or (approved_at is not null and submitted_at is not null)),
  constraint contact_forms_commercial_only check (status not in ('QUALIFIED', 'PREPARED', 'APPROVED', 'SUBMITTED') or (form_type <> 'NON_COMMERCIAL' and not login_required))
);
-- One account, one active form route.
create unique index if not exists contact_forms_one_active on public.contact_forms (company_id) where status in ('PREPARED', 'APPROVED');
create index if not exists contact_forms_status on public.contact_forms (status, company_id);
alter table public.contact_forms enable row level security;

-- Purpose classification from the form's page path and visible labels. Consumer support, returns, complaints, privacy, careers and
-- consumer booking forms are NON_COMMERCIAL and never count as sales routes.
create or replace function public.form_type_classify(p_url text, p_text text) returns text
 language sql immutable
as $$
  select case
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(career|jobs|vacanc|recruit|privacy|gdpr|data[- ]request|unsubscribe|complain|returns?\M|refund|warranty|customer[- ]service|support[- ]ticket|helpdesk|order[- ]status|newsletter|book[- ]a[- ]table|reservation|check[- ]availability|book[- ]now|track[- ]order|login|sign[- ]?in|register\M)' then 'NON_COMMERCIAL'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(travel[- ]?advis|travel[- ]?agent|trade[- ]partner|for[- ]agents|agent[- ]portal|travel[- ]trade)' then 'TRAVEL_ADVISOR'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(new[- ]business|work[- ]with[- ]us|start[- ]a[- ]project|brief[- ]us|hire[- ]us)' then 'NEW_BUSINESS'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(vendor|supplier|procurement|become[- ]a[- ]supplier)' then 'SUPPLIER_VENDOR'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(brand[- ]partner|collab|sponsor|ambassador)' then 'BRAND_PARTNERSHIP'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(member[- ]benefit|membership[- ]partner|club[- ]partner)' then 'MEMBERSHIP_PARTNERSHIP'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(partner|become[- ]a[- ]partner|affiliat|referral)' then 'PARTNERSHIP'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(wholesale|stockist|retailer|distribut|b2b)' then 'WHOLESALE_COMMERCIAL'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(press|media|production|filming|location[- ]shoot)' then 'PRESS_PRODUCTION'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(group|events?\M|private[- ]event|meeting|incentive|conference|wedding|celebration|venue[- ]hire)' then 'GROUP_EVENT'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(corporate|business[- ]enquir|company[- ]account)' then 'CORPORATE_ENQUIRY'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(owner|residen|homeowner|property[- ]management)' then 'RESIDENCE_OWNER'
    when lower(coalesce(p_url, '') || ' ' || coalesce(p_text, '')) ~ '(agency|talent|management|represent|booking[- ]enquir)' then 'AGENCY_ENQUIRY'
    else 'CONTACT' end
$$;

-- 4. Research logs, the discovery matrix and the credit ledger.
create table if not exists public.route_research_log (
  id bigserial primary key,
  company_id uuid not null references public.companies(id),
  at timestamptz not null default now(),
  method text not null default 'W27_SITE',
  pages jsonb,
  emails_found integer not null default 0,
  named_found integer not null default 0,
  inboxes_added integer not null default 0,
  forms_found integer not null default 0,
  forms_qualified integer not null default 0,
  socials_added integer not null default 0,
  outcome text,
  error text
);
create index if not exists route_research_log_company on public.route_research_log (company_id, at desc);
alter table public.route_research_log enable row level security;

create table if not exists public.discovery_queries (
  id bigserial primary key,
  family text not null references public.outreach_families(code),
  stream text,
  market text not null,
  buyer_type text not null,
  signal text,
  provider text not null default 'WEB' check (provider in ('WEB', 'MAPS')),
  query text not null,
  priority integer not null default 50,
  active boolean not null default true,
  last_run_at timestamptz,
  runs integer not null default 0,
  results integer not null default 0,
  new_companies integer not null default 0,
  qualified integer not null default 0,
  unique (provider, query)
);
alter table public.discovery_queries enable row level security;

create table if not exists public.research_credit_ledger (
  id bigserial primary key,
  at timestamptz not null default now(),
  provider text not null check (provider in ('SERPER', 'FIRECRAWL', 'CLAY', 'HUNTER', 'GEMINI', 'OTHER')),
  credits numeric not null default 0,
  usd numeric,
  purpose text not null check (purpose in ('DISCOVERY', 'ROUTE', 'VERIFY', 'ENRICH', 'DRAFT', 'FORM', 'CHECK')),
  company_id uuid,
  contact_id uuid,
  outcome text,
  detail text,
  actor text not null default 'AGENT'
);
create index if not exists research_credit_ledger_at on public.research_credit_ledger (provider, at desc);
alter table public.research_credit_ledger enable row level security;

insert into public.system_config (key, value, note) values ('research_credits', jsonb_build_object(
  'serper', jsonb_build_object('target_runway_days', 30, 'reserve', 300, 'note', 'Prepaid pack; balance from provider_balances (W22). Top-up needs Adam.'),
  'firecrawl', jsonb_build_object('monthly', 1000, 'cycle_day', 30, 'remaining', 730, 'as_of', '2026-10-30', 'reserve', 100),
  'clay', jsonb_build_object('monthly', null, 'remaining', null, 'as_of', null, 'per_day_cap', 10, 'rule', 'Only after qualification and preferably after the right person is known; never twice on the same unresolved person within 30 days.'),
  'hunter', jsonb_build_object('source', 'system_config.hunter_account'),
  'gemini', jsonb_build_object('source', 'system_config.ai_budget', 'note', 'Free-tier rate limits cause about half of W18 first passes to fail; enabling billing keeps cost inside the approved monthly AI ceiling.'),
  'no_new_spend', 'The engine may recommend a top-up or a new provider; it never buys.'),
  'Research credit budgets for the acquisition engine (22 Nov 2026). Spend is logged in research_credit_ledger.')
on conflict (key) do nothing;

-- Discovery matrix: family x buyer type x market x signal, web and map queries. Variations, not only exact phrases.
with fam(family, stream, buyer, signals) as (values
  ('TRAVEL_DMC', 'TRAVEL_ADVISORS', array['luxury travel agency', 'luxury travel designer', 'private travel advisor', 'luxury travel club', 'concierge company', 'destination management company'], array['new destination', 'Africa Middle East programme', 'Egypt itineraries']),
  ('CLUBS_NETWORKS', 'PRIVATE_CLUBS', array['private members club', 'founder club', 'business leaders network', 'family office network', 'entrepreneurs organisation chapter'], array['member travel programme', 'member experiences', 'new club opening']),
  ('AGENCIES_CONSULTANCIES', 'EXPERIENTIAL_AGENCIES', array['experiential agency', 'luxury PR agency', 'brand activation agency', 'luxury communications agency', 'influencer marketing agency', 'production company', 'hospitality consultancy', 'executive search firm', 'global mobility company'], array['new account win', 'MENA expansion', 'regional office opening']),
  ('BRANDS', 'FASHION_LUXURY', array['luxury fashion brand', 'beauty brand', 'fragrance house', 'jewellery brand', 'watch brand', 'streetwear brand', 'luxury automotive brand'], array['Middle East launch', 'creator campaign', 'brand ambassador', 'store opening']),
  ('FOOTBALL_TALENT', 'ATHLETES_FOOTBALL', array['football agency', 'player care agency', 'sports management agency', 'talent management agency', 'artist management company'], array['player services', 'new signings', 'roster']),
  ('WEDDINGS_EVENTS', 'WEDDINGS', array['luxury destination wedding planner', 'luxury event planner', 'private celebration planner'], array['destination weddings', 'international celebrations']),
  ('CORPORATE_EXECUTIVE', 'EXECUTIVE_LANDING', array['corporate incentive travel company', 'leadership retreat organiser', 'executive relocation company', 'corporate event agency'], array['incentive programme', 'executive offsite', 'relocation services']),
  ('HOSPITALITY_PRIVATE', 'BRANDED_RESIDENCES', array['branded residences', 'luxury villa company', 'luxury hotel group', 'private office', 'art advisory'], array['new opening', 'owner services', 'resident services'])),
mkt(market, places, weight) as (values
  ('UK', array['London'], 10), ('GCC', array['Dubai', 'Riyadh', 'Abu Dhabi', 'Doha'], 10), ('EGYPT', array['Cairo'], 9),
  ('EUROPE', array['Paris', 'Milan', 'Geneva', 'Monaco'], 8), ('NORTH_AMERICA', array['New York', 'Miami'], 6))
insert into public.discovery_queries (family, stream, market, buyer_type, signal, provider, query, priority)
select f.family, f.stream, m.market, b.buyer, null, case when b.buyer ~* '(planner|club|villa|hotel|agency|company)' then 'MAPS' else 'WEB' end,
       b.buyer || ' ' || p.place, m.weight * 5 + (case when (select multiplier from outreach_families where code = f.family) then 10 else 0 end)
  from fam f cross join lateral unnest(f.buyer) b(buyer) cross join mkt m cross join lateral unnest(m.places) p(place)
on conflict (provider, query) do nothing;
with fam(family, stream, buyer, signals) as (values
  ('TRAVEL_DMC', 'TRAVEL_ADVISORS', 'luxury travel agency', array['new destination', 'Egypt itineraries']),
  ('CLUBS_NETWORKS', 'PRIVATE_CLUBS', 'private members club', array['member travel programme', 'new club opening']),
  ('AGENCIES_CONSULTANCIES', 'EXPERIENTIAL_AGENCIES', 'experiential agency', array['new account win', 'MENA expansion']),
  ('BRANDS', 'FASHION_LUXURY', 'luxury brand', array['Middle East launch', 'brand ambassador']),
  ('FOOTBALL_TALENT', 'ATHLETES_FOOTBALL', 'football agency', array['player care', 'new signings']),
  ('CORPORATE_EXECUTIVE', 'EXECUTIVE_LANDING', 'executive search', array['Egypt office', 'MENA practice'])),
mkt(market, place) as (values ('GCC', 'Dubai'), ('UK', 'London'), ('EGYPT', 'Egypt'))
insert into public.discovery_queries (family, stream, market, buyer_type, signal, provider, query, priority)
select f.family, f.stream, m.market, f.buyer, s, 'WEB', f.buyer || ' ' || m.place || ' ' || s, 60
  from fam f cross join lateral unnest(f.signals) s cross join mkt m
on conflict (provider, query) do nothing;

-- 5. Queue columns for the multi-channel route and the family (added to the 22 Nov table; existing columns unchanged).
alter table public.daily_outreach_queue add column if not exists family text;
alter table public.daily_outreach_queue add column if not exists route_channel text;
alter table public.daily_outreach_queue add column if not exists route_rank smallint;
alter table public.daily_outreach_queue add column if not exists fallback_route text;
alter table public.daily_outreach_queue add column if not exists form_id uuid;
alter table public.daily_outreach_runs add column if not exists engine jsonb;
alter table public.outreach_candidates add column if not exists repair_count smallint not null default 0;
alter table public.outreach_learning add column if not exists route_channel text;

-- 6. Sender profile for prepared forms (the monitored outreach mailbox; W13 syncs it).
insert into public.system_config (key, value, note) values ('sender_profile', jsonb_build_object(
  'name', 'Adam Elshazly', 'first_name', 'Adam', 'last_name', 'Elshazly', 'role', 'Founder', 'company', 'NOYA Concierge',
  'email', 'noya@noyaconcierge.com', 'website', 'https://noyaconcierge.com', 'phone', null, 'country', 'Egypt',
  'phone_rule', 'Leave phone empty unless the form requires it and Adam has recorded a business number here.'),
  'Identity used to prefill public commercial forms. Replies land in noya@ (synced by W13).')
on conflict (key) do nothing;
alter table public.contact_forms add column if not exists fields_sig text;

-- 7. Route research (W27: the company's own pages, no paid credits). Next batch, then ingest.
create or replace function public.route_research_next_batch(p_limit integer default null) returns jsonb
 language sql stable security definer set search_path to 'public'
as $$
  with cfg as (select value v from system_config where key = 'acquisition_engine'),
  lim as (select least(greatest(coalesce(p_limit, ((select v from cfg)->'route_research'->>'batch_per_run')::int, 30), 1),
                       coalesce(((select v from cfg)->'route_research'->>'max_batch')::int, 60)) n,
                 coalesce(((select v from cfg)->'route_research'->>'revisit_days')::int, 30) revisit),
  rd as (select max(run_date) d from daily_outreach_runs),
  fam_gap as (
    select f.code, greatest(f.target_min - coalesce(t.n, 0), 0) gap, f.multiplier from outreach_families f
      left join (select q.family, count(*) n from daily_outreach_queue q, rd where q.run_date = rd.d and q.lane = 'TODAY' and q.state in ('QUEUED', 'SENT') group by 1) t on t.family = f.code),
  cand as (
    select distinct on (c.id) c.id company_id, c.name, c.website, registrable_domain(c.website) domain, o.id opportunity_id,
           coalesce(oc.family, 'HOSPITALITY_PRIVATE') family, o.primary_stream stream, coalesce(o.priority, 50) prio,
           coalesce((select q.rank from daily_outreach_queue q, rd where q.run_date = rd.d and q.opportunity_id = o.id and q.lane = 'NEEDS_CONTACT' limit 1), 999) nc_rank
      from companies c join opportunities o on o.company_id = c.id
      left join outreach_categories oc on oc.code = outreach_category(o.primary_stream, c.company_type)
     where c.merged_into is null and coalesce(c.universe_status, '') in ('QUALIFIED', 'RESEARCHING', 'NEEDS_REVIEW')
       and c.website ~* '^https?://' and o.status in ('NEW', 'RESEARCHING', 'READY') and coalesce(o.relationship_type, 'COLD') = 'COLD'
       and coalesce(c.outreach_hold_until, '-infinity'::timestamptz) < now()
       and not exists (select 1 from route_research_log l where l.company_id = c.id and l.at > now() - make_interval(days => (select revisit from lim)))
       and not exists (select 1 from contact_forms f where f.company_id = c.id and f.status in ('PREPARED', 'APPROVED', 'SUBMITTED'))
       and not exists (select 1 from hq_route_cache r where r.company_id = c.id and r.usable)
     order by c.id, o.priority desc nulls last)
  select coalesce(jsonb_agg(jsonb_build_object('company_id', x.company_id, 'name', x.name, 'website', x.website, 'domain', x.domain,
                                               'family', x.family, 'stream', x.stream) order by x.ord), '[]'::jsonb)
    from (select c.*, row_number() over (order by (c.nc_rank < 999) desc, coalesce(g.gap, 0) desc, coalesce(g.multiplier, false) desc, c.prio desc, c.company_id) ord
            from cand c left join fam_gap g on g.code = c.family
           where relationship_state(c.company_id) = 'COLD') x
   where x.ord <= (select n from lim)
$$;

create or replace function public.route_research_ingest(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public'
as $$
declare c companies%rowtype; v_dom text; e jsonb; f jsonb; v_email text; v_local text; v_cls text; v_ct uuid; v_type text; v_req text[];
        v_max int; v_team text; v_url text; v_text text; v_login boolean; v_sig text; v_opp uuid; v_ig text; v_li text;
        n_em int := 0; n_named int := 0; n_inb int := 0; n_forms int := 0; n_fq int := 0; n_soc int := 0;
begin
  select * into c from companies where id = nullif(p->>'company_id', '')::uuid;
  if c.id is null then return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_COMPANY'); end if;
  v_dom := registrable_domain(c.website);
  select id into v_opp from opportunities where company_id = c.id and status in ('NEW', 'RESEARCHING', 'READY') order by priority desc nulls last limit 1;

  -- Emails: only on the company's own domain, never support / careers / privacy style inboxes, never guessed. A personal-looking
  -- address is attached only to a known person at the company whose name it clearly spells; no person is ever created from an address.
  for e in select * from jsonb_array_elements(coalesce(p->'emails', '[]'::jsonb)) loop
    v_email := lower(btrim(coalesce(e->>'email', '')));
    continue when v_email !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$';
    continue when registrable_domain(split_part(v_email, '@', 2)) is distinct from v_dom;
    v_local := split_part(v_email, '@', 1);
    continue when coalesce(email_local_class(v_email), '') = 'EXCLUDED'
      or v_local ~ '^(support|help|helpdesk|careers?|jobs|hr|recruit(ment|ing)?|privacy|legal|dpo|gdpr|no-?reply|abuse|billing|accounts?|invoices?|webmaster|returns|orders?|customerservice|customercare|unsubscribe)$';
    n_em := n_em + 1;
    continue when exists (select 1 from contacts where lower(email) = v_email);
    v_cls := email_local_class(v_email);
    if v_cls = 'PERSONAL' then
      v_ct := null;
      select k.id into v_ct from contacts k
       where k.company_id = c.id and k.email is null and coalesce(k.do_not_contact, false) = false and length(coalesce(k.first_name, '')) >= 2
         and (v_local = regexp_replace(lower(k.first_name), '[^a-z]', '', 'g')
              or (length(coalesce(k.last_name, '')) >= 2 and (v_local ~ ('^' || regexp_replace(lower(k.first_name), '[^a-z]', '', 'g') || '[._-]?' || regexp_replace(lower(k.last_name), '[^a-z]', '', 'g') || '$')
                   or v_local ~ ('^' || left(regexp_replace(lower(k.first_name), '[^a-z]', '', 'g'), 1) || '[._-]?' || regexp_replace(lower(k.last_name), '[^a-z]', '', 'g') || '$'))))
       limit 1;
      if v_ct is not null then
        update contacts set email = v_email, email_status = 'UNVERIFIED', email_source_url = e->>'page', email_source_type = 'OFFICIAL_SITE',
               route_type = 'PERSON_EMAIL', email_tier = 1, email_found_at = now(), updated_at = now() where id = v_ct;
        n_named := n_named + 1;
      end if;
    else
      insert into contacts (company_id, position, email, email_status, email_source_url, email_source_type, source_type, source_url, route_type,
                            email_tier, email_found_at, confidence, status, source)
      values (c.id, initcap(regexp_replace(v_local, '[._-]+', ' ', 'g')) || ' inbox', v_email, 'UNVERIFIED', e->>'page', 'OFFICIAL_SITE', 'OFFICIAL_SITE', e->>'page',
              'COMPANY_INBOX', case when v_cls = 'DEPARTMENT' then 2 else 3 end, now(), case when v_cls = 'DEPARTMENT' then 55 else 45 end, 'NEW',
              'W27 website route research');
      n_inb := n_inb + 1;
    end if;
  end loop;

  -- Forms: a message field is required (search, newsletter and login widgets are ignored); one row per distinct form per company.
  for f in select * from jsonb_array_elements(coalesce(p->'forms', '[]'::jsonb)) loop
    continue when not exists (select 1 from jsonb_array_elements(coalesce(f->'fields', '[]'::jsonb)) x where x->>'type' = 'textarea');
    v_url := coalesce(nullif(f->>'page', ''), c.website);
    v_text := coalesce(f->>'label', '') || ' ' || coalesce((select string_agg(coalesce(x->>'label', '') || ' ' || coalesce(x->>'name', ''), ' ')
                                                             from jsonb_array_elements(coalesce(f->'fields', '[]'::jsonb)) x), '');
    v_sig := md5(coalesce(f->>'action', '') || '|' || coalesce((select string_agg(coalesce(x->>'name', ''), ',' order by x->>'name')
                                                                 from jsonb_array_elements(coalesce(f->'fields', '[]'::jsonb)) x), ''));
    continue when exists (select 1 from contact_forms cf where cf.company_id = c.id and cf.fields_sig = v_sig and cf.url <> v_url);
    v_type := form_type_classify(v_url, v_text);
    v_login := coalesce((f->>'password')::boolean, false);
    v_req := array(select coalesce(nullif(btrim(x->>'label'), ''), x->>'name') from jsonb_array_elements(coalesce(f->'fields', '[]'::jsonb)) x
                    where coalesce((x->>'required')::boolean, false));
    v_max := (select min((x->>'maxlength')::int) from jsonb_array_elements(coalesce(f->'fields', '[]'::jsonb)) x
               where x->>'type' = 'textarea' and coalesce(x->>'maxlength', '') ~ '^[0-9]{2,6}$');
    v_team := case v_type when 'PARTNERSHIP' then 'Partnerships' when 'TRAVEL_ADVISOR' then 'Trade and travel advisors' when 'NEW_BUSINESS' then 'New business'
                          when 'SUPPLIER_VENDOR' then 'Suppliers' when 'BRAND_PARTNERSHIP' then 'Brand partnerships' when 'MEMBERSHIP_PARTNERSHIP' then 'Membership partnerships'
                          when 'GROUP_EVENT' then 'Events and groups' when 'PRESS_PRODUCTION' then 'Press and production' when 'CORPORATE_ENQUIRY' then 'Corporate'
                          when 'WHOLESALE_COMMERCIAL' then 'Commercial' when 'RESIDENCE_OWNER' then 'Owner and resident services' when 'AGENCY_ENQUIRY' then 'Management' else null end;
    n_forms := n_forms + 1;
    insert into contact_forms as cf (company_id, opportunity_id, url, form_type, target_team, fields, fields_sig, required_fields, max_message_chars,
                                     attachments_allowed, captcha, login_required, source_url, status, reject_reason, verified_at)
    values (c.id, v_opp, v_url, v_type, v_team, coalesce(f->'fields', '[]'::jsonb), v_sig, v_req, v_max, coalesce((f->>'file')::boolean, false),
            case when coalesce(f->>'captcha', '') in ('NONE', 'RECAPTCHA', 'HCAPTCHA', 'TURNSTILE', 'OTHER') then f->>'captcha' else 'UNKNOWN' end, v_login, v_url,
            case when v_type = 'NON_COMMERCIAL' or v_login then 'REJECTED' else 'QUALIFIED' end,
            case when v_login then 'Login required' when v_type = 'NON_COMMERCIAL' then 'Not a commercial route (support, careers, privacy, booking or similar)' end, now())
    on conflict (company_id, url) do update set fields = excluded.fields, fields_sig = excluded.fields_sig, required_fields = excluded.required_fields,
      max_message_chars = excluded.max_message_chars, captcha = excluded.captcha, verified_at = now(), updated_at = now(),
      form_type = case when cf.status in ('PREPARED', 'APPROVED', 'SUBMITTED') then cf.form_type else excluded.form_type end,
      status = case when cf.status in ('DISCOVERED', 'QUALIFIED', 'REJECTED') then excluded.status else cf.status end,
      reject_reason = case when cf.status in ('DISCOVERED', 'QUALIFIED', 'REJECTED') then excluded.reject_reason else cf.reject_reason end;
    if v_type <> 'NON_COMMERCIAL' and not v_login then n_fq := n_fq + 1; end if;
  end loop;

  -- Public professional profiles linked from the official site fill only empty fields.
  v_ig := substring(coalesce(p->>'instagram', '') from '^(https?://(www\.)?instagram\.com/[A-Za-z0-9_.]{2,30})/?$');
  v_li := substring(coalesce(p->>'linkedin', '') from '^(https?://([a-z]{2,3}\.)?linkedin\.com/company/[A-Za-z0-9_%-]{2,80})/?$');
  if v_ig is not null and coalesce(c.instagram, '') = '' then update companies set instagram = v_ig, updated_at = now() where id = c.id; n_soc := n_soc + 1; end if;
  if v_li is not null and coalesce(c.linkedin, '') = '' then update companies set linkedin = v_li, updated_at = now() where id = c.id; n_soc := n_soc + 1; end if;

  insert into route_research_log (company_id, method, pages, emails_found, named_found, inboxes_added, forms_found, forms_qualified, socials_added, outcome, error)
  values (c.id, coalesce(nullif(p->>'method', ''), 'W27_SITE'), p->'pages', n_em, n_named, n_inb, n_forms, n_fq, n_soc,
          case when n_named + n_inb + n_fq > 0 then 'ROUTE_FOUND' when nullif(p->>'error', '') is not null then 'FETCH_FAILED' else 'NO_ROUTE' end, nullif(p->>'error', ''));
  return jsonb_build_object('ok', true, 'company_id', c.id, 'emails', n_em, 'named', n_named, 'inboxes', n_inb, 'forms', n_forms, 'forms_qualified', n_fq, 'socials', n_soc);
end $$;

-- 8. Form copy: next batch for W27's drafting step, a deterministic quality gate, and the save.
create or replace function public.form_message_quality(p_subject text, p_message text, p_max integer, p_company text) returns jsonb
 language plpgsql immutable set search_path to 'public'
as $$
declare b text := coalesce(p_message, ''); w int; issues text[] := '{}'; hard text[] := '{}'; ph text; tok text;
  banned text[] := array['i hope this email finds you well', 'i hope you''re well', 'i hope you are well', 'i wanted to reach out', 'i am reaching out',
    'i''m reaching out', 'i wanted to introduce', 'unparalleled', 'world-class', 'world class', 'elevate', 'seamless luxury', 'bespoke excellence',
    'bespoke solutions', 'luxury redefined', 'curated to perfection', 'synergies', 'we are delighted', 'free call', 'based in egypt', 'complimentary',
    'free of charge', 'all expenses paid', 'fam trip', 'on us'];
begin
  w := coalesce(array_length(regexp_split_to_array(btrim(b), E'\\s+'), 1), 0);
  if w < 45 then issues := issues || ('TOO_SHORT(' || w || 'w)'); end if;
  if w > 140 then issues := issues || ('TOO_LONG(' || w || 'w)'); end if;
  if p_max is not null and length(b) > p_max then hard := hard || ('OVER_FIELD_LIMIT(' || length(b) || '>' || p_max || ')'); end if;
  if b ~ '\{\{|\[(name|company|first name)\]' then hard := hard || 'UNFILLED_PLACEHOLDER'::text; end if;
  if b ~* '(https?://|calendly|<img)' then hard := hard || 'LINK_IN_MESSAGE'::text; end if;
  foreach ph in array banned loop if position(ph in lower(b || ' ' || coalesce(p_subject, ''))) > 0 then hard := hard || ('BANNED:' || ph); end if; end loop;
  if (length(b) - length(replace(b, '?', ''))) > 1 then issues := issues || 'MORE_THAN_ONE_QUESTION'::text; end if;
  if b !~* '(\?|short call|introduction call|right person)' then issues := issues || 'NO_CTA'::text; end if;
  if b !~* 'Adam Elshazly' then issues := issues || 'NO_SIGN_OFF'::text; end if;
  tok := split_part(regexp_replace(lower(coalesce(p_company, '')), '^(the|la|le|el|al)\s+', ''), ' ', 1);
  if length(tok) >= 3 and position(tok in lower(b)) = 0 then issues := issues || 'NOT_PERSONALISED'::text; end if;
  return jsonb_build_object('status', case when array_length(hard, 1) > 0 then 'BLOCKED' when array_length(issues, 1) > 0 then 'NEEDS_EDIT' else 'PASS' end,
                            'words', w, 'blocking', to_jsonb(hard), 'issues', to_jsonb(issues));
end $$;

create or replace function public.form_draft_next_batch(p_limit integer default 15) returns jsonb
 language sql stable security definer set search_path to 'public'
as $$
  with sp as (select value v from system_config where key = 'sender_profile'),
  f as (
    select distinct on (cf.company_id) cf.*, c.name company, c.company_type, o.id opp_id, o.primary_stream, st.label stream_label,
           coalesce(nullif(btrim(o.commercial_trigger), ''), nullif(btrim(o.reason), '')) why_now,
           coalesce(nullif(btrim(o.angle), ''), nullif(btrim(o.description), '')) project_idea, c.universe_reason evidence,
           k.first_name, k.last_name, k.position, coalesce(oc.family, 'HOSPITALITY_PRIVATE') family, coalesce(o.priority, 50) prio
      from contact_forms cf join companies c on c.id = cf.company_id
      join opportunities o on o.company_id = c.id and o.status in ('NEW', 'RESEARCHING', 'READY') and coalesce(o.relationship_type, 'COLD') = 'COLD'
      left join contacts k on k.id = o.contact_id and coalesce(k.do_not_contact, false) = false
      left join commercial_streams st on st.code = o.primary_stream
      left join outreach_categories oc on oc.code = outreach_category(o.primary_stream, c.company_type)
     where cf.status = 'QUALIFIED' and cf.verified_at > now() - interval '120 days' and c.merged_into is null
       and not exists (select 1 from contact_forms x where x.company_id = cf.company_id and x.status in ('PREPARED', 'APPROVED', 'SUBMITTED'))
       and length(coalesce(o.commercial_trigger, o.reason, '')) >= 25 and length(coalesce(nullif(o.angle, ''), o.description, '')) >= 25
     order by cf.company_id, (cf.form_type = 'CONTACT'), o.priority desc nulls last)
  select coalesce(jsonb_agg(jsonb_build_object(
           'form_id', f.id, 'url', f.url, 'form_type', f.form_type, 'target_team', f.target_team, 'fields', f.fields, 'required', to_jsonb(f.required_fields),
           'max_chars', f.max_message_chars, 'company', f.company, 'stream', f.stream_label, 'family', f.family,
           'person', nullif(btrim(coalesce(f.first_name, '') || ' ' || coalesce(f.last_name, '')), ''), 'position', f.position,
           'why_now', left(f.why_now, 600), 'project_idea', left(f.project_idea, 600), 'evidence', left(f.evidence, 600),
           'sender', (select v from sp)) order by f.prio desc), '[]'::jsonb)
    from (select * from f order by prio desc limit greatest(coalesce(p_limit, 15), 1)) f
$$;

create or replace function public.form_prepare_save(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public'
as $$
declare cf contact_forms%rowtype; v_company text; q jsonb;
begin
  select * into cf from contact_forms where id = nullif(p->>'form_id', '')::uuid for update;
  if cf.id is null then return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_FORM'); end if;
  if cf.status <> 'QUALIFIED' then return jsonb_build_object('ok', false, 'reason', 'NOT_QUALIFIED', 'status', cf.status); end if;
  if exists (select 1 from contact_forms x where x.company_id = cf.company_id and x.id <> cf.id and x.status in ('PREPARED', 'APPROVED', 'SUBMITTED')) then
    update contact_forms set status = 'SUPERSEDED', updated_at = now() where id = cf.id;
    return jsonb_build_object('ok', false, 'reason', 'ANOTHER_FORM_ACTIVE');
  end if;
  select name into v_company from companies where id = cf.company_id;
  q := form_message_quality(p->>'subject', p->>'message', cf.max_message_chars, v_company);
  update contact_forms set qa_status = q->>'status', qa_issues = q, updated_at = now(),
         prepared_subject = left(nullif(btrim(p->>'subject'), ''), 120), prepared_message = case when q->>'status' = 'PASS' then p->>'message' else prepared_message end,
         prepared_fields = case when q->>'status' = 'PASS' then coalesce(p->'fields', '{}'::jsonb) else prepared_fields end,
         prepared_at = case when q->>'status' = 'PASS' then now() else prepared_at end, prepared_by = coalesce(nullif(p->>'model', ''), 'W27'),
         status = case when q->>'status' = 'PASS' then 'PREPARED' else status end
   where id = cf.id;
  insert into research_credit_ledger (provider, credits, usd, purpose, company_id, outcome, detail, actor)
  values ('GEMINI', 1, nullif(p->>'usd', '')::numeric, 'FORM', cf.company_id, q->>'status', left(coalesce(p->>'model', ''), 80), 'W27');
  return jsonb_build_object('ok', true, 'form_id', cf.id, 'quality', q);
end $$;

-- 9. HQ: form detail and Adam's approval (approval only; nothing is submitted here).
create or replace function public.hq_form_detail(p_id uuid) returns jsonb
 language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); r jsonb;
begin
  select jsonb_build_object('ok', true, 'id', cf.id, 'company', c.name, 'url', cf.url, 'source_url', cf.source_url, 'form_type', cf.form_type,
           'target_team', cf.target_team, 'fields', cf.fields, 'required', to_jsonb(cf.required_fields), 'max_chars', cf.max_message_chars,
           'captcha', cf.captcha, 'attachments_allowed', cf.attachments_allowed, 'status', cf.status, 'subject', cf.prepared_subject,
           'message', cf.prepared_message, 'prepared_fields', cf.prepared_fields, 'qa', cf.qa_issues, 'verified_at', cf.verified_at,
           'approved_at', cf.approved_at, 'submitted_at', cf.submitted_at, 'confirmation', cf.confirmation_text, 'reference', cf.reference,
           'rule', 'Approving records your go-ahead. The operating agent then submits this form once, records the confirmation, and no cold email goes to this company while the form route is active.')
    into r from contact_forms cf join companies c on c.id = cf.company_id where cf.id = p_id;
  return coalesce(r, jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'));
end $$;

create or replace function public.hq_form_action(p_id uuid, p_action text, p_note text default null) returns jsonb
 language plpgsql security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); cf contact_forms%rowtype; v_new text;
begin
  select * into cf from contact_forms where id = p_id for update;
  if cf.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  p_action := upper(coalesce(p_action, ''));
  if p_action = 'APPROVE' then
    if cf.status <> 'PREPARED' then return jsonb_build_object('ok', false, 'reason', 'NOT_PREPARED', 'status', cf.status); end if;
    -- One account, one active cold route: no form while an email route is live or was used recently.
    if exists (select 1 from outbound_emails e where e.company_id = cf.company_id and e.status in ('QUEUED', 'CLAIMED', 'DRAFTED', 'SENT') and e.created_at > now() - interval '180 days')
       or exists (select 1 from interactions i where i.company_id = cf.company_id and i.direction = 'OUTBOUND' and i.occurred_at > now() - interval '180 days') then
      return jsonb_build_object('ok', false, 'reason', 'ACTIVE_ROUTE_EXISTS');
    end if;
    v_new := 'APPROVED';
  elsif p_action = 'REJECT' then
    if cf.status not in ('QUALIFIED', 'PREPARED', 'APPROVED') then return jsonb_build_object('ok', false, 'reason', 'LOCKED_STATUS', 'status', cf.status); end if;
    v_new := 'REJECTED';
  elsif p_action = 'REOPEN' then
    if cf.status <> 'APPROVED' then return jsonb_build_object('ok', false, 'reason', 'NOT_APPROVED'); end if;
    v_new := 'PREPARED';
  else
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION');
  end if;
  update contact_forms set status = v_new, updated_at = now(),
         approved_at = case when v_new = 'APPROVED' then now() when v_new = 'PREPARED' then null else approved_at end,
         approved_note = case when v_new = 'APPROVED' then p_note else approved_note end,
         reject_reason = case when v_new = 'REJECTED' then coalesce(p_note, 'Rejected by Adam') else reject_reason end
   where id = cf.id;
  insert into approval_audit (opportunity_id, action, result, actor, detail)
  values (cf.opportunity_id, 'FORM_' || p_action, v_new, coalesce(v_admin, 'hq'), jsonb_build_object('form_id', cf.id, 'url', cf.url, 'note', p_note));
  return jsonb_build_object('ok', true, 'status', v_new);
end $$;

-- Recorded by the operating agent after it submits an APPROVED form (never before approval).
create or replace function public.form_submission_record(p_id uuid, p_ok boolean, p_confirmation text, p_reference text, p_content jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public'
as $$
declare cf contact_forms%rowtype; v_company text;
begin
  select * into cf from contact_forms where id = p_id for update;
  if cf.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if cf.status <> 'APPROVED' or cf.approved_at is null then return jsonb_build_object('ok', false, 'reason', 'NOT_APPROVED'); end if;
  if not coalesce(p_ok, false) then
    update contact_forms set status = 'FAILED', confirmation_text = left(p_confirmation, 2000), updated_at = now() where id = cf.id;
    insert into approval_audit (opportunity_id, action, result, actor, detail) values (cf.opportunity_id, 'FORM_SUBMIT', 'FAILED', 'agent', jsonb_build_object('form_id', cf.id, 'detail', left(p_confirmation, 500)));
    return jsonb_build_object('ok', true, 'status', 'FAILED');
  end if;
  update contact_forms set status = 'SUBMITTED', submitted_at = now(), submitted_content = coalesce(p_content, jsonb_build_object('subject', prepared_subject, 'message', prepared_message, 'fields', prepared_fields)),
         confirmation_text = left(p_confirmation, 2000), reference = left(p_reference, 200), next_follow_up_on = current_date + 7, updated_at = now()
   where id = cf.id;
  select name into v_company from companies where id = cf.company_id;
  insert into interactions (company_id, opportunity_id, channel, direction, subject, summary, occurred_at)
  values (cf.company_id, cf.opportunity_id, 'WEBSITE', 'OUTBOUND', coalesce(cf.prepared_subject, 'Website form'),
          'Website form submitted with Adam''s approval: ' || cf.url || coalesce(' · reference ' || p_reference, ''), now());
  if cf.opportunity_id is not null then
    update opportunities set status = 'CONTACTED', next_action = 'Website form submitted ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon') || '; check for a reply, follow up once after 7 days if there is a reason',
           next_action_due = current_date + 7, updated_at = now()
     where id = cf.opportunity_id and status in ('NEW', 'RESEARCHING', 'READY');
  end if;
  insert into approval_audit (opportunity_id, action, result, actor, detail) values (cf.opportunity_id, 'FORM_SUBMIT', 'SUBMITTED', 'agent', jsonb_build_object('form_id', cf.id, 'reference', p_reference));
  return jsonb_build_object('ok', true, 'status', 'SUBMITTED');
end $$;

-- 10. Failed-draft repair: a failed draft is not a failed account. Diagnose, free the account for W18's next run (which drafts
-- carried-over PLANNED candidates first with its one automatic redraft), at most twice per draft.
create or replace function public.outreach_draft_repair(p_limit integer default null) returns jsonb
 language plpgsql security definer set search_path to 'public'
as $$
declare v_cfg jsonb; v_lim int; v_max int; r record; n_repair int := 0; n_research int := 0; v_diag text;
begin
  select value->'draft_repair' into v_cfg from system_config where key = 'acquisition_engine';
  v_lim := least(coalesce(p_limit, (v_cfg->>'per_night')::int, 30), coalesce((v_cfg->>'max_per_night')::int, 50));
  v_max := coalesce((v_cfg->>'max_repairs_per_draft')::int, 2);
  for r in
    select oc.id, oc.task_id, oc.opportunity_id, oc.qa_issues, oc.repair_count
      from outreach_candidates oc
      join opportunities o on o.id = oc.opportunity_id and o.status in ('NEW', 'RESEARCHING', 'READY') and coalesce(o.relationship_type, 'COLD') = 'COLD'
      left join daily_outreach_queue q on q.opportunity_id = oc.opportunity_id and q.run_date = (select max(run_date) from daily_outreach_runs)
     where not oc.dry_run and oc.channel = 'EMAIL' and oc.status = 'REVIEW_REQUIRED' and oc.repair_count < v_max
       and oc.created_at > now() - interval '45 days' and oc.review_reason is null and coalesce(oc.qa_status, '') <> 'PASS' and relationship_state(o.company_id) = 'COLD'
     order by (q.lane = 'NEEDS_DRAFT') desc nulls last, q.score desc nulls last, oc.updated_at desc
     limit v_lim
  loop
    v_diag := case
      when coalesce(r.qa_issues::text, '') ~* '(RATE_LIMITED|MODEL_ERROR|EMPTY|Service unavailable)' then 'MODEL_LIMIT'
      when coalesce(r.qa_issues::text, '') ~* '(UNSUPPORTED_TERMS|BANNED|PRESUMPTUOUS|LUXURY_ADJECTIVES|TOO_LONG|TOO_SHORT|GREETING|SUBJECT|QUESTION|NO_CTA)' then 'COPY'
      when jsonb_array_length(coalesce(r.qa_issues->'evidence_terms', '[]'::jsonb)) < 3 then 'THIN_EVIDENCE'
      else 'OTHER' end;
    if v_diag = 'THIN_EVIDENCE' then
      n_research := n_research + 1;  -- left for re-research (W23 / operating agent); not redrafted from thin evidence
      continue;
    end if;
    if r.task_id is not null then
      update tasks set status = 'CANCELLED', updated_at = now(),
             description = 'Draft repair ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon') || ' (' || v_diag || '): rewritten by W18 on its next run.' || chr(10) || coalesce(description, '')
       where id = r.task_id and status in ('OPEN', 'IN_PROGRESS', 'WAITING');
    end if;
    update outreach_candidates set status = 'PLANNED', run_date = current_date, qa_status = null, review_action = null, reviewed_at = null,
           hold_reason = 'REPAIR ' || v_diag || ': ' || left(coalesce(qa_issues->>'final', qa_issues::text, ''), 300), repair_count = repair_count + 1, updated_at = now()
     where id = r.id;
    n_repair := n_repair + 1;
  end loop;
  insert into system_config (key, value, note) values ('draft_repair_last', jsonb_build_object('at', now(), 'repaired', n_repair, 'needs_research', n_research, 'limit', v_lim),
    'Last failed-draft repair run (outreach_draft_repair).')
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('ok', true, 'repaired', n_repair, 'needs_research', n_research);
end $$;

-- 11. Credit budgets: remaining allowance over the remaining runway / cycle, and what was spent today.
create or replace function public.research_credit_budget() returns jsonb
 language plpgsql stable security definer set search_path to 'public'
as $$
declare rc jsonb; su jsonb; h jsonb; v_serper numeric; v_runway int; v_fc_rem numeric; v_fc_used numeric; v_days_left int; v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  select value into rc from system_config where key = 'research_credits';
  select value into h from system_config where key = 'hunter_account';
  su := serper_usage(3);
  v_serper := coalesce((su->>'balance')::numeric, 0);
  v_runway := coalesce((rc->'serper'->>'target_runway_days')::int, 30);
  v_fc_used := coalesce((select sum(credits) from research_credit_ledger where provider = 'FIRECRAWL' and at > coalesce(nullif(rc->'firecrawl'->>'as_of', '')::date, current_date - 30)), 0);
  v_fc_rem := greatest(coalesce((rc->'firecrawl'->>'remaining')::numeric, 0) - v_fc_used, 0);
  v_days_left := greatest(coalesce((rc->'firecrawl'->>'cycle_day')::int, 30) - extract(day from v_today)::int, 1);
  return jsonb_build_object(
    'serper', jsonb_build_object('balance', v_serper, 'burn_per_day', su->'per_day', 'runway_days', su->'runway_days',
              'daily_allowance', greatest(floor((v_serper - coalesce((rc->'serper'->>'reserve')::numeric, 300)) / v_runway), 0),
              'status', case when coalesce((su->>'runway_days')::numeric, 99) < 7 then 'CRITICAL' when coalesce((su->>'runway_days')::numeric, 99) < 21 then 'TIGHT' else 'OK' end,
              'recommendation', case when coalesce((su->>'runway_days')::numeric, 99) < 21 then 'Top up Serper (Starter pack: USD 50 for 50,000 searches, 6-month expiry) or keep discovery at the daily allowance. Needs Adam.' end),
    'firecrawl', jsonb_build_object('remaining_est', v_fc_rem, 'used_since_as_of', v_fc_used, 'daily_allowance', greatest(floor((v_fc_rem - coalesce((rc->'firecrawl'->>'reserve')::numeric, 100)) / v_days_left), 0),
              'basis', 'remaining recorded on ' || coalesce(rc->'firecrawl'->>'as_of', '?') || ' minus logged use'),
    'clay', jsonb_build_object('remaining', rc->'clay'->'remaining', 'per_day_cap', rc->'clay'->'per_day_cap',
              'used_today', (select coalesce(sum(credits), 0) from research_credit_ledger where provider = 'CLAY' and (at at time zone 'Africa/Cairo')::date = v_today)),
    'hunter', jsonb_build_object('available', (h->>'credits_available')::numeric - coalesce((h->>'credits_used')::numeric, 0), 'reset', h->>'reset_date'),
    'today', (select coalesce(jsonb_object_agg(provider, n), '{}'::jsonb) from (select provider, sum(credits) n from research_credit_ledger where (at at time zone 'Africa/Cairo')::date = v_today group by 1) x));
end $$;

-- 12. Builder v2: 14 gates, one best route per account (email or a commercial website form), family cap and round-robin order,
--     inventory targets from config. MORNING / TOPUP semantics, the route cache shortcut and the set-based conflict lookups are kept.
alter table public.daily_outreach_queue drop constraint if exists daily_outreach_queue_lane_check;
alter table public.daily_outreach_queue add constraint daily_outreach_queue_lane_check
  check (lane in ('TODAY', 'FORM_READY', 'RESERVE', 'NEEDS_CONTACT', 'NEEDS_DRAFT'));
alter table public.daily_outreach_queue drop constraint if exists daily_outreach_queue_ready_gates;
alter table public.daily_outreach_queue add constraint daily_outreach_queue_ready_gates
  check (lane not in ('TODAY', 'FORM_READY', 'RESERVE') or cardinality(failed) = 0);

update public.system_config set value = jsonb_set(value, '{inventory,family_cap_overrides}',
  jsonb_build_object('WEDDINGS_EVENTS', 10, '_reason', jsonb_build_object('WEDDINGS_EVENTS',
    'Adam, final engine brief 22 Nov 2026: weddings must never dominate because old inventory is easier. Capped at its target maximum; overflow stays in Reserve.')))
 where key = 'acquisition_engine';

-- Route rank (lower is stronger), the order in acquisition_engine.route_ranking: WARM 1, named email 2, management/agent 3,
-- validated work email 4, Instagram business email 5, commercial form 6, Clay 7, official inbox 8, general contact form 9, LinkedIn 10, Instagram DM 11.
create or replace function public.route_rank_of(p_channel text, p_canonical text, p_form_type text default null) returns smallint
 language sql immutable set search_path to 'public'
as $$
  select (case
    when p_channel = 'WARM' then 1
    when p_channel = 'FORM' then case when coalesce(p_form_type, 'CONTACT') = 'CONTACT' then 9 else 6 end
    when p_channel = 'LINKEDIN' then 10
    when p_channel = 'INSTAGRAM' then 11
    else case p_canonical when 'PUBLIC_NAMED_EMAIL' then 2 when 'MANAGEMENT_EMAIL' then 3 when 'AGENT_EMAIL' then 3
                          when 'VALID_VERIFIED' then 4 when 'PUBLIC_PROFESSIONAL_EMAIL' then 4 when 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM' then 5
                          when 'CLAY_WORK_EMAIL' then 7 when 'OFFICIAL_PUBLISHED_INBOX' then 8 else 99 end end)::smallint
$$;

create or replace function public.form_type_label(p text) returns text
 language sql immutable set search_path to 'public'
as $$
  select case p when 'PARTNERSHIP' then 'Partnership form' when 'SUPPLIER_VENDOR' then 'Supplier / vendor form' when 'NEW_BUSINESS' then 'New business form'
                when 'TRAVEL_ADVISOR' then 'Travel advisor form' when 'AGENCY_ENQUIRY' then 'Management / agency enquiry form'
                when 'GROUP_EVENT' then 'Group / event enquiry form' when 'MEMBERSHIP_PARTNERSHIP' then 'Membership partnership form'
                when 'PRESS_PRODUCTION' then 'Press / production form' when 'BRAND_PARTNERSHIP' then 'Brand partnership form'
                when 'WHOLESALE_COMMERCIAL' then 'Commercial / wholesale form' when 'CORPORATE_ENQUIRY' then 'Corporate enquiry form'
                when 'RESIDENCE_OWNER' then 'Owner / residence services form' when 'CONTACT' then 'General contact form' else 'Website form' end
$$;

create or replace function public.outreach_queue_build(p_mode text default 'MORNING') returns jsonb
 language plpgsql security definer set search_path to 'public' set statement_timeout to '55s'
as $$
declare
  v_date date := (now() at time zone 'Africa/Cairo')::date;
  v_dow int := extract(dow from (now() at time zone 'Africa/Cairo'))::int;
  v_day_start timestamptz := ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo';
  v_t0 timestamptz := clock_timestamp();
  v_cfg jsonb; v_inv jsonb; v_floor int; v_w jsonb; v_sent_today int; v_slots int; v_marked int; v_marked_f int;
  v_res int; v_nd int; v_nc int; v_share numeric;
  v_funnel jsonb; v_cat jsonb; v_fail jsonb; v_today int; v_bottleneck text; v_engine jsonb;
begin
  p_mode := upper(coalesce(p_mode, 'MORNING'));
  if p_mode not in ('MORNING', 'TOPUP') then raise exception 'outreach_queue_build: mode must be MORNING or TOPUP'; end if;
  if not pg_try_advisory_xact_lock(hashtext('outreach_queue_build')) then return jsonb_build_object('ok', false, 'reason', 'BUSY'); end if;
  select value into v_cfg from system_config where key = 'acquisition_engine';
  v_inv := coalesce(v_cfg->'inventory', '{}'::jsonb);
  v_floor := coalesce((v_inv->>'ready_target')::int, (v_cfg->>'send_ready_floor')::int, 25);
  v_res := coalesce((v_inv->>'reserve_target')::int, 100);
  v_nd := coalesce((v_inv->>'needs_draft_target')::int, 100);
  v_nc := coalesce((v_inv->>'needs_contact_target')::int, 150);
  v_share := coalesce((v_inv->>'family_cap_share')::numeric, 0.25);
  v_w := coalesce(outreach_learning_weights()->'weights', '{}'::jsonb);

  -- 1. Adam's manual sends (and approved form submissions) since the start of the Cairo day stay in the queue as SENT.
  update daily_outreach_queue q set state = 'SENT', state_at = now(), state_reason = 'First touch sent by Adam from Gmail'
   where q.run_date = v_date and q.state = 'QUEUED' and q.lane in ('TODAY', 'RESERVE')
     and (exists (select 1 from interactions i where i.opportunity_id = q.opportunity_id and i.direction = 'OUTBOUND' and i.channel = 'EMAIL' and i.occurred_at >= v_day_start)
          or exists (select 1 from outbound_emails e where e.opportunity_id = q.opportunity_id and e.status = 'SENT' and coalesce(e.sent_at, e.updated_at) >= v_day_start));
  get diagnostics v_marked = row_count;
  update daily_outreach_queue q set state = 'SENT', state_at = now(), state_reason = 'Website form submitted with Adam''s approval'
   where q.run_date = v_date and q.state = 'QUEUED' and q.lane = 'FORM_READY'
     and exists (select 1 from contact_forms f where f.id = q.form_id and f.status = 'SUBMITTED' and f.submitted_at >= v_day_start);
  get diagnostics v_marked_f = row_count;
  select count(*) into v_sent_today from daily_outreach_queue where run_date = v_date and lane in ('TODAY', 'FORM_READY') and state = 'SENT';
  v_slots := greatest(v_floor - v_sent_today, 0);

  -- 2. Evaluate the live cold universe once against the 14 gates, for the email route and for a website form route.
  create temp table _e on commit drop as
  with cand as (
    select distinct on (oc.opportunity_id) oc.opportunity_id, oc.id cand_id, oc.contact_id cand_contact, oc.route_contact_id, oc.status cand_status,
           oc.qa_status, oc.first_pass_ok, oc.subject cand_subject, oc.draft cand_draft, oc.why_now cand_why, oc.angle cand_angle, oc.task_id, oc.created_at cand_created, oc.review_reason cand_review
      from outreach_candidates oc
     where not oc.dry_run and oc.channel = 'EMAIL' and oc.opportunity_id is not null and oc.status in ('READY', 'APPROVED', 'REVIEW_REQUIRED', 'HOLD', 'PLANNED')
     order by oc.opportunity_id, (oc.status = 'APPROVED') desc, (oc.status = 'READY') desc, oc.updated_at desc),
  ob as (
    select distinct on (e.opportunity_id) e.opportunity_id, e.id ob_id, e.gmail_draft_id, e.subject ob_subject, e.body ob_body
      from outbound_emails e where e.status in ('QUEUED', 'CLAIMED', 'DRAFTED') and e.opportunity_id is not null
     order by e.opportunity_id, e.created_at desc),
  -- One website form per company: an approved or prepared form first, then the most specific qualified form.
  fm as (
    select distinct on (f.company_id) f.company_id, f.id form_id, f.status form_status, f.form_type, f.target_team, f.url form_url,
           coalesce(f.source_url, f.url) form_src, f.qa_status form_qa, f.prepared_subject form_subject, f.prepared_message form_message,
           f.verified_at form_verified, f.login_required form_login
      from contact_forms f where f.status in ('APPROVED', 'PREPARED', 'QUALIFIED')
     order by f.company_id, (f.status = 'APPROVED') desc, (f.status = 'PREPARED') desc, (f.form_type = 'CONTACT'), f.verified_at desc nulls last),
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
           o.angle o_angle, o.description, o.next_action, o.created_at o_created, o.updated_at o_updated,
           c.name cname, c.website, c.instagram cinsta, c.linkedin clinked, c.outreach_hold_until, c.company_type, c.commercial_class, c.relationship_status crel,
           c.universe_status cuniv, c.noya_fit,
           cd.cand_id, cd.cand_contact, cd.route_contact_id, cd.cand_status, cd.qa_status, cd.first_pass_ok, cd.cand_subject, cd.cand_draft, cd.cand_why,
           cd.cand_angle, cd.task_id, cd.cand_created, cd.cand_review, ob.ob_id, ob.gmail_draft_id, ob.ob_subject, ob.ob_body,
           fm.form_id, fm.form_status, fm.form_type, fm.target_team, fm.form_url, fm.form_src, fm.form_qa, fm.form_subject, fm.form_message, fm.form_verified, fm.form_login,
           coalesce(cd.cand_contact, o.contact_id) person_id
      from opportunities o join companies c on c.id = o.company_id
      left join cand cd on cd.opportunity_id = o.id left join ob on ob.opportunity_id = o.id left join fm on fm.company_id = o.company_id
     where o.status in ('NEW', 'RESEARCHING', 'READY') and coalesce(o.relationship_type, 'COLD') = 'COLD'
       and c.merged_into is null and coalesce(c.universe_status, '') not in ('EXCLUDED', 'PARKED')),
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
           split_part(regexp_replace(lower(coalesce(x.cname, '')), '^(the|la|le|el|al)\s+', ''), ' ', 1) ptoken,
           -- A 22 Nov readiness hold (qa PASS but held by the readiness check) fails the gate it names, not the draft gate.
           case when x.cand_status = 'REVIEW_REQUIRED' and x.qa_status = 'PASS' and x.cand_review is not null then
             case when x.cand_review ~* '(right person|named route|addressed to|wrong person)' then 'decision_maker'
                  when x.cand_review ~* '(route unverified|unverified route)' then 'contact_route'
                  when x.cand_review ~* '(weak noya fit|weak fit)' then 'commercial_fit'
                  when x.cand_review ~* '(trigger|sourced fact|past event|claim|unsourced|ai summary)' then 'commercial_reason'
                  else 'project_hypothesis' end end hold_gate
      from routed x),
  -- Materialised: the gate expressions (relationship_state, conflict lookups) are evaluated once per row, not once per reference.
  typed as materialized (
    select y.*, outreach_source_type(y.kr_src_type, y.src_url, y.website, y.kr_provider) src_type,
           outreach_category(y.primary_stream, y.company_type) category
      from canon y),
  gated as materialized (
    select t.*,
      -- Common gates (both channels).
      (t.website is not null or t.cinsta is not null or t.clinked is not null) account_ok,
      exists (select 1 from commercial_streams s where s.code = t.primary_stream and s.active) g2,
      (coalesce(t.cuniv, '') = 'QUALIFIED' and coalesce(t.priority, 50) >= 50 and coalesce(t.noya_fit, 60) >= 55 and t.hold_gate is distinct from 'commercial_fit') gfit,
      (length(coalesce(t.why_now, '')) >= 25 and t.hold_gate is distinct from 'commercial_reason') g3,
      (length(coalesce(t.project_idea, '')) >= 25 and t.hold_gate is distinct from 'project_hypothesis') g4,
      length(btrim(coalesce(t.next_action, ''))) > 5 g10,
      (not coalesce(t.k_dnc, false) and not coalesce(t.kr_dnc, false) and lower(coalesce(t.crel, '')) not in ('do not contact', 'do_not_contact')) gdnc,
      (coalesce(t.outreach_hold_until, '-infinity'::timestamptz) < now()
        and coalesce(t.commercial_class, '') <> 'SUPPLIER'
        and lower(coalesce(t.crel, '')) not in ('supplier', 'client', 'partner')
        and t.cand_status is distinct from 'HOLD'
        and relationship_state(t.company_id) = 'COLD'
        and not exists (select 1 from live_other lo where lo.company_id = t.company_id and lo.id <> t.opportunity_id)
        and not exists (select 1 from touched tc where tc.company_id = t.company_id and tc.last_out > now() - interval '180 days')
        and (t.email is null or not exists (select 1 from sent_to s where s.em = lower(t.email)))
        and (length(coalesce(t.commercial_trigger, '')) > 20 or not exists (select 1 from touched tc where tc.company_id = t.company_id))) gco,
      (t.o_created > now() - interval '180 days' or t.o_updated > now() - interval '120 days' or t.cand_created > now() - interval '30 days') gcur,
      -- Email route gates.
      ((t.website is not null or t.cinsta is not null or t.clinked is not null)
        and ((t.person is not null and (t.identity_status = 'CONFIRMED' or (t.identity_status is null and coalesce(t.k_src, t.k_li, '') <> '')))
             or (t.person is null and t.canonical = 'OFFICIAL_PUBLISHED_INBOX'))) g1,
      ((t.person is not null and coalesce(role_score(t.position), 0) > 0 and coalesce(t.position, '') !~* '(intern|student|trainee|volunteer|scout|recruit)')
        or (t.person is null and t.canonical = 'OFFICIAL_PUBLISHED_INBOX')) and t.hold_gate is distinct from 'decision_maker' g5,
      (t.canonical in ('VALID_VERIFIED', 'PUBLIC_NAMED_EMAIL', 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM', 'PUBLIC_PROFESSIONAL_EMAIL', 'MANAGEMENT_EMAIL', 'AGENT_EMAIL',
                       'CLAY_WORK_EMAIL', 'OFFICIAL_PUBLISHED_INBOX')
        and t.email is not null and coalesce(email_local_class(t.email), '') <> 'EXCLUDED'
        and split_part(lower(t.email), '@', 1) !~ '^(support|help|helpdesk|careers?|jobs|hr|recruit(ment|ing)?|privacy|legal|dpo|gdpr|reservations?|bookings?|no-?reply|abuse|billing|accounts|invoices?|webmaster)$'
        and coalesce(t.kr_status, '') <> 'INVALID' and t.hold_gate is distinct from 'contact_route') g6,
      (coalesce(t.src_url, '') ~ '^https?://' or t.kr_src_type in ('CLAY', 'PROVIDER') or t.kr_provider is not null) g7,
      (coalesce(t.canonical, 'UNKNOWN') not in ('UNKNOWN', 'NOT_FOUND', 'INVALID') and t.src_type is not null) g8,
      ((t.cand_status = 'APPROVED' or (t.cand_status = 'READY' and t.qa_status in ('PASS', 'HUMAN_REVIEWED')) or t.ob_id is not null)
        and length(coalesce(t.draft_text, '')) >= 200 and coalesce(t.draft_text, '') !~* '(\{\{|\[name\]|\[company\]|lorem ipsum)'
        and (t.ob_id is not null or t.cand_created > now() - interval '30 days')
        and ((length(t.ptoken) >= 3 and position(t.ptoken in lower(t.draft_text)) > 0)
             or (length(coalesce(t.first_name, '')) >= 2 and position(lower(t.first_name) in lower(t.draft_text)) > 0))) g9,
      -- Website form route gates (official commercial form; the team is the gatekeeper).
      (t.form_id is not null and t.form_type is not null and t.form_type <> 'NON_COMMERCIAL' and not coalesce(t.form_login, false)
        and t.form_verified > now() - interval '120 days') f_route,
      (coalesce(t.form_src, '') ~ '^https?://') f_prov,
      (t.form_id is not null and (t.target_team is not null or t.form_type = 'CONTACT')) f_dm,
      (t.form_status in ('PREPARED', 'APPROVED') and t.form_qa = 'PASS' and length(coalesce(t.form_message, '')) >= 150
        and coalesce(t.form_message, '') !~* '(\{\{|\[name\]|\[company\])') f_draft
      from typed t),
  chans as (
    select g.*,
      (g.g1 and g.g2 and g.gfit and g.g4 and g.g3 and g.g5 and g.g6 and g.g7 and g.g8 and g.g9 and g.gdnc and g.gco and g.gcur and g.g10) email_ready,
      (g.account_ok and g.g2 and g.gfit and g.g4 and g.g3 and g.f_dm and g.f_route and g.f_prov and g.f_draft and g.gdnc and g.gco and g.gcur and g.g10) form_ready,
      route_rank_of('EMAIL', g.canonical) e_rank, route_rank_of('FORM', null, g.form_type) f_rank
      from gated g),
  picked as (
    select c.*,
      -- ONE ACCOUNT, ONE ACTIVE COLD ROUTE: an approved email (Gmail draft) locks email; an approved form locks the form; otherwise the stronger route.
      case when c.email_ready and c.ob_id is not null then 'EMAIL'
           when c.form_ready and c.form_status = 'APPROVED' then 'FORM'
           when c.email_ready and c.form_ready then case when c.e_rank <= c.f_rank then 'EMAIL' else 'FORM' end
           when c.email_ready then 'EMAIL'
           when c.form_ready then 'FORM' end chan
      from chans c),
  shown as (
    select p.*,
      coalesce(p.chan, case when p.f_route and p.f_prov and not (p.g6 and p.g7 and p.g8) then 'FORM' else 'EMAIL' end) fchan
      from picked p),
  scored as (
    select s.*,
      case when s.fchan = 'FORM' then s.account_ok else s.g1 end x_person,
      case when s.fchan = 'FORM' then s.f_dm else s.g5 end x_dm,
      case when s.fchan = 'FORM' then s.f_route else s.g6 end x_route,
      case when s.fchan = 'FORM' then s.f_prov else s.g7 end x_prov,
      case when s.fchan = 'FORM' then s.f_route else s.g8 end x_class,
      case when s.fchan = 'FORM' then s.f_draft else s.g9 end x_draft
      from shown s),
  final as (
    select z.*,
      (z.x_person and z.g2 and z.gfit and z.g4 and z.g3 and z.x_dm and z.x_route and z.x_prov and z.x_class and z.x_draft and z.gdnc and z.gco and z.gcur and z.g10) ready,
      array_remove(array[case when not z.x_person then 'real_account_person' end, case when not z.g2 then 'stream' end,
                         case when not z.gfit then 'commercial_fit' end, case when not z.g4 then 'project_hypothesis' end,
                         case when not z.g3 then 'commercial_reason' end, case when not z.x_dm then 'decision_maker' end,
                         case when not z.x_route then 'contact_route' end, case when not z.x_prov then 'provenance' end,
                         case when not z.x_class then 'route_classification' end, case when not z.x_draft then 'personalised_draft' end,
                         case when not z.gdnc then 'no_dnc' end, case when not z.gco then 'no_company_conflict' end,
                         case when not z.gcur then 'research_current' end, case when not z.g10 then 'next_action' end], null) failed,
      round(coalesce(z.priority, 50) * 0.5, 1) s_base,
      case when z.fchan = 'FORM' then case when z.form_type = 'CONTACT' then 3 else 9 end
           else case z.canonical when 'VALID_VERIFIED' then 15 when 'PUBLIC_NAMED_EMAIL' then 14 when 'MANAGEMENT_EMAIL' then 12 when 'AGENT_EMAIL' then 12
                       when 'PUBLIC_PROFESSIONAL_EMAIL' then 11 when 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM' then 9 when 'OFFICIAL_PUBLISHED_INBOX' then 5
                       when 'CLAY_WORK_EMAIL' then 4 else 0 end end s_route,
      least(coalesce(role_score(z.position), 0), 5) * 2 s_role,
      case when length(coalesce(z.commercial_trigger, '')) > 20 then 8 else 0 end s_trigger,
      case when z.fchan = 'FORM' then case when z.form_status = 'APPROVED' then 6 when z.f_draft then 4 else 0 end
           when z.cand_status = 'APPROVED' or z.ob_id is not null then 6 when z.first_pass_ok then 4 when z.cand_status = 'READY' then 2 else 0 end s_draft,
      case when z.o_created > now() - interval '7 days' then 3 else 0 end s_fresh,
      case when outreach_market_open(z.market, v_dow) then 2 else 0 end s_market,
      coalesce((select exp(sum(ln((v_w->>k)::numeric))) from unnest(array['category:' || coalesce(z.category, ''), 'route_type:' || coalesce(z.canonical, ''),
                 'dm_role:' || outreach_role_bucket(z.position), 'source:' || coalesce(z.src_type, ''), 'angle:' || outreach_angle_bucket(z.project_idea),
                 'stream:' || coalesce(z.primary_stream, '')]) k where v_w ? k), 1) w_learn,
      coalesce((select oc.family from outreach_categories oc where oc.code = z.category), 'HOSPITALITY_PRIVATE') family,
      coalesce((select f.multiplier from outreach_categories oc join outreach_families f on f.code = oc.family where oc.code = z.category), false) multiplier
      from scored z)
  select f.*,
         round((f.s_base + f.s_route + f.s_role + f.s_trigger + f.s_draft + f.s_fresh + f.s_market + case when f.multiplier then 4 else 0 end) * f.w_learn, 2) raw,
         case when f.fchan = 'FORM' then route_rank_of('FORM', null, f.form_type) else route_rank_of('EMAIL', f.canonical) end r_rank,
         -- Fallback: the next legitimate route, used only after the primary route has run its course (never at the same time).
         case when f.fchan = 'FORM' then
                case when f.g6 and f.g7 then 'EMAIL · ' || route_label(f.canonical)
                     when coalesce(f.k_li, '') <> '' then 'LINKEDIN · decision maker profile'
                     when coalesce(f.clinked, '') <> '' then 'LINKEDIN · company page'
                     when coalesce(f.cinsta, '') <> '' then 'INSTAGRAM · business profile' end
              else
                case when f.f_route then 'FORM · ' || form_type_label(f.form_type)
                     when coalesce(f.k_li, '') <> '' then 'LINKEDIN · decision maker profile'
                     when coalesce(f.clinked, '') <> '' then 'LINKEDIN · company page'
                     when coalesce(f.cinsta, '') <> '' then 'INSTAGRAM · business profile' end end fallback
    from final f;

  -- 3. Rank: one route per company; a family cap (25% of the ready target unless a documented override); then round-robin by family
  --    (two per family per round) so the top of the list is a balanced portfolio, never one easy segment.
  create temp table _rk on commit drop as
  with rdy as (select e.*, row_number() over (partition by e.company_id order by e.raw desc, e.opportunity_id) rn_co from _e e where e.ready),
  fam as (select r.*, row_number() over (partition by r.family order by r.raw desc, r.opportunity_id) k_fam from rdy r where r.rn_co = 1),
  capd as (select f.*, coalesce(case when (v_inv->'family_cap_overrides'->>f.family) ~ '^[0-9]+$' then (v_inv->'family_cap_overrides'->>f.family)::int end,
                                ceil(v_share * v_floor)::int) cap,
                  exists (select 1 from daily_outreach_queue q where q.run_date = v_date and q.opportunity_id = f.opportunity_id
                           and q.lane in ('TODAY', 'FORM_READY') and q.state = 'QUEUED') was_today
             from fam f)
  select c.*, c.raw adj, (c.k_fam <= c.cap) in_cap,
         row_number() over (order by (p_mode = 'TOPUP' and c.was_today and c.k_fam <= c.cap) desc, (c.k_fam <= c.cap) desc,
                                     ceil(c.k_fam / 2.0), c.raw desc, c.opportunity_id) pos
    from capd c;

  create temp table _lanes on commit drop as
  with sel as (
    select case when r.chan = 'FORM' then 'FORM_READY' else 'TODAY' end lane, r.pos, r.opportunity_id, r.adj score_final
      from _rk r where r.in_cap and r.pos <= v_slots),
  res as (
    select 'RESERVE'::text lane, r.pos, r.opportunity_id, r.adj score_final from _rk r
     where r.opportunity_id not in (select opportunity_id from sel) order by r.pos limit v_res)
  select s.lane, row_number() over (partition by s.lane order by s.pos)::int rnk, s.opportunity_id, s.score_final from sel s
  union all
  select r.lane, row_number() over (order by r.pos)::int, r.opportunity_id, r.score_final from res r
  union all
  select 'NEEDS_DRAFT', z.rn::int, z.opportunity_id, z.raw from (
    select e.opportunity_id, e.raw, row_number() over (order by e.multiplier desc, e.raw desc, e.opportunity_id) rn
      from (select e1.*, row_number() over (partition by e1.company_id order by e1.raw desc, e1.opportunity_id) rn_co
              from _e e1 where not e1.ready and e1.failed = array['personalised_draft']) e
     where e.rn_co = 1 and e.company_id not in (select company_id from _rk)) z where z.rn <= v_nd
  union all
  select 'NEEDS_CONTACT', z.rn::int, z.opportunity_id, z.raw from (
    select e.opportunity_id, e.raw, row_number() over (order by e.multiplier desc, e.raw desc, e.opportunity_id) rn
      from (select e1.*, row_number() over (partition by e1.company_id order by e1.raw desc, e1.opportunity_id) rn_co
              from _e e1 where not e1.ready and e1.account_ok and e1.g2 and e1.gfit and e1.g3 and e1.g4 and e1.g10 and e1.gdnc and e1.gco and e1.gcur
               and (not e1.x_person or not e1.x_dm or not e1.x_route or not e1.x_prov or not e1.x_class)) e
     where e.rn_co = 1 and e.company_id not in (select company_id from _rk)
       and e.company_id not in (select e2.company_id from _e e2 where not e2.ready and e2.failed = array['personalised_draft'])) z where z.rn <= v_nc;

  -- 4. Write: rebuild the day's live rows in place (SENT rows are never touched; rows that no longer qualify are DROPPED with history).
  update daily_outreach_queue set state = 'REBUILDING' where run_date = v_date and state = 'QUEUED';
  insert into daily_outreach_queue as q (run_date, lane, rank, state, state_at, mode, opportunity_id, company_id, contact_id, route_contact_id, candidate_id, task_id,
         outbound_email_id, category, stream, market, person, position, company, project_idea, why_now, route_email, route_canonical, route_label,
         route_source_url, route_source_type, confidence, draft_subject, draft_excerpt, draft_status, gmail_draft_id, next_action, gates, failed,
         score, score_parts, sendable_today, send_window, dims, built_at, family, route_channel, route_rank, fallback_route, form_id)
  select v_date, l.lane, l.rnk, 'QUEUED', now(), p_mode, e.opportunity_id, e.company_id, e.person_id, e.route_id, e.cand_id, e.task_id,
         e.ob_id, e.category, e.primary_stream, e.market,
         coalesce(e.person, case when e.fchan = 'FORM' and e.form_id is not null then coalesce(e.target_team, 'Enquiries') || ' team' end),
         e.position, e.cname, left(e.project_idea, 600), left(e.why_now, 600),
         case when e.fchan = 'FORM' then null else e.email end,
         case when e.fchan = 'FORM' and e.form_id is not null then case when e.form_type = 'CONTACT' then 'GENERAL_FORM' else 'COMMERCIAL_FORM' end else e.canonical end,
         case when e.fchan = 'FORM' and e.form_id is not null then form_type_label(e.form_type) || ' · official website' else route_label(e.canonical) end,
         case when e.fchan = 'FORM' and e.form_id is not null then e.form_src else e.src_url end,
         case when e.fchan = 'FORM' and e.form_id is not null then 'OFFICIAL_WEBSITE' else e.src_type end,
         case when e.fchan = 'FORM' and e.form_id is not null then case when e.form_type = 'CONTACT' then 'MEDIUM' else 'HIGH' end
              when e.canonical in ('UNKNOWN', 'NOT_FOUND', 'INVALID') or e.canonical is null then null
              when e.canonical = 'VALID_VERIFIED' then 'HIGH'
              when e.canonical in ('PUBLIC_NAMED_EMAIL', 'MANAGEMENT_EMAIL', 'AGENT_EMAIL') and coalesce(e.src_url, '') ~ '^https?://' then 'HIGH'
              when e.canonical = 'CLAY_WORK_EMAIL' or e.canonical = 'ACCEPT_ALL_RISKY' or e.canonical = 'PUBLIC_UNVERIFIED' then 'LOW'
              else 'MEDIUM' end,
         case when e.fchan = 'FORM' and e.form_id is not null then e.form_subject else e.draft_subject end,
         left(regexp_replace(coalesce(case when e.fchan = 'FORM' and e.form_id is not null then e.form_message else e.draft_text end, ''), '\s+', ' ', 'g'), 280),
         case when e.fchan = 'FORM' and e.form_id is not null then
                case e.form_status when 'APPROVED' then 'FORM_APPROVED' when 'PREPARED' then 'FORM_PREPARED' else 'FORM_DRAFTING' end
              when e.gmail_draft_id is not null then 'GMAIL_DRAFT' when e.ob_id is not null then 'APPROVED_PENDING_GMAIL'
              when e.cand_status = 'APPROVED' then 'APPROVED' when e.cand_status = 'READY' then 'READY_FOR_REVIEW'
              when e.cand_status = 'REVIEW_REQUIRED' then 'NEEDS_EDIT' when e.cand_status = 'PLANNED' then 'PLANNED_TONIGHT'
              when e.cand_status = 'HOLD' then 'HELD' else 'NONE' end,
         e.gmail_draft_id, e.next_action,
         jsonb_build_object('real_account_person', e.x_person, 'stream', e.g2, 'commercial_fit', e.gfit, 'project_hypothesis', e.g4,
                            'commercial_reason', e.g3, 'decision_maker', e.x_dm, 'contact_route', e.x_route, 'provenance', e.x_prov,
                            'route_classification', e.x_class, 'personalised_draft', e.x_draft, 'no_dnc', e.gdnc, 'no_company_conflict', e.gco,
                            'research_current', e.gcur, 'next_action', e.g10),
         e.failed, l.score_final,
         jsonb_build_object('base', e.s_base, 'route', e.s_route, 'role', e.s_role, 'signal', e.s_trigger, 'draft', e.s_draft, 'fresh', e.s_fresh,
                            'market', e.s_market, 'multiplier', case when e.multiplier then 4 else 0 end, 'learning', round(e.w_learn::numeric, 3), 'raw', e.raw),
         outreach_market_open(e.market, v_dow),
         case when outreach_market_open(e.market, v_dow) then 'Today'
              else (select to_char(v_date + d, 'Dy DD Mon') from generate_series(1, 7) d where outreach_market_open(e.market, extract(dow from v_date + d)::int) order by d limit 1) end,
         jsonb_build_object('stream', e.primary_stream, 'category', e.category, 'family', e.family, 'account_type', coalesce(e.commercial_class, e.company_type),
                            'dm_role', case when e.person is null then 'TEAM_INBOX' else outreach_role_bucket(e.position) end,
                            'source', case when e.fchan = 'FORM' then 'OFFICIAL_WEBSITE' else e.src_type end,
                            'route_type', case when e.fchan = 'FORM' then 'FORM' else e.canonical end, 'channel', e.fchan,
                            'hypothesis', e.project_type_canon, 'angle', outreach_angle_bucket(e.project_idea)),
         now(), e.family,
         case when l.lane = 'NEEDS_CONTACT' then null else e.fchan end,
         case when l.lane = 'NEEDS_CONTACT' then null else e.r_rank end,
         e.fallback, case when e.fchan = 'FORM' then e.form_id end
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
    send_window = excluded.send_window, dims = excluded.dims, built_at = now(), family = excluded.family, route_channel = excluded.route_channel,
    route_rank = excluded.route_rank, fallback_route = excluded.fallback_route, form_id = excluded.form_id
  where q.state <> 'SENT';
  update daily_outreach_queue set state = 'DROPPED', state_at = now(), state_reason = 'No longer meets every gate (' || lower(p_mode) || ' check)'
   where run_date = v_date and state = 'REBUILDING';

  -- 5. Funnel, coverage, gate record and engine health for the day (small: counts only).
  select count(*) into v_today from daily_outreach_queue where run_date = v_date and lane in ('TODAY', 'FORM_READY') and state in ('QUEUED', 'SENT');
  select jsonb_build_object(
           'considered', count(*),
           'screened', count(*) filter (where account_ok and g2 and gfit and g3 and gco and gdnc),
           'researched', count(*) filter (where account_ok and g2 and gfit and g3 and gco and gdnc and g4 and x_dm and x_route and x_prov and x_class),
           'ready', count(*) filter (where ready),
           'ready_unique_companies', (select count(*) from _rk),
           'today', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'TODAY' and state in ('QUEUED', 'SENT')),
           'form_ready', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'FORM_READY' and state in ('QUEUED', 'SENT')),
           'ready_total', v_today, 'today_sent', v_sent_today,
           'reserve', (select count(*) from _lanes where lane = 'RESERVE'),
           'needs_draft', (select count(*) from _lanes where lane = 'NEEDS_DRAFT'),
           'needs_contact', (select count(*) from _lanes where lane = 'NEEDS_CONTACT'),
           'new_accounts_24h', (select count(*) from companies where created_at > now() - interval '24 hours'),
           'new_opportunities_24h', (select count(*) from opportunities where created_at > now() - interval '24 hours'),
           'targets', jsonb_build_object('ready', v_floor, 'ready_range', v_inv->'ready_range', 'reserve', v_res, 'needs_contact', v_nc, 'needs_draft', v_nd)),
         jsonb_build_object('real_account_person', count(*) filter (where not x_person), 'stream', count(*) filter (where not g2),
           'commercial_fit', count(*) filter (where not gfit), 'project_hypothesis', count(*) filter (where not g4),
           'commercial_reason', count(*) filter (where not g3), 'decision_maker', count(*) filter (where not x_dm),
           'contact_route', count(*) filter (where not x_route), 'provenance', count(*) filter (where not x_prov),
           'route_classification', count(*) filter (where not x_class), 'personalised_draft', count(*) filter (where not x_draft),
           'no_dnc', count(*) filter (where not gdnc), 'no_company_conflict', count(*) filter (where not gco),
           'research_current', count(*) filter (where not gcur), 'next_action', count(*) filter (where not g10))
    into v_funnel, v_fail from _e;
  select coalesce(jsonb_object_agg(c.code, jsonb_build_object('label', c.label, 'family', c.family, 'considered', coalesce(x.considered, 0), 'ready', coalesce(x.ready, 0),
                                                              'today', coalesce(t.today, 0))), '{}'::jsonb) into v_cat
    from outreach_categories c
    left join (select category, count(*) considered, count(*) filter (where ready) ready from _e group by category) x on x.category = c.code
    left join (select category, count(*) today from daily_outreach_queue where run_date = v_date and lane in ('TODAY', 'FORM_READY') and state in ('QUEUED', 'SENT') group by category) t on t.category = c.code;
  select k into v_bottleneck from (
    select k, count(*) n from _e e cross join lateral unnest(e.failed) k
     where e.account_ok and e.g2 and e.gfit and e.g3 and e.gco and e.gdnc and not e.ready group by k order by count(*) desc limit 1) b;

  with fl as (
    select f.code, f.label, f.target_min, f.target_max, f.multiplier,
           coalesce(case when (v_inv->'family_cap_overrides'->>f.code) ~ '^[0-9]+$' then (v_inv->'family_cap_overrides'->>f.code)::int end, ceil(v_share * v_floor)::int) cap,
           (select count(*) from daily_outreach_queue q where q.run_date = v_date and q.family = f.code and q.lane in ('TODAY', 'FORM_READY') and q.state in ('QUEUED', 'SENT')) ready,
           (select count(*) from _rk r where r.family = f.code) ready_pool,
           (select count(*) from _rk r where r.family = f.code and not r.in_cap) over_cap,
           (select count(*) from _lanes l join _e e on e.opportunity_id = l.opportunity_id where l.lane = 'RESERVE' and e.family = f.code) reserve,
           (select count(*) from _lanes l join _e e on e.opportunity_id = l.opportunity_id where l.lane = 'NEEDS_DRAFT' and e.family = f.code) needs_draft,
           (select count(*) from _lanes l join _e e on e.opportunity_id = l.opportunity_id where l.lane = 'NEEDS_CONTACT' and e.family = f.code) needs_contact
      from outreach_families f)
  select jsonb_build_object(
    'families', (select jsonb_object_agg(code, jsonb_build_object('label', label, 'ready', ready, 'ready_pool', ready_pool, 'over_cap', over_cap, 'cap', cap,
                   'reserve', reserve, 'needs_draft', needs_draft, 'needs_contact', needs_contact, 'target_min', target_min, 'target_max', target_max,
                   'multiplier', multiplier, 'gap', greatest(target_min - ready, 0))) from fl),
    'families_ready', (select count(*) from fl where ready > 0),
    'min_families', coalesce((v_inv->>'min_families')::int, 6),
    'max_family_share', (select round(max(ready)::numeric / nullif(sum(ready), 0), 3) from fl),
    'cap_note', case when (select max(ready)::numeric / nullif(sum(ready), 0) from fl) > v_share
                     then 'One family is above 25% of READY because other families do not yet have enough send-ready records; the cap is measured against the ' || v_floor || ' target and the overflow waits in Reserve.' end,
    'channels', (select coalesce(jsonb_object_agg(coalesce(route_channel, 'NONE'), n), '{}'::jsonb) from (select route_channel, count(*) n from daily_outreach_queue
                  where run_date = v_date and lane in ('TODAY', 'FORM_READY') and state in ('QUEUED', 'SENT') group by 1) x),
    'routes_ready', (select coalesce(jsonb_object_agg(coalesce(route_canonical, 'NONE'), n), '{}'::jsonb) from (select route_canonical, count(*) n from daily_outreach_queue
                  where run_date = v_date and lane in ('TODAY', 'FORM_READY') and state in ('QUEUED', 'SENT') group by 1) x),
    'routes_reserve', (select coalesce(jsonb_object_agg(coalesce(route_canonical, 'NONE'), n), '{}'::jsonb) from (select route_canonical, count(*) n from daily_outreach_queue
                  where run_date = v_date and lane = 'RESERVE' and state = 'QUEUED' group by 1) x),
    'forms', (select jsonb_build_object('qualified', count(*) filter (where status = 'QUALIFIED'), 'prepared', count(*) filter (where status = 'PREPARED'),
                       'approved', count(*) filter (where status = 'APPROVED'), 'submitted_7d', count(*) filter (where status = 'SUBMITTED' and submitted_at > now() - interval '7 days'),
                       'rejected', count(*) filter (where status = 'REJECTED')) from contact_forms),
    'slots', v_slots, 'marked_forms_sent', v_marked_f) into v_engine;

  insert into daily_outreach_runs as r (run_date, morning_at, built_at, mode, runs, duration_ms, funnel, by_category, gate_failures, shortfall, bottleneck, engine)
  values (v_date, case when p_mode = 'MORNING' then now() end, now(), p_mode, 1, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int,
          v_funnel, v_cat, v_fail, greatest(v_floor - v_today, 0), v_bottleneck, v_engine)
  on conflict (run_date) do update set morning_at = coalesce(case when p_mode = 'MORNING' then now() end, r.morning_at), built_at = now(), mode = p_mode,
    runs = r.runs + 1, duration_ms = excluded.duration_ms, funnel = excluded.funnel, by_category = excluded.by_category,
    gate_failures = excluded.gate_failures, shortfall = excluded.shortfall, bottleneck = excluded.bottleneck,
    engine = coalesce(r.engine, '{}'::jsonb) || excluded.engine;

  return jsonb_build_object('ok', true, 'date', v_date, 'mode', p_mode, 'marked_sent', v_marked + v_marked_f, 'funnel', v_funnel, 'gate_failures', v_fail,
                            'shortfall', greatest(v_floor - v_today, 0), 'bottleneck', v_bottleneck, 'families_ready', v_engine->'families_ready',
                            'max_family_share', v_engine->'max_family_share',
                            'duration_ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
end $$;
revoke all on function public.outreach_queue_build(text) from public, anon, authenticated;
revoke all on function public.route_rank_of(text, text, text) from public, anon;
revoke all on function public.form_type_label(text) from public, anon;

-- 13. HQ reads v2: lanes add FORM_READY and HISTORY, the best route and its fallback on every card; one form on demand.
create or replace function public.hq_outreach_lanes(p_lane text default 'TODAY', p_limit integer default 25, p_offset integer default 0) returns jsonb
 language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); v_today date := (now() at time zone 'Africa/Cairo')::date; v_date date; v_run daily_outreach_runs%rowtype;
        v_items jsonb := '[]'::jsonb; v_total int := 0; v_counts jsonb; v_extra jsonb := '{}'::jsonb; v_learn jsonb; v_t jsonb;
begin
  p_lane := upper(coalesce(p_lane, 'TODAY')); p_limit := least(greatest(coalesce(p_limit, 25), 1), 50); p_offset := greatest(coalesce(p_offset, 0), 0);
  if p_lane not in ('ACT_NOW', 'TODAY', 'FORM_READY', 'RESERVE', 'NEEDS_CONTACT', 'FOLLOW_UPS', 'REPLIES', 'HISTORY') then
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_LANE');
  end if;
  select max(run_date) into v_date from daily_outreach_runs where run_date <= v_today;
  select * into v_run from daily_outreach_runs where run_date = v_date;

  select jsonb_build_object(
    'act_now', outreach_act_now_count(),
    'today', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'TODAY' and state = 'QUEUED'),
    'today_sent', (select count(*) from daily_outreach_queue where run_date = v_date and lane in ('TODAY', 'FORM_READY') and state = 'SENT'),
    'form_ready', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'FORM_READY' and state = 'QUEUED'),
    'reserve', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'RESERVE' and state = 'QUEUED'),
    'needs_contact', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'NEEDS_CONTACT' and state = 'QUEUED'),
    'needs_draft', (select count(*) from daily_outreach_queue where run_date = v_date and lane = 'NEEDS_DRAFT' and state = 'QUEUED'),
    'follow_ups', (select count(*) from opportunities where status in ('CONTACTED', 'FOLLOW_UP') and next_action_due is not null and next_action_due <= current_date + 2),
    'replies', (select count(*) from gmail_history_threads g where g.relevant and g.last_direction = 'INBOUND' and g.last_inbound_at > now() - interval '14 days'
                 and coalesce(g.hq_status, '') <> 'DISMISSED'),
    'history', (select count(*) from outreach_learning l where l.sent_at > now() - interval '30 days')
                + (select count(*) from contact_forms f where f.status = 'SUBMITTED' and f.submitted_at > now() - interval '30 days')) into v_counts;

  if p_lane in ('TODAY', 'FORM_READY', 'RESERVE', 'NEEDS_CONTACT') then
    select count(*) into v_total from daily_outreach_queue q where q.run_date = v_date and q.lane = p_lane and q.state in ('QUEUED', 'SENT');
    select coalesce(jsonb_agg(j order by o1, o2, o3), '[]'::jsonb) into v_items from (
      select (q.state <> 'QUEUED') o1, (not coalesce(q.sendable_today, false) and coalesce(q.route_channel, 'EMAIL') = 'EMAIL') o2, q.rank o3,
             jsonb_build_object('id', q.id, 'rank', q.rank, 'state', q.state, 'opportunity_id', q.opportunity_id, 'company_id', q.company_id,
               'person', q.person, 'position', q.position, 'company', q.company, 'stream', q.stream, 'stream_label', st.label,
               'category', q.category, 'category_label', oc.label, 'family', q.family, 'family_label', fa.label, 'multiplier', fa.multiplier,
               'market', q.market, 'project_idea', left(q.project_idea, 280), 'why_now', left(q.why_now, 280),
               'route_channel', q.route_channel, 'route_rank', q.route_rank, 'fallback_route', q.fallback_route,
               'route_email', q.route_email, 'route_canonical', q.route_canonical, 'route_label', q.route_label, 'route_source_type', q.route_source_type,
               'route_source_url', q.route_source_url, 'confidence', q.confidence, 'draft_subject', q.draft_subject, 'draft_excerpt', q.draft_excerpt,
               'draft_status', q.draft_status, 'has_gmail_draft', q.gmail_draft_id is not null, 'task_id', q.task_id, 'next_action', left(q.next_action, 200),
               'form', case when q.form_id is not null then jsonb_build_object('id', f.id, 'url', f.url, 'type', f.form_type, 'type_label', form_type_label(f.form_type),
                              'team', f.target_team, 'status', f.status, 'required', to_jsonb(f.required_fields), 'max_chars', f.max_message_chars,
                              'captcha', f.captcha, 'verified_at', f.verified_at) end,
               'next_step', case q.draft_status
                              when 'FORM_PREPARED' then 'Review the prepared form; approving lets the agent submit it once and log the confirmation'
                              when 'FORM_APPROVED' then 'Approved: the agent submits this form and records the confirmation'
                              when 'FORM_DRAFTING' then 'Form copy is being prepared'
                              when 'GMAIL_DRAFT' then 'Send the unsent Gmail draft yourself, in a send window'
                              when 'APPROVED_PENDING_GMAIL' then 'Approved: the unsent Gmail draft is being created'
                              when 'APPROVED' then 'Approved: create the unsent Gmail draft from the approval desk'
                              when 'READY_FOR_REVIEW' then 'Review the draft; approving creates an unsent Gmail draft'
                              when 'NEEDS_EDIT' then 'Draft failed the quality gate: it is rewritten tonight'
                              when 'PLANNED_TONIGHT' then 'W18 drafts this account tonight'
                              else case when q.lane = 'NEEDS_CONTACT' then 'The agents are finding the right person and a sourced professional route (website, forms, Instagram, Clay)' else 'Prepare a personalised draft' end end,
               'failed', to_jsonb(q.failed), 'score', q.score, 'sendable_today', q.sendable_today, 'send_window', q.send_window) j
        from daily_outreach_queue q left join commercial_streams st on st.code = q.stream left join outreach_categories oc on oc.code = q.category
        left join outreach_families fa on fa.code = q.family left join contact_forms f on f.id = q.form_id
       where q.run_date = v_date and q.lane = p_lane and q.state in ('QUEUED', 'SENT')
       order by (q.state <> 'QUEUED'), (not coalesce(q.sendable_today, false) and coalesce(q.route_channel, 'EMAIL') = 'EMAIL'), q.rank limit p_limit offset p_offset) s;
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
  elsif p_lane = 'HISTORY' then
    v_total := coalesce((v_counts->>'history')::int, 0);
    select coalesce(jsonb_agg(j order by t desc), '[]'::jsonb) into v_items from (
      select x.t, x.j from (
        select l.sent_at t, jsonb_build_object('kind', 'FIRST_TOUCH', 'channel', coalesce(l.route_channel, 'EMAIL'), 'at', l.sent_at, 'opportunity_id', l.opportunity_id,
                 'company_id', l.company_id, 'company', c.name, 'person', nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), ''),
                 'route_type', l.route_type, 'category_label', oc.label, 'cohort', l.cohort, 'bounced', l.bounced, 'replied', l.replied, 'positive', l.positive,
                 'meeting', l.meeting, 'status', o.status) j
          from outreach_learning l left join companies c on c.id = l.company_id left join contacts k on k.id = l.contact_id
          left join outreach_categories oc on oc.code = l.category left join opportunities o on o.id = l.opportunity_id
         where l.sent_at > now() - interval '30 days'
        union all
        select f.submitted_at, jsonb_build_object('kind', 'FORM', 'channel', 'FORM', 'at', f.submitted_at, 'opportunity_id', f.opportunity_id, 'company_id', f.company_id,
                 'company', c.name, 'person', coalesce(f.target_team, 'Enquiries') || ' team', 'route_type', form_type_label(f.form_type), 'url', f.url,
                 'reference', f.reference, 'follow_up_on', f.next_follow_up_on, 'status', o.status,
                 'replied', exists (select 1 from interactions i where i.company_id = f.company_id and i.direction = 'INBOUND' and i.occurred_at > f.submitted_at)) j
          from contact_forms f left join companies c on c.id = f.company_id left join opportunities o on o.id = f.opportunity_id
         where f.status = 'SUBMITTED' and f.submitted_at > now() - interval '30 days') x
       order by x.t desc limit p_limit offset p_offset) s;
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
           'engine', jsonb_build_object('families', v_run.engine->'families', 'families_ready', v_run.engine->'families_ready',
                                        'max_family_share', v_run.engine->'max_family_share', 'cap_note', v_run.engine->'cap_note',
                                        'channels', v_run.engine->'channels', 'routes_ready', v_run.engine->'routes_ready', 'self_correct', v_run.engine->'self_correct'),
           'learning', v_learn, 'items', v_items, 'total', v_total, 'limit', p_limit, 'offset', p_offset, 'extra', v_extra);
end $$;

-- One prepared draft (email or form) on demand.
create or replace function public.hq_outreach_draft(p_id uuid) returns jsonb
 language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); q daily_outreach_queue%rowtype; v_subject text; v_body text; v_msg text;
begin
  select * into q from daily_outreach_queue where id = p_id;
  if q.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if q.form_id is not null then
    return hq_form_detail(q.form_id) || jsonb_build_object('queue_id', q.id, 'kind', 'FORM', 'person', q.person, 'route_label', q.route_label);
  end if;
  select e.subject, e.body, e.gmail_message_id into v_subject, v_body, v_msg from outbound_emails e where e.id = q.outbound_email_id;
  if v_body is null then select oc.subject, oc.draft into v_subject, v_body from outreach_candidates oc where oc.id = q.candidate_id; end if;
  return jsonb_build_object('ok', true, 'kind', 'EMAIL', 'id', q.id, 'company', q.company, 'person', q.person, 'to', q.route_email, 'route_label', q.route_label,
           'route_source_type', q.route_source_type, 'route_source_url', q.route_source_url, 'subject', v_subject, 'body', v_body,
           'draft_status', q.draft_status, 'task_id', q.task_id, 'fallback_route', q.fallback_route,
           'gmail_draft_url', case when v_msg is not null then gmail_draft_url(v_msg) end,
           'rule', 'Unsent. Approving in the desk creates an unsent Gmail draft; Adam sends it himself.');
end $$;

-- 14. Self-correction: when READY is under the floor of the range, find the exact bottleneck and raise only that stage, within bounds.
--     Knobs: draft_repair.per_night (max_per_night), route_research.batch_per_run (max_batch), focus_families. It never buys anything and
--     never runs workflows more often; a top-up or billing change is recorded as a recommendation for Adam.
create or replace function public.engine_self_correct() returns jsonb
 language plpgsql security definer set search_path to 'public'
as $$
declare v_cfg jsonb; v_inv jsonb; r daily_outreach_runs%rowtype; v_ready int; v_min int; v_target int; v_stage text; v_actions jsonb := '[]'::jsonb;
        v_recs jsonb := '[]'::jsonb; v_rep int; v_rep_max int; v_rr int; v_rr_max int; v_focus jsonb; v_cred jsonb; v_rl numeric; v_out jsonb; v_hist jsonb;
begin
  select value into v_cfg from system_config where key = 'acquisition_engine';
  v_inv := coalesce(v_cfg->'inventory', '{}'::jsonb);
  select * into r from daily_outreach_runs order by run_date desc limit 1;
  if r.run_date is null then return jsonb_build_object('ok', false, 'reason', 'NO_RUN'); end if;
  v_ready := coalesce((r.funnel->>'ready_total')::int, (r.funnel->>'today')::int, 0);
  v_min := coalesce((v_inv->'ready_range'->>0)::int, 60);
  v_target := coalesce((v_inv->>'ready_target')::int, 75);
  v_rep := coalesce((v_cfg->'draft_repair'->>'per_night')::int, 30); v_rep_max := coalesce((v_cfg->'draft_repair'->>'max_per_night')::int, 50);
  v_rr := coalesce((v_cfg->'route_research'->>'batch_per_run')::int, 30); v_rr_max := coalesce((v_cfg->'route_research'->>'max_batch')::int, 60);
  v_cred := research_credit_budget();
  -- Share of last night's W18 drafts lost to the free-tier rate limit.
  select round(count(*) filter (where rate_limited)::numeric / nullif(count(*), 0), 2) into v_rl
    from outreach_candidates where not dry_run and created_at > now() - interval '36 hours' and status <> 'PLANNED';
  select coalesce(jsonb_agg(k order by (v->>'gap')::int desc), '[]'::jsonb) into v_focus
    from jsonb_each(coalesce(r.engine->'families', '{}'::jsonb)) x(k, v) where (v->>'gap')::int > 0;

  v_stage := case
    when v_ready >= v_min then 'OK'
    when r.bottleneck = 'personalised_draft' then 'DRAFTS'
    when r.bottleneck in ('contact_route', 'provenance', 'route_classification') then 'ROUTES'
    when r.bottleneck in ('decision_maker', 'real_account_person') then 'PEOPLE'
    when r.bottleneck in ('commercial_fit', 'commercial_reason', 'project_hypothesis', 'research_current') then 'QUALIFIED_ACCOUNTS'
    else 'OTHER' end;

  if v_stage = 'OK' then
    -- Recovered: step the raised knobs back towards their defaults once READY reaches the target.
    if v_ready >= v_target then
      v_rep := greatest(v_rep - 10, 30); v_rr := greatest(v_rr - 10, 30);
      v_actions := v_actions || jsonb_build_object('stage', 'OK', 'action', 'READY at target: research and repair stepped back to defaults');
    end if;
  else
    if v_stage = 'DRAFTS' then
      if v_rep < v_rep_max then v_rep := least(v_rep + 10, v_rep_max);
        v_actions := v_actions || jsonb_build_object('stage', v_stage, 'action', 'Failed-draft repair raised to ' || v_rep || ' a night'); end if;
      if coalesce(v_rl, 0) >= 0.3 then
        v_recs := v_recs || jsonb_build_object('decision', 'GEMINI_BILLING', 'why', round(v_rl * 100) || '% of last night''s drafts hit the Gemini free-tier rate limit',
                  'recommendation', 'Enable Gemini billing inside the approved USD 10 monthly AI ceiling; drafting capacity roughly doubles.');
      end if;
    end if;
    if v_stage in ('ROUTES', 'PEOPLE') or coalesce((r.funnel->>'needs_contact')::int, 0) >= coalesce((v_inv->>'needs_contact_target')::int, 150) then
      if v_rr < v_rr_max then v_rr := least(v_rr + 10, v_rr_max);
        v_actions := v_actions || jsonb_build_object('stage', coalesce(nullif(v_stage, 'DRAFTS'), 'ROUTES'), 'action', 'Website route and form research raised to ' || v_rr || ' accounts a run'); end if;
    end if;
    if v_stage = 'QUALIFIED_ACCOUNTS' then
      v_actions := v_actions || jsonb_build_object('stage', v_stage, 'action', 'Discovery focus set to the families furthest from target: ' || coalesce((select string_agg(x, ', ') from jsonb_array_elements_text(v_focus) x), 'none'));
    end if;
    if coalesce((r.engine->>'families_ready')::int, 0) < coalesce((v_inv->>'min_families')::int, 6) then
      v_actions := v_actions || jsonb_build_object('stage', 'PORTFOLIO', 'action', 'Route research and drafting prioritise ' || coalesce((select string_agg(x, ', ') from jsonb_array_elements_text(v_focus) x), 'all families'));
    end if;
  end if;
  if v_cred->'serper'->>'status' in ('CRITICAL', 'TIGHT') then
    v_recs := v_recs || jsonb_build_object('decision', 'SERPER_TOP_UP', 'why', 'Serper runway ' || coalesce(v_cred->'serper'->>'runway_days', '?') || ' days at the current burn',
              'recommendation', coalesce(v_cred->'serper'->>'recommendation', 'Top up Serper'));
  end if;

  update system_config set value = value
      || jsonb_build_object('draft_repair', coalesce(value->'draft_repair', '{}'::jsonb) || jsonb_build_object('per_night', v_rep))
      || jsonb_build_object('route_research', coalesce(value->'route_research', '{}'::jsonb) || jsonb_build_object('batch_per_run', v_rr))
      || jsonb_build_object('focus_families', v_focus), updated_at = now()
   where key = 'acquisition_engine';
  v_out := jsonb_build_object('at', now(), 'run_date', r.run_date, 'ready', v_ready, 'floor', v_min, 'stage', v_stage, 'bottleneck', r.bottleneck,
                              'actions', v_actions, 'recommendations', v_recs, 'knobs', jsonb_build_object('draft_repair_per_night', v_rep, 'route_research_batch', v_rr),
                              'focus_families', v_focus, 'rate_limited_share', v_rl);
  select coalesce(value->'history', '[]'::jsonb) into v_hist from system_config where key = 'engine_self_correct';
  v_hist := (select coalesce(jsonb_agg(h), '[]'::jsonb) from (select h from jsonb_array_elements(coalesce(v_hist, '[]'::jsonb) || jsonb_build_array(v_out - 'history')) h offset greatest(jsonb_array_length(coalesce(v_hist, '[]'::jsonb)) + 1 - 14, 0)) z);
  insert into system_config (key, value, note) values ('engine_self_correct', v_out || jsonb_build_object('history', v_hist),
    'Daily self-correction (engine_self_correct, after the morning build). Bounded knobs only; recommendations need Adam.')
  on conflict (key) do update set value = excluded.value, updated_at = now();
  update daily_outreach_runs set engine = coalesce(engine, '{}'::jsonb) || jsonb_build_object('self_correct', v_out) where run_date = r.run_date;
  return v_out;
end $$;

-- 15. Daily engine health (admin read for HQ and the morning report): inventory, routes found, forms, failures, credits, mix, Director
--     (family) accountability, learning by source, cost per outcome, top 10.
create or replace function public.hq_engine_health() returns jsonb
 language plpgsql stable security definer set search_path to 'public' set statement_timeout to '20s'
as $$
declare v_admin text := hq_admin_email(); r daily_outreach_runs%rowtype; v_cred jsonb; v_fam jsonb; v_learn jsonb; v_routes jsonb; v_top jsonb; v_cost jsonb;
        v_usd numeric; v_routes30 int; v_ready int; v_pos int; v_meet int; v_serper30 numeric;
begin
  select * into r from daily_outreach_runs order by run_date desc limit 1;
  v_cred := research_credit_budget();
  select jsonb_build_object(
      'named_emails', count(*) filter (where k.route_type = 'PERSON_EMAIL' and coalesce(k.email_source_type, '') not in ('CLAY', 'INSTAGRAM')),
      'instagram', count(*) filter (where k.email_source_type = 'INSTAGRAM'),
      'clay', count(*) filter (where k.email_source_type = 'CLAY'),
      'inboxes', count(*) filter (where k.route_type = 'COMPANY_INBOX' and coalesce(k.email_source_type, '') not in ('INSTAGRAM')),
      'total', count(*))
    into v_routes from contacts k where k.email is not null and k.email_found_at > now() - interval '24 hours';
  -- Director (family) accountability on the live cold book: accounts, people, usable routes, forms, ready; outcomes from the clean ledger.
  with book as (
    select o.id opp, o.company_id, o.contact_id, coalesce(oc.family, 'HOSPITALITY_PRIVATE') fam, o.status, c.universe_status
      from opportunities o join companies c on c.id = o.company_id
      left join outreach_categories oc on oc.code = outreach_category(o.primary_stream, c.company_type)
     where c.merged_into is null and o.status not in ('LOST', 'ARCHIVED')),
  outc as (
    select coalesce(oc.family, 'HOSPITALITY_PRIVATE') fam, count(*) sends, count(*) filter (where l.replied) replies, count(*) filter (where l.positive) positive,
           count(*) filter (where l.meeting) meetings, count(*) filter (where l.brief) briefs, count(*) filter (where l.proposal) proposals, count(*) filter (where l.won) wins
      from outreach_learning l left join outreach_categories oc on oc.code = l.category where l.cohort = 'CLEAN' group by 1)
  select jsonb_object_agg(f.code, jsonb_build_object('label', f.label, 'multiplier', f.multiplier,
           'qualified_accounts', (select count(distinct b.company_id) from book b where b.fam = f.code and b.universe_status = 'QUALIFIED' and b.status in ('NEW', 'RESEARCHING', 'READY')),
           'named_people', (select count(distinct b.contact_id) from book b join contacts k on k.id = b.contact_id where b.fam = f.code and k.first_name is not null and b.status in ('NEW', 'RESEARCHING', 'READY')),
           'usable_routes', (select count(*) from book b join hq_route_cache h on h.opportunity_id = b.opp and h.usable where b.fam = f.code and b.status in ('NEW', 'RESEARCHING', 'READY')),
           'forms', (select count(*) from contact_forms cf where cf.status in ('QUALIFIED', 'PREPARED', 'APPROVED') and cf.company_id in (select b.company_id from book b where b.fam = f.code)),
           'ready', coalesce((r.engine->'families'->f.code->>'ready')::int, 0), 'reserve', coalesce((r.engine->'families'->f.code->>'reserve')::int, 0),
           'needs_contact', coalesce((r.engine->'families'->f.code->>'needs_contact')::int, 0), 'target_min', f.target_min, 'target_max', f.target_max,
           'live_conversations', (select count(*) from book b where b.fam = f.code and b.status in ('INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION')),
           'sends', coalesce(o.sends, 0), 'positive_replies', coalesce(o.positive, 0), 'meetings', coalesce(o.meetings, 0), 'briefs', coalesce(o.briefs, 0),
           'proposals', coalesce(o.proposals, 0), 'wins', coalesce(o.wins, 0)) order by f.sort)
    into v_fam from outreach_families f left join outc o on o.fam = f.code;
  select coalesce(jsonb_object_agg(src, jsonb_build_object('sends', n, 'replies', rep, 'positive', pos, 'meetings', mtg, 'reply_rate', round(rep::numeric / nullif(n, 0), 3))), '{}'::jsonb)
    into v_learn from (select coalesce(source, 'UNKNOWN') src, count(*) n, count(*) filter (where replied) rep, count(*) filter (where positive) pos, count(*) filter (where meeting) mtg
                         from outreach_learning where cohort = 'CLEAN' group by 1) x;
  select coalesce(jsonb_agg(j order by o1, o2), '[]'::jsonb) into v_top from (
    select q.rank o1, q.lane o2, jsonb_build_object('rank', q.rank, 'lane', q.lane, 'company', q.company, 'person', q.person, 'family', fa.label,
             'channel', q.route_channel, 'route', q.route_label, 'project_idea', left(q.project_idea, 160), 'opportunity_id', q.opportunity_id) j
      from daily_outreach_queue q left join outreach_families fa on fa.code = q.family
     where q.run_date = r.run_date and q.lane in ('TODAY', 'FORM_READY') and q.state = 'QUEUED' order by q.rank, q.lane limit 10) s;
  -- Cost per outcome (30 days): logged research spend plus Serper credits at the pack price (USD 50 per 50,000).
  v_usd := coalesce((select sum(usd) from research_credit_ledger where at > now() - interval '30 days'), 0);
  v_serper30 := coalesce((v_cred->'serper'->>'burn_per_day')::numeric, 0) * 30 * 0.001;
  v_routes30 := (select count(*) from contacts where email is not null and email_found_at > now() - interval '30 days')
              + (select count(*) from contact_forms where status in ('QUALIFIED', 'PREPARED', 'APPROVED', 'SUBMITTED') and discovered_at > now() - interval '30 days');
  v_ready := coalesce((r.funnel->>'ready_total')::int, 0);
  select count(*) filter (where positive), count(*) filter (where meeting) into v_pos, v_meet from outreach_learning where cohort = 'CLEAN' and sent_at > now() - interval '30 days';
  v_cost := jsonb_build_object('usd_30d_est', round(v_usd + v_serper30, 2), 'usable_routes_30d', v_routes30,
              'per_usable_route', round((v_usd + v_serper30) / nullif(v_routes30, 0), 3), 'per_ready', round((v_usd + v_serper30) / 30 / nullif(v_ready, 0), 3),
              'per_positive_reply', round((v_usd + v_serper30) / nullif(v_pos, 0), 2), 'per_meeting', round((v_usd + v_serper30) / nullif(v_meet, 0), 2),
              'basis', 'Serper at USD 0.001 per credit plus logged Gemini, Clay and Firecrawl spend; AI drafting cost is in ai_budget');
  return jsonb_build_object('ok', true, 'date', r.run_date, 'built_at', r.built_at,
    'inventory', jsonb_build_object('ready', v_ready, 'email_ready', r.funnel->'today', 'form_ready', r.funnel->'form_ready', 'reserve', r.funnel->'reserve',
                                    'needs_draft', r.funnel->'needs_draft', 'needs_contact', r.funnel->'needs_contact', 'targets', r.funnel->'targets', 'shortfall', r.shortfall,
                                    'bottleneck', r.bottleneck),
    'routes_found_24h', v_routes,
    'forms', r.engine->'forms', 'forms_found_24h', (select count(*) from contact_forms where discovered_at > now() - interval '24 hours'),
    'route_research_24h', (select jsonb_build_object('accounts', count(*), 'route_found', count(*) filter (where outcome = 'ROUTE_FOUND'),
                             'no_route', count(*) filter (where outcome = 'NO_ROUTE'), 'fetch_failed', count(*) filter (where outcome = 'FETCH_FAILED'))
                             from route_research_log where at > now() - interval '24 hours'),
    'draft_repair', (select value from system_config where key = 'draft_repair_last'),
    'self_correct', (select value - 'history' from system_config where key = 'engine_self_correct'),
    'credits', v_cred, 'mix', jsonb_build_object('families', r.engine->'families', 'families_ready', r.engine->'families_ready',
                                                  'max_family_share', r.engine->'max_family_share', 'cap_note', r.engine->'cap_note',
                                                  'channels', r.engine->'channels', 'routes_ready', r.engine->'routes_ready'),
    'directors', v_fam, 'learning_by_source', v_learn, 'cost', v_cost, 'top10', v_top);
end $$;

-- 16. Discovery matrix: the next queries for the families furthest from target, within the Serper daily allowance; results are recorded.
create or replace function public.discovery_next_batch(p_limit integer default null) returns jsonb
 language sql stable security definer set search_path to 'public'
as $$
  with cfg as (select value v from system_config where key = 'acquisition_engine'),
  cred as (select research_credit_budget() c),
  lim as (select least(coalesce(p_limit, ((select v from cfg)->'discovery'->>'per_day')::int, 20),
                       greatest(coalesce(((select c from cred)->'serper'->>'daily_allowance')::int, 0), 0), 60) n),
  gap as (select k fam, coalesce((v->>'gap')::int, 0) g from daily_outreach_runs r, jsonb_each(coalesce(r.engine->'families', '{}'::jsonb)) x(k, v)
           where r.run_date = (select max(run_date) from daily_outreach_runs))
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'query', q.query, 'provider', q.provider, 'family', q.family, 'stream', q.stream, 'market', q.market,
                                               'buyer_type', q.buyer_type, 'signal', q.signal) order by q.ord), '[]'::jsonb)
    from (select d.*, row_number() over (order by coalesce(g.g, 0) desc, d.last_run_at nulls first, d.priority desc, d.id) ord
            from discovery_queries d left join gap g on g.fam = d.family
           where d.active and (d.last_run_at is null or d.last_run_at < now() - interval '21 days')) q
   where q.ord <= (select n from lim)
$$;

create or replace function public.discovery_record(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public'
as $$
declare v_id bigint := nullif(p->>'id', '')::bigint;
begin
  update discovery_queries set last_run_at = now(), runs = runs + 1, results = results + coalesce((p->>'results')::int, 0),
         new_companies = new_companies + coalesce((p->>'new_companies')::int, 0), qualified = qualified + coalesce((p->>'qualified')::int, 0)
   where id = v_id;
  insert into research_credit_ledger (provider, credits, usd, purpose, outcome, detail, actor)
  values (upper(coalesce(nullif(p->>'provider', ''), 'SERPER')), coalesce((p->>'credits')::numeric, 1), nullif(p->>'usd', '')::numeric, 'DISCOVERY',
          case when coalesce((p->>'new_companies')::int, 0) > 0 then 'NEW_ACCOUNTS' else 'NO_NEW' end, left(coalesce(p->>'query', v_id::text), 200),
          coalesce(nullif(p->>'actor', ''), 'engine'));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Clay spend is logged once per enriched person (never twice on the same unresolved person within 30 days).
create or replace function public.clay_spend_record(p_contact uuid, p_credits numeric, p_outcome text, p_detail text default null) returns jsonb
 language plpgsql security definer set search_path to 'public'
as $$
begin
  if exists (select 1 from research_credit_ledger where provider = 'CLAY' and contact_id = p_contact and at > now() - interval '30 days' and outcome <> 'FOUND') then
    return jsonb_build_object('ok', false, 'reason', 'ALREADY_TRIED_30D');
  end if;
  insert into research_credit_ledger (provider, credits, purpose, company_id, contact_id, outcome, detail, actor)
  values ('CLAY', coalesce(p_credits, 0), 'WORK_EMAIL', (select company_id from contacts where id = p_contact), p_contact, upper(coalesce(p_outcome, 'NOT_FOUND')), left(p_detail, 200), 'engine');
  return jsonb_build_object('ok', true);
end $$;

update public.system_config set value = value || jsonb_build_object('discovery', jsonb_build_object('per_day', 20, 'max_per_day', 60, 'revisit_days', 21,
  'rule', 'Matrix queries by family x buyer type x market x signal; families furthest from target first; never above the Serper daily allowance.'))
 where key = 'acquisition_engine' and not (value ? 'discovery');

-- 17. Grants: three admin reads/writes for HQ; everything else internal (cron, W27 and the daily operating check only).
revoke all on function public.hq_outreach_lanes(text, integer, integer) from public, anon;
revoke all on function public.hq_outreach_draft(uuid) from public, anon;
revoke all on function public.hq_engine_health() from public, anon;
revoke all on function public.hq_form_detail(uuid) from public, anon;
revoke all on function public.hq_form_action(uuid, text, text) from public, anon;
grant execute on function public.hq_outreach_lanes(text, integer, integer) to authenticated;
grant execute on function public.hq_outreach_draft(uuid) to authenticated;
grant execute on function public.hq_engine_health() to authenticated;
grant execute on function public.hq_form_detail(uuid) to authenticated;
grant execute on function public.hq_form_action(uuid, text, text) to authenticated;
revoke all on function public.engine_self_correct() from public, anon, authenticated;
revoke all on function public.discovery_next_batch(integer) from public, anon, authenticated;
revoke all on function public.discovery_record(jsonb) from public, anon, authenticated;
revoke all on function public.clay_spend_record(uuid, numeric, text, text) from public, anon, authenticated;
revoke all on function public.route_research_next_batch(integer) from public, anon, authenticated;
revoke all on function public.route_research_ingest(jsonb) from public, anon, authenticated;
revoke all on function public.form_message_quality(text, text, integer, text) from public, anon, authenticated;
revoke all on function public.form_draft_next_batch(integer) from public, anon, authenticated;
revoke all on function public.form_prepare_save(jsonb) from public, anon, authenticated;
revoke all on function public.form_submission_record(uuid, boolean, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.outreach_draft_repair(integer) from public, anon, authenticated;
revoke all on function public.research_credit_budget() from public, anon, authenticated;
revoke all on function public.form_type_classify(text, text) from public, anon, authenticated;

-- 18. Schedule (UTC; Cairo UTC+2 in winter). 20:40 Cairo failed-draft repair, before W18's nightly drafting (21:00-23:30 Cairo);
--     05:40 Cairo self-correction, after the 05:30 morning build. W27 (n8n) runs route and form research overnight and at midday.
select cron.schedule('outreach-draft-repair', '40 18 * * 0-5', $c$select public.outreach_draft_repair()$c$);
select cron.schedule('engine-self-correct', '40 3 * * 0-5', $c$select public.engine_self_correct()$c$);
