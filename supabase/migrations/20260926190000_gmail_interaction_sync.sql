-- NOYA Gmail Interaction Sync (workflow 13).
-- Additive: two new tables, new functions, and two new values on outbound_emails
-- (status DISCARDED, sent_via/sent_at/sent_to_email). Workflow 12 functions are unchanged.
--
-- Workflow 13 only READS Gmail. Every CRM write goes through these functions, which
-- (a) only look at threads/senders NOYA itself emailed after go-live,
-- (b) record each Gmail message id at most once (gmail_sync_ledger primary key),
-- (c) never guess: ambiguous matches and low-confidence classifications become
--     HUMAN_REVIEW tasks instead of status changes.

alter table public.outbound_emails drop constraint outbound_emails_status_check;
alter table public.outbound_emails add constraint outbound_emails_status_check
  check (status in ('APPROVED', 'PROCESSING', 'DRAFTED', 'SENT', 'FAILED', 'DISCARDED'));
alter table public.outbound_emails
  add column if not exists sent_via text check (sent_via in ('EXECUTOR', 'MANUAL_GMAIL')),
  add column if not exists sent_at timestamptz,
  add column if not exists sent_to_email text;

create table if not exists public.gmail_sync_state (
  id smallint primary key default 1 check (id = 1),
  mailbox text not null,
  go_live_at timestamptz not null,
  last_run_at timestamptz,
  last_run_summary jsonb
);

comment on table public.gmail_sync_state is
  'Workflow 13 boundary: Gmail activity before go_live_at is never processed.';

insert into public.gmail_sync_state (id, mailbox, go_live_at)
values (1, 'noya@noyaconcierge.com', '2026-09-26 19:00:00+00')
on conflict (id) do nothing;

create table if not exists public.gmail_sync_ledger (
  gmail_message_id text primary key,
  gmail_thread_id text,
  kind text not null check (kind in ('MANUAL_SEND', 'INBOUND_REPLY')),
  classification text,
  confidence numeric,
  match_method text,
  opportunity_id uuid references public.opportunities(id),
  contact_id uuid references public.contacts(id),
  outbound_email_id uuid references public.outbound_emails(id),
  interaction_id uuid references public.interactions(id),
  task_id uuid references public.tasks(id),
  outcome text not null,
  detail jsonb,
  received_at timestamptz,
  processed_at timestamptz not null default now()
);

comment on table public.gmail_sync_ledger is
  'One row per Gmail message workflow 13 acted on. The primary key is the duplicate guard.';

alter table public.gmail_sync_state enable row level security;
alter table public.gmail_sync_ledger enable row level security;
revoke all on public.gmail_sync_state from anon, authenticated;
revoke all on public.gmail_sync_ledger from anon, authenticated;

-- Threads and senders worth reading: only what NOYA emailed through the approval layer.
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
      select jsonb_agg(distinct o.gmail_thread_id)
      from outbound_emails o
      where o.gmail_thread_id is not null
        and o.status in ('DRAFTED', 'SENT')
        and coalesce(o.sent_at, o.completed_at, o.created_at) > now() - interval '120 days'), '[]'::jsonb),
    'sender_emails', coalesce((
      select jsonb_agg(distinct lower(c.email))
      from outbound_emails o join contacts c on c.id = o.contact_id
      where o.status = 'SENT' and coalesce(btrim(c.email), '') <> ''
        and lower(c.email) <> s.mailbox
        and coalesce(o.sent_at, o.completed_at) > now() - interval '120 days'), '[]'::jsonb)
  )
  from gmail_sync_state s where s.id = 1;
$$;

-- Deterministic labels that must not depend on a model.
create or replace function public.gmail_prelabel(
  p_from text, p_subject text, p_auto_submitted text, p_failed_recipients text)
returns text
language sql
immutable
as $$
  select case
    when coalesce(p_from, '') ~* '^(mailer-daemon|postmaster)@'
      or coalesce(btrim(p_failed_recipients), '') <> ''
      or coalesce(p_subject, '') ~* '(delivery status notification|undeliverable|undelivered mail|delivery has failed|mail delivery (failed|subsystem)|returned mail)'
      then 'BOUNCE'
    when coalesce(p_auto_submitted, '') ~* 'auto-replied'
      or coalesce(p_subject, '') ~* '(out of (the )?office|automatic reply|auto[- ]?reply|autoreply|away from (the )?office|on leave|on vacation)'
      then 'OUT_OF_OFFICE'
    else null
  end;
