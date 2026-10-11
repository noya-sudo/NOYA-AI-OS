-- Final efficiency pass (Adam, 11 Oct 2026). No new agents, no HQ redesign: the existing commercial engine made efficient.
-- 1. EMAIL READY is the primary acquisition KPI. Acquisition health is split: valid verified email / verified general inbox /
--    LinkedIn fallback / Instagram fallback / warm / existing relationship (acquisition_health, queue_health, Advisor).
-- 2. Backlog first: an address already on file is a verification job, never a reason to fall back to LinkedIn (the 10-day
--    expiry is gone). The verification queue works exactly what the route is waiting on, in priority order, on the company's
--    confirmed domain only, cold and unsuppressed companies only, one company one address.
-- 3. Hunter Starter (decided 11 Oct, Adam buys it; no auto-recharge): plan-aware daily caps read from the live account
--    snapshot. Free keeps 8 verifications / 2 lookups a day; Starter 40 / 25 inside a 1,500-credit monthly budget.
--    hunter_daily_funnel() tracks finder attempts -> finds -> verifications -> VALID / RISKY / INVALID -> credits -> drafts
--    -> sends -> replies -> meetings.
-- 4. LinkedIn cleanup: cold_route_sweep() keeps a LinkedIn / Instagram task only where email is exhausted with evidence,
--    moves the rest back to email, supersedes them when a verified email exists, and cancels duplicate cold touches.
--    The planner runs it nightly. One company, one active cold route.
-- 5. Small founder-led firms (weddings, travel, concierge, creative, production, villas): a verified official general inbox
--    after named-person research fails, addressed for the attention of the named decision maker (VERIFIED_GENERAL).
-- 6. Reserve discipline: 100-150 email-ready prospects in reserve; at most 30 unsent email drafts and 20 open LinkedIn /
--    Instagram drafts at a time. 40-50 verified drafts a day is scaling capacity, not a quota.
-- 7. Reply attribution by originating message and channel, per Director and send cohort (outreach_attribution).

-- ---------------------------------------------------------------- 1. settings
update system_config set value = value || jsonb_build_object(
    'plan_caps', jsonb_build_object(
      'FREE', jsonb_build_object('verify_per_day', 8, 'finder_per_day', 2, 'monthly_credits', 50),
      'STARTER', jsonb_build_object('verify_per_day', 40, 'finder_per_day', 25, 'monthly_credits', 2000, 'monthly_budget_credits', 1500)),
    'auto_recharge', false,
    'plan_note', 'Hunter Starter decided 11 Oct (Adam buys it in Hunter; auto-recharge off). Caps follow the live plan in hunter_account. Growth only if a month of real use shows Starter constrains qualified email production.',
    'scope', 'ROUTE_PENDING'), updated_at = now()
 where key = 'email_verification';
update system_config set value = value || jsonb_build_object(
    'priority_lanes', jsonb_build_array('BRANDS', 'WEDDINGS', 'TRAVEL', 'SPORTS', 'HOSPITALITY', 'PRIVATE', 'CORPORATE'),
    'verification_wait_days_note', 'Retired 11 Oct: an unchecked address waits for verification without expiry.'), updated_at = now()
 where key = 'email_first';
insert into system_config (key, value) values ('email_reserve', jsonb_build_object(
  'email_ready_target', jsonb_build_array(100, 150),
  'weekly_new_sends_target', jsonb_build_array(75, 100),
  'max_unsent_email_drafts', 30,
  'max_open_social_drafts', 20,
  'scaling_capacity_drafts_per_day', jsonb_build_array(40, 50),
  'note', 'Email is the dominant cold channel. Keep 100-150 email-ready prospects in reserve; draft from the reserve without stockpiling: at most 30 unsent email drafts and 20 open LinkedIn / Instagram drafts.'))
on conflict (key) do update set value = excluded.value, updated_at = now();

-- ---------------------------------------------------------------- 2. helpers
-- The live Hunter plan (from workflow 24's account snapshot) -> today's caps. Nothing is ever bought here.
create or replace function public.hunter_plan_caps()
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  with a as (select coalesce((select value from system_config where key = 'hunter_account'), '{}'::jsonb) v),
  c as (select coalesce((select value from system_config where key = 'email_verification'), '{}'::jsonb) v),
  f as (select coalesce((select value from system_config where key = 'email_first'), '{}'::jsonb) v),
  t as (select case when lower(coalesce((select v from a)->>'plan', 'free')) like 'free%' then 'FREE'
                    when lower((select v from a)->>'plan') like 'starter%' then 'STARTER'
                    when lower((select v from a)->>'plan') like 'growth%' then 'GROWTH' else 'PAID' end tier),
  k as (select t.tier, (select v from c)->'plan_caps'->(case when t.tier = 'FREE' then 'FREE' else 'STARTER' end) caps,
               nullif((select v from a)->>'credits_used', '')::numeric used from t),
  b as (select k.*, coalesce((k.caps->>'monthly_budget_credits')::numeric, (k.caps->>'monthly_credits')::numeric) budget from k)
  select jsonb_build_object(
    'plan', coalesce((select v from a)->>'plan', 'Free'), 'tier', b.tier,
    'verify_per_day', case when b.tier <> 'FREE' and b.used >= b.budget then 0
                           else coalesce((b.caps->>'verify_per_day')::int, ((select v from c)->>'daily_cap')::int, 8) end,
    'finder_per_day', case when b.tier <> 'FREE' and b.used >= b.budget then 0
                           else coalesce((b.caps->>'finder_per_day')::int, ((select v from f)->>'finder_daily_cap')::int, 2) end,
    'finder_first', b.tier <> 'FREE',
    'monthly_credits', (b.caps->>'monthly_credits')::int, 'monthly_budget_credits', b.budget,
    'credits_used', b.used, 'budget_reached', b.tier <> 'FREE' and coalesce(b.used >= b.budget, false),
    'reset_date', (select v from a)->>'reset_date', 'checked_at', (select v from a)->>'checked_at')
  from b
$function$;

-- An address is only worth verifying on the company's own confirmed domain (company_research_domain is the same guard
-- email research uses: an unconfirmed website that does not spell the company's name gives no domain).
create or replace function public.email_on_company_domain(p_email text, p_company uuid)
returns boolean language sql stable security definer set search_path to 'public' as $function$
  select coalesce((select x.d is not null and (split_part(lower(btrim(coalesce(p_email, ''))), '@', 2) = x.d
                                               or split_part(lower(btrim(coalesce(p_email, ''))), '@', 2) like '%.' || x.d)
                     from (select company_research_domain(c.name, c.website, c.website_confirmed_at) d from companies c where c.id = p_company) x), false)
$function$;

-- The same domain test with the domain already computed (contact_email_route computes it once per contact).
create or replace function public.email_domain_matches(p_email text, p_domain text)
returns boolean language sql immutable set search_path to 'public' as $function$
  select p_domain is not null and (split_part(lower(btrim(coalesce(p_email, ''))), '@', 2) = p_domain
                                   or split_part(lower(btrim(coalesce(p_email, ''))), '@', 2) like '%.' || p_domain)
$function$;

-- D4 (Adam, 11 Oct): small / founder-led wedding, travel, concierge, creative, production and villa firms may be reached
-- through a verified official general inbox, for the attention of the named decision maker. Never large brands, groups,
-- hotels, banks, airlines or corporates.
create or replace function public.general_route_eligible(p_company uuid)
returns boolean language sql stable security definer set search_path to 'public' as $function$
  select coalesce((
    select agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes)
             in ('WEDDINGS', 'TRAVEL', 'BRANDS', 'HOSPITALITY', 'PRIVATE', 'SPORTS', 'MEDIA')
       and coalesce(c.company_type, '') ~* '(wedding|event|planner|travel|tour|dmc|destination management|concierge|villa|lodge|creative|production|studio|photograph|film|pr agency|pr_agency|expedition|safari|retreat|yacht charter)'
       and coalesce(c.company_type, '') !~* '(group|chain|multinational|global|international|network|platform|marketplace|bank|airline|hotel|resort|fashion house|management company|management_company|tmc|family.office|wealth|invest|law|legal|consult|insurance|developer|real.estate|summit|forum|conference|b2b|media group|automotive|manufactur|payment|streaming)'
       and coalesce(c.company_type, '') !~* '\mbrand\)?\s*$'
       and c.name !~* '(four seasons|marriott|hilton|accor|ihg|hyatt|st\. regis|ritz|sheraton|kempinski|mandarin oriental|shangri|fairmont|radisson|wyndham|intercontinental|jumeirah|aman\M|rosewood|belmond|six senses|abercrombie|kuoni|tui\M|virtuoso)'
      from companies c where c.id = p_company), false)
$function$;

