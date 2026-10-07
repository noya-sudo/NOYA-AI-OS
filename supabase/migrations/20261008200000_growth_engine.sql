-- NOYA Growth Engine (Adam brief, 7 Oct 2026): continuous agents, 60-75 outreach-ready prospects per 3-day cycle,
-- 500+ company universe. Quality bar unchanged: a prospect counts only with company, person, role, evidence,
-- commercial reason, channel and a finished message. Nothing is sent automatically.

-- ---------------------------------------------------------------- lanes = agents
-- PARTNERSHIPS   Agent 1  Hospitality & strategic partnerships (hotels, villas, residences, groups, aviation, yachts, chauffeur, security, DMCs, event hospitality)
-- BRANDS         Agent 2  Brands / PR / production
-- WEDDINGS       Agent 3  Weddings & events
-- TRAVEL_PRIVATE Agent 4  Travel / concierge / private-client network (advisors, travel designers, concierge & lifestyle firms, clubs, family & private offices, EAs)
-- CORPORATE      Agent 5  Corporate
-- SPORTS_PRIVATE Agent 6  Sports / talent / entertainment
-- EGYPT_EVENTS   Egypt event signals (routed by workflow 17; no fixed daily slots)
alter table public.companies drop constraint if exists companies_acquisition_lane_check;
alter table public.companies add constraint companies_acquisition_lane_check check (acquisition_lane is null or acquisition_lane in
  ('BRANDS', 'PARTNERSHIPS', 'WEDDINGS', 'EGYPT_EVENTS', 'CORPORATE', 'SPORTS_PRIVATE', 'TRAVEL_PRIVATE'));

create or replace function public.company_lane(p_lane text, p_segment text, p_vertical_override text, p_company_type text)
returns text language sql immutable as $$
  select coalesce(p_lane, case
    when p_segment = 'BRAND_PR_PRODUCTION' then 'BRANDS'
    when p_segment = 'HOTELS_HOSPITALITY' then 'PARTNERSHIPS'
    when p_segment in ('TRAVEL_PARTNER', 'MEMBER_COMMUNITIES', 'PRIVATE_OFFICE') then 'TRAVEL_PRIVATE'
    when p_segment = 'WEDDING_EVENTS' then 'WEDDINGS'
    when p_segment = 'LIVE_SIGNAL' then 'EGYPT_EVENTS'
    when p_segment = 'CORPORATE_EVENTS' then 'CORPORATE'
    when p_segment = 'TALENT' then 'SPORTS_PRIVATE'
    when coalesce(p_company_type, '') ~* '(hotel|resort|villa|residence|apart|hospitality|aviation|jet|yacht|marina|chauffeur|limousine|security|protection|dmc|destination management)' then 'PARTNERSHIPS'
    when coalesce(p_company_type, '') ~* '(travel|concierge|lifestyle|members|club|family office|private office|assistant)' then 'TRAVEL_PRIVATE'
    when coalesce(p_company_type, '') ~* '(wedding|event planner|celebration)' then 'WEDDINGS'
    when coalesce(p_company_type, '') ~* '(brand|fashion|beauty|jewel|watch|agency|production|studio|pr )' then 'BRANDS'
    when coalesce(p_company_type, '') ~* '(sport|football|athlete|talent|entertainment)' then 'SPORTS_PRIVATE'
    else 'CORPORATE' end)
$$;

-- Department (agent) source -> lane. Agents save with source "NOYA <Department name> v1" (06/07 prefix "0n - ").
create or replace function public.agent_lane(p_source text, p_company_type text, p_sector text)
returns text language sql immutable as $$
  select case
    when coalesce(p_source, '') ~* 'Hotels & Content' then 'PARTNERSHIPS'
    when coalesce(p_source, '') ~* 'Brand & Production' then 'BRANDS'
    when coalesce(p_source, '') ~* 'Weddings & Events' then 'WEDDINGS'
    when coalesce(p_source, '') ~* 'Creators & Talent' then 'SPORTS_PRIVATE'
    when coalesce(p_source, '') ~* 'Global Partnerships' then case
      when coalesce(p_company_type, '') || ' ' || coalesce(p_sector, '') ~* '(hotel|resort|villa|residence|hospitality|aviation|jet|yacht|marina|chauffeur|limousine|security|protection|dmc|destination management|event hospitality)' then 'PARTNERSHIPS'
      when coalesce(p_company_type, '') || ' ' || coalesce(p_sector, '') ~* '(sport|athlete|talent|entertainment)' then 'SPORTS_PRIVATE'
      when coalesce(p_company_type, '') || ' ' || coalesce(p_sector, '') ~* '(wedding|event)' then 'WEDDINGS'
      else 'TRAVEL_PRIVATE' end
    when coalesce(p_source, '') ~* 'Corporate & Private' then case
      when coalesce(p_company_type, '') || ' ' || coalesce(p_sector, '') ~* '(family office|private office|members|club|concierge|lifestyle|travel)' then 'TRAVEL_PRIVATE'
      when coalesce(p_company_type, '') || ' ' || coalesce(p_sector, '') ~* '(sport|football|athlete|talent)' then 'SPORTS_PRIVATE'
      else 'CORPORATE' end
    else null end
