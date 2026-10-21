-- NOYA Studio — READY FOR ATTACHMENT (Adam, 21 Oct): "Never mark READY TO SEND unless the attachment is actually present."
-- Build brief → Quality review → Approved → Gmail draft → PDF attached → READY TO SEND. A client document that travels as a PDF
-- on a Gmail draft is READY_FOR_ATTACHMENT until the attachment has been verified on that draft (content.attachment_verified_at);
-- only then READY_TO_SEND. Its cover email follows it. A guard enforces this whichever script or session writes the class, and
-- the morning board, the next-move baseline and Follow up / Reopen show both states. Nothing is sent.

-- 1. The class.
set local lock_timeout = '5s';
alter table public.studio_documents drop constraint if exists studio_documents_ready_class_check;
alter table public.studio_documents add constraint studio_documents_ready_class_check
  check (ready_class is null or ready_class in ('READY_TO_SEND', 'READY_FOR_ATTACHMENT', 'NEEDS_UPDATE', 'INTERNAL_ONLY', 'SUPERSEDED', 'HOLD')) not valid;
alter table public.studio_documents validate constraint studio_documents_ready_class_check;

-- 2. The guard: a document (or the cover email of a document) with a prepared Gmail draft is not READY_TO_SEND until the PDF is
-- verified on that draft. Re-checked whenever a document's class is written and whenever its output gets a draft.
create or replace function public.studio_attachment_pending(p_slug text, p_stage text) returns boolean
language sql stable set search_path = public as $$
  select exists (select 1 from studio_outputs o
                  where o.status in ('PREPARED', 'HELD') and o.gmail_draft_id is not null and o.document_slug is not null
                    and (o.document_slug = p_slug or (p_stage = 'email' and o.email_slug = p_slug)))
$$;

create or replace function public.studio_ready_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.ready_class = 'READY_TO_SEND' and new.sent_at is null and nullif(new.content->>'attachment_verified_at', '') is null
     and studio_attachment_pending(new.slug, new.stage) then
    new.ready_class := 'READY_FOR_ATTACHMENT';
    new.ready_reason := 'READY TO SEND only once the PDF is verified on the Gmail draft. ' || coalesce(new.ready_reason, '');
  end if;
  return new;
end $$;
create or replace trigger studio_ready_guard before insert or update on public.studio_documents
  for each row execute function public.studio_ready_guard();

create or replace function public.studio_outputs_ready_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  update studio_documents set ready_class = ready_class where ready_class = 'READY_TO_SEND' and slug in (new.document_slug, new.email_slug);
  return null;
end $$;
create or replace trigger studio_outputs_ready_guard after insert or update of gmail_draft_id, status, document_slug, email_slug on public.studio_outputs
  for each row execute function public.studio_outputs_ready_guard();

-- 3. The three documents waiting for their PDF on a Gmail draft (checked in Gmail, 21 Oct: no attachment on any of them), and their
-- cover emails. The PDF's fingerprint is recorded so only that exact file can go on the draft. (Applied as short statements:
-- the Supabase connector drops some long sentences, so the reasons are written with concat.)
update public.studio_documents set ready_class = 'READY_FOR_ATTACHMENT', ready_checked_at = now()
 where slug in ('ykone-egypt-brief', 'ykone-egypt-email', 'crush-egypt-brief', 'crush-egypt-email', 'nados-forever-is-now-onepage', 'nados-forever-is-now-email')
   and ready_class = 'READY_TO_SEND';
update public.studio_documents set content = content || jsonb_build_object('pdf_sha256', '54c72e3708e036f9ed12feb8b2e80ef528aeb211c516937e67a783712757a952', 'pdf_bytes', 1873205)
 where slug = 'ykone-egypt-brief' and version = 5;
update public.studio_documents set content = content || jsonb_build_object('pdf_sha256', '8142d03598f9011b6f6c87f61bddb01a2849e60bb2e87b0d7f5441f18c24d4b5', 'pdf_bytes', 2067855)
 where slug = 'crush-egypt-brief' and version = 3;
update public.studio_documents set content = content || jsonb_build_object('pdf_sha256', '9d566ad460d95570624c0ad09f406f49b1cb06d26975b83ff261d2acbac519c3', 'pdf_bytes', 297496)
 where slug = 'nados-forever-is-now-onepage' and version = 1;
