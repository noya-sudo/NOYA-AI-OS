-- NOYA HQ V3: Outreach is Adam's commercial approval desk (9 Oct 2026)
-- NEEDS REVIEW · APPROVED / GMAIL DRAFTS · FOLLOW-UPS · SENT · REPLIED · HELD · RESEARCHING, built from the tasks Adam
-- actually acts on (joined to the workflow 18 candidate, the contact, the route contact and the legacy approval), so
-- every counter is the length of the list behind it — nothing hidden, nothing capped.
--   EMAIL in NEEDS REVIEW only with a VALID_VERIFIED recipient; a QA-flagged draft is HELD until Adam edits it.
--   Actions: EDIT (original kept), HOLD / RELEASE, RESEARCH MORE (back to contact / email intelligence, no duplicate
--   company), REJECT (reason kept, company not re-planned for 180 days, research evidence untouched).
--   Follow-ups also start for sends with no CRM opportunity (workflow 18 candidates).

alter table public.outreach_candidates add column if not exists review_action text check (review_action in ('EDITED', 'HELD', 'RESEARCH_MORE', 'REJECTED'));
alter table public.outreach_candidates add column if not exists review_reason text;
alter table public.outreach_candidates add column if not exists reviewed_at timestamptz;
alter table public.companies add column if not exists outreach_hold_until timestamptz;
alter table public.companies add column if not exists outreach_hold_reason text;

