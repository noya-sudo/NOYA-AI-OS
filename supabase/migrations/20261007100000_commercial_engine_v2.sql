-- NOYA Commercial Engine V2 (Adam, 7 Oct 2026): daily outreach, specialist lanes, Commercial Director.
--  * Six acquisition lanes (specialist agents): BRANDS, PARTNERSHIPS, WEDDINGS, EGYPT_EVENTS, CORPORATE, SPORTS_PRIVATE.
--  * relationship_state(): a live conversation, booked meeting, proposal, client or active partner suppresses cold outreach.
--  * commercial_director_plan(): picks the day's 15-20 qualified touches across lanes (warm routes first), never two
--    touches on the same company, never someone already in the queue or in conversation. Writes outreach_candidates.
--  * outreach_candidate_save(): stores the drafted message + QA from workflow 18. Live mode creates the hand-send task
--    (Adam sends personally); dry run creates nothing. Nothing is ever sent automatically.
--  * commercial_today() / commercial_learning(): CEO dashboard and weekly learning, from system records only.

-- ---------------------------------------------------------------- lanes + config
alter table public.companies add column if not exists acquisition_lane text;
alter table public.companies drop constraint if exists companies_acquisition_lane_check;
alter table public.companies add constraint companies_acquisition_lane_check check (acquisition_lane is null or acquisition_lane in
  ('BRANDS', 'PARTNERSHIPS', 'WEDDINGS', 'EGYPT_EVENTS', 'CORPORATE', 'SPORTS_PRIVATE'));

create or replace function public.company_lane(p_lane text, p_segment text, p_vertical_override text, p_company_type text)
returns text language sql stable as $$
  select coalesce(p_lane, case company_segment(p_segment, p_vertical_override, p_company_type)
    when 'BRAND_PR_PRODUCTION' then 'BRANDS'
    when 'TRAVEL_PARTNER' then 'PARTNERSHIPS'
    when 'HOTELS_HOSPITALITY' then 'PARTNERSHIPS'
    when 'MEMBER_COMMUNITIES' then 'PARTNERSHIPS'
    when 'WEDDING_EVENTS' then 'WEDDINGS'
    when 'LIVE_SIGNAL' then 'EGYPT_EVENTS'
    when 'CORPORATE_EVENTS' then 'CORPORATE'
    when 'PRIVATE_OFFICE' then 'SPORTS_PRIVATE'
    when 'TALENT' then 'SPORTS_PRIVATE'
    else 'CORPORATE' end)
$$;

insert into public.system_config (key, value, note, updated_at) values
  ('acquisition_mix', '{"BRANDS":6,"PARTNERSHIPS":4,"WEDDINGS":3,"CORPORATE":3,"EGYPT_EVENTS":2,"SPORTS_PRIVATE":2}',
   'Starting daily mix for a 20-touch day. The Commercial Director reallocates unused slots to lanes with stronger candidates.', now()),
  ('daily_touch_target', '{"floor":15,"target":20}', 'Qualified outbound touches per working day. Quality first: a shortfall is shown, never filled.', now()),
  ('drafting_model', '{"draft":"models/gemini-3-flash-preview","research":"models/gemini-3.1-flash-lite"}',
   'Final outbound drafting only uses the stronger model (Gemini 3 Flash, $0.50/$3.00 per 1M tokens, checked 7 Oct 2026).', now())
on conflict (key) do update set value = excluded.value, note = excluded.note, updated_at = now();

