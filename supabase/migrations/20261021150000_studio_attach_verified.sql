-- NOYA Studio — attach the approved PDF to its own Gmail draft, verify it there, then READY TO SEND (Adam, 21 Oct: 1A 2A 3A).
-- Workflow 26 (n8n) calls these two functions with the service role; nothing else can. Supabase decides what may be attached:
-- the latest version, APPROVED, unsent, and exactly the approved PDF (its exact fingerprint, or its render-proof fingerprint,
-- which ignores only the render timestamp), onto the one unsent Gmail draft recorded for that document. The caller never
-- chooses a draft. READY TO SEND is written only after workflow 26 has downloaded the attachment back from the draft and
-- matched it to the approved file. Nothing is sent.

-- 1. Adam's approvals (21 Oct, 2A and 3A) and the render-proof fingerprints. Nado's one-page: the approved file is the one Adam
-- received on 17 Oct (also recorded on its output); the earlier fingerprint on the record was of a later, identical re-render.
-- (Applied as short statements: the Supabase connector drops some long sentences.)
update public.studio_documents set status = 'APPROVED', approved_at = now()
 where ((slug = 'ykone-egypt-brief' and version = 5) or (slug = 'crush-egypt-brief' and version = 3)) and status = 'FOR_REVIEW';
update public.studio_documents set review_notes = review_notes || jsonb_build_array(concat('Approved by Adam, ', '21 Oct 2026: ', 'decision 2A.'))
 where slug = 'ykone-egypt-brief' and version = 5;
update public.studio_documents set review_notes = review_notes || jsonb_build_array(concat('Approved by Adam, ', '21 Oct 2026: ', 'decision 3A.'))
 where slug = 'crush-egypt-brief' and version = 3;
update public.studio_documents set content = content || jsonb_build_object('pdf_fingerprint', case slug
         when 'ykone-egypt-brief' then '31d2ed46d4282b81dd5a03f5722cf092addc3ff8ded364c7f38d3e9cc386d497'
         when 'crush-egypt-brief' then 'acdda96159388d9261be4fabbc82fb46180757633ed0d8a3418890d49fee3ca4'
         else 'b17298a421af68fd4f634708dbb2e3619c530edf6d9c6bccc6e3595d36aec889' end)
 where (slug, version) in (('ykone-egypt-brief', 5), ('crush-egypt-brief', 3), ('nados-forever-is-now-onepage', 1));
update public.studio_documents set content = content || jsonb_build_object('pdf_sha256', '33ef822bbfee8e04b67b853471631fd012df53730f1619f3b664575ba185d3e2')
 where slug = 'nados-forever-is-now-onepage' and version = 1;

-- 2. May this exact PDF go onto this document's own draft? Returns the draft, never takes one.
create or replace function public.studio_attachment_target(p_slug text, p_version integer, p_sha256 text, p_fingerprint text, p_bytes integer)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d studio_documents%rowtype; o studio_outputs%rowtype; n integer;
begin
  select * into d from studio_documents where slug = p_slug and version = p_version;
  if not found then return jsonb_build_object('ok', false, 'reason', 'NO_SUCH_DOCUMENT_VERSION'); end if;
  if p_version < (select max(version) from studio_documents where slug = p_slug) then return jsonb_build_object('ok', false, 'reason', 'NOT_THE_LATEST_VERSION'); end if;
  if d.status is distinct from 'APPROVED' then return jsonb_build_object('ok', false, 'reason', 'NOT_APPROVED'); end if;
  if d.sent_at is not null then return jsonb_build_object('ok', false, 'reason', 'ALREADY_SENT'); end if;
  if coalesce(d.ready_class, '') not in ('READY_FOR_ATTACHMENT', 'READY_TO_SEND') then return jsonb_build_object('ok', false, 'reason', 'NOT_READY_FOR_ATTACHMENT'); end if;
  if (d.content->>'pdf_bytes')::integer is distinct from p_bytes
     or not (d.content->>'pdf_sha256' = p_sha256 or d.content->>'pdf_fingerprint' = p_fingerprint) then
    return jsonb_build_object('ok', false, 'reason', 'NOT_THE_APPROVED_PDF'); end if;
  select count(*) into n from studio_outputs where document_slug = p_slug and status in ('PREPARED', 'HELD') and gmail_draft_id is not null and sent_at is null;
  if n = 0 then return jsonb_build_object('ok', false, 'reason', 'NO_UNSENT_DRAFT_RECORDED'); end if;
  if n > 1 then return jsonb_build_object('ok', false, 'reason', 'MORE_THAN_ONE_DRAFT_RECORDED'); end if;
  select * into o from studio_outputs where document_slug = p_slug and status in ('PREPARED', 'HELD') and gmail_draft_id is not null and sent_at is null;
  return jsonb_build_object('ok', true, 'draft_id', o.gmail_draft_id, 'thread_id', o.gmail_thread_id, 'file_name', d.file_name, 'output_id', o.id, 'email_slug', o.email_slug);
