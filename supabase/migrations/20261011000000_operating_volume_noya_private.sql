-- Operating phase (Adam, 8 Oct 2026). No new agents, no HQ redesign: volume through the existing email-first engine.
-- 1. Volume settings: lane mix (Brands first), same-day email top-up, weekly send targets per Director (75-100 a week).
-- 2. NOYA PRIVATE — ATHLETE & TALENT RELATIONS: the Sports & Talent Director upgraded (name, mission, representation-first
--    roles, scouting excluded). Discovery runs in workflow 06; the W18 drafter has the NOYA Private positioning.
-- 3. HQ Advisor: five decision points a day (what needs Adam, which Director is under target, where email coverage is weak,
--    the strongest commercial opportunities incl. NOYA PRIVATE OPPORTUNITY, where to allocate effort).

-- ---------------------------------------------------------------- 1. volume settings
update system_config set value = '{"BRANDS": 6, "WEDDINGS": 4, "TRAVEL_PRIVATE": 4, "PARTNERSHIPS": 3, "SPORTS_PRIVATE": 2, "CORPORATE": 1, "EGYPT_EVENTS": 0}'::jsonb,
       updated_at = now()
 where key = 'acquisition_mix';
update system_config set value = value || '{"email_topup_per_day": 10}'::jsonb, updated_at = now() where key = 'planner_options';
insert into system_config (key, value) values ('weekly_send_targets', jsonb_build_object(
  'note', 'NEW outreaches actually sent per working week (Mon-Fri, Cairo), email as the primary channel. Directors keep at least buffer_weeks of untouched qualified prospects with a decision maker.',
  'total', jsonb_build_array(75, 100), 'buffer_weeks', 2,
  'by_director', jsonb_build_object('BRANDS', jsonb_build_array(20, 25), 'WEDDINGS', jsonb_build_array(12, 18), 'TRAVEL', jsonb_build_array(12, 15),
                                    'HOSPITALITY', jsonb_build_array(10, 12), 'PRIVATE', jsonb_build_array(8, 10), 'SPORTS', jsonb_build_array(8, 12),
                                    'CORPORATE', jsonb_build_array(3, 5), 'MEDIA', jsonb_build_array(2, 3))))
on conflict (key) do update set value = excluded.value, updated_at = now();

-- ---------------------------------------------------------------- 2. NOYA PRIVATE — ATHLETE & TALENT RELATIONS
update agent_registry set
  name = 'NOYA Private — Athlete & Talent Relations',
  mission = 'Make NOYA the trusted private concierge and on-ground Egypt partner for elite athletes, footballers, celebrities, artists and their representatives. The representative keeps the client; NOYA privately handles Egypt.',
  scope = 'Representation first, never the celebrity: football and athlete agencies, player care, talent, celebrity and music management, booking agencies, publicists, sports marketing, athlete concierge, sports law and private offices; and the public Egypt occasions that bring talent.',
  focus = 'Workflow 06 searches representation agencies and public Egypt occasions (concerts, launches, festivals, premieres, sports events) every run; workflow 08 keeps creator discovery. White-label Egypt desk. Judged on agency relationships, referrals, Egypt trips and talent stays, not famous names. 8-12 qualified agency outreaches a week, email first.',
  workflows = array['06 -', '08 -'], schedule = array['08:00', '09:00', '14:00', '20:00']
 where key = 'SPORTS';

create or replace function public.advisor_agent_label(p_key text)
returns text language sql immutable set search_path = public as $$
  select case p_key when 'PRIVATE' then 'Private Membership' when 'HOSPITALITY' then 'Hospitality' when 'TRAVEL' then 'Travel & Concierge'
    when 'BRANDS' then 'Brands & Production' when 'WEDDINGS' then 'Weddings & Events' when 'CORPORATE' then 'Corporate'
    when 'MEDIA' then 'Media & Culture' when 'SPORTS' then 'NOYA Private — Athlete & Talent' when 'EGYPT' then 'Egypt Growth' when 'GROWTH' then 'Growth & Social'
    when 'PARTNERSHIPS' then 'Partnerships' else initcap(lower(coalesce(p_key, 'Other'))) end
$$;

