-- Commercial intelligence wrap-up (Adam, 29 Oct 2026: the final commercial-system pass; after this, operate).
-- Small additions on the existing engine. No new CRM, page or agent:
--  1. tool_capabilities: which approved tool does each capability today. Internal; the Advisor proposes an adoption,
--     it never switches a commercial workflow by itself.
--  2. companies.commercial_class (BUYER, DISTRIBUTION_PARTNER, LOCAL_PARTNER, SUPPLIER, TALENT_AMPLIFIER, COMPETITOR,
--     NOT_RELEVANT). Cold first touches, Hunter verification and the Finder spend only on buyers and distribution partners
--     (an unclassified account counts as a buyer, as before) and never on a sprint HOLD account.
--  3. lead_readiness: the seven questions a qualified lead answers before outreach.
--  4. warm_route_check: Gmail, LinkedIn, meetings, CRM people and linked companies before any first message.
--  5. asset_recommendation: which asset, if any, helps at this stage (a cold first touch is plain text, nothing attached).
--  6. hq_lead_card: the evidence block in the lead drawer and the Top 5.
--  7. commercial_learning_proposals and Advisor slot 6: rule changes proposed to Adam from outcomes, with minimum
--     samples; nothing is applied silently.

-- 1. Capability registry -------------------------------------------------------------------------------------------
create table if not exists public.tool_capabilities (
  capability text not null,
  tool text not null,
  status text not null check (status in ('AVAILABLE', 'LIMITED', 'NOT_CONNECTED', 'PENDING_APPROVAL', 'NOT_PERMITTED')),
  strength int not null default 3 check (strength between 1 and 5),
  cost text,
  rule text,
  used_by text,
  note text,
  checked_at timestamptz not null default now(),
  primary key (capability, tool)
);
alter table public.tool_capabilities enable row level security;
revoke all on public.tool_capabilities from anon, authenticated;

