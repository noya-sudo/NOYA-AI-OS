-- CEO effectiveness pass (Adam, 16 Oct 2026). No new architecture: read models over the existing tables, used by the
-- Dashboard, Agents, Outreach, Relationships and Operations screens. Nothing here writes commercial data.
-- 1. Honest Director status: WORKING only while a scheduled run has started and its completion is not yet recorded.
--    Before, "Working" meant "any activity in the last 20 minutes", which is not the same as running.
-- 2. project_type() and multiplier_reason(): every opportunity is framed as a potential project (brand shoot,
--    destination wedding, travel partner...) and every relationship by what it can repeatedly bring NOYA.
-- 3. hq_ceo_dashboard(): pipeline by stage (and where it is stuck), the conversion funnel (this week, 30 days, by
--    Director), the top commercial opportunities, money as recorded (never estimated), Director outcomes and Operations
--    buckets. One admin-gated read.
-- 4. hq_network(): important relationships, ranked by what they can repeatedly create, and relationships going cold.

-- ---------------------------------------------------------------- 1. honest status
create or replace function public.agent_prev_run(p_times text[], p_every integer)
returns timestamptz language sql stable as $$
  select case
    when p_every is not null then date_trunc('hour', now()) + make_interval(mins => p_every * floor(extract(minute from now()) / p_every)::int)
    else (select max(ts) from (
            select ((d + t::time) at time zone 'Africa/Cairo') ts
              from unnest(p_times) t,
                   (values ((now() at time zone 'Africa/Cairo')::date), ((now() at time zone 'Africa/Cairo')::date - 1)) v(d)) x
           where ts <= now()) end
$$;

do $p$
declare d text := pg_get_functiondef('public.directors_snapshot'::regproc); n text;
begin
  n := replace(d, $o$director_last_run(r.key) last_run, agent_next_run(r.schedule, r.every_minutes) next_run from agent_registry r$o$,
                  $n$director_last_run(r.key) last_run, agent_next_run(r.schedule, r.every_minutes) next_run, agent_prev_run(r.schedule, r.every_minutes) prev_run from agent_registry r$n$);
  n := replace(n, $o$when d.last_run > now() - interval '20 minutes' then 'WORKING'$o$,
                  $n$when d.prev_run > now() - interval '15 minutes' and (d.last_run is null or d.last_run < d.prev_run) then 'WORKING'$n$);
  n := replace(n, $o$'Working — last activity ' || to_char(d.last_run at time zone 'Africa/Cairo', 'HH24:MI')$o$,
                  $n$'Working — run started ' || to_char(d.prev_run at time zone 'Africa/Cairo', 'HH24:MI')$n$);
  if n = d or strpos(n, 'prev_run from agent_registry') = 0 or strpos(n, 'run started') = 0 or strpos(n, 'interval ''20 minutes'' then ''WORKING''') > 0 then
    raise exception 'directors_snapshot status patch did not apply cleanly';
  end if;
  execute n;
end $p$;

-- ---------------------------------------------------------------- 2. project framing
-- Type text only (opportunity type, company type, sector): research descriptions carry boilerplate fields such as
-- "Content opportunity:" on every record, so they would make everything look like content.
create or replace function public.project_type(p_dir text, p_opp_type text, p_company_type text, p_sector text)
returns text language sql immutable as $$
  with x(t) as (select lower(concat_ws(' ', p_opp_type, p_company_type, p_sector)))
  select case
    when p_dir = 'BRANDS' then case
      when t ~ '(automotive|\mcars?\M|motor|vehicle)' then 'AUTOMOTIVE_SHOOT'
      when t ~ '(jewel|watch|horolog)' then 'JEWELLERY_CAMPAIGN'
      when t ~ '(creator|influencer)' then 'CREATOR_TRIP'
      when t ~ '(press trip|public relations|\mpr\M)' then 'PRESS_TRIP'
      when t ~ 'launch' then 'PRODUCT_LAUNCH'
      when t ~ '(activation|event|pop.?up|experience desk)' then 'BRAND_ACTIVATION'
      when t ~ '(production|studio|film|creative agency|content|marketing agency|agency)' then 'CONTENT_PRODUCTION'
      when t ~ '(fashion|apparel|swim|resort ?wear|activewear|athleisure|clothing|womenswear|menswear|streetwear|lingerie|beauty|cosmetic|skincare|fragrance)' then 'FASHION_CAMPAIGN'
      else 'BRAND_SHOOT' end
    when p_dir = 'WEDDINGS' then case when t ~ '(guest desk|guest concierge|vip guest)' then 'WEDDING_GUEST_CONCIERGE' else 'DESTINATION_WEDDING' end
    when p_dir = 'MEDIA' then 'MEDIA_PRODUCTION'
    when p_dir = 'SPORTS' then 'NOYA_PRIVATE_AGENCY'
    when p_dir = 'TRAVEL' then 'TRAVEL_PARTNER'
    when p_dir = 'HOSPITALITY' then case when t ~ '(content|creator|brand trip|host property|shoot|talent|influencer)' then 'HOTEL_CONTENT_PARTNERSHIP' else 'PREFERRED_STAY' end
    when p_dir = 'CORPORATE' then case when t ~ 'white.?label' then 'WHITE_LABEL_CONCIERGE' when t ~ '(retreat|offsite|summit|incentive)' then 'CORPORATE_RETREAT' else 'CORPORATE_CONCIERGE' end
    when p_dir = 'PRIVATE' then case when t ~ '(retreat|founder)' then 'FOUNDER_RETREAT' else 'PRIVATE_NETWORK' end
    when p_dir = 'EGYPT' then 'EGYPT_EVENT'
    else 'PARTNERSHIP' end
  from x
$$;

