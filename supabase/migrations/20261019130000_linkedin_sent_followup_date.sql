-- LinkedIn Mark sent (19 Oct 2026): the follow-up date shown on the LinkedIn item is the one actually booked. Every real outbound
-- send books follow-up 1 four days later (the standard rule), so the item now reports that task's date instead of its own guess.
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
    -- The standard rule books follow-up 1 four days after a real send; report the date actually booked.
    select (due_at at time zone 'Africa/Cairo')::date into v_follow from tasks
     where opportunity_id = a.opportunity_id and a.opportunity_id is not null and task_type = 'OUTREACH_FOLLOW_UP' and status = 'OPEN' order by due_at limit 1;
    update linkedin_actions set state = 'SENT', sent_at = now(), updated_at = now(),
           next_action = 'Waiting for a reply.' || coalesce(' Follow-up booked for ' || to_char(v_follow, 'DD Mon') || '.', '') || ' When they reply, paste it with Log reply.' where id = a.id;
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