insert into public.tool_capabilities (capability, tool, status, strength, cost, rule, used_by, note) values
  ('COMPANY_DISCOVERY', 'Serper search (discovery departments 02-09)', 'AVAILABLE', 4, 'Serper credits', 'Qualify the company before any enrichment', 'All Directors', 'Rotating query banks with lookalike seeds'),
  ('COMPANY_DISCOVERY', 'Clay', 'NOT_CONNECTED', 5, 'Clay credits', 'Only after the company qualifies', 'All Directors', 'Connector not installed in this workspace'),
  ('COMPANY_DISCOVERY', 'Gojiberry', 'NOT_CONNECTED', 3, 'Subscription', 'Signals only; nothing sends', 'All Directors', 'Not connected'),
  ('COMPANY_DISCOVERY', 'Firecrawl', 'LIMITED', 3, 'Firecrawl credits', 'Stay on the current plan (Adam, 17 Oct)', 'Research', 'Production discovery uses search'),
  ('PEOPLE_DISCOVERY', 'Public research (W19, W23, daily-check web search)', 'AVAILABLE', 3, 'Free', 'Confirm the person from a source; never guess', 'All Directors', null),
  ('PEOPLE_DISCOVERY', 'Clay', 'NOT_CONNECTED', 5, 'Clay credits', 'One or two decision makers per qualified company; dedupe first', 'All Directors', 'Connector not installed in this workspace'),
  ('PEOPLE_DISCOVERY', 'LinkedIn data archive (Adam’s export)', 'LIMITED', 4, 'Free', 'Read-only history; strict matching', 'LinkedIn agent', 'Waiting for Adam’s upload'),
  ('EMAIL_ENRICHMENT', 'Hunter (W24 verification, W25 Finder)', 'AVAILABLE', 4, 'Free plan: 50 searches and 100 verifications a month', 'Right person first; buyers only; reserve kept', 'Email Intelligence', 'Allowance reset 27 Oct'),
  ('EMAIL_ENRICHMENT', 'Official published inbox (W23)', 'AVAILABLE', 3, 'Free', 'Company’s own website, source and date saved; never labelled VERIFIED', 'Email Intelligence', null),
  ('EMAIL_ENRICHMENT', 'Clay', 'NOT_CONNECTED', 4, 'Clay credits', 'Only with a realistic outreach action', 'Email Intelligence', 'Connector not installed in this workspace'),
  ('PUBLIC_WEB_RESEARCH', 'Web search (daily check)', 'AVAILABLE', 4, 'Free', 'Evidence with URL and date', 'Daily check', null),
  ('PUBLIC_WEB_RESEARCH', 'Serper search', 'AVAILABLE', 4, 'Serper credits', 'Evidence with URL and date', 'Discovery, W19, W23', null),
  ('SOCIAL_SIGNAL_RESEARCH', 'Serper site search (public Instagram and LinkedIn pages)', 'AVAILABLE', 3, 'Serper credits', 'Public pages only; follower counts are weak evidence', 'Discovery', null),
  ('SOCIAL_SIGNAL_RESEARCH', 'Windsor.ai', 'LIMITED', 2, 'Subscription', 'NOYA’s own accounts only', 'Content', null),
  ('GMAIL', 'Gmail (W13 sync, W15 history, W12 drafts, connector)', 'AVAILABLE', 5, 'Free', 'Reads and drafts; never sends', 'All', null),
  ('LINKEDIN_HISTORY', 'LinkedIn data archive import (HQ, LinkedIn page)', 'LIMITED', 4, 'Free', 'Read-only; no cookies, no scraping', 'LinkedIn agent', 'Waiting for Adam’s upload'),
  ('LINKEDIN_HISTORY', 'LinkedIn official API', 'NOT_PERMITTED', 5, null, 'Partner programmes only', 'LinkedIn agent', 'See docs/LINKEDIN_OFFICIAL_ACCESS.md'),
  ('LINKEDIN_CONNECTIONS', 'LinkedIn data archive (Connections.csv)', 'LIMITED', 4, 'Free', 'A plain connection is not a warm route', 'LinkedIn agent', 'Waiting for Adam’s upload'),
  ('LINKEDIN_CONNECTIONS', 'LinkedIn official API', 'NOT_PERMITTED', 5, null, 'Partner programmes only', 'LinkedIn agent', 'See docs/LINKEDIN_OFFICIAL_ACCESS.md'),
  ('LINKEDIN_REQUESTS', 'LinkedIn data archive (Invitations.csv)', 'LIMITED', 4, 'Free', 'A pending request is never sent again', 'LinkedIn agent', 'Waiting for Adam’s upload'),
  ('LINKEDIN_REQUESTS', 'LinkedIn official API', 'NOT_PERMITTED', 5, null, 'Partner programmes only', 'LinkedIn agent', 'See docs/LINKEDIN_OFFICIAL_ACCESS.md'),
  ('LINKEDIN_MESSAGES', 'Copy and Open LinkedIn, Mark sent (HQ)', 'AVAILABLE', 3, 'Free', 'Adam sends every message himself', 'LinkedIn agent', null),
  ('LINKEDIN_MESSAGES', 'LinkedIn official API', 'NOT_PERMITTED', 5, null, 'Partner programmes only', 'LinkedIn agent', 'See docs/LINKEDIN_OFFICIAL_ACCESS.md'),
  ('CALENDAR', 'Google Calendar (NOYA calendar)', 'AVAILABLE', 4, 'Free', 'No attendees, no invitations', 'Meeting Assist', null),
  ('STUDIO_DOCUMENTS', 'NOYA Studio (masters, reviewer, record)', 'AVAILABLE', 5, 'Free', 'Level gate; reviewer before READY', 'Studio', null),
  ('IMAGE_ASSET_SOURCING', 'Studio approved image library', 'AVAILABLE', 4, 'Free', 'Approved photos only; the never-list is binding', 'Studio', null),
  ('IMAGE_ASSET_SOURCING', 'Canva', 'LIMITED', 2, 'Subscription', 'Not used for client documents', 'Studio', null),
  ('PDF_GENERATION', 'Studio renderer (Chromium)', 'AVAILABLE', 5, 'Free', null, 'Studio', null),
  ('EMAIL_ATTACHMENT', 'Workflow 26 attach and byte-for-byte verify', 'AVAILABLE', 5, 'Free', 'READY TO SEND only after verification', 'Studio', null)
on conflict (capability, tool) do update set status = excluded.status, strength = excluded.strength, cost = excluded.cost,
  rule = excluded.rule, used_by = excluded.used_by, note = excluded.note, checked_at = now();

-- The strongest approved tool available today for one capability.
create or replace function public.capability_tool(p_capability text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('tool', t.tool, 'status', t.status, 'strength', t.strength, 'rule', t.rule)
                     from tool_capabilities t where t.capability = upper(p_capability) and t.status in ('AVAILABLE', 'LIMITED')
                    order by (t.status = 'AVAILABLE') desc, t.strength desc, t.tool limit 1),
                  jsonb_build_object('tool', null, 'status', 'NONE'))
