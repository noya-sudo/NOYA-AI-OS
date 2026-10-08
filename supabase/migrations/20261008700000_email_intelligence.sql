-- Email & Contact Intelligence (Adam, 8 Oct 2026): the right person + the right email + proof + the commercial angle.
-- Research order (workflow 23): official contact, team, partnerships, press and media-kit pages, Instagram bio, speaker and
-- press pages, LinkedIn, Google-indexed business emails. Hunter only by hand for a confirmed high-value person.
-- Email quality tiers: 1 named person's business email, 2 relevant department inbox (partnerships@, sales@, pr@, events@...),
-- 3 general business inbox (info@, hello@, reservations@), 4 LinkedIn / Instagram only (never counted as an email).
-- Email status stays honest: VERIFIED (SMTP, by a provider), RISKY, INVALID, PUBLICLY LISTED (printed on a public page,
-- source kept), UNVERIFIED (no source recorded), NOT FOUND. Nothing is inferred or constructed.

alter table public.contacts
  add column if not exists email_tier smallint,
  add column if not exists email_found_at timestamptz,
  add column if not exists email_source_type text,
  add column if not exists email_verification_provider text;
alter table public.contacts drop constraint if exists contacts_email_tier_check;
alter table public.contacts add constraint contacts_email_tier_check check (email_tier is null or email_tier in (1, 2, 3));
alter table public.companies
  add column if not exists email_checked_at timestamptz,
  add column if not exists email_attempts smallint not null default 0,
  add column if not exists email_outcome text;
alter table public.outreach_candidates
  add column if not exists route_contact_id uuid references public.contacts(id) on delete set null;

-- What workflow 23 did for each company: searches, pages read, emails seen, what was kept, outcome. Operational log, not CRM data.
create table if not exists public.email_research (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  researched_at timestamptz not null default now(),
  test_tag text,
  searches int not null default 0,
  pages_fetched int not null default 0,
  pages_read int not null default 0,
  emails_seen int not null default 0,
  tier1 int not null default 0,
  tier2 int not null default 0,
  tier3 int not null default 0,
  people_found int not null default 0,
  rejected int not null default 0,
  outcome text not null check (outcome in ('NAMED_EMAIL', 'DEPARTMENT_EMAIL', 'INBOX_ONLY', 'NO_EMAIL_FOUND')),
  sources jsonb not null default '[]'::jsonb
);
create index if not exists email_research_company on public.email_research (company_id, researched_at desc);
alter table public.email_research enable row level security;
revoke all on public.email_research from anon, authenticated;

-- Acceptance tests: the companies in a test and their route state before and after.
create table if not exists public.email_intel_tests (
  test_tag text not null,
  company_id uuid not null references public.companies(id) on delete cascade,
  before jsonb not null,
  after jsonb,
  created_at timestamptz not null default now(),
  primary key (test_tag, company_id)
);
alter table public.email_intel_tests enable row level security;
revoke all on public.email_intel_tests from anon, authenticated;

-- ---------------------------------------------------------------- classification
create or replace function public.email_local_class(p_email text)
returns text language sql immutable as $$
  with l as (select lower(split_part(coalesce(p_email, ''), '@', 1)) lp)
  select case
    when p_email is null or p_email !~ '@' then null
    when lp ~ '(career|jobs?$|^jobs|recruit|^hr$|^hr\.|^joinus$|^join$|^apply$|privacy|gdpr|^dpo$|dataprotection|noreply|no-reply|donotreply|do-not-reply|support|customer|helpdesk|^help$|returns|orders|billing|invoice|^accounts?$|accounts?payable|finance|payroll|legal|abuse|webmaster|postmaster|security|unsubscribe|newsletter|subscribe|^test$)' then 'EXCLUDED'
    when lp ~ '^(partnerships?|partners?|collab\w*|sales|commercial|business|bd|newbusiness|new\.business|marketing|brand|brands|pr|press|media|communications|comms|events?|weddings?|groups?|meetings|mice|concierge|sponsorships?|guestrelations|guest\.relations|experiences?|leisure|leisuresales|leisure\.sales|trade|tradesales|travelagents|agents|b2b|influencers?|creators?|production)$'
      -- whole tokens only (maria.rosales@ is a person, sales.uk@ is a department)
      or lp ~ '(^|[._-])(partner\w*|sales|press|media|events?|weddings?|concierge|marketing|sponsor\w*|collab\w*|commercial|groups?|pr)([._-]|$)' then 'DEPARTMENT'
    when lp ~ '^(info|hello|hi|hey|contact|contactus|contact\.us|enquire|enquiries|enquiry|inquire|inquiries|inquiry|reservations?|reserve|res|bookings?|book|office|team|admin|general|mail|studio|stay|hotel|frontdesk|front\.office|reception|welcome|ask|bonjour|ciao|hola|global|international|intl|headoffice|hq)$'
      or lp ~ '(^|[._-])(info|hello|contact|enquire|enquiries|enquiry|inquire|inquiries|inquiry|reservations?|bookings?|stay|welcome|office|reception|frontdesk)([._-]|$)' then 'GENERAL'
    else 'PERSONAL' end
  from l
$$;

create or replace function public.email_tier(p_email text, p_named boolean)
returns smallint language sql immutable as $$
  select case email_local_class(p_email)
    when 'PERSONAL' then case when p_named then 1 end
    when 'DEPARTMENT' then 2
    when 'GENERAL' then 3 end::smallint
$$;

-- Honest status in words. PUBLICLY_LISTED is not VERIFIED, and VERIFIED needs a verification on record
-- (provider 'UNRECORDED' = marked verified by research without an SMTP check: shown as publicly listed / unverified).
create or replace function public.email_state(p_status text, p_source_url text, p_provider text)
returns text language sql immutable as $$
  select case
    when p_status = 'VERIFIED' and coalesce(p_provider, '') <> 'UNRECORDED' then 'VERIFIED'
    when p_status = 'VERIFIED' and coalesce(p_source_url, '') <> '' then 'PUBLICLY_LISTED'
    when p_status = 'VERIFIED' then 'UNVERIFIED'
    when p_status = 'RISKY' then 'RISKY'
    when p_status = 'INVALID' then 'INVALID'
    when p_status in ('UNVERIFIED', 'UNKNOWN', 'NOT_FOUND') and coalesce(p_source_url, '') <> '' then 'PUBLICLY_LISTED'
    when p_status in ('UNVERIFIED', 'UNKNOWN') then 'UNVERIFIED'
    else 'NOT_FOUND' end
$$;
create or replace function public.email_state(p_status text, p_source_url text)
returns text language sql immutable as $$ select email_state(p_status, p_source_url, null::text) $$;

-- The agents page names: SMTP_VERIFIED / PUBLICLY_LISTED / RISKY / INVALID / UNVERIFIED.
create or replace function public.email_trust(p_status text, p_source_url text, p_provider text)
returns text language sql immutable as $$
  select case email_state(p_status, p_source_url, p_provider) when 'VERIFIED' then 'SMTP_VERIFIED' when 'NOT_FOUND' then 'UNVERIFIED' else email_state(p_status, p_source_url, p_provider) end
$$;
create or replace function public.email_trust(p_status text, p_source_url text)
returns text language sql immutable as $$ select email_trust(p_status, p_source_url, null::text) $$;