-- What one relationship can repeatedly bring NOYA (Adam: one agency with 30 players can matter more than 30 names).
create or replace function public.multiplier_reason(p_dir text, p_company_type text, p_partnership_model text)
returns text language sql immutable as $$
  with x(t) as (select lower(coalesce(p_company_type, '')))
  select case
    when t ~ '(football|sport|athlete|talent|player care|celebrity|management agency|representation)' then 'Represents a roster: one relationship can bring repeat private clients and Egypt trips'
    when t ~ '(wedding|event planner|event agency|celebration)' or p_dir = 'WEDDINGS' then 'Plans several high-value events a year: repeat destination projects'
    when t ~ '(travel|concierge|lifestyle|dmc|destination management|tour operator)' or p_dir = 'TRAVEL' then 'Their clients can become recurring Egypt bookings; they keep the client'
    when t ~ '(member|club|community|family office|private office|network)' or p_dir = 'PRIVATE' then 'A private network: introductions and repeat private clients'
    when t ~ '(production|creative|influencer|public relations|\mpr\M|marketing|agency|studio)' then 'Agency with many brands: repeat productions and campaigns'
    when t ~ '(hotel|resort|villa|hospitality|residence)' or p_dir = 'HOSPITALITY' then 'Property network: preferred stays and content collaborations'
    when p_dir = 'BRANDS' then 'Brand with campaign activity: a shoot, launch or creator trip in Egypt'
    when p_dir = 'MEDIA' then 'Media reach: an Egypt episode or production'
    when p_dir = 'CORPORATE' then 'Recurring institutional demand: executives, client events, white-label'
    when p_dir = 'SPORTS' then 'Represents talent: repeat private clients and Egypt trips'
    else coalesce(initcap(replace(p_partnership_model, '_', ' ')) || ' partner', 'Commercial partner') end
  from x
$$;
create or replace function public.is_multiplier(p_dir text, p_company_type text)
returns boolean language sql immutable as $$
  select coalesce(p_company_type, '') ~* '(football|sport.*agency|athlete|talent|player care|celebrity|management agency|representation|wedding|event planner|event agency|travel|concierge|dmc|destination management|member|club|community|family office|private office|production|creative agency|influencer|public relations|\mpr\M|marketing agency|hotel group|hospitality group|collection)'
      or p_dir in ('WEDDINGS', 'TRAVEL', 'SPORTS', 'PRIVATE')
$$;

