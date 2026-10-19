-- NOYA professional operating mode (Adam, 18 Oct 2026), part 1: the CEO Command Centre read model.
-- Revenue reconciliation, the commercial funnel (15 stages), CEO work orders to the Directors and Director scorecards.
-- Additive only: new nullable columns, new functions, and one ORDER BY key added to each specialist queue so an open CEO work
-- order is worked first. Nothing is deleted. No value is invented: revenue only exists as an imported record with evidence.

-- ---------------------------------------------------------------- 1. Revenue: the fields Adam asked for
alter table public.revenue
  add column if not exists client_name text,
  add column if not exists project_name text,
  add column if not exists service text,
  add column if not exists director text,
  add column if not exists supplier_cost numeric check (supplier_cost is null or supplier_cost >= 0),
  add column if not exists evidence text,
  add column if not exists revenue_date date,
  add column if not exists historical boolean not null default false;
alter table public.revenue add column if not exists gross_profit numeric
  generated always as (case when supplier_cost is not null then amount - supplier_cost end) stored;
comment on column public.revenue.revenue_date is 'Date of the project or invoice. Period reports use this before received_at / created_at, so an imported historical row never lands in the week it was imported.';
comment on column public.revenue.historical is 'Imported by hq_revenue_import from Adam''s own records (evidence required on every row).';

-- Adam''s stated historical revenue is the reconciliation target, never a revenue record.
insert into public.system_config (key, value, note) values ('historical_revenue',
  jsonb_build_object('stated_amount', 60000, 'currency', 'GBP', 'period', 'about 18 months to October 2026',
                     'stated_by', 'Adam, CEO brief 18 Oct 2026', 'status', 'TO_BE_RECONCILED'),
  'Stated by Adam, not a revenue record. Actual revenue = imported rows with evidence (hq_revenue_import). HQ shows the gap as HISTORICAL REVENUE — TO BE RECONCILED.')
on conflict (key) do nothing;

-- Historical import: validate every row, refuse rows without evidence, skip duplicates, dry run by default.
create or replace function public.hq_revenue_import(p_rows jsonb, p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); r jsonb; i int := 0; v_ok jsonb := '[]'; v_err jsonb := '[]'; v_dup jsonb := '[]';
  v_client text; v_date date; v_amount numeric; v_paid numeric; v_cur text; v_status text; v_cost numeric; v_dir text; v_company uuid;
  v_id uuid; v_ev text; v_errs text[];
begin
  if jsonb_typeof(p_rows) is distinct from 'array' then return jsonb_build_object('ok', false, 'reason', 'ROWS_MUST_BE_A_LIST'); end if;
  if jsonb_array_length(p_rows) > 500 then return jsonb_build_object('ok', false, 'reason', 'TOO_MANY_ROWS', 'max', 500); end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1; v_errs := '{}'; v_cost := null; v_paid := null; v_date := null; v_amount := null; v_company := null;
    v_client := hq_trim(r->>'client'); v_ev := hq_trim(r->>'evidence');
    v_cur := upper(coalesce(hq_trim(r->>'currency'), '')); v_status := upper(coalesce(hq_trim(r->>'payment_status'), ''));
    v_dir := upper(hq_trim(r->>'director'));
    begin v_date := (r->>'date')::date; exception when others then v_errs := v_errs || 'date is not YYYY-MM-DD'::text; end;
    begin v_amount := (r->>'gross')::numeric; exception when others then v_errs := v_errs || 'gross is not a number'::text; end;
    begin v_cost := nullif(btrim(coalesce(r->>'supplier_cost', '')), '')::numeric; exception when others then v_errs := v_errs || 'supplier_cost is not a number'::text; end;
    begin v_paid := nullif(btrim(coalesce(r->>'amount_paid', '')), '')::numeric; exception when others then v_errs := v_errs || 'amount_paid is not a number'::text; end;
    if v_client is null then v_errs := v_errs || 'client missing'::text; end if;
    if v_date is null and nullif(btrim(coalesce(r->>'date', '')), '') is null then v_errs := v_errs || 'date missing'::text; elsif v_date > current_date then v_errs := v_errs || 'date is in the future'::text; end if;
    if (v_amount is null and nullif(btrim(coalesce(r->>'gross', '')), '') is null) or v_amount <= 0 then v_errs := v_errs || 'gross must be a positive amount'::text; end if;
    if v_cur !~ '^[A-Z]{3}$' then v_errs := v_errs || 'currency must be a 3-letter code (GBP, USD, EUR, EGP)'::text; end if;
    if v_status not in ('PAID', 'PART_PAID', 'PENDING') then v_errs := v_errs || 'payment_status must be PAID, PART_PAID or PENDING'::text; end if;
    if v_status = 'PART_PAID' and (v_paid is null or v_paid <= 0 or v_paid >= coalesce(v_amount, 0)) then
      v_errs := v_errs || 'PART_PAID needs amount_paid above 0 and below gross'::text; end if;
    if v_ev is null then v_errs := v_errs || 'evidence missing (invoice number, bank reference, contract or email)'::text; end if;
    if v_cost is not null and v_cost < 0 then v_errs := v_errs || 'supplier_cost cannot be negative'::text; end if;
    if v_dir is not null and not exists (select 1 from agent_registry where key = v_dir) then v_errs := v_errs || ('director ' || v_dir || ' is not a Director key')::text; end if;
    if coalesce(array_length(v_errs, 1), 0) > 0 then
      v_err := v_err || jsonb_build_object('row', i, 'client', v_client, 'errors', to_jsonb(v_errs)); continue;
    end if;
    if exists (select 1 from revenue x left join companies c on c.id = x.company_id
                where lower(coalesce(x.client_name, c.name, '')) = lower(v_client) and coalesce(x.revenue_date, x.received_at::date) = v_date
                  and x.amount = v_amount and x.currency = v_cur and x.payment_status <> 'CANCELLED') then
      v_dup := v_dup || jsonb_build_object('row', i, 'client', v_client, 'date', v_date, 'gross', v_amount, 'currency', v_cur); continue;
    end if;
    select c.id into v_company from companies c
     where company_name_key(c.name) = company_name_key(v_client) and coalesce(c.notes, '') not like '%MERGED_INTO:%' order by c.created_at limit 1;
    v_ok := v_ok || jsonb_build_object('row', i, 'client', v_client, 'company_id', v_company, 'project', hq_trim(r->>'project'), 'date', v_date,
              'service', hq_trim(r->>'service'), 'director', v_dir, 'gross', v_amount, 'currency', v_cur, 'supplier_cost', v_cost,
              'gross_profit', case when v_cost is not null then v_amount - v_cost end, 'payment_status', v_status, 'evidence', v_ev);
    if p_apply then
      insert into revenue (company_id, client_name, project_name, service, director, revenue_type, description, amount, currency, supplier_cost,
                           payment_status, invoice_status, revenue_date, received_at, source, source_category, evidence, invoice_reference, notes,
                           recorded_by, historical)
      values (v_company, v_client, hq_trim(r->>'project'), hq_trim(r->>'service'), v_dir, hq_trim(r->>'revenue_type'),
              coalesce(hq_trim(r->>'project'), hq_trim(r->>'service'), 'Historical revenue'), v_amount, v_cur, v_cost,
              v_status, case v_status when 'PAID' then 'PAID' when 'PART_PAID' then 'PART_PAID' else 'SENT' end,
              v_date, case when v_status = 'PAID' then v_date::timestamptz end, 'HISTORICAL_IMPORT', hq_trim(r->>'source'), v_ev,
              hq_trim(r->>'invoice_reference'), hq_trim(r->>'notes'), v_admin, true)
      returning id into v_id;
      if v_status in ('PAID', 'PART_PAID') then
        insert into revenue_payments (revenue_id, amount, currency, paid_at, method, reference, note, recorded_by)
        values (v_id, case when v_status = 'PAID' then v_amount else v_paid end, v_cur, v_date, 'HISTORICAL', v_ev, 'Historical import', v_admin);
      end if;
    end if;
  end loop;
  if p_apply and jsonb_array_length(v_ok) > 0 then
    perform hq_audit('REVENUE_HISTORICAL_IMPORT', null, jsonb_build_object('rows', jsonb_array_length(v_ok), 'duplicates', jsonb_array_length(v_dup),
                                                                         'errors', jsonb_array_length(v_err)));
  end if;
  return jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'applied', p_apply and jsonb_array_length(v_ok) > 0,
    'valid', v_ok, 'errors', v_err, 'duplicates', v_dup,
    'totals', coalesce((select jsonb_object_agg(cur, amt) from (select x->>'currency' cur, sum((x->>'gross')::numeric) amt
                                                               from jsonb_array_elements(v_ok) x group by 1) t), '{}'::jsonb));
