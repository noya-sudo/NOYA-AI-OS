-- Deep contact & partnership enrichment (Adam, 7 Oct 2026). Find the actual route into each company.
-- Hierarchy: 1 named decision maker + publicly listed business email, 2 named decision maker + LinkedIn,
-- 3 Instagram account / DM route, 4 correct company inbox (partnerships / sales / PR / media). Hunter only after these fail.
-- A publicly listed email is NOT verified: it stays UNVERIFIED with its source URL. Nothing is ever invented:
-- workflow 19 only passes names, emails and handles that appear verbatim in the search evidence.
-- Supabase is shared with ChatGPT research: existing records are enriched, never duplicated.

alter table public.contacts
  add column if not exists source_url text,
  add column if not exists source_type text,
  add column if not exists route_type text;
alter table public.contacts drop constraint if exists contacts_source_type_check;
alter table public.contacts add constraint contacts_source_type_check check (source_type is null or source_type in
  ('OFFICIAL_SITE', 'LINKEDIN', 'INSTAGRAM', 'PRESS', 'INTERVIEW', 'SPEAKER_PAGE', 'MEDIA_KIT', 'PARTNERSHIP_PAGE', 'SEARCH_RESULT', 'HUNTER', 'MANUAL', 'OTHER'));
alter table public.contacts drop constraint if exists contacts_route_type_check;
alter table public.contacts add constraint contacts_route_type_check check (route_type is null or route_type in
  ('PERSON_EMAIL', 'LINKEDIN', 'INSTAGRAM', 'COMPANY_INBOX'));
alter table public.companies
  add column if not exists last_enriched_at timestamptz,
  add column if not exists enrichment_attempts smallint not null default 0;

-- Companies whose route in is weak: no confirmed person, or a confirmed person with no LinkedIn URL, email or Instagram.
-- Hospitality/partnerships first (Adam: extra weight), then weddings, brands, travel/private, corporate, sports.
create or replace function public.enrichment_queue(p_limit int default 12)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (
    select c.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane,
           registrable_domain(c.website) domain
      from companies c
     where c.universe_status in ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING')
       and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'
       and coalesce(c.last_enriched_at, '-infinity'::timestamptz) < now() - interval '14 days'
       and coalesce(c.enrichment_attempts, 0) < 3
       and relationship_state(c.id) = 'COLD'
       and not exists (select 1 from contacts k where k.company_id = c.id and k.identity_status = 'CONFIRMED' and k.position is not null
                         and not coalesce(k.do_not_contact, false)
                         and (coalesce(k.linkedin, '') ~* 'linkedin\.com/in/' or (k.email is not null and k.email_status in ('VERIFIED', 'UNVERIFIED'))
                              or coalesce(k.instagram, '') <> '')))
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object(
      'company_id', c.id, 'company', c.name, 'website', c.website, 'domain', c.domain, 'country', c.country, 'city', c.city,
      'company_type', c.company_type, 'lane', c.lane, 'instagram', c.instagram,
      'has_email', exists (select 1 from contacts e where e.company_id = c.id and e.email is not null and not coalesce(e.do_not_contact, false)),
      'people', (select coalesce(jsonb_agg(jsonb_build_object('first_name', k.first_name, 'last_name', k.last_name, 'position', k.position,
                   'linkedin', k.linkedin, 'email', k.email, 'instagram', k.instagram)), '[]'::jsonb)
                   from contacts k where k.company_id = c.id and coalesce(k.first_name, k.last_name) is not null)
    ) order by s.rnk), '[]'::jsonb))
  -- weighted round robin so every agent's finds get routes each run: hospitality x3, weddings and brands x2, sports selective
  from (select l.*, row_number() over (order by l.rn_lane / case l.lane when 'PARTNERSHIPS' then 3 when 'WEDDINGS' then 2 when 'BRANDS' then 2
                                                                   when 'TRAVEL_PRIVATE' then 1.5 when 'SPORTS_PRIVATE' then 0.5 else 1 end,
                                        array_position(array['PARTNERSHIPS','WEDDINGS','BRANDS','TRAVEL_PRIVATE','CORPORATE','EGYPT_EVENTS','SPORTS_PRIVATE'], l.lane)) rnk
          from (select c.*, row_number() over (partition by c.lane order by (c.universe_status = 'QUALIFIED') desc,
                                               coalesce(c.universe_added_at, c.created_at) desc)::numeric rn_lane
                  from c) l) s
  join c on c.id = s.id
  where s.rnk <= greatest(1, least(coalesce(p_limit, 12), 40))
