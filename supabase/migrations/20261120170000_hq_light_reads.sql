-- Applied to production as two migrations: hq_light_reads_part_a and hq_light_reads_part_b (20 Nov 2026).
-- FINAL MASTER DIRECTIVE (20 Nov 2026), part 2: lightweight server-side reads for the CEO screens.
-- hq_route_cache (one row per live opportunity: canonical route state, warm/primary flags), refreshed every 10 minutes;
-- ceo_actions (Adam's personal queue, curated by the daily check from Gmail truth); seasonal_windows (sourced windows only);
-- hq_today, hq_opportunities, hq_streams, hq_email_summary, hq_email_routes, hq_ceo_action. All admin-gated, small payloads.

-- Canonical contact-route states (the truth is preserved: a Clay or Instagram address is never called verified).
create or replace function public.route_canonical(p_raw text, p_source_type text, p_lead_type text, p_email_status text)
 returns text language sql immutable
as $$
  select case
    when p_email_status = 'INVALID' then 'INVALID'
    when p_raw = 'VERIFIED' then 'VALID_VERIFIED'
    when p_raw = 'PUBLIC_NAMED_EMAIL' and p_source_type in ('INSTAGRAM','INSTAGRAM_PROFILE') then 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM'
    when p_raw = 'PUBLIC_NAMED_EMAIL' and coalesce(p_lead_type, '') ~* 'agent' then 'AGENT_EMAIL'
    when p_raw = 'PUBLIC_NAMED_EMAIL' and coalesce(p_lead_type, '') ~* 'management' then 'MANAGEMENT_EMAIL'
    when p_raw = 'PUBLIC_NAMED_EMAIL' then 'PUBLIC_NAMED_EMAIL'
    when p_raw = 'CLAY_WORK_EMAIL' then 'CLAY_WORK_EMAIL'
    when p_raw in ('VERIFIED_INBOX','VERIFIED_GENERAL','OFFICIAL_PUBLISHED_INBOX') then 'OFFICIAL_PUBLISHED_INBOX'
    when p_email_status = 'RISKY' then 'ACCEPT_ALL_RISKY'
    when p_raw = 'NEEDS_VERIFICATION' then 'PUBLIC_UNVERIFIED'
    when p_raw = 'RESEARCH_PENDING' then 'UNKNOWN'
    when p_raw in ('EXHAUSTED','NO_PERSON') then 'NOT_FOUND'
    else 'UNKNOWN' end;
$$;
create or replace function public.route_label(p_canon text)
 returns text language sql immutable
as $$
  select case p_canon
    when 'VALID_VERIFIED' then 'Verified email'
    when 'PUBLIC_NAMED_EMAIL' then 'Public named email · published source'
    when 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM' then 'Public business email · Instagram · not SMTP-verified'
    when 'PUBLIC_PROFESSIONAL_EMAIL' then 'Public professional email · published source'
    when 'MANAGEMENT_EMAIL' then 'Management email · published'
    when 'AGENT_EMAIL' then 'Agent email · published'
    when 'CLAY_WORK_EMAIL' then 'Clay work email · not independently verified'
    when 'OFFICIAL_PUBLISHED_INBOX' then 'Official published inbox · for their attention'
    when 'ACCEPT_ALL_RISKY' then 'Accept-all domain · risky'
    when 'PUBLIC_UNVERIFIED' then 'Found, not verified · held'
    when 'INVALID' then 'Invalid'
    when 'NOT_FOUND' then 'No email found'
    else 'Unknown · research pending' end;
$$;

create table if not exists public.hq_route_cache (
  opportunity_id uuid primary key,
  company_id uuid, contact_id uuid, company text, person text, position text,
  status text, primary_stream text, market text, relationship_type text,
  raw_state text, canonical text, email text, label text, source_url text,
  usable boolean not null default false, warm boolean not null default false, sent boolean not null default false,
  rank_bucket int not null default 9, is_primary boolean not null default false,
  next_action text, next_action_due date, priority int, computed_at timestamptz not null default now()
);
alter table public.hq_route_cache enable row level security;
create index if not exists hq_route_cache_bucket_idx on public.hq_route_cache (rank_bucket, priority desc);

create or replace function public.hq_route_cache_refresh()
 returns int language plpgsql security definer set search_path to 'public'
as $$
declare n int;
begin
  if not pg_try_advisory_xact_lock(hashtext('hq_route_cache')) then return null; end if;
  drop table if exists _rc;
  create temp table _rc on commit drop as
  select o.id opportunity_id, o.company_id, o.contact_id, coalesce(c.name, o.company_name) company,
         nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), '') person, k.position,
         o.status, o.primary_stream, o.market, o.relationship_type,
         case when o.contact_id is null then jsonb_build_object('state', 'NO_PERSON') else contact_email_route(o.contact_id) end r,
         k.lead_type, k.email_status, k.email_source_type,
         exists (select 1 from outbound_emails e where e.opportunity_id = o.id and e.status = 'SENT') sent,
         (o.status in ('INTERESTED','CALL_REQUIRED','PROPOSAL','NEGOTIATION')
           or exists (select 1 from gmail_history_threads g where g.company_id = o.company_id and g.relevant and g.last_direction = 'INBOUND' and g.last_inbound_at > now() - interval '30 days')) warm,
         o.next_action, o.next_action_due, coalesce(o.priority, 0) priority
    from opportunities o left join companies c on c.id = o.company_id left join contacts k on k.id = o.contact_id
   where o.status not in ('ARCHIVED','LOST') and coalesce(k.do_not_contact, false) = false;
  delete from hq_route_cache;
  insert into hq_route_cache (opportunity_id, company_id, contact_id, company, person, position, status, primary_stream, market, relationship_type,
                              raw_state, canonical, email, label, source_url, usable, warm, sent, rank_bucket, is_primary, next_action, next_action_due, priority, computed_at)
  select x.opportunity_id, x.company_id, x.contact_id, x.company, x.person, x.position, x.status, x.primary_stream, x.market, x.relationship_type,
         x.r->>'state', x.canon, x.r->>'email', route_label(x.canon), x.r->>'source_url', x.usable, x.warm, x.sent, x.bucket,
         row_number() over (partition by coalesce(x.company_id, x.opportunity_id) order by x.bucket, x.priority desc, x.opportunity_id) = 1,
         x.next_action, x.next_action_due, x.priority, now()
    from (select r.*, route_canonical(r.r->>'state', r.email_source_type, r.lead_type, r.email_status) canon from _rc r) y
    cross join lateral (select y.*, y.canon in ('VALID_VERIFIED','PUBLIC_NAMED_EMAIL','PUBLIC_BUSINESS_EMAIL_INSTAGRAM','PUBLIC_PROFESSIONAL_EMAIL','MANAGEMENT_EMAIL','AGENT_EMAIL','CLAY_WORK_EMAIL','OFFICIAL_PUBLISHED_INBOX') usable,
                               case when y.warm then 1 when y.status = 'FOLLOW_UP' then 2
                                    when y.status = 'READY' and y.canon in ('VALID_VERIFIED','PUBLIC_NAMED_EMAIL','PUBLIC_BUSINESS_EMAIL_INSTAGRAM','PUBLIC_PROFESSIONAL_EMAIL','MANAGEMENT_EMAIL','AGENT_EMAIL','CLAY_WORK_EMAIL','OFFICIAL_PUBLISHED_INBOX') then 3
                                    when y.canon in ('VALID_VERIFIED','PUBLIC_NAMED_EMAIL','PUBLIC_PROFESSIONAL_EMAIL') then 4
                                    when y.canon in ('MANAGEMENT_EMAIL','AGENT_EMAIL') then 5
                                    when y.canon = 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM' then 6
                                    when y.canon = 'CLAY_WORK_EMAIL' then 7
                                    when y.canon = 'OFFICIAL_PUBLISHED_INBOX' then 8 else 9 end bucket) x;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.hq_route_cache_refresh() from public, anon, authenticated;
