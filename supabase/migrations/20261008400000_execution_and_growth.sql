-- Execution and growth in parallel (Adam, 7 Oct 2026: D1 A / D2 B modified / D3 B).
-- 15-20 high-quality commercial actions a day in a fixed priority order, old drafts revalidated (never blindly redrafted),
-- every partnership prospect carries its commercial model, media targets carry a filmable concept, Serper spend is measured.
-- Research never waits for the send queue.

-- ---------------------------------------------------------------- Serper balance (measured, not estimated)
create table if not exists public.provider_balances (
  id bigint generated always as identity primary key,
  provider text not null,
  balance numeric not null,
  rate_limit numeric,
  recorded_at timestamptz not null default now()
);
create index if not exists provider_balances_provider_at on public.provider_balances (provider, recorded_at desc);
alter table public.provider_balances enable row level security;

create or replace function public.provider_balance_save(p_provider text, p_balance numeric, p_rate_limit numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if p_provider is null or p_balance is null then return jsonb_build_object('ok', false); end if;
  insert into provider_balances (provider, balance, rate_limit) values (upper(p_provider), p_balance, p_rate_limit);
  return jsonb_build_object('ok', true);
end $$;

-- Real burn from balance snapshots, plus the configured price ($50 per 50,000 credits = $1 per 1,000).
create or replace function public.serper_usage(p_days int default 3)
returns jsonb language sql stable security definer set search_path = public as $$
  with s as (select balance, recorded_at from provider_balances where provider = 'SERPER'),
       latest as (select balance, recorded_at from s order by recorded_at desc limit 1),
       base as (select balance, recorded_at from s where recorded_at <= now() - make_interval(days => p_days) order by recorded_at desc limit 1),
       earliest as (select balance, recorded_at from s order by recorded_at limit 1),
       ref as (select * from base union all select * from earliest where not exists (select 1 from base) limit 1),
       w as (select (select balance from latest) bal, (select balance from ref) - (select balance from latest) used,
                    extract(epoch from ((select recorded_at from latest) - (select recorded_at from ref))) / 86400.0 days),
       -- measured burn only once a full day of readings exists (department runs are bursty); the plan stands in until then
       m as (select w.*, case when days >= 1 then round(used / days, 0) end per_day from w)
  select jsonb_build_object(
    'balance', (select bal from m),
    'as_of', (select recorded_at from latest),
    'window_days', (select round(days, 2) from m),
    'used_in_window', (select used from m),
    'per_day', (select per_day from m),
    'per_day_basis', (select case when per_day is null then 'PLANNED (under a day of readings)' else 'MEASURED' end from m),
    'planned_per_day', 650,
    'per_cycle', (select coalesce(per_day, 650) * 3 from m),
    'cycle_usd', (select round(coalesce(per_day, 650) * 3 / 1000.0, 2) from m),
    'runway_days', (select floor(bal / greatest(coalesce(per_day, 650), 1)) from m),
    'usd_per_1000', 1.00,
    'note', 'Serper Starter pack: $50 for 50,000 credits, 6-month expiry. One credit per search at 10 results.')
$$;

-- ---------------------------------------------------------------- partnership model on every partnership prospect
alter table public.companies add column if not exists partnership_model text;
alter table public.companies add column if not exists partnership_model_source text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'companies_partnership_model_check') then
    alter table public.companies add constraint companies_partnership_model_check check (partnership_model is null or partnership_model in
      ('REFERRAL', 'RECIPROCAL', 'PREFERRED_STAY', 'EGYPT_EXECUTION', 'WHITE_LABEL_CONCIERGE', 'GUEST_CONCIERGE', 'CONTENT_TALENT'));
  end if;
end $$;

