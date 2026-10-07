-- AGENTS command centre (Adam, 7 Oct 2026): make the commercial team of agents visible in HQ.
-- Read layer only, built on the existing records (companies, contacts, opportunities, outreach_candidates, tasks,
-- interactions, department_run_metrics, ai_usage, Gmail state, creative_concepts, intelligence). Nothing is copied.
-- agent_registry is configuration (who each agent is, which workflows it runs, when they are scheduled), not CRM data.
-- Browser access goes through hq_agents() and hq_agent(key), both gated by hq_admin_email(); every helper is revoked
-- from anon and authenticated.

create table if not exists public.agent_registry (
  key text primary key,
  name text not null,
  kind text not null check (kind in ('ACQUISITION', 'SUPPORT')),
  sort int not null,
  scope text not null,
  focus text not null,
  workflows text[] not null default '{}',     -- n8n workflow name prefixes, e.g. '03 -'
  schedule text[] not null default '{}',      -- Cairo times 'HH:MI'
  every_minutes int,                          -- or a fixed interval
  max_gap_hours numeric not null default 14,  -- a logged agent with no run for longer than this has missed a run
  run_logged boolean not null default true,   -- false when the agent leaves no run record, only its output
  ai_workflows text[] not null default '{}'   -- ai_usage.workflow values the agent spends on
);
alter table public.agent_registry enable row level security;
revoke all on public.agent_registry from anon, authenticated;

insert into public.agent_registry (key, name, kind, sort, scope, focus, workflows, schedule, every_minutes, max_gap_hours, run_logged, ai_workflows) values
 ('HOSPITALITY', 'Hospitality & Partnerships', 'ACQUISITION', 1,
  'Hotels, boutique hotels, villas and villa portfolios, serviced and branded residences, resorts, concierge companies, travel partners, DMCs, private clubs and strategic partnerships.',
  'Searching boutique hotel groups, villa portfolios, serviced and branded residences and resorts (rotating query bank), then researching the strongest six each run',
  '{"03 -"}', '{"06:30","12:30","18:30"}', null, 14, true, '{}'),
 ('BRANDS', 'Brands / PR / Production', 'ACQUISITION', 2,
  'Brands, agencies, PR, campaigns, production companies, creator trips and destination shoots.',
  'Searching UK and international brands with destination campaigns, PR and production agencies, and creator-trip briefs',
  '{"02 -"}', '{"06:00","12:00","18:00"}', null, 14, true, '{}'),
 ('WEDDINGS', 'Weddings & Events', 'ACQUISITION', 3,
  'Luxury wedding planners, destination planners, events and celebrations.',
  'Searching luxury and destination wedding planners and UHNW event agencies, including planners discovered through public Instagram profiles',
  '{"04 -"}', '{"07:00","13:00","19:00"}', null, 14, true, '{}'),
 ('CORPORATE', 'Corporate & Private Client', 'ACQUISITION', 4,
  'Corporates, EAs, private offices, family-office routes, financial and professional firms and executive travel.',
  'Searching private banks, family-office routes, law and advisory firms and corporate travel and events teams',
  '{"06 -"}', '{"08:00","14:00","20:00"}', null, 14, true, '{}'),
 ('TRAVEL', 'Travel & Concierge Partnerships', 'ACQUISITION', 5,
  'Luxury travel advisors, concierge companies, travel designers and referral partners.',
  'Searching luxury travel advisors and designers, concierge companies, DMCs and referral networks',
  '{"07 -"}', '{"08:30","14:30","20:30"}', null, 14, true, '{}'),
 ('MEDIA', 'Media / Podcast / Content', 'ACQUISITION', 6,
  'Podcasts, travel media, hospitality media, YouTube and filmed content, and creative Egypt-location opportunities.',
  'Finding podcasts, travel and hospitality media and production companies, and writing a filmable Egypt concept for each one',
  '{"21 -"}', '{"11:30"}', null, 26, false, '{"21"}'),
 ('SPORTS', 'Sports & Talent', 'ACQUISITION', 7,
  'Clubs, agencies, player and talent representation and selective commercial opportunities.',
  'Searching clubs, talent agencies and athlete representation (selective: held for warm routes)',
  '{"08 -"}', '{"09:00"}', null, 26, true, '{}'),
 ('EGYPT', 'Egypt Opportunities / Events', 'ACQUISITION', 8,
  'Events, openings, festivals, launches, tourism developments and other time-sensitive Egypt opportunities.',
  'Watching Egypt events, openings, festivals and launches, then naming the organisations behind each signal',
  '{"09 -","17 -"}', '{"10:00","10:45"}', null, 26, false, '{}'),
 ('ENRICHMENT', 'Contact Enrichment', 'SUPPORT', 11,
  'Finds the actual person, public email, LinkedIn, Instagram and company contact routes.',
  'Finding the named decision maker and a published business email for companies that have no usable route yet',
  '{"19 -"}', '{"11:00","17:00","21:00"}', null, 14, false, '{"19"}'),
 ('DRAFTING', 'Outreach Drafting', 'SUPPORT', 12,
  'Converts qualified prospects into professional email and LinkedIn outreach.',
  'Drafting the Commercial Director''s planned touches; quality gate and one redraft; drafts older than 14 days revalidated daily',
  '{"18 -","20 -"}', '{"10:15","21:30","22:00","22:30"}', null, 14, false, '{"18"}'),
 ('REPLY', 'Reply & Relationship', 'SUPPORT', 13,
  'Watches replies, historical Gmail relationships and follow-ups.',
  'Reading noya@ for replies and manual sends every 30 minutes; importing Gmail history every 3 hours',
  '{"13 -","15 -","16 -"}', '{}', 30, 2, true, '{}'),
 ('DIRECTOR', 'Commercial Director', 'SUPPORT', 14,
  'Prioritises opportunities across all agents and determines what Adam should act on.',
  'Planning the day''s touches across lanes and ranking today''s 15-20 actions for Adam',
  '{"18 -"}', '{"21:30"}', null, 26, false, '{"18"}')