$$;

-- Thread match first (strong), then bounce recipient, then sender (only if unique).
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

-- An approved Gmail draft that Adam sent by hand: log the real send from Gmail evidence.
create or replace function public.gmail_record_manual_send(
  p_outbound_id uuid, p_gmail_message_id text, p_gmail_thread_id text,
  p_sent_at timestamptz, p_to_emails jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row outbound_emails%rowtype;
  v_company text;
  v_actual_to text;
  v_follow_up timestamptz;
  v_interaction_id uuid;
  v_task_id uuid;
  v_review_id uuid;
begin
  if coalesce(p_gmail_message_id, '') = '' or p_sent_at is null then
    raise exception 'gmail message id and sent time are required';
  end if;
  select * into v_row from outbound_emails where id = p_outbound_id for update;
  if not found or v_row.status <> 'DRAFTED' then
    return jsonb_build_object('ok', false, 'reason', 'NOT_DRAFTED');
  end if;

  insert into gmail_sync_ledger (gmail_message_id, gmail_thread_id, kind, outcome, outbound_email_id,
    opportunity_id, contact_id, received_at)
  values (p_gmail_message_id, p_gmail_thread_id, 'MANUAL_SEND', 'PROCESSING', v_row.id,
    v_row.opportunity_id, v_row.contact_id, p_sent_at)
  on conflict do nothing;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'DUPLICATE_MESSAGE');
  end if;

  v_actual_to := coalesce((select lower(x) from jsonb_array_elements_text(coalesce(p_to_emails, '[]'::jsonb)) x limit 1), v_row.to_email);
  v_follow_up := p_sent_at + interval '4 days';

  select coalesce(o.company_name, c.name) into v_company
  from opportunities o left join companies c on c.id = o.company_id where o.id = v_row.opportunity_id;

  update outbound_emails set status = 'SENT', sent_via = 'MANUAL_GMAIL', sent_at = p_sent_at,
    sent_to_email = v_actual_to, gmail_message_id = p_gmail_message_id,
    gmail_thread_id = p_gmail_thread_id, updated_at = now()
  where id = v_row.id;

  insert into interactions (company_id, contact_id, opportunity_id, channel, direction,
    subject, summary, external_message_id, occurred_at)
  values (v_row.company_id, v_row.contact_id, v_row.opportunity_id, 'EMAIL', 'OUTBOUND', v_row.subject,
    'Approved draft sent manually by Adam from noya@noyaconcierge.com to ' || v_actual_to ||
      '. Logged from Gmail evidence. Gmail thread ' || coalesce(p_gmail_thread_id, 'unknown') || '.',
    p_gmail_message_id, p_sent_at)
  on conflict do nothing
  returning id into v_interaction_id;

  update contacts set status = case when status in ('NEW', 'QUALIFIED', 'OPENED', 'FOLLOW_UP') then 'CONTACTED' else status end,
    last_contact_at = greatest(coalesce(last_contact_at, p_sent_at), p_sent_at),
    next_follow_up_at = v_follow_up, updated_at = now()
  where id = v_row.contact_id;

  update opportunities set
    status = case when status in ('NEW', 'RESEARCHING', 'READY', 'FOLLOW_UP') then 'CONTACTED' else status end,
    approval_status = 'APPROVED',
    next_action = 'Await reply - follow up ' || to_char(v_follow_up at time zone 'Africa/Cairo', 'DD Mon YYYY'),
    updated_at = now()
  where id = v_row.opportunity_id;

  insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type,
    assigned_to, created_by, priority, status, due_at)
  values (v_row.company_id, v_row.contact_id, v_row.opportunity_id,
    'FOLLOW UP -- ' || coalesce(v_company, 'opportunity'),
    'First email sent ' || to_char(p_sent_at at time zone 'Africa/Cairo', 'DD Mon YYYY HH24:MI') || ' Cairo (manual send of approved draft).' || chr(10) ||
    'To: ' || v_actual_to || chr(10) || 'Subject: ' || v_row.subject || chr(10) ||
    'Reply in the same Gmail thread: ' || coalesce(p_gmail_thread_id, 'unknown') || chr(10) ||
    'Skip if a reply has arrived.',
    'OUTREACH_FOLLOW_UP', 'Adam', '13 - NOYA Gmail Interaction Sync v1', 80, 'OPEN', v_follow_up)
  on conflict do nothing
  returning id into v_task_id;

  update tasks set status = 'COMPLETED', completed_at = now(), updated_at = now()
  where opportunity_id = v_row.opportunity_id
    and task_type in ('OUTREACH_DRAFT_READY', 'SALES_OUTREACH_APPROVAL')
    and status in ('OPEN', 'IN_PROGRESS', 'WAITING');

  if v_actual_to <> v_row.to_email then
    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type,
      assigned_to, created_by, priority, status, due_at)
    values (v_row.company_id, v_row.contact_id, v_row.opportunity_id,
      'HUMAN REVIEW -- draft sent to a different address (' || coalesce(v_company, 'opportunity') || ')',
      'Approved recipient: ' || v_row.to_email || chr(10) || 'Actually sent to: ' || v_actual_to || chr(10) ||
      'Update the contact record if the new address is correct.',
      'HUMAN_REVIEW', 'Adam', '13 - NOYA Gmail Interaction Sync v1', 85, 'OPEN', now() + interval '1 day')
    returning id into v_review_id;
  end if;

  insert into approval_audit (opportunity_id, outbound_email_id, action, result, actor, detail)
  values (v_row.opportunity_id, v_row.id, 'MANUAL_SEND_DETECTED', 'SENT', 'n8n-13',
    jsonb_build_object('gmail_message_id', p_gmail_message_id, 'gmail_thread_id', p_gmail_thread_id,
      'sent_at', p_sent_at, 'sent_to', v_actual_to, 'interaction_id', v_interaction_id,
      'follow_up_task_id', v_task_id, 'recipient_changed', v_review_id is not null));

  update gmail_sync_ledger set outcome = 'LOGGED_MANUAL_SEND', interaction_id = v_interaction_id,
    task_id = v_task_id, match_method = 'DRAFT_THREAD'
  where gmail_message_id = p_gmail_message_id;

  return jsonb_build_object('ok', true, 'outbound_id', v_row.id, 'interaction_id', v_interaction_id,
    'follow_up_task_id', v_task_id, 'recipient_changed', v_review_id is not null);