select cron.schedule('hq-route-cache', '3-59/10 * * * *', $$select public.hq_route_cache_refresh()$$)
 where not exists (select 1 from cron.job where jobname = 'hq-route-cache');

-- Adam's personal queue: curated each morning by the daily check from Gmail truth; Today shows it first.
create table if not exists public.ceo_actions (
  id uuid primary key default gen_random_uuid(),
  priority int not null default 50,
  kind text not null check (kind in ('CLIENT_ISSUE','REPLY','CALL','MEETING','PROPOSAL','DECIDE','FOLLOW_UP','SEND','FIX','NEXT_MOVE','COLD','FORM')),
  who text not null, what_happened text, why_it_matters text, what_to_do text not null,
  button_label text, button_url text, gmail_draft_id text,
  company_id uuid, opportunity_id uuid, related_company_ids uuid[] not null default '{}',
  status text not null default 'OPEN' check (status in ('OPEN','WAITING','DONE','DROPPED')),
  waiting_on text, due_on date, source text not null default 'daily_check',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), done_at timestamptz, done_note text
);
alter table public.ceo_actions enable row level security;

create or replace function public.hq_ceo_action(p_id uuid, p_action text, p_note text default null)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); v ceo_actions%rowtype;
begin
  if p_action not in ('DONE','DROPPED','OPEN','WAITING') then return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION'); end if;
  update ceo_actions set status = p_action, done_at = case when p_action in ('DONE','DROPPED') then now() end,
         done_note = coalesce(nullif(btrim(p_note), ''), done_note), updated_at = now()
   where id = p_id returning * into v;
  if v.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  insert into approval_audit (opportunity_id, action, result, actor, detail)
  values (v.opportunity_id, 'CEO_ACTION', p_action, v_admin, jsonb_build_object('ceo_action', v.id, 'who', v.who, 'note', p_note));
  return jsonb_build_object('ok', true, 'status', v.status);
