-- Commercial Engine V2: AI cost controls, honest draft metrics, human-reviewed path (8 Oct 2026)
-- * Every model call workflow 18 makes is logged with tokens and estimated cost (ai_usage).
-- * NOYA-side budget guardrail: target $5/month, review ceiling $10/month (Adam must approve above it),
--   daily hold. Workflow 18 checks ai_budget_status() before drafting and stops when it says HOLD.
-- * The system draft is kept separately from anything a human rewrote, so the system pass rate
--   and the final ready-after-review count are always two different numbers.

-- ---------------------------------------------------------------- config
insert into public.system_config (key, value) values
  ('ai_budget', '{"target_usd_month": 5, "approved_ceiling_usd_month": 10, "daily_hold_usd": 0.75}'::jsonb),
  ('ai_pricing', '{"models/gemini-3-flash-preview": {"in": 0.50, "out": 3.00}, "models/gemini-3.1-flash-lite": {"in": 0.25, "out": 1.50}, "source": "ai.google.dev/gemini-api/docs/pricing (checked 7 Oct 2026); output price includes thinking tokens"}'::jsonb)
on conflict (key) do update set value = excluded.value;
update public.system_config set value = value || '{"thinking_level": "minimal", "max_output_tokens": 1024}'::jsonb where key = 'drafting_model';

-- ---------------------------------------------------------------- usage log
create table if not exists public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  at timestamptz not null default now(),
  workflow text not null,
  purpose text not null,
  model text not null,
  candidate_id uuid references public.outreach_candidates(id) on delete set null,
  company_id uuid references public.companies(id) on delete set null,
  input_tokens int not null default 0,
  output_tokens int not null default 0,
  thinking_tokens int not null default 0,
  est_cost_usd numeric(12, 6) not null default 0,
  status text not null default 'OK' check (status in ('OK', 'RATE_LIMITED', 'ERROR'))
);
create index if not exists ai_usage_at on public.ai_usage (at desc);
alter table public.ai_usage enable row level security;
revoke all on public.ai_usage from anon, authenticated;

create or replace function public.ai_cost_usd(p_model text, p_in int, p_out int)
returns numeric language sql stable security definer set search_path = public as $$
  select round((coalesce(p_in, 0) * coalesce((value -> p_model ->> 'in')::numeric, 0.50)
              + coalesce(p_out, 0) * coalesce((value -> p_model ->> 'out')::numeric, 3.00)) / 1000000.0, 6)
    from system_config where key = 'ai_pricing'
$$;

-- OK / OVER_TARGET (still drafting, flagged) / HOLD (monthly ceiling reached: needs Adam) / DAILY_HOLD
create or replace function public.ai_budget_status()
returns jsonb language sql stable security definer set search_path = public as $$
  with b as (select value v from system_config where key = 'ai_budget'),
       u as (select coalesce(sum(est_cost_usd) filter (where at >= date_trunc('month', now())), 0) mtd,
                    coalesce(sum(est_cost_usd) filter (where at >= current_date), 0) today,
                    count(*) filter (where at >= date_trunc('month', now())) calls_mtd
               from ai_usage)
  select jsonb_build_object(
    'mtd_usd', round(u.mtd, 4), 'today_usd', round(u.today, 4), 'calls_mtd', u.calls_mtd,
    'target_usd', (b.v->>'target_usd_month')::numeric, 'ceiling_usd', (b.v->>'approved_ceiling_usd_month')::numeric,
    'daily_hold_usd', (b.v->>'daily_hold_usd')::numeric,
    'status', case when u.mtd >= (b.v->>'approved_ceiling_usd_month')::numeric then 'HOLD'
                   when u.today >= (b.v->>'daily_hold_usd')::numeric then 'DAILY_HOLD'
                   when u.mtd >= (b.v->>'target_usd_month')::numeric then 'OVER_TARGET'
                   else 'OK' end,
    'note', 'NOYA-side guardrail. Raising the ceiling needs Adam''s approval. Google budget alerts warn; they do not stop spend.')
  from b, u
$$;
revoke all on function public.ai_cost_usd(text, int, int) from public, anon, authenticated;
revoke all on function public.ai_budget_status() from public, anon, authenticated;

