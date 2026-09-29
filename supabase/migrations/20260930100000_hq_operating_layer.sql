-- NOYA HQ — commercial operating layer (30 Sep 2026).
-- Additive and backward compatible. Nothing existing is renamed or removed.
--
--  Classification (deterministic, no AI):
--    hq_vertical()      one of PRIVATE_UHNW, CORPORATE, BRAND_PRODUCTION, HOSPITALITY,
--                       TRAVEL_CONCIERGE, WEDDINGS_EVENTS, SPORTS_TALENT, OTHER
--                       (companies.vertical_override wins when Adam sets it)
--    hq_market()        EGYPT, EUROPE, GCC, NORTH_AMERICA, REST_OF_WORLD, GLOBAL, UNKNOWN
--  Relationship memory:  relationship_notes (how we met, referral, promise, prior project, note)
--                        touchpoints are recorded as interactions (MEETING, LINKEDIN, PHONE…)
--  LinkedIn:             linkedin_connections — filled ONLY from Adam's own LinkedIn data export
--                        (Connections.csv). No scraping, no password, no cookies.
--  Drafting:             message_drafts — HQ requests a draft; workflow 14 writes it (Gemini
--                        Flash-Lite → GPT-5 mini → deterministic template). Nothing is ever sent.
--  Finance:              revenue gains invoice_status / due_at / notes / source; revenue_payments
--                        is the payment ledger (collected = sum of payments, never an edited total).
--  Costs:                system_services = dependency register + cost centre (UNKNOWN stays UNKNOWN).
--  Every HQ write is admin-checked and audited in approval_audit.

-- ---------------------------------------------------------------- classification
create or replace function public.hq_vertical(p_company_type text, p_opportunity_type text, p_sector text default null)
returns text language sql immutable as $$
  select case
    when x ~* '(SPORT|ATHLET|FOOTBALL|TALENT|CREATOR|INFLUENCER|CELEBRITY|PUBLIC_FIGURE)' then 'SPORTS_TALENT'
    when x ~* 'WEDDING' or x ~* '(EVENT_AGENCY|EVENT AGENCY|EVENT PLANNING|EVENT MANAGEMENT|EVENT SERVICES|EVENT SUPPLIER|CELEBRATION)' then 'WEDDINGS_EVENTS'
    when x ~* '(FAMILY.OFFICE|PRIVATE.OFFICE|PRIVATE_CLIENT|PRIVATE CLIENT|UHNW|WEALTH|PRIVATE_BANK|PRIVATE BANK)' then 'PRIVATE_UHNW'
    when x ~* '(HOTEL|RESORT|VILLA|HOSPITALITY|RESTAURANT)' then 'HOSPITALITY'
    when x ~* '(CONCIERGE|TRAVEL|DMC|DESTINATION_PARTNER|MEMBER|CLUB|AVIATION|AIRLINE|EXPEDITION|TOUR|YACHT)' then 'TRAVEL_CONCIERGE'
    when x ~* '(BRAND|PRODUCTION|FASHION|BEAUTY|COSMETIC|AUTOMOTIVE|PR_|PR AGENCY|MARKETING|CREATIVE|RETAIL|CAMPAIGN|SHOOT|MEDIA)' then 'BRAND_PRODUCTION'
    when x ~* '(LAW|LEGAL|CONSULT|PROFESSIONAL|CORPORATE|INVEST|BANK|FINANCIAL|INSURANCE|EXECUTIVE)' then 'CORPORATE'
    else 'OTHER'
  end
  from (select coalesce(p_company_type, '') || ' ' || coalesce(p_opportunity_type, '') || ' ' || coalesce(p_sector, '') as x) s
$$;

create or replace function public.hq_market(p text)
returns text language sql immutable as $$
  select case
    when coalesce(btrim(p), '') = '' then 'UNKNOWN'
    when p ~* 'egypt|cairo|gouna|red sea|luxor|aswan|nile|sharm|hurghada|alexandria|north coast' then 'EGYPT'
    when p ~* '(^|[^a-z])(uae|u\.a\.e)([^a-z]|$)|emirates|dubai|abu dhabi|saudi|ksa|riyadh|jeddah|qatar|doha|kuwait|bahrain|oman|muscat' then 'GCC'
    when p ~* 'united kingdom|(^|[^a-z])uk([^a-z]|$)|england|london|scotland|france|paris|monaco|switzerland|geneva|zurich|italy|milan|rome|spain|madrid|mallorca|ibiza|marbella|greece|mykonos|athens|germany|belgium|netherlands|portugal|austria|ireland|jersey|guernsey|luxembourg|sweden|norway|denmark|iceland|cyprus|malta|europe|saint-tropez|courchevel|st moritz|cannes' then 'EUROPE'
    when p ~* 'united states|(^|[^a-z])(usa|us)([^a-z]|$)|new york|miami|los angeles|canada|toronto' then 'NORTH_AMERICA'
    when p ~* '^\s*global' then 'GLOBAL'
    else 'REST_OF_WORLD'
  end
$$;

alter table public.companies add column if not exists vertical_override text
  check (vertical_override in ('PRIVATE_UHNW', 'CORPORATE', 'BRAND_PRODUCTION', 'HOSPITALITY', 'TRAVEL_CONCIERGE', 'WEDDINGS_EVENTS', 'SPORTS_TALENT', 'OTHER'));

-- One classified row per opportunity (origin = where the client is, opportunity = where the work is).
create or replace view public.hq_opportunity_facts
with (security_invoker = true) as
select o.id as opportunity_id, o.company_id,
       coalesce(c.vertical_override, hq_vertical(coalesce(c.company_type, o.company_type), o.opportunity_type, coalesce(c.sector, o.sector))) as vertical,
       hq_market(coalesce(c.country, o.country)) as origin_market,
       coalesce(c.country, o.country) as origin_country,
       case when o.destination ~* 'egypt|cairo|gouna|red sea|luxor|aswan|nile' then 'EGYPT'
            else hq_market(o.destination) end as opportunity_market,
       o.destination
from opportunities o left join companies c on c.id = o.company_id;
revoke all on public.hq_opportunity_facts from anon, authenticated;

-- ---------------------------------------------------------------- relationship memory
create table if not exists public.relationship_notes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete set null,
  contact_id uuid references public.contacts(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  connection_id uuid,
  kind text not null check (kind in ('NOTE', 'HOW_WE_MET', 'REFERRAL', 'PROMISE', 'PRIOR_PROJECT', 'MEETING_NOTES', 'SHARED_CONNECTION')),
  body text not null check (length(btrim(body)) between 1 and 4000),
  follow_up_at date,
  created_by text not null,
  created_at timestamptz not null default now()
);
create index if not exists relationship_notes_company_idx on public.relationship_notes (company_id);
create index if not exists relationship_notes_contact_idx on public.relationship_notes (contact_id);
create index if not exists relationship_notes_opp_idx on public.relationship_notes (opportunity_id);
alter table public.relationship_notes enable row level security;
revoke all on public.relationship_notes from anon, authenticated;

