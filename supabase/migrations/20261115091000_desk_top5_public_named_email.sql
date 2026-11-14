-- Desk, Top 5 and Next 20 follow the published-email rule (15 Nov 2026).
-- outreach_desk: a person's own address published on a public professional page (with source URL, not INVALID/RISKY)
--   counts as published, so the desk shows PUBLIC_NAMED_EMAIL instead of an unverified state.
-- outreach_top5 / outreach_next20: PUBLIC_NAMED_EMAIL qualifies alongside verified routes (Hunter is not required for
--   published data). Edited in place so nothing else in these functions changes.
do $mig$
declare d text;
begin
  d := pg_get_functiondef('public.outreach_desk'::regproc);
  if position('-- published on a public professional page (15 Nov)' in d) = 0 then
    d := replace(d, 'and pp.company_id = r.company_id) r_official',
      'and pp.company_id = r.company_id)
             -- published on a public professional page (15 Nov)
             or (coalesce(r.route_type, ''PERSON_EMAIL'') = ''PERSON_EMAIL''
                 and r.email_source_type in (''OFFICIAL_SITE'', ''PRESS'', ''MEDIA_KIT'', ''INTERVIEW'', ''PARTNERSHIP_PAGE'', ''SPEAKER_PAGE'', ''INSTAGRAM'')
                 and coalesce(btrim(r.email_source_url), '''') ~* ''^https?://''
                 and coalesce(r.email_status, '''') not in (''INVALID'', ''RISKY'')
                 and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(r.email)) and v.provider_status is not null and v.provider_status <> ''valid'')) r_official');
    execute d;
  end if;

  d := pg_get_functiondef('public.outreach_top5'::regproc);
  if position('''VERIFIED_GENERAL'', ''PUBLIC_NAMED_EMAIL''))' in d) = 0 then
    d := replace(d, 'in (''VALID_VERIFIED'', ''VERIFIED'', ''VERIFIED_INBOX'', ''VERIFIED_GENERAL''))',
                    'in (''VALID_VERIFIED'', ''VERIFIED'', ''VERIFIED_INBOX'', ''VERIFIED_GENERAL'', ''PUBLIC_NAMED_EMAIL''))');
    execute d;
  end if;

  d := pg_get_functiondef('public.outreach_next20'::regproc);
  if position('''VERIFIED_GENERAL'', ''PUBLIC_NAMED_EMAIL''))' in d) = 0 then
    d := replace(d, 'in (''VALID_VERIFIED'', ''VERIFIED'', ''VERIFIED_INBOX'', ''VERIFIED_GENERAL''))',
                    'in (''VALID_VERIFIED'', ''VERIFIED'', ''VERIFIED_INBOX'', ''VERIFIED_GENERAL'', ''PUBLIC_NAMED_EMAIL''))');
    execute d;
  end if;
end
$mig$;
