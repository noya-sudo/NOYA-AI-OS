-- NOYA commercial engine: final operating & outreach standard (Adam, 4 Oct 2026).
--  1. Working account universe: QUALIFIED / NEEDS_REVIEW / RESEARCHING / PARKED (+ EXCLUDED). QUALIFIED needs a written
--     reason, a confirmed decision maker and a usable channel. Re-runnable: universe_reclassify().
--  2. A person whose identity or role is inferred is never send-ready: their READY tasks become VERIFY FIRST.
--  3. Follow-up 2 is due 6 days after follow-up 1 is actually sent (was ~+10 days from the first message).
--  4. Hunter ROI: credits -> usable verified emails -> sends -> replies -> meetings.
--  5. Professional cold-email standard: rewritten playbook templates, outreach_quality() gate in hq_prepare_outreach.
-- Nothing here sends anything.

-- ---------------------------------------------------------------- 1. person identity
alter table public.contacts add column if not exists identity_status text;
alter table public.contacts drop constraint if exists contacts_identity_status_check;
alter table public.contacts add constraint contacts_identity_status_check
  check (identity_status is null or identity_status in ('CONFIRMED', 'NEEDS_VERIFICATION'));

-- Evidence-based, from the research notes: an inferred title, an explicit "needs verification", a dated appointment to
-- re-check, or a note that the person has left. Everything else with a named, sourced person is CONFIRMED.
update public.contacts set identity_status = case
    when coalesce(position, '') ~* 'INFERRED'
      or coalesce(notes, '') ~* '(NEEDS VERIFICATION|title INFERRED|confirm still|confirm for 20[0-9]{2}|left [A-Za-z]+ as an employee)'
      or coalesce(confidence, 0) < 60 then 'NEEDS_VERIFICATION'
    else 'CONFIRMED' end
 where identity_status is null and coalesce(first_name, last_name) is not null;