-- ---------------------------------------------------------------- candidates: system vs human
alter table public.outreach_candidates
  add column if not exists system_subject text,
  add column if not exists system_draft text,
  add column if not exists system_qa_status text,
  add column if not exists system_qa_issues jsonb,
  add column if not exists first_pass_ok boolean,
  add column if not exists redraft_ok boolean,
  add column if not exists rate_limited boolean not null default false,
  add column if not exists model_calls smallint not null default 0,
  add column if not exists tokens_in int not null default 0,
  add column if not exists tokens_out int not null default 0,
  add column if not exists est_cost_usd numeric(12, 6) not null default 0,
  add column if not exists review_source text not null default 'SYSTEM',
  add column if not exists hold_reason text,
  add column if not exists batch text;
alter table public.outreach_candidates drop constraint if exists outreach_candidates_status_check;
alter table public.outreach_candidates add constraint outreach_candidates_status_check
  check (status in ('PLANNED', 'READY', 'REVIEW_REQUIRED', 'APPROVED', 'SENT', 'SKIPPED', 'HOLD', 'RESEARCH'));
alter table public.outreach_candidates drop constraint if exists outreach_candidates_review_source_check;
alter table public.outreach_candidates add constraint outreach_candidates_review_source_check
  check (review_source in ('SYSTEM', 'HUMAN_REVIEWED'));