-- Which buying centre a company is: decides which people are worth finding.
create or replace function public.contact_segment(p_lane text, p_type text, p_notes text)
returns text language sql immutable as $$
  select case
    when is_media_target(p_type, p_notes) then 'MEDIA'
    when coalesce(p_type, '') ~* '(villa|residence|serviced|aparthotel|apart-hotel|apartment|chalet|holiday home|home rental|vacation rental|private home|estate rental)' then 'VILLA'
    when coalesce(p_type, '') ~* '(members|private club|social club|community)' then 'CLUB'
    when coalesce(p_type, '') ~* '(hotel|resort|lodge|hospitality|inn\M|palace|safari camp|ryokan)' then 'HOTEL'
    when p_lane = 'PARTNERSHIPS' and coalesce(p_type, '') ~* '(concierge|travel|dmc|destination management|advisor|agency|tour)' then 'TRAVEL'
    when p_lane = 'PARTNERSHIPS' then 'HOTEL'
    when p_lane = 'TRAVEL_PRIVATE' then 'TRAVEL'
    when p_lane = 'WEDDINGS' then 'WEDDINGS'
    when p_lane = 'BRANDS' then 'BRANDS'
    when p_lane = 'SPORTS_PRIVATE' then 'SPORTS'
    when p_lane = 'EGYPT_EVENTS' then 'EVENTS'
    else 'CORPORATE' end
$$;

-- The people to find, best first, per segment (Adam, 8 Oct). Used in searches, prompts and ranking.
create or replace function public.role_focus(p_segment text)
returns text[] language sql immutable as $$
  -- Adam's priority roles per vertical (8 Oct 2026), best route first
  select case p_segment
    when 'HOTEL' then array['general manager', 'hotel manager', 'director of sales', 'director of sales and marketing', 'commercial director', 'partnerships',
                            'marketing director', 'marketing manager', 'communications', 'owner', 'managing director', 'guest relations director', 'chef concierge']
    when 'VILLA' then array['founder', 'owner', 'managing director', 'head of sales', 'partnerships', 'operations director', 'guest experience',
                            'commercial director', 'portfolio director']
    when 'TRAVEL' then array['founder', 'managing director', 'partnerships', 'head of trade', 'b2b', 'commercial director', 'head of product',
                             'supplier relations', 'destination director']
    when 'WEDDINGS' then array['founder', 'owner', 'creative director', 'lead planner', 'partner', 'events director', 'managing director', 'partnerships']
    when 'BRANDS' then array['brand partnerships', 'head of marketing', 'marketing director', 'pr director', 'experiential', 'influencer marketing',
                             'creative director', 'executive producer', 'head of production', 'talent manager', 'partnerships', 'creative producer']
    when 'MEDIA' then array['founder', 'host', 'editor', 'executive producer', 'partnerships', 'head of content', 'producer']
    when 'CORPORATE' then array['travel manager', 'executive assistant', 'chief of staff', 'head of events', 'workplace experience', 'partnerships',
                                'travel procurement', 'office of the ceo', 'corporate travel']
    when 'CLUB' then array['founder', 'membership director', 'head of partnerships', 'general manager', 'events director', 'concierge']
    when 'SPORTS' then array['commercial director', 'partnerships', 'player care', 'head of operations', 'team manager']
    else array['founder', 'director', 'head of partnerships', 'commercial director'] end
$$;

-- 0-100: how well a role fits the segment's buying centre. 0 = not a route in.
create or replace function public.role_priority(p_position text, p_segment text)
returns int language sql immutable as $$
  with r as (select lower(coalesce(p_position, '')) p),
  hit as (
    select min(i) i from r, unnest(role_focus(p_segment)) with ordinality f(term, i)
     where r.p ~ ('\m' || replace(f.term, ' ', '\M.*\m') || '\M')
        or (f.term = 'director of sales and marketing' and r.p ~ '\m(dosm|sales (and|&) marketing)\M')
        or (f.term = 'general manager' and r.p ~ '\m(gm|hotel manager|resort manager)\M')
        or (f.term = 'partnerships' and r.p ~ '\m(partnerships?|business development|alliances?)\M')
        or (f.term = 'executive assistant' and r.p ~ '\m(executive assistant|ea to|pa to|personal assistant|chief of staff)\M'))
  select case
    -- hotel guest relations and concierge leadership are a route in (front-line staff are not)
    when p_segment = 'HOTEL' and (select p from r) ~ '\m(guest relations|concierge)\M' and (select p from r) ~ '\m(director|head|chef|chief|manager)\M' then 60
    -- procurement is a route in only for corporate travel and events
    when p_segment = 'CORPORATE' and (select p from r) ~ '\mprocurement\M' and (select p from r) ~ '\m(travel|events?|meetings)\M' then 60
    when role_score(p_position) = 0 then 0
    when (select i from hit) is not null then greatest(55, 100 - ((select i from hit) - 1) * 6)::int
    else role_score(p_position) * 10 end
$$;

-- Keep tier and found date right whoever writes the email (departments, workflow 19/23, ChatGPT research, Adam in HQ).
create or replace function public.contacts_email_meta()
returns trigger language plpgsql as $$
declare v_named boolean := coalesce(new.first_name, '') <> '' and coalesce(new.last_name, '') <> '';
        v_changed boolean := false; v_names boolean := false;
begin
  if tg_op = 'INSERT' then
    v_changed := new.email is not null;
  else
    v_changed := new.email is distinct from old.email;
    v_names := new.first_name is distinct from old.first_name or new.last_name is distinct from old.last_name;
    if new.email_status = 'VERIFIED' and old.email_status is distinct from 'VERIFIED' and new.email_verification_provider is null then
      new.email_verification_provider := 'HUNTER';  -- HQ verification and the department verifier both use Hunter
    end if;
  end if;
  if tg_op = 'INSERT' and new.email_status = 'VERIFIED' and new.email_verification_provider is null then
    new.email_verification_provider := case when coalesce(new.source, '') ~* '(Department|^0[2-8] )' then 'HUNTER' else 'UNRECORDED' end;
  end if;
  if new.email is null then
    new.email_tier := null;
  elsif v_changed then
    new.email_found_at := now();
    new.email_tier := email_tier(new.email, v_named);
    new.email_source_type := coalesce(new.email_source_type, case when coalesce(new.email_source_url, '') <> '' then coalesce(new.source_type, 'SEARCH_RESULT') end);
  elsif v_names then
    new.email_tier := email_tier(new.email, v_named);
  end if;
  return new;
end $$;
create or replace trigger contacts_email_meta before insert or update on public.contacts for each row execute function public.contacts_email_meta();
revoke all on function public.contacts_email_meta() from public, anon, authenticated;