end $$;

-- ---------------------------------------------------------------- 2. Opportunity discipline: owner, next action, date, blocker
alter table public.opportunities add column if not exists blocker text;
comment on column public.opportunities.blocker is 'What stops this opportunity moving (set in HQ). Shown on the commercial funnel.';

create or replace function public.hq_opportunity_plan(p_opportunity uuid, p_next_action text, p_due date, p_owner text default null,
                                                      p_blocker text default null, p_clear_blocker boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); o opportunities%rowtype;
begin
  if p_due is not null and p_due < (now() at time zone 'Africa/Cairo')::date - 1 then return jsonb_build_object('ok', false, 'reason', 'DATE_IN_PAST'); end if;
  update opportunities set next_action = coalesce(hq_trim(p_next_action), next_action), next_action_due = coalesce(p_due, next_action_due),
         owner = coalesce(hq_trim(p_owner), owner),
         blocker = case when p_clear_blocker then null else coalesce(hq_trim(p_blocker), blocker) end, updated_at = now()
   where id = p_opportunity returning * into o;
  if o.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  perform hq_audit('OPPORTUNITY_PLAN', o.id, jsonb_build_object('next_action', o.next_action, 'due', o.next_action_due, 'owner', o.owner, 'blocker', o.blocker));
  return jsonb_build_object('ok', true, 'id', o.id);
end $$;

-- ---------------------------------------------------------------- 3. CEO work orders (existing tasks table, task_type WORK_ORDER)
alter table public.tasks add column if not exists spec jsonb;
comment on column public.tasks.spec is 'Structured detail for WORK_ORDER and IMPROVEMENT tasks (director, mission, target terms, metric, goal, deadline, baseline, outcome).';

-- A target term as a case-insensitive pattern; common market words expand, everything else is matched literally.
create or replace function public.work_order_term_re(p text)
returns text language sql immutable set search_path = public as $$
  select case lower(btrim(p))
    when 'uk' then '(\muk\M|united kingdom|england|london|scotland|wales|manchester)'
    when 'united kingdom' then '(\muk\M|united kingdom|england|london|scotland|wales|manchester)'
    when 'us' then '(united states|\musa\M|\mus\M|new york|los angeles|miami)'
    when 'usa' then '(united states|\musa\M|\mus\M|new york|los angeles|miami)'
    when 'uae' then '(united arab emirates|\muae\M|dubai|abu dhabi)'
    when 'ksa' then '(saudi|riyadh|jeddah)'
    when 'gcc' then '(united arab emirates|\muae\M|dubai|abu dhabi|saudi|riyadh|jeddah|qatar|doha|kuwait|bahrain|oman)'
    when 'europe' then '(united kingdom|\muk\M|france|italy|spain|greece|germany|switzerland|portugal|netherlands|monaco|austria|belgium|sweden|denmark|ireland)'
    when 'jewellery' then 'jewel' when 'jewelry' then 'jewel'
    else regexp_replace(lower(btrim(p)), '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') end
$$;

-- The Director's companies that match every target term (name, type, sector, country, city, segment, research notes).
create or replace function public.work_order_companies(p_spec jsonb)
returns table (company_id uuid) language sql stable set search_path = public as $$
  select c.id from companies c
   where coalesce(c.notes, '') not like '%MERGED_INTO:%'
     and coalesce(c.universe_status, '') not in ('EXCLUDED', 'PARKED')
     and (p_spec->>'director' is null
          or agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) = p_spec->>'director')
     and not exists (select 1 from jsonb_array_elements_text(coalesce(p_spec->'terms', '[]'::jsonb)) t(term)
                      where btrim(t.term) <> ''
                        and lower(concat_ws(' ', c.name, c.company_type, c.sector, c.country, c.city, c.prospect_segment, c.universe_reason, c.notes))
                            !~ work_order_term_re(t.term))
$$;

-- Companies under an open work order. The specialist queues and the planner put these first.
create or replace function public.work_order_targets()
returns table (company_id uuid, task_id uuid, priority int) language sql stable set search_path = public as $$
  select distinct on (w.company_id) w.company_id, t.id, coalesce(t.priority, 50)::int
    from tasks t cross join lateral work_order_companies(t.spec) w
   where t.task_type = 'WORK_ORDER' and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and t.spec is not null
   order by w.company_id, coalesce(t.priority, 50) desc
$$;