$$;

-- ---------------------------------------------------------------- intake: every new agent record is classified on arrival
-- Company: RESEARCHING with its reason (from the agent's "Why NOYA" line) and lane; watchlist saves are PARKED.
create or replace function public.company_intake()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.acquisition_lane is null then
    new.acquisition_lane := coalesce(agent_lane(new.source, new.company_type, new.sector),
                                     company_lane(null, new.prospect_segment, new.vertical_override, new.company_type));
  end if;
  if coalesce(new.source, '') ~* 'NOYA .*Department' then
    if new.universe_status is null then
      new.universe_status := case when new.source ~* 'watchlist' then 'PARKED' else 'RESEARCHING' end;
    end if;
    new.universe_added_at := coalesce(new.universe_added_at, now());
    new.universe_reason := coalesce(nullif(btrim(new.universe_reason), ''),
      nullif(btrim(substring(coalesce(new.notes, '') from 'Why NOYA:\s*([^\n]+)')), ''),
      nullif(btrim(substring(coalesce(new.notes, '') from 'Research summary:\s*([^\n]+)')), ''));
  end if;
  return new;
end $$;
create or replace trigger company_intake before insert on public.companies for each row execute function public.company_intake();

-- Contact: CONFIRMED only with a name, a role and a source (a LinkedIn profile URL or a source-backed note);
-- a name without a source is NEEDS_VERIFICATION (shown as "Likely - verify"); no person = company stays RESEARCHING ("Person required").
create or replace function public.contact_intake()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.identity_status is null and coalesce(new.first_name, new.last_name) is not null then
    new.identity_status := case
      when new.position is not null and (coalesce(new.linkedin, '') ~* 'linkedin\.com/in/' or coalesce(new.notes, '') ~* '(source-backed|verified)')
        then 'CONFIRMED' else 'NEEDS_VERIFICATION' end;
  end if;
  return new;
end $$;
create or replace trigger contact_intake before insert or update of linkedin, position, notes, first_name, last_name on public.contacts
  for each row execute function public.contact_intake();

-- Re-qualify the company whenever one of its people changes (same rules as universe_reclassify, one company).
create or replace function public.universe_reclassify_company(p_company uuid)
returns text language plpgsql security definer set search_path = public as $$
declare c record; r jsonb; v text;
begin
  select id, universe_status, universe_reason into c from companies where id = p_company;
  if c.id is null or c.universe_status not in ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING') then return c.universe_status; end if;
  r := company_reach(c.id);
  v := case
    when (r->>'people')::int = 0 then 'RESEARCHING'
    when length(btrim(coalesce(c.universe_reason, ''))) >= 20 and (r->>'confirmed')::int > 0
         and ((r->>'verified_email')::boolean or (r->>'linkedin')::boolean or (r->>'instagram')::boolean) then 'QUALIFIED'
    else 'NEEDS_REVIEW' end;
  if v is distinct from c.universe_status then update companies set universe_status = v where id = c.id; end if;
  return v;
end $$;
create or replace function public.contact_requalify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.company_id is not null then perform universe_reclassify_company(new.company_id); end if;
  return new;
end $$;
create or replace trigger contact_requalify after insert or update of identity_status, position, linkedin, email_status, do_not_contact, company_id on public.contacts
  for each row execute function public.contact_requalify();
revoke all on function public.universe_reclassify_company(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- targets
-- Research never pauses because messages are waiting (Adam: supply and execution both run). Cap 10 per department per day.
-- Daily mix ~ Adam's 3-day allocation (20/15/10/10/10/5): the planner scales these by target/20 and fills leftovers.
create or replace function public.ops_growth_config() returns jsonb language plpgsql security definer set search_path = public as $f$
begin
  update system_config set value = value || '{"pause_at_backlog": 100000, "reduce_at_backlog": 100000, "normal_research_cap": 10, "reduced_research_cap": 10, "paused_research_cap": 10}'::jsonb
   where key = 'discovery_throttle';
  insert into system_config (key, value) values
    ('acquisition_mix', '{"PARTNERSHIPS": 6, "BRANDS": 4, "TRAVEL_PRIVATE": 3, "WEDDINGS": 3, "CORPORATE": 3, "SPORTS_PRIVATE": 1, "EGYPT_EVENTS": 0}'::jsonb),
    ('daily_touch_target', '{"floor": 20, "target": 23, "cycle_days": 3, "cycle_floor": 60, "cycle_target": 75}'::jsonb)
  on conflict (key) do update set value = excluded.value;
  -- lanes for existing records under the new agent map
  update companies set acquisition_lane = coalesce(agent_lane(source, company_type, sector), company_lane(null, prospect_segment, vertical_override, company_type))
   where universe_status is not null and (acquisition_lane is null or prospect_segment in ('TRAVEL_PARTNER', 'MEMBER_COMMUNITIES', 'PRIVATE_OFFICE') or source ~* 'NOYA .*Department');
  -- agent saves that arrived before intake existed
  update companies set universe_status = case when source ~* 'watchlist' then 'PARKED' else 'RESEARCHING' end,
         universe_added_at = coalesce(universe_added_at, created_at),
         universe_reason = coalesce(universe_reason, nullif(btrim(substring(coalesce(notes, '') from 'Why NOYA:\s*([^\n]+)')), ''))
   where universe_status is null and source ~* 'NOYA .*Department';
  return (select value from system_config where key = 'acquisition_mix');
end $f$;
revoke all on function public.ops_growth_config() from public, anon, authenticated;
select public.ops_growth_config();
select public.universe_reclassify();

-- ---------------------------------------------------------------- 3-day cycle report (system records only)
create or replace function public.growth_cycle_report(p_since timestamptz default now() - interval '3 days')
returns jsonb language sql stable security definer set search_path = public as $$
  with lane_name(lane, agent) as (values ('PARTNERSHIPS', 'Hospitality & strategic partnerships'), ('BRANDS', 'Brands / PR / production'),
         ('TRAVEL_PRIVATE', 'Travel / concierge / private network'), ('WEDDINGS', 'Weddings & events'), ('CORPORATE', 'Corporate'),
         ('SPORTS_PRIVATE', 'Sports / talent / entertainment'), ('EGYPT_EVENTS', 'Egypt event signals')),
  co as (select c.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane
           from companies c where coalesce(c.universe_added_at, c.created_at) >= p_since),
  ppl as (select k.*, co.lane from contacts k join co on co.id = k.company_id where coalesce(k.first_name, k.last_name) is not null),
  ready as (select t.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane
              from tasks t join companies c on c.id = t.company_id
             where t.created_at >= p_since and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|EMAIL READY)'),
  runs as (select * from department_run_metrics where recorded_at >= p_since),
  per as (
    select l.lane, l.agent,
      (select count(*) from co where co.lane = l.lane) discovered,
      (select count(*) from co where co.lane = l.lane and co.universe_status = 'QUALIFIED') qualified,
      (select count(*) from co where co.lane = l.lane and co.universe_status in ('RESEARCHING', 'NEEDS_REVIEW')) research_required,
      (select count(*) from co where co.lane = l.lane and co.universe_status = 'PARKED') parked,
      (select count(*) from ppl where ppl.lane = l.lane) named_people,
      (select count(*) from ppl where ppl.lane = l.lane and ppl.identity_status = 'CONFIRMED') confirmed_people,
      (select count(*) from ppl where ppl.lane = l.lane and ppl.identity_status = 'CONFIRMED' and ppl.email_status = 'VERIFIED') email_ready,
      (select count(*) from ppl where ppl.lane = l.lane and ppl.identity_status = 'CONFIRMED' and coalesce(ppl.linkedin, '') ~* 'linkedin\.com/in/') linkedin_ready,
      (select count(*) from ready where ready.lane = l.lane) outreach_ready
    from lane_name l)
  select jsonb_build_object(
    'since', p_since, 'target', (select value from system_config where key = 'daily_touch_target'),
    'totals', (select jsonb_build_object('discovered', sum(discovered), 'qualified', sum(qualified), 'research_required', sum(research_required),
        'parked', sum(parked), 'named_people', sum(named_people), 'confirmed_people', sum(confirmed_people), 'email_ready', sum(email_ready),
        'linkedin_ready', sum(linkedin_ready), 'outreach_ready', sum(outreach_ready)) from per),
    'rejected_by_agents', (select coalesce(sum(coalesce((metrics->'report_counts'->>'rejected')::int, (metrics->'report_counts'->>'REJECTED')::int, 0)), 0) from runs),
    'agents', (select jsonb_agg(to_jsonb(per) order by per.outreach_ready desc, per.discovered desc) from per),
    'by_country', (select coalesce(jsonb_object_agg(country, n), '{}'::jsonb) from (select coalesce(nullif(country, ''), 'UNKNOWN') country, count(*) n from co group by 1 order by 2 desc limit 25) s),
    'by_vertical', (select coalesce(jsonb_object_agg(v, n), '{}'::jsonb) from (select coalesce(nullif(company_type, ''), 'unspecified') v, count(*) n from co group by 1 order by 2 desc limit 25) s),
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('workflow', workflow_name, 'at', recorded_at,
        'serper_searches', metrics->>'serper_searches', 'candidates_found', metrics->>'candidates_found', 'research_cap', metrics->>'research_cap',
        'deep_researched', metrics->>'deep_researched', 'qualified', metrics->>'qualified', 'provider_failures', metrics->>'provider_failures',
        'throttle', metrics->>'throttle_level') order by recorded_at), '[]'::jsonb) from runs),
    'cost', jsonb_build_object(
        'drafting_usd', (select coalesce(round(sum(est_cost_usd), 4), 0) from ai_usage where at >= p_since),
        'drafting_calls', (select count(*) from ai_usage where at >= p_since),
        'serper_searches', (select coalesce(sum((metrics->>'serper_searches')::int), 0) from runs),
        'research_ai_calls_estimated', (select coalesce(sum((metrics->>'ai_calls_estimated')::int), 0) from runs),
        'hunter_credits', 0),
    'note', 'A prospect counts as outreach-ready only when HQ holds company, person, role, evidence, reason, channel and a finished message (a READY task).')