create or replace function public.partnership_model_label(p text)
returns text language sql immutable as $$
  select case p
    when 'REFERRAL' then 'Referral: they introduce clients or members who need Egypt; NOYA introduces clients to them'
    when 'RECIPROCAL' then 'Reciprocal destination support: each looks after the other''s clients in its own destination'
    when 'PREFERRED_STAY' then 'Preferred stay: NOYA places suitable private clients with them'
    when 'EGYPT_EXECUTION' then 'Egypt execution: they keep the client; NOYA runs the Egypt side'
    when 'WHITE_LABEL_CONCIERGE' then 'White-label concierge: NOYA delivers Egypt under their name'
    when 'GUEST_CONCIERGE' then 'Guest concierge: NOYA looks after their guests travelling to Egypt'
    when 'CONTENT_TALENT' then 'Content and talent partnership: NOYA hosts creators, talent or a production in Egypt'
  end
$$;

-- Deterministic first guess from what the company is. An agent or Adam can overwrite it (source AGENT / MANUAL).
create or replace function public.partnership_model_guess(p_lane text, p_type text, p_country text, p_notes text)
returns text language sql immutable as $$
  select case
    -- media, podcast, creator and production targets are content partnerships whichever lane found them
    when coalesce(p_type, '') ~* '(creator|influencer|podcast|media|magazine|youtube|talent|production|broadcast|documentary|film)'
         and coalesce(p_type, '') !~* '(hotel|resort|villa|residence)' then 'CONTENT_TALENT'
    when p_lane not in ('PARTNERSHIPS', 'TRAVEL_PRIVATE', 'WEDDINGS') then null
    when p_lane = 'WEDDINGS' then 'EGYPT_EXECUTION'
    when coalesce(p_type, '') ~* '(concierge|lifestyle management)' then 'WHITE_LABEL_CONCIERGE'
    when coalesce(p_type, '') ~* '(members? club|member_community|community|club|athlete fund|network of)' then 'REFERRAL'
    when coalesce(p_type, '') ~* '(\mdmc\M|destination management)' then 'RECIPROCAL'
    when coalesce(p_type, '') ~* '(travel|advisor|agency|tour operator|travel designer|tmc|management company|family office|private office)' then 'EGYPT_EXECUTION'
    when coalesce(p_type, '') ~* '(hotel|resort|villa|residence|aparthotel|serviced|chalet|lodge|camp|collection|hospitality)'
         then case when coalesce(p_country, '') ~* '^(eg|egypt)$' then 'PREFERRED_STAY' else 'RECIPROCAL' end
    when coalesce(p_type, '') ~* '(aviation|jet|yacht|chauffeur|security|protection)' then 'RECIPROCAL'
    else 'REFERRAL' end
$$;

create or replace function public.partnership_model_fill()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.partnership_model is null then
    new.partnership_model := partnership_model_guess(company_lane(new.acquisition_lane, new.prospect_segment, new.vertical_override, new.company_type),
                                                     new.company_type, new.country, new.notes);
    if new.partnership_model is not null then new.partnership_model_source := 'RULE'; end if;
  end if;
  return new;
end $$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'companies_partnership_model') then
    create trigger companies_partnership_model before insert or update of company_type, acquisition_lane, country, partnership_model
      on public.companies for each row execute function public.partnership_model_fill();
  end if;
end $$;

create or replace function public.ops_backfill_partnership_model()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update companies c set partnership_model = partnership_model_guess(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type),
                                                                     c.company_type, c.country, c.notes),
                         partnership_model_source = 'RULE'
   where c.partnership_model is null
     and partnership_model_guess(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.country, c.notes) is not null;
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------- creative concepts for media / podcast / creator targets
create table if not exists public.creative_concepts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  contact_id uuid references public.contacts(id) on delete set null,
  concept text not null,
  backdrop text not null,
  noya_role text not null,
  commercial_value text not null,
  source text not null default 'Workflow 21 creative concepts',
  status text not null default 'PROPOSED' check (status in ('PROPOSED', 'USED', 'REJECTED')),
  model text,
  created_at timestamptz not null default now(),
  unique (company_id)
);
alter table public.creative_concepts enable row level security;

create or replace function public.is_media_target(p_type text, p_notes text)
returns boolean language sql immutable as $$
  select coalesce(p_type, '') ~* '(podcast|youtube|media|magazine|publication|creator|show|series|broadcast|channel|documentary|production company|film)'
      or (coalesce(p_type, '') ~* '(brand|agency)' and coalesce(p_notes, '') ~* '(podcast|youtube series|video series|filmed)')
