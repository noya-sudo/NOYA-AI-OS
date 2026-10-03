-- Commercial execution rules (Adam, 3 Oct 2026):
--  1. Follow-ups: after a genuine send, follow-up tasks at ~+4 and ~+10 days. Never auto-sent.
--     A reply, a booked call, a decline or an unsuitable prospect cancels the future follow-ups.
--  2. Queue health: 15 quality actions a day (5 new emails, 5 LinkedIn, 3 follow-ups, 2 warm reconnects),
--     3 working days (45) kept ready. Shortfalls are shown, never filled with weak prospects.
--  3. Working universe: a company counts only when there is written evidence for why NOYA should pursue it.
--  4. Weekly measurement by prospecting segment, from sends to revenue.

-- ---------------------------------------------------------------- 1. follow-up cadence
alter table public.tasks add column if not exists sequence_step smallint not null default 1;

-- The existing index (one open follow-up per opportunity) stays: steps are chained, so only one is ever open.
-- (Dropping it hangs on this project; chaining makes it unnecessary.)
create unique index if not exists tasks_one_open_follow_up_per_step on public.tasks (opportunity_id, sequence_step)
  where task_type = 'OUTREACH_FOLLOW_UP' and status in ('OPEN', 'IN_PROGRESS', 'WAITING');

-- Opportunity states after which no further chasing is appropriate.
create or replace function public.opportunity_stops_follow_up(p_status text)
returns boolean language sql immutable as $$
  select coalesce(p_status, '') in ('INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST', 'LONG_TERM', 'ARCHIVED')
$$;

-- Step 1 (+4 days) is created by the existing send paths (workflow 12 / 13 / HQ log-touch) or by the trigger below for
-- manual LinkedIn / WhatsApp / Instagram / email sends. Step 2 (~+10 days from the first message) is created when Adam
-- marks step 1 done (= he sent it). A reply cancels step 1 first (trigger on interactions), so no step 2 follows it.
create or replace function public.follow_up_second_step()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_first timestamptz;
begin
  if new.task_type = 'OUTREACH_FOLLOW_UP' and new.sequence_step = 1 and new.title like 'FOLLOW UP --%'
     and new.status = 'COMPLETED' and old.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and new.opportunity_id is not null
     and not opportunity_stops_follow_up((select status from opportunities where id = new.opportunity_id))
     and not exists (select 1 from interactions i where i.opportunity_id = new.opportunity_id and i.direction = 'INBOUND'
                     and i.occurred_at >= coalesce(new.created_at, now()) - interval '1 day') then
    v_first := coalesce(new.due_at, now()) - interval '4 days';
    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at, sequence_step)
    values (new.company_id, new.contact_id, new.opportunity_id,
            'FOLLOW UP 2 --' || substr(new.title, length('FOLLOW UP --') + 1),
            'Second and final follow-up (~10 days after the first message). Short, one new reason to talk, easy way out.' || chr(10) ||
            'Cancelled automatically if they reply, book a call or decline. Never sent automatically.',
            'OUTREACH_FOLLOW_UP', coalesce(new.assigned_to, 'Adam'), 'Cadence rule (+10 days)', greatest(coalesce(new.priority, 70) - 10, 50), 'OPEN',
            greatest(v_first + interval '10 days', now() + interval '2 days'), 2)
    on conflict do nothing;
  end if;
  return new;
end $$;
create or replace trigger follow_up_second_step after update of status on public.tasks
  for each row execute function public.follow_up_second_step();

-- A hand-sent message (LinkedIn / Instagram / WhatsApp / email task marked Complete in HQ) is a genuine send:
-- log it once, mark the opportunity contacted and book follow-up 1 (+4 days); step 2 follows from the trigger above.
-- "Dismiss" in HQ (status CANCELLED) means it was not sent and books nothing.
create or replace function public.manual_send_cadence()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ch text; v_company text; v_label text;
begin
  if new.status = 'COMPLETED' and old.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and new.opportunity_id is not null
     and new.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)' then
    v_ch := case when new.title like 'LINKEDIN%' then 'LINKEDIN' when new.title like 'INSTAGRAM%' then 'INSTAGRAM_DM'
                 when new.title like 'WHATSAPP%' then 'WHATSAPP' else 'EMAIL' end;
    v_label := case v_ch when 'LINKEDIN' then 'LinkedIn' when 'INSTAGRAM_DM' then 'Instagram' when 'WHATSAPP' then 'WhatsApp' else 'Email' end;
    if not exists (select 1 from interactions i where i.opportunity_id = new.opportunity_id and i.direction = 'OUTBOUND'
                   and i.channel = v_ch and i.occurred_at > now() - interval '15 minutes') then
      insert into interactions (company_id, contact_id, opportunity_id, channel, direction, subject, summary, occurred_at)
      values (new.company_id, new.contact_id, new.opportunity_id, v_ch, 'OUTBOUND', left(new.title, 200),
              'Sent by Adam by hand (task marked done in HQ)', now());
    end if;
    update opportunities set status = 'CONTACTED', updated_at = now(),
           next_action = 'Await reply - follow up ' || to_char((now() + interval '4 days') at time zone 'Africa/Cairo', 'DD Mon')
     where id = new.opportunity_id and status in ('NEW', 'RESEARCHING', 'READY', 'FOLLOW_UP');
    if not opportunity_stops_follow_up((select status from opportunities where id = new.opportunity_id)) then
      select name into v_company from companies where id = new.company_id;
      insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at, sequence_step)
      values (new.company_id, new.contact_id, new.opportunity_id,
              'FOLLOW UP -- ' || coalesce(v_company, 'opportunity') || ' (' || v_label || ')',
              'First message sent ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon YYYY') || ' via ' || v_label || '.' || chr(10) ||
              'Original task: ' || new.title || chr(10) || 'Same channel, two lines, add one useful detail. Skip if they replied.',
              'OUTREACH_FOLLOW_UP', 'Adam', 'Cadence rule (+4 days)', coalesce(new.priority, 70), 'OPEN', now() + interval '4 days', 1)
      on conflict do nothing;
    end if;
  end if;
  return new;
