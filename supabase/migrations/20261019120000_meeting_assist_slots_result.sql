-- Meeting Assist (19 Oct 2026): meeting_assist_set_slots reported ok=false when the meeting had no LinkedIn item, because it
-- returned FOUND from the second update. It now reports whether the meeting task itself was updated.
create or replace function public.meeting_assist_set_slots(p_task uuid, p_slots jsonb, p_reply text, p_timezone text default 'Europe/London')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ok boolean;
begin
  update tasks set spec = coalesce(spec, '{}'::jsonb) || jsonb_build_object('state', 'SLOTS_PROPOSED', 'slots', p_slots, 'reply', p_reply,
                     'timezone', p_timezone, 'calendar_checked_at', now()),
         description = regexp_replace(coalesce(description, ''), E'\n\nPROPOSED TIMES:.*$', '', 's') || E'\n\nPROPOSED TIMES: ' ||
           (select string_agg(to_char((s->>'start')::timestamptz at time zone p_timezone, 'Dy DD Mon HH24:MI'), ' or ') from jsonb_array_elements(p_slots) s)
           || ' (' || p_timezone || E', checked against Adam''s calendar)\nREPLY: ' || coalesce(p_reply, '')
   where id = p_task and task_type = 'MEETING_ACTION';
  v_ok := found;
  update linkedin_actions set response_draft = coalesce(p_reply, response_draft), updated_at = now() where meeting_task_id = p_task;
  return jsonb_build_object('ok', v_ok);
end $$;
revoke all on function public.meeting_assist_set_slots(uuid, jsonb, text, text) from public, anon, authenticated;