$$;

create or replace function public.creative_concept_queue(p_limit int default 8)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(x order by x->>'company'), '[]'::jsonb)) from (
    select jsonb_build_object('company_id', c.id, 'company', c.name, 'company_type', c.company_type, 'country', c.country,
             'evidence', left(coalesce(c.universe_reason, '') || ' ' || coalesce(c.notes, ''), 1400),
             'contact_id', k.id, 'person', nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), ''), 'position', k.position) x
      from companies c
      left join lateral (select * from contacts k where k.company_id = c.id and k.identity_status = 'CONFIRMED' and k.first_name is not null
                           and role_score(k.position) > 0 order by role_score(k.position) desc, k.confidence desc nulls last limit 1) k on true
     where c.universe_status in ('QUALIFIED', 'NEEDS_REVIEW')
       and company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) = 'BRANDS'
       and is_media_target(c.company_type, c.notes)
       and not exists (select 1 from creative_concepts cc where cc.company_id = c.id)
     order by (k.id is not null) desc, c.universe_added_at desc nulls last
     limit greatest(1, least(coalesce(p_limit, 8), 20))) q
$$;

create or replace function public.creative_concept_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_backdrops text[] := array['Pyramids of Giza', 'Mena House', 'Grand Egyptian Museum', 'The Nile', 'Aswan', 'Luxor', 'El Gouna',
                                    'Red Sea', 'Western Desert', 'Cairo', 'Private villa or resort'];
        u jsonb;
begin
  for u in select * from jsonb_array_elements(coalesce(p->'usage', '[]'::jsonb)) loop
    insert into ai_usage (workflow, purpose, model, company_id, input_tokens, output_tokens, thinking_tokens, est_cost_usd, status)
    values ('21', 'CONCEPT', coalesce(u->>'model', 'models/gemini-3.1-flash-lite'), (p->>'company_id')::uuid,
            coalesce((u->>'input_tokens')::int, 0), coalesce((u->>'output_tokens')::int, 0), coalesce((u->>'thinking_tokens')::int, 0),
            ai_cost_usd(coalesce(u->>'model', 'models/gemini-3.1-flash-lite'), coalesce((u->>'input_tokens')::int, 0), coalesce((u->>'output_tokens')::int, 0)),
            coalesce(u->>'status', 'OK'));
  end loop;
  if coalesce(p->>'concept', '') = '' or not (p->>'backdrop' = any (v_backdrops)) or coalesce(p->>'noya_role', '') = '' or coalesce(p->>'commercial_value', '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'INCOMPLETE_OR_UNKNOWN_BACKDROP');
  end if;
  insert into creative_concepts (company_id, contact_id, concept, backdrop, noya_role, commercial_value, model)
  values ((p->>'company_id')::uuid, nullif(p->>'contact_id', '')::uuid, left(p->>'concept', 600), p->>'backdrop', left(p->>'noya_role', 400),
          left(p->>'commercial_value', 400), p->>'model')
  on conflict (company_id) do nothing;
  return jsonb_build_object('ok', true);
end $$;

-- Angle prefix the planner adds for every account: the recorded partnership model, and the filmable concept for media.
create or replace function public.prospect_angle_prefix(p_company uuid)
returns text language sql stable security definer set search_path = public as $$
  select nullif(concat_ws(' ',
    (select 'Partnership model (recorded): ' || partnership_model_label(c.partnership_model) || '.' from companies c where c.id = p_company and c.partnership_model is not null),
    (select 'Concept: ' || cc.concept || ' Backdrop: ' || cc.backdrop || '. NOYA arranges: ' || cc.noya_role || '.'
       from creative_concepts cc where cc.company_id = p_company and cc.status <> 'REJECTED')), '')
$$;

-- ---------------------------------------------------------------- revalidation of drafts older than 14 days
alter table public.tasks add column if not exists revalidated_at timestamptz;
-- Adam explicitly approved this ready draft for sending (D3, 7 Oct: AC Milan, PSG). It always appears in today's actions; Adam still sends it.
alter table public.tasks add column if not exists ceo_approved_at timestamptz;

-- Deterministic checks first; workflow 20 adds the one search that confirms the person still holds the role.
create or replace function public.revalidation_queue(p_limit int default 15)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(x order by (x->>'created_at')), '[]'::jsonb)) from (
    select jsonb_build_object(
      'task_id', t.id, 'title', t.title, 'created_at', t.created_at, 'company_id', c.id, 'company', c.name,
      'contact_id', k.id, 'first_name', k.first_name, 'last_name', k.last_name, 'position', k.position, 'linkedin', k.linkedin,
      'company_relevant', c.universe_status in ('QUALIFIED', 'NEEDS_REVIEW') and not coalesce(k.do_not_contact, false),
      'relationship_state', relationship_state(c.id),
      'gmail_since', exists (select 1 from gmail_history_messages g where g.company_id = c.id and g.sent_at > t.created_at),
      'duplicate_open', exists (select 1 from tasks t2 where t2.company_id = c.id and t2.id <> t.id and t2.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
                                  and t2.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY|OUTREACH READY|DRAFT REVIEW)'
                                  and t2.contact_id is not distinct from t.contact_id and t2.created_at > t.created_at),
      'why_now', substring(coalesce(t.description, '') from 'Why now: ([^\n]*)')) x
      from tasks t
      join companies c on c.id = t.company_id
      left join contacts k on k.id = t.contact_id
     where t.status in ('OPEN', 'WAITING')
       and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY|OUTREACH READY)'
       and t.created_at < now() - interval '14 days'
       and coalesce(t.revalidated_at, '-infinity'::timestamptz) < now() - interval '14 days'
     order by t.created_at
     limit greatest(1, least(coalesce(p_limit, 15), 40))) q
