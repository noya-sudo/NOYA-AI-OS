-- LinkedIn Relationship Agent, Meeting Assist and the morning Top 5 (Adam, 19 Oct 2026: "LinkedIn becomes a high-value
-- relationship and meeting channel, not a mass automation channel").
-- No new system: the agent's work queue is one table linked to contacts, companies, opportunities, tasks and outreach
-- candidates; sends and replies are logged through hq_log_touch so they count in the canonical funnel (commercial_messages /
-- commercial_facts); meetings use the existing MEETING_ACTION tasks and the "MEETING --" record the funnel already counts.
-- Nothing is ever sent: Adam copies the message, opens LinkedIn and sends it himself; HQ only records what he did. No LinkedIn
-- password, cookie or session token is stored or used, and nothing scrapes LinkedIn.

-- ---------------------------------------------------------------- 1. the agent's work queue
create table if not exists public.linkedin_actions (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid references public.contacts(id) on delete cascade,
  company_id uuid references public.companies(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  task_id uuid references public.tasks(id) on delete set null,
  candidate_id uuid,
  director text,
  state text not null default 'READY' check (state in ('READY', 'CONNECTION_SENT', 'CONNECTED', 'SENT', 'REPLIED', 'MEETING', 'HELD', 'CLOSED')),
  connection text not null default 'UNKNOWN' check (connection in ('UNKNOWN', 'CONNECTED', 'NOT_CONNECTED')),
  message text,            -- 40-80 words: the specific reason, the Egypt opportunity, NOYA's role, one simple next step
  connection_note text,    -- for a request when Adam is not connected (LinkedIn allows 200-300 characters)
  followup text,           -- sent after the request is accepted
  why_them text, why_now text, project text, next_action text,
  connection_sent_at timestamptz, connected_at timestamptz, sent_at timestamptz,
  replied_at timestamptz, reply_text text,
  reply_class text check (reply_class is null or reply_class in ('POSITIVE', 'QUESTION', 'INFO_REQUEST', 'MEETING_INTENT', 'INTRODUCTION', 'NOT_NOW', 'SOFT_NO', 'DECLINED')),
  response_draft text, meeting_task_id uuid, hold_reason text,
  source text not null default 'DESK',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint linkedin_actions_person_opp unique nulls not distinct (contact_id, opportunity_id));
alter table public.linkedin_actions enable row level security;
revoke all on public.linkedin_actions from anon, authenticated;
comment on table public.linkedin_actions is 'LinkedIn Relationship Agent work queue: one row per person and opportunity. Adam sends every message himself; HQ records the send, the reply and the meeting. Never automated sending, never scraping.';

-- ---------------------------------------------------------------- 2. registry: a shared specialist that serves every Director
insert into public.agent_registry (key, name, kind, sort, scope, focus, workflows, schedule, every_minutes, max_gap_hours, run_logged, ai_workflows, v3_role, mission)
values ('LINKEDIN', 'LinkedIn Relationship Agent', 'SUPPORT', 27,
  'Turns strategic LinkedIn relationships into conversations and meetings for every Director: the right person, a short personal message or connection note, reply handling and meeting assist.',
  'Prepares messages and connection notes in Outreach → LinkedIn; Adam copies, opens LinkedIn and sends; logs the send, the reply and the meeting',
  '{}', '{}', null, 48, false, '{}', 'SUPPORT',
  'LinkedIn as a high-value relationship and meeting channel, never mass automation. Adam keeps the Send. Success is replies and meetings, not drafts.')
on conflict (key) do update set name = excluded.name, kind = excluded.kind, sort = excluded.sort, scope = excluded.scope, focus = excluded.focus,
  v3_role = excluded.v3_role, mission = excluded.mission, max_gap_hours = excluded.max_gap_hours;

-- ---------------------------------------------------------------- 3. sync: LinkedIn items Adam would send land in the queue
-- Source: the Outreach desk's LinkedIn items waiting for Adam (they already passed the email-first gate). Re-running is safe.
create or replace function public.linkedin_sync()
returns int language plpgsql security definer set search_path = public as $$
declare d jsonb := outreach_desk(); x jsonb; n int := 0;
begin
  for x in select e from jsonb_array_elements(coalesce(d->'needs_review', '[]'::jsonb)) e
            where e->>'channel' = 'LINKEDIN' and nullif(e->>'contact_id', '') is not null loop
    insert into linkedin_actions (contact_id, company_id, opportunity_id, task_id, candidate_id, director, message, why_them, why_now, project, next_action, source)
    select (x->>'contact_id')::uuid, nullif(x->>'company_id', '')::uuid, nullif(x->>'opportunity_id', '')::uuid, nullif(x->>'task_id', '')::uuid,
           nullif(x->>'candidate_id', '')::uuid, x->>'director', nullif(x->>'draft', ''), nullif(x->>'angle', ''), nullif(x->>'why_now', ''),
           (select coalesce(o.egypt->>'proposed_project', o.angle) from opportunities o where o.id = nullif(x->>'opportunity_id', '')::uuid),
           'Copy the message, open LinkedIn and send it yourself, then press Mark sent. Not connected? Send the connection note instead.', 'DESK'
    on conflict on constraint linkedin_actions_person_opp do update
       set task_id = coalesce(linkedin_actions.task_id, excluded.task_id), candidate_id = coalesce(linkedin_actions.candidate_id, excluded.candidate_id),
           message = coalesce(linkedin_actions.message, excluded.message), why_now = coalesce(linkedin_actions.why_now, excluded.why_now),
           project = coalesce(linkedin_actions.project, excluded.project), updated_at = now()
     where linkedin_actions.state in ('READY', 'HELD');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.linkedin_sync() from public, anon, authenticated;

-- ---------------------------------------------------------------- 4. reply classification and suggested responses
-- Conservative keyword rules on the text Adam pastes (a LinkedIn notification never carries the full message). Adam can override
-- the class in one tap; the suggested response is a starting point he edits and sends himself.
create or replace function public.linkedin_classify(p_text text)
returns text language sql immutable set search_path = public as $$
  select case
    when t ~* '(not interested|no,? thank|please (remove|stop)|unsubscribe|not a (good )?fit|we (do not|don''t) (work|need|use)|decline)' then 'DECLINED'
    when t ~* '(call|chat|speak|talk|meet|meeting|zoom|teams|catch[ -]?up|coffee)' and t ~* '(happy|glad|keen|let''?s|would love|available|free (on|next|this)|send (me |over )?(some |a few )?(times|slots)|when (are|is) (you|good)|book|schedule|arrange|diary|calendar|next week)' then 'MEETING_INTENT'
    when t ~* '(introduc|copying in|cc''?ing|looping in|connect you with|right person (is|would be)|speak (to|with) my colleague|reach out to)' then 'INTRODUCTION'
    when t ~* '(not (right )?now|next year|later (this|in the) year|in (a few|some|a couple of) months|revisit|circle back|bad timing|after (the )?(summer|holidays|season))' then 'NOT_NOW'
    when t ~* '(not (really )?(something|for us)|no plans|not at the moment|unlikely|we already (have|work)|already work with)' then 'SOFT_NO'
    when t ~* '(send (me |us |over )?(more |some |a )?(info|information|details|deck|brochure|rates|pricing|proposal|portfolio|outline)|more details|rate card|how much|pricing|price)' then 'INFO_REQUEST'
    when t ~ '\?' then 'QUESTION'
    else 'POSITIVE' end
  from (select coalesce(p_text, '') t) x
$$;

create or replace function public.linkedin_response(p_class text, p_first text, p_project text)
returns text language sql immutable set search_path = public as $$
  select case p_class
    when 'MEETING_INTENT' then 'Thank you, ' || n || '. Glad this is of interest. Would [time 1] or [time 2] (UK time) suit for a 20-minute call? I will send an invite to whichever works.'
    when 'POSITIVE' then 'Thank you, ' || n || '. The simplest next step would be a 20-minute call to understand how you work and where ' || p || ' could fit. Would sometime next week suit?'
    when 'INFO_REQUEST' then 'Thank you, ' || n || '. I will put together a short one-page outline of ' || p || ', with what NOYA would run on the ground. What is the best email to send it to?'
    when 'QUESTION' then 'Thank you, ' || n || '. [Answer the question in one or two lines.] Happy to explain more on a short call if useful.'
    when 'INTRODUCTION' then 'Thank you, ' || n || ', that is kind of you. I will reach out to them directly and mention that you suggested it.'
    when 'NOT_NOW' then 'Understood, ' || n || ', thank you. I will come back to you nearer the time. If anything in Egypt comes up before then, I am here.'
    when 'SOFT_NO' then 'Thank you for the honest reply, ' || n || '. If Egypt ever comes up for a client, I would be glad to help.'
    when 'DECLINED' then 'Thank you for letting me know, ' || n || '. All the best.'
  end
  from (select coalesce(nullif(btrim(p_first), ''), 'there') n,
               coalesce(nullif(btrim(regexp_replace(split_part(coalesce(p_project, ''), ':', 1), '\s+', ' ', 'g')), ''), 'an Egypt project') p) x
$$;

-- ---------------------------------------------------------------- 5. Meeting Assist
-- A meeting intent (LinkedIn or email) opens one MEETING_ACTION task per opportunity. The daily check (Claude, with Adam's
-- Google Calendar) finds two real free times and writes them, with the reply, into the task (meeting_assist_set_slots). When
-- the other side confirms, hq_meeting_confirm records the meeting (the funnel's "MEETING --" record), links it to the person,
-- company, opportunity, Director and relationship, and stores a short briefing. The Calendar event is created in Adam's own
-- calendar without inviting anyone; Adam adds the guest himself.
create or replace function public.meeting_assist_open(p_opp uuid, p_contact uuid, p_source text, p_ref uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_co uuid; v_name text; v_person text;
begin
  select id into v_id from tasks where opportunity_id = p_opp and p_opp is not null and task_type = 'MEETING_ACTION' and status in ('OPEN', 'IN_PROGRESS') limit 1;
  if v_id is not null then
    update tasks set spec = coalesce(spec, '{}'::jsonb) || jsonb_build_object('assist', true, 'source', p_source, 'ref', p_ref) where id = v_id;
    return v_id;
  end if;
  select o.company_id, c.name into v_co, v_name from opportunities o left join companies c on c.id = o.company_id where o.id = p_opp;
  select btrim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')) into v_person from contacts where id = p_contact;
  insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at, spec)
  values (v_co, p_contact, p_opp, 'MEETING ASSIST -- ' || coalesce(v_name, 'company') || coalesce(' · ' || nullif(v_person, ''), ''),
          'They want to talk (' || initcap(lower(p_source)) || '). Meeting Assist checks Adam''s calendar and proposes two real times in the reply. Adam sends it; when they confirm, press Confirm meeting.',
          'MEETING_ACTION', 'Adam', 'LinkedIn Relationship Agent', 92, 'OPEN', now() + interval '1 day',
          jsonb_build_object('assist', true, 'source', p_source, 'ref', p_ref, 'state', 'NEEDS_SLOTS', 'opened_at', now()))
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.meeting_assist_open(uuid, uuid, text, uuid) from public, anon, authenticated;

create or replace function public.meeting_assist_set_slots(p_task uuid, p_slots jsonb, p_reply text, p_timezone text default 'Europe/London')
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update tasks set spec = coalesce(spec, '{}'::jsonb) || jsonb_build_object('state', 'SLOTS_PROPOSED', 'slots', p_slots, 'reply', p_reply,
                     'timezone', p_timezone, 'calendar_checked_at', now()),
         description = regexp_replace(coalesce(description, ''), E'\n\nPROPOSED TIMES:.*$', '', 's') || E'\n\nPROPOSED TIMES: ' ||
           (select string_agg(to_char((s->>'start')::timestamptz at time zone p_timezone, 'Dy DD Mon HH24:MI'), ' or ') from jsonb_array_elements(p_slots) s)
           || ' (' || p_timezone || E', checked against Adam''s calendar)\nREPLY: ' || coalesce(p_reply, '')
   where id = p_task and task_type = 'MEETING_ACTION';
  update linkedin_actions set response_draft = coalesce(p_reply, response_draft), updated_at = now() where meeting_task_id = p_task;
  return jsonb_build_object('ok', found);
end $$;
revoke all on function public.meeting_assist_set_slots(uuid, jsonb, text, text) from public, anon, authenticated;

create or replace function public.meeting_briefing(p_opp uuid, p_contact uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with o as (select o.*, c.name co_name, c.country co_country, c.company_type co_type, c.website co_website from opportunities o join companies c on c.id = o.company_id where o.id = p_opp),
  k as (select * from contacts where id = p_contact),
  h as (select i.occurred_at, i.channel, i.direction, left(regexp_replace(coalesce(i.summary, i.subject, ''), '\s*\(logged in HQ by [^)]*\)', ''), 220) s
          from interactions i, o where i.company_id = o.company_id order by i.occurred_at desc limit 6)
  select jsonb_build_object(
    'who', (select jsonb_build_object('name', btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), 'role', k.position, 'linkedin', nullif(k.linkedin, '')) from k),
    'company', (select jsonb_build_object('name', co_name, 'country', co_country, 'type', co_type, 'website', co_website) from o),
    'why_they_matter', (select coalesce(egypt->>'why_egypt', angle, reason) from o),
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', occurred_at, 'channel', channel, 'direction', direction, 'summary', s)) from h), '[]'::jsonb),
    'pitch', (select coalesce(egypt->>'proposed_project', angle) from o),
    'egypt_opportunity', (select concat_ws(' · ', egypt->>'egypt_format', egypt->>'why_now') from o),
    'questions', (select case egypt->>'bucket'
        when 'WEDDINGS' then '["Which couples are looking beyond Europe for 2027?","Typical guest count and length of the celebration?","How do you work with ground partners today: fee, commission or on your invoice?","What would a first Egypt wedding need to prove to you?"]'::jsonb
        when 'BRAND_PRODUCTION' then '["Which clients run international shoots, trips or launches next year?","How are production partners chosen and paid?","What would make Egypt an easy yes for a client?","Who signs off the budget?"]'::jsonb
        when 'PRIVATE_CLUBS' then '["How many member trips a year, and how are destinations chosen?","Typical group size and price per member?","Do you work with a ground partner today?","Could an Egypt programme go on the 2027 calendar?"]'::jsonb
        when 'TRAVEL' then '["How do advisors choose a ground partner in a destination?","Commission and payment terms you expect?","Which client profiles ask for Egypt?","What is the step to become a preferred Egypt partner?"]'::jsonb
        when 'MEDIA' then '["What is on the 2027 slate where Egypt fits the story?","Who funds location shoots: you, the commissioner or a partner brand?","What do you need on the ground: permits, access, hospitality?","Who decides the location?"]'::jsonb
        else '["What would make Egypt relevant for you or your clients this year?","How do you work with local partners today?","Who else should be part of the conversation?","What would a good first project look like?"]'::jsonb end from o),
    'outcome', 'Agree one specific Egypt project and the brief: dates, scope or guests, budget range, decision maker and timing. Studio prepares the brief after the call.')
$$;
revoke all on function public.meeting_briefing(uuid, uuid) from public, anon, authenticated;

create or replace function public.hq_meeting_confirm(p_task uuid, p_start timestamptz, p_minutes int default 30, p_where text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); t tasks%rowtype; v_name text; v_meet uuid; v_brief jsonb;
begin
  select * into t from tasks where id = p_task and task_type = 'MEETING_ACTION';
  if t.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if p_start is null or p_start < now() - interval '1 day' then return jsonb_build_object('ok', false, 'reason', 'START_REQUIRED'); end if;
  if t.opportunity_id is null then return jsonb_build_object('ok', false, 'reason', 'OPPORTUNITY_REQUIRED'); end if;
  select name into v_name from companies where id = t.company_id;
  v_brief := meeting_briefing(t.opportunity_id, t.contact_id);
  insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at, spec)
  values (t.company_id, t.contact_id, t.opportunity_id,
          'MEETING -- ' || coalesce(v_name, 'company') || ' · ' || to_char(p_start at time zone 'Europe/London', 'DD Mon HH24:MI') || ' UK',
          'Meeting booked (confirmed by them). Briefing in HQ. Record the outcome after the call.' || coalesce(E'\nWhere: ' || hq_trim(p_where), ''),
          'MEETING_BOOKED', 'Adam', 'HQ (' || v_admin || ')', 95, 'OPEN', p_start,
          jsonb_build_object('start', p_start, 'end', p_start + make_interval(mins => greatest(coalesce(p_minutes, 30), 10)), 'where', hq_trim(p_where),
                             'calendar', 'TO_CREATE', 'briefing', v_brief, 'assist_task', t.id))
  returning id into v_meet;
  update tasks set status = 'COMPLETED', completed_at = now(), spec = coalesce(spec, '{}'::jsonb) || jsonb_build_object('state', 'CONFIRMED', 'meeting_task', v_meet),
         description = coalesce(description, '') || E'\n\nConfirmed in HQ: ' || to_char(p_start at time zone 'Europe/London', 'Dy DD Mon HH24:MI') || ' UK'
   where id = t.id;
  update opportunities set status = case when status in ('NEW', 'RESEARCHING', 'READY', 'CONTACTED', 'FOLLOW_UP', 'INTERESTED', 'LONG_TERM') then 'CALL_REQUIRED' else status end,
         next_action = 'Meeting ' || to_char(p_start at time zone 'Europe/London', 'Dy DD Mon HH24:MI') || ' UK: briefing ready in HQ. Record the outcome after the call.',
         next_action_due = (p_start at time zone 'Europe/London')::date, updated_at = now()
   where id = t.opportunity_id;
  insert into relationship_notes (company_id, opportunity_id, kind, body, created_by)
  values (t.company_id, t.opportunity_id, 'MEETING_NOTES', 'Meeting booked for ' || to_char(p_start at time zone 'Europe/London', 'Dy DD Mon YYYY HH24:MI') || ' UK' || coalesce(' (' || hq_trim(p_where) || ')', ''), v_admin);
  update linkedin_actions set state = 'MEETING', next_action = 'Meeting ' || to_char(p_start at time zone 'Europe/London', 'DD Mon HH24:MI') || ' UK', updated_at = now()
   where meeting_task_id = t.id or (opportunity_id = t.opportunity_id and contact_id is not distinct from t.contact_id and state = 'REPLIED');
  perform hq_audit('MEETING_CONFIRMED', t.opportunity_id, jsonb_build_object('task', t.id, 'meeting_task', v_meet, 'start', p_start));
  return jsonb_build_object('ok', true, 'meeting_task', v_meet, 'briefing', v_brief);
end $$;
revoke all on function public.hq_meeting_confirm(uuid, timestamptz, int, text) from public, anon;
grant execute on function public.hq_meeting_confirm(uuid, timestamptz, int, text) to authenticated;

-- ---------------------------------------------------------------- 6. Adam's actions on a LinkedIn item
create or replace function public.hq_linkedin_action(p_id uuid, p_action text, p_text text default null, p_date date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); a linkedin_actions%rowtype; v_act text := upper(coalesce(p_action, '')); v_txt text := hq_trim(p_text);
        v_follow date; r jsonb; v_words int;
begin
  select * into a from linkedin_actions where id = p_id for update;
  if a.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if v_act in ('EDIT', 'EDIT_NOTE', 'EDIT_FOLLOWUP') and v_txt is null then return jsonb_build_object('ok', false, 'reason', 'EMPTY'); end if;
  if v_act = 'EDIT' then
    update linkedin_actions set message = v_txt, updated_at = now() where id = a.id;
    if a.task_id is not null and exists (select 1 from tasks where id = a.task_id and status in ('OPEN', 'IN_PROGRESS', 'WAITING')) then
      perform hq_outreach_edit(a.task_id, null, v_txt);
    end if;
  elsif v_act = 'EDIT_NOTE' then
    if length(v_txt) > 300 then return jsonb_build_object('ok', false, 'reason', 'NOTE_TOO_LONG', 'limit', 300); end if;
    update linkedin_actions set connection_note = v_txt, updated_at = now() where id = a.id;
  elsif v_act = 'EDIT_FOLLOWUP' then
    update linkedin_actions set followup = v_txt, updated_at = now() where id = a.id;
  elsif v_act = 'CONNECTION_SENT' then
    if a.connection_note is null then return jsonb_build_object('ok', false, 'reason', 'NO_CONNECTION_NOTE'); end if;
    r := hq_log_touch(p_channel => 'LINKEDIN', p_summary => 'LinkedIn connection request sent by Adam with a note: ' || a.connection_note,
                      p_company => a.company_id, p_contact => a.contact_id, p_opportunity => a.opportunity_id, p_outcome => 'Connection request sent');
    update linkedin_actions set state = 'CONNECTION_SENT', connection = 'NOT_CONNECTED', connection_sent_at = now(), updated_at = now(),
           next_action = 'Waiting for them to accept. When they do, press Connected: the follow-up message becomes ready.' where id = a.id;
    update tasks set status = 'WAITING', description = coalesce(description, '') || E'\n\nConnection request sent ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ', waiting for acceptance.'
     where id = a.task_id and status in ('OPEN', 'IN_PROGRESS');
  elsif v_act = 'CONNECTED' then
    update linkedin_actions set state = 'CONNECTED', connection = 'CONNECTED', connected_at = now(), updated_at = now(),
           next_action = 'Connected: copy the follow-up, open LinkedIn and send it, then press Mark sent.' where id = a.id;
    update tasks set status = 'OPEN', description = coalesce(description, '') || E'\n\nConnected ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ': follow-up ready.'
     where id = a.task_id and status = 'WAITING';
    if a.task_id is not null and coalesce(a.followup, '') <> '' then perform hq_outreach_edit(a.task_id, null, a.followup); end if;
  elsif v_act = 'SENT' then
    v_follow := coalesce(p_date, current_date + 5);
    r := hq_log_touch(p_channel => 'LINKEDIN', p_summary => 'LinkedIn message sent by Adam: ' || left(coalesce(case when a.state = 'CONNECTED' then coalesce(a.followup, a.message) else a.message end, ''), 600),
                      p_company => a.company_id, p_contact => a.contact_id, p_opportunity => a.opportunity_id, p_task => a.task_id, p_follow_up => v_follow,
                      p_outcome => 'LinkedIn message sent');
    if (r->>'ok')::boolean is not true then return r; end if;
    update linkedin_actions set state = 'SENT', sent_at = now(), updated_at = now(),
           next_action = 'Waiting for a reply. Follow-up booked for ' || to_char(v_follow, 'DD Mon') || '. When they reply, paste it with Log reply.' where id = a.id;
    update outreach_candidates set status = 'SENT', updated_at = now() where id = a.candidate_id and status in ('READY', 'APPROVED', 'REVIEW_REQUIRED');
  elsif v_act = 'HOLD' then
    update linkedin_actions set state = 'HELD', hold_reason = coalesce(v_txt, 'Held by Adam'), updated_at = now(), next_action = 'On hold: ' || coalesce(v_txt, 'held by Adam') where id = a.id;
    update tasks set status = 'WAITING', due_at = coalesce(p_date::timestamptz, due_at) where id = a.task_id and status in ('OPEN', 'IN_PROGRESS');
  elsif v_act = 'RELEASE' then
    update linkedin_actions set state = 'READY', hold_reason = null, updated_at = now(),
           next_action = 'Copy the message, open LinkedIn and send it yourself, then press Mark sent.' where id = a.id;
    update tasks set status = 'OPEN' where id = a.task_id and status = 'WAITING';
  elsif v_act = 'CLOSE' then
    update linkedin_actions set state = 'CLOSED', hold_reason = coalesce(v_txt, hold_reason), updated_at = now(), next_action = null where id = a.id;
    update tasks set status = 'CANCELLED', description = coalesce(description, '') || E'\n\nClosed in HQ (LinkedIn): ' || coalesce(v_txt, 'not relevant now')
     where id = a.task_id and status in ('OPEN', 'IN_PROGRESS', 'WAITING');
  else
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION');
  end if;
  perform hq_audit('LINKEDIN_' || v_act, a.opportunity_id, jsonb_build_object('linkedin_action', a.id, 'contact', a.contact_id));
  select * into a from linkedin_actions where id = p_id;
  v_words := array_length(regexp_split_to_array(btrim(coalesce(a.message, '')), '\s+'), 1);
  return jsonb_build_object('ok', true, 'state', a.state, 'words', v_words,
    'warning', case when v_act = 'EDIT' and (v_words < 25 or v_words > 100) then 'LinkedIn messages work best at 40 to 80 words.' end);
end $$;
revoke all on function public.hq_linkedin_action(uuid, text, text, date) from public, anon;
grant execute on function public.hq_linkedin_action(uuid, text, text, date) to authenticated;

-- Adam pastes the reply (from LinkedIn, never assumed from a notification). Classified, logged as a LinkedIn reply on the
-- canonical funnel, follow-ups cancelled, a response suggested, and Meeting Assist opened on a meeting intent.
create or replace function public.hq_linkedin_reply(p_id uuid, p_text text, p_class text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); a linkedin_actions%rowtype; v_txt text := hq_trim(p_text); v_class text; v_first text; v_person text;
        v_resp text; v_prefix text; v_co text; v_meet uuid; v_url text; v_label text;
begin
  select * into a from linkedin_actions where id = p_id for update;
  if a.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if v_txt is null then return jsonb_build_object('ok', false, 'reason', 'PASTE_THE_REPLY'); end if;
  v_class := coalesce(upper(nullif(btrim(p_class), '')), linkedin_classify(v_txt));
  if v_class not in ('POSITIVE', 'QUESTION', 'INFO_REQUEST', 'MEETING_INTENT', 'INTRODUCTION', 'NOT_NOW', 'SOFT_NO', 'DECLINED') then
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_CLASS');
  end if;
  select first_name, btrim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')) || coalesce(', ' || position, ''), nullif(linkedin, '')
    into v_first, v_person, v_url from contacts where id = a.contact_id;
  select name into v_co from companies where id = a.company_id;
  v_resp := linkedin_response(v_class, v_first, a.project);
  v_label := initcap(replace(lower(v_class), '_', ' '));
  v_prefix := case v_class when 'POSITIVE' then 'POSITIVE' when 'MEETING_INTENT' then 'MEETING_REQUEST' when 'INFO_REQUEST' then 'NEEDS_INFO' when 'QUESTION' then 'NEEDS_INFO'
                           when 'INTRODUCTION' then 'REFERRAL' else v_class end;
  perform hq_log_touch(p_channel => 'LINKEDIN', p_summary => v_prefix || ': LinkedIn reply from ' || coalesce(v_person, 'contact') || ': ' || left(v_txt, 1500),
                       p_company => a.company_id, p_contact => a.contact_id, p_opportunity => a.opportunity_id,
                       p_outcome => 'LinkedIn reply (' || v_label || ')', p_direction => 'INBOUND');
  update tasks set status = 'CANCELLED', description = coalesce(description, '') || E'\n\nCancelled: they replied on LinkedIn ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon')
   where opportunity_id = a.opportunity_id and a.opportunity_id is not null and task_type = 'OUTREACH_FOLLOW_UP' and status in ('OPEN', 'WAITING');
  insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at, spec)
  values (a.company_id, a.contact_id, a.opportunity_id, 'LINKEDIN REPLY -- ' || coalesce(v_co, 'company') || ' (' || v_label || ')',
          'CONTACT: ' || coalesce(v_person, 'contact') || E'\nTHEIR REPLY: ' || left(v_txt, 1500) || E'\nCLASSIFIED: ' || v_label ||
          E'\nSUGGESTED RESPONSE: ' || coalesce(v_resp, '') || E'\nEXACT ACTION: Reply on LinkedIn ' || coalesce(v_url, ''),
          'REPLY_ACTION', 'Adam', 'LinkedIn Relationship Agent', case when v_class in ('MEETING_INTENT', 'POSITIVE', 'INFO_REQUEST', 'INTRODUCTION') then 95 else 70 end,
          case when v_class = 'DECLINED' then 'COMPLETED' else 'OPEN' end, now(), jsonb_build_object('linkedin_action', a.id, 'class', v_class));
  update opportunities set
         status = case when v_class = 'MEETING_INTENT' and status in ('NEW', 'RESEARCHING', 'READY', 'CONTACTED', 'FOLLOW_UP', 'INTERESTED', 'LONG_TERM') then 'CALL_REQUIRED'
                       when v_class in ('POSITIVE', 'INFO_REQUEST', 'QUESTION', 'INTRODUCTION') and status in ('NEW', 'RESEARCHING', 'READY', 'CONTACTED', 'FOLLOW_UP') then 'INTERESTED'
                       when v_class in ('NOT_NOW', 'SOFT_NO') and status in ('NEW', 'RESEARCHING', 'READY', 'CONTACTED', 'FOLLOW_UP') then 'LONG_TERM'
                       when v_class = 'DECLINED' and status in ('NEW', 'RESEARCHING', 'READY', 'CONTACTED', 'FOLLOW_UP', 'INTERESTED') then 'LOST'
                       else status end,
         next_action = case v_class when 'MEETING_INTENT' then 'They want to talk (LinkedIn): Meeting Assist proposes two times from your calendar.'
                                     when 'INFO_REQUEST' then 'They asked for details (LinkedIn): Studio one-page outline, then send.'
                                     when 'DECLINED' then 'Declined on LinkedIn.' else 'Answer their LinkedIn reply (response suggested in HQ).' end,
         next_action_due = case when v_class = 'DECLINED' then next_action_due else current_date end, updated_at = now()
   where id = a.opportunity_id;
  if v_class = 'MEETING_INTENT' and a.opportunity_id is not null then v_meet := meeting_assist_open(a.opportunity_id, a.contact_id, 'LINKEDIN', a.id); end if;
  update linkedin_actions set state = case when v_class = 'DECLINED' then 'CLOSED' else 'REPLIED' end, replied_at = now(), reply_text = v_txt, reply_class = v_class,
         response_draft = v_resp, meeting_task_id = coalesce(v_meet, meeting_task_id), updated_at = now(),
         next_action = case when v_class = 'MEETING_INTENT' then 'Meeting Assist: two times from your calendar go into the reply. Send it on LinkedIn.'
                            when v_class = 'DECLINED' then null else 'Copy the suggested response, edit, and send it on LinkedIn.' end
   where id = a.id;
  perform hq_audit('LINKEDIN_REPLY', a.opportunity_id, jsonb_build_object('linkedin_action', a.id, 'class', v_class, 'meeting_task', v_meet));
  return jsonb_build_object('ok', true, 'class', v_class, 'response', v_resp, 'meeting_task', v_meet);
