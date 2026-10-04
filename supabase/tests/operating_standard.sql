-- Operating standard (4 Oct 2026) acceptance check. Runs against live data and rolls itself back (ends in RAISE).
-- Expected (4 Oct 2026):
--   1 restored=1 identity=CONFIRMED                       confirming VERIFY FIRST restores the LinkedIn task
--   2 VERIFY FIRST -- ... / CONTACT_RESEARCH              a READY task for an unconfirmed person is gated on insert
--   3 step2_due_days=6.00                                 follow-up 2 is due 6 days after follow-up 1 is sent
--   4 {"ok": true, "quality": {"status": "PASS", ...}}    playbook outreach passes the quality gate (104 words)
--   5 {"ok": false, "reason": "PERSON_NOT_CONFIRMED"}     no outreach for an unconfirmed person
do $$
declare vt record; n int; k uuid; o uuid; t1 uuid; d timestamptz; r jsonb; msgs text := ''; a record;
begin
  select * into vt from tasks where title like 'VERIFY FIRST --%Amr Gazarin%' and status = 'OPEN' limit 1;
  update tasks set status = 'COMPLETED', completed_at = now() where id = vt.id;
  select count(*) into n from tasks where contact_id = vt.contact_id and status = 'OPEN' and title like 'LINKEDIN MESSAGE READY%' and description not like 'ORIGINAL_TITLE%';
  msgs := msgs || '1 restored=' || n || ' identity=' || (select identity_status from contacts where id = vt.contact_id) || '; ';
  select id into k from contacts where first_name = 'Hannah' and last_name = 'Felt';
  insert into tasks (contact_id, company_id, title, description, task_type, status, priority) values (k, (select company_id from contacts where id = k),
    'LINKEDIN MESSAGE READY -- Quintessentially · Hannah Felt', 'test', 'CONTACT_RESOLUTION', 'OPEN', 70) returning id into t1;
  msgs := msgs || '2 ' || (select title || ' / ' || task_type from tasks where id = t1) || '; ';
  o := 'f343c7b1-16cc-4cd8-bbd3-3cb851aec7a3';
  update tasks set status = 'CANCELLED' where opportunity_id = o and task_type = 'OUTREACH_FOLLOW_UP' and status in ('OPEN','IN_PROGRESS','WAITING');
  insert into tasks (opportunity_id, title, task_type, status, priority, due_at, sequence_step) values (o, 'FOLLOW UP -- TEST (LinkedIn)', 'OUTREACH_FOLLOW_UP', 'OPEN', 70, now(), 1) returning id into t1;
  update tasks set status = 'COMPLETED' where id = t1;
  select due_at into d from tasks where opportunity_id = o and sequence_step = 2 and status = 'OPEN' order by created_at desc limit 1;
  msgs := msgs || '3 step2_due_days=' || coalesce(round(extract(epoch from (d - now())) / 86400.0, 2)::text, 'none') || '; ';
  select * into a from hq_admins limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', a.user_id, 'email', a.email, 'role', 'authenticated')::text, true);
  select id into o from opportunities o2 where product_code is not null and contact_id is not null and status not in ('WON','LOST','ARCHIVED','LONG_TERM')
     and (select identity_status from contacts where id = o2.contact_id) = 'CONFIRMED' and signal_id is not null limit 1;
  r := hq_prepare_outreach(o);
  msgs := msgs || '4 ' || coalesce(r::text, 'null');
  r := hq_prepare_outreach('8af4feda-f793-427d-8a99-33c3b4a2fce0');
  msgs := msgs || ' | 5 ' || r::text;
  raise exception 'TEST RESULT (rolled back): %', msgs;
end $$;
