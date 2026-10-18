-- NOYA Studio (18 Oct 2026): the Gmail connector cannot attach a stored PDF, so drafts carry no attachment and never say
-- "attached". The output's next step now names Adam's one action, ATTACH APPROVED PDF, with the approved file's name, read from
-- the attachment provenance recorded on studio_outputs.evidence. Text-only change to the status view; nothing sends.
create or replace view public.studio_output_status with (security_invoker = true) as
select o.id, c.name as company, o.case_slug, o.level,
       case o.level when 1 then 'Email idea' when 2 then 'One-page concept' else 'Full brief / proposal' end as level_label,
       o.document_slug, o.status, o.send_after, o.hold_reason, o.prepared_at, o.sent_at, o.reply_at, o.meeting_at, o.proposal_at, o.won_at,
       case when o.won_at is not null then 'Won'
            when o.proposal_at is not null then 'Proposal out: follow up'
            when o.meeting_at is not null then 'Meeting held: Level 3 brief or proposal'
            when o.reply_at is not null then 'Replied: answer and move to a meeting'
            when o.sent_at is not null then 'Sent: wait for a reply'
            when o.status = 'HELD' then 'Held: ' || coalesce(o.hold_reason, 'not yet')
            when o.status = 'PREPARED' and o.evidence->'attachment'->>'state' = 'NOT_ATTACHED'
              then 'ATTACH APPROVED PDF: ' || (o.evidence->'attachment'->>'filename')
                   || case when o.send_after > current_date then ', then send on ' || to_char(o.send_after, 'DD Mon') else ', then send' end
            when o.status = 'PREPARED' and o.evidence->'attachment'->>'state' = 'NOT_APPROVED' then 'Adam to approve the document and timing'
            when o.status = 'PREPARED' and o.send_after > current_date then 'Draft ready: send on ' || to_char(o.send_after, 'DD Mon')
            when o.status = 'PREPARED' then 'Draft ready: Adam to send'
            else o.status end as next_step,
       op.contracted_value as won_value_recorded, o.gmail_draft_id, o.gmail_thread_id
  from studio_outputs o join companies c on c.id = o.company_id left join opportunities op on op.id = o.opportunity_id;
revoke all on public.studio_output_status from public, anon, authenticated;
