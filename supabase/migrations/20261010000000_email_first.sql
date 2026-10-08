-- Email-first outreach (Adam, 8 Oct 2026 — final amendment). Email is the primary cold-outreach channel; LinkedIn is a
-- fallback, Instagram a selective lifestyle fallback. LinkedIn becomes the channel only when the company is qualified, the
-- right person is confirmed, public email research for that person is complete and no VALID_VERIFIED email exists — and the
-- desk then says LINKEDIN FALLBACK — EMAIL EXHAUSTED with the research evidence.
--   1. contact_email_route(): one route state per decision maker
--        VERIFIED            their own VALID_VERIFIED business email
--        VERIFIED_INBOX      a VALID_VERIFIED department inbox (partnerships@, sales@, events@ …) for their attention
--        NEEDS_VERIFICATION  an address was found and waits for the provider check (at most verification_wait_days)
--        RESEARCH_PENDING    public email research has not covered this person yet (never run, older than them, or stale)
--        EXHAUSTED           research done, nothing verifiable: fallback LINKEDIN / INSTAGRAM, with the evidence
--   2. company_email_state() / prospect_routes(): the best route per qualified company.
--   3. director_channel_health(): per Director — verified, needs verification, email gap, LinkedIn fallback, Instagram
--      fallback, needs review — and the EMAIL COVERAGE RATE (qualified with a VALID_VERIFIED email / qualified with a
--      confirmed decision maker).
--   4. email_finder_log: the provider lookup (Hunter Email Finder, by name + domain) used only after the company and the
--      person are established and public research is exhausted. A provider result is saved only when it verifies valid;
--      nothing is ever guessed or constructed here.
-- Nothing in this file sends anything.

alter table public.email_research add column if not exists checked jsonb not null default '{}'::jsonb;
alter table public.outreach_candidates add column if not exists channel_reason text;

create table if not exists public.email_finder_log (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid references public.contacts(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  domain text,
  attempted_at timestamptz not null default now(),
  status_code int,
  email text,
  score int,
  verification text,
  outcome text not null check (outcome in ('VERIFIED', 'NOT_VERIFIED', 'NOT_FOUND', 'ERROR')),
  sources jsonb not null default '[]'::jsonb,
  execution text
);
create index if not exists email_finder_log_contact on public.email_finder_log (contact_id, attempted_at desc);
alter table public.email_finder_log enable row level security;
revoke all on public.email_finder_log from anon, authenticated;

insert into public.system_config (key, value, note) values ('email_first', jsonb_build_object(
  'research_max_age_days', 60, 'verification_wait_days', 10,
  'brand_daily_verified_target', jsonb_build_array(8, 12), 'wedding_weekly_send_target', jsonb_build_array(12, 18),
  'coverage_alert_pct', 30, 'coverage_alert_min_dm', 8,
  'finder_daily_cap', 2, 'finder_reserve_credits', 3,
  'priority_lanes', jsonb_build_array('BRANDS', 'WEDDINGS', 'TRAVEL', 'HOSPITALITY', 'CORPORATE')),
  'Email-first outreach rules (Adam, 8 Oct 2026)')
on conflict (key) do update set value = excluded.value, note = excluded.note, updated_at = now();

-- ---------------------------------------------------------------- 1. route state per decision maker
create or replace function public.contact_email_route(p_contact uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare k contacts%rowtype; c companies%rowtype; er email_research%rowtype; v_inbox contacts%rowtype; v_pend contacts%rowtype; v_find email_finder_log%rowtype;
        v_cfg jsonb := coalesce((select value from system_config where key = 'email_first'), '{}'::jsonb);
        v_max int; v_wait int; v_st text; v_ver text; v_fb text; v_ev text; v_kinds text;
begin
  v_max := coalesce((v_cfg->>'research_max_age_days')::int, 60);
  v_wait := coalesce((v_cfg->>'verification_wait_days')::int, 10);
  select * into k from contacts where id = p_contact;
  if k.id is null then return jsonb_build_object('state', 'NO_PERSON', 'label', 'No decision maker confirmed yet'); end if;
  select * into c from companies where id = k.company_id;
  v_st := email_state_v3(k.email, k.email_status, k.email_source_url, k.email_verification_provider);
  if v_st = 'VALID_VERIFIED' and email_local_class(k.email) <> 'EXCLUDED' then
    return jsonb_build_object('state', 'VERIFIED', 'email', lower(btrim(k.email)), 'label', 'Verified email');
  end if;
  -- a verified department inbox for their attention (partnership pitches never go to press / PR inboxes)
  select i.* into v_inbox from contacts i
   where i.company_id = k.company_id and i.route_type = 'COMPANY_INBOX' and i.email_tier = 2 and not coalesce(i.do_not_contact, false)
     and email_state_v3(i.email, i.email_status, i.email_source_url, i.email_verification_provider) = 'VALID_VERIFIED'
     and not (coalesce(c.partnership_model, 'CONTENT_TALENT') <> 'CONTENT_TALENT' and (coalesce(i.position, '') || ' ' || i.email) ~* '(press|media|communications|comms|\mpr\M)')
   order by i.created_at limit 1;
  if v_inbox.id is not null then
    return jsonb_build_object('state', 'VERIFIED_INBOX', 'email', lower(btrim(v_inbox.email)), 'inbox_id', v_inbox.id,
                              'label', 'Verified ' || lower(coalesce(nullif(v_inbox.position, ''), 'department inbox')) || ' for their attention');
  end if;
  select v.provider_status into v_ver from contact_email_verifications v
   where lower(v.email) = lower(btrim(coalesce(k.email, ''))) and v.provider_status is not null
   order by coalesce(v.checked_at, v.created_at) desc limit 1;
  -- an address found for this person, not yet checked by the provider: it waits for verification (not LinkedIn)
  if coalesce(btrim(k.email), '') <> '' and v_ver is null and v_st in ('PUBLIC_UNVERIFIED', 'UNKNOWN') and email_local_class(k.email) <> 'EXCLUDED'
     and coalesce(k.email_found_at, k.updated_at, k.created_at) > now() - make_interval(days => v_wait) then
    return jsonb_build_object('state', 'NEEDS_VERIFICATION', 'email', lower(btrim(k.email)), 'label', 'Email found — waiting for verification');
  end if;
  select i.* into v_pend from contacts i
   where i.company_id = k.company_id and i.route_type = 'COMPANY_INBOX' and i.email_tier = 2 and not coalesce(i.do_not_contact, false)
     and email_state_v3(i.email, i.email_status, i.email_source_url, i.email_verification_provider) in ('PUBLIC_UNVERIFIED', 'UNKNOWN')
     and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(i.email)) and v.provider_status is not null)
     and coalesce(i.email_found_at, i.created_at) > now() - make_interval(days => v_wait)
     and not (coalesce(c.partnership_model, 'CONTENT_TALENT') <> 'CONTENT_TALENT' and (coalesce(i.position, '') || ' ' || i.email) ~* '(press|media|communications|comms|\mpr\M)')
   order by i.created_at limit 1;
  if v_pend.id is not null then
    return jsonb_build_object('state', 'NEEDS_VERIFICATION', 'email', lower(btrim(v_pend.email)), 'inbox_id', v_pend.id,
                              'label', 'Department inbox found — waiting for verification');
  end if;
  select * into er from email_research where company_id = k.company_id order by researched_at desc limit 1;
  -- research counts as complete only when it covered this person (ran after they were confirmed), is recent, and followed the
  -- full checklist (official pages, documents, people sources, directories, Instagram: checked.version >= 2)
  if er.id is null or er.researched_at < k.created_at - interval '1 hour' or er.researched_at < now() - make_interval(days => v_max)
     or coalesce((er.checked->>'version')::int, 1) < 2 then
    return jsonb_build_object('state', 'RESEARCH_PENDING', 'label', case when er.id is null then 'Email research pending' else 'Email research to complete (full checklist)' end,
                              'researched_at', er.researched_at);
  end if;
  select f.* into v_find from email_finder_log f where f.contact_id = k.id order by f.attempted_at desc limit 1;
  v_fb := case when coalesce(k.linkedin, '') ~* 'linkedin\.com/in/' then 'LINKEDIN'
               when coalesce(k.instagram, c.instagram, '') <> '' then 'INSTAGRAM' end;
  v_kinds := (select string_agg(lower(replace(x, '_', ' ')), ', ') from jsonb_array_elements_text(coalesce(er.checked->'kinds', '[]'::jsonb)) x);
  v_ev := 'Email research ' || to_char(er.researched_at at time zone 'Africa/Cairo', 'DD Mon') || ': ' || er.searches || ' searches'
       || coalesce(' (' || v_kinds || ')', '') || ', ' || er.pages_read || ' official page' || case when er.pages_read = 1 then '' else 's' end || ' read, '
       || er.emails_seen || ' address' || case when er.emails_seen = 1 then '' else 'es' end || ' seen. '
       || case
            when coalesce(btrim(k.email), '') <> '' and v_ver is not null then 'Their address ' || lower(btrim(k.email)) || ' was checked: ' || replace(v_ver, '_', '-') || '. '
            when coalesce(btrim(k.email), '') <> '' then 'Their address ' || lower(btrim(k.email)) || ' could not be verified within ' || v_wait || ' days. '
            when er.outcome = 'NO_EMAIL_FOUND' then 'No business email is published for them. '
            when er.outcome = 'INBOX_ONLY' then 'Only a general inbox is published. '
            when er.outcome = 'DEPARTMENT_EMAIL' then 'Only a department inbox, which did not verify. '
            else 'The named addresses found belong to other people. ' end
       || case when v_find.id is not null then 'Provider lookup ' || to_char(v_find.attempted_at at time zone 'Africa/Cairo', 'DD Mon') || ': '
                    || case v_find.outcome when 'NOT_FOUND' then 'no address' when 'NOT_VERIFIED' then 'an address that did not verify' else lower(v_find.outcome) end || '.'
               else '' end;
  return jsonb_build_object('state', 'EXHAUSTED', 'fallback', v_fb,
    'label', case v_fb when 'LINKEDIN' then 'LinkedIn fallback — email exhausted' when 'INSTAGRAM' then 'Instagram fallback — email exhausted'
                       else 'Email exhausted — no fallback route' end,
    'evidence', btrim(v_ev), 'researched_at', er.researched_at, 'research_id', er.id);