-- Status from evidence only: QUEUED until the Director has run; WORKING while the pipeline moves the targets; WAITING when only
-- Adam's review or send is outstanding; COMPLETE at the goal; BLOCKED with the reason (no match, workflow not running, deadline).
create or replace function public.work_order_eval(p_task uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t tasks%rowtype; s jsonb; v_since timestamptz; v_dir text; v_last timestamptz; v_gap numeric; m jsonb; v_goal int; v_metric text;
  v_res int; v_status text; v_blocker text; v_note text; v_name text; v_act int; v_wait int; v_accepted timestamptz;
begin
  select * into t from tasks where id = p_task and task_type = 'WORK_ORDER';
  if t.id is null then return null; end if;
  s := coalesce(t.spec, '{}'::jsonb); v_since := coalesce((s->>'issued_at')::timestamptz, t.created_at); v_dir := s->>'director';
  v_goal := greatest(coalesce((s->>'goal')::int, 1), 1); v_metric := coalesce(s->>'metric', 'EMAILS_SENT');
  select r.name, r.max_gap_hours into v_name, v_gap from agent_registry r where r.key = v_dir;
  v_last := director_last_run(v_dir);
  with mc as materialized (select company_id from work_order_companies(s))
  select jsonb_build_object(
    'matched', (select count(*) from mc),
    'qualified', (select count(*) from companies c join mc on mc.company_id = c.id where c.universe_status = 'QUALIFIED'),
    'new_qualified', (select count(*) from companies c join mc on mc.company_id = c.id where c.universe_status = 'QUALIFIED' and c.universe_added_at >= v_since),
    'people_found', (select count(*) from contacts k join mc on mc.company_id = k.company_id where k.created_at >= v_since and k.identity_status = 'CONFIRMED'),
    'email_research', (select count(distinct er.company_id) from email_research er join mc on mc.company_id = er.company_id where er.researched_at >= v_since),
    'verified', (select count(*) from contact_email_verifications v join mc on mc.company_id = v.company_id where v.created_at >= v_since and v.provider_result = 'deliverable'),
    'email_ready', (select count(*) from mc where company_email_state(mc.company_id)->>'state' in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX')),
    'drafted', (select count(*) from outreach_candidates oc join mc on mc.company_id = oc.company_id where not oc.dry_run and oc.created_at >= v_since and oc.draft is not null),
    'in_review', (select count(*) from outreach_candidates oc join mc on mc.company_id = oc.company_id where not oc.dry_run and oc.channel = 'EMAIL' and oc.status in ('READY', 'REVIEW_REQUIRED')),
    'gmail_drafts', (select count(*) from outbound_emails ob join mc on mc.company_id = ob.company_id where ob.status = 'DRAFTED'),
    'sent', (select count(distinct i.company_id) from interactions i join mc on mc.company_id = i.company_id where i.direction = 'OUTBOUND' and i.channel = 'EMAIL' and i.occurred_at >= v_since),
    'replies', (select count(distinct i.company_id) from interactions i join mc on mc.company_id = i.company_id where i.direction = 'INBOUND' and i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM') and i.occurred_at >= v_since),
    'positive', (select count(distinct i.company_id) from interactions i join mc on mc.company_id = i.company_id where i.direction = 'INBOUND' and i.occurred_at >= v_since
                   and coalesce(i.summary, '') ~ '^(POSITIVE|MEETING_REQUEST|NEEDS_INFO|REFERRAL)'),
    'meetings', (select count(distinct x.company_id) from (
                   select i.company_id from interactions i join mc on mc.company_id = i.company_id where i.channel = 'MEETING' and i.occurred_at >= v_since
                   union all select k.company_id from tasks k join mc on mc.company_id = k.company_id where k.task_type = 'MEETING_ACTION' and k.created_at >= v_since
                   union all select o.company_id from opportunities o join mc on mc.company_id = o.company_id where o.status = 'CALL_REQUIRED' and o.updated_at >= v_since) x),
    'proposals', (select count(*) from opportunities o join mc on mc.company_id = o.company_id where o.status in ('PROPOSAL', 'NEGOTIATION') and o.updated_at >= v_since),
    'wins', (select count(*) from opportunities o join mc on mc.company_id = o.company_id where o.won_at >= v_since))
  into m;
  v_res := case v_metric
    when 'QUALIFIED_TARGETS' then (m->>'new_qualified')::int
    when 'EMAIL_READY' then greatest(0, (m->>'email_ready')::int - coalesce((s->>'baseline_email_ready')::int, 0))
    when 'REPLIES' then (m->>'replies')::int when 'MEETINGS' then (m->>'meetings')::int
    when 'PROPOSALS' then (m->>'proposals')::int when 'WINS' then (m->>'wins')::int
    else (m->>'sent')::int end;
  v_act := (m->>'new_qualified')::int + (m->>'people_found')::int + (m->>'email_research')::int + (m->>'verified')::int + (m->>'drafted')::int + (m->>'sent')::int;
  v_wait := (m->>'in_review')::int + (m->>'gmail_drafts')::int;
  v_accepted := coalesce((s->>'accepted_at')::timestamptz, case when v_last >= v_since then v_last end);
  if t.status = 'CANCELLED' then v_status := 'CANCELLED'; v_note := coalesce(s->>'outcome', 'Cancelled');
  elsif t.status = 'COMPLETED' or v_res >= v_goal then v_status := 'COMPLETE';
    v_note := coalesce(s->>'outcome', v_res || ' of ' || v_goal || ' achieved');
  elsif (m->>'matched')::int = 0 then v_status := 'BLOCKED';
    v_blocker := 'No company in ' || coalesce(v_name, v_dir) || '''s universe matches "' || coalesce((select string_agg(x, ', ') from jsonb_array_elements_text(s->'terms') x), 'the target')
      || '" yet. New discovery for this target needs the Director''s search bank widened (n8n), or a broader target.';
  elsif v_last is null or v_last < now() - make_interval(hours => coalesce(v_gap, 26)::int) then v_status := 'BLOCKED';
    v_blocker := coalesce(v_name, v_dir) || '''s workflow has not run since ' || coalesce(to_char(v_last at time zone 'Africa/Cairo', 'DD Mon HH24:MI'), 'it was registered')
      || ': it is not running on schedule.';
  elsif (s->>'deadline')::date < (now() at time zone 'Africa/Cairo')::date then v_status := 'BLOCKED';
    v_blocker := 'Deadline ' || to_char((s->>'deadline')::date, 'DD Mon') || ' passed at ' || v_res || ' of ' || v_goal || '.';
  elsif v_accepted is null and v_act = 0 then v_status := 'QUEUED';
    v_note := 'Accepted at ' || coalesce(v_name, v_dir) || '''s next run; the specialist queues already put these ' || (m->>'matched') || ' companies first.';
  elsif v_wait > 0 and v_metric in ('EMAILS_SENT', 'REPLIES', 'MEETINGS') then v_status := 'WAITING';
    v_note := 'Waiting for you: ' || concat_ws(' · ', case when (m->>'in_review')::int > 0 then (m->>'in_review') || ' email' || case when (m->>'in_review')::int = 1 then '' else 's' end || ' to review' end,
                                                     case when (m->>'gmail_drafts')::int > 0 then (m->>'gmail_drafts') || ' Gmail draft' || case when (m->>'gmail_drafts')::int = 1 then '' else 's' end || ' to send' end) || '.';
  else v_status := 'WORKING';
    v_note := 'In the pipeline: ' || (m->>'matched') || ' matching companies, ' || (m->>'email_ready') || ' email-ready, ' || (m->>'drafted') || ' drafted since issue.';
  end if;
  return jsonb_build_object('id', t.id, 'director', v_dir, 'director_name', v_name, 'mission', s->>'mission', 'terms', s->'terms', 'metric', v_metric,
    'goal', v_goal, 'result', v_res, 'deadline', s->>'deadline', 'priority', s->>'priority', 'issued_at', v_since, 'accepted_at', v_accepted,
    'director_last_run', v_last, 'status', v_status, 'blocker', v_blocker, 'note', v_note, 'outcome', s->>'outcome', 'completed_at', t.completed_at, 'results', m);
end $$;

create or replace function public.hq_work_order(p_director text, p_mission text, p_target text, p_metric text, p_goal integer, p_deadline date, p_priority text default 'P2')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_name text; v_terms jsonb; v_spec jsonb; v_id uuid; v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  select r.name into v_name from agent_registry r where r.key = upper(btrim(p_director)) and r.v3_role = 'DIRECTOR' and r.kind = 'ACQUISITION';
  if v_name is null then return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_DIRECTOR'); end if;
  if length(coalesce(btrim(p_mission), '')) < 5 or length(p_mission) > 300 then return jsonb_build_object('ok', false, 'reason', 'MISSION_LENGTH'); end if;
  if coalesce(p_metric, '') not in ('QUALIFIED_TARGETS', 'EMAIL_READY', 'EMAILS_SENT', 'REPLIES', 'MEETINGS', 'PROPOSALS', 'WINS') then
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_METRIC'); end if;
  if p_goal is null or p_goal < 1 or p_goal > 500 then return jsonb_build_object('ok', false, 'reason', 'GOAL_RANGE'); end if;
  if p_deadline is null or p_deadline < v_today or p_deadline > v_today + 90 then return jsonb_build_object('ok', false, 'reason', 'DEADLINE_RANGE'); end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_terms
    from (select btrim(s.term) x from regexp_split_to_table(coalesce(p_target, ''), '\s*,\s*') as s(term) where btrim(s.term) <> '' limit 5) q;
  v_spec := jsonb_build_object('director', upper(btrim(p_director)), 'mission', btrim(p_mission), 'target', hq_trim(p_target), 'terms', v_terms,
    'metric', p_metric, 'goal', p_goal, 'deadline', p_deadline, 'priority', coalesce(nullif(upper(btrim(p_priority)), ''), 'P2'),
    'issued_at', now(), 'issued_by', v_admin);
  v_spec := v_spec || jsonb_build_object('baseline_email_ready', (select count(*) from work_order_companies(v_spec) w
    where company_email_state(w.company_id)->>'state' in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX')));
  insert into tasks (title, description, task_type, assigned_to, created_by, priority, status, due_at, spec)
  values ('WORK ORDER -- ' || v_name || ': ' || btrim(p_mission),
          'CEO work order. Target: ' || coalesce(hq_trim(p_target), 'the Director''s universe') || '. Result wanted: ' || p_goal || ' ' || lower(replace(p_metric, '_', ' '))
            || ' by ' || to_char(p_deadline, 'DD Mon YYYY') || '. Status is computed from evidence (work_order_eval).',
          'WORK_ORDER', upper(btrim(p_director)), 'Adam (HQ)',
          case v_spec->>'priority' when 'P1' then 90 when 'P3' then 40 else 65 end, 'WAITING',
          ((p_deadline + 1)::timestamp at time zone 'Africa/Cairo') - interval '1 second', v_spec)
  returning id into v_id;
  perform hq_audit('WORK_ORDER_ISSUED', null, jsonb_build_object('task_id', v_id) || v_spec);
  return jsonb_build_object('ok', true, 'id', v_id, 'work_order', work_order_eval(v_id));
end $$;

create or replace function public.hq_work_order_action(p_id uuid, p_action text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); t tasks%rowtype; e jsonb;
begin
  select * into t from tasks where id = p_id and task_type = 'WORK_ORDER';
  if t.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if t.status in ('COMPLETED', 'CANCELLED') then return jsonb_build_object('ok', false, 'reason', 'ALREADY_CLOSED'); end if;
  if upper(p_action) not in ('CANCEL', 'CLOSE') then return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION'); end if;
  e := work_order_eval(p_id);
  update tasks set status = case when upper(p_action) = 'CANCEL' then 'CANCELLED' else 'COMPLETED' end, completed_at = now(), updated_at = now(),
         spec = spec || jsonb_build_object('outcome', coalesce(hq_trim(p_note), case when upper(p_action) = 'CANCEL' then 'Cancelled by Adam' else 'Closed by Adam' end)
                                           || ' at ' || (e->>'result') || ' of ' || (e->>'goal') || '.', 'final_results', e->'results', 'closed_by', v_admin)
   where id = p_id;
  perform hq_audit('WORK_ORDER_' || upper(p_action), null, jsonb_build_object('task_id', p_id, 'result', e->'result', 'goal', e->'goal'));
  return jsonb_build_object('ok', true);
end $$;

-- Every 30 minutes: record when a Director first ran after the order (acceptance) and close orders that reached their goal.
create or replace function public.work_orders_refresh()
returns integer language plpgsql security definer set search_path = public as $$
declare t record; e jsonb; n int := 0;
begin
  for t in select id, spec from tasks where task_type = 'WORK_ORDER' and status in ('OPEN', 'IN_PROGRESS', 'WAITING') loop
    e := work_order_eval(t.id);
    if t.spec->>'accepted_at' is null and e->>'accepted_at' is not null then
      update tasks set spec = spec || jsonb_build_object('accepted_at', e->'accepted_at'), updated_at = now() where id = t.id;
    end if;
    if e->>'status' = 'COMPLETE' then
      update tasks set status = 'COMPLETED', completed_at = now(), updated_at = now(),
             spec = spec || jsonb_build_object('outcome', 'Goal reached: ' || (e->>'result') || ' of ' || (e->>'goal') || '.', 'final_results', e->'results')
       where id = t.id;
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------- 4. Specialist queues: open work orders first; Adam's lane order
-- Priority order (Adam, 18 Oct): Brand / Production, Weddings / Private Events, Media / Podcasts, Travel / Concierge, Hospitality,
-- NOYA Private. Member and founder communities are opportunistic. Each patch must apply exactly once or the migration stops.
create or replace function pg_temp.patch(p_fn regprocedure, p_pairs text[]) returns void language plpgsql as $$
declare d text := pg_get_functiondef(p_fn); i int; n int;
begin
  for i in 1 .. array_length(p_pairs, 1) / 2 loop
    n := (length(d) - length(replace(d, p_pairs[2 * i - 1], ''))) / length(p_pairs[2 * i - 1]);
    if n <> 1 then raise exception 'patch % #%: expected 1 match, found %', p_fn, i, n; end if;
    d := replace(d, p_pairs[2 * i - 1], p_pairs[2 * i]);
  end loop;
  execute d;
end $$;

select pg_temp.patch('public.enrichment_queue(integer)'::regprocedure, array[
  'order by (c.universe_status = ''QUALIFIED'') desc,',
  'order by (c.id in (select w.company_id from work_order_targets() w)) desc, (c.universe_status = ''QUALIFIED'') desc,',
  'case l.lane when ''PARTNERSHIPS'' then 3 when ''WEDDINGS'' then 2 when ''BRANDS'' then 2',
  'case l.lane when ''BRANDS'' then 3 when ''WEDDINGS'' then 2.5 when ''PARTNERSHIPS'' then 1.5',
  'array_position(array[''PARTNERSHIPS'',''WEDDINGS'',''BRANDS'',''TRAVEL_PRIVATE'',''CORPORATE'',''EGYPT_EVENTS'',''SPORTS_PRIVATE''], l.lane)',
  'array_position(array[''BRANDS'',''WEDDINGS'',''TRAVEL_PRIVATE'',''PARTNERSHIPS'',''SPORTS_PRIVATE'',''CORPORATE'',''EGYPT_EVENTS''], l.lane)']);

select pg_temp.patch('public.email_gap_list(integer,text,boolean)'::regprocedure, array[
  '(select * from ranked order by score desc, created_at desc limit',
  '(select * from ranked order by (id in (select w.company_id from work_order_targets() w)) desc, score desc, created_at desc limit',
  'order by x.score desc, x.created_at desc) from',
  'order by (x.id in (select w.company_id from work_order_targets() w)) desc, x.score desc, x.created_at desc) from']);

select pg_temp.patch('public.email_verification_queue(integer)'::regprocedure, array[
  'row_number() over (order by q.draft_waiting desc, q.src,',
  'row_number() over (order by q.draft_waiting desc, (q.company_id in (select w.company_id from work_order_targets() w)) desc, q.src,',
  'array[''BRANDS'', ''WEDDINGS'', ''TRAVEL'', ''SPORTS'', ''HOSPITALITY'', ''CORPORATE'', ''PRIVATE'', ''MEDIA'', ''EGYPT''], q.agent',
  'array[''BRANDS'', ''WEDDINGS'', ''MEDIA'', ''TRAVEL'', ''HOSPITALITY'', ''SPORTS'', ''PRIVATE'', ''CORPORATE'', ''EGYPT''], q.agent']);

select pg_temp.patch('public.email_finder_queue(integer)'::regprocedure, array[
  'order by (route_state = ''FINDER_PENDING'') desc, cohort desc,',
  'order by (route_state = ''FINDER_PENDING'') desc, (company_id in (select w.company_id from work_order_targets() w)) desc, cohort desc,',
  'array[''BRANDS'', ''WEDDINGS'', ''TRAVEL'', ''SPORTS'', ''HOSPITALITY'', ''CORPORATE'', ''PRIVATE'', ''MEDIA'', ''EGYPT''], agent',
  'array[''BRANDS'', ''WEDDINGS'', ''MEDIA'', ''TRAVEL'', ''HOSPITALITY'', ''SPORTS'', ''PRIVATE'', ''CORPORATE'', ''EGYPT''], agent']);

select pg_temp.patch('public.commercial_director_plan(boolean,integer,boolean)'::regprocedure, array[
  'row_number() over (partition by p.lane order by (p.channel = ''EMAIL'') desc, (p.k_id is not null) desc,',
  'row_number() over (partition by p.lane order by (p.channel = ''EMAIL'') desc, (p.company_id in (select w.company_id from work_order_targets() w)) desc, (p.k_id is not null) desc,',
  'order by (p.channel = ''EMAIL'') desc, (p.warm is not null) desc, (p.k_id is not null) desc,',
  'order by (p.channel = ''EMAIL'') desc, (p.company_id in (select w.company_id from work_order_targets() w)) desc, (p.warm is not null) desc, (p.k_id is not null) desc,',
  'order by array_position(array[''BRANDS'', ''WEDDINGS'', ''TRAVEL_PRIVATE'', ''PARTNERSHIPS'', ''SPORTS_PRIVATE'', ''CORPORATE''], p.lane) nulls last, p.rn',
  'order by (p.company_id in (select w.company_id from work_order_targets() w)) desc, array_position(array[''BRANDS'', ''WEDDINGS'', ''TRAVEL_PRIVATE'', ''PARTNERSHIPS'', ''SPORTS_PRIVATE'', ''CORPORATE''], p.lane) nulls last, p.rn',
  'order by (x.warm_route is not null) desc,',
  'order by (x.warm_route is not null) desc, (x.company_id in (select w.company_id from work_order_targets() w)) desc,',
  'array[''BRANDS'', ''WEDDINGS'', ''TRAVEL_PRIVATE'', ''SPORTS_PRIVATE'', ''PARTNERSHIPS'', ''CORPORATE'', ''EGYPT_EVENTS''], x.lane',
  'array[''BRANDS'', ''WEDDINGS'', ''TRAVEL_PRIVATE'', ''PARTNERSHIPS'', ''SPORTS_PRIVATE'', ''CORPORATE'', ''EGYPT_EVENTS''], x.lane']);

-- Period revenue uses the revenue date, so an imported historical row never counts as this week's revenue.
select pg_temp.patch('public.hq_ceo_dashboard()'::regprocedure, array[
  'where coalesce(received_at, created_at) >= per.since',
  'where coalesce(revenue_date::timestamptz, received_at, created_at) >= per.since']);

-- ---------------------------------------------------------------- 5. Director scorecards (7 days, 30 days, all time)
-- Commercial results only: no credit for searches or contacts added. Rates need at least 20 first messages; below that the
-- Director is marked "insufficient data" and never ranked.
create or replace function public.director_scorecards()
returns jsonb language sql stable security definer set search_path = public as $$
  with co as materialized (
    select c.id, agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) dir,
           c.universe_status, c.universe_added_at
      from companies c where coalesce(c.notes, '') not like '%MERGED_INTO:%'),
  dirs as (select key, name, sort from agent_registry where v3_role = 'DIRECTOR' and kind = 'ACQUISITION'),
  per(p, since) as (values ('d7', now() - interval '7 days'), ('d30', now() - interval '30 days'), ('all', '-infinity'::timestamptz)),
  so as materialized (  -- first message of each sequence; follow-ups never count
    select i.company_id, i.channel, i.occurred_at from interactions i
     where i.direction = 'OUTBOUND' and i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM') and i.company_id is not null
       and not exists (select 1 from interactions e where e.company_id = i.company_id and e.channel = i.channel and e.direction = 'OUTBOUND'
                        and e.occurred_at < i.occurred_at and e.occurred_at > i.occurred_at - interval '120 days')),
  gt as materialized (
    select t.company_id, t.last_inbound_at, t.relationship_state from gmail_history_threads t
     where t.company_id is not null and t.inbound > 0 and t.outbound > 0 and coalesce(t.relevant, true) and coalesce(t.hq_status, '') <> 'DISMISSED'),
  rp as materialized (
    select i.company_id, i.occurred_at at_, coalesce(i.summary, '') ~ '^(POSITIVE|MEETING_REQUEST|NEEDS_INFO|REFERRAL)' pos
      from interactions i where i.direction = 'INBOUND' and i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM') and i.company_id is not null
    union all select gt.company_id, gt.last_inbound_at, gt.relationship_state = 'MEETING' from gt where gt.last_inbound_at is not null
    union all select o.company_id, o.updated_at, true from opportunities o where o.status in ('INTERESTED', 'CALL_REQUIRED')),
  mt as materialized (
    select i.company_id, i.occurred_at at_ from interactions i where i.channel = 'MEETING' and i.company_id is not null
    union all select t.company_id, t.created_at from tasks t where t.company_id is not null and (t.task_type = 'MEETING_ACTION' or t.title like 'MEETING --%')
    union all select o.company_id, o.updated_at from opportunities o where o.status = 'CALL_REQUIRED'
    union all select gt.company_id, gt.last_inbound_at from gt where gt.relationship_state = 'MEETING'),
  br as materialized (  -- briefs / concepts that reached the counterpart
    select s.company_id, s.sent_at at_ from studio_outputs s where s.level >= 2 and s.sent_at is not null and s.company_id is not null
    union all select cc.company_id, cc.created_at from creative_concepts cc where cc.status = 'USED' and cc.company_id is not null
    union all select p.company_id, p.created_at from projects p where p.brief is not null and p.company_id is not null),
  cov as (select coalesce((select payload->'coverage' from hq_read_cache where key = 'advisor'), '{}'::jsonb) j),
  card as (
    select d.key, per.p, jsonb_build_object(
      'qualified', (select count(*) from co where co.dir = d.key and co.universe_status = 'QUALIFIED' and co.universe_added_at >= per.since),
      'sent_email', (select count(*) from so join co on co.id = so.company_id where co.dir = d.key and so.channel = 'EMAIL' and so.occurred_at >= per.since),
      'sent_other', (select count(*) from so join co on co.id = so.company_id where co.dir = d.key and so.channel <> 'EMAIL' and so.occurred_at >= per.since),
      'replies', (select count(distinct rp.company_id) from rp join co on co.id = rp.company_id where co.dir = d.key and rp.at_ >= per.since),
      'positive', (select count(distinct rp.company_id) from rp join co on co.id = rp.company_id where co.dir = d.key and rp.pos and rp.at_ >= per.since),
      'meetings', (select count(distinct mt.company_id) from mt join co on co.id = mt.company_id where co.dir = d.key and mt.at_ >= per.since),
      'briefs', (select count(distinct br.company_id) from br join co on co.id = br.company_id where co.dir = d.key and br.at_ >= per.since),
      'proposals', (select count(*) from opportunities o join co on co.id = o.company_id where co.dir = d.key and o.status in ('PROPOSAL', 'NEGOTIATION') and o.updated_at >= per.since),
      'wins', (select count(*) from opportunities o join co on co.id = o.company_id where co.dir = d.key and o.won_at >= per.since),
      'revenue', (select coalesce(jsonb_object_agg(currency, amt), '{}'::jsonb) from (
                    select r.currency, sum(r.amount) amt from revenue r left join co on co.id = r.company_id
                     where coalesce(r.director, co.dir) = d.key and r.payment_status <> 'CANCELLED'
                       and coalesce(r.revenue_date::timestamptz, r.received_at, r.created_at) >= per.since group by 1) x)) j
      from dirs d cross join per),
  card2 as (
    select key, p, j || jsonb_build_object('sent', (j->>'sent_email')::int + (j->>'sent_other')::int,
      'reply_rate_pct', case when (j->>'sent_email')::int + (j->>'sent_other')::int >= 20
                             then round(100.0 * (j->>'replies')::int / ((j->>'sent_email')::int + (j->>'sent_other')::int)) end,
      'sample', case when (j->>'sent_email')::int + (j->>'sent_other')::int >= 20 then 'OK' else 'INSUFFICIENT' end) j
      from card)
  select jsonb_build_object(
    'min_sample', 20,
    'directors', (select jsonb_agg(jsonb_build_object('key', d.key, 'name', d.name,
        'd7', (select j from card2 where card2.key = d.key and p = 'd7'), 'd30', (select j from card2 where card2.key = d.key and p = 'd30'),
        'all', (select j from card2 where card2.key = d.key and p = 'all'),
        'coverage', (select cov.j->d.key from cov)) order by d.sort) from dirs d),
    'ranking_d30', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'reply_rate_pct', j->'reply_rate_pct', 'sent', j->'sent')
                                              order by (j->>'reply_rate_pct')::numeric desc), '[]'::jsonb)
                      from card2 where p = 'd30' and j->>'sample' = 'OK'),
    'method', 'Sent = first messages of a sequence (follow-ups excluded). Replies, positive and meetings count companies. Briefs = Studio Level 2 or 3 documents actually sent, concepts used with the counterpart and project briefs. Rates and rankings only from 20 first messages in the window; below that: insufficient data. Email coverage is the current verified-email coverage from the Advisor read.')
$$;

-- ---------------------------------------------------------------- 6. hq_command: the CEO Command Centre read (cached as 'command')
create or replace function public.hq_command()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb; v_ceo jsonb; v_hist jsonb; v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  v_ceo := coalesce((select payload from hq_read_cache where key = 'ceo'), '{}'::jsonb);
  v_hist := coalesce((select value from system_config where key = 'historical_revenue'), '{}'::jsonb);
  with
  co as materialized (
    select c.id, c.name, c.universe_status,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) dir
      from companies c where coalesce(c.notes, '') not like '%MERGED_INTO:%'),
  gt as materialized (
    select t.company_id, t.last_at, t.relationship_state from gmail_history_threads t
     where t.company_id is not null and t.inbound > 0 and t.outbound > 0 and coalesce(t.relevant, true) and coalesce(t.hq_status, '') <> 'DISMISSED'),
  ev as materialized (
    select co.id, co.name, co.dir, co.universe_status,
      exists (select 1 from opportunities o where o.company_id = co.id and o.status not in ('LOST', 'ARCHIVED', 'LONG_TERM')) open_opp,
      exists (select 1 from opportunities o where o.company_id = co.id) any_opp,
      exists (select 1 from revenue r left join projects p on p.id = r.project_id where coalesce(r.company_id, p.company_id) = co.id and r.payment_status = 'PAID') paid,
      exists (select 1 from projects p where p.company_id = co.id and p.status in ('DELIVERED', 'CLOSED')) proj_done,
      exists (select 1 from projects p where p.company_id = co.id and p.status in ('CONFIRMED', 'PLANNING', 'LIVE')) proj_active,
      exists (select 1 from opportunities o where o.company_id = co.id and o.status = 'WON') won,
      exists (select 1 from opportunities o where o.company_id = co.id and o.status = 'NEGOTIATION') nego,
      exists (select 1 from opportunities o where o.company_id = co.id and o.status = 'PROPOSAL') prop,
      exists (select 1 from studio_outputs s where s.company_id = co.id and s.level >= 2 and s.sent_at is not null)
        or exists (select 1 from creative_concepts cc where cc.company_id = co.id and cc.status = 'USED')
        or exists (select 1 from projects p where p.company_id = co.id and p.brief is not null) brief,
      exists (select 1 from gt where gt.company_id = co.id and gt.relationship_state = 'MEETING')
        or exists (select 1 from interactions i where i.company_id = co.id and i.channel = 'MEETING')
        or exists (select 1 from opportunities o where o.company_id = co.id and o.status = 'CALL_REQUIRED')
        or exists (select 1 from tasks t where t.company_id = co.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and (t.task_type = 'MEETING_ACTION' or t.title like 'MEETING --%')) meeting,
      exists (select 1 from opportunities o where o.company_id = co.id and o.status = 'INTERESTED')
        or exists (select 1 from interactions i where i.company_id = co.id and i.direction = 'INBOUND' and coalesce(i.summary, '') ~ '^(POSITIVE|MEETING_REQUEST|NEEDS_INFO|REFERRAL)') positive,
      exists (select 1 from gt where gt.company_id = co.id)
        or exists (select 1 from interactions i where i.company_id = co.id and i.direction = 'INBOUND' and i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM')) replied,
      exists (select 1 from interactions i where i.company_id = co.id and i.direction = 'OUTBOUND' and i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM'))
        or exists (select 1 from opportunities o where o.company_id = co.id and o.status in ('CONTACTED', 'FOLLOW_UP')) outreach,
      co.universe_status = 'QUALIFIED' and company_email_state(co.id)->>'state' in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX') contact_ready,
      greatest((select max(i.occurred_at) from interactions i where i.company_id = co.id and i.channel <> 'WEBSITE'),
               (select max(gt.last_at) from gt where gt.company_id = co.id),
               (select max(o.updated_at) from opportunities o where o.company_id = co.id)) last_at
      from co),
  stg as materialized (
    select ev.*, case
        when paid then 14 when proj_done then 13 when proj_active then 12 when won then 11 when nego then 10 when prop then 9
        when not (meeting or positive) and ((any_opp and not open_opp) or coalesce(universe_status, '') in ('PARKED', 'EXCLUDED')) then 0
        when brief and (replied or positive or meeting) then 8
        when meeting then 7 when positive then 6 when replied then 5 when outreach then 4
        when universe_status = 'QUALIFIED' and contact_ready then 3 when universe_status = 'QUALIFIED' then 2
        when universe_status in ('RESEARCHING', 'NEEDS_REVIEW') or open_opp then 1 end rank
      from ev),
  names(rank, stage, label) as (values (1, 'TARGET', 'Target'), (2, 'QUALIFIED', 'Qualified'), (3, 'CONTACT_READY', 'Contact ready'), (4, 'OUTREACH_SENT', 'Outreach sent'),
    (5, 'REPLIED', 'Replied'), (6, 'POSITIVE', 'Positive'), (7, 'MEETING', 'Meeting'), (8, 'BRIEF_CONCEPT', 'Brief / concept'), (9, 'PROPOSAL', 'Proposal'),
    (10, 'NEGOTIATION', 'Negotiation'), (11, 'WON', 'Won'), (12, 'PROJECT_ACTIVE', 'Project active'), (13, 'COMPLETED', 'Completed'), (14, 'PAID', 'Paid'), (0, 'LOST_PARKED', 'Lost / parked')),
  best as materialized (
    select distinct on (o.company_id) o.company_id, o.id, o.status, o.owner, o.next_action, o.next_action_due, o.blocker, o.updated_at
      from opportunities o join stg s on s.id = o.company_id and s.rank >= 5
     order by o.company_id, (o.status in ('LOST', 'ARCHIVED')) , case o.status when 'NEGOTIATION' then 0 when 'PROPOSAL' then 1 when 'CALL_REQUIRED' then 2 when 'INTERESTED' then 3
              when 'FOLLOW_UP' then 4 when 'CONTACTED' then 5 else 6 end, o.updated_at desc),
  live as (
    select s.id company_id, s.name, s.dir, s.rank, n.stage, n.label, s.last_at, b.id opp_id, b.status opp_status, b.owner, b.next_action, b.next_action_due, b.blocker,
           (select tk.title from tasks tk where tk.company_id = s.id and tk.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and coalesce(tk.task_type, '') <> 'WORK_ORDER' order by tk.due_at nulls last limit 1) open_task,
           (select tk.due_at from tasks tk where tk.company_id = s.id and tk.status in ('OPEN', 'IN_PROGRESS', 'WAITING') and coalesce(tk.task_type, '') <> 'WORK_ORDER' order by tk.due_at nulls last limit 1) open_task_due
      from stg s join names n on n.rank = s.rank left join best b on b.company_id = s.id
     where s.rank >= 5)
  select jsonb_build_object(
    'generated_at', now(),
    'kpis', jsonb_build_object(
      'revenue', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt) order by amt desc), '[]'::jsonb)
                    from (select currency, sum(amount) amt from revenue where payment_status <> 'CANCELLED' group by 1) r),
      'revenue_records', (select count(*) from revenue where payment_status <> 'CANCELLED'),
      'active_projects', (select count(*) from projects where status in ('CONFIRMED', 'PLANNING', 'LIVE')),
      'open_proposals', (select count(*) from opportunities where status in ('PROPOSAL', 'NEGOTIATION')),
      'meetings_30', coalesce((v_ceo->'funnel'->'d30'->>'meetings')::int, 0),
      'positive_30', coalesce((v_ceo->'funnel'->'d30'->>'positive')::int, 0),
      'gmail_drafts_to_send', (select count(*) from outbound_emails where status = 'DRAFTED'),
      'studio_drafts_to_send', (select count(*) from studio_outputs where status = 'PREPARED' and gmail_draft_id is not null and coalesce(send_after, v_today) <= v_today),
      'studio_drafts_later', (select count(*) from studio_outputs where status = 'PREPARED' and gmail_draft_id is not null and send_after > v_today)),
    'funnel', jsonb_build_object(
      'stages', (select jsonb_agg(jsonb_build_object('stage', n.stage, 'label', n.label, 'n', (select count(*) from stg where stg.rank = n.rank),
                   'reached', case when n.rank > 0 then (select count(*) from stg where stg.rank >= n.rank) end,
                   'stuck', case when n.rank between 5 and 10 then (select count(*) from live l where l.rank = n.rank and l.next_action_due is null and l.open_task is null
                                                                 and coalesce(l.last_at, now() - interval '1 year') < now() - interval '7 days') end)
                 order by case when n.rank = 0 then 99 else n.rank end) from names n),
      'method', 'Each company sits at the furthest stage it has reached (lost / parked when its opportunities are closed or it was parked, unless a positive conversation or meeting is live). Contact ready = qualified with an EMAIL READY route (valid verified email or approved official published inbox). Brief / concept = a Studio Level 2-3 document sent, a concept used or a project brief. Paid = revenue recorded as paid. Stuck = no next-action date, no open task and no movement for 7 days.'),
    'opportunities', coalesce((select jsonb_agg(jsonb_build_object('company_id', l.company_id, 'company', l.name, 'director', l.dir, 'stage', l.stage, 'label', l.label,
        'opportunity_id', l.opp_id, 'status', l.opp_status, 'owner', l.owner, 'next_action', coalesce(nullif(btrim(l.next_action), ''), l.open_task),
        'next_action_due', coalesce(l.next_action_due, (l.open_task_due at time zone 'Africa/Cairo')::date), 'blocker', l.blocker, 'last_at', l.last_at,
        'missing', to_jsonb(array_remove(array[
            case when l.opp_id is null then 'NO_OPPORTUNITY' end,
            case when coalesce(nullif(btrim(l.next_action), ''), l.open_task) is null then 'NO_NEXT_ACTION' end,
            case when coalesce(l.next_action_due, (l.open_task_due at time zone 'Africa/Cairo')::date) is null then 'NO_DATE' end,
            case when coalesce(l.next_action_due, (l.open_task_due at time zone 'Africa/Cairo')::date) < v_today then 'OVERDUE' end,
            case when l.opp_id is not null and nullif(btrim(l.owner), '') is null then 'NO_OWNER' end], null)))
      order by l.rank desc, l.last_at desc nulls last) from live l), '[]'::jsonb),
    'revenue', jsonb_build_object(
      'recorded', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt, 'records', n)), '[]'::jsonb)
                     from (select currency, sum(amount) amt, count(*) n from revenue where payment_status <> 'CANCELLED' group by 1) r),
      'received', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt)), '[]'::jsonb)
                     from (select currency, sum(amount) amt from revenue_payments group by 1) r),
      'receivables', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt)), '[]'::jsonb)
                        from (select r.currency, sum(r.amount - coalesce((select sum(p.amount) from revenue_payments p where p.revenue_id = r.id), 0)) amt
                                from revenue r where r.payment_status in ('PENDING', 'PART_PAID') group by 1) r),
      'gross_profit', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt, 'records', n)), '[]'::jsonb)
                         from (select currency, sum(gross_profit) amt, count(*) n from revenue where gross_profit is not null and payment_status <> 'CANCELLED' group by 1) r),
      'historical', v_hist || jsonb_build_object(
          'reconciled', (select coalesce(sum(amount), 0) from revenue where historical and payment_status <> 'CANCELLED' and currency = coalesce(v_hist->>'currency', 'GBP')),
          'reconciled_records', (select count(*) from revenue where historical and payment_status <> 'CANCELLED'),
          'other_currency_records', (select count(*) from revenue where historical and payment_status <> 'CANCELLED' and currency <> coalesce(v_hist->>'currency', 'GBP'))),
      'by_service', (select coalesce(jsonb_agg(jsonb_build_object('service', s, 'currency', currency, 'amount', amt, 'records', n) order by amt desc), '[]'::jsonb)
                       from (select coalesce(nullif(btrim(service), ''), 'Not recorded') s, currency, sum(amount) amt, count(*) n from revenue where payment_status <> 'CANCELLED' group by 1, 2) r),
      'by_director', (select coalesce(jsonb_agg(jsonb_build_object('director', d, 'currency', currency, 'amount', amt, 'records', n) order by amt desc), '[]'::jsonb)
                        from (select coalesce(r.director, co.dir, 'UNATTRIBUTED') d, r.currency, sum(r.amount) amt, count(*) n
                                from revenue r left join co on co.id = r.company_id where r.payment_status <> 'CANCELLED' group by 1, 2) r),
      'by_month', (select coalesce(jsonb_agg(jsonb_build_object('month', m, 'currency', currency, 'amount', amt) order by m), '[]'::jsonb)
                     from (select to_char(coalesce(revenue_date, (received_at at time zone 'Africa/Cairo')::date, (created_at at time zone 'Africa/Cairo')::date), 'YYYY-MM') m,
                                  currency, sum(amount) amt from revenue where payment_status <> 'CANCELLED' group by 1, 2) r),
      'won_without_revenue', (select coalesce(jsonb_agg(jsonb_build_object('opportunity_id', o.id, 'company', c.name, 'won_at', o.won_at)), '[]'::jsonb)
                                from opportunities o join companies c on c.id = o.company_id
                               where o.status = 'WON' and not exists (select 1 from revenue r where r.opportunity_id = o.id or (r.company_id = o.company_id and r.payment_status <> 'CANCELLED'))),
      'records', (select coalesce(jsonb_agg(x order by x->>'date' desc), '[]'::jsonb) from (
                    select jsonb_build_object('id', r.id, 'client', coalesce(r.client_name, c.name), 'project', coalesce(r.project_name, p.name, r.description),
                      'date', coalesce(r.revenue_date, (r.received_at at time zone 'Africa/Cairo')::date, (r.created_at at time zone 'Africa/Cairo')::date),
                      'service', r.service, 'director', coalesce(r.director, co.dir), 'gross', r.amount, 'supplier_cost', r.supplier_cost, 'gross_profit', r.gross_profit,
                      'currency', r.currency, 'payment_status', r.payment_status, 'evidence', r.evidence, 'source', r.source, 'historical', r.historical) x
                      from revenue r left join companies c on c.id = r.company_id left join projects p on p.id = r.project_id left join co on co.id = r.company_id
                     where r.payment_status <> 'CANCELLED' order by coalesce(r.revenue_date, r.received_at::date, r.created_at::date) desc limit 200) q)),
    'scorecards', director_scorecards(),
    'work_orders', coalesce((select jsonb_agg(work_order_eval(t.id) order by (t.status in ('COMPLETED', 'CANCELLED')), t.priority desc nulls last, t.created_at desc)
                               from tasks t where t.task_type = 'WORK_ORDER' and (t.status in ('OPEN', 'IN_PROGRESS', 'WAITING') or t.completed_at > now() - interval '14 days')), '[]'::jsonb),
    'directors', (select jsonb_agg(jsonb_build_object('key', r.key, 'name', r.name) order by r.sort) from agent_registry r where r.v3_role = 'DIRECTOR' and r.kind = 'ACQUISITION'))
  into v;
  return v;
end $$;

-- ---------------------------------------------------------------- 7. Cache: 'command' joins the 5-minute core snapshots
create or replace function public.hq_cache_key_ok(p_key text)
returns boolean language sql stable security definer set search_path = public as $$
  select p_key in ('ceo', 'network', 'advisor', 'directors', 'execution', 'command')
      or (p_key like 'director:%' and exists (select 1 from agent_registry r where r.key = substr(p_key, 10) and r.v3_role is not null));
$$;
select pg_temp.patch('public.hq_cache_build(text)'::regprocedure, array[
  'when ''execution'' then hq_execution()',
  'when ''execution'' then hq_execution()
      when ''command'' then hq_command()']);
select pg_temp.patch('public.hq_cache_refresh(text)'::regprocedure, array[
  'array[''directors'', ''ceo'', ''advisor'', ''network'', ''execution'']',
  'array[''directors'', ''ceo'', ''advisor'', ''command'', ''network'', ''execution'']']);

-- ---------------------------------------------------------------- 8. Privileges: admin RPCs for HQ; helpers stay internal
revoke all on function public.hq_revenue_import(jsonb, boolean), public.hq_opportunity_plan(uuid, text, date, text, text, boolean),
  public.hq_work_order(text, text, text, text, integer, date, text), public.hq_work_order_action(uuid, text, text), public.hq_command(),
  public.work_order_term_re(text), public.work_order_companies(jsonb), public.work_order_targets(), public.work_order_eval(uuid),
  public.work_orders_refresh(), public.director_scorecards() from public, anon, authenticated;
grant execute on function public.hq_revenue_import(jsonb, boolean), public.hq_opportunity_plan(uuid, text, date, text, text, boolean),
  public.hq_work_order(text, text, text, text, integer, date, text), public.hq_work_order_action(uuid, text, text), public.hq_command() to authenticated;

select cron.schedule('work-orders-refresh', '17,47 * * * *', 'select public.work_orders_refresh()');
