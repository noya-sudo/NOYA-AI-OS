-- NOYA HQ V3: Club foundation, Growth / Social Director, Operations (9 Oct 2026)
-- Club: the structural foundation for NOYA Private / NOYA Club. People and companies stay in contacts / companies (no
-- second CRM); these tables only say how someone relates to the club. No members, revenue or activity are invented:
-- every list starts from real records only.
-- Growth: Instagram performance (content_performance), paid media (paid_media_performance), media concepts, the content
-- pipeline (content), attribution — with honest connection state (Windsor plan limit; Metricool not connected to HQ).
-- Operations: confirmed client delivery only (projects, won business, revenue) — never cold leads.

create table if not exists public.club_people (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references public.contacts(id) on delete cascade,
  role text not null check (role in ('MEMBER', 'POTENTIAL_MEMBER', 'PRIVATE_CLIENT', 'INTRODUCER')),
  status text not null default 'PROSPECT' check (status in ('PROSPECT', 'INVITED', 'APPLIED', 'ACTIVE', 'PAUSED', 'DECLINED')),
  introduced_by uuid references public.contacts(id) on delete set null,
  source text not null,
  evidence text,
  notes text,
  decided_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (contact_id, role)
);
create table if not exists public.club_benefits (
  id uuid primary key default gen_random_uuid(),
  partner_company_id uuid references public.companies(id) on delete set null,
  title text not null,
  benefit_type text not null check (benefit_type in ('MEMBER_PRIVILEGE', 'PARTNER_RATE', 'ACCESS', 'EXPERIENCE', 'EVENT')),
  terms text,
  status text not null default 'PROPOSED' check (status in ('PROPOSED', 'NEGOTIATING', 'ACTIVE', 'ENDED')),
  source text not null,
  valid_from date, valid_to date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.club_introductions (
  id uuid primary key default gen_random_uuid(),
  from_contact_id uuid references public.contacts(id) on delete set null,
  to_contact_id uuid references public.contacts(id) on delete set null,
  to_company_id uuid references public.companies(id) on delete set null,
  purpose text not null,
  status text not null default 'PROPOSED' check (status in ('PROPOSED', 'MADE', 'DECLINED')),
  source text not null,
  made_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.club_events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  event_date date,
  city text, country text,
  venue_company_id uuid references public.companies(id) on delete set null,
  capacity int,
  status text not null default 'IDEA' check (status in ('IDEA', 'PLANNED', 'CONFIRMED', 'COMPLETED', 'CANCELLED')),
  notes text,
  source text not null,
  created_at timestamptz not null default now()
);
do $rls$
declare t text;
begin
  foreach t in array array['club_people', 'club_benefits', 'club_introductions', 'club_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $rls$;

-- ---------------------------------------------------------------- Club read
create or replace function public.hq_club()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with p as (
    select cp.*, k.first_name, k.last_name, k.position, k.email, k.linkedin, co.name company, co.id company_id
      from club_people cp join contacts k on k.id = cp.contact_id left join companies co on co.id = k.company_id),
  pj as (select p.role, jsonb_build_object('id', p.id, 'contact_id', p.contact_id, 'person', btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')),
           'position', p.position, 'company', p.company, 'company_id', p.company_id, 'status', p.status, 'source', p.source, 'evidence', p.evidence,
           'notes', p.notes, 'since', p.created_at) j, p.status from p),
  comm as (  -- communities NOYA could partner with: real qualified private clubs / member communities (Private Membership & Network)
    select c.id, c.name, c.company_type, c.country, c.city, c.website, c.partnership_model, relationship_state(c.id) rel
      from companies c
     where c.universe_status in ('QUALIFIED', 'NEEDS_REVIEW')
       and agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) = 'PRIVATE'),
  intro as (  -- introducer routes already in the CRM: confirmed people at private offices, family offices, communities
    select k.id contact_id, btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')) person, k.position, c.name company, c.id company_id,
           email_state_v3(k.email, k.email_status, k.email_source_url, k.email_verification_provider) email_state, k.linkedin
      from contacts k join comm c on c.id = k.company_id
     where k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3 and coalesce(k.first_name, '') <> '' and not coalesce(k.do_not_contact, false)
       and not exists (select 1 from club_people cp where cp.contact_id = k.id))
  select jsonb_build_object(
    'members', coalesce((select jsonb_agg(j) from pj where role = 'MEMBER'), '[]'),
    'potential_members', coalesce((select jsonb_agg(j) from pj where role = 'POTENTIAL_MEMBER'), '[]'),
    'private_clients', coalesce((select jsonb_agg(j) from pj where role = 'PRIVATE_CLIENT'), '[]'),
    'introducers', coalesce((select jsonb_agg(j) from pj where role = 'INTRODUCER'), '[]'),
    'applications', coalesce((select jsonb_agg(j) from pj where status = 'APPLIED'), '[]'),
    'benefits', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'title', b.title, 'type', b.benefit_type, 'terms', b.terms, 'status', b.status,
                   'partner', (select name from companies where id = b.partner_company_id), 'partner_company_id', b.partner_company_id, 'source', b.source,
                   'valid_to', b.valid_to) order by b.created_at desc) from club_benefits b), '[]'),
    'introductions', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'purpose', i.purpose, 'status', i.status, 'made_at', i.made_at,
                   'from', (select btrim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')) from contacts where id = i.from_contact_id),
                   'to', coalesce((select btrim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')) from contacts where id = i.to_contact_id),
                                  (select name from companies where id = i.to_company_id))) order by i.created_at desc) from club_introductions i), '[]'),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'title', e.title, 'date', e.event_date, 'city', e.city, 'country', e.country,
                   'venue', (select name from companies where id = e.venue_company_id), 'capacity', e.capacity, 'status', e.status, 'notes', e.notes)
                   order by e.event_date nulls last) from club_events e), '[]'),
    'communities', coalesce((select jsonb_agg(jsonb_build_object('company_id', c.id, 'name', c.name, 'type', c.company_type, 'country', c.country,
                   'city', c.city, 'website', c.website, 'model', c.partnership_model, 'relationship', c.rel) order by c.rel <> 'COLD' desc, c.name) from comm c), '[]'),
    'introducer_routes', coalesce((select jsonb_agg(to_jsonb(i) order by i.company) from intro i), '[]'),
    'partner_privileges', coalesce((select jsonb_agg(jsonb_build_object('company_id', c.id, 'name', c.name, 'model', c.partnership_model,
                   'value', partnership_values(c.partnership_model)) order by c.name)
                   from companies c where c.universe_status = 'QUALIFIED' and c.partnership_model in ('PREFERRED_STAY', 'RECIPROCAL', 'REFERRAL', 'GUEST_CONCIERGE')
                     and relationship_state(c.id) <> 'COLD'), '[]'))
  into v;
  return v;