end $$;
revoke all on function public.contact_email_route(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- 2. best route per company
create or replace function public.company_email_state(p_company uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (select c.*, contact_segment(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) seg
               from companies c where c.id = p_company),
  dm as (select k.id, role_priority(k.position, c.seg) rp, contact_email_route(k.id) r
           from contacts k join c on c.id = k.company_id
          where k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3 and not coalesce(k.do_not_contact, false)
            and coalesce(k.status, '') <> 'DO_NOT_CONTACT'
            and length(btrim(coalesce(k.first_name, ''))) >= 2 and length(btrim(coalesce(k.last_name, ''))) >= 2
            and not (coalesce(c.partnership_model, 'CONTENT_TALENT') <> 'CONTENT_TALENT' and pr_role(k.position)))
  select coalesce(
    (select dm.r || jsonb_build_object('contact_id', dm.id, 'has_dm', true, 'dms', (select count(*) from dm))
       from dm order by case dm.r->>'state' when 'VERIFIED' then 0 when 'VERIFIED_INBOX' then 1 when 'NEEDS_VERIFICATION' then 2 when 'RESEARCH_PENDING' then 3 else 4 end,
                        case dm.r->>'fallback' when 'LINKEDIN' then 0 when 'INSTAGRAM' then 1 else 2 end, dm.rp desc limit 1),
    jsonb_build_object('state', 'NO_PERSON', 'has_dm', false, 'dms', 0, 'label', 'No decision maker confirmed yet'))
$$;
revoke all on function public.company_email_state(uuid) from public, anon, authenticated;

create or replace function public.prospect_routes()
returns table (company_id uuid, company text, agent text, partnership boolean, cold boolean, state text, fallback text,
               contact_id uuid, has_dm boolean, label text, evidence text)
language sql stable security definer set search_path = public as $$
  select c.id, c.name,
         agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes),
         c.partnership_model is not null, relationship_state(c.id) = 'COLD',
         s->>'state', s->>'fallback', (s->>'contact_id')::uuid, coalesce((s->>'has_dm')::boolean, false), s->>'label', s->>'evidence'
    from companies c cross join lateral (select company_email_state(c.id) s) x
   where c.universe_status = 'QUALIFIED' and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'
$$;
revoke all on function public.prospect_routes() from public, anon, authenticated;

-- ---------------------------------------------------------------- 3. channel health and email coverage per Director
create or replace function public.director_channel_health(p_desk jsonb default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with p as (select * from prospect_routes()),
  r as (select p.agent k, p.* from p union all select 'PARTNERSHIPS', p.* from p where p.partnership),
  d as (select x->>'director' director, (x->>'company_id')::uuid company_id, x->>'channel' channel, x->'fallback' fb
          from jsonb_array_elements(coalesce(p_desk, outreach_desk())->'needs_review') x),
  dk as (select director k, count(*) n, count(*) filter (where channel = 'EMAIL') e, count(*) filter (where fb is not null and fb <> 'null'::jsonb) f from d group by 1
         union all
         select 'PARTNERSHIPS', count(*), count(*) filter (where d.channel = 'EMAIL'), count(*) filter (where d.fb is not null and d.fb <> 'null'::jsonb)
           from d join companies c on c.id = d.company_id where c.partnership_model is not null)
  select coalesce(jsonb_object_agg(s.k, s.j), '{}'::jsonb) from (
    select r.k, jsonb_build_object(
      'qualified', count(*), 'with_dm', count(*) filter (where r.has_dm),
      'verified', count(*) filter (where r.state in ('VERIFIED', 'VERIFIED_INBOX')),
      'needs_verification', count(*) filter (where r.state = 'NEEDS_VERIFICATION'),
      'email_gap', count(*) filter (where r.state = 'RESEARCH_PENDING'),
      'linkedin_fallback', count(*) filter (where r.state = 'EXHAUSTED' and r.fallback = 'LINKEDIN'),
      'instagram_fallback', count(*) filter (where r.state = 'EXHAUSTED' and r.fallback = 'INSTAGRAM'),
      'no_route', count(*) filter (where r.state = 'EXHAUSTED' and r.fallback is null),
      'no_person', count(*) filter (where not r.has_dm),
      'needs_review', coalesce((select sum(n) from dk where dk.k = r.k), 0),
      'needs_review_email', coalesce((select sum(e) from dk where dk.k = r.k), 0),
      'needs_review_fallback', coalesce((select sum(f) from dk where dk.k = r.k), 0),
      'coverage_pct', round(100.0 * count(*) filter (where r.state in ('VERIFIED', 'VERIFIED_INBOX')) / nullif(count(*) filter (where r.has_dm), 0))) j
    from r group by r.k) s
$$;
revoke all on function public.director_channel_health(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- 4. role focus (Adam's preferred contacts, 8 Oct)
create or replace function public.role_focus(p_segment text)
returns text[] language sql immutable as $$
  select case p_segment
    when 'HOTEL' then array['general manager', 'hotel manager', 'director of sales', 'director of sales and marketing', 'commercial director', 'partnerships',
                            'marketing director', 'marketing manager', 'communications', 'owner', 'managing director', 'guest relations director', 'chef concierge']
    when 'VILLA' then array['founder', 'owner', 'managing director', 'head of sales', 'partnerships', 'operations director', 'guest experience',
                            'commercial director', 'portfolio director']
    when 'TRAVEL' then array['founder', 'managing director', 'commercial director', 'partnerships', 'head of product', 'head of travel',
                             'supplier relations', 'destination director', 'head of trade', 'b2b']
    when 'WEDDINGS' then array['founder', 'managing director', 'creative director', 'destination director', 'partnerships', 'owner', 'lead planner',
                               'partner', 'events director']
    when 'BRANDS' then array['marketing director', 'head of brand', 'brand director', 'global pr', 'head of communications', 'partnerships director',
                             'experiential director', 'influencer marketing', 'creative producer', 'executive producer', 'production director',
                             'account director', 'head of marketing', 'brand partnerships', 'pr director', 'head of production', 'creative director',
                             'talent manager', 'partnerships']
    when 'MEDIA' then array['founder', 'host', 'editor', 'executive producer', 'partnerships', 'head of content', 'producer']
    when 'CORPORATE' then array['travel manager', 'executive assistant', 'chief of staff', 'head of events', 'workplace experience', 'partnerships',
                                'travel procurement', 'office of the ceo', 'corporate travel']
    when 'CLUB' then array['founder', 'membership director', 'head of partnerships', 'general manager', 'events director', 'concierge']
    when 'SPORTS' then array['commercial director', 'partnerships', 'player care', 'head of operations', 'team manager']
    else array['founder', 'director', 'head of partnerships', 'commercial director'] end
$$;

-- ---------------------------------------------------------------- 5. the Commercial Director's plan, email first
-- Channel per prospect: VERIFIED -> email to the person; VERIFIED_INBOX -> email to the department inbox for their attention;
-- EXHAUSTED -> LinkedIn (or Instagram for lifestyle lanes) as a documented fallback; RESEARCH_PENDING / NEEDS_VERIFICATION ->
-- not planned (Email Intelligence and verification go first). Each lane's quota fills with email first.
-- A LinkedIn / Instagram message prepared before a verified email existed is retired so the email replaces it.
create or replace function public.commercial_director_plan(p_dry_run boolean default true, p_target int default null, p_replan boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_mix jsonb := (select value from system_config where key = 'acquisition_mix');
        v_target int := coalesce(p_target, ((select value from system_config where key = 'daily_touch_target')->>'target')::int, 20);
        v_total int := 0; v_lane text; v_quota int; v_left int; v_out jsonb; v_superseded int := 0;
        p_refresh boolean := coalesce((select (value->>'refresh_stale_drafts')::boolean from system_config where key = 'planner_options'), false);
begin
  if p_replan then delete from outreach_candidates where run_date = current_date and status = 'PLANNED' and dry_run = p_dry_run; end if;
  if not exists (select 1 from outreach_candidates where run_date = current_date and dry_run = p_dry_run) then
    if not p_dry_run then
      with s as (
        update tasks t set status = 'CANCELLED', updated_at = now(),
               description = 'Superseded ' || to_char(now() at time zone 'Africa/Cairo', 'DD Mon') || ': a verified email now exists for this person, so email replaces this message (email-first rule).'
                             || chr(10) || coalesce(t.description, '')
         where t.status in ('OPEN', 'IN_PROGRESS') and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY)' and t.contact_id is not null
           and contact_email_route(t.contact_id)->>'state' in ('VERIFIED', 'VERIFIED_INBOX')
        returning t.id)
      update outreach_candidates oc set status = 'SKIPPED', hold_reason = 'SUPERSEDED_BY_VERIFIED_EMAIL', updated_at = now()
        from s where oc.task_id = s.id;
      get diagnostics v_superseded = row_count;
    end if;
    create temp table _pool on commit drop as
    with base as (
      select c.id company_id, c.name, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane,
             c.company_type, c.universe_reason, c.instagram company_instagram, company_warm_route(c.id) warm,
             c.partnership_model model_code, partner_hotel_route(c.partnership_model, c.company_type) hotel_route,
             (select o.id from opportunities o where o.company_id = c.id and o.status not in ('WON', 'LOST', 'ARCHIVED') order by o.priority desc nulls last, o.created_at desc limit 1) opp_id,
             exists (select 1 from email_research er where er.company_id = c.id and coalesce((er.checked->>'version')::int, 1) >= 2) researched
        from companies c
       where c.universe_status = 'QUALIFIED'
         and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'
         and relationship_state(c.id) = 'COLD'
         and coalesce(c.outreach_hold_until, '-infinity'::timestamptz) < now()
         and not exists (select 1 from tasks t where t.company_id = c.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
                          and (t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY|OUTREACH READY|VERIFY|DRAFT REVIEW|FOLLOW UP|HOLD|ADAM PERSONAL OUTREACH|APPROVE OUTREACH|RECONNECT|WARM ROUTE|MEETING)'
                               or t.task_type = 'SALES_OUTREACH_APPROVAL')
                          and not (p_refresh and p_dry_run and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|EMAIL READY)'
                                   and t.created_at < now() - interval '3 days'))
         and not exists (select 1 from outreach_candidates oc where oc.company_id = c.id and oc.status <> 'SKIPPED' and oc.created_at > now() - interval '30 days')
         and not exists (select 1 from outbound_emails ob where ob.company_id = c.id and ob.status in ('QUEUED', 'CLAIMED', 'DRAFTED', 'SENT') and ob.created_at > now() - interval '60 days')),
    pick0 as (
      select b.*, k.id k_id, ib.id ib_id, case when k.id is not null then contact_email_route(k.id) end rt
        from base b
        left join lateral (select * from contacts k where k.company_id = b.company_id and not coalesce(k.do_not_contact, false)
                        and k.identity_status = 'CONFIRMED' and k.position is not null and role_score(k.position) > 0
                        and length(btrim(coalesce(k.first_name, ''))) >= 2 and length(btrim(coalesce(k.last_name, ''))) >= 2
                        -- partnership pitches never go to PR / communications (content, press, creator stays, brand trips, editorial only)
                        and not (coalesce(b.model_code, 'CONTENT_TALENT') <> 'CONTENT_TALENT' and pr_role(k.position))
                      order by
                        -- hotels: GM, Commercial Director, Sales Director, Partnerships; then whoever has a verified email
                        case when b.hotel_route then partner_route_rank(k.position) >= 1 end desc nulls last,
                        (email_state_v3(k.email, k.email_status, k.email_source_url, k.email_verification_provider) = 'VALID_VERIFIED') desc,
                        case when b.hotel_route then partner_route_rank(k.position) end desc nulls last,
                        (role_score(k.position) >= 4) desc, (coalesce(k.linkedin, '') ~* 'linkedin\.com/in/') desc, (coalesce(k.instagram, '') <> '') desc,
                        role_score(k.position) desc, k.confidence desc nulls last limit 1) k on true
        -- no named person: a verified partnerships / sales / events inbox (never support, careers, admin; never press for partnership pitches)
        left join lateral (select * from contacts i where i.company_id = b.company_id and i.route_type = 'COMPANY_INBOX' and i.email is not null
                             and not coalesce(i.do_not_contact, false) and coalesce(i.email_source_url, '') <> ''
                             and email_local_class(i.email) <> 'EXCLUDED' and coalesce(i.email_status, '') <> 'INVALID'
                             and email_state_v3(i.email, i.email_status, i.email_source_url, i.email_verification_provider) = 'VALID_VERIFIED'
                             and not (coalesce(b.model_code, 'CONTENT_TALENT') <> 'CONTENT_TALENT'
                                      and coalesce(i.position, '') || ' ' || i.email ~* '(press|media|communications|comms|\mpr\M)')
                           order by coalesce(i.email_tier = 2, false) desc, i.created_at limit 1) ib on true),
    pick1 as (
      select p.*,
        case
          when p.k_id is not null and p.rt->>'state' in ('VERIFIED', 'VERIFIED_INBOX') then 'EMAIL'
          when p.k_id is not null and p.rt->>'state' = 'EXHAUSTED' and p.rt->>'fallback' = 'LINKEDIN' then 'LINKEDIN'
          when p.k_id is not null and p.rt->>'state' = 'EXHAUSTED' and p.rt->>'fallback' = 'INSTAGRAM'
               and p.lane in ('BRANDS', 'WEDDINGS', 'PARTNERSHIPS', 'TRAVEL_PRIVATE')
               and coalesce(p.company_type, '') !~* '(bank|wealth|law|legal|consult|invest|family|financial|insurance|asset|equity)' then 'INSTAGRAM'
          when p.k_id is null and p.ib_id is not null then 'EMAIL'
          when p.k_id is null and p.researched and coalesce(p.company_instagram, '') <> '' and p.lane in ('BRANDS', 'WEDDINGS', 'PARTNERSHIPS', 'TRAVEL_PRIVATE')
               and coalesce(p.company_type, '') !~* '(bank|wealth|law|legal|consult|invest|family|financial|insurance|asset|equity)' then 'INSTAGRAM'
        end channel,
        case when p.k_id is not null and p.rt->>'state' = 'VERIFIED_INBOX' then (p.rt->>'inbox_id')::uuid
             when p.k_id is null and p.ib_id is not null then p.ib_id end route_id,
        case when p.k_id is not null and p.rt->>'state' = 'EXHAUSTED' then upper(coalesce(p.rt->>'label', '')) || '. ' || coalesce(p.rt->>'evidence', '')
             when p.k_id is null and p.ib_id is null then 'INSTAGRAM FALLBACK — NO PERSON CONFIRMED, EMAIL RESEARCH COMPLETE' end channel_reason
        from pick0 p),
    pick as (
      select p.*, row_number() over (partition by p.lane order by (p.channel = 'EMAIL') desc, (p.k_id is not null) desc, (p.warm is not null) desc,
               coalesce((select o.priority from opportunities o where o.id = p.opp_id), 0) desc, p.name) rn
        from pick1 p where p.channel is not null)
    select * from pick;
    for v_lane, v_quota in select key, round((value::text)::numeric * v_target / 20.0)::int from jsonb_each(v_mix) loop
      insert into outreach_candidates (run_date, dry_run, lane, company_id, contact_id, route_contact_id, opportunity_id, channel, warm_route, why_now, evidence, angle, channel_reason)
      select current_date, p_dry_run, p.lane, p.company_id, p.k_id, case when p.channel = 'EMAIL' then p.route_id end, p.opp_id, p.channel, p.warm,
             (select coalesce(o.commercial_trigger, o.reason) from opportunities o where o.id = p.opp_id),
             p.universe_reason, nullif(concat_ws(' ', prospect_angle_prefix(p.company_id), (select o.angle from opportunities o where o.id = p.opp_id)), ''), p.channel_reason
        from _pool p where p.lane = v_lane and p.rn <= v_quota;
    end loop;
    select count(*) into v_total from outreach_candidates where run_date = current_date and dry_run = p_dry_run;
    v_left := v_target - v_total;
    if v_left > 0 then
      insert into outreach_candidates (run_date, dry_run, lane, company_id, contact_id, route_contact_id, opportunity_id, channel, warm_route, why_now, evidence, angle, channel_reason)
      select current_date, p_dry_run, p.lane, p.company_id, p.k_id, case when p.channel = 'EMAIL' then p.route_id end, p.opp_id, p.channel, p.warm,
             (select coalesce(o.commercial_trigger, o.reason) from opportunities o where o.id = p.opp_id),
             p.universe_reason, nullif(concat_ws(' ', prospect_angle_prefix(p.company_id), (select o.angle from opportunities o where o.id = p.opp_id)), ''), p.channel_reason
        from _pool p
       where not exists (select 1 from outreach_candidates oc where oc.company_id = p.company_id and oc.run_date = current_date and oc.dry_run = p_dry_run)
       order by (p.channel = 'EMAIL') desc, (p.warm is not null) desc, (p.k_id is not null) desc,
                -- leftovers follow the agent weights too: sports stays selective
                p.rn::numeric / greatest(coalesce((v_mix->>p.lane)::numeric, 0), 0.5)
       limit v_left;
    end if;
  end if;
  select jsonb_build_object(
    'run_date', current_date, 'dry_run', p_dry_run, 'target', v_target,
    'floor', ((select value from system_config where key = 'daily_touch_target')->>'floor')::int,
    'superseded', v_superseded,
    'planned', count(*), 'by_lane', (select jsonb_object_agg(lane, n) from (select lane, count(*) n from outreach_candidates
        where run_date = current_date and dry_run = p_dry_run group by 1) s),
    'by_channel', (select jsonb_object_agg(channel, n) from (select channel, count(*) n from outreach_candidates
        where run_date = current_date and dry_run = p_dry_run group by 1) s),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'candidate_id', oc.id, 'lane', oc.lane, 'channel', oc.channel, 'status', oc.status, 'channel_reason', oc.channel_reason,
      'company', c.name, 'company_type', c.company_type, 'country', c.country, 'website', c.website,
      'first_name', k.first_name, 'last_name', k.last_name, 'position', k.position,
      'email', case when oc.channel = 'EMAIL' then coalesce(ri.email, k.email) end, 'email_status', case when oc.channel = 'EMAIL' then coalesce(ri.email_status, k.email_status) end,
      'via_inbox', ri.email is not null, 'inbox_label', ri.position, 'linkedin', k.linkedin, 'instagram', coalesce(k.instagram, c.instagram),
      'warm_route', oc.warm_route, 'why_now', oc.why_now, 'evidence', left(coalesce(oc.evidence, '') || ' ' || coalesce(c.notes, ''), 1500),
      'angle', oc.angle, 'contact_notes', left(k.notes, 600)) order by oc.lane, oc.created_at) filter (where oc.status = 'PLANNED'), '[]'::jsonb))
  into v_out
  from outreach_candidates oc join companies c on c.id = oc.company_id left join contacts k on k.id = oc.contact_id
       left join contacts ri on ri.id = oc.route_contact_id
  where oc.run_date = current_date and oc.dry_run = p_dry_run;
  return v_out;
