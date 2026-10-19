-- DESTINATION EGYPT — PROJECT GENERATION (Adam, 19 Oct 2026). A cross-company mission run by the existing Directors through
-- work orders; not a new Director, page or CRM. "Egypt as a destination + NOYA as the execution layer": find the companies
-- that already move people, clients, members, brands or audiences, and bring their next project to Egypt.
-- Success is reply → meeting → brief → proposal → project → revenue, never discovery volume.

-- 1. Programme definition
insert into system_config (key, value, note) values ('destination_egypt', jsonb_build_object(
  'name', 'DESTINATION EGYPT — PROJECT GENERATION',
  'north_star', 'The company international brands, agencies, wedding planners, private clubs, travel companies, media companies and private-client representatives call when they want to do something exceptional in Egypt.',
  'question', 'Who already moves people, clients, members, brands or audiences around the world, and how can NOYA bring their next project to Egypt?',
  'started_at', '2026-10-19', 'review_by', '2026-11-18',
  'buckets', jsonb_build_array(
    jsonb_build_object('key', 'BRAND_PRODUCTION', 'label', 'Brand / production / marketing', 'target', 20, 'director', 'BRANDS'),
    jsonb_build_object('key', 'WEDDINGS', 'label', 'Weddings / events', 'target', 20, 'director', 'WEDDINGS'),
    jsonb_build_object('key', 'PRIVATE_CLUBS', 'label', 'Private clubs / founder communities', 'target', 15, 'director', 'PRIVATE'),
    jsonb_build_object('key', 'TRAVEL', 'label', 'Travel / concierge', 'target', 15, 'director', 'TRAVEL'),
    jsonb_build_object('key', 'MEDIA', 'label', 'Media / podcasts / production', 'target', 15, 'director', 'MEDIA'),
    jsonb_build_object('key', 'NOYA_PRIVATE', 'label', 'NOYA Private / talent representation', 'target', 10, 'director', 'SPORTS'),
    jsonb_build_object('key', 'CORPORATE', 'label', 'Corporate retreats / executive events', 'target', 5, 'director', 'CORPORATE')),
  'project_types', jsonb_build_array('BRAND_CAMPAIGN_EGYPT', 'BRAND_SHOOT_EGYPT', 'CREATOR_TRIP_EGYPT', 'BRAND_LAUNCH_EGYPT', 'PRODUCTION_EGYPT',
    'AGENCY_CLIENT_PROJECT_EGYPT', 'DESTINATION_WEDDING_EGYPT', 'WEDDING_GUEST_CONCIERGE', 'WEDDING_SCOUTING_TRIP', 'PRIVATE_CLUB_MEMBER_TRIP',
    'FOUNDER_RETREAT_EGYPT', 'CORPORATE_OFFSITE_EGYPT', 'EXECUTIVE_RETREAT_EGYPT', 'PRIVATE_DINNER_EGYPT', 'PODCAST_EGYPT', 'MEDIA_PRODUCTION_EGYPT',
    'PRESS_TRIP_EGYPT', 'TRAVEL_ADVISOR_FAM', 'WHITE_LABEL_EGYPT_DESK', 'TALENT_PRIVATE_TRIP', 'ATHLETE_PRIVATE_TRIP', 'HOTEL_BRAND_CREATOR_COLLABORATION'),
  'score_weights', jsonb_build_object('project_generation', 20, 'network', 20, 'repeat', 15, 'egypt_relevance', 15, 'destination_evidence', 10,
    'warmth', 10, 'contactability', 5, 'studio_ready', 5),
  'hosting_rule', 'Hosting is never free by default and never offered in cold outreach. A FAM trip, scouting trip, creative recce, partner weekend, wedding planner FAM, brand or agency recce or private club preview needs the commercial case first (opportunity, audience or client access, repeat potential, partner and hotel contribution, NOYA cost, objective) and Adam''s approval for any spend or complimentary commitment.',
  'capacity', 'About 5 excellent new emails a working day plus replies and follow-ups. Quality before quota.'),
  'Destination Egypt mission (Adam, 19 Oct 2026). Targets are research targets, not outreach quotas.')
on conflict (key) do update set value = excluded.value, note = excluded.note, updated_at = now();