end $$;
revoke all on function public.hq_ceo_action(uuid, text, text) from public, anon;
grant execute on function public.hq_ceo_action(uuid, text, text) to authenticated;

-- Seasonal commercial windows: only sourced or clearly labelled entries; surfaced only when actionable.
create table if not exists public.seasonal_windows (
  id uuid primary key default gen_random_uuid(),
  name text not null, market text, stream text references public.commercial_streams(code),
  starts_on date, ends_on date, lead_time_days int, commercial_angle text, accounts_hint text,
  source_url text, source_title text, published_at date, last_verified_at timestamptz,
  confidence text not null default 'ESTIMATE' check (confidence in ('VERIFIED','ESTIMATE','HYPOTHESIS')),
  status text not null default 'ACTIVE', created_at timestamptz not null default now(),
  unique (name, starts_on)
);
alter table public.seasonal_windows enable row level security;

create or replace function public.jlen(p jsonb) returns int language sql immutable as $$ select case when jsonb_typeof(p) = 'array' then jsonb_array_length(p) else 0 end $$;

-- TODAY: Adam's CEO screen in one small read.
create or replace function public.hq_today()
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); ceo jsonb; auth jsonb; reserve jsonb; health jsonb; wk jsonb; gate text;
        v_actions jsonb; v_more int; v_live jsonb; v_streams jsonb; v_blockers jsonb := '[]'::jsonb;
        warm_open int; gmail_drafts int; held_cold int; v_bottleneck text; v_overdue int;
