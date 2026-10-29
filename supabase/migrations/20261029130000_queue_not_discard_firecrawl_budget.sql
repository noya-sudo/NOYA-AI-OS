-- Corrections from Adam, 29 Oct 2026 ("Go"), on top of 20261029110000 and 20261029120000.
-- 1. No lead cap means no lead cap. Nothing is capped or discarded: discovered, qualified, contact-ready, email-ready,
--    LinkedIn-ready or draft-ready. The writer's nightly capacity (about 30 drafts: workflow 18, three runs of 10) is a
--    processing throughput only: the planner plans that many by score, the rest stay in the pool for the next run, and anything
--    planned but not drafted carries over to the next night, first in line. Same for LinkedIn.
-- 2. Firecrawl (the connected account has 1,000 credits a month, about 730 left on 29 Oct): 195 credits a week, cheap public web
--    search first, then Instagram PROFILE SEARCH (one call, many accounts), and a full PROFILE LOOKUP only for high-value qualified
--    targets whose public email matters. Advisor warns Adam below 300 and again below 100. Exhaustion never stops discovery
--    (web, official sites, Clay and Hunter carry on). No automatic upgrade or spend.

-- 1. Throughput, not a ceiling ----------------------------------------------------------------------------------------------
-- The send target (daily_touch_target, read by the reports) is unchanged; the planner plans to the writer's throughput.
update public.system_config
   set value = value || jsonb_build_object('nightly_draft_throughput', 30, 'email_topup_per_day', 10,
                 'previous_email_topup_per_day', value->'email_topup_per_day',
                 'note', 'Adam, 29 Oct 2026: about 30 a night is the writer''s throughput, not a cap. The rest stay queued by score; planned items carry over.'),
       updated_at = now()
 where key = 'planner_options';

do $patch$
declare src text := pg_get_functiondef('public.commercial_director_plan(boolean, integer, boolean)'::regprocedure);
  a0 text := $a$v_target int := coalesce(p_target, ((select value from system_config where key = 'daily_touch_target')->>'target')::int, 20);$a$;
  b0 text := $a$v_target int := coalesce(p_target, ((select value from system_config where key = 'planner_options')->>'nightly_draft_throughput')::int,
                                   ((select value from system_config where key = 'daily_touch_target')->>'target')::int, 20);$a$;
  -- carry-over: earlier PLANNED candidates move to today (re-checked first), and today's fresh plan still runs
  a1 text := $a$  v_has_plan := exists (select 1 from outreach_candidates where run_date = current_date and dry_run = p_dry_run);$a$;
  b1 text := $a$  -- Carry-over (29 Oct): nothing planned is lost when the writer reaches its nightly throughput. Earlier PLANNED candidates move to
  -- today and are drafted first; one that is no longer eligible (no longer cold, held, or spend not allowed) is skipped with the reason.
  if not p_dry_run then
    update outreach_candidates oc set status = 'SKIPPED', hold_reason = 'NO_LONGER_ELIGIBLE', updated_at = now()
     where oc.status = 'PLANNED' and not oc.dry_run and oc.run_date < current_date
       and (relationship_state(oc.company_id) <> 'COLD' or not outreach_spend_ok(oc.company_id)
            or exists (select 1 from companies c where c.id = oc.company_id and coalesce(c.outreach_hold_until, '-infinity'::timestamptz) > now()));
    update outreach_candidates oc set run_date = current_date, updated_at = now()
     where oc.status = 'PLANNED' and not oc.dry_run and oc.run_date < current_date;
  end if;
  v_has_plan := exists (select 1 from outreach_candidates where run_date = current_date and dry_run = p_dry_run and created_at >= current_date);$a$;
  -- the writer takes items best first: carried-over, email, warm, then the opportunity's priority
  a2 text := $a$order by oc.lane, oc.created_at) filter (where oc.status = 'PLANNED')$a$;
  b2 text := $a$order by (oc.created_at < current_date) desc, (oc.channel = 'EMAIL') desc, (oc.warm_route is not null) desc,
                 coalesce((select o.priority from opportunities o where o.id = oc.opportunity_id), 0) desc, oc.created_at) filter (where oc.status = 'PLANNED')$a$;