-- ---------------------------------------------------------------- relationship state (overrides automation)
create or replace function public.relationship_state(p_company uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when p_company is null then 'UNKNOWN'
    when exists (select 1 from companies c where c.id = p_company and coalesce(c.relationship_status, '') ~* 'client')
      or exists (select 1 from revenue r where r.company_id = p_company) then 'CLIENT'
    when exists (select 1 from company_relationships cr where cr.company_id = p_company and cr.relationship_status = 'ACTIVE') then 'PARTNER_ACTIVE'
    when exists (select 1 from opportunities o where o.company_id = p_company and o.status in ('PROPOSAL', 'NEGOTIATION')) then 'PROPOSAL'
    when exists (select 1 from opportunities o where o.company_id = p_company and o.status = 'CALL_REQUIRED')
      or exists (select 1 from interactions i where i.company_id = p_company and i.channel = 'MEETING' and i.occurred_at > now() - interval '30 days')
      or exists (select 1 from tasks t where t.company_id = p_company and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
                 and (t.task_type = 'MEETING_ACTION' or t.title like 'MEETING --%')) then 'MEETING_BOOKED'
    when exists (select 1 from opportunities o where o.company_id = p_company and o.status = 'INTERESTED')
      or exists (select 1 from interactions i where i.company_id = p_company and i.direction = 'INBOUND' and i.channel <> 'WEBSITE'
                 and i.occurred_at > now() - interval '45 days')
      or exists (select 1 from tasks t where t.company_id = p_company and t.status in ('OPEN', 'IN_PROGRESS') and t.task_type in ('REPLY_ACTION', 'HUMAN_REVIEW')) then 'ACTIVE_CONVERSATION'
    when exists (select 1 from opportunities o where o.company_id = p_company and o.status = 'LOST' and o.updated_at > now() - interval '180 days') then 'DECLINED_RECENTLY'
    when exists (select 1 from interactions i where i.company_id = p_company and i.direction = 'OUTBOUND' and i.occurred_at > now() - interval '60 days') then 'CONTACTED_RECENTLY'
    else 'COLD' end
$$;

-- Warm route evidence only (never inferred): a real two-way email history, a LinkedIn connection, or a past reply.
create or replace function public.company_warm_route(p_company uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select 'LinkedIn connection: ' || coalesce(l.first_name, '') || ' ' || coalesce(l.last_name, '') from linkedin_connections l where l.matched_company_id = p_company limit 1),
    (select 'Previous email relationship (' || coalesce(r.status, 'reviewed') || ')' from relationship_reviews r join companies c on c.id = p_company
      where c.website is not null and r.key = 'd:' || lower(regexp_replace(c.website, '^(https?://)?(www\.)?([^/?#]+).*$', '\3'))
        and coalesce(r.status, '') not in ('NOT_RELEVANT') limit 1),
    (select 'Replied to NOYA before (' || to_char(max(i.occurred_at), 'Mon YYYY') || ')' from interactions i where i.company_id = p_company and i.direction = 'INBOUND' and i.channel <> 'WEBSITE' having count(*) > 0))
$$;

