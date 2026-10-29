-- Instagram contact intelligence (Adam, 29 Oct 2026, evening): Firecrawl is connected with an indexed Instagram source.
-- Contact order for every qualified or promising account:
--   PUBLIC INSTAGRAM / PROFILE → OFFICIAL WEBSITE / LINK-IN-BIO → RIGHT PERSON → CLAY → HUNTER (only when a direct email is
--   still missing or needs verification).
-- A business email an account publishes itself on its Instagram profile is saved with its evidence: a shared inbox becomes an
-- OFFICIAL_PUBLISHED_INBOX, a named person's own address a PUBLIC_NAMED_EMAIL. Neither is ever labelled VERIFIED; Adam approves
-- every email; nothing sends automatically. Hunter is never spent rediscovering an address that is already published.
-- No new agent: the lookups run inside Contact Intelligence (workflow 23) and the daily check; prospects found by bio search
-- go through the discovery departments' existing qualification.

-- 1. Capability registry ----------------------------------------------------------------------------------------------
insert into public.tool_capabilities (capability, tool, status, strength, cost, rule, used_by, note, checked_at) values
  ('PUBLIC_WEB_RESEARCH', 'Firecrawl (scrape and search)', 'AVAILABLE', 4, 'Firecrawl credits, about 1 a page',
   'Official website and link-in-bio pages; evidence with URL and date', 'Discovery, Contact Intelligence', 'Connected 29 Oct', now()),
  ('INSTAGRAM_PROFILE_SEARCH', 'Firecrawl Instagram index', 'AVAILABLE', 5,
   '35 / 50 / 65 credits a non-empty call (basic / default / full), up to 100 profiles a call; an empty result is free',
   'Bio and name search in the priority verticals; distribution power and project generation first, follower count only as secondary evidence',
   'Discovery (Instagram-first prospecting)', 'An index, not a live feed: a missing profile proves nothing', now()),
  ('INSTAGRAM_PROFILE_LOOKUP', 'Firecrawl Instagram index', 'AVAILABLE', 5, '65 credits a profile (full detail)',
   'Qualified or promising targets only: it costs materially more than ordinary web search', 'Contact Intelligence',
   'Exact handle search returns one profile', now()),
  ('INSTAGRAM_POST_SEARCH', 'Firecrawl Instagram index', 'AVAILABLE', 4, '35 / 50 / 65 credits a non-empty call, up to 100 posts',
   'Campaign, trip, event and launch signals (why now); never contact data', 'Discovery', null, now()),
  ('INSTAGRAM_PUBLIC_CONTACT', 'Firecrawl Instagram index', 'AVAILABLE', 5, 'Included in a full profile search or lookup',
   'An email the account publishes itself: OFFICIAL_PUBLISHED_INBOX (a shared inbox) or PUBLIC_NAMED_EMAIL (a named person). Never VERIFIED; never rediscovered with Hunter',
   'Contact Intelligence', null, now())
on conflict (capability, tool) do update set status = excluded.status, strength = excluded.strength, cost = excluded.cost,
  rule = excluded.rule, used_by = excluded.used_by, note = excluded.note, checked_at = now();

update public.tool_capabilities set status = 'AVAILABLE', strength = 4, rule = 'Website research and the Instagram index; credit-aware',
       note = 'Connected 29 Oct with the Instagram index', checked_at = now()
 where capability = 'COMPANY_DISCOVERY' and tool = 'Firecrawl';
update public.tool_capabilities set status = 'LIMITED', checked_at = now(),
       note = 'Connected 29 Oct: used in the daily check for right-person research (step 4 of the contact order), not inside n8n'
 where tool = 'Clay';
update public.tool_capabilities set checked_at = now(),
       rule = 'Last step of the contact order: only when a direct email is still missing or needs verification; never to rediscover a published address'
 where tool like 'Hunter%';

insert into public.system_config (key, value, note) values ('contact_order', jsonb_build_object(
    'steps', jsonb_build_array('PUBLIC_INSTAGRAM_PROFILE', 'OFFICIAL_WEBSITE_OR_LINK_IN_BIO', 'RIGHT_PERSON_RESEARCH', 'CLAY', 'HUNTER'),
    'hunter_only_when', 'A direct email is still missing or needs verification',
    'right_person_roles', jsonb_build_array('Founder', 'Co-Founder', 'CEO', 'Managing Director', 'Creative Director', 'Events Director',
      'Partnerships Director', 'Head of Experiences', 'Membership Director', 'Brand Partnerships', 'Commercial Director',
      'Client Services Director', 'Production Director'),
    'instagram', jsonb_build_object('daily_credit_budget', 650, 'lookup_projection', 'full', 'refresh_after_days', 90,
      'note', 'About 10 full lookups a day until Adam sets a different budget')),
  'Adam, 29 Oct 2026: Instagram first, Hunter last.')