begin
  if strpos(src, 'NO_LONGER_ELIGIBLE') > 0 then return; end if;
  if strpos(src, a0) = 0 or strpos(src, a1) = 0 or strpos(src, a2) = 0 then raise exception 'commercial_director_plan changed: anchors not found'; end if;
  execute replace(replace(replace(src, a0, b0), a1, b1), a2, b2);
end $patch$;

-- 2. Firecrawl: a weekly budget on the connected account, and its remaining credits ------------------------------------------
update public.system_config
   set value = jsonb_set(value, '{instagram}', (value->'instagram' - 'daily_credit_budget' - 'prospect_searches_per_day') || jsonb_build_object(
         'weekly_credit_budget', 195, 'prospect_searches_per_week', 2, 'lookups_per_week', 1,
         'order', jsonb_build_array('Public web search (free)', 'Instagram profile search: one call, many accounts', 'Full profile lookup: high-value qualified targets only'),
         'runs_in', 'Daily operating check, on the connected Firecrawl account (Adam, 29 Oct: decision A). The n8n credential is not changed.',
         'note', 'Adam, 29 Oct: 195 credits a week; never stop discovery when credits run out; no automatic upgrade or spend.'))
       || jsonb_build_object('firecrawl_account', jsonb_build_object('monthly_credits', 1000, 'remaining', 730, 'as_of', now(),
            'warn_below', jsonb_build_array(300, 100), 'source', 'Adam, 29 Oct 2026')),
       updated_at = now()
 where key = 'contact_order';

-- The connected account's credits: Adam's figure, less every call logged since.
create or replace function public.firecrawl_credits() returns jsonb language sql stable security definer set search_path = public as $$
  with a as (select value->'firecrawl_account' f from system_config where key = 'contact_order')
  select jsonb_build_object('monthly', (a.f->>'monthly_credits')::int, 'as_of', a.f->>'as_of',
           'remaining', (a.f->>'remaining')::int - coalesce((select sum(credits) from public_profile_calls where called_at > (a.f->>'as_of')::timestamptz), 0)::int,
           'warn', case when (a.f->>'remaining')::int - coalesce((select sum(credits) from public_profile_calls where called_at > (a.f->>'as_of')::timestamptz), 0) < 100 then 'BELOW_100'
                        when (a.f->>'remaining')::int - coalesce((select sum(credits) from public_profile_calls where called_at > (a.f->>'as_of')::timestamptz), 0) < 300 then 'BELOW_300' end)
    from a
$$;
revoke all on function public.firecrawl_credits() from public, anon, authenticated;

-- This week's Firecrawl allowance (Monday to Sunday, Cairo), never more than the account has left.
create or replace function public.instagram_budget() returns jsonb language sql stable security definer set search_path = public as $$
  with w as (select date_trunc('week', now() at time zone 'Africa/Cairo') at time zone 'Africa/Cairo' since),
  b as (select coalesce((select (value->'instagram'->>'weekly_credit_budget')::int from system_config where key = 'contact_order'), 195) budget,
               coalesce((select sum(credits) from public_profile_calls, w where called_at >= w.since), 0)::int used,
               coalesce((select count(*) from public_profile_calls, w where called_at >= w.since and purpose = 'LOOKUP' and credits > 0), 0)::int lookups,
               coalesce((select count(*) from public_profile_calls, w where called_at >= w.since and purpose = 'PROSPECT_SEARCH'), 0)::int searches,
               (firecrawl_credits()->>'remaining')::int account_left)
  select jsonb_build_object('period', 'week', 'budget', budget, 'used_this_week', used, 'lookups_this_week', lookups, 'searches_this_week', searches,
           'account_left', account_left, 'left', greatest(0, least(budget - used, account_left)))
    from b
$$;
revoke all on function public.instagram_budget() from public, anon, authenticated;