end $$;
revoke all on function public.hq_linkedin_reply(uuid, text, text) from public, anon;
grant execute on function public.hq_linkedin_reply(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------- 7. read models: the LinkedIn board, the Top 5, Meeting Assist, Studio ready
create or replace function public.linkedin_board()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id, 'state', a.state, 'connection', a.connection, 'person', btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')),
      'first_name', k.first_name, 'role', k.position, 'linkedin', nullif(k.linkedin, ''), 'company', c.name, 'company_id', a.company_id,
      'opportunity_id', a.opportunity_id, 'task_id', a.task_id, 'director', a.director, 'project', a.project, 'why_them', a.why_them, 'why_now', a.why_now,
      'relationship', relationship_state(a.company_id), 'message', a.message, 'connection_note', a.connection_note, 'followup', a.followup,
      'next_action', a.next_action, 'sent_at', a.sent_at, 'connection_sent_at', a.connection_sent_at, 'connected_at', a.connected_at,
      'replied_at', a.replied_at, 'reply_text', a.reply_text, 'reply_class', a.reply_class, 'response_draft', a.response_draft,
      'meeting_task_id', a.meeting_task_id, 'hold_reason', a.hold_reason, 'created_at', a.created_at,
      'words', array_length(regexp_split_to_array(btrim(coalesce(a.message, '')), '\s+'), 1))
    order by case a.state when 'REPLIED' then 0 when 'CONNECTED' then 1 when 'READY' then 2 when 'CONNECTION_SENT' then 3 when 'SENT' then 4 when 'MEETING' then 5 else 6 end,
             a.updated_at desc), '[]'::jsonb)
    from linkedin_actions a left join contacts k on k.id = a.contact_id left join companies c on c.id = a.company_id
   where a.state <> 'CLOSED' or a.updated_at > now() - interval '14 days'