end;
$$;

-- Batch triage of what workflow 13 read from Gmail. Logs manual sends and discarded
-- drafts immediately; returns the inbound messages that need classification.
create or replace function public.gmail_sync_triage(p_mailbox text, p_threads jsonb, p_messages jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s gmail_sync_state%rowtype;
  d outbound_emails%rowtype;
  m jsonb;
  v_sent jsonb;
  v_from text;
  v_match record;
  v_manual jsonb := '[]'::jsonb;
  v_discarded jsonb := '[]'::jsonb;
  v_classify jsonb := '[]'::jsonb;
  v_skipped int := 0;
begin
  select * into s from gmail_sync_state where id = 1;
  if lower(coalesce(p_mailbox, '')) <> s.mailbox then
    raise exception 'wrong mailbox: %', p_mailbox;
  end if;
  p_threads := coalesce(p_threads, '[]'::jsonb);
  p_messages := coalesce(p_messages, '[]'::jsonb);

  -- 1. Approved drafts: sent by Adam, deleted, or still waiting.
  for d in select * from outbound_emails where status = 'DRAFTED' and gmail_thread_id is not null loop
    select x into v_sent
    from jsonb_array_elements(p_messages) x
    where x->>'thread_id' = d.gmail_thread_id
      and (x->'label_ids') ? 'SENT' and not (x->'label_ids') ? 'DRAFT'
      and lower(x->>'from_email') = s.mailbox
      and (x->>'internal_date')::bigint >= (extract(epoch from d.completed_at) * 1000)::bigint - 60000
    order by (x->>'internal_date')::bigint
    limit 1;

    if v_sent is not null then
      v_manual := v_manual || jsonb_build_array(gmail_record_manual_send(d.id, v_sent->>'message_id',
        v_sent->>'thread_id', to_timestamp((v_sent->>'internal_date')::bigint / 1000.0), v_sent->'to_emails'));
    elsif exists (select 1 from jsonb_array_elements(p_threads) t
                  where t->>'thread_id' = d.gmail_thread_id and (t->>'http_status')::int = 404) then
      update outbound_emails set status = 'DISCARDED', error = 'Gmail draft deleted without sending',
        updated_at = now() where id = d.id;
      update tasks set status = 'CANCELLED', updated_at = now()
      where opportunity_id = d.opportunity_id and task_type = 'OUTREACH_DRAFT_READY'
        and status in ('OPEN', 'IN_PROGRESS', 'WAITING');
      update opportunities set next_action = 'Approved Gmail draft was deleted without sending - re-approve if still wanted',
        updated_at = now() where id = d.opportunity_id;
      insert into approval_audit (opportunity_id, outbound_email_id, action, result, actor, detail)
      values (d.opportunity_id, d.id, 'DRAFT_DISCARD_DETECTED', 'DISCARDED', 'n8n-13',
        jsonb_build_object('gmail_thread_id', d.gmail_thread_id));
      v_discarded := v_discarded || jsonb_build_array(d.id);
    end if;
    v_sent := null;
  end loop;

  -- 2. Inbound messages after go-live that match NOYA outreach.
  for m in select * from jsonb_array_elements(p_messages) loop
    v_from := lower(btrim(coalesce(m->>'from_email', '')));
    if v_from = s.mailbox or v_from = ''
       or (m->'label_ids') ? 'DRAFT' or (m->'label_ids') ? 'SENT'
       or to_timestamp((m->>'internal_date')::bigint / 1000.0) < s.go_live_at
       or exists (select 1 from gmail_sync_ledger l where l.gmail_message_id = m->>'message_id') then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    select * into v_match from gmail_match_inbound(m->>'thread_id', v_from, m->>'x_failed_recipients');
    if v_match.method = 'NONE' then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    v_classify := v_classify || jsonb_build_array(m || jsonb_build_object(
      'match_method', v_match.method,
      'prelabel', gmail_prelabel(v_from, m->>'subject', m->>'auto_submitted', m->>'x_failed_recipients')));
  end loop;

  update gmail_sync_state set last_run_at = now(), last_run_summary = jsonb_build_object(
    'threads_read', jsonb_array_length(p_threads), 'messages_read', jsonb_array_length(p_messages),
    'manual_sends_logged', jsonb_array_length(v_manual), 'drafts_discarded', jsonb_array_length(v_discarded),
    'inbound_to_classify', jsonb_array_length(v_classify), 'skipped', v_skipped)
  where id = 1;

  return jsonb_build_object('manual_sends', v_manual, 'discarded', v_discarded, 'to_classify', v_classify);
end;
$$;

-- Apply one classified inbound message. Re-matches server-side; never trusts ids from n8n.
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
  v_locked := v_opp.status in ('PROPOSAL', 'NEGOTIATION', 'WON');

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
    v_task_title := 'HUMAN REVIEW -- reply on late-stage deal ' || v_company;
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
      v_task_desc := v_task_desc || chr(10) || chr(10) || 'Deal is ' || v_opp.status || ': no status was changed automatically.';
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
revoke all on function public.gmail_prelabel(text, text, text, text) from public, anon, authenticated;
revoke all on function public.gmail_match_inbound(text, text, text) from public, anon, authenticated;
revoke all on function public.gmail_record_manual_send(uuid, text, text, timestamptz, jsonb) from public, anon, authenticated;
revoke all on function public.gmail_sync_triage(text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.gmail_ingest_inbound(jsonb) from public, anon, authenticated;
grant execute on function public.gmail_sync_targets() to service_role;
grant execute on function public.gmail_prelabel(text, text, text, text) to service_role;
grant execute on function public.gmail_match_inbound(text, text, text) to service_role;
grant execute on function public.gmail_record_manual_send(uuid, text, text, timestamptz, jsonb) to service_role;
grant execute on function public.gmail_sync_triage(text, jsonb, jsonb) to service_role;
grant execute on function public.gmail_ingest_inbound(jsonb) to service_role;
