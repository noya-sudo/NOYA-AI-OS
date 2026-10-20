-- NOYA HQ — FOLLOW UP / REOPEN (21 Oct 2026)
-- One button on every relationship, opportunity and outreach item. HQ reads the whole relationship first (Gmail, LinkedIn,
-- meetings, notes, outreach, replies, Studio documents, the opportunity, the Director, Destination Egypt and dated Egypt events)
-- and decides whether a follow-up is appropriate at all: FOLLOW UP NOW, REOPEN WITH NEW ANGLE, SEND MATERIAL, ASK FOR MEETING,
-- WAIT UNTIL DATE, HOLD, CLOSE or DO NOT CONTACT. The logic adapts to who it is, suggests a date with its reason, and a reopen must
-- answer "what changed since we last spoke?". Relationship context overrides cadence.
-- Nothing sends: the actions schedule a task, ask the drafter for a message in Adam's voice, hand a concept to the Studio, or
-- hold / close. Adam approves and sends every external message himself.

-- 1. Five recency bands (Adam, 21 Oct). The four-band recency_band() stays for commercial_next_moves.
create or replace function public.follow_up_band(p_at timestamptz) returns text
language sql stable set search_path = public as $$
  select case when p_at is null then null
    when p_at > now() - interval '14 days' then '0-14'
    when p_at > now() - interval '30 days' then '15-30'
    when p_at > now() - interval '90 days' then '31-90'
    when p_at > now() - interval '365 days' then '3-12M'
    else '12M+' end
$$;

create or replace function public.follow_up_workday(p date) returns date
language sql immutable as $$
  select case extract(isodow from p) when 6 then p + 2 when 7 then p + 1 else p end
$$;