on conflict (key) do update set value = excluded.value, note = excluded.note, updated_at = now();

-- 2. Public profiles --------------------------------------------------------------------------------------------------
create table if not exists public.public_profiles (
  id uuid primary key default gen_random_uuid(),
  platform text not null default 'instagram',
  handle text not null,
  profile_url text,
  display_name text,
  bio text,
  bio_link text,
  public_email text,
  email_class text check (email_class in ('OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL', 'NOT_USABLE')),
  followers integer,
  is_verified boolean,
  is_private boolean,
  observed_at timestamptz not null default now(),
  source text not null default 'FIRECRAWL_INSTAGRAM_INDEX',
  projection text,
  credits integer,
  company_id uuid references public.companies(id) on delete set null,
  contact_id uuid references public.contacts(id) on delete set null,
  person_name text,
  person_role text,
  lane text,
  status text not null default 'OBSERVED' check (status in ('OBSERVED', 'MATCHED', 'PROSPECT', 'QUALIFIED', 'REJECTED')),
  confidence text check (confidence in ('HIGH', 'MEDIUM', 'LOW')),
  confidence_reason text,
  found_by text,
  raw jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (platform, handle)
);
alter table public.public_profiles enable row level security;
create index if not exists public_profiles_company on public.public_profiles (company_id);
create index if not exists public_profiles_email on public.public_profiles (lower(public_email)) where public_email is not null;
create index if not exists public_profiles_status on public.public_profiles (status, observed_at desc);

-- Credits spent, per call, so the daily budget is measured rather than assumed.
create table if not exists public.public_profile_calls (
  id bigserial primary key,
  called_at timestamptz not null default now(),
  purpose text not null check (purpose in ('LOOKUP', 'PROSPECT_SEARCH', 'POST_SEARCH')),
  query text,
  company_id uuid,
  results integer,
  credits integer not null default 0,
  caller text,
  error text
);
alter table public.public_profile_calls enable row level security;

create or replace function public.ig_handle(p text) returns text language sql immutable as $$
  select nullif(lower(regexp_replace(regexp_replace(regexp_replace(btrim(coalesce(p, '')), '^https?://(www\.)?instagram\.com/', '', 'i'),
         '[/?#].*$', ''), '^@', '')), '')
$$;

-- Credits used today by the Instagram index, and what the budget still allows.
create or replace function public.instagram_budget() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('budget', b, 'used_today', u, 'left', greatest(0, b - u))
    from (select coalesce((select (value->'instagram'->>'daily_credit_budget')::int from system_config where key = 'contact_order'), 650) b,
                 coalesce((select sum(credits) from public_profile_calls where called_at >= date_trunc('day', now() at time zone 'Africa/Cairo') at time zone 'Africa/Cairo'), 0)::int u) x
$$;
revoke all on function public.instagram_budget() from public, anon, authenticated;

-- Qualified or promising companies to look up on Instagram, strongest first: cold, spend allowed, no usable email route yet,
-- a known handle, and no observation in the refresh window. p_limit is a batch size; the credit budget is the real limit.
create or replace function public.instagram_lookup_queue(p_limit int default 10) returns jsonb
language plpgsql stable security definer set search_path = public set statement_timeout = '55s' as $$
declare v_days int := coalesce((select (value->'instagram'->>'refresh_after_days')::int from system_config where key = 'contact_order'), 90);
        v_left int := (instagram_budget()->>'left')::int; v_n int;
