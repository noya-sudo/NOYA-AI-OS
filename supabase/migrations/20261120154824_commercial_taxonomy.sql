-- FINAL MASTER DIRECTIVE (20 Nov 2026), part 1: canonical commercial taxonomy.
-- One primary_stream per opportunity, plus service_tags, project_type_canon, buyer_type, market, season, relationship_type.
-- Original values are preserved in opportunities.taxonomy (provenance: rule, confidence, original fields, mapped_at).
-- Idempotent: tables use IF NOT EXISTS / ON CONFLICT; the backfill only fills rows without a stream.

create table if not exists public.commercial_streams (
  code text primary key,
  pillar text not null check (pillar in ('PRIVATE_TALENT','BRANDS_CULTURE','EVENTS_CORPORATE','TRAVEL_DISTRIBUTION')),
  label text not null,
  mission text,
  director_key text,
  sort int not null default 100,
  active boolean not null default true
);
alter table public.commercial_streams enable row level security;

insert into public.commercial_streams (code, pillar, label, mission, director_key, sort) values
 ('PRIVATE_CLIENTS','PRIVATE_TALENT','Private clients / family offices','Win and keep UHNW families and their private offices through PAs, EAs, clubs and referrers; value first, membership later.','PRIVATE',10),
 ('CELEBRITY_ENTERTAINMENT','PRIVATE_TALENT','Celebrity / entertainment','Become the trusted travel, security and lifestyle desk for talent through their managers, agents and PR teams.','SPORTS',11),
 ('ATHLETES_FOOTBALL','PRIVATE_TALENT','Athletes / football / sports','You manage the player''s career; NOYA handles the lifestyle around it. Agencies, player care, commercial managers.','SPORTS',12),
 ('PRIVATE_CLUBS','PRIVATE_TALENT','Private clubs / founder networks','Member weekends, founder retreats and private journeys for clubs and investor networks.','PRIVATE',13),
 ('EXECUTIVE_LANDING','PRIVATE_TALENT','Executive Landing / expat families','You hire or place the leader; NOYA makes the move and life in Egypt work.','CORPORATE',14),
 ('SOURCING','PRIVATE_TALENT','Sourcing & collectibles','Verified sourcing of exceptional cars, bags, watches, jewellery and legitimate collectibles.','PRIVATE',15),
 ('FASHION_LUXURY','BRANDS_CULTURE','Fashion / luxury','Egypt campaigns, shoots, VIC dinners and launches for luxury and premium fashion houses.','BRANDS',20),
 ('STREETWEAR','BRANDS_CULTURE','Streetwear','Drops, creator trips and culture-led activations in Egypt and the GCC.','BRANDS',21),
 ('BEAUTY','BRANDS_CULTURE','Beauty / cosmetics / skincare','Launches, press trips and creator programmes for beauty brands entering or growing in MENA.','BRANDS',22),
 ('FRAGRANCE','BRANDS_CULTURE','Fragrance','Launch experiences and storytelling trips rooted in place.','BRANDS',23),
 ('JEWELLERY_WATCHES','BRANDS_CULTURE','Jewellery / watches','VIC journeys, private viewings and launches for maisons.','BRANDS',24),
 ('LUXURY_AUTOMOTIVE','BRANDS_CULTURE','Luxury automotive','Drives, launches and owner experiences in Egypt''s desert and coast.','BRANDS',25),
 ('PRODUCT_LAUNCHES','BRANDS_CULTURE','Product launches','Launch hospitality and logistics for brands of any category.','BRANDS',26),
 ('CREATOR_TRIPS','BRANDS_CULTURE','Creator trips','Creator and influencer programmes with ground logistics, access and safety.','BRANDS',27),
 ('PR_AGENCIES','BRANDS_CULTURE','PR / marketing / creative agencies','Agency owns client, creative and comms; NOYA owns Egypt execution, hospitality and logistics.','BRANDS',28),
 ('EXPERIENTIAL_AGENCIES','BRANDS_CULTURE','Experiential agencies','Destination execution partner for experiential and event agencies.','BRANDS',29),
 ('MEDIA_PRODUCTION','BRANDS_CULTURE','Media / production / shoots','Locations, access, talent movement and ground logistics for shoots.','MEDIA',30),
 ('FILM_TV','BRANDS_CULTURE','Film / TV / entertainment','Production hospitality, talent logistics and festival guest desks.','MEDIA',31),
 ('WEDDINGS','EVENTS_CORPORATE','Weddings','Planner keeps client, creative and design; NOYA runs guests, hotels, cars, security and experiences.','WEDDINGS',40),
 ('PRIVATE_CELEBRATIONS','EVENTS_CORPORATE','Private celebrations','Milestone birthdays, anniversaries and family gatherings.','WEDDINGS',41),
 ('CORPORATE_EVENTS','EVENTS_CORPORATE','Corporate events','Client events, conference hospitality and delegations.','CORPORATE',42),
 ('INCENTIVES','EVENTS_CORPORATE','Incentives','Incentive journeys with genuine access.','CORPORATE',43),
 ('EXECUTIVE_HOSPITALITY','EVENTS_CORPORATE','Executive hospitality','VIP visits, board travel and executive programmes.','CORPORATE',44),
 ('RETREATS','EVENTS_CORPORATE','Retreats','Founder, investor and wellness retreats in Cairo, Giza and the Red Sea.','CORPORATE',45),
 ('LEADERSHIP_OFFSITES','EVENTS_CORPORATE','Leadership offsites','Offsites for leadership teams and partners.','CORPORATE',46),
 ('SPORT_ENTERTAINMENT_EVENTS','EVENTS_CORPORATE','Sport / entertainment events','Guest desks and hospitality around festivals, tours and sporting events.','EGYPT',47),
 ('TRAVEL_ADVISORS','TRAVEL_DISTRIBUTION','Luxury travel advisors','They keep the client; NOYA delivers Egypt.','TRAVEL',60),
 ('CONCIERGE_COMPANIES','TRAVEL_DISTRIBUTION','Concierge companies','The Egypt desk behind other concierge brands.','TRAVEL',61),
 ('DMC_WHITE_LABEL','TRAVEL_DISTRIBUTION','DMC / white-label','White-label Egypt fulfilment for DMCs and consortia.','TRAVEL',62),
 ('HOTELS','TRAVEL_DISTRIBUTION','Hotels','Booking partner, preferred rates, referrals and VIP guest desks.','HOSPITALITY',63),
 ('RESORTS','TRAVEL_DISTRIBUTION','Resorts','Resort partnerships, guest experiences and content projects.','HOSPITALITY',64),
 ('VILLAS','TRAVEL_DISTRIBUTION','Villas','Villa portfolios and guest concierge.','HOSPITALITY',65),
 ('BRANDED_RESIDENCES','TRAVEL_DISTRIBUTION','Branded residences','Owner lifestyle and residence concierge desks.','HOSPITALITY',66),
 ('GLOBAL_MOBILITY','TRAVEL_DISTRIBUTION','Global mobility','The lifestyle layer after the move, for relocation and mobility firms.','CORPORATE',67),
 ('EXECUTIVE_SEARCH','TRAVEL_DISTRIBUTION','Executive search','Executive Landing for the leaders search firms place in Egypt.','CORPORATE',68),
 ('CORPORATE_TRAVEL','TRAVEL_DISTRIBUTION','Corporate travel','Executive travel and VIP movements for corporate travel teams.','CORPORATE',69)