-- Full lookups: high-value qualified targets only, within the week's lookup allowance and credits.
create or replace function public.instagram_lookup_queue(p_limit int default 1) returns jsonb
language plpgsql stable security definer set search_path = public set statement_timeout = '55s' as $$
declare v_days int := coalesce((select (value->'instagram'->>'refresh_after_days')::int from system_config where key = 'contact_order'), 90);
        v_b jsonb := instagram_budget(); v_n int;
begin
  v_n := least(greatest(coalesce(p_limit, 1), 0), floor((v_b->>'left')::int / 65.0)::int,
               coalesce((select (value->'instagram'->>'lookups_per_week')::int from system_config where key = 'contact_order'), 1) - (v_b->>'lookups_this_week')::int);
  if v_n <= 0 then return jsonb_build_object('items', '[]'::jsonb, 'budget', v_b); end if;
  return jsonb_build_object('budget', v_b, 'items', coalesce((
    select jsonb_agg(jsonb_build_object('company_id', q.id, 'company', q.name, 'handle', q.h, 'url', 'https://www.instagram.com/' || q.h || '/') order by q.rk desc)
      from (select c.id, c.name, ig_handle(c.instagram) h,
                   coalesce((select max(coalesce(destination_egypt_score(o.egypt, 0, 0), o.priority, 0)) from opportunities o
                              where o.company_id = c.id and o.status not in ('WON', 'LOST', 'ARCHIVED')), 0) rk
              from companies c
             where c.universe_status = 'QUALIFIED' and ig_handle(c.instagram) ~ '^[a-z0-9._]{2,30}$'
               and coalesce(c.universe_reason, '') !~* '^\[WATCHLIST\]' and coalesce(c.source, '') !~* 'WATCHLIST'
               and coalesce(c.outreach_hold_until, '-infinity'::timestamptz) < now()
               and relationship_state(c.id) = 'COLD' and outreach_spend_ok(c.id)
               and not exists (select 1 from public_profiles p where p.handle = ig_handle(c.instagram) and p.observed_at > now() - make_interval(days => v_days))
               and coalesce(company_email_state(c.id)->>'state', 'NO_PERSON')
                   not in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL', 'NEEDS_VERIFICATION')
             order by 4 desc limit v_n) q
     where q.rk >= 70), '[]'::jsonb));
end $$;
revoke all on function public.instagram_lookup_queue(int) from public, anon, authenticated;

-- Profile searches: the week's search allowance, Adam's priority searches first, none repeated within 30 days.
create or replace function public.instagram_prospect_plan(p_max int default 1) returns jsonb
language sql stable security definer set search_path = public as $$
  with cfg as (select value v from system_config where key = 'contact_order'),
  allowed as (select greatest(0, least(coalesce(p_max, 1),
                coalesce(((select v from cfg)->'instagram'->>'prospect_searches_per_week')::int, 2) - (instagram_budget()->>'searches_this_week')::int,
                floor((instagram_budget()->>'left')::int / 65.0)::int)) k),
  bank as (select b.value q, b.ordinality o from cfg, jsonb_array_elements(cfg.v->'prospect_bank') with ordinality b)
  select coalesce(jsonb_agg(jsonb_build_object('q', x.q->>'q', 'lane', x.q->>'lane') order by x.last_run nulls first, x.o), '[]'::jsonb)
    from (select bank.*, (select max(called_at) from public_profile_calls c where c.purpose = 'PROSPECT_SEARCH' and c.query = bank.q->>'q') last_run
            from bank) x
   where (x.last_run is null or x.last_run < now() - interval '30 days')
   limit (select k from allowed);
$$;
revoke all on function public.instagram_prospect_plan(int) from public, anon, authenticated;