-- 2. The Egypt opportunity record lives on the opportunity itself
alter table opportunities add column if not exists mission text;
alter table opportunities add column if not exists egypt jsonb;
create index if not exists opportunities_mission_idx on opportunities (mission) where mission is not null;
alter table opportunities drop constraint if exists opportunities_egypt_shape_check;
alter table opportunities add constraint opportunities_egypt_shape_check check (
  egypt is null or (
    (egypt->>'bucket' is null or egypt->>'bucket' in ('BRAND_PRODUCTION', 'WEDDINGS', 'PRIVATE_CLUBS', 'TRAVEL', 'MEDIA', 'NOYA_PRIVATE', 'CORPORATE'))
    and (egypt->>'project_type' is null or egypt->>'project_type' in ('BRAND_CAMPAIGN_EGYPT', 'BRAND_SHOOT_EGYPT', 'CREATOR_TRIP_EGYPT', 'BRAND_LAUNCH_EGYPT',
      'PRODUCTION_EGYPT', 'AGENCY_CLIENT_PROJECT_EGYPT', 'DESTINATION_WEDDING_EGYPT', 'WEDDING_GUEST_CONCIERGE', 'WEDDING_SCOUTING_TRIP',
      'PRIVATE_CLUB_MEMBER_TRIP', 'FOUNDER_RETREAT_EGYPT', 'CORPORATE_OFFSITE_EGYPT', 'EXECUTIVE_RETREAT_EGYPT', 'PRIVATE_DINNER_EGYPT', 'PODCAST_EGYPT',
      'MEDIA_PRODUCTION_EGYPT', 'PRESS_TRIP_EGYPT', 'TRAVEL_ADVISOR_FAM', 'WHITE_LABEL_EGYPT_DESK', 'TALENT_PRIVATE_TRIP', 'ATHLETE_PRIVATE_TRIP',
      'HOTEL_BRAND_CREATOR_COLLABORATION'))
    and (egypt->>'role' is null or egypt->>'role' in ('PROJECT_GENERATOR', 'PARTNER_SUPPLIER', 'AMPLIFIER', 'TALENT'))
    and (egypt->>'studio_level' is null or egypt->>'studio_level' in ('1', '2', '3'))));
comment on column opportunities.egypt is 'Destination Egypt record: bucket, category, role (PROJECT_GENERATOR / PARTNER_SUPPLIER / AMPLIFIER / TALENT), what_they_do, audience, evidence [{fact, url, seen}], why_egypt, project_type, proposed_project, egypt_format, studio_level (1 email idea, 2 one-page, 3 brief), scores 0-5 (project_generation, network, repeat, egypt_relevance, destination_evidence, studio_ready). Never a deal value.';

-- 3. Score the opportunity, not fame: research scores (0-5) plus live warmth and contactability (0-5). Followers are not an input.
create or replace function destination_egypt_score(p_egypt jsonb, p_warmth int, p_contact int)
returns int language sql immutable set search_path = public as $$
  select round(
      coalesce(least(greatest((p_egypt->'scores'->>'project_generation')::numeric, 0), 5), 0) * 4
    + coalesce(least(greatest((p_egypt->'scores'->>'network')::numeric, 0), 5), 0) * 4
    + coalesce(least(greatest((p_egypt->'scores'->>'repeat')::numeric, 0), 5), 0) * 3
    + coalesce(least(greatest((p_egypt->'scores'->>'egypt_relevance')::numeric, 0), 5), 0) * 3
    + coalesce(least(greatest((p_egypt->'scores'->>'destination_evidence')::numeric, 0), 5), 0) * 2
    + coalesce(least(greatest(p_warmth, 0), 5), 0) * 2
    + coalesce(least(greatest(p_contact, 0), 5), 0)
    + coalesce(least(greatest((p_egypt->'scores'->>'studio_ready')::numeric, 0), 5), 0))::int
$$;