$$;
revoke all on function public.linkedin_board() from public, anon, authenticated;

-- The five new outreach items worth Adam's attention today, ranked by commercial and project potential, relationship warmth,
-- time sensitivity, decision-maker quality, the strength of the Egypt opportunity and repeat-business potential. Email first;
-- at most two per Director; accounts on hold (Adam's sprint decisions) and quality-flagged drafts are left out.
create or replace function public.outreach_top5(d jsonb)
returns jsonb language sql stable security definer set search_path = public as $$
  with it as (
    select e, e->>'ref' ref, coalesce(e->>'channel', 'EMAIL') ch, e->>'director' dir, nullif(e->>'opportunity_id', '')::uuid opp,
           nullif(e->>'company_id', '')::uuid co, nullif(e->>'contact_id', '')::uuid ct, e->>'role' role, coalesce((e->>'age_days')::int, 0) age,
           nullif(e->>'why_now', '') why, coalesce(e->>'angle', '') angle
      from jsonb_array_elements(coalesce(d->'needs_review', '[]'::jsonb)) e),
  s as (
    select it.*, o.egypt eg, o.mission, coalesce(o.priority, 50) pr, c.partnership_model pm, relationship_state(it.co) rel,
           least(coalesce(role_score(it.role), 0), 5) rs, (select k.identity_status from contacts k where k.id = it.ct) idst
      from it left join opportunities o on o.id = it.opp left join companies c on c.id = it.co
     where coalesce(o.egypt->>'sprint', '') <> 'HOLD' and coalesce(it.e->>'qa', 'PASS') <> 'FLAGGED'),
  sc as (
    select s.*,
      case when s.eg ? 'scores' then (coalesce((s.eg->'scores'->>'project_generation')::numeric, 0) * 4 + coalesce((s.eg->'scores'->>'repeat')::numeric, 0) * 3 + coalesce((s.eg->'scores'->>'network')::numeric, 0) * 3) * 0.6
           else s.pr * 0.2 end potential,
      case when s.rel in ('ACTIVE_CONVERSATION', 'THEY_WROTE_LAST', 'MEETING_BOOKED', 'PROPOSAL', 'CLIENT', 'PARTNER_ACTIVE', 'TWO_WAY', 'RECONNECT', 'FOLLOW_UP') then 15
           when s.rel = 'COLD' then 0 else 4 end warmth,
      (case when s.why is not null then 8 else 0 end) + (case when s.age <= 7 then 4 when s.age > 21 then -4 else 0 end) + (case when s.mission = 'DESTINATION_EGYPT' then 6 else 0 end) timing,
      s.rs * 3 + case when s.idst = 'CONFIRMED' then 3 else 0 end dm,
      case when s.eg ? 'scores' then (coalesce((s.eg->'scores'->>'egypt_relevance')::numeric, 0) + coalesce((s.eg->'scores'->>'destination_evidence')::numeric, 0)) * 2
           when (s.angle || ' ' || coalesce(s.why, '')) ~* '(egypt|cairo|nile|giza|red sea|luxor|aswan|pyramid)' then 8 else 2 end egypt,
      case when s.eg ? 'scores' then coalesce((s.eg->'scores'->>'repeat')::numeric, 0) * 2 when s.pm is not null then 6 else 2 end rep,
      case when s.ch = 'EMAIL' then 5 else 0 end chan
      from s),
  r as (
    select sc.*, round(potential + warmth + timing + dm + egypt + rep + chan) score,
           row_number() over (partition by coalesce(dir, '-') order by potential + warmth + timing + dm + egypt + rep + chan desc) per_dir
      from sc)
  select coalesce(jsonb_agg(jsonb_build_object('ref', ref, 'score', score, 'channel', ch,
           'why', array_to_string(array_remove(array[
             case when mission = 'DESTINATION_EGYPT' then 'Destination Egypt' end,
             case when warmth >= 15 then 'warm relationship' end,
             case when rs >= 4 then 'senior decision maker' when rs >= 3 then 'right person' end,
             case when why is not null then 'clear why-now' end,
             case when ch = 'EMAIL' then 'email route' else 'LinkedIn (email exhausted)' end], null), ' · '))
           order by score desc), '[]'::jsonb)
    from (select * from r where per_dir <= 2 order by score desc limit 5) q
$$;
revoke all on function public.outreach_top5(jsonb) from public, anon, authenticated;

create or replace function public.meeting_assist_board()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('task_id', t.id, 'title', t.title, 'company', c.name, 'company_id', t.company_id, 'opportunity_id', t.opportunity_id,
           'person', btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), 'source', coalesce(t.spec->>'source', 'EMAIL'),
           'state', coalesce(t.spec->>'state', 'NEEDS_SLOTS'), 'slots', t.spec->'slots', 'reply', t.spec->>'reply', 'timezone', t.spec->>'timezone',
           'checked_at', t.spec->>'calendar_checked_at', 'created_at', t.created_at) order by t.created_at desc), '[]'::jsonb)
    from tasks t left join companies c on c.id = t.company_id left join contacts k on k.id = t.contact_id
   where t.task_type = 'MEETING_ACTION' and t.status in ('OPEN', 'IN_PROGRESS')