-- company_correct() may also set the outreach hold (history kept)
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.company_correct(uuid, text, text, text, text, text)'::regprocedure);
  n := replace(d, $a$'universe_reason', 'notes')$a$, $a$'universe_reason', 'notes', 'outreach_hold_until', 'outreach_hold_reason')$a$);
  n := replace(n, $a$v_type := case when p_field = 'website_confirmed_at' then 'timestamptz' else 'text' end;$a$,
                  $a$v_type := case when p_field in ('website_confirmed_at', 'outreach_hold_until') then 'timestamptz' else 'text' end;$a$);
  if n = d then raise exception 'company_correct patch did not apply'; end if;
  execute n;
  -- the planner never re-plans a company Adam rejected for outreach
  d := pg_get_functiondef('public.commercial_director_plan(boolean,integer,boolean)'::regprocedure);
  n := replace(d, $a$         and relationship_state(c.id) = 'COLD'
         and not exists (select 1 from tasks t where t.company_id = c.id$a$,
                  $a$         and relationship_state(c.id) = 'COLD'
         and coalesce(c.outreach_hold_until, '-infinity'::timestamptz) < now()
         and not exists (select 1 from tasks t where t.company_id = c.id$a$);
  if n = d then raise exception 'planner hold patch did not apply'; end if;
  execute n;
end $patch$;

-- Text helpers for legacy (non-workflow-18) task descriptions.
create or replace function public.task_field(p_desc text, p_label text)
returns text language sql immutable as $$
  select nullif(btrim(substring(coalesce(p_desc, '') from '(?n)^' || p_label || ':\s*(.+)$')), '')
$$;
create or replace function public.task_message(p_desc text)
returns text language sql immutable as $$
  select nullif(btrim(coalesce(
    substring(coalesce(p_desc, '') from '--- CONNECTION NOTE[^\n]*\n(.*?)\n\n--- IF NOT ACCEPTED'),
    substring(coalesce(p_desc, '') from '--- MESSAGE ---\n(.*?)\n\nAfter sending'),
    substring(coalesce(p_desc, '') from '(=== NOYA SALES DRAFT.*)$'))), '')
$$;

-- ---------------------------------------------------------------- the desk
create or replace function public.outreach_desk()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  with
  appr as (  -- legacy opportunity approvals (workflow 05 era): recipient gate and current draft
    select o.id opportunity_id, outbound_recipient_block_reason(o.contact_id) block, hq_current_draft(o.id) draft,
           exists (select 1 from approval_queue_state q where q.opportunity_id = o.id and q.state = 'HOLD') on_hold
      from opportunities o
     where exists (select 1 from tasks t where t.opportunity_id = o.id and t.task_type = 'SALES_OUTREACH_APPROVAL'
                    and t.title ~ '^APPROVE OUTREACH' and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING'))),
  t as (
    select t.id task_id, t.title, t.status, t.task_type, t.description, t.created_by, t.created_at, t.due_at, t.company_id, t.contact_id, t.opportunity_id,
           oc.id cand_id, oc.channel cand_channel, oc.subject cand_subject, oc.draft cand_draft, oc.system_draft, oc.why_now cand_why, oc.evidence cand_evidence, oc.angle cand_angle,
           oc.qa_status, oc.status cand_status, oc.hold_reason, oc.route_contact_id, oc.review_action,
           co.name company, agent_key_of(company_lane(co.acquisition_lane, co.prospect_segment, co.vertical_override, co.company_type), co.company_type, co.notes) director,
           co.partnership_model,
           k.first_name, k.last_name, k.position, k.linkedin, k.instagram, k.phone, k.source_url contact_source, k.identity_status,
           r.email r_email, email_state_v3(r.email, r.email_status, r.email_source_url, r.email_verification_provider) r_state, r.email_source_url r_source, r.position r_label,
           a.block appr_block, a.draft appr_draft, a.on_hold appr_hold,
           case when t.title ~ '^(EMAIL|APPROVE OUTREACH)' then 'EMAIL'
                when t.title ~* 'LINKEDIN' then 'LINKEDIN' when t.title ~* 'INSTAGRAM' then 'INSTAGRAM' when t.title ~* 'WHATSAPP' then 'WHATSAPP'
                when oc.channel is not null then oc.channel else 'EMAIL' end channel
      from tasks t
      left join outreach_candidates oc on oc.task_id = t.id
      left join companies co on co.id = t.company_id
      left join contacts k on k.id = t.contact_id
      left join contacts r on r.id = coalesce(oc.route_contact_id, t.contact_id)
      left join appr a on a.opportunity_id = t.opportunity_id and t.title ~ '^APPROVE OUTREACH'
     where t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
       and t.title ~ '^(EMAIL READY|EMAIL NEEDS VERIFICATION|LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|DRAFT REVIEW|VERIFY FIRST|HOLD - WARM ROUTE|APPROVE OUTREACH|ADAM -- LINKEDIN|ADAM PERSONAL OUTREACH)'),
  b as (
    select t.*,
      case
        when t.title ~ '^DRAFT REVIEW' then 'HELD'
        when t.title ~ '^HOLD - WARM ROUTE' then 'HELD'
        when t.title ~ '^(VERIFY FIRST|EMAIL NEEDS VERIFICATION)' then 'RESEARCHING'
        when t.status = 'WAITING' then 'HELD'
        when t.title ~ '^EMAIL READY' and t.r_state = 'VALID_VERIFIED' then 'NEEDS_REVIEW'
        when t.title ~ '^EMAIL READY' then 'RESEARCHING'
        when t.title ~ '^APPROVE OUTREACH' and t.appr_hold then 'HELD'
        when t.title ~ '^APPROVE OUTREACH' and t.appr_block is null then 'NEEDS_REVIEW'
        when t.title ~ '^APPROVE OUTREACH' then 'RESEARCHING'
        when t.title ~ '^ADAM PERSONAL OUTREACH' and t.contact_id is null then 'RESEARCHING'
        when t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|ADAM -- LINKEDIN|ADAM PERSONAL OUTREACH)' then 'NEEDS_REVIEW'
        else 'RESEARCHING' end bucket,
      case
        when t.title ~ '^DRAFT REVIEW' then 'The draft failed the quality check — edit it, or reject'
        when t.title ~ '^HOLD - WARM ROUTE' then 'A warm route exists: use the relationship, not a cold message'
        when t.title ~ '^VERIFY FIRST' then 'Person or role not confirmed yet'
        when t.title ~ '^EMAIL NEEDS VERIFICATION' then 'Email waiting for SMTP verification (workflow 24)'
        when t.title ~ '^EMAIL READY' and t.r_state <> 'VALID_VERIFIED' then 'Email is ' || lower(replace(t.r_state, '_', ' ')) || ' — not verifiable as valid; use LinkedIn or find another route'
        when t.title ~ '^APPROVE OUTREACH' and t.appr_block is not null then
          case when t.appr_block like 'EMAIL_NOT_VERIFIED%' then 'Email not verified' when t.appr_block = 'NO_CONTACT' then 'No contact person yet' else 'No email on record' end
        when t.title ~ '^ADAM PERSONAL OUTREACH' and t.contact_id is null then 'No contact person yet'
        when t.status = 'WAITING' then coalesce(substring(t.description from '^(?:ON HOLD|HELD)[^\n]*'), 'On hold')
      end reason
    from t),
  items as (
    select b.bucket, b.channel, b.created_at, b.director, b.company,
      jsonb_build_object(
        'ref', b.task_id, 'task_id', b.task_id, 'candidate_id', b.cand_id, 'opportunity_id', b.opportunity_id,
        'bucket', b.bucket, 'channel', b.channel, 'director', b.director, 'company', b.company, 'company_id', b.company_id,
        'contact_id', b.contact_id, 'person', nullif(btrim(coalesce(b.first_name, '') || ' ' || coalesce(b.last_name, '')), ''), 'role', b.position,
        'route', jsonb_build_object('email', case when b.channel = 'EMAIL' then b.r_email end, 'email_state', case when b.channel = 'EMAIL' then b.r_state end,
                                    'email_source', case when b.channel = 'EMAIL' then b.r_source end, 'via_inbox', b.route_contact_id is not null,
                                    'inbox_label', case when b.route_contact_id is not null then b.r_label end,
                                    'linkedin', nullif(b.linkedin, ''), 'instagram', nullif(b.instagram, ''), 'phone', nullif(b.phone, '')),
        'why_now', left(coalesce(b.cand_why, nullif(b.cand_evidence, ''), task_field(b.description, 'WHY THEM'), task_field(b.description, 'Why now')), 300),
        'angle', left(coalesce(b.cand_angle, task_field(b.description, 'ANGLE / OFFER'), task_field(b.description, 'Primary angle')), 300),
        'subject', coalesce(b.cand_subject, b.appr_draft->>'subject'),
        'draft', coalesce(b.cand_draft, b.appr_draft->>'body', task_message(b.description)),
        'original_draft', case when b.system_draft is distinct from b.cand_draft then b.system_draft end,
        'draft_version', (b.appr_draft->>'version')::int,
        'qa', case when b.cand_id is null then null when b.qa_status = 'PASS' then 'PASS' else 'FLAGGED' end,
        'reason', b.reason, 'status', b.status, 'created_at', b.created_at, 'due_at', b.due_at,
        'age_days', floor(extract(epoch from now() - b.created_at) / 86400)::int,
        'approve_via', case when b.bucket <> 'NEEDS_REVIEW' then null
                            when b.title ~ '^APPROVE OUTREACH' then 'OPPORTUNITY_DRAFT'
                            when b.channel = 'EMAIL' and b.cand_id is not null then 'EMAIL_CANDIDATE'
                            when b.channel = 'EMAIL' then null
                            else 'MANUAL_SEND' end,
        'source', jsonb_build_object('person', b.contact_source, 'email', case when b.channel = 'EMAIL' then b.r_source end, 'identity', b.identity_status),
        'tech', jsonb_build_object('title', b.title, 'task_type', b.task_type, 'created_by', b.created_by, 'candidate_status', b.cand_status,
                                   'hold_reason', b.hold_reason)) j
      from b),
  approved as (
    select o.*, co.name company, agent_key_of(company_lane(co.acquisition_lane, co.prospect_segment, co.vertical_override, co.company_type), co.company_type, co.notes) director,
           k.first_name, k.last_name, email_state_v3(k.email, k.email_status, k.email_source_url, k.email_verification_provider) state
      from outbound_emails o left join companies co on co.id = o.company_id left join contacts k on k.id = o.contact_id
     where o.status in ('APPROVED', 'PROCESSING', 'DRAFTED', 'FAILED') or (o.status = 'DISCARDED' and o.updated_at > now() - interval '14 days')),
  fu as (
    select t.*, co.name company, k.first_name, k.last_name, k.position,
           agent_key_of(company_lane(co.acquisition_lane, co.prospect_segment, co.vertical_override, co.company_type), co.company_type, co.notes) director
      from tasks t left join companies co on co.id = t.company_id left join contacts k on k.id = t.contact_id
     where t.task_type = 'OUTREACH_FOLLOW_UP' and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')),
  sent as (
    select i.*, co.name company, k.first_name, k.last_name, k.position,
           agent_key_of(company_lane(co.acquisition_lane, co.prospect_segment, co.vertical_override, co.company_type), co.company_type, co.notes) director
      from interactions i left join companies co on co.id = i.company_id left join contacts k on k.id = i.contact_id
     where i.direction = 'OUTBOUND' and i.occurred_at > now() - interval '60 days'),
  replied as (
    select i.*, co.name company, k.first_name, k.last_name, k.position,
           agent_key_of(company_lane(co.acquisition_lane, co.prospect_segment, co.vertical_override, co.company_type), co.company_type, co.notes) director,
           (select l.classification from gmail_sync_ledger l where l.gmail_message_id = i.external_message_id limit 1) classification
      from interactions i left join companies co on co.id = i.company_id left join contacts k on k.id = i.contact_id
     where i.direction = 'INBOUND' and i.channel <> 'WEBSITE' and i.occurred_at > now() - interval '60 days'),
  researched as (  -- sent back by Adam for more research (desk audit), until the company is planned again
    select a.created_at reviewed_at, a.detail->>'reason' review_reason, t.id task_id, t.title, t.company_id, t.contact_id,
           coalesce((select oc.channel from outreach_candidates oc where oc.task_id = t.id),
                    case when t.title ~* 'linkedin' then 'LINKEDIN' when t.title ~* 'instagram' then 'INSTAGRAM' when t.title ~* 'whatsapp' then 'WHATSAPP' else 'EMAIL' end) channel,
           co.name company, k.first_name, k.last_name, k.position,
           agent_key_of(company_lane(co.acquisition_lane, co.prospect_segment, co.vertical_override, co.company_type), co.company_type, co.notes) director
      from approval_audit a join tasks t on t.id = (a.detail->>'task_id')::uuid
      left join companies co on co.id = t.company_id left join contacts k on k.id = t.contact_id
     where a.action = 'DESK_RESEARCH' and a.created_at > now() - interval '30 days' and t.status = 'CANCELLED'
       and not exists (select 1 from outreach_candidates n where n.company_id = t.company_id and n.created_at > a.created_at)
       and not exists (select 1 from tasks t2 where t2.company_id = t.company_id and t2.created_at > a.created_at and t2.status in ('OPEN', 'IN_PROGRESS', 'WAITING'))),
  rejected as (  -- rejected by Adam on the desk (the company is held from outreach for 180 days)
    select a.created_at reviewed_at, a.detail->>'reason' review_reason, (a.detail->>'candidate_id')::uuid cand_id, t.id task_id, t.company_id,
           coalesce((select oc.channel from outreach_candidates oc where oc.task_id = t.id),
                    case when t.title ~* 'linkedin' then 'LINKEDIN' when t.title ~* 'instagram' then 'INSTAGRAM' when t.title ~* 'whatsapp' then 'WHATSAPP' else 'EMAIL' end) channel,
           co.name company, co.outreach_hold_until, k.first_name, k.last_name,
           agent_key_of(company_lane(co.acquisition_lane, co.prospect_segment, co.vertical_override, co.company_type), co.company_type, co.notes) director
      from approval_audit a join tasks t on t.id = (a.detail->>'task_id')::uuid
      left join companies co on co.id = t.company_id left join contacts k on k.id = t.contact_id
     where a.action = 'DESK_REJECT' and a.created_at > now() - interval '30 days'),
  lists as (
    select
      coalesce((select jsonb_agg(j order by (channel = 'EMAIL') desc, (j->>'candidate_id' is not null) desc, created_at desc) from items where bucket = 'NEEDS_REVIEW'), '[]') needs_review,  -- email first, then quality-gated drafts, newest first
      coalesce((select jsonb_agg(j order by created_at desc) from items where bucket = 'HELD'), '[]') held,
      coalesce((select jsonb_agg(x order by x->>'created_at' desc) from (
          select j x from items where bucket = 'RESEARCHING'
          union all
          select jsonb_build_object('ref', r.task_id, 'task_id', r.task_id, 'bucket', 'RESEARCHING', 'channel', r.channel, 'director', r.director,
                   'company', r.company, 'company_id', r.company_id, 'contact_id', r.contact_id,
                   'person', nullif(btrim(coalesce(r.first_name, '') || ' ' || coalesce(r.last_name, '')), ''), 'role', r.position,
                   'reason', 'Sent back by Adam: ' || coalesce(r.review_reason, 'research more'), 'created_at', r.reviewed_at,
                   'age_days', floor(extract(epoch from now() - r.reviewed_at) / 86400)::int, 'route', '{}'::jsonb)
            from researched r) s), '[]') researching,
      coalesce((select jsonb_agg(jsonb_build_object(
          'ref', a.id, 'outbound_id', a.id, 'candidate_id', a.candidate_id, 'opportunity_id', a.opportunity_id, 'company', a.company, 'company_id', a.company_id,
          'director', a.director, 'person', nullif(btrim(coalesce(a.first_name, '') || ' ' || coalesce(a.last_name, '')), ''), 'to_email', a.to_email,
          'email_state', a.state, 'subject', a.subject, 'status', a.status,
          'gmail_confirmed', a.status = 'DRAFTED' and coalesce(a.gmail_message_id, '') <> '', 'gmail_draft_id', a.gmail_draft_id,
          'gmail_url', case when a.status = 'DRAFTED' then gmail_draft_url(a.gmail_message_id) end,
          'approved_at', a.approved_at, 'drafted_at', a.completed_at, 'error', a.error,
          'can_retry', a.status = 'APPROVED' and a.created_at < now() - interval '2 minutes')
          order by a.created_at desc) from approved a), '[]') approved,
      coalesce((select jsonb_agg(jsonb_build_object(
          'ref', f.id, 'task_id', f.id, 'opportunity_id', f.opportunity_id, 'company', f.company, 'company_id', f.company_id, 'director', f.director,
          'person', nullif(btrim(coalesce(f.first_name, '') || ' ' || coalesce(f.last_name, '')), ''), 'role', f.position,
          'step', coalesce(f.sequence_step, 1), 'due_at', f.due_at, 'overdue', f.due_at < now(), 'title', f.title,
          'channel', case when f.title ~* 'linkedin' then 'LINKEDIN' when f.title ~* 'instagram' then 'INSTAGRAM' else 'EMAIL' end,
          'thread_id', substring(f.description from 'Gmail thread: ([0-9a-f]+)'))
          order by f.due_at nulls last) from fu f), '[]') followups,
      coalesce((select jsonb_agg(jsonb_build_object(
          'ref', s.id, 'company', s.company, 'company_id', s.company_id, 'director', s.director, 'channel', s.channel,
          'person', nullif(btrim(coalesce(s.first_name, '') || ' ' || coalesce(s.last_name, '')), ''), 'role', s.position,
          'subject', s.subject, 'summary', left(s.summary, 240), 'sent_at', s.occurred_at, 'opportunity_id', s.opportunity_id)
          order by s.occurred_at desc) from sent s), '[]') sent,
      coalesce((select jsonb_agg(jsonb_build_object(
          'ref', r.id, 'company', r.company, 'company_id', r.company_id, 'director', r.director, 'channel', r.channel,
          'person', nullif(btrim(coalesce(r.first_name, '') || ' ' || coalesce(r.last_name, '')), ''), 'role', r.position,
          'subject', r.subject, 'summary', left(r.summary, 240), 'received_at', r.occurred_at, 'classification', r.classification,
          'opportunity_id', r.opportunity_id) order by r.occurred_at desc) from replied r), '[]') replied,
      coalesce((select jsonb_agg(jsonb_build_object('ref', x.task_id, 'task_id', x.task_id, 'candidate_id', x.cand_id, 'company', x.company, 'company_id', x.company_id,
          'director', x.director, 'channel', x.channel, 'person', nullif(btrim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '')), ''),
          'reason', x.review_reason, 'rejected_at', x.reviewed_at, 'held_until', x.outreach_hold_until) order by x.reviewed_at desc) from rejected x), '[]') rejected)
  select jsonb_build_object(
    'generated_at', now(),
    'counts', jsonb_build_object(
      'needs_review', jsonb_build_object('total', jsonb_array_length(l.needs_review),
         'EMAIL', (select count(*) from jsonb_array_elements(l.needs_review) e where e->>'channel' = 'EMAIL'),
         'LINKEDIN', (select count(*) from jsonb_array_elements(l.needs_review) e where e->>'channel' = 'LINKEDIN'),
         'INSTAGRAM', (select count(*) from jsonb_array_elements(l.needs_review) e where e->>'channel' = 'INSTAGRAM'),
         'WHATSAPP', (select count(*) from jsonb_array_elements(l.needs_review) e where e->>'channel' = 'WHATSAPP')),
      'approved', jsonb_array_length(l.approved),
      'gmail_drafts_confirmed', (select count(*) from jsonb_array_elements(l.approved) e where (e->>'gmail_confirmed')::boolean),
      'followups', jsonb_array_length(l.followups),
      'followups_due', (select count(*) from jsonb_array_elements(l.followups) e where (e->>'due_at')::timestamptz < now() + interval '1 day'),
      'sent', jsonb_array_length(l.sent), 'replied', jsonb_array_length(l.replied),
      'held', jsonb_array_length(l.held), 'researching', jsonb_array_length(l.researching), 'rejected', jsonb_array_length(l.rejected)),
    'needs_review', l.needs_review, 'approved', l.approved, 'followups', l.followups, 'sent', l.sent, 'replied', l.replied,
    'held', l.held, 'researching', l.researching, 'rejected', l.rejected)
  into v from lists l;
  return v;
end $$;
revoke all on function public.outreach_desk() from public, anon, authenticated;

create or replace function public.hq_outreach_desk()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  return outreach_desk();
end $$;
revoke all on function public.hq_outreach_desk() from public, anon;
grant execute on function public.hq_outreach_desk() to authenticated;

-- ---------------------------------------------------------------- actions
-- HOLD (until a date) / RELEASE / RESEARCH (reason code) / REJECT (reason). Evidence is never deleted.
create or replace function public.hq_outreach_action(p_task uuid, p_action text, p_reason text default null, p_until date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); t tasks%rowtype; oc outreach_candidates%rowtype; v_note text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  select * into t from tasks where id = p_task;
  if t.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if t.status not in ('OPEN', 'IN_PROGRESS', 'WAITING') then return jsonb_build_object('ok', false, 'reason', 'TASK_NOT_OPEN'); end if;
  select * into oc from outreach_candidates where task_id = t.id;
  if p_action in ('RESEARCH', 'REJECT') and v_note is null then return jsonb_build_object('ok', false, 'reason', 'REASON_REQUIRED'); end if;

  if p_action = 'HOLD' then
    update tasks set status = 'WAITING', due_at = coalesce(p_until::timestamptz, now() + interval '7 days'), updated_at = now(),
           description = 'HELD by Adam ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon') || coalesce(': ' || v_note, '') ||
                         coalesce(' (review ' || to_char(p_until, 'DD Mon') || ')', '') || chr(10) || coalesce(description, '')
     where id = t.id;
    if oc.id is not null then
      update outreach_candidates set status = 'HOLD', hold_reason = 'ADAM: ' || coalesce(v_note, 'held'), review_action = 'HELD',
             review_reason = v_note, reviewed_at = now(), updated_at = now() where id = oc.id;
    end if;
  elsif p_action = 'RELEASE' then
    update tasks set status = 'OPEN', due_at = now(), updated_at = now(),
           description = 'RELEASED by Adam ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon') || chr(10) || coalesce(description, '')
     where id = t.id and status = 'WAITING';
    if oc.id is not null and oc.status = 'HOLD' then
      update outreach_candidates set status = case when qa_status = 'PASS' then 'READY' else 'REVIEW_REQUIRED' end, hold_reason = null, updated_at = now() where id = oc.id;
    end if;
  elsif p_action = 'RESEARCH' then
    update tasks set status = 'CANCELLED', updated_at = now(),
           description = 'SENT BACK FOR RESEARCH by Adam ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon') || ': ' || v_note || chr(10) || coalesce(description, '')
     where id = t.id;
    if oc.id is not null then
      update outreach_candidates set review_action = 'RESEARCH_MORE', review_reason = v_note, reviewed_at = now(), updated_at = now() where id = oc.id;
    end if;
    -- back into the contact and email queues (same company, no duplicate)
    update companies set last_enriched_at = null, enrichment_attempts = 0, email_checked_at = null, email_attempts = 0 where id = t.company_id;
    if v_note ~* '^(WRONG_PERSON|OUTDATED_ROLE)' and t.contact_id is not null then
      update contacts set identity_status = 'NEEDS_VERIFICATION', updated_at = now(),
             notes = concat_ws(chr(10), notes, 'Adam ' || to_char(now(), 'DD Mon YYYY') || ': ' || v_note) where id = t.contact_id;
    end if;
  elsif p_action = 'REJECT' then
    update tasks set status = 'CANCELLED', updated_at = now(),
           description = 'REJECTED by Adam ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon') || ': ' || v_note || chr(10) || coalesce(description, '')
     where id = t.id;
    if oc.id is not null then
      update outreach_candidates set review_action = 'REJECTED', review_reason = v_note, reviewed_at = now(), updated_at = now() where id = oc.id;
    end if;
    if t.company_id is not null then
      perform company_correct(t.company_id, 'outreach_hold_until', (now() + interval '180 days')::text, 'Outreach rejected by Adam: ' || v_note, null, v_admin);
      perform company_correct(t.company_id, 'outreach_hold_reason', 'Rejected for outreach ' || to_char(now(), 'DD Mon YYYY') || ': ' || v_note, 'Outreach desk', null, v_admin);
    end if;
  else
    return jsonb_build_object('ok', false, 'reason', 'INVALID_ACTION');
  end if;
  insert into approval_audit (opportunity_id, action, result, actor, detail)
  values (t.opportunity_id, 'DESK_' || p_action, 'DONE', v_admin,
          jsonb_build_object('task_id', t.id, 'candidate_id', oc.id, 'company_id', t.company_id, 'reason', v_note, 'until', p_until));
  return jsonb_build_object('ok', true, 'action', p_action);