-- ---------------------------------------------------------------- daily candidates
create table if not exists public.outreach_candidates (
  id uuid primary key default gen_random_uuid(),
  run_date date not null default current_date,
  dry_run boolean not null default true,
  lane text not null,
  company_id uuid not null references public.companies(id) on delete cascade,
  contact_id uuid references public.contacts(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  channel text not null check (channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM', 'WARM_INTRO')),
  warm_route text,
  why_now text,
  evidence text,
  angle text,
  status text not null default 'PLANNED' check (status in ('PLANNED', 'READY', 'REVIEW_REQUIRED', 'APPROVED', 'SENT', 'SKIPPED')),
  subject text,
  draft text,
  qa_status text,
  qa_issues jsonb,
  attempts smallint not null default 0,
  model text,
  task_id uuid references public.tasks(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists outreach_candidates_run on public.outreach_candidates (run_date, status);
create index if not exists outreach_candidates_company on public.outreach_candidates (company_id, created_at desc);
alter table public.outreach_candidates enable row level security;
revoke all on public.outreach_candidates from anon, authenticated;

-- The day's plan. Re-running on the same day returns the same plan (idempotent) unless p_replan.
create or replace function public.commercial_director_plan(p_dry_run boolean default true, p_target int default null, p_replan boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_mix jsonb := (select value from system_config where key = 'acquisition_mix');
        v_target int := coalesce(p_target, ((select value from system_config where key = 'daily_touch_target')->>'target')::int, 20);
        v_total int := 0; v_lane text; v_quota int; v_left int; r record; v_out jsonb;
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
         and relationship_state(c.id) = 'COLD'
         -- never two agents on one company, never anything already queued or recently planned
         and not exists (select 1 from tasks t where t.company_id = c.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
                          and (t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY|VERIFY FIRST|DRAFT REVIEW|FOLLOW UP)'
                               or t.task_type = 'SALES_OUTREACH_APPROVAL'))
         and not exists (select 1 from outreach_candidates oc where oc.company_id = c.id and oc.status <> 'SKIPPED' and oc.created_at > now() - interval '30 days')
         and not exists (select 1 from outbound_emails ob where ob.company_id = c.id and ob.status in ('QUEUED', 'CLAIMED', 'DRAFTED', 'SENT') and ob.created_at > now() - interval '60 days')),
    pick as (
      select b.*, k.id contact_id, k.first_name, k.last_name, k.position, k.email, k.email_status, k.linkedin, k.instagram,
        case
          when k.email_status = 'VERIFIED' and email_kind(k.email) = 'DIRECT_PERSON_EMAIL' and b.lane in ('CORPORATE', 'PARTNERSHIPS', 'EGYPT_EVENTS') then 'EMAIL'
          when coalesce(k.linkedin, '') ~* 'linkedin\.com/in/' then 'LINKEDIN'
          when k.email_status = 'VERIFIED' and email_kind(k.email) = 'DIRECT_PERSON_EMAIL' then 'EMAIL'
          when coalesce(k.instagram, b.company_instagram, '') <> '' and b.lane in ('BRANDS', 'WEDDINGS')
               and coalesce(b.company_type, '') !~* '(bank|wealth|law|legal|consult|invest|family|financial|insurance|asset|equity)' then 'INSTAGRAM'
          else 'LINKEDIN' end channel,
        row_number() over (partition by b.lane order by (b.warm is not null) desc,
          coalesce((select o.priority from opportunities o where o.id = b.opp_id), 0) desc, b.name) rn
      from base b
      join lateral (select * from contacts k where k.company_id = b.company_id and not coalesce(k.do_not_contact, false)
                      and k.identity_status = 'CONFIRMED' and k.position is not null
                    order by (k.email_status = 'VERIFIED') desc, (coalesce(k.linkedin, '') <> '') desc, k.confidence desc nulls last limit 1) k on true)
    select * from pick;

    -- 1) each lane up to its quota (scaled to the target), 2) unused slots to the best remaining candidates anywhere
    for v_lane, v_quota in select key, round((value::text)::numeric * v_target / 20.0)::int from jsonb_each(v_mix) loop
      insert into outreach_candidates (run_date, dry_run, lane, company_id, contact_id, opportunity_id, channel, warm_route, why_now, evidence, angle)
      select current_date, p_dry_run, p.lane, p.company_id, p.contact_id, p.opp_id, p.channel, p.warm,
             (select coalesce(o.commercial_trigger, o.reason) from opportunities o where o.id = p.opp_id),
             p.universe_reason, (select o.angle from opportunities o where o.id = p.opp_id)
        from _pool p where p.lane = v_lane and p.rn <= v_quota;
    end loop;
    select count(*) into v_total from outreach_candidates where run_date = current_date and dry_run = p_dry_run;
    v_left := v_target - v_total;
    if v_left > 0 then
      insert into outreach_candidates (run_date, dry_run, lane, company_id, contact_id, opportunity_id, channel, warm_route, why_now, evidence, angle)
      select current_date, p_dry_run, p.lane, p.company_id, p.contact_id, p.opp_id, p.channel, p.warm,
             (select coalesce(o.commercial_trigger, o.reason) from opportunities o where o.id = p.opp_id),
             p.universe_reason, (select o.angle from opportunities o where o.id = p.opp_id)
        from _pool p
       where not exists (select 1 from outreach_candidates oc where oc.company_id = p.company_id and oc.run_date = current_date and oc.dry_run = p_dry_run)
       order by (p.warm is not null) desc, p.rn
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
      'email', case when oc.channel = 'EMAIL' then k.email end, 'linkedin', k.linkedin, 'instagram', coalesce(k.instagram, c.instagram),
      'warm_route', oc.warm_route, 'why_now', oc.why_now, 'evidence', left(coalesce(oc.evidence, '') || ' ' || coalesce(c.notes, ''), 1500),
      'angle', oc.angle, 'contact_notes', left(k.notes, 600)) order by oc.lane, oc.created_at) filter (where oc.status = 'PLANNED'), '[]'::jsonb))
  into v_out
  from outreach_candidates oc join companies c on c.id = oc.company_id left join contacts k on k.id = oc.contact_id
  where oc.run_date = current_date and oc.dry_run = p_dry_run;
  return v_out;
end $$;

-- Workflow 18 writes the drafted message back. Live mode: PASS -> hand-send task; failed twice -> DRAFT REVIEW task.
create or replace function public.outreach_candidate_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare oc outreach_candidates%rowtype; c companies%rowtype; k contacts%rowtype; v_status text; v_title text; v_task uuid;
        v_banned text := '(i am reaching out|i''m reaching out|i wanted to reach out|i wanted to introduce|been following|love what you)';
