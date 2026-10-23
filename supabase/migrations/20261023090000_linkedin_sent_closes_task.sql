-- LinkedIn (frozen) — production defect fix, 23 Oct daily check.
-- Mark sent on a LinkedIn action logged the touch and booked the follow-up but left the action's own task OPEN, because
-- hq_log_touch never completes approval tasks (task_type SALES_OUTREACH_APPROVAL). A message Adam sent on 21 Oct (Colin Cowie)
-- therefore stayed in the Outreach top 5 and in the LinkedIn review count. When a LinkedIn action becomes SENT, its own task is
-- now completed. The cadence triggers on tasks add no second follow-up: one open follow-up per opportunity (unique index), and
-- every LinkedIn action carries an opportunity. Nothing else changes. Includes the one-off repair of the task already sent.
create or replace function public.linkedin_action_sent_task() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.state = 'SENT' and old.state is distinct from 'SENT' and new.task_id is not null then
    update tasks set status = 'COMPLETED', completed_at = now(),
           description = coalesce(description, '') || E'\n\nLinkedIn message sent '
             || to_char(coalesce(new.sent_at, now()) at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ' (marked sent in HQ).'
     where id = new.task_id and status in ('OPEN', 'IN_PROGRESS', 'WAITING');
  end if;
  return new;
end $$;
revoke all on function public.linkedin_action_sent_task() from public, anon, authenticated;

create or replace trigger linkedin_action_sent_task after update of state on public.linkedin_actions
  for each row execute function public.linkedin_action_sent_task();

update tasks t set status = 'COMPLETED', completed_at = now(),
       description = coalesce(t.description, '') || E'\n\nLinkedIn message sent '
         || to_char(la.sent_at at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ' (marked sent in HQ).'
  from linkedin_actions la
 where la.task_id = t.id and la.state = 'SENT' and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING');