-- ---------------------------------------------------------------- domain trust
-- A website on file is used for email research only if its domain carries a distinctive word of the company name (a news
-- site or an awards page saved as the website must never make its addresses look like the company's). Same rule as
-- domainTrusted() in workflow 23.
create or replace function public.domain_trusted(p_name text, p_domain text)
returns boolean language sql immutable set search_path = public as $$
  with l as (select dom, regexp_replace(split_part(dom, '.', 1), '[^a-z0-9]', '', 'g') lbl
               from (select lower(regexp_replace(coalesce(p_domain, ''), '^(https?://)?(www\.)?', '', 'i')) dom) d),
       n as (select btrim(regexp_replace(translate(lower(coalesce(p_name, '')), 'àáâãäåèéêëìíîïòóôõöøùúûüýÿçñ', 'aaaaaaeeeeiiiiooooooouuuuyycn'), '[^a-z0-9]+', ' ', 'g')) s),
       stop as (select array['the','and','hotel','hotels','resort','resorts','group','groups','club','clubs','collection','collections','luxury','travel','travels',
                             'residence','residences','inn','inns','spa','members','member','global','international','company','worldwide','world','lifestyle',
                             'hospitality','management','house','villa','villas','beach','grand','palace','private','boutique','apartments','suites','island',
                             'city','royal','del','des','les','for','mgmt','ltd','llc','inc','plc','limited','official'] w)
  select l.dom <> '' and l.dom !~ '(instagram|linkedin|facebook|wixsite|squarespace|linktr|booking|tripadvisor|wikipedia)' and length(l.lbl) >= 2
     and (exists (select 1 from n, stop, regexp_split_to_table(n.s, ' ') tok
                   where length(tok) >= 3 and tok <> all (stop.w)
                     and case when length(tok) >= 4 then position(tok in l.lbl) > 0 else position(tok in l.lbl) = 1 end)
          or (length(l.lbl) >= 5 and l.lbl <> all (sw.w) and position(l.lbl in replace((select s from n), ' ', '')) > 0))
  from l, stop sw
$$;
revoke all on function public.domain_trusted(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- usable routes per company
-- Tier 1 / 2 count only when the address is verified or publicly listed with its source (never a bare unsourced address).
create or replace function public.company_email_routes(p_company uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with k as (select * from contacts where company_id = p_company and not coalesce(do_not_contact, false)),
  usable as (select * from k where email is not null and email_state(email_status, email_source_url, email_verification_provider) in ('VERIFIED', 'PUBLICLY_LISTED') and email_local_class(email) <> 'EXCLUDED')
  select jsonb_build_object(
    'decision_maker', exists (select 1 from k where coalesce(first_name, '') <> '' and coalesce(last_name, '') <> '' and identity_status = 'CONFIRMED' and role_score(position) >= 3),
    'tier1', exists (select 1 from usable where email_tier = 1 and role_score(position) >= 3),
    'tier1_any', exists (select 1 from usable where email_tier = 1),
    'tier2', exists (select 1 from usable where email_tier = 2),
    'tier3', exists (select 1 from usable where email_tier = 3),
    'verified', exists (select 1 from usable where email_state(email_status, email_source_url, email_verification_provider) = 'VERIFIED'),
    'linkedin', exists (select 1 from k where coalesce(linkedin, '') ~* 'linkedin\.com/in/' and identity_status = 'CONFIRMED'),
    'instagram', exists (select 1 from k where coalesce(instagram, '') <> '') or exists (select 1 from companies where id = p_company and coalesce(instagram, '') <> ''))
$$;
revoke all on function public.company_email_routes(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- the email gap queue (workflow 23 works it continuously)
-- Qualified, cold companies with a commercial angle and no usable named-person or department email yet.
-- Rank: strategic value (hospitality first), decision-maker quality, partnership / revenue potential, chance of a public email.
create or replace function public.email_gap_list(p_limit int default 40, p_test text default null, p_include_recent boolean default false)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (
    select c.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent,
           contact_segment(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) segment,
           case when domain_trusted(c.name, registrable_domain(c.website)) then registrable_domain(c.website) end domain, company_email_routes(c.id) r
      from companies c
     where (p_test is null and c.universe_status = 'QUALIFIED'
            and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'
            and relationship_state(c.id) = 'COLD'
            and (p_include_recent or (coalesce(c.email_checked_at, '-infinity'::timestamptz) < now() - interval '14 days' and coalesce(c.email_attempts, 0) < 3)))
        or (p_test is not null and c.id in (select t.company_id from email_intel_tests t where t.test_tag = p_test)
            and not exists (select 1 from email_research er where er.company_id = c.id and er.test_tag = p_test))),
  g as (
    select c.*,
      (select max(role_priority(k.position, c.segment)) from contacts k where k.company_id = c.id and not coalesce(k.do_not_contact, false)
          and coalesce(k.first_name, '') <> '' and coalesce(k.last_name, '') <> '' and role_score(k.position) > 0) best_role,
      case c.agent when 'HOSPITALITY' then 40 when 'WEDDINGS' then 22 when 'BRANDS' then 20 when 'TRAVEL' then 18 when 'CORPORATE' then 14
                   when 'MEDIA' then 12 when 'EGYPT' then 10 else 4 end strategic,
      case c.partnership_model when 'PREFERRED_STAY' then 15 when 'WHITE_LABEL_CONCIERGE' then 15 when 'EGYPT_EXECUTION' then 14 when 'RECIPROCAL' then 12
                               when 'GUEST_CONCIERGE' then 12 when 'CONTENT_TALENT' then 9 when 'REFERRAL' then 8 else 5 end potential,
      (case when c.domain is not null then 10 else 0 end
       + case when coalesce(c.company_type, '') ~* '(boutique|independent|villa|residence|planner|agency|collection|studio|advisor|designer|club)' then 5 else 0 end
       - case when c.name ~* '(four seasons|marriott|hilton|accor|ihg|hyatt|st\. regis|ritz|sheraton|kempinski|mandarin oriental|shangri|fairmont|radisson|wyndham|intercontinental|w hotels|jumeirah)' then 6 else 0 end
       + case when coalesce(c.instagram, '') <> '' then 2 else 0 end) likelihood
      from c
     where p_test is not null or not ((c.r->>'tier1')::boolean or (c.r->>'tier2')::boolean)),
  ranked as (select g.*, strategic + coalesce(best_role, 0) / 4 + potential + likelihood score from g)
  select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object(
      'company_id', x.id, 'company', x.name, 'website', x.website, 'domain', x.domain, 'country', x.country, 'city', x.city,
      'company_type', x.company_type, 'lane', x.lane, 'agent', x.agent, 'segment', x.segment, 'instagram', x.instagram,
      'role_focus', to_jsonb(role_focus(x.segment)), 'score', x.score, 'routes', x.r,
      'model', partnership_model_label(x.partnership_model), 'model_code', x.partnership_model,
      'angle', concat_ws(' ', array_to_string(partnership_model_route(x.partnership_model), '; '),
                         (select coalesce(o.angle, o.suggested_approach) from opportunities o where o.company_id = x.id order by o.created_at desc limit 1)),
      'people', (select coalesce(jsonb_agg(jsonb_build_object('first_name', k.first_name, 'last_name', k.last_name, 'position', k.position,
                                  'email', k.email, 'linkedin', k.linkedin, 'priority', role_priority(k.position, x.segment))
                                  order by role_priority(k.position, x.segment) desc), '[]'::jsonb)
                   from contacts k where k.company_id = x.id and not coalesce(k.do_not_contact, false)
                    and coalesce(k.first_name, '') <> '' and coalesce(k.last_name, '') <> '' and role_score(k.position) > 0),
      'best_role', x.best_role, 'test_tag', p_test, 'checked_at', x.email_checked_at, 'attempts', x.email_attempts)
      order by x.score desc, x.created_at desc) from (select * from ranked order by score desc, created_at desc limit greatest(1, least(coalesce(p_limit, 40), 200))) x), '[]'::jsonb))
$$;
revoke all on function public.email_gap_list(int, text, boolean) from public, anon, authenticated;

-- What workflow 23 reads: an active test first, otherwise the live gap queue.
create or replace function public.email_gap_queue(p_limit int default 8)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when (select value->>'test_tag' from system_config where key = 'email_intel_test') is not null
                   and jsonb_array_length(email_gap_list(p_limit, (select value->>'test_tag' from system_config where key = 'email_intel_test'))->'items') > 0
              then email_gap_list(p_limit, (select value->>'test_tag' from system_config where key = 'email_intel_test'))
              else email_gap_list(p_limit) end
$$;
revoke all on function public.email_gap_queue(int) from public, anon, authenticated;

-- ---------------------------------------------------------------- save (proof first)
-- Every email must carry the URL of the public page or search result it was printed on (checked upstream against the
-- fetched text). The address must sit on the company's domain, except an address printed in the company's own Instagram bio.
create or replace function public.email_intel_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_company uuid := (p->>'company_id')::uuid; c companies%rowtype; e jsonb; k uuid; v_domain text; v_email text; v_tier smallint;
        v_new int := 0; v_upd int := 0; v_inbox int := 0; v_rej int := 0; v_t1 int := 0; v_t2 int := 0; v_t3 int := 0; v_people int := 0;
        v_outcome text; v_ig_ok boolean; u jsonb; v_note text; v_src jsonb := '[]'::jsonb; v_found text;
