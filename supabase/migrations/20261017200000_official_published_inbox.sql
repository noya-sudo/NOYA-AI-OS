-- OFFICIAL_PUBLISHED_INBOX (Adam, 17 Oct 2026): until the 27 Oct Hunter test, an inbox the company publishes on its own
-- official website may be outreach-ready without Hunter.
--   * source must be the company's own official website; the source URL and date are saved (email_official_inboxes)
--   * classified OFFICIAL_PUBLISHED_INBOX, never VERIFIED (contacts.email_status is untouched)
--   * Adam still reviews and approves every email; Approve still creates an unsent Gmail draft; nothing sends automatically
--   * named personal addresses still wait for Hunter: a company where a decision maker's own address is waiting for
--     verification keeps waiting, so its one cold route is not spent on an inbox
--   * one company, one active cold route (the planner and cold_route_sweep supersede the LinkedIn fallback)

create table if not exists public.email_official_inboxes (
  contact_id uuid primary key references public.contacts(id) on delete cascade,
  company_id uuid not null references public.companies(id),
  email text not null,
  source_url text not null,
  source_domain text not null,
  company_domain text not null,
  found_at timestamptz not null,
  classified_at timestamptz not null default now(),
  classification text not null default 'OFFICIAL_PUBLISHED_INBOX' check (classification = 'OFFICIAL_PUBLISHED_INBOX'),
  rule text not null,
  revoked_at timestamptz,
  revoked_reason text
);
alter table public.email_official_inboxes enable row level security;
revoke all on table public.email_official_inboxes from public, anon, authenticated;
comment on table public.email_official_inboxes is 'Company inboxes published on the company''s own official website (Adam, 17 Oct 2026). Not VERIFIED. Read by contact_email_route and outbound_recipient_block_reason.';

-- Classify (idempotent): own-domain inbox, found on the company's own website, never checked by the provider.
create or replace function public.official_inbox_classify()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into email_official_inboxes (contact_id, company_id, email, source_url, source_domain, company_domain, found_at, rule)
  select i.id, i.company_id, lower(btrim(i.email)), i.email_source_url, registrable_domain(i.email_source_url), registrable_domain(c.website),
         coalesce(i.email_found_at, i.created_at),
         'Adam, 17 Oct 2026: an inbox the company publishes on its own official website may be used without Hunter. Not VERIFIED; Adam reviews and approves every email; nothing sends automatically.'
    from contacts i join companies c on c.id = i.company_id
   where i.route_type = 'COMPANY_INBOX' and not coalesce(i.do_not_contact, false) and coalesce(i.status, '') <> 'DO_NOT_CONTACT'
     and coalesce(btrim(i.email), '') <> '' and i.email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
     and email_local_class(i.email) in ('GENERAL', 'DEPARTMENT')
     and email_state_v3(i.email, i.email_status, i.email_source_url, i.email_verification_provider) in ('PUBLIC_UNVERIFIED', 'UNKNOWN')
     and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(i.email)) and v.provider_status is not null)
     and coalesce(c.website, '') <> '' and coalesce(i.email_source_url, '') ~* '^https?://'
     and registrable_domain(i.email_source_url) = registrable_domain(c.website)
     and registrable_domain(split_part(lower(btrim(i.email)), '@', 2)) = registrable_domain(c.website)
  on conflict (contact_id) do nothing;
  get diagnostics n = row_count;
  -- an address that changed, became do-not-contact, or was later checked and not found valid is no longer a route
  update email_official_inboxes o set revoked_at = now(), revoked_reason = 'Address changed, do-not-contact, or the verification provider did not confirm it'
   where o.revoked_at is null
     and (not exists (select 1 from contacts i where i.id = o.contact_id and lower(btrim(i.email)) = o.email
                       and not coalesce(i.do_not_contact, false) and coalesce(i.status, '') <> 'DO_NOT_CONTACT')
          or exists (select 1 from contact_email_verifications v where lower(v.email) = o.email and v.provider_status is not null and v.provider_status <> 'valid'));
  return n;
end $$;
revoke all on function public.official_inbox_classify() from public, anon, authenticated;