$$;
revoke all on function public.meeting_assist_board() from public, anon, authenticated;

create or replace function public.studio_ready_board()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'slug', s.slug, 'title', s.title, 'company', c.name, 'company_id', s.company_id, 'status', s.status,
           'level', s.level, 'doc_type', s.doc_type, 'hold_reason', s.hold_reason, 'created_at', s.created_at) order by s.created_at desc), '[]'::jsonb)
    from studio_documents s left join companies c on c.id = s.company_id
   where s.status in ('FOR_REVIEW', 'APPROVED') and s.sent_at is null
$$;
revoke all on function public.studio_ready_board() from public, anon, authenticated;

-- The Outreach desk read carries the morning additions in the same call (no extra read for the browser).
create or replace function public.hq_outreach_desk()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); d jsonb;
begin
  d := outreach_desk();
  return d || jsonb_build_object('top5', outreach_top5(d), 'linkedin', linkedin_board(), 'meeting_assist', meeting_assist_board(), 'studio_ready', studio_ready_board());
end $$;

-- ---------------------------------------------------------------- 8. the agent on the Agents page
-- Scorecard on what actually happened: messages SENT, replies, positive replies, meetings, introductions, briefs, proposals,
-- wins, revenue. Never drafts, profiles found or messages copied.
create or replace function public.linkedin_scorecard()
returns jsonb language sql stable security definer set search_path = public as $$
  with li as (select i.company_id, min(i.occurred_at) filter (where i.direction = 'OUTBOUND') first_out, min(i.occurred_at) filter (where i.direction = 'INBOUND') first_in,
                     count(*) filter (where i.direction = 'OUTBOUND') sent,
                     bool_or(i.direction = 'INBOUND' and coalesce(i.summary, '') ~ '^(POSITIVE|MEETING_REQUEST|NEEDS_INFO|REFERRAL)') positive
                from interactions i where i.channel = 'LINKEDIN' and i.company_id is not null group by i.company_id),
  f as (select f.* from commercial_facts() f join li on li.company_id = f.company_id where li.first_in is not null)
  select jsonb_build_object(
    'sent', (select coalesce(sum(sent), 0) from li), 'sent_30', (select count(*) from interactions where channel = 'LINKEDIN' and direction = 'OUTBOUND' and occurred_at > now() - interval '30 days'),
    'replies', (select count(*) from li where first_in is not null), 'positive', (select count(*) from li where positive),
    'introductions', (select count(*) from linkedin_actions where reply_class = 'INTRODUCTION'),
    'meetings', (select count(*) from f where meeting_at is not null), 'briefs', (select count(*) from f where brief_at is not null),
    'proposals', (select count(*) from f where proposal_at is not null), 'wins', (select count(*) from f where won_at is not null),
    'revenue', coalesce((select jsonb_agg(jsonb_build_object('currency', x.currency, 'amount', x.amount)) from (
        select rv.currency, sum(rv.amount) amount from revenue rv join f on f.company_id = rv.company_id where rv.payment_status <> 'CANCELLED' group by 1) x), '[]'::jsonb),
    'note', 'Counted from what was actually sent and answered on LinkedIn (companies counted once). Drafts, profiles found and copies are not counted.')
