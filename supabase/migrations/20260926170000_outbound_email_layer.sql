-- NOYA controlled outbound email layer.
-- Additive only: new tables, new functions, partial unique indexes on
-- interactions/tasks for rows of new types. No existing column or row is changed.
--
-- Flow: outbound_approve (records Adam's approval, runs every gate)
--     → n8n "12 - NOYA Outbound Email Executor" calls outbound_claim (atomic, exactly once)
--     → Gmail draft or send from noya@noyaconcierge.com
--     → outbound_complete (CRM logging) or outbound_fail.
-- The database row is the only authority to send: the executor webhook accepts
-- nothing but an outbound id, so it cannot be used to email an arbitrary address.

create table if not exists public.outbound_emails (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.opportunities(id),
  contact_id uuid not null references public.contacts(id),
  company_id uuid references public.companies(id),
  mode text not null check (mode in ('DRAFT', 'SEND')),
  status text not null default 'APPROVED'
    check (status in ('APPROVED', 'PROCESSING', 'DRAFTED', 'SENT', 'FAILED')),
  to_email text not null,
  subject text not null check (length(btrim(subject)) > 0),
  body text not null check (length(btrim(body)) > 0),
  human_only boolean not null,
  approved_by text not null,
  approved_at timestamptz not null default now(),
  approval_note text,
  idempotency_key text not null unique,
  gmail_message_id text,
  gmail_thread_id text,
  gmail_draft_id text,
  error text,
  claimed_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.outbound_emails is
  'Approval-gated prospect email queue. One row per explicit Adam approval. Never written by discovery workflows.';

-- One live or completed send per opportunity. A FAILED send frees the slot
-- only for a new explicit approval.
create unique index if not exists outbound_emails_one_send_per_opportunity
  on public.outbound_emails (opportunity_id)
  where mode = 'SEND' and status in ('APPROVED', 'PROCESSING', 'SENT');

create unique index if not exists outbound_emails_gmail_message_id_key
  on public.outbound_emails (gmail_message_id)
  where gmail_message_id is not null;

create table if not exists public.approval_audit (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid references public.opportunities(id),
  outbound_email_id uuid references public.outbound_emails(id),
  action text not null,
  result text not null,
  actor text not null,
  detail jsonb,
  created_at timestamptz not null default now()
);

comment on table public.approval_audit is
  'Append-only log of every approval attempt and outbound state change, including blocked attempts.';

alter table public.outbound_emails enable row level security;
alter table public.approval_audit enable row level security;
revoke all on public.outbound_emails from anon, authenticated;
revoke all on public.approval_audit from anon, authenticated;

-- CRM duplicate guards for the new row types only.
create unique index if not exists interactions_external_message_id_key
  on public.interactions (external_message_id)
  where external_message_id is not null;

create unique index if not exists tasks_one_open_outreach_follow_up
  on public.tasks (opportunity_id)
  where task_type = 'OUTREACH_FOLLOW_UP' and status in ('OPEN', 'IN_PROGRESS', 'WAITING');

create unique index if not exists tasks_one_open_draft_ready
  on public.tasks (opportunity_id)
  where task_type = 'OUTREACH_DRAFT_READY' and status in ('OPEN', 'IN_PROGRESS', 'WAITING');

-- HUMAN_ONLY is decided by workflow 05 and stored in its approval task.
create or replace function public.opportunity_is_human_only(p_opportunity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from tasks t
    where t.opportunity_id = p_opportunity_id
      and t.task_type = 'SALES_OUTREACH_APPROVAL'
      and (t.description ilike '%Outreach mode: HUMAN_ONLY%'
           or t.title ilike 'ADAM PERSONAL%')
  );
$$;

-- Returns the reason a recipient may not be emailed, or null when it may.
create or replace function public.outbound_recipient_block_reason(p_contact_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when c.id is null then 'NO_CONTACT'
    when coalesce(btrim(c.email), '') = '' then 'NO_EMAIL'
    when c.email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then 'MALFORMED_EMAIL'
    when c.do_not_contact then 'DO_NOT_CONTACT'
    when c.status = 'DO_NOT_CONTACT' then 'DO_NOT_CONTACT'
    when c.email_status <> 'VERIFIED' then 'EMAIL_NOT_VERIFIED:' || c.email_status
    else null
  end
  from (select 1) one
  left join contacts c on c.id = p_contact_id;
$$;

create or replace function public.outbound_approve(
  p_opportunity_id uuid,
  p_mode text,
  p_subject text,
  p_body text,
  p_approved_by text,
  p_idempotency_key text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_opp opportunities%rowtype;
  v_contact contacts%rowtype;
  v_block text;
  v_human_only boolean;
  v_existing outbound_emails%rowtype;
  v_id uuid;
begin
  if p_mode not in ('DRAFT', 'SEND') then
    raise exception 'invalid mode %', p_mode;
  end if;
  if coalesce(btrim(p_approved_by), '') = '' or coalesce(btrim(p_idempotency_key), '') = '' then
    raise exception 'approved_by and idempotency_key are required';
  end if;

  -- Same approval submitted twice returns the original row, never a second one.
  select * into v_existing from outbound_emails where idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('ok', true, 'duplicate_request', true,
      'outbound_id', v_existing.id, 'status', v_existing.status);
  end if;

  select * into v_opp from opportunities where id = p_opportunity_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'OPPORTUNITY_NOT_FOUND');
  end if;

  select * into v_contact from contacts where id = v_opp.contact_id;
  v_block := outbound_recipient_block_reason(v_opp.contact_id);
  v_human_only := opportunity_is_human_only(p_opportunity_id);

  if v_block is null and p_mode = 'SEND' and v_human_only then
    v_block := 'HUMAN_ONLY_DRAFT_ONLY';
  end if;
  if v_block is null and p_mode = 'SEND' and exists (
    select 1 from outbound_emails
    where opportunity_id = p_opportunity_id and mode = 'SEND'
      and status in ('APPROVED', 'PROCESSING', 'SENT')) then
    v_block := 'ALREADY_SENT_OR_IN_FLIGHT';
  end if;

  if v_block is not null then
    insert into approval_audit (opportunity_id, action, result, actor, detail)
    values (p_opportunity_id, 'APPROVE_' || p_mode, 'BLOCKED', p_approved_by,
      jsonb_build_object('reason', v_block, 'idempotency_key', p_idempotency_key));
    return jsonb_build_object('ok', false, 'reason', v_block);
  end if;

  insert into outbound_emails (opportunity_id, contact_id, company_id, mode, to_email,
    subject, body, human_only, approved_by, approval_note, idempotency_key)
  values (p_opportunity_id, v_contact.id, coalesce(v_opp.company_id, v_contact.company_id), p_mode,
    lower(btrim(v_contact.email)), btrim(p_subject), p_body, v_human_only,
    p_approved_by, p_note, p_idempotency_key)
  returning id into v_id;

  update opportunities set approval_status = 'APPROVED', updated_at = now()
  where id = p_opportunity_id;

  insert into approval_audit (opportunity_id, outbound_email_id, action, result, actor, detail)
  values (p_opportunity_id, v_id, 'APPROVE_' || p_mode, 'APPROVED', p_approved_by,
    jsonb_build_object('to', lower(btrim(v_contact.email)), 'subject', btrim(p_subject),
      'human_only', v_human_only, 'note', p_note));

  return jsonb_build_object('ok', true, 'outbound_id', v_id, 'mode', p_mode,
    'human_only', v_human_only, 'to_email', lower(btrim(v_contact.email)));
end;
$$;

-- Atomic, exactly-once hand-off to the mailbox executor. Re-runs every gate
-- because the contact may have changed since approval.
create or replace function public.outbound_claim(p_outbound_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row outbound_emails%rowtype;
  v_block text;
begin
  select * into v_row from outbound_emails where id = p_outbound_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'OUTBOUND_NOT_FOUND');
  end if;
  if v_row.status <> 'APPROVED' then
    return jsonb_build_object('ok', false, 'reason', 'ALREADY_PROCESSED', 'status', v_row.status);
  end if;

  v_block := outbound_recipient_block_reason(v_row.contact_id);
  if v_block is null and lower(btrim((select email from contacts where id = v_row.contact_id))) <> v_row.to_email then
    v_block := 'RECIPIENT_CHANGED_SINCE_APPROVAL';
  end if;
  if v_block is null and v_row.mode = 'SEND'
     and (v_row.human_only or opportunity_is_human_only(v_row.opportunity_id)) then
    v_block := 'HUMAN_ONLY_DRAFT_ONLY';
  end if;

  if v_block is not null then
    update outbound_emails set status = 'FAILED', error = 'BLOCKED_AT_CLAIM: ' || v_block,
      completed_at = now(), updated_at = now()
    where id = p_outbound_id;
    insert into approval_audit (opportunity_id, outbound_email_id, action, result, actor, detail)
    values (v_row.opportunity_id, v_row.id, 'CLAIM', 'BLOCKED', 'n8n-12',
      jsonb_build_object('reason', v_block));
    return jsonb_build_object('ok', false, 'reason', v_block);
  end if;

  update outbound_emails set status = 'PROCESSING', claimed_at = now(), updated_at = now()
  where id = p_outbound_id;

  return jsonb_build_object('ok', true, 'outbound_id', v_row.id, 'mode', v_row.mode,
    'to_email', v_row.to_email, 'subject', v_row.subject, 'body', v_row.body);
end;
$$;

create or replace function public.outbound_complete(
  p_outbound_id uuid,
  p_gmail_message_id text,
  p_gmail_thread_id text,
  p_gmail_draft_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row outbound_emails%rowtype;
  v_company text;
  v_follow_up timestamptz := now() + interval '4 days';
  v_interaction_id uuid;
  v_task_id uuid;
begin
  select * into v_row from outbound_emails where id = p_outbound_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'OUTBOUND_NOT_FOUND');
  end if;
  if v_row.status <> 'PROCESSING' then
    return jsonb_build_object('ok', false, 'reason', 'NOT_PROCESSING', 'status', v_row.status);
  end if;
  if coalesce(p_gmail_message_id, '') = '' then
    raise exception 'gmail message id required as provider proof';
  end if;

  select coalesce(o.company_name, c.name) into v_company
  from opportunities o left join companies c on c.id = o.company_id
  where o.id = v_row.opportunity_id;

  if v_row.mode = 'DRAFT' then
    update outbound_emails set status = 'DRAFTED', gmail_message_id = p_gmail_message_id,
      gmail_thread_id = p_gmail_thread_id, gmail_draft_id = p_gmail_draft_id,
      completed_at = now(), updated_at = now()
    where id = p_outbound_id;

    update opportunities set next_action = 'Gmail draft ready in noya@noyaconcierge.com - review and send from Gmail',
      updated_at = now()
    where id = v_row.opportunity_id;

    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type,
      assigned_to, created_by, priority, status, due_at)
    values (v_row.company_id, v_row.contact_id, v_row.opportunity_id,
      'SEND APPROVED DRAFT -- ' || coalesce(v_company, 'opportunity'),
      'Approved draft is waiting in Gmail Drafts (noya@noyaconcierge.com).' || chr(10) ||
      'To: ' || v_row.to_email || chr(10) || 'Subject: ' || v_row.subject || chr(10) ||
      'Gmail draft id: ' || coalesce(p_gmail_draft_id, 'unknown') || chr(10) ||
      'Outbound id: ' || v_row.id,
      'OUTREACH_DRAFT_READY', 'Adam', '12 - NOYA Outbound Email Executor v1', 85, 'OPEN',
      now() + interval '1 day')
    on conflict do nothing
    returning id into v_task_id;

    insert into approval_audit (opportunity_id, outbound_email_id, action, result, actor, detail)
    values (v_row.opportunity_id, v_row.id, 'COMPLETE_DRAFT', 'DRAFTED', 'n8n-12',
      jsonb_build_object('gmail_draft_id', p_gmail_draft_id, 'gmail_message_id', p_gmail_message_id,
        'gmail_thread_id', p_gmail_thread_id));

    return jsonb_build_object('ok', true, 'status', 'DRAFTED', 'task_id', v_task_id);
  end if;

  -- SEND: provider proof received, now record the real send.
  update outbound_emails set status = 'SENT', gmail_message_id = p_gmail_message_id,
    gmail_thread_id = p_gmail_thread_id, completed_at = now(), updated_at = now()
  where id = p_outbound_id;

  insert into interactions (company_id, contact_id, opportunity_id, channel, direction,
    subject, summary, external_message_id, occurred_at)
  values (v_row.company_id, v_row.contact_id, v_row.opportunity_id, 'EMAIL', 'OUTBOUND',
    v_row.subject,
    'Approved outreach sent from noya@noyaconcierge.com to ' || v_row.to_email ||
      '. Gmail thread ' || coalesce(p_gmail_thread_id, 'unknown') ||
      '. Approved by ' || v_row.approved_by || '.',
    p_gmail_message_id, now())
  returning id into v_interaction_id;

  update contacts set status = 'CONTACTED', last_contact_at = now(),
    next_follow_up_at = v_follow_up, updated_at = now()
  where id = v_row.contact_id;

  update opportunities set status = 'CONTACTED', approval_status = 'APPROVED',
    next_action = 'Await reply - follow up ' || to_char(v_follow_up at time zone 'Africa/Cairo', 'DD Mon YYYY'),
    updated_at = now()
  where id = v_row.opportunity_id;

  insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type,
    assigned_to, created_by, priority, status, due_at)
  values (v_row.company_id, v_row.contact_id, v_row.opportunity_id,
    'FOLLOW UP -- ' || coalesce(v_company, 'opportunity'),
    'First email sent ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon YYYY HH24:MI') || ' Cairo.' || chr(10) ||
    'To: ' || v_row.to_email || chr(10) || 'Subject: ' || v_row.subject || chr(10) ||
    'Reply in the same Gmail thread: ' || coalesce(p_gmail_thread_id, 'unknown') || chr(10) ||
    'Skip if a reply has arrived.',
    'OUTREACH_FOLLOW_UP', 'Adam', '12 - NOYA Outbound Email Executor v1', 80, 'OPEN', v_follow_up)
  on conflict do nothing
  returning id into v_task_id;

  -- The approval task is now genuinely done.
  update tasks set status = 'COMPLETED', completed_at = now(), updated_at = now()
  where opportunity_id = v_row.opportunity_id
    and task_type = 'SALES_OUTREACH_APPROVAL'
    and status in ('OPEN', 'IN_PROGRESS', 'WAITING');

  insert into approval_audit (opportunity_id, outbound_email_id, action, result, actor, detail)
  values (v_row.opportunity_id, v_row.id, 'COMPLETE_SEND', 'SENT', 'n8n-12',
    jsonb_build_object('gmail_message_id', p_gmail_message_id, 'gmail_thread_id', p_gmail_thread_id,
      'interaction_id', v_interaction_id, 'follow_up_task_id', v_task_id));

  return jsonb_build_object('ok', true, 'status', 'SENT', 'interaction_id', v_interaction_id,
    'follow_up_task_id', v_task_id, 'follow_up_at', v_follow_up);