end $$;
revoke all on function public.studio_attachment_target(text, integer, text, text, integer) from public, anon, authenticated;
grant execute on function public.studio_attachment_target(text, integer, text, text, integer) to service_role;

-- 3. The attachment was downloaded back from the draft and matched: record it, and only now READY TO SEND (document and cover email).
create or replace function public.studio_attachment_verified(p_slug text, p_version integer, p_draft_id text, p_message_id text, p_sha256 text, p_fingerprint text, p_bytes integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d studio_documents%rowtype; o studio_outputs%rowtype; v_at timestamptz := now(); v_ev jsonb; v_when text; v_after text;
begin
  select * into d from studio_documents where slug = p_slug and version = p_version;
  if not found or d.status is distinct from 'APPROVED' or d.sent_at is not null then return jsonb_build_object('ok', false, 'reason', 'NOT_APPROVED_OR_ALREADY_SENT'); end if;
  if (d.content->>'pdf_bytes')::integer is distinct from p_bytes
     or not (d.content->>'pdf_sha256' = p_sha256 or d.content->>'pdf_fingerprint' = p_fingerprint) then
    return jsonb_build_object('ok', false, 'reason', 'ATTACHMENT_IS_NOT_THE_APPROVED_PDF'); end if;
  select * into o from studio_outputs where document_slug = p_slug and gmail_draft_id = p_draft_id and status in ('PREPARED', 'HELD') and sent_at is null;
  if not found then return jsonb_build_object('ok', false, 'reason', 'NOT_THIS_DOCUMENTS_DRAFT'); end if;
  v_ev := jsonb_build_object('attachment_verified_at', v_at, 'attachment_draft_id', p_draft_id, 'attachment_message_id', p_message_id,
                             'attachment_sha256', p_sha256, 'attachment_bytes', p_bytes);
  v_when := to_char(v_at at time zone 'Africa/Cairo', 'DD Mon HH24:MI');
  v_after := case when o.send_after > current_date then concat(' Not before ', to_char(o.send_after, 'DD Mon'), ', and only if there is no reply by then.') else '' end;
  update studio_documents set content = content || v_ev, ready_class = 'READY_TO_SEND', ready_checked_at = v_at,
         ready_reason = concat('Approved. The PDF is on the Gmail draft (verified ', v_when, ' Cairo). ', 'Adam sends it from Gmail.', v_after)
   where id = d.id;
  update studio_documents e set content = e.content || v_ev, ready_class = 'READY_TO_SEND', ready_checked_at = v_at,
         ready_reason = concat('Cover email: the approved PDF is on this draft (verified ', v_when, ' Cairo). ', 'Adam sends it from Gmail.', v_after)
   where e.slug = o.email_slug and e.sent_at is null and e.ready_class in ('READY_FOR_ATTACHMENT', 'READY_TO_SEND')
     and e.version = (select max(x.version) from studio_documents x where x.slug = e.slug);
  update studio_outputs set updated_at = v_at,
         evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('attachment', coalesce(evidence->'attachment', '{}'::jsonb) || jsonb_build_object(
           'state', 'ATTACHED_VERIFIED', 'action', 'Open the draft in Gmail and send it yourself', 'verified_at', v_at, 'draft_id', p_draft_id,
           'message_id', p_message_id, 'document', p_slug, 'version', p_version, 'filename', d.file_name, 'pdf_sha256', p_sha256, 'pdf_bytes', p_bytes,
           'how', 'Workflow 26 attached the PDF to this draft, downloaded it back from Gmail and matched it to the approved file'))
   where id = o.id;
  return jsonb_build_object('ok', true, 'verified_at', v_at, 'document', p_slug, 'version', p_version, 'email', o.email_slug, 'draft_id', p_draft_id);
end $$;
revoke all on function public.studio_attachment_verified(text, integer, text, text, text, text, integer) from public, anon, authenticated;
grant execute on function public.studio_attachment_verified(text, integer, text, text, text, text, integer) to service_role;