-- 4. Mission panel (Dashboard): the commercial funnel of mission companies on the canonical layer, progress by bucket, top opportunities.
create or replace function destination_egypt_mission()
returns jsonb language plpgsql stable set search_path = public as $$
declare v jsonb; cfg jsonb := (select value from system_config where key = 'destination_egypt');
begin
  with mo as materialized (
    select distinct on (o.company_id) o.id, o.company_id, o.status, o.egypt, o.next_action, o.next_action_due, o.blocker, o.created_at,
           c.name, c.country, c.universe_status,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) director
      from opportunities o join companies c on c.id = o.company_id
     where o.mission = 'DESTINATION_EGYPT' and o.status <> 'ARCHIVED' and coalesce(c.notes, '') not like '%MERGED_INTO:%'
     order by o.company_id, o.created_at desc),
  cf as materialized (select f.* from commercial_facts() f join mo on mo.company_id = f.company_id),
  es as materialized (select mo.company_id, company_email_state(mo.company_id)->>'state' st from mo),
  x as (
    select mo.*, es.st email_state, cf.first_outreach_at, cf.first_reply_at, cf.inbound_first_at, cf.positive_at, cf.meeting_at, cf.brief_at, cf.proposal_at, cf.won_at,
           case when cf.meeting_at is not null then 5 when cf.positive_at is not null then 4 when cf.first_reply_at is not null or cf.inbound_first_at is not null then 3
                when cf.first_outreach_at is not null then 1 else 0 end warmth,
           case when es.st in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL') then 5 when es.st = 'OFFICIAL_PUBLISHED_INBOX' then 4
                when es.st = 'NEEDS_VERIFICATION' then 2 when es.st in ('FINDER_PENDING', 'RESEARCH_PENDING') then 1 else 0 end contact
      from mo left join cf on cf.company_id = mo.company_id left join es on es.company_id = mo.company_id),
  live as (select * from x where status not in ('LOST') and coalesce(universe_status, '') not in ('EXCLUDED', 'PARKED'))
  select jsonb_build_object(
    'name', cfg->>'name', 'question', cfg->>'question', 'started_at', cfg->>'started_at', 'review_by', cfg->>'review_by',
    'funnel', jsonb_build_object(
      'qualified', (select count(*) from live where universe_status = 'QUALIFIED'),
      'email_ready', (select count(*) from live where email_state in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX')),
      'contacted', (select count(*) from x where first_outreach_at is not null),
      'replied', (select count(*) from x where first_reply_at is not null or inbound_first_at is not null),
      'meetings', (select count(*) from x where meeting_at is not null),
      'briefs', (select count(*) from x where brief_at is not null),
      'proposals', (select count(*) from x where proposal_at is not null),
      'won', (select count(*) from x where won_at is not null),
      'revenue', coalesce((select jsonb_agg(jsonb_build_object('currency', r.currency, 'amount', r.amount)) from (
          select rv.currency, sum(rv.amount) amount from revenue rv join mo on mo.company_id = rv.company_id
           where rv.payment_status <> 'CANCELLED' group by 1) r), '[]'::jsonb)),
    'buckets', (select jsonb_agg(jsonb_build_object('key', b->>'key', 'label', b->>'label', 'target', (b->>'target')::int, 'director', b->>'director',
        'researched', (select count(*) from live where live.egypt->>'bucket' = b->>'key'),
        'email_ready', (select count(*) from live where live.egypt->>'bucket' = b->>'key' and email_state in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX')),
        'contacted', (select count(*) from x where x.egypt->>'bucket' = b->>'key' and first_outreach_at is not null),
        'replied', (select count(*) from x where x.egypt->>'bucket' = b->>'key' and (first_reply_at is not null or inbound_first_at is not null))))
      from jsonb_array_elements(cfg->'buckets') b),
    'top', coalesce((select jsonb_agg(t order by (t->>'score')::int desc, t->>'company') from (
        select jsonb_build_object('opportunity_id', live.id, 'company_id', live.company_id, 'company', live.name, 'country', live.country, 'director', live.director,
          'bucket', live.egypt->>'bucket', 'category', live.egypt->>'category', 'role', live.egypt->>'role', 'project_type', live.egypt->>'project_type',
          'project', live.egypt->>'proposed_project', 'format', live.egypt->>'egypt_format', 'studio_level', live.egypt->>'studio_level',
          'email_state', live.email_state, 'stage', case when live.won_at is not null then 'Won' when live.proposal_at is not null then 'Proposal'
              when live.brief_at is not null then 'Brief' when live.meeting_at is not null then 'Meeting' when live.positive_at is not null then 'Positive'
              when live.first_reply_at is not null or live.inbound_first_at is not null then 'Replied' when live.first_outreach_at is not null then 'Contacted'
              else 'Not contacted' end,
          'next_action', live.next_action, 'blocker', live.blocker,
          'score', destination_egypt_score(live.egypt, live.warmth, live.contact)) t
          from live order by destination_egypt_score(live.egypt, live.warmth, live.contact) desc, live.name limit 10) q), '[]'::jsonb),
    'method', 'Mission companies only, on the canonical model (companies counted once). Score = research scores (project generation, network leverage, repeat potential, Egypt relevance, destination evidence, Studio-ready idea) plus warmth and contactability. Followers are never an input. No deal value is shown until one is recorded.')
  into v;
  return v;
end $$;

-- 5. Weekly CEO intelligence for the mission: what responds, where conversion stops, who gets more resources, what should stop.
create or replace function destination_egypt_learning(p_since timestamptz)
returns jsonb language plpgsql stable set search_path = public as $$
declare v jsonb;
begin
  with mo as materialized (
    select distinct on (o.company_id) o.company_id, o.egypt, c.country,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) director
      from opportunities o join companies c on c.id = o.company_id
     where o.mission = 'DESTINATION_EGYPT' and o.status <> 'ARCHIVED' and coalesce(c.notes, '') not like '%MERGED_INTO:%'
     order by o.company_id, o.created_at desc),
  x as materialized (
    select mo.*, f.first_outreach_at, coalesce(f.first_reply_at, f.inbound_first_at) replied_at, f.positive_at, f.meeting_at, f.proposal_at
      from mo join commercial_facts() f on f.company_id = mo.company_id),
  dims as (
    select 'project_type' dim, coalesce(egypt->>'project_type', 'UNSET') k, x.* from x
    union all select 'director', director, x.* from x
    union all select 'market', coalesce(country, 'Unknown'), x.* from x
    union all select 'studio_level', 'Level ' || coalesce(egypt->>'studio_level', '?'), x.* from x),
  agg as (
    select dim, k,
           count(*) filter (where first_outreach_at is not null) contacted,
           count(*) filter (where replied_at is not null) replied,
           count(*) filter (where positive_at is not null) positive,
           count(*) filter (where meeting_at is not null) meetings,
           count(*) filter (where first_outreach_at >= p_since) contacted_week,
           count(*) filter (where replied_at >= p_since) replied_week,
           count(*) filter (where meeting_at >= p_since) meetings_week
      from dims group by 1, 2),
  tot as (
    select count(*) filter (where first_outreach_at is not null) c, count(*) filter (where replied_at is not null) r,
           count(*) filter (where positive_at is not null) p, count(*) filter (where meeting_at is not null) m,
           count(*) filter (where proposal_at is not null) pr from x)
  select jsonb_build_object(
    'since', p_since,
    'by', (select jsonb_object_agg(dim, rows) from (select dim, jsonb_agg(jsonb_build_object('key', k, 'contacted', contacted, 'replied', replied,
              'positive', positive, 'meetings', meetings, 'contacted_week', contacted_week, 'replied_week', replied_week, 'meetings_week', meetings_week)
              order by replied desc, contacted desc) rows from agg where contacted > 0 or replied > 0 group by dim) d),
    'concepts_with_interest', coalesce((select jsonb_agg(jsonb_build_object('company', c.name, 'level', so.level, 'reply_at', so.reply_at, 'meeting_at', so.meeting_at))
        from studio_outputs so join mo on mo.company_id = so.company_id join companies c on c.id = so.company_id
       where so.reply_at is not null or so.meeting_at is not null), '[]'::jsonb),
    'conversion_stops_at', (select case when t.c = 0 then 'Nothing contacted yet: the mission is still in research.'
        when t.r = 0 then 'Contacted to reply (' || t.c || ' contacted, no reply yet).'
        when t.m = 0 then 'Reply to meeting (' || t.r || ' replied, no meeting yet).'
        when t.pr = 0 then 'Meeting to proposal (' || t.m || ' meetings, no proposal yet).'
        else 'Proposal to win.' end from tot t),
    'more_resources', (select 'Most replies per company contacted: ' || k || ' (' || replied || ' of ' || contacted || ').'
        from agg where dim = 'director' and contacted >= 5 order by replied::numeric / contacted desc, contacted desc limit 1),
    'stop', coalesce((select jsonb_agg(k || ': ' || contacted || ' contacted, no reply') from agg where dim = 'project_type' and contacted >= 8 and replied = 0), '[]'::jsonb),
    'note', 'Rates are only read from 5 companies contacted per Director and 8 per project type. Before that this is information, not a verdict.')
  into v;
  return v;
end $$;

revoke all on function destination_egypt_score(jsonb, int, int) from public, anon, authenticated;
revoke all on function destination_egypt_mission() from public, anon, authenticated;
revoke all on function destination_egypt_learning(timestamptz) from public, anon, authenticated;

-- 6. Dashboard (snapshot 'command') and weekly review carry the mission
do $do$
declare v_src text; a text; b text;
begin
  v_src := pg_get_functiondef('hq_command()'::regprocedure);
  a := $a$    'integrity', (select jsonb_build_object('generated_at', payload->'generated_at'$a$;
  b := $a$    'destination_egypt', destination_egypt_mission(),
    'integrity', (select jsonb_build_object('generated_at', payload->'generated_at'$a$;
  if (length(v_src) - length(replace(v_src, a, ''))) / length(a) <> 1 then raise exception 'hq_command anchor does not match exactly once'; end if;
  execute replace(v_src, a, b);

  v_src := pg_get_functiondef('hq_weekly_review()'::regprocedure);
  a := $a$'attribution', commercial_cohorts(8),$a$;
  b := $a$'destination_egypt', destination_egypt_learning(now() - interval '7 days'), 'attribution', commercial_cohorts(8),$a$;
  if (length(v_src) - length(replace(v_src, a, ''))) / length(a) <> 1 then raise exception 'hq_weekly_review anchor does not match exactly once'; end if;
  execute replace(v_src, a, b);
end $do$;

-- 7. Directors own their part: work orders carry the programme, and a programme work order only counts mission companies
create or replace function work_order_companies(p_spec jsonb)
returns table (company_id uuid) language sql stable set search_path = public as $$
  select c.id from companies c
   where coalesce(c.notes, '') not like '%MERGED_INTO:%'
     and coalesce(c.universe_status, '') not in ('EXCLUDED', 'PARKED')
     and (p_spec->>'director' is null
          or agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) = p_spec->>'director')
     and (p_spec->>'programme' is null
          or exists (select 1 from opportunities o where o.company_id = c.id and o.mission = p_spec->>'programme' and o.status <> 'ARCHIVED'))
     and not exists (select 1 from jsonb_array_elements_text(coalesce(p_spec->'terms', '[]'::jsonb)) t(term)
                      where btrim(t.term) <> ''
                        and lower(concat_ws(' ', c.name, c.company_type, c.sector, c.country, c.city, c.prospect_segment, c.universe_reason, c.notes))
                            !~ work_order_term_re(t.term))
$$;

insert into tasks (title, description, task_type, assigned_to, created_by, priority, status, due_at, spec)
select 'WORK ORDER -- ' || r.name || ': Destination Egypt — ' || w.mission,
       'Destination Egypt mission (Adam, 19 Oct). Research target: ' || w.goal || ' high-quality accounts with real evidence, a project hypothesis, the right person, a source-backed route and a next action, by 18 Nov 2026. Research targets are not outreach quotas. Status is computed from evidence (work_order_eval).',
       'WORK_ORDER', w.director, 'Adam (HQ)', 90, 'WAITING', (('2026-11-19'::date)::timestamp at time zone 'Africa/Cairo') - interval '1 second',
       jsonb_build_object('director', w.director, 'mission', 'Destination Egypt — ' || w.mission, 'target', 'Destination Egypt mission companies', 'terms', '[]'::jsonb,
         'metric', 'QUALIFIED_TARGETS', 'goal', w.goal, 'deadline', '2026-11-18', 'priority', 'P1', 'issued_at', now(),
         'issued_by', 'Adam (Destination Egypt mission, 19 Oct 2026)', 'programme', 'DESTINATION_EGYPT', 'bucket', w.bucket, 'baseline_email_ready', 0)
  from (values ('BRANDS', 'BRAND_PRODUCTION', 20, 'brands and agencies with evidence of destination shoots, creator trips, launches or campaigns abroad'),
               ('WEDDINGS', 'WEDDINGS', 20, 'international wedding planners and event producers who own UHNW client relationships'),
               ('PRIVATE', 'PRIVATE_CLUBS', 15, 'private clubs, founder and executive communities that already take members abroad'),
               ('TRAVEL', 'TRAVEL', 15, 'travel advisors, concierge companies and advisor networks that keep the client while NOYA runs Egypt'),
               ('MEDIA', 'MEDIA', 15, 'podcasts, media companies and production studios with a filmable Egypt concept'),
               ('SPORTS', 'NOYA_PRIVATE', 10, 'football and talent representatives with rosters (representation first, never named clients)'),
               ('CORPORATE', 'CORPORATE', 5, 'corporate retreat and executive-event organisers')) w(director, bucket, goal, mission)
  join agent_registry r on r.key = w.director
 where not exists (select 1 from tasks t where t.task_type = 'WORK_ORDER' and t.spec->>'programme' = 'DESTINATION_EGYPT' and t.spec->>'director' = w.director);

-- 8. Decision makers by category (role priority): agency leaders, club experiences and partnerships, media commercial
create or replace function role_focus(p_segment text)
returns text[] language sql immutable set search_path = public as $$
  select case p_segment
    when 'HOTEL' then array['general manager', 'hotel manager', 'director of sales', 'director of sales and marketing', 'commercial director', 'partnerships',
                            'marketing director', 'marketing manager', 'communications', 'owner', 'managing director', 'guest relations director', 'chef concierge']
    when 'VILLA' then array['founder', 'owner', 'managing director', 'head of sales', 'partnerships', 'operations director', 'guest experience',
                            'commercial director', 'portfolio director']
    when 'TRAVEL' then array['founder', 'managing director', 'commercial director', 'partnerships', 'head of product', 'head of travel',
                             'supplier relations', 'destination director', 'head of trade', 'b2b']
    when 'WEDDINGS' then array['founder', 'managing director', 'creative director', 'destination director', 'partnerships', 'owner', 'lead planner',
                               'partner', 'events director']
    when 'BRANDS' then array['marketing director', 'head of brand', 'brand director', 'global pr', 'head of communications', 'partnerships director',
                             'experiential director', 'influencer marketing', 'creative producer', 'executive producer', 'production director',
                             'account director', 'head of marketing', 'brand partnerships', 'pr director', 'head of production', 'creative director',
                             'talent manager', 'partnerships', 'founder', 'managing director', 'managing partner']
    when 'MEDIA' then array['founder', 'host', 'executive producer', 'partnerships', 'commercial director', 'editor', 'head of content', 'producer', 'commercial']
    when 'CORPORATE' then array['travel manager', 'executive assistant', 'chief of staff', 'head of events', 'workplace experience', 'partnerships',
                                'travel procurement', 'office of the ceo', 'corporate travel']
    when 'CLUB' then array['founder', 'membership director', 'experiences director', 'head of partnerships', 'partnerships director', 'events director',
                           'general manager', 'concierge']
    when 'SPORTS' then array['founder', 'managing director', 'senior agent', 'agent', 'player manager', 'personal manager', 'business manager',
                             'player care', 'player services', 'lifestyle', 'client services', 'commercial director', 'partnerships',
                             'operations director', 'travel', 'logistics', 'talent manager', 'artist manager', 'publicist', 'tour manager',
                             'booking agent', 'executive assistant', 'player liaison', 'team operations', 'international relations']
    else array['founder', 'director', 'head of partnerships', 'commercial director'] end
$$;

-- 9. Studio becomes visible: requests from HQ, the pipeline by state, and the Studio team
create table if not exists studio_requests (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('IDEA', 'ONE_PAGE_CONCEPT', 'BRIEF', 'PROPOSAL', 'ITINERARY', 'RETREAT_CONCEPT', 'WEDDING_CONCEPT',
                                     'BRAND_CAMPAIGN_CONCEPT', 'MEDIA_CONCEPT')),
  level smallint not null check (level between 1 and 3),
  company_id uuid references companies (id),
  opportunity_id uuid references opportunities (id),
  note text,
  status text not null default 'REQUESTED' check (status in ('REQUESTED', 'IN_PROGRESS', 'DONE', 'CANCELLED')),
  document_slug text,
  requested_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
alter table studio_requests enable row level security;
revoke all on table studio_requests from anon, authenticated;
comment on table studio_requests is 'Studio work Adam asks for from HQ. The Studio team builds it with studio/build.mjs at the level the relationship has earned (a higher level is prepared and held, never sent early). Nothing is sent.';

create or replace function hq_studio_request(p_kind text, p_company uuid, p_opportunity uuid default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_kind text := upper(btrim(coalesce(p_kind, ''))); v_company uuid := p_company; v_id uuid; v_level smallint;
begin
  if v_kind not in ('IDEA', 'ONE_PAGE_CONCEPT', 'BRIEF', 'PROPOSAL', 'ITINERARY', 'RETREAT_CONCEPT', 'WEDDING_CONCEPT', 'BRAND_CAMPAIGN_CONCEPT', 'MEDIA_CONCEPT') then
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_KIND'); end if;
  if v_company is null and p_opportunity is not null then select company_id into v_company from opportunities where id = p_opportunity; end if;
  if v_company is null or not exists (select 1 from companies where id = v_company) then return jsonb_build_object('ok', false, 'reason', 'COMPANY_REQUIRED'); end if;
  v_level := case v_kind when 'IDEA' then 1 when 'ONE_PAGE_CONCEPT' then 2 else 3 end;
  if exists (select 1 from studio_requests where company_id = v_company and kind = v_kind and status in ('REQUESTED', 'IN_PROGRESS')) then
    return jsonb_build_object('ok', false, 'reason', 'ALREADY_REQUESTED'); end if;
  insert into studio_requests (kind, level, company_id, opportunity_id, note, requested_by)
  values (v_kind, v_level, v_company, p_opportunity, hq_trim(p_note), v_admin) returning id into v_id;
  perform hq_audit('STUDIO_REQUESTED', p_opportunity, jsonb_build_object('request_id', v_id, 'kind', v_kind, 'company_id', v_company));
  return jsonb_build_object('ok', true, 'id', v_id, 'level', v_level);
end $$;

create or replace function hq_studio_request_action(p_id uuid, p_action text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); n int;
begin
  if upper(coalesce(p_action, '')) <> 'CANCEL' then return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION'); end if;
  update studio_requests set status = 'CANCELLED', updated_at = now() where id = p_id and status in ('REQUESTED', 'IN_PROGRESS');
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  perform hq_audit('STUDIO_REQUEST_CANCELLED', null, jsonb_build_object('request_id', p_id, 'by', v_admin));
  return jsonb_build_object('ok', true);
end $$;

create or replace function hq_studio()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with d as materialized (
    select sd.id, sd.slug, sd.version, sd.doc_type, sd.title, sd.company_id, sd.opportunity_id, sd.prepared_for, sd.status, sd.vertical, sd.stage, sd.level,
           sd.file_name, sd.file_location, sd.created_at, sd.approved_at, sd.sent_at, sd.hold_reason, c.name company,
           (sd.qa is not null) qa_passed
      from studio_documents sd left join companies c on c.id = sd.company_id),
  item as (
    select d.*, jsonb_build_object('id', d.id, 'slug', d.slug, 'version', d.version, 'title', coalesce(d.title, d.slug), 'doc_type', d.doc_type, 'stage', d.stage,
             'level', d.level, 'vertical', d.vertical, 'company', coalesce(d.company, d.prepared_for), 'company_id', d.company_id, 'opportunity_id', d.opportunity_id,
             'status', d.status, 'created_at', d.created_at, 'approved_at', d.approved_at, 'sent_at', d.sent_at, 'hold_reason', d.hold_reason, 'file', d.file_name) j
      from d),
  req as (
    select r.*, c.name company from studio_requests r left join companies c on c.id = r.company_id),
  roles(key, name, main, does, doc_types, verticals) as (values
    ('BRIEF_PROPOSAL', 'Brief & Proposal Architect', true, 'Turns a reply or a meeting into the opportunity note, the brief and the proposal (fees stay unapproved until Adam approves them).',
       array['OPPORTUNITY_NOTE', 'BRIEF', 'PROPOSAL', 'PROJECT'], null::text[]),
    ('CREATIVE_DIRECTOR', 'Creative Director & Brand Guardian', false, 'Holds the NOYA house style, the approved wording and the level each relationship has earned.', null::text[], null::text[]),
    ('BRAND_CONCEPT', 'Brand & Production Concept Architect', false, 'Email ideas, one-page concepts and concepts for brand, campaign, production and media projects.',
       array['EMAIL_IDEA', 'ONE_PAGE_CONCEPT', 'CONCEPT'], array['brand', 'media']),
    ('ITINERARY', 'Itinerary Architect', false, 'Client itineraries (marked indicative) and the internal operations itinerary.', array['ITINERARY', 'OPS_ITINERARY'], null::text[]),
    ('WEDDING_EVENT', 'Wedding & Private Event Architect', false, 'Wedding, celebration and retreat concepts where the planner or club keeps the client.',
       array['EMAIL_IDEA', 'ONE_PAGE_CONCEPT', 'CONCEPT'], array['weddings', 'retreat']),
    ('PRIVATE_EXPERIENCE', 'NOYA Private Experience Architect', false, 'NOYA Private desk briefs for representatives: discreet, no client named.', null::text[], array['private']),
    ('SUPPLIER_QUOTE', 'Supplier & Quote Intelligence', false, 'Supplier options and quotes for live projects (named only once confirmed).', null::text[], null::text[]),
    ('QUALITY_REVIEWER', 'Brand & Quality Reviewer', false, 'Runs the QA gate on every document before Adam sees it: facts with provenance, level, layout, wording.', null::text[], null::text[])),
  rd as (
    select r.key, d.* from roles r join d on (r.doc_types is null or d.doc_type = any(r.doc_types)) and (r.verticals is null or d.vertical = any(r.verticals))
     where r.key not in ('CREATIVE_DIRECTOR', 'SUPPLIER_QUOTE', 'QUALITY_REVIEWER')
    union all select 'CREATIVE_DIRECTOR', d.* from d where d.status in ('FOR_REVIEW', 'APPROVED')
    union all select 'QUALITY_REVIEWER', d.* from d where d.qa_passed)
  select jsonb_build_object(
    'generated_at', now(),
    'levels', jsonb_build_array(
      jsonb_build_object('level', 1, 'label', 'Level 1 · Email idea', 'when', 'Any prospect, including cold: the idea inside the email, no attachment.'),
      jsonb_build_object('level', 2, 'label', 'Level 2 · One-page concept', 'when', 'Warm (they replied), or cold with a dated public trigger.'),
      jsonb_build_object('level', 3, 'label', 'Level 3 · Full brief / proposal', 'when', 'After demonstrated interest, a meeting or an actual brief.')),
    'columns', jsonb_build_object(
      'NEEDS_BRIEF', jsonb_build_object(
        'requests', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'level', level, 'company', company, 'company_id', company_id,
            'opportunity_id', opportunity_id, 'note', note, 'status', status, 'created_at', created_at) order by created_at desc)
            from req where status in ('REQUESTED', 'IN_PROGRESS')), '[]'::jsonb),
        'warmed', coalesce((select jsonb_agg(jsonb_build_object('company', q.company, 'company_id', q.company_id, 'lane', q.lane, 'warmed_at', q.warmed_at,
            'earned_level', q.earned_level, 'next_output', q.next_output) order by q.warmed_at desc) from studio_queue q), '[]'::jsonb)),
      'DRAFTING', coalesce((select jsonb_agg(j order by created_at desc) from item where status = 'DRAFT'), '[]'::jsonb),
      'NEEDS_REVIEW', coalesce((select jsonb_agg(j order by created_at desc) from item where status = 'FOR_REVIEW'), '[]'::jsonb),
      'APPROVED', coalesce((select jsonb_agg(j order by approved_at desc nulls last) from item where status = 'APPROVED' and sent_at is null), '[]'::jsonb),
      'SENT', coalesce((select jsonb_agg(x order by x->>'sent_at' desc) from (
          select j x from item where sent_at is not null
          union all select jsonb_build_object('id', so.id, 'title', coalesce(so.document_slug, so.email_slug, so.case_slug), 'level', so.level,
                   'company', c.name, 'company_id', so.company_id, 'status', 'SENT', 'sent_at', so.sent_at, 'reply_at', so.reply_at, 'meeting_at', so.meeting_at)
            from studio_outputs so left join companies c on c.id = so.company_id where so.status = 'SENT') s), '[]'::jsonb),
      'SUPERSEDED', jsonb_build_object('count', (select count(*) from item where status = 'SUPERSEDED'),
          'recent', coalesce((select jsonb_agg(j) from (select j from item where status = 'SUPERSEDED' order by created_at desc limit 8) s), '[]'::jsonb))),
    'outputs', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'company', s.company, 'level', s.level, 'level_label', s.level_label, 'status', s.status,
        'next_step', s.next_step, 'send_after', s.send_after, 'sent_at', s.sent_at, 'reply_at', s.reply_at, 'meeting_at', s.meeting_at) order by s.prepared_at desc)
        from studio_output_status s), '[]'::jsonb),
    'team', (select jsonb_agg(jsonb_build_object('key', r.key, 'name', r.name, 'main', r.main, 'does', r.does,
        'drafting', (select count(*) from rd where rd.key = r.key and rd.status = 'DRAFT'),
        'needs_review', (select count(*) from rd where rd.key = r.key and rd.status = 'FOR_REVIEW'),
        'approved', (select count(*) from rd where rd.key = r.key and rd.status = 'APPROVED' and rd.sent_at is null),
        'sent', (select count(*) from rd where rd.key = r.key and rd.sent_at is not null),
        'quotes', case when r.key = 'SUPPLIER_QUOTE' then (select count(*) from project_items pi where pi.supplier_company_id is not null) end,
        'qa_passed', case when r.key = 'QUALITY_REVIEWER' then (select count(*) from d where d.qa_passed) end,
        'last', (select jsonb_build_object('title', coalesce(rd.title, rd.slug), 'company', coalesce(rd.company, rd.prepared_for), 'status', rd.status, 'at', rd.created_at)
                   from rd where rd.key = r.key order by rd.created_at desc limit 1),
        'current', (select coalesce(jsonb_agg(jsonb_build_object('title', coalesce(t.title, t.slug), 'company', coalesce(t.company, t.prepared_for), 'status', t.status, 'at', t.created_at)), '[]'::jsonb)
                      from (select * from rd where rd.key = r.key and rd.status in ('DRAFT', 'FOR_REVIEW') order by rd.created_at desc limit 6) t))
        order by r.main desc, r.name) from roles r),
    'architect', jsonb_build_object(
      'current', coalesce((select jsonb_agg(j order by created_at desc) from item where doc_type in ('OPPORTUNITY_NOTE', 'BRIEF', 'PROPOSAL', 'PROJECT') and status in ('DRAFT', 'FOR_REVIEW')), '[]'::jsonb),
      'briefs', coalesce((select jsonb_agg(j order by created_at desc) from item where doc_type = 'BRIEF' and status <> 'SUPERSEDED'), '[]'::jsonb),
      'concepts_ready', coalesce((select jsonb_agg(j order by created_at desc) from item where doc_type in ('CONCEPT', 'ONE_PAGE_CONCEPT', 'EMAIL_IDEA') and status in ('FOR_REVIEW', 'APPROVED') and sent_at is null), '[]'::jsonb),
      'proposals', coalesce((select jsonb_agg(j order by created_at desc) from item where doc_type = 'PROPOSAL' and status <> 'SUPERSEDED'), '[]'::jsonb),
      'needs_adam', coalesce((select jsonb_agg(x) from (
          select jsonb_build_object('what', 'Review ' || lower(replace(doc_type, '_', ' ')), 'title', coalesce(title, slug), 'company', coalesce(company, prepared_for), 'at', created_at) x
            from item where status = 'FOR_REVIEW'
          union all select jsonb_build_object('what', s.next_step, 'title', coalesce(s.document_slug, s.case_slug), 'company', s.company, 'at', s.prepared_at)
            from studio_output_status s where s.status = 'PREPARED') q), '[]'::jsonb),
      'last_outputs', coalesce((select jsonb_agg(j) from (select j from item where status <> 'SUPERSEDED' order by created_at desc limit 8) s), '[]'::jsonb)),
    'actions', jsonb_build_array(
      jsonb_build_object('kind', 'IDEA', 'label', 'Create idea', 'level', 1), jsonb_build_object('kind', 'ONE_PAGE_CONCEPT', 'label', 'Create one-page concept', 'level', 2),
      jsonb_build_object('kind', 'BRIEF', 'label', 'Create brief', 'level', 3), jsonb_build_object('kind', 'PROPOSAL', 'label', 'Create proposal', 'level', 3),
      jsonb_build_object('kind', 'ITINERARY', 'label', 'Create itinerary', 'level', 3), jsonb_build_object('kind', 'RETREAT_CONCEPT', 'label', 'Create retreat concept', 'level', 3),
      jsonb_build_object('kind', 'WEDDING_CONCEPT', 'label', 'Create wedding concept', 'level', 3),
      jsonb_build_object('kind', 'BRAND_CAMPAIGN_CONCEPT', 'label', 'Create brand campaign concept', 'level', 3),
      jsonb_build_object('kind', 'MEDIA_CONCEPT', 'label', 'Create media concept', 'level', 3)),
    'rules', 'Studio prepares, Adam approves and sends. A document above the level the relationship has earned is prepared and held, never sent early. Nothing promises a permit or access that has not been verified.')
  into v;
  return v;
end $$;

revoke all on function hq_studio() from public, anon;
revoke all on function hq_studio_request(text, uuid, uuid, text) from public, anon;
revoke all on function hq_studio_request_action(uuid, text) from public, anon;
grant execute on function hq_studio() to authenticated;
grant execute on function hq_studio_request(text, uuid, uuid, text) to authenticated;
grant execute on function hq_studio_request_action(uuid, text) to authenticated;