begin
  select payload into ceo from hq_read_cache where key = 'ceo';
  select payload into health from hq_read_cache where key = 'health';
  select value into auth from system_config where key = 'email_authentication';
  select value into reserve from system_config where key = 'email_reserve';
  wk := coalesce(ceo->'funnel'->'week', '{}'::jsonb);
  gate := coalesce(auth->'last_live_check'->>'gate', 'UNKNOWN');

  with covered as (
    select unnest(array_append(related_company_ids, company_id)) cid from ceo_actions where status in ('OPEN','WAITING')),
  manual as (
    select a.priority p, jsonb_build_object('id', a.id, 'kind', a.kind, 'who', a.who, 'what_happened', a.what_happened, 'why', a.why_it_matters,
             'todo', a.what_to_do, 'button_label', a.button_label, 'button_url', a.button_url, 'status', a.status, 'due_on', a.due_on,
             'company_id', a.company_id, 'opportunity_id', a.opportunity_id, 'source', a.source) j
      from ceo_actions a where a.status = 'OPEN'),
  replies as (
    select distinct on (g.company_id) 15 p, jsonb_build_object('id', null, 'kind', 'REPLY', 'who', c.name,
             'what_happened', 'They wrote last on ' || to_char(g.last_inbound_at at time zone 'Africa/Cairo', 'DD Mon') || ': ' || left(coalesce(g.summary, g.subject, ''), 140),
             'why', 'A reply is waiting: the warmest move available', 'todo', 'Reply in Gmail', 'button_label', 'Open the thread',
             'button_url', 'https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#all/' || g.gmail_thread_id, 'status', 'OPEN', 'source', 'gmail',
             'company_id', g.company_id, 'opportunity_id', g.opportunity_id) j
      from gmail_history_threads g join companies c on c.id = g.company_id left join opportunities o on o.id = g.opportunity_id
     where g.relevant and g.last_direction = 'INBOUND' and g.last_inbound_at > now() - interval '14 days'
       and coalesce(g.hq_status, '') <> 'DISMISSED' and coalesce(c.relationship_status, '') <> 'supplier'
       and (o.id is null or o.status in ('INTERESTED','CALL_REQUIRED','PROPOSAL','NEGOTIATION','WON'))
       and not exists (select 1 from covered v where v.cid = g.company_id)
     order by g.company_id, g.last_inbound_at desc),
  allx as (select p, j from manual union all select p, j from replies)
  select coalesce(jsonb_agg(j order by p) filter (where rn <= 7), '[]'::jsonb), greatest(count(*) - 7, 0)
    into v_actions, v_more
    from (select j, p, row_number() over (order by p) rn from allx) s;

  select coalesce(jsonb_agg(to_jsonb(t) - 'rank' - 'updated_at' order by t.rank desc, t.priority desc nulls last, t.updated_at desc), '[]'::jsonb) into v_live
    from (select o.id, o.company_id, coalesce(c.name, o.company_name) company, o.primary_stream stream, st.label stream_label,
                 coalesce(nullif(o.angle, ''), nullif(o.opportunity_type, ''), o.project_type_canon) project,
                 hq_stage(o.status, coalesce(rc.usable, false), true, coalesce(o.next_action, '') <> '', c.universe_status = 'QUALIFIED') stage,
                 hq_stage_rank(hq_stage(o.status, coalesce(rc.usable, false), true, coalesce(o.next_action, '') <> '', c.universe_status = 'QUALIFIED')) rank,
                 coalesce(nullif(o.commercial_trigger, ''), nullif(o.reason, '')) why_now, o.relationship_type relationship,
                 greatest((select max(g.last_at) from gmail_history_threads g where g.company_id = o.company_id),
                          (select max(i.occurred_at) from interactions i where i.company_id = o.company_id)) last_interaction,
                 rc.person decision_maker, rc.position, rc.label route, o.next_action, o.next_action_due, o.priority, o.updated_at,
                 (select count(*) from studio_documents d where d.company_id = o.company_id) prepared_docs,
                 exists (select 1 from ceo_actions a where a.company_id = o.company_id and a.status = 'OPEN') action_open
            from opportunities o left join companies c on c.id = o.company_id
                 left join commercial_streams st on st.code = o.primary_stream left join hq_route_cache rc on rc.opportunity_id = o.id
           where o.status in ('INTERESTED','CALL_REQUIRED','PROPOSAL','NEGOTIATION','WON')
              or (o.status in ('FOLLOW_UP','CONTACTED') and o.relationship_type in ('WARM','PARTNER','CLIENT') and coalesce(o.next_action, '') <> '')
           order by rank desc, o.priority desc nulls last limit 8) t;

  select count(*) into warm_open from ceo_actions where status = 'OPEN' and kind in ('CALL','MEETING','REPLY','PROPOSAL','DECIDE','FOLLOW_UP','SEND','FORM');
  select count(*) into gmail_drafts from outbound_emails where status = 'DRAFTED' and sent_at is null;
  held_cold := jlen(reserve#>'{release_plan_18_nov,wave_1}') + jlen(reserve#>'{release_plan_18_nov,phase_2_queue_19_nov,merged_wave_2_order}');

  select coalesce(jsonb_agg(z.j order by z.score desc), '[]'::jsonb) into v_streams from (
    select jsonb_build_object('code', s.code, 'label', s.label, 'pillar', s.pillar,
             'live', count(*) filter (where o.status in ('INTERESTED','CALL_REQUIRED','PROPOSAL','NEGOTIATION')),
             'warm', count(*) filter (where rc.warm), 'ready', count(*) filter (where o.status = 'READY'),
             'season', (select w.name from seasonal_windows w where w.stream = s.code and w.status = 'ACTIVE' and w.starts_on between current_date and current_date + 60 order by w.starts_on limit 1)) j,
           3 * count(*) filter (where o.status in ('INTERESTED','CALL_REQUIRED','PROPOSAL','NEGOTIATION')) + 2 * count(*) filter (where rc.warm)
             + least(count(*) filter (where o.status = 'READY'), 5)
             + 3 * (select count(*) from seasonal_windows w where w.stream = s.code and w.status = 'ACTIVE' and w.starts_on between current_date and current_date + 60) score
      from commercial_streams s join opportunities o on o.primary_stream = s.code left join hq_route_cache rc on rc.opportunity_id = o.id
     where o.status not in ('ARCHIVED','LOST')
     group by s.code, s.label, s.pillar order by score desc limit 6) z where z.score > 0;

  if gate <> 'PASS' then
    v_blockers := v_blockers || jsonb_build_object('kind', 'DELIVERABILITY', 'text',
      'Cold email held: SPF and DKIM do not pass yet' || coalesce(' (checked ' || to_char((auth->'last_live_check'->>'at')::timestamptz at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ' Cairo)', ''),
      'action', 'Fix SPF and DKIM');
  end if;
  select count(*) into v_overdue from opportunities where status in ('PROPOSAL','NEGOTIATION') and next_action_due < current_date;
  if v_overdue > 0 then v_blockers := v_blockers || jsonb_build_object('kind', 'PROPOSAL_OVERDUE', 'text', v_overdue || ' proposal or negotiation past its next date'); end if;
  if jlen(health->'failures') > 0 then
    v_blockers := v_blockers || jsonb_build_object('kind', 'SYSTEM', 'text', jlen(health->'failures') || ' automation failure(s) recorded (More / Admin → System)');
  end if;

  v_bottleneck := case
    when warm_open >= 3 then 'Conversion: ' || warm_open || ' warm actions are prepared and waiting for you'
    when gate <> 'PASS' and held_cold + gmail_drafts > 0 then 'Deliverability: ' || (held_cold + gmail_drafts) || ' cold first touches held until SPF and DKIM pass'
    when jlen(v_live) = 0 then 'Pipeline: no live conversation yet'
    else 'No single bottleneck today' end;

  return jsonb_build_object(
    'generated_at', now(), 'gate', gate,
    'actions', v_actions, 'actions_more', v_more,
    'live', v_live, 'best', v_live->0,
    'week', jsonb_build_object('right_people_contacted', wk->'contacted', 'emails_sent', wk->'sent_email', 'replies', wk->'replies', 'positive', wk->'positive',
             'meetings', wk->'meetings', 'briefs', wk->'concepts', 'proposals', wk->'proposals', 'wins', wk->'won', 'revenue', coalesce(wk->'revenue', '[]'::jsonb),
             'as_of', ceo->>'generated_at'),
    'ready_unsent', jsonb_build_object('warm', warm_open, 'cold_gmail_drafts', gmail_drafts, 'cold_held', held_cold, 'total', warm_open + gmail_drafts + held_cold,
             'gated', gate <> 'PASS'),
    'bottleneck', v_bottleneck, 'streams', v_streams, 'blockers', v_blockers);
end $$;
revoke all on function public.hq_today() from public, anon;
grant execute on function public.hq_today() to authenticated;

-- OPPORTUNITIES: server-side filtered, ranked and paginated. Default: PROJECT READY and above.
create or replace function public.hq_opportunities(p_stage text default 'PROJECT_READY_PLUS', p_stream text default null, p_market text default null,
                                                   p_relationship text default null, p_q text default null, p_limit int default 30, p_offset int default 0)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  p_limit := least(greatest(coalesce(p_limit, 30), 1), 100); p_offset := greatest(coalesce(p_offset, 0), 0);
  p_q := nullif(btrim(coalesce(p_q, '')), '');
  with base as (
    select o.id, o.company_id, coalesce(c.name, o.company_name) company, o.status, o.primary_stream stream, st.label stream_label,
           coalesce(nullif(o.angle, ''), nullif(o.opportunity_type, ''), o.project_type_canon) project, o.market, o.relationship_type relationship,
           rc.person, rc.position, rc.label route, rc.canonical route_state, coalesce(rc.usable, false) usable,
           o.next_action, o.next_action_due, o.priority, o.blocker, coalesce(nullif(o.commercial_trigger, ''), nullif(o.reason, '')) why_now,
           hq_stage(o.status, coalesce(rc.usable, false), coalesce(nullif(o.angle, ''), nullif(o.opportunity_type, '')) is not null,
                    coalesce(o.next_action, '') <> '', c.universe_status = 'QUALIFIED') stage
      from opportunities o left join companies c on c.id = o.company_id left join commercial_streams st on st.code = o.primary_stream
           left join hq_route_cache rc on rc.opportunity_id = o.id
     where o.status not in ('ARCHIVED','LOST')
       and (p_stream is null or o.primary_stream = p_stream)
       and (p_market is null or o.market = p_market)
       and (p_relationship is null or o.relationship_type = p_relationship)
       and (p_q is null or coalesce(c.name, o.company_name, '') ilike '%' || p_q || '%' or coalesce(o.opportunity_type, '') ilike '%' || p_q || '%'
            or coalesce(rc.person, '') ilike '%' || p_q || '%')),
  f as (select b.*, hq_stage_rank(b.stage) rank,
               (hq_stage_rank(b.stage) >= hq_stage_rank('CONTACTED') and coalesce(b.next_action, '') = '') missing_next,
               coalesce(b.next_action_due < current_date, false) overdue
          from base b
         where case when p_stage = 'PROJECT_READY_PLUS' then hq_stage_rank(b.stage) >= hq_stage_rank('PROJECT_READY')
                    when p_stage = 'ALL' then true else b.stage = p_stage end)
  select jsonb_build_object(
    'rows', coalesce((select jsonb_agg(to_jsonb(r) order by r.rank desc, r.priority desc nulls last, r.next_action_due nulls last)
                        from (select * from f order by rank desc, priority desc nulls last, next_action_due nulls last limit p_limit offset p_offset) r), '[]'::jsonb),
    'total', (select count(*) from f),
    'counts', coalesce((select jsonb_object_agg(stage, n) from (select stage, count(*) n from base group by stage) x), '{}'::jsonb),
    'missing_next', (select count(*) from f where missing_next),
    'stage', p_stage, 'limit', p_limit, 'offset', p_offset) into v;
  return v;
end $$;
revoke all on function public.hq_opportunities(text, text, text, text, text, int, int) from public, anon;
grant execute on function public.hq_opportunities(text, text, text, text, text, int, int) to authenticated;

-- STREAMS: one card per canonical stream (outcomes from records only; revenue only as recorded).
create or replace function public.hq_streams()
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with so as (
    select o.primary_stream code, o.id, o.company_id, coalesce(c.name, o.company_name) company,
           coalesce(nullif(o.angle, ''), nullif(o.opportunity_type, ''), o.project_type_canon) project, o.status,
           o.next_action, o.next_action_due, coalesce(o.priority, 0) priority, coalesce(rc.usable, false) usable, coalesce(rc.warm, false) warm,
           hq_stage(o.status, coalesce(rc.usable, false), coalesce(nullif(o.angle, ''), nullif(o.opportunity_type, '')) is not null,
                    coalesce(o.next_action, '') <> '', c.universe_status = 'QUALIFIED') stage
      from opportunities o left join companies c on c.id = o.company_id left join hq_route_cache rc on rc.opportunity_id = o.id
     where o.status not in ('ARCHIVED','LOST') and o.primary_stream is not null)
  select jsonb_build_object('generated_at', now(), 'streams', coalesce(jsonb_agg(j order by srt), '[]'::jsonb)) into v from (
    select s.sort srt, jsonb_build_object(
      'code', s.code, 'label', s.label, 'pillar', s.pillar, 'mission', s.mission, 'director', s.director_key,
      'universe', (select count(*) from so where so.code = s.code),
      'conversations', (select count(*) from so where so.code = s.code and so.stage in ('ACTIVE_CONVERSATION','MEETING','BRIEF','PROPOSAL','NEGOTIATION')),
      'project_ready', (select count(*) from so where so.code = s.code and so.stage in ('PROJECT_READY','OUTREACH_READY')),
      'contacted', (select count(*) from so where so.code = s.code and so.stage in ('CONTACTED','FOLLOW_UP')),
      'meetings', (select count(*) from so where so.code = s.code and so.stage = 'MEETING'),
      'proposals', (select count(*) from so where so.code = s.code and so.stage in ('PROPOSAL','NEGOTIATION')),
      'wins', (select count(*) from so where so.code = s.code and so.stage = 'WON'),
      'replies_30d', (select count(distinct g.company_id) from gmail_history_threads g join so on so.company_id = g.company_id and so.code = s.code
                       where g.relevant and g.last_direction = 'INBOUND' and g.last_inbound_at > now() - interval '30 days'),
      'revenue', coalesce((select jsonb_agg(jsonb_build_object('currency', x.currency, 'amount', x.amt)) from (
                   select f.currency, sum(f.gross_amount) amt from hq_finance_records f join opportunities o2 on o2.id = f.opportunity_id
                    where o2.primary_stream = s.code and coalesce(f.status, '') not in ('DRAFT','CANCELLED') group by f.currency) x), '[]'::jsonb),
      'contact_gap', (select count(*) from so where so.code = s.code and so.status in ('NEW','RESEARCHING','READY') and not so.usable and so.priority >= 60),
      'top', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'company_id', t.company_id, 'company', t.company, 'project', t.project, 'stage', t.stage, 'next_action', t.next_action))
                 from (select * from so where so.code = s.code order by hq_stage_rank(so.stage) desc, so.priority desc limit 3) t), '[]'::jsonb),
      'next_action', (select so.next_action from so where so.code = s.code and coalesce(so.next_action, '') <> '' order by hq_stage_rank(so.stage) desc, so.priority desc limit 1),
      'season', (select jsonb_build_object('name', w.name, 'starts_on', w.starts_on, 'ends_on', w.ends_on, 'angle', w.commercial_angle, 'confidence', w.confidence, 'source_url', w.source_url)
                   from seasonal_windows w where w.stream = s.code and w.status = 'ACTIVE' and coalesce(w.ends_on, w.starts_on) >= current_date and w.starts_on <= current_date + 180
                   order by w.starts_on limit 1)) j
    from commercial_streams s where s.active) z;
  return v;