on conflict (key) do update set name = excluded.name, kind = excluded.kind, sort = excluded.sort, scope = excluded.scope, focus = excluded.focus,
  workflows = excluded.workflows, schedule = excluded.schedule, every_minutes = excluded.every_minutes, max_gap_hours = excluded.max_gap_hours,
  run_logged = excluded.run_logged, ai_workflows = excluded.ai_workflows;

-- Which acquisition agent a company belongs to: media first (any lane), then the lane.
create or replace function public.agent_key_of(p_lane text, p_type text, p_notes text)
returns text language sql immutable as $$
  select case
    when is_media_target(p_type, p_notes) then 'MEDIA'
    when p_lane = 'PARTNERSHIPS' then 'HOSPITALITY'
    when p_lane = 'TRAVEL_PRIVATE' then 'TRAVEL'
    when p_lane = 'BRANDS' then 'BRANDS'
    when p_lane = 'WEDDINGS' then 'WEDDINGS'
    when p_lane = 'CORPORATE' then 'CORPORATE'
    when p_lane = 'SPORTS_PRIVATE' then 'SPORTS'
    when p_lane = 'EGYPT_EVENTS' then 'EGYPT'
    else 'CORPORATE' end
$$;

-- Next scheduled run from Cairo wall-clock times (or a fixed interval).
create or replace function public.agent_next_run(p_times text[], p_every int)
returns timestamptz language sql stable as $$
  select case
    when p_every is not null then date_trunc('hour', now()) + make_interval(mins => p_every * (floor(extract(minute from now()) / p_every)::int + 1))
    else (select min(ts) from (
            select ((d + t::time) at time zone 'Africa/Cairo') ts
              from unnest(p_times) t,
                   (values ((now() at time zone 'Africa/Cairo')::date), ((now() at time zone 'Africa/Cairo')::date + 1)) v(d)) x
           where ts > now()) end
$$;

-- How sure we are of an email, in words Adam can act on. PUBLICLY LISTED is not SMTP VERIFIED.
create or replace function public.email_trust(p_status text, p_source_url text)
returns text language sql immutable as $$
  select case
    when p_status = 'VERIFIED' then 'SMTP_VERIFIED'
    when p_status = 'UNVERIFIED' and coalesce(p_source_url, '') <> '' then 'PUBLICLY_LISTED'
    when p_status = 'NOT_FOUND' then 'NOT_VERIFIABLE'
    else 'SOURCE_NOT_RECORDED' end
$$;

-- Plain-English description of each partnership model for the radar (what the model means, not a claim about the company).
create or replace function public.partnership_model_route(p_model text)
returns text[] language sql immutable as $$
  select case p_model
    when 'PREFERRED_STAY' then array['NOYA places suitable clients in their properties', 'they refer Egypt and concierge requirements back to NOYA']
    when 'RECIPROCAL' then array['NOYA supports their guests in Egypt', 'they become NOYA''s trusted option in their destination']
    when 'EGYPT_EXECUTION' then array['they keep the client relationship', 'NOYA executes on the ground in Egypt: guests, logistics, concierge']
    when 'WHITE_LABEL_CONCIERGE' then array['NOYA delivers concierge under their brand', 'recurring service revenue']
    when 'GUEST_CONCIERGE' then array['NOYA runs the guest concierge for their clients or residents']
    when 'CONTENT_TALENT' then array['filmed or editorial content in Egypt', 'NOYA handles access, hospitality and logistics']
    when 'REFERRAL' then array['two-way introductions between their members or clients and NOYA']
    else array[]::text[] end
$$;

