-- Company corrections with provenance (8 Oct 2026, Adam D1 / D2)
--  1. company_field_history: every corrected company field keeps its previous value, the reason and the source.
--  2. company_correct(): the one way corrections are applied (history first, then the field).
--  3. website_confirmed_at: an official website whose domain does not spell the company name (db.com, ff.co, slh.com,
--     ghmhotels.com...) is trusted for email research only once it has been confirmed; a wrong domain is never active.
--  4. Starwood Hotels & Resorts disqualified (Marriott brand since 2016); the Marriott brand records stay.
--  5. Wrong websites corrected from official sources; unresolved ones cleared and flagged for review.
--  6. Partnership routing (D2): GM -> Commercial Director -> Sales Director -> Partnerships for stay, reciprocal,
--     referral, guest-concierge and commercial partnership models; PR / communications inboxes only for content,
--     press, creator / talent stays, brand trips and editorial collaborations.

create table if not exists public.company_field_history (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  field text not null,
  old_value text,
  new_value text,
  reason text not null,
  source_url text,
  decided_by text not null,
  changed_at timestamptz not null default now()
);
create index if not exists company_field_history_company on public.company_field_history (company_id, changed_at desc);
alter table public.company_field_history enable row level security;
revoke all on public.company_field_history from anon, authenticated;

alter table public.companies add column if not exists website_confirmed_at timestamptz;