-- ---------------------------------------------------------------- 2. working account universe
alter table public.companies drop constraint if exists companies_universe_status_check;
alter table public.companies add constraint companies_universe_status_check check (universe_status is null or universe_status in
  ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING', 'PARKED', 'EXCLUDED'));

-- The decision-maker and channel state of one company, from contacts only (no inference).
create or replace function public.company_reach(p_company uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with k as (
    select ct.*, c.company_type
      from contacts ct join companies c on c.id = ct.company_id
     where ct.company_id = p_company and not coalesce(ct.do_not_contact, false) and coalesce(ct.first_name, ct.last_name) is not null)
  select jsonb_build_object(
    'people', (select count(*) from k),
    'confirmed', (select count(*) from k where identity_status = 'CONFIRMED' and position is not null),
    'unconfirmed', (select count(*) from k where identity_status is distinct from 'CONFIRMED'),
    'verified_email', exists (select 1 from k where identity_status = 'CONFIRMED' and email_status = 'VERIFIED' and email_kind(email) = 'DIRECT_PERSON_EMAIL'),
    -- LinkedIn: a saved profile, or a prepared LinkedIn message (Adam finds the confirmed person by name).
    'linkedin', exists (select 1 from k where identity_status = 'CONFIRMED' and (coalesce(linkedin, '') ~* 'linkedin\.com/in/'
                          or exists (select 1 from tasks t where t.contact_id = k.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING', 'COMPLETED')
                                       and t.title like 'LINKEDIN MESSAGE READY%'))),
    'instagram', exists (select 1 from k where identity_status = 'CONFIRMED' and coalesce(instagram, '') <> ''
                          and coalesce(company_type, '') !~* '(bank|wealth|law|legal|consult|invest|family|financial|insurance|asset|equity)'))
$$;

-- QUALIFIED   reason (>= 20 chars) + confirmed decision maker + a usable channel (verified personal email, personal
--             LinkedIn, or Instagram for a non-formal sector).
-- NEEDS_REVIEW a person exists but is unconfirmed, or confirmed without a usable channel, or no written reason.
-- RESEARCHING no named person yet.
-- PARKED / EXCLUDED are Adam's decisions and are never overwritten.
create or replace function public.universe_reclassify()
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; r jsonb; v text; n int := 0;
begin
  for c in select id, universe_status, universe_reason from companies
            where universe_status in ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING') loop
    r := company_reach(c.id);
    v := case
      when (r->>'people')::int = 0 then 'RESEARCHING'
      when length(btrim(coalesce(c.universe_reason, ''))) >= 20 and (r->>'confirmed')::int > 0
           and ((r->>'verified_email')::boolean or (r->>'linkedin')::boolean or (r->>'instagram')::boolean) then 'QUALIFIED'
      else 'NEEDS_REVIEW' end;
    if v is distinct from c.universe_status then
      update companies set universe_status = v where id = c.id; n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('changed', n, 'by_status',
    (select jsonb_object_agg(universe_status, k) from (select universe_status, count(*) k from companies where universe_status is not null group by 1) s));
end $$;
revoke all on function public.universe_reclassify() from public, anon, authenticated;
revoke all on function public.company_reach(uuid) from public, anon;

-- ---------------------------------------------------------------- 3. VERIFY FIRST gate
-- Any hand-send task for a person whose identity is not confirmed is rewritten to a VERIFY FIRST research task, so it
-- never counts as send-ready. The original title is kept in the description and restored when Adam confirms.
create or replace function public.verify_first_gate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status in ('OPEN', 'IN_PROGRESS') and new.contact_id is not null
     and new.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)'
     and (select identity_status from contacts where id = new.contact_id) is distinct from 'CONFIRMED' then
    new.description := 'ORIGINAL_TITLE: ' || new.title || chr(10) || 'ORIGINAL_TYPE: ' || coalesce(new.task_type, '') || chr(10) ||
      'Not send-ready: this person''s identity or role is not confirmed. Check their LinkedIn or the company site. ' ||
      'Mark done once confirmed and the message moves to your send queue. Dismiss if it is the wrong person.' || chr(10) || chr(10) ||
      coalesce(new.description, '');
    new.title := 'VERIFY FIRST -- ' || coalesce(nullif(substring(new.title from ' -- (.*)$'), ''), new.title);
    new.task_type := 'CONTACT_RESEARCH';
  end if;
  return new;
end $$;
create or replace trigger verify_first_gate before insert or update of title, status, contact_id on public.tasks
  for each row execute function public.verify_first_gate();

-- Confirming (marking VERIFY FIRST done) confirms the person and restores the original send task.
create or replace function public.verify_first_confirmed()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_title text; v_type text;
begin
  if new.title like 'VERIFY FIRST --%' and new.status = 'COMPLETED' and old.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
     and new.contact_id is not null and new.description like 'ORIGINAL_TITLE: %' then
    v_title := substring(new.description from '^ORIGINAL_TITLE: ([^' || chr(10) || ']+)');
    v_type := nullif(substring(new.description from 'ORIGINAL_TYPE: ([^' || chr(10) || ']*)'), '');
    update contacts set identity_status = 'CONFIRMED',
           notes = coalesce(notes, '') || chr(10) || 'Identity confirmed by Adam ' || to_char(now(), 'DD Mon YYYY') || ' (VERIFY FIRST task).'
     where id = new.contact_id;
    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
    values (new.company_id, new.contact_id, new.opportunity_id, v_title,
            regexp_replace(new.description, '^ORIGINAL_TITLE:[^' || chr(10) || ']*' || chr(10) || 'ORIGINAL_TYPE:[^' || chr(10) || ']*' || chr(10) || '[^' || chr(10) || ']*' || chr(10) || chr(10), ''),
            coalesce(v_type, 'CONTACT_RESOLUTION'), new.assigned_to, 'Verify-first gate (confirmed)', new.priority, 'OPEN', now());
  end if;
  return new;
end $$;
create or replace trigger verify_first_confirmed after update of status on public.tasks
  for each row execute function public.verify_first_confirmed();

-- Apply the gate to the existing queue (the BEFORE trigger rewrites them).
update public.tasks t set title = t.title
 where t.status in ('OPEN', 'IN_PROGRESS')
   and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)'
   and (select identity_status from contacts where id = t.contact_id) is distinct from 'CONFIRMED' and t.contact_id is not null;

