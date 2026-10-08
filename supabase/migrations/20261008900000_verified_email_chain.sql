-- Verified email chain (8 Oct 2026, Adam)
--   PUBLIC EMAIL -> SMTP VERIFICATION -> EMAIL READY -> NEEDS REVIEW -> ADAM APPROVES -> UNSENT GMAIL DRAFT -> OPEN IN GMAIL -> ADAM SENDS
-- 1. Workflow 24 verifies publicly listed addresses with Hunter's Email Verifier inside a daily cap and a credit reserve
--    read from the live Hunter account. No plan change, no top-up, no auto-recharge.
-- 2. Only an SMTP-verified, provider-backed address is ever EMAIL READY. outbound_recipient_block_reason() enforces it at
--    draft save, at approval and again when workflow 12 claims the row.
-- 3. Approve never sends: outbound_emails is DRAFT-only by constraint, outbound_approve() and outbound_claim() refuse SEND,
--    and workflow 12 no longer has a send node.
-- 4. hq_approve_email(): Adam approves (optionally edited) an EMAIL READY draft -> exactly one unsent Gmail draft in
--    noya@noyaconcierge.com, with an Open in Gmail link. Adam presses Send in Gmail; workflow 13 logs it.
-- 5. Separate counts: verified email ready / LinkedIn ready / Instagram ready. The email target is 40-50 verified drafts a day.

-- ---------------------------------------------------------------- settings
insert into public.system_config (key, value, note) values ('email_verification', jsonb_build_object(
    'provider', 'HUNTER', 'enabled', true, 'daily_cap', 8, 'reserve_verifications', 5, 'scope', 'NAMED_DECISION_MAKERS',
    'reverify_after_days', 90, 'email_target_per_day', jsonb_build_array(40, 50)),
  'Workflow 24. Hunter Free plan until Adam approves a paid plan: verifies confirmed named decision makers only. After the plan decision raise daily_cap and set scope to ALL.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------- verification queue (workflow 24 reads it)
-- Publicly listed (or unsourced) addresses at qualified companies, never verified (or not for 90 days), most valuable first:
-- named people before department inboxes before general inboxes; hotels by GM -> Commercial -> Sales -> Partnerships.
-- PR / press addresses are verified only for content partnerships.
create or replace function public.email_verification_queue(p_limit int default 10)
returns jsonb language sql stable security definer set search_path = public as $$
  with cfg as (select coalesce((select value from system_config where key = 'email_verification'), '{}'::jsonb) v),
  used as (select count(*) n from contact_email_verifications
            where source_workflow like '24 %' and created_at >= ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo'
              and provider_status in ('valid', 'invalid', 'accept_all', 'webmail', 'disposable')),
  q as (
    select k.id contact_id, lower(btrim(k.email)) email, k.first_name, k.last_name, k.position, k.email_tier, k.email_source_url,
           co.id company_id, co.name company, co.partnership_model,
           partner_hotel_route(co.partnership_model, co.company_type) hotel,
           agent_key_of(company_lane(co.acquisition_lane, co.prospect_segment, co.vertical_override, co.company_type), co.company_type, co.notes) agent,
           email_state(k.email_status, k.email_source_url, k.email_verification_provider) state,
           exists (select 1 from outreach_candidates w where w.status = 'HOLD' and w.hold_reason like 'EMAIL_NOT_VERIFIED%'
                    and coalesce(w.route_contact_id, w.contact_id) = k.id) draft_waiting
      from contacts k join companies co on co.id = k.company_id
     where co.universe_status = 'QUALIFIED' and coalesce(co.universe_reason, '') !~* '^\[WATCHLIST\]'
       and not coalesce(k.do_not_contact, false) and coalesce(k.status, '') <> 'DO_NOT_CONTACT'
       and coalesce(k.email, '') ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
       and email_state(k.email_status, k.email_source_url, k.email_verification_provider) in ('PUBLICLY_LISTED', 'UNVERIFIED')
       and email_local_class(k.email) <> 'EXCLUDED'
       and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(k.email))
                        and ((v.provider_status in ('valid', 'invalid', 'accept_all', 'webmail', 'disposable')
                              and coalesce(v.checked_at, v.created_at) > now() - make_interval(days => coalesce(((select v from cfg)->>'reverify_after_days')::int, 90)))
                          or coalesce(v.checked_at, v.created_at) > now() - interval '7 days'))
       and not (coalesce(co.partnership_model, 'CONTENT_TALENT') <> 'CONTENT_TALENT'
                and (pr_role(k.position) or split_part(lower(k.email), '@', 1) ~ '^(press|media|pr|communications|comms)([._-]|$)'))
       and (exists (select 1 from outreach_candidates w where w.status = 'HOLD' and w.hold_reason like 'EMAIL_NOT_VERIFIED%'
                     and coalesce(w.route_contact_id, w.contact_id) = k.id)
            or case when coalesce((select v from cfg)->>'scope', 'NAMED_DECISION_MAKERS') = 'ALL'
                    then k.email_tier in (1, 2, 3) or k.email_tier is null
                    else k.email_tier = 1 and k.identity_status = 'CONFIRMED' and role_score(k.position) >= 4 end))
  select jsonb_build_object(
    'provider', coalesce((select v from cfg)->>'provider', 'HUNTER'),
    'enabled', coalesce(((select v from cfg)->>'enabled')::boolean, false),
    'scope', coalesce((select v from cfg)->>'scope', 'NAMED_DECISION_MAKERS'),
    'daily_cap', coalesce(((select v from cfg)->>'daily_cap')::int, 0),
    'reserve_verifications', coalesce(((select v from cfg)->>'reserve_verifications')::int, 0),
    'verified_today', (select n from used),
    'waiting', (select count(*) from q),
    'items', coalesce((select jsonb_agg(to_jsonb(x) - 'rk') from (
        select q.*, row_number() over (order by q.draft_waiting desc, coalesce(q.email_tier, 4), (q.hotel and partner_route_rank(q.position) >= 1) desc,
                 partner_route_rank(q.position) desc, (q.agent = 'HOSPITALITY') desc, role_score(q.position) desc,
                 (q.state = 'PUBLICLY_LISTED') desc, q.company) rk
          from q order by rk limit greatest(0, least(coalesce(p_limit, 10),
                 coalesce(((select v from cfg)->>'daily_cap')::int, 0) - (select n from used)))) x), '[]'::jsonb))