on conflict (code) do update set pillar = excluded.pillar, label = excluded.label, mission = excluded.mission, director_key = excluded.director_key, sort = excluded.sort;

create table if not exists public.commercial_services (
  code text primary key, label text not null, regulated boolean not null default false, note text
);
alter table public.commercial_services enable row level security;
insert into public.commercial_services (code, label, regulated, note) values
 ('BESPOKE_TRAVEL','Bespoke travel',false,null),('HOTELS','Hotels',false,null),('VILLAS','Villas',false,null),('RESIDENCES','Residences',false,null),
 ('VIP_AIRPORT','VIP airport',false,null),('CHAUFFEURS','Chauffeurs',false,null),('SECURITY','Security',false,'Licensed security providers only'),
 ('DINING_NIGHTLIFE','Dining / nightlife',false,null),('TICKETS_ACCESS','Tickets / access',false,null),('YACHTS','Yachts',false,null),
 ('PRIVATE_AVIATION','Private aviation',false,'Licensed operators only'),('WEDDINGS','Weddings',false,null),('CELEBRATIONS','Celebrations',false,null),
 ('CORPORATE_EVENTS','Corporate events',false,null),('INCENTIVES','Incentives',false,null),('RETREATS','Retreats',false,null),
 ('BRAND_PRODUCTION','Brand production',false,null),('CREATOR_LOGISTICS','Creator logistics',false,null),('TALENT_LOGISTICS','Talent logistics',false,null),
 ('LOCATION_SHOOT','Location / shoot support',false,'Permits through proper partners'),('PRODUCTION_SUPPORT','Production support',false,null),
 ('EXECUTIVE_LANDING','Executive Landing',false,null),('HOUSING','Housing coordination',false,null),('SCHOOLS','School support',false,null),
 ('HOUSEHOLD_STAFF','Household staffing coordination',false,null),('MEDICAL_ORIENTATION','Medical orientation',true,'Clinical care by licensed professionals only'),
 ('PRIVATE_DESK','Ongoing private desk',false,null),('RESIDENCE_CONCIERGE','Residence owner concierge',false,null),('GIFTING','Gifting',false,null),
 ('SOURCING','Sourcing',false,'Never auto-buy; authentication and provenance first'),('CARS','Cars',false,null),('HANDBAGS','Handbags',false,null),
 ('WATCHES','Watches',false,null),('JEWELLERY','Jewellery',false,null),('COLLECTIBLES','Collectibles',false,null),
 ('IMMIGRATION_LEGAL_TAX','Immigration / legal / tax',true,'Licensed professionals only; NOYA coordinates')