$$;

-- p: { task_id, role_check: STILL_IN_ROLE | MOVED | NOT_FOUND | NOT_CHECKED, evidence_url, why_now_stale: bool }
create or replace function public.revalidation_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t tasks%rowtype; c companies%rowtype; v_rs text; v_dup boolean; v_gmail boolean; v_decision text; v_note text;
begin
  select * into t from tasks where id = (p->>'task_id')::uuid;
  if t.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  select * into c from companies where id = t.company_id;
  v_rs := relationship_state(c.id);
  v_gmail := exists (select 1 from gmail_history_messages g where g.company_id = c.id and g.sent_at > t.created_at);
  v_dup := exists (select 1 from tasks t2 where t2.company_id = c.id and t2.id <> t.id and t2.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
                     and t2.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY|OUTREACH READY|DRAFT REVIEW)'
                     and t2.contact_id is not distinct from t.contact_id and t2.created_at > t.created_at);
  v_decision := case
    when c.universe_status not in ('QUALIFIED', 'NEEDS_REVIEW') then 'CLOSE'
    when v_rs not in ('COLD', 'UNKNOWN') or v_gmail then 'CLOSE'
    when v_dup then 'CLOSE'
    when p->>'role_check' = 'MOVED' then 'REPLACE_PERSON'
    when coalesce((p->>'why_now_stale')::boolean, false) then 'REDRAFT'
    when t.contact_id is null then 'FIND_PERSON'
    else 'KEEP' end;
  v_note := 'REVALIDATED ' || to_char(now(), 'DD Mon YYYY') || ': ' || case v_decision
    when 'KEEP' then case p->>'role_check' when 'STILL_IN_ROLE' then 'person still in role' || coalesce(' (' || (p->>'evidence_url') || ')', '')
                                           when 'NOT_FOUND' then 'role not re-confirmed by search; company still relevant and cold'
                                           else 'company still relevant and cold' end || '. Draft kept.'
    when 'REPLACE_PERSON' then 'the person appears to have moved' || coalesce(' (' || (p->>'evidence_url') || ')', '') || '. Draft closed; contact routes re-searched.'
    when 'REDRAFT' then 'the why-now evidence is out of date. Draft closed so the planner can re-draft with fresh evidence.'
    when 'FIND_PERSON' then 'company still relevant and cold, but the draft names no person. Draft kept; held out of the send queue until a decision maker is found.'
    else case when c.universe_status not in ('QUALIFIED', 'NEEDS_REVIEW') then 'company no longer qualified'
              when v_rs not in ('COLD', 'UNKNOWN') then 'relationship moved on (' || v_rs || ')'
              when v_gmail then 'new Gmail interaction since the draft'
              else 'a newer draft exists for the same person' end || '. Draft closed.' end;
  if v_decision in ('KEEP', 'FIND_PERSON') then
    update tasks set revalidated_at = now(), description = v_note || chr(10) || chr(10) || coalesce(description, '') where id = t.id;
    if v_decision = 'FIND_PERSON' then
      update companies set last_enriched_at = null, enrichment_attempts = 0 where id = c.id;
    end if;
  else
    update tasks set status = 'CANCELLED', revalidated_at = now(), description = v_note || chr(10) || chr(10) || coalesce(description, '') where id = t.id;
    if v_decision = 'REPLACE_PERSON' then
      update companies set last_enriched_at = null, enrichment_attempts = 0 where id = c.id;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'decision', v_decision, 'company', c.name);