end $$;
create or replace trigger manual_send_cadence after update of status on public.tasks
  for each row execute function public.manual_send_cadence();

-- Cancel future follow-ups (and conditional "ONLY if ... has not replied" sends) once the conversation moves.
create or replace function public.cancel_follow_ups(p_opp uuid, p_reason text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update tasks set status = 'CANCELLED', updated_at = now(),
         description = coalesce(description, '') || E'\n\nSuperseded ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon YYYY') || ': ' || p_reason
   where opportunity_id = p_opp and status in ('OPEN', 'IN_PROGRESS', 'WAITING')
     and ((task_type = 'OUTREACH_FOLLOW_UP' and title like 'FOLLOW UP%') or title like '%ONLY if%');
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.follow_up_cancel_on_reply()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.direction = 'INBOUND' and new.opportunity_id is not null then
    perform cancel_follow_ups(new.opportunity_id, 'reply received (' || coalesce(new.channel, '?') || ')');
  end if;
  return new;
end $$;
create or replace trigger follow_up_cancel_on_reply after insert on public.interactions
  for each row execute function public.follow_up_cancel_on_reply();

create or replace function public.follow_up_cancel_on_stage()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and opportunity_stops_follow_up(new.status) then
    perform cancel_follow_ups(new.id, 'opportunity moved to ' || new.status);
  end if;
  return new;
end $$;
create or replace trigger follow_up_cancel_on_stage after update of status on public.opportunities
  for each row execute function public.follow_up_cancel_on_stage();

create or replace function public.follow_up_cancel_on_dnc()
returns trigger language plpgsql security definer set search_path = public as $$
declare o record;
begin
  if coalesce(new.do_not_contact, false) and not coalesce(old.do_not_contact, false) then
    for o in select id from opportunities where contact_id = new.id loop
      perform cancel_follow_ups(o.id, 'contact marked do-not-contact');
    end loop;
  end if;
  return new;
end $$;
create or replace trigger follow_up_cancel_on_dnc after update of do_not_contact on public.contacts
  for each row execute function public.follow_up_cancel_on_dnc();

-- ---------------------------------------------------------------- 3. working universe
alter table public.companies add column if not exists prospect_segment text;
alter table public.companies add column if not exists universe_status text;
alter table public.companies add column if not exists universe_reason text;
alter table public.companies add column if not exists universe_added_at timestamptz;
alter table public.companies add constraint companies_prospect_segment_check check (prospect_segment is null or prospect_segment in
  ('PRIVATE_OFFICE', 'TRAVEL_PARTNER', 'BRAND_PR_PRODUCTION', 'WEDDING_EVENTS', 'HOTELS_HOSPITALITY', 'LIVE_SIGNAL', 'MEMBER_COMMUNITIES', 'CORPORATE_EVENTS', 'TALENT', 'OTHER'));
alter table public.companies add constraint companies_universe_status_check check (universe_status is null or universe_status in ('QUALIFIED', 'PARKED', 'EXCLUDED'));
-- QUALIFIED requires the written reason (the evidence for why NOYA should pursue it).
alter table public.companies add constraint companies_universe_reason_check check (universe_status is distinct from 'QUALIFIED' or length(btrim(coalesce(universe_reason, ''))) >= 20);

