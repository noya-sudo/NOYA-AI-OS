-- LinkedIn queue stays in step with the desk (19 Oct 2026). A LinkedIn item can also be handled from Outreach → Needs review
-- (Mark sent, Hold, Reject). The half-hourly sync now mirrors those decisions on the agent's queue, so the LinkedIn view, the
-- Top 5 and the Agents page never show a message as waiting when Adam already sent, held or rejected it.
create or replace function public.linkedin_sync()
returns int language plpgsql security definer set search_path = public as $$
declare d jsonb := outreach_desk(); x jsonb; n int := 0;
begin
  for x in select e from jsonb_array_elements(coalesce(d->'needs_review', '[]'::jsonb)) e
            where e->>'channel' = 'LINKEDIN' and nullif(e->>'contact_id', '') is not null loop
    insert into linkedin_actions (contact_id, company_id, opportunity_id, task_id, candidate_id, director, message, why_them, why_now, project, next_action, source)
    select (x->>'contact_id')::uuid, nullif(x->>'company_id', '')::uuid, nullif(x->>'opportunity_id', '')::uuid, nullif(x->>'task_id', '')::uuid,
           nullif(x->>'candidate_id', '')::uuid, x->>'director', nullif(x->>'draft', ''), nullif(x->>'angle', ''), nullif(x->>'why_now', ''),
           (select coalesce(o.egypt->>'proposed_project', o.angle) from opportunities o where o.id = nullif(x->>'opportunity_id', '')::uuid),
           'Copy the message, open LinkedIn and send it yourself, then press Mark sent. Not connected? Send the connection note instead.', 'DESK'
    on conflict on constraint linkedin_actions_person_opp do update
       set task_id = coalesce(linkedin_actions.task_id, excluded.task_id), candidate_id = coalesce(linkedin_actions.candidate_id, excluded.candidate_id),
           message = coalesce(linkedin_actions.message, excluded.message), why_now = coalesce(linkedin_actions.why_now, excluded.why_now),
           project = coalesce(linkedin_actions.project, excluded.project), updated_at = now()
     where linkedin_actions.state in ('READY', 'HELD');
    n := n + 1;
  end loop;
  -- Decisions taken on the desk: sent by hand, rejected, held or released.
  update linkedin_actions a set state = 'SENT', sent_at = coalesce(t.completed_at, now()), updated_at = now(),
         next_action = 'Waiting for a reply. When they reply, paste it with Log reply.'
    from tasks t where t.id = a.task_id and a.state in ('READY', 'CONNECTED', 'HELD') and t.status = 'COMPLETED';
  update linkedin_actions a set state = 'CLOSED', updated_at = now(), next_action = null, hold_reason = coalesce(a.hold_reason, 'Closed on the desk')
    from tasks t where t.id = a.task_id and a.state in ('READY', 'CONNECTED', 'HELD') and t.status = 'CANCELLED';
  update linkedin_actions a set state = 'HELD', hold_reason = 'Held on the desk', updated_at = now(), next_action = 'On hold: held on the desk'
    from tasks t where t.id = a.task_id and a.state = 'READY' and t.status = 'WAITING';
  update linkedin_actions a set state = 'READY', hold_reason = null, updated_at = now(),
         next_action = 'Copy the message, open LinkedIn and send it yourself, then press Mark sent.'
    from tasks t where t.id = a.task_id and a.state = 'HELD' and a.hold_reason = 'Held on the desk' and t.status in ('OPEN', 'IN_PROGRESS');
  return n;
end $$;
revoke all on function public.linkedin_sync() from public, anon, authenticated;

-- The board carries the contact id so the desk and the LinkedIn view point at the same item.
create or replace function public.linkedin_board()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id, 'state', a.state, 'connection', a.connection, 'person', btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')),
      'first_name', k.first_name, 'role', k.position, 'linkedin', nullif(k.linkedin, ''), 'company', c.name, 'company_id', a.company_id, 'contact_id', a.contact_id,
      'opportunity_id', a.opportunity_id, 'task_id', a.task_id, 'director', a.director, 'project', a.project, 'why_them', a.why_them, 'why_now', a.why_now,
      'relationship', relationship_state(a.company_id), 'message', a.message, 'connection_note', a.connection_note, 'followup', a.followup,
      'next_action', a.next_action, 'sent_at', a.sent_at, 'connection_sent_at', a.connection_sent_at, 'connected_at', a.connected_at,
      'replied_at', a.replied_at, 'reply_text', a.reply_text, 'reply_class', a.reply_class, 'response_draft', a.response_draft,
      'meeting_task_id', a.meeting_task_id, 'hold_reason', a.hold_reason, 'created_at', a.created_at,
      'words', array_length(regexp_split_to_array(btrim(coalesce(a.message, '')), '\s+'), 1))
    order by case a.state when 'REPLIED' then 0 when 'CONNECTED' then 1 when 'READY' then 2 when 'CONNECTION_SENT' then 3 when 'SENT' then 4 when 'MEETING' then 5 else 6 end,
             a.updated_at desc), '[]'::jsonb)
    from linkedin_actions a left join contacts k on k.id = a.contact_id left join companies c on c.id = a.company_id
   where a.state <> 'CLOSED' or a.updated_at > now() - interval '14 days'
$$;
revoke all on function public.linkedin_board() from public, anon, authenticated;