-- 2. Who we are dealing with, from the Director that owns the relationship (the Directors' own lane rules).
create or replace function public.follow_up_type(p_director text, p_type text) returns text
language sql immutable as $$
  select case
    when p_director = 'MEDIA' then 'MEDIA'
    when p_director = 'WEDDINGS' then 'WEDDING_PLANNER'
    when p_director = 'SPORTS' then 'NOYA_PRIVATE'
    when p_director = 'PRIVATE' then 'PRIVATE_CLUB'
    when p_director = 'HOSPITALITY' then 'HOSPITALITY'
    when p_director = 'TRAVEL' then case when coalesce(p_type, '') ~* '(member|club|community|founder)' then 'PRIVATE_CLUB' else 'TRAVEL' end
    when p_director = 'BRANDS' then case when coalesce(p_type, '') ~* '(agency|production|\mpr\M|marketing|creative|activation|experiential|studio)' then 'AGENCY' else 'BRAND' end
    else 'CORPORATE' end
$$;

-- What each type is about, its follow-up cadence (days), which Egypt events can be a reason (and how strong a reason), and its planning
-- window (months).
create or replace function public.follow_up_profile(p_type text) returns jsonb
language sql immutable as $$
  select (case p_type
    when 'BRAND' then '{"label":"Brand","event_strength":2,"focus":"A campaign, launch, creator trip, shoot, GCC / MENA expansion, or a seasonal or destination angle.","cadence":7,"events":["EGYPT","FASHION_CULTURE","ENTERTAINMENT","SPORT","SEASONAL"],"season":[10,11,12,1,2,3],"season_note":"Egypt’s cooler months (October to April) are the season for shoots and creator trips.","season_strength":1}'
    when 'AGENCY' then '{"label":"Marketing / creative agency","event_strength":2,"focus":"A specific client or project reason to use NOYA as their Egypt execution partner.","cadence":7,"events":["EGYPT","FASHION_CULTURE","ENTERTAINMENT","SPORT","SEASONAL"],"season":[10,11,12,1,2,3],"season_note":"Egypt’s cooler months (October to April) are the season for client shoots, creator trips and hosted moments.","season_strength":1}'
    when 'WEDDING_PLANNER' then '{"label":"Wedding planner","event_strength":1,"focus":"Destination wedding opportunities, guest concierge, scouting, seasonality and Egypt programmes.","cadence":10,"events":["SEASONAL"],"season":[9,10,11,12,1,2],"season_note":"Egypt’s wedding season runs October to April, and 2027 destinations are being chosen now.","season_strength":2}'
    when 'TRAVEL' then '{"label":"Travel / concierge","event_strength":2,"focus":"Client requests, white-label Egypt execution, agent rates and repeat referrals.","cadence":7,"events":["EGYPT","FASHION_CULTURE","ENTERTAINMENT","SPORT","MOTORSPORT","SEASONAL"],"season":[9,10,11,12,1,2,3],"season_note":"Egypt’s winter season (October to April) is when client demand peaks.","season_strength":2}'
    when 'PRIVATE_CLUB' then '{"label":"Private club / network","event_strength":2,"focus":"Member trips, retreats, private dinners and relevant planning windows.","cadence":10,"events":["EGYPT","FASHION_CULTURE","ENTERTAINMENT","SPORT"],"season":[9,10,11,12,1],"season_note":"2027 member trips and retreats are planned in the autumn.","season_strength":2}'
    when 'MEDIA' then '{"label":"Media / podcast","event_strength":2,"focus":"Production concepts, episodes, cultural moments, events and sponsor opportunities.","cadence":10,"events":["EGYPT","FASHION_CULTURE","ENTERTAINMENT"],"season":[],"season_note":null,"season_strength":0}'
    when 'NOYA_PRIVATE' then '{"label":"NOYA Private / talent","event_strength":1,"focus":"Discreet and relationship-led. No aggressive follow-ups.","cadence":21,"events":["EGYPT","ENTERTAINMENT","SPORT"],"season":[],"season_note":null,"season_strength":0,"discreet":true}'
    when 'HOSPITALITY' then '{"label":"Hospitality / supplier","event_strength":0,"focus":"Client bookings, rates, availability, partnership relevance and actual business.","cadence":10,"events":[],"season":[],"season_note":null,"season_strength":0}'
    else '{"label":"Corporate / other","event_strength":1,"focus":"Retreats, offsites, client events and executive travel in Egypt.","cadence":7,"events":["EGYPT","SPORT","ENTERTAINMENT"],"season":[9,10,11,12],"season_note":"2027 offsites and retreats are budgeted in the autumn.","season_strength":1}'
  end)::jsonb
$$;

-- A calendar entry as a reason: "Forever Is Now 06 (Giza, 4–28 Nov)". Events under ten days away are too close to act on.
create or replace function public.follow_up_event_text(p_title text, p_city text, p_from date, p_to date) returns text
language sql stable as $$
  select case when t ~ '\d{1,2} [A-Z][a-z]+ \d{4}' then t
    else t || ' (' || coalesce(nullif(btrim(split_part(p_city, ',', 1)), '') || ', ', '') || to_char(p_from, 'FMDD Mon')
         || case when p_to is not null and p_to <> p_from then '–' || to_char(p_to, 'FMDD Mon') else '' end || ')' end
  from (select regexp_replace(coalesce(p_title, ''), ':\s[^:]*\d{4}-\d{2}-\d{2}.*$', '') as t) x
$$;

create or replace function public.follow_up_outcome_label(p text) returns text
language sql immutable as $$
  select case p when 'FOLLOW_UP_NOW' then 'Follow up now' when 'REOPEN_NEW_ANGLE' then 'Reopen with a new angle' when 'SEND_MATERIAL' then 'Send material'
    when 'ASK_FOR_MEETING' then 'Ask for a meeting' when 'WAIT_UNTIL_DATE' then 'Wait until the date' when 'HOLD' then 'Hold' when 'CLOSE' then 'Close'
    when 'DO_NOT_CONTACT' then 'Do not contact' else p end
$$;

-- 3. The analysis. Read-only. p_company, or a LinkedIn connection not linked to a company, or a Gmail key (e:<address>, d:<domain>).
create or replace function public.follow_up_assess(p_company uuid, p_connection uuid default null, p_key text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c companies%rowtype; l linkedin_connections%rowtype; op commercial_next_moves%rowtype;
  v_ctx jsonb; v_key text; v_typetext text; v_dir text; v_type text; p jsonb; v_name text; v_person text; v_opp uuid;
  v_in timestamptz; v_out timestamptz; v_last timestamptz; v_them boolean; v_days int; v_band text; v_li_no boolean; v_li_later timestamptz;
  v_inbound int; v_meetings int; v_chasers int := 0; v_dnc boolean; v_state text; v_engaged boolean; v_cad int;
  v_declined text; v_later date; v_later_why text; v_d date; v_rv_status text; v_rv_pos text; v_has_op boolean := false;
  v_task_id uuid; v_task_title text; v_task_due timestamptz; v_task_spec jsonb;
  v_material jsonb; v_concept jsonb; v_changes jsonb; v_best int; v_top jsonb; v_draft jsonb; v_gmail text;
  v_strong text; v_outcome text; v_why text; v_action text; v_date date; v_date_why text; v_channel text; v_stage text;
begin
  -- 1. The whole relationship, one read.
  if p_company is not null then
    select * into c from companies where id = p_company;
    if not found then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
    v_ctx := next_move_context(p_company); v_key := 'co:' || p_company::text; v_name := c.name; v_typetext := c.company_type;
    v_dir := agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes);
    if p_connection is not null then select * into l from linkedin_connections where id = p_connection; end if;
  elsif p_connection is not null then
    select * into l from linkedin_connections where id = p_connection;
    if not found then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
    v_ctx := next_move_li_context(p_connection); v_key := 'li:' || p_connection::text;
    v_name := coalesce(nullif(l.company, ''), concat_ws(' ', l.first_name, l.last_name)); v_typetext := concat_ws(' ', l.position, l.company);
    v_dir := agent_key_of(company_lane(null, null, null, v_typetext), v_typetext, null);
  elsif nullif(btrim(coalesce(p_key, '')), '') is not null then
    v_key := btrim(p_key);
    select jsonb_build_object('last_in', max(g.last_inbound_at), 'last_out', max(g.last_outbound_at), 'inbound', coalesce(sum(g.inbound), 0), 'meetings', 0,
             'sent', coalesce(sum(g.outbound), 0), 'threads', count(*), 'thread', (array_agg(g.gmail_thread_id order by g.last_at desc))[1],
             'subject', (array_agg(left(g.subject, 120) order by g.last_at desc))[1], 'dnc', coalesce(bool_or(g.relationship_state = 'DO_NOT_CONTACT'), false),
             'name', (array_agg(g.counterpart_emails[1] order by g.last_at desc))[1])
      into v_ctx
      from gmail_history_threads g
     where g.relevant and case split_part(v_key, ':', 1)
             when 'e' then substr(v_key, 3) = any(g.counterpart_emails)
             when 'd' then exists (select 1 from unnest(g.counterpart_domains) dm where registrable_domain(dm) = substr(v_key, 3))
             else false end;
    if coalesce((v_ctx->>'threads')::int, 0) = 0 then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
    v_name := coalesce((select m.from_name from gmail_history_messages m where m.gmail_thread_id = v_ctx->>'thread' and m.direction = 'INBOUND' and m.from_name is not null limit 1), v_ctx->>'name');
    v_dir := 'CORPORATE';
  else
    return jsonb_build_object('ok', false, 'reason', 'RECORD_REQUIRED');
  end if;

  -- LinkedIn outreach by the LinkedIn agent counts as conversation; its reply class records "not now" and declines.
  select greatest((v_ctx->>'last_in')::timestamptz, max(a.replied_at)), greatest((v_ctx->>'last_out')::timestamptz, max(a.sent_at)),
         coalesce(bool_or(a.reply_class in ('SOFT_NO', 'DECLINED')), false), max(a.replied_at) filter (where a.reply_class = 'NOT_NOW')
    into v_in, v_out, v_li_no, v_li_later
    from linkedin_actions a where p_company is not null and a.company_id = p_company;
  v_last := greatest(v_in, v_out);
  v_them := v_in is not null and v_in >= coalesce(v_out, '-infinity'::timestamptz);
  v_days := current_date - v_last::date; v_band := follow_up_band(v_last);
  v_inbound := greatest(coalesce((v_ctx->>'inbound')::int, 0), case when v_in is not null then 1 else 0 end);
  v_meetings := coalesce((v_ctx->>'meetings')::int, 0);
  v_engaged := v_inbound > 0 or v_meetings > 0;
  v_dnc := coalesce((v_ctx->>'dnc')::boolean, false) or coalesce(l.li_state = 'DO_NOT_CONTACT' or l.li_opt_out_at is not null, false);
  v_state := v_ctx->>'state';
  v_type := follow_up_type(v_dir, v_typetext); p := follow_up_profile(v_type); v_cad := (p->>'cadence')::int;
  v_opp := (v_ctx #>> '{opportunity,id}')::uuid;
  select nullif(btrim(concat_ws(' ', coalesce(k.first_name, o.contact_first_name), coalesce(k.last_name, o.contact_last_name))), '') into v_person
    from opportunities o left join contacts k on k.id = o.contact_id where o.id = v_opp;
  v_person := coalesce(v_person, nullif(btrim(concat_ws(' ', l.first_name, l.last_name)), ''));

  -- NOYA messages since their last reply (all of them when they never replied).
  if p_company is not null then
    select count(*) into v_chasers from interactions i
     where i.company_id = p_company and i.direction = 'OUTBOUND' and i.channel <> 'WEBSITE' and i.occurred_at > coalesce(v_in, '-infinity'::timestamptz);
    if v_in is null then
      v_chasers := greatest(v_chasers, (select coalesce(sum(g.outbound), 0)::int from gmail_history_threads g where g.company_id = p_company and g.relevant));
    end if;
  elsif v_in is null then v_chasers := coalesce((v_ctx->>'sent')::int, 0);
  end if;

  -- Declined or closed: never chased.
  v_declined := case
    when exists (select 1 from relationship_reviews rv where rv.key = v_key and rv.status = 'NOT_RELEVANT') then 'You marked this relationship not relevant'
    when exists (select 1 from commercial_next_moves m where m.rel_key = v_key and m.status = 'CLOSED'
                   and coalesce(m.decided_at, m.updated_at) > coalesce(v_in, '-infinity'::timestamptz)) then 'This relationship was closed'
    when v_li_no then 'They declined on LinkedIn'
    when v_state = 'DECLINED_RECENTLY' then 'They declined: the opportunity was lost in the last six months'
    when coalesce(c.relationship_status, '') ~* '(not interested|declined)' then 'Recorded as not interested' end;

  -- Asked to reconnect later, or parked by Adam: the latest future date wins.
  select n.follow_up_at::date, 'Your note: ' || left(n.body, 160) into v_later, v_later_why from relationship_notes n
   where ((p_company is not null and n.company_id = p_company) or (p_connection is not null and n.connection_id = p_connection)) and n.follow_up_at::date > current_date + 14
   order by n.follow_up_at desc limit 1;
  if c.outreach_hold_until::date > current_date and (v_later is null or c.outreach_hold_until::date > v_later) then
    v_later := c.outreach_hold_until::date; v_later_why := 'On hold' || coalesce(': ' || c.outreach_hold_reason, ''); end if;
  select m.hold_until into v_d from commercial_next_moves m where m.rel_key = v_key and m.status = 'HELD' and m.hold_until > current_date order by m.hold_until desc limit 1;
  if v_d is not null and (v_later is null or v_d > v_later) then v_later := v_d; v_later_why := 'You parked it until ' || to_char(v_d, 'FMDD Mon'); end if;
  if v_li_later is not null and v_li_later::date + 90 > current_date and (v_later is null or v_li_later::date + 90 > v_later) then
    v_later := v_li_later::date + 90; v_later_why := 'They said not now on LinkedIn (' || to_char(v_li_later, 'FMDD Mon') || ')'; end if;
  select rv.status, rv.their_position into v_rv_status, v_rv_pos from relationship_reviews rv where rv.key = v_key;
  if v_rv_status in ('FOLLOW_UP_LATER', 'LONG_TERM') and v_last is not null and not v_them then
    v_d := v_last::date + case v_rv_status when 'FOLLOW_UP_LATER' then 90 else 180 end;
    if v_d > current_date and (v_later is null or v_d > v_later) then
      v_later := v_d; v_later_why := 'They asked to talk later' || coalesce(': ' || left(v_rv_pos, 160), ''); end if;
  end if;

  -- A follow-up already in the CRM.
  select tk.id, tk.title, tk.due_at, tk.spec into v_task_id, v_task_title, v_task_due, v_task_spec from tasks tk
   where tk.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and tk.task_type in ('NEXT_MOVE_FOLLOW_UP', 'OUTREACH_FOLLOW_UP')
     and ((p_company is not null and tk.company_id = p_company) or (p_company is null and tk.spec->>'rel_key' = v_key))
   order by tk.due_at nulls last limit 1;

  -- Studio: a client document ready to send and not sent (with its cover email draft), and the latest client document.
  if p_company is not null then
    select jsonb_build_object('slug', d.slug, 'version', d.version, 'title', d.title, 'stage', d.stage, 'ready_reason', d.ready_reason, 'file', d.file_name,
             'gmail_draft_id', o.gmail_draft_id, 'thread', o.gmail_thread_id, 'send_after', o.send_after)
      into v_material
      from (select distinct on (slug) * from studio_documents where company_id = p_company order by slug, version desc) d
      left join lateral (select * from studio_outputs so where so.document_slug = d.slug and so.status in ('PREPARED', 'HELD') order by so.prepared_at desc limit 1) o on true
     where d.audience = 'CLIENT' and d.stage <> 'email' and d.ready_class = 'READY_TO_SEND' and d.sent_at is null and d.status in ('FOR_REVIEW', 'APPROVED')
       and not exists (select 1 from studio_outputs s2 where s2.document_slug = d.slug and s2.status = 'SENT')
     order by d.created_at desc limit 1;
    select jsonb_build_object('slug', d.slug, 'version', d.version, 'title', d.title, 'stage', d.stage, 'ready_class', d.ready_class, 'sent_at', d.sent_at)
      into v_concept
      from (select distinct on (slug) * from studio_documents where company_id = p_company order by slug, version desc) d
     where d.audience = 'CLIENT' and d.stage <> 'email' and coalesce(d.ready_class, '') not in ('SUPERSEDED', 'INTERNAL_ONLY')
     order by d.created_at desc limit 1;
  end if;
  v_stage := case v_material->>'stage' when 'master' then 'brief' when 'onepage' then 'one-page concept' else coalesce(v_material->>'stage', 'document') end;

  -- WHAT CHANGED SINCE WE LAST SPOKE? Real reasons only, strongest first (3 = specific to them, 2 = credible, 1 = context).
  select coalesce(jsonb_agg(x order by (x->>'strength')::int desc, x->>'date' nulls last), '[]'::jsonb) into v_changes from (
    select jsonb_build_object('kind', 'MATERIAL', 'strength', 3, 'text', 'Prepared for them and not yet sent: ' || (v_material->>'title') || ' (' || v_stage || ')') x
     where v_material is not null
    union all
    select jsonb_build_object('kind', 'THEIR_REQUEST', 'strength', 3, 'date', n.follow_up_at::date, 'text', 'Due from your note: ' || left(n.body, 160))
      from relationship_notes n
     where ((p_company is not null and n.company_id = p_company) or (p_connection is not null and n.connection_id = p_connection))
       and n.follow_up_at::date between coalesce(v_last::date, current_date - 365) and current_date + 14
    union all
    (select jsonb_build_object('kind', 'THEIR_NEWS', 'strength', 3, 'date', coalesce(i.event_date, i.created_at::date), 'source', i.source_url,
              'text', i.title || coalesce(' (' || to_char(i.event_date, 'FMDD Mon') || ')', ''))
       from intelligence i
      where p_company is not null and i.company_id = p_company and i.dismissed_reason is null and i.created_at > coalesce(v_last, '-infinity'::timestamptz)
        and (i.event_date is null or i.event_date >= current_date)
      order by i.created_at desc limit 2)
    union all
    (select jsonb_build_object('kind', 'PROJECT', 'strength', case when o.created_at > coalesce(v_last, '-infinity'::timestamptz) then 2 else 1 end,
              'text', 'Destination Egypt project on file: ' || lower(replace(replace(coalesce(o.egypt->>'project_type', 'EGYPT_PROJECT'), '_EGYPT', ''), '_', ' ')))
       from opportunities o
      where p_company is not null and o.company_id = p_company and o.mission = 'DESTINATION_EGYPT' and o.status not in ('LOST', 'ARCHIVED', 'WON')
      order by o.updated_at desc limit 1)
    union all
    (select jsonb_build_object('kind', 'EVENT', 'strength', coalesce((p->>'event_strength')::int, 1), 'date', i.event_date, 'source', i.source_url,
              'text', follow_up_event_text(i.title, i.city, i.event_date, i.event_end))
       from intelligence i
      where i.egypt_relevance >= 90 and i.calendar_status in ('VERIFIED', 'APPROVED') and i.event_date between current_date + 10 and current_date + 120
        and coalesce(i.calendar_category, '') in (select jsonb_array_elements_text(p->'events')) and (p_company is null or i.company_id is distinct from p_company)
      order by i.event_date limit 2)
    union all
    select jsonb_build_object('kind', 'SEASON', 'strength', (p->>'season_strength')::int, 'text', p->>'season_note')
     where (p->>'season_strength')::int > 0 and (p->'season') @> to_jsonb(extract(month from current_date)::int)
  ) s;
  v_best := coalesce((select max((x->>'strength')::int) from jsonb_array_elements(v_changes) x), 0);
  v_top := (select x from jsonb_array_elements(v_changes) x where x->>'kind' <> 'MATERIAL' order by (x->>'strength')::int desc, x->>'date' nulls last limit 1);

  -- Only a credible reason (2+) goes into a suggested message; context alone never does.
  v_strong := case when (v_top->>'strength')::int >= 2 then v_top->>'text' end;

  -- The operator's written recommendation, when it is newer than their last message.
  select * into op from commercial_next_moves m
   where m.rel_key = v_key and m.status in ('PROPOSED', 'CHOSEN') and m.created_by not like 'HQ%' order by m.updated_at desc limit 1;
  v_has_op := found and op.updated_at > coalesce(v_in, '-infinity'::timestamptz);

  -- 4. Decide. Context first, then cadence.
  v_date := current_date;
  if v_dnc then
    v_outcome := 'DO_NOT_CONTACT'; v_why := 'Marked do-not-contact. It is never revived.'; v_action := 'Nothing.'; v_date := null;
  elsif v_declined is not null and not v_them then
    v_outcome := 'CLOSE'; v_why := v_declined || '. No bad relationship gets chased.'; v_action := 'Close it. It comes back only if they write again.'; v_date := null;
  elsif v_last is null then
    v_outcome := 'HOLD'; v_why := 'No conversation yet: first contact belongs to the Director’s outreach queue, not a follow-up.';
    v_action := 'Leave it with the Outreach desk.'; v_date := null;
  elsif v_them and (v_days <= 30 or (v_days <= 90 and v_inbound >= 2)) then
    -- A reply owed: they wrote last recently, or within 90 days in a real conversation. An older or one-off answer (often a supplier
    -- replying to a NOYA enquiry) follows the recency rules below.
    v_outcome := 'FOLLOW_UP_NOW';
    v_why := 'They wrote last, ' || case when v_days = 0 then 'today' when v_days = 1 then 'yesterday' else v_days || ' days ago' end || ': NOYA owes the reply.';
    v_action := 'Reply in their thread' || case when v_material is not null then ', with “' || (v_material->>'title') || '”' else '' end || '.';
    v_date_why := 'A reply owed waits for nothing';
  elsif v_later is not null then
    v_outcome := 'WAIT_UNTIL_DATE'; v_why := v_later_why || '.'; v_action := 'Prepare the message now; it comes back to you on the date.';
    v_date := v_later; v_date_why := v_later_why;
  elsif v_has_op then
    v_outcome := case op.action when 'DRAFT_REPLY' then 'FOLLOW_UP_NOW' when 'ASK_FOR_CALL' then 'ASK_FOR_MEETING' when 'SCHEDULE_FOLLOWUP' then 'WAIT_UNTIL_DATE'
      when 'RECONNECT' then 'REOPEN_NEW_ANGLE' when 'HOLD' then 'HOLD' when 'CLOSE' then 'CLOSE' else 'SEND_MATERIAL' end;
    v_why := coalesce(op.why_now, op.situation); v_action := coalesce(op.action_label, initcap(replace(lower(op.action), '_', ' ')));
    v_date := case when v_outcome = 'WAIT_UNTIL_DATE' then coalesce(v_task_due::date, (v_material->>'send_after')::date, v_last::date + v_cad)
                   when v_outcome in ('HOLD', 'CLOSE') then op.hold_until
                   else greatest(current_date, coalesce((v_material->>'send_after')::date, current_date)) end;
    v_date_why := case when v_outcome = 'WAIT_UNTIL_DATE' and v_task_due is not null then 'Already in the CRM: ' || v_task_title
                       when v_outcome = 'SEND_MATERIAL' then 'The operator’s recommendation, written ' || to_char(op.updated_at, 'FMDD Mon') end;
  elsif v_material is not null then
    v_outcome := 'SEND_MATERIAL';
    v_why := 'A tailored ' || v_stage || ' is ready for them and has not been sent: send it rather than another follow-up.';
    v_action := 'Approve and send “' || (v_material->>'title') || '” with its cover email.';
    v_date := greatest(current_date, coalesce((v_material->>'send_after')::date, current_date));
    v_date_why := case when (v_material->>'send_after')::date > current_date then 'The planned send date' else 'Ready now' end;
  elsif v_task_due::date > current_date then
    v_outcome := 'WAIT_UNTIL_DATE'; v_why := 'Already scheduled: ' || v_task_title || '.'; v_action := 'Nothing until then. The message can be prepared now.';
    v_date := v_task_due::date; v_date_why := 'The follow-up already in the CRM';
  elsif v_meetings > 0 and v_concept is null and (v_ctx->>'last_meeting')::timestamptz > now() - interval '30 days' then
    v_outcome := 'SEND_MATERIAL'; v_why := 'You met them on ' || to_char((v_ctx->>'last_meeting')::timestamptz, 'FMDD Mon') || ' and nothing tailored has gone back yet.';
    v_action := 'Build the brief (Build concept), then send it with a short note.'; v_date_why := 'While the meeting is fresh';
  elsif coalesce((p->>'discreet')::boolean, false) and not v_engaged then
    v_outcome := 'HOLD'; v_why := 'NOYA Private: discreet and relationship-led. One message is enough until they respond.';
    v_action := 'Wait for them, or for a warm introduction.'; v_date := current_date + 30; v_date_why := 'Review date';
  elsif v_chasers >= 2 and not v_engaged then
    v_outcome := 'HOLD'; v_why := v_chasers || ' messages from NOYA without a reply: stop chasing.';
    v_action := 'Reopen later only with a new reason.'; v_date := current_date + 90; v_date_why := 'Review date';
  elsif v_band = '0-14' and v_days < v_cad then
    v_outcome := 'WAIT_UNTIL_DATE'; v_why := 'NOYA wrote ' || case when v_days = 0 then 'today' when v_days = 1 then 'yesterday' else v_days || ' days ago' end || ': too soon to follow up.';
    v_action := 'One short follow-up in the same thread on the date' || coalesce(', adding: ' || v_strong, '') || '.';
    v_date := v_last::date + v_cad; v_date_why := v_cad || ' days after NOYA’s last message (' || lower(p->>'label') || ' cadence)';
  elsif v_band = '0-14' then
    v_outcome := 'FOLLOW_UP_NOW'; v_why := 'NOYA wrote ' || v_days || ' days ago with no reply yet: a normal follow-up.';
    v_action := 'One short follow-up in the same thread' || coalesce(', adding one useful line: ' || v_strong, '') || '.';
  elsif v_band = '15-30' then
    if v_engaged and v_meetings = 0 then
      v_outcome := 'ASK_FOR_MEETING'; v_why := 'They have engaged before; a call moves it forward more than another email.';
      v_action := 'Ask for twenty minutes around one concrete idea' || coalesce(': ' || v_strong, '') || '.';
    elsif v_engaged then
      v_outcome := 'FOLLOW_UP_NOW'; v_why := 'You have met: pick up from the meeting with the next concrete step.';
      v_action := 'A short note with the next step' || coalesce(' and one new reason: ' || v_strong, '') || '.';
    elsif v_best >= 1 then
      v_outcome := 'FOLLOW_UP_NOW'; v_why := 'A contextual follow-up: ' || (v_top->>'text');
      v_action := 'One short message built on that reason, never a bare follow-up.';
    else
      v_outcome := 'HOLD'; v_why := 'No reply and nothing new to say: a second message now would be a generic chaser.';
      v_action := 'Wait for a reason.'; v_date := current_date + 30; v_date_why := 'Review date';
    end if;
  elsif v_band in ('31-90', '3-12M') then
    if v_best >= 2 then
      v_outcome := 'REOPEN_NEW_ANGLE';
      v_why := case when v_band = '31-90' then 'A useful reason to reopen: ' else 'A credible new angle: ' end || (v_top->>'text');
      v_action := 'A short reopen built on what changed' || case when v_concept is not null then ', with the concept as an option' else '' end || '.';
    else
      v_outcome := 'HOLD';
      v_why := case when v_band = '31-90' then 'Nothing useful has changed since you last spoke: reopening now would be a generic follow-up.'
                    else 'No credible new angle, event, project or change since you last spoke.' end;
      v_action := 'Wait for a reason.'; v_date := current_date + case when v_band = '31-90' then 30 else 60 end; v_date_why := 'Review date';
    end if;
  else
    if v_inbound >= 2 or v_meetings > 0 then
      v_outcome := 'REOPEN_NEW_ANGLE';
      v_why := 'Dormant since ' || to_char(v_last, 'FMMon YYYY') || ': a personal reconnect, never a sales follow-up.' || coalesce(' Reason to write now: ' || v_strong, '');
      v_action := 'A personal note from Adam.';
    else
      v_outcome := 'HOLD'; v_why := 'Over a year, and never a two-way conversation: not a relationship to chase.'; v_action := 'Leave it.'; v_date := null;
    end if;
  end if;
  if v_them and v_outcome not in ('FOLLOW_UP_NOW', 'DO_NOT_CONTACT') then
    v_why := 'They wrote last (' || to_char(v_in, 'FMDD Mon YYYY') || ') and NOYA did not reply. ' || v_why; end if;
  -- NOYA Private: never an aggressive ask.
  if coalesce((p->>'discreet')::boolean, false) and v_outcome = 'ASK_FOR_MEETING' then
    v_outcome := 'FOLLOW_UP_NOW'; v_action := 'A personal, low-key note. No ask.'; end if;
  if v_date is not null then v_date := follow_up_workday(greatest(v_date, current_date)); end if;
  v_date_why := coalesce(v_date_why, case when v_date is null then null when v_date = current_date then 'Today' else 'Review date' end);

  -- How Adam would send it.
  v_channel := case when v_has_op and op.channel in ('EMAIL', 'LINKEDIN') then op.channel
    when p_company is null and p_connection is not null then 'LINKEDIN'
    when p_company is null then 'EMAIL'
    when v_ctx->>'thread' is not null or exists (select 1 from contacts k where k.company_id = p_company and k.email is not null) then 'EMAIL'
    when coalesce((v_ctx #>> '{linkedin,people}')::int, 0) > 0 then 'LINKEDIN' else 'EMAIL' end;

  -- What is already prepared.
  select jsonb_build_object('id', md.id, 'status', md.status, 'channel', md.channel, 'type', md.message_type, 'text', md.draft, 'requested_at', md.requested_at)
    into v_draft from message_drafts md
   where md.status in ('REQUESTED', 'DRAFTING', 'READY')
     and ((p_company is not null and md.company_id = p_company) or (p_connection is not null and md.connection_id = p_connection))
   order by md.requested_at desc limit 1;
  v_gmail := coalesce(v_material->>'gmail_draft_id', case when v_has_op then op.gmail_draft_id end, v_task_spec->>'gmail_draft_id');

  return jsonb_build_object('ok', true, 'key', v_key, 'company_id', p_company, 'connection_id', p_connection, 'opportunity_id', v_opp,
    'name', v_name, 'person', v_person, 'type', v_type, 'type_label', p->>'label', 'focus', p->>'focus',
    'director', v_dir, 'director_name', (select r.name from agent_registry r where r.key = v_dir),
    'outcome', v_outcome, 'outcome_label', follow_up_outcome_label(v_outcome), 'why', v_why, 'action', v_action,
    'date', v_date, 'date_reason', v_date_why, 'channel', v_channel, 'source', case when v_has_op then 'OPERATOR' else 'RULES' end,
    'angle', v_top, 'changes', v_changes,
    'facts', jsonb_build_object('last_at', v_last, 'last_in', v_in, 'last_out', v_out,
      'last_by', case when v_last is null then null when v_them then 'THEM' else 'NOYA' end, 'days', v_days, 'band', v_band,
      'band_rule', case v_band when '0-14' then 'Under 14 days: a normal follow-up where appropriate.' when '15-30' then '15–30 days: a contextual follow-up.'
        when '31-90' then '31–90 days: reopen only with a useful reason.' when '3-12M' then '3–12 months: only with a credible new angle, event, project or change.'
        when '12M+' then 'Over a year: dormant; a personal reconnect, never a sales follow-up.' end,
      'replies', v_inbound, 'meetings', v_meetings, 'last_meeting', v_ctx->>'last_meeting', 'unanswered', v_chasers, 'threads', v_ctx->'threads',
      'subject', v_ctx->>'subject', 'thread', v_ctx->>'thread', 'state', v_state, 'declined', v_declined, 'asked_later', v_later, 'linkedin', v_ctx->'linkedin',
      'opportunity', v_ctx->'opportunity'),
    'task', case when v_task_id is not null then jsonb_build_object('id', v_task_id, 'title', v_task_title, 'due', v_task_due) end,
    'prepared', jsonb_build_object(
      'message', case when v_gmail is not null or (v_has_op and op.recommended_message is not null) or v_draft->>'status' = 'READY' then 'READY'
                      when v_draft is not null then 'DRAFTING' else 'NONE' end,
      'gmail_draft_id', v_gmail, 'thread', coalesce(v_material->>'thread', case when v_has_op then op.gmail_thread_id end, v_ctx->>'thread'),
      'subject', case when v_has_op then op.message_subject end,
      'text', coalesce(case when v_has_op then op.recommended_message end, v_draft->>'text'), 'draft', v_draft,
      'material', v_material, 'concept', v_concept, 'concept_optional', v_outcome <> 'SEND_MATERIAL'));
end $$;
revoke execute on function public.follow_up_assess(uuid, uuid, text) from public, anon, authenticated;

-- 4. The button (read). Any record resolves to the relationship it belongs to.
create or replace function public.hq_follow_up(p_company uuid default null, p_opportunity uuid default null, p_contact uuid default null,
  p_connection uuid default null, p_key text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_company uuid := p_company; v_key text := nullif(btrim(coalesce(p_key, '')), '');
begin
  if v_company is null and p_opportunity is not null then select company_id into v_company from opportunities where id = p_opportunity; end if;
  if v_company is null and p_contact is not null then select company_id into v_company from contacts where id = p_contact; end if;
  if v_company is null and p_connection is not null then select matched_company_id into v_company from linkedin_connections where id = p_connection; end if;
  if v_company is null and v_key ~ '^co:[0-9a-f-]{36}$' then v_company := substr(v_key, 4)::uuid; end if;
  if v_company is null and v_key ~ '^ct:[0-9a-f-]{36}$' then select company_id into v_company from contacts where id = substr(v_key, 4)::uuid; end if;
  if v_company is null and v_key ~ '^li:[0-9a-f-]{36}$' then return hq_follow_up(p_connection => substr(v_key, 4)::uuid); end if;
  return follow_up_assess(v_company, p_connection, case when v_company is null and p_connection is null then v_key end);
end $$;
grant execute on function public.hq_follow_up(uuid, uuid, uuid, uuid, text) to authenticated;

-- hq_request_draft reused an open draft for another company when only the company was given: compare the company too.
do $$
declare v text := pg_get_functiondef('public.hq_request_draft(text,text,text,uuid,uuid,uuid,uuid,text)'::regprocedure);
begin
  if position('company_id = p_company' in v) = 0 then
    v := replace(v, 'and opportunity_id is not distinct from p_opportunity limit 1;',
                    'and opportunity_id is not distinct from p_opportunity and (p_company is null or company_id = p_company) limit 1;');
    execute v;
  end if;
end $$;

-- 5. Adam's choice. Schedule + Draft · Draft only · Change date · Hold · Close · Build concept · Ask for meeting. Never sends.
create or replace function public.hq_follow_up_action(p_action text, p_company uuid default null, p_opportunity uuid default null, p_contact uuid default null,
  p_connection uuid default null, p_key text default null, p_date date default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_action text := upper(btrim(coalesce(p_action, ''))); a jsonb; v_company uuid; v_opp uuid; v_contact uuid := p_contact;
  v_key text; v_brief text; v_date date; v_task uuid; v_due timestamptz; r jsonb := '{}'::jsonb; d jsonb; v_name text; v_li boolean;
begin
  if v_action not in ('SCHEDULE_AND_DRAFT', 'DRAFT_ONLY', 'CHANGE_DATE', 'HOLD', 'CLOSE', 'BUILD_CONCEPT', 'ASK_FOR_MEETING') then
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION'); end if;
  a := hq_follow_up(p_company, p_opportunity, p_contact, p_connection, p_key);
  if (a->>'ok')::boolean is not true then return a; end if;
  v_company := (a->>'company_id')::uuid; v_opp := coalesce(p_opportunity, (a->>'opportunity_id')::uuid); v_key := a->>'key';
  v_name := coalesce(a->>'name', a->>'person', 'relationship'); v_li := v_company is null and p_connection is not null;
  if a->>'outcome' = 'DO_NOT_CONTACT' and v_action not in ('HOLD', 'CLOSE') then return jsonb_build_object('ok', false, 'reason', 'DO_NOT_CONTACT'); end if;
  if v_company is null and p_connection is null and v_action in ('DRAFT_ONLY', 'BUILD_CONCEPT', 'ASK_FOR_MEETING') then
    return jsonb_build_object('ok', false, 'reason', 'ADD_TO_CRM_FIRST'); end if;
  if v_action = 'CHANGE_DATE' and p_date is null then return jsonb_build_object('ok', false, 'reason', 'DATE_REQUIRED'); end if;
  if v_contact is null and v_opp is not null then select contact_id into v_contact from opportunities where id = v_opp; end if;
  -- The drafter's brief: the analysis, so the message opens with what changed.
  v_brief := left(concat_ws(E'\n',
    'FOLLOW UP / REOPEN: ' || (a->>'outcome_label') || '.',
    'Why: ' || (a->>'why'),
    'Suggested action: ' || (a->>'action'),
    'What changed since we last spoke: ' || coalesce(case when (a #>> '{angle,strength}')::int >= 2 then a #>> '{angle,text}' end, 'nothing specific; keep it personal and short'),
    'Who: ' || (a->>'type_label') || '. ' || (a->>'focus'),
    case when a->>'type' = 'NOYA_PRIVATE' then 'Discreet and relationship-led: no ask, no pressure.' end,
    case when v_action = 'ASK_FOR_MEETING' then 'Ask for a twenty-minute call around one concrete idea.' end,
    'Never write “just following up”: open with what changed. Adam sends it himself.',
    'Adam’s note: ' || hq_trim(p_note)), 1500);

  -- The message, prepared now (unless one is already ready in Gmail or HQ).
  if v_action = 'DRAFT_ONLY' or (v_action = 'SCHEDULE_AND_DRAFT' and coalesce(a #>> '{prepared,message}', 'NONE') <> 'READY') then
    if v_company is null and p_connection is null then
      d := jsonb_build_object('skipped', 'ADD_TO_CRM_FIRST');
    else
      d := hq_request_draft(p_channel => case when v_li then 'LINKEDIN' else coalesce(a->>'channel', 'EMAIL') end, p_voice => 'ADAM_PERSONAL',
             p_type => case when a->>'outcome' = 'REOPEN_NEW_ANGLE' or a #>> '{facts,band}' in ('3-12M', '12M+') then 'RECONNECTION' else 'FOLLOW_UP' end,
             p_connection => p_connection, p_contact => v_contact, p_company => v_company, p_opportunity => v_opp, p_note => v_brief);
      if (d->>'ok')::boolean is not true then return d; end if;
    end if;
  elsif v_action = 'SCHEDULE_AND_DRAFT' then
    d := jsonb_build_object('prepared', true, 'gmail_draft_id', a #>> '{prepared,gmail_draft_id}', 'thread', a #>> '{prepared,thread}');
  end if;

  if v_action in ('SCHEDULE_AND_DRAFT', 'CHANGE_DATE') then
    v_date := follow_up_workday(greatest(coalesce(p_date, (a->>'date')::date, current_date + 7), current_date));
    v_due := (v_date::timestamp + interval '9 hours') at time zone 'Europe/London';
    v_task := (a #>> '{task,id}')::uuid;
    if v_task is not null then
      update tasks set due_at = v_due, updated_at = now(),
             spec = coalesce(spec, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('source', 'FOLLOW_UP_REOPEN', 'director', a->>'director', 'outcome', a->>'outcome',
               'reason', a->>'why', 'draft_id', d->>'id'))
       where id = v_task;
    else
      insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at, spec)
      values (v_company, v_contact, v_opp, 'FOLLOW UP -- ' || v_name, v_brief, 'NEXT_MOVE_FOLLOW_UP', 'Adam', 'HQ follow up / reopen',
              case when a #>> '{facts,last_by}' = 'THEM' then 85 else 70 end, 'OPEN', v_due,
              jsonb_strip_nulls(jsonb_build_object('source', 'FOLLOW_UP_REOPEN', 'director', a->>'director', 'rel_key', v_key, 'connection_id', p_connection,
                'outcome', a->>'outcome', 'reason', a->>'why', 'action', a->>'action', 'channel', a->>'channel',
                'angle', case when (a #>> '{angle,strength}')::int >= 2 then a #>> '{angle,text}' end,
                'draft_id', d->>'id', 'gmail_draft_id', d->>'gmail_draft_id')))
      returning id into v_task;
    end if;
    r := jsonb_build_object('task_id', v_task, 'due', v_due, 'date', v_date, 'moved', (a #>> '{task,id}') is not null);
    -- Recorded on the relationship, so it leaves the reopen list while the follow-up is scheduled.
    update commercial_next_moves set status = 'CHOSEN', chosen_action = 'SCHEDULE_FOLLOWUP', decided_at = now(), decided_by = v_admin,
           outcome = coalesce(hq_trim(p_note), outcome), updated_at = now()
     where rel_key = v_key and status in ('PROPOSED', 'CHOSEN');
    if not found then
      insert into commercial_next_moves (rel_key, kind, company_id, opportunity_id, connection_id, situation, action, last_contact_at, last_by, recency_band,
                                         status, chosen_action, decided_at, decided_by, created_by)
      values (v_key, case when a->>'outcome' = 'REOPEN_NEW_ANGLE' then 'REOPEN' else 'LIVE' end, v_company, v_opp, p_connection, coalesce(a->>'why', 'Follow-up scheduled'),
              'SCHEDULE_FOLLOWUP', (a #>> '{facts,last_at}')::timestamptz, a #>> '{facts,last_by}', recency_band((a #>> '{facts,last_at}')::timestamptz),
              'CHOSEN', 'SCHEDULE_FOLLOWUP', now(), v_admin, 'HQ follow up / reopen (rule-based)');
    end if;
  elsif v_action = 'HOLD' then
    v_date := coalesce(p_date, case when a->>'outcome' in ('HOLD', 'WAIT_UNTIL_DATE') then (a->>'date')::date end, current_date + 30);
    r := hq_next_move_action(p_action => 'HOLD', p_company => v_company, p_opportunity => v_opp, p_connection => p_connection,
           p_note => coalesce(hq_trim(p_note), 'Held from FOLLOW UP / REOPEN'), p_until => v_date, p_key => case when v_company is null and p_connection is null then v_key end);
    if (r->>'ok')::boolean is not true then return r; end if;
    update tasks set due_at = greatest(due_at, (v_date::timestamp + interval '9 hours') at time zone 'Europe/London'), updated_at = now()
     where status in ('OPEN', 'IN_PROGRESS', 'WAITING') and task_type in ('NEXT_MOVE_FOLLOW_UP', 'OUTREACH_FOLLOW_UP')
       and ((v_company is not null and company_id = v_company) or spec->>'rel_key' = v_key);
    r := r || jsonb_build_object('until', v_date);
  elsif v_action = 'CLOSE' then
    r := hq_next_move_action(p_action => 'CLOSE', p_company => v_company, p_opportunity => v_opp, p_connection => p_connection,
           p_note => coalesce(hq_trim(p_note), 'Closed from FOLLOW UP / REOPEN'), p_key => case when v_company is null and p_connection is null then v_key end);
    if (r->>'ok')::boolean is not true then return r; end if;
    update tasks set status = 'CANCELLED', updated_at = now(),
           description = coalesce(description, '') || E'\n\nCancelled ' || to_char(current_date, 'FMDD Mon') || ': relationship closed (FOLLOW UP / REOPEN).'
     where status in ('OPEN', 'IN_PROGRESS', 'WAITING') and task_type in ('NEXT_MOVE_FOLLOW_UP', 'OUTREACH_FOLLOW_UP')
       and ((v_company is not null and company_id = v_company) or spec->>'rel_key' = v_key);
  elsif v_action = 'BUILD_CONCEPT' then
    r := hq_next_move_action(p_action => 'BUILD_CONCEPT', p_company => v_company, p_opportunity => v_opp, p_connection => p_connection, p_note => v_brief);
    if (r->>'ok')::boolean is not true then return r; end if;
  elsif v_action = 'ASK_FOR_MEETING' then
    r := hq_next_move_action(p_action => 'ASK_FOR_CALL', p_company => v_company, p_opportunity => v_opp, p_connection => p_connection, p_note => v_brief);
    if (r->>'ok')::boolean is not true then return r; end if;
  end if;
  perform hq_audit('FOLLOW_UP_REOPEN', v_opp, jsonb_build_object('action', v_action, 'key', v_key, 'outcome', a->>'outcome', 'result', r, 'draft', d));
  return jsonb_build_object('ok', true, 'action', v_action, 'outcome', a->>'outcome', 'director', a->>'director', 'director_name', a->>'director_name',
    'result', r, 'draft', d);
end $$;
grant execute on function public.hq_follow_up_action(text, uuid, uuid, uuid, uuid, text, date, text) to authenticated;

-- 6. The morning: only commercially justified actions, never every stale relationship.
--    FOLLOW-UPS DUE · REPLIES OWED · PAST RELATIONSHIPS WORTH REOPENING · MEETINGS TO SCHEDULE. Each item carries the same analysis.
create or replace function public.hq_follow_up_board(p_limit int default 5)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); n int := least(greatest(coalesce(p_limit, 5), 1), 10);
  v_due jsonb; v_owed jsonb; v_reopen jsonb; v_meet jsonb; v_cold int;
begin
  -- Follow-ups due (today or overdue), re-checked: a reply since, a decline or a hold changes the answer.
  select coalesce(jsonb_agg(x order by (x->>'due')), '[]'::jsonb) into v_due from (
    select follow_up_assess(t.company_id, (t.spec->>'connection_id')::uuid, case when t.company_id is null then t.spec->>'rel_key' end)
             || jsonb_build_object('task_id', t.id, 'task_title', t.title, 'due', t.due_at) x
      from tasks t
     where t.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and (t.task_type = 'NEXT_MOVE_FOLLOW_UP' or t.spec->>'source' = 'FOLLOW_UP_REOPEN')
       and t.due_at < (current_date + 1)::timestamp at time zone 'Europe/London'
       and (t.company_id is not null or t.spec->>'rel_key' is not null)
     order by t.due_at limit n) s where (x->>'ok')::boolean;
  select count(*) into v_cold from tasks t
   where t.status = 'OPEN' and t.task_type = 'OUTREACH_FOLLOW_UP' and t.due_at < (current_date + 1)::timestamp at time zone 'Europe/London'
     and t.due_at > now() - interval '14 days';

  -- Replies owed: they wrote last within 90 days in a two-way conversation, or a reply task is open.
  select coalesce(jsonb_agg(x order by x #>> '{facts,last_in}' desc), '[]'::jsonb) into v_owed from (
    select follow_up_assess(k.company_id, null, case when k.company_id is null then k.gkey end) x
      from (select distinct on (coalesce(g.company_id::text, g.gkey)) g.company_id, g.gkey, g.last_inbound_at
              from (select t.*, coalesce('co:' || t.company_id::text,
                      case when cardinality(t.counterpart_domains) > 0 and not email_is_freemail(t.counterpart_domains[1]) then 'd:' || registrable_domain(t.counterpart_domains[1]) end,
                      'e:' || t.counterpart_emails[1]) as gkey
                      from gmail_history_threads t
                     where t.relevant and t.outbound > 0 and t.last_inbound_at > now() - interval '90 days'
                       and t.last_inbound_at >= coalesce(t.last_outbound_at, '-infinity'::timestamptz)) g
             order by coalesce(g.company_id::text, g.gkey), g.last_inbound_at desc) k
     order by k.last_inbound_at desc limit 25) s
   where (x->>'ok')::boolean and x->>'outcome' = 'FOLLOW_UP_NOW' and x #>> '{facts,last_by}' = 'THEM';
  v_owed := (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(v_owed) e limit n) z);

  -- Past relationships worth reopening: two-way, older than three weeks, with a real reason. Strongest reason first.
  select coalesce(jsonb_agg(x order by (x #>> '{angle,strength}')::int desc nulls last, x #>> '{facts,last_at}' desc), '[]'::jsonb) into v_reopen from (
    select follow_up_assess(k.company_id, null, case when k.company_id is null then k.gkey end) x
      from (select coalesce(g.company_id::text, g.gkey) as k2, (array_agg(g.company_id))[1] as company_id, (array_agg(g.gkey))[1] as gkey,
                   sum(g.inbound) as received, max(g.last_at) as last_at
              from (select t.*, coalesce('co:' || t.company_id::text,
                      case when cardinality(t.counterpart_domains) > 0 and not email_is_freemail(t.counterpart_domains[1]) then 'd:' || registrable_domain(t.counterpart_domains[1]) end,
                      'e:' || t.counterpart_emails[1]) as gkey
                      from gmail_history_threads t where t.relevant and t.outbound > 0 and t.inbound > 0) g
             group by 1 having max(g.last_at) < now() - interval '21 days') k
     where not exists (select 1 from commercial_next_moves m where m.rel_key in (k.gkey, 'co:' || k.company_id::text)
                         and (m.status in ('CHOSEN', 'CLOSED') or (m.status = 'HELD' and coalesce(m.hold_until, current_date) >= current_date)))
       and not exists (select 1 from relationship_reviews rv where rv.key = k.gkey and rv.status in ('NOT_RELEVANT', 'EXISTING_PARTNER', 'CLIENT'))
     order by k.received desc, k.last_at desc limit 40) s
   where (x->>'ok')::boolean and x->>'outcome' in ('REOPEN_NEW_ANGLE', 'SEND_MATERIAL', 'ASK_FOR_MEETING')
     and (x->>'outcome' <> 'REOPEN_NEW_ANGLE' or (x #>> '{angle,strength}')::int >= 2 or x #>> '{facts,band}' = '12M+');
  v_reopen := (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(v_reopen) e limit n) z);

  -- Meetings to schedule: meeting requests waiting for a time, and LinkedIn replies asking to meet.
  select coalesce(jsonb_agg(x order by x->>'since'), '[]'::jsonb) into v_meet from (
    select jsonb_build_object('task_id', t.id, 'company_id', t.company_id, 'name', co.name, 'title', t.title, 'since', t.created_at, 'state', t.spec->>'state',
             'detail', coalesce(t.spec->>'reply', left(t.description, 200))) x
      from tasks t left join companies co on co.id = t.company_id
     where t.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and (t.task_type = 'MEETING_ACTION' or t.title like 'MEETING --%')
    union all
    select jsonb_build_object('task_id', a.meeting_task_id, 'company_id', a.company_id, 'name', co.name, 'title', 'LinkedIn: asked to meet', 'since', a.replied_at,
             'state', 'REPLIED', 'detail', left(a.reply_text, 200))
      from linkedin_actions a left join companies co on co.id = a.company_id
     where a.reply_class = 'MEETING_INTENT' and a.state = 'REPLIED' and a.meeting_task_id is null
    limit n) s;

  return jsonb_build_object('generated_at', now(),
    'due', v_due, 'replies_owed', v_owed, 'reopen', v_reopen, 'meetings', v_meet,
    'counts', jsonb_build_object('due', jsonb_array_length(v_due), 'replies_owed', jsonb_array_length(v_owed), 'reopen', jsonb_array_length(v_reopen),
      'meetings', jsonb_array_length(v_meet), 'cold_sequence_due', v_cold));
end $$;
grant execute on function public.hq_follow_up_board(int) to authenticated;