-- Decision makers: scouting staff are never a NOYA route (we do not pitch transfers); the representative is
-- (football / sports / FIFA / licensed / senior agents, talent, artist, player, personal, business and tour managers, publicists, player care).
create or replace function public.role_score(p text)
returns integer language sql immutable as $$
  select case
    when p is null or btrim(p) = '' then 1
    when p ~* '\m(assistant to|executive assistant|personal assistant|pa to)\M' then 3
    when p ~* '\m(founder|co-founder|cofounder|owner|ceo|chief|president|managing director|managing partner|proprietor|chairman|chairwoman)\M' then 5
    when p ~* '\m(hr|human resources|recruit\w*|scout\w*|talent acquisition|front office|guest relations?|reception\w*|housekeeping|engineer\w*|maintenance|accountant|accounting|payroll|intern|trainee|student|waiter|waitress|chef|cook|barista|bartender|sommelier|kitchen|restaurant|brasserie|f&b|food (and|&) beverage|spa|therapist|security officer|driver|legal|counsel|compliance|procurement|purchasing|developer|software|night manager|cashier|butler|valet|board member|non-executive)\M' then 0
    when p ~* '\m(general manager|gm|partner|principal)\M' then 5
    when p ~* '\m(football|sports?|players?|fifa|registered|licensed|senior|talent|booking|music) agents?\M'
      or p ~* '\m(publicist|player (care|services|liaison))\M'
      or p ~* '\m(talent|artist|players?|personal|business|tour) manager\M' then 4
    when p ~* '\m(director|head|vp|vice president|svp|evp)\M' then 4
    when p ~* '\m(partnerships?|business development|commercial|experiential|influencer|brand|marketing|sales|pr|communications|press|events?|production|creative)\M'
     and p ~* '\m(manager|lead)\M' then 4
    when p ~* '\m(manager|lead|producer|planner|designer|curator|editor|buyer)\M' then 3
    else 2 end
$$;

-- Role order per segment; SPORTS now follows the agency hierarchy (founder / MD, senior agent, player and personal managers,
-- player care, lifestyle, client services, commercial, partnerships, operations, travel / logistics; then the celebrity side).
create or replace function public.role_focus(p_segment text)
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
                             'talent manager', 'partnerships']
    when 'MEDIA' then array['founder', 'host', 'editor', 'executive producer', 'partnerships', 'head of content', 'producer']
    when 'CORPORATE' then array['travel manager', 'executive assistant', 'chief of staff', 'head of events', 'workplace experience', 'partnerships',
                                'travel procurement', 'office of the ceo', 'corporate travel']
    when 'CLUB' then array['founder', 'membership director', 'head of partnerships', 'general manager', 'events director', 'concierge']
    when 'SPORTS' then array['founder', 'managing director', 'senior agent', 'agent', 'player manager', 'personal manager', 'business manager',
                             'player care', 'player services', 'lifestyle', 'client services', 'commercial director', 'partnerships',
                             'operations director', 'travel', 'logistics', 'talent manager', 'artist manager', 'publicist', 'tour manager',
                             'booking agent', 'executive assistant', 'player liaison', 'team operations', 'international relations']
    else array['founder', 'director', 'head of partnerships', 'commercial director'] end
$$;

-- ---------------------------------------------------------------- 3. HQ Advisor: five decisions a day
-- Fixed order, one observation each: WHAT NEEDS YOU · UNDER TARGET · EMAIL COVERAGE · STRONGEST OPPORTUNITIES (NOYA PRIVATE
-- OPPORTUNITY when a representation agency has a verified decision-maker email) · ALLOCATE EFFORT. Every line is a count or a
-- record from the database; nothing is generated text. Week = Monday to Friday, Cairo; "new outreach" = the first outbound
-- message NOYA ever sent to that company.
create or replace function public.hq_advisor()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
        v_desk jsonb := outreach_desk(); v_health jsonb;
        v_cfg jsonb := coalesce((select value from system_config where key = 'email_first'), '{}'::jsonb);
        v_tgt jsonb := coalesce((select value from system_config where key = 'weekly_send_targets'), '{}'::jsonb);
        v_hunter jsonb := (select value from system_config where key = 'hunter_account');
        v_since timestamptz; v_hour int := extract(hour from now() at time zone 'Africa/Cairo')::int;
        v_today timestamptz := ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo';
        v_week timestamptz := date_trunc('week', now() at time zone 'Africa/Cairo') at time zone 'Africa/Cairo';
        v_days int := least(extract(isodow from now() at time zone 'Africa/Cairo')::int, 5);
        v_prio text[] := array['BRANDS', 'WEDDINGS', 'TRAVEL', 'HOSPITALITY', 'PRIVATE', 'SPORTS', 'CORPORATE', 'MEDIA'];
        v_obs jsonb := '[]'::jsonb; v_brief jsonb := '[]'::jsonb; v_changed jsonb := '[]'::jsonb; v_win jsonb := '[]'::jsonb; v_waste jsonb := '[]'::jsonb;
        v_replies int; v_reply_names text; v_meet int; v_email_nr int; v_li_nr int; v_gmail int; v_fu_overdue int; v_fu_oldest timestamptz;
        v_brand_today int; v_brand_min int; r record; v_n int;
        v_sent jsonb; v_ready jsonb; v_buffer jsonb; v_total int; v_parts text[] := '{}'; v_steps text[] := '{}';
        v_under record; v_cov record; v_priv jsonb; v_opp text; v_opp_next text; v_buf_low text; v_buf_all text;
        v_credits numeric; v_finder_ok int; v_finder_n int; v_action text;