-- ---------------------------------------------------------------- LinkedIn (Adam's own export)
create table if not exists public.linkedin_connections (
  id uuid primary key default gen_random_uuid(),
  first_name text,
  last_name text,
  profile_url text not null unique,
  email text,                          -- only if present in Adam's own export; never inferred
  company text,
  position text,
  connected_on date,
  matched_company_id uuid references public.companies(id) on delete set null,
  vertical text,
  status text not null default 'NEW' check (status in ('NEW', 'TO_CONTACT', 'CONTACTED', 'REPLIED', 'MEETING', 'INTRODUCED',
                                                         'OPPORTUNITY', 'NO_RESPONSE', 'LONG_TERM', 'DO_NOT_CONTACT')),
  relationship_strength text not null default 'UNKNOWN',  -- no data source measures this; never invented
  how_we_know text,
  last_contacted_at timestamptz,
  next_follow_up_at date,
  follow_ups_sent smallint not null default 0,
  source text not null default 'LINKEDIN_DATA_EXPORT',
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists linkedin_connections_company_idx on public.linkedin_connections (matched_company_id);
alter table public.linkedin_connections enable row level security;
revoke all on public.linkedin_connections from anon, authenticated;

-- ---------------------------------------------------------------- drafting requests
create table if not exists public.message_drafts (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('LINKEDIN', 'EMAIL', 'INSTAGRAM', 'WHATSAPP')),
  voice text not null check (voice in ('ADAM_PERSONAL', 'NOYA')),
  message_type text not null check (message_type in ('FIRST_MESSAGE', 'RECONNECTION', 'FOLLOW_UP', 'INTRODUCTION_REQUEST', 'PARTNERSHIP',
                                                     'EGYPT_OPPORTUNITY', 'CORPORATE', 'HOSPITALITY', 'BRAND_PRODUCTION', 'PRIVATE_CLIENT_INTRO')),
  connection_id uuid references public.linkedin_connections(id) on delete cascade,
  contact_id uuid references public.contacts(id) on delete set null,
  company_id uuid references public.companies(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  context jsonb not null default '{}'::jsonb,   -- only the facts needed to write the message
  adam_note text,
  status text not null default 'REQUESTED' check (status in ('REQUESTED', 'DRAFTING', 'READY', 'PROVIDER_UNAVAILABLE', 'USED', 'DISCARDED')),
  draft text,
  quality_issues jsonb,
  model text,
  attempts smallint not null default 0,
  requested_by text not null,
  requested_at timestamptz not null default now(),
  completed_at timestamptz
);
create index if not exists message_drafts_status_idx on public.message_drafts (status, requested_at);
alter table public.message_drafts enable row level security;
revoke all on public.message_drafts from anon, authenticated;

-- ---------------------------------------------------------------- finance
alter table public.revenue add column if not exists invoice_status text not null default 'DRAFT'
  check (invoice_status in ('DRAFT', 'SENT', 'PART_PAID', 'PAID', 'OVERDUE', 'CANCELLED'));
alter table public.revenue add column if not exists due_at date;
alter table public.revenue add column if not exists notes text;
alter table public.revenue add column if not exists source text not null default 'MANUAL';
alter table public.revenue add column if not exists recorded_by text;

create table if not exists public.revenue_payments (
  id uuid primary key default gen_random_uuid(),
  revenue_id uuid not null references public.revenue(id) on delete restrict,
  amount numeric(14, 2) not null check (amount > 0),
  currency text not null,
  paid_at date not null,
  method text,
  reference text,
  note text,
  recorded_by text not null,
  created_at timestamptz not null default now()
);
create index if not exists revenue_payments_revenue_idx on public.revenue_payments (revenue_id);
alter table public.revenue_payments enable row level security;
revoke all on public.revenue_payments from anon, authenticated;

-- Effective finance state per revenue record: paid = sum of payments (never an edited total).
create or replace view public.hq_finance_records
with (security_invoker = true) as
select r.id, r.company_id, r.opportunity_id, coalesce(c.name, o.company_name) as company, r.revenue_type, r.description,
       r.currency, r.amount as gross_amount, coalesce(p.paid, 0) as amount_paid,
       greatest(r.amount - coalesce(p.paid, 0), 0) as outstanding,
       r.invoice_reference, r.due_at, p.last_paid_at, r.notes, r.source, r.created_at, r.updated_at, r.recorded_by,
       case
         when r.invoice_status = 'CANCELLED' then 'CANCELLED'
         when coalesce(p.paid, 0) >= r.amount and r.amount > 0 then 'PAID'
         when r.invoice_status = 'DRAFT' then 'DRAFT'
         when r.due_at < (now() at time zone 'Africa/Cairo')::date and coalesce(p.paid, 0) < r.amount then 'OVERDUE'
         when coalesce(p.paid, 0) > 0 then 'PART_PAID'
         else 'SENT'
       end as status
from revenue r
left join companies c on c.id = r.company_id
left join opportunities o on o.id = r.opportunity_id
left join (select revenue_id, sum(amount) paid, max(paid_at) last_paid_at from revenue_payments group by 1) p on p.revenue_id = r.id;
revoke all on public.hq_finance_records from anon, authenticated;

-- Keep the legacy payment_status column consistent with the ledger.
create or replace function public.sync_revenue_payment_status(p_revenue uuid)
returns void language sql security definer set search_path = public as $$
  update revenue r set payment_status = case
      when r.invoice_status = 'CANCELLED' then 'CANCELLED'
      when f.amount_paid >= r.amount and r.amount > 0 then 'PAID'
      when f.amount_paid > 0 then 'PART_PAID'
      else 'PENDING' end,
    received_at = case when f.amount_paid >= r.amount and r.amount > 0 then f.last_paid_at else r.received_at end,
    updated_at = now()
  from hq_finance_records f where f.id = r.id and r.id = p_revenue
$$;

-- ---------------------------------------------------------------- cost centre / dependency register
create table if not exists public.system_services (
  id uuid primary key default gen_random_uuid(),
  service text not null unique,
  purpose text not null,
  used_by text,
  owner text not null default 'Adam',
  current_plan text,
  cost_type text not null check (cost_type in ('FREE', 'FIXED_MONTHLY', 'PAY_AS_YOU_GO', 'USAGE_LIMITED', 'UNKNOWN')),
  monthly_cost numeric(12, 2),       -- null = UNKNOWN; only from an invoice or plan page
  currency text,
  usage_cost text,
  usage_limit text,
  breaks_if_removed text,
  alternative text,
  credentials_location text,          -- where the credential lives, never the value
  renewal_date date,
  verified boolean not null default false,
  verification_note text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'PROPOSED', 'AWAITING_APPROVAL', 'RETIRED')),
  updated_at timestamptz not null default now()
);
alter table public.system_services enable row level security;
revoke all on public.system_services from anon, authenticated;

