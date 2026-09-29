-- Outreach cards need each opportunity's channel decision and prepared copy on one screen.
-- Adds outreach_readiness (already deterministic, from 05's OUTREACH_READY_JSON) to hq_directory.
do $$
declare d text;
begin
  d := pg_get_functiondef('public.hq_directory()'::regprocedure);
  d := replace(d, $x$'notes_count', (select count(*) from relationship_notes)$x$,
    $x$'notes_count', (select count(*) from relationship_notes),
    'readiness', coalesce((select jsonb_object_agg(r.opportunity_id, jsonb_build_object(
        'primary_channel', r.primary_channel, 'available', r.available_channels, 'linkedin', r.linkedin, 'instagram', r.instagram,
        'email', r.email, 'email_status', r.email_status, 'email_kind', r.email_kind, 'contact_role', r.contact_role,
        'ready_linkedin', r.ready_linkedin, 'ready_instagram', r.ready_instagram, 'why_now', r.why_now_evidence,
        'evidence', r.personalisation_evidence, 'last_outbound_at', r.last_outbound_at, 'last_inbound_at', r.last_inbound_at,
        'next_follow_up_at', r.next_follow_up_at)) from outreach_readiness r), '{}'::jsonb)$x$);
  if d not like '%''readiness''%' then raise exception 'readiness not added'; end if;
  execute d;
end $$;