begin
  select * into oc from outreach_candidates where id = (p->>'candidate_id')::uuid;
  if oc.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  select * into c from companies where id = oc.company_id;
  select * into k from contacts where id = oc.contact_id;
  v_status := case when p->>'qa_status' = 'PASS' and coalesce(p->>'draft', '') <> '' and lower(p->>'draft') !~ v_banned then 'READY' else 'REVIEW_REQUIRED' end;
  update outreach_candidates set subject = nullif(p->>'subject', ''), draft = p->>'draft', qa_status = p->>'qa_status', qa_issues = p->'qa_issues',
         attempts = coalesce((p->>'attempts')::int, attempts), model = p->>'model', status = v_status, updated_at = now()
   where id = oc.id;
  if not oc.dry_run then
    v_title := case when v_status = 'READY' then
                 case oc.channel when 'EMAIL' then 'EMAIL READY' when 'INSTAGRAM' then 'INSTAGRAM DM READY' else 'LINKEDIN MESSAGE READY' end
               else 'DRAFT REVIEW' end
               || ' -- ' || c.name || coalesce(' · ' || nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), ''), '');
    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
    values (oc.company_id, oc.contact_id, oc.opportunity_id, v_title,
            'Lane: ' || oc.lane || ' · Channel: ' || oc.channel || coalesce(' · Warm route: ' || oc.warm_route, '') || chr(10) ||
            coalesce('Why now: ' || oc.why_now || chr(10), '') ||
            case when v_status = 'READY' then '' else 'QA failed twice: ' || coalesce((p->'qa_issues')::text, '') || chr(10) end || chr(10) ||
            coalesce('Subject: ' || nullif(p->>'subject', '') || chr(10) || chr(10), '') || coalesce(p->>'draft', '') || chr(10) || chr(10) ||
            'Send it yourself, then mark done (logs the send, books follow-ups). Dismiss = not sent.',
            'CONTACT_RESOLUTION', 'Adam', 'Commercial Director (workflow 18)', case when oc.warm_route is not null then 85 else 75 end, 'OPEN', now())
    returning id into v_task;
    update outreach_candidates set task_id = v_task where id = oc.id;
  end if;
  return jsonb_build_object('ok', true, 'status', v_status, 'task_id', v_task);
end $$;
revoke all on function public.commercial_director_plan(boolean, int, boolean) from public, anon, authenticated;
revoke all on function public.outreach_candidate_save(jsonb) from public, anon, authenticated;

-- A sent hand-send task marks its candidate SENT (feeds weekly learning).
create or replace function public.outreach_candidate_sent()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status <> old.status and new.status in ('COMPLETED', 'CANCELLED') then
    update outreach_candidates set status = case when new.status = 'COMPLETED' then 'SENT' else 'SKIPPED' end, updated_at = now()
     where task_id = new.id;
  end if;
  return new;
end $$;
create or replace trigger outreach_candidate_sent after update of status on public.tasks
  for each row execute function public.outreach_candidate_sent();

