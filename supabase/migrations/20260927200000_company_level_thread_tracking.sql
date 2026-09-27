-- Company-level outreach threads (a send to a generic company address such as partnerships@,
-- with no verified named contact). Recorded as a MANUAL_SEND ledger row with no contact and no
-- outbound_emails row. Workflow 13 now also reads those threads, and a reply on one is matched
-- to the company and opportunity only (method COMPANY_THREAD, contact left null). Such a reply
-- surfaces to Adam as a task but never changes the opportunity status automatically.
-- No workflow, node or schema change: two read helpers and one guard line.

create or replace function public.gmail_sync_targets()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'mailbox', s.mailbox,
    'go_live_at', s.go_live_at,
    'after_epoch', floor(extract(epoch from s.go_live_at))::bigint,
    'threads', coalesce((
      select jsonb_agg(distinct t.thread_id) from (
        select o.gmail_thread_id as thread_id
        from outbound_emails o
        where o.gmail_thread_id is not null
          and o.status in ('DRAFTED', 'SENT')
          and coalesce(o.sent_at, o.completed_at, o.created_at) > now() - interval '120 days'
        union
        select l.gmail_thread_id
        from gmail_sync_ledger l
        where l.kind = 'MANUAL_SEND' and l.outbound_email_id is null and l.contact_id is null
          and l.opportunity_id is not null and l.gmail_thread_id is not null
          and l.received_at > now() - interval '120 days') t), '[]'::jsonb),
    'sender_emails', coalesce((
      select jsonb_agg(distinct lower(c.email))
      from outbound_emails o join contacts c on c.id = o.contact_id
      where o.status = 'SENT' and coalesce(btrim(c.email), '') <> ''
        and lower(c.email) <> s.mailbox
        and coalesce(o.sent_at, o.completed_at) > now() - interval '120 days'), '[]'::jsonb)
  )
  from gmail_sync_state s where s.id = 1;
$$;

-- Thread match first (strong), then company-level thread, then bounce recipient, then sender (only if unique).
create or replace function public.gmail_match_inbound(
  p_thread_id text, p_from text, p_failed_recipients text)
returns table (method text, opportunity_id uuid, contact_id uuid, company_id uuid, outbound_email_id uuid)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_n int;
begin
  return query
    select 'THREAD'::text, o.opportunity_id, o.contact_id, o.company_id, o.id
    from outbound_emails o
    where o.gmail_thread_id = p_thread_id and o.status = 'SENT'
    order by coalesce(o.sent_at, o.completed_at) desc limit 1;
  if found then return; end if;

  return query
    select 'COMPANY_THREAD'::text, l.opportunity_id, null::uuid, op.company_id, null::uuid
    from gmail_sync_ledger l join opportunities op on op.id = l.opportunity_id
    where l.gmail_thread_id = p_thread_id and l.kind = 'MANUAL_SEND'
      and l.outbound_email_id is null and l.contact_id is null
    order by l.received_at desc limit 1;
  if found then return; end if;

  if coalesce(btrim(p_failed_recipients), '') <> '' then
    select count(distinct o.opportunity_id) into v_n
    from outbound_emails o
    where o.status = 'SENT' and lower(coalesce(o.sent_to_email, o.to_email)) = lower(btrim(p_failed_recipients));
    if v_n = 1 then
      return query
        select 'FAILED_RECIPIENT'::text, o.opportunity_id, o.contact_id, o.company_id, o.id
        from outbound_emails o
        where o.status = 'SENT' and lower(coalesce(o.sent_to_email, o.to_email)) = lower(btrim(p_failed_recipients))
        order by coalesce(o.sent_at, o.completed_at) desc limit 1;
      return;
    elsif v_n > 1 then
      return query select 'AMBIGUOUS'::text, null::uuid, null::uuid, null::uuid, null::uuid;
      return;
    end if;
  end if;

  select count(distinct o.opportunity_id) into v_n
  from outbound_emails o
  join contacts c on c.id = o.contact_id
  join opportunities op on op.id = o.opportunity_id
  where o.status = 'SENT' and lower(c.email) = lower(btrim(p_from))
    and op.status not in ('WON', 'LOST', 'ARCHIVED');
  if v_n = 1 then
    return query
      select 'SENDER'::text, o.opportunity_id, o.contact_id, o.company_id, o.id
      from outbound_emails o
      join contacts c on c.id = o.contact_id
      join opportunities op on op.id = o.opportunity_id
      where o.status = 'SENT' and lower(c.email) = lower(btrim(p_from))
        and op.status not in ('WON', 'LOST', 'ARCHIVED')
      order by coalesce(o.sent_at, o.completed_at) desc limit 1;
  elsif v_n > 1 then
    return query select 'AMBIGUOUS'::text, null::uuid, null::uuid, null::uuid, null::uuid;
  else
    return query select 'NONE'::text, null::uuid, null::uuid, null::uuid, null::uuid;
  end if;