end $$;
revoke all on function public.commercial_director_plan(boolean, int, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------- 6. Email Intelligence queue, email first
-- Every lane gets researched (Brands, Weddings and Travel first: the amendment's priority sectors; hospitality no longer
-- crowds them out). A company is queued when its best decision maker is RESEARCH_PENDING (never researched, researched
-- before that person was confirmed, stale, or researched before the full checklist), or when it has no person yet.
-- Companies whose LinkedIn / Instagram message waits on email research jump the queue so the desk resolves.
create or replace function public.email_gap_list(p_limit int default 40, p_test text default null, p_include_recent boolean default false)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (
    select c.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent,
           contact_segment(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) segment,
           company_research_domain(c.name, c.website, c.website_confirmed_at) domain, company_email_routes(c.id) r, company_email_state(c.id) es
      from companies c
     where (p_test is null and c.universe_status = 'QUALIFIED'
            and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'
            and relationship_state(c.id) = 'COLD'
            and coalesce(c.email_attempts, 0) < 6
            and (p_include_recent
                 or coalesce(c.email_checked_at, '-infinity'::timestamptz) < now() - interval '14 days'
                 -- researched before the full checklist existed, or before a decision maker was confirmed: research again now
                 or not exists (select 1 from email_research er where er.company_id = c.id and coalesce((er.checked->>'version')::int, 1) >= 2)
                 or exists (select 1 from contacts k where k.company_id = c.id and k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3
                             and k.created_at > coalesce(c.email_checked_at, '-infinity'::timestamptz) + interval '1 hour')))
        or (p_test is not null and c.id in (select t.company_id from email_intel_tests t where t.test_tag = p_test)
            and not exists (select 1 from email_research er where er.company_id = c.id and er.test_tag = p_test))),
  g as (
    select c.*,
      (select max(role_priority(k.position, c.segment)) from contacts k where k.company_id = c.id and not coalesce(k.do_not_contact, false)
          and coalesce(k.first_name, '') <> '' and coalesce(k.last_name, '') <> '' and role_score(k.position) > 0) best_role,
      case c.agent when 'BRANDS' then 40 when 'WEDDINGS' then 38 when 'TRAVEL' then 38 when 'HOSPITALITY' then 34 when 'CORPORATE' then 30
                   when 'PRIVATE' then 28 when 'MEDIA' then 20 when 'EGYPT' then 18 when 'SPORTS' then 12 else 10 end strategic,
      case c.partnership_model when 'PREFERRED_STAY' then 15 when 'WHITE_LABEL_CONCIERGE' then 15 when 'EGYPT_EXECUTION' then 14 when 'RECIPROCAL' then 12
                               when 'GUEST_CONCIERGE' then 12 when 'CONTENT_TALENT' then 9 when 'REFERRAL' then 8 else 5 end potential,
      (case when c.domain is not null then 10 else 0 end
       + case when coalesce(c.company_type, '') ~* '(boutique|independent|villa|residence|planner|agency|collection|studio|advisor|designer|club)' then 5 else 0 end
       - case when c.name ~* '(four seasons|marriott|hilton|accor|ihg|hyatt|st\. regis|ritz|sheraton|kempinski|mandarin oriental|shangri|fairmont|radisson|wyndham|intercontinental|w hotels|jumeirah)' then 6 else 0 end
       + case when coalesce(c.instagram, '') <> '' then 2 else 0 end) likelihood,
      (case when c.es->>'state' = 'RESEARCH_PENDING' then 30 else 0 end
       + case when exists (select 1 from tasks t where t.company_id = c.id and t.status in ('OPEN', 'IN_PROGRESS')
                            and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY)') then 20 else 0 end) email_first
      from c
     where p_test is not null or c.es->>'state' in ('RESEARCH_PENDING', 'NO_PERSON')),
  ranked as (select g.*, strategic + coalesce(best_role, 0) / 4 + potential + likelihood + email_first score from g)
  select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object(
      'company_id', x.id, 'company', x.name, 'website', x.website, 'domain', x.domain, 'country', x.country, 'city', x.city,
      'company_type', x.company_type, 'lane', x.lane, 'agent', x.agent, 'segment', x.segment, 'instagram', x.instagram,
      'role_focus', to_jsonb(role_focus(x.segment)), 'score', x.score, 'routes', x.r, 'route_state', x.es->>'state',
      'model', partnership_model_label(x.partnership_model), 'model_code', x.partnership_model,
      'angle', concat_ws(' ', array_to_string(partnership_model_route(x.partnership_model), '; '),
                         (select coalesce(o.angle, o.suggested_approach) from opportunities o where o.company_id = x.id order by o.created_at desc limit 1)),
      'people', (select coalesce(jsonb_agg(jsonb_build_object('first_name', k.first_name, 'last_name', k.last_name, 'position', k.position,
                                  'email', k.email, 'linkedin', k.linkedin, 'priority', role_priority(k.position, x.segment))
                                  order by (k.identity_status = 'CONFIRMED') desc, role_priority(k.position, x.segment) desc), '[]'::jsonb)
                   from contacts k where k.company_id = x.id and not coalesce(k.do_not_contact, false)
                    and coalesce(k.first_name, '') <> '' and coalesce(k.last_name, '') <> '' and role_score(k.position) > 0),
      'best_role', x.best_role, 'test_tag', p_test, 'checked_at', x.email_checked_at, 'attempts', x.email_attempts)
      order by x.score desc, x.created_at desc) from (select * from ranked order by score desc, created_at desc limit greatest(1, least(coalesce(p_limit, 40), 200))) x), '[]'::jsonb))