on conflict (code) do update set label = excluded.label, regulated = excluded.regulated, note = excluded.note;

alter table public.opportunities
  add column if not exists primary_stream text references public.commercial_streams(code),
  add column if not exists service_tags text[] not null default '{}',
  add column if not exists project_type_canon text,
  add column if not exists buyer_type text,
  add column if not exists market text,
  add column if not exists season text,
  add column if not exists relationship_type text,
  add column if not exists taxonomy jsonb;
create index if not exists opportunities_primary_stream_idx on public.opportunities (primary_stream);

-- The mapping: first matching rule wins; the rule and the original values are kept.
create or replace function public.opportunity_taxonomy(p_opp uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $$
declare o opportunities%rowtype; c companies%rowtype; t text; s text; r text; conf text := 'MEDIUM'; tags text[] := '{}'; mk text; bt text; rel text;
begin
  select * into o from opportunities where id = p_opp; if o.id is null then return null; end if;
  select * into c from companies where id = o.company_id;
  t := lower(concat_ws(' ', o.opportunity_type, o.product_code, o.egypt->>'bucket', o.sector, o.company_type, o.angle, o.commercial_trigger, o.track,
                       c.name, c.sector, c.company_type, c.acquisition_lane, c.prospect_segment, c.vertical_override, c.partnership_model));
  if o.product_code = 'EXECUTIVE_LANDING_DESK' then s := 'EXECUTIVE_LANDING'; r := 'product:EXECUTIVE_LANDING_DESK'; conf := 'HIGH';
  elsif t ~* '(executive search|headhunt|search firm|\mboyden\M|\msignium\M|spencer stuart|egon zehnder|korn ferry|heidrick)' then s := 'EXECUTIVE_SEARCH'; r := 'kw:executive search';
  elsif t ~* '(relocation|global mobility|\mmovers?\M|\mmoving\M)' then s := 'GLOBAL_MOBILITY'; r := 'kw:mobility';
  elsif t ~* '(football|soccer|\mfifa\M|\mplayers?\M|athlete|sports? management|sports? agency|player care)' then s := 'ATHLETES_FOOTBALL'; r := 'kw:sport';
  elsif t ~* '(celebrit|talent management|talent agency|artist management|record label|musician|\mactor|actress)' then s := 'CELEBRITY_ENTERTAINMENT'; r := 'kw:talent';
  elsif t ~* '(wedding|bridal)' then s := 'WEDDINGS'; r := 'kw:wedding'; conf := 'HIGH';
  elsif t ~* '(film festival|\mfilm\M|\mtv\M|television|documentar)' then s := 'FILM_TV'; r := 'kw:film';
  elsif t ~* '(members? club|private club|founder network|investor network|\mypo\M|private_clubs)' then s := 'PRIVATE_CLUBS'; r := 'kw:club';
  elsif t ~* '(family office|private office|\muhnw\M|noya_private|private client)' or c.prospect_segment = 'PRIVATE_OFFICE' or c.vertical_override = 'PRIVATE_UHNW' then s := 'PRIVATE_CLIENTS'; r := 'kw/segment:private';
  elsif t ~* '(branded residence|\mresidences?\M)' then s := 'BRANDED_RESIDENCES'; r := 'kw:residence';
  elsif t ~* '\mvillas?\M' then s := 'VILLAS'; r := 'kw:villa';
  elsif t ~* '\mresorts?\M' then s := 'RESORTS'; r := 'kw:resort';
  elsif t ~* '(\mhotels?\M|hospitality|preferred_stay|nile cruise|\mcruises?\M|dahabiya)' or c.prospect_segment = 'HOTELS_HOSPITALITY' then s := 'HOTELS'; r := 'kw/segment:hotel';
  elsif t ~* 'concierge' then s := 'CONCIERGE_COMPANIES'; r := 'kw:concierge';
  elsif t ~* '(\mdmc\M|destination management|white.label)' then s := 'DMC_WHITE_LABEL'; r := 'kw:dmc';
  elsif t ~* '(travel advis|travel design|travel agen|luxury travel|tour operator|travel_partner|virtuoso|serandipians|indagare)' or c.prospect_segment = 'TRAVEL_PARTNER' then s := 'TRAVEL_ADVISORS'; r := 'kw/segment:travel';
  elsif t ~* '(retreat|wellness)' then s := 'RETREATS'; r := 'kw:retreat';
  elsif t ~* '(offsite|leadership)' then s := 'LEADERSHIP_OFFSITES'; r := 'kw:offsite';
  elsif t ~* 'incentive' then s := 'INCENTIVES'; r := 'kw:incentive';
  elsif t ~* '(experiential|activation)' then s := 'EXPERIENTIAL_AGENCIES'; r := 'kw:experiential';
  elsif t ~* '(\mpr\M|public relations|communications agency|marketing agency|creative agency|influencer agency|\magency\M|agencies)' then s := 'PR_AGENCIES'; r := 'kw:agency';
  elsif t ~* '(production|\mshoots?\M|photograph|content_production|\mmedia\M)' then s := 'MEDIA_PRODUCTION'; r := 'kw:production';
  elsif t ~* '(fragrance|perfume|parfum)' then s := 'FRAGRANCE'; r := 'kw:fragrance';
  elsif t ~* '(beauty|cosmetic|skin ?care|hair ?care|make-?up)' then s := 'BEAUTY'; r := 'kw:beauty';
  elsif t ~* '(jewel|\mwatch|horlog)' then s := 'JEWELLERY_WATCHES'; r := 'kw:jewellery';
  elsif t ~* '(automotive|\mmotors?\M|supercar)' then s := 'LUXURY_AUTOMOTIVE'; r := 'kw:automotive';
  elsif t ~* '(streetwear|sneaker)' then s := 'STREETWEAR'; r := 'kw:streetwear';
  elsif t ~* '(creator|influencer)' then s := 'CREATOR_TRIPS'; r := 'kw:creator';
  elsif t ~* '\mlaunch' then s := 'PRODUCT_LAUNCHES'; r := 'kw:launch';
  elsif t ~* '(fashion|luxury|apparel|lingerie|couture|swim|\mbrands?\M)' or c.acquisition_lane = 'BRANDS' then s := 'FASHION_LUXURY'; r := 'kw/lane:brands'; conf := case when c.acquisition_lane = 'BRANDS' and t !~* '(fashion|luxury|apparel)' then 'LOW' else 'MEDIUM' end;
  elsif t ~* 'festival' then s := 'SPORT_ENTERTAINMENT_EVENTS'; r := 'kw:festival';
  elsif t ~* '(\mevents?\M|conference|\mgala\M)' or c.prospect_segment = 'CORPORATE_EVENTS' then s := 'CORPORATE_EVENTS'; r := 'kw/segment:events';
  elsif c.acquisition_lane = 'WEDDINGS' then s := 'WEDDINGS'; r := 'lane:WEDDINGS'; conf := 'LOW';
  elsif c.acquisition_lane = 'CORPORATE' or c.vertical_override = 'CORPORATE' then s := 'CORPORATE_EVENTS'; r := 'lane:CORPORATE'; conf := 'LOW';
  elsif c.acquisition_lane = 'TRAVEL_PRIVATE' then s := 'TRAVEL_ADVISORS'; r := 'lane:TRAVEL_PRIVATE'; conf := 'LOW';
  elsif c.acquisition_lane = 'SPORTS_PRIVATE' then s := 'ATHLETES_FOOTBALL'; r := 'lane:SPORTS_PRIVATE'; conf := 'LOW';
  elsif c.acquisition_lane = 'PARTNERSHIPS' then s := 'HOTELS'; r := 'lane:PARTNERSHIPS'; conf := 'LOW';
  elsif c.acquisition_lane = 'EGYPT_EVENTS' then s := 'SPORT_ENTERTAINMENT_EVENTS'; r := 'lane:EGYPT_EVENTS'; conf := 'LOW';
  else s := null; r := 'none'; conf := 'NONE';
  end if;
  -- service tags (from the project words)
  if t ~* '\mhotels?\M' then tags := array_append(tags, 'HOTELS'); end if;
  if t ~* '\mvillas?\M' then tags := array_append(tags, 'VILLAS'); end if;
  if t ~* 'yacht' then tags := array_append(tags, 'YACHTS'); end if;
  if t ~* '(aviation|private jet|jet charter)' then tags := array_append(tags, 'PRIVATE_AVIATION'); end if;
  if t ~* '(chauffeur|transfers?|\mdrivers?\M)' then tags := array_append(tags, 'CHAUFFEURS'); end if;
  if t ~* 'security' then tags := array_append(tags, 'SECURITY'); end if;
  if t ~* 'wedding' then tags := array_append(tags, 'WEDDINGS'); end if;
  if t ~* '(production|\mshoots?\M|campaign)' then tags := array_append(tags, 'BRAND_PRODUCTION'); end if;
  if t ~* '(creator|influencer)' then tags := array_append(tags, 'CREATOR_LOGISTICS'); end if;
  if t ~* '(retreat)' then tags := array_append(tags, 'RETREATS'); end if;
  if s = 'EXECUTIVE_LANDING' then tags := array_append(tags, 'EXECUTIVE_LANDING'); end if;
  -- market from the company's country
  mk := case
    when c.country ~* 'egypt' then 'EGYPT'
    when c.country ~* '(united kingdom|\muk\M|england|london|scotland)' then 'UK'
    when c.country ~* '(emirates|\muae\M|dubai|abu dhabi|saudi|ksa|qatar|kuwait|bahrain|oman)' then 'GCC'
    when c.country ~* '(france|monaco|italy|spain|greece|switzerland|germany|netherlands|portugal|belgium|austria|sweden|denmark|norway|ireland|europe)' then 'EUROPE'
    when c.country ~* '(united states|\musa?\M|canada|new york|los angeles)' then 'NORTH_AMERICA'
    when c.country ~* 'global' then 'GLOBAL'
    when coalesce(c.country, '') = '' then 'UNKNOWN' else 'REST_OF_WORLD' end;
  bt := case
    when s in ('PRIVATE_CLIENTS') then 'PRIVATE_OFFICE' when s = 'PRIVATE_CLUBS' then 'CLUB'
    when s in ('CELEBRITY_ENTERTAINMENT') then 'TALENT_MANAGEMENT' when s = 'ATHLETES_FOOTBALL' then 'SPORTS_AGENCY'
    when s in ('PR_AGENCIES','EXPERIENTIAL_AGENCIES') then 'AGENCY' when s in ('MEDIA_PRODUCTION','FILM_TV') then 'PRODUCTION'
    when s in ('FASHION_LUXURY','STREETWEAR','BEAUTY','FRAGRANCE','JEWELLERY_WATCHES','LUXURY_AUTOMOTIVE','PRODUCT_LAUNCHES','CREATOR_TRIPS') then 'BRAND'
    when s in ('WEDDINGS','PRIVATE_CELEBRATIONS') then 'PLANNER'
    when s in ('CORPORATE_EVENTS','INCENTIVES','EXECUTIVE_HOSPITALITY','RETREATS','LEADERSHIP_OFFSITES','CORPORATE_TRAVEL','EXECUTIVE_LANDING') then 'CORPORATE'
    when s in ('TRAVEL_ADVISORS','CONCIERGE_COMPANIES','DMC_WHITE_LABEL') then 'TRAVEL_TRADE'
    when s in ('HOTELS','RESORTS','VILLAS','BRANDED_RESIDENCES') then 'HOSPITALITY'
    when s = 'GLOBAL_MOBILITY' then 'MOBILITY' when s = 'EXECUTIVE_SEARCH' then 'EXECUTIVE_SEARCH'
    when s = 'SPORT_ENTERTAINMENT_EVENTS' then 'EVENT_ORGANISER' else null end;
  rel := case
    when c.relationship_status = 'client' then 'CLIENT'
    when c.relationship_status = 'partner' then 'PARTNER'
    when c.relationship_status = 'supplier' then 'SUPPLIER'
    when exists (select 1 from gmail_history_threads g where g.company_id = o.company_id and g.inbound > 0) then 'WARM'
    else 'COLD' end;
  return jsonb_build_object('stream', s, 'rule', r, 'confidence', conf, 'service_tags', to_jsonb(tags), 'market', mk, 'buyer_type', bt, 'relationship_type', rel,
    'project_type', coalesce(nullif(o.product_code, ''), nullif(o.opportunity_type, '')),
    'original', jsonb_build_object('opportunity_type', o.opportunity_type, 'product_code', o.product_code, 'egypt', o.egypt, 'track', o.track,
       'acquisition_lane', c.acquisition_lane, 'prospect_segment', c.prospect_segment, 'vertical_override', c.vertical_override, 'sector', coalesce(o.sector, c.sector)));
end $$;
revoke all on function public.opportunity_taxonomy(uuid) from public, anon, authenticated;

create or replace function public.opportunity_apply_taxonomy(p_opp uuid, p_force boolean default false)
 returns text language plpgsql security definer set search_path to 'public'
as $$
declare x jsonb;
begin
  x := opportunity_taxonomy(p_opp); if x is null then return null; end if;
  update opportunities set
    primary_stream = case when p_force or primary_stream is null then x->>'stream' else primary_stream end,
    service_tags = case when p_force or service_tags = '{}' then coalesce(array(select jsonb_array_elements_text(x->'service_tags')), '{}') else service_tags end,
    project_type_canon = coalesce(project_type_canon, x->>'project_type'),
    buyer_type = case when p_force or buyer_type is null then x->>'buyer_type' else buyer_type end,
    market = case when p_force or market is null then x->>'market' else market end,
    relationship_type = case when p_force or relationship_type is null then x->>'relationship_type' else relationship_type end,
    taxonomy = coalesce(taxonomy, '{}'::jsonb) || jsonb_build_object('rule', x->>'rule', 'confidence', x->>'confidence', 'mapped_at', now(),
                 'original', coalesce(taxonomy->'original', x->'original'))
  where id = p_opp;
  return x->>'stream';
end $$;
revoke all on function public.opportunity_apply_taxonomy(uuid, boolean) from public, anon, authenticated;

-- Future writes stay canonical: a new opportunity (or one whose company changes) without a stream is mapped on write.
create or replace function public.opportunity_taxonomy_after()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.primary_stream is null and pg_trigger_depth() = 1 then perform opportunity_apply_taxonomy(new.id); end if;
  return null;
end $$;
drop trigger if exists opportunity_taxonomy_after on public.opportunities;
create trigger opportunity_taxonomy_after after insert or update of company_id, opportunity_type, product_code on public.opportunities
  for each row execute function public.opportunity_taxonomy_after();

-- Canonical CEO stage (raw status kept as is). Route readiness comes from the route cache (part 2).
create or replace function public.hq_stage(p_status text, p_has_route boolean, p_has_project boolean, p_has_next boolean, p_qualified boolean)
 returns text language sql immutable
as $$
  select case p_status
    when 'WON' then 'WON' when 'NEGOTIATION' then 'NEGOTIATION' when 'PROPOSAL' then 'PROPOSAL'
    when 'CALL_REQUIRED' then 'MEETING' when 'INTERESTED' then 'ACTIVE_CONVERSATION' when 'FOLLOW_UP' then 'FOLLOW_UP'
    when 'CONTACTED' then 'CONTACTED' when 'READY' then 'OUTREACH_READY'
    when 'LONG_TERM' then 'PARKED' when 'LOST' then 'LOST' when 'ARCHIVED' then 'ARCHIVED'
    else case when p_has_route and p_has_project and p_has_next then 'PROJECT_READY'
              when p_has_route then 'CONTACT_READY'
              when p_qualified then 'QUALIFIED_ACCOUNT' else 'MARKET_UNIVERSE' end end;
$$;
create or replace function public.hq_stage_rank(p_stage text)
 returns int language sql immutable
as $$
  select coalesce(array_position(array['MARKET_UNIVERSE','QUALIFIED_ACCOUNT','CONTACT_READY','PROJECT_READY','OUTREACH_READY','CONTACTED','FOLLOW_UP',
    'ACTIVE_CONVERSATION','MEETING','BRIEF','PROPOSAL','NEGOTIATION','WON','ACTIVE_PROJECT','COMPLETED','REPEAT'], p_stage), 0);
$$;

-- Backfill (only rows without a stream; originals kept).
do $$ declare r record; begin
  for r in select id from opportunities where primary_stream is null loop perform opportunity_apply_taxonomy(r.id); end loop;
end $$;