$$;
revoke all on function public.growth_cycle_report(timestamptz) from public, anon;
grant execute on function public.growth_cycle_report(timestamptz) to authenticated;

-- ---------------------------------------------------------------- weekly agent performance (recommendations only)
create or replace function public.agent_performance(p_weeks int default 1)
returns jsonb language sql stable security definer set search_path = public as $$
  with since as (select now() - make_interval(weeks => greatest(1, least(coalesce(p_weeks, 1), 12))) t),
  c as (select c.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane from companies c),
  lanes(lane) as (values ('PARTNERSHIPS'), ('BRANDS'), ('TRAVEL_PRIVATE'), ('WEDDINGS'), ('CORPORATE'), ('SPORTS_PRIVATE'), ('EGYPT_EVENTS'))
  select jsonb_build_object('weeks', p_weeks, 'rows', jsonb_agg(jsonb_build_object(
    'lane', l.lane,
    'discovered', (select count(*) from c where c.lane = l.lane and coalesce(c.universe_added_at, c.created_at) >= (select t from since)),
    'qualified', (select count(*) from c where c.lane = l.lane and c.universe_status = 'QUALIFIED' and coalesce(c.universe_added_at, c.created_at) >= (select t from since)),
    'decision_makers', (select count(*) from contacts k join c on c.id = k.company_id where c.lane = l.lane and k.identity_status = 'CONFIRMED' and k.created_at >= (select t from since)),
    'outreach_ready', (select count(*) from tasks t join c on c.id = t.company_id where c.lane = l.lane and t.created_at >= (select t from since) and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|EMAIL READY)'),
    'sent', (select count(*) from interactions i join c on c.id = i.company_id where c.lane = l.lane and i.direction = 'OUTBOUND' and i.occurred_at >= (select t from since)),
    'replies', (select count(*) from interactions i join c on c.id = i.company_id where c.lane = l.lane and i.direction = 'INBOUND' and i.channel <> 'WEBSITE' and i.occurred_at >= (select t from since)),
    'positive', (select count(*) from opportunities o join c on c.id = o.company_id where c.lane = l.lane and o.status in ('INTERESTED', 'CALL_REQUIRED') and o.updated_at >= (select t from since)),
    'calls', (select count(*) from interactions i join c on c.id = i.company_id where c.lane = l.lane and i.channel = 'MEETING' and i.occurred_at >= (select t from since)),
    'proposals', (select count(*) from opportunities o join c on c.id = o.company_id where c.lane = l.lane and o.status in ('PROPOSAL', 'NEGOTIATION') and o.updated_at >= (select t from since)),
    'wins', (select count(*) from opportunities o join c on c.id = o.company_id where c.lane = l.lane and o.status = 'WON' and o.updated_at >= (select t from since)),
    'revenue', (select coalesce(jsonb_object_agg(cur, amt), '{}'::jsonb) from (select r.currency cur, sum(r.amount) amt from revenue r join c on c.id = r.company_id where c.lane = l.lane and r.created_at >= (select t from since) group by 1) s)
  )), 'note', 'Capacity reallocation follows replies, calls and wins, not volume. Recommendations only.')
  from lanes l