-- ---------------------------------------------------------------- 3. the CEO dashboard read
create or replace function public.hq_ceo_dashboard()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with
  co as materialized (
    select c.id, c.name, c.company_type, c.sector, c.partnership_model, c.universe_status, c.universe_reason, registrable_domain(c.website) dom,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) dir
      from companies c where coalesce(c.notes, '') not like '%MERGED_INTO:%'),
  gt as materialized (  -- two-way conversations in the NOYA mailbox
    select t.gmail_thread_id, t.subject, t.last_at, t.inbound, t.outbound, t.last_direction, t.last_inbound_at, t.relationship_state, t.counterpart_emails,
           registrable_domain(t.counterpart_domains[1]) dom,
           coalesce(t.company_id, (select co.id from co where co.dom = registrable_domain(t.counterpart_domains[1]) order by co.id limit 1)) company_id
      from gmail_history_threads t
     where t.inbound > 0 and t.outbound > 0 and coalesce(t.relevant, true) and coalesce(t.hq_status, '') <> 'DISMISSED'),
  so as materialized (  -- first message of each sequence (follow-ups never count as new outreach)
    select i.company_id, i.channel, i.occurred_at from interactions i
     where i.direction = 'OUTBOUND' and i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM') and i.company_id is not null and i.occurred_at > now() - interval '30 days'
       and not exists (select 1 from interactions e where e.company_id = i.company_id and e.channel = i.channel and e.direction = 'OUTBOUND'
                        and e.occurred_at < i.occurred_at and e.occurred_at > i.occurred_at - interval '120 days')),
  rp as materialized (  -- replies: CRM interactions and the mailbox, one per counterpart per period
    select i.company_id::text k, i.company_id, i.occurred_at at_, coalesce(i.summary, '') ~ '^(POSITIVE|MEETING_REQUEST|NEEDS_INFO|REFERRAL)' pos
      from interactions i where i.direction = 'INBOUND' and i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM') and i.company_id is not null and i.occurred_at > now() - interval '30 days'
    union all
    select coalesce(gt.company_id::text, gt.dom), gt.company_id, gt.last_inbound_at, gt.relationship_state = 'MEETING' from gt where gt.last_inbound_at > now() - interval '30 days'
    union all
    select o.company_id::text, o.company_id, o.updated_at, true from opportunities o join co on co.id = o.company_id
     where o.status in ('INTERESTED', 'CALL_REQUIRED') and o.updated_at > now() - interval '30 days'),
  mt as materialized (  -- meetings and calls
    select i.company_id::text k, i.company_id, i.occurred_at at_ from interactions i where i.channel = 'MEETING' and i.company_id is not null and i.occurred_at > now() - interval '30 days'
    union all select t.company_id::text, t.company_id, t.created_at from tasks t where t.company_id is not null and (t.task_type = 'MEETING_ACTION' or t.title like 'MEETING --%') and t.created_at > now() - interval '30 days'
    union all select o.company_id::text, o.company_id, o.updated_at from opportunities o where o.status = 'CALL_REQUIRED' and o.updated_at > now() - interval '30 days'
    union all select coalesce(gt.company_id::text, gt.dom), gt.company_id, gt.last_at from gt where gt.relationship_state = 'MEETING' and gt.last_at > now() - interval '30 days'),
  per(p, since) as (values ('week', now() - interval '7 days'), ('d30', now() - interval '30 days')),
  fun as (
    select per.p, jsonb_build_object(
      'sent_email', (select count(*) from so where so.channel = 'EMAIL' and so.occurred_at >= per.since),
      'sent_linkedin', (select count(*) from so where so.channel = 'LINKEDIN' and so.occurred_at >= per.since),
      'sent_instagram', (select count(*) from so where so.channel = 'INSTAGRAM' and so.occurred_at >= per.since),
      'replies', (select count(distinct rp.k) from rp where rp.at_ >= per.since),
      'positive', (select count(distinct rp.k) from rp where rp.at_ >= per.since and rp.pos),
      'meetings', (select count(distinct mt.k) from mt where mt.at_ >= per.since),
      'concepts', (select count(*) from creative_concepts where created_at >= per.since and status = 'USED') + (select count(*) from projects where brief is not null and created_at >= per.since),
      'proposals', (select count(*) from opportunities where status in ('PROPOSAL', 'NEGOTIATION') and updated_at >= per.since),
      'won', (select count(*) from opportunities where status = 'WON' and won_at >= per.since),
      'revenue', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt)), '[]'::jsonb)
                    from (select currency, sum(amount) amt from revenue where coalesce(received_at, created_at) >= per.since and payment_status <> 'CANCELLED' group by 1) r)) j
      from per),
  dirs as (select distinct dir from co where dir is not null),
  bd as (
    select per.p, d.dir, jsonb_build_object(
      'sent', (select count(*) from so join co on co.id = so.company_id where co.dir = d.dir and so.occurred_at >= per.since),
      'sent_email', (select count(*) from so join co on co.id = so.company_id where co.dir = d.dir and so.channel = 'EMAIL' and so.occurred_at >= per.since),
      'replies', (select count(distinct rp.k) from rp join co on co.id = rp.company_id where co.dir = d.dir and rp.at_ >= per.since),
      'positive', (select count(distinct rp.k) from rp join co on co.id = rp.company_id where co.dir = d.dir and rp.at_ >= per.since and rp.pos),
      'meetings', (select count(distinct mt.k) from mt join co on co.id = mt.company_id where co.dir = d.dir and mt.at_ >= per.since),
      'proposals', (select count(*) from opportunities o join co on co.id = o.company_id where co.dir = d.dir and o.status in ('PROPOSAL', 'NEGOTIATION') and o.updated_at >= per.since),
      'wins', (select count(*) from opportunities o join co on co.id = o.company_id where co.dir = d.dir and o.status = 'WON' and o.won_at >= per.since)) j
      from per cross join dirs d),
  -- the most advanced stage each company has reached
  ev as materialized (
    select co.id company_id, co.name, co.dir, co.company_type, co.partnership_model, co.universe_reason,
      exists (select 1 from opportunities o where o.company_id = co.id and o.status not in ('LOST', 'ARCHIVED', 'LONG_TERM')) open_opp,
      exists (select 1 from opportunities o where o.company_id = co.id) any_opp,
      exists (select 1 from projects p where p.company_id = co.id and p.status in ('DELIVERED', 'CLOSED')) proj_done,
      exists (select 1 from projects p where p.company_id = co.id and p.status in ('CONFIRMED', 'PLANNING', 'LIVE')) proj_active,
      exists (select 1 from opportunities o where o.company_id = co.id and o.status = 'WON') won,
      exists (select 1 from opportunities o where o.company_id = co.id and o.status = 'NEGOTIATION') nego,
      exists (select 1 from opportunities o where o.company_id = co.id and o.status = 'PROPOSAL') prop,
      exists (select 1 from creative_concepts cc where cc.company_id = co.id and cc.status <> 'REJECTED') concept,
      exists (select 1 from gt where gt.company_id = co.id and gt.relationship_state = 'MEETING')
        or exists (select 1 from interactions i where i.company_id = co.id and i.channel = 'MEETING')
        or exists (select 1 from opportunities o where o.company_id = co.id and o.status = 'CALL_REQUIRED')
        or exists (select 1 from tasks t where t.company_id = co.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and (t.task_type = 'MEETING_ACTION' or t.title like 'MEETING --%')) meeting,
      exists (select 1 from opportunities o where o.company_id = co.id and o.status = 'INTERESTED')
        or exists (select 1 from interactions i where i.company_id = co.id and i.direction = 'INBOUND' and coalesce(i.summary, '') ~ '^(POSITIVE|MEETING_REQUEST|NEEDS_INFO|REFERRAL)') positive,
      exists (select 1 from gt where gt.company_id = co.id)
        or exists (select 1 from interactions i where i.company_id = co.id and i.direction = 'INBOUND' and i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM')) replied,
      exists (select 1 from interactions i where i.company_id = co.id and i.direction = 'OUTBOUND' and i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM'))
        or exists (select 1 from opportunities o where o.company_id = co.id and o.status in ('CONTACTED', 'FOLLOW_UP')) outreach,
      greatest((select max(i.occurred_at) from interactions i where i.company_id = co.id and i.channel <> 'WEBSITE'),
               (select max(gt.last_at) from gt where gt.company_id = co.id)) last_at,
      (select max(o.updated_at) from opportunities o where o.company_id = co.id) opp_moved,
      exists (select 1 from tasks t where t.company_id = co.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')) open_task
      from co),
  stg as materialized (
    select ev.*, case
        when proj_done then 11 when proj_active then 10 when won then 9 when nego then 8 when prop then 7
        when any_opp and not open_opp and not replied then 0
        when (meeting or positive or replied) and concept then 6
        when meeting then 5 when positive then 4 when replied then 3 when outreach then 2
        when open_opp then 1 else null end rank
      from ev),
  stage_names(rank, stage) as (values (1, 'PROSPECT'), (2, 'OUTREACH'), (3, 'REPLIED'), (4, 'QUALIFIED_CONVERSATION'), (5, 'MEETING'), (6, 'CONCEPT_BRIEF'),
                                       (7, 'PROPOSAL'), (8, 'NEGOTIATION'), (9, 'WON'), (10, 'PROJECT_ACTIVE'), (11, 'COMPLETED'), (0, 'LOST_PARKED')),
  best_opp as materialized (  -- each company's most relevant open opportunity
    select distinct on (o.company_id) o.company_id, o.id, o.status, o.opportunity_type, o.next_action, o.next_action_due, o.commercial_trigger, o.reason, o.value_evidence,
           o.priority, o.contact_id, o.signal_id
      from opportunities o join co on co.id = o.company_id
     where o.status not in ('LOST', 'ARCHIVED', 'LONG_TERM')
     order by o.company_id, case o.status when 'NEGOTIATION' then 0 when 'PROPOSAL' then 1 when 'CALL_REQUIRED' then 2 when 'INTERESTED' then 3 when 'FOLLOW_UP' then 4
                                           when 'CONTACTED' then 5 when 'READY' then 6 else 7 end, o.priority desc nulls last, o.updated_at desc),
  verified as materialized (
    select distinct k.company_id from contacts k where k.email_status = 'VERIFIED' and not coalesce(k.do_not_contact, false) and coalesce(k.email, '') <> ''),
  cand as (  -- live conversations first, then the strongest verified-email-ready prospects
    select s.company_id, s.name, s.dir, s.company_type, s.partnership_model, s.universe_reason, s.rank, s.last_at, null::text dom, null::text subject, null::text gstate,
           (s.rank >= 3) live, b.id opp_id, b.status opp_status, b.opportunity_type, b.next_action, b.commercial_trigger, b.reason, b.value_evidence, b.priority, b.contact_id,
           (select gt.last_direction from gt where gt.company_id = s.company_id order by gt.last_at desc limit 1) last_dir
      from stg s left join best_opp b on b.company_id = s.company_id
     where s.rank between 3 and 10
    union all
    select null, initcap(regexp_replace(split_part(g.dom, '.', 1), '[-_]+', ' ', 'g')), null, null, null, null, case when g.relationship_state = 'MEETING' then 5 else 3 end,
           g.last_at, g.dom, g.subject, g.relationship_state, true, null, null, null, null, null, null, null, null, null, g.last_direction
      from (select distinct on (dom) * from gt where gt.company_id is null and gt.last_at > now() - interval '30 days' and gt.relationship_state in ('MEETING', 'REPLIED')
               and gt.dom !~ '^(gmail|googlemail|hotmail|outlook|live|yahoo|icloud|aol|proton|protonmail|me|msn)\.'
             order by dom, last_at desc) g
    union all
    select * from (
      select s.company_id, s.name, s.dir, s.company_type, s.partnership_model, s.universe_reason, s.rank, s.last_at, null, null, null, false,
             b.id, b.status, b.opportunity_type, b.next_action, b.commercial_trigger, b.reason, b.value_evidence, b.priority, b.contact_id, null::text
        from stg s join best_opp b on b.company_id = s.company_id join co on co.id = s.company_id
       where s.rank = 1 and co.universe_status = 'QUALIFIED' and s.company_id in (select company_id from verified) and b.status in ('READY', 'NEW', 'RESEARCHING')
       order by (b.commercial_trigger is not null) desc, b.priority desc nulls last limit 10) fresh),
  top as (
    select c.*, row_number() over (order by c.live desc, c.rank desc, c.last_at desc nulls last, c.priority desc nulls last) rn from cand c),
  topj as (
    select jsonb_agg(jsonb_build_object(
      'company_id', t.company_id, 'company', t.name, 'director', t.dir,
      'project', case when t.company_id is not null then project_type(t.dir, t.opportunity_type, t.company_type, null)
                      when t.subject ~* '(production|shoot|campaign)' then 'CONTENT_PRODUCTION' when t.subject ~* 'retreat' then 'FOUNDER_RETREAT'
                      when t.subject ~* 'wedding' then 'DESTINATION_WEDDING' when t.subject ~* '(hospitality|property|hotel|stay)' then 'HOTEL_CONTENT_PARTNERSHIP'
                      else 'PARTNERSHIP' end,
      'stage', (select sn.stage from stage_names sn where sn.rank = t.rank), 'live', t.live,
      'relationship', case when t.company_id is not null then relationship_state(t.company_id)
                           when t.gstate = 'MEETING' then 'MEETING_BOOKED' else 'ACTIVE_CONVERSATION' end,
      'last_at', t.last_at,
      'why_now', coalesce(nullif(btrim(t.commercial_trigger), ''),
                          case when t.subject is not null then 'Two-way email: "' || left(t.subject, 90) || '"' end,
                          (select 'Replied ' || to_char(max(gt.last_inbound_at) at time zone 'Africa/Cairo', 'DD Mon') || ': "' || left((array_agg(gt.subject order by gt.last_inbound_at desc))[1], 80) || '"'
                             from gt where gt.company_id = t.company_id having max(gt.last_inbound_at) is not null),
                          nullif(split_part(coalesce(t.reason, ''), '. ', 1), '')),
      'next_move', coalesce(nullif(btrim(t.next_action), ''),
                            (select tk.title from tasks tk where tk.company_id = t.company_id and tk.status in ('OPEN', 'IN_PROGRESS', 'WAITING') order by tk.due_at nulls last limit 1),
                            case when t.rank >= 3 and t.last_dir = 'OUTBOUND' then 'NOYA wrote last (' || to_char(t.last_at at time zone 'Africa/Cairo', 'DD Mon') || '): follow up if there is no answer'
                                 when t.rank >= 5 then 'Book the call and record it' when t.rank >= 3 then 'They wrote last: reply and propose a call' else 'Approve the verified email' end),
      'evidence', coalesce(nullif(btrim(t.value_evidence), ''),
                           (select count(*) || ' email thread' || case when count(*) = 1 then '' else 's' end || ' · ' || sum(gt.inbound) || ' in / ' || sum(gt.outbound) || ' out'
                              from gt where (t.company_id is not null and gt.company_id = t.company_id) or (t.company_id is null and gt.dom = t.dom) having count(*) > 0),
                           nullif(left(btrim(t.universe_reason), 200), '')),
      'strategic_value', multiplier_reason(t.dir, t.company_type, t.partnership_model),
      'multiplier', is_multiplier(t.dir, t.company_type),
      'contact', (select jsonb_build_object('name', nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), ''), 'role', k.position, 'email_status', k.email_status,
                                            'email', case when k.email_status = 'VERIFIED' then k.email end)
                    from contacts k where k.id = t.contact_id)) order by t.rn) j
      from top t where t.rn <= 10),
  bucket as (
    select p.id, p.name, p.status, p.company_id, p.starts_on,
      exists (select 1 from tasks t where t.project_id = p.id and t.status = 'WAITING' and (t.title || ' ' || coalesce(t.description, '')) ~* 'client') awaiting_client,
      exists (select 1 from tasks t where t.project_id = p.id and t.status = 'WAITING' and (t.title || ' ' || coalesce(t.description, '')) ~* '(supplier|vendor|partner)') awaiting_supplier,
      exists (select 1 from revenue r where r.project_id = p.id and r.payment_status in ('PENDING', 'PART_PAID')) payment_required
      from projects p where p.status <> 'CANCELLED')
  select jsonb_build_object(
    'generated_at', now(),
    'funnel', jsonb_build_object('week', (select j from fun where p = 'week'), 'd30', (select j from fun where p = 'd30'),
      'active_projects', (select count(*) from projects where status in ('CONFIRMED', 'PLANNING', 'LIVE')),
      'by_director_week', (select jsonb_object_agg(dir, j) from bd where p = 'week'), 'by_director_30', (select jsonb_object_agg(dir, j) from bd where p = 'd30'),
      'method', 'Sent = the first message of a sequence (follow-ups excluded). Replies = companies or counterparts who wrote back in the period, from the CRM and the NOYA mailbox. Positive = classified positive, meeting request, needs information or referral, or moved to interested or call. Meetings = recorded meetings, meeting tasks, call-required opportunities and email threads at meeting stage. Briefs / concepts = concepts actually used with a counterpart plus project briefs (internal AI concept ideas are not counted).'),
    'pipeline', (select jsonb_agg(jsonb_build_object('stage', sn.stage, 'n', (select count(*) from stg where stg.rank = sn.rank),
                   'stuck', (select count(*) from stg where stg.rank = sn.rank and sn.rank between 3 and 8 and not stg.open_task
                              and coalesce(greatest(stg.last_at, stg.opp_moved), now() - interval '1 year') < now() - interval '7 days'))
                 order by case when sn.rank = 0 then 99 else sn.rank end) from stage_names sn),
    'active_opportunities', (select count(*) from stg where rank between 3 and 8),
    'top_opportunities', coalesce((select j from topj), '[]'::jsonb),
    'directors', (select jsonb_object_agg(d.dir, jsonb_build_object(
        'd7', (select j from bd where bd.p = 'week' and bd.dir = d.dir),
        'top', (select jsonb_build_object('company', t.name, 'company_id', t.company_id, 'project', project_type(t.dir, t.opportunity_type, t.company_type, null),
                                          'stage', (select sn.stage from stage_names sn where sn.rank = t.rank), 'next', t.next_action)
                  from top t where t.dir = d.dir order by t.rn limit 1))) from dirs d),
    'companies', (select jsonb_object_agg(co.id::text, jsonb_build_array(co.dir, (select project_type(co.dir, b.opportunity_type, co.company_type, co.sector) from best_opp b where b.company_id = co.id),
                                                                    (select sn.stage from stg join stage_names sn on sn.rank = stg.rank where stg.company_id = co.id)))
                    from co where co.universe_status is not null or exists (select 1 from opportunities o where o.company_id = co.id)),
    'money', jsonb_build_object(
      'revenue', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt)), '[]'::jsonb) from (select currency, sum(amount) amt from revenue where payment_status <> 'CANCELLED' group by 1) r),
      'fees', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt)), '[]'::jsonb) from (select currency, sum(amount) amt from revenue where payment_status <> 'CANCELLED' and revenue_type ~* 'fee' group by 1) r),
      'commission', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt)), '[]'::jsonb) from (select currency, sum(amount) amt from revenue where payment_status <> 'CANCELLED' and revenue_type ~* 'commission' group by 1) r),
      'supplier_cost', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt)), '[]'::jsonb) from (select currency, sum(supplier_cost) amt from projects where supplier_cost is not null group by 1) r),
      'gross_profit', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt)), '[]'::jsonb) from (select currency, sum(gross_profit) amt from projects where gross_profit is not null group by 1) r),
      'receivables', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt)), '[]'::jsonb) from (select currency, sum(amount) amt from revenue where payment_status in ('PENDING', 'PART_PAID') group by 1) r),
      'records', (select count(*) from revenue) + (select count(*) from projects where supplier_cost is not null or gross_profit is not null or client_charge is not null)),
    'operations', jsonb_build_object(
      'active', (select coalesce(jsonb_agg(to_jsonb(b) order by b.starts_on nulls last), '[]'::jsonb) from bucket b where b.status = 'LIVE'),
      'upcoming', (select coalesce(jsonb_agg(to_jsonb(b) order by b.starts_on nulls last), '[]'::jsonb) from bucket b where b.status in ('CONFIRMED', 'PLANNING')),
      'awaiting_client', (select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb) from bucket b where b.awaiting_client and b.status not in ('DELIVERED', 'CLOSED')),
      'awaiting_supplier', (select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb) from bucket b where b.awaiting_supplier and b.status not in ('DELIVERED', 'CLOSED')),
      'payment_required', (select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb) from bucket b where b.payment_required),
      'completed', (select coalesce(jsonb_agg(to_jsonb(b) order by b.starts_on desc nulls last), '[]'::jsonb) from bucket b where b.status in ('DELIVERED', 'CLOSED'))))
  into v;
  return v;