create or replace function public.company_correct(p_company uuid, p_field text, p_new text, p_reason text, p_source text, p_by text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old text; v_type text;
begin
  if p_field not in ('website', 'website_confirmed_at', 'instagram', 'universe_status', 'universe_reason', 'notes') then
    raise exception 'company_correct: field % is not correctable here', p_field; end if;
  if coalesce(btrim(p_reason), '') = '' or coalesce(btrim(p_by), '') = '' then raise exception 'company_correct: reason and decided_by are required'; end if;
  v_type := case when p_field = 'website_confirmed_at' then 'timestamptz' else 'text' end;
  if not exists (select 1 from companies where id = p_company) then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  execute format('select %I::text from companies where id = $1', p_field) into v_old using p_company;
  if v_old is not distinct from p_new then return jsonb_build_object('ok', true, 'changed', false); end if;
  insert into company_field_history (company_id, field, old_value, new_value, reason, source_url, decided_by)
  values (p_company, p_field, v_old, p_new, p_reason, nullif(btrim(coalesce(p_source, '')), ''), p_by);
  execute format('update companies set %I = $1::%s where id = $2', p_field, v_type) using p_new, p_company;
  -- a new website is unconfirmed until someone confirms it
  if p_field = 'website' then update companies set website_confirmed_at = null where id = p_company; end if;
  return jsonb_build_object('ok', true, 'changed', true, 'old', v_old, 'new', p_new);
end $$;
revoke all on function public.company_correct(uuid, text, text, text, text, text) from public, anon, authenticated;

-- The domain email research may use: the website's registrable domain when it carries the company name, or when the
-- website has been confirmed as the official one.
create or replace function public.company_research_domain(p_name text, p_website text, p_confirmed timestamptz)
returns text language sql stable set search_path = public as $$
  select case when coalesce(p_website, '') <> ''
               and (p_confirmed is not null or domain_trusted(p_name, registrable_domain(p_website)))
              then registrable_domain(p_website) end
$$;
revoke all on function public.company_research_domain(text, text, timestamptz) from public, anon, authenticated;

do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.email_gap_list(int, text, boolean)'::regprocedure);
  n := replace(d, 'case when domain_trusted(c.name, registrable_domain(c.website)) then registrable_domain(c.website) end domain',
                  'company_research_domain(c.name, c.website, c.website_confirmed_at) domain');
  if n = d then raise exception 'email_gap_list patch did not apply'; end if;
  execute n;
  d := pg_get_functiondef('public.email_intel_save(jsonb)'::regprocedure);
  n := replace(d, 'v_domain := case when domain_trusted(c.name, registrable_domain(c.website)) then registrable_domain(c.website) end;',
                  'v_domain := company_research_domain(c.name, c.website, c.website_confirmed_at);');
  if n = d then raise exception 'email_intel_save patch did not apply'; end if;
  execute n;
end $patch$;

-- ---------------------------------------------------------------- 4. Starwood (Adam D1, 8 Oct 2026)
do $starwood$
declare c uuid := (select id from companies where name = 'Starwood Hotels & Resorts' limit 1);
begin
  if c is null then return; end if;
  perform company_correct(c, 'universe_status', 'EXCLUDED',
    'Disqualified as a standalone prospect: Starwood was acquired by Marriott International in 2016 and is no longer a separate operator.',
    'https://marriott.gcs-web.com/node/14521', 'Adam Elshazly (D1)');
  perform company_correct(c, 'universe_reason',
    '[DISQUALIFIED 08 Oct 2026] Starwood Hotels & Resorts became part of Marriott International in 2016. Work Marriott through its brand records (St. Regis Hotels & Resorts, The St. Regis Cairo). Contacts kept for reference only.',
    'Adam D1: not an active qualified brand', null, 'Adam Elshazly (D1)');
  update opportunities set status = 'ARCHIVED', updated_at = now(),
         description = concat_ws(E'\n', description, '[ARCHIVED 08 Oct 2026] Starwood disqualified as a standalone prospect (part of Marriott since 2016).')
   where company_id = c and status not in ('WON', 'LOST', 'ARCHIVED');
  update tasks set status = 'CANCELLED', updated_at = now()
   where company_id = c and status in ('OPEN', 'IN_PROGRESS', 'WAITING');
  update outreach_candidates set status = 'SKIPPED', updated_at = now()
   where company_id = c and status not in ('SENT', 'SKIPPED', 'APPROVED');
end $starwood$;

-- ---------------------------------------------------------------- 5. websites
-- Workflow 23 no longer leaves a wrong website in place with a "please check" note: an official domain it identifies by
-- company name replaces an unconfirmed website that does not carry the name, and the old value goes to the history.
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.email_intel_save(jsonb)'::regprocedure);
  n := replace(d, $a$  if v_found is not null and not coalesce(c.notes, '') ~* ('W23: official domain .*' || replace(v_found, '.', '\.')) then
    update companies set website = coalesce(website, 'https://' || v_found),
           notes = concat_ws(chr(10), notes, case when c.website is null
             then 'W23: official domain ' || v_found || ' identified from search results by company name (' || to_char(now(), 'DD Mon YYYY') || ').'
             else 'W23: official domain ' || v_found || ' identified by company name; the website on file (' || c.website || ') does not carry the company name — please check (' || to_char(now(), 'DD Mon YYYY') || ').' end)
     where id = c.id;
  end if;$a$, $a$  if v_found is not null and c.website_confirmed_at is null and registrable_domain(c.website) is distinct from v_found then
    perform company_correct(c.id, 'website', 'https://' || v_found,
      case when c.website is null then 'Official domain identified from search results by company name'
           else 'Website on file does not carry the company name; official domain identified from search results by company name' end,
      null, 'Workflow 23 email intelligence');
  end if;$a$);
  if n = d then raise exception 'email_intel_save website patch did not apply'; end if;
  execute n;
end $patch$;

do $websites$
declare r record; v_by text := 'NOYA system review (Adam instruction, 08 Oct 2026)';
begin
  -- wrong websites replaced by the official one (old value and source kept in company_field_history)
  for r in select * from (values
      ('Maybourne Hotel Group', 'https://www.maybourne.com', 'https://www.maybourne.com/about-maybourne',
       'Website on file (hospitality-on.com) is a trade-news site; official group site is maybourne.com'),
      ('Grand-Hôtel du Cap-Ferrat, A Four Seasons Hotel', 'https://www.fourseasons.com/capferrat/', 'https://press.fourseasons.com/capferrat/hotel-press-contacts/',
       'Website on file (worldtravelawards.com) is an awards site; the hotel is a Four Seasons property at fourseasons.com/capferrat'),
      ('Jet Linx', 'https://www.jetlinx.com', 'https://www.jetlinx.com',
       'Website on file (wealthranking.org) is a third-party ranking site; official site is jetlinx.com'),
      ('Patterson Belknap Webb & Tyler LLP', 'https://www.pbwt.com', 'https://www.pbwt.com',
       'Website on file (pplaw.com) belongs to a different firm; Patterson Belknap''s official domain is pbwt.com'),
      ('SNITCH', 'https://www.snitch.com', 'https://www.datanyze.com/companies/snitch/46776684',
       'Website on file (open.spotify.com) is not the company; snitch.com per third-party company listings (not first-party confirmed)')
    ) v(name, site, src, why) loop
    perform company_correct(c.id, 'website', r.site, r.why, r.src, v_by) from companies c where c.name = r.name;
  end loop;

  -- wrong websites with no official replacement found: cleared so they can never drive research, and flagged
  for r in select * from (values
      ('Summits', 'pangeamembersclub.com is Pangea (founder Matt Gray) and does not mention Summits, Sam Pisker or Jacob Rudoy; no official Summits site found'),
      ('Beyond Members Club', 'Website on file is the club''s Instagram profile, not a website; no official site found'),
      ('Fait Accompli', 'Website on file (press.armywarcollege.edu) is unrelated; no official site found'),
      ('Seven Private Members Club', 'Website on file (scribd.com) is a document host; no official site or other trace found'),
      ('Event Planet', 'Website on file (scz.org) is unrelated; Cairo agency listed on GoodFirms / ExpoStandZone, no official domain found'),
      ('The Ritz-Carlton New York, Westchester', 'Website on file (hotel-online.com) is a trade-news site; the property is reported rebranded (The Opus Westchester), not confirmed')
    ) v(name, why) loop
    perform company_correct(c.id, 'website', null, r.why, null, v_by) from companies c where c.name = r.name;
  end loop;
  -- the Instagram URL that was saved as Beyond's website belongs in instagram
  perform company_correct(c.id, 'instagram', 'https://www.instagram.com/beyondmembers.club/', 'Moved from the website field', null, v_by)
     from companies c where c.name = 'Beyond Members Club' and coalesce(c.instagram, '') = '';
  -- Summits qualified on Pangea's description: identity must be confirmed before any outreach
  perform company_correct(c.id, 'universe_status', 'NEEDS_REVIEW',
    'Qualification evidence came from pangeamembersclub.com (Pangea), which does not mention Summits; identity unresolved', null, v_by)
     from companies c where c.name = 'Summits' and c.universe_status = 'QUALIFIED';
  perform company_correct(c.id, 'universe_reason',
    '[NEEDS REVIEW 08 Oct 2026] Identity unresolved: the qualifying description came from Pangea''s site (pangeamembersclub.com), not Summits. People on file: Sam Pisker (Founder), Jacob Rudoy (Co-Founder & Culinary Director). Confirm the company and its official site before outreach.',
    'Website corrected; identity not confirmed', null, v_by)
     from companies c where c.name = 'Summits';
  -- superseded "please check" note on Cap-Ferrat
  perform company_correct(c.id, 'notes',
    regexp_replace(c.notes, '\s*W23: official domain fourseasons\.com identified by company name; the website on file \(https://worldtravelawards\.com\) does not carry the company name — please check \([^)]*\)\.', '', 'g'),
    'Superseded: website corrected to fourseasons.com/capferrat', null, v_by)
     from companies c where c.name = 'Grand-Hôtel du Cap-Ferrat, A Four Seasons Hotel' and c.notes ~ 'please check';

  -- official websites whose domain does not spell the company name: confirmed so email research may use them
  for r in select * from (values
      ('Cairo International Film Festival', 'ciff.org.eg is the festival''s official site'),
      ('Deutsche Bank Private Bank', 'db.com is Deutsche Bank''s official domain'),
      ('Founders Forum Group', 'ff.co is Founders Forum''s official domain (published contacts @ff.co)'),
      ('GPJ Dubai', 'gpj.com is George P. Johnson''s official domain'),
      ('Louis Vuitton', 'louisvuitton.com is the maison''s official domain'),
      ('Manchester City FC', 'mancity.com is the club''s official domain'),
      ('MCI Middle East', 'wearemci.com is MCI Group''s official domain'),
      ('MCI UK', 'wearemci.com is MCI Group''s official domain'),
      ('Noah Holdings Limited', 'noahgroup.com is Noah Holdings'' official domain'),
      ('Paris Saint-Germain', 'psg.fr is the club''s official domain'),
      ('Small Luxury Hotels of the World', 'slh.com is SLH''s official domain'),
      ('St. Regis Hotels & Resorts', 'st-regis.marriott.com is the brand''s official site on marriott.com'),
      ('The Chedi El Gouna', 'ghmhotels.com is the operator GHM''s official domain'),
      ('Four Seasons Resort and Residences Red Sea at Shura Island', 'fourseasons.com is the operator''s official domain'),
      ('Maybourne Hotel Group', 'Official site confirmed (about page lists Claridge''s, The Connaught, The Berkeley, The Emory, Maybourne Beverly Hills, Maybourne Riviera)'),
      ('Grand-Hôtel du Cap-Ferrat, A Four Seasons Hotel', 'Official hotel page on fourseasons.com; hotel press contacts published at press.fourseasons.com/capferrat'),
      ('Jet Linx', 'jetlinx.com is the company''s official domain'),
      ('Patterson Belknap Webb & Tyler LLP', 'pbwt.com is the firm''s official domain')
    ) v(name, why) loop
    perform company_correct(c.id, 'website_confirmed_at', now()::text, r.why, c.website, v_by)
       from companies c where c.name = r.name and c.website is not null and c.website_confirmed_at is null;
  end loop;
end $websites$;

-- ---------------------------------------------------------------- 6. partnership routing (Adam D2) + verified-only email
-- PR / communications roles and inboxes are for content, press, creator / talent stays, brand trips and editorial work
-- (partnership model CONTENT_TALENT). A stay, reciprocal, referral, guest-concierge or commercial partnership pitch never
-- goes to them just because they publish an address.
create or replace function public.pr_role(p_position text)
returns boolean language sql immutable as $$
  select coalesce(p_position, '') ~* '(public relations|\mpr\M|communications|\mcomms\M|\mpress\M|media relations|publicist)'
     and coalesce(p_position, '') !~* '(general manager|managing director|commercial|\msales\M|founder|owner|chief executive|\mceo\M)'
$$;

-- Hotel routing order: 4 General Manager, 3 Commercial Director, 2 Sales Director, 1 Partnerships, 0 anyone else, -1 PR.
create or replace function public.partner_route_rank(p_position text)
returns int language sql immutable as $$
  select case
    when p = '' then 0
    when pr_role(p) then -1
    when p ~* '(general manager|managing director)' and p ~* '(assistant|deputy|executive assistant)' then 0
    when p ~* '(general manager|\mgm\M|managing director)' then 4
    when p ~* '(chief commercial|\mcco\M)' or (p ~* 'commercial' and p ~* '(director|head|chief|\mvp\M|vice president)') then 3
    when p ~* '(director of sales|chief sales|sales director|\mdos\M)' or (p ~* '\msales\M' and p ~* '(director|head|\mvp\M|vice president)') then 2
    when p ~* '(partnership|business development|alliances)' then 1
    else 0 end
  from (select btrim(coalesce(p_position, '')) p) x
$$;

-- The hotel rule applies to hotel / resort / hospitality companies under a stay, reciprocal, referral, guest-concierge or
-- commercial (white-label) partnership model.
create or replace function public.partner_hotel_route(p_model text, p_company_type text)
returns boolean language sql immutable as $$
  select coalesce(p_model, '') in ('PREFERRED_STAY', 'RECIPROCAL', 'REFERRAL', 'GUEST_CONCIERGE', 'WHITE_LABEL_CONCIERGE')
     and coalesce(p_company_type, '') ~* '(hotel|resort|hospitality|lodge|aparthotel|serviced.apartment|nile cruise|destination developer)'
$$;
revoke all on function public.pr_role(text) from public, anon, authenticated;
revoke all on function public.partner_route_rank(text) from public, anon, authenticated;
revoke all on function public.partner_hotel_route(text, text) from public, anon, authenticated;

-- Planner: EMAIL only to an SMTP-verified address (the person's own, or a verified department inbox for their attention);
-- a publicly listed address waits for verification. Hotels pick GM -> Commercial -> Sales -> Partnerships, and use that
-- person's confirmed LinkedIn before any inbox. PR people and PR inboxes are skipped for every partnership model except content.
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.commercial_director_plan(boolean,integer,boolean)'::regprocedure);
  n := d;
  n := replace(n, $a$             c.company_type, c.universe_reason, c.instagram company_instagram, company_warm_route(c.id) warm,$a$,
                  $a$             c.company_type, c.universe_reason, c.instagram company_instagram, company_warm_route(c.id) warm,
             c.partnership_model model_code, partner_hotel_route(c.partnership_model, c.company_type) hotel_route,$a$);
  n := replace(n, $a$                  and not (email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and (k.email_status = 'VERIFIED' or (k.email_status = 'UNVERIFIED' and coalesce(k.email_source_url, '') <> '')))$a$,
                  $a$                  and not (email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and email_state(k.email_status, k.email_source_url, k.email_verification_provider) = 'VERIFIED')$a$);
  n := replace(n, $a$          when email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and (k.email_status = 'VERIFIED' or (k.email_status = 'UNVERIFIED' and coalesce(k.email_source_url, '') <> '')) then 'EMAIL'$a$,
                  $a$          when email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and email_state(k.email_status, k.email_source_url, k.email_verification_provider) = 'VERIFIED' then 'EMAIL'$a$);
  n := replace(n, $a$          when k.id is not null and ib.email_tier = 2 then 'EMAIL'$a$,
                  $a$          when k.id is not null and ib.email_tier = 2 and not (coalesce(b.hotel_route, false) and coalesce(k.linkedin, '') ~* 'linkedin\.com/in/') then 'EMAIL'$a$);
  n := replace(n, $a$          coalesce((email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and (k.email_status = 'VERIFIED' or coalesce(k.email_source_url, '') <> '')) or ib.email_tier = 2, false) desc,$a$,
                  $a$          coalesce((email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and email_state(k.email_status, k.email_source_url, k.email_verification_provider) = 'VERIFIED') or ib.email_tier = 2, false) desc,$a$);
  n := replace(n, $a$                      and length(btrim(coalesce(k.first_name, ''))) >= 2 and length(btrim(coalesce(k.last_name, ''))) >= 2
                    order by (role_score(k.position) >= 4) desc, (email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and (k.email_status = 'VERIFIED' or coalesce(k.email_source_url, '') <> '')) desc,$a$,
                  $a$                      and length(btrim(coalesce(k.first_name, ''))) >= 2 and length(btrim(coalesce(k.last_name, ''))) >= 2
                      -- partnership pitches never go to PR / communications (content, press, creator stays, brand trips, editorial only)
                      and not (coalesce(b.model_code, 'CONTENT_TALENT') <> 'CONTENT_TALENT' and pr_role(k.position))
                    order by
                      -- hotels: GM, Commercial Director, Sales Director, Partnerships; within that set, someone with a verified route first
                      case when b.hotel_route then partner_route_rank(k.position) >= 1 end desc nulls last,
                      case when b.hotel_route then (email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and email_state(k.email_status, k.email_source_url, k.email_verification_provider) = 'VERIFIED')
                                                   or coalesce(k.linkedin, '') ~* 'linkedin\.com/in/' end desc nulls last,
                      case when b.hotel_route then partner_route_rank(k.position) end desc nulls last,
                      (role_score(k.position) >= 4) desc, (email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and email_state(k.email_status, k.email_source_url, k.email_verification_provider) = 'VERIFIED') desc,$a$);
  n := replace(n, $a$                           and email_local_class(i.email) <> 'EXCLUDED' and coalesce(i.email_status, '') <> 'INVALID'$a$,
                  $a$                           and email_local_class(i.email) <> 'EXCLUDED' and coalesce(i.email_status, '') <> 'INVALID'
                           -- an inbox is emailed only once it is SMTP-verified (publicly listed is not enough)
                           and email_state(i.email_status, i.email_source_url, i.email_verification_provider) = 'VERIFIED'
                           and not (coalesce(b.model_code, 'CONTENT_TALENT') <> 'CONTENT_TALENT'
                                    and coalesce(i.position, '') || ' ' || i.email ~* '(press|media|communications|comms|\mpr\M)')$a$);
  if strpos(n, 'hotel_route,') = 0 or strpos(n, 'partner_route_rank(k.position) >= 1') = 0 or strpos(n, 'and pr_role(k.position)') = 0
     or strpos(n, 'email_state(i.email_status, i.email_source_url, i.email_verification_provider) = ''VERIFIED''') = 0
     or strpos(n, 'k.email_status = ''UNVERIFIED''') > 0 or strpos(n, 'k.email_status = ''VERIFIED'' or') > 0
     or strpos(n, 'not (coalesce(b.hotel_route, false)') = 0 then
    raise exception 'planner routing patch incomplete'; end if;
  execute n;
end $patch$;