end $$;
revoke all on function public.hq_streams() from public, anon;
grant execute on function public.hq_streams() to authenticated;

-- EMAIL: summary counts and a ranked, paginated route list (never the whole contact universe).
create or replace function public.hq_email_summary()
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  select jsonb_build_object(
    'actionable', count(*) filter (where is_primary and usable and not sent and status <> 'LONG_TERM'),
    'replies', count(*) filter (where is_primary and warm),
    'follow_ups', count(*) filter (where is_primary and status = 'FOLLOW_UP'),
    'ready', count(*) filter (where is_primary and status = 'READY' and usable),
    'public_named', count(*) filter (where is_primary and canonical in ('VALID_VERIFIED','PUBLIC_NAMED_EMAIL','PUBLIC_PROFESSIONAL_EMAIL')),
    'management_agent', count(*) filter (where is_primary and canonical in ('MANAGEMENT_EMAIL','AGENT_EMAIL')),
    'instagram', count(*) filter (where is_primary and canonical = 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM'),
    'clay', count(*) filter (where is_primary and canonical = 'CLAY_WORK_EMAIL'),
    'official_inbox', count(*) filter (where is_primary and canonical = 'OFFICIAL_PUBLISHED_INBOX'),
    'needs_research', count(*) filter (where is_primary and not usable and status in ('NEW','RESEARCHING','READY') and coalesce(priority, 0) >= 60),
    'sent', (select count(*) from outbound_emails where status = 'SENT'),
    'computed_at', max(computed_at),
    'gate', (select value->'last_live_check'->>'gate' from system_config where key = 'email_authentication')) into v
  from hq_route_cache;
  return v;
end $$;
revoke all on function public.hq_email_summary() from public, anon;
grant execute on function public.hq_email_summary() to authenticated;

create or replace function public.hq_email_routes(p_filter text default 'ACTIONABLE', p_stream text default null, p_q text default null, p_limit int default 25, p_offset int default 0)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  p_limit := least(greatest(coalesce(p_limit, 25), 1), 50); p_offset := greatest(coalesce(p_offset, 0), 0);
  p_q := nullif(btrim(coalesce(p_q, '')), ''); p_filter := upper(coalesce(p_filter, 'ACTIONABLE'));
  with f as (
    select r.*, st.label stream_label from hq_route_cache r left join commercial_streams st on st.code = r.primary_stream
     where r.is_primary
       and case p_filter
             when 'ACTIONABLE' then r.usable and not r.sent and r.status <> 'LONG_TERM'
             when 'REPLIES' then r.warm
             when 'FOLLOW_UPS' then r.status = 'FOLLOW_UP'
             when 'READY' then r.status = 'READY' and r.usable
             when 'PUBLIC_NAMED' then r.canonical in ('VALID_VERIFIED','PUBLIC_NAMED_EMAIL','PUBLIC_PROFESSIONAL_EMAIL')
             when 'MANAGEMENT_AGENT' then r.canonical in ('MANAGEMENT_EMAIL','AGENT_EMAIL')
             when 'INSTAGRAM' then r.canonical = 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM'
             when 'CLAY' then r.canonical = 'CLAY_WORK_EMAIL'
             when 'OFFICIAL_INBOX' then r.canonical = 'OFFICIAL_PUBLISHED_INBOX'
             when 'NEEDS_RESEARCH' then not r.usable and r.status in ('NEW','RESEARCHING','READY') and coalesce(r.priority, 0) >= 60
             when 'SENT' then r.sent
             else false end
       and (p_stream is null or r.primary_stream = p_stream)
       and (p_q is null or coalesce(r.company, '') ilike '%' || p_q || '%' or coalesce(r.person, '') ilike '%' || p_q || '%' or coalesce(r.email, '') ilike '%' || p_q || '%'))
  select jsonb_build_object(
    'rows', coalesce((select jsonb_agg(jsonb_build_object('opportunity_id', x.opportunity_id, 'company_id', x.company_id, 'company', x.company, 'person', x.person,
                         'position', x.position, 'stream', x.stream_label, 'status', x.status, 'route_state', x.canonical, 'label', x.label, 'email', x.email,
                         'source_url', x.source_url, 'warm', x.warm, 'sent', x.sent, 'next_action', x.next_action, 'next_action_due', x.next_action_due,
                         'priority', x.priority, 'bucket', x.rank_bucket) order by x.rank_bucket, x.priority desc nulls last, x.company)
                       from (select * from f order by rank_bucket, priority desc nulls last, company limit p_limit offset p_offset) x), '[]'::jsonb),
    'total', (select count(*) from f), 'filter', p_filter, 'limit', p_limit, 'offset', p_offset,
    'computed_at', (select max(computed_at) from hq_route_cache)) into v;
  return v;
end $$;
revoke all on function public.hq_email_routes(text, text, text, int, int) from public, anon;
grant execute on function public.hq_email_routes(text, text, text, int, int) to authenticated;

select public.hq_route_cache_refresh();