begin
  v_n := least(greatest(coalesce(p_limit, 10), 0), floor(v_left / 65.0)::int);
  if v_n <= 0 then return jsonb_build_object('items', '[]'::jsonb, 'budget', instagram_budget()); end if;
  return jsonb_build_object('budget', instagram_budget(), 'items', coalesce((
    select jsonb_agg(jsonb_build_object('company_id', q.id, 'company', q.name, 'handle', q.h,
             'url', 'https://www.instagram.com/' || q.h || '/') order by q.rk desc)
      from (select c.id, c.name, ig_handle(c.instagram) h,
                   coalesce((select max(coalesce(destination_egypt_score(o.egypt, 0, 0), o.priority, 0)) from opportunities o
                              where o.company_id = c.id and o.status not in ('WON', 'LOST', 'ARCHIVED')), 0) rk
              from companies c
             where c.universe_status = 'QUALIFIED' and ig_handle(c.instagram) ~ '^[a-z0-9._]{2,30}$'
               and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'
               and coalesce(c.outreach_hold_until, '-infinity'::timestamptz) < now()
               and relationship_state(c.id) = 'COLD' and outreach_spend_ok(c.id)
               and not exists (select 1 from public_profiles p where p.handle = ig_handle(c.instagram) and p.observed_at > now() - make_interval(days => v_days))
               and coalesce(company_email_state(c.id)->>'state', 'NO_PERSON')
                   not in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL')
             order by 4 desc limit v_n) q), '[]'::jsonb));
end $$;
revoke all on function public.instagram_lookup_queue(int) from public, anon, authenticated;