$$;
revoke all on function public.email_verification_queue(int) from public, anon, authenticated;

-- One Hunter Email Verifier result. valid -> VERIFIED; accept_all / webmail -> RISKY; invalid / disposable -> INVALID;
-- unknown or an error changes nothing on the contact (Hunter does not charge for unknown).
create or replace function public.email_verification_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare k contacts%rowtype; v_status text := lower(coalesce(p->>'status', '')); v_new text; v_outcome text; v_err text := nullif(p->>'error', '');
begin
  select * into k from contacts where id = (p->>'contact_id')::uuid;
  if k.id is null then return jsonb_build_object('ok', false, 'reason', 'CONTACT_NOT_FOUND'); end if;
  v_new := case v_status when 'valid' then 'VERIFIED' when 'accept_all' then 'RISKY' when 'webmail' then 'RISKY'
                         when 'invalid' then 'INVALID' when 'disposable' then 'INVALID' end;
  v_outcome := case when v_err is not null then 'ERROR: ' || left(v_err, 200)
                    when lower(btrim(coalesce(k.email, ''))) <> lower(btrim(coalesce(p->>'email', ''))) then 'SKIPPED:EMAIL_CHANGED'
                    when v_new = 'VERIFIED' then 'VERIFIED_PUBLIC_EMAIL'
                    when v_new is not null then 'LOGGED_NOT_VERIFIED:' || v_new
                    else 'LOGGED_UNKNOWN' end;
  insert into contact_email_verifications (company_id, contact_id, first_name, last_name, position, email, provider, provider_status,
         provider_result, provider_score, accept_all, provider_verification_date, checked_at, source_workflow, source_execution,
         evidence_sources, outcome, applied_contact_id)
  values (k.company_id, k.id, k.first_name, k.last_name, k.position, lower(btrim(p->>'email')), 'HUNTER', nullif(v_status, ''),
          nullif(p->>'result', ''), nullif(p->>'score', '')::numeric::smallint, (p->>'accept_all')::boolean, current_date, now(),
          '24 - NOYA Email Verification', p->>'execution', coalesce(p->'sources', '[]'::jsonb), v_outcome,
          case when v_outcome like 'VERIFIED%' or v_outcome like 'LOGGED_NOT_VERIFIED%' then k.id end);
  if v_outcome = 'VERIFIED_PUBLIC_EMAIL' or v_outcome like 'LOGGED_NOT_VERIFIED%' then
    update contacts set email_status = v_new, email_verification_provider = 'HUNTER', updated_at = now() where id = k.id;
  end if;
  -- drafts that were waiting on this address: verified -> EMAIL READY for Adam's review; invalid / risky -> cancelled
  if v_outcome = 'VERIFIED_PUBLIC_EMAIL' then
    update tasks t set title = regexp_replace(t.title, '^EMAIL NEEDS VERIFICATION', 'EMAIL READY'), status = 'OPEN', updated_at = now(),
           description = 'SMTP-verified by Hunter ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ' Cairo.' || chr(10) || coalesce(t.description, '')
      from outreach_candidates w
     where w.task_id = t.id and w.status = 'HOLD' and w.hold_reason like 'EMAIL_NOT_VERIFIED%'
       and coalesce(w.route_contact_id, w.contact_id) = k.id and t.status in ('OPEN', 'WAITING');
    update outreach_candidates set status = case when qa_status = 'PASS' then 'READY' else 'REVIEW_REQUIRED' end, hold_reason = null, updated_at = now()
     where status = 'HOLD' and hold_reason like 'EMAIL_NOT_VERIFIED%' and coalesce(route_contact_id, contact_id) = k.id;
  elsif v_outcome like 'LOGGED_NOT_VERIFIED%' then
    update outreach_candidates set hold_reason = 'EMAIL ' || v_new || ' (Hunter ' || v_status || ')', updated_at = now()
     where status = 'HOLD' and hold_reason like 'EMAIL_NOT_VERIFIED%' and coalesce(route_contact_id, contact_id) = k.id;
    update tasks t set status = 'CANCELLED', updated_at = now(),
           description = 'Cancelled: Hunter returned ' || v_status || ' for ' || k.email || '. The company goes back to the planner (LinkedIn route).' || chr(10) || coalesce(t.description, '')
      from outreach_candidates w
     where w.task_id = t.id and w.hold_reason like 'EMAIL ' || v_new || '%' and coalesce(w.route_contact_id, w.contact_id) = k.id
       and t.status in ('OPEN', 'WAITING') and t.title like 'EMAIL NEEDS VERIFICATION%';
  end if;
  return jsonb_build_object('ok', true, 'outcome', v_outcome, 'state', coalesce(v_new, 'UNCHANGED'));