$$;
revoke all on function public.capability_tool(text) from public, anon;

-- Tools not connected that would beat today's best for people, email or company discovery (one row per tool).
create or replace function public.capability_advice() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('tool', x.tool, 'capabilities', x.caps, 'gain', x.gain) order by x.gain desc, x.tool), '[]'::jsonb)
    from (select t.tool, jsonb_agg(t.capability order by t.capability) caps,
                 max(t.strength - coalesce((capability_tool(t.capability)->>'strength')::int, 0)) gain
            from tool_capabilities t
           where t.status = 'NOT_CONNECTED' and t.capability in ('PEOPLE_DISCOVERY', 'EMAIL_ENRICHMENT', 'COMPANY_DISCOVERY')
             and t.strength > coalesce((capability_tool(t.capability)->>'strength')::int, 0)
           group by t.tool) x
$$;
revoke all on function public.capability_advice() from public, anon, authenticated;

create or replace function public.hq_capabilities() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not hq_is_admin() then return jsonb_build_object('ok', false, 'reason', 'NOT_ADMIN'); end if;
  return jsonb_build_object('ok', true, 'advice', capability_advice(),
    'capabilities', coalesce((select jsonb_agg(jsonb_build_object('capability', t.capability, 'tool', t.tool, 'status', t.status,
        'strength', t.strength, 'cost', t.cost, 'rule', t.rule, 'used_by', t.used_by, 'note', t.note, 'checked_at', t.checked_at)
        order by t.capability, (t.status = 'AVAILABLE') desc, t.strength desc) from tool_capabilities t), '[]'::jsonb));
end $$;
revoke all on function public.hq_capabilities() from public, anon;

-- 2. Commercial class ------------------------------------------------------------------------------------------------
alter table public.companies add column if not exists commercial_class text;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'companies_commercial_class_check') then
    alter table public.companies add constraint companies_commercial_class_check check (commercial_class is null or commercial_class in
      ('BUYER', 'DISTRIBUTION_PARTNER', 'LOCAL_PARTNER', 'SUPPLIER', 'TALENT_AMPLIFIER', 'COMPETITOR', 'NOT_RELEVANT'));
  end if;
end $c$;

-- Backfill from the Destination Egypt record, where the role is already researched.
update public.companies c set commercial_class = case
    when o.egypt->>'partner_class' = 'EGYPT_SIDE_PARTNER' then 'LOCAL_PARTNER'
    when o.egypt->>'role' = 'PROJECT_GENERATOR' then 'BUYER'
    when o.egypt->>'role' in ('AMPLIFIER', 'TALENT') then 'TALENT_AMPLIFIER'
    when o.egypt->>'role' = 'PARTNER_SUPPLIER' then 'DISTRIBUTION_PARTNER' end
  from public.opportunities o
 where o.company_id = c.id and o.mission = 'DESTINATION_EGYPT' and o.status <> 'ARCHIVED' and c.commercial_class is null
   and (o.egypt ? 'role' or o.egypt ? 'partner_class');

-- Spend (a cold first touch, a Hunter verification, a Finder lookup) goes only to buyers and distribution partners,
-- never to an account the sprint put on HOLD.
create or replace function public.outreach_spend_ok(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(c.commercial_class, 'BUYER') in ('BUYER', 'DISTRIBUTION_PARTNER') from companies c where c.id = p_company), false)
     and not exists (select 1 from opportunities o where o.company_id = p_company and o.egypt->>'sprint' = 'HOLD' and o.status <> 'ARCHIVED')
$$;
revoke all on function public.outreach_spend_ok(uuid) from public, anon, authenticated;

