-- Priority queue, not caps (Adam, 29 Oct 2026, evening). NOYA should never run out of strong companies to contact.
-- No hard ceiling on potential leads, qualified companies, contact-ready companies, public emails found, named decision makers,
-- Hunter-ready contacts, email-ready or draft-ready opportunities. Discovery never waits on Adam's review backlog.
-- What stays: the quality gates, human approval, controlled sending (nothing cold sends automatically), and ranking:
--   TOP 5 (send / review today) → NEXT 20 (high priority) → READY POOL (every other qualified, email-ready account)
--   → RESEARCHING (still being enriched) → HOLD (not commercially justified now).
-- When Adam clears an item from the Top 5 the desk is read again and the next one is promoted at once.

-- 1. Draft supply: the reserve caps (10 unsent emails, 5 open LinkedIn / Instagram items) are removed. The planner keeps its
--    nightly throughput (the daily target plus the email top-up: what workflow 18 drafts in its three runs) and its gates.
update public.system_config
   set value = (value - 'max_unsent_email_drafts' - 'max_open_social_drafts')
               || jsonb_build_object('caps_removed_at', now(),
                    'removed_caps', jsonb_build_object('max_unsent_email_drafts', value->'max_unsent_email_drafts', 'max_open_social_drafts', value->'max_open_social_drafts'),
                    'note', 'Adam, 29 Oct 2026: no cap on prepared email opportunities; ranking decides what Adam sees (Top 5, Next 20, Ready pool). Nothing cold sends automatically.'),
       updated_at = now()
 where key = 'email_reserve';

do $patch$
declare src text := pg_get_functiondef('public.commercial_director_plan(boolean, integer, boolean)'::regprocedure);
  -- caps only when configured (none now)
  a1 text := $a$select coalesce((value->>'max_unsent_email_drafts')::int, 30), coalesce((value->>'max_open_social_drafts')::int, 20) into v_cap_e, v_cap_s$a$;
  b1 text := $a$select (value->>'max_unsent_email_drafts')::int, (value->>'max_open_social_drafts')::int into v_cap_e, v_cap_s$a$;
  a2 text := $a$  if v_cap_e is not null then$a$;
  b2 text := $a$  if v_cap_e is not null or v_cap_s is not null then$a$;
  a3 text := $a$((z.channel = 'EMAIL' and z.rn > greatest(0, v_cap_e - v_open_e)) or (z.channel <> 'EMAIL' and z.rn > greatest(0, v_cap_s - v_open_s)))$a$;
  b3 text := $a$((z.channel = 'EMAIL' and v_cap_e is not null and z.rn > greatest(0, v_cap_e - v_open_e)) or (z.channel <> 'EMAIL' and v_cap_s is not null and z.rn > greatest(0, v_cap_s - v_open_s)))$a$;
  -- draft gates (29 Oct): a project to talk about (an open opportunity) and a reason now, on top of the existing gates
  -- (qualified, cold, spend allowed, not on hold, right person or department, a usable route, one active route per company)
  a4 text := $a$        from pick1 p where p.channel is not null)$a$;
  b4 text := $a$        from pick1 p where p.channel is not null and p.opp_id is not null
         and exists (select 1 from opportunities o where o.id = p.opp_id and coalesce(nullif(btrim(o.commercial_trigger), ''), nullif(btrim(o.reason), '')) is not null))$a$;
begin
  if strpos(src, a1) = 0 or strpos(src, a2) = 0 or strpos(src, a3) = 0 or strpos(src, a4) = 0 then
    raise exception 'commercial_director_plan changed: anchors not found';
  end if;
  execute replace(replace(replace(replace(src, a1, b1), a2, b2), a3, b3), a4, b4);
end $patch$;

-- 2. Discovery never waits: the backlog throttle stays off and each run researches the code ceiling (12) instead of 10.
update public.system_config
   set value = value || jsonb_build_object('normal_research_cap', 12, 'reduced_research_cap', 12, 'paused_research_cap', 12,
                 'note', 'Adam, 29 Oct 2026: discovery never pauses for the review backlog; the per-run research count is throughput, not a ceiling on the universe.'),
       updated_at = now()
 where key = 'discovery_throttle';