-- ---------------------------------------------------------------- 3. routes
-- Order: VERIFIED (their own) > VERIFIED_INBOX (department, for their attention) > NEEDS_VERIFICATION (their own address,
-- then a department inbox; no expiry) > RESEARCH_PENDING > VERIFIED_GENERAL / general inbox pending (small firms, after
-- research) > FINDER_PENDING (paid Hunter plan, priority lanes) > EXHAUSTED with evidence and a LinkedIn / Instagram fallback.
create or replace function public.contact_email_route(p_contact uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare k contacts%rowtype; c companies%rowtype; er email_research%rowtype; v_inbox contacts%rowtype; v_pend contacts%rowtype; v_gen contacts%rowtype;
        v_find email_finder_log%rowtype;
        v_cfg jsonb := coalesce((select value from system_config where key = 'email_first'), '{}'::jsonb);
        v_max int; v_st text; v_ver text; v_gver text; v_fb text; v_ev text; v_kinds text; v_name text; v_general boolean := false;
        v_dom text; v_dom_set boolean := false;
begin
  v_max := coalesce((v_cfg->>'research_max_age_days')::int, 60);
  select * into k from contacts where id = p_contact;
  if k.id is null then return jsonb_build_object('state', 'NO_PERSON', 'label', 'No decision maker confirmed yet'); end if;
  select * into c from companies where id = k.company_id;
  v_name := nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), '');
  v_st := email_state_v3(k.email, k.email_status, k.email_source_url, k.email_verification_provider);
  -- 1 their own verified address
  if v_st = 'VALID_VERIFIED' and email_local_class(k.email) <> 'EXCLUDED' then
    return jsonb_build_object('state', 'VERIFIED', 'email', lower(btrim(k.email)), 'label', 'Verified email');
  end if;
  -- 2 a verified department inbox for their attention (partnership pitches never go to press / PR inboxes)
  select i.* into v_inbox from contacts i
   where i.company_id = k.company_id and i.route_type = 'COMPANY_INBOX' and i.email_tier = 2 and not coalesce(i.do_not_contact, false)
     and email_state_v3(i.email, i.email_status, i.email_source_url, i.email_verification_provider) = 'VALID_VERIFIED'
     and not (coalesce(c.partnership_model, 'CONTENT_TALENT') <> 'CONTENT_TALENT' and (coalesce(i.position, '') || ' ' || i.email) ~* '(press|media|communications|comms|\mpr\M)')
   order by i.created_at limit 1;
  if v_inbox.id is not null then
    return jsonb_build_object('state', 'VERIFIED_INBOX', 'email', lower(btrim(v_inbox.email)), 'inbox_id', v_inbox.id,
                              'label', 'Verified ' || lower(coalesce(nullif(v_inbox.position, ''), 'department inbox')) || ' for their attention');
  end if;
  -- 3 their own address on the company's confirmed domain, never provider-checked: a verification job (no expiry)
  select v.provider_status into v_ver from contact_email_verifications v
   where lower(v.email) = lower(btrim(coalesce(k.email, ''))) and v.provider_status is not null
   order by coalesce(v.checked_at, v.created_at) desc limit 1;
  if coalesce(btrim(k.email), '') <> '' and v_ver is null and v_st in ('PUBLIC_UNVERIFIED', 'UNKNOWN') and email_local_class(k.email) in ('PERSONAL', 'DEPARTMENT') then
    v_dom := company_research_domain(c.name, c.website, c.website_confirmed_at); v_dom_set := true;
    if email_domain_matches(k.email, v_dom) then
      return jsonb_build_object('state', 'NEEDS_VERIFICATION', 'email', lower(btrim(k.email)), 'label', 'Email found — waiting for verification');
    end if;
  end if;
  -- 4 a department inbox on the company domain, not yet checked (no expiry)
  if exists (select 1 from contacts i where i.company_id = k.company_id and i.route_type = 'COMPANY_INBOX' and i.email_tier = 2 and not coalesce(i.do_not_contact, false)
               and email_state_v3(i.email, i.email_status, i.email_source_url, i.email_verification_provider) in ('PUBLIC_UNVERIFIED', 'UNKNOWN')) then
    if not v_dom_set then v_dom := company_research_domain(c.name, c.website, c.website_confirmed_at); v_dom_set := true; end if;
    select i.* into v_pend from contacts i
     where i.company_id = k.company_id and i.route_type = 'COMPANY_INBOX' and i.email_tier = 2 and not coalesce(i.do_not_contact, false)
       and email_state_v3(i.email, i.email_status, i.email_source_url, i.email_verification_provider) in ('PUBLIC_UNVERIFIED', 'UNKNOWN')
       and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(i.email)) and v.provider_status is not null)
       and email_domain_matches(i.email, v_dom)
       and not (coalesce(c.partnership_model, 'CONTENT_TALENT') <> 'CONTENT_TALENT' and (coalesce(i.position, '') || ' ' || i.email) ~* '(press|media|communications|comms|\mpr\M)')
     order by i.created_at limit 1;
    if v_pend.id is not null then
      return jsonb_build_object('state', 'NEEDS_VERIFICATION', 'email', lower(btrim(v_pend.email)), 'inbox_id', v_pend.id,
                                'label', 'Department inbox found — waiting for verification');
    end if;
  end if;
  -- 5 the full email research checklist comes before any fallback
  select * into er from email_research where company_id = k.company_id order by researched_at desc limit 1;
  if er.id is null or er.researched_at < k.created_at - interval '1 hour' or er.researched_at < now() - make_interval(days => v_max)
     or coalesce((er.checked->>'version')::int, 1) < 2 then
    return jsonb_build_object('state', 'RESEARCH_PENDING', 'label', case when er.id is null then 'Email research pending' else 'Email research to complete (full checklist)' end,
                              'researched_at', er.researched_at);
  end if;
  if not v_dom_set then v_dom := company_research_domain(c.name, c.website, c.website_confirmed_at); v_dom_set := true; end if;
  -- 6 small founder-led firms: a verified official general inbox, for the attention of the named decision maker (D4)
  v_general := v_name is not null and general_route_eligible(k.company_id);
  if v_general then
    select i.* into v_gen from contacts i
     where i.company_id = k.company_id and i.route_type = 'COMPANY_INBOX' and not coalesce(i.do_not_contact, false)
       and email_local_class(i.email) = 'GENERAL' and email_domain_matches(i.email, v_dom)
       and email_state_v3(i.email, i.email_status, i.email_source_url, i.email_verification_provider) = 'VALID_VERIFIED'
     order by (split_part(lower(i.email), '@', 1) ~ '^(hello|info|contact|enquiries|enquiry|inquiries|office|team|studio)$') desc, i.created_at limit 1;
    if v_gen.id is not null then
      return jsonb_build_object('state', 'VERIFIED_GENERAL', 'email', lower(btrim(v_gen.email)), 'inbox_id', v_gen.id, 'general', true,
                                'label', 'Verified general inbox, for the attention of ' || v_name);
    end if;
    select i.* into v_gen from contacts i
     where i.company_id = k.company_id and i.route_type = 'COMPANY_INBOX' and not coalesce(i.do_not_contact, false)
       and email_local_class(i.email) = 'GENERAL' and email_domain_matches(i.email, v_dom)
       and email_state_v3(i.email, i.email_status, i.email_source_url, i.email_verification_provider) in ('PUBLIC_UNVERIFIED', 'UNKNOWN')
       and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(i.email)) and v.provider_status is not null)
     order by (split_part(lower(i.email), '@', 1) ~ '^(hello|info|contact|enquiries|enquiry|inquiries|office|team|studio)$') desc, i.created_at limit 1;
    if v_gen.id is not null then
      return jsonb_build_object('state', 'NEEDS_VERIFICATION', 'email', lower(btrim(v_gen.email)), 'inbox_id', v_gen.id, 'general', true,
                                'label', 'General inbox found — waiting for verification (for the attention of ' || v_name || ')');
    end if;
    select v.provider_status into v_gver from contact_email_verifications v join contacts i on lower(btrim(i.email)) = lower(v.email)
     where i.company_id = k.company_id and i.route_type = 'COMPANY_INBOX' and email_local_class(i.email) = 'GENERAL' and v.provider_status is not null
     order by coalesce(v.checked_at, v.created_at) desc limit 1;
  end if;
  -- 7 a provider lookup by name before any fallback, when the Hunter plan has the capacity (paid plans only)
  select f.* into v_find from email_finder_log f where f.contact_id = k.id order by f.attempted_at desc limit 1;
  if coalesce(btrim(k.email), '') = '' and k.identity_status = 'CONFIRMED' and v_dom is not null
     and (v_find.id is null or v_find.attempted_at < now() - interval '90 days')
     and length(btrim(coalesce(k.first_name, ''))) >= 2 and length(btrim(coalesce(k.last_name, ''))) >= 2 then
    if role_score(k.position) >= 3
       and lower(coalesce((select value->>'plan' from system_config where key = 'hunter_account'), 'free')) not like 'free%'
       and agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes)
           in (select jsonb_array_elements_text(coalesce(v_cfg->'priority_lanes', '[]'::jsonb))) then
      return jsonb_build_object('state', 'FINDER_PENDING', 'label', 'Email research complete — provider lookup by name pending', 'researched_at', er.researched_at);
    end if;
  end if;
  -- 8 exhausted: the fallback carries the evidence
  v_fb := case when coalesce(k.linkedin, '') ~* 'linkedin\.com/in/' then 'LINKEDIN'
               when coalesce(k.instagram, c.instagram, '') <> '' then 'INSTAGRAM' end;
  v_kinds := (select string_agg(lower(replace(x, '_', ' ')), ', ') from jsonb_array_elements_text(coalesce(er.checked->'kinds', '[]'::jsonb)) x);
  v_ev := 'Email research ' || to_char(er.researched_at at time zone 'Africa/Cairo', 'DD Mon') || ': ' || er.searches || ' searches'
       || coalesce(' (' || v_kinds || ')', '') || ', ' || er.pages_read || ' official page' || case when er.pages_read = 1 then '' else 's' end || ' read, '
       || er.emails_seen || ' address' || case when er.emails_seen = 1 then '' else 'es' end || ' seen. '
       || case
            when coalesce(btrim(k.email), '') <> '' and v_ver is not null then 'Their address ' || lower(btrim(k.email)) || ' was checked: ' || replace(v_ver, '_', '-') || '. '
            when coalesce(btrim(k.email), '') <> '' then 'Their listed address ' || lower(btrim(k.email)) || ' is not usable (a shared inbox, or not on the confirmed company domain). '
            when er.outcome = 'NO_EMAIL_FOUND' then 'No business email is published for them. '
            when er.outcome = 'INBOX_ONLY' then 'Only a general inbox is published. '
            when er.outcome = 'DEPARTMENT_EMAIL' then 'Only a department inbox, which did not verify. '
            else 'The named addresses found belong to other people. ' end
       || case when v_general then case when v_gver is not null then 'Official general inbox checked: ' || replace(v_gver, '_', '-') || '. '
                                        else 'No official general inbox on the company domain. ' end else '' end
       || case when v_find.id is not null then 'Provider lookup ' || to_char(v_find.attempted_at at time zone 'Africa/Cairo', 'DD Mon') || ': '
                    || case v_find.outcome when 'NOT_FOUND' then 'no address' when 'NOT_VERIFIED' then 'an address that did not verify' else lower(v_find.outcome) end || '.'
               else '' end;
  return jsonb_build_object('state', 'EXHAUSTED', 'fallback', v_fb,
    'label', case v_fb when 'LINKEDIN' then 'LinkedIn fallback — email exhausted' when 'INSTAGRAM' then 'Instagram fallback — email exhausted'
                       else 'Email exhausted — no fallback route' end,
    'evidence', btrim(v_ev), 'researched_at', er.researched_at, 'research_id', er.id);
