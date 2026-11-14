-- Published named emails are usable without Hunter (Adam, master operating system, 15 Nov 2026).
-- A person's own professional address that is published on a public page (company website, press page,
-- media kit, interview, partnership or speaker page, Instagram), with the source URL recorded, becomes
-- PUBLIC_NAMED_EMAIL: usable for a one-to-one email, never labelled VERIFIED. Spot check before the change:
-- 4 of 4 sampled addresses appeared on their recorded source page exactly as stored.
-- Addresses with a failed verification, or marked INVALID or RISKY, are excluded.
-- Applied as an in-place edit of the live function so the rest of its routing order is unchanged.
do $mig$
declare
  d text;
  anchor constant text := '  -- 2 a verified department inbox for their attention';
  block constant text := $blk$  -- 1c their own address, published on a public professional page with the source URL recorded (15 Nov): usable without Hunter, never labelled VERIFIED
  if coalesce(btrim(k.email), '') <> '' and email_local_class(k.email) = 'PERSONAL'
     and coalesce(k.route_type, 'PERSON_EMAIL') = 'PERSON_EMAIL'
     and k.email_source_type in ('OFFICIAL_SITE', 'PRESS', 'MEDIA_KIT', 'INTERVIEW', 'PARTNERSHIP_PAGE', 'SPEAKER_PAGE', 'INSTAGRAM')
     and coalesce(btrim(k.email_source_url), '') ~* '^https?://'
     and coalesce(k.email_status, '') not in ('INVALID', 'RISKY')
     and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(k.email)) and v.provider_status is not null and v.provider_status <> 'valid') then
    return jsonb_build_object('state', 'PUBLIC_NAMED_EMAIL', 'email', lower(btrim(k.email)), 'source_url', k.email_source_url, 'found_at', k.email_found_at,
                              'source_type', k.email_source_type,
                              'label', 'Their own address, published on ' || case k.email_source_type
                                         when 'OFFICIAL_SITE' then 'the company website' when 'PRESS' then 'a press page'
                                         when 'MEDIA_KIT' then 'a media kit' when 'INTERVIEW' then 'an interview'
                                         when 'PARTNERSHIP_PAGE' then 'a partnership page' when 'SPEAKER_PAGE' then 'a speaker page'
                                         else 'Instagram' end || ' (not verified)');
  end if;
$blk$;
begin
  d := pg_get_functiondef('public.contact_email_route(uuid)'::regprocedure);
  if position('-- 1c their own address, published on a public professional page' in d) > 0 then
    return;  -- already applied
  end if;
  if position(anchor in d) = 0 then
    raise exception 'contact_email_route: anchor for step 2 not found; not changed';
  end if;
  d := replace(d, anchor, block || anchor);
  execute d;
end
$mig$;