$$;
revoke all on function public.agent_performance(int) from public, anon;
grant execute on function public.agent_performance(int) to authenticated;

-- HQ: Today panel carries the 7-lane view and the rolling 3-day cycle.
create or replace function public.commercial_today()
returns jsonb language sql stable security definer set search_path = public as $$
  with lanes(lane) as (values ('PARTNERSHIPS'), ('BRANDS'), ('TRAVEL_PRIVATE'), ('WEDDINGS'), ('CORPORATE'), ('SPORTS_PRIVATE'), ('EGYPT_EVENTS')),
  t as (select t.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane
          from tasks t left join companies c on c.id = t.company_id where t.status in ('OPEN', 'IN_PROGRESS')),
  i as (select i.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane
          from interactions i left join companies c on c.id = i.company_id where i.occurred_at >= current_date),
  per as (
    select l.lane,
      (select count(*) from companies c where c.universe_added_at >= current_date and c.universe_status in ('QUALIFIED', 'NEEDS_REVIEW')
         and company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) = l.lane) discovered,
      (select count(*) from t where t.lane = l.lane and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)') send_ready,
      (select count(*) from t where t.lane = l.lane and t.title like 'LINKEDIN MESSAGE READY%') linkedin,
      (select count(*) from t where t.lane = l.lane and t.title like 'INSTAGRAM DM READY%') instagram,
      (select count(*) from t where t.lane = l.lane and (t.title like 'EMAIL READY%' or t.task_type = 'SALES_OUTREACH_APPROVAL')) emails,
      (select count(*) from t where t.lane = l.lane and (t.task_type = 'SALES_OUTREACH_APPROVAL' or t.title like 'DRAFT REVIEW%')) awaiting_approval,
      (select count(*) from t where t.lane = l.lane and t.task_type = 'OUTREACH_FOLLOW_UP' and coalesce(t.due_at, now()) <= now() + interval '1 day') follow_ups_due,
      (select count(*) from i where i.lane = l.lane and i.direction = 'OUTBOUND') sent_today,
      (select count(*) from i where i.lane = l.lane and i.direction = 'INBOUND' and i.channel not in ('WEBSITE', 'MEETING')) replies_today,
      (select count(*) from i where i.lane = l.lane and i.channel = 'MEETING') meetings_today
    from lanes l)
  select jsonb_build_object(
    'date', current_date,
    'target', (select value from system_config where key = 'daily_touch_target'),
    'lanes', (select jsonb_agg(to_jsonb(per) order by array_position(array['PARTNERSHIPS','BRANDS','TRAVEL_PRIVATE','WEDDINGS','CORPORATE','SPORTS_PRIVATE','EGYPT_EVENTS'], per.lane)) from per),
    'totals', (select jsonb_build_object('discovered', sum(discovered), 'send_ready', sum(send_ready), 'linkedin', sum(linkedin), 'instagram', sum(instagram),
        'emails', sum(emails), 'awaiting_approval', sum(awaiting_approval), 'follow_ups_due', sum(follow_ups_due), 'sent_today', sum(sent_today),
        'replies_today', sum(replies_today), 'meetings_today', sum(meetings_today)) from per),
    'planned_today', (select jsonb_build_object('planned', count(*), 'ready', count(*) filter (where status = 'READY'),
        'review_required', count(*) filter (where status = 'REVIEW_REQUIRED'), 'dry_run', bool_or(dry_run))
        from outreach_candidates where run_date = current_date),
    'conversations', (select coalesce(jsonb_agg(jsonb_build_object('company', c.name, 'state', relationship_state(c.id)) order by c.name), '[]'::jsonb)
        from companies c where c.id in (select company_id from opportunities where status in ('CALL_REQUIRED', 'INTERESTED', 'PROPOSAL', 'NEGOTIATION'))))
$$;


create or replace function public.hq_execution()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  return jsonb_build_object('queue', queue_health(), 'weekly', commercial_weekly_metrics(6), 'hunter', hunter_roi(),
    'today', commercial_today(), 'ai_budget', ai_budget_status(), 'engine', engine_metrics(current_date - 30, current_date, null),
    'cycle', growth_cycle_report(now() - interval '3 days') - 'runs', 'agents_week', agent_performance(1));
end $$;
revoke all on function public.hq_execution() from public, anon;
grant execute on function public.hq_execution() to authenticated;