$$;
revoke all on function public.email_gap_list(int, text, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------- 7. patches to earlier functions (applied as text replacements)
do $$
declare d text; r text[][]; i int;
begin
  -- the desk: a LinkedIn / Instagram message is in Needs review only as a documented fallback; otherwise it waits in Researching
  d := pg_get_functiondef('public.outreach_desk()'::regprocedure);
  r := array[
   array[$a$           a.block appr_block, a.draft appr_draft, a.on_hold appr_hold,$a$,
         $b$           a.block appr_block, a.draft appr_draft, a.on_hold appr_hold,
           -- email-first (Adam, 8 Oct): a LinkedIn / Instagram message is a fallback only once email research is exhausted
           case when t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY)' then
             case when t.contact_id is not null then contact_email_route(t.contact_id)
                  when exists (select 1 from email_research er where er.company_id = t.company_id and coalesce((er.checked->>'version')::int, 1) >= 2)
                    then jsonb_build_object('state', 'EXHAUSTED', 'fallback', 'INSTAGRAM', 'label', 'Instagram fallback — no person confirmed, email research complete')
                  else jsonb_build_object('state', 'RESEARCH_PENDING', 'label', 'Email research pending') end end er_route,$b$],
   array[$a$        when t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|ADAM -- LINKEDIN|ADAM PERSONAL OUTREACH)' then 'NEEDS_REVIEW'$a$,
         $b$        when t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY)' and coalesce(t.er_route->>'state', '') <> 'EXHAUSTED' then 'RESEARCHING'
        when t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|ADAM -- LINKEDIN|ADAM PERSONAL OUTREACH)' then 'NEEDS_REVIEW'$b$],
   array[$a$        when t.status = 'WAITING' then coalesce(substring(t.description from '^(?:ON HOLD|HELD)[^\n]*'), 'On hold')$a$,
         $b$        when t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY)' and t.status <> 'WAITING' and coalesce(t.er_route->>'state', '') <> 'EXHAUSTED' then
          case t.er_route->>'state'
            when 'NEEDS_VERIFICATION' then 'Email first: ' || coalesce(t.er_route->>'email', 'an address') || ' was found and is waiting for verification'
            when 'VERIFIED' then 'Email first: a verified email exists, so an email replaces this message in tonight''s plan'
            when 'VERIFIED_INBOX' then 'Email first: a verified department inbox exists, so an email replaces this message in tonight''s plan'
            else 'Email first: email research for this person is not complete yet, so LinkedIn waits' end
        when t.status = 'WAITING' then coalesce(substring(t.description from '^(?:ON HOLD|HELD)[^\n]*'), 'On hold')$b$],
   array[$a$        'reason', b.reason, 'status', b.status,$a$,
         $b$        'reason', b.reason, 'status', b.status,
        'fallback', case when b.channel in ('LINKEDIN', 'INSTAGRAM') and b.er_route->>'state' = 'EXHAUSTED'
                         then jsonb_build_object('label', b.er_route->>'label', 'evidence', b.er_route->>'evidence') end,$b$]];
  for i in 1..array_length(r, 1) loop
    if position(r[i][1] in d) = 0 then raise exception 'desk pattern % not found', i; end if;
    d := replace(d, r[i][1], r[i][2]);
  end loop;
  execute d;

  -- Email Intelligence keeps what each pass checked (the evidence behind a fallback)
  d := pg_get_functiondef('public.email_intel_save(jsonb)'::regprocedure);
  r := array[
    array[$a$people_found, rejected, outcome, sources)$a$, $b$people_found, rejected, outcome, sources, checked)$b$],
    array[$a$v_rej + coalesce((p->'research'->>'rejected')::int, 0), v_outcome, v_src);$a$, $b$v_rej + coalesce((p->'research'->>'rejected')::int, 0), v_outcome, v_src, coalesce(p->'research'->'checked', '{}'::jsonb));$b$]];
  for i in 1..array_length(r, 1) loop
    if position(r[i][1] in d) = 0 then raise exception 'save pattern % not found', i; end if;
    d := replace(d, r[i][1], r[i][2]);
  end loop;
  execute d;

  -- verification: every confirmed decision maker's address (role score 3+), a department inbox when no decision-maker address
  -- exists, the cohort under test first, then the email-first lanes
  d := pg_get_functiondef('public.email_verification_queue(integer)'::regprocedure);
  r := array[
    array[$a$else k.email_tier = 1 and k.identity_status = 'CONFIRMED' and role_score(k.position) >= 4 end))$a$,
          $b$else (k.email_tier = 1 and k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3)
                         -- email first: a department inbox is checked when the company has no decision-maker address to check
                         or (k.route_type = 'COMPANY_INBOX' and k.email_tier = 2
                             and not exists (select 1 from contacts d where d.company_id = co.id and d.email_tier = 1 and d.identity_status = 'CONFIRMED'
                                              and role_score(d.position) >= 3 and coalesce(d.email, '') <> '' and coalesce(d.email_status, '') <> 'INVALID')) end))$b$],
    array[$a$row_number() over (order by q.draft_waiting desc, coalesce(q.email_tier, 4), (q.hotel and partner_route_rank(q.position) >= 1) desc,
                 partner_route_rank(q.position) desc, (q.agent = 'HOSPITALITY') desc, role_score(q.position) desc,
                 (q.state = 'PUBLICLY_LISTED') desc, q.company) rk$a$,
          $b$row_number() over (order by q.draft_waiting desc,
                 (q.company_id in (select t.company_id from email_intel_tests t
                                    where t.test_tag = (select value->>'priority_test' from system_config where key = 'email_first'))) desc,
                 coalesce(q.email_tier, 4),
                 array_position(array['BRANDS', 'WEDDINGS', 'TRAVEL', 'HOSPITALITY', 'CORPORATE', 'PRIVATE'], q.agent) nulls last,
                 (q.hotel and partner_route_rank(q.position) >= 1) desc, partner_route_rank(q.position) desc, role_score(q.position) desc,
                 (q.state = 'PUBLICLY_LISTED') desc, q.company) rk$b$]];
  for i in 1..array_length(r, 1) loop
    if position(r[i][1] in d) = 0 then raise exception 'queue pattern % not found', i; end if;
    d := replace(d, r[i][1], r[i][2]);
  end loop;
  execute d;