-- Record one profile from the Instagram index (lookup or search). Matches the account (handle on the company, or a bio link
-- on the company's own domain), classifies a published email and saves it where the route logic reads it. A profile that
-- matches no company is kept as a PROSPECT for the discovery departments when p_prospect_lane is given.
create or replace function public.public_profile_record(p jsonb, p_found_by text default 'CONTACT_INTELLIGENCE',
                                                        p_prospect_lane text default null, p_company uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_h text := ig_handle(coalesce(p->>'handle', p->>'profileUrl')); v_email text := nullif(lower(btrim(coalesce(p->>'publicEmail', ''))), '');
        v_link text := nullif(btrim(coalesce(p->>'bioLink', '')), ''); v_co companies%rowtype; v_dom text; v_link_dom text; v_mail_dom text;
        v_class text; v_conf text; v_why text; v_contact uuid; v_status text; v_id uuid; v_local text; v_person text; v_role text;
begin
  if v_h is null or v_h !~ '^[a-z0-9._]{2,30}$' then return jsonb_build_object('ok', false, 'reason', 'NO_HANDLE'); end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then v_email := null; end if;
  v_link_dom := case when v_link ~* '^https?://' then registrable_domain(v_link) end;
  if v_link_dom ~* '(linktr\.ee|beacons\.ai|instagram\.com|facebook\.com|tiktok\.com|youtube\.com|youtu\.be|wa\.me|whatsapp|bit\.ly|linkin\.bio|lnk\.bio|campsite\.bio|later\.com|cntraveller|vogue|harpersbazaar)' then
    v_link_dom := null; end if;
  -- the account: an explicit company, else the company that already holds this handle, else one whose website is the bio link
  if p_company is not null then select * into v_co from companies where id = p_company; end if;
  if v_co.id is null then select * into v_co from companies where ig_handle(instagram) = v_h order by (universe_status = 'QUALIFIED') desc, created_at limit 1; end if;
  if v_co.id is null and v_link_dom is not null then
    select * into v_co from companies where registrable_domain(website) = v_link_dom order by (universe_status = 'QUALIFIED') desc, created_at limit 1;
  end if;
  v_dom := registrable_domain(v_co.website);
  v_mail_dom := case when v_email is not null then registrable_domain(split_part(v_email, '@', 2)) end;
  -- how sure we are that this is the company's own account
  v_conf := case when v_co.id is null then null
                 when coalesce((p->>'isVerified')::boolean, false) or (v_link_dom is not null and v_link_dom = v_dom) then 'HIGH'
                 when ig_handle(v_co.instagram) = v_h then 'MEDIUM' else 'LOW' end;
  v_why := case when v_co.id is null then 'No CRM company matches this account yet'
                else concat_ws('; ', case when coalesce((p->>'isVerified')::boolean, false) then 'verified Instagram account' end,
                               case when v_link_dom is not null and v_link_dom = v_dom then 'bio link is the company website' end,
                               case when ig_handle(v_co.instagram) = v_h then 'handle already on the company record' end) end;
  -- the published email: only on the company's own domain, and only from an account we are sure of
  if v_email is not null then
    v_local := email_local_class(v_email);
    v_class := case when v_co.id is null or v_conf = 'LOW' or v_mail_dom is distinct from coalesce(v_dom, v_link_dom) or v_local = 'EXCLUDED' then 'NOT_USABLE'
                    when v_local = 'PERSONAL' then 'PUBLIC_NAMED_EMAIL' else 'OFFICIAL_PUBLISHED_INBOX' end;
  end if;
  v_status := case when v_co.id is not null then 'MATCHED' when p_prospect_lane is not null then 'PROSPECT' else 'OBSERVED' end;

  if v_class = 'PUBLIC_NAMED_EMAIL' then
    -- the named person: an existing contact with this address, else the confirmed decision maker whose first name is the local part
    select id into v_contact from contacts where company_id = v_co.id and lower(btrim(coalesce(email, ''))) = v_email limit 1;
    if v_contact is null then
      select id into v_contact from contacts
       where company_id = v_co.id and coalesce(btrim(email), '') = '' and not coalesce(do_not_contact, false)
         and lower(coalesce(first_name, '')) = split_part(split_part(v_email, '@', 1), '.', 1)
       order by (identity_status = 'CONFIRMED') desc, role_score(position) desc limit 1;
      if v_contact is not null then
        update contacts set email = v_email, email_status = 'UNVERIFIED', email_source_url = 'https://www.instagram.com/' || v_h || '/',
               email_found_at = now(), email_source_type = 'INSTAGRAM_PROFILE', route_type = coalesce(route_type, 'PERSON_EMAIL'),
               notes = coalesce(notes, '') || chr(10) || 'Email published on the company''s Instagram profile @' || v_h || ', seen ' || to_char(now(), 'DD Mon YYYY') || '.'
         where id = v_contact;
      end if;
    end if;
    if v_contact is not null then
      select concat_ws(' ', first_name, last_name), position into v_person, v_role from contacts where id = v_contact;
    end if;
    if v_contact is null then v_class := 'NOT_USABLE'; v_why := concat_ws('; ', v_why, 'named address with no matching person: research the person first'); end if;
  elsif v_class = 'OFFICIAL_PUBLISHED_INBOX' then
    select id into v_contact from contacts where company_id = v_co.id and lower(btrim(coalesce(email, ''))) = v_email limit 1;
    if v_contact is null then
      insert into contacts (company_id, position, email, email_status, email_source_url, email_found_at, email_source_type, source, source_url, source_type,
                            route_type, email_tier, relationship_owner, status, confidence, notes)
      values (v_co.id, 'Company inbox (Instagram)', v_email, 'UNVERIFIED', 'https://www.instagram.com/' || v_h || '/', now(), 'INSTAGRAM_PROFILE',
              'Instagram profile (Firecrawl index)', 'https://www.instagram.com/' || v_h || '/', 'INSTAGRAM_PROFILE', 'COMPANY_INBOX',
              case when email_local_class(v_email) = 'DEPARTMENT' then 2 end, 'Adam Elshazly', 'NEW', 60,
              'Inbox published on the company''s own Instagram profile @' || v_h || ' (' || coalesce(v_why, '') || '), seen ' || to_char(now(), 'DD Mon YYYY') || '. Not checked by a provider.')
      returning id into v_contact;
    end if;
    insert into email_official_inboxes (contact_id, company_id, email, source_url, source_domain, company_domain, found_at, rule)
    values (v_contact, v_co.id, v_email, 'https://www.instagram.com/' || v_h || '/', 'instagram.com', v_dom, now(),
            'Adam, 29 Oct 2026: an inbox the company publishes on its own Instagram profile, like its own website. Not VERIFIED; Adam approves every email; nothing sends automatically.')
    on conflict (contact_id) do update set revoked_at = null, revoked_reason = null
      where email_official_inboxes.email = excluded.email and email_official_inboxes.revoked_reason is distinct from 'Address changed, do-not-contact, or the verification provider did not confirm it';
  end if;

  if v_co.id is not null and coalesce(v_co.instagram, '') = '' and v_conf in ('HIGH', 'MEDIUM') then
    update companies set instagram = v_h where id = v_co.id;
  end if;

  insert into public_profiles (platform, handle, profile_url, display_name, bio, bio_link, public_email, email_class, followers, is_verified, is_private,
                               observed_at, projection, credits, company_id, contact_id, person_name, person_role, lane, status, confidence, confidence_reason, found_by, raw)
  values ('instagram', v_h, coalesce(p->>'profileUrl', 'https://www.instagram.com/' || v_h || '/'), p->>'displayName', left(p->>'bio', 1000), v_link, v_email, v_class,
          nullif(p->>'followersCount', '')::numeric::int, (p->>'isVerified')::boolean, (p->>'isPrivate')::boolean, now(), p->>'_projection',
          nullif(p->>'_credits', '')::int, v_co.id, v_contact, v_person, v_role, coalesce(p_prospect_lane, company_lane(v_co.acquisition_lane, v_co.prospect_segment, v_co.vertical_override, v_co.company_type)),
          v_status, v_conf, v_why, p_found_by, p - 'profilePictureUrl')
  on conflict (platform, handle) do update set
    profile_url = excluded.profile_url, display_name = excluded.display_name, bio = excluded.bio, bio_link = excluded.bio_link,
    public_email = coalesce(excluded.public_email, public_profiles.public_email), email_class = coalesce(excluded.email_class, public_profiles.email_class),
    followers = excluded.followers, is_verified = excluded.is_verified, is_private = excluded.is_private, observed_at = now(),
    projection = coalesce(excluded.projection, public_profiles.projection), company_id = coalesce(excluded.company_id, public_profiles.company_id),
    contact_id = coalesce(excluded.contact_id, public_profiles.contact_id), person_name = coalesce(excluded.person_name, public_profiles.person_name),
    person_role = coalesce(excluded.person_role, public_profiles.person_role), lane = coalesce(public_profiles.lane, excluded.lane),
    status = case when public_profiles.status in ('QUALIFIED', 'REJECTED') and excluded.status = 'PROSPECT' then public_profiles.status else excluded.status end,
    confidence = excluded.confidence, confidence_reason = excluded.confidence_reason, raw = excluded.raw, updated_at = now()
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'handle', v_h, 'company_id', v_co.id, 'status', v_status, 'email', v_email,
                            'email_class', v_class, 'contact_id', v_contact, 'confidence', v_conf);
end $$;
revoke all on function public.public_profile_record(jsonb, text, text, uuid) from public, anon, authenticated;

-- One call to the Instagram index, with what it cost (the n8n branch and the daily check both log here).
create or replace function public.public_profile_call_log(p_purpose text, p_query text, p_results int, p_credits int,
                                                          p_caller text default 'n8n', p_company uuid default null, p_error text default null)
returns void language sql volatile security definer set search_path = public as $$
  insert into public_profile_calls (purpose, query, company_id, results, credits, caller, error)
  values (p_purpose, left(p_query, 300), p_company, p_results, coalesce(p_credits, 0), p_caller, left(p_error, 300));
$$;
revoke all on function public.public_profile_call_log(text, text, int, int, text, uuid, text) from public, anon, authenticated;

-- 3. The route: a person's own address, published on the company's own Instagram, is PUBLIC_NAMED_EMAIL --------------------
-- Checked straight after a provider-verified address and before "waiting for verification", so Hunter is not spent on it.
-- A provider result other than valid revokes it, exactly as for an official inbox.
do $patch$
declare src text := pg_get_functiondef('public.contact_email_route(uuid)'::regprocedure);
  a1 text := $a$  -- 2 a verified department inbox for their attention$a$;
  b1 text := $a$  -- 1b their own address, published by them on the company's own Instagram profile (29 Oct): usable, never labelled VERIFIED
  if coalesce(btrim(k.email), '') <> '' and email_local_class(k.email) = 'PERSONAL'
     and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(k.email)) and v.provider_status is not null and v.provider_status <> 'valid') then
    select * into v_pp from public_profiles pp
     where lower(pp.public_email) = lower(btrim(k.email)) and pp.email_class = 'PUBLIC_NAMED_EMAIL' and pp.company_id = k.company_id
     order by pp.observed_at desc limit 1;
    if v_pp.id is not null then
      return jsonb_build_object('state', 'PUBLIC_NAMED_EMAIL', 'email', lower(btrim(k.email)), 'source_url', v_pp.profile_url, 'found_at', v_pp.observed_at,
                                'label', 'Their own address, published on the company''s Instagram (@' || v_pp.handle || ', seen '
                                         || to_char(v_pp.observed_at at time zone 'Africa/Cairo', 'DD Mon') || ')');
    end if;
  end if;
  -- 2 a verified department inbox for their attention$a$;
  a2 text := $a$        v_dom text; v_dom_set boolean := false;$a$;
  b2 text := $a$        v_dom text; v_dom_set boolean := false; v_pp public_profiles%rowtype;$a$;