-- Adam's priority searches lead the bank (account → company → decision maker → email follows through websites, Clay, LinkedIn).
update public.system_config set value = value || jsonb_build_object('prospect_bank', jsonb_build_array(
    jsonb_build_object('q', 'private members club', 'lane', 'PARTNERSHIPS'), jsonb_build_object('q', 'founder club', 'lane', 'PARTNERSHIPS'),
    jsonb_build_object('q', 'luxury members club', 'lane', 'PARTNERSHIPS'), jsonb_build_object('q', 'travel club', 'lane', 'TRAVEL_PRIVATE'),
    jsonb_build_object('q', 'destination wedding planner', 'lane', 'WEDDINGS'), jsonb_build_object('q', 'luxury wedding planner', 'lane', 'WEDDINGS'),
    jsonb_build_object('q', 'event agency', 'lane', 'WEDDINGS'), jsonb_build_object('q', 'experiential agency', 'lane', 'BRANDS'),
    jsonb_build_object('q', 'luxury events', 'lane', 'WEDDINGS'), jsonb_build_object('q', 'creative agency', 'lane', 'BRANDS'),
    jsonb_build_object('q', 'PR agency', 'lane', 'BRANDS'), jsonb_build_object('q', 'beauty PR', 'lane', 'BRANDS'),
    jsonb_build_object('q', 'fashion PR', 'lane', 'BRANDS'), jsonb_build_object('q', 'brand experience', 'lane', 'BRANDS'),
    jsonb_build_object('q', 'creator agency', 'lane', 'BRANDS'), jsonb_build_object('q', 'influencer agency', 'lane', 'BRANDS'),
    jsonb_build_object('q', 'brand trips', 'lane', 'BRANDS'), jsonb_build_object('q', 'luxury lifestyle', 'lane', 'PARTNERSHIPS'),
    jsonb_build_object('q', 'private concierge', 'lane', 'TRAVEL_PRIVATE'),
    jsonb_build_object('q', 'corporate retreats', 'lane', 'CORPORATE'), jsonb_build_object('q', 'incentive travel', 'lane', 'CORPORATE'),
    jsonb_build_object('q', 'talent management', 'lane', 'SPORTS_PRIVATE'), jsonb_build_object('q', 'family office', 'lane', 'CORPORATE'))),
  updated_at = now()
 where key = 'contact_order';

-- The Advisor's decision slot warns first when the connected Firecrawl account runs low (300, then 100). Nothing is bought.
do $patch$
declare src text := pg_get_functiondef('public.advisor_proposal()'::regprocedure);
  a text := $a$begin
  if v is not null then$a$;
  b text := $a$        f jsonb := firecrawl_credits();
begin
  if f->>'warn' is not null then
    return jsonb_build_array(jsonb_build_object('kind', 'ATTENTION', 'title', 'ADAM TO DECIDE', 'slot', 6, 'tab', 'system',
      'situation', 'Firecrawl has about ' || (f->>'remaining') || ' of its ' || (f->>'monthly') || ' monthly credits left'
                   || case when f->>'warn' = 'BELOW_100' then ' (below 100).' else ' (below 300).' end,
      'meaning', 'Instagram searches and lookups slow down, then stop. Discovery carries on with web search, official sites, Clay and Hunter.',
      'action', 'Nothing is bought automatically. Keep the plan, or decide on more credits when the Instagram results justify it.'));
  end if;
  if v is not null then$a$;
begin
  if strpos(src, 'firecrawl_credits') > 0 then return; end if;
  if strpos(src, a) = 0 then raise exception 'advisor_proposal changed: anchor not found'; end if;
  execute replace(src, a, b);
end $patch$;

-- The pipeline also reports the Firecrawl allowance, for the daily check and the System page.
do $patch$
declare src text := pg_get_functiondef('public.commercial_pipeline()'::regprocedure);
  a text := $a$    'computed_at', now())$a$;
  b text := $a$    'firecrawl', firecrawl_credits() || jsonb_build_object('week', instagram_budget()),
    'computed_at', now())$a$;
begin
  if strpos(src, 'firecrawl_credits') > 0 then return; end if;
  if strpos(src, a) = 0 then raise exception 'commercial_pipeline changed: anchor not found'; end if;
  execute replace(src, a, b);
end $patch$;