begin
  v_health := director_channel_health(v_desk);
  v_since := coalesce((select prev_seen_at from hq_advisor_state where admin_email = v_admin), now() - interval '24 hours');

  -- ---- facts
  select count(*), string_agg(distinct coalesce(co.name, 'a reply'), ', ') into v_replies, v_reply_names
    from tasks t left join companies co on co.id = t.company_id
   where t.task_type in ('REPLY_ACTION', 'HUMAN_REVIEW') and t.status in ('OPEN', 'IN_PROGRESS');
  v_meet := (select count(*) from tasks where task_type = 'MEETING_ACTION' and status in ('OPEN', 'IN_PROGRESS'))
          + (select count(*) from opportunities o where o.status = 'CALL_REQUIRED'
              and not exists (select 1 from tasks t where t.opportunity_id = o.id and t.task_type = 'MEETING_ACTION' and t.status in ('OPEN', 'IN_PROGRESS')));
  v_email_nr := coalesce((v_desk->'counts'->'needs_review'->>'EMAIL')::int, 0);
  v_li_nr := coalesce((v_desk->'counts'->'needs_review'->>'LINKEDIN')::int, 0);
  v_gmail := coalesce((v_desk->'counts'->>'gmail_drafts_confirmed')::int, 0);
  select count(*), min((x->>'due_at')::timestamptz) into v_fu_overdue, v_fu_oldest
    from jsonb_array_elements(v_desk->'followups') x where (x->>'due_at')::timestamptz < now();
  v_brand_today := (select count(*) from outreach_candidates oc join companies c on c.id = oc.company_id
                     where not oc.dry_run and oc.channel = 'EMAIL' and oc.draft is not null and oc.created_at >= v_today
                       and agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) = 'BRANDS');
  v_brand_min := coalesce((v_cfg->'brand_daily_verified_target'->>0)::int, 8);
  -- new outreaches sent this week, by Director (first outbound message to the company)
  with ft as (select i.company_id, min(i.occurred_at) first_at from interactions i
               where i.direction = 'OUTBOUND' and i.channel <> 'WEBSITE' and i.company_id is not null group by 1)
  select coalesce(jsonb_object_agg(agent, n), '{}'::jsonb), coalesce(sum(n), 0) into v_sent, v_total
    from (select agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent, count(*) n
            from ft join companies c on c.id = ft.company_id where ft.first_at >= v_week group by 1) s;
  -- drafts ready for Adam, by Director
  select coalesce(jsonb_object_agg(d, n), '{}'::jsonb) into v_ready
    from (select x->>'director' d, count(*) n from jsonb_array_elements(v_desk->'needs_review') x group by 1) s;
  -- one read of the prospect routes (about 2 s): the buffer of untouched qualified prospects with a confirmed decision maker,
  -- by Director, and the best NOYA Private representation agency with a verified decision-maker email
  with p as materialized (
    select pr.*, not exists (select 1 from outreach_candidates oc where oc.company_id = pr.company_id and oc.status <> 'SKIPPED')
                 and not exists (select 1 from interactions i where i.company_id = pr.company_id and i.direction = 'OUTBOUND') untouched
      from prospect_routes() pr)
  select (select coalesce(jsonb_object_agg(agent, n), '{}'::jsonb) from (select agent, count(*) n from p where cold and has_dm and untouched group by 1) s),
         (select to_jsonb(x) from (select c.name, c.company_type, k.first_name || ' ' || k.last_name person, k.position
                                     from p join companies c on c.id = p.company_id join contacts k on k.id = p.contact_id
                                    where p.agent = 'SPORTS' and p.cold and p.state = 'VERIFIED'
                                      and not exists (select 1 from interactions i where i.company_id = p.company_id and i.direction = 'OUTBOUND')
                                    order by role_priority(k.position, 'SPORTS') desc limit 1) x)
    into v_buffer, v_priv;
  v_credits := nullif(v_hunter->>'credits_available', '')::numeric - nullif(v_hunter->>'credits_used', '')::numeric;
  select count(*) filter (where outcome = 'VERIFIED'), count(*) into v_finder_ok, v_finder_n
    from email_finder_log where attempted_at > now() - interval '14 days' and status_code = 200;

  -- ---- brief chips (counts only)
  if v_replies > 0 then v_brief := v_brief || jsonb_build_object('text', v_replies || case when v_replies = 1 then ' reply needs you' else ' replies need you' end, 'tab', 'today'); end if;
  if v_email_nr > 0 then v_brief := v_brief || jsonb_build_object('text', v_email_nr || case when v_email_nr = 1 then ' verified email waiting for approval' else ' verified emails waiting for approval' end, 'tab', 'desk'); end if;
  if v_gmail > 0 then v_brief := v_brief || jsonb_build_object('text', v_gmail || case when v_gmail = 1 then ' approved Gmail draft waiting to send' else ' approved Gmail drafts waiting to send' end, 'tab', 'desk'); end if;
  if v_meet > 0 then v_brief := v_brief || jsonb_build_object('text', v_meet || case when v_meet = 1 then ' meeting or call to handle' else ' meetings or calls to handle' end, 'tab', 'today'); end if;
  if v_fu_overdue > 0 then v_brief := v_brief || jsonb_build_object('text', v_fu_overdue || case when v_fu_overdue = 1 then ' follow-up overdue' else ' follow-ups overdue' end, 'tab', 'today'); end if;
  v_brief := v_brief || jsonb_build_object('text', v_total || ' new outreach' || case when v_total = 1 then '' else 'es' end || ' sent this week (target '
             || coalesce(v_tgt->'total'->>0, '75') || '–' || coalesce(v_tgt->'total'->>1, '100') || ')', 'tab', 'agents');

  -- ---- 1. WHAT NEEDS YOU
  if v_replies > 0 then v_parts := v_parts || (v_replies || ' repl' || case when v_replies = 1 then 'y' else 'ies' end || ' (' || v_reply_names || ')');
                        v_steps := v_steps || ('answer ' || v_reply_names); end if;
  if v_meet > 0 then v_parts := v_parts || (v_meet || case when v_meet = 1 then ' meeting or call' else ' meetings or calls' end); end if;
  if v_gmail > 0 then v_parts := v_parts || (v_gmail || ' approved Gmail draft' || case when v_gmail = 1 then '' else 's' end || ' to send');
                      v_steps := v_steps || ('send the approved Gmail draft' || case when v_gmail = 1 then '' else 's' end); end if;
  if v_email_nr > 0 then v_parts := v_parts || (v_email_nr || ' verified email' || case when v_email_nr = 1 then '' else 's' end || ' to approve');
                         v_steps := v_steps || 'approve the verified emails in Outreach'::text; end if;
  if v_li_nr > 0 then v_parts := v_parts || (v_li_nr || ' LinkedIn fallback' || case when v_li_nr = 1 then '' else 's' end || ' to send by hand'); end if;
  if v_fu_overdue > 0 then v_parts := v_parts || (v_fu_overdue || ' follow-up' || case when v_fu_overdue = 1 then '' else 's' end || ' overdue');
                           v_steps := v_steps || 'clear the oldest follow-ups'::text; end if;
  v_obs := v_obs || jsonb_build_object('rank', 10, 'kind', 'ATTENTION', 'title', 'WHAT NEEDS YOU',
    'situation', case when array_length(v_parts, 1) is null then 'Nothing is waiting for you.' else 'Waiting for you: ' || array_to_string(v_parts, ', ') || '.' end,
    'meaning', 'Replies and meetings are closest to revenue; an approved draft only counts once you press send in Gmail.',
    'action', case when array_length(v_steps, 1) is null then 'Nothing to do here today.'
                   else 'First ' || v_steps[1] || coalesce('; then ' || v_steps[2], '') || coalesce('; then ' || v_steps[3], '') || '.' end,
    'tab', 'today');

  -- ---- 2. UNDER TARGET (furthest behind its pro-rated weekly minimum; priority lanes win ties)
  select k key, (t->>0)::int tmin, (t->>1)::int tmax, coalesce((v_sent->>k)::int, 0) sent,
         ceil((t->>0)::numeric * v_days / 5.0)::int expected, coalesce((v_ready->>k)::int, 0) ready
    into v_under
    from jsonb_each(coalesce(v_tgt->'by_director', '{}'::jsonb)) e(k, t)
   where ceil((t->>0)::numeric * v_days / 5.0)::int - coalesce((v_sent->>k)::int, 0) > 0
   order by ceil((t->>0)::numeric * v_days / 5.0)::int - coalesce((v_sent->>k)::int, 0) desc, array_position(v_prio, k) nulls last limit 1;
  if v_under.key is not null then
    v_obs := v_obs || jsonb_build_object('rank', 20, 'kind', 'TARGET', 'title', 'UNDER TARGET', 'director', v_under.key,
      'situation', advisor_agent_label(v_under.key) || ': ' || v_under.sent || ' new outreach' || case when v_under.sent = 1 then '' else 'es' end
                   || ' sent this week against ' || v_under.tmin || '–' || v_under.tmax || ' (on pace means ' || v_under.expected || ' by today). All Directors: '
                   || v_total || ' of ' || coalesce(v_tgt->'total'->>0, '75') || '–' || coalesce(v_tgt->'total'->>1, '100') || '.',
      'meaning', case when v_under.ready >= v_under.expected - v_under.sent
                      then v_under.ready || ' ' || advisor_agent_label(v_under.key) || ' draft' || case when v_under.ready = 1 then ' is' else 's are' end
                           || ' ready in Outreach, so sending is the limit, not supply.'
                      when v_under.ready > 0
                      then v_under.ready || ' ' || advisor_agent_label(v_under.key) || ' draft' || case when v_under.ready = 1 then ' is' else 's are' end
                           || ' ready; sending ' || case when v_under.ready = 1 then 'it' else 'them' end || ' closes part of the gap, and the other '
                           || (v_under.expected - v_under.sent - v_under.ready) || case when v_under.expected - v_under.sent - v_under.ready = 1 then ' needs' else ' need' end || ' more verified prospects.'
                      else 'No ' || advisor_agent_label(v_under.key) || ' draft is ready, so supply is the limit: this Director needs more verified prospects.' end,
      'action', case when v_under.ready >= v_under.expected - v_under.sent then 'Review and send the ' || advisor_agent_label(v_under.key) || ' drafts first today.'
                     when v_under.ready > 0 then 'Send the ' || v_under.ready || ' ready ' || advisor_agent_label(v_under.key) || ' draft' || case when v_under.ready = 1 then '' else 's' end
                          || ' today; the Email Finder and verification go to ' || advisor_agent_label(v_under.key) || ' first.'
                     else 'Give ' || advisor_agent_label(v_under.key) || ' the Email Finder and verification first; its discovery now researches 10 companies a run.' end,
      'tab', 'desk');
  else
    v_obs := v_obs || jsonb_build_object('rank', 20, 'kind', 'TARGET', 'title', 'ON PACE',
      'situation', 'Every Director is on pace this week: ' || v_total || ' new outreaches sent (target ' || coalesce(v_tgt->'total'->>0, '75') || '–' || coalesce(v_tgt->'total'->>1, '100') || ').',
      'meaning', 'The weekly target is being met through the email-first engine.', 'action', 'Keep the daily review rhythm; no reallocation needed.', 'tab', 'agents');
  end if;

  -- ---- 3. EMAIL COVERAGE (weakest priority lane below the alert line)
  select key, (value->>'with_dm')::int dm, (value->>'verified')::int ver, coalesce((value->>'coverage_pct')::int, 0) cov,
         (value->>'email_gap')::int gap, (value->>'needs_verification')::int nv, (value->>'linkedin_fallback')::int li
    into v_cov
    from jsonb_each(v_health)
   where key <> 'PARTNERSHIPS' and (value->>'with_dm')::int >= coalesce((v_cfg->>'coverage_alert_min_dm')::int, 8)
     and coalesce((value->>'coverage_pct')::int, 0) < coalesce((v_cfg->>'coverage_alert_pct')::int, 30)
   order by array_position(v_prio, key) nulls last, (value->>'with_dm')::int desc limit 1;
  if v_cov.key is not null then
    v_obs := v_obs || jsonb_build_object('rank', 30, 'kind', 'BOTTLENECK', 'title', 'EMAIL COVERAGE', 'director', v_cov.key,
      'situation', advisor_agent_label(v_cov.key) || ' has ' || v_cov.dm || ' qualified companies with a decision maker, but only ' || v_cov.ver || ' with a verified email (' || v_cov.cov || '% coverage).',
      'meaning', v_cov.gap || ' still need email research, ' || v_cov.nv || ' have an address waiting for verification and ' || v_cov.li
                 || ' had public email research exhausted (LinkedIn fallback).'
                 || case when v_credits is not null then ' Hunter ' || coalesce(v_hunter->>'plan', '') || ' had ' || round(v_credits)::int || ' credits left at '
                         || to_char((v_hunter->>'checked_at')::timestamptz at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ' (resets '
                         || coalesce(to_char((v_hunter->>'reset_date')::date, 'DD Mon'), 'monthly') || ').' else '' end,
      'action', case when v_cov.li > v_cov.gap + v_cov.nv then 'Public sources are exhausted for most of ' || advisor_agent_label(v_cov.key) || '; the remaining lever is a provider lookup by name (Email Finder), which needs verification capacity.'
                     when v_cov.nv > v_cov.gap then 'Give verification capacity to the ' || advisor_agent_label(v_cov.key) || ' addresses before adding discovery.'
                     else 'Email Intelligence works the ' || advisor_agent_label(v_cov.key) || ' queue first.' end,
      'tab', 'agents');
  else
    v_obs := v_obs || jsonb_build_object('rank', 30, 'kind', 'BOTTLENECK', 'title', 'EMAIL COVERAGE',
      'situation', 'Email coverage is 30% or better in every priority lane.', 'meaning', 'Email stays the primary channel everywhere.', 'action', 'No change.', 'tab', 'agents');
  end if;

  -- ---- 4. STRONGEST OPPORTUNITIES (NOYA PRIVATE OPPORTUNITY first when one exists)
  select string_agg(s.name || ' (' || s.stage || ')', ', ' order by s.ord, s.priority desc nulls last),
         (array_agg(s.name || ': ' || coalesce(left(s.next_action, 120), 'agree the next step') order by s.ord, s.priority desc nulls last))[1]
    into v_opp, v_opp_next
    from (select c.name, lower(replace(o.status, '_', ' ')) stage, o.next_action, o.priority,
                 case o.status when 'NEGOTIATION' then 0 when 'PROPOSAL' then 1 when 'PROPOSAL_SENT' then 1 when 'MEETING' then 2 when 'CALL_REQUIRED' then 3 else 4 end ord
            from opportunities o join companies c on c.id = o.company_id
           where o.status in ('NEGOTIATION', 'PROPOSAL', 'PROPOSAL_SENT', 'MEETING', 'CALL_REQUIRED')
           order by ord, o.priority desc nulls last limit 3) s;
  if v_priv->>'name' is not null or v_opp is not null then
    v_obs := v_obs || jsonb_build_object('rank', 40, 'kind', case when v_priv->>'name' is not null then 'PRIVATE' else 'OPPORTUNITY' end,
      'title', case when v_priv->>'name' is not null then 'NOYA PRIVATE OPPORTUNITY' else 'STRONGEST OPPORTUNITIES' end,
      'situation', concat_ws(' ',
                     case when v_priv->>'name' is not null then (v_priv->>'name') || coalesce(' (' || (v_priv->>'company_type') || ')', '') || ' has a verified email for '
                          || (v_priv->>'person') || coalesce(', ' || (v_priv->>'position'), '') || ', and NOYA has not contacted them yet.' end,
                     case when v_opp is not null then 'Closest to revenue: ' || v_opp || '.' end),
      'meaning', case when v_priv->>'name' is not null then 'One representative can bring several private clients to Egypt; NOYA works behind them, white-label.'
                      else 'These are the live opportunities closest to revenue.' end,
      'action', case when v_priv->>'name' is not null then 'Approve the NOYA Private email when it reaches Outreach; it offers a short private-services overview.'
                     else 'Next: ' || v_opp_next || '.' end,
      'tab', case when v_priv->>'name' is not null then 'desk' else 'today' end);
  else
    v_obs := v_obs || jsonb_build_object('rank', 40, 'kind', 'OPPORTUNITY', 'title', 'STRONGEST OPPORTUNITIES',
      'situation', 'No live opportunity is at call, meeting, proposal or negotiation stage.', 'meaning', 'Replies are the next source of opportunities.',
      'action', 'Answer replies the same day.', 'tab', 'today');
  end if;

  -- ---- 5. ALLOCATE EFFORT
  select string_agg(advisor_agent_label(k) || ' ' || to_char(coalesce((v_buffer->>k)::numeric, 0) / greatest((t->>0)::numeric, 1), 'FM990.0') || ' wk', ', ' order by array_position(v_prio, k)),
         string_agg(advisor_agent_label(k), ', ' order by array_position(v_prio, k))
           filter (where coalesce((v_buffer->>k)::numeric, 0) < coalesce((v_tgt->>'buffer_weeks')::numeric, 2) * (t->>0)::numeric)
    into v_buf_all, v_buf_low
    from jsonb_each(coalesce(v_tgt->'by_director', '{}'::jsonb)) e(k, t)
   where k = any(array['BRANDS', 'WEDDINGS', 'TRAVEL', 'HOSPITALITY', 'PRIVATE', 'SPORTS']);
  v_action := case
    when v_cov.key is not null and v_cov.li > v_cov.gap + v_cov.nv and coalesce(v_hunter->>'plan', 'Free') = 'Free' then
      'Decide verification capacity (Hunter Starter, €49/month): the Email Finder is capped at 2 lookups a day on Free'
      || case when v_finder_n > 0 then ' and turned ' || v_finder_ok || ' of ' || v_finder_n || ' recent lookups into verified emails' else '' end
      || '; point it at ' || advisor_agent_label(v_cov.key) || ' first.'
    when v_under.key is not null and v_under.ready = 0 then
      'Put research and verification behind ' || advisor_agent_label(v_under.key) || ' this week.'
    when v_buf_low is not null then 'Keep discovery at full volume for ' || v_buf_low || '.'
    else 'Allocation holds: every priority lane has supply and is on pace.' end;
  v_obs := v_obs || jsonb_build_object('rank', 50, 'kind', 'ALLOCATE', 'title', 'ALLOCATE EFFORT',
    'situation', 'Prospect buffer, in weeks of target: ' || coalesce(v_buf_all, 'not measured') || '.',
    'meaning', case when v_buf_low is not null then 'Below ' || coalesce(v_tgt->>'buffer_weeks', '2') || ' weeks: ' || v_buf_low || '. Discovery never pauses for waiting drafts.'
                    else 'Every priority lane holds at least ' || coalesce(v_tgt->>'buffer_weeks', '2') || ' weeks of prospects.' end,
    'action', v_action, 'tab', 'agents');

  -- ---- winning / wasting (30 days of real sends and replies) and what changed
  for r in select agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent,
                  count(*) filter (where i.direction = 'INBOUND') replies, count(*) filter (where i.direction = 'OUTBOUND') sent
             from interactions i join companies c on c.id = i.company_id
            where i.occurred_at > now() - interval '30 days' and i.channel <> 'WEBSITE' group by 1 order by 2 desc, 3 desc loop
    if r.replies > 0 then
      v_win := v_win || jsonb_build_object('director', r.agent, 'text', advisor_agent_label(r.agent) || ': ' || r.replies || ' repl' || case when r.replies = 1 then 'y' else 'ies' end
                                       || ' from ' || r.sent || ' sent (' || round(100.0 * r.replies / nullif(r.sent, 0)) || '%)');
    elsif r.sent >= 5 then
      v_waste := v_waste || jsonb_build_object('director', r.agent, 'text', advisor_agent_label(r.agent) || ': ' || r.sent || ' sent in 30 days, no reply yet — check targeting and angle');
    end if;
  end loop;
  for r in select key, (value->>'linkedin_fallback')::int li, (value->>'verified')::int ver from jsonb_each(v_health)
            where key <> 'PARTNERSHIPS' and (value->>'linkedin_fallback')::int > greatest(4, 2 * (value->>'verified')::int) loop
    v_waste := v_waste || jsonb_build_object('director', r.key, 'text', advisor_agent_label(r.key) || ': ' || r.li || ' LinkedIn fallbacks against ' || r.ver || ' verified emails — email routes are thin here');
  end loop;
  select count(*) into v_n from companies where created_at > v_since and universe_status = 'QUALIFIED';
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' new qualified ' || case when v_n = 1 then 'company' else 'companies' end); end if;
  select count(*) into v_n from contacts where created_at > v_since and identity_status = 'CONFIRMED' and role_score(position) >= 3;
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' new decision ' || case when v_n = 1 then 'maker' else 'makers' end || ' confirmed'); end if;
  select count(*) into v_n from contact_email_verifications where created_at > v_since and provider_status = 'valid';
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' email' || case when v_n = 1 then '' else 's' end || ' verified valid'); end if;
  select count(*) into v_n from email_research where researched_at > v_since;
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' compan' || case when v_n = 1 then 'y' else 'ies' end || ' fully researched for email'); end if;
  select count(*) into v_n from interactions where occurred_at > v_since and direction = 'INBOUND' and channel <> 'WEBSITE';
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' new repl' || case when v_n = 1 then 'y' else 'ies' end); end if;
  select count(*) into v_n from interactions where occurred_at > v_since and direction = 'OUTBOUND';
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' message' || case when v_n = 1 then '' else 's' end || ' sent'); end if;
  select count(*) into v_n from outreach_candidates where created_at > v_since and not dry_run and draft is not null and channel = 'EMAIL';
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' email draft' || case when v_n = 1 then '' else 's' end || ' prepared'); end if;

  return jsonb_build_object(
    'greeting', case when v_hour < 12 then 'Good morning, Adam' when v_hour < 18 then 'Good afternoon, Adam' else 'Good evening, Adam' end,
    'brief', v_brief,
    'observations', coalesce((select jsonb_agg(o order by (o->>'rank')::int) from jsonb_array_elements(v_obs) o), '[]'::jsonb),
    'changed', v_changed, 'since', v_since, 'winning', v_win, 'wasting', v_waste,
    'week', jsonb_build_object('sent', v_sent, 'total', v_total, 'target', v_tgt->'total', 'targets', v_tgt->'by_director', 'working_days', v_days, 'ready', v_ready, 'buffer', v_buffer),
    'coverage', (select jsonb_object_agg(key, jsonb_build_object('coverage_pct', value->'coverage_pct', 'with_dm', value->'with_dm', 'verified', value->'verified')) from jsonb_each(v_health)),
    'generated_at', now());