create or replace function public.company_segment(p_segment text, p_vertical_override text, p_company_type text)
returns text language sql stable as $$
  select coalesce(p_segment,
    case coalesce(p_vertical_override, commercial_vertical(null, p_company_type))
      when 'BRAND_PRODUCTION' then 'BRAND_PR_PRODUCTION'
      when 'WEDDINGS_PRIVATE_EVENTS' then 'WEDDING_EVENTS'
      when 'HOTELS_CONTENT' then 'HOTELS_HOSPITALITY'
      when 'DESTINATION_CONCIERGE_PARTNERS' then 'TRAVEL_PARTNER'
      when 'MEMBER_COMMUNITIES' then 'MEMBER_COMMUNITIES'
      when 'TALENT_SUPPORT' then 'TALENT'
      when 'CORPORATE_EVENTS' then case when coalesce(p_company_type, '') ~* '(bank|wealth|invest|family|private.office|asset)' then 'PRIVATE_OFFICE' else 'CORPORATE_EVENTS' end
      else 'OTHER' end)
$$;

-- Existing companies with a written fit (opportunity reason or notes) count as qualified; the rest stay unclassified.
update companies c set universe_status = 'QUALIFIED', universe_added_at = coalesce(universe_added_at, c.created_at),
       universe_reason = left(coalesce((select coalesce(o.reason, o.description) from opportunities o where o.company_id = c.id and length(coalesce(o.reason, o.description, '')) >= 20 order by o.priority desc nulls last limit 1), c.notes), 600)
 where c.universe_status is null and coalesce(c.notes, '') not like '%MERGED_INTO:%'
   and length(coalesce((select coalesce(o.reason, o.description) from opportunities o where o.company_id = c.id and length(coalesce(o.reason, o.description, '')) >= 20 limit 1), c.notes, '')) >= 20;

-- ---------------------------------------------------------------- 2. queue health
create or replace function public.queue_health()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_h interval := interval '3 days'; r jsonb; e int; l int; f int; w int;
begin
  -- new emails: approvals whose recipient is sendable + hand-send email tasks + approved drafts sitting in Gmail
  select (select count(*) from tasks t where t.status = 'OPEN' and t.task_type = 'SALES_OUTREACH_APPROVAL'
            and outbound_recipient_block_reason((select contact_id from opportunities where id = t.opportunity_id)) is null)
       + (select count(*) from tasks t where t.status = 'OPEN' and t.title like 'EMAIL READY%' and coalesce(t.due_at, now()) <= now() + v_h)
       + (select count(*) from outbound_emails where status = 'DRAFTED') into e;
  select count(*) into l from tasks t where t.status = 'OPEN' and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY)'
     and coalesce(t.due_at, now()) <= now() + v_h;
  select count(*) into f from tasks t where t.status = 'OPEN' and t.task_type = 'OUTREACH_FOLLOW_UP' and coalesce(t.due_at, now()) <= now() + v_h;
  select count(*) into w from tasks t where t.status = 'OPEN' and coalesce(t.due_at, now()) <= now() + v_h
     and (t.title like 'RECONNECT%' or t.task_type in ('REPLY_ACTION', 'MEETING_ACTION') or t.title like 'ADAM -- PERSONAL%');
  r := jsonb_build_array(
    jsonb_build_object('key', 'email', 'label', 'New emails', 'per_day', 5, 'ready', e, 'target', 15, 'shortfall', greatest(15 - e, 0)),
    jsonb_build_object('key', 'linkedin', 'label', 'LinkedIn / DM', 'per_day', 5, 'ready', l, 'target', 15, 'shortfall', greatest(15 - l, 0)),
    jsonb_build_object('key', 'follow_up', 'label', 'Follow-ups due', 'per_day', 3, 'ready', f, 'target', 9, 'shortfall', greatest(9 - f, 0)),
    jsonb_build_object('key', 'warm', 'label', 'Warm reconnects / replies', 'per_day', 2, 'ready', w, 'target', 6, 'shortfall', greatest(6 - w, 0)));
  return jsonb_build_object('lines', r, 'ready', least(e, 15) + least(l, 15) + least(f, 9) + least(w, 6), 'target', 45,
    'rule', 'Quality first: a shortfall is shown, never filled with weak prospects.',
    'universe', (select count(*) from companies where universe_status = 'QUALIFIED'),
    'universe_target', '300–500 qualified named accounts, built progressively');
end $$;