begin
  if strpos(src, 'PUBLIC_NAMED_EMAIL') > 0 then return; end if;
  if strpos(src, a1) = 0 or strpos(src, a2) = 0 then raise exception 'contact_email_route changed: anchors not found'; end if;
  execute replace(replace(src, a1, b1), a2, b2);
end $patch$;

-- The official inbox label says where it was published.
create or replace function public.official_inbox_route(p_inbox uuid, p_name text, p_general boolean)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('state', 'OFFICIAL_PUBLISHED_INBOX', 'email', o.email, 'inbox_id', o.contact_id, 'general', p_general,
           'source_url', o.source_url, 'found_at', o.found_at,
           'label', 'Official published ' || case when p_general then 'inbox' else lower(coalesce(nullif(i.position, ''), 'department inbox')) end
                    || case when o.source_domain = 'instagram.com' then ' (company Instagram)' else ' (company website)' end
                    || coalesce(', for the attention of ' || p_name, ', for their attention'))
    from email_official_inboxes o join contacts i on i.id = o.contact_id where o.contact_id = p_inbox;
$$;

-- company_email_state: a self-published named address ranks with a verified department inbox.
do $patch$
declare src text := pg_get_functiondef('public.company_email_state(uuid)'::regprocedure);
  a text := $a$when dm.r->>'state' = 'VERIFIED_INBOX' then 1$a$;
  b text := $a$when dm.r->>'state' in ('VERIFIED_INBOX', 'PUBLIC_NAMED_EMAIL') then 1$a$;