-- Usable for this person now: the inbox is classified, and no decision maker at the company has their own address
-- waiting for Hunter (named personal addresses wait until 27 Oct; the company keeps its one cold route for them).
create or replace function public.official_inbox_usable(p_inbox uuid, p_person uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from email_official_inboxes o join contacts i on i.id = o.contact_id
                  where o.contact_id = p_inbox and o.revoked_at is null and lower(btrim(i.email)) = o.email)
     and not exists (select 1 from contacts p join companies c on c.id = p.company_id join contacts d on d.company_id = p.company_id
                      where p.id = p_person and d.identity_status = 'CONFIRMED' and role_score(d.position) >= 3
                        and not coalesce(d.do_not_contact, false) and coalesce(btrim(d.email), '') <> '' and email_local_class(d.email) = 'PERSONAL'
                        and email_state_v3(d.email, d.email_status, d.email_source_url, d.email_verification_provider) in ('PUBLIC_UNVERIFIED', 'UNKNOWN')
                        and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(d.email)) and v.provider_status is not null)
                        and registrable_domain(split_part(lower(btrim(d.email)), '@', 2)) = registrable_domain(c.website));
$$;
revoke all on function public.official_inbox_usable(uuid, uuid) from public, anon, authenticated;

create or replace function public.official_inbox_route(p_inbox uuid, p_name text, p_general boolean)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('state', 'OFFICIAL_PUBLISHED_INBOX', 'email', o.email, 'inbox_id', o.contact_id, 'general', p_general,
           'source_url', o.source_url, 'found_at', o.found_at,
           'label', 'Official published ' || case when p_general then 'inbox' else lower(coalesce(nullif(i.position, ''), 'department inbox')) end
                    || ' (company website)' || coalesce(', for the attention of ' || p_name, ', for their attention'))
    from email_official_inboxes o join contacts i on i.id = o.contact_id where o.contact_id = p_inbox;
$$;
revoke all on function public.official_inbox_route(uuid, text, boolean) from public, anon, authenticated;