end $$;

-- ---------------------------------------------------------------- 8. provider lookup (workflow 25 — Hunter Email Finder)
-- Only after the company and the person are established and public research is exhausted (state EXHAUSTED, no address
-- for the person). Uses the remaining credits after verification and keeps a reserve; a provider address is saved only
-- when Hunter verifies it valid on the company's own domain. Nothing is guessed or built from a pattern here.
create or replace function public.email_finder_queue(p_limit int default 5)
returns jsonb language sql stable security definer set search_path = public as $$
  with cfg as (select coalesce((select value from system_config where key = 'email_first'), '{}'::jsonb) v),
  used as (select count(*) n from email_finder_log
            where attempted_at >= ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo' and outcome <> 'ERROR'),
  q as (
    select k.id contact_id, k.first_name, k.last_name, k.position, c.id company_id, c.name company, p.agent,
           company_research_domain(c.name, c.website, c.website_confirmed_at) domain,
           c.id in (select t.company_id from email_intel_tests t where t.test_tag = (select v->>'priority_test' from cfg)) cohort,
           role_priority(k.position, contact_segment(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes)) rp
      from prospect_routes() p join contacts k on k.id = p.contact_id join companies c on c.id = p.company_id
     where p.state = 'EXHAUSTED' and p.cold and coalesce(btrim(k.email), '') = ''
       and length(btrim(coalesce(k.first_name, ''))) >= 2 and length(btrim(coalesce(k.last_name, ''))) >= 2
       and company_research_domain(c.name, c.website, c.website_confirmed_at) is not null
       and not exists (select 1 from email_finder_log f where f.contact_id = k.id and f.attempted_at > now() - interval '90 days'))
  select jsonb_build_object(
    'daily_cap', coalesce(((select v from cfg)->>'finder_daily_cap')::int, 0),
    'reserve_credits', coalesce(((select v from cfg)->>'finder_reserve_credits')::int, 3),
    'used_today', (select n from used), 'waiting', (select count(*) from q),
    'items', coalesce((select jsonb_agg(to_jsonb(x) - 'rp' - 'cohort') from (
        select * from q order by cohort desc, array_position(array['BRANDS', 'WEDDINGS', 'TRAVEL', 'HOSPITALITY', 'CORPORATE', 'PRIVATE'], agent) nulls last, rp desc, company
        limit greatest(0, least(coalesce(p_limit, 5), coalesce(((select v from cfg)->>'finder_daily_cap')::int, 0) - (select n from used)))) x), '[]'::jsonb))
$$;
revoke all on function public.email_finder_queue(int) from public, anon, authenticated;

create or replace function public.email_finder_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare k contacts%rowtype; c companies%rowtype; v_email text := lower(btrim(coalesce(p->>'email', ''))); v_ver text := lower(coalesce(p->>'verification', ''));
        v_code int := nullif(p->>'status_code', '')::int; v_dom text; v_out text;
begin
  select * into k from contacts where id = (p->>'contact_id')::uuid;
  if k.id is null then return jsonb_build_object('ok', false, 'reason', 'CONTACT_NOT_FOUND'); end if;
  select * into c from companies where id = k.company_id;
  v_dom := company_research_domain(c.name, c.website, c.website_confirmed_at);
  v_out := case when v_code is null or (v_code >= 400 and v_code <> 404) then 'ERROR'
                when v_email = '' then 'NOT_FOUND'
                when v_ver = 'valid' and registrable_domain(split_part(v_email, '@', 2)) = v_dom and email_local_class(v_email) = 'PERSONAL' then 'VERIFIED'
                else 'NOT_VERIFIED' end;
  insert into email_finder_log (contact_id, company_id, domain, status_code, email, score, verification, outcome, sources, execution)
  values (k.id, c.id, v_dom, v_code, nullif(v_email, ''), nullif(p->>'score', '')::numeric::int, nullif(v_ver, ''), v_out, coalesce(p->'sources', '[]'::jsonb), p->>'execution');
  if v_out = 'VERIFIED' and coalesce(btrim(k.email), '') = '' then
    update contacts set email = v_email, email_status = 'VERIFIED', email_verification_provider = 'HUNTER', email_tier = 1, route_type = 'PERSON_EMAIL',
           email_source_url = 'https://hunter.io/email-finder', email_source_type = 'PROVIDER', email_found_at = now(), updated_at = now(),
           notes = concat_ws(chr(10), notes, 'Email from Hunter Email Finder (name + company domain), ' || to_char(now(), 'DD Mon YYYY')
                   || '; Hunter verification: valid, score ' || coalesce(p->>'score', '?') || '. A provider result, not published by the company.')
     where id = k.id;
    insert into contact_email_verifications (company_id, contact_id, first_name, last_name, position, email, provider, provider_status, provider_score,
           finder_score, checked_at, source_workflow, source_execution, evidence_sources, outcome, applied_contact_id)
    values (c.id, k.id, k.first_name, k.last_name, k.position, v_email, 'HUNTER', 'valid', nullif(p->>'score', '')::numeric::smallint,
            nullif(p->>'score', '')::numeric::smallint, now(), '25 - NOYA Email Finder', p->>'execution', coalesce(p->'sources', '[]'::jsonb),
            'VERIFIED_FINDER_EMAIL', k.id);
  end if;
  return jsonb_build_object('ok', true, 'outcome', v_out);
end $$;
revoke all on function public.email_finder_save(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- 9. HQ Advisor (Adam's Chief-of-Staff layer)
-- Not a prospecting Director: it reads every Director and says what matters. Every line is computed from NOYA data:
-- the morning brief, 3-5 observations (situation -> meaning -> recommended action), what changed since Adam last looked,
-- where NOYA is winning, where time is being wasted, and the weekly review. It never invents a recommendation: a rule
-- fires only when its numbers are present.
create table if not exists public.hq_advisor_state (
  admin_email text primary key,
  last_seen_at timestamptz,
  prev_seen_at timestamptz
);
alter table public.hq_advisor_state enable row level security;
revoke all on public.hq_advisor_state from anon, authenticated;

create or replace function public.advisor_agent_label(p_key text)
returns text language sql immutable as $$
  select case p_key when 'PRIVATE' then 'Private Membership' when 'HOSPITALITY' then 'Hospitality' when 'TRAVEL' then 'Travel & Concierge'
    when 'BRANDS' then 'Brands & Production' when 'WEDDINGS' then 'Weddings & Events' when 'CORPORATE' then 'Corporate'
    when 'MEDIA' then 'Media & Culture' when 'SPORTS' then 'Sports & Talent' when 'EGYPT' then 'Egypt Growth' when 'GROWTH' then 'Growth & Social'
    when 'PARTNERSHIPS' then 'Partnerships' else initcap(lower(coalesce(p_key, 'Other'))) end
$$;

create or replace function public.hq_advisor()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
        v_desk jsonb := outreach_desk(); v_health jsonb; v_cfg jsonb := coalesce((select value from system_config where key = 'email_first'), '{}'::jsonb);
        v_hunter jsonb := (select value from system_config where key = 'hunter_account');
        v_since timestamptz; v_hour int := extract(hour from now() at time zone 'Africa/Cairo')::int;
        v_today timestamptz := ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo';
        v_obs jsonb := '[]'::jsonb; v_brief jsonb := '[]'::jsonb; v_changed jsonb := '[]'::jsonb; v_win jsonb := '[]'::jsonb; v_waste jsonb := '[]'::jsonb;
        v_replies int; v_reply_names text; v_meet int; v_email_nr int; v_gmail int; v_fu_overdue int; v_fu_oldest timestamptz;
        v_gap int; v_needver int; v_ver_left int; v_brand_today int; v_brand_min int; r record; v_n int;
begin
  v_health := director_channel_health(v_desk);
  v_since := coalesce((select prev_seen_at from hq_advisor_state where admin_email = v_admin), now() - interval '24 hours');

  -- ---- the morning brief: only what needs Adam
  select count(*), string_agg(distinct coalesce(co.name, 'a reply'), ', ') into v_replies, v_reply_names
    from tasks t left join companies co on co.id = t.company_id
   where t.task_type in ('REPLY_ACTION', 'HUMAN_REVIEW') and t.status in ('OPEN', 'IN_PROGRESS');
  v_meet := (select count(*) from tasks where task_type = 'MEETING_ACTION' and status in ('OPEN', 'IN_PROGRESS'))
          + (select count(*) from opportunities o where o.status = 'CALL_REQUIRED'
              and not exists (select 1 from tasks t where t.opportunity_id = o.id and t.task_type = 'MEETING_ACTION' and t.status in ('OPEN', 'IN_PROGRESS')));
  v_email_nr := coalesce((v_desk->'counts'->'needs_review'->>'EMAIL')::int, 0);
  v_gmail := coalesce((v_desk->'counts'->>'gmail_drafts_confirmed')::int, 0);
  select count(*), min((x->>'due_at')::timestamptz) into v_fu_overdue, v_fu_oldest
    from jsonb_array_elements(v_desk->'followups') x where (x->>'due_at')::timestamptz < now();
  v_brand_today := (select count(*) from outreach_candidates oc join companies c on c.id = oc.company_id
                     where not oc.dry_run and oc.channel = 'EMAIL' and oc.draft is not null and oc.created_at >= v_today
                       and agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) = 'BRANDS');
  v_brand_min := coalesce((v_cfg->'brand_daily_verified_target'->>0)::int, 8);
  if v_replies > 0 then v_brief := v_brief || jsonb_build_object('text', v_replies || case when v_replies = 1 then ' reply needs you' else ' replies need you' end, 'tab', 'today'); end if;
  if v_email_nr > 0 then v_brief := v_brief || jsonb_build_object('text', v_email_nr || case when v_email_nr = 1 then ' verified email waiting for approval' else ' verified emails waiting for approval' end, 'tab', 'desk'); end if;
  if v_gmail > 0 then v_brief := v_brief || jsonb_build_object('text', v_gmail || case when v_gmail = 1 then ' approved Gmail draft waiting to send' else ' approved Gmail drafts waiting to send' end, 'tab', 'desk'); end if;
  if v_meet > 0 then v_brief := v_brief || jsonb_build_object('text', v_meet || case when v_meet = 1 then ' meeting or call to handle' else ' meetings or calls to handle' end, 'tab', 'today'); end if;
  if v_fu_overdue > 0 then v_brief := v_brief || jsonb_build_object('text', v_fu_overdue || case when v_fu_overdue = 1 then ' follow-up overdue' else ' follow-ups overdue' end, 'tab', 'today'); end if;
  if v_brand_today < v_brand_min then
    v_brief := v_brief || jsonb_build_object('text', 'Brands is behind email target (' || v_brand_today || ' of ' || v_brand_min || '–' || coalesce(v_cfg->'brand_daily_verified_target'->>1, '12') || ' today)', 'tab', 'agents');
  end if;

  -- ---- observations, ranked: what needs attention, where the bottleneck is, what to do next
  if v_replies > 0 then
    v_obs := v_obs || jsonb_build_object('rank', 10, 'kind', 'ATTENTION',
      'situation', v_replies || case when v_replies = 1 then ' reply is' else ' replies are' end || ' waiting: ' || coalesce(v_reply_names, '') || '.',
      'meaning', 'A reply is the warmest moment in the pipeline; it cools within days.',
      'action', 'Answer ' || case when v_replies = 1 then 'it' else 'them' end || ' first today.', 'tab', 'today');
  end if;
  if v_email_nr > 0 then
    v_obs := v_obs || jsonb_build_object('rank', 20, 'kind', 'ATTENTION',
      'situation', v_email_nr || ' verified ' || case when v_email_nr = 1 then 'email is' else 'emails are' end || ' ready for your review.',
      'meaning', 'Each is a named decision maker with a provider-verified address: the channel NOYA wants most.',
      'action', 'Review and approve in Outreach; approving creates an unsent Gmail draft.', 'tab', 'desk');
  end if;
  if v_gmail > 0 then
    v_obs := v_obs || jsonb_build_object('rank', 15, 'kind', 'ATTENTION',
      'situation', v_gmail || ' approved Gmail ' || case when v_gmail = 1 then 'draft has' else 'drafts have' end || ' not been sent yet.',
      'meaning', 'The work is done; nothing happens until you press send in Gmail.',
      'action', 'Send them from Gmail.', 'tab', 'desk');
  end if;
  -- contact enrichment bottleneck: good discovery, poor email coverage
  for r in select key, (value->>'with_dm')::int dm, (value->>'verified')::int ver, coalesce((value->>'coverage_pct')::int, 0) cov,
                  (value->>'email_gap')::int gap, (value->>'needs_verification')::int nv, (value->>'linkedin_fallback')::int li
             from jsonb_each(v_health)
            where key <> 'PARTNERSHIPS' and (value->>'with_dm')::int >= coalesce((v_cfg->>'coverage_alert_min_dm')::int, 8)
              and coalesce((value->>'coverage_pct')::int, 0) < coalesce((v_cfg->>'coverage_alert_pct')::int, 30)
            order by array_position(array['BRANDS', 'WEDDINGS', 'TRAVEL', 'HOSPITALITY', 'CORPORATE'], key) nulls last, (value->>'with_dm')::int desc limit 2 loop
    -- ranked by lane (Brands first), so the two bottlenecks shown are the priority Directors
    v_obs := v_obs || jsonb_build_object('rank', 30 + coalesce(array_position(array['BRANDS', 'WEDDINGS', 'TRAVEL', 'HOSPITALITY', 'CORPORATE'], r.key), 6), 'kind', 'BOTTLENECK', 'title', 'CONTACT ENRICHMENT BOTTLENECK', 'director', r.key,
      'situation', advisor_agent_label(r.key) || ' has ' || r.dm || ' qualified companies with a decision maker, but only ' || r.ver || ' with a verified email (' || r.cov || '% coverage).',
      'meaning', 'The problem is contact enrichment, not discovery: ' || r.gap || ' still need email research, ' || r.nv || ' have an address waiting for verification and '
                 || r.li || ' had public email research exhausted (LinkedIn fallback).',
      'action', case when r.li > r.gap + r.nv then 'Public sources are exhausted for most of ' || advisor_agent_label(r.key) || '; the remaining lever is a provider lookup by name (Email Finder), which needs verification capacity.'
                     when r.nv > r.gap then 'Give verification capacity to the ' || advisor_agent_label(r.key) || ' addresses before adding discovery.'
                     else 'Email Intelligence works the ' || advisor_agent_label(r.key) || ' queue first; hold extra discovery until coverage passes 30%.' end,
      'tab', 'agents');
  end loop;
  -- verification capacity
  v_needver := (select coalesce(sum((value->>'needs_verification')::int), 0) from jsonb_each(v_health) where key <> 'PARTNERSHIPS');
  v_ver_left := nullif(v_hunter->>'verifications_left', '')::int;
  if v_needver > 0 and coalesce(v_ver_left, 0) < v_needver + 40 then
    v_obs := v_obs || jsonb_build_object('rank', 35, 'kind', 'BOTTLENECK', 'title', 'VERIFICATION CAPACITY',
      'situation', v_needver || ' decision-maker ' || case when v_needver = 1 then 'address is' else 'addresses are' end || ' found and waiting for verification; Hunter Free has '
                   || coalesce(v_ver_left::text, 'few') || ' checks left until ' || coalesce(to_char((v_hunter->>'reset_date')::date, 'DD Mon'), 'the reset') || '.',
      'meaning', 'Found emails cannot become outreach until they verify; 40–50 a day needs about 1,500 checks a month.',
      'action', 'Decide on verification capacity (Hunter Starter, €49/month, recommended).', 'tab', 'agents');
  end if;
  -- research backlog
  v_gap := (select coalesce(sum((value->>'email_gap')::int), 0) from jsonb_each(v_health) where key <> 'PARTNERSHIPS');
  if v_gap >= 10 then
    v_obs := v_obs || jsonb_build_object('rank', 40, 'kind', 'BOTTLENECK', 'title', 'EMAIL RESEARCH BACKLOG',
      'situation', v_gap || ' qualified prospects still need full email research before any channel is chosen.',
      'meaning', 'At 72 companies a day Email Intelligence clears this in about ' || greatest(1, ceil(v_gap / 72.0))::int || ' day' || case when v_gap > 72 then 's' else '' end
                 || '; LinkedIn waits for them, by design.',
      'action', 'No action needed unless it grows; the research queue runs six times a day.', 'tab', 'agents');
  end if;
  if v_fu_overdue > 0 then
    v_obs := v_obs || jsonb_build_object('rank', 45, 'kind', 'NEXT',
      'situation', v_fu_overdue || ' follow-up' || case when v_fu_overdue = 1 then ' is' else 's are' end || ' overdue, the oldest since ' || to_char(v_fu_oldest at time zone 'Africa/Cairo', 'DD Mon') || '.',
      'meaning', 'Most replies come from the first or second follow-up.',
      'action', 'Clear the oldest five today; mark each Followed up or Snooze.', 'tab', 'today');
  end if;
  -- prospect buffer: a Director running out of untouched, ready prospects
  for r in select p.agent, count(*) filter (where p.cold and p.has_dm and not exists (
                    select 1 from outreach_candidates oc where oc.company_id = p.company_id and oc.status <> 'SKIPPED' and oc.created_at > now() - interval '30 days')) ready
             from prospect_routes() p where p.agent in ('BRANDS', 'WEDDINGS', 'TRAVEL', 'HOSPITALITY') group by 1 having count(*) filter (where p.cold and p.has_dm and not exists (
                    select 1 from outreach_candidates oc where oc.company_id = p.company_id and oc.status <> 'SKIPPED' and oc.created_at > now() - interval '30 days')) < 6
             order by 2 limit 1 loop
    v_obs := v_obs || jsonb_build_object('rank', 50, 'kind', 'NEXT',
      'situation', advisor_agent_label(r.agent) || ' has only ' || r.ready || ' untouched qualified prospect' || case when r.ready = 1 then '' else 's' end || ' with a decision maker left.',
      'meaning', 'Below the buffer the Director cannot fill its daily quota.',
      'action', 'Increase ' || advisor_agent_label(r.agent) || ' discovery this week.', 'tab', 'agents');
  end loop;

  -- ---- where NOYA is winning / wasting time (last 30 days, real interactions)
  for r in select agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent,
                  count(*) filter (where i.direction = 'INBOUND') replies, count(*) filter (where i.direction = 'OUTBOUND') sent
             from interactions i join companies c on c.id = i.company_id
            where i.occurred_at > now() - interval '30 days' and i.channel <> 'WEBSITE' group by 1 order by 2 desc, 3 desc loop
    if r.replies > 0 then
      v_win := v_win || jsonb_build_object('director', r.agent, 'text', advisor_agent_label(r.agent) || ': ' || r.replies || ' repl' || case when r.replies = 1 then 'y' else 'ies' end
                                       || ' from ' || r.sent || ' sent (' || round(100.0 * r.replies / nullif(r.sent, 0)) || '%)');
    elsif r.sent >= 5 then
      v_waste := v_waste || jsonb_build_object('director', r.agent, 'text', advisor_agent_label(r.agent) || ': ' || r.sent || ' sent in 30 days, no reply yet — check targeting and angle');
    end if;
  end loop;
  for r in select key, (value->>'linkedin_fallback')::int li, (value->>'verified')::int ver from jsonb_each(v_health)
            where key <> 'PARTNERSHIPS' and (value->>'linkedin_fallback')::int > greatest(4, 2 * (value->>'verified')::int) loop
    v_waste := v_waste || jsonb_build_object('director', r.key, 'text', advisor_agent_label(r.key) || ': ' || r.li || ' LinkedIn fallbacks against ' || r.ver || ' verified emails — email routes are thin here');
  end loop;

  -- ---- what changed since Adam last looked
  select count(*) into v_n from companies where created_at > v_since and universe_status = 'QUALIFIED';
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' new qualified ' || case when v_n = 1 then 'company' else 'companies' end); end if;
  select count(*) into v_n from contacts where created_at > v_since and identity_status = 'CONFIRMED' and role_score(position) >= 3;
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' new decision ' || case when v_n = 1 then 'maker' else 'makers' end || ' confirmed'); end if;
  select count(*) into v_n from contact_email_verifications where created_at > v_since and provider_status = 'valid';
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' email' || case when v_n = 1 then '' else 's' end || ' verified valid'); end if;
  select count(*) into v_n from email_research where researched_at > v_since;
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' compan' || case when v_n = 1 then 'y' else 'ies' end || ' fully researched for email'); end if;
  select count(*) into v_n from interactions where occurred_at > v_since and direction = 'INBOUND' and channel <> 'WEBSITE';
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' new repl' || case when v_n = 1 then 'y' else 'ies' end); end if;
  select count(*) into v_n from interactions where occurred_at > v_since and direction = 'OUTBOUND';
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' message' || case when v_n = 1 then '' else 's' end || ' sent'); end if;
  select count(*) into v_n from outreach_candidates where created_at > v_since and not dry_run and draft is not null and channel = 'EMAIL';
  if v_n > 0 then v_changed := v_changed || jsonb_build_object('text', v_n || ' email draft' || case when v_n = 1 then '' else 's' end || ' prepared'); end if;

  return jsonb_build_object(
    'greeting', case when v_hour < 12 then 'Good morning, Adam' when v_hour < 18 then 'Good afternoon, Adam' else 'Good evening, Adam' end,
    'brief', v_brief,
    'observations', coalesce((select jsonb_agg(o order by (o->>'rank')::int) from (select o from jsonb_array_elements(v_obs) o order by (o->>'rank')::int limit 5) z), '[]'::jsonb),
    'changed', v_changed, 'since', v_since, 'winning', v_win, 'wasting', v_waste,
    'coverage', (select jsonb_object_agg(key, jsonb_build_object('coverage_pct', value->'coverage_pct', 'with_dm', value->'with_dm', 'verified', value->'verified')) from jsonb_each(v_health)),
    'generated_at', now());