-- ---------------------------------------------------------------- 4. weekly metrics by segment
create or replace function public.commercial_weekly_metrics(p_weeks int default 6)
returns jsonb language sql stable security definer set search_path = public as $$
  with seg as (
    select c.id, company_segment(c.prospect_segment, c.vertical_override, c.company_type) s from companies c),
  wk as (select generate_series(date_trunc('week', now()) - ((greatest(least(coalesce(p_weeks, 6), 26), 1) - 1) * interval '1 week'), date_trunc('week', now()), interval '1 week') w),
  ev as (
    select date_trunc('week', c.universe_added_at) w, sg.s, 'qualified' k from companies c join seg sg on sg.id = c.id where c.universe_status = 'QUALIFIED'
    union all select date_trunc('week', k.created_at), sg.s, 'contacts' from contacts k join seg sg on sg.id = k.company_id
      where coalesce(k.first_name, k.last_name) is not null and (k.email is not null or coalesce(k.linkedin, '') <> '')
    union all select date_trunc('week', v.created_at), sg.s, 'verified' from contact_email_verifications v join seg sg on sg.id = v.company_id
      where v.provider_result = 'deliverable' and v.outcome not like 'SKIPPED%'
    union all select date_trunc('week', k.created_at), sg.s, 'linkedin_ready' from contacts k join seg sg on sg.id = k.company_id where coalesce(k.linkedin, '') <> ''
    union all select date_trunc('week', i.occurred_at), sg.s, 'sends' from interactions i join seg sg on sg.id = i.company_id
      where i.direction = 'OUTBOUND' and i.channel <> 'MEETING'
    union all select date_trunc('week', i.occurred_at), sg.s, 'replies' from interactions i join seg sg on sg.id = i.company_id
      where i.direction = 'INBOUND' and i.channel <> 'MEETING'
    union all select date_trunc('week', i.occurred_at), sg.s, 'positive' from interactions i join seg sg on sg.id = i.company_id
      where i.direction = 'INBOUND' and coalesce(i.summary, '') ~ '^(POSITIVE|MEETING_REQUEST|NEEDS_INFO|REFERRAL)'
    union all select date_trunc('week', i.occurred_at), sg.s, 'meetings' from interactions i join seg sg on sg.id = i.company_id where i.channel = 'MEETING'
    union all select date_trunc('week', o.updated_at), sg.s, 'proposals' from opportunities o join seg sg on sg.id = o.company_id
      where o.proposal_value is not null or o.status in ('PROPOSAL', 'NEGOTIATION')
    union all select date_trunc('week', o.won_at), sg.s, 'wins' from opportunities o join seg sg on sg.id = o.company_id where o.won_at is not null),
  rev as (
    select date_trunc('week', p.paid_at) w, sg.s, p.currency, sum(p.amount) amt
    from revenue_payments p join revenue r on r.id = p.revenue_id join seg sg on sg.id = r.company_id group by 1, 2, 3)
  select jsonb_build_object(
    'weeks', (select jsonb_agg(to_char(w, 'DD Mon') order by w) from wk),
    'rows', coalesce((select jsonb_agg(x order by x->>'segment', x->>'week') from (
      select jsonb_build_object('week', to_char(wk.w, 'DD Mon'), 'week_start', wk.w::date, 'segment', s.s,
        'qualified', count(*) filter (where ev.k = 'qualified'), 'contacts', count(*) filter (where ev.k = 'contacts'),
        'verified', count(*) filter (where ev.k = 'verified'), 'linkedin_ready', count(*) filter (where ev.k = 'linkedin_ready'),
        'sends', count(*) filter (where ev.k = 'sends'), 'replies', count(*) filter (where ev.k = 'replies'),
        'positive', count(*) filter (where ev.k = 'positive'), 'meetings', count(*) filter (where ev.k = 'meetings'),
        'proposals', count(*) filter (where ev.k = 'proposals'), 'wins', count(*) filter (where ev.k = 'wins'),
        'revenue', (select jsonb_object_agg(currency, amt) from rev where rev.w = wk.w and rev.s = s.s)) x
      from wk cross join (select distinct s from seg) s left join ev on ev.w = wk.w and ev.s = s.s
      group by wk.w, s.s having count(ev.k) > 0) q), '[]'::jsonb),
    'note', 'Sends/replies are logged interactions (Gmail-tracked email + hand-logged LinkedIn/WhatsApp). Allocation changes are recommendations only.')
$$;

revoke all on function public.queue_health() from public, anon;
revoke all on function public.commercial_weekly_metrics(int) from public, anon;
revoke all on function public.cancel_follow_ups(uuid, text) from public, anon, authenticated;

-- HQ reads both through admin-gated wrappers
create or replace function public.hq_execution()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  return jsonb_build_object('queue', queue_health(), 'weekly', commercial_weekly_metrics(6));
end $$;
revoke all on function public.hq_execution() from public, anon;
grant execute on function public.hq_execution() to authenticated;

-- ---------------------------------------------------------------- 5. prospecting batch loader (service only)
-- Loads researched accounts: company (QUALIFIED with written reason), named person (public source, no email guessed),
-- opportunity (READY when a person exists, else RESEARCHING — never NEW, so workflow 05 never spends Hunter on them)
-- and either a LINKEDIN MESSAGE READY task (note + message) or a CONTACT_RESEARCH task. Skips existing company names.
-- (Applied on 3 Oct 2026 through the SQL runner; see the live definition: public.prospect_batch_load(jsonb, text).)