$$;
revoke all on function public.linkedin_scorecard() from public, anon, authenticated;

create or replace function public.linkedin_agent_detail()
returns jsonb language sql stable security definer set search_path = public as $$
  with b as (select e from jsonb_array_elements(linkedin_board()) e),
  sec(ord, key, title, st) as (values
    (1, 'replies', 'Replies to answer', array['REPLIED']), (2, 'ready', 'Ready for you to send', array['READY', 'CONNECTED']),
    (3, 'connections', 'Connection requests waiting for acceptance', array['CONNECTION_SENT']), (4, 'sent', 'Sent, waiting for a reply', array['SENT']),
    (5, 'meetings', 'Meetings', array['MEETING']), (6, 'held', 'Held or closed', array['HELD', 'CLOSED']))
  select jsonb_build_object('key', 'LINKEDIN', 'scorecard', linkedin_scorecard(), 'sections',
    (select jsonb_agg(jsonb_build_object('key', sec.key, 'title', sec.title, 'kind', 'linkedin',
              'total', (select count(*) from b where b.e->>'state' = any(sec.st)),
              'items', coalesce((select jsonb_agg(b.e) from b where b.e->>'state' = any(sec.st)), '[]'::jsonb)) order by sec.ord) from sec))
$$;
revoke all on function public.linkedin_agent_detail() from public, anon, authenticated;