end $$;
revoke all on function public.hq_advisor() from public, anon;
grant execute on function public.hq_advisor() to authenticated;

-- Adam opened Today: what changed is measured from the previous visit (at least 30 minutes apart).
create or replace function public.hq_advisor_seen()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  insert into hq_advisor_state (admin_email, last_seen_at, prev_seen_at) values (v_admin, now(), now() - interval '24 hours')
  on conflict (admin_email) do update
    set prev_seen_at = case when hq_advisor_state.last_seen_at < now() - interval '30 minutes' then hq_advisor_state.last_seen_at else hq_advisor_state.prev_seen_at end,
        last_seen_at = now();
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hq_advisor_seen() from public, anon;
grant execute on function public.hq_advisor_seen() to authenticated;

-- Weekly review: the last 7 days against the 7 before, by Director, with the strongest opportunities and the weakest bottleneck.
create or replace function public.hq_weekly_review()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_health jsonb := director_channel_health(); v jsonb; v_weak record; v_best record;
begin
  with w(k, s, e) as (values ('this', now() - interval '7 days', now()), ('prev', now() - interval '14 days', now() - interval '7 days')),
  i as (select i.*, agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent,
               (select l.classification from gmail_sync_ledger l where l.gmail_message_id = i.external_message_id limit 1) cls
          from interactions i left join companies c on c.id = i.company_id where i.channel <> 'WEBSITE' and i.occurred_at > now() - interval '14 days'),
  m as (select w.k,
          count(*) filter (where i.direction = 'OUTBOUND' and i.occurred_at >= w.s and i.occurred_at < w.e) sent,
          count(*) filter (where i.direction = 'OUTBOUND' and i.channel = 'EMAIL' and i.occurred_at >= w.s and i.occurred_at < w.e) sent_email,
          count(*) filter (where i.direction = 'OUTBOUND' and i.channel = 'LINKEDIN' and i.occurred_at >= w.s and i.occurred_at < w.e) sent_linkedin,
          count(*) filter (where i.direction = 'INBOUND' and i.occurred_at >= w.s and i.occurred_at < w.e) replies,
          count(*) filter (where i.direction = 'INBOUND' and i.cls in ('MEETING_REQUEST', 'INTERESTED', 'POSITIVE', 'REFERRAL') and i.occurred_at >= w.s and i.occurred_at < w.e) positive
          from w left join i on true group by w.k)
  select jsonb_build_object(
    'period', jsonb_build_object('from', now() - interval '7 days', 'to', now()),
    'this_week', (select to_jsonb(m) - 'k' from m where k = 'this'), 'previous_week', (select to_jsonb(m) - 'k' from m where k = 'prev'),
    'reply_rate_pct', (select round(100.0 * replies / nullif(sent, 0)) from m where k = 'this'),
    'positive_reply_rate_pct', (select round(100.0 * positive / nullif(sent, 0)) from m where k = 'this'),
    'meetings', (select count(*) from tasks where task_type = 'MEETING_ACTION' and created_at > now() - interval '7 days'),
    'proposals', (select count(*) from opportunities where status in ('PROPOSAL', 'PROPOSAL_SENT') and updated_at > now() - interval '7 days'),
    'wins', (select count(*) from opportunities where status = 'WON' and updated_at > now() - interval '7 days'),
    'verified_emails', (select count(*) from contact_email_verifications where provider_status = 'valid' and created_at > now() - interval '7 days'),
    'email_drafts', (select count(*) from outreach_candidates where not dry_run and channel = 'EMAIL' and draft is not null and created_at > now() - interval '7 days'),
    'linkedin_drafts', (select count(*) from outreach_candidates where not dry_run and channel = 'LINKEDIN' and draft is not null and created_at > now() - interval '7 days'),
    'by_director', (select jsonb_agg(jsonb_build_object('director', h.key, 'label', advisor_agent_label(h.key), 'coverage_pct', h.value->'coverage_pct',
                        'with_dm', h.value->'with_dm', 'verified', h.value->'verified', 'linkedin_fallback', h.value->'linkedin_fallback',
                        'sent', (select count(*) from i where i.agent = h.key and i.direction = 'OUTBOUND' and i.occurred_at > now() - interval '7 days'),
                        'replies', (select count(*) from i where i.agent = h.key and i.direction = 'INBOUND' and i.occurred_at > now() - interval '7 days'))
                        order by (h.value->>'with_dm')::int desc) from jsonb_each(v_health) h where h.key <> 'PARTNERSHIPS'),
    'strongest_opportunities', (select coalesce(jsonb_agg(jsonb_build_object('company', c.name, 'status', o.status, 'next', o.next_action) order by o.priority desc nulls last), '[]'::jsonb)
                                  from (select * from opportunities where status in ('CALL_REQUIRED', 'MEETING', 'PROPOSAL', 'NEGOTIATION', 'CONTACTED')
                                         order by case status when 'NEGOTIATION' then 0 when 'PROPOSAL' then 1 when 'MEETING' then 2 when 'CALL_REQUIRED' then 3 else 4 end, priority desc nulls last limit 3) o
                                  join companies c on c.id = o.company_id))
  into v;
  select key, (value->>'coverage_pct')::int cov, (value->>'with_dm')::int dm into v_weak from jsonb_each(v_health)
   where key <> 'PARTNERSHIPS' and (value->>'with_dm')::int >= 8 order by coalesce((value->>'coverage_pct')::int, 0), (value->>'with_dm')::int desc limit 1;
  select h.key into v_best from jsonb_each(v_health) h
   where h.key <> 'PARTNERSHIPS' order by coalesce((h.value->>'coverage_pct')::int, 0) desc, (h.value->>'verified')::int desc limit 1;
  return v || jsonb_build_object(
    'weakest_bottleneck', case when v_weak.key is not null then advisor_agent_label(v_weak.key) || ': ' || coalesce(v_weak.cov, 0) || '% email coverage across ' || v_weak.dm || ' companies with a decision maker' end,
    'recommended_allocation', case when v_weak.key is not null then
      'Next week: give Email Intelligence and verification capacity to ' || advisor_agent_label(v_weak.key) || ' first; keep discovery steady where coverage is already highest ('
      || advisor_agent_label(v_best.key) || ').' end);