begin
  if strpos(src, 'PUBLIC_NAMED_EMAIL') > 0 then return; end if;
  if strpos(src, a) = 0 then raise exception 'company_email_state changed: anchor not found'; end if;
  execute replace(src, a, b);
end $patch$;

-- Everywhere an email route counts as ready, PUBLIC_NAMED_EMAIL counts too.
do $patch$
declare f text; src text; a text := $a$'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX'$a$; b text := $a$'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL'$a$;
begin
  foreach f in array array['cold_route_sweep(boolean)', 'commercial_director_plan(boolean, integer, boolean)', 'destination_egypt_mission()',
                           'director_channel_health(jsonb)', 'hq_command()', 'hq_work_order(text, text, text, text, integer, date, text)',
                           'warm_route_check(uuid, uuid)', 'work_order_eval(uuid)'] loop
    if to_regprocedure('public.' || f) is null then raise exception 'signature changed: %', f; end if;
    src := pg_get_functiondef(('public.' || f)::regprocedure);
    if strpos(src, 'PUBLIC_NAMED_EMAIL') > 0 or strpos(src, a) = 0 then continue; end if;
    src := replace(src, a, b);
    -- single-state counts and scores: a self-published address sits with the published inboxes
    src := regexp_replace(src, '(\m[a-z]+\.st(ate)?) = ''OFFICIAL_PUBLISHED_INBOX''', '\1 in (''OFFICIAL_PUBLISHED_INBOX'', ''PUBLIC_NAMED_EMAIL'')', 'g');
    execute src;
  end loop;
  -- acquisition_health counts published routes in one bucket (EMAIL READY = verified + verified general + published)
  src := pg_get_functiondef('public.acquisition_health()'::regprocedure);
  if strpos(src, 'PUBLIC_NAMED_EMAIL') = 0 then
    if strpos(src, $a$w.state = 'OFFICIAL_PUBLISHED_INBOX') official_inbox$a$) = 0 then raise exception 'acquisition_health changed: anchor not found'; end if;
    execute replace(src, $a$w.state = 'OFFICIAL_PUBLISHED_INBOX') official_inbox$a$, $a$w.state in ('OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL')) official_inbox$a$);
  end if;
end $patch$;

-- The outreach desk: an EMAIL READY item to a self-published address goes to Needs review, labelled as such.
do $patch$
declare src text := pg_get_functiondef('public.outreach_desk()'::regprocedure);
  a1 text := $a$= lower(btrim(r.email))) r_official,$a$;
  b1 text := $a$= lower(btrim(r.email)))
             or exists (select 1 from public_profiles pp where lower(pp.public_email) = lower(btrim(r.email)) and pp.email_class = 'PUBLIC_NAMED_EMAIL' and pp.company_id = r.company_id) r_official,$a$;
  a2 text := $a$case when b.r_official then 'OFFICIAL_PUBLISHED_INBOX' else b.r_state end$a$;
  b2 text := $a$case when b.r_official and email_local_class(b.r_email) = 'PERSONAL' then 'PUBLIC_NAMED_EMAIL' when b.r_official then 'OFFICIAL_PUBLISHED_INBOX' else b.r_state end$a$;
begin
  if strpos(src, 'PUBLIC_NAMED_EMAIL') > 0 then return; end if;
  if strpos(src, a1) = 0 or strpos(src, a2) = 0 then raise exception 'outreach_desk changed: anchors not found'; end if;
  execute replace(replace(src, a1, b1), a2, b2);