-- Workflow 18 save. The system's own result is frozen in system_* and the metric columns;
-- a later human rewrite changes draft/status/review_source, never these.
create or replace function public.outreach_candidate_save(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare oc outreach_candidates%rowtype; c companies%rowtype; k contacts%rowtype; v_status text; v_title text; v_task uuid; u jsonb;
        v_in int := 0; v_out int := 0; v_cost numeric := 0; v_calls int := 0; v_rl boolean := false;
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
  end loop;
  v_status := case when p->>'qa_status' = 'PASS' and coalesce(p->>'draft', '') <> '' and lower(p->>'draft') !~ v_banned then 'READY' else 'REVIEW_REQUIRED' end;
  update outreach_candidates set subject = nullif(p->>'subject', ''), draft = p->>'draft', qa_status = p->>'qa_status', qa_issues = p->'qa_issues',
         system_subject = nullif(p->>'subject', ''), system_draft = p->>'draft', system_qa_status = p->>'qa_status', system_qa_issues = p->'qa_issues',
         first_pass_ok = (p->>'first_pass_ok')::boolean, redraft_ok = (p->>'redraft_ok')::boolean, rate_limited = v_rl,
         model_calls = v_calls, tokens_in = v_in, tokens_out = v_out, est_cost_usd = v_cost, review_source = 'SYSTEM', batch = p->>'batch',
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

-- Human-reviewed path: Adam (or Claude on Adam's instruction) replaces the draft and approves it.
-- The system_* columns and metrics stay as the system produced them.
create or replace function public.outreach_candidate_human_ready(p_candidate uuid, p_draft text, p_subject text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare oc outreach_candidates%rowtype; c companies%rowtype; k contacts%rowtype; v_task uuid; v_title text;
begin
  select * into oc from outreach_candidates where id = p_candidate;
  if oc.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if coalesce(btrim(p_draft), '') = '' then return jsonb_build_object('ok', false, 'reason', 'EMPTY_DRAFT'); end if;
  if oc.task_id is not null and exists (select 1 from tasks where id = oc.task_id and status in ('OPEN', 'IN_PROGRESS', 'WAITING')) then
    return jsonb_build_object('ok', false, 'reason', 'TASK_ALREADY_OPEN', 'task_id', oc.task_id); end if;
  select * into c from companies where id = oc.company_id;
  select * into k from contacts where id = oc.contact_id;
  v_title := case oc.channel when 'EMAIL' then 'EMAIL READY' when 'INSTAGRAM' then 'INSTAGRAM DM READY' else 'LINKEDIN MESSAGE READY' end
             || ' -- ' || c.name || coalesce(' · ' || nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), ''), '');
  insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
  values (oc.company_id, oc.contact_id, oc.opportunity_id, v_title,
          'Lane: ' || oc.lane || ' · Channel: ' || oc.channel || chr(10) ||
          coalesce('Why now: ' || oc.why_now || chr(10), '') ||
          'Draft source: HUMAN_REVIEWED (the workflow 18 draft did not pass; this version was rewritten from the recorded evidence and approved by Adam)' || chr(10) ||
          coalesce(p_note || chr(10), '') || chr(10) ||
          coalesce('Subject: ' || p_subject || chr(10) || chr(10), '') || p_draft || chr(10) || chr(10) ||
          'Send it yourself, then mark done (logs the send, books follow-ups). Dismiss = not sent.',
          'CONTACT_RESOLUTION', 'Adam', 'Human review (acceptance run)', 75, 'OPEN', now())
  returning id into v_task;
  update outreach_candidates set draft = p_draft, subject = p_subject, status = 'READY', review_source = 'HUMAN_REVIEWED',
         qa_status = 'HUMAN_REVIEWED', task_id = v_task, updated_at = now()
   where id = oc.id;
  return jsonb_build_object('ok', true, 'task_id', v_task);
end $$;

-- Hold or park a candidate with a reason and a concrete research task.
create or replace function public.outreach_candidate_hold(p_candidate uuid, p_status text, p_reason text, p_task_title text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare oc outreach_candidates%rowtype; v_task uuid;
begin
  if p_status not in ('HOLD', 'RESEARCH') then return jsonb_build_object('ok', false, 'reason', 'BAD_STATUS'); end if;
  select * into oc from outreach_candidates where id = p_candidate;
  if oc.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
  values (oc.company_id, oc.contact_id, oc.opportunity_id, p_task_title, p_reason, 'CONTACT_RESEARCH', 'Adam', 'Commercial Director (hold)', 60, 'OPEN', now() + interval '2 days')
  returning id into v_task;
  update outreach_candidates set status = p_status, hold_reason = p_reason, updated_at = now() where id = oc.id;
  return jsonb_build_object('ok', true, 'task_id', v_task);
end $$;
revoke all on function public.outreach_candidate_human_ready(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.outreach_candidate_hold(uuid, text, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- honest batch metrics
create or replace function public.engine_metrics(p_from date default current_date - 7, p_to date default current_date, p_batch text default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with oc as (select * from outreach_candidates where run_date between p_from and p_to and (p_batch is null or batch = p_batch)
                and system_qa_status is not null)
  select jsonb_build_object(
    'from', p_from, 'to', p_to, 'batch', p_batch,
    'drafted', count(*),
    'system_first_pass', count(*) filter (where first_pass_ok),
    'redraft_success', count(*) filter (where not coalesce(first_pass_ok, false) and redraft_ok),
    'system_ready', count(*) filter (where system_qa_status = 'PASS'),
    'system_ready_pct', case when count(*) > 0 then round(100.0 * count(*) filter (where system_qa_status = 'PASS') / count(*)) end,
    'evidence_failures', count(*) filter (where system_qa_issues::text ~ 'UNSUPPORTED|PRESUMPTUOUS'),
    'rate_limited', count(*) filter (where rate_limited),
    'review_required', count(*) filter (where system_qa_status <> 'PASS'),
    'final_ready_after_human_review', count(*) filter (where status in ('READY', 'SENT') and review_source = 'HUMAN_REVIEWED'),
    'avg_calls', round(avg(model_calls), 2), 'avg_tokens', round(avg(tokens_in + tokens_out)),
    'avg_cost_usd', round(avg(est_cost_usd), 5), 'total_cost_usd', round(sum(est_cost_usd), 4))
  from oc
$$;
revoke all on function public.engine_metrics(date, date, text) from public, anon, authenticated;

-- Dashboard: add the budget and the two pass-rate measurements.
create or replace function public.hq_execution()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  return jsonb_build_object('queue', queue_health(), 'weekly', commercial_weekly_metrics(6), 'hunter', hunter_roi(),
    'today', commercial_today(), 'ai_budget', ai_budget_status(), 'engine', engine_metrics(current_date - 30, current_date, null));
end $$;
revoke all on function public.hq_execution() from public, anon;
grant execute on function public.hq_execution() to authenticated;

-- ---------------------------------------------------------------- planner: refresh stale drafts (dry run only)
-- 59 hand-send drafts were waiting unsent on 7 Oct, most written under the older, weaker gate. In dry run the
-- planner may pick those accounts again so workflow 18 can re-draft them for comparison; it never touches the tasks.
insert into public.system_config (key, value) values ('planner_options', '{"refresh_stale_drafts": false}'::jsonb) on conflict (key) do nothing;
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
         and relationship_state(c.id) = 'COLD'
         -- never two agents on one company, never anything already queued or recently planned
         and not exists (select 1 from tasks t where t.company_id = c.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
                          and (t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|WHATSAPP MESSAGE READY|EMAIL READY|VERIFY FIRST|DRAFT REVIEW|FOLLOW UP)'
                               or t.task_type = 'SALES_OUTREACH_APPROVAL')
                          -- refresh (dry run only): an unsent hand-send draft older than 3 days may be re-drafted for comparison
                          and not (p_refresh and p_dry_run and t.title ~ '^(LINKEDIN MESSAGE READY|INSTAGRAM DM READY|EMAIL READY)'
                                   and t.created_at < now() - interval '3 days'))
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

revoke all on function public.commercial_director_plan(boolean, int, boolean) from public, anon, authenticated;

-- Budget hold: one alert task per day when the guardrail stops drafting.
create or replace function public.ai_budget_hold_alert(p_status text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b jsonb := ai_budget_status(); v_id uuid;
begin
  if b->>'status' not in ('HOLD', 'DAILY_HOLD') then return jsonb_build_object('ok', true, 'alert', false, 'budget', b); end if;
  if exists (select 1 from tasks where title like 'AI BUDGET HOLD --%' and created_at >= current_date) then
    return jsonb_build_object('ok', true, 'alert', false, 'reason', 'ALREADY_ALERTED_TODAY', 'budget', b); end if;
  insert into tasks (title, description, task_type, assigned_to, created_by, priority, status, due_at)
  values ('AI BUDGET HOLD -- outreach drafting paused (' || (b->>'status') || ')',
          'Workflow 18 did not draft today. Month to date: $' || (b->>'mtd_usd') || ' of the approved $' || (b->>'ceiling_usd') ||
          ' (target $' || (b->>'target_usd') || '). Today: $' || (b->>'today_usd') || '.' || chr(10) ||
          'Drafting resumes automatically tomorrow (daily hold) or next month (monthly ceiling). Raising the ceiling needs Adam''s approval.',
          'SYSTEM_ALERT', 'Adam', 'AI budget guardrail (workflow 18)', 90, 'OPEN', now())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'alert', true, 'task_id', v_id, 'budget', b);
end $$;
revoke all on function public.ai_budget_hold_alert(text) from public, anon, authenticated;

-- Discovery throttle: overdue tasks are already inside the other backlog counts (no double count), and a
-- paused throttle still researches 2 candidates per department per day so qualified supply keeps growing.
create or replace function public.discovery_context()
 returns jsonb language sql stable security definer set search_path to 'public' as $function$
  with b as (select * from commercial_backlog),
  cfg as (select value v from system_config where key = 'discovery_throttle'),
  tot as (select (approval_ready + contact_blocked + follow_ups_open) as n from b),
  dom as (
    select array_agg(distinct d) as ds from (
      select registrable_domain(website) d from companies where website is not null
      union
      select registrable_domain(split_part(email, '@', 2)) from contacts where email like '%@%'
    ) x where d is not null
  )
  select jsonb_build_object(
    'known_domains', coalesce((select to_jsonb(ds) from dom), '[]'::jsonb),
    'backlog', (select to_jsonb(b) from b) || jsonb_build_object('total', (select n from tot)),
    'throttle_level', case
        when (select n from tot) >= ((select v from cfg)->>'pause_at_backlog')::int then 'PAUSED'
        when (select n from tot) >= ((select v from cfg)->>'reduce_at_backlog')::int then 'REDUCED'
        else 'NORMAL' end,
    'research_cap', case
        when (select n from tot) >= ((select v from cfg)->>'pause_at_backlog')::int then ((select v from cfg)->>'paused_research_cap')::int
        when (select n from tot) >= ((select v from cfg)->>'reduce_at_backlog')::int then ((select v from cfg)->>'reduced_research_cap')::int
        else ((select v from cfg)->>'normal_research_cap')::int end,
    'generated_at', now()
  );
$function$;
update public.system_config set value = value || '{"paused_research_cap": 2}'::jsonb where key = 'discovery_throttle';