-- ---------------------------------------------------------------- 4. follow-up 2 at +6 days after follow-up 1 is sent
create or replace function public.follow_up_second_step()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.task_type = 'OUTREACH_FOLLOW_UP' and new.sequence_step = 1 and new.title like 'FOLLOW UP --%'
     and new.status = 'COMPLETED' and old.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and new.opportunity_id is not null
     and not opportunity_stops_follow_up((select status from opportunities where id = new.opportunity_id))
     and not exists (select 1 from interactions i where i.opportunity_id = new.opportunity_id and i.direction = 'INBOUND'
                     and i.occurred_at >= coalesce(new.created_at, now()) - interval '1 day') then
    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at, sequence_step)
    values (new.company_id, new.contact_id, new.opportunity_id,
            'FOLLOW UP 2 --' || substr(new.title, length('FOLLOW UP --') + 1),
            'Second and final follow-up (6 days after follow-up 1 was sent). Short, one new reason to talk, easy way out.' || chr(10) ||
            'Cancelled automatically if they reply, book a call or decline. Never sent automatically.',
            'OUTREACH_FOLLOW_UP', coalesce(new.assigned_to, 'Adam'), 'Cadence rule (+6 days after follow-up 1)', greatest(coalesce(new.priority, 70) - 10, 50), 'OPEN',
            now() + interval '6 days', 2)
    on conflict do nothing;
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------- 5. Hunter ROI
-- Each workflow-05 lookup is an Email Finder (1 credit) followed by an Email Verifier (0.5 credit).
create or replace function public.hunter_roi()
returns jsonb language sql stable security definer set search_path = public as $$
  with v as (
    select v.*, coalesce(v.applied_contact_id, v.contact_id) cid,
           (case when v.finder_score is not null then 1 else 0 end + 0.5) credits,
           v.outcome in ('APPLIED_NEW_EMAIL', 'CONFIRMED_EXISTING_EMAIL', 'CREATED_CONTACT') usable
      from contact_email_verifications v where v.provider = 'HUNTER'),
  u as (select distinct on (cid) cid, created_at from v where usable and cid is not null order by cid, created_at),
  f as (
    select u.cid,
      exists (select 1 from interactions i where i.contact_id = u.cid and i.direction = 'OUTBOUND' and i.channel = 'EMAIL' and i.occurred_at >= u.created_at) sent,
      exists (select 1 from interactions i where i.contact_id = u.cid and i.direction = 'INBOUND' and i.channel <> 'MEETING' and i.occurred_at >= u.created_at) replied,
      exists (select 1 from interactions i where i.contact_id = u.cid and i.channel = 'MEETING' and i.occurred_at >= u.created_at) met
    from u)
  select jsonb_build_object(
    'lookups', (select count(*) from v),
    'credits', (select coalesce(sum(credits), 0) from v),
    'credits_30d', (select coalesce(sum(credits), 0) from v where created_at >= now() - interval '30 days'),
    'usable_emails', (select count(*) from v where usable),
    'usable_rate', (select round(100.0 * count(*) filter (where usable) / nullif(count(*), 0)) from v),
    'credits_per_usable', (select round(sum(credits) / nullif(count(*) filter (where usable), 0), 1) from v),
    'sent', (select count(*) from f where sent),
    'replies', (select count(*) from f where replied),
    'meetings', (select count(*) from f where met),
    'gate', 'Hunter runs only for a qualified account, confirmed decision maker (confidence >= 85), priority >= 85, email the right channel, no verified email.',
    'last_lookup', (select max(created_at) from v))
$$;
revoke all on function public.hunter_roi() from public, anon;

-- ---------------------------------------------------------------- 6. professional cold-email standard
create or replace function public.outreach_quality(p_subject text, p_body text)
returns jsonb language plpgsql immutable as $$
declare b text := coalesce(p_body, ''); s text := btrim(coalesce(p_subject, '')); main text; w int; issues text[] := '{}'; hard text[] := '{}'; ph text;
  banned text[] := array['i hope this email finds you well', 'i hope you''re well', 'i hope you are well', 'i wanted to reach out', 'i am reaching out',
    'i''m reaching out', 'i wanted to introduce', 'unparalleled', 'world-class', 'world class', 'elevate', 'seamless luxury', 'bespoke excellence',
    'bespoke solutions', 'luxury redefined', 'curated to perfection', 'synergies', 'we are delighted', 'free call', 'based in egypt'];