end $$;
revoke all on function public.hq_weekly_review() from public, anon;
grant execute on function public.hq_weekly_review() to authenticated;

-- Agents page: each Director carries its channel health and email coverage.
create or replace function public.hq_directors()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb := directors_snapshot(); h jsonb := director_channel_health();
begin
  return jsonb_set(v, '{members}', coalesce((select jsonb_agg(m || jsonb_build_object('channel', h->(m->>'key')) order by ord)
                                              from jsonb_array_elements(v->'members') with ordinality e(m, ord)), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------- 10. compliance / investor inboxes are never a commercial route
do $$ declare d text := pg_get_functiondef('public.email_local_class(text)'::regprocedure);
  a text := $a$|security|unsubscribe|newsletter|subscribe|^test$)' then 'EXCLUDED'$a$;
  b text := $b$|security|unsubscribe|newsletter|subscribe|^test$|compliance|investor|^ir$|whistleblow|ethics)' then 'EXCLUDED'$b$;
begin if position(a in d) > 0 then execute replace(d, a, b); end if; end $$;

-- ---------------------------------------------------------------- 11. company-level fallback carries its research evidence too
create or replace function public.email_research_summary(p_company uuid)
returns text language sql stable security definer set search_path = public as $$
  select 'Email research ' || to_char(er.researched_at at time zone 'Africa/Cairo', 'DD Mon') || ': ' || er.searches || ' searches'
         || coalesce(' (' || (select string_agg(lower(replace(x, '_', ' ')), ', ') from jsonb_array_elements_text(coalesce(er.checked->'kinds', '[]'::jsonb)) x) || ')', '')
         || ', ' || er.pages_read || ' official page' || case when er.pages_read = 1 then '' else 's' end || ' read, '
         || er.emails_seen || ' address' || case when er.emails_seen = 1 then '' else 'es' end || ' seen. '
         || case er.outcome when 'NO_EMAIL_FOUND' then 'No business email is published.' when 'INBOX_ONLY' then 'Only a general inbox is published.'
                            when 'DEPARTMENT_EMAIL' then 'Only a department inbox, which did not verify.' else 'No named person''s address verified.' end
    from email_research er where er.company_id = p_company order by er.researched_at desc limit 1