begin
  select * into c from companies where id = v_company;
  if c.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  v_domain := case when domain_trusted(c.name, registrable_domain(c.website)) then registrable_domain(c.website) end;
  v_found := case when v_domain is null and domain_trusted(c.name, p->>'found_domain') then registrable_domain(p->>'found_domain') end;
  v_domain := coalesce(v_domain, v_found);

  -- people from official team / leadership / press pages (name and role printed on the page)
  for e in select * from jsonb_array_elements(coalesce(p->'people', '[]'::jsonb)) loop
    if coalesce(e->>'source_url', '') = '' or length(regexp_replace(coalesce(e->>'first_name', ''), '[^[:alpha:]]', '', 'g')) < 2
       or length(regexp_replace(coalesce(e->>'last_name', ''), '[^[:alpha:]]', '', 'g')) < 2 or role_score(e->>'position') = 0 then
      v_rej := v_rej + 1; continue; end if;
    select id into k from contacts where company_id = c.id
       and lower(coalesce(first_name, '')) = lower(btrim(e->>'first_name')) and lower(coalesce(last_name, '')) = lower(btrim(e->>'last_name')) limit 1;
    if k is null then
      insert into contacts (company_id, first_name, last_name, position, source, source_url, source_type, route_type, relationship_owner, status, confidence, email_status, notes)
      values (c.id, btrim(e->>'first_name'), btrim(e->>'last_name'), nullif(btrim(coalesce(e->>'position', '')), ''), 'Workflow 23 email intelligence',
              e->>'source_url', coalesce(e->>'source_type', 'OFFICIAL_SITE'), null, 'Adam Elshazly', 'NEW', 80, 'NOT_FOUND',
              'SOURCE-BACKED: name and role published at ' || (e->>'source_url'));
      v_people := v_people + 1; v_new := v_new + 1;
    else
      update contacts set position = coalesce(position, nullif(btrim(coalesce(e->>'position', '')), '')),
             source_url = coalesce(source_url, e->>'source_url'), source_type = coalesce(source_type, e->>'source_type')
       where id = k;
    end if;
  end loop;

  for e in select * from jsonb_array_elements(coalesce(p->'emails', '[]'::jsonb)) loop
    v_email := nullif(lower(btrim(coalesce(e->>'email', ''))), '');
    v_ig_ok := e->>'source_type' = 'INSTAGRAM' and coalesce(c.instagram, '') <> ''
               and lower(coalesce(e->>'source_url', '')) ~ ('instagram\.com/' || lower(regexp_replace(c.instagram, '^@', '')) || '([/?#]|$)');
    if v_email is null or coalesce(e->>'source_url', '') = '' or v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' or email_local_class(v_email) = 'EXCLUDED'
       -- email-format and people-search sites publish guessed patterns: never a source (checked again here, after the workflow)
       or lower(e->>'source_url') ~ '(rocketreach|prospeo|datanyze|aeroleads|zoominfo|signalhire|lusha|contactout|apollo\.io|hunter\.io|emailformat|email-format|leadiq|snov\.io|clearbit|unifers|contactlevel)'
       or (not v_ig_ok and (v_domain is null or registrable_domain(split_part(v_email, '@', 2)) is distinct from v_domain)) then
      v_rej := v_rej + 1; continue; end if;
    v_tier := case when coalesce(e->>'owner_first', '') <> '' and coalesce(e->>'owner_last', '') <> '' and email_local_class(v_email) = 'PERSONAL' then 1
                   when email_local_class(v_email) = 'DEPARTMENT' then 2
                   when email_local_class(v_email) = 'GENERAL' or v_ig_ok then 3 end;
    if v_tier is null then v_rej := v_rej + 1; continue; end if;
    v_note := 'Email publicly listed at ' || (e->>'source_url') || ' (' || coalesce(e->>'source_type', 'SEARCH_RESULT') || ', found ' || to_char(now(), 'DD Mon YYYY')
              || '); not SMTP-verified.' || coalesce(' Evidence: "' || left(e->>'evidence', 160) || '"', '');
    v_src := v_src || jsonb_build_array(jsonb_build_object('email', v_email, 'tier', v_tier, 'url', e->>'source_url', 'type', e->>'source_type'));
    if exists (select 1 from contacts where company_id = c.id and lower(coalesce(email, '')) = v_email) then
      -- already on file: if it had no public source, record the one just found (it becomes PUBLICLY LISTED, still not SMTP-verified)
      update contacts set email_source_url = e->>'source_url', email_source_type = coalesce(e->>'source_type', 'SEARCH_RESULT'),
             email_status = case when email_status is null or email_status in ('NOT_FOUND', 'UNKNOWN') then 'UNVERIFIED' else email_status end,
             notes = coalesce(notes, '') || chr(10) || v_note
       where company_id = c.id and lower(coalesce(email, '')) = v_email and coalesce(email_source_url, '') = '';
      continue;
    end if;
    if v_tier = 1 then
      select id into k from contacts where company_id = c.id
         and lower(coalesce(first_name, '')) = lower(btrim(e->>'owner_first')) and lower(coalesce(last_name, '')) = lower(btrim(e->>'owner_last')) limit 1;
      if k is not null and exists (select 1 from contacts where id = k and email is not null) then
        update contacts set notes = coalesce(notes, '') || chr(10) || 'Another public address seen: ' || v_email || ' at ' || (e->>'source_url') where id = k;
        continue;
      elsif k is not null then
        update contacts set email = v_email, email_status = 'UNVERIFIED', email_source_url = e->>'source_url', email_source_type = coalesce(e->>'source_type', 'SEARCH_RESULT'),
               route_type = 'PERSON_EMAIL', position = coalesce(position, nullif(btrim(coalesce(e->>'owner_role', '')), '')),
               notes = coalesce(notes, '') || chr(10) || v_note
         where id = k;
        v_upd := v_upd + 1;
      else
        insert into contacts (company_id, first_name, last_name, position, email, email_status, email_source_url, email_source_type, source, source_url, source_type,
                              route_type, relationship_owner, status, confidence, notes)
        values (c.id, btrim(e->>'owner_first'), btrim(e->>'owner_last'), nullif(btrim(coalesce(e->>'owner_role', '')), ''), v_email, 'UNVERIFIED', e->>'source_url',
                coalesce(e->>'source_type', 'SEARCH_RESULT'), 'Workflow 23 email intelligence', e->>'source_url', coalesce(e->>'source_type', 'SEARCH_RESULT'),
                'PERSON_EMAIL', 'Adam Elshazly', 'NEW', 80,
                case when nullif(btrim(coalesce(e->>'owner_role', '')), '') is not null then 'SOURCE-BACKED: name, role and email published at ' || (e->>'source_url') || chr(10) else '' end || v_note);
        v_new := v_new + 1;
      end if;
      v_t1 := v_t1 + 1;
    else
      insert into contacts (company_id, position, email, email_status, email_source_url, email_source_type, source, source_url, source_type, route_type,
                            relationship_owner, status, confidence, notes)
      values (c.id, coalesce(nullif(btrim(coalesce(e->>'department', '')), ''), case v_tier when 2 then 'Department inbox' else 'Company inbox' end),
              v_email, 'UNVERIFIED', e->>'source_url', coalesce(e->>'source_type', 'OFFICIAL_SITE'), 'Workflow 23 email intelligence', e->>'source_url',
              coalesce(e->>'source_type', 'OFFICIAL_SITE'), 'COMPANY_INBOX', 'Adam Elshazly', 'NEW', case v_tier when 2 then 60 else 45 end, v_note);
      if v_tier = 2 then v_t2 := v_t2 + 1; else v_t3 := v_t3 + 1; end if;
      v_inbox := v_inbox + 1;
    end if;
  end loop;

  for u in select * from jsonb_array_elements(coalesce(p->'usage', '[]'::jsonb)) loop
    insert into ai_usage (workflow, purpose, model, company_id, input_tokens, output_tokens, thinking_tokens, est_cost_usd, status)
    values ('23', 'EMAIL_INTEL', coalesce(u->>'model', 'models/gemini-3.1-flash-lite'), c.id, coalesce((u->>'input_tokens')::int, 0), coalesce((u->>'output_tokens')::int, 0),
            coalesce((u->>'thinking_tokens')::int, 0),
            ai_cost_usd(coalesce(u->>'model', 'models/gemini-3.1-flash-lite'), coalesce((u->>'input_tokens')::int, 0), coalesce((u->>'output_tokens')::int, 0) + coalesce((u->>'thinking_tokens')::int, 0)),
            coalesce(u->>'status', 'OK'));
  end loop;

  -- the outcome reflects the company's routes after this pass (including what was already on file)
  v_outcome := case when (company_email_routes(c.id)->>'tier1_any')::boolean then 'NAMED_EMAIL'
                    when (company_email_routes(c.id)->>'tier2')::boolean then 'DEPARTMENT_EMAIL'
                    when (company_email_routes(c.id)->>'tier3')::boolean then 'INBOX_ONLY'
                    else 'NO_EMAIL_FOUND' end;
  insert into email_research (company_id, test_tag, searches, pages_fetched, pages_read, emails_seen, tier1, tier2, tier3, people_found, rejected, outcome, sources)
  values (c.id, nullif(p->>'test_tag', ''), coalesce((p->'research'->>'searches')::int, 0), coalesce((p->'research'->>'pages_fetched')::int, 0),
          coalesce((p->'research'->>'pages_read')::int, 0), coalesce((p->'research'->>'emails_seen')::int, 0), v_t1, v_t2, v_t3, v_people,
          v_rej + coalesce((p->'research'->>'rejected')::int, 0), v_outcome, v_src);
  update companies set email_checked_at = now(), email_attempts = coalesce(email_attempts, 0) + 1, email_outcome = v_outcome where id = c.id;
  -- an official domain found by name: record it (website only if none on file; a conflicting website is surfaced, not replaced)
  if v_found is not null and not coalesce(c.notes, '') ~* ('W23: official domain .*' || replace(v_found, '.', '\.')) then
    update companies set website = coalesce(website, 'https://' || v_found),
           notes = concat_ws(chr(10), notes, case when c.website is null
             then 'W23: official domain ' || v_found || ' identified from search results by company name (' || to_char(now(), 'DD Mon YYYY') || ').'
             else 'W23: official domain ' || v_found || ' identified by company name; the website on file (' || c.website || ') does not carry the company name — please check (' || to_char(now(), 'DD Mon YYYY') || ').' end)
     where id = c.id;
  end if;
  return jsonb_build_object('ok', true, 'company', c.name, 'outcome', v_outcome, 'found_domain', v_found, 'tier1', v_t1, 'tier2', v_t2, 'tier3', v_t3, 'people', v_people,
                            'new', v_new, 'updated', v_upd, 'rejected', v_rej, 'universe', universe_reclassify_company(c.id));