end $function$;

create or replace function public.company_email_state(p_company uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  with c as (select c.*, contact_segment(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) seg
               from companies c where c.id = p_company),
  dm as materialized (select k.id, role_priority(k.position, c.seg) rp, contact_email_route(k.id) r
           from contacts k join c on c.id = k.company_id
          where k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3 and not coalesce(k.do_not_contact, false)
            and coalesce(k.status, '') <> 'DO_NOT_CONTACT'
            and length(btrim(coalesce(k.first_name, ''))) >= 2 and length(btrim(coalesce(k.last_name, ''))) >= 2
            and not (coalesce(c.partnership_model, 'CONTENT_TALENT') <> 'CONTENT_TALENT' and pr_role(k.position)))
  select coalesce(
    (select dm.r || jsonb_build_object('contact_id', dm.id, 'has_dm', true, 'dms', (select count(*) from dm))
       from dm order by case dm.r->>'state' when 'VERIFIED' then 0 when 'VERIFIED_INBOX' then 1 when 'VERIFIED_GENERAL' then 2
                                            when 'NEEDS_VERIFICATION' then 3 when 'FINDER_PENDING' then 4 when 'RESEARCH_PENDING' then 5 else 6 end,
                        case dm.r->>'fallback' when 'LINKEDIN' then 0 when 'INSTAGRAM' then 1 else 2 end, dm.rp desc limit 1),
    jsonb_build_object('state', 'NO_PERSON', 'has_dm', false, 'dms', 0, 'label', 'No decision maker confirmed yet'))
$function$;

-- offset 0 keeps the route a single call per company (it was being re-evaluated per output column: 5.4s -> 1.2s)
create or replace function public.prospect_routes()
returns table(company_id uuid, company text, agent text, partnership boolean, cold boolean, state text, fallback text, contact_id uuid, has_dm boolean, label text, evidence text)
language sql stable security definer set search_path to 'public' as $function$
  select c.id, c.name,
         agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes),
         c.partnership_model is not null, relationship_state(c.id) = 'COLD',
         s->>'state', s->>'fallback', (s->>'contact_id')::uuid, coalesce((s->>'has_dm')::boolean, false), s->>'label', s->>'evidence'
    from companies c cross join lateral (select company_email_state(c.id) s offset 0) x
   where c.universe_status = 'QUALIFIED' and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'
$function$;

-- ---------------------------------------------------------------- 4. verification and finder queues
-- Backlog first: verify exactly what each cold company's route is waiting on (the decision maker's own address, else a
-- department inbox, else a small firm's general inbox), then drafts held for verification, then department inboxes at
-- companies with no decision maker yet. Company domain only, not suppressed, one address per company, priority order.
create or replace function public.email_verification_queue(p_limit integer default 10)
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  with cfg as (select coalesce((select value from system_config where key = 'email_verification'), '{}'::jsonb) v),
  caps as (select hunter_plan_caps() v),
  used as (select count(*) n from contact_email_verifications
            where source_workflow like '24 %' and created_at >= ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo'
              and provider_status in ('valid', 'invalid', 'accept_all', 'webmail', 'disposable')),
  co as materialized (
    select c.id company_id, c.name company, c.partnership_model, partner_hotel_route(c.partnership_model, c.company_type) hotel,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent,
           (select company_email_state(c.id) offset 0) s
      from companies c
     where c.universe_status = 'QUALIFIED' and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'
       and relationship_state(c.id) = 'COLD' and coalesce(c.outreach_hold_until, '-infinity'::timestamptz) < now()
       -- a warm path or Adam's own approach comes first: no cold verification spend there
       and not exists (select 1 from tasks w where w.company_id = c.id and w.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
                        and w.title ~* '^(ADAM --|ADAM PERSONAL|WARM ROUTE|HOLD - WARM ROUTE|RECONNECT)')),
  t as (
    select co.company_id, co.company, co.partnership_model, co.hotel, co.agent, coalesce((co.s->>'inbox_id')::uuid, (co.s->>'contact_id')::uuid) target,
           case when co.s->>'inbox_id' is null then 'PERSON' when coalesce((co.s->>'general')::boolean, false) then 'GENERAL_INBOX' else 'DEPARTMENT_INBOX' end kind, 1 src
      from co where co.s->>'state' = 'NEEDS_VERIFICATION'
    union all
    select co.company_id, co.company, co.partnership_model, co.hotel, co.agent, coalesce(w.route_contact_id, w.contact_id), 'HELD_DRAFT', 0
      from co join outreach_candidates w on w.company_id = co.company_id and w.status = 'HOLD' and w.hold_reason like 'EMAIL_NOT_VERIFIED%'
    union all
    select co.company_id, co.company, co.partnership_model, co.hotel, co.agent, i.id, 'DEPARTMENT_INBOX', 2
      from co join lateral (select i.id from contacts i
                             where i.company_id = co.company_id and i.route_type = 'COMPANY_INBOX' and i.email_tier = 2 and not coalesce(i.do_not_contact, false)
                               and not (coalesce(co.partnership_model, 'CONTENT_TALENT') <> 'CONTENT_TALENT'
                                        and (coalesce(i.position, '') || ' ' || coalesce(i.email, '')) ~* '(press|media|communications|comms|\mpr\M)')
                             order by i.created_at limit 1) i on true
     where co.s->>'state' = 'NO_PERSON'),
  q0 as (
    select k.id contact_id, lower(btrim(k.email)) email, k.first_name, k.last_name, k.position, k.email_tier, k.email_source_url,
           t.company_id, t.company, t.partnership_model, t.hotel, t.agent, t.kind, t.src,
           email_state(k.email_status, k.email_source_url, k.email_verification_provider) state, (t.src = 0) draft_waiting,
           row_number() over (partition by t.company_id order by t.src, (t.kind = 'PERSON') desc) per_company
      from t join contacts k on k.id = t.target
     where not coalesce(k.do_not_contact, false) and coalesce(k.status, '') <> 'DO_NOT_CONTACT'
       and coalesce(k.email, '') ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
       and email_state(k.email_status, k.email_source_url, k.email_verification_provider) in ('PUBLICLY_LISTED', 'UNVERIFIED')
       and email_local_class(k.email) <> 'EXCLUDED'
       and email_on_company_domain(k.email, k.company_id)
       and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(k.email))
                        and ((v.provider_status in ('valid', 'invalid', 'accept_all', 'webmail', 'disposable')
                              and coalesce(v.checked_at, v.created_at) > now() - make_interval(days => coalesce(((select v from cfg)->>'reverify_after_days')::int, 90)))
                          or coalesce(v.checked_at, v.created_at) > now() - interval '7 days'))
       and not (coalesce(t.partnership_model, 'CONTENT_TALENT') <> 'CONTENT_TALENT'
                and (pr_role(k.position) or split_part(lower(k.email), '@', 1) ~ '^(press|media|pr|communications|comms)([._-]|$)'))),
  q as (select * from q0 where per_company = 1)
  select jsonb_build_object(
    'provider', coalesce((select v from cfg)->>'provider', 'HUNTER'),
    'enabled', coalesce(((select v from cfg)->>'enabled')::boolean, false),
    'scope', 'ROUTE_PENDING',
    'plan', (select v->>'plan' from caps), 'tier', (select v->>'tier' from caps),
    'daily_cap', (select (v->>'verify_per_day')::int from caps),
    'reserve_verifications', coalesce(((select v from cfg)->>'reserve_verifications')::int, 0),
    'verified_today', (select n from used),
    'waiting', (select count(*) from q),
    'waiting_list', coalesce((select jsonb_agg(jsonb_build_object('contact_id', q.contact_id, 'email', q.email, 'name', nullif(btrim(coalesce(q.first_name, '') || ' ' || coalesce(q.last_name, '')), ''),
                      'position', q.position, 'company', q.company, 'company_id', q.company_id, 'agent', q.agent, 'kind', q.kind, 'tier', q.email_tier, 'source', q.email_source_url,
                      'draft_waiting', q.draft_waiting) order by q.draft_waiting desc, q.company) from q), '[]'::jsonb),
    'waiting_by_agent', coalesce((select jsonb_object_agg(agent, n) from (select coalesce(agent, 'OTHER') agent, count(*) n from q group by 1) z), '{}'::jsonb),
    'waiting_by_kind', coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from q group by 1) z), '{}'::jsonb),
    'items', coalesce((select jsonb_agg(to_jsonb(x) - 'rk' - 'per_company') from (
        select q.*, row_number() over (order by q.draft_waiting desc, q.src,
                 array_position(array['BRANDS', 'WEDDINGS', 'TRAVEL', 'SPORTS', 'HOSPITALITY', 'PRIVATE', 'CORPORATE', 'MEDIA', 'EGYPT'], q.agent) nulls last,
                 case q.kind when 'PERSON' then 0 when 'HELD_DRAFT' then 0 when 'GENERAL_INBOX' then 1 else 2 end,
                 (q.hotel and partner_route_rank(q.position) >= 1) desc, partner_route_rank(q.position) desc, role_score(q.position) desc,
                 (q.state = 'PUBLICLY_LISTED') desc, q.company) rk
          from q order by rk limit greatest(0, least(coalesce(p_limit, 10), (select (v->>'verify_per_day')::int from caps) - (select n from used)))) x), '[]'::jsonb))