$$;
revoke all on function public.enrichment_queue(int) from public, anon, authenticated;

-- How useful a role is as the route in (0 = not a route: HR, front office, F&B floor, spa, board seats).
-- Top-level titles win over the exclusions (a founder of a restaurant group is still a founder).
create or replace function public.role_score(p text)
returns int language sql immutable as $$
  select case
    when p is null or btrim(p) = '' then 1
    when p ~* '\m(assistant to|executive assistant|pa to)\M' then 3
    when p ~* '\m(founder|co-founder|cofounder|owner|ceo|chief|president|managing director|managing partner|proprietor|chairman|chairwoman)\M' then 5
    when p ~* '\m(hr|human resources|recruit\w*|talent acquisition|front office|guest relations?|reception\w*|housekeeping|engineer\w*|maintenance|accountant|accounting|payroll|intern|trainee|student|waiter|waitress|chef|cook|barista|bartender|sommelier|kitchen|restaurant|brasserie|f&b|food (and|&) beverage|spa|therapist|security officer|driver|legal|counsel|compliance|procurement|purchasing|developer|software|night manager|cashier|butler|valet|board member|non-executive)\M' then 0
    when p ~* '\m(general manager|gm|partner|principal)\M' then 5
    when p ~* '\m(director|head|vp|vice president|svp|evp)\M' then 4
    -- the persona matters more than the grade: a partnerships, PR, events or production manager is the right door
    when p ~* '\m(partnerships?|business development|commercial|experiential|influencer|brand|marketing|sales|pr|communications|press|events?|production|creative)\M'
     and p ~* '\m(manager|lead)\M' then 4
    when p ~* '\m(manager|lead|producer|planner|designer|curator|editor|buyer)\M' then 3
    else 2 end
$$;