end $$;
revoke all on function public.hq_club() from public, anon;
grant execute on function public.hq_club() to authenticated;

-- Adam adds a real person (already a contact) to the club structure. Nobody is added automatically.
create or replace function public.hq_club_person(p_contact uuid, p_role text, p_status text default 'PROSPECT', p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_id uuid;
begin
  if not exists (select 1 from contacts where id = p_contact) then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if p_role not in ('MEMBER', 'POTENTIAL_MEMBER', 'PRIVATE_CLIENT', 'INTRODUCER') then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE'); end if;
  if p_status not in ('PROSPECT', 'INVITED', 'APPLIED', 'ACTIVE', 'PAUSED', 'DECLINED') then return jsonb_build_object('ok', false, 'reason', 'INVALID_STATUS'); end if;
  insert into club_people (contact_id, role, status, source, notes, decided_by)
  values (p_contact, p_role, p_status, 'Adam in HQ', nullif(btrim(coalesce(p_note, '')), ''), v_admin)
  on conflict (contact_id, role) do update set status = excluded.status, notes = coalesce(excluded.notes, club_people.notes), updated_at = now(), decided_by = excluded.decided_by
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke all on function public.hq_club_person(uuid, text, text, text) from public, anon;
grant execute on function public.hq_club_person(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------- Growth, Social & Paid Media
create or replace function public.hq_growth()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  select jsonb_build_object(
    'connections', jsonb_build_object(
      'instagram', jsonb_build_object('via', 'Windsor.ai (workflow 10a, daily 10:30)', 'account', 'noyaconcierge',
          'state', case when exists (select 1 from system_blockers where blocker_key = 'WINDSOR_ACCOUNT_LIMIT' and status = 'OPEN') then 'PAUSED' else 'CONNECTED' end,
          'detail', 'Windsor free plan allows 1 connected account; Instagram, Meta Ads and Google Analytics are connected, so reads are paused.',
          'last_data', (select max(last_synced_at) from content_performance)),
      'metricool', jsonb_build_object('state', 'NOT_CONNECTED_TO_HQ',
          'detail', 'Metricool is connected to NOYA''s Instagram, but HQ cannot read Metricool yet.'),
      'meta_ads', jsonb_build_object('state', case when exists (select 1 from system_blockers where blocker_key = 'WINDSOR_ACCOUNT_LIMIT' and status = 'OPEN') then 'READ_PAUSED' else 'READ_ONLY' end,
          'detail', 'Read-only performance through Windsor. HQ never launches, boosts or changes spend.',
          'last_data', (select max(last_synced_at) from paid_media_performance), 'last_spend_date', (select max(date) from paid_media_performance where spend > 0))),
    'top_posts', coalesce((select jsonb_agg(jsonb_build_object('media_id', media_id, 'date', media_date, 'type', media_type, 'category', category,
          'destination', destination, 'property', property_or_brand, 'reach', reach, 'views', views, 'saved', saved, 'shares', shares,
          'caption', left(split_part(coalesce(caption, ''), chr(10), 1), 120)) order by reach desc nulls last) from content_performance), '[]'),
    'paid', jsonb_build_object('rows', (select count(*) from paid_media_performance),
          'spend', (select sum(spend) from paid_media_performance), 'clicks', (select sum(clicks) from paid_media_performance),
          'reach', (select sum(reach) from paid_media_performance), 'first_date', (select min(date) from paid_media_performance),
          'last_date', (select max(date) from paid_media_performance)),
    'concepts', coalesce((select jsonb_agg(jsonb_build_object('id', cc.id, 'company', c.name, 'company_id', cc.company_id, 'concept', cc.concept, 'backdrop', cc.backdrop,
          'noya_role', cc.noya_role, 'commercial_value', cc.commercial_value, 'status', cc.status, 'created_at', cc.created_at) order by cc.created_at desc)
          from creative_concepts cc left join companies c on c.id = cc.company_id), '[]'),
    'pipeline', jsonb_build_object(
          'ideas', (select count(*) from content where status in ('IDEA', 'RESEARCHING')), 'drafts', (select count(*) from content where status = 'DRAFT'),
          'approved', (select count(*) from content where status = 'APPROVED'), 'scheduled', (select count(*) from content where status = 'SCHEDULED'),
          'published', (select count(*) from content where status = 'PUBLISHED')),
    'content', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from content x), '[]'),
    'attributed_leads', coalesce((select jsonb_agg(jsonb_build_object('lead_type', lead_type, 'source', coalesce(last_touch_source, utm_source, source_type),
          'campaign', coalesce(utm_campaign, campaign_label), 'confidence', attribution_confidence, 'at', created_at) order by created_at desc) from marketing_attribution
          where not (coalesce(utm_source, '') ~* '^noya-(golive|v3-live)' or coalesce(utm_campaign, '') ~* '(test|release)')), '[]'),  -- go-live test enquiries are kept, never counted
    'test_leads_excluded', (select count(*) from marketing_attribution where coalesce(utm_source, '') ~* '^noya-(golive|v3-live)' or coalesce(utm_campaign, '') ~* '(test|release)'),
    'competitor_patterns', coalesce((select jsonb_agg(jsonb_build_object('competitor', competitor_name, 'category', competitor_category, 'hook', hook_message,
          'why', why_it_matters, 'action', recommended_action, 'at', created_at) order by relevance_score desc nulls last, created_at desc)
          from (select * from competitor_intelligence order by created_at desc limit 12) ci), '[]'))
  into v;
  return v;