-- support_detail() gains the LinkedIn agent; directors_snapshot() gains its "today" numbers (patched in place).
do $patch$
declare src text := pg_get_functiondef('public.support_detail(text)'::regprocedure);
  a text := E'    into v;\n  end if;\n  return v;';
  b text := E'    into v;\n  elsif p_key = ''LINKEDIN'' then\n    v := linkedin_agent_detail();\n  end if;\n  return v;';
begin
  if strpos(src, 'linkedin_agent_detail') > 0 then return; end if;
  if strpos(src, a) = 0 then raise exception 'support_detail() changed: anchor not found'; end if;
  execute replace(src, a, b);
end $patch$;

do $patch$
declare src text := pg_get_functiondef('public.directors_snapshot()'::regprocedure);
  a text := $a$      when 'DIRECTOR' then jsonb_build_object('touches_planned'$a$;
  b text := $a$      when 'LINKEDIN' then jsonb_build_object('messages_sent', (select count(*) from interactions where channel = 'LINKEDIN' and direction = 'OUTBOUND' and occurred_at >= win.since),
                                               'replies', (select count(*) from interactions where channel = 'LINKEDIN' and direction = 'INBOUND' and occurred_at >= win.since),
                                               'meetings', (select count(*) from linkedin_actions where state = 'MEETING' and updated_at >= win.since),
                                               'ready', (select count(*) from linkedin_actions where state in ('READY', 'CONNECTED', 'REPLIED')))
      when 'DIRECTOR' then jsonb_build_object('touches_planned'$a$;
begin
  if strpos(src, $a$when 'LINKEDIN' then jsonb_build_object('messages_sent'$a$) > 0 then return; end if;
  if strpos(src, a) = 0 then raise exception 'directors_snapshot() changed: anchor not found'; end if;
  execute replace(src, a, b);
end $patch$;

-- ---------------------------------------------------------------- 9. keep the queue in step with the desk
select public.linkedin_sync();
select cron.schedule('linkedin-sync', '7,37 * * * *', 'select public.linkedin_sync()');