update public.studio_documents set ready_reason = concat('Passed the quality review. ', 'Waiting for your approval. ', 'Then the PDF goes onto the Gmail draft ', 'and is checked there. ', 'READY TO SEND only after that.')
 where slug = 'ykone-egypt-brief' and version = 5;
update public.studio_documents set ready_reason = case slug
  when 'ykone-egypt-email' then concat('Cover email for brief v5, in Gmail. ', 'READY TO SEND once the brief PDF ', 'is verified on this draft.')
  when 'crush-egypt-brief' then concat('Passed the quality review. ', 'For 26 Oct, only if Sophie has not replied. ', 'Waiting for your approval. ', 'Then the PDF goes onto the draft in the CRUSH thread ', 'and is checked there.')
  when 'crush-egypt-email' then concat('Cover email for brief v3 ', '(26 Oct, only if no reply). ', 'READY TO SEND once the PDF ', 'is verified on this draft.')
  when 'nados-forever-is-now-onepage' then concat('Approved. ', 'The PDF goes onto the follow-up draft in the 16 Oct thread ', 'and is checked there. ', 'READY TO SEND only after that.')
  when 'nados-forever-is-now-email' then concat('Cover email for the approved one-page (16 Oct thread). ', 'READY TO SEND once the PDF ', 'is verified on this draft.') end
 where (slug, version) in (('ykone-egypt-email', 4), ('crush-egypt-brief', 3), ('crush-egypt-email', 3), ('nados-forever-is-now-onepage', 1), ('nados-forever-is-now-email', 2));

-- 4. The read models show both states: the morning's Studio documents ready, the next-move baseline and Follow up / Reopen.
do $do$
declare v text; w text;
begin
  v := pg_get_functiondef('public.studio_ready_board()'::regprocedure); w := v;
  v := replace(v, $o$s.ready_class = 'READY_TO_SEND'$o$, $n$s.ready_class in ('READY_TO_SEND', 'READY_FOR_ATTACHMENT')$n$);
  if v = w then raise exception 'studio_ready_board unchanged'; end if;
  execute v;
  v := pg_get_functiondef('public.next_move_baseline(jsonb)'::regprocedure); w := v;
  v := replace(v, $o$x->>'ready_class' = 'READY_TO_SEND'$o$, $n$x->>'ready_class' in ('READY_TO_SEND', 'READY_FOR_ATTACHMENT')$n$);
  if v = w then raise exception 'next_move_baseline unchanged'; end if;
  execute v;
end $do$;

do $do$
declare v text; w text;
begin
  v := pg_get_functiondef('public.follow_up_assess(uuid,uuid,text)'::regprocedure); w := v;
  v := replace(v, $o$d.ready_class = 'READY_TO_SEND' and d.sent_at is null$o$, $n$d.ready_class in ('READY_TO_SEND', 'READY_FOR_ATTACHMENT') and d.sent_at is null$n$);
  v := replace(v, $o$'stage', d.stage, 'ready_reason', d.ready_reason, 'file', d.file_name,$o$,
                  $n$'stage', d.stage, 'status', d.status, 'ready_class', d.ready_class, 'ready_reason', d.ready_reason, 'file', d.file_name,$n$);
  v := replace(v, $o$    v_action := 'Approve and send “' || (v_material->>'title') || '” with its cover email.';$o$,
                  concat($n$    v_action := case when v_material->>'ready_class' = 'READY_TO_SEND' then 'Send “' || (v_material->>'title') || '” from Gmail: $n$, $n$the PDF is on the draft.'$n$,
                         E'\n', $n$                     when v_material->>'status' = 'APPROVED' then '“' || (v_material->>'title') || '” is approved: $n$, $n$the PDF goes onto the Gmail draft and is checked there; then you send.'$n$,
                         E'\n', $n$                     else 'Approve “' || (v_material->>'title') || '”: $n$, $n$the PDF then goes onto the Gmail draft and is checked there; then you send.' end;$n$));
  if v = w or position('the PDF is on the draft' in v) = 0 or position($c$'status', d.status, 'ready_class', d.ready_class$c$ in v) = 0 then
    raise exception 'follow_up_assess patch incomplete'; end if;
  execute v;
end $do$;