insert into public.system_services (service, purpose, used_by, current_plan, cost_type, monthly_cost, currency, usage_cost, usage_limit,
  breaks_if_removed, alternative, credentials_location, verified, verification_note) values
 ('n8n Cloud', 'Runs every NOYA workflow (discovery, outreach drafting, Gmail sync, briefs, alerts)', 'All workflows 00–13',
  'UNKNOWN (instance noyaprivate.app.n8n.cloud)', 'UNKNOWN', null, null, 'Plan-based executions', 'UNKNOWN',
  'All automation stops: no discovery, no drafts, no reply tracking, no CEO brief', 'Self-hosted n8n (server + maintenance)', 'n8n account (Adam)', false, 'Check plan and renewal in n8n → Settings → Usage and plan'),
 ('n8n AI gateway credits', 'Low-cost AI: Gemini 3.1 Flash-Lite (primary), GPT-5 mini (drafting/backup)', '02–11, 13',
  'Included credits of the n8n plan (allowance UNKNOWN)', 'UNKNOWN', null, null, 'Per-call credits, price not exposed', 'UNKNOWN',
  'AI drafting/classification degrade to deterministic fallbacks; CEO brief still arrives (degraded)', 'Own Gemini/OpenAI API key in n8n', 'Managed by n8n (no key held by NOYA)', false, 'Confirm allowance before increasing volume'),
 ('Anthropic API', 'Premium model (Claude Sonnet 4.6) for manual escalation only', 'None automatic',
  'Pay-as-you-go account; credit not reaching the n8n key', 'PAY_AS_YOU_GO', null, 'USD', 'Per token', 'Account balance',
  'Nothing in normal operation', 'Leave unused', 'n8n credential "Anthropic"', false, 'Balance showed too low on 28–29 Sep'),
 ('Supabase', 'CRM database, HQ authentication and server functions (source of truth)', 'HQ, all workflows',
  'UNKNOWN (project noya-ai-hq)', 'UNKNOWN', null, null, null, 'UNKNOWN',
  'HQ and every workflow stop; CRM unavailable', 'None short-term (core)', 'Supabase dashboard; n8n credential "Supabase account"', false, 'Check plan in Supabase → Billing'),
 ('Hunter', 'Finds and verifies business email addresses', '05, discovery 02–08',
  'UNKNOWN', 'UNKNOWN', null, null, 'Per search/verification', 'UNKNOWN',
  'No new VERIFIED emails; outreach falls back to LinkedIn/Instagram/contact research', 'Manual verification', 'n8n credential (Hunter header auth)', false, null),
 ('Serper', 'Google search API for discovery and decision-maker search', '02–08, 05',
  'UNKNOWN', 'UNKNOWN', null, null, 'Per search', 'UNKNOWN',
  'Discovery and contact search stop', 'Firecrawl search / manual research', 'n8n credential (Serper)', false, '~2,000 searches/month projected at current throttle'),
 ('Firecrawl', 'Reads company websites during research', '02–08',
  'UNKNOWN', 'UNKNOWN', null, null, 'Per page/credit', 'UNKNOWN',
  'Research depth drops; discovery continues on search results', 'Plain HTTP fetch', 'n8n credential (Firecrawl)', false, '~180 calls/month projected'),
 ('Google Workspace (noya@noyaconcierge.com)', 'Mailbox for outreach drafts, sending and reply tracking', '12, 13, Adam',
  'UNKNOWN', 'UNKNOWN', null, null, null, null,
  'No Gmail drafts, sends or reply tracking', 'None (core)', 'n8n credential "NOYA Gmail" (OAuth)', false, null),
 ('Cloudflare (Pages / DNS)', 'Hosts hq.noyaconcierge.com (static HQ)', 'HQ',
  'UNKNOWN (static assets usually free tier)', 'UNKNOWN', null, null, null, null,
  'HQ unreachable (data is safe in Supabase)', 'Any static host', 'Cloudflare account (Adam)', false, null),
 ('Windsor.ai', 'Instagram / paid-media performance data for 10a/10b', '10a, 10b',
  'Free plan (1 account allowed, 3 connected)', 'USAGE_LIMITED', 0, null, null, '1 connected account',
  'Marketing performance data stops (already stale)', 'Instagram Graph API directly', 'n8n credential (Windsor)', true, 'Free-plan notice returned 29 Sep'),
 ('GitHub', 'Code repository for HQ, migrations and workflow code', 'Build/deploy',
  'UNKNOWN', 'UNKNOWN', null, null, null, null,
  'No new deployments; running systems unaffected', 'Any git host', 'GitHub account (noya-sudo)', false, null),
 ('Domain noyaconcierge.com', 'Website, email and HQ domain', 'Everything',
  'UNKNOWN registrar/renewal', 'UNKNOWN', null, null, null, null,
  'Email, website and HQ stop if the domain lapses', 'None', 'Registrar account', false, 'Record the renewal date'),
 ('LinkedIn (Adam personal)', 'Warm network and relationship outreach (manual send, deep links)', 'HQ LinkedIn view',
  'Free personal account; no API integration connected', 'FREE', 0, null, null, 'LinkedIn''s own limits on invitations/messages',
  'Nothing automated depends on it', 'n/a', 'None stored (by design)', true, 'Integration method awaiting Adam''s approval')
on conflict (service) do nothing;

-- ---------------------------------------------------------------- audit helper
create or replace function public.hq_audit(p_action text, p_opportunity uuid, p_detail jsonb)
returns void language sql security definer set search_path = public as $$
  insert into approval_audit (opportunity_id, action, result, actor, detail)
  values (p_opportunity, p_action, 'OK', hq_admin_email(), p_detail)
$$;
revoke all on function public.hq_audit(text, uuid, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- read: directory
create or replace function public.hq_directory()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with
  co as (
    select c.*, coalesce(c.vertical_override, hq_vertical(c.company_type, null, c.sector)) as vertical, hq_market(c.country) as market,
      (select count(*) from opportunities o where o.company_id = c.id) as opp_count,
      (select count(*) from opportunities o where o.company_id = c.id and o.status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM')) as active_opps,
      (select count(*) from opportunities o where o.company_id = c.id and o.status = 'WON') as won,
      (select count(*) from tasks t where t.company_id = c.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')) as open_tasks,
      (select count(*) from contacts k where k.company_id = c.id) as contacts,
      greatest(c.updated_at, (select max(occurred_at) from interactions i where i.company_id = c.id),
               (select max(o.updated_at) from opportunities o where o.company_id = c.id)) as last_activity,
      (select string_agg(distinct o.status, ',') from opportunities o where o.company_id = c.id) as stages
    from companies c where coalesce(c.notes, '') not like '%MERGED_INTO:%'
  ),
  ct as (
    select k.*, co.name as company, email_kind(k.email) as email_kind,
      p.provenance, p.provider, p.checked_at, p.source_workflow, p.quality_issue,
      (select max(occurred_at) from interactions i where i.contact_id = k.id) as last_interaction,
      (select count(*) from opportunities o where o.contact_id = k.id and o.status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM')) as active_opps
    from contacts k left join companies co on co.id = k.company_id
    left join contact_email_provenance p on p.contact_id = k.id
  )
  select jsonb_build_object(
    'generated_at', now(),
    'companies', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'website', website, 'country', country, 'city', city,
        'market', market, 'vertical', vertical, 'vertical_override', vertical_override, 'company_type', company_type,
        'relationship_status', relationship_status, 'source', source, 'instagram', instagram, 'linkedin', linkedin,
        'opp_count', opp_count, 'active_opps', active_opps, 'won', won, 'open_tasks', open_tasks, 'contacts', contacts,
        'stages', stages, 'last_activity', last_activity, 'created_at', created_at) order by active_opps desc, name) from co), '[]'::jsonb),
    'contacts', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'first_name', first_name, 'last_name', last_name,
        'name', nullif(btrim(concat_ws(' ', first_name, last_name)), ''), 'position', position, 'company_id', company_id, 'company', company,
        'email', email, 'email_status', email_status, 'email_kind', email_kind, 'provenance', provenance, 'provider', provider,
        'verified_at', checked_at, 'verified_by', source_workflow, 'email_source', email_source_url, 'quality_issue', quality_issue,
        'phone', phone, 'linkedin', linkedin, 'instagram', instagram, 'country', country, 'status', status,
        'do_not_contact', do_not_contact, 'source', source, 'created_at', created_at,
        'last_interaction', last_interaction, 'active_opps', active_opps) order by company nulls last, last_name) from ct), '[]'::jsonb),
    'opportunity_facts', coalesce((select jsonb_object_agg(opportunity_id, jsonb_build_object('company_id', company_id, 'vertical', vertical,
        'origin_market', origin_market, 'origin_country', origin_country, 'opportunity_market', opportunity_market, 'destination', destination))
      from hq_opportunity_facts), '{}'::jsonb),
    'connections', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'name', nullif(btrim(concat_ws(' ', l.first_name, l.last_name)), ''),
        'profile_url', l.profile_url, 'company', l.company, 'position', l.position, 'connected_on', l.connected_on,
        'matched_company_id', l.matched_company_id, 'matched_company', mc.name, 'vertical', l.vertical, 'status', l.status,
        'relationship_strength', l.relationship_strength, 'how_we_know', l.how_we_know,
        'last_contacted_at', l.last_contacted_at, 'next_follow_up_at', l.next_follow_up_at, 'follow_ups_sent', l.follow_ups_sent,
        'active_opps', (select count(*) from opportunities o where o.company_id = l.matched_company_id and o.status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM'))))
      from linkedin_connections l left join companies mc on mc.id = l.matched_company_id), '[]'::jsonb),
    'drafts', coalesce((select jsonb_agg(to_jsonb(d) - 'context' order by d.requested_at desc) from (
        select * from message_drafts where status in ('REQUESTED', 'DRAFTING', 'READY', 'PROVIDER_UNAVAILABLE') order by requested_at desc limit 100) d), '[]'::jsonb),
    'notes_count', (select count(*) from relationship_notes)
  ) into v;
  return v;
end $$;