end $$;
revoke all on function public.hq_advisor() from public, anon;
grant execute on function public.hq_advisor() to authenticated;

-- ---------------------------------------------------------------- 4. weekly review carries each Director's weekly target
do $p$ declare d text := pg_get_functiondef('public.hq_weekly_review()'::regprocedure);
begin
  if position('''target'', (select value' in d) = 0 then
    if position($o$'linkedin_fallback', h.value->'linkedin_fallback',$o$ in d) = 0 then raise exception 'hq_weekly_review: pattern not found'; end if;
    execute replace(d, $o$'linkedin_fallback', h.value->'linkedin_fallback',$o$,
      $n$'linkedin_fallback', h.value->'linkedin_fallback', 'target', (select value->'by_director'->h.key from system_config where key = 'weekly_send_targets'),$n$);
  end if;
end $p$;

-- ---------------------------------------------------------------- 5. NOYA Private agencies get email research in good time
-- (8-12 a week target): the Sports / Talent weight in the email research queue rises from 12 to 32.
do $p$ declare d text := pg_get_functiondef('public.email_gap_list(integer,text,boolean)'::regprocedure);
begin
  if position($o$when 'SPORTS' then 12 else 10 end strategic,$o$ in d) > 0 then
    execute replace(d, $o$when 'SPORTS' then 12 else 10 end strategic,$o$, $n$when 'SPORTS' then 32 else 10 end strategic,$n$);
  end if;
end $p$;