end $$;
revoke all on function public.email_intel_save(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- funnel and report
-- Company-level conversion for one agent: qualified -> decision maker -> email -> usable -> ready.
create or replace function public.agent_email_funnel(p_agent text)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (
    select c.id, company_email_routes(c.id) r
      from companies c
     where c.universe_status = 'QUALIFIED'
       and agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) = p_agent)
  select jsonb_build_object(
    'qualified', count(*),
    'decision_makers', count(*) filter (where (r->>'decision_maker')::boolean),
    'direct_emails', count(*) filter (where (r->>'tier1_any')::boolean),
    'department_emails', count(*) filter (where (r->>'tier2')::boolean and not (r->>'tier1_any')::boolean),
    'usable_emails', count(*) filter (where (r->>'tier1_any')::boolean or (r->>'tier2')::boolean),
    'verified', count(*) filter (where (r->>'verified')::boolean),
    'email_gaps', count(*) filter (where (r->>'decision_maker')::boolean and not ((r->>'tier1_any')::boolean or (r->>'tier2')::boolean)),
    'ready_email', (select count(distinct t.company_id) from tasks t where t.company_id in (select id from c) and t.status in ('OPEN', 'IN_PROGRESS')
                      and t.title like 'EMAIL READY%'),
    'ready_linkedin', (select count(distinct t.company_id) from tasks t where t.company_id in (select id from c) and t.status in ('OPEN', 'IN_PROGRESS')
                         and t.title like 'LINKEDIN MESSAGE READY%'))
  from c
$$;
revoke all on function public.agent_email_funnel(text) from public, anon, authenticated;

create or replace function public.email_intel_report(p_since timestamptz default now() - interval '3 days')
returns jsonb language sql stable security definer set search_path = public as $$
  with nk as (select * from contacts where created_at >= p_since and not coalesce(do_not_contact, false)),
  em as (select * from contacts where email_found_at >= p_since and email is not null and not coalesce(do_not_contact, false)),
  q as (select c.id, company_email_routes(c.id) r from companies c where c.universe_status = 'QUALIFIED')
  select jsonb_build_object(
    'since', p_since,
    'companies_researched', (select count(distinct company_id) from email_research where researched_at >= p_since)
                            + (select count(distinct company_id) from ai_usage where workflow = '19' and "at" >= p_since
                                 and company_id not in (select company_id from email_research where researched_at >= p_since)),
    'email_research_runs', (select count(*) from email_research where researched_at >= p_since),
    'decision_makers_found', (select count(*) from nk where coalesce(first_name, '') <> '' and identity_status = 'CONFIRMED' and role_score(position) >= 3),
    'named_public_emails', (select count(*) from em where email_tier = 1 and email_state(email_status, email_source_url) in ('PUBLICLY_LISTED', 'VERIFIED')),
    'department_emails', (select count(*) from em where email_tier = 2 and email_state(email_status, email_source_url) in ('PUBLICLY_LISTED', 'VERIFIED')),
    'general_inboxes', (select count(*) from em where email_tier = 3 and email_state(email_status, email_source_url) in ('PUBLICLY_LISTED', 'VERIFIED')),
    -- SMTP verifications that happened in the window (a provider check on record), not rows merely touched
    'verified_emails', (select count(*) from contacts k where email_state(k.email_status, k.email_source_url, k.email_verification_provider) = 'VERIFIED'
                          and exists (select 1 from contact_email_verifications v where (v.contact_id = k.id or v.applied_contact_id = k.id)
                                        and lower(v.email) = lower(k.email) and v.created_at >= p_since)),
    'emails_still_missing', (select count(*) from q where (r->>'decision_maker')::boolean and not ((r->>'tier1_any')::boolean or (r->>'tier2')::boolean)),
    'linkedin_only', (select count(*) from q where (r->>'linkedin')::boolean and not ((r->>'tier1_any')::boolean or (r->>'tier2')::boolean or (r->>'tier3')::boolean)),
    'instagram_only', (select count(*) from q where (r->>'instagram')::boolean and not (r->>'linkedin')::boolean
                         and not ((r->>'tier1_any')::boolean or (r->>'tier2')::boolean or (r->>'tier3')::boolean)),
    'ready_email_drafts', (select count(*) from tasks where status in ('OPEN', 'IN_PROGRESS') and title like 'EMAIL READY%'),
    'ready_linkedin_drafts', (select count(*) from tasks where status in ('OPEN', 'IN_PROGRESS') and title like 'LINKEDIN MESSAGE READY%'),
    'outcomes', (select jsonb_object_agg(outcome, n) from (select outcome, count(*) n from email_research where researched_at >= p_since group by 1) s))