-- Save what workflow 19 found. Every element must carry a source_url (validated against the search evidence upstream).
-- Matches existing people by LinkedIn URL, email, or company + name; fills gaps only, never overwrites, keeps provenance.
create or replace function public.enrich_company_routes(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_company uuid := (p->>'company_id')::uuid; c companies%rowtype; e jsonb; k uuid; v_domain text;
        v_new int := 0; v_upd int := 0; v_inbox int := 0; v_rej int := 0; u jsonb; v_email text; v_li text; v_ig text;
begin
  select * into c from companies where id = v_company;
  if c.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  v_domain := registrable_domain(c.website);

  if coalesce(p->>'company_instagram', '') <> '' and coalesce(c.instagram, '') = '' then
    update companies set instagram = p->>'company_instagram' where id = c.id;
  end if;

  for e in select * from jsonb_array_elements(coalesce(p->'people', '[]'::jsonb)) loop
    if coalesce(e->>'source_url', '') = '' or length(btrim(coalesce(e->>'first_name', ''))) < 2 or length(btrim(coalesce(e->>'last_name', ''))) < 2 then
      v_rej := v_rej + 1; continue; end if;
    -- initials only ("Laura S.") or a role that is not a route in: skip
    if length(regexp_replace(e->>'last_name', '[^[:alpha:]]', '', 'g')) < 2 or role_score(e->>'position') = 0 then
      v_rej := v_rej + 1; continue; end if;
    v_li := nullif(lower(btrim(coalesce(e->>'linkedin', ''))), '');
    if v_li is not null and v_li !~ 'linkedin\.com/in/' then v_li := null; end if;
    v_email := nullif(lower(btrim(coalesce(e->>'email', ''))), '');
    -- the email must sit on the company's domain (or, with no website on file, on the domain of the page it was published on)
    if v_email is not null and (v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'
       or registrable_domain(split_part(v_email, '@', 2)) is distinct from coalesce(v_domain, registrable_domain(e->>'source_url'))) then
      v_email := null; end if;
    v_ig := nullif(btrim(coalesce(e->>'instagram', '')), '');
    select id into k from contacts
     where company_id = c.id and (
           (v_li is not null and lower(coalesce(linkedin, '')) = v_li)
        or (v_email is not null and lower(coalesce(email, '')) = v_email)
        or (lower(coalesce(first_name, '')) = lower(btrim(e->>'first_name')) and lower(coalesce(last_name, '')) = lower(btrim(e->>'last_name'))))
     limit 1;
    if k is null then
      insert into contacts (company_id, first_name, last_name, position, linkedin, instagram, email, email_status, email_source_url,
                            source, source_url, source_type, route_type, relationship_owner, status, confidence, identity_status, notes)
      values (c.id, btrim(e->>'first_name'), btrim(e->>'last_name'), nullif(btrim(coalesce(e->>'position', '')), ''), v_li, v_ig,
              v_email, case when v_email is not null then 'UNVERIFIED' else 'NOT_FOUND' end, case when v_email is not null then e->>'source_url' end,
              'Workflow 19 contact enrichment', e->>'source_url', coalesce(e->>'source_type', 'SEARCH_RESULT'),
              case when v_email is not null then 'PERSON_EMAIL' when v_li is not null then 'LINKEDIN' when v_ig is not null then 'INSTAGRAM' end,
              'Adam Elshazly', 'NEW', case when e->>'source_type' in ('OFFICIAL_SITE', 'LINKEDIN', 'PRESS', 'INTERVIEW', 'SPEAKER_PAGE', 'MEDIA_KIT', 'PARTNERSHIP_PAGE') then 80 else 60 end,
              -- a LinkedIn profile that names the company only in its body text (education, past roles, memberships)
              -- does not prove the person works there: leave it for review (null lets contact_intake decide otherwise)
              case when e->>'employer_confirmed' = 'false' then 'NEEDS_VERIFICATION' end,
              case when e->>'source_type' in ('OFFICIAL_SITE', 'PRESS', 'INTERVIEW', 'SPEAKER_PAGE', 'MEDIA_KIT', 'PARTNERSHIP_PAGE') and nullif(btrim(coalesce(e->>'position', '')), '') is not null
                   then 'SOURCE-BACKED: name and role published at ' || (e->>'source_url')
                   else 'Found by search (' || coalesce(e->>'source_type', 'SEARCH_RESULT') || '): ' || (e->>'source_url') end
              || case when v_email is not null then chr(10) || 'Email publicly listed at ' || (e->>'source_url') || '; address not checked.' else '' end
              || case when e->>'employer_confirmed' = 'false' then chr(10) || 'Company named in the profile text, not the headline: current employer unconfirmed.' else '' end);
      v_new := v_new + 1;
    else
      update contacts set
        position = coalesce(position, nullif(btrim(coalesce(e->>'position', '')), '')),
        linkedin = coalesce(nullif(linkedin, ''), v_li),
        instagram = coalesce(nullif(instagram, ''), v_ig),
        email = coalesce(email, v_email),
        email_status = case when email is null and v_email is not null then 'UNVERIFIED' else email_status end,
        email_source_url = case when email is null and v_email is not null then e->>'source_url' else email_source_url end,
        source_url = coalesce(source_url, e->>'source_url'),
        source_type = coalesce(source_type, e->>'source_type'),
        route_type = coalesce(route_type, case when v_email is not null then 'PERSON_EMAIL' when v_li is not null then 'LINKEDIN' when v_ig is not null then 'INSTAGRAM' end),
        notes = coalesce(notes, '') || chr(10) || 'Enriched ' || to_char(now(), 'DD Mon YYYY') || ' from ' || (e->>'source_url')
      where id = k;
      v_upd := v_upd + 1;
    end if;
  end loop;

  for e in select * from jsonb_array_elements(coalesce(p->'inboxes', '[]'::jsonb)) loop
    v_email := nullif(lower(btrim(coalesce(e->>'email', ''))), '');
    if v_email is null or coalesce(e->>'source_url', '') = '' or v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'
       or registrable_domain(split_part(v_email, '@', 2)) is distinct from coalesce(v_domain, registrable_domain(e->>'source_url'))
       or coalesce(e->>'purpose', '') || ' ' || v_email ~* '(subject access|privacy|gdpr|data protection|dpo|career|jobs|recruit|hr@|unsubscribe|noreply|no-reply|support|customer|helpdesk|help@|returns|orders|billing|invoice|accounts@)' then
      v_rej := v_rej + 1; continue; end if;
    if not exists (select 1 from contacts where company_id = c.id and lower(coalesce(email, '')) = v_email) then
      insert into contacts (company_id, position, email, email_status, email_source_url, source, source_url, source_type, route_type, relationship_owner, status, confidence, notes)
      values (c.id, coalesce(nullif(e->>'purpose', ''), 'Company inbox'), v_email, 'UNVERIFIED', e->>'source_url', 'Workflow 19 contact enrichment',
              e->>'source_url', coalesce(e->>'source_type', 'OFFICIAL_SITE'), 'COMPANY_INBOX', 'Adam Elshazly', 'NEW', 50,
              'Company inbox publicly listed at ' || (e->>'source_url') || ' (not a named person; address not checked).');
      v_inbox := v_inbox + 1;
    end if;
  end loop;

  for u in select * from jsonb_array_elements(coalesce(p->'usage', '[]'::jsonb)) loop
    insert into ai_usage (workflow, purpose, model, company_id, input_tokens, output_tokens, thinking_tokens, est_cost_usd, status)
    values ('19', 'ENRICH', coalesce(u->>'model', 'models/gemini-3.1-flash-lite'), c.id, coalesce((u->>'input_tokens')::int, 0), coalesce((u->>'output_tokens')::int, 0),
            coalesce((u->>'thinking_tokens')::int, 0),
            ai_cost_usd(coalesce(u->>'model', 'models/gemini-3.1-flash-lite'), coalesce((u->>'input_tokens')::int, 0), coalesce((u->>'output_tokens')::int, 0) + coalesce((u->>'thinking_tokens')::int, 0)),
            coalesce(u->>'status', 'OK'));
  end loop;

  update companies set last_enriched_at = now(), enrichment_attempts = coalesce(enrichment_attempts, 0) + 1 where id = c.id;
  return jsonb_build_object('ok', true, 'new_people', v_new, 'updated_people', v_upd, 'inboxes', v_inbox, 'rejected', v_rej,
                            'universe', universe_reclassify_company(c.id));
end $$;
revoke all on function public.enrich_company_routes(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- planner + save follow the contact hierarchy
create or replace function public.commercial_director_plan(p_dry_run boolean default true, p_target int default null, p_replan boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_mix jsonb := (select value from system_config where key = 'acquisition_mix');
        v_target int := coalesce(p_target, ((select value from system_config where key = 'daily_touch_target')->>'target')::int, 20);
        v_total int := 0; v_lane text; v_quota int; v_left int; r record; v_out jsonb;
        p_refresh boolean := coalesce((select (value->>'refresh_stale_drafts')::boolean from system_config where key = 'planner_options'), false);
begin
  if p_replan then delete from outreach_candidates where run_date = current_date and status = 'PLANNED' and dry_run = p_dry_run; end if;
  if not exists (select 1 from outreach_candidates where run_date = current_date and dry_run = p_dry_run) then
    create temp table _pool on commit drop as
    with base as (
      select c.id company_id, c.name, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane,
             c.company_type, c.universe_reason, c.instagram company_instagram, company_warm_route(c.id) warm,
             (select o.id from opportunities o where o.company_id = c.id and o.status not in ('WON', 'LOST', 'ARCHIVED') order by o.priority desc nulls last, o.created_at desc limit 1) opp_id
        from companies c
       where c.universe_status = 'QUALIFIED'
         -- an agent's own watchlist save (scored below its minimum) is never planned
         and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'
         and relationship_state(c.id) = 'COLD'
         -- never two agents on one company, never anything already queued or recently planned
         and not exists (select 1 from tasks t where t.company_id = c.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
                          and (t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY|OUTREACH READY|VERIFY|DRAFT REVIEW|FOLLOW UP|HOLD|ADAM PERSONAL OUTREACH|APPROVE OUTREACH|RECONNECT|WARM ROUTE|MEETING)'
                               or t.task_type = 'SALES_OUTREACH_APPROVAL')
                          -- refresh (dry run only): an unsent hand-send draft older than 3 days may be re-drafted for comparison
                          and not (p_refresh and p_dry_run and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|EMAIL READY)'
                                   and t.created_at < now() - interval '3 days'))
         and not exists (select 1 from outreach_candidates oc where oc.company_id = c.id and oc.status <> 'SKIPPED' and oc.created_at > now() - interval '30 days'
                          -- a dry-run test draft never blocks the live plan unless a person reviewed it
                          and (oc.dry_run = p_dry_run or oc.review_source = 'HUMAN_REVIEWED'))
         and not exists (select 1 from outbound_emails ob where ob.company_id = c.id and ob.status in ('QUEUED', 'CLAIMED', 'DRAFTED', 'SENT') and ob.created_at > now() - interval '60 days')),
    pick as (
      select b.*, coalesce(k.id, ib.id) contact_id, k.first_name, k.last_name, coalesce(k.position, ib.position) position,
             coalesce(k.email, ib.email) email, coalesce(k.email_status, ib.email_status) email_status, k.linkedin, k.instagram,
        case
          -- contact hierarchy (Adam, 7 Oct): 1 named person + business email (verified, or publicly listed with its source), 2 LinkedIn,
          -- 3 Instagram (the person's, else the company account), then LinkedIn by name; 4 the right company inbox when no person is known
          when email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and (k.email_status = 'VERIFIED' or (k.email_status = 'UNVERIFIED' and coalesce(k.email_source_url, '') <> '')) then 'EMAIL'
          when coalesce(k.linkedin, '') ~* 'linkedin\.com/in/' then 'LINKEDIN'
          when coalesce(k.instagram, b.company_instagram, '') <> '' and b.lane in ('BRANDS', 'WEDDINGS', 'PARTNERSHIPS', 'TRAVEL_PRIVATE')
               and coalesce(b.company_type, '') !~* '(bank|wealth|law|legal|consult|invest|family|financial|insurance|asset|equity)' then 'INSTAGRAM'
          when k.id is not null then 'LINKEDIN'
          else 'EMAIL' end channel,
        row_number() over (partition by b.lane order by (k.id is not null) desc, (b.warm is not null) desc,
          coalesce((select o.priority from opportunities o where o.id = b.opp_id), 0) desc, b.name) rn
      from base b
      left join lateral (select * from contacts k where k.company_id = b.company_id and not coalesce(k.do_not_contact, false)
                      and k.identity_status = 'CONFIRMED' and k.position is not null and role_score(k.position) > 0
                      and length(btrim(coalesce(k.first_name, ''))) >= 2 and length(btrim(coalesce(k.last_name, ''))) >= 2
                    order by (role_score(k.position) >= 4) desc, (email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and (k.email_status = 'VERIFIED' or coalesce(k.email_source_url, '') <> '')) desc,
                             (coalesce(k.linkedin, '') ~* 'linkedin\.com/in/') desc, (coalesce(k.instagram, '') <> '') desc, role_score(k.position) desc, k.confidence desc nulls last limit 1) k on true
      -- tier 4: a published partnerships / sales / press / events / general inbox (never support, careers or admin)
      left join lateral (select * from contacts i where i.company_id = b.company_id and i.route_type = 'COMPANY_INBOX' and i.email is not null
                           and not coalesce(i.do_not_contact, false) and coalesce(i.email_source_url, '') <> ''
                           and coalesce(i.position, '') || ' ' || i.email !~* '(support|customer|helpdesk|returns|orders|billing|invoice|accounts@|career|jobs|recruit|privacy|gdpr|noreply|no-reply)'
                         order by (coalesce(i.position, '') || ' ' || i.email ~* '(partner|collab|sales|commercial|business|press|pr@|media|events?|wedding|brand|marketing)') desc,
                                  i.created_at limit 1) ib on true
      where k.id is not null or ib.id is not null
         or (coalesce(b.company_instagram, '') <> '' and b.lane in ('BRANDS', 'WEDDINGS', 'PARTNERSHIPS', 'TRAVEL_PRIVATE')
             and coalesce(b.company_type, '') !~* '(bank|wealth|law|legal|consult|invest|family|financial|insurance|asset|equity)'))
    select * from pick;

    -- 1) each lane up to its quota (scaled to the target), 2) unused slots to the best remaining candidates anywhere
    for v_lane, v_quota in select key, round((value::text)::numeric * v_target / 20.0)::int from jsonb_each(v_mix) loop
      insert into outreach_candidates (run_date, dry_run, lane, company_id, contact_id, opportunity_id, channel, warm_route, why_now, evidence, angle)
      select current_date, p_dry_run, p.lane, p.company_id, p.contact_id, p.opp_id, p.channel, p.warm,
             (select coalesce(o.commercial_trigger, o.reason) from opportunities o where o.id = p.opp_id),
             p.universe_reason, nullif(concat_ws(' ', prospect_angle_prefix(p.company_id), (select o.angle from opportunities o where o.id = p.opp_id)), '')
        from _pool p where p.lane = v_lane and p.rn <= v_quota;
    end loop;
    select count(*) into v_total from outreach_candidates where run_date = current_date and dry_run = p_dry_run;
    v_left := v_target - v_total;
    if v_left > 0 then
      insert into outreach_candidates (run_date, dry_run, lane, company_id, contact_id, opportunity_id, channel, warm_route, why_now, evidence, angle)
      select current_date, p_dry_run, p.lane, p.company_id, p.contact_id, p.opp_id, p.channel, p.warm,
             (select coalesce(o.commercial_trigger, o.reason) from opportunities o where o.id = p.opp_id),
             p.universe_reason, nullif(concat_ws(' ', prospect_angle_prefix(p.company_id), (select o.angle from opportunities o where o.id = p.opp_id)), '')
        from _pool p
       where not exists (select 1 from outreach_candidates oc where oc.company_id = p.company_id and oc.run_date = current_date and oc.dry_run = p_dry_run)
       order by (p.warm is not null) desc, (p.contact_id is not null) desc,
                -- leftovers follow the agent weights too: sports stays selective
                p.rn::numeric / greatest(coalesce((v_mix->>p.lane)::numeric, 0), 0.5)
       limit v_left;
    end if;
  end if;

  select jsonb_build_object(
    'run_date', current_date, 'dry_run', p_dry_run, 'target', v_target,
    'floor', ((select value from system_config where key = 'daily_touch_target')->>'floor')::int,
    'planned', count(*), 'by_lane', (select jsonb_object_agg(lane, n) from (select lane, count(*) n from outreach_candidates
        where run_date = current_date and dry_run = p_dry_run group by 1) s),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'candidate_id', oc.id, 'lane', oc.lane, 'channel', oc.channel, 'status', oc.status,
      'company', c.name, 'company_type', c.company_type, 'country', c.country, 'website', c.website,
      'first_name', k.first_name, 'last_name', k.last_name, 'position', k.position,
      'email', case when oc.channel = 'EMAIL' then k.email end, 'email_status', case when oc.channel = 'EMAIL' then k.email_status end, 'linkedin', k.linkedin, 'instagram', coalesce(k.instagram, c.instagram),
      'warm_route', oc.warm_route, 'why_now', oc.why_now, 'evidence', left(coalesce(oc.evidence, '') || ' ' || coalesce(c.notes, ''), 1500),
      'angle', oc.angle, 'contact_notes', left(k.notes, 600)) order by oc.lane, oc.created_at) filter (where oc.status = 'PLANNED'), '[]'::jsonb))
  into v_out
  from outreach_candidates oc join companies c on c.id = oc.company_id left join contacts k on k.id = oc.contact_id
  where oc.run_date = current_date and oc.dry_run = p_dry_run;
  return v_out;