$$;
revoke all on function public.email_research_summary(uuid) from public, anon, authenticated;

do $$ declare d text := pg_get_functiondef('public.outreach_desk()'::regprocedure);
  a text := $a$then jsonb_build_object('state', 'EXHAUSTED', 'fallback', 'INSTAGRAM', 'label', 'Instagram fallback — no person confirmed, email research complete')$a$;
  b text := $b$then jsonb_build_object('state', 'EXHAUSTED', 'fallback', case when t.title ~ '^LINKEDIN' then 'LINKEDIN' else 'INSTAGRAM' end,
                           'label', case when t.title ~ '^LINKEDIN' then 'LinkedIn fallback — no named person, email exhausted' else 'Instagram fallback — no named person, email exhausted' end,
                           'evidence', email_research_summary(t.company_id))$b$;
begin if position(a in d) > 0 then execute replace(d, a, b); end if; end $$;

-- ---------------------------------------------------------------- 12. cohort acceptance report (20 Brand, 20 Wedding, 20 Travel)
create or replace function public.email_first_cohort_report(p_tag text)
returns jsonb language sql stable security definer set search_path = public as $$
  with t as (select t.company_id, t.before from email_intel_tests t where t.test_tag = p_tag),
  c as (select t.company_id, c.name, t.before,
               agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent,
               company_email_state(c.id) s, c.universe_status = 'QUALIFIED' qualified,
               exists (select 1 from contacts k where k.company_id = c.id and coalesce(btrim(k.email), '') <> '' and email_local_class(k.email) in ('PERSONAL', 'DEPARTMENT')
                         and (coalesce(k.email_source_url, '') <> '' or k.email_verification_provider is not null)
                         and (k.email_tier = 2 or (k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3))) public_email,
               (select er.id from email_research er where er.company_id = c.id and er.test_tag = p_tag order by er.researched_at desc limit 1) research_id
          from t join companies c on c.id = t.company_id),
  d as (select (x->>'company_id')::uuid company_id, x->>'channel' channel from jsonb_array_elements(outreach_desk()->'needs_review') x)
  select jsonb_build_object('tag', p_tag, 'cohorts', (select jsonb_agg(z order by array_position(array['BRANDS', 'WEDDINGS', 'TRAVEL'], z->>'agent')) from (
    select jsonb_build_object('agent', c.agent, 'label', advisor_agent_label(c.agent),
      'companies', count(*), 'qualified', count(*) filter (where c.qualified),
      'researched', count(*) filter (where c.research_id is not null),
      'decision_maker', count(*) filter (where (c.s->>'has_dm')::boolean),
      'public_email_found', count(*) filter (where c.public_email),
      'valid_verified', count(*) filter (where c.s->>'state' in ('VERIFIED', 'VERIFIED_INBOX')),
      'valid_verified_before', count(*) filter (where c.before->'email_route'->>'state' in ('VERIFIED', 'VERIFIED_INBOX')),
      'needs_verification', count(*) filter (where c.s->>'state' = 'NEEDS_VERIFICATION'),
      'research_pending', count(*) filter (where c.s->>'state' = 'RESEARCH_PENDING'),
      'linkedin_fallback', count(*) filter (where c.s->>'state' = 'EXHAUSTED' and c.s->>'fallback' = 'LINKEDIN'),
      'linkedin_fallback_with_evidence', count(*) filter (where c.s->>'state' = 'EXHAUSTED' and c.s->>'fallback' = 'LINKEDIN' and coalesce(c.s->>'evidence', '') <> ''),
      'instagram_fallback', count(*) filter (where c.s->>'state' = 'EXHAUSTED' and c.s->>'fallback' = 'INSTAGRAM'),
      'no_route', count(*) filter (where c.s->>'state' = 'EXHAUSTED' and c.s->>'fallback' is null),
      'email_needs_review', (select count(*) from d where d.channel = 'EMAIL' and d.company_id in (select c2.company_id from c c2 where c2.agent = c.agent)),
      'linkedin_needs_review', (select count(*) from d where d.channel = 'LINKEDIN' and d.company_id in (select c2.company_id from c c2 where c2.agent = c.agent)),
      'coverage_pct', round(100.0 * count(*) filter (where c.s->>'state' in ('VERIFIED', 'VERIFIED_INBOX')) / nullif(count(*) filter (where (c.s->>'has_dm')::boolean), 0)),
      'outcomes', (select jsonb_object_agg(o, n) from (select er.outcome o, count(*) n from email_research er
                    where er.test_tag = p_tag and er.company_id in (select c2.company_id from c c2 where c2.agent = c.agent) group by 1) q),
      'searches_avg', (select round(avg(er.searches), 1) from email_research er where er.test_tag = p_tag and er.company_id in (select c2.company_id from c c2 where c2.agent = c.agent)),
      'pages_avg', (select round(avg(er.pages_read), 1) from email_research er where er.test_tag = p_tag and er.company_id in (select c2.company_id from c c2 where c2.agent = c.agent))) z
    from c group by c.agent) q),
    'companies', (select jsonb_agg(jsonb_build_object('company', c.name, 'agent', c.agent, 'state', c.s->>'state', 'fallback', c.s->>'fallback',
                    'label', c.s->>'label', 'email', c.s->>'email', 'evidence', c.s->>'evidence') order by c.agent, c.name) from c))
$$;
revoke all on function public.email_first_cohort_report(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- 15. the before / after snapshot carries the email route
-- email_intel_snapshot (the cohort "before" record) also stores company_email_state, so a cohort report can show VALID_VERIFIED before vs after.
do $p$ declare d text := pg_get_functiondef('public.email_intel_snapshot(uuid)'::regprocedure);
begin
  if position('''email_route''' in d) = 0 then
    if position($o$else 'NOT DRAFTED' end,
    'at', now())$o$ in d) = 0 then raise exception 'email_intel_snapshot: pattern not found'; end if;
    execute replace(d, $o$else 'NOT DRAFTED' end,
    'at', now())$o$, $n$else 'NOT DRAFTED' end,
    'email_route', company_email_state(p_company), 'at', now())$n$);
  end if;
end $p$;

-- ---------------------------------------------------------------- 16. the Email agent owns workflow 25 too
update agent_registry set workflows = array['23 -', '24 -', '25 -'],
  schedule = array['03:15', '08:40', '09:45', '12:15', '15:45', '18:15', '20:40', '20:55', '23:15'],
  focus = 'Workflow 23 (full public checklist: official contact, team, press and partnership pages, PDFs and media kits, the named people, trade directories, Instagram bio), workflow 24 (Hunter verification inside a daily cap) and workflow 25 (Email Finder by name, only after public research is exhausted; saved only when verified valid)'
 where key = 'EMAIL';

-- ---------------------------------------------------------------- 17. fixed search_path on the helpers this migration (re)defines
alter function public.advisor_agent_label(text) set search_path = public;
alter function public.email_local_class(text) set search_path = public;
alter function public.role_focus(text) set search_path = public;