end;
$$;

create or replace function public.gmail_ingest_inbound(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s gmail_sync_state%rowtype;
  v_msg text := p->>'message_id';
  v_from text := lower(btrim(coalesce(p->>'from_email', '')));
  v_received timestamptz := to_timestamp((p->>'internal_date')::bigint / 1000.0);
  v_match record;
  v_pre text;
  v_class text;
  v_conf numeric := coalesce(nullif(p->>'confidence', '')::numeric, 0);
  v_summary text := left(coalesce(nullif(btrim(p->>'summary'), ''), p->>'snippet', ''), 600);
  v_suggested text := left(coalesce(p->>'suggested_reply', ''), 3000);
  v_body text := coalesce(p->>'body_text', '');
  v_date date;
  v_opp opportunities%rowtype;
  v_company text;
  v_locked boolean;
  v_interaction_id uuid;
  v_task_id uuid;
  v_new_contact uuid;
  v_ref_email text := lower(btrim(coalesce(p->>'referred_email', '')));
  v_task_title text;
  v_task_type text;
  v_task_priority int;
  v_task_due timestamptz;
  v_task_desc text;
  v_outcome text;
begin
  select * into s from gmail_sync_state where id = 1;
  if coalesce(v_msg, '') = '' then raise exception 'message_id required'; end if;
  if v_from = s.mailbox or v_received < s.go_live_at then
    return jsonb_build_object('ok', false, 'reason', 'NOT_ELIGIBLE');
  end if;

  insert into gmail_sync_ledger (gmail_message_id, gmail_thread_id, kind, outcome, received_at)
  values (v_msg, p->>'thread_id', 'INBOUND_REPLY', 'PROCESSING', v_received)
  on conflict do nothing;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'DUPLICATE_MESSAGE');
  end if;

  select * into v_match from gmail_match_inbound(p->>'thread_id', v_from, p->>'x_failed_recipients');

  if v_match.method = 'NONE' then
    update gmail_sync_ledger set outcome = 'IGNORED_UNMATCHED', match_method = 'NONE' where gmail_message_id = v_msg;
    return jsonb_build_object('ok', true, 'outcome', 'IGNORED_UNMATCHED');
  end if;

  if v_match.method = 'AMBIGUOUS' then
    insert into tasks (title, description, task_type, assigned_to, created_by, priority, status, due_at)
    values ('HUMAN REVIEW -- email from ' || v_from || ' matches more than one opportunity',
      'From: ' || coalesce(p->>'from_name', '') || ' <' || v_from || '>' || chr(10) ||
      'Subject: ' || coalesce(p->>'subject', '') || chr(10) ||
      'Received: ' || to_char(v_received at time zone 'Africa/Cairo', 'DD Mon YYYY HH24:MI') || ' Cairo' || chr(10) ||
      'Gmail message: ' || v_msg || chr(10) || chr(10) || left(coalesce(p->>'snippet', ''), 500) || chr(10) || chr(10) ||
      'No CRM status was changed. Link this reply to the right opportunity.',
      'HUMAN_REVIEW', 'Adam', '13 - NOYA Gmail Interaction Sync v1', 90, 'OPEN', now() + interval '1 day')
    returning id into v_task_id;
    update gmail_sync_ledger set outcome = 'HUMAN_REVIEW_AMBIGUOUS', match_method = 'AMBIGUOUS', task_id = v_task_id
    where gmail_message_id = v_msg;
    return jsonb_build_object('ok', true, 'outcome', 'HUMAN_REVIEW_AMBIGUOUS', 'task_id', v_task_id);
  end if;

  -- Classification: deterministic labels win; low confidence becomes UNKNOWN.
  v_pre := gmail_prelabel(v_from, p->>'subject', p->>'auto_submitted', p->>'x_failed_recipients');
  v_class := upper(coalesce(p->>'classification', ''));
  if v_pre is not null then
    v_class := v_pre;
  elsif v_class not in ('POSITIVE', 'NEEDS_INFO', 'MEETING_REQUEST', 'NOT_NOW', 'REFERRAL', 'DECLINED',
                        'OUT_OF_OFFICE', 'BOUNCE', 'UNRELATED', 'UNKNOWN') or v_conf < 0.7 then
    v_class := 'UNKNOWN';
  elsif v_class = 'BOUNCE' then
    v_class := 'UNKNOWN'; -- a model may not declare a bounce; only delivery evidence can
  end if;

  begin
    v_date := nullif(p->>'return_date', '')::date;
  exception when others then v_date := null;
  end;
  if v_date is not null and (v_date < current_date or v_date > current_date + 365) then
    v_date := null;
  end if;

  select * into v_opp from opportunities where id = v_match.opportunity_id for update;
  select coalesce(v_opp.company_name, c.name) into v_company from companies c where c.id = v_match.company_id;
  v_company := coalesce(v_company, v_opp.company_name, 'opportunity');
  -- Late-stage deals are never moved automatically.
  v_locked := v_opp.status in ('PROPOSAL', 'NEGOTIATION', 'WON')
    -- A reply on a company-level thread (generic inbox, no named contact) never moves the deal by itself.
    or v_match.method = 'COMPANY_THREAD';

  if v_class in ('POSITIVE', 'NEEDS_INFO', 'MEETING_REQUEST', 'NOT_NOW', 'REFERRAL', 'DECLINED', 'UNKNOWN') then
    insert into interactions (company_id, contact_id, opportunity_id, channel, direction, subject,
      summary, external_message_id, occurred_at)
    values (v_match.company_id, v_match.contact_id, v_match.opportunity_id, 'EMAIL', 'INBOUND', p->>'subject',
      v_class || ': ' || v_summary || ' (from ' || v_from || ')', v_msg, v_received)
    on conflict do nothing
    returning id into v_interaction_id;

    update contacts set last_contact_at = greatest(coalesce(last_contact_at, v_received), v_received), updated_at = now()
    where id = v_match.contact_id;

    -- A reply arrived: the pending follow-up is done.
    update tasks set status = 'COMPLETED', completed_at = now(), updated_at = now()
    where opportunity_id = v_match.opportunity_id and task_type = 'OUTREACH_FOLLOW_UP'
      and status in ('OPEN', 'IN_PROGRESS', 'WAITING');
  end if;

  v_task_desc := 'From: ' || coalesce(p->>'from_name', '') || ' <' || v_from || '>' || chr(10) ||
    'Subject: ' || coalesce(p->>'subject', '') || chr(10) ||
    'Received: ' || to_char(v_received at time zone 'Africa/Cairo', 'DD Mon YYYY HH24:MI') || ' Cairo' || chr(10) ||
    'Classification: ' || v_class || ' (confidence ' || v_conf || ', match ' || v_match.method || ')' || chr(10) ||
    'Gmail thread: ' || coalesce(p->>'thread_id', '') || chr(10) || chr(10) ||
    'Summary: ' || v_summary;

  case v_class
    when 'POSITIVE' then
      if not v_locked then
        update contacts set status = 'INTERESTED' where id = v_match.contact_id;
        update opportunities set status = 'INTERESTED', next_action = 'Positive reply - respond personally', updated_at = now()
        where id = v_match.opportunity_id;
      end if;
      v_task_type := 'REPLY_ACTION'; v_task_priority := 95; v_task_due := now() + interval '4 hours';
      v_task_title := 'POSITIVE REPLY -- ' || v_company;
    when 'MEETING_REQUEST' then
      if not v_locked then
        update contacts set status = 'CALL_REQUIRED' where id = v_match.contact_id;
        update opportunities set status = 'CALL_REQUIRED', next_action = 'Meeting requested - confirm a time', updated_at = now()
        where id = v_match.opportunity_id;
      end if;
      v_task_type := 'MEETING_ACTION'; v_task_priority := 95; v_task_due := now() + interval '4 hours';
      v_task_title := 'MEETING REQUESTED -- ' || v_company;
    when 'NEEDS_INFO' then
      if not v_locked then
        update contacts set status = 'REPLIED' where id = v_match.contact_id;
        update opportunities set next_action = 'Prospect asked for information - approve reply', updated_at = now()
        where id = v_match.opportunity_id;
      end if;
      v_task_type := 'REPLY_ACTION'; v_task_priority := 90; v_task_due := now() + interval '1 day';
      v_task_title := 'INFO REQUESTED -- ' || v_company;
    when 'NOT_NOW' then
      v_task_due := coalesce(v_date::timestamptz, v_received + interval '90 days');
      if not v_locked then
        update contacts set status = 'FOLLOW_UP', next_follow_up_at = v_task_due where id = v_match.contact_id;
        update opportunities set status = 'FOLLOW_UP',
          next_action = 'Not now - revisit ' || to_char(v_task_due at time zone 'Africa/Cairo', 'DD Mon YYYY'), updated_at = now()
        where id = v_match.opportunity_id;
      end if;
      v_task_type := 'OUTREACH_FOLLOW_UP'; v_task_priority := 60;
      v_task_title := 'REVISIT (not now) -- ' || v_company;
    when 'REFERRAL' then
      if not v_locked then
        update contacts set status = 'REPLIED' where id = v_match.contact_id;
        update opportunities set next_action = 'Referred to another contact - review', updated_at = now()
        where id = v_match.opportunity_id;
      end if;
      -- Capture the referred person only when the address literally appears in the email.
      if v_ref_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and position(v_ref_email in lower(v_body)) > 0
         and not exists (select 1 from contacts where lower(email) = v_ref_email) then
        insert into contacts (company_id, first_name, last_name, email, email_status, email_source_url,
          source, status, notes)
        values (v_match.company_id, nullif(split_part(btrim(coalesce(p->>'referred_name', '')), ' ', 1), ''),
          nullif(btrim(substr(btrim(coalesce(p->>'referred_name', '')), length(split_part(btrim(coalesce(p->>'referred_name', '')), ' ', 1)) + 1)), ''),
          v_ref_email, 'UNVERIFIED', 'gmail:' || v_msg, 'REFERRAL', 'NEW',
          'Referred by ' || v_from || ' in reply ' || v_msg || '. Email stated in the reply; not yet verified.')
        returning id into v_new_contact;
      end if;
      v_task_type := 'REPLY_ACTION'; v_task_priority := 85; v_task_due := now() + interval '1 day';
      v_task_title := 'REFERRAL -- ' || v_company;
    when 'DECLINED' then
      if not v_locked then
        if coalesce((p->>'unsubscribe_requested')::boolean, false) then
          update contacts set status = 'DO_NOT_CONTACT', do_not_contact = true where id = v_match.contact_id;
          update opportunities set status = 'LOST', next_action = 'Declined and asked not to be contacted', updated_at = now()
          where id = v_match.opportunity_id;
        elsif upper(coalesce(p->>'decline_type', '')) = 'SOFT' then
          update contacts set status = 'LONG_TERM' where id = v_match.contact_id;
          update opportunities set status = 'LONG_TERM', next_action = 'Declined for now - long-term relationship', updated_at = now()
          where id = v_match.opportunity_id;
        else
          update contacts set status = 'LOST' where id = v_match.contact_id;
          update opportunities set status = 'LOST', next_action = 'Declined', updated_at = now()
          where id = v_match.opportunity_id;
        end if;
      end if;
    when 'OUT_OF_OFFICE' then
      if v_date is not null then
        update tasks set due_at = (v_date + 1)::timestamptz, updated_at = now()
        where opportunity_id = v_match.opportunity_id and task_type = 'OUTREACH_FOLLOW_UP'
          and status in ('OPEN', 'IN_PROGRESS', 'WAITING');
        update contacts set next_follow_up_at = (v_date + 1)::timestamptz where id = v_match.contact_id;
      end if;
    when 'BOUNCE' then
      update contacts set email_status = 'INVALID', updated_at = now()
      where id = v_match.contact_id
        and (v_match.method = 'THREAD' or lower(email) = lower(btrim(coalesce(p->>'x_failed_recipients', ''))));
      update tasks set status = 'CANCELLED', updated_at = now()
      where opportunity_id = v_match.opportunity_id and task_type = 'OUTREACH_FOLLOW_UP'
        and status in ('OPEN', 'IN_PROGRESS', 'WAITING');
      update opportunities set next_action = 'Email bounced - find a working contact', updated_at = now()
      where id = v_match.opportunity_id;
      v_task_type := 'CONTACT_RESOLUTION'; v_task_priority := 80; v_task_due := now() + interval '2 days';
      v_task_title := 'EMAIL BOUNCED -- ' || v_company;
    when 'UNKNOWN' then
      if not v_locked then
        update contacts set status = 'REPLIED' where id = v_match.contact_id and status in ('CONTACTED', 'FOLLOW_UP');
      end if;
      v_task_type := 'HUMAN_REVIEW'; v_task_priority := 90; v_task_due := now() + interval '1 day';
      v_task_title := 'HUMAN REVIEW -- reply from ' || v_company;
    else
      null; -- UNRELATED: recorded in the ledger only
  end case;

  if v_locked and v_task_type is null and v_class not in ('OUT_OF_OFFICE', 'UNRELATED', 'BOUNCE') then
    v_task_type := 'HUMAN_REVIEW'; v_task_priority := 90; v_task_due := now() + interval '1 day';
    v_task_title := case when v_match.method = 'COMPANY_THREAD'
      then 'HUMAN REVIEW -- company-level reply from ' || v_company
      else 'HUMAN REVIEW -- reply on late-stage deal ' || v_company end;
  end if;

  if v_task_type is not null then
    if v_suggested <> '' and v_class in ('POSITIVE', 'NEEDS_INFO', 'MEETING_REQUEST', 'REFERRAL', 'UNKNOWN') then
      v_task_desc := v_task_desc || chr(10) || chr(10) ||
        '--- SUGGESTED REPLY (draft for Adam - NOT sent) ---' || chr(10) || v_suggested;
    end if;
    if v_new_contact is not null then
      v_task_desc := v_task_desc || chr(10) || chr(10) || 'Referred contact captured as UNVERIFIED: ' || v_ref_email;
    end if;
    if v_locked then
      v_task_desc := v_task_desc || chr(10) || chr(10) || case when v_match.method = 'COMPANY_THREAD'
        then 'Company-level thread (no named contact): no status was changed automatically. Link the sender as a contact only once they identify themselves.'
        else 'Deal is ' || v_opp.status || ': no status was changed automatically.' end;
    end if;
    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type,
      assigned_to, created_by, priority, status, due_at)
    values (v_match.company_id, v_match.contact_id, v_match.opportunity_id, v_task_title, v_task_desc,
      v_task_type, 'Adam', '13 - NOYA Gmail Interaction Sync v1', v_task_priority, 'OPEN', v_task_due)
    on conflict do nothing
    returning id into v_task_id;
  end if;

  v_outcome := 'APPLIED_' || v_class;
  update gmail_sync_ledger set classification = v_class, confidence = v_conf, match_method = v_match.method,
    opportunity_id = v_match.opportunity_id, contact_id = v_match.contact_id,
    outbound_email_id = v_match.outbound_email_id, interaction_id = v_interaction_id, task_id = v_task_id,
    outcome = v_outcome,
    detail = jsonb_build_object('from', v_from, 'subject', p->>'subject', 'summary', v_summary,
      'return_date', v_date, 'referred_contact_id', v_new_contact, 'late_stage_locked', v_locked)
  where gmail_message_id = v_msg;

  return jsonb_build_object('ok', true, 'outcome', v_outcome, 'classification', v_class,
    'match_method', v_match.method, 'interaction_id', v_interaction_id, 'task_id', v_task_id,
    'referred_contact_id', v_new_contact);
end;
$$;

revoke all on function public.gmail_sync_targets() from public, anon, authenticated;
revoke all on function public.gmail_match_inbound(text, text, text) from public, anon, authenticated;
revoke all on function public.gmail_ingest_inbound(jsonb) from public, anon, authenticated;