create or replace function public.agent_last_run(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r agent_registry%rowtype; v_ts timestamptz; v_basis text; v_metrics jsonb;
begin
  select * into r from agent_registry where key = p_key;
  if r.key is null then return null; end if;
  if r.key = 'REPLY' then
    select last_run_at into v_ts from gmail_sync_state order by last_run_at desc nulls last limit 1;
    v_basis := 'Gmail sync run';
  elsif r.key = 'EGYPT' then
    select max(greatest(created_at, coalesce(analysed_at, created_at))) into v_ts from intelligence;
    v_basis := 'Last signal saved (09 keeps no run log)';
  elsif r.key = 'MEDIA' then
    select max(x) into v_ts from (select max("at") x from ai_usage where workflow = '21' union all select max(created_at) from creative_concepts) s;
    v_basis := 'Last concept work';
  elsif r.key = 'ENRICHMENT' then
    select max("at") into v_ts from ai_usage where workflow = '19';
    v_basis := 'Last company enriched';
  elsif r.key in ('DRAFTING', 'DIRECTOR') then
    select max(x) into v_ts from (select max("at") x from ai_usage where workflow = '18' union all select max(created_at) from outreach_candidates
                                  union all select max(revalidated_at) from tasks where r.key = 'DRAFTING') s;
    v_basis := case when r.key = 'DIRECTOR' then 'Last plan' else 'Last draft or revalidation' end;
  else
    select m.recorded_at, m.metrics into v_ts, v_metrics from department_run_metrics m
     where m.workflow_name like any (select w || '%' from unnest(r.workflows) w) order by m.recorded_at desc limit 1;
    v_basis := 'Run log';
  end if;
  return jsonb_build_object('at', v_ts, 'basis', v_basis, 'metrics', v_metrics);
end $$;

-- ---------------------------------------------------------------- the whole floor
create or replace function public.agents_snapshot()
returns jsonb language sql stable security definer set search_path = public as $$
  with co as (
    select c.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent
      from companies c),
  ct as (select k.*, co.agent, co.name company, co.lane, co.universe_status from contacts k join co on co.id = k.company_id
          where not coalesce(k.do_not_contact, false)),
  rdy as (select t.*, co.agent from tasks t join co on co.id = t.company_id
           where t.status in ('OPEN', 'IN_PROGRESS') and t.contact_id is not null
             and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)'),
  win(w, since) as (values ('today', (date_trunc('day', now() at time zone 'Africa/Cairo')) at time zone 'Africa/Cairo'), ('d3', now() - interval '3 days')),
  runs as (select m.*, a.key agent from department_run_metrics m join agent_registry a on m.workflow_name like any (select w || '%' from unnest(a.workflows) w)
            where m.recorded_at > now() - interval '3 days'),
  budget as (select ai_budget_status() b),
  provider as (select exists (select 1 from tasks where task_type = 'PROVIDER_HEALTH_ALERT' and status = 'OPEN' and created_at > now() - interval '30 hours') bad),
  stats as (
    select a.key, win.w,
      jsonb_build_object(
        'searches', (select sum(nullif(r.metrics->>'serper_searches', '')::numeric) from runs r where r.agent = a.key and r.recorded_at >= win.since),
        'runs', (select count(*) from runs r where r.agent = a.key and r.recorded_at >= win.since),
        'discovered', (select count(*) from co where co.agent = a.key and co.created_at >= win.since),
        'discovered_by_agent', (select count(*) from co where co.agent = a.key and co.created_at >= win.since and co.source ~* 'Department'),
        'researched', (select sum(nullif(r.metrics->>'deep_researched', '')::numeric) from runs r where r.agent = a.key and r.recorded_at >= win.since),
        'qualified', (select count(*) from co where co.agent = a.key and co.created_at >= win.since and co.universe_status = 'QUALIFIED'),
        'decision_makers', (select count(*) from ct where ct.agent = a.key and ct.created_at >= win.since and ct.first_name is not null
                              and ct.identity_status = 'CONFIRMED' and role_score(ct.position) >= 3),
        'public_emails', (select count(*) from ct where ct.agent = a.key and ct.created_at >= win.since and ct.email is not null and ct.email_status in ('UNVERIFIED', 'VERIFIED')),
        'person_emails', (select count(*) from ct where ct.agent = a.key and ct.created_at >= win.since and ct.email is not null and email_kind(ct.email) = 'DIRECT_PERSON_EMAIL'),
        'verified_emails', (select count(*) from ct where ct.agent = a.key and ct.created_at >= win.since and ct.email_status = 'VERIFIED'),
        'linkedin', (select count(*) from ct where ct.agent = a.key and ct.created_at >= win.since and coalesce(ct.linkedin, '') ~* 'linkedin\.com/in/'),
        'instagram', (select count(*) from ct where ct.agent = a.key and ct.created_at >= win.since and coalesce(ct.instagram, '') <> '')
                     + (select count(*) from co where co.agent = a.key and co.created_at >= win.since and coalesce(co.instagram, '') <> ''),
        'opportunities', (select count(*) from opportunities o join co on co.id = o.company_id where co.agent = a.key and o.created_at >= win.since),
        'outreach_ready', (select count(*) from tasks t join co on co.id = t.company_id where co.agent = a.key and t.created_at >= win.since
                             and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)'),
        'replies', (select count(*) from interactions i join co on co.id = i.company_id where co.agent = a.key and i.occurred_at >= win.since
                      and i.direction = 'INBOUND' and i.channel <> 'WEBSITE'),
        'rejected', (select sum(v::numeric) from runs r, jsonb_each_text(coalesce(r.metrics->'reject_reasons', '{}')) e(k, v) where r.agent = a.key and r.recorded_at >= win.since)
      ) s
    from agent_registry a cross join win where a.kind = 'ACQUISITION'),
  support_stats as (
    select a.key, win.w,
      case a.key
        when 'ENRICHMENT' then jsonb_build_object(
          'companies_enriched', (select count(distinct company_id) from ai_usage where workflow = '19' and "at" >= win.since),
          'decision_makers', (select count(*) from contacts where source = 'Workflow 19 contact enrichment' and created_at >= win.since and first_name is not null),
          'public_emails', (select count(*) from contacts where source = 'Workflow 19 contact enrichment' and created_at >= win.since and email is not null),
          'person_emails', (select count(*) from contacts where source = 'Workflow 19 contact enrichment' and created_at >= win.since and email is not null and email_kind(email) = 'DIRECT_PERSON_EMAIL'),
          'linkedin', (select count(*) from contacts where source = 'Workflow 19 contact enrichment' and created_at >= win.since and coalesce(linkedin, '') ~* 'linkedin\.com/in/'),
          'instagram', (select count(*) from contacts where source = 'Workflow 19 contact enrichment' and created_at >= win.since and coalesce(instagram, '') <> ''),
          'rate_limited', (select count(*) from ai_usage where workflow = '19' and "at" >= win.since and status = 'RATE_LIMITED'))
        when 'DRAFTING' then jsonb_build_object(
          'drafted', (select count(*) from outreach_candidates where created_at >= win.since and not dry_run),
          'ready', (select count(*) from outreach_candidates where created_at >= win.since and not dry_run and status = 'READY'),
          'review_required', (select count(*) from outreach_candidates where created_at >= win.since and not dry_run and status = 'REVIEW_REQUIRED'),
          'revalidated', (select count(*) from tasks where revalidated_at >= win.since),
          'ai_usd', (select round(coalesce(sum(est_cost_usd), 0), 4) from ai_usage where workflow = '18' and "at" >= win.since))
        when 'REPLY' then jsonb_build_object(
          'replies', (select count(*) from interactions where direction = 'INBOUND' and channel <> 'WEBSITE' and occurred_at >= win.since),
          'sent_logged', (select count(*) from interactions where direction = 'OUTBOUND' and occurred_at >= win.since),
          'gmail_messages_imported', (select count(*) from gmail_history_messages where first_seen_at >= win.since))
        else jsonb_build_object(
          'planned', (select count(*) from outreach_candidates where created_at >= win.since and not dry_run),
          'actions_today', (daily_action_queue(20)->>'count')::int,
          'approved_sends_open', (select count(*) from tasks where ceo_approved_at is not null and status in ('OPEN', 'IN_PROGRESS')))
      end s
    from agent_registry a cross join win where a.kind = 'SUPPORT'),
  floor_rows as (
    select a.*, agent_last_run(a.key) lr, agent_next_run(a.schedule, a.every_minutes) next_run,
      (select jsonb_agg(jsonb_build_object('title', t.title, 'at', t.created_at)) from tasks t
        where t.task_type = 'SYSTEM_FAILURE_ALERT' and t.status = 'OPEN' and t.title like any (select 'SYSTEM FAILURE — ' || w || '%' from unnest(a.workflows) w)) failures
      from agent_registry a),
  floor as (
    select f.*,
      (f.lr->>'at')::timestamptz last_at,
      array_remove(array[
        case when f.ai_workflows <> '{}' and (select b->>'status' from budget) = 'HOLD' then 'AI budget hold: drafting paused at the NOYA ceiling' end,
        case when f.kind = 'ACQUISITION' and f.key <> 'MEDIA' and (select bad from provider) then 'AI provider failure reported by the daily health check' end,
        case when f.ai_workflows <> '{}' and (select count(*) filter (where status = 'RATE_LIMITED') > 0 and count(*) filter (where status = 'OK') = 0
                                                from ai_usage u where u.workflow = any (f.ai_workflows) and u."at" > now() - interval '24 hours')
             then 'Gemini limit: every model call in the last 24 hours was refused' end,
        -- notes explain without blocking: the fallback model is still producing
        case when f.ai_workflows <> '{}' and (select count(*) filter (where status = 'RATE_LIMITED') > 0 and count(*) filter (where status = 'OK') > 0
                                                from ai_usage u where u.workflow = any (f.ai_workflows) and u."at" > now() - interval '24 hours')
             then 'Note: Gemini 3 Flash quota reached; drafts are using the Flash-Lite fallback until billing is on' end,
        case when f.kind = 'ACQUISITION' and coalesce(nullif(f.lr->'metrics'->>'provider_failures', '')::int, 0) > 0
             then 'Note: last run had ' || (f.lr->'metrics'->>'provider_failures') || ' provider failure(s)' end
      ], null) blockers
      from floor_rows f),
  stuck as (
    select co.agent,
      count(*) filter (where not exists (select 1 from ct where ct.company_id = co.id and ct.first_name is not null and role_score(ct.position) >= 3)) no_decision_maker,
      count(*) filter (where not exists (select 1 from ct where ct.company_id = co.id and ct.email is not null)) no_email,
      (select count(*) from ct where ct.agent = co.agent and ct.identity_status = 'NEEDS_VERIFICATION') needs_verification
      from co where co.universe_status = 'QUALIFIED' group by co.agent)
  select jsonb_build_object(
    'generated_at', now(),
    'targets', jsonb_build_object('contactable_3d_floor', 50, 'contactable_3d_low', 60, 'contactable_3d_high', 75, 'hospitality_3d_low', 20, 'hospitality_3d_high', 25,
                                  'contactable_means', 'Relevant organisation, commercial reason, a real person or legitimate company route, a channel, evidence and a finished draft.'),
    'agents', (select jsonb_agg(jsonb_build_object(
        'key', f.key, 'name', f.name, 'kind', f.kind, 'scope', f.scope, 'workflows', f.workflows,
        'status', case when f.failures is not null then 'ERROR'
                       when cardinality(f.blockers) > 0 and f.blockers[1] not like 'Note:%' then 'BLOCKED'
                       when f.last_at is not null and f.last_at > now() - make_interval(secs => (f.max_gap_hours * 3600)::int) then 'WORKING'
                       when f.run_logged and f.last_at is not null then 'ERROR'
                       else 'WAITING' end,
        'status_reason', case when f.failures is not null then (f.failures->0->>'title')
                              when cardinality(f.blockers) > 0 and f.blockers[1] not like 'Note:%' then f.blockers[1]
                              when f.last_at is not null and f.last_at > now() - make_interval(secs => (f.max_gap_hours * 3600)::int) then 'Ran on schedule'
                              when f.run_logged and f.last_at is not null then 'No run recorded since ' || to_char(f.last_at at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ' (missed schedule)'
                              when f.last_at is null then 'No run recorded yet'
                              else 'Nothing new to process since ' || to_char(f.last_at at time zone 'Africa/Cairo', 'DD Mon HH24:MI') end,
        'last_run', f.last_at, 'last_run_basis', f.lr->>'basis', 'next_run', f.next_run,
        'last_run_result', case when f.lr->'metrics' is not null then jsonb_build_object(
                                 'searches', f.lr->'metrics'->'serper_searches', 'researched', f.lr->'metrics'->'deep_researched',
                                 'qualified', f.lr->'metrics'->'qualified', 'candidates', f.lr->'metrics'->'candidates_found',
                                 'reject_reasons', f.lr->'metrics'->'reject_reasons') end,
        'current_work', f.focus,
        'blockers', to_jsonb(f.blockers),
        'stuck', (select jsonb_build_object('no_decision_maker', s.no_decision_maker, 'no_email', s.no_email, 'needs_verification', s.needs_verification)
                    from stuck s where s.agent = f.key),
        'totals', case when f.kind = 'ACQUISITION' then jsonb_build_object(
                    'companies', (select count(*) from co where co.agent = f.key and co.universe_status in ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING')),
                    'qualified', (select count(*) from co where co.agent = f.key and co.universe_status = 'QUALIFIED'),
                    'people', (select count(*) from ct where ct.agent = f.key and ct.first_name is not null),
                    'emails', (select count(*) from ct where ct.agent = f.key and ct.email is not null and ct.email_status in ('UNVERIFIED', 'VERIFIED')),
                    'ready', (select count(*) from rdy where rdy.agent = f.key)) end,
        'today', coalesce((select s from stats where stats.key = f.key and w = 'today'), (select s from support_stats ss where ss.key = f.key and w = 'today')),
        'd3', coalesce((select s from stats where stats.key = f.key and w = 'd3'), (select s from support_stats ss where ss.key = f.key and w = 'd3'))
      ) order by f.sort) from floor f),
    'ceo', jsonb_build_object(
      'new_companies_24h', (select count(*) from co where co.created_at > now() - interval '24 hours' and co.universe_status in ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING')),
      'new_decision_makers_24h', (select count(*) from ct where ct.created_at > now() - interval '24 hours' and ct.first_name is not null
                                    and ct.identity_status = 'CONFIRMED' and role_score(ct.position) >= 3),
      'new_emails_24h', (select count(*) from ct where ct.created_at > now() - interval '24 hours' and ct.email is not null and ct.email_status in ('UNVERIFIED', 'VERIFIED')),
      'ready', (select count(*) from rdy),
      'replies_7d', (select count(*) from interactions where direction = 'INBOUND' and channel <> 'WEBSITE' and occurred_at > now() - interval '7 days'),
      'calls_7d', (select count(*) from interactions where channel = 'MEETING' and occurred_at > now() - interval '7 days')
                  + (select count(*) from tasks where created_at > now() - interval '7 days' and (task_type = 'MEETING_ACTION' or title like 'MEETING --%')),
      'contactable_3d', (select count(distinct t.company_id) from tasks t where t.created_at > now() - interval '3 days'
                           and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)'),
      'hospitality_contactable_3d', (select count(distinct t.company_id) from tasks t join co on co.id = t.company_id where co.agent = 'HOSPITALITY'
                                       and t.created_at > now() - interval '3 days' and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)'),
      'best_window_hours', case when exists (select 1 from co where co.created_at > now() - interval '24 hours' and co.universe_status = 'QUALIFIED') then 24 else 72 end,
      'best', (select jsonb_agg(b - 'rank_score' order by (b->>'rank_score')::int desc, b->>'found_at' desc) from (select y.b from (
          select jsonb_build_object('company_id', co.id, 'company', co.name, 'agent', co.agent, 'country', co.country, 'type', co.company_type,
                   'model', partnership_model_label(co.partnership_model),
                   'person', (select concat_ws(' ', k.first_name, k.last_name) || coalesce(', ' || k.position, '') from ct k where k.company_id = co.id and k.first_name is not null
                               order by (k.email is not null) desc, role_score(k.position) desc limit 1),
                   'email', (select k.email from ct k where k.company_id = co.id and k.email is not null order by (email_kind(k.email) = 'DIRECT_PERSON_EMAIL') desc limit 1),
                   'angle', (select left(coalesce(o.angle, o.suggested_approach, o.reason), 240) from opportunities o where o.company_id = co.id order by o.created_at desc limit 1),
                   'concept', (select cc.concept from creative_concepts cc where cc.company_id = co.id and cc.concept <> ''),
                   'ready', exists (select 1 from rdy where rdy.company_id = co.id),
                   'found_at', co.created_at,
                   'rank_score', (case when exists (select 1 from ct k where k.company_id = co.id and k.email is not null and email_kind(k.email) = 'DIRECT_PERSON_EMAIL') then 40 else 0 end
                                + case when exists (select 1 from ct k where k.company_id = co.id and k.first_name is not null and role_score(k.position) >= 4) then 25 else 0 end
                                + case when exists (select 1 from rdy where rdy.company_id = co.id) then 20 else 0 end
                                + case when co.agent = 'HOSPITALITY' then 10 else 0 end
                                + case when co.partnership_model is not null then 5 else 0 end)) b
            from co where co.universe_status = 'QUALIFIED'
             and co.created_at > now() - make_interval(hours => case when exists (select 1 from co c2 where c2.created_at > now() - interval '24 hours' and c2.universe_status = 'QUALIFIED') then 24 else 72 end)) y
        order by (y.b->>'rank_score')::int desc, y.b->>'found_at' desc limit 12) z)),
    'email_desk', (select jsonb_agg(e order by e->>'sort' desc) from (
        select jsonb_build_object(
          'contact_id', k.id, 'person', nullif(concat_ws(' ', k.first_name, k.last_name), ''), 'role', k.position, 'company', k.company, 'company_id', k.company_id,
          'agent', k.agent, 'lane', k.lane, 'market', coalesce(k.country, (select country from companies where id = k.company_id)),
          'email', k.email, 'email_kind', email_kind(k.email), 'source_type', k.source_type, 'source_url', coalesce(k.email_source_url, k.source_url), 'source', k.source,
          'trust', email_trust(k.email_status, k.email_source_url),
          'why_noya', (select left(coalesce(o.reason, o.description), 280) from opportunities o where o.company_id = k.company_id order by o.created_at desc limit 1),
          'opportunity', coalesce((select partnership_model_label(partnership_model) from companies where id = k.company_id),
                                  (select o.opportunity_type from opportunities o where o.company_id = k.company_id order by o.created_at desc limit 1)),
          'why_now', (select left(oc.why_now, 280) from outreach_candidates oc where oc.company_id = k.company_id and oc.why_now is not null order by oc.created_at desc limit 1),
          'draft_state', (select t.title from tasks t where t.contact_id = k.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
                            and t.title ~ '^(EMAIL READY|LINKEDIN MESSAGE READY|INSTAGRAM DM READY|DRAFT REVIEW|HOLD)' order by t.created_at desc limit 1),
          'draft_subject', (select oc.subject from outreach_candidates oc where oc.contact_id = k.id and oc.status = 'READY' order by oc.created_at desc limit 1),
          'draft', (select left(oc.draft, 1500) from outreach_candidates oc where oc.contact_id = k.id and oc.status = 'READY' order by oc.created_at desc limit 1),
          'prior_relationship', relationship_state(k.company_id),
          'last_contact', greatest(k.last_contact_at, (select max(i.occurred_at) from interactions i where i.company_id = k.company_id)),
          'state', case
              when exists (select 1 from interactions i where i.company_id = k.company_id and i.direction = 'INBOUND' and i.channel <> 'WEBSITE') then 'REPLIED'
              when exists (select 1 from tasks t where t.company_id = k.company_id and t.status in ('OPEN', 'IN_PROGRESS')
                             and (t.task_type = 'OUTREACH_FOLLOW_UP' or t.title like 'FOLLOW UP%')) then 'FOLLOW_UP'
              when exists (select 1 from interactions i where i.company_id = k.company_id and i.direction = 'OUTBOUND') then 'SENT'
              when exists (select 1 from tasks t where t.contact_id = k.id and t.status in ('OPEN', 'IN_PROGRESS') and t.title ~ '^(EMAIL READY|LINKEDIN MESSAGE READY|INSTAGRAM DM READY)') then 'READY'
              when k.created_at > now() - interval '3 days' then 'NEW'
              else 'OPEN' end,
          'created_at', k.created_at,
          'sort', to_char(k.created_at, 'YYYYMMDDHH24MISS')) e
        from ct k where k.email is not null and k.universe_status in ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING')) z),
    'radar', (select jsonb_agg(r order by r->>'at' desc) from (
        select jsonb_build_object('kind', 'CONCEPT', 'company_id', c.company_id, 'company', co.name, 'agent', 'MEDIA',
                 'headline', 'Egypt filmed concept · ' || c.backdrop,
                 'lines', jsonb_build_array(c.concept, 'NOYA: ' || c.noya_role, c.commercial_value), 'at', c.created_at) r
          from creative_concepts c join co on co.id = c.company_id where c.concept is not null and c.concept <> ''
        union all
        select jsonb_build_object('kind', 'PARTNERSHIP', 'company_id', co.id, 'company', co.name, 'agent', co.agent,
                 'headline', split_part(partnership_model_label(co.partnership_model), ':', 1) || coalesce(' · ' || nullif(co.company_type, ''), ''),
                 'lines', to_jsonb(partnership_model_route(co.partnership_model))
                          || coalesce((select jsonb_build_array(left(coalesce(o.angle, o.suggested_approach), 220)) from opportunities o
                                         where o.company_id = co.id and coalesce(o.angle, o.suggested_approach) is not null order by o.created_at desc limit 1), '[]'::jsonb),
                 'at', co.created_at) r
          from co where co.partnership_model is not null and co.partnership_model <> 'CONTENT_TALENT' and co.universe_status = 'QUALIFIED'
            and co.created_at > now() - interval '21 days') z),
    'feed', (select jsonb_agg(f order by f->>'at' desc) from (
        select * from (
          select jsonb_build_object('at', m.recorded_at, 'agent', m.agent, 'kind', 'RUN',
                   'text', 'completed a run: ' || coalesce(m.metrics->>'serper_searches', '?') || ' searches, ' || coalesce(m.metrics->>'deep_researched', '0')
                           || ' researched, ' || coalesce(m.metrics->>'qualified', '0') || ' qualified') f from runs m
          union all
          select jsonb_build_object('at', m.recorded_at, 'agent', m.agent, 'kind', 'REJECTED',
                   'text', 'rejected ' || e.v || ' — ' || lower(replace(e.k, '_', ' '))) from runs m, jsonb_each_text(coalesce(m.metrics->'reject_reasons', '{}')) e(k, v) where e.v::numeric > 0
          union all
          select jsonb_build_object('at', co.created_at, 'agent', co.agent, 'kind', case when co.source ~* 'WATCHLIST' then 'WATCHLIST' else 'FOUND' end, 'company_id', co.id,
                   'text', case when co.source ~* 'WATCHLIST' then 'held ' || co.name || ' on the watchlist (scored below the bar)'
                                when co.source ~* 'Department' then 'found ' || co.name || coalesce(' (' || co.country || ')', '')
                                else co.name || coalesce(' (' || co.country || ')', '') || ' added by research' end)
            from co where co.created_at > now() - interval '72 hours'
          union all
          select jsonb_build_object('at', k.created_at, 'agent', case when k.source = 'Workflow 19 contact enrichment' then 'ENRICHMENT' else k.agent end, 'kind', 'PERSON', 'company_id', k.company_id,
                   'text', case when k.email is not null then 'found ' || case when email_kind(k.email) = 'DIRECT_PERSON_EMAIL' then 'a public email for ' else 'a company inbox at ' end
                                      || coalesce(nullif(concat_ws(' ', k.first_name, k.last_name), '') || ' at ', '') || k.company
                                else 'found ' || concat_ws(' ', k.first_name, k.last_name) || coalesce(', ' || k.position, '') || ' at ' || k.company end)
            from ct k where k.created_at > now() - interval '72 hours' and (k.email is not null or (k.first_name is not null and role_score(k.position) >= 3))
          union all
          select jsonb_build_object('at', oc.created_at, 'agent', 'DRAFTING', 'kind', 'DRAFT', 'company_id', oc.company_id,
                   'text', case oc.status when 'READY' then 'prepared ' || lower(coalesce(oc.channel, 'a')) || ' draft for ' when 'REVIEW_REQUIRED' then 'flagged a draft for review: '
                                         when 'SKIPPED' then 'skipped (model limit): ' else lower(oc.status) || ': ' end
                           || coalesce((select nullif(concat_ws(' ', first_name, last_name), '') || ' at ' from contacts where id = oc.contact_id), '') || (select name from companies where id = oc.company_id))
            from outreach_candidates oc where oc.created_at > now() - interval '72 hours' and not oc.dry_run
          union all
          select jsonb_build_object('at', i.occurred_at, 'agent', 'REPLY', 'kind', 'REPLY', 'company_id', i.company_id,
                   'text', 'detected a reply from ' || (select name from companies where id = i.company_id))
            from interactions i where i.direction = 'INBOUND' and i.channel <> 'WEBSITE' and i.occurred_at > now() - interval '72 hours'
          union all
          select jsonb_build_object('at', c.created_at, 'agent', 'MEDIA', 'kind', 'CONCEPT', 'company_id', c.company_id,
                   'text', 'proposed a ' || c.backdrop || ' concept for ' || (select name from companies where id = c.company_id))
            from creative_concepts c where c.created_at > now() - interval '72 hours'
          union all
          select jsonb_build_object('at', t.revalidated_at, 'agent', 'DRAFTING', 'kind', 'REVALIDATED', 'company_id', t.company_id,
                   'text', 'revalidated the draft for ' || (select name from companies where id = t.company_id) || ': '
                           || lower(coalesce(substring(t.description from '^REVALIDATED [^:]*: ([^.]*)'), 'checked')))
            from tasks t where t.revalidated_at > now() - interval '72 hours'
        ) u order by (f->>'at') desc limit 120) z)
  )
$$;

-- ---------------------------------------------------------------- one agent's work
create or replace function public.agent_detail(p_key text)
returns jsonb language sql stable security definer set search_path = public as $$
  with a as (select * from agent_registry where key = p_key),
  co as (
    select c.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent
      from companies c),
  mine as (select * from co where co.agent = p_key or (p_key in ('ENRICHMENT', 'DRAFTING', 'REPLY', 'DIRECTOR'))),
  ppl as (
    select k.*, co.name company, co.country company_country, co.agent from contacts k join co on co.id = k.company_id
     where not coalesce(k.do_not_contact, false)
       and (co.agent = p_key or (p_key = 'ENRICHMENT' and k.source = 'Workflow 19 contact enrichment'))),
  person_json as (
    select k.id, k.created_at, jsonb_build_object('contact_id', k.id, 'name', nullif(concat_ws(' ', k.first_name, k.last_name), ''), 'role', k.position,
             'company', k.company, 'company_id', k.company_id, 'country', coalesce(k.country, k.company_country), 'agent', k.agent,
             'email', k.email, 'email_kind', email_kind(k.email), 'trust', case when k.email is not null then email_trust(k.email_status, k.email_source_url) end,
             'linkedin', k.linkedin, 'instagram', k.instagram, 'source_type', k.source_type, 'source_url', coalesce(k.email_source_url, k.source_url), 'source', k.source,
             'confidence', case when k.identity_status = 'CONFIRMED' and role_score(k.position) >= 4 then 'HIGH'
                                when k.identity_status = 'CONFIRMED' then 'MEDIUM' else 'NEEDS_VERIFICATION' end,
             'route', k.route_type, 'found_at', k.created_at) j
      from ppl k where k.first_name is not null or k.email is not null),
  sections as (
    select 1 ord, 'finds' key, 'New finds' title, 'companies' kind,
      (select jsonb_agg(jsonb_build_object('company_id', m.id, 'company', m.name, 'country', m.country, 'type', m.company_type, 'status', m.universe_status,
                 'model', partnership_model_label(m.partnership_model), 'source', m.source, 'website', m.website, 'instagram', m.instagram, 'found_at', m.created_at,
                 'people', (select count(*) from ppl where ppl.company_id = m.id and ppl.first_name is not null),
                 'emails', (select count(*) from ppl where ppl.company_id = m.id and ppl.email is not null)) order by m.created_at desc)
         from (select * from mine where p_key not in ('ENRICHMENT', 'DRAFTING', 'REPLY', 'DIRECTOR') and universe_status in ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING')
                order by created_at desc limit 60) m) items
    union all
    select 2, 'people', 'People', 'people', (select jsonb_agg(j order by created_at desc) from (select * from person_json order by created_at desc limit 150) p)
    union all
    select 3, 'opportunities', 'Opportunities', 'opportunities',
      (select jsonb_agg(x order by x->>'at' desc) from (
         select jsonb_build_object('company_id', m.id, 'company', m.name, 'model', partnership_model_label(m.partnership_model),
                  'route', to_jsonb(partnership_model_route(m.partnership_model)),
                  'type', o.opportunity_type, 'angle', left(coalesce(o.angle, o.suggested_approach, o.reason, o.description), 320), 'status', o.status,
                  'concept', (select jsonb_build_object('concept', cc.concept, 'backdrop', cc.backdrop, 'noya_role', cc.noya_role, 'value', cc.commercial_value)
                                from creative_concepts cc where cc.company_id = m.id and cc.concept <> ''),
                  'at', coalesce(o.created_at, m.created_at)) x
           from mine m left join lateral (select * from opportunities o where o.company_id = m.id order by o.created_at desc limit 1) o on true
          where p_key not in ('ENRICHMENT', 'DRAFTING', 'REPLY', 'DIRECTOR') and m.universe_status = 'QUALIFIED'
          order by coalesce(o.created_at, m.created_at) desc limit 60) z)
    union all
    select 4, 'ready', 'Ready for Adam', 'tasks',
      (select jsonb_agg(jsonb_build_object('task_id', t.id, 'title', t.title, 'company', m.name, 'company_id', m.id,
                 'person', (select nullif(concat_ws(' ', first_name, last_name), '') || coalesce(', ' || position, '') from contacts where id = t.contact_id),
                 'approved', t.ceo_approved_at is not null, 'created_at', t.created_at) order by (t.ceo_approved_at is not null) desc, t.created_at desc)
         from tasks t join mine m on m.id = t.company_id
        where t.status in ('OPEN', 'IN_PROGRESS') and t.contact_id is not null
          and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)'
          and (p_key not in ('ENRICHMENT', 'REPLY')))
    union all
    select 5, 'researching', 'Researching — route still missing', 'companies',
      (select jsonb_agg(jsonb_build_object('company_id', m.id, 'company', m.name, 'country', m.country, 'type', m.company_type, 'status', m.universe_status,
                 'missing', case when not exists (select 1 from ppl where ppl.company_id = m.id and ppl.first_name is not null and role_score(ppl.position) >= 3) then 'No decision maker yet'
                                 else 'No email yet (LinkedIn or Instagram only)' end,
                 'attempts', m.enrichment_attempts, 'last_enriched', m.last_enriched_at, 'found_at', m.created_at) order by m.created_at desc)
         from (select * from mine where p_key not in ('ENRICHMENT', 'DRAFTING', 'REPLY', 'DIRECTOR') and universe_status in ('QUALIFIED', 'RESEARCHING')
                 and (not exists (select 1 from ppl where ppl.company_id = mine.id and ppl.first_name is not null and role_score(ppl.position) >= 3)
                      or not exists (select 1 from ppl where ppl.company_id = mine.id and ppl.email is not null))
               order by created_at desc limit 80) m)
    union all
    select 6, 'rejected', 'Rejected or held', 'companies',
      (select jsonb_agg(jsonb_build_object('company_id', m.id, 'company', m.name, 'country', m.country, 'type', m.company_type, 'status', m.universe_status,
                 'missing', case when m.source ~* 'WATCHLIST' then 'Scored below the agent''s bar (watchlist)' else 'Parked: ' || coalesce(left(m.universe_reason, 160), 'no reason recorded') end,
                 'found_at', m.created_at) order by m.created_at desc)
         from (select * from co where co.agent = p_key and (co.source ~* 'WATCHLIST' or co.universe_status = 'PARKED') order by created_at desc limit 40) m)
    union all
    select 7, 'reject_reasons', 'Discarded in the last 3 days (counts from run logs)', 'counts',
      (select jsonb_object_agg(k, n) from (select e.k, sum(e.v::numeric) n
          from department_run_metrics r, a, jsonb_each_text(coalesce(r.metrics->'reject_reasons', '{}')) e(k, v)
         where r.recorded_at > now() - interval '3 days' and r.workflow_name like any (select w || '%' from unnest(a.workflows) w) group by e.k) s)
    union all
    select 8, 'runs', 'Recent runs', 'runs',
      (select jsonb_agg(jsonb_build_object('at', r.recorded_at, 'workflow', r.workflow_name, 'searches', r.metrics->'serper_searches', 'candidates', r.metrics->'candidates_found',
                 'researched', r.metrics->'deep_researched', 'qualified', r.metrics->'qualified', 'known_skipped', r.metrics->'known_skipped') order by r.recorded_at desc)
         from (select r.* from department_run_metrics r, a where r.workflow_name like any (select w || '%' from unnest(a.workflows) w) order by r.recorded_at desc limit 12) r)
    union all
    select 9, 'drafts', 'Drafts prepared', 'drafts',
      (select jsonb_agg(jsonb_build_object('company', (select name from companies where id = oc.company_id), 'company_id', oc.company_id,
                 'person', (select nullif(concat_ws(' ', first_name, last_name), '') from contacts where id = oc.contact_id),
                 'channel', oc.channel, 'status', oc.status, 'subject', oc.subject, 'hold_reason', oc.hold_reason, 'at', oc.created_at) order by oc.created_at desc)
         from (select * from outreach_candidates where p_key in ('DRAFTING', 'DIRECTOR') and not dry_run order by created_at desc limit 60) oc)
    union all
    select 10, 'replies', 'Replies and relationships', 'replies',
      (select jsonb_agg(jsonb_build_object('company', (select name from companies where id = i.company_id), 'company_id', i.company_id, 'subject', i.subject,
                 'summary', left(i.summary, 240), 'at', i.occurred_at, 'state', relationship_state(i.company_id)) order by i.occurred_at desc)
         from (select * from interactions where p_key = 'REPLY' and direction = 'INBOUND' and channel <> 'WEBSITE' order by occurred_at desc limit 40) i)
    union all
    select 11, 'actions', 'Today''s actions for Adam', 'actions', (select daily_action_queue(20)->'items' where p_key = 'DIRECTOR')
  )
  select jsonb_build_object('key', p_key, 'agent', (select to_jsonb(a) from a),
    'sections', (select jsonb_agg(jsonb_build_object('key', key, 'title', title, 'kind', kind, 'items', coalesce(items, case when kind = 'counts' then '{}'::jsonb else '[]'::jsonb end)) order by ord)
                   from sections where items is not null and items <> '[]'::jsonb and items <> '{}'::jsonb))
$$;

-- Browser entry points: admin only.
create or replace function public.hq_agents()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  return agents_snapshot();
end $$;

create or replace function public.hq_agent(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  if not exists (select 1 from agent_registry where key = p_key) then return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_AGENT'); end if;
  return agent_detail(p_key);
end $$;

revoke all on function public.agent_key_of(text, text, text) from public, anon, authenticated;
revoke all on function public.agent_next_run(text[], int) from public, anon, authenticated;
revoke all on function public.email_trust(text, text) from public, anon, authenticated;
revoke all on function public.partnership_model_route(text) from public, anon, authenticated;
revoke all on function public.agent_last_run(text) from public, anon, authenticated;
revoke all on function public.agents_snapshot() from public, anon, authenticated;
revoke all on function public.agent_detail(text) from public, anon, authenticated;
revoke all on function public.hq_agents() from public, anon;
revoke all on function public.hq_agent(text) from public, anon;
grant execute on function public.hq_agents() to authenticated;
grant execute on function public.hq_agent(text) to authenticated;