end $patch$;

-- 4. One batch from the Instagram index, saved in one call (workflow 23 and the daily check use the same functions) --------
-- p = {companies: [{company_id, handle}], response: <Firecrawl /v2/scrape answer with an alexandria array>, caller}
create or replace function public.instagram_lookup_save(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare i int := 0; r jsonb; c jsonb; prof jsonb; v_rec jsonb; v_found int := 0; v_emails int := 0; v_err text;
        v_calls jsonb := coalesce(p->'response'->'data'->'alexandria', '[]'::jsonb);
begin
  v_err := coalesce(p->'response'->>'error', case when coalesce((p->'response'->>'success')::boolean, true) = false then 'Firecrawl call failed' end);
  if v_err is not null or jsonb_typeof(v_calls) <> 'array' then
    perform public_profile_call_log('LOOKUP', 'batch', 0, 0, coalesce(p->>'caller', 'n8n'), null, coalesce(v_err, 'No results array'));
    return jsonb_build_object('ok', false, 'error', coalesce(v_err, 'No results array'));
  end if;
  for r in select * from jsonb_array_elements(v_calls) loop
    c := p->'companies'->i; i := i + 1;
    prof := r->'data'->'data'->0;
    perform public_profile_call_log('LOOKUP', c->>'handle', case when prof is null then 0 else 1 end,
                                    case when prof is null then 0 else 65 end, coalesce(p->>'caller', 'n8n'),
                                    nullif(c->>'company_id', '')::uuid, r->'error'->>'message');
    if prof is not null then
      v_rec := public_profile_record(prof || jsonb_build_object('_projection', 'full', '_credits', 65), 'CONTACT_INTELLIGENCE', null, nullif(c->>'company_id', '')::uuid);
      v_found := v_found + 1;
      if v_rec->>'email_class' in ('OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL') then v_emails := v_emails + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'looked_up', i, 'found', v_found, 'emails', v_emails, 'budget', instagram_budget());
end $$;
revoke all on function public.instagram_lookup_save(jsonb) from public, anon, authenticated;

-- Instagram-first prospecting: a rotating bank of bio searches across the priority verticals (each search returns up to 100
-- public profiles with their published email for 65 credits). Follower count is secondary evidence only.
update public.system_config set value = jsonb_set(value, '{instagram,prospect_searches_per_day}', '4'::jsonb)
  || jsonb_build_object('prospect_bank', jsonb_build_array(
    jsonb_build_object('q', 'destination wedding planner', 'lane', 'WEDDINGS'), jsonb_build_object('q', 'brand experience agency', 'lane', 'BRANDS'),
    jsonb_build_object('q', 'private members club', 'lane', 'PARTNERSHIPS'), jsonb_build_object('q', 'luxury event planner', 'lane', 'WEDDINGS'),
    jsonb_build_object('q', 'experiential agency', 'lane', 'BRANDS'), jsonb_build_object('q', 'luxury travel club', 'lane', 'TRAVEL_PRIVATE'),
    jsonb_build_object('q', 'founders club', 'lane', 'PARTNERSHIPS'), jsonb_build_object('q', 'influencer marketing agency', 'lane', 'BRANDS'),
    jsonb_build_object('q', 'luxury wedding planner', 'lane', 'WEDDINGS'), jsonb_build_object('q', 'private concierge', 'lane', 'TRAVEL_PRIVATE'),
    jsonb_build_object('q', 'PR agency luxury', 'lane', 'BRANDS'), jsonb_build_object('q', 'event production', 'lane', 'WEDDINGS'),
    jsonb_build_object('q', 'creator trips', 'lane', 'BRANDS'), jsonb_build_object('q', 'VIP hospitality', 'lane', 'TRAVEL_PRIVATE'),
    jsonb_build_object('q', 'brand activations', 'lane', 'BRANDS'), jsonb_build_object('q', 'corporate retreats', 'lane', 'CORPORATE'),
    jsonb_build_object('q', 'creative director', 'lane', 'BRANDS'), jsonb_build_object('q', 'lifestyle club', 'lane', 'PARTNERSHIPS'),
    jsonb_build_object('q', 'fashion marketing', 'lane', 'BRANDS'), jsonb_build_object('q', 'incentive travel', 'lane', 'CORPORATE'),
    jsonb_build_object('q', 'beauty marketing', 'lane', 'BRANDS'), jsonb_build_object('q', 'luxury travel advisor', 'lane', 'TRAVEL_PRIVATE'),
    jsonb_build_object('q', 'talent management', 'lane', 'SPORTS_PRIVATE'), jsonb_build_object('q', 'private events', 'lane', 'WEDDINGS'),
    jsonb_build_object('q', 'event producer', 'lane', 'BRANDS'), jsonb_build_object('q', 'family office', 'lane', 'CORPORATE'),
    jsonb_build_object('q', 'production company', 'lane', 'BRANDS'), jsonb_build_object('q', 'luxury lifestyle', 'lane', 'PARTNERSHIPS'),
    jsonb_build_object('q', 'executive retreats', 'lane', 'CORPORATE'), jsonb_build_object('q', 'podcast production', 'lane', 'BRANDS'))),
  updated_at = now()
 where key = 'contact_order';