end $$;
revoke all on function public.hq_outreach_action(uuid, text, text, date) from public, anon;
grant execute on function public.hq_outreach_action(uuid, text, text, date) to authenticated;

-- EDIT: Adam's subject / message replace the working draft; the original stays (candidate system_* fields, or the audit).
-- A quality-flagged draft Adam has edited goes back to Needs Review (an email only with a verified recipient).
create or replace function public.hq_outreach_edit(p_task uuid, p_subject text, p_body text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); t tasks%rowtype; oc outreach_candidates%rowtype; v_block text; v_title text;
begin
  select * into t from tasks where id = p_task;
  if t.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if t.status not in ('OPEN', 'IN_PROGRESS', 'WAITING') then return jsonb_build_object('ok', false, 'reason', 'TASK_NOT_OPEN'); end if;
  if coalesce(btrim(p_body), '') = '' or length(p_body) > 8000 or length(coalesce(p_subject, '')) > 200 then
    return jsonb_build_object('ok', false, 'reason', 'INVALID_CONTENT'); end if;
  select * into oc from outreach_candidates where task_id = t.id;
  insert into approval_audit (opportunity_id, action, result, actor, detail)
  values (t.opportunity_id, 'DESK_EDIT', 'DONE', v_admin, jsonb_build_object('task_id', t.id, 'candidate_id', oc.id,
          'before', jsonb_build_object('subject', oc.subject, 'draft', coalesce(oc.draft, task_message(t.description))),
          'after', jsonb_build_object('subject', p_subject, 'draft', p_body)));
  if oc.id is not null then
    update outreach_candidates set subject = nullif(btrim(coalesce(p_subject, '')), ''), draft = p_body, review_source = 'HUMAN_REVIEWED',
           review_action = 'EDITED', reviewed_at = now(), updated_at = now(),
           qa_status = case when status = 'REVIEW_REQUIRED' then 'PASS' else qa_status end
     where id = oc.id;
    if t.title ~ '^DRAFT REVIEW' then
      v_block := case when oc.channel = 'EMAIL' then outbound_recipient_block_reason(coalesce(oc.route_contact_id, oc.contact_id)) end;
      v_title := case when oc.channel = 'EMAIL' and v_block is null then 'EMAIL READY'
                      when oc.channel = 'EMAIL' then 'EMAIL NEEDS VERIFICATION'
                      when oc.channel = 'INSTAGRAM' then 'INSTAGRAM DM READY' else 'LINKEDIN MESSAGE READY' end;
      update tasks set title = v_title || substring(title from ' -- .*$'), status = case when v_title = 'EMAIL NEEDS VERIFICATION' then 'WAITING' else 'OPEN' end,
             updated_at = now(), description = 'EDITED by Adam ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || chr(10) || coalesce(description, '')
       where id = t.id;
      update outreach_candidates set status = case when v_title = 'EMAIL NEEDS VERIFICATION' then 'HOLD' else 'READY' end,
             hold_reason = case when v_title = 'EMAIL NEEDS VERIFICATION' then v_block end where id = oc.id;
    end if;
  else
    update tasks set updated_at = now(),
           description = 'EDITED by Adam ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || chr(10) ||
                         coalesce('Subject: ' || nullif(btrim(coalesce(p_subject, '')), '') || chr(10), '') ||
                         '--- MESSAGE ---' || chr(10) || p_body || chr(10) || chr(10) || 'After sending: mark sent.' || chr(10) || chr(10) ||
                         '--- ORIGINAL ---' || chr(10) || coalesce(description, '')
     where id = t.id;
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hq_outreach_edit(uuid, text, text) from public, anon;
grant execute on function public.hq_outreach_edit(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------- follow-ups without a CRM opportunity
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.manual_send_cadence()'::regprocedure);
  n := replace(d, $a$and old.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and new.opportunity_id is not null$a$,
                  $a$and old.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and (new.opportunity_id is not null or new.company_id is not null)$a$);
  n := replace(n, $a$    if not exists (select 1 from interactions i where i.opportunity_id = new.opportunity_id and i.direction = 'OUTBOUND'$a$,
                  $a$    if not exists (select 1 from interactions i where (i.opportunity_id = new.opportunity_id or (new.opportunity_id is null and i.company_id = new.company_id)) and i.direction = 'OUTBOUND'$a$);
  n := replace(n, $a$    if not opportunity_stops_follow_up((select status from opportunities where id = new.opportunity_id)) then$a$,
                  $a$    if not coalesce(opportunity_stops_follow_up((select status from opportunities where id = new.opportunity_id)), false) then$a$);
  if strpos(n, 'new.company_id is not null)') = 0 or strpos(n, 'coalesce(opportunity_stops_follow_up') = 0 then raise exception 'manual_send_cadence patch incomplete'; end if;
  execute n;

  d := pg_get_functiondef('public.follow_up_second_step()'::regprocedure);
  n := replace(d, $a$and new.status = 'COMPLETED' and old.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and new.opportunity_id is not null
     and not opportunity_stops_follow_up((select status from opportunities where id = new.opportunity_id))
     and not exists (select 1 from interactions i where i.opportunity_id = new.opportunity_id and i.direction = 'INBOUND'$a$,
                  $a$and new.status = 'COMPLETED' and old.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and (new.opportunity_id is not null or new.company_id is not null)
     and not coalesce(opportunity_stops_follow_up((select status from opportunities where id = new.opportunity_id)), false)
     and not exists (select 1 from interactions i where (i.opportunity_id = new.opportunity_id or (new.opportunity_id is null and i.company_id = new.company_id)) and i.direction = 'INBOUND'$a$);
  if n = d then raise exception 'follow_up_second_step patch did not apply'; end if;
  execute n;
end $patch$;

-- A reply also stops follow-ups that carry no opportunity (drafter-era tasks keep company and contact only).
create or replace function public.follow_up_cancel_on_reply()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.direction = 'INBOUND' and new.opportunity_id is not null then
    perform cancel_follow_ups(new.opportunity_id, 'reply received (' || coalesce(new.channel, '?') || ')');
  elsif new.direction = 'INBOUND' and coalesce(new.channel, '') <> 'WEBSITE' and (new.company_id is not null or new.contact_id is not null) then
    update tasks set status = 'CANCELLED', updated_at = now(),
           description = coalesce(description, '') || E'\n\nSuperseded ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon YYYY') || ': reply received (' || coalesce(new.channel, '?') || ')'
     where opportunity_id is null and status in ('OPEN', 'IN_PROGRESS', 'WAITING') and task_type = 'OUTREACH_FOLLOW_UP' and title like 'FOLLOW UP%'
       and (company_id = new.company_id or contact_id = new.contact_id);
  end if;
  return new;
end $$;