begin
  main := regexp_replace(b, E'\\n\\s*\\nBest,[\\s\\S]*$', '');
  w := coalesce(array_length(regexp_split_to_array(btrim(main), E'\\s+'), 1), 0);
  if w < 85 then issues := issues || ('TOO_SHORT(' || w || 'w)'); end if;
  if w > 140 then issues := issues || ('TOO_LONG(' || w || 'w)'); end if;
  if b !~ '^(Hi [^,\n]+,|Hello,)' then issues := issues || 'GREETING'::text; end if;
  if b !~ E'Adam Elshazly\\nFounder, NOYA Concierge\\nGlobal concierge & lifestyle management\\nnoyaconcierge\\.com · @noyaconcierge\\nadam@noyaconcierge\\.com'
    then hard := hard || 'SIGNATURE'::text; end if;
  if b ~ '\{\{' or s ~ '\{\{' then hard := hard || 'UNFILLED_PLACEHOLDER'::text; end if;
  if main ~* '(https?://|calendly|<img|\[image)' then hard := hard || 'LINK_OR_IMAGE_IN_BODY'::text; end if;
  foreach ph in array banned loop
    if position(ph in lower(b || ' ' || s)) > 0 then hard := hard || ('BANNED:' || ph); end if;
  end loop;
  if (length(main) - length(replace(main, '?', ''))) > 1 then issues := issues || 'MORE_THAN_ONE_QUESTION'::text; end if;
  if main !~* '(\?|short call|introduction call|right person)' then issues := issues || 'NO_CTA'::text; end if;
  if s = '' or length(s) > 60 or s ~ '[!]' then issues := issues || 'SUBJECT'::text; end if;
  return jsonb_build_object('status', case when array_length(hard, 1) > 0 then 'BLOCKED' when array_length(issues, 1) > 0 then 'NEEDS_EDIT' else 'PASS' end,
    'words', w, 'blocking', to_jsonb(hard), 'issues', to_jsonb(issues));
end $$;

-- Playbook outreach now passes the gate before a draft is created: a BLOCKED draft is refused, a NEEDS_EDIT draft is
-- created with the issues written into the approval task.
create or replace function public.hq_prepare_outreach(p_opp uuid, p_contact uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); o opportunities%rowtype; r jsonb; v_ver int; k contacts%rowtype; q jsonb;
begin
  select * into o from opportunities where id = p_opp; if o.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if p_contact is not null then
    select * into k from contacts where id = p_contact;
    if k.id is null or k.company_id is distinct from o.company_id then return jsonb_build_object('ok', false, 'reason', 'CONTACT_NOT_AT_COMPANY'); end if;
    update opportunities set contact_id = k.id, contact_first_name = k.first_name, contact_last_name = k.last_name, contact_position = k.position,
           contact_email = k.email, email_status = k.email_status where id = p_opp;
  end if;
  if (select identity_status from contacts where id = coalesce(p_contact, o.contact_id)) is distinct from 'CONFIRMED'
     and coalesce(p_contact, o.contact_id) is not null then
    return jsonb_build_object('ok', false, 'reason', 'PERSON_NOT_CONFIRMED');
  end if;
  r := opportunity_outreach(p_opp);
  if not coalesce((r->>'ready')::boolean, false) then return jsonb_build_object('ok', false, 'reason', 'OUTREACH_NOT_READY', 'missing', r->'missing', 'preview', r); end if;
  q := outreach_quality(r->>'subject', r->>'body');
  if q->>'status' = 'BLOCKED' then return jsonb_build_object('ok', false, 'reason', 'QUALITY_GATE', 'quality', q, 'preview', r); end if;
  select coalesce(max(version), 0) + 1 into v_ver from outreach_drafts where opportunity_id = p_opp;
  insert into outreach_drafts (opportunity_id, version, subject, body, follow_up_plan, source, created_by)
  values (p_opp, v_ver, r->>'subject', r->>'body',
          (select string_agg('Day +' || (f->>'day') || ' · ' || (f->>'channel') || ' · ' || (f->>'purpose') || ': ' || (f->>'message'), E'\n') from jsonb_array_elements(r->'follow_ups') f),
          'PLAYBOOK_TEMPLATE', v_admin);
  insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
  select o.company_id, coalesce(p_contact, o.contact_id), p_opp, 'Approve outreach: ' || coalesce(o.company_name, 'opportunity'),
         'Playbook draft (' || coalesce(r->>'product', '') || '). Quality: ' || (q->>'status') ||
         case when q->>'status' <> 'PASS' then ' -- ' || array_to_string(array(select jsonb_array_elements_text(q->'issues')), ', ') else '' end ||
         '. Review, edit if needed, approve → Gmail draft → you send from Gmail.', 'SALES_OUTREACH_APPROVAL',
         o.owner, 'HQ (playbook template)', 75, 'OPEN', now()
  where not exists (select 1 from tasks where opportunity_id = p_opp and task_type = 'SALES_OUTREACH_APPROVAL' and status in ('OPEN', 'IN_PROGRESS'));
  update opportunities set status = 'READY', approval_status = 'PENDING', next_action = 'Approve the outreach draft (Sales & Outreach → Ready)', next_action_due = current_date where id = p_opp;
  perform hq_audit('OUTREACH_PREPARED', p_opp, jsonb_build_object('version', v_ver, 'product', o.product_code, 'source', 'PLAYBOOK_TEMPLATE', 'quality', q));
  return jsonb_build_object('ok', true, 'version', v_ver, 'subject', r->>'subject', 'quality', q);