$$;
revoke all on function public.email_intel_report(timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------- backfill
-- Tier for every address already on file; found date = when it was recorded; provider where a verification is on record.
create or replace function public.ops_backfill_email_meta()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  alter table public.contacts disable trigger contacts_email_meta;
  update public.contacts k set
    email_tier = email_tier(k.email, coalesce(k.first_name, '') <> '' and coalesce(k.last_name, '') <> ''),
    email_found_at = coalesce(k.email_found_at, k.created_at),
    email_source_type = coalesce(k.email_source_type, case when coalesce(k.email_source_url, '') <> '' then coalesce(k.source_type, 'SEARCH_RESULT') end),
    email_verification_provider = coalesce(k.email_verification_provider,
      (select 'HUNTER' from contact_email_verifications v where (v.contact_id = k.id or v.applied_contact_id = k.id) and lower(v.email) = lower(k.email) limit 1),
      case when k.email_status = 'VERIFIED' and coalesce(k.source, '') ~* '(Department|^0[2-8] )' then 'HUNTER'
           when k.email_status = 'VERIFIED' then 'UNRECORDED' end)
   where k.email is not null;
  get diagnostics n = row_count;
  alter table public.contacts enable trigger contacts_email_meta;
  return n;
end $$;
revoke all on function public.ops_backfill_email_meta() from public, anon, authenticated;
select public.ops_backfill_email_meta();

-- ---------------------------------------------------------------- acceptance test snapshots
-- One company's contactability at a point in time: routes, best decision maker, best address per tier, LinkedIn, Instagram,
-- partnership model and outreach status. Stored before and after a test run in email_intel_tests.
create or replace function public.email_intel_snapshot(p_company uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (select c.*, contact_segment(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) seg
               from companies c where c.id = p_company),
  k as (select k.*, email_state(k.email_status, k.email_source_url, k.email_verification_provider) st from contacts k where k.company_id = p_company and not coalesce(k.do_not_contact, false)),
  usable as (select * from k where email is not null and st in ('VERIFIED', 'PUBLICLY_LISTED') and email_local_class(email) <> 'EXCLUDED')
  select jsonb_build_object(
    'routes', company_email_routes(p_company),
    'decision_maker', (select jsonb_build_object('name', k.first_name || ' ' || k.last_name, 'role', k.position, 'linkedin', k.linkedin, 'identity', k.identity_status)
                         from k, c where coalesce(k.first_name, '') <> '' and coalesce(k.last_name, '') <> '' and role_score(k.position) > 0
                        order by role_priority(k.position, c.seg) desc, (k.email is not null) desc limit 1),
    'direct_email', (select jsonb_build_object('email', email, 'name', first_name || ' ' || last_name, 'role', position, 'source', email_source_url,
                                               'source_type', email_source_type, 'state', st, 'provider', email_verification_provider)
                       from usable where email_tier = 1 order by role_score(position) desc, created_at limit 1),
    'department_email', (select jsonb_build_object('email', email, 'label', position, 'source', email_source_url, 'source_type', email_source_type, 'state', st)
                           from usable where email_tier = 2 order by created_at limit 1),
    'inbox_email', (select jsonb_build_object('email', email, 'label', position, 'source', email_source_url, 'source_type', email_source_type, 'state', st)
                      from usable where email_tier = 3 order by created_at limit 1),
    'linkedin', (select linkedin from k where coalesce(linkedin, '') ~* 'linkedin\.com/in/' and identity_status = 'CONFIRMED' order by role_score(position) desc limit 1),
    'instagram', (select nullif(instagram, '') from c),
    'website', (select website from c),
    'model', (select partnership_model_label(partnership_model) from c),
    'outreach', case when exists (select 1 from tasks t where t.company_id = p_company and t.status in ('OPEN', 'IN_PROGRESS') and t.title like 'EMAIL READY%') then 'EMAIL READY'
                     when exists (select 1 from tasks t where t.company_id = p_company and t.status in ('OPEN', 'IN_PROGRESS') and t.title like 'LINKEDIN MESSAGE READY%') then 'LINKEDIN READY'
                     else 'NOT DRAFTED' end,
    'at', now())
$$;
revoke all on function public.email_intel_snapshot(uuid) from public, anon, authenticated;

-- Start a test: record each company's state before, and point workflow 23 at the test set (email_gap_queue reads the tag).
create or replace function public.ops_email_intel_test_start(p_tag text, p_ids uuid[])
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into email_intel_tests (test_tag, company_id, before)
  select p_tag, id, email_intel_snapshot(id) from unnest(p_ids) id on conflict (test_tag, company_id) do nothing;
  get diagnostics n = row_count;
  insert into system_config (key, value, note, updated_at) values ('email_intel_test', jsonb_build_object('test_tag', p_tag), 'Workflow 23 works this test set before the live gap queue', now())
  on conflict (key) do update set value = excluded.value, note = excluded.note, updated_at = now();
  return n;
end $$;
revoke all on function public.ops_email_intel_test_start(text, uuid[]) from public, anon, authenticated;

-- Finish: record the state after and hand workflow 23 back to the live gap queue.
create or replace function public.ops_email_intel_test_finish(p_tag text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update email_intel_tests set after = email_intel_snapshot(company_id) where test_tag = p_tag;
  get diagnostics n = row_count;
  update system_config set value = '{}'::jsonb, updated_at = now() where key = 'email_intel_test' and value->>'test_tag' = p_tag;
  return n;
end $$;
revoke all on function public.ops_email_intel_test_finish(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- workflow 19 searches people by vertical
-- The enrichment queue carries the company's segment and its priority roles so the LinkedIn search asks for the right titles.
create or replace function public.enrichment_queue(p_limit int default 12)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (
    select c.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane,
           registrable_domain(c.website) domain
      from companies c
     where c.universe_status in ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING')
       and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'
       and coalesce(c.last_enriched_at, '-infinity'::timestamptz) < now() - interval '14 days'
       and coalesce(c.enrichment_attempts, 0) < 3
       and relationship_state(c.id) = 'COLD'
       and not exists (select 1 from contacts k where k.company_id = c.id and k.identity_status = 'CONFIRMED' and k.position is not null
                         and not coalesce(k.do_not_contact, false)
                         and (coalesce(k.linkedin, '') ~* 'linkedin\.com/in/' or (k.email is not null and k.email_status in ('VERIFIED', 'UNVERIFIED'))
                              or coalesce(k.instagram, '') <> '')))
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object(
      'company_id', c.id, 'company', c.name, 'website', c.website, 'domain', c.domain, 'country', c.country, 'city', c.city,
      'company_type', c.company_type, 'lane', c.lane, 'instagram', c.instagram,
      'segment', contact_segment(c.lane, c.company_type, c.notes), 'role_focus', to_jsonb(role_focus(contact_segment(c.lane, c.company_type, c.notes))),
      'has_email', exists (select 1 from contacts e where e.company_id = c.id and e.email is not null and not coalesce(e.do_not_contact, false)),
      'people', (select coalesce(jsonb_agg(jsonb_build_object('first_name', k.first_name, 'last_name', k.last_name, 'position', k.position,
                   'linkedin', k.linkedin, 'email', k.email, 'instagram', k.instagram)), '[]'::jsonb)
                   from contacts k where k.company_id = c.id and coalesce(k.first_name, k.last_name) is not null)
    ) order by s.rnk), '[]'::jsonb))
  -- weighted round robin so every agent's finds get routes each run: hospitality x3, weddings and brands x2, sports selective
  from (select l.*, row_number() over (order by l.rn_lane / case l.lane when 'PARTNERSHIPS' then 3 when 'WEDDINGS' then 2 when 'BRANDS' then 2
                                                                   when 'TRAVEL_PRIVATE' then 1.5 when 'SPORTS_PRIVATE' then 0.5 else 1 end,
                                        array_position(array['PARTNERSHIPS','WEDDINGS','BRANDS','TRAVEL_PRIVATE','CORPORATE','EGYPT_EVENTS','SPORTS_PRIVATE'], l.lane)) rnk
          from (select c.*, row_number() over (partition by c.lane order by (c.universe_status = 'QUALIFIED') desc,
                                               coalesce(c.universe_added_at, c.created_at) desc)::numeric rn_lane
                  from c) l) s
  join c on c.id = s.id
  where s.rnk <= greatest(1, least(coalesce(p_limit, 12), 40))
$$;
revoke all on function public.enrichment_queue(int) from public, anon, authenticated;

-- ---------------------------------------------------------------- Agents page wiring (patches 20261008600000 in place)
-- The enrichment agent becomes Email & Contact Intelligence: workflows 19 (people) and 23 (email-first research).
insert into public.agent_registry (key, name, kind, sort, scope, focus, workflows, schedule, every_minutes, max_gap_hours, run_logged, ai_workflows) values
 ('ENRICHMENT', 'Email & Contact Intelligence', 'SUPPORT', 11,
  'Finds the right person, the right email, the proof and the strongest commercial angle for every qualified company.',
  'Working the email gap queue (qualified, strong angle, person known, no usable email): official contact, team, partnerships and press pages, indexed addresses, Instagram bio; then naming decision makers by vertical',
  '{"19 -","23 -"}', '{"03:15","09:45","11:00","15:45","17:00","21:00","23:15"}', null, 14, false, '{"19","23"}')
on conflict (key) do update set name = excluded.name, scope = excluded.scope, focus = excluded.focus, workflows = excluded.workflows,
  schedule = excluded.schedule, ai_workflows = excluded.ai_workflows;

do $patch$
declare d text; n text;
begin
  -- last run: either enrichment workflow, or the email research log
  d := pg_get_functiondef('public.agent_last_run(text)'::regprocedure);
  n := replace(d, $a$    select max("at") into v_ts from ai_usage where workflow = '19';
    v_basis := 'Last company enriched';$a$,
               $a$    select max(x) into v_ts from (select max("at") x from ai_usage where workflow in ('19', '23') union all select max(researched_at) from email_research) s;
    v_basis := 'Last company researched for people or email';$a$);
  if n = d then raise exception 'agent_last_run patch did not apply'; end if;
  execute n;

  d := pg_get_functiondef('public.agents_snapshot()'::regprocedure);
  n := d;
  -- support stats for the email agent
  n := replace(n, $a$          'companies_enriched', (select count(distinct company_id) from ai_usage where workflow = '19' and "at" >= win.since),$a$,
                  $a$          'companies_enriched', (select count(distinct company_id) from ai_usage where workflow = '19' and "at" >= win.since),
          'companies_email_researched', (select count(distinct company_id) from email_research where researched_at >= win.since),
          'named_emails_found', (select coalesce(sum(tier1), 0) from email_research where researched_at >= win.since),
          'department_emails_found', (select coalesce(sum(tier2), 0) from email_research where researched_at >= win.since),
          'inbox_emails_found', (select coalesce(sum(tier3), 0) from email_research where researched_at >= win.since),
          'people_from_pages', (select coalesce(sum(people_found), 0) from email_research where researched_at >= win.since),
          'no_email_found', (select count(*) from companies where email_checked_at >= win.since and email_outcome = 'NO_EMAIL_FOUND'),
          'pages_read', (select coalesce(sum(pages_read), 0) from email_research where researched_at >= win.since),$a$);
  n := replace(n, $a$          'rate_limited', (select count(*) from ai_usage where workflow = '19' and "at" >= win.since and status = 'RATE_LIMITED'))$a$,
                  $a$          'rate_limited', (select count(*) from ai_usage where workflow in ('19', '23') and "at" >= win.since and status = 'RATE_LIMITED'))$a$);
  -- per-agent email funnel on every acquisition card
  n := replace(n, $a$        'today', coalesce((select s from stats where stats.key = f.key and w = 'today'),$a$,
                  $a$        'email_funnel', case when f.kind = 'ACQUISITION' then agent_email_funnel(f.key) end,
        'today', coalesce((select s from stats where stats.key = f.key and w = 'today'),$a$);
  -- the email gap queue and the 3-day email report, inside Email Opportunities
  n := replace(n, $a$    'radar', (select jsonb_agg(r order by r->>'at' desc) from ($a$,
                  $a$    'email_gaps', email_gap_list(60, null, true)->'items',
    'email_report', email_intel_report(),
    'radar', (select jsonb_agg(r order by r->>'at' desc) from ($a$);
  -- honest email state: provider-aware trust and the tier on every desk row
  n := replace(n, $a$          'trust', email_trust(k.email_status, k.email_source_url),$a$,
                  $a$          'trust', email_trust(k.email_status, k.email_source_url, k.email_verification_provider), 'tier', k.email_tier,$a$);
  -- feed: workflow 23 finds belong to the email agent, and a search with nothing public is reported
  n := replace(n, $a$'agent', case when k.source = 'Workflow 19 contact enrichment' then 'ENRICHMENT' else k.agent end, 'kind', 'PERSON'$a$,
                  $a$'agent', case when k.source in ('Workflow 19 contact enrichment', 'Workflow 23 email intelligence') then 'ENRICHMENT' else k.agent end, 'kind', 'PERSON'$a$);
  n := replace(n, $a$          select jsonb_build_object('at', c.created_at, 'agent', 'MEDIA', 'kind', 'CONCEPT', 'company_id', c.company_id,$a$,
                  $a$          select jsonb_build_object('at', er.researched_at, 'agent', 'ENRICHMENT', 'kind', 'NO_EMAIL', 'company_id', er.company_id,
                   'text', 'searched ' || (select name from companies where id = er.company_id) || ' (' || er.searches || ' searches, ' || er.pages_read
                           || ' official pages read): no public business email found')
            from email_research er where er.outcome = 'NO_EMAIL_FOUND' and er.researched_at > now() - interval '72 hours'
          union all
          select jsonb_build_object('at', c.created_at, 'agent', 'MEDIA', 'kind', 'CONCEPT', 'company_id', c.company_id,$a$);
  if strpos(n, 'companies_email_researched') = 0 or strpos(n, 'workflow in (''19'', ''23'') and "at" >= win.since and status') = 0
     or strpos(n, '''email_funnel''') = 0 or strpos(n, '''email_gaps''') = 0 or strpos(n, 'k.email_verification_provider), ''tier''') = 0
     or strpos(n, '''Workflow 23 email intelligence'') then ''ENRICHMENT''') = 0 or strpos(n, '''NO_EMAIL''') = 0 then
    raise exception 'agents_snapshot patch incomplete'; end if;
  execute n;

  d := pg_get_functiondef('public.agent_detail(text)'::regprocedure);
  n := replace(d, $a$(p_key = 'ENRICHMENT' and k.source = 'Workflow 19 contact enrichment')$a$,
                  $a$(p_key = 'ENRICHMENT' and k.source in ('Workflow 19 contact enrichment', 'Workflow 23 email intelligence'))$a$);
  n := replace(n, $a$email_trust(k.email_status, k.email_source_url)$a$, $a$email_trust(k.email_status, k.email_source_url, k.email_verification_provider)$a$);
  if n = d then raise exception 'agent_detail patch did not apply'; end if;
  execute n;
end $patch$;

-- ---------------------------------------------------------------- the planner goes email-first (Adam, 8 Oct 2026)
-- Hierarchy: 1 the named decision maker's own published / verified email; 2 the relevant department inbox for the attention of that
-- named person (tier 2, when no direct email is public); then their LinkedIn; then the company inbox for their attention when no
-- LinkedIn profile is on file; Instagram; LinkedIn by name; a company inbox when nobody is named. Companies with an email route rank
-- first. The inbox used is stored on the candidate (route_contact_id); the named person stays the contact.
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.commercial_director_plan(boolean,integer,boolean)'::regprocedure);
  n := d;
  n := replace(n, $a$             coalesce(k.email, ib.email) email, coalesce(k.email_status, ib.email_status) email_status, k.linkedin, k.instagram,
        case$a$, $a$             coalesce(k.email, ib.email) email, coalesce(k.email_status, ib.email_status) email_status, k.linkedin, k.instagram,
        case when k.id is not null and ib.id is not null
                  and not (email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and (k.email_status = 'VERIFIED' or (k.email_status = 'UNVERIFIED' and coalesce(k.email_source_url, '') <> '')))
                  and (ib.email_tier = 2 or coalesce(k.linkedin, '') !~* 'linkedin\.com/in/') then ib.id end route_id,
        case$a$);
  n := replace(n, $a$          when email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and (k.email_status = 'VERIFIED' or (k.email_status = 'UNVERIFIED' and coalesce(k.email_source_url, '') <> '')) then 'EMAIL'
          when coalesce(k.linkedin, '') ~* 'linkedin\.com/in/' then 'LINKEDIN'$a$,
                  $a$          when email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and (k.email_status = 'VERIFIED' or (k.email_status = 'UNVERIFIED' and coalesce(k.email_source_url, '') <> '')) then 'EMAIL'
          -- tier 2: the named decision maker has no public email but the relevant department inbox does: email it for their attention
          when k.id is not null and ib.email_tier = 2 then 'EMAIL'
          when coalesce(k.linkedin, '') ~* 'linkedin\.com/in/' then 'LINKEDIN'
          -- a named person with no LinkedIn profile on file: the company inbox for their attention beats a LinkedIn name search
          when k.id is not null and ib.id is not null then 'EMAIL'$a$);
  n := replace(n, $a$        row_number() over (partition by b.lane order by (k.id is not null) desc, (b.warm is not null) desc,$a$,
                  $a$        row_number() over (partition by b.lane order by (k.id is not null) desc, (b.warm is not null) desc,
          coalesce((email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and (k.email_status = 'VERIFIED' or coalesce(k.email_source_url, '') <> '')) or ib.email_tier = 2, false) desc,$a$);
  n := replace(n, $a$                           and not coalesce(i.do_not_contact, false) and coalesce(i.email_source_url, '') <> ''$a$,
                  $a$                           and not coalesce(i.do_not_contact, false) and coalesce(i.email_source_url, '') <> ''
                           and email_local_class(i.email) <> 'EXCLUDED' and coalesce(i.email_status, '') <> 'INVALID'$a$);
  n := replace(n, $a$                         order by (coalesce(i.position, '') || ' ' || i.email ~* '(partner|collab|sales|commercial|business|press|pr@|media|events?|wedding|brand|marketing)') desc,$a$,
                  $a$                         order by coalesce(i.email_tier = 2, false) desc, (coalesce(i.position, '') || ' ' || i.email ~* '(partner|collab|sales|commercial|business|press|pr@|media|events?|wedding|brand|marketing)') desc,$a$);
  n := replace(n, $a$      insert into outreach_candidates (run_date, dry_run, lane, company_id, contact_id, opportunity_id, channel, warm_route, why_now, evidence, angle)
      select current_date, p_dry_run, p.lane, p.company_id, p.contact_id, p.opp_id, p.channel, p.warm,$a$,
                  $a$      insert into outreach_candidates (run_date, dry_run, lane, company_id, contact_id, route_contact_id, opportunity_id, channel, warm_route, why_now, evidence, angle)
      select current_date, p_dry_run, p.lane, p.company_id, p.contact_id, case when p.channel = 'EMAIL' then p.route_id end, p.opp_id, p.channel, p.warm,$a$);
  n := replace(n, $a$      'email', case when oc.channel = 'EMAIL' then k.email end, 'email_status', case when oc.channel = 'EMAIL' then k.email_status end,$a$,
                  $a$      'email', case when oc.channel = 'EMAIL' then coalesce(ri.email, k.email) end, 'email_status', case when oc.channel = 'EMAIL' then coalesce(ri.email_status, k.email_status) end,
      'via_inbox', ri.email is not null, 'inbox_label', ri.position,$a$);
  n := replace(n, $a$  from outreach_candidates oc join companies c on c.id = oc.company_id left join contacts k on k.id = oc.contact_id
  where oc.run_date = current_date and oc.dry_run = p_dry_run;$a$,
                  $a$  from outreach_candidates oc join companies c on c.id = oc.company_id left join contacts k on k.id = oc.contact_id
       left join contacts ri on ri.id = oc.route_contact_id
  where oc.run_date = current_date and oc.dry_run = p_dry_run;$a$);
  if strpos(n, ' route_id,') = 0 or strpos(n, 'ib.email_tier = 2 then ''EMAIL''') = 0 or strpos(n, 'or ib.email_tier = 2, false) desc') = 0
     or strpos(n, 'email_local_class(i.email) <> ''EXCLUDED''') = 0 or strpos(n, 'coalesce(i.email_tier = 2, false) desc') = 0
     or (length(n) - length(replace(n, 'case when p.channel = ''EMAIL'' then p.route_id end', ''))) / length('case when p.channel = ''EMAIL'' then p.route_id end') <> 2
     or strpos(n, '''via_inbox''') = 0 or strpos(n, 'left join contacts ri on ri.id = oc.route_contact_id') = 0 then
    raise exception 'planner patch incomplete'; end if;
  execute n;

  d := pg_get_functiondef('public.outreach_candidate_save(jsonb)'::regprocedure);
  n := d;
  n := replace(n, $a$declare oc outreach_candidates%rowtype; c companies%rowtype; k contacts%rowtype;$a$,
                  $a$declare oc outreach_candidates%rowtype; c companies%rowtype; k contacts%rowtype; ri contacts%rowtype;$a$);
  n := replace(n, $a$  select * into k from contacts where id = oc.contact_id;$a$,
                  $a$  select * into k from contacts where id = oc.contact_id;
  select * into ri from contacts where id = oc.route_contact_id;$a$);
  n := replace(n, $a$            case when oc.channel = 'EMAIL' and k.email is not null then 'To: ' || k.email ||
                 case when k.email_status = 'VERIFIED' then ' (verified)' else ' (publicly listed at ' || coalesce(k.email_source_url, 'source on file') || '; not verified)' end || chr(10)$a$,
                  $a$            case when oc.channel = 'EMAIL' and ri.email is not null then 'To: ' || ri.email || ' (' || coalesce(ri.position, 'company inbox')
                      || coalesce(', for the attention of ' || nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), '') || coalesce(', ' || k.position, ''), '') || ')'
                      || case when email_state(ri.email_status, ri.email_source_url, ri.email_verification_provider) = 'VERIFIED' then ' · SMTP-verified'
                              else ' · publicly listed at ' || coalesce(ri.email_source_url, 'source on file') || '; not SMTP-verified' end || chr(10)
                 when oc.channel = 'EMAIL' and k.email is not null then 'To: ' || k.email ||
                 case when email_state(k.email_status, k.email_source_url, k.email_verification_provider) = 'VERIFIED' then ' (SMTP-verified)' else ' (publicly listed at ' || coalesce(k.email_source_url, 'source on file') || '; not SMTP-verified)' end || chr(10)$a$);
  if strpos(n, 'ri contacts%rowtype') = 0 or strpos(n, 'select * into ri from contacts') = 0 or strpos(n, 'for the attention of') = 0 then
    raise exception 'candidate save patch incomplete'; end if;
  execute n;
end $patch$;
