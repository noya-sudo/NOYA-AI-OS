-- NOYA Studio — the handoff on every card (Adam, 21 Oct): RELATIONSHIP → DOCUMENT → PDF → EMAIL DRAFT → ATTACHMENT → SEND.
-- Every external Studio document card shows its real actions: Preview PDF (the exact rendered file), Open email draft (the
-- document's own recorded Gmail draft), Attach to email (workflow 26 attaches this exact approved PDF to that draft, downloads it
-- back and verifies it; only then READY TO SEND) and Open Gmail & send. Nothing sends automatically: Adam presses Send in Gmail.
-- Built from what exists: Supabase Storage for the file, pg_net + the vault (as workflow 14's wake) to call workflow 26, and the
-- 20261021150000 attachment checks.

-- 1. One private home for each document's PDF: studio-pdfs/<slug>/v<version>.pdf. HQ admins read and upload; n8n uses the
-- service role. Nobody else can see it.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('studio-pdfs', 'studio-pdfs', false, 8388608, array['application/pdf']) on conflict (id) do nothing;

create or replace function public.hq_is_admin() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin perform hq_admin_email(); return true; exception when others then return false; end $$;
revoke all on function public.hq_is_admin() from public, anon;
grant execute on function public.hq_is_admin() to authenticated, service_role;

create policy studio_pdfs_admin_read on storage.objects for select to authenticated
  using (bucket_id = 'studio-pdfs' and public.hq_is_admin());
create policy studio_pdfs_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'studio-pdfs' and public.hq_is_admin());
create policy studio_pdfs_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'studio-pdfs' and public.hq_is_admin()) with check (bucket_id = 'studio-pdfs' and public.hq_is_admin());