end $$;

-- Rewritten templates: Hi [First Name] / why them / who NOYA is / commercial fit / one CTA / standard signature.
-- Word-counted at 92-115 words each (excluding the signature) with typical placeholder values.
update public.commercial_products set email_template = '{"subject": "NOYA x {{company}}", "body": "Hi {{first_name}},\n\nWith {{event}} in {{destination}} on {{event_date}}, your international athletes and VIP participants will need the ground to work around the race: arrivals, rooms near the venue, transport and recovery.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nFor an organiser, that means one athlete lead on our side handling VIP airport arrivals, hotel allocation, transfers and wellness partners, while your team stays focused on the race itself. Everything is arranged to your standards and reported back to you.\n\nWould you be the right person to discuss this with?\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'ATHLETE_TEAM_DESK';
update public.commercial_products set email_template = '{"subject": "{{company}} x NOYA", "body": "Hi {{first_name}},\n\nI saw {{trigger_detail}}, and moments like this usually bring international guests, press and creators into Egypt at short notice.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nFor brands, we act as the local execution partner: locations, accommodation, transport, hospitality and talent, with one team handling the details between the venue and the hotel. Your agency keeps the creative lead and the client relationship; we make sure the ground delivers to the same standard.\n\nIf Egypt is relevant to anything coming up, I''d be happy to arrange a short introduction call.\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'BRAND_EXPERIENCE_DESK';
update public.commercial_products set email_template = '{"subject": "NOYA x {{company}}", "body": "Hi {{first_name}},\n\nI saw {{company}} is involved in {{event}} in {{destination}}, which usually means senior delegations and clients arriving on tight schedules.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nFor corporate teams, we handle executive travel and VIP arrivals end to end: airport, chauffeurs, security, hotels and private client dinners, with one lead and one point of accountability. It takes the logistics away from your team and gives your guests a consistent standard throughout.\n\nWould be good to arrange a short call and explore whether there could be a fit.\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'CORPORATE_DESK';
update public.commercial_products set email_template = '{"subject": "Egypt partnership", "body": "Hi {{first_name}},\n\nEgypt is back on many private clients'' lists with the Grand Egyptian Museum open and new openings on the Nile and Red Sea, and {{company}} looks after the kind of traveller who expects it done properly.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nFor travel and concierge partners, you keep the client relationship while we handle the local execution: private access, hotels, Nile programmes, transport and security, on net rates or commission as you prefer.\n\nIf Egypt is relevant to anything coming up, I''d be happy to arrange a short introduction call.\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'EGYPT_DESTINATION_DESK';
update public.commercial_products set supply_email_template = '{"subject": "{{company}} x NOYA", "body": "Hi {{first_name}},\n\n{{trigger_detail}} is exactly the kind of news our private clients ask us about first.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nWe plan travel for private clients, families and partner agencies who book at this level, and we would like to introduce {{company}} to them properly: one contact on your sales team, agreed partner terms, and our clients looked after before, during and after their stay. Where it fits, there may also be selective content opportunities.\n\nWould you be the right person to discuss this with?\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'EGYPT_DESTINATION_DESK';
update public.commercial_products set email_template = '{"subject": "NOYA x {{company}}", "body": "Hi {{first_name}},\n\nWith international guests arriving for {{event}}, much of what they remember happens outside the venue: arrivals, transfers, where they stay and where they eat.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nFor organisers, we run that layer as a guest desk: one named lead, a 24/7 line for your guests, and our hotel and transport partners behind it. Your team keeps control of the programme; we make sure every guest is handled to the same standard from the airport onwards.\n\nWould be good to arrange a short call and explore whether there could be a fit.\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'EVENT_CONCIERGE_DESK';
update public.commercial_products set email_template = '{"subject": "NOYA x {{company}}", "body": "Hi {{first_name}},\n\n{{trigger_detail}}.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nWe look after a small number of private clients and families: villas, yachts, travel, reservations and access, handled by one manager with a trusted network behind them. Requests are often time-sensitive, so discretion and responsiveness matter more to us than volume. Egypt and the Mediterranean are a particular strength, but we work wherever our clients travel.\n\nIf anything is coming up, I''d be happy to arrange a short introduction call.\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'GLOBAL_TRAVEL_LIFESTYLE';
update public.commercial_products set email_template = '{"subject": "NOYA x {{company}}", "body": "Hi {{first_name}},\n\nFor guests at {{event}}, a gift that feels chosen for them tends to be remembered long after the evening itself.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nAlongside travel and hospitality, we source and deliver luxury gifts and hard-to-find items for brands and hosts: authenticated, presented properly and delivered on time, including in Egypt, where local sourcing is often the hardest part. One contact handles the brief from shortlist to delivery.\n\nWould you be the right person to discuss this with?\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'LUXURY_SOURCING';
update public.commercial_products set email_template = '{"subject": "NOYA x {{company}}", "body": "Hi {{first_name}},\n\n{{trigger_detail}}.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nFor families and principals, we act as a private lifestyle and travel team: one dedicated manager, a trusted network behind them, and the discretion that comes from working with a small number of clients. That covers travel, villas, reservations, security and the requests that cannot wait until the morning.\n\nIf it would be helpful, I''d be happy to arrange a short introduction call.\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'NOYA_PRIVATE';
update public.commercial_products set partner_email_template = '{"subject": "{{company}} x NOYA", "body": "Hi {{first_name}},\n\n{{trigger_detail}}, and buyers at this level tend to expect more than the keys.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nFor developers, we can be the concierge your sales team introduces to buyers: arrivals handled, villas and hotels while they visit, the right tables, drivers and security, all delivered to your standards and reported back to your team. It adds a service layer to the launch without adding headcount.\n\nWould be good to arrange a short call and explore whether there could be a fit.\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'NOYA_PRIVATE';
update public.commercial_products set email_template = '{"subject": "Egypt production support", "body": "Hi {{first_name}},\n\nI saw {{trigger_detail}}; on shoots in Egypt, schedules usually slip because of what happens off set rather than on it.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nFor production teams, we act as the local execution partner for the ground layer: crew accommodation and fleets, talent care, location support, dining and supplier coordination, working alongside your fixer and permit partners. Your team keeps creative and production control; we keep the logistics moving.\n\nWould you be the right person to discuss this with?\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'PRODUCTION_DESK';
update public.commercial_products set email_template = '{"subject": "NOYA x {{company}}", "body": "Hi {{first_name}},\n\nWith {{event}} on {{event_date}}, there is usually a short list of guests whose experience matters more than anyone else''s.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nFor organisers, we host those VIPs discreetly: met at the aircraft, private transport, security, suites and one host they can message at any hour. Your team keeps the programme and the relationships; we take the time-sensitive requests off your hands so the event gets your full attention.\n\nWould be good to arrange a short call and explore whether there could be a fit.\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'VIP_GUEST_DESK';
update public.commercial_products set email_template = '{"subject": "Egypt destination support", "body": "Hi {{first_name}},\n\nFor weddings in Egypt with international guests, the planner''s week is often taken over by guest logistics rather than the event itself.\n\nNOYA is a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt.\n\nFor planners, you keep the client and the creative direction while we support the destination side: guest travel, accommodation, airport arrivals, transfers, experiences and one concierge line for every guest. Your team can focus on the day while the guests are looked after properly from arrival to departure.\n\nIf an Egypt wedding is coming up, I''d be happy to arrange a short introduction call.\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"}'::jsonb, updated_at = now() where code = 'WEDDING_GUEST_DESK';