-- Today's next bio searches: not run in the last 30 days, within the day's search count and credit budget.
create or replace function public.instagram_prospect_plan(p_max int default 2) returns jsonb
language sql stable security definer set search_path = public as $$
  with cfg as (select value v from system_config where key = 'contact_order'),
  done_today as (select count(*) n from public_profile_calls where purpose = 'PROSPECT_SEARCH'
                  and called_at >= date_trunc('day', now() at time zone 'Africa/Cairo') at time zone 'Africa/Cairo'),
  allowed as (select greatest(0, least(coalesce(p_max, 2),
                coalesce(((select v from cfg)->'instagram'->>'prospect_searches_per_day')::int, 4) - (select n from done_today),
                floor((instagram_budget()->>'left')::int / 65.0)::int)) k),
  bank as (select b.value q, b.ordinality o from cfg, jsonb_array_elements(cfg.v->'prospect_bank') with ordinality b)
  select coalesce(jsonb_agg(jsonb_build_object('q', x.q->>'q', 'lane', x.q->>'lane') order by x.last_run nulls first, x.o), '[]'::jsonb)
    from (select bank.*, (select max(called_at) from public_profile_calls c where c.purpose = 'PROSPECT_SEARCH' and c.query = bank.q->>'q') last_run
            from bank) x
   where x.last_run is null or x.last_run < now() - interval '30 days'
   limit (select k from allowed);
$$;
revoke all on function public.instagram_prospect_plan(int) from public, anon, authenticated;

-- Save one bio search: business accounts only (public, own website or business email, a real business bio). Profiles that
-- match a CRM company enrich it; the rest wait as PROSPECTS for the department that owns the lane.
-- p = {q, lane, response: <Firecrawl answer for one profiles-search call>, caller}
create or replace function public.instagram_prospect_save(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare prof jsonb; v_rows jsonb := p->'response'->'data'->'alexandria'->0->'data'->'data'; v_kept int := 0; v_skip int := 0; v_err text;
begin
  v_err := coalesce(p->'response'->>'error', p->'response'->'data'->'alexandria'->0->'error'->>'message');
  perform public_profile_call_log('PROSPECT_SEARCH', p->>'q', coalesce(jsonb_array_length(case when jsonb_typeof(v_rows) = 'array' then v_rows end), 0),
                                  case when jsonb_typeof(v_rows) = 'array' and jsonb_array_length(v_rows) > 0 then 65 else 0 end,
                                  coalesce(p->>'caller', 'n8n'), null, v_err);
  if jsonb_typeof(v_rows) <> 'array' then return jsonb_build_object('ok', false, 'error', coalesce(v_err, 'No results array')); end if;
  for prof in select * from jsonb_array_elements(v_rows) loop
    if coalesce((prof->>'isPrivate')::boolean, false)
       or (coalesce(prof->>'bioLink', '') !~* '^https?://' and coalesce(prof->>'publicEmail', '') !~ '@')
       or coalesce(prof->>'bio', '') ~* '(personal account|fan page|meme|giveaway|onlyfans|crypto|forex|dropshipping|link in bio for)' then
      v_skip := v_skip + 1; continue;
    end if;
    perform public_profile_record(prof || jsonb_build_object('_projection', 'full'), 'PROSPECTING: ' || coalesce(p->>'q', ''), coalesce(p->>'lane', 'BRANDS'), null);
    v_kept := v_kept + 1;
  end loop;
  return jsonb_build_object('ok', true, 'q', p->>'q', 'kept', v_kept, 'skipped', v_skip, 'budget', instagram_budget());
end $$;
revoke all on function public.instagram_prospect_save(jsonb) from public, anon, authenticated;