-- 3. NEXT 20: the same score as the Top 5 (outreach_top5 is copied, not rewritten, so the two rank identically).
do $patch$
declare src text := pg_get_functiondef('public.outreach_top5(jsonb)'::regprocedure);
  a1 text := 'FUNCTION public.outreach_top5(d jsonb)';
  a2 text := $a$from (select * from r where per_dir <= 2 order by score desc limit 5) q$a$;
  b2 text := $a$from (select * from r where ref not in (select x->>'ref' from jsonb_array_elements(outreach_top5(d)) x) order by score desc limit 20) q$a$;
begin
  if strpos(src, a1) = 0 or strpos(src, a2) = 0 then raise exception 'outreach_top5 changed: anchors not found'; end if;
  execute replace(replace(src, a1, 'FUNCTION public.outreach_next20(d jsonb)'), a2, b2);
end $patch$;
revoke all on function public.outreach_next20(jsonb) from public, anon;

create or replace function public.hq_outreach_desk() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); d jsonb;
begin
  d := outreach_desk();
  return d || jsonb_build_object('top5', outreach_top5(d), 'next20', outreach_next20(d), 'linkedin', linkedin_board(),
                                 'meeting_assist', meeting_assist_board(), 'studio_ready', studio_ready_board());
end $$;

-- 4. The pipeline under the Top 5: visibility, not a cap. Every qualified account appears once.
--    READY POOL: cold, spend allowed, not on hold, with a usable email route (verified, verified inbox or general,
--    an inbox the company publishes, or a named address it publishes itself). Today's five come from here.
--    CONTACT RESEARCH: the same accounts still being enriched (person, route or verification missing).
--    HOLD: qualified but not commercially justified now (held, a sprint HOLD, or a class we do not spend on).
--    IN CONVERSATION: already talking (not a cold lead).
create or replace function public.commercial_pipeline() returns jsonb
language plpgsql stable security definer set search_path = public set statement_timeout = '55s' as $$
declare v jsonb;
begin
  with q as (select c.id, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane,
                    coalesce(c.outreach_hold_until, '-infinity'::timestamptz) > now() held
               from companies c
              where c.universe_status = 'QUALIFIED'
                and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'),
  s as materialized (select q.*, relationship_state(q.id) rel, outreach_spend_ok(q.id) ok from q),
  e as materialized (select s.*, case when s.rel = 'COLD' and s.ok and not s.held then company_email_state(s.id)->>'state' end es from s),
  t as (select e.*, case when e.rel <> 'COLD' then 'IN_CONVERSATION'
                         when not e.ok or e.held then 'HOLD'
                         when e.es in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL') then 'READY_POOL'
                         else 'CONTACT_RESEARCH' end tier from e)
  select jsonb_build_object(
    'qualified', count(*),
    'ready_pool', count(*) filter (where tier = 'READY_POOL'),
    'contact_research', count(*) filter (where tier = 'CONTACT_RESEARCH'),
    'hold', count(*) filter (where tier = 'HOLD'),
    'in_conversation', count(*) filter (where tier = 'IN_CONVERSATION'),
    'ready_by_route', (select coalesce(jsonb_object_agg(es, n), '{}'::jsonb) from (select es, count(*) n from t where tier = 'READY_POOL' group by es) x),
    'research_by_state', (select coalesce(jsonb_object_agg(coalesce(es, 'UNKNOWN'), n), '{}'::jsonb) from (select es, count(*) n from t where tier = 'CONTACT_RESEARCH' group by es) x),
    'ready_by_lane', (select coalesce(jsonb_object_agg(coalesce(lane, 'OTHER'), n), '{}'::jsonb) from (select lane, count(*) n from t where tier = 'READY_POOL' group by lane) x),
    'public_profiles', jsonb_build_object('observed', (select count(*) from public_profiles),
                         'emails', (select count(*) from public_profiles where email_class in ('OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL')),
                         'prospects', (select count(*) from public_profiles where status = 'PROSPECT')),
    'computed_at', now())
  into v from t;
  return v;
end $$;
revoke all on function public.commercial_pipeline() from public, anon, authenticated;

-- The Dashboard snapshot (rebuilt every 5 minutes) carries the pipeline counts; the live desk carries Next 20.
do $patch$
declare src text := pg_get_functiondef('public.hq_ceo_dashboard()'::regprocedure);
  a text := E'  into v;\n  return v;\nend';
  b text := E'  into v;\n  return v || jsonb_build_object(''pipeline'', commercial_pipeline());\nend';
begin
  if strpos(src, 'commercial_pipeline') > 0 then return; end if;
  if strpos(src, a) = 0 then raise exception 'hq_ceo_dashboard changed: anchor not found'; end if;
  execute replace(src, a, b);
end $patch$;

-- 5. Instagram-first prospects for the discovery departments. A profile found by bio search that matches no CRM company and
--    publishes its own website (or a business email on its own domain) is offered to the department that owns its lane, in the
--    same shape as a search result, so the existing research, scoring and qualification decide. Known domains are left out.
create or replace function public.instagram_prospects(p_limit int default 40) returns jsonb
language sql stable security definer set search_path = public as $$
  with p as (
    select pp.*, coalesce(case when pp.bio_link ~* '^https?://' then registrable_domain(pp.bio_link) end,
                          case when pp.public_email is not null and email_local_class(pp.public_email) <> 'EXCLUDED'
                                then registrable_domain(split_part(lower(pp.public_email), '@', 2)) end) dom
      from public_profiles pp
     where pp.status = 'PROSPECT' and pp.company_id is null and pp.observed_at > now() - interval '30 days' and not coalesce(pp.is_private, false))
  select coalesce(jsonb_agg(jsonb_build_object(
           'company_name', coalesce(nullif(btrim(p.display_name), ''), p.handle), 'website', 'https://' || p.dom, 'domain', p.dom,
           'source_url', p.profile_url, 'prospect_lane', p.lane, 'lane', 'DIRECT', 'search_query', 'instagram:' || coalesce(p.found_by, 'bio search'),
           'search_evidence', 'Instagram profile ' || p.profile_url || ': ' || left(coalesce(p.bio, ''), 300)
                              || coalesce(' · ' || p.followers || ' followers', '') || case when p.is_verified then ' · verified account' else '' end)
           order by p.observed_at desc), '[]'::jsonb)
    from (select * from p
           where p.dom is not null
             and p.dom !~ '(linktr\.ee|beacons\.ai|instagram\.com|facebook\.com|tiktok\.com|youtube\.com|youtu\.be|wa\.me|bit\.ly|gmail\.com|hotmail\.|yahoo\.|outlook\.|icloud\.com)'
             and not exists (select 1 from companies c where registrable_domain(c.website) = p.dom)
           order by p.observed_at desc limit greatest(coalesce(p_limit, 40), 0)) p;
$$;
revoke all on function public.instagram_prospects(int) from public, anon;

do $patch$
declare src text := pg_get_functiondef('public.discovery_context()'::regprocedure);
  a text := $a$    'generated_at', now()$a$;
  b text := $a$    'instagram_prospects', instagram_prospects(40),
    'generated_at', now()$a$;
begin
  if strpos(src, 'instagram_prospects') > 0 then return; end if;
  if strpos(src, a) = 0 then raise exception 'discovery_context changed: anchor not found'; end if;
  execute replace(src, a, b);
end $patch$;

-- A prospect that the departments have since saved as a company is linked to it (and its published email classified);
-- one they rejected leaves the prospect list. Runs every 30 minutes.
create or replace function public.public_profiles_link() returns jsonb
language plpgsql volatile security definer set search_path = public set statement_timeout = '55s' as $$
declare r record; v_linked int := 0; v_rej int := 0;
begin
  for r in select pp.id, pp.raw, pp.lane, c.id company_id, c.universe_status
             from public_profiles pp
             join companies c on registrable_domain(c.website) = coalesce(case when pp.bio_link ~* '^https?://' then registrable_domain(pp.bio_link) end,
                                                                         registrable_domain(split_part(lower(pp.public_email), '@', 2)))
            where pp.status = 'PROSPECT' and pp.company_id is null loop
    if r.universe_status = 'QUALIFIED' then
      perform public_profile_record(r.raw, 'DISCOVERY_LINK', null, r.company_id);
      update public_profiles set status = 'QUALIFIED', updated_at = now() where id = r.id;
      v_linked := v_linked + 1;
    elsif r.universe_status in ('EXCLUDED', 'PARKED') then
      update public_profiles set status = 'REJECTED', company_id = r.company_id, updated_at = now() where id = r.id;
      v_rej := v_rej + 1;
    end if;
  end loop;
  return jsonb_build_object('linked', v_linked, 'rejected', v_rej);
end $$;
revoke all on function public.public_profiles_link() from public, anon, authenticated;

select cron.schedule('public-profiles-link', '23,53 * * * *', 'select public.public_profiles_link()');
