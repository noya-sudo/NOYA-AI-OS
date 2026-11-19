-- Clay work emails are usable without Hunter (Adam, 18 Nov 2026: "Clay work-email enrichment is allowed and useful.
-- Hunter is NOT required. A Clay-derived work email is not automatically independently verified.")
--
-- New route state CLAY_WORK_EMAIL: a person's own address found by Clay work-email enrichment, on the company's
-- confirmed domain, never INVALID/RISKY and never failed a provider check. It counts as usable (Email ready) wherever
-- PUBLIC_NAMED_EMAIL counts, and it is never labelled VERIFIED. A Hunter-verified Clay address stays VERIFIED (step 1).
-- Also fixes the send gate: outbound_recipient_block_reason now accepts every PUBLIC_NAMED_EMAIL route (published-page
-- addresses approved 15 Nov were still blocked there) as well as CLAY_WORK_EMAIL.
-- Every function is edited in place by exact text replacement, so nothing else in them changes. Idempotent.
do $mig$
declare d text; f text;
  ready_a text := $a$'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL'$a$;
  ready_b text := $a$'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL', 'CLAY_WORK_EMAIL'$a$;
begin
  -- 1. the route
  d := pg_get_functiondef('public.contact_email_route'::regproc);
  if position('CLAY_WORK_EMAIL' in d) = 0 then
    d := replace(d, $a$  -- 2 a verified department inbox$a$,
$a$  -- 1d a Clay work email on the company's confirmed domain (18 Nov): usable without Hunter, never labelled VERIFIED
  if coalesce(btrim(k.email), '') <> '' and k.email_source_type = 'CLAY' and email_local_class(k.email) = 'PERSONAL'
     and coalesce(k.route_type, 'PERSON_EMAIL') = 'PERSON_EMAIL'
     and coalesce(k.email_status, '') not in ('INVALID', 'RISKY')
     and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(k.email)) and v.provider_status is not null and v.provider_status <> 'valid')
     and email_domain_matches(k.email, company_research_domain(c.name, c.website, c.website_confirmed_at)) then
    return jsonb_build_object('state', 'CLAY_WORK_EMAIL', 'email', lower(btrim(k.email)), 'source_type', 'CLAY',
                              'label', 'Clay work email on the company domain (not independently verified)');
  end if;
  -- 2 a verified department inbox$a$);
    execute d;
  end if;

  -- 2. company ranking: same rank as a published named email
  d := pg_get_functiondef('public.company_email_state'::regproc);
  if position('CLAY_WORK_EMAIL' in d) = 0 then
    d := replace(d, $a$when dm.r->>'state' in ('VERIFIED_INBOX', 'PUBLIC_NAMED_EMAIL') then 1$a$,
                    $a$when dm.r->>'state' in ('VERIFIED_INBOX', 'PUBLIC_NAMED_EMAIL', 'CLAY_WORK_EMAIL') then 1$a$);
    execute d;
  end if;

  -- 3. everywhere a route counts as ready, CLAY_WORK_EMAIL counts too
  foreach f in array array['cold_route_sweep', 'commercial_director_plan', 'director_channel_health', 'hq_command', 'hq_work_order',
                           'warm_route_check', 'work_order_eval'] loop
    d := pg_get_functiondef(('public.' || f)::regproc);
    if position('CLAY_WORK_EMAIL' in d) = 0 and position(ready_a in d) > 0 then
      execute replace(d, ready_a, ready_b);
    end if;
  end loop;

  d := pg_get_functiondef('public.commercial_pipeline'::regproc);
  if position('CLAY_WORK_EMAIL' in d) = 0 then
    execute replace(d, $a$e.es in ('OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL') then 'CONTACT_READY'$a$,
                       $a$e.es in ('OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL', 'CLAY_WORK_EMAIL') then 'CONTACT_READY'$a$);
  end if;

  foreach f in array array['outreach_top5', 'outreach_next20'] loop
    d := pg_get_functiondef(('public.' || f)::regproc);
    if position('CLAY_WORK_EMAIL' in d) = 0 then
      execute replace(d, $a$'VERIFIED_GENERAL', 'PUBLIC_NAMED_EMAIL'))$a$, $a$'VERIFIED_GENERAL', 'PUBLIC_NAMED_EMAIL', 'CLAY_WORK_EMAIL'))$a$);
    end if;
  end loop;

  -- 4. the desk: a Clay work email is usable (Email ready) and shown as such, never as published or verified
  d := pg_get_functiondef('public.outreach_desk'::regproc);
  if position('CLAY_WORK_EMAIL' in d) = 0 then
    d := replace(d, $a$and v.provider_status <> 'valid')) r_official$a$,
$a$and v.provider_status <> 'valid'))
             -- a Clay work email on the confirmed company domain (18 Nov)
             or (r.email_source_type = 'CLAY' and contact_email_route(r.id)->>'state' = 'CLAY_WORK_EMAIL') r_official$a$);
    d := replace(d, $a$case when b.r_official and email_local_class(b.r_email) = 'PERSONAL' then 'PUBLIC_NAMED_EMAIL'$a$,
$a$case when b.r_official and email_local_class(b.r_email) = 'PERSONAL'
                    and exists (select 1 from contacts kc where lower(btrim(kc.email)) = lower(btrim(b.r_email)) and kc.email_source_type = 'CLAY'
                                  and contact_email_route(kc.id)->>'state' = 'CLAY_WORK_EMAIL') then 'CLAY_WORK_EMAIL'
               when b.r_official and email_local_class(b.r_email) = 'PERSONAL' then 'PUBLIC_NAMED_EMAIL'$a$);
    execute d;
  end if;

  -- 5. the send gate (W12 drafts only Adam-approved rows): accept usable unverified routes, never INVALID/RISKY
  d := pg_get_functiondef('public.outbound_recipient_block_reason'::regproc);
  if position('CLAY_WORK_EMAIL' in d) = 0 then
    execute replace(d, $a$      then 'EMAIL_NOT_VERIFIED:'$a$,
$a$      and coalesce(contact_email_route(c.id)->>'state', '') not in ('PUBLIC_NAMED_EMAIL', 'CLAY_WORK_EMAIL')
      then 'EMAIL_NOT_VERIFIED:'$a$);
  end if;
end
$mig$;