-- ---------------------------------------------------------------- read: timeline for one record
create or replace function public.hq_timeline(p_kind text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with scope as (
    select o.id as opp_id from opportunities o
    where (p_kind = 'opportunity' and o.id = p_id) or (p_kind = 'company' and o.company_id = p_id) or (p_kind = 'contact' and o.contact_id = p_id)
  ),
  ev as (
    select i.occurred_at as at, case i.channel when 'MEETING' then 'Meeting' when 'LINKEDIN' then 'LinkedIn' when 'INSTAGRAM_DM' then 'Instagram'
             when 'PHONE' then 'Call' when 'WHATSAPP' then 'WhatsApp' when 'WEBSITE' then 'Website' else 'Email' end as channel,
           i.direction, coalesce(i.subject, '') as title, coalesce(i.summary, '') as detail, 'interaction' as src
    from interactions i
    where (p_kind = 'company' and i.company_id = p_id) or (p_kind = 'contact' and i.contact_id = p_id)
       or i.opportunity_id in (select opp_id from scope)
    union all
    select l.received_at, case when l.classification in ('OUT_OF_OFFICE', 'BOUNCE') then 'Auto-reply' else 'Reply' end, 'INBOUND',
           coalesce(l.classification, '') || ' — ' || coalesce(l.detail->>'subject', ''), coalesce(l.detail->>'summary', ''), 'reply'
    from gmail_sync_ledger l where l.kind = 'INBOUND_REPLY' and l.opportunity_id in (select opp_id from scope)
    union all
    select n.created_at, 'Note', null, replace(initcap(replace(n.kind, '_', ' ')), 'Noya', 'NOYA'), n.body, 'note'
    from relationship_notes n
    where (p_kind = 'company' and n.company_id = p_id) or (p_kind = 'contact' and n.contact_id = p_id)
       or (p_kind = 'opportunity' and n.opportunity_id = p_id) or n.opportunity_id in (select opp_id from scope)
    union all
    select coalesce(t.completed_at, t.created_at), 'Task', null, t.status || ' — ' || t.title, '', 'task'
    from tasks t where t.opportunity_id in (select opp_id from scope) and t.status in ('COMPLETED', 'CANCELLED')
    union all
    select w.created_at, 'Website', 'INBOUND', 'Website enquiry ' || coalesce(w.reference, '') || ' — ' || w.lead_type, coalesce(left(w.message, 300), ''), 'website'
    from website_enquiries w where w.created_opportunity_id in (select opp_id from scope)
       or (p_kind = 'company' and w.matched_company_id = p_id) or (p_kind = 'contact' and w.matched_contact_id = p_id)
    union all
    select v.checked_at, 'Verification', null, 'Email check: ' || v.email || ' — ' || coalesce(v.outcome, ''), coalesce(v.provider_status, ''), 'verification'
    from contact_email_verifications v
    where (p_kind = 'contact' and v.applied_contact_id = p_id) or (p_kind = 'company' and v.company_id = p_id) or v.opportunity_id in (select opp_id from scope)
  )
  select jsonb_build_object('events', coalesce((select jsonb_agg(to_jsonb(e) order by e.at desc) from (select distinct * from ev) e), '[]'::jsonb),
    'notes', coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc) from relationship_notes n
        where (p_kind = 'company' and n.company_id = p_id) or (p_kind = 'contact' and n.contact_id = p_id) or (p_kind = 'opportunity' and n.opportunity_id = p_id)), '[]'::jsonb))
  into v;
  return v;
end $$;

-- ---------------------------------------------------------------- read: insight (markets, growth, finance, costs)
create or replace function public.hq_insight()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with
  f as (
    select o.*, x.vertical, x.origin_market, x.opportunity_market,
      exists (select 1 from gmail_sync_ledger l where l.opportunity_id = o.id and l.kind = 'INBOUND_REPLY'
              and l.classification in ('POSITIVE', 'MEETING_REQUEST', 'NEEDS_INFO', 'REFERRAL')) as positive_reply,
      exists (select 1 from outbound_emails e where e.opportunity_id = o.id and e.status = 'SENT')
        or exists (select 1 from interactions i where i.opportunity_id = o.id and i.direction = 'OUTBOUND') as contacted
    from opportunities o join hq_opportunity_facts x on x.opportunity_id = o.id
  ),
  active as (select * from f where status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM')),
  mk as (select unnest(array['EGYPT', 'EUROPE', 'GCC', 'NORTH_AMERICA', 'REST_OF_WORLD', 'GLOBAL', 'UNKNOWN']) as m),
  fin as (select * from hq_finance_records)
  select jsonb_build_object(
    'generated_at', now(),
    'markets', (select jsonb_agg(jsonb_build_object('market', mk.m,
        'companies', (select count(*) from companies c where hq_market(c.country) = mk.m and coalesce(c.notes, '') not like '%MERGED_INTO:%'),
        'contacts', (select count(*) from contacts k left join companies c on c.id = k.company_id where hq_market(coalesce(c.country, k.country)) = mk.m),
        'active_opps_origin', (select count(*) from active a where a.origin_market = mk.m),
        'active_opps_destination', (select count(*) from active a where a.opportunity_market = mk.m),
        'contacted', (select count(*) from f where f.origin_market = mk.m and f.contacted),
        'positive_replies', (select count(*) from f where f.origin_market = mk.m and f.positive_reply),
        'calls', (select count(*) from f where f.origin_market = mk.m and f.status in ('CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON')),
        'won', (select count(*) from f where f.origin_market = mk.m and f.status = 'WON'),
        'pipeline', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', s)), '[]'::jsonb) from
            (select currency, sum(estimated_value) s from active a where a.origin_market = mk.m and estimated_value is not null group by currency) q),
        'verticals', (select coalesce(jsonb_object_agg(vertical, n), '{}'::jsonb) from (select vertical, count(*) n from active a where a.origin_market = mk.m group by vertical) q),
        'last_activity', (select max(updated_at) from f where f.origin_market = mk.m)) order by mk.m) from mk),
    'bridges', (select coalesce(jsonb_agg(jsonb_build_object('route', route, 'active', n, 'contacted', c, 'positive', p, 'calls', k) order by n desc), '[]'::jsonb) from (
        select origin_market || ' → ' || opportunity_market as route, count(*) filter (where status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM')) n,
               count(*) filter (where contacted) c, count(*) filter (where positive_reply) p,
               count(*) filter (where status in ('CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON')) k
        from f group by 1) b),
    'verticals', (select coalesce(jsonb_agg(jsonb_build_object('vertical', vertical, 'active', a, 'contacted', c, 'positive', p, 'calls', k, 'won', w,
        'reply_rate', case when c > 0 then round(100.0 * p / c) end) order by c desc, a desc), '[]'::jsonb) from (
        select vertical, count(*) filter (where status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM')) a, count(*) filter (where contacted) c,
               count(*) filter (where positive_reply) p, count(*) filter (where status in ('CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON')) k,
               count(*) filter (where status = 'WON') w
        from f group by vertical) v),
    'channels', (select jsonb_agg(jsonb_build_object('channel', ch, 'sent', s, 'replies', r)) from (
        select 'EMAIL' ch, (select count(*) from outbound_emails where status = 'SENT') s,
               (select count(*) from gmail_sync_ledger where kind = 'INBOUND_REPLY' and classification not in ('OUT_OF_OFFICE', 'BOUNCE', 'UNRELATED')) r
        union all select 'LINKEDIN', (select count(*) from interactions where channel = 'LINKEDIN' and direction = 'OUTBOUND'),
               (select count(*) from interactions where channel = 'LINKEDIN' and direction = 'INBOUND')
        union all select 'INSTAGRAM', (select count(*) from interactions where channel = 'INSTAGRAM_DM' and direction = 'OUTBOUND'),
               (select count(*) from interactions where channel = 'INSTAGRAM_DM' and direction = 'INBOUND')) q),
    'stalled', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'company', company_name, 'status', status, 'value', estimated_value,
        'currency', currency, 'days', floor(extract(epoch from now() - updated_at) / 86400), 'next_action', next_action)
        order by estimated_value desc nulls last), '[]'::jsonb)
      from active where status in ('CONTACTED', 'FOLLOW_UP', 'INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION') and updated_at < now() - interval '10 days'),
    'reactivate', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'company', company_name, 'status', status,
        'days', floor(extract(epoch from now() - updated_at) / 86400)) order by updated_at), '[]'::jsonb)
      from f where status in ('LONG_TERM', 'FOLLOW_UP') or (status = 'CONTACTED' and updated_at < now() - interval '21 days' and not positive_reply)),
    'finance', jsonb_build_object(
      'records', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from fin x), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'revenue_id', p.revenue_id, 'amount', p.amount, 'currency', p.currency,
          'paid_at', p.paid_at, 'method', p.method, 'reference', p.reference, 'recorded_by', p.recorded_by, 'created_at', p.created_at) order by p.paid_at desc)
        from revenue_payments p), '[]'::jsonb),
      'by_currency', coalesce((select jsonb_agg(jsonb_build_object('currency', currency, 'won', won, 'collected', collected, 'outstanding', outstanding,
          'overdue', overdue)) from (
          select currency, sum(gross_amount) filter (where status not in ('CANCELLED', 'DRAFT')) won,
                 sum(amount_paid) collected, sum(outstanding) filter (where status in ('SENT', 'PART_PAID', 'OVERDUE')) outstanding,
                 sum(outstanding) filter (where status = 'OVERDUE') overdue
          from fin group by currency) q), '[]'::jsonb),
      'pipeline', coalesce((select jsonb_agg(jsonb_build_object('currency', currency, 'amount', s, 'opportunities', n)) from (
          select currency, sum(estimated_value) s, count(*) n from active where estimated_value is not null group by currency) q), '[]'::jsonb),
      'pipeline_unknown', (select count(*) from active where estimated_value is null)),
    'services', coalesce((select jsonb_agg(to_jsonb(s) order by s.status, s.service) from system_services s), '[]'::jsonb),
    'cost_usage', coalesce((select jsonb_agg(to_jsonb(c)) from cost_observability c), '[]'::jsonb),
    'budget', (select value from system_config where key = 'ai_budget')
  ) into v;
  return v;