-- ---------------------------------------------------------------- 7. queue health + HQ
create or replace function public.queue_health()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_h interval := interval '3 days'; r jsonb; e int; eb int; l int; f int; w int; vf int;
begin
  -- new emails: approvals with a sendable recipient AND a draft that passes the quality gate (not BLOCKED),
  -- not already sitting in Gmail (those count once, as DRAFTED)
  select count(*) filter (where q <> 'BLOCKED'), count(*) filter (where q = 'BLOCKED') into e, eb from (
    select coalesce(outreach_quality(d->>'subject', d->>'body')->>'status', 'BLOCKED') q
      from tasks t cross join lateral (select hq_current_draft(t.opportunity_id) d) x
     where t.status = 'OPEN' and t.task_type = 'SALES_OUTREACH_APPROVAL'
       and outbound_recipient_block_reason((select contact_id from opportunities where id = t.opportunity_id)) is null
       and not exists (select 1 from outbound_emails ob where ob.opportunity_id = t.opportunity_id and ob.status in ('QUEUED', 'CLAIMED', 'DRAFTED', 'SENT'))) s;
  e := e + (select count(*) from tasks t where t.status = 'OPEN' and t.title like 'EMAIL READY%' and coalesce(t.due_at, now()) <= now() + v_h)
         + (select count(*) from outbound_emails where status = 'DRAFTED');
  select count(*) into l from tasks t where t.status = 'OPEN' and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY)'
     and coalesce(t.due_at, now()) <= now() + v_h;
  select count(*) into f from tasks t where t.status = 'OPEN' and t.task_type = 'OUTREACH_FOLLOW_UP' and coalesce(t.due_at, now()) <= now() + v_h;
  select count(*) into w from tasks t where t.status = 'OPEN' and coalesce(t.due_at, now()) <= now() + v_h
     and (t.title like 'RECONNECT%' or t.task_type in ('REPLY_ACTION', 'MEETING_ACTION') or t.title like 'ADAM -- PERSONAL%');
  select count(*) into vf from tasks t where t.status = 'OPEN' and t.title like 'VERIFY FIRST --%';
  r := jsonb_build_array(
    jsonb_build_object('key', 'email', 'label', 'New emails', 'per_day', 5, 'ready', e, 'target', 15, 'shortfall', greatest(15 - e, 0)),
    jsonb_build_object('key', 'linkedin', 'label', 'LinkedIn / DM', 'per_day', 5, 'ready', l, 'target', 15, 'shortfall', greatest(15 - l, 0)),
    jsonb_build_object('key', 'follow_up', 'label', 'Follow-ups due', 'per_day', 3, 'ready', f, 'target', 9, 'shortfall', greatest(9 - f, 0)),
    jsonb_build_object('key', 'warm', 'label', 'Warm reconnects / replies', 'per_day', 2, 'ready', w, 'target', 6, 'shortfall', greatest(6 - w, 0)));
  return jsonb_build_object('lines', r, 'ready', least(e, 15) + least(l, 15) + least(f, 9) + least(w, 6), 'target', 45,
    'rule', 'Quality first: a shortfall is shown, never filled with weak prospects or unconfirmed people.',
    'verify_first', vf, 'email_blocked', eb,
    'universe', (select count(*) from companies where universe_status = 'QUALIFIED'),
    'universe_by_status', (select jsonb_object_agg(universe_status, k) from (select universe_status, count(*) k from companies where universe_status is not null group by 1) s),
    'universe_target', '300–500 named accounts, built progressively');