do $p$
declare d text;
begin
  -- 1 the route: a classified, usable inbox is OFFICIAL_PUBLISHED_INBOX (department inbox and small-firm general inbox)
  d := pg_get_functiondef('contact_email_route'::regproc);
  if strpos(d, 'official_inbox_usable') = 0 then
    d := replace(d, E'     order by i.created_at limit 1;\n    if v_pend.id is not null then',
      E'     order by (exists (select 1 from email_official_inboxes o where o.contact_id = i.id and o.revoked_at is null)) desc, i.created_at limit 1;\n    if v_pend.id is not null and official_inbox_usable(v_pend.id, k.id) then\n      return official_inbox_route(v_pend.id, v_name, false);\n    end if;\n    if v_pend.id is not null then');
    d := replace(d, E'       and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(i.email)) and v.provider_status is not null)\n     order by (split_part',
      E'       and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(i.email)) and v.provider_status is not null)\n     order by (exists (select 1 from email_official_inboxes o where o.contact_id = i.id and o.revoked_at is null)) desc, (split_part');
    d := replace(d, E'    if v_gen.id is not null then\n      return jsonb_build_object(''state'', ''NEEDS_VERIFICATION''',
      E'    if v_gen.id is not null and official_inbox_usable(v_gen.id, k.id) then\n      return official_inbox_route(v_gen.id, v_name, true);\n    end if;\n    if v_gen.id is not null then\n      return jsonb_build_object(''state'', ''NEEDS_VERIFICATION''');
    if (length(d) - length(replace(d, 'official_inbox_usable', ''))) / length('official_inbox_usable') <> 2
       or (length(d) - length(replace(d, 'from email_official_inboxes o where o.contact_id = i.id', ''))) / length('from email_official_inboxes o where o.contact_id = i.id') <> 2 then
      raise exception 'contact_email_route anchors not found';
    end if;
    execute d;
  end if;

  -- 2 company ranking: a decision maker's own address waiting for Hunter outranks an official inbox
  d := pg_get_functiondef('company_email_state'::regproc);
  if strpos(d, 'OFFICIAL_PUBLISHED_INBOX') = 0 then
    d := replace(d, $r$order by case dm.r->>'state' when 'VERIFIED' then 0 when 'VERIFIED_INBOX' then 1 when 'VERIFIED_GENERAL' then 2
                                            when 'NEEDS_VERIFICATION' then 3 when 'FINDER_PENDING' then 4 when 'RESEARCH_PENDING' then 5 else 6 end,$r$,
      $r$order by case when dm.r->>'state' = 'VERIFIED' then 0 when dm.r->>'state' = 'VERIFIED_INBOX' then 1 when dm.r->>'state' = 'VERIFIED_GENERAL' then 2
                                 when dm.r->>'state' = 'NEEDS_VERIFICATION' and dm.r->>'inbox_id' is null then 3 when dm.r->>'state' = 'OFFICIAL_PUBLISHED_INBOX' then 4
                                 when dm.r->>'state' = 'NEEDS_VERIFICATION' then 5 when dm.r->>'state' = 'FINDER_PENDING' then 6 when dm.r->>'state' = 'RESEARCH_PENDING' then 7 else 8 end,$r$);
    if strpos(d, 'OFFICIAL_PUBLISHED_INBOX') = 0 then raise exception 'company_email_state anchor not found'; end if;
    execute d;
  end if;

  -- 3 the planner: an official inbox is an email route; classify before planning; supersede the LinkedIn fallback
  d := pg_get_functiondef('commercial_director_plan'::regproc);
  if strpos(d, 'OFFICIAL_PUBLISHED_INBOX') = 0 then
    d := replace(d, $r$('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL')$r$, $r$('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX')$r$);
    d := replace(d, $r$'VERIFIED_GENERAL', 'NEEDS_VERIFICATION', 'FINDER_PENDING'$r$, $r$'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX', 'NEEDS_VERIFICATION', 'FINDER_PENDING'$r$);
    d := replace(d, $r$in ('VERIFIED_INBOX', 'VERIFIED_GENERAL') then (p.rt->>'inbox_id')::uuid$r$, $r$in ('VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX') then (p.rt->>'inbox_id')::uuid$r$);
    d := replace(d, ': a verified email now exists for ', ': a verified email or an official published inbox now exists for ');
    d := replace(d, E'begin\n  if not p_dry_run then\n    insert into system_config', E'begin\n  if not p_dry_run then\n    perform official_inbox_classify();\n    insert into system_config');
    if strpos(d, 'perform official_inbox_classify()') = 0 or strpos(d, $r$'OFFICIAL_PUBLISHED_INBOX', 'NEEDS_VERIFICATION'$r$) = 0
       or strpos(d, $r$'OFFICIAL_PUBLISHED_INBOX') then (p.rt->>'inbox_id')::uuid$r$) = 0 then
      raise exception 'commercial_director_plan anchors not found';
    end if;
    execute d;
  end if;

  -- 4 one company, one cold route: an official inbox supersedes the open LinkedIn / Instagram message
  d := pg_get_functiondef('cold_route_sweep'::regproc);
  if strpos(d, 'OFFICIAL_PUBLISHED_INBOX') = 0 then
    d := replace(d, $r$('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL')$r$, $r$('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX')$r$);
    d := replace(d, 'a verified email now exists at this company', 'a verified email or an official published inbox now exists at this company');
    if strpos(d, 'OFFICIAL_PUBLISHED_INBOX') = 0 then raise exception 'cold_route_sweep anchor not found'; end if;
    execute d;
  end if;

  -- 5 the Gmail-draft gate: a classified official inbox passes; everything else still needs VERIFIED
  d := pg_get_functiondef('outbound_recipient_block_reason'::regproc);
  if strpos(d, 'email_official_inboxes') = 0 then
    d := replace(d, E'    when email_state(c.email_status, c.email_source_url, c.email_verification_provider) <> ''VERIFIED''\n      then',
      E'    when email_state(c.email_status, c.email_source_url, c.email_verification_provider) <> ''VERIFIED''\n      and not exists (select 1 from email_official_inboxes o where o.contact_id = c.id and o.revoked_at is null and o.email = lower(btrim(c.email)))\n      then');
    if strpos(d, 'email_official_inboxes') = 0 then raise exception 'outbound_recipient_block_reason anchor not found'; end if;
    execute d;
  end if;

  -- 6 the review task says exactly what Adam is approving
  d := pg_get_functiondef('outreach_candidate_save'::regproc);
  if strpos(d, 'email_official_inboxes') = 0 then
    d := replace(d, $r$else ' · publicly listed at ' || coalesce(ri.email_source_url, 'source on file') || '; not SMTP-verified' end$r$,
      $r$when exists (select 1 from email_official_inboxes o where o.contact_id = ri.id and o.revoked_at is null)
                                then ' · OFFICIAL PUBLISHED INBOX: listed on the company''s own website (' || coalesce(ri.email_source_url, 'source on file') || '); not SMTP-verified'
                              else ' · publicly listed at ' || coalesce(ri.email_source_url, 'source on file') || '; not SMTP-verified' end$r$);
    if strpos(d, 'email_official_inboxes') = 0 then raise exception 'outreach_candidate_save anchor not found'; end if;
    execute d;
  end if;

  -- 7 the desk shows the class (never "verified") and the reason a fallback moved to email
  d := pg_get_functiondef('outreach_desk'::regproc);
  if strpos(d, 'r_official') = 0 then
    d := replace(d, 'r.position r_label,', 'r.position r_label, exists (select 1 from email_official_inboxes o where o.contact_id = r.id and o.revoked_at is null and o.email = lower(btrim(r.email))) r_official,');
    d := replace(d, $r$'email_state', case when b.channel = 'EMAIL' then b.r_state end,$r$,
                    $r$'email_state', case when b.channel = 'EMAIL' then case when b.r_official then 'OFFICIAL_PUBLISHED_INBOX' else b.r_state end end,$r$);
    d := replace(d, $r$when 'VERIFIED_GENERAL' then 'Email first: a verified general inbox exists (for their attention), so an email replaces this message in tonight''s plan'$r$,
                    $r$when 'VERIFIED_GENERAL' then 'Email first: a verified general inbox exists (for their attention), so an email replaces this message in tonight''s plan'
            when 'OFFICIAL_PUBLISHED_INBOX' then 'Email first: the company publishes an inbox on its own website (for their attention), so an email replaces this message in tonight''s plan'$r$);
    if strpos(d, 'b.r_official') = 0 or strpos(d, 'publishes an inbox on its own website') = 0 then raise exception 'outreach_desk anchors not found'; end if;
    execute d;
  end if;

  -- 8 health counts: email ready includes official inboxes; "verified" stays strictly verified
  d := pg_get_functiondef('director_channel_health'::regproc);
  if strpos(d, 'official_inbox') = 0 then
    d := replace(d, $r$r.state in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'NEEDS_VERIFICATION') or r.dm_email$r$,
                    $r$r.state in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX', 'NEEDS_VERIFICATION') or r.dm_email$r$);
    d := replace(d, $r$count(*) filter (where r.cold and r.untouched and r.state in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL')) email_ready,$r$,
                    $r$count(*) filter (where r.cold and r.untouched and r.state in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX')) email_ready,
           count(*) filter (where r.state = 'OFFICIAL_PUBLISHED_INBOX') official_inbox,$r$);
    d := replace(d, $r$'verified_general', a.verified_general, 'email_ready', a.email_ready,$r$,
                    $r$'verified_general', a.verified_general, 'official_inbox', a.official_inbox, 'email_ready', a.email_ready,$r$);
    if strpos(d, 'a.official_inbox') = 0 or strpos(d, $r$'OFFICIAL_PUBLISHED_INBOX')) email_ready$r$) = 0 then raise exception 'director_channel_health anchors not found'; end if;
    execute d;
  end if;
  d := pg_get_functiondef('acquisition_health'::regproc);
  if strpos(d, 'official_inbox') = 0 then
    d := replace(d, $r$count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'VERIFIED_GENERAL') verified_general,$r$,
                    $r$count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'VERIFIED_GENERAL') verified_general,
           count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'OFFICIAL_PUBLISHED_INBOX') official_inbox,$r$);
    d := replace(d, 'sum(verified_general)::int verified_general,', 'sum(verified_general)::int verified_general, sum(official_inbox)::int official_inbox,');
    d := replace(d, 'tot.valid_verified + tot.verified_general', 'tot.valid_verified + tot.verified_general + tot.official_inbox');
    d := replace(d, $r$jsonb_build_object('email_ready', valid_verified + verified_general)$r$, $r$jsonb_build_object('email_ready', valid_verified + verified_general + official_inbox)$r$);
    d := replace(d, $r$'verified_general_email_ready', tot.verified_general,$r$, $r$'verified_general_email_ready', tot.verified_general, 'official_inbox_email_ready', tot.official_inbox,$r$);
    if strpos(d, 'official_inbox_email_ready') = 0 or strpos(d, 'verified_general + official_inbox') = 0 then raise exception 'acquisition_health anchors not found'; end if;
    execute d;
  end if;
end $p$;

-- classify the backlog now
select public.official_inbox_classify();