-- ---------------------------------------------------------------- CEO dashboard (system records only)
create or replace function public.commercial_today()
returns jsonb language sql stable security definer set search_path = public as $$
  with lanes(lane) as (values ('BRANDS'), ('PARTNERSHIPS'), ('WEDDINGS'), ('EGYPT_EVENTS'), ('CORPORATE'), ('SPORTS_PRIVATE')),
  t as (select t.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane
          from tasks t left join companies c on c.id = t.company_id where t.status in ('OPEN', 'IN_PROGRESS')),
  i as (select i.*, company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) lane
          from interactions i left join companies c on c.id = i.company_id where i.occurred_at >= current_date),
  per as (
    select l.lane,
      (select count(*) from companies c where c.universe_added_at >= current_date and c.universe_status in ('QUALIFIED', 'NEEDS_REVIEW')
         and company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type) = l.lane) discovered,
      (select count(*) from t where t.lane = l.lane and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY)') send_ready,
      (select count(*) from t where t.lane = l.lane and t.title like 'LINKEDIN MESSAGE READY%') linkedin,
      (select count(*) from t where t.lane = l.lane and t.title like 'INSTAGRAM DM READY%') instagram,
      (select count(*) from t where t.lane = l.lane and (t.title like 'EMAIL READY%' or t.task_type = 'SALES_OUTREACH_APPROVAL')) emails,
      (select count(*) from t where t.lane = l.lane and (t.task_type = 'SALES_OUTREACH_APPROVAL' or t.title like 'DRAFT REVIEW%')) awaiting_approval,
      (select count(*) from t where t.lane = l.lane and t.task_type = 'OUTREACH_FOLLOW_UP' and coalesce(t.due_at, now()) <= now() + interval '1 day') follow_ups_due,
      (select count(*) from i where i.lane = l.lane and i.direction = 'OUTBOUND') sent_today,
      (select count(*) from i where i.lane = l.lane and i.direction = 'INBOUND' and i.channel not in ('WEBSITE', 'MEETING')) replies_today,
      (select count(*) from i where i.lane = l.lane and i.channel = 'MEETING') meetings_today
    from lanes l)
  select jsonb_build_object(
    'date', current_date,
    'target', (select value from system_config where key = 'daily_touch_target'),
    'lanes', (select jsonb_agg(to_jsonb(per) order by array_position(array['BRANDS','PARTNERSHIPS','WEDDINGS','EGYPT_EVENTS','CORPORATE','SPORTS_PRIVATE'], per.lane)) from per),
    'totals', (select jsonb_build_object('discovered', sum(discovered), 'send_ready', sum(send_ready), 'linkedin', sum(linkedin), 'instagram', sum(instagram),
        'emails', sum(emails), 'awaiting_approval', sum(awaiting_approval), 'follow_ups_due', sum(follow_ups_due), 'sent_today', sum(sent_today),
        'replies_today', sum(replies_today), 'meetings_today', sum(meetings_today)) from per),
    'planned_today', (select jsonb_build_object('planned', count(*), 'ready', count(*) filter (where status = 'READY'),
        'review_required', count(*) filter (where status = 'REVIEW_REQUIRED'), 'dry_run', bool_or(dry_run))
        from outreach_candidates where run_date = current_date),
    'conversations', (select coalesce(jsonb_agg(jsonb_build_object('company', c.name, 'state', relationship_state(c.id)) order by c.name), '[]'::jsonb)
        from companies c where c.id in (select company_id from opportunities where status in ('CALL_REQUIRED', 'INTERESTED', 'PROPOSAL', 'NEGOTIATION'))))
$$;

-- Weekly learning: what produced replies, by lane / channel / angle / model / country / title. Recommendations only.
create or replace function public.commercial_learning(p_weeks int default 4)
returns jsonb language sql stable security definer set search_path = public as $$
  with oc as (
    select oc.*, c.country, k.position,
           exists (select 1 from interactions i where i.company_id = oc.company_id and i.direction = 'INBOUND' and i.occurred_at > oc.updated_at) replied,
           exists (select 1 from interactions i where i.company_id = oc.company_id and i.channel = 'MEETING' and i.occurred_at > oc.updated_at)
             or exists (select 1 from opportunities o where o.company_id = oc.company_id and o.status in ('CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON')) met
      from outreach_candidates oc join companies c on c.id = oc.company_id left join contacts k on k.id = oc.contact_id
     where oc.status = 'SENT' and oc.updated_at > now() - make_interval(weeks => greatest(1, least(coalesce(p_weeks, 4), 26)))),
  dim as (
    select 'lane' d, lane v, replied, met from oc union all select 'channel', channel, replied, met from oc
    union all select 'angle', coalesce(angle, 'unspecified'), replied, met from oc union all select 'model', coalesce(model, 'unknown'), replied, met from oc
    union all select 'country', coalesce(country, 'UNKNOWN'), replied, met from oc union all select 'title', coalesce(position, 'unknown'), replied, met from oc)
  select jsonb_build_object('weeks', p_weeks, 'sent', (select count(*) from oc),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('dimension', d, 'value', v, 'sent', n, 'replies', r, 'reply_rate', round(100.0 * r / n), 'meetings', m) order by d, n desc)
       from (select d, v, count(*) n, count(*) filter (where replied) r, count(*) filter (where met) m from dim group by 1, 2) s), '[]'::jsonb),
    'note', 'Only sends recorded through workflow 18 hand-send tasks. Allocation changes are recommendations for Adam.')
$$;
revoke all on function public.commercial_today() from public, anon;
revoke all on function public.commercial_learning(int) from public, anon;

create or replace function public.hq_execution()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  return jsonb_build_object('queue', queue_health(), 'weekly', commercial_weekly_metrics(6), 'hunter', hunter_roi(), 'today', commercial_today());
end $$;
revoke all on function public.hq_execution() from public, anon;
grant execute on function public.hq_execution() to authenticated;

-- Lane backfill from the segment rules (explicit, re-runnable).
update public.companies set acquisition_lane = company_lane(null, prospect_segment, vertical_override, company_type)
 where acquisition_lane is null and universe_status is not null;