end $$;

create or replace function public.hq_execution()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  return jsonb_build_object('queue', queue_health(), 'weekly', commercial_weekly_metrics(6), 'hunter', hunter_roi());
end $$;
revoke all on function public.hq_execution() from public, anon;
grant execute on function public.hq_execution() to authenticated;

select public.universe_reclassify();

-- Data decisions applied on 4 Oct 2026 (recorded here; ids are live rows):
-- * Opportunities whose contact is unconfirmed moved READY -> RESEARCHING (The Chedi El Gouna, CIFF, Aman, Campden Wealth,
--   Orascom Pyramids Entertainment); their LinkedIn tasks became VERIFY FIRST.
-- * Celebrity cold approaches with no warm route (Huda Kattan, Samih Sawiris, Kendall Jenner) moved to LONG_TERM.
-- * 9 pending workflow-05 approval drafts: old signature replaced with the standard one (exact text swap, no other edits).
-- * Aman (Jihane Mamouri) approval put on hold (WAITING): title inferred.
-- * Intelligence 9776ff01 (El Gouna lineup article) DISMISSED as DUPLICATE_OF 1218021c; no opportunities attached, nothing merged,
--   evidence kept in notes. (The 3 Oct hang was lock contention; retried with lock_timeout.)
-- * Reclassification result: 64 QUALIFIED, 21 NEEDS_REVIEW, 51 RESEARCHING (was 136 QUALIFIED).