end;
$$;

create or replace function public.outbound_fail(p_outbound_id uuid, p_error text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row outbound_emails%rowtype;
begin
  update outbound_emails set status = 'FAILED', error = left(coalesce(p_error, 'unknown'), 2000),
    completed_at = now(), updated_at = now()
  where id = p_outbound_id and status = 'PROCESSING'
  returning * into v_row;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'NOT_PROCESSING');
  end if;
  insert into approval_audit (opportunity_id, outbound_email_id, action, result, actor, detail)
  values (v_row.opportunity_id, v_row.id, 'COMPLETE_' || v_row.mode, 'FAILED', 'n8n-12',
    jsonb_build_object('error', left(coalesce(p_error, 'unknown'), 2000)));
  return jsonb_build_object('ok', true, 'status', 'FAILED');
end;
$$;

-- Server-side only. The future dashboard reaches outbound_approve through an
-- authenticated admin wrapper, never with the service-role key in the browser.
revoke all on function public.opportunity_is_human_only(uuid) from public, anon, authenticated;
revoke all on function public.outbound_recipient_block_reason(uuid) from public, anon, authenticated;
revoke all on function public.outbound_approve(uuid, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.outbound_claim(uuid) from public, anon, authenticated;
revoke all on function public.outbound_complete(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.outbound_fail(uuid, text) from public, anon, authenticated;
grant execute on function public.opportunity_is_human_only(uuid) to service_role;
grant execute on function public.outbound_recipient_block_reason(uuid) to service_role;
grant execute on function public.outbound_approve(uuid, text, text, text, text, text, text) to service_role;
grant execute on function public.outbound_claim(uuid) to service_role;
grant execute on function public.outbound_complete(uuid, text, text, text) to service_role;
grant execute on function public.outbound_fail(uuid, text) to service_role;