end $$;

-- ---------------------------------------------------------------- the day's 15-20 commercial actions
-- Order: 1 replies needing action, 2 warm opportunities, 3 follow-ups due, 4 strongest partnerships, 5 best cold prospects.
-- Drafts older than 14 days wait for revalidation before they can appear.
create or replace function public.daily_action_queue(p_limit int default 20)
returns jsonb language sql stable security definer set search_path = public as $$
  with lane_w(lane, w) as (values ('PARTNERSHIPS', 1.0), ('TRAVEL_PRIVATE', 0.9), ('WEDDINGS', 0.8), ('BRANDS', 0.8), ('EGYPT_EVENTS', 0.7), ('CORPORATE', 0.6), ('SPORTS_PRIVATE', 0.4)),
  open_t as (
    select t.*, c.name company, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane,
           relationship_state(c.id) rs, c.partnership_model, k.first_name, k.last_name, k.position, k.email, k.email_status, k.linkedin
      from tasks t left join companies c on c.id = t.company_id left join contacts k on k.id = t.contact_id
     where t.status in ('OPEN', 'IN_PROGRESS')),
  replies as (
    select 1 grp, 'Reply' action, null::uuid task_id, c.name company, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane,
           i.channel, coalesce(i.summary, i.subject, 'Inbound message') detail, 100 + extract(epoch from i.occurred_at) / 1e10 score, i.occurred_at ts
      from interactions i join companies c on c.id = i.company_id
     where i.direction = 'INBOUND' and i.occurred_at > now() - interval '21 days'
       and not exists (select 1 from interactions o where o.company_id = i.company_id and o.direction = 'OUTBOUND' and o.occurred_at > i.occurred_at)
    union all
    select 1, 'Reply', t.id, t.company, t.lane, 'TASK', t.title, 99, t.created_at from open_t t where t.task_type = 'REPLY_ACTION'),
  warm as (
    select 2 grp, 'Warm opportunity' action, t.id, t.company, t.lane, null channel, t.title detail,
           80 + coalesce(t.priority, 0) / 10.0 score, t.created_at ts
      from open_t t
     where (t.rs in ('MEETING_BOOKED', 'PROPOSAL', 'ACTIVE_CONVERSATION', 'PARTNER_ACTIVE', 'CLIENT')
            or t.title ~ '^(WARM ROUTE|RECONNECT|MEETING|ADAM PERSONAL OUTREACH|APPROVE OUTREACH)' or t.task_type = 'MEETING_ACTION')
       and t.task_type not in ('PROVIDER_HEALTH_ALERT', 'SYSTEM_ALERT', 'REPLY_ACTION')),
  follow as (
    select 3 grp, 'Follow up' action, t.id, t.company, t.lane, null, t.title, 60 + coalesce(t.priority, 0) / 10.0, coalesce(t.due_at, t.created_at)
      from open_t t
     where (t.task_type = 'OUTREACH_FOLLOW_UP' or t.title like 'FOLLOW UP%') and coalesce(t.due_at, now()) <= now() + interval '1 day'
       and t.rs in ('COLD', 'CONTACTED_RECENTLY', 'UNKNOWN')),
  ready as (
    select case when t.ceo_approved_at is not null or t.lane in ('PARTNERSHIPS', 'TRAVEL_PRIVATE') then 4 else 5 end grp,
           case when t.ceo_approved_at is not null then 'Approved send' when t.lane in ('PARTNERSHIPS', 'TRAVEL_PRIVATE') then 'Partnership outreach' else 'New prospect outreach' end action,
           t.id, t.company, t.lane,
           case when t.title like 'EMAIL READY%' then 'EMAIL' when t.title like 'INSTAGRAM%' then 'INSTAGRAM' else 'LINKEDIN' end,
           t.title,
           40 * coalesce((select w from lane_w where lane_w.lane = t.lane), 0.5)
             + 5 * role_score(t.position)
             + case when t.email_status = 'VERIFIED' then 15 when t.title like 'EMAIL READY%' then 12
                    when coalesce(t.linkedin, '') ~* 'linkedin\.com/in/' then 10 when t.title like 'INSTAGRAM%' then 8 else 4 end
             + case when t.created_at > now() - interval '7 days' then 5 else 0 end
             + coalesce(t.priority, 0) / 20.0 + case when t.ceo_approved_at is not null then 100 else 0 end,
           t.created_at
      from open_t t
     where t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)'
       and t.rs in ('COLD', 'UNKNOWN')
       and t.contact_id is not null  -- a draft with no named person is not ready to send (W19 looks for one)
       and (t.created_at > now() - interval '14 days' or t.revalidated_at > now() - interval '14 days')),
  allq as (select * from replies union all select * from warm union all select * from follow union all select * from ready),
  ranked as (select a.*, row_number() over (partition by coalesce(a.company, a.task_id::text) order by a.grp, a.score desc) dup from allq a),
  dedup as (select r.*, row_number() over (partition by case when grp in (4, 5) then 4 else grp end order by grp, score desc) gi from ranked r where dup = 1),
  -- one action per company; replies, warm opportunities and drafts Adam approved (ceo_approved_at) always appear; at least 3 outreach slots (partnerships first) keep new prospects moving;
  -- the strongest follow-ups due take the rest of the 15-20
  n as (select greatest(15, least(coalesce(p_limit, 20), 40)) lim, (select count(*) from dedup where grp in (1, 2)) n12,
               (select count(*) from dedup where grp = 3) n3, (select count(*) from dedup where grp in (4, 5)) n45),
  quota as (select lim, n12, least(n3, greatest(0, lim - n12 - least(3, n45))) q3 from n),
  pick as (select d.* from dedup d, quota q
            where d.grp in (1, 2)
               or (d.grp = 3 and d.gi <= q.q3)
               or (d.grp in (4, 5) and d.action = 'Approved send')
               or (d.grp in (4, 5) and d.gi <= greatest(least(3, (select n45 from n)), q.lim - q.n12 - q.q3)))
  select jsonb_build_object(
    'target', '15-20 commercial actions a working day',
    'count', (select count(*) from pick),
    'by_group', (select jsonb_object_agg(action, n) from (select action, count(*) n from pick group by action) s),
    'waiting_revalidation', (select count(*) from open_t t where t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)'
                               and t.created_at <= now() - interval '14 days' and coalesce(t.revalidated_at, '-infinity'::timestamptz) <= now() - interval '14 days'),
    'waiting_for_person', (select count(*) from open_t t where t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)'
                             and t.contact_id is null and t.rs in ('COLD', 'UNKNOWN')),
    'items', coalesce((select jsonb_agg(jsonb_build_object('rank', rn, 'group', grp, 'action', action, 'task_id', task_id, 'company', company,
                                                           'lane', lane, 'channel', channel, 'detail', left(detail, 160)) order by rn)
                         from (select p.*, row_number() over (order by grp, score desc) rn from pick p) z), '[]'::jsonb))