end $$;
revoke all on function public.hq_growth() from public, anon;
grant execute on function public.hq_growth() to authenticated;

-- ---------------------------------------------------------------- Operations: confirmed delivery only
create or replace function public.hq_operations()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  select jsonb_build_object(
    'clients', coalesce((select jsonb_agg(jsonb_build_object('company_id', c.id, 'name', c.name, 'country', c.country, 'since', c.updated_at) order by c.name)
          from companies c where c.relationship_status ilike 'client%'), '[]'),
    'won', coalesce((select jsonb_agg(jsonb_build_object('opportunity_id', o.id, 'company', coalesce(c.name, o.company_name), 'type', o.opportunity_type,
          'value', o.contracted_value, 'currency', o.currency, 'won_at', o.won_at) order by o.won_at desc nulls last)
          from opportunities o left join companies c on c.id = o.company_id where o.status = 'WON'), '[]'),
    'projects', coalesce((select jsonb_agg(to_jsonb(p) || jsonb_build_object('company', (select name from companies where id = p.company_id),
          'items', (select count(*) from project_items pi where pi.project_id = p.id),
          'open_tasks', (select count(*) from tasks t where t.project_id = p.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING'))) order by p.starts_on nulls last)
          from projects p where p.status in ('CONFIRMED', 'PLANNING', 'LIVE', 'DELIVERED')), '[]'),
    'revenue', jsonb_build_object('records', (select count(*) from revenue), 'pending', (select count(*) from revenue where payment_status = 'PENDING')),
    'issues', coalesce((select jsonb_agg(jsonb_build_object('task_id', t.id, 'title', t.title, 'due_at', t.due_at, 'project_id', t.project_id) order by t.due_at nulls last)
          from tasks t where t.project_id is not null and t.status in ('OPEN', 'IN_PROGRESS') and coalesce(t.priority, 0) >= 80), '[]'))
  into v;
  return v;
end $$;
revoke all on function public.hq_operations() from public, anon;
grant execute on function public.hq_operations() to authenticated;