end $$;

-- ---------------------------------------------------------------- writes (all admin-checked + audited)
create or replace function public.hq_opportunity_update(p_opportunity uuid, p_status text default null, p_next_action text default null, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_old opportunities%rowtype;
begin
  select * into v_old from opportunities where id = p_opportunity for update;
  if v_old.id is null then return jsonb_build_object('ok', false, 'reason', 'OPPORTUNITY_NOT_FOUND'); end if;
  if p_status is not null and p_status not in ('NEW', 'RESEARCHING', 'READY', 'CONTACTED', 'INTERESTED', 'CALL_REQUIRED', 'PROPOSAL',
      'NEGOTIATION', 'WON', 'LOST', 'FOLLOW_UP', 'LONG_TERM', 'ARCHIVED') then
    return jsonb_build_object('ok', false, 'reason', 'INVALID_STAGE');
  end if;
  update opportunities set status = coalesce(p_status, status), next_action = coalesce(hq_trim(p_next_action), next_action), updated_at = now()
   where id = p_opportunity;
  if hq_trim(p_note) is not null then
    insert into relationship_notes (company_id, opportunity_id, kind, body, created_by) values (v_old.company_id, p_opportunity, 'NOTE', hq_trim(p_note), v_admin);
  end if;
  perform hq_audit('OPPORTUNITY_UPDATE', p_opportunity, jsonb_build_object('from_status', v_old.status, 'to_status', coalesce(p_status, v_old.status),
    'next_action', p_next_action, 'note', p_note));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_add_note(p_kind text, p_body text, p_company uuid default null, p_contact uuid default null,
  p_opportunity uuid default null, p_connection uuid default null, p_follow_up date default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_id uuid; v_company uuid := p_company;
begin
  if hq_trim(p_body) is null then return jsonb_build_object('ok', false, 'reason', 'NOTE_REQUIRED'); end if;
  if coalesce(p_company, p_contact, p_opportunity, p_connection) is null then return jsonb_build_object('ok', false, 'reason', 'RECORD_REQUIRED'); end if;
  if v_company is null and p_opportunity is not null then select company_id into v_company from opportunities where id = p_opportunity; end if;
  if v_company is null and p_contact is not null then select company_id into v_company from contacts where id = p_contact; end if;
  insert into relationship_notes (company_id, contact_id, opportunity_id, connection_id, kind, body, follow_up_at, created_by)
  values (v_company, p_contact, p_opportunity, p_connection, upper(p_kind), hq_trim(p_body), p_follow_up, v_admin) returning id into v_id;
  if p_follow_up is not null then
    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
    values (v_company, p_contact, p_opportunity, 'FOLLOW UP (Adam note)', hq_trim(p_body), 'OUTREACH_FOLLOW_UP', 'Adam', 'HQ (Adam)', 70, 'OPEN',
            (p_follow_up::timestamp + time '09:00') at time zone 'Africa/Cairo');
  end if;
  perform hq_audit('NOTE_ADDED', p_opportunity, jsonb_build_object('note_id', v_id, 'kind', upper(p_kind), 'company_id', v_company, 'contact_id', p_contact));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Record a touchpoint Adam made himself (LinkedIn message, call, meeting, Instagram, WhatsApp).
-- Optionally closes the task it came from and books one follow-up. Never sends anything.
create or replace function public.hq_log_touch(p_channel text, p_summary text, p_company uuid default null, p_contact uuid default null,
  p_opportunity uuid default null, p_connection uuid default null, p_task uuid default null, p_follow_up date default null,
  p_outcome text default null, p_direction text default 'OUTBOUND')
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_company uuid := p_company; v_contact uuid := p_contact; v_id uuid; v_ch text := upper(p_channel);
begin
  if v_ch not in ('LINKEDIN', 'INSTAGRAM_DM', 'PHONE', 'MEETING', 'WHATSAPP', 'EMAIL', 'OTHER') then return jsonb_build_object('ok', false, 'reason', 'INVALID_CHANNEL'); end if;
  if hq_trim(p_summary) is null then return jsonb_build_object('ok', false, 'reason', 'SUMMARY_REQUIRED'); end if;
  if v_company is null and p_opportunity is not null then select company_id, coalesce(v_contact, contact_id) into v_company, v_contact from opportunities where id = p_opportunity; end if;
  if v_company is null and p_contact is not null then select company_id into v_company from contacts where id = p_contact; end if;
  if v_company is null and p_connection is not null then select matched_company_id into v_company from linkedin_connections where id = p_connection; end if;
  insert into interactions (company_id, contact_id, opportunity_id, channel, direction, subject, summary, occurred_at)
  values (v_company, v_contact, p_opportunity, v_ch, case when upper(p_direction) = 'INBOUND' then 'INBOUND' else 'OUTBOUND' end,
          coalesce(hq_trim(p_outcome), initcap(replace(v_ch, '_', ' '))), hq_trim(p_summary) || ' (logged in HQ by ' || v_admin || ')', now())
  returning id into v_id;
  if p_task is not null then
    update tasks set status = 'COMPLETED', completed_at = now(),
           description = coalesce(description, '') || E'\n\nDone in HQ: ' || initcap(replace(v_ch, '_', ' ')) || ' logged ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon HH24:MI')
     where id = p_task and status in ('OPEN', 'IN_PROGRESS', 'WAITING') and task_type <> 'SALES_OUTREACH_APPROVAL';
  end if;
  if p_connection is not null then
    update linkedin_connections set status = case when v_ch = 'MEETING' then 'MEETING' when status in ('NEW', 'TO_CONTACT') then 'CONTACTED' else status end,
           last_contacted_at = now(), next_follow_up_at = coalesce(p_follow_up, next_follow_up_at),
           follow_ups_sent = follow_ups_sent + case when status in ('CONTACTED', 'NO_RESPONSE') then 1 else 0 end, updated_at = now()
     where id = p_connection;
  end if;
  if p_opportunity is not null and v_ch in ('LINKEDIN', 'INSTAGRAM_DM', 'PHONE', 'WHATSAPP') and upper(p_direction) <> 'INBOUND' then
    update opportunities set status = 'CONTACTED', updated_at = now() where id = p_opportunity and status in ('NEW', 'RESEARCHING', 'READY');
  end if;
  if p_follow_up is not null then
    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
    select v_company, v_contact, p_opportunity, 'FOLLOW UP -- ' || coalesce((select name from companies where id = v_company), 'contact') || ' (' || initcap(replace(v_ch, '_', ' ')) || ')',
           'Follow-up booked in HQ after: ' || hq_trim(p_summary), 'OUTREACH_FOLLOW_UP', 'Adam', 'HQ (Adam)', 70, 'OPEN',
           (p_follow_up::timestamp + time '09:00') at time zone 'Africa/Cairo'
    where not exists (select 1 from tasks t where t.opportunity_id = p_opportunity and p_opportunity is not null
                      and t.task_type = 'OUTREACH_FOLLOW_UP' and t.status = 'OPEN');
  end if;
  perform hq_audit('TOUCH_LOGGED', p_opportunity, jsonb_build_object('interaction_id', v_id, 'channel', v_ch, 'task_id', p_task, 'connection_id', p_connection,
    'follow_up', p_follow_up, 'outcome', p_outcome));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Record a meeting: interaction + notes + optional stage change + one follow-up.
create or replace function public.hq_record_meeting(p_opportunity uuid, p_summary text, p_outcome text default null,
  p_new_status text default null, p_follow_up date default null, p_next_meeting date default null, p_task uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare r jsonb; v_admin text := hq_admin_email(); v_company uuid;
begin
  if p_opportunity is null then return jsonb_build_object('ok', false, 'reason', 'OPPORTUNITY_REQUIRED'); end if;
  select company_id into v_company from opportunities where id = p_opportunity;
  r := hq_log_touch('MEETING', p_summary, null, null, p_opportunity, null, p_task, p_follow_up, coalesce(hq_trim(p_outcome), 'Meeting held'));
  if (r->>'ok')::boolean is not true then return r; end if;
  insert into relationship_notes (company_id, opportunity_id, kind, body, follow_up_at, created_by)
  values (v_company, p_opportunity, 'MEETING_NOTES', hq_trim(p_summary) || coalesce(E'\nOutcome: ' || hq_trim(p_outcome), '')
          || coalesce(E'\nNext meeting: ' || to_char(p_next_meeting, 'DD Mon YYYY'), ''), p_follow_up, v_admin);
  if p_new_status is not null or p_next_meeting is not null then
    perform hq_opportunity_update(p_opportunity, p_new_status,
      case when p_next_meeting is not null then 'Next meeting ' || to_char(p_next_meeting, 'DD Mon YYYY') end, null);
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- Change the outreach channel for an opportunity: the email approval is put on hold with the reason,
-- and a single manual-channel task is created (LinkedIn / Instagram / phone). No message is sent.
create or replace function public.hq_change_channel(p_opportunity uuid, p_channel text, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_ch text := upper(p_channel); o opportunities%rowtype; v_company text; v_msg text;
begin
  select * into o from opportunities where id = p_opportunity;
  if o.id is null then return jsonb_build_object('ok', false, 'reason', 'OPPORTUNITY_NOT_FOUND'); end if;
  if v_ch not in ('LINKEDIN', 'INSTAGRAM', 'PHONE', 'EMAIL') then return jsonb_build_object('ok', false, 'reason', 'INVALID_CHANNEL'); end if;
  if v_ch = 'INSTAGRAM' and (coalesce(o.company_type, '') || ' ' || coalesce(o.opportunity_type, '')) ~* '(BANK|WEALTH|LAW|LEGAL|CONSULT|INVEST|FAMILY.OFFICE|FINANCIAL|INSURANCE)' then
    return jsonb_build_object('ok', false, 'reason', 'INSTAGRAM_NOT_APPROPRIATE');
  end if;
  select name into v_company from companies where id = o.company_id;
  if v_ch = 'EMAIL' then
    delete from approval_queue_state where opportunity_id = p_opportunity and state = 'HOLD' and reason like 'Channel changed%';
  else
    insert into approval_queue_state (opportunity_id, state, reason, decided_by)
    values (p_opportunity, 'HOLD', 'Channel changed to ' || v_ch || coalesce(': ' || hq_trim(p_note), ''), v_admin)
    on conflict (opportunity_id) do update set state = 'HOLD', reason = excluded.reason, decided_by = excluded.decided_by, decided_at = now();
    -- reuse any prepared message for that channel from the 05 draft
    select case v_ch when 'LINKEDIN' then try_jsonb(substring(t.description from 'OUTREACH_READY_JSON: (\{[^\n]*\})'))->>'linkedin_message'
                     when 'INSTAGRAM' then try_jsonb(substring(t.description from 'OUTREACH_READY_JSON: (\{[^\n]*\})'))->>'instagram_dm' end
      into v_msg from tasks t where t.opportunity_id = p_opportunity and t.description like '%OUTREACH_READY_JSON:%' order by t.created_at desc limit 1;
    if not exists (select 1 from tasks where opportunity_id = p_opportunity and status = 'OPEN'
                   and title like case v_ch when 'LINKEDIN' then 'LINKEDIN MESSAGE READY%' when 'INSTAGRAM' then 'INSTAGRAM DM READY%' else 'CALL -- %' end) then
      insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
      values (o.company_id, o.contact_id, p_opportunity,
        case v_ch when 'LINKEDIN' then 'LINKEDIN MESSAGE READY -- ' when 'INSTAGRAM' then 'INSTAGRAM DM READY -- ' else 'CALL -- ' end || coalesce(v_company, o.company_name, ''),
        case v_ch when 'LINKEDIN' then 'LINKEDIN MESSAGE READY' when 'INSTAGRAM' then 'INSTAGRAM DM READY' else 'CALL' end
          || E' -- ADAM SENDS MANUALLY (never automated)\nChannel changed in HQ by ' || v_admin || coalesce('. Reason: ' || hq_trim(p_note), '')
          || E'\n\n--- MESSAGE ---\n' || coalesce(v_msg, '(no prepared message for this channel — draft one in HQ)'),
        'CONTACT_RESOLUTION', 'Adam', 'HQ (Adam)', coalesce(o.priority, 70), 'OPEN', now() + interval '1 day');
    end if;
  end if;
  perform hq_audit('CHANNEL_CHANGED', p_opportunity, jsonb_build_object('channel', v_ch, 'note', p_note));
  return jsonb_build_object('ok', true);
end $$;

-- LinkedIn connections from Adam's own export (Connections.csv parsed in the browser).
-- Idempotent on profile URL. Stores only name, company, position, connected date, URL (and email
-- only if the export itself contains it). Matching and vertical are deterministic.
create or replace function public.hq_import_connections(p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); r jsonb; v_new int := 0; v_upd int := 0; v_skip int := 0; v_url text; v_co uuid;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 30000 then return jsonb_build_object('ok', false, 'reason', 'INVALID_ROWS'); end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_url := lower(btrim(coalesce(r->>'url', '')));
    if v_url !~ '^https?://([a-z]+\.)?linkedin\.com/in/' then v_skip := v_skip + 1; continue; end if;
    select c.id into v_co from companies c
     where coalesce(c.notes, '') not like '%MERGED_INTO:%' and hq_trim(r->>'company') is not null
       and lower(regexp_replace(c.name, '[^a-z0-9]', '', 'gi')) = lower(regexp_replace(r->>'company', '[^a-z0-9]', '', 'gi'))
     limit 1;
    insert into linkedin_connections (first_name, last_name, profile_url, email, company, position, connected_on, matched_company_id, vertical)
    values (hq_trim(r->>'first_name'), hq_trim(r->>'last_name'), v_url, nullif(lower(btrim(coalesce(r->>'email', ''))), ''),
            hq_trim(r->>'company'), hq_trim(r->>'position'),
            case when r->>'connected_on' ~ '^\d{4}-\d{2}-\d{2}$' then (r->>'connected_on')::date end, v_co,
            hq_vertical((select company_type from companies where id = v_co), r->>'position', r->>'company'))
    on conflict (profile_url) do update set company = excluded.company, position = excluded.position,
      matched_company_id = coalesce(excluded.matched_company_id, linkedin_connections.matched_company_id),
      vertical = excluded.vertical, updated_at = now();
    if found then v_new := v_new + 1; end if;
  end loop;
  perform hq_audit('LINKEDIN_IMPORT', null, jsonb_build_object('rows', jsonb_array_length(p_rows), 'upserted', v_new, 'skipped', v_skip));
  return jsonb_build_object('ok', true, 'upserted', v_new, 'skipped', v_skip);
end $$;

create or replace function public.hq_connection_update(p_connection uuid, p_status text default null, p_how_we_know text default null, p_follow_up date default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  if p_status is not null and p_status not in ('NEW', 'TO_CONTACT', 'CONTACTED', 'REPLIED', 'MEETING', 'INTRODUCED', 'OPPORTUNITY', 'NO_RESPONSE', 'LONG_TERM', 'DO_NOT_CONTACT') then
    return jsonb_build_object('ok', false, 'reason', 'INVALID_STATUS');
  end if;
  update linkedin_connections set status = coalesce(p_status, status), how_we_know = coalesce(hq_trim(p_how_we_know), how_we_know),
         next_follow_up_at = coalesce(p_follow_up, next_follow_up_at), updated_at = now() where id = p_connection;
  if not found then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  perform hq_audit('CONNECTION_UPDATE', null, jsonb_build_object('connection_id', p_connection, 'status', p_status, 'follow_up', p_follow_up));
  return jsonb_build_object('ok', true);
end $$;

-- Ask for a drafted message. Only the facts needed are stored as context; drafting happens in
-- workflow 14. Duplicate open requests for the same target and type are not created.
create or replace function public.hq_request_draft(p_channel text, p_voice text, p_type text, p_connection uuid default null, p_contact uuid default null,
  p_company uuid default null, p_opportunity uuid default null, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_id uuid; v_ctx jsonb; l linkedin_connections%rowtype; o opportunities%rowtype; k contacts%rowtype; c companies%rowtype;
begin
  if coalesce(p_connection, p_contact, p_company, p_opportunity) is null then return jsonb_build_object('ok', false, 'reason', 'RECORD_REQUIRED'); end if;
  select id into v_id from message_drafts where status in ('REQUESTED', 'DRAFTING', 'READY') and message_type = upper(p_type) and channel = upper(p_channel)
    and connection_id is not distinct from p_connection and contact_id is not distinct from p_contact and opportunity_id is not distinct from p_opportunity limit 1;
  if v_id is not null then return jsonb_build_object('ok', true, 'id', v_id, 'existing', true); end if;
  if p_connection is not null then select * into l from linkedin_connections where id = p_connection; end if;
  if p_opportunity is not null then select * into o from opportunities where id = p_opportunity; end if;
  if p_contact is not null then select * into k from contacts where id = p_contact;
  elsif o.contact_id is not null then select * into k from contacts where id = o.contact_id; end if;
  select * into c from companies where id = coalesce(p_company, o.company_id, k.company_id, l.matched_company_id);
  v_ctx := jsonb_strip_nulls(jsonb_build_object(
    'first_name', coalesce(l.first_name, k.first_name), 'role', coalesce(l.position, k.position),
    'company', coalesce(c.name, l.company, o.company_name), 'company_type', c.company_type, 'country', coalesce(c.country, o.country),
    'vertical', coalesce(c.vertical_override, hq_vertical(c.company_type, o.opportunity_type, c.sector)),
    'opportunity', o.opportunity_type, 'why_now', left(o.reason, 400), 'destination', o.destination,
    'how_we_know', l.how_we_know, 'connected_on', l.connected_on, 'relationship_status', l.status,
    'notes', (select string_agg(n.kind || ': ' || left(n.body, 200), ' | ') from (select * from relationship_notes n
               where (p_connection is not null and n.connection_id = p_connection) or (c.id is not null and n.company_id = c.id)
               order by n.created_at desc limit 3) n)));
  insert into message_drafts (channel, voice, message_type, connection_id, contact_id, company_id, opportunity_id, context, adam_note, requested_by)
  values (upper(p_channel), upper(p_voice), upper(p_type), p_connection, coalesce(p_contact, o.contact_id), c.id, p_opportunity, v_ctx, hq_trim(p_note), v_admin)
  returning id into v_id;
  perform hq_audit('DRAFT_REQUESTED', p_opportunity, jsonb_build_object('draft_id', v_id, 'channel', upper(p_channel), 'type', upper(p_type)));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.hq_draft_action(p_draft uuid, p_action text, p_text text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_a text := upper(p_action);
begin
  if v_a = 'SAVE' then update message_drafts set draft = hq_trim(p_text), status = 'READY' where id = p_draft and status in ('READY', 'PROVIDER_UNAVAILABLE');
  elsif v_a = 'USED' then update message_drafts set status = 'USED', draft = coalesce(hq_trim(p_text), draft) where id = p_draft and status in ('READY', 'PROVIDER_UNAVAILABLE');
  elsif v_a = 'DISCARD' then update message_drafts set status = 'DISCARDED' where id = p_draft and status <> 'USED';
  elsif v_a = 'RETRY' then update message_drafts set status = 'REQUESTED', attempts = 0 where id = p_draft and status = 'PROVIDER_UNAVAILABLE';
  else return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION'); end if;
  if not found then return jsonb_build_object('ok', false, 'reason', 'NOT_ALLOWED_IN_THIS_STATE'); end if;
  perform hq_audit('DRAFT_' || v_a, null, jsonb_build_object('draft_id', p_draft));
  return jsonb_build_object('ok', true);
end $$;

-- Finance writes. A record's gross amount can be corrected only while DRAFT; after that the change
-- is refused (cancel and re-issue instead), so issued figures are never silently altered.
create or replace function public.hq_finance_upsert(p_id uuid, p_company uuid, p_opportunity uuid, p_currency text, p_amount numeric,
  p_description text, p_invoice_ref text, p_due date, p_invoice_status text, p_revenue_type text default null, p_notes text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_old revenue%rowtype; v_id uuid; v_cur text := upper(btrim(coalesce(p_currency, '')));
begin
  if v_cur !~ '^[A-Z]{3}$' then return jsonb_build_object('ok', false, 'reason', 'INVALID_CURRENCY'); end if;
  if p_amount is null or p_amount <= 0 then return jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT'); end if;
  if upper(coalesce(p_invoice_status, 'DRAFT')) not in ('DRAFT', 'SENT', 'CANCELLED') then return jsonb_build_object('ok', false, 'reason', 'STATUS_IS_DERIVED'); end if;
  if p_company is null and p_opportunity is null then return jsonb_build_object('ok', false, 'reason', 'CLIENT_REQUIRED'); end if;
  if p_id is null then
    insert into revenue (company_id, opportunity_id, currency, amount, description, invoice_reference, due_at, invoice_status, revenue_type, notes,
                         payment_status, source, recorded_by, source_category)
    values (coalesce(p_company, (select company_id from opportunities where id = p_opportunity)), p_opportunity, v_cur, p_amount, hq_trim(p_description),
            hq_trim(p_invoice_ref), p_due, upper(coalesce(p_invoice_status, 'DRAFT')), hq_trim(p_revenue_type), hq_trim(p_notes), 'PENDING', 'HQ', v_admin, 'HQ')
    returning id into v_id;
    perform hq_audit('FINANCE_CREATED', p_opportunity, jsonb_build_object('revenue_id', v_id, 'currency', v_cur, 'amount', p_amount, 'status', p_invoice_status));
  else
    select * into v_old from revenue where id = p_id for update;
    if v_old.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
    if v_old.invoice_status <> 'DRAFT' and (p_amount <> v_old.amount or v_cur <> v_old.currency) then
      return jsonb_build_object('ok', false, 'reason', 'ISSUED_AMOUNT_LOCKED');
    end if;
    update revenue set currency = v_cur, amount = p_amount, description = hq_trim(p_description), invoice_reference = hq_trim(p_invoice_ref),
           due_at = p_due, invoice_status = upper(coalesce(p_invoice_status, invoice_status)), revenue_type = coalesce(hq_trim(p_revenue_type), revenue_type),
           notes = hq_trim(p_notes), updated_at = now()
     where id = p_id;
    v_id := p_id;
    perform hq_audit('FINANCE_UPDATED', v_old.opportunity_id, jsonb_build_object('revenue_id', p_id, 'from', jsonb_build_object('amount', v_old.amount,
      'currency', v_old.currency, 'status', v_old.invoice_status, 'due', v_old.due_at), 'to', jsonb_build_object('amount', p_amount, 'currency', v_cur,
      'status', p_invoice_status, 'due', p_due)));
  end if;
  perform sync_revenue_payment_status(v_id);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.hq_record_payment(p_revenue uuid, p_amount numeric, p_paid_at date, p_method text default null,
  p_reference text default null, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); r hq_finance_records%rowtype; v_id uuid;
begin
  select * into r from hq_finance_records where id = p_revenue;
  if r.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if r.status in ('CANCELLED', 'DRAFT') then return jsonb_build_object('ok', false, 'reason', 'RECORD_NOT_ISSUED'); end if;
  if p_amount is null or p_amount <= 0 then return jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT'); end if;
  if p_amount > r.outstanding then return jsonb_build_object('ok', false, 'reason', 'MORE_THAN_OUTSTANDING', 'outstanding', r.outstanding); end if;
  if p_paid_at is null or p_paid_at > (now() at time zone 'Africa/Cairo')::date then return jsonb_build_object('ok', false, 'reason', 'INVALID_DATE'); end if;
  insert into revenue_payments (revenue_id, amount, currency, paid_at, method, reference, note, recorded_by)
  values (p_revenue, p_amount, r.currency, p_paid_at, hq_trim(p_method), hq_trim(p_reference), hq_trim(p_note), v_admin) returning id into v_id;
  perform sync_revenue_payment_status(p_revenue);
  perform hq_audit('PAYMENT_RECORDED', r.opportunity_id, jsonb_build_object('revenue_id', p_revenue, 'payment_id', v_id, 'amount', p_amount, 'currency', r.currency, 'paid_at', p_paid_at));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Quick action: add an opportunity for a company, reusing the existing account when the name or
-- website domain already exists (no duplicate accounts). Email, if given, is UNVERIFIED.
create or replace function public.hq_create_opportunity(p_company_name text, p_website text, p_country text, p_opportunity_type text,
  p_next_action text, p_contact_first text default null, p_contact_last text default null, p_contact_role text default null,
  p_contact_email text default null, p_contact_linkedin text default null, p_destination text default 'Egypt', p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_co uuid; v_ct uuid; v_opp uuid; v_reused boolean := false;
begin
  if hq_trim(p_company_name) is null then return jsonb_build_object('ok', false, 'reason', 'COMPANY_REQUIRED'); end if;
  if hq_trim(p_opportunity_type) is null then return jsonb_build_object('ok', false, 'reason', 'OPPORTUNITY_TYPE_REQUIRED'); end if;
  if p_contact_email is not null and hq_trim(p_contact_email) is not null and p_contact_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok', false, 'reason', 'INVALID_EMAIL');
  end if;
  select id into v_co from companies c where coalesce(c.notes, '') not like '%MERGED_INTO:%' and (
      lower(regexp_replace(c.name, '[^a-z0-9]', '', 'gi')) = lower(regexp_replace(p_company_name, '[^a-z0-9]', '', 'gi'))
      or (hq_trim(p_website) is not null and c.website is not null and registrable_domain(c.website) = registrable_domain(p_website))) limit 1;
  if v_co is null then
    insert into companies (name, website, country, source, relationship_status) values (hq_trim(p_company_name), hq_trim(p_website), hq_trim(p_country), 'HQ (Adam)', 'prospect')
    returning id into v_co;
  else v_reused := true; end if;
  if hq_trim(p_contact_first) is not null then
    select id into v_ct from contacts where company_id = v_co and lower(first_name) = lower(hq_trim(p_contact_first))
      and lower(coalesce(last_name, '')) = lower(coalesce(hq_trim(p_contact_last), '')) limit 1;
    if v_ct is null then
      insert into contacts (company_id, first_name, last_name, position, email, email_status, linkedin, source, status, do_not_contact)
      values (v_co, hq_trim(p_contact_first), hq_trim(p_contact_last), hq_trim(p_contact_role), lower(hq_trim(p_contact_email)),
              case when hq_trim(p_contact_email) is null then 'NOT_FOUND' else 'UNVERIFIED' end, hq_trim(p_contact_linkedin), 'HQ (Adam)', 'NEW', false)
      returning id into v_ct;
    end if;
  end if;
  insert into opportunities (company_id, contact_id, company_name, opportunity_type, destination, next_action, status, approval_status, priority,
                             country, owner, run_id, description)
  values (v_co, v_ct, (select name from companies where id = v_co), hq_trim(p_opportunity_type), hq_trim(p_destination), hq_trim(p_next_action),
          'NEW', 'PENDING', 80, coalesce(hq_trim(p_country), (select country from companies where id = v_co)), 'Adam', 'HQ_MANUAL', hq_trim(p_note))
  returning id into v_opp;
  perform hq_audit('OPPORTUNITY_CREATED', v_opp, jsonb_build_object('company_id', v_co, 'company_reused', v_reused, 'contact_id', v_ct));
  return jsonb_build_object('ok', true, 'opportunity_id', v_opp, 'company_id', v_co, 'company_reused', v_reused);
end $$;

-- Company vertical classification by Adam.
create or replace function public.hq_company_update(p_company uuid, p_vertical text default null, p_relationship text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  update companies set vertical_override = case when p_vertical = 'AUTO' then null else coalesce(p_vertical, vertical_override) end,
         relationship_status = coalesce(p_relationship, relationship_status), updated_at = now() where id = p_company;
  if not found then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  perform hq_audit('COMPANY_UPDATE', null, jsonb_build_object('company_id', p_company, 'vertical', p_vertical, 'relationship', p_relationship));
  return jsonb_build_object('ok', true);
exception when check_violation then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;

-- Task action gains DISMISS (not relevant / will not do) with a reason.
create or replace function public.hq_task_dismiss(p_task uuid, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); t tasks%rowtype;
begin
  if hq_trim(p_reason) is null then return jsonb_build_object('ok', false, 'reason', 'REASON_REQUIRED'); end if;
  select * into t from tasks where id = p_task for update;
  if t.id is null or t.status not in ('OPEN', 'IN_PROGRESS', 'WAITING') then return jsonb_build_object('ok', false, 'reason', 'TASK_NOT_OPEN'); end if;
  if t.task_type = 'SALES_OUTREACH_APPROVAL' then return jsonb_build_object('ok', false, 'reason', 'USE_APPROVAL_FLOW'); end if;
  update tasks set status = 'CANCELLED', description = coalesce(description, '') || E'\n\nDismissed in HQ by ' || v_admin || ': ' || hq_trim(p_reason) where id = p_task;
  perform hq_audit('TASK_DISMISS', t.opportunity_id, jsonb_build_object('task_id', p_task, 'title', t.title, 'reason', p_reason));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- grants
do $$
declare f text;
begin
  foreach f in array array[
    'public.hq_directory()', 'public.hq_timeline(text, uuid)', 'public.hq_insight()',
    'public.hq_opportunity_update(uuid, text, text, text)', 'public.hq_add_note(text, text, uuid, uuid, uuid, uuid, date)',
    'public.hq_log_touch(text, text, uuid, uuid, uuid, uuid, uuid, date, text, text)',
    'public.hq_record_meeting(uuid, text, text, text, date, date, uuid)', 'public.hq_change_channel(uuid, text, text)',
    'public.hq_import_connections(jsonb)', 'public.hq_connection_update(uuid, text, text, date)',
    'public.hq_request_draft(text, text, text, uuid, uuid, uuid, uuid, text)', 'public.hq_draft_action(uuid, text, text)',
    'public.hq_finance_upsert(uuid, uuid, uuid, text, numeric, text, text, date, text, text, text)',
    'public.hq_record_payment(uuid, numeric, date, text, text, text)',
    'public.hq_create_opportunity(text, text, text, text, text, text, text, text, text, text, text, text)',
    'public.hq_company_update(uuid, text, text)', 'public.hq_task_dismiss(uuid, text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
revoke all on function public.sync_revenue_payment_status(uuid) from public, anon, authenticated;