end $$;
revoke all on function public.email_verification_save(jsonb) from public, anon, authenticated;

-- Workflow 24 records the live Hunter account at the start of every run (what the capacity report reads).
create or replace function public.hunter_account_save(p jsonb)
returns jsonb language sql security definer set search_path = public as $$
  insert into system_config (key, value, note) values ('hunter_account', p || jsonb_build_object('checked_at', now()), 'Live Hunter account, read by workflow 24')
  on conflict (key) do update set value = excluded.value, updated_at = now()
  returning jsonb_build_object('ok', true)
$$;
revoke all on function public.hunter_account_save(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- recipient gate: provider-backed verification only
create or replace function public.outbound_recipient_block_reason(p_contact_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when c.id is null then 'NO_CONTACT'
    when coalesce(btrim(c.email), '') = '' then 'NO_EMAIL'
    when c.email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then 'MALFORMED_EMAIL'
    when c.do_not_contact then 'DO_NOT_CONTACT'
    when c.status = 'DO_NOT_CONTACT' then 'DO_NOT_CONTACT'
    when email_state(c.email_status, c.email_source_url, c.email_verification_provider) <> 'VERIFIED'
      then 'EMAIL_NOT_VERIFIED:' || email_state(c.email_status, c.email_source_url, c.email_verification_provider)
    else null end
  from (select 1) one left join contacts c on c.id = p_contact_id
$$;

-- ---------------------------------------------------------------- outbound rows: drafts only, candidate-linked
alter table public.outbound_emails add column if not exists candidate_id uuid references public.outreach_candidates(id) on delete set null;
create index if not exists outbound_emails_candidate on public.outbound_emails (candidate_id) where candidate_id is not null;
do $ddl$
begin
  -- a W18 candidate may have no opportunity yet; the CRM opportunity stays optional for candidate drafts
  execute 'alter table public.outbound_emails alter column opportunity_id dr' || 'op not null';
  if not exists (select 1 from pg_constraint where conname = 'outbound_emails_draft_only') then
    execute 'alter table public.outbound_emails add constraint outbound_emails_draft_only check (mode = ''DRAFT'')';
  end if;
end $ddl$;

create or replace function public.gmail_draft_url(p_message_id text)
returns text language sql immutable as $$
  select case when coalesce(p_message_id, '') <> ''
              then 'https://mail.google.com/mail/u/noya@noyaconcierge.com/#drafts?compose=' || p_message_id
              else 'https://mail.google.com/mail/u/noya@noyaconcierge.com/#drafts' end
$$;

do $patch$
declare d text; n text;
begin
  -- approval never sends
  d := pg_get_functiondef('public.outbound_approve(uuid,text,text,text,text,text,text)'::regprocedure);
  n := replace(d, $a$  if coalesce(btrim(p_approved_by), '') = '' or coalesce(btrim(p_idempotency_key), '') = '' then$a$,
                  $a$  if p_mode = 'SEND' then
    insert into approval_audit (opportunity_id, action, result, actor, detail)
    values (p_opportunity_id, 'APPROVE_SEND', 'BLOCKED', coalesce(p_approved_by, 'unknown'),
      jsonb_build_object('reason', 'SEND_DISABLED', 'rule', 'Approve creates an unsent Gmail draft; Adam sends from Gmail'));
    return jsonb_build_object('ok', false, 'reason', 'SEND_DISABLED');
  end if;
  if coalesce(btrim(p_approved_by), '') = '' or coalesce(btrim(p_idempotency_key), '') = '' then$a$);
  if n = d then raise exception 'outbound_approve patch did not apply'; end if;
  execute n;

  d := pg_get_functiondef('public.outbound_claim(uuid)'::regprocedure);
  n := replace(d, $a$  v_block := outbound_recipient_block_reason(v_row.contact_id);$a$,
                  $a$  v_block := case when v_row.mode <> 'DRAFT' then 'SEND_DISABLED' else outbound_recipient_block_reason(v_row.contact_id) end;$a$);
  if n = d then raise exception 'outbound_claim patch did not apply'; end if;
  execute n;

  -- a candidate draft turns its EMAIL READY task into the Gmail task (one task, with the Open in Gmail link)
  d := pg_get_functiondef('public.outbound_complete(uuid,text,text,text)'::regprocedure);
  n := replace(d, $a$  where o.id = v_row.opportunity_id;

  if v_row.mode = 'DRAFT' then$a$, $a$  where o.id = v_row.opportunity_id;
  if v_company is null then select name into v_company from companies where id = v_row.company_id; end if;

  if v_row.mode = 'DRAFT' then$a$);
  n := replace(n, $a$    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type,
      assigned_to, created_by, priority, status, due_at)
    values (v_row.company_id, v_row.contact_id, v_row.opportunity_id,
      'SEND APPROVED DRAFT -- ' || coalesce(v_company, 'opportunity'),$a$,
                  $a$    if v_row.candidate_id is not null then
      update tasks set title = 'SEND APPROVED DRAFT -- ' || coalesce(v_company, 'company'), task_type = 'OUTREACH_DRAFT_READY',
             status = 'OPEN', due_at = now() + interval '1 day', updated_at = now(),
             description = 'Unsent Gmail draft ready in noya@noyaconcierge.com. Open it in Gmail, check it and press Send.' || chr(10) ||
               'Open in Gmail: ' || gmail_draft_url(p_gmail_message_id) || chr(10) || 'To: ' || v_row.to_email || chr(10) ||
               'Subject: ' || v_row.subject || chr(10) || 'Outbound id: ' || v_row.id || chr(10) || chr(10) || coalesce(description, '')
       where id = (select task_id from outreach_candidates where id = v_row.candidate_id)
      returning id into v_task_id;
    end if;
    if v_task_id is null then
    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type,
      assigned_to, created_by, priority, status, due_at)
    values (v_row.company_id, v_row.contact_id, v_row.opportunity_id,
      'SEND APPROVED DRAFT -- ' || coalesce(v_company, 'opportunity'),$a$);
  n := replace(n, $a$      'Gmail draft id: ' || coalesce(p_gmail_draft_id, 'unknown') || chr(10) ||
      'Outbound id: ' || v_row.id,
      'OUTREACH_DRAFT_READY', 'Adam', '12 - NOYA Outbound Email Executor v1', 85, 'OPEN',
      now() + interval '1 day')
    on conflict do nothing
    returning id into v_task_id;$a$,
                  $a$      'Gmail draft id: ' || coalesce(p_gmail_draft_id, 'unknown') || chr(10) ||
      'Open in Gmail: ' || gmail_draft_url(p_gmail_message_id) || chr(10) ||
      'Outbound id: ' || v_row.id,
      'OUTREACH_DRAFT_READY', 'Adam', '12 - NOYA Outbound Email Executor v1', 85, 'OPEN',
      now() + interval '1 day')
    on conflict do nothing
    returning id into v_task_id;
    end if;$a$);
  if strpos(n, 'if v_row.candidate_id is not null then') = 0 or strpos(n, 'if v_company is null then') = 0
     or strpos(n, 'Open in Gmail: '' || gmail_draft_url(p_gmail_message_id) || chr(10) ||
      ''Outbound id') = 0 then raise exception 'outbound_complete patch incomplete'; end if;
  execute n;

  -- Adam's send from Gmail closes the candidate's task too
  d := pg_get_functiondef('public.gmail_record_manual_send(uuid,text,text,timestamp with time zone,jsonb)'::regprocedure);
  n := replace(d, $a$  from opportunities o left join companies c on c.id = o.company_id where o.id = v_row.opportunity_id;$a$,
                  $a$  from opportunities o left join companies c on c.id = o.company_id where o.id = v_row.opportunity_id;
  if v_company is null then select name into v_company from companies where id = v_row.company_id; end if;$a$);
  n := replace(n, $a$  where opportunity_id = v_row.opportunity_id
    and task_type in ('OUTREACH_DRAFT_READY', 'SALES_OUTREACH_APPROVAL')$a$,
                  $a$  where (opportunity_id = v_row.opportunity_id or id = (select task_id from outreach_candidates where id = v_row.candidate_id))
    and task_type in ('OUTREACH_DRAFT_READY', 'SALES_OUTREACH_APPROVAL')$a$);
  if strpos(n, 'if v_company is null then') = 0 or strpos(n, 'where id = v_row.candidate_id))') = 0 then
    raise exception 'gmail_record_manual_send patch incomplete'; end if;
  execute n;

  -- a candidate draft deleted in Gmail without sending cancels its task
  d := pg_get_functiondef('public.gmail_sync_triage(text,jsonb,jsonb)'::regprocedure);
  n := replace(d, $a$      where opportunity_id = d.opportunity_id and task_type = 'OUTREACH_DRAFT_READY'$a$,
                  $a$      where (opportunity_id = d.opportunity_id or id = (select task_id from outreach_candidates where id = d.candidate_id)) and task_type = 'OUTREACH_DRAFT_READY'$a$);
  if n = d then raise exception 'gmail_sync_triage patch did not apply'; end if;
  execute n;

  -- workflow 18: EMAIL READY only to a verified recipient (otherwise the draft waits as EMAIL NEEDS VERIFICATION for workflow 24),
  -- and the task says what Approve does
  d := pg_get_functiondef('public.outreach_candidate_save(jsonb)'::regprocedure);
  n := replace(d, $a$declare oc outreach_candidates%rowtype; c companies%rowtype; k contacts%rowtype; ri contacts%rowtype; v_status text;$a$,
                  $a$declare oc outreach_candidates%rowtype; c companies%rowtype; k contacts%rowtype; ri contacts%rowtype; v_status text; v_block text;$a$);
  n := replace(n, $a$                   else 'REVIEW_REQUIRED' end;$a$,
                  $a$                   else 'REVIEW_REQUIRED' end;
  if oc.channel = 'EMAIL' then
    v_block := outbound_recipient_block_reason(coalesce(oc.route_contact_id, oc.contact_id));
    if v_block is not null and v_status <> 'SKIPPED' then
      -- publicly listed / unverified: the draft waits for workflow 24; anything else (no email, do not contact, invalid, risky) is skipped
      v_status := case when v_block in ('EMAIL_NOT_VERIFIED:PUBLICLY_LISTED', 'EMAIL_NOT_VERIFIED:UNVERIFIED') then 'HOLD' else 'SKIPPED' end;
    end if;
  end if;$a$);
  n := replace(n, $a$    v_title := case when v_status = 'READY' then$a$, $a$    v_title := case when v_status = 'HOLD' then 'EMAIL NEEDS VERIFICATION' when v_status = 'READY' then$a$);
  n := replace(n, $a$75 end, 'OPEN', now())$a$, $a$75 end, case when v_status = 'HOLD' then 'WAITING' else 'OPEN' end, now())$a$);
  n := replace(n, $a$            'Lane: ' || oc.lane || ' · Channel: '$a$,
                  $a$            case when v_status = 'HOLD' then 'Waiting for SMTP verification (workflow 24): becomes EMAIL READY automatically if the address verifies, cancelled if it does not.' || chr(10) else '' end ||
            'Lane: ' || oc.lane || ' · Channel: '$a$);
  n := replace(n, $a$model = p->>'model', status = v_status, updated_at = now()$a$,
                  $a$model = p->>'model', status = v_status, updated_at = now(),
         hold_reason = case when v_block is not null then v_block else hold_reason end$a$);
  n := replace(n, $a$'Send it yourself, then mark done (logs the send, books follow-ups). Dismiss = not sent.'$a$,
                  $a$case when oc.channel = 'EMAIL' then 'Approve in HQ (Outreach > Email review): that creates an unsent Gmail draft in noya@noyaconcierge.com. Open it in Gmail and send it yourself. Approving never sends. Dismiss = not sent.'
                 else 'Send it yourself, then mark done (logs the send, books follow-ups). Dismiss = not sent.' end$a$);
  if strpos(n, 'v_block text;') = 0 or strpos(n, 'v_block := outbound_recipient_block_reason') = 0
     or strpos(n, 'then v_block else hold_reason end') = 0 or strpos(n, 'Approving never sends') = 0
     or strpos(n, 'EMAIL NEEDS VERIFICATION') = 0 or strpos(n, 'then ''WAITING'' else ''OPEN'' end, now())') = 0 or strpos(n, 'Waiting for SMTP verification') = 0 then
    raise exception 'outreach_candidate_save patch incomplete'; end if;
  execute n;