end $$;
revoke all on function public.hq_ceo_dashboard() from public, anon;
grant execute on function public.hq_ceo_dashboard() to authenticated;

-- ---------------------------------------------------------------- 4. the network
create or replace function public.hq_network()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with
  co as materialized (
    select c.id, c.name, c.company_type, c.partnership_model, registrable_domain(c.website) dom,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) dir
      from companies c where coalesce(c.notes, '') not like '%MERGED_INTO:%'),
  th as materialized (
    select registrable_domain(t.counterpart_domains[1]) dom, t.company_id, t.contact_id, lower(t.counterpart_emails[1]) email, t.subject, t.last_at, t.first_at,
           t.last_direction, t.inbound, t.outbound, t.relationship_state, t.gmail_thread_id
      from gmail_history_threads t
     where t.inbound > 0 and t.outbound > 0 and coalesce(t.relevant, true) and coalesce(t.hq_status, '') <> 'DISMISSED'),
  g as materialized (
    select x.cid company_id, max(x.dom) dom, max(x.last_at) last_at, min(x.first_at) since, sum(x.inbound) inbound, sum(x.outbound) outbound, count(*) threads,
           (array_agg(x.subject order by x.last_at desc))[1] subject, (array_agg(x.last_direction order by x.last_at desc))[1] last_dir,
           (array_agg(x.relationship_state order by x.last_at desc))[1] st, (array_agg(x.email order by x.last_at desc))[1] email,
           (array_agg(x.gmail_thread_id order by x.last_at desc))[1] thread,
           (array_agg(x.contact_id order by x.last_at desc) filter (where x.contact_id is not null))[1] contact_id
      from (select th.*, coalesce(th.company_id, case when th.dom !~ '^(gmail|googlemail|hotmail|outlook|live|yahoo|icloud|aol|proton|protonmail|me|msn)\.' then (select co.id from co where co.dom = th.dom order by co.id limit 1) end) cid,
                   th.dom ~ '^(gmail|googlemail|hotmail|outlook|live|yahoo|icloud|aol|proton|protonmail|me|msn)\.' personal from th) x
     group by x.cid, case when x.cid is null then case when x.personal then x.email else x.dom end end),
  crm as materialized (  -- CRM relationships beyond cold outreach
    select co.id company_id, relationship_state(co.id) st from co
     where exists (select 1 from opportunities o where o.company_id = co.id and o.status in ('INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON'))
        or exists (select 1 from company_relationships cr where cr.company_id = co.id and cr.relationship_status = 'ACTIVE')
        or exists (select 1 from interactions i where i.company_id = co.id and i.direction = 'INBOUND' and i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM'))),
  r as (
    select coalesce(g.company_id, crm.company_id) company_id, g.dom, g.last_at g_last, g.since, g.inbound, g.outbound, g.threads, g.subject, g.last_dir, g.st g_state,
           g.email, g.thread, g.contact_id, crm.st crm_state
      from g full join crm on crm.company_id = g.company_id),
  rr as (
    select r.*, co.name, co.dir, co.company_type, co.partnership_model,
           coalesce(co.name, case when r.dom ~ '^(gmail|googlemail|hotmail|outlook|live|yahoo|icloud|aol|proton|protonmail|me|msn)\.' then r.email else initcap(regexp_replace(split_part(r.dom, '.', 1), '[-_]+', ' ', 'g')) end) display,
           greatest(r.g_last, (select max(i.occurred_at) from interactions i where i.company_id = r.company_id and i.channel <> 'WEBSITE')) last_at,
           (select o from opportunities o where o.company_id = r.company_id and o.status not in ('LOST', 'ARCHIVED', 'LONG_TERM')
             order by case o.status when 'NEGOTIATION' then 0 when 'PROPOSAL' then 1 when 'CALL_REQUIRED' then 2 when 'INTERESTED' then 3 else 4 end, o.priority desc nulls last limit 1) opp,
           (select t.title from tasks t where t.company_id = r.company_id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING') order by t.due_at nulls last limit 1) task,
           (select cr.owner from company_relationships cr where cr.company_id = r.company_id and cr.owner is not null limit 1) owner,
           coalesce((select k from contacts k where k.id = r.contact_id),
                    (select k from contacts k where r.email is not null and lower(k.email) = r.email limit 1)) person
      from r left join co on co.id = r.company_id),
  nw as (
    select rr.*, coalesce(rr.crm_state, case rr.g_state when 'MEETING' then 'MEETING_BOOKED' when 'REPLIED' then 'THEY_WROTE_LAST' when 'WAIT' then 'WAITING_FOR_THEM'
                                                    when 'FOLLOW_UP' then 'FOLLOW_UP' when 'RECONNECT' then 'RECONNECT' when 'LONG_TERM' then 'LONG_TERM' else 'TWO_WAY' end) state,
           is_multiplier(rr.dir, rr.company_type) multiplier,
           (rr.last_at < now() - interval '30 days' and rr.last_at > now() - interval '365 days' and rr.task is null
             and coalesce((rr.opp).status, '') not in ('PROPOSAL', 'NEGOTIATION', 'WON')) going_cold
      from rr)
  select jsonb_build_object(
    'generated_at', now(),
    'counts', jsonb_build_object('relationships', (select count(*) from nw), 'multipliers', (select count(*) from nw where multiplier),
                                 'going_cold', (select count(*) from nw where going_cold), 'in_conversation', (select count(*) from nw where last_at > now() - interval '30 days')),
    'important', coalesce((select jsonb_agg(j order by ord) from (
        select jsonb_build_object(
          'company_id', o.company_id, 'company', o.display, 'domain', o.dom, 'director', o.dir,
          'who', nullif(btrim(coalesce((o.person).first_name, '') || ' ' || coalesce((o.person).last_name, '')), ''), 'role', (o.person).position, 'email', o.email,
          'why', case when o.company_id is null then 'Two-way email relationship with NOYA' else multiplier_reason(o.dir, o.company_type, o.partnership_model) end,
          'multiplier', o.multiplier, 'state', o.state, 'last_at', o.last_at, 'last_dir', o.last_dir, 'threads', o.threads, 'thread', o.thread, 'subject', o.subject,
          'opportunity', case when (o.opp).id is not null then jsonb_build_object('id', (o.opp).id, 'status', (o.opp).status,
                                  'project', project_type(o.dir, (o.opp).opportunity_type, o.company_type, null)) end,
          'next_action', coalesce(nullif(btrim((o.opp).next_action), ''), o.task),
          'owner', coalesce(o.owner, 'Adam'), 'going_cold', o.going_cold) j,
          row_number() over (order by (o.state in ('MEETING_BOOKED', 'PROPOSAL', 'CLIENT', 'PARTNER_ACTIVE', 'ACTIVE_CONVERSATION', 'THEY_WROTE_LAST')) desc,
                                      o.multiplier desc, o.last_at desc nulls last) ord
          from nw o where not o.going_cold) z where ord <= 40), '[]'::jsonb),
    'going_cold', coalesce((select jsonb_agg(jsonb_build_object(
          'company_id', o.company_id, 'company', o.display, 'domain', o.dom, 'director', o.dir,
          'who', nullif(btrim(coalesce((o.person).first_name, '') || ' ' || coalesce((o.person).last_name, '')), ''), 'role', (o.person).position, 'email', o.email,
          'why', case when o.company_id is null then 'Two-way email relationship with NOYA' else multiplier_reason(o.dir, o.company_type, o.partnership_model) end,
          'multiplier', o.multiplier, 'state', o.state, 'last_at', o.last_at, 'last_dir', o.last_dir, 'thread', o.thread, 'subject', o.subject) order by o.multiplier desc, o.last_at desc)
        from nw o where o.going_cold), '[]'::jsonb))
  into v;
  return v;
end $$;
revoke all on function public.hq_network() from public, anon;
grant execute on function public.hq_network() to authenticated;
revoke all on function public.agent_prev_run(text[], integer) from public, anon;

-- ---------------------------------------------------------------- 5. Director missions (Adam, 16 Oct): projects, not names
update public.agent_registry set mission = v.mission, focus = coalesce(v.focus, agent_registry.focus), name = coalesce(v.name, agent_registry.name)
from (values
 ('BRANDS', null,
  'Find brands and agencies with a real reason to use Egypt, and turn them into projects: brand shoots, fashion and jewellery campaigns, creator, influencer and press trips, activations, launches, automotive shoots and content productions. Success is a project, not a brand contacted.',
  'Fashion, womenswear, activewear, swimwear, resortwear, jewellery, watches, beauty, streetwear, premium clothing and automotive, plus marketing, PR, creative and influencer agencies and production companies. Lookalikes of Alo Yoga, Gymshark, Spanx, The Couture Club, House of CB, Adanola, TALA, Hunza G, SKIMS and Represent (seeds, not targets). Signals: destination and international shoots, lookbooks, creator and influencer trips, hotel and resort collaborations, GCC / MENA and Dubai activity, Morocco, Greece, Mykonos and Ibiza campaigns, international launches. Every opportunity answers: what they did, who made it, why Egypt fits, who decides, what NOYA would handle, the next commercial step.'),
 ('WEDDINGS', null,
  'Win destination weddings and private celebrations for Egypt through the planners who already deliver them: luxury and UHNW planners, Indian wedding specialists, GCC and European destination planners and international event agencies. Projects: a destination wedding in Egypt, wedding guest concierge, pre and post-wedding programmes, VIP guest services. The planner keeps the client and creative control.',
  'Planners already running multi-day, destination and high-value private events with international guests. Never a list of planner names: one planner with UHNW clients can matter more than thirty enquiries.'),
 ('MEDIA', null,
  'Create commercially valuable Egypt media projects, never "can Adam come on your podcast?". For each podcast, YouTube format, business, fashion, travel or hospitality outlet, documentary producer or studio, a specific Egypt concept: a Pyramids interview, a Mena House founder conversation, a Grand Egyptian Museum episode, Aswan, the Nile, El Gouna, the Red Sea. Outcomes: collaboration, destination episode, production, sponsorship, content partnership, brand x media x Egypt.',
  'Every opportunity carries the concept, why them, why Egypt, the right person, their email, NOYA''s role and the next action.'),
 ('SPORTS', null,
  'Build relationships that repeatedly create private clients: football agencies, athlete managers, player care, talent and celebrity managers, private travel managers, family and private offices. Success is an agency relationship, a private referral, an Egypt trip, an event visit, a talent stay or a repeat client, never famous names collected. Representatives first; talent is never cold-messaged as the default.',
  null),
 ('HOSPITALITY', null,
  'Build one of the strongest accommodation networks available to an independent concierge, in two separate streams: commercial (preferred stays, rates and client bookings) and content (talent, creator and brand-shoot stays). Hotels, villas, residences, resorts and groups, independents as much as famous brands.',
  null),
 ('TRAVEL', 'Travel & Concierge Partnerships', 'Make NOYA the trusted Egypt execution partner for international travel and concierge companies. They keep the client; NOYA executes Egypt.', null)
) v(key, name, mission, focus)
where agent_registry.key = v.key;
-- Workflow 02's query bank gained the activewear / swimwear / resortwear / womenswear / streetwear / premium clothing
-- categories and the seed brands (n8n/live_code_2026_10_16/02_generate_search_queries.js). Workflow 13's reply classifier
-- backup is gemini-3.5-flash-lite (it was an OpenAI node with no credential, so a Gemini failure left replies unclassified).

-- ---------------------------------------------------------------- 6. Director drill-down: projects, not records
-- Each opportunity also carries what the company did (trigger / research reason), its project type and, for Media, the
-- Egypt concept (concept, backdrop, NOYA's role), so the drill-down answers: what did they do, why Egypt, who decides,
-- what NOYA would handle, the next step.
do $p$
declare d text := pg_get_functiondef('public.director_detail'::regproc); n text;
begin
  n := replace(d, $o$relationship_state(m.id) rel
      from mine m left join lateral$o$,
  $n$relationship_state(m.id) rel, m.agent, m.company_type, m.sector, o.commercial_trigger trig, left(o.reason, 240) why,
           (select jsonb_build_object('concept', cc.concept, 'backdrop', cc.backdrop, 'noya_role', cc.noya_role, 'value', cc.commercial_value)
              from creative_concepts cc where cc.company_id = m.id and cc.status <> 'REJECTED') concept
      from mine m left join lateral$n$);
  n := replace(n, $o$'contact', o.contact, 'relationship', o.rel,$o$,
  $n$'contact', o.contact, 'relationship', o.rel, 'trigger', o.trig, 'why', o.why,
                 'project', project_type(o.agent, o.opportunity_type, o.company_type, o.sector), 'concept', o.concept,$n$);
  if strpos(n, 'o.commercial_trigger trig') = 0 or strpos(n, '''project'', project_type(o.agent') = 0 then
    raise exception 'director_detail patch did not apply cleanly';
  end if;
  execute n;
end $p$;

-- ---------------------------------------------------------------- 7. Outreach Writer status honesty (real defect found in this pass)
-- Workflow 18 ran on schedule (21:30, 22:00, 22:30 Cairo) but, with no verified email ready to draft, made no AI call;
-- director_last_run('WRITER') only saw AI calls, so HQ showed "Missed its schedule" (ERROR) for a healthy, idle writer.
-- Same pattern as the Media Director heartbeat (11 Oct): every live planner run records a heartbeat; an empty run is a run.
do $p$
declare d text := pg_get_functiondef('commercial_director_plan'::regproc);
begin
  if strpos(d, 'heartbeat_w18') = 0 then
    d := replace(d, E'begin\n  if p_replan then',
      E'begin\n  if not p_dry_run then\n    insert into system_config (key, value, note) values (''heartbeat_w18'', jsonb_build_object(''at'', now()),\n      ''Workflow 18 planner ran (a run with nothing to draft is still a run). Read by director_last_run(WRITER).'')\n    on conflict (key) do update set value = excluded.value, updated_at = now();\n  end if;\n  if p_replan then');
    if strpos(d, 'heartbeat_w18') = 0 then raise exception 'commercial_director_plan anchor not found'; end if;
    execute d;
  end if;
  d := pg_get_functiondef('director_last_run'::regproc);
  if strpos(d, 'heartbeat_w18') = 0 then
    d := replace(d, $r$union all select max(revalidated_at) from tasks) s)$r$,
      $r$union all select max(revalidated_at) from tasks
                                           union all select (value->>'at')::timestamptz from system_config where key = 'heartbeat_w18') s)$r$);
    if strpos(d, 'heartbeat_w18') = 0 then raise exception 'director_last_run anchor not found'; end if;
    execute d;
  end if;
end $p$;

-- ---------------------------------------------------------------- 8. Stuck Gmail-draft claims are recoverable from HQ (real defect, seen 8 Oct and 16 Oct)
-- Workflow 12's claim call can time out on the n8n side while the database commits the claim: the row then sits in
-- PROCESSING with no Gmail draft and no way back. A claim older than 10 minutes with no Gmail draft id is offered as
-- Retry on the desk; Retry puts it back to APPROVED (audited) and dispatches workflow 12 again. Draft only, never a send.
create or replace function public.hq_redispatch(p_outbound_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_admin text := hq_admin_email();
  v_row outbound_emails%rowtype;
begin
  select * into v_row from outbound_emails where id = p_outbound_id for update;
  if found and v_row.mode = 'DRAFT' and v_row.status = 'PROCESSING' and v_row.claimed_at < now() - interval '10 minutes'
     and v_row.gmail_draft_id is null and v_row.gmail_message_id is null then
    update outbound_emails set status = 'APPROVED', claimed_at = null, updated_at = now() where id = p_outbound_id;
    insert into approval_audit (opportunity_id, outbound_email_id, action, result, actor, detail)
    values (v_row.opportunity_id, v_row.id, 'RECOVER_CLAIM', 'REQUEUED', v_admin,
      jsonb_build_object('reason', 'Gmail draft step did not finish: claimed ' || to_char(v_row.claimed_at at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ' with no Gmail draft; retried from HQ'));
    return jsonb_build_object('ok', true, 'recovered', true, 'pg_net_request_id', hq_dispatch_outbound(p_outbound_id, v_admin));
  end if;
  if not found or v_row.mode <> 'DRAFT' or v_row.status <> 'APPROVED' or v_row.created_at > now() - interval '2 minutes' then
    return jsonb_build_object('ok', false, 'reason', 'NOT_ELIGIBLE');
  end if;
  return jsonb_build_object('ok', true, 'pg_net_request_id', hq_dispatch_outbound(p_outbound_id, v_admin));
end;
$$;
revoke all on function public.hq_redispatch(uuid) from public, anon;
grant execute on function public.hq_redispatch(uuid) to authenticated, service_role;

do $p$
declare d text := pg_get_functiondef('outreach_desk'::regproc);
begin
  if strpos(d, 'a.claimed_at < now()') = 0 then
    d := replace(d, $r$'can_retry', a.status = 'APPROVED' and a.created_at < now() - interval '2 minutes')$r$,
      $r$'can_retry', (a.status = 'APPROVED' and a.created_at < now() - interval '2 minutes')
                       or (a.status = 'PROCESSING' and a.claimed_at < now() - interval '10 minutes' and a.gmail_draft_id is null and a.gmail_message_id is null))$r$);
    if strpos(d, 'a.claimed_at < now()') = 0 then raise exception 'outreach_desk anchor not found'; end if;
    execute d;
  end if;
end $p$;