do $do$
declare v text; w text;
begin
  v := pg_get_functiondef('public.commercial_director_plan(boolean,integer,boolean)'::regprocedure); w := v;
  v := replace(v, $o$and relationship_state(c.id) = 'COLD'$o$, $n$and relationship_state(c.id) = 'COLD' and outreach_spend_ok(c.id)$n$);
  if v = w then raise exception 'planner patch not applied'; end if;
  execute v;
  v := pg_get_functiondef('public.email_finder_queue(integer)'::regprocedure); w := v;
  v := replace(v, $o$and coalesce(c.outreach_hold_until, '-infinity'::timestamptz) < now()$o$,
                  $n$and coalesce(c.outreach_hold_until, '-infinity'::timestamptz) < now() and outreach_spend_ok(c.id)$n$);
  if v = w then raise exception 'finder patch not applied'; end if;
  execute v;
  v := pg_get_functiondef('public.email_verification_queue(integer)'::regprocedure); w := v;
  v := replace(v, $o$and relationship_state(c.id) = 'COLD' and coalesce(c.outreach_hold_until$o$,
                  $n$and relationship_state(c.id) = 'COLD' and outreach_spend_ok(c.id) and coalesce(c.outreach_hold_until$n$);
  if v = w then raise exception 'verification patch not applied'; end if;
  execute v;
end $do$;

-- 4. Warm route check (before 3, which reads it) ---------------------------------------------------------------------
-- LinkedIn requests from the archive (Invitations.csv): a pending request is never sent again; one Adam received is a warm route.
alter table public.linkedin_connections add column if not exists li_invite_state text;
alter table public.linkedin_connections add column if not exists li_invite_at timestamptz;
alter table public.linkedin_connections add column if not exists li_invite_message text;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'linkedin_connections_li_invite_state_check') then
    alter table public.linkedin_connections add constraint linkedin_connections_li_invite_state_check
      check (li_invite_state is null or li_invite_state in ('SENT_PENDING', 'RECEIVED_PENDING'));
  end if;
end $c$;

create or replace function public.warm_route_check(p_company uuid, p_contact uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_rel text := relationship_state(p_company); v_li record; v_pending record; v_meet timestamptz; v_people int; v_link record;
        v_route jsonb := company_email_state(p_company); v_decision text; v_why text[] := '{}';
begin
  if p_company is null then return jsonb_build_object('decision', 'HOLD', 'reasons', jsonb_build_array('No company')); end if;
  if exists (select 1 from contacts k where k.id = p_contact and (coalesce(k.do_not_contact, false) or k.status = 'DO_NOT_CONTACT'))
     or exists (select 1 from linkedin_connections l where l.matched_contact_id = p_contact and l.li_state = 'DO_NOT_CONTACT') then
    return jsonb_build_object('decision', 'HOLD', 'reasons', jsonb_build_array('They asked not to be contacted'), 'relationship', v_rel);
  end if;
  select l.first_name, l.last_name, l.li_state, l.li_last_at into v_li from linkedin_connections l
   where (l.matched_company_id = p_company or l.matched_contact_id = p_contact) and l.li_state in ('ACTIVE', 'WARM', 'DORMANT', 'REPLIED_BEFORE')
   order by (l.matched_contact_id = p_contact) desc, case l.li_state when 'ACTIVE' then 1 when 'WARM' then 2 when 'REPLIED_BEFORE' then 3 else 4 end,
            l.li_last_at desc nulls last limit 1;
  select l.first_name, l.last_name, l.li_invite_state, l.li_invite_at into v_pending from linkedin_connections l
   where (l.matched_company_id = p_company or l.matched_contact_id = p_contact) and l.li_invite_state in ('SENT_PENDING', 'RECEIVED_PENDING')
   order by l.li_invite_at desc nulls last limit 1;
  select max(coalesce(t.completed_at, t.due_at)) into v_meet from tasks t
   where t.company_id = p_company and t.status = 'COMPLETED' and (t.task_type = 'MEETING_ACTION' or t.title like 'MEETING --%');
  select count(distinct i.contact_id) into v_people from interactions i
   where i.company_id = p_company and i.direction = 'INBOUND' and i.channel <> 'WEBSITE' and i.contact_id is distinct from p_contact;
  select e.from_label, e.to_label, e.relation into v_link from relationship_edges e
   where (e.to_type = 'company' and e.to_id = p_company and relationship_state(e.from_id) not in ('COLD', 'UNKNOWN') and e.from_type = 'company')
      or (e.from_type = 'company' and e.from_id = p_company and e.to_type = 'company' and relationship_state(e.to_id) not in ('COLD', 'UNKNOWN'))
   limit 1;

  if v_rel in ('CLIENT', 'PARTNER_ACTIVE', 'PROPOSAL', 'MEETING_BOOKED', 'ACTIVE_CONVERSATION') then
    v_decision := 'WARM_RECONNECT'; v_why := v_why || ('Live relationship (' || lower(replace(v_rel, '_', ' ')) || '): work the existing thread');
  elsif v_rel = 'CONTACTED_RECENTLY' then
    v_decision := 'HOLD'; v_why := v_why || 'Contacted in the last 60 days: follow the sequence, no new first message'::text;
  elsif v_rel = 'DECLINED_RECENTLY' then
    v_decision := 'HOLD'; v_why := v_why || 'Declined in the last 180 days'::text;
  elsif v_li.li_state is not null then
    v_decision := 'WARM_RECONNECT';
    v_why := v_why || ('LinkedIn: ' || btrim(concat_ws(' ', v_li.first_name, v_li.last_name)) || ' (' || lower(replace(v_li.li_state, '_', ' ')) ||
                       coalesce(', last ' || to_char(v_li.li_last_at, 'Mon YYYY'), '') || ')');
  elsif v_meet is not null then
    v_decision := 'WARM_RECONNECT'; v_why := v_why || ('Met before (' || to_char(v_meet, 'Mon YYYY') || ')');
  elsif coalesce(v_people, 0) > 0 then
    v_decision := 'INTRODUCTION_ROUTE'; v_why := v_why || (v_people || ' other person at this company has written to NOYA before: ask for the introduction');
  elsif v_link.relation is not null then
    v_decision := 'INTRODUCTION_ROUTE'; v_why := v_why || ('Linked to ' || coalesce(nullif(v_link.from_label, ''), v_link.to_label) || ' (' || v_link.relation || '), a live relationship');
  elsif v_route->>'state' in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX') then
    v_decision := 'EMAIL_FIRST'; v_why := v_why || ('Email route: ' || coalesce(v_route->>'label', v_route->>'state'));
  elsif v_route->>'state' = 'EXHAUSTED' and exists (select 1 from contacts k where k.company_id = p_company and coalesce(k.linkedin, '') ~* 'linkedin\.com/in/'
                                                     and k.identity_status = 'CONFIRMED' and not coalesce(k.do_not_contact, false)) then
    v_decision := 'LINKEDIN_FIRST'; v_why := v_why || 'Email research exhausted; the confirmed person is on LinkedIn'::text;
  else
    v_decision := 'HOLD'; v_why := v_why || ('No usable route yet (' || coalesce(lower(replace(v_route->>'state', '_', ' ')), 'not researched') || ')');
  end if;
  if v_pending.li_invite_state = 'SENT_PENDING' then
    v_why := v_why || ('LinkedIn request to ' || btrim(concat_ws(' ', v_pending.first_name, v_pending.last_name)) || ' is pending: do not send another');
    if v_decision = 'LINKEDIN_FIRST' then v_decision := 'HOLD'; end if;
  elsif v_pending.li_invite_state = 'RECEIVED_PENDING' then
    v_why := v_why || (btrim(concat_ws(' ', v_pending.first_name, v_pending.last_name)) || ' sent Adam a LinkedIn request: accept it first');
    if v_decision in ('EMAIL_FIRST', 'LINKEDIN_FIRST', 'HOLD') then v_decision := 'WARM_RECONNECT'; end if;
  end if;
  return jsonb_build_object('decision', v_decision, 'reasons', to_jsonb(v_why), 'relationship', v_rel,
    'email_route', v_route->>'state', 'email_label', v_route->>'label', 'linkedin', v_li.li_state, 'linkedin_request', v_pending.li_invite_state,
    'met_before', v_meet, 'other_people_wrote', coalesce(v_people, 0));
end $$;
revoke all on function public.warm_route_check(uuid, uuid) from public, anon, authenticated;

-- 3. Seven questions -------------------------------------------------------------------------------------------------
create or replace function public.lead_readiness(p_opp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o opportunities%rowtype; c companies%rowtype; k contacts%rowtype; v_route jsonb; a jsonb; v_missing text[] := '{}';
begin
  select * into o from opportunities where id = p_opp;
  if o.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  select * into c from companies where id = o.company_id;
  select * into k from contacts x where x.id = o.contact_id and coalesce(x.first_name, '') <> '';
  if k.id is null then
    select * into k from contacts x where x.company_id = c.id and coalesce(x.first_name, '') <> '' and not coalesce(x.do_not_contact, false)
     order by (x.identity_status = 'CONFIRMED') desc, role_score(x.position) desc nulls last, x.created_at limit 1;
  end if;
  v_route := warm_route_check(c.id, k.id);
  a := jsonb_build_object(
    'who', coalesce(o.egypt->>'what_they_do', nullif(concat_ws(', ', c.company_type, c.country), '')),
    'why_they_matter', coalesce(o.egypt->>'audience', o.egypt->>'reach', c.universe_reason),
    'right_person', case when k.id is not null then btrim(concat_ws(' ', k.first_name, k.last_name)) || coalesce(', ' || k.position, '') end,
    'why_egypt', coalesce(o.egypt->>'why_egypt', case when coalesce(o.angle, '') ~* '(egypt|cairo|giza|nile|red sea|luxor|aswan)' then o.angle end),
    'why_now', coalesce(o.egypt->>'why_now', o.commercial_trigger, c.universe_reason),
    'project', coalesce(o.egypt->>'proposed_project', o.description, o.angle),
    'channel', v_route->>'decision');
  if a->>'who' is null then v_missing := v_missing || 'who they are'::text; end if;
  if a->>'why_they_matter' is null then v_missing := v_missing || 'why they matter'::text; end if;
  if a->>'right_person' is null then v_missing := v_missing || 'the right person'::text;
  elsif coalesce(k.identity_status, '') <> 'CONFIRMED' then v_missing := v_missing || 'person not confirmed from a source'::text; end if;
  if a->>'why_egypt' is null then v_missing := v_missing || 'why Egypt or NOYA'::text; end if;
  if a->>'why_now' is null then v_missing := v_missing || 'why now'::text; end if;
  if a->>'project' is null then v_missing := v_missing || 'the project idea'::text; end if;
  if a->>'channel' = 'HOLD' then v_missing := v_missing || ('channel: ' || coalesce(v_route->'reasons'->>0, 'none'))::text; end if;
  return jsonb_build_object('ok', true, 'ready', coalesce(array_length(v_missing, 1), 0) = 0, 'answers', a, 'missing', to_jsonb(v_missing),
    'person_confirmed', k.identity_status = 'CONFIRMED', 'contact_id', k.id, 'warm_route', v_route);
end $$;
revoke all on function public.lead_readiness(uuid) from public, anon, authenticated;

-- 5. Attachment intelligence -----------------------------------------------------------------------------------------
create or replace function public.asset_recommendation(p_opp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o opportunities%rowtype; v_rel text; v_doc record; v_wedding boolean;
begin
  select * into o from opportunities where id = p_opp;
  if o.id is null then return jsonb_build_object('asset', 'NONE', 'format', 'PLAIN', 'reason', 'No opportunity'); end if;
  v_rel := relationship_state(o.company_id);
  v_wedding := coalesce(o.egypt->>'bucket', '') = 'WEDDINGS' or coalesce(o.opportunity_type, '') ~* 'wedding';
  select d.slug, d.version, d.title, d.ready_class into v_doc from studio_documents d
   where d.company_id = o.company_id and d.ready_class in ('READY_TO_SEND', 'READY_FOR_ATTACHMENT') order by d.version desc limit 1;
  if v_doc.slug is not null then
    return jsonb_build_object('asset', 'STUDIO_DOCUMENT', 'slug', v_doc.slug, 'version', v_doc.version, 'title', v_doc.title, 'format', 'BRANDED',
      'reason', 'An approved document already exists for them; it travels only once verified on its draft');
  end if;
  if o.status in ('PROPOSAL', 'NEGOTIATION') then
    return jsonb_build_object('asset', 'PROPOSAL', 'format', 'BRANDED', 'reason', 'A real brief exists: send the proposal');
  elsif v_rel = 'MEETING_BOOKED' then
    return jsonb_build_object('asset', case when v_wedding then 'WEDDING_CONCEPT' else 'BRIEF' end, 'format', 'BRANDED',
      'reason', 'After the meeting: a tailored 2-3 page brief');
  elsif v_rel in ('ACTIVE_CONVERSATION', 'CLIENT', 'PARTNER_ACTIVE') then
    return jsonb_build_object('asset', 'ONE_PAGE', 'format', 'BRANDED', 'reason', 'They replied: one tailored page, or the NOYA brochure if they asked for credentials');
  end if;
  return jsonb_build_object('asset', 'NONE', 'format', 'PLAIN',
    'reason', 'First touch: a plain founder email with one idea; no attachment');
end $$;
revoke all on function public.asset_recommendation(uuid) from public, anon, authenticated;

-- 6. Lead card (drawer and Top 5) ------------------------------------------------------------------------------------
create or replace function public.lead_if_they_respond(p_bucket text) returns text
language sql immutable set search_path = public as $$
  select case coalesce(p_bucket, '')
    when 'WEDDINGS' then 'Offer a 20-minute call, then a one-page Egypt wedding outline (guest arrivals, hotels, venue access to verify)'
    when 'PRIVATE_CLUBS' then 'Offer a call, then a one-page member programme (dates, group size, three moments that only Egypt gives)'
    when 'TRAVEL' then 'Agree the referral or white-label terms and send the Egypt desk one-page'
    when 'MEDIA' then 'Send the production concept page and propose a scouting call'
    when 'BRAND_PRODUCTION' then 'Ask for the brief and dates; reply with three locations and how NOYA runs the Egypt side'
    when 'CORPORATE' then 'Ask for group size and dates; send a retreat outline'
    when 'NOYA_PRIVATE' then 'A discreet call; nothing in writing about any client'
    else 'Offer a short call and one tailored page' end
$$;

create or replace function public.hq_lead_card(p_opp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o opportunities%rowtype; c companies%rowtype; k contacts%rowtype; r jsonb; v_cand record; v_li record; v_move record; v_src text;
begin
  if not hq_is_admin() then return jsonb_build_object('ok', false, 'reason', 'NOT_ADMIN'); end if;
  select * into o from opportunities where id = p_opp;
  if o.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  select * into c from companies where id = o.company_id;
  r := lead_readiness(p_opp);
  select * into k from contacts where id = (r->>'contact_id')::uuid;
  select oc.channel, oc.subject, oc.draft, oc.status, oc.why_now into v_cand from outreach_candidates oc
   where oc.company_id = c.id and oc.status in ('READY', 'REVIEW_REQUIRED', 'APPROVED') and oc.draft is not null order by oc.updated_at desc limit 1;
  select a.state, a.message into v_li from linkedin_actions a where a.company_id = c.id and a.state not in ('CLOSED') order by a.updated_at desc limit 1;
  select m.recommended_message, m.action_label into v_move from commercial_next_moves m
   where m.company_id = c.id and m.status in ('PROPOSED', 'CHOSEN') order by m.updated_at desc limit 1;
  v_src := nullif(concat_ws(' · ', nullif(coalesce(k.source_type, ''), ''), nullif(coalesce(k.source_url, k.email_source_url, ''), '')), '');
  return jsonb_build_object('ok', true,
    'company', c.name, 'website', c.website, 'class', c.commercial_class,
    'person', btrim(concat_ws(' ', k.first_name, k.last_name)), 'role', k.position,
    'source', coalesce(v_src, c.source),
    'why_qualified', c.universe_reason,
    'why_now', r->'answers'->>'why_now',
    'project_idea', r->'answers'->>'project',
    'channel', r->'warm_route'->>'decision', 'channel_reasons', r->'warm_route'->'reasons',
    'relationship_state', relationship_state(c.id),
    'contact_confidence', case when k.identity_status = 'CONFIRMED' then 'Confirmed from a source' when k.id is not null then 'Needs confirming' else 'No person yet' end,
    'email_state', coalesce(r->'warm_route'->>'email_label', r->'warm_route'->>'email_route'),
    'linkedin_state', coalesce(r->'warm_route'->>'linkedin_request', r->'warm_route'->>'linkedin', v_li.state),
    'recommended_message', coalesce(v_cand.draft, v_move.recommended_message, v_li.message),
    'message_subject', v_cand.subject, 'message_status', v_cand.status,
    'supporting_asset', asset_recommendation(p_opp),
    'next_action', o.next_action,
    'if_they_respond', lead_if_they_respond(o.egypt->>'bucket'),
    'readiness', jsonb_build_object('ready', r->'ready', 'missing', r->'missing', 'answers', r->'answers'));
end $$;
revoke all on function public.hq_lead_card(uuid) from public, anon;

-- 7. Learning proposals and Advisor slot 6 ----------------------------------------------------------------------------
-- Segments need at least 8 companies contacted before any conclusion (Adam: no conclusions from tiny samples).
create or replace function public.commercial_learning_proposals() returns jsonb
language sql stable security definer set search_path = public as $$
  with f as (select * from commercial_facts() where first_outreach_at is not null),
  d as (select coalesce(dir, 'OTHER') dir, count(*) n, count(first_reply_at) rep, count(positive_at) pos, count(meeting_at) mtg,
               count(proposal_at) prop, count(won_at) won from f group by 1),
  route as (select case when exists (select 1 from outbound_emails ob join contacts k on lower(k.email) = lower(ob.to_email)
                                     where ob.company_id = f.company_id and ob.status = 'SENT' and coalesce(k.first_name, '') <> '') then 'NAMED' else 'INBOX' end kind,
                   f.first_reply_at from f),
  r as (select kind, count(*) n, count(first_reply_at) rep from route group by 1),
  p as (
    select 'EXPAND' kind, d.dir, 'Expand ' || initcap(replace(d.dir, '_', ' ')) || ': ' || d.rep || ' of ' || d.n || ' contacted replied (' ||
           round(100.0 * d.rep / d.n) || '%).' txt, d.n, 1 rk from d where d.n >= 8 and d.rep::numeric / d.n >= 0.2
    union all
    select 'REDUCE', d.dir, initcap(replace(d.dir, '_', ' ')) || ': ' || d.n || ' contacted, no reply yet. Review the angle and the people before more volume.', d.n, 2
      from d where d.n >= 8 and d.rep = 0
    union all
    select 'REVIEW', d.dir, initcap(replace(d.dir, '_', ' ')) || ': ' || d.mtg || ' meetings but no proposal yet. Check the project fit before ranking it higher.', d.n, 3
      from d where d.mtg >= 3 and d.prop = 0
    union all
    select 'ROUTE', null, 'Named decision makers reply at ' || round(100.0 * nm.rep / nm.n) || '% (' || nm.n || ' companies) against ' ||
           round(100.0 * ib.rep / ib.n) || '% for general inboxes (' || ib.n || '). Favour named regional decision makers.', nm.n + ib.n, 1
      from r nm, r ib where nm.kind = 'NAMED' and ib.kind = 'INBOX' and nm.n >= 8 and ib.n >= 8 and nm.rep::numeric / nm.n > ib.rep::numeric / ib.n + 0.1)
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'director', dir, 'text', txt, 'sample', n) order by rk, n desc), '[]'::jsonb) from p
$$;
revoke all on function public.commercial_learning_proposals() from public, anon, authenticated;

-- One decision for Adam in slot 6: a tool worth connecting, else the strongest learning proposal.
create or replace function public.advisor_proposal() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb := capability_advice()->0; l jsonb := commercial_learning_proposals()->0;
begin
  if v is not null then
    return jsonb_build_array(jsonb_build_object('kind', 'PROPOSAL', 'title', 'ADAM TO DECIDE', 'slot', 6, 'tab', 'system',
      'situation', (v->>'tool') || ' is not connected to this workspace.',
      'meaning', 'It would be the strongest tool for ' || lower(replace(array_to_string(array(select jsonb_array_elements_text(v->'capabilities')), ', '), '_', ' ')) || '.',
      'action', 'Connect it in claude.ai connectors. Directors then use it only for the one or two right people at qualified accounts.'));
  elsif l is not null then
    return jsonb_build_array(jsonb_build_object('kind', 'PROPOSAL', 'title', 'ADAM TO DECIDE', 'slot', 6, 'tab', 'agents', 'director', l->>'director',
      'situation', l->>'text', 'meaning', 'From real outcomes, sample of ' || (l->>'sample') || ' companies.',
      'action', 'Approve the change and the Director re-ranks; nothing changes until you do.'));
  end if;
  return '[]'::jsonb;
end $$;
revoke all on function public.advisor_proposal() from public, anon, authenticated;

do $do$
declare v text; w text;
begin
  v := pg_get_functiondef('public.advisor_slots(jsonb,jsonb)'::regprocedure); w := v;
  v := replace(v, $o$  return o;$o$, $n$  o := o || coalesce(advisor_proposal(), '[]'::jsonb);
  return o;$n$);
  if v = w then raise exception 'advisor_slots patch not applied'; end if;
  execute v;
end $do$;

-- Project generation also rewards a high-value audience that already travels (scores.audience, 0-5, researched per account).
create or replace function public.destination_egypt_score(p_egypt jsonb, p_warmth integer, p_contact integer) returns integer
language sql immutable set search_path = public as $$
  select round(
      coalesce(least(greatest((p_egypt->'scores'->>'project_generation')::numeric, 0), 5), 0) * 4
    + coalesce(least(greatest((p_egypt->'scores'->>'network')::numeric, 0), 5), 0) * 4
    + coalesce(least(greatest((p_egypt->'scores'->>'repeat')::numeric, 0), 5), 0) * 3
    + coalesce(least(greatest((p_egypt->'scores'->>'egypt_relevance')::numeric, 0), 5), 0) * 3
    + coalesce(least(greatest((p_egypt->'scores'->>'audience')::numeric, 0), 5), 0) * 2
    + coalesce(least(greatest((p_egypt->'scores'->>'destination_evidence')::numeric, 0), 5), 0) * 2
    + coalesce(least(greatest(p_warmth, 0), 5), 0) * 2
    + coalesce(least(greatest(p_contact, 0), 5), 0)
    + coalesce(least(greatest((p_egypt->'scores'->>'studio_ready')::numeric, 0), 5), 0))::int
$$;