$function$;

-- Provider lookup by name: FINDER_PENDING first (paid plan: before any fallback), then exhausted decision makers never looked up.
create or replace function public.email_finder_queue(p_limit integer default 5)
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  with cfg as (select coalesce((select value from system_config where key = 'email_first'), '{}'::jsonb) v),
  caps as (select hunter_plan_caps() v),
  used as (select count(*) n from email_finder_log
            where attempted_at >= ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo' and outcome <> 'ERROR'),
  p as materialized (select * from prospect_routes() pr where pr.cold and pr.state in ('FINDER_PENDING', 'EXHAUSTED')),
  q as (
    select k.id contact_id, k.first_name, k.last_name, k.position, c.id company_id, c.name company, p.agent, p.state route_state,
           company_research_domain(c.name, c.website, c.website_confirmed_at) domain,
           c.id in (select t.company_id from email_intel_tests t where t.test_tag = (select v->>'priority_test' from cfg)) cohort,
           role_priority(k.position, contact_segment(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes)) rp
      from p join contacts k on k.id = p.contact_id join companies c on c.id = p.company_id
     where coalesce(btrim(k.email), '') = ''
       and length(btrim(coalesce(k.first_name, ''))) >= 2 and length(btrim(coalesce(k.last_name, ''))) >= 2
       and company_research_domain(c.name, c.website, c.website_confirmed_at) is not null
       and coalesce(c.outreach_hold_until, '-infinity'::timestamptz) < now()
       and not exists (select 1 from email_finder_log f where f.contact_id = k.id and f.attempted_at > now() - interval '90 days'))
  select jsonb_build_object(
    'plan', (select v->>'plan' from caps), 'tier', (select v->>'tier' from caps),
    'daily_cap', (select (v->>'finder_per_day')::int from caps),
    'reserve_credits', coalesce(((select v from cfg)->>'finder_reserve_credits')::int, 3),
    'used_today', (select n from used), 'waiting', (select count(*) from q),
    'waiting_by_agent', coalesce((select jsonb_object_agg(agent, n) from (select coalesce(agent, 'OTHER') agent, count(*) n from q group by 1) z), '{}'::jsonb),
    'items', coalesce((select jsonb_agg(to_jsonb(x) - 'rp' - 'cohort') from (
        select * from q order by (route_state = 'FINDER_PENDING') desc, cohort desc,
                 array_position(array['BRANDS', 'WEDDINGS', 'TRAVEL', 'SPORTS', 'HOSPITALITY', 'PRIVATE', 'CORPORATE', 'MEDIA', 'EGYPT'], agent) nulls last, rp desc, company
        limit greatest(0, least(coalesce(p_limit, 5), (select (v->>'finder_per_day')::int from caps) - (select n from used)))) x), '[]'::jsonb))
$function$;

-- Email research order follows the priority audiences (Brands, Weddings, Travel, NOYA Private / talent, Hospitality, Private, Corporate)
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.email_gap_list(integer, text, boolean)'::regprocedure);
  n := replace(d, $a$case c.agent when 'BRANDS' then 40 when 'WEDDINGS' then 38 when 'TRAVEL' then 38 when 'HOSPITALITY' then 34 when 'CORPORATE' then 30
                   when 'PRIVATE' then 28 when 'MEDIA' then 20 when 'EGYPT' then 18 when 'SPORTS' then 32 else 10 end strategic$a$,
                  $a$case c.agent when 'BRANDS' then 40 when 'WEDDINGS' then 38 when 'TRAVEL' then 38 when 'SPORTS' then 36 when 'HOSPITALITY' then 34
                   when 'PRIVATE' then 31 when 'CORPORATE' then 28 when 'MEDIA' then 20 when 'EGYPT' then 18 else 10 end strategic$a$);
  if n = d then raise exception 'email_gap_list patch: pattern not found'; end if;
  execute n;
end $patch$;

-- ---------------------------------------------------------------- 5. one company, one active cold route
-- Every open cold LinkedIn / Instagram task is tested against true email exhaustion. Kept only where the person's and the
-- company's email routes are exhausted with research evidence (or a paid-plan provider lookup is about to run first).
-- Otherwise: superseded by a verified email, cancelled as a duplicate cold touch, or moved back to email (research or
-- verification). Cancelling is recorded on the task and the candidate; nothing is deleted.
create or replace function public.cold_route_sweep(p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_out jsonb; v_day text := to_char(now() at time zone 'Africa/Cairo', 'DD Mon');
begin
  drop table if exists _sweep;
  create temp table _sweep on commit drop as
  with t as (
    select t.id task_id, t.title, t.company_id, t.contact_id, t.created_at, t.status,
           case when t.title ~ '^INSTAGRAM' then 'INSTAGRAM' else 'LINKEDIN' end channel
      from tasks t
     where t.status in ('OPEN', 'IN_PROGRESS') and t.company_id is not null
       and (t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY)' or (t.title ~ '^ADAM -- LINKEDIN' and t.title !~* 'WARM'))
       and relationship_state(t.company_id) = 'COLD'),
  r as materialized (
    select t.*, (select case when t.contact_id is not null then contact_email_route(t.contact_id) end offset 0) rc,
           (select company_email_state(t.company_id) offset 0) cs,
           exists (select 1 from email_research er where er.company_id = t.company_id and coalesce((er.checked->>'version')::int, 1) >= 2) researched,
           exists (select 1 from tasks e where e.company_id = t.company_id and e.id <> t.task_id and e.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
                    and (e.title ~ '^(EMAIL READY|SEND APPROVED DRAFT)' or e.task_type = 'OUTREACH_DRAFT_READY'
                         or (e.task_type = 'SALES_OUTREACH_APPROVAL' and e.title !~ '^ADAM -- LINKEDIN')))
             or exists (select 1 from outbound_emails ob where ob.company_id = t.company_id and ob.status in ('QUEUED', 'CLAIMED', 'DRAFTED')) email_open,
           row_number() over (partition by t.company_id order by (t.channel = 'LINKEDIN') desc, (t.title ~ '^ADAM') desc, t.created_at desc) company_rank
      from t)
  select r.*, c.name company, agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent,
    case
      when r.rc->>'state' in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL') or r.cs->>'state' in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL') then 'SUPERSEDED_BY_VERIFIED_EMAIL'
      when r.email_open or r.company_rank > 1 then 'DUPLICATE_COLD_ROUTE'
      when r.rc->>'state' = 'NEEDS_VERIFICATION' or r.cs->>'state' = 'NEEDS_VERIFICATION' then 'BACK_TO_EMAIL_VERIFICATION'
      when r.rc->>'state' = 'RESEARCH_PENDING' or r.cs->>'state' = 'RESEARCH_PENDING' or not r.researched then 'BACK_TO_EMAIL_RESEARCH'
      when r.rc->>'state' = 'FINDER_PENDING' or r.cs->>'state' = 'FINDER_PENDING' then 'KEEP_FINDER_FIRST'
      else 'KEEP_EMAIL_EXHAUSTED' end verdict
    from r join companies c on c.id = r.company_id;

  if p_apply then
    drop table if exists _swept;
    create temp table _swept on commit drop as select task_id, verdict from _sweep where verdict not like 'KEEP%';
    update tasks t set status = 'CANCELLED', updated_at = now(),
           description = case s.verdict
             when 'SUPERSEDED_BY_VERIFIED_EMAIL' then 'Superseded ' || v_day || ': a verified email now exists at this company, so email replaces this message (email first, one cold route per company).'
             when 'DUPLICATE_COLD_ROUTE' then 'Cancelled ' || v_day || ': duplicate cold approach. This company already has an email or another message in progress (one company, one active cold route).'
             when 'BACK_TO_EMAIL_VERIFICATION' then 'Moved back to email ' || v_day || ': ' || coalesce(nullif(coalesce(s.rc->>'email', s.cs->>'email'), ''), 'an address for this company')
                  || ' is waiting for verification. LinkedIn is used only once email is exhausted with evidence.'
             else 'Moved back to email research ' || v_day || ': the full email research checklist is not complete for this company. LinkedIn is used only once email is exhausted with evidence.' end
           || chr(10) || coalesce(t.description, '')
      from _sweep s where s.task_id = t.id and s.verdict not like 'KEEP%';
    update outreach_candidates oc set status = 'SKIPPED', hold_reason = s.verdict, updated_at = now()
      from _swept s where oc.task_id = s.task_id;
  end if;

  select jsonb_build_object(
    'applied', p_apply, 'tested', count(*),
    'survived', count(*) filter (where verdict like 'KEEP%'),
    'by_verdict', (select jsonb_object_agg(verdict, n) from (select verdict, count(*) n from _sweep group by 1) z),
    'moved_back_by_agent', coalesce((select jsonb_object_agg(agent, n) from (select coalesce(agent, 'OTHER') agent, count(*) n from _sweep where verdict like 'BACK_TO_EMAIL%' group by 1) z), '{}'::jsonb),
    'survived_by_agent', coalesce((select jsonb_object_agg(agent, n) from (select coalesce(agent, 'OTHER') agent, count(*) n from _sweep where verdict like 'KEEP%' group by 1) z), '{}'::jsonb),
    'items', coalesce(jsonb_agg(jsonb_build_object('task_id', task_id, 'company', company, 'agent', agent, 'channel', channel, 'verdict', verdict,
                         'person_route', rc->>'state', 'company_route', cs->>'state', 'email', coalesce(rc->>'email', cs->>'email')) order by verdict, company), '[]'::jsonb))
    into v_out from _sweep;
  return v_out;
end $function$;

-- Planner: VERIFIED_GENERAL is an email route; LinkedIn / Instagram only when the whole company is exhausted; the nightly sweep;
-- the reserve caps (unsent email drafts, open LinkedIn / Instagram drafts). pick0 materialised so each route is computed once.
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.commercial_director_plan(boolean, integer, boolean)'::regprocedure);
  n := d;
  n := replace(n, $a$v_superseded int := 0; v_has_plan boolean; v_topup int;$a$,
                  $a$v_superseded int := 0; v_has_plan boolean; v_topup int; v_sweep jsonb; v_cap_e int; v_cap_s int; v_open_e int; v_open_s int;$a$);
  n := replace(n, $a$case when t.contact_id is not null and contact_email_route(t.contact_id)->>'state' in ('VERIFIED', 'VERIFIED_INBOX') then 'this person'$a$,
                  $a$case when t.contact_id is not null and contact_email_route(t.contact_id)->>'state' in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL') then 'this person'$a$);
  n := replace(n, $a$and ((t.contact_id is not null and contact_email_route(t.contact_id)->>'state' in ('VERIFIED', 'VERIFIED_INBOX'))
                or (t.company_id is not null and company_email_state(t.company_id)->>'state' = 'VERIFIED'))$a$,
                  $a$and ((t.contact_id is not null and contact_email_route(t.contact_id)->>'state' in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL'))
                or (t.company_id is not null and company_email_state(t.company_id)->>'state' in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL')))$a$);
  n := replace(n, $a$      get diagnostics v_superseded = row_count;
    end if;$a$,
                  $a$      get diagnostics v_superseded = row_count;
      v_sweep := cold_route_sweep(true);
    end if;$a$);
  n := replace(n, $a$ADAM PERSONAL OUTREACH|APPROVE OUTREACH$a$, $a$ADAM PERSONAL OUTREACH|ADAM --|SEND APPROVED DRAFT|APPROVE OUTREACH$a$);
  n := replace(n, $a$    pick0 as (
      select b.*, k.id k_id, ib.id ib_id, case when k.id is not null then contact_email_route(k.id) end rt$a$,
                  $a$    pick0 as materialized (
      select b.*, k.id k_id, ib.id ib_id, case when k.id is not null then contact_email_route(k.id) end rt,
             coalesce(company_email_state(b.company_id)->>'state', 'NO_PERSON') not in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'NEEDS_VERIFICATION', 'FINDER_PENDING', 'RESEARCH_PENDING') fallback_ok$a$);
  n := replace(n, $a$                           order by coalesce(i.email_tier = 2, false) desc, i.created_at limit 1) ib on true),$a$,
                  $a$                             and i.email_tier = 2
                           order by i.created_at limit 1) ib on true),$a$);
  n := replace(n, $a$          when p.k_id is not null and p.rt->>'state' in ('VERIFIED', 'VERIFIED_INBOX') then 'EMAIL'
          when p.k_id is not null and p.rt->>'state' = 'EXHAUSTED' and p.rt->>'fallback' = 'LINKEDIN' then 'LINKEDIN'
          when p.k_id is not null and p.rt->>'state' = 'EXHAUSTED' and p.rt->>'fallback' = 'INSTAGRAM'$a$,
                  $a$          when p.k_id is not null and p.rt->>'state' in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL') then 'EMAIL'
          when p.k_id is not null and p.fallback_ok and p.rt->>'state' = 'EXHAUSTED' and p.rt->>'fallback' = 'LINKEDIN' then 'LINKEDIN'
          when p.k_id is not null and p.fallback_ok and p.rt->>'state' = 'EXHAUSTED' and p.rt->>'fallback' = 'INSTAGRAM'$a$);
  n := replace(n, $a$        case when p.k_id is not null and p.rt->>'state' = 'VERIFIED_INBOX' then (p.rt->>'inbox_id')::uuid$a$,
                  $a$        case when p.k_id is not null and p.rt->>'state' in ('VERIFIED_INBOX', 'VERIFIED_GENERAL') then (p.rt->>'inbox_id')::uuid$a$);
  n := replace(n, $a$  select jsonb_build_object(
    'run_date', current_date, 'dry_run', p_dry_run, 'target', v_target,$a$,
                  $a$  -- Reserve discipline (11 Oct): draft from the email-ready reserve, never stockpile. Today's undrafted candidates beyond the
  -- room left under max_unsent_email_drafts / max_open_social_drafts are not planned (they stay in the reserve).
  select coalesce((value->>'max_unsent_email_drafts')::int, 30), coalesce((value->>'max_open_social_drafts')::int, 20) into v_cap_e, v_cap_s
    from system_config where key = 'email_reserve';
  v_open_e := (select count(*) from outreach_candidates oc join tasks t on t.id = oc.task_id
                where not oc.dry_run and oc.channel = 'EMAIL' and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING'))
            + (select count(*) from outbound_emails where status in ('QUEUED', 'CLAIMED', 'DRAFTED'));
  v_open_s := (select count(*) from tasks t where t.status in ('OPEN', 'IN_PROGRESS') and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY)');
  if v_cap_e is not null then
    delete from outreach_candidates oc using (
        select x.id, x.channel, row_number() over (partition by (x.channel = 'EMAIL') order by (x.warm_route is not null) desc,
               array_position(array['BRANDS', 'WEDDINGS', 'TRAVEL_PRIVATE', 'SPORTS_PRIVATE', 'PARTNERSHIPS', 'CORPORATE', 'EGYPT_EVENTS'], x.lane) nulls last, x.created_at) rn
          from outreach_candidates x where x.run_date = current_date and x.dry_run = p_dry_run and x.status = 'PLANNED') z
     where oc.id = z.id
       and ((z.channel = 'EMAIL' and z.rn > greatest(0, v_cap_e - v_open_e)) or (z.channel <> 'EMAIL' and z.rn > greatest(0, v_cap_s - v_open_s)));
  end if;
  select jsonb_build_object(
    'run_date', current_date, 'dry_run', p_dry_run, 'target', v_target,
    'sweep', v_sweep - 'items', 'reserve_caps', jsonb_build_object('email', v_cap_e, 'email_open', v_open_e, 'social', v_cap_s, 'social_open', v_open_s),$a$);
  if strpos(n, 'v_sweep := cold_route_sweep(true);') = 0 or strpos(n, 'pick0 as materialized') = 0 or strpos(n, 'p.fallback_ok and p.rt->>''state'' = ''EXHAUSTED'' and p.rt->>''fallback'' = ''LINKEDIN''') = 0
     or strpos(n, '''VERIFIED_INBOX'', ''VERIFIED_GENERAL'') then (p.rt->>''inbox_id'')::uuid') = 0 or strpos(n, 'and i.email_tier = 2') = 0
     or strpos(n, 'company_email_state(t.company_id)->>''state'' in (''VERIFIED'', ''VERIFIED_INBOX'', ''VERIFIED_GENERAL'')') = 0
     or strpos(n, 'v_cap_e - v_open_e') = 0 or strpos(n, 'v_cap_e int;') = 0 or strpos(n, '|ADAM --|SEND APPROVED DRAFT|') = 0 or strpos(n, '''VERIFIED_INBOX'', ''VERIFIED_GENERAL'') then ''this person''') = 0 then
    raise exception 'planner patch incomplete'; end if;
  execute n;

  -- Outreach desk: a verified general inbox supersedes a LinkedIn draft; a pending provider lookup does not block one.
  d := pg_get_functiondef('public.outreach_desk()'::regprocedure);
  n := replace(d, $a$coalesce(t.er_route->>'state', '') <> 'EXHAUSTED' then$a$, $a$coalesce(t.er_route->>'state', '') not in ('EXHAUSTED', 'FINDER_PENDING') then$a$);
  n := replace(n, $a$            when 'VERIFIED_INBOX' then 'Email first: a verified department inbox exists, so an email replaces this message in tonight''s plan'$a$,
                  $a$            when 'VERIFIED_INBOX' then 'Email first: a verified department inbox exists, so an email replaces this message in tonight''s plan'
            when 'VERIFIED_GENERAL' then 'Email first: a verified general inbox exists (for their attention), so an email replaces this message in tonight''s plan'$a$);
  if strpos(n, 'not in (''EXHAUSTED'', ''FINDER_PENDING'')') = 0 or strpos(n, 'when ''VERIFIED_GENERAL'' then') = 0 then raise exception 'desk patch incomplete'; end if;
  execute n;
  -- The quality gate accepts the "For the attention of <name>, <position>" line that opens an inbox-route email.
  d := pg_get_functiondef('public.outreach_quality'::regproc);
  n := replace(d, $a$if b !~ '^(Hi [^,\n]+,|Hello,)' then$a$, $a$if b !~ '^(For the attention of [^\n]+\n+)?(Hi [^,\n]+,|Hello,)' then$a$);
  if n = d then raise exception 'outreach_quality pattern not found'; end if;
  execute n;
end $patch$;


-- ---------------------------------------------------------------- 6. email-first health
-- Per Director: decision makers confirmed -> emails found -> valid verified -> in Needs Review; email-ready reserve.
create or replace function public.director_channel_health(p_desk jsonb default null)
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  with p as materialized (
    select pr.*, exists (select 1 from contacts k where k.id = pr.contact_id and coalesce(btrim(k.email), '') <> '') dm_email,
           not exists (select 1 from interactions i where i.company_id = pr.company_id and i.direction = 'OUTBOUND' and i.channel <> 'WEBSITE')
           and not exists (select 1 from outbound_emails ob where ob.company_id = pr.company_id and ob.status = 'SENT') untouched
      from prospect_routes() pr),
  r as (select p.agent k, p.* from p union all select 'PARTNERSHIPS', p.* from p where p.partnership),
  d as (select x->>'director' director, (x->>'company_id')::uuid company_id, x->>'channel' channel, x->'fallback' fb
          from jsonb_array_elements(coalesce(p_desk, outreach_desk())->'needs_review') x),
  dk as (select director k, count(*) n, count(*) filter (where channel = 'EMAIL') e, count(*) filter (where fb is not null and fb <> 'null'::jsonb) f from d group by 1
         union all
         select 'PARTNERSHIPS', count(*), count(*) filter (where d.channel = 'EMAIL'), count(*) filter (where d.fb is not null and d.fb <> 'null'::jsonb)
           from d join companies c on c.id = d.company_id where c.partnership_model is not null),
  a as (
    select r.k, count(*) qualified, count(*) filter (where r.has_dm) with_dm,
           count(*) filter (where r.has_dm and (r.state in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'NEEDS_VERIFICATION') or r.dm_email)) emails_found,
           count(*) filter (where r.state in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL')) verified,
           count(*) filter (where r.state = 'VERIFIED') verified_person, count(*) filter (where r.state = 'VERIFIED_INBOX') verified_inbox,
           count(*) filter (where r.state = 'VERIFIED_GENERAL') verified_general,
           count(*) filter (where r.cold and r.untouched and r.state in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL')) email_ready,
           count(*) filter (where r.state = 'NEEDS_VERIFICATION') needs_verification, count(*) filter (where r.state = 'FINDER_PENDING') finder_pending,
           count(*) filter (where r.state = 'RESEARCH_PENDING') email_gap,
           count(*) filter (where r.state = 'EXHAUSTED' and r.fallback = 'LINKEDIN') linkedin_fallback,
           count(*) filter (where r.state = 'EXHAUSTED' and r.fallback = 'INSTAGRAM') instagram_fallback,
           count(*) filter (where r.state = 'EXHAUSTED' and r.fallback is null) no_route, count(*) filter (where not r.has_dm) no_person
      from r group by r.k)
  select coalesce(jsonb_object_agg(a.k, jsonb_build_object(
      'qualified', a.qualified, 'with_dm', a.with_dm, 'emails_found', a.emails_found, 'verified', a.verified,
      'verified_person', a.verified_person, 'verified_inbox', a.verified_inbox, 'verified_general', a.verified_general, 'email_ready', a.email_ready,
      'needs_verification', a.needs_verification, 'finder_pending', a.finder_pending, 'email_gap', a.email_gap,
      'linkedin_fallback', a.linkedin_fallback, 'instagram_fallback', a.instagram_fallback, 'no_route', a.no_route, 'no_person', a.no_person,
      'needs_review', coalesce((select sum(n) from dk where dk.k = a.k), 0),
      'needs_review_email', coalesce((select sum(e) from dk where dk.k = a.k), 0),
      'needs_review_fallback', coalesce((select sum(f) from dk where dk.k = a.k), 0),
      'coverage_pct', round(100.0 * a.verified / nullif(a.with_dm, 0)),
      'bottleneck', case when a.with_dm >= coalesce((select (value->>'coverage_alert_min_dm')::int from system_config where key = 'email_first'), 8)
                          and coalesce(round(100.0 * a.verified / nullif(a.with_dm, 0)), 0) < coalesce((select (value->>'coverage_alert_pct')::int from system_config where key = 'email_first'), 30)
                         then case when a.emails_found - a.verified >= greatest(a.with_dm - a.emails_found, 1) then 'VERIFICATION' else 'CONTACT' end end)), '{}'::jsonb)
  from a
$function$;

-- The CEO-facing acquisition split. EMAIL READY (valid verified + verified general, cold and never contacted) is the KPI.
create or replace function public.acquisition_health()
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  with cfg as (select coalesce((select value from system_config where key = 'email_reserve'), '{}'::jsonb) v),
  p as materialized (
    select pr.*, not exists (select 1 from interactions i where i.company_id = pr.company_id and i.direction = 'OUTBOUND' and i.channel <> 'WEBSITE')
                 and not exists (select 1 from outbound_emails ob where ob.company_id = pr.company_id and ob.status = 'SENT') untouched
      from prospect_routes() pr),
  w as materialized (select p.*, case when p.cold and p.untouched then company_warm_route(p.company_id) end warm from p),
  agg as (
    select coalesce(w.agent, 'OTHER') agent,
           count(*) filter (where w.cold and w.untouched and w.warm is null and w.state in ('VERIFIED', 'VERIFIED_INBOX')) valid_verified,
           count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'VERIFIED_INBOX') via_department,
           count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'VERIFIED_GENERAL') verified_general,
           count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'EXHAUSTED' and w.fallback = 'LINKEDIN') linkedin_fallback,
           count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'EXHAUSTED' and w.fallback = 'INSTAGRAM') instagram_fallback,
           count(*) filter (where w.cold and w.untouched and w.warm is not null) warm,
           count(*) filter (where not w.cold) existing_relationship,
           count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'NEEDS_VERIFICATION') needs_verification,
           count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'FINDER_PENDING') finder_pending,
           count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'RESEARCH_PENDING') research_pending,
           count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'NO_PERSON') no_person,
           count(*) filter (where w.cold and w.untouched and w.warm is null and w.state = 'EXHAUSTED' and w.fallback is null) no_route
      from w group by 1),
  tot as (select sum(valid_verified)::int valid_verified, sum(via_department)::int via_department, sum(verified_general)::int verified_general,
                 sum(linkedin_fallback)::int linkedin_fallback, sum(instagram_fallback)::int instagram_fallback, sum(warm)::int warm,
                 sum(existing_relationship)::int existing_relationship, sum(needs_verification)::int needs_verification, sum(finder_pending)::int finder_pending,
                 sum(research_pending)::int research_pending, sum(no_person)::int no_person, sum(no_route)::int no_route from agg)
  select jsonb_build_object(
    'primary_kpi', 'EMAIL_READY',
    'email_ready', tot.valid_verified + tot.verified_general,
    'valid_verified_email_ready', tot.valid_verified, 'of_which_department_inbox', tot.via_department,
    'verified_general_email_ready', tot.verified_general,
    'linkedin_fallback', tot.linkedin_fallback, 'instagram_fallback', tot.instagram_fallback,
    'warm', tot.warm, 'existing_relationship', tot.existing_relationship,
    'pipeline', jsonb_build_object('needs_verification', tot.needs_verification, 'finder_pending', tot.finder_pending, 'research_pending', tot.research_pending,
                                   'no_person', tot.no_person, 'no_route', tot.no_route),
    'reserve', jsonb_build_object('email_ready', tot.valid_verified + tot.verified_general, 'target', (select v->'email_ready_target' from cfg),
                                  'status', case when tot.valid_verified + tot.verified_general < coalesce(((select v from cfg)->'email_ready_target'->>0)::int, 100) then 'LOW'
                                                 when tot.valid_verified + tot.verified_general > coalesce(((select v from cfg)->'email_ready_target'->>1)::int, 150) then 'HIGH' else 'OK' end),
    'by_director', (select jsonb_object_agg(agent, to_jsonb(agg) - 'agent' || jsonb_build_object('email_ready', valid_verified + verified_general)) from agg),
    'note', 'Counts qualified companies never contacted. Warm and existing relationships are counted once, outside the cold routes.')
  from tot
$function$;

create or replace function public.queue_health()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_h interval := interval '3 days'; r jsonb; e int; eb int; l int; f int; w int; vf int;
        v_res jsonb := coalesce((select value from system_config where key = 'email_reserve'), '{}'::jsonb); v_cap int; v_scap int;
begin
  v_cap := coalesce((v_res->>'max_unsent_email_drafts')::int, 30); v_scap := coalesce((v_res->>'max_open_social_drafts')::int, 20);
  -- emails ready for Adam: approvals with a sendable recipient and a draft that passes the quality gate, EMAIL READY drafts, unsent Gmail drafts
  select count(*) filter (where q <> 'BLOCKED'), count(*) filter (where q = 'BLOCKED') into e, eb from (
    select coalesce(outreach_quality(d->>'subject', d->>'body')->>'status', 'BLOCKED') q
      from tasks t cross join lateral (select hq_current_draft(t.opportunity_id) d) x
     where t.status = 'OPEN' and t.task_type = 'SALES_OUTREACH_APPROVAL'
       and outbound_recipient_block_reason((select contact_id from opportunities where id = t.opportunity_id)) is null
       and not exists (select 1 from outbound_emails ob where ob.opportunity_id = t.opportunity_id and ob.status in ('QUEUED', 'CLAIMED', 'DRAFTED', 'SENT'))) s;
  e := e + (select count(*) from tasks t where t.status = 'OPEN' and t.title like 'EMAIL READY%' and coalesce(t.due_at, now()) <= now() + v_h)
         + (select count(*) from outbound_emails where status = 'DRAFTED');
  select count(*) into l from tasks t where t.status = 'OPEN' and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY)'
     and coalesce(t.due_at, now()) <= now() + v_h;
  select count(*) into f from tasks t where t.status = 'OPEN' and t.task_type = 'OUTREACH_FOLLOW_UP' and coalesce(t.due_at, now()) <= now() + v_h;
  select count(*) into w from tasks t where t.status = 'OPEN' and coalesce(t.due_at, now()) <= now() + v_h
     and (t.title like 'RECONNECT%' or t.task_type in ('REPLY_ACTION', 'MEETING_ACTION') or t.title like 'ADAM -- PERSONAL%');
  select count(*) into vf from tasks t where t.status = 'OPEN' and t.title like 'VERIFY FIRST --%';
  r := jsonb_build_array(
    jsonb_build_object('key', 'email', 'label', 'Verified emails ready', 'per_day', 12, 'ready', e, 'target', v_cap, 'shortfall', greatest(v_cap - e, 0), 'primary', true),
    jsonb_build_object('key', 'follow_up', 'label', 'Follow-ups due', 'per_day', 3, 'ready', f, 'target', 9, 'shortfall', greatest(9 - f, 0)),
    jsonb_build_object('key', 'warm', 'label', 'Warm reconnects / replies', 'per_day', 2, 'ready', w, 'target', 6, 'shortfall', greatest(6 - w, 0)),
    jsonb_build_object('key', 'linkedin', 'label', 'LinkedIn / DM fallback', 'per_day', 3, 'ready', l, 'target', v_scap, 'shortfall', 0, 'fallback', true));
  return jsonb_build_object('lines', r, 'headline', 'EMAIL_READY', 'ready', e, 'target', v_cap,
    'rule', 'Email first: LinkedIn and Instagram are fallbacks, counted apart and never part of the headline. A shortfall is shown, never filled with weak prospects or unconfirmed people.',
    'acquisition', acquisition_health(),
    'verify_first', vf, 'email_blocked', eb,
    'universe', (select count(*) from companies where universe_status = 'QUALIFIED'),
    'universe_by_status', (select jsonb_object_agg(universe_status, k) from (select universe_status, count(*) k from companies where universe_status is not null group by 1) s),
    'universe_target', '300–500 named accounts, built progressively');
end $function$;

-- ---------------------------------------------------------------- 7. Hunter daily funnel and reply attribution
create or replace function public.hunter_daily_funnel(p_days integer default 14)
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  with caps as (select hunter_plan_caps() v),
  dd as (select generate_series((now() at time zone 'Africa/Cairo')::date - (greatest(least(coalesce(p_days, 14), 60), 1) - 1),
                                (now() at time zone 'Africa/Cairo')::date, interval '1 day')::date as day),
  fl as (select (attempted_at at time zone 'Africa/Cairo')::date as day, count(*) filter (where outcome <> 'ERROR') attempts,
                count(*) filter (where coalesce(email, '') <> '') found, count(*) filter (where outcome = 'VERIFIED') found_valid
           from email_finder_log group by 1),
  vr as (select v.id, (coalesce(v.checked_at, v.created_at) at time zone 'Africa/Cairo')::date as day, lower(v.email) email, v.provider_status,
                coalesce(v.checked_at, v.created_at) at_ts
           from contact_email_verifications v where v.source_workflow like '24 %' and v.provider_status is not null),
  conv as (
    select vr.day, vr.email, vr.provider_status,
           (select oc.id from outreach_candidates oc left join contacts k on k.id = coalesce(oc.route_contact_id, oc.contact_id)
             where not oc.dry_run and oc.channel = 'EMAIL' and oc.draft is not null and lower(btrim(k.email)) = vr.email and oc.created_at >= vr.at_ts
             order by oc.created_at limit 1) cand
      from vr where vr.provider_status = 'valid'),
  conv2 as (
    select conv.*, ob.company_id, ob.sent_at
      from conv left join lateral (select o.company_id, o.sent_at from outbound_emails o where o.candidate_id = conv.cand and o.status = 'SENT' order by o.sent_at limit 1) ob on true),
  conv3 as (
    select conv2.*,
           exists (select 1 from interactions i where i.company_id = conv2.company_id and i.direction = 'INBOUND' and i.channel not in ('WEBSITE', 'MEETING') and i.occurred_at >= conv2.sent_at) replied,
           exists (select 1 from interactions i where i.company_id = conv2.company_id and i.channel = 'MEETING' and i.occurred_at >= conv2.sent_at)
             or exists (select 1 from opportunities o where o.company_id = conv2.company_id and o.status in ('MEETING', 'PROPOSAL', 'PROPOSAL_SENT', 'NEGOTIATION', 'WON') and o.updated_at >= conv2.sent_at) meeting
      from conv2),
  rw as (
    select dd.day, coalesce(fl.attempts, 0) finder_attempts, coalesce(fl.found, 0) finder_found, coalesce(fl.found_valid, 0) finder_valid,
           (select count(*) from vr where vr.day = dd.day) verifications,
           (select count(*) from vr where vr.day = dd.day and vr.provider_status = 'valid') valid,
           (select count(*) from vr where vr.day = dd.day and vr.provider_status in ('accept_all', 'unknown', 'webmail')) risky,
           (select count(*) from vr where vr.day = dd.day and vr.provider_status in ('invalid', 'disposable')) invalid,
           (select count(*) from conv3 where conv3.day = dd.day and conv3.cand is not null) valid_to_draft,
           (select count(*) from conv3 where conv3.day = dd.day and conv3.sent_at is not null) draft_to_send,
           (select count(*) from conv3 where conv3.day = dd.day and conv3.replied) send_to_reply,
           (select count(*) from conv3 where conv3.day = dd.day and conv3.replied and conv3.meeting) reply_to_meeting
      from dd left join fl on fl.day = dd.day),
  r2 as (select rw.*, round(rw.finder_found * 1.0 + rw.verifications * 0.5, 1) credits from rw),
  last7 as (select coalesce(sum(credits), 0) c7 from r2 where day > (now() at time zone 'Africa/Cairo')::date - 7)
  select jsonb_build_object(
    'plan', (select v->>'plan' from caps), 'tier', (select v->>'tier' from caps),
    'caps', jsonb_build_object('verify_per_day', (select v->'verify_per_day' from caps), 'finder_per_day', (select v->'finder_per_day' from caps)),
    'credits_used_this_cycle', (select v->'credits_used' from caps), 'reset_date', (select v->>'reset_date' from caps),
    'days', coalesce((select jsonb_agg(to_jsonb(r2) order by r2.day desc) from r2), '[]'::jsonb),
    'totals', (select jsonb_build_object('finder_attempts', sum(finder_attempts), 'finder_found', sum(finder_found), 'verifications', sum(verifications),
                                         'valid', sum(valid), 'risky', sum(risky), 'invalid', sum(invalid), 'credits', sum(credits),
                                         'valid_to_draft', sum(valid_to_draft), 'draft_to_send', sum(draft_to_send), 'send_to_reply', sum(send_to_reply),
                                         'reply_to_meeting', sum(reply_to_meeting)) from r2),
    'monthly_projection', jsonb_build_object(
       'at_last_7_days', round((select c7 from last7) / 7.0 * 30),
       'at_starter_caps', round((coalesce(((select value from system_config where key = 'email_verification')->'plan_caps'->'STARTER'->>'verify_per_day')::numeric, 40) * 0.5
                                + coalesce(((select value from system_config where key = 'email_verification')->'plan_caps'->'STARTER'->>'finder_per_day')::numeric, 25)) * 30),
       'starter_credits', coalesce(((select value from system_config where key = 'email_verification')->'plan_caps'->'STARTER'->>'monthly_credits')::int, 2000),
       'starter_budget', coalesce(((select value from system_config where key = 'email_verification')->'plan_caps'->'STARTER'->>'monthly_budget_credits')::int, 1500)),
    'note', 'Credits: one per Email Finder address found, half per verification. VALID -> draft -> send -> reply -> meeting follows each verified address forward.')
$function$;

create or replace function public.outreach_attribution(p_weeks integer default 8)
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  with s as (
    select i.id, i.company_id, case when i.channel = 'EMAIL' then 'EMAIL' when i.channel = 'LINKEDIN' then 'LINKEDIN' else i.channel end channel,
           i.occurred_at, g.gmail_thread_id
      from interactions i left join gmail_sync_ledger g on g.gmail_message_id = i.external_message_id
     where i.direction = 'OUTBOUND' and i.channel not in ('WEBSITE', 'MEETING') and i.company_id is not null),
  rp as (
    select r.id, r.company_id, r.occurred_at, coalesce(r.summary, '') summary, g.gmail_thread_id
      from interactions r left join gmail_sync_ledger g on g.gmail_message_id = r.external_message_id
     where r.direction = 'INBOUND' and r.channel not in ('WEBSITE', 'MEETING') and r.company_id is not null),
  -- each reply belongs to the message it answers: the same Gmail thread first, else the latest earlier message to that company (120 days) ...
  a as (
    select rp.*, m.channel from rp cross join lateral (
      select s.channel from s where s.company_id = rp.company_id and s.occurred_at <= rp.occurred_at and s.occurred_at > rp.occurred_at - interval '120 days'
       order by (rp.gmail_thread_id is not null and s.gmail_thread_id = rp.gmail_thread_id) desc, s.occurred_at desc limit 1) m),
  -- ... and then to the first message of that sequence on that channel: the originating outbound
  o as (
    select a.*, (select s.id from s where s.company_id = a.company_id and s.channel = a.channel and s.occurred_at <= a.occurred_at
                   and s.occurred_at > a.occurred_at - interval '120 days' order by s.occurred_at limit 1) origin_id
      from a),
  ft as (
    select s.*, date_trunc('week', s.occurred_at at time zone 'Africa/Cairo')::date cohort,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent
      from s join companies c on c.id = s.company_id
     where s.occurred_at > now() - make_interval(weeks => greatest(least(coalesce(p_weeks, 8), 52), 1))
       and not exists (select 1 from s e where e.company_id = s.company_id and e.channel = s.channel and e.occurred_at < s.occurred_at
                        and e.occurred_at > s.occurred_at - interval '120 days')),
  res as (
    select ft.*,
           exists (select 1 from o where o.origin_id = ft.id) replied,
           exists (select 1 from o where o.origin_id = ft.id and o.summary ~ '^(POSITIVE|MEETING_REQUEST|NEEDS_INFO|REFERRAL)') positive,
           exists (select 1 from interactions mt where mt.company_id = ft.company_id and mt.channel = 'MEETING' and mt.occurred_at >= ft.occurred_at)
             or exists (select 1 from opportunities op where op.company_id = ft.company_id and op.status in ('MEETING', 'PROPOSAL', 'PROPOSAL_SENT', 'NEGOTIATION', 'WON')
                         and op.updated_at >= ft.occurred_at) meeting
      from ft)
  select jsonb_build_object(
    'weeks', greatest(least(coalesce(p_weeks, 8), 52), 1),
    'by_channel', coalesce((select jsonb_object_agg(channel, j) from (
        select channel, jsonb_build_object('sent', count(*), 'replied', count(*) filter (where replied), 'positive', count(*) filter (where positive),
               'meetings', count(*) filter (where meeting), 'reply_rate_pct', round(100.0 * count(*) filter (where replied) / nullif(count(*), 0)),
               'positive_rate_pct', round(100.0 * count(*) filter (where positive) / nullif(count(*), 0))) j
          from res group by channel) x), '{}'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('cohort', cohort, 'director', agent, 'channel', channel, 'sent', n, 'replied', rr, 'positive', pp, 'meetings', mm)
                                       order by cohort desc, agent, channel)
                        from (select cohort, coalesce(agent, 'OTHER') agent, channel, count(*) n, count(*) filter (where replied) rr,
                                     count(*) filter (where positive) pp, count(*) filter (where meeting) mm from res group by 1, 2, 3) x), '[]'::jsonb),
    'unattributed_replies', (select count(*) from rp where not exists (select 1 from a where a.id = rp.id)),
    'method', 'Each reply is attributed to the message it answers (same Gmail thread first, otherwise the latest earlier message to that company within 120 days), then to the first message of that sequence. Cohort = the Cairo week that first message was sent. Follow-ups never count as new sends.')
$function$;

-- ---------------------------------------------------------------- 8. HQ Advisor and weekly review
do $patch$
declare d text; n text; s int; e int; v_end text;
begin
  d := pg_get_functiondef('public.hq_advisor()'::regprocedure);
  n := d;
  n := replace(n, $a$v_credits numeric; v_finder_ok int; v_finder_n int; v_action text;$a$,
                  $a$v_credits numeric; v_finder_ok int; v_finder_n int; v_action text;
        v_er int; v_low text; v_res jsonb := coalesce((select value from system_config where key = 'email_reserve'), '{}'::jsonb);$a$);
  n := replace(n, $a$  v_health := director_channel_health(v_desk);$a$,
                  $a$  v_health := director_channel_health(v_desk);
  v_er := coalesce((select sum((value->>'email_ready')::int) from jsonb_each(v_health) where key <> 'PARTNERSHIPS'), 0);$a$);
  n := replace(n, $a$  v_brief := v_brief || jsonb_build_object('text', v_total || ' new outreach'$a$,
                  $a$  v_brief := v_brief || jsonb_build_object('text', 'Email ready: ' || v_er || ' verified prospect' || case when v_er = 1 then '' else 's' end
             || ' in reserve (target ' || coalesce(v_res->'email_ready_target'->>0, '100') || '–' || coalesce(v_res->'email_ready_target'->>1, '150') || ')', 'tab', 'agents');
  v_brief := v_brief || jsonb_build_object('text', v_total || ' new outreach'$a$);
  -- the coverage observation becomes the per-Director funnel with a CONTACT / VERIFICATION BOTTLENECK verdict
  s := strpos(n, $a$  select key, (value->>'with_dm')::int dm, (value->>'verified')::int ver, coalesce((value->>'coverage_pct')::int, 0) cov,$a$);
  v_end := $a$'action', 'No change.', 'tab', 'agents');
  end if;$a$;
  e := strpos(n, v_end);
  if s = 0 or e = 0 or e < s then raise exception 'advisor coverage block not found'; end if;
  n := left(n, s - 1) || $a$  select key, (value->>'with_dm')::int dm, coalesce((value->>'emails_found')::int, 0) found, (value->>'verified')::int ver,
         coalesce((value->>'coverage_pct')::int, 0) cov, (value->>'email_gap')::int gap, (value->>'needs_verification')::int nv,
         (value->>'linkedin_fallback')::int li, coalesce((value->>'needs_review_email')::int, 0) nr, coalesce((value->>'finder_pending')::int, 0) fp,
         coalesce(value->>'bottleneck', 'CONTACT') side
    into v_cov
    from jsonb_each(v_health)
   where key <> 'PARTNERSHIPS' and value->>'bottleneck' is not null
   order by array_position(v_prio, key) nulls last, (value->>'with_dm')::int desc limit 1;
  select string_agg(advisor_agent_label(key) || ' ' || coalesce(value->>'coverage_pct', '0') || '%', ', ' order by array_position(v_prio, key) nulls last)
    into v_low from jsonb_each(v_health) where key <> 'PARTNERSHIPS' and value->>'bottleneck' is not null and key <> coalesce(v_cov.key, '');
  if v_cov.key is not null then
    v_obs := v_obs || jsonb_build_object('rank', 30, 'kind', 'BOTTLENECK', 'title', 'CONTACT / VERIFICATION BOTTLENECK', 'director', v_cov.key,
      'situation', advisor_agent_label(v_cov.key) || ': ' || v_cov.dm || ' decision makers confirmed → ' || v_cov.found || ' with an email found → '
                   || v_cov.ver || ' valid verified → ' || v_cov.nr || ' email' || case when v_cov.nr = 1 then '' else 's' end || ' in Needs Review ('
                   || v_cov.cov || '% verified coverage).',
      'meaning', case when v_cov.side = 'VERIFICATION'
                      then 'Verification bottleneck: ' || (v_cov.found - v_cov.ver) || ' addresses are found but not verified (' || v_cov.nv || ' queued for verification now). Discovery is not the limit.'
                      else 'Contact bottleneck: ' || greatest(v_cov.dm - v_cov.found, 0) || ' decision makers have no email found yet (' || v_cov.gap || ' still need email research'
                           || case when v_cov.fp > 0 then ', ' || v_cov.fp || ' wait for a provider lookup' else '' end || '). Discovery volume is not the limit.' end
                 || case when v_low is not null then ' Also below ' || coalesce(v_cfg->>'coverage_alert_pct', '30') || '%: ' || v_low || '.' else '' end
                 || case when v_credits is not null then ' Hunter ' || coalesce(v_hunter->>'plan', '') || ' had ' || round(v_credits)::int || ' credits left at '
                         || to_char((v_hunter->>'checked_at')::timestamptz at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ' (resets '
                         || coalesce(to_char((v_hunter->>'reset_date')::date, 'DD Mon'), 'monthly') || ').' else '' end,
      'action', case when v_cov.side = 'VERIFICATION'
                     then 'Verify the ' || advisor_agent_label(v_cov.key) || ' backlog before adding discovery'
                          || case when coalesce(v_hunter->>'plan', 'Free') ~* '^free' then ': on Hunter Free that is 8 checks a day; Starter lifts it to 40.' else '.' end
                     else 'Email Intelligence and the Email Finder work ' || advisor_agent_label(v_cov.key) || ' first. LinkedIn volume is not progress here.' end,
      'tab', 'agents');
  else
    v_obs := v_obs || jsonb_build_object('rank', 30, 'kind', 'BOTTLENECK', 'title', 'CONTACT / VERIFICATION BOTTLENECK',
      'situation', 'Verified-email coverage is ' || coalesce(v_cfg->>'coverage_alert_pct', '30') || '% or better for every Director with enough decision makers.',
      'meaning', 'Email stays the primary channel everywhere.', 'action', 'No change.', 'tab', 'agents');
  end if;$a$ || substr(n, e + length(v_end));
  n := replace(n, $a$    when v_cov.key is not null and v_cov.li > v_cov.gap + v_cov.nv and coalesce(v_hunter->>'plan', 'Free') = 'Free' then
      'Decide verification capacity (Hunter Starter, €49/month): the Email Finder is capped at 2 lookups a day on Free'$a$,
                  $a$    when v_cov.key is not null and coalesce(v_hunter->>'plan', 'Free') ~* '^free' then
      'Upgrade Hunter to Starter (€49/month, decided 11 Oct; keep auto-recharge off): on Free, verification is capped at 8 a day and the Email Finder at 2'$a$);
  n := replace(n, $a$    'coverage', (select jsonb_object_agg(key, jsonb_build_object('coverage_pct', value->'coverage_pct', 'with_dm', value->'with_dm', 'verified', value->'verified')) from jsonb_each(v_health)),$a$,
                  $a$    'coverage', (select jsonb_object_agg(key, jsonb_build_object('coverage_pct', value->'coverage_pct', 'with_dm', value->'with_dm', 'emails_found', value->'emails_found',
                                 'verified', value->'verified', 'verified_general', value->'verified_general', 'needs_review_email', value->'needs_review_email',
                                 'email_ready', value->'email_ready', 'linkedin_fallback', value->'linkedin_fallback', 'bottleneck', value->'bottleneck')) from jsonb_each(v_health)),
    'email_ready', v_er, 'email_ready_target', v_res->'email_ready_target',$a$);
  if strpos(n, 'v_er int;') = 0 or strpos(n, 'v_er := coalesce(') = 0 or strpos(n, '''Email ready: ''') = 0 or strpos(n, 'CONTACT / VERIFICATION BOTTLENECK') = 0
     or strpos(n, 'Upgrade Hunter to Starter') = 0 or strpos(n, '''email_ready'', v_er') = 0 then
    raise exception 'advisor patch incomplete'; end if;
  execute n;

  d := pg_get_functiondef('public.hq_weekly_review()'::regprocedure);
  n := replace(d, $a$  return v || jsonb_build_object(
    'weakest_bottleneck',$a$, $a$  return v || jsonb_build_object(
    'attribution', outreach_attribution(8), 'hunter_funnel', hunter_daily_funnel(7), 'acquisition', acquisition_health(),
    'weakest_bottleneck',$a$);
  if n = d then raise exception 'weekly review patch: pattern not found'; end if;
  execute n;
end $patch$;

-- ---------------------------------------------------------------- 9. privileges: internal helpers are service-role only
do $$
declare f text;
begin
  foreach f in array array['public.hunter_plan_caps()', 'public.email_on_company_domain(text, uuid)', 'public.email_domain_matches(text, text)', 'public.general_route_eligible(uuid)',
                           'public.cold_route_sweep(boolean)', 'public.acquisition_health()', 'public.hunter_daily_funnel(integer)',
                           'public.outreach_attribution(integer)', 'public.contact_email_route(uuid)', 'public.company_email_state(uuid)',
                           'public.prospect_routes()', 'public.email_verification_queue(integer)', 'public.email_finder_queue(integer)',
                           'public.director_channel_health(jsonb)', 'public.queue_health()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