$$;

-- ---------------------------------------------------------------- growth scorecard (the next report)
create or replace function public.growth_scorecard(p_since timestamptz default now() - interval '3 days')
returns jsonb language sql stable security definer set search_path = public as $$
  with nc as (select c.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane
                from companies c where c.created_at >= p_since and c.universe_status in ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING')),
       nk as (select k.* from contacts k where k.created_at >= p_since and not coalesce(k.do_not_contact, false)),
       ready as (select t.* from tasks t where t.created_at >= p_since and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)'),
       sent as (select i.* from interactions i where i.occurred_at >= p_since and i.direction = 'OUTBOUND'),
       done_send as (select t.* from tasks t where t.status = 'COMPLETED' and coalesce(t.completed_at, t.updated_at) >= p_since and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)')
  select jsonb_build_object(
    'since', p_since,
    'new_companies', (select count(*) from nc),
    'new_companies_by_source', (select jsonb_object_agg(src, n) from (select case when source ~* '^https?://|chatgpt' then 'ChatGPT' when source ~* 'Department' then 'Agents' else 'Other research' end src, count(*) n from nc group by 1) s),
    'new_decision_makers', (select count(*) from nk where identity_status = 'CONFIRMED' and first_name is not null and role_score(position) >= 3),
    'new_public_emails', (select count(*) from nk where email is not null and email_status in ('UNVERIFIED', 'VERIFIED') and email_kind(email) = 'DIRECT_PERSON_EMAIL'),
    'new_company_inboxes', (select count(*) from nk where route_type = 'COMPANY_INBOX'),
    'new_linkedin_routes', (select count(*) from nk where identity_status = 'CONFIRMED' and coalesce(linkedin, '') ~* 'linkedin\.com/in/'),
    'new_instagram_routes', (select count(*) from nk where coalesce(instagram, '') <> '')
                            + (select count(*) from companies c where c.updated_at >= p_since and coalesce(c.instagram, '') <> '' and c.created_at >= p_since),
    'outreach_ready', (select count(*) from ready),
    'outreach_ready_by_lane', (select jsonb_object_agg(lane, n) from (select company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane, count(*) n
                                                                       from ready r join companies c on c.id = r.company_id group by 1) s),
    'hospitality_partnerships', (select count(*) from nc where lane = 'PARTNERSHIPS'
                                   and coalesce(company_type, '') ~* '(hotel|resort|villa|residence|aparthotel|serviced|chalet|collection|hospitality)'),
    'partnership_prospects_with_model', (select count(*) from nc where lane in ('PARTNERSHIPS', 'TRAVEL_PRIVATE') and partnership_model is not null),
    'partnership_models', (select jsonb_object_agg(partnership_model, n) from (select partnership_model, count(*) n from nc where partnership_model is not null group by 1) s),
    'media_concepts', (select count(*) from creative_concepts where created_at >= p_since),
    'wedding_prospects', (select count(*) from nc where lane = 'WEDDINGS'),
    'brands_production_prospects', (select count(*) from nc where lane = 'BRANDS'),
    'sends', (select count(*) from sent) + (select count(*) from done_send where not exists (select 1 from sent s where s.company_id = done_send.company_id)),
    'replies', (select count(*) from interactions i where i.occurred_at >= p_since and i.direction = 'INBOUND' and i.channel <> 'WEBSITE'),
    'calls', (select count(*) from interactions i where i.occurred_at >= p_since and i.channel = 'MEETING')
             + (select count(*) from tasks t where t.created_at >= p_since and (t.task_type = 'MEETING_ACTION' or t.title like 'MEETING --%')),
    'serper', serper_usage(3),
    'ai_cost', ai_budget_status())
$$;

revoke all on function public.provider_balance_save(text, numeric, numeric) from public, anon, authenticated;
revoke all on function public.creative_concept_save(jsonb) from public, anon, authenticated;
revoke all on function public.revalidation_save(jsonb) from public, anon, authenticated;
revoke all on function public.ops_backfill_partnership_model() from public, anon, authenticated;

-- one-off: models for the companies already in the universe, and the first Serper balance reading (7 Oct 02:30 UTC)
select ops_backfill_partnership_model();
select provider_balance_save('SERPER', 41194, 50);