end $$;

revoke all on function public.commercial_director_plan(boolean, int, boolean) from public, anon, authenticated;

create or replace function public.outreach_candidate_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare oc outreach_candidates%rowtype; c companies%rowtype; k contacts%rowtype; v_status text; v_title text; v_task uuid; u jsonb;
        v_in int := 0; v_out int := 0; v_cost numeric := 0; v_calls int := 0; v_rl boolean := false; v_ok boolean := false;
        v_banned text := '(i am reaching out|i''m reaching out|i wanted to reach out|i wanted to introduce|been following|love what you)';
begin
  select * into oc from outreach_candidates where id = (p->>'candidate_id')::uuid;
  if oc.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  select * into c from companies where id = oc.company_id;
  select * into k from contacts where id = oc.contact_id;
  for u in select * from jsonb_array_elements(coalesce(p->'usage', '[]'::jsonb)) loop
    insert into ai_usage (workflow, purpose, model, candidate_id, company_id, input_tokens, output_tokens, thinking_tokens, est_cost_usd, status)
    values ('18', coalesce(u->>'purpose', 'DRAFT'), coalesce(u->>'model', 'unknown'), oc.id, oc.company_id,
            coalesce((u->>'input_tokens')::int, 0), coalesce((u->>'output_tokens')::int, 0), coalesce((u->>'thinking_tokens')::int, 0),
            ai_cost_usd(u->>'model', coalesce((u->>'input_tokens')::int, 0), coalesce((u->>'output_tokens')::int, 0) + coalesce((u->>'thinking_tokens')::int, 0)),
            coalesce(u->>'status', 'OK'));
    v_calls := v_calls + 1;
    v_in := v_in + coalesce((u->>'input_tokens')::int, 0);
    v_out := v_out + coalesce((u->>'output_tokens')::int, 0) + coalesce((u->>'thinking_tokens')::int, 0);
    v_cost := v_cost + ai_cost_usd(u->>'model', coalesce((u->>'input_tokens')::int, 0), coalesce((u->>'output_tokens')::int, 0) + coalesce((u->>'thinking_tokens')::int, 0));
    v_rl := v_rl or u->>'status' = 'RATE_LIMITED';
    v_ok := v_ok or coalesce(u->>'status', 'OK') = 'OK';
  end loop;
  v_status := case when p->>'qa_status' = 'PASS' and coalesce(p->>'draft', '') <> '' and lower(p->>'draft') !~ v_banned then 'READY'
                   -- never drafted because every model call was rate-limited: release the account so it is planned again tomorrow
                   when v_rl and not v_ok then 'SKIPPED'
                   else 'REVIEW_REQUIRED' end;
  update outreach_candidates set subject = nullif(p->>'subject', ''), draft = p->>'draft', qa_status = p->>'qa_status', qa_issues = p->'qa_issues',
         system_subject = nullif(p->>'subject', ''), system_draft = p->>'draft', system_qa_status = p->>'qa_status', system_qa_issues = p->'qa_issues',
         first_pass_ok = (p->>'first_pass_ok')::boolean, redraft_ok = (p->>'redraft_ok')::boolean, rate_limited = v_rl,
         model_calls = v_calls, tokens_in = v_in, tokens_out = v_out, est_cost_usd = v_cost, review_source = 'SYSTEM', batch = p->>'batch',
         attempts = coalesce((p->>'attempts')::int, attempts), model = p->>'model', status = v_status, updated_at = now()
   where id = oc.id;
  if not oc.dry_run and v_status <> 'SKIPPED' then
    v_title := case when v_status = 'READY' then
                 case oc.channel when 'EMAIL' then 'EMAIL READY' when 'INSTAGRAM' then 'INSTAGRAM DM READY' else 'LINKEDIN MESSAGE READY' end
               else 'DRAFT REVIEW' end
               || ' -- ' || c.name || coalesce(' · ' || nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), ''), '');
    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
    values (oc.company_id, oc.contact_id, oc.opportunity_id, v_title,
            'Lane: ' || oc.lane || ' · Channel: ' || oc.channel || coalesce(' · Warm route: ' || oc.warm_route, '') || chr(10) ||
            case when oc.channel = 'EMAIL' and k.email is not null then 'To: ' || k.email ||
                 case when k.email_status = 'VERIFIED' then ' (verified)' else ' (publicly listed at ' || coalesce(k.email_source_url, 'source on file') || '; not verified)' end || chr(10)
                 when oc.channel = 'INSTAGRAM' then 'Instagram: @' || coalesce(nullif(k.instagram, ''), c.instagram, '?') || chr(10)
                 when oc.channel = 'LINKEDIN' and coalesce(k.linkedin, '') <> '' then 'LinkedIn: ' || k.linkedin || chr(10) else '' end ||
            coalesce('Why now: ' || oc.why_now || chr(10), '') ||
            case when v_status = 'READY' then 'Draft source: workflow 18 (passed the gate)' || chr(10)
                 else 'QA failed after one redraft: ' || coalesce((p->'qa_issues')::text, '') || chr(10) end || chr(10) ||
            coalesce('Subject: ' || nullif(p->>'subject', '') || chr(10) || chr(10), '') || coalesce(p->>'draft', '') || chr(10) || chr(10) ||
            'Send it yourself, then mark done (logs the send, books follow-ups). Dismiss = not sent.',
            'CONTACT_RESOLUTION', 'Adam', 'Commercial Director (workflow 18)', case when oc.warm_route is not null then 85 else 75 end, 'OPEN', now())
    returning id into v_task;
    update outreach_candidates set task_id = v_task where id = oc.id;
  end if;
  return jsonb_build_object('ok', true, 'status', v_status, 'task_id', v_task, 'cost_usd', v_cost, 'calls', v_calls);
end $$;
revoke all on function public.outreach_candidate_save(jsonb) from public, anon, authenticated;