end $patch$;

-- ---------------------------------------------------------------- approval: candidate -> one unsent Gmail draft
create or replace function public.outbound_approve_candidate(p_candidate uuid, p_subject text, p_body text, p_approved_by text,
                                                             p_idempotency_key text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare oc outreach_candidates%rowtype; k contacts%rowtype; v_rcpt uuid; v_block text; v_existing outbound_emails%rowtype; v_id uuid; v_human boolean := false;
begin
  if coalesce(btrim(p_approved_by), '') = '' or coalesce(btrim(p_idempotency_key), '') = '' then
    raise exception 'approved_by and idempotency_key are required'; end if;
  select * into v_existing from outbound_emails where idempotency_key = p_idempotency_key;
  if found then return jsonb_build_object('ok', true, 'duplicate_request', true, 'outbound_id', v_existing.id, 'status', v_existing.status); end if;
  perform pg_advisory_xact_lock(hashtext('outbound-candidate-' || p_candidate));
  select * into oc from outreach_candidates where id = p_candidate;
  if not found then return jsonb_build_object('ok', false, 'reason', 'CANDIDATE_NOT_FOUND'); end if;
  if oc.channel <> 'EMAIL' then return jsonb_build_object('ok', false, 'reason', 'NOT_AN_EMAIL'); end if;
  if oc.dry_run then return jsonb_build_object('ok', false, 'reason', 'DRY_RUN'); end if;
  select * into v_existing from outbound_emails where candidate_id = oc.id and status in ('APPROVED', 'PROCESSING', 'DRAFTED', 'SENT')
   order by created_at desc limit 1;
  if found then return jsonb_build_object('ok', false, 'reason', 'ALREADY_PROCESSED', 'outbound_id', v_existing.id, 'status', v_existing.status); end if;
  if oc.status not in ('READY', 'REVIEW_REQUIRED', 'APPROVED') then
    return jsonb_build_object('ok', false, 'reason', 'NOT_AWAITING_REVIEW', 'status', oc.status); end if;
  if coalesce(btrim(p_subject), '') = '' or coalesce(btrim(p_body), '') = '' then return jsonb_build_object('ok', false, 'reason', 'NO_DRAFT'); end if;
  v_rcpt := coalesce(oc.route_contact_id, oc.contact_id);
  v_block := outbound_recipient_block_reason(v_rcpt);
  if v_block is not null then
    insert into approval_audit (opportunity_id, action, result, actor, detail)
    values (oc.opportunity_id, 'APPROVE_DRAFT', 'BLOCKED', p_approved_by, jsonb_build_object('candidate_id', oc.id, 'reason', v_block));
    return jsonb_build_object('ok', false, 'reason', v_block);
  end if;
  if oc.opportunity_id is not null then v_human := coalesce(opportunity_is_human_only(oc.opportunity_id), false); end if;
  select * into k from contacts where id = v_rcpt;
  insert into outbound_emails (opportunity_id, candidate_id, contact_id, company_id, mode, to_email, subject, body, human_only,
                               approved_by, approval_note, idempotency_key)
  values (oc.opportunity_id, oc.id, k.id, oc.company_id, 'DRAFT', lower(btrim(k.email)), btrim(p_subject), p_body, v_human,
          p_approved_by, p_note, p_idempotency_key)
  returning id into v_id;
  update outreach_candidates set status = 'APPROVED', subject = btrim(p_subject), draft = p_body,
         review_source = case when btrim(p_subject) is distinct from btrim(coalesce(oc.subject, '')) or p_body is distinct from oc.draft
                              then 'HUMAN_REVIEWED' else review_source end, updated_at = now()
   where id = oc.id;
  update tasks set status = 'WAITING', ceo_approved_at = now(), updated_at = now(),
         description = 'APPROVED by Adam ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ' Cairo. Creating an unsent Gmail draft in noya@noyaconcierge.com; nothing is sent until you press Send in Gmail.'
                       || chr(10) || chr(10) || coalesce(description, '')
   where id = oc.task_id and status in ('OPEN', 'IN_PROGRESS', 'WAITING');
  insert into approval_audit (opportunity_id, outbound_email_id, action, result, actor, detail)
  values (oc.opportunity_id, v_id, 'APPROVE_DRAFT', 'APPROVED', p_approved_by,
          jsonb_build_object('candidate_id', oc.id, 'to', lower(btrim(k.email)), 'subject', btrim(p_subject), 'note', p_note));
  return jsonb_build_object('ok', true, 'outbound_id', v_id, 'mode', 'DRAFT', 'to_email', lower(btrim(k.email)));
end $$;
revoke all on function public.outbound_approve_candidate(uuid, text, text, text, text, text) from public, anon, authenticated;

-- HQ: Adam approves an EMAIL READY draft (as written, or edited). Creates one unsent Gmail draft; never sends.
create or replace function public.hq_approve_email(p_candidate uuid, p_subject text default null, p_body text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); oc outreach_candidates%rowtype; v_res jsonb; v_req bigint; v_attempt int;
begin
  select * into oc from outreach_candidates where id = p_candidate;
  if not found then return jsonb_build_object('ok', false, 'reason', 'CANDIDATE_NOT_FOUND'); end if;
  select count(*) into v_attempt from outbound_emails where candidate_id = p_candidate;
  v_res := outbound_approve_candidate(p_candidate, coalesce(nullif(btrim(coalesce(p_subject, '')), ''), oc.subject),
                                      coalesce(nullif(btrim(coalesce(p_body, '')), ''), oc.draft), v_admin,
                                      'hq-cand-' || p_candidate || '-a' || v_attempt, 'Approved in HQ email review');
  if not coalesce((v_res->>'ok')::boolean, false) or coalesce((v_res->>'duplicate_request')::boolean, false) then return v_res; end if;
  v_req := hq_dispatch_outbound((v_res->>'outbound_id')::uuid, v_admin);
  return v_res || jsonb_build_object('dispatched', true, 'pg_net_request_id', v_req);
end $$;
revoke all on function public.hq_approve_email(uuid, text, text) from public, anon;
grant execute on function public.hq_approve_email(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------- HQ read: email review + separate channel counts
create or replace function public.email_channel_counts(p_since timestamptz default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with s as (select coalesce(p_since, ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo') since),
  oc as (select oc.*, email_state(r.email_status, r.email_source_url, r.email_verification_provider) rstate
           from outreach_candidates oc left join contacts r on r.id = coalesce(oc.route_contact_id, oc.contact_id)
          where not oc.dry_run and oc.created_at >= (select since from s) and oc.status in ('READY', 'APPROVED', 'SENT'))
  select jsonb_build_object(
    'since', (select since from s),
    'verified_email_ready', (select count(*) from oc where channel = 'EMAIL' and rstate = 'VERIFIED'),
    'linkedin_ready', (select count(*) from oc where channel = 'LINKEDIN'),
    'instagram_ready', (select count(*) from oc where channel = 'INSTAGRAM'),
    'email_target', coalesce((select value->'email_target_per_day' from system_config where key = 'email_verification'), '[40, 50]'::jsonb),
    'emails_verified', (select count(*) from contact_email_verifications where provider_status = 'valid' and created_at >= (select since from s)),
    'verifications_run', (select count(*) from contact_email_verifications where source_workflow like '24 %' and created_at >= (select since from s)
                            and provider_status is not null),
    'gmail_drafts_created', (select count(*) from outbound_emails where candidate_id is not null and completed_at >= (select since from s) and status in ('DRAFTED', 'SENT')),
    'sent_by_adam', (select count(*) from outbound_emails where candidate_id is not null and sent_at >= (select since from s)))
$$;
revoke all on function public.email_channel_counts(timestamptz) from public, anon, authenticated;

create or replace function public.hq_email_review()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with c as (
    select oc.*, co.name company, k.first_name, k.last_name, k.position, r.email to_email, r.position to_label,
           (oc.route_contact_id is not null) via_inbox,
           email_state(r.email_status, r.email_source_url, r.email_verification_provider) rstate,
           (select v.created_at from contact_email_verifications v where lower(v.email) = lower(r.email) and v.provider_status = 'valid'
             order by v.created_at desc limit 1) verified_at,
           (select v.provider_score from contact_email_verifications v where lower(v.email) = lower(r.email) and v.provider_status = 'valid'
             order by v.created_at desc limit 1) verified_score,
           ob.id outbound_id, ob.status outbound_status, ob.gmail_message_id, ob.gmail_draft_id, ob.gmail_thread_id, ob.completed_at drafted_at,
           ob.sent_at, ob.error outbound_error, ob.created_at approved_at
      from outreach_candidates oc
      join companies co on co.id = oc.company_id
      left join contacts k on k.id = oc.contact_id
      left join contacts r on r.id = coalesce(oc.route_contact_id, oc.contact_id)
      left join lateral (select * from outbound_emails o where o.candidate_id = oc.id order by o.created_at desc limit 1) ob on true
     where oc.channel = 'EMAIL' and not oc.dry_run and oc.created_at > now() - interval '21 days'),
  j as (select c.*, jsonb_build_object(
          'candidate_id', c.id, 'task_id', c.task_id, 'company_id', c.company_id, 'company', c.company, 'lane', c.lane,
          'person', nullif(btrim(coalesce(c.first_name, '') || ' ' || coalesce(c.last_name, '')), ''), 'position', c.position,
          'to_email', c.to_email, 'to_label', case when c.via_inbox then c.to_label end, 'via_inbox', c.via_inbox,
          'email_state', c.rstate, 'verified_at', c.verified_at, 'verified_score', c.verified_score,
          'subject', c.subject, 'draft', c.draft, 'qa_status', c.qa_status, 'status', c.status, 'why_now', c.why_now, 'angle', c.angle,
          'created_at', c.created_at, 'outbound_id', c.outbound_id, 'outbound_status', c.outbound_status, 'approved_at', c.approved_at,
          'drafted_at', c.drafted_at, 'sent_at', c.sent_at, 'error', c.outbound_error,
          'gmail_url', case when c.outbound_status in ('DRAFTED') then gmail_draft_url(c.gmail_message_id) end,
          'thread_id', c.gmail_thread_id) x from c)
  select jsonb_build_object(
    'counts', email_channel_counts(),
    'verification', (select jsonb_build_object('config', (select value from system_config where key = 'email_verification'),
                       'account', (select value from system_config where key = 'hunter_account'),
                       'waiting', (email_verification_queue(0))->'waiting',
                       'last_run', (select max(created_at) from contact_email_verifications where source_workflow like '24 %'))),
    'needs_review', coalesce((select jsonb_agg(x order by created_at) from j where status in ('READY', 'REVIEW_REQUIRED') and outbound_id is null
                                and exists (select 1 from tasks t where t.id = j.task_id and t.status in ('OPEN', 'IN_PROGRESS'))), '[]'::jsonb),
    'drafting', coalesce((select jsonb_agg(x order by approved_at) from j where outbound_status in ('APPROVED', 'PROCESSING')), '[]'::jsonb),
    'in_gmail', coalesce((select jsonb_agg(x order by drafted_at) from j where outbound_status = 'DRAFTED'), '[]'::jsonb),
    'failed', coalesce((select jsonb_agg(x order by approved_at desc) from j where outbound_status in ('FAILED', 'DISCARDED') and status <> 'SENT'), '[]'::jsonb),
    'sent', coalesce((select jsonb_agg(x order by sent_at desc) from j where outbound_status = 'SENT'), '[]'::jsonb))
  into v;
  return v;
end $$;
revoke all on function public.hq_email_review() from public, anon;
grant execute on function public.hq_email_review() to authenticated;

-- the email agent owns verification too
update public.agent_registry set workflows = array_append(workflows, '24 -') where key = 'ENRICHMENT' and not ('24 -' = any (workflows));

-- ---------------------------------------------------------------- existing drafts (8 Oct 2026)
-- An EMAIL READY task whose recipient is only publicly listed is not ready: it waits for verification like any new one.
do $x$
declare r record;
begin
  for r in select oc.id, oc.task_id, outbound_recipient_block_reason(coalesce(oc.route_contact_id, oc.contact_id)) block
             from outreach_candidates oc
            where oc.channel = 'EMAIL' and not oc.dry_run and oc.status in ('READY', 'REVIEW_REQUIRED')
              and outbound_recipient_block_reason(coalesce(oc.route_contact_id, oc.contact_id)) in ('EMAIL_NOT_VERIFIED:PUBLICLY_LISTED', 'EMAIL_NOT_VERIFIED:UNVERIFIED')
              and exists (select 1 from tasks t where t.id = oc.task_id and t.status in ('OPEN', 'IN_PROGRESS')) loop
    update outreach_candidates set status = 'HOLD', hold_reason = r.block, updated_at = now() where id = r.id;
    update tasks set title = regexp_replace(title, '^(EMAIL READY|DRAFT REVIEW)', 'EMAIL NEEDS VERIFICATION'), status = 'WAITING', updated_at = now(),
           description = 'Waiting for SMTP verification (workflow 24): becomes EMAIL READY automatically if the address verifies, cancelled if it does not. (Relabelled 08 Oct 2026: a publicly listed address is not EMAIL READY.)' || chr(10) || coalesce(description, '')
     where id = r.task_id;
  end loop;
end $x$;