-- 2. What a card needs: is it external, its PDF (and whether the exact file is stored), its recorded Gmail draft (with the link
-- that opens that draft), the attachment state (requested, workflow 26's answer, verified) and the send-after date.
create or replace function public.studio_try_jsonb(p text) returns jsonb
language plpgsql immutable as $$ begin return p::jsonb; exception when others then return null; end $$;

create or replace function public.studio_handoff(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with d as (select * from studio_documents where id = p_id),
  o as (select so.* from studio_outputs so join d on (d.stage = 'email' and so.email_slug = d.slug) or (d.stage is distinct from 'email' and so.document_slug = d.slug)
         order by (so.sent_at is null and so.status in ('PREPARED', 'HELD')) desc, so.prepared_at desc nulls last limit 1),
  r as (select x.status_code, x.content, x.error_msg, x.timed_out from d join net._http_response x on x.id = nullif(d.content #>> '{attach_request,id}', '')::bigint)
  select jsonb_build_object(
    'external', d.audience is distinct from 'INTERNAL' and d.stage is distinct from 'email',
    'email', d.stage = 'email',
    'pdf', case when d.stage = 'email' or d.content->>'pdf_bytes' is null then null else jsonb_build_object(
      'file_name', d.file_name, 'bytes', (d.content->>'pdf_bytes')::bigint, 'sha256', d.content->>'pdf_sha256', 'fingerprint', d.content->>'pdf_fingerprint',
      'path', d.slug || '/v' || d.version || '.pdf', 'stored_at', d.content->>'pdf_stored_at',
      'stored', exists (select 1 from storage.objects s where s.bucket_id = 'studio-pdfs' and s.name = d.slug || '/v' || d.version || '.pdf')) end,
    'draft', (select jsonb_build_object('id', o.gmail_draft_id, 'thread_id', o.gmail_thread_id, 'status', o.status, 'send_after', o.send_after, 'sent_at', o.sent_at, 'to', o.recipients,
      'url', case when o.sent_at is null and o.gmail_draft_id is not null
                  then coalesce(o.evidence #>> '{draft,view_url}', 'https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#drafts')
                  when o.gmail_thread_id is not null then 'https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#all/' || o.gmail_thread_id end,
      'thread_url', case when o.gmail_thread_id is not null then 'https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#all/' || o.gmail_thread_id end) from o),
    'attach', jsonb_build_object('verified_at', d.content->>'attachment_verified_at', 'requested_at', d.content #>> '{attach_request,at}',
      'status_code', (select status_code from r), 'result', (select studio_try_jsonb(content) from r),
      'error', (select coalesce(error_msg, case when timed_out then 'timed out' end) from r)))
  from d
$$;
revoke all on function public.studio_handoff(uuid) from public, anon, authenticated;

do $do$
declare v text; w text;
begin
  v := pg_get_functiondef('public.hq_studio()'::regprocedure); w := v;
  v := replace(v, $o$'ready_reason', d.ready_reason, 'file', d.file_name) j$o$, $n$'ready_reason', d.ready_reason, 'file', d.file_name, 'handoff', studio_handoff(d.id)) j$n$);
  if v = w then raise exception 'hq_studio handoff patch not applied'; end if;
  execute v;
end $do$;

-- 3. Is this exactly this document's PDF? (Its exact fingerprint, or the render-proof one, and its size.) Then record it stored.
create or replace function public.studio_pdf_match(p_slug text, p_version integer, p_sha256 text, p_fingerprint text, p_bytes bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d studio_documents%rowtype;
begin
  select * into d from studio_documents where slug = p_slug and version = p_version;
  if not found then return jsonb_build_object('ok', false, 'reason', 'NO_SUCH_DOCUMENT_VERSION'); end if;
  if d.stage = 'email' or d.content->>'pdf_bytes' is null then return jsonb_build_object('ok', false, 'reason', 'NO_PDF_FOR_THIS_DOCUMENT'); end if;
  if (d.content->>'pdf_bytes')::bigint is distinct from p_bytes
     or not (d.content->>'pdf_sha256' = p_sha256 or d.content->>'pdf_fingerprint' = p_fingerprint) then
    return jsonb_build_object('ok', false, 'reason', 'NOT_THIS_DOCUMENTS_PDF'); end if;
  return jsonb_build_object('ok', true, 'path', d.slug || '/v' || d.version || '.pdf', 'file_name', d.file_name);
end $$;
revoke all on function public.studio_pdf_match(text, integer, text, text, bigint) from public, anon, authenticated;
grant execute on function public.studio_pdf_match(text, integer, text, text, bigint) to service_role;

create or replace function public.studio_pdf_stored(p_slug text, p_version integer, p_sha256 text, p_fingerprint text, p_bytes bigint, p_by text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m jsonb := studio_pdf_match(p_slug, p_version, p_sha256, p_fingerprint, p_bytes);
begin
  if not (m->>'ok')::boolean then return m; end if;
  if not exists (select 1 from storage.objects s where s.bucket_id = 'studio-pdfs' and s.name = m->>'path'
                   and coalesce((s.metadata->>'size')::bigint, p_bytes) = p_bytes) then
    return jsonb_build_object('ok', false, 'reason', 'PDF_NOT_IN_STORAGE'); end if;
  update studio_documents set content = content || jsonb_build_object('pdf_stored_at', now(), 'pdf_stored_by', p_by, 'pdf_stored_sha256', p_sha256)
   where slug = p_slug and version = p_version;
  return jsonb_build_object('ok', true, 'path', m->>'path');
end $$;
revoke all on function public.studio_pdf_stored(text, integer, text, text, bigint, text) from public, anon, authenticated;
grant execute on function public.studio_pdf_stored(text, integer, text, text, bigint, text) to service_role;

-- HQ: Adam's browser uploaded the PDF (after checking its fingerprint itself); the record is checked again here.
create or replace function public.hq_studio_pdf_stored(p_slug text, p_version integer, p_sha256 text, p_fingerprint text, p_bytes bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return studio_pdf_stored(p_slug, p_version, p_sha256, p_fingerprint, p_bytes, hq_admin_email());
end $$;
revoke all on function public.hq_studio_pdf_stored(text, integer, text, text, bigint) from public, anon;
grant execute on function public.hq_studio_pdf_stored(text, integer, text, text, bigint) to authenticated;

-- 4. Attach to email: the same checks as workflow 26 (approved, latest, unsent, this exact PDF, the one recorded draft), then
-- pg_net calls workflow 26 (its address and token are in the vault, never in HQ or the repo). Workflow 26 attaches the stored PDF,
-- downloads it back and verifies it; studio_attachment_verified then writes READY TO SEND. Its answer shows on the card.
create or replace function public.hq_studio_attach(p_slug text, p_version integer)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_admin text := hq_admin_email(); d studio_documents%rowtype; t jsonb; v_url text; v_tok text; v_id bigint; v_path text;
begin
  select * into d from studio_documents where slug = p_slug and version = p_version;
  if not found then return jsonb_build_object('ok', false, 'reason', 'NO_SUCH_DOCUMENT_VERSION'); end if;
  if nullif(d.content->>'attachment_verified_at', '') is not null then return jsonb_build_object('ok', true, 'already', true); end if;
  if d.status is distinct from 'APPROVED' then return jsonb_build_object('ok', false, 'reason', 'NOT_APPROVED'); end if;
  v_path := d.slug || '/v' || d.version || '.pdf';
  if not exists (select 1 from storage.objects s where s.bucket_id = 'studio-pdfs' and s.name = v_path) then
    return jsonb_build_object('ok', false, 'reason', 'PDF_NOT_STORED'); end if;
  t := studio_attachment_target(p_slug, p_version, d.content->>'pdf_sha256', d.content->>'pdf_fingerprint', (d.content->>'pdf_bytes')::integer);
  if not coalesce((t->>'ok')::boolean, false) then return t; end if;
  if (d.content #>> '{attach_request,at}')::timestamptz > now() - interval '2 minutes' then
    return jsonb_build_object('ok', true, 'pending', true, 'request_id', d.content #>> '{attach_request,id}'); end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'n8n_studio_attach_url';
  select decrypted_secret into v_tok from vault.decrypted_secrets where name = 'n8n_studio_attach_token';
  if v_url is null or v_tok is null then return jsonb_build_object('ok', false, 'reason', 'ATTACH_NOT_CONFIGURED'); end if;
  v_id := net.http_post(url := v_url, body := jsonb_build_object('slug', p_slug, 'version', p_version),
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-noya-attach', v_tok), timeout_milliseconds := 120000);
  update studio_documents set content = content || jsonb_build_object('attach_request', jsonb_build_object('id', v_id, 'at', now(), 'by', v_admin))
   where id = d.id;
  return jsonb_build_object('ok', true, 'request_id', v_id, 'draft_id', t->>'draft_id');
end $$;
revoke all on function public.hq_studio_attach(text, integer) from public, anon;
grant execute on function public.hq_studio_attach(text, integer) to authenticated;

-- 5. Review on the card: Approve, or ask for changes (the note goes on the record; the daily check takes it up). Never sends.
create or replace function public.hq_studio_document_action(p_slug text, p_version integer, p_action text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); d studio_documents%rowtype; v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  select * into d from studio_documents where slug = p_slug and version = p_version;
  if not found then return jsonb_build_object('ok', false, 'reason', 'NO_SUCH_DOCUMENT_VERSION'); end if;
  if p_version < (select max(version) from studio_documents where slug = p_slug) then return jsonb_build_object('ok', false, 'reason', 'NOT_THE_LATEST_VERSION'); end if;
  if d.status is distinct from 'FOR_REVIEW' then return jsonb_build_object('ok', false, 'reason', 'NOT_IN_REVIEW'); end if;
  if p_action = 'APPROVE' then
    update studio_documents set status = 'APPROVED', approved_at = now(),
           review_notes = coalesce(review_notes, '[]'::jsonb) || jsonb_build_array(concat('Approved by Adam in HQ, ', to_char(now() at time zone 'Africa/Cairo', 'DD Mon YYYY HH24:MI'), coalesce(': ' || v_note, '')))
     where id = d.id;
  elsif p_action = 'CHANGES' then
    if v_note is null then return jsonb_build_object('ok', false, 'reason', 'NOTE_REQUIRED'); end if;
    update studio_documents set ready_class = 'NEEDS_UPDATE', ready_reason = concat('Adam asked for changes: ', v_note), ready_checked_at = now(),
           review_notes = coalesce(review_notes, '[]'::jsonb) || jsonb_build_array(concat('Changes requested by Adam in HQ, ', to_char(now() at time zone 'Africa/Cairo', 'DD Mon YYYY'), ': ', v_note))
     where id = d.id;
  else return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION'); end if;
  return jsonb_build_object('ok', true, 'action', p_action, 'by', v_admin);
end $$;
revoke all on function public.hq_studio_document_action(text, integer, text, text) from public, anon;
grant execute on function public.hq_studio_document_action(text, integer, text, text) to authenticated;

-- 6. The exact Gmail draft each of the three opens (Gmail's own link for that draft, read from Gmail on 21 Oct).
update public.studio_outputs set evidence = jsonb_set(evidence, '{draft,view_url}',
       to_jsonb('https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#all?compose=thread-a:r1874138929045963898%2Bmsg-a:r3413834542155918452'::text))
 where id = '97d658f0-e095-42bb-9d98-f70eeded4f94';
update public.studio_outputs set evidence = jsonb_set(evidence, '{draft,view_url}',
       to_jsonb('https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#all?compose=thread-f:1878056417507623715%2Bmsg-a:r-7941037991870327689'::text))
 where id = '8add1aab-a5bd-4344-9f4e-7b0ffe44ef6f';
update public.studio_outputs set evidence = evidence || jsonb_build_object('draft', jsonb_build_object('id', 'r-8776625469132144549',
       'view_url', 'https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#all?compose=thread-f:1878787082969754824%2Bmsg-a:r-8776625469132144549'))
 where id = '23af25b3-b2ef-4741-b1d8-5c7ba8f078c5';

-- 7. The vault holds workflow 26's production address and the token it checks (set directly, never written here):
--   select vault.create_secret('<workflow 26 production webhook URL>', 'n8n_studio_attach_url');
--   select vault.create_secret('<random token>', 'n8n_studio_attach_token');

-- 8. The cards say what is true now (Adam approved YKONE v5 and CRUSH v3 on 21 Oct), and the Dashboard's "Emails to send" no
-- longer counts a Studio draft whose PDF is not yet verified on it: those are counted apart as "to attach first".
update public.studio_documents set ready_reason = concat('Approved by Adam, 21 Oct. Press Attach to YKONE email: the PDF goes onto the Gmail draft',
       ' and is checked there. READY TO SEND only after that.') where slug = 'ykone-egypt-brief' and version = 5 and status = 'APPROVED';
update public.studio_documents set ready_reason = concat('Approved by Adam, 21 Oct. For 26 Oct, only if Sophie has not replied. Attach now:',
       ' the PDF goes onto the draft in the CRUSH thread and is checked there.') where slug = 'crush-egypt-brief' and version = 3 and status = 'APPROVED';
do $do$
declare v text; w text;
begin
  v := pg_get_functiondef('public.hq_command()'::regprocedure); w := v;
  v := replace(v, $o$'studio_drafts_to_send', (select count(*) from studio_outputs where status = 'PREPARED' and gmail_draft_id is not null and coalesce(send_after, v_today) <= v_today),$o$,
                  $n$'studio_drafts_to_send', (select count(*) from studio_outputs so where so.status = 'PREPARED' and so.gmail_draft_id is not null and coalesce(so.send_after, v_today) <= v_today
         and not exists (select 1 from studio_documents sd where sd.slug = so.document_slug and sd.status = 'APPROVED' and sd.ready_class = 'READY_FOR_ATTACHMENT')),
      'studio_drafts_to_attach', (select count(*) from studio_outputs so where so.status = 'PREPARED' and so.gmail_draft_id is not null and coalesce(so.send_after, v_today) <= v_today
         and exists (select 1 from studio_documents sd where sd.slug = so.document_slug and sd.status = 'APPROVED' and sd.ready_class = 'READY_FOR_ATTACHMENT')),$n$);
  if v = w then raise exception 'hq_command attach-first patch not applied'; end if;
  execute v;
end $do$;
