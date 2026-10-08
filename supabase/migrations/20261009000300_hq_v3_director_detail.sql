-- NOYA HQ V3: one drill-down for every member of the workforce (9 Oct 2026)
-- hq_director(key) serves the ten Directors, the Strategic Partnerships Manager and the seven support agents from the live
-- tables. Every list carries its true total, so HQ can say "showing 60 of 104" instead of silently cutting records.
--   Directors / Partnerships: new finds, people, verified contacts, email gaps, opportunities (model, value both ways,
--     right contact, next step), outreach waiting for Adam, approved / Gmail drafts, researching, held / rejected.
--   Support agents: their own working queue (decision makers missing, verification queue, drafts, follow-ups, threads, runs).
--   Growth: the Growth, Social & Paid Media read (hq_growth).

-- The verification queue as a full compact list (the items array stays capped by the daily allowance for workflow 24).
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.email_verification_queue(integer)'::regprocedure);
  n := replace(d, $a$    'waiting', (select count(*) from q),$a$,
                  $a$    'waiting', (select count(*) from q),
    'waiting_list', coalesce((select jsonb_agg(jsonb_build_object('contact_id', q.contact_id, 'email', q.email, 'name', nullif(btrim(coalesce(q.first_name, '') || ' ' || coalesce(q.last_name, '')), ''),
                      'position', q.position, 'company', q.company, 'company_id', q.company_id, 'agent', q.agent, 'tier', q.email_tier, 'source', q.email_source_url,
                      'draft_waiting', q.draft_waiting) order by q.draft_waiting desc, q.company) from q), '[]'::jsonb),$a$);
  if n = d then raise exception 'email_verification_queue list patch did not apply'; end if;
  execute n;
end $patch$;

create or replace function public.director_detail(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_desk jsonb := outreach_desk(); v_gaps jsonb := email_gap_list(1000)->'items'; v jsonb;
begin
  with
  co as (select c.*, agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent
           from companies c),
  mine as (select * from co where co.agent = p_key or (p_key = 'PARTNERSHIPS' and co.partnership_model is not null)),
  ppl as (select k.*, m.name company, m.country company_country,
                 email_state_v3(k.email, k.email_status, k.email_source_url, k.email_verification_provider) st
            from contacts k join mine m on m.id = k.company_id
           where not coalesce(k.do_not_contact, false) and (coalesce(k.first_name, '') <> '' or k.email is not null)),
  pj as (select k.created_at, k.st, k.company_id, role_score(k.position) rs, jsonb_build_object(
           'contact_id', k.id, 'name', nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), ''), 'role', k.position,
           'company', k.company, 'company_id', k.company_id, 'country', coalesce(k.country, k.company_country),
           'email', k.email, 'email_state', k.st, 'linkedin', nullif(k.linkedin, ''), 'instagram', nullif(k.instagram, ''),
           'phone', nullif(k.phone, ''), 'source', coalesce(k.source_url, k.email_source_url), 'source_type', k.source_type,
           'confidence', case when k.identity_status = 'CONFIRMED' and role_score(k.position) >= 4 then 'HIGH'
                              when k.identity_status = 'CONFIRMED' then 'MEDIUM' else 'NEEDS_VERIFICATION' end,
           'found_at', k.created_at) j from ppl k),
  mine_ids as (select id from mine),
  desk(bucket, e) as (
    select b, e from (values ('needs_review'), ('approved'), ('researching'), ('held'), ('rejected')) x(b), jsonb_array_elements(v_desk->b) e
     where (e->>'company_id')::uuid in (select id from mine_ids)),
  opp as (
    select m.id company_id, m.name, m.partnership_model, o.opportunity_type, o.status, o.next_action, o.created_at,
           left(coalesce(o.angle, o.suggested_approach, o.reason, o.description), 320) angle,
           (select p.j from pj p where p.company_id = m.id and p.rs >= 3 order by (p.st = 'VALID_VERIFIED') desc, p.rs desc, p.created_at limit 1) contact,
           relationship_state(m.id) rel
      from mine m left join lateral (select * from opportunities o where o.company_id = m.id order by o.created_at desc limit 1) o on true
     where m.universe_status = 'QUALIFIED'),
  sec(ord, key, title, kind, total, items) as (
    select 1, 'finds', 'New finds', 'companies', (select count(*) from mine where universe_status in ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING')),
      (select jsonb_agg(jsonb_build_object('company_id', m.id, 'company', m.name, 'country', m.country, 'type', m.company_type, 'status', m.universe_status,
                 'model', partnership_model_label(m.partnership_model), 'website', m.website, 'source', m.source, 'found_at', m.created_at,
                 'people', (select count(*) from pj where pj.company_id = m.id and pj.rs >= 3),
                 'verified', (select count(*) from pj where pj.company_id = m.id and pj.st = 'VALID_VERIFIED')) order by m.created_at desc)
         from (select * from mine where universe_status in ('QUALIFIED', 'NEEDS_REVIEW', 'RESEARCHING') order by created_at desc limit 60) m)
    union all
    select 2, 'people', 'People', 'people', (select count(*) from pj),
      (select jsonb_agg(j order by created_at desc) from (select * from pj order by created_at desc limit 150) p)
    union all
    select 3, 'verified', 'Verified contacts', 'people', (select count(*) from pj where st = 'VALID_VERIFIED'),
      (select jsonb_agg(j order by created_at desc) from (select * from pj where st = 'VALID_VERIFIED' order by created_at desc limit 150) p)
    union all
    select 4, 'email_gaps', 'Email gaps', 'gaps', (select count(*) from jsonb_array_elements(v_gaps) g where (g->>'company_id')::uuid in (select id from mine_ids)),
      (select jsonb_agg(g) from jsonb_array_elements(v_gaps) g where (g->>'company_id')::uuid in (select id from mine_ids))
    union all
    select 5, 'opportunities', 'Opportunities', 'opportunities', (select count(*) from opp),
      (select jsonb_agg(jsonb_build_object('company_id', o.company_id, 'company', o.name, 'model', partnership_model_label(o.partnership_model),
                 'value', partnership_values(o.partnership_model), 'type', o.opportunity_type, 'status', o.status, 'angle', o.angle,
                 'contact', o.contact, 'relationship', o.rel,
                 'next_step', case when o.rel <> 'COLD' then 'Use the existing relationship'
                                   when o.contact is null then 'Find the right decision maker'
                                   when o.contact->>'email_state' = 'VALID_VERIFIED' then 'Email draft for Adam''s review'
                                   when o.contact->>'linkedin' is not null then 'LinkedIn message for Adam to send'
                                   else 'Find a verified route to ' || coalesce(o.contact->>'name', 'the decision maker') end,
                 'at', coalesce(o.created_at, now())) order by o.created_at desc nulls last)
         from (select * from opp order by created_at desc nulls last limit 80) o)
    union all
    select 6, 'needs_review', 'Waiting for Adam', 'desk', (select count(*) from desk where bucket = 'needs_review'),
      (select jsonb_agg(e) from desk where bucket = 'needs_review')
    union all
    select 7, 'approved', 'Approved / Gmail drafts', 'desk', (select count(*) from desk where bucket = 'approved'),
      (select jsonb_agg(e) from desk where bucket = 'approved')
    union all
    select 8, 'researching', 'Researching', 'desk', (select count(*) from desk where bucket = 'researching'),
      (select jsonb_agg(e) from desk where bucket = 'researching')
    union all
    select 9, 'held', 'Held or rejected', 'desk', (select count(*) from desk where bucket in ('held', 'rejected')),
      (select jsonb_agg(e) from desk where bucket in ('held', 'rejected')))
  select jsonb_build_object('key', p_key, 'sections',
    (select jsonb_agg(jsonb_build_object('key', key, 'title', title, 'kind', kind, 'total', total, 'items', coalesce(items, '[]'::jsonb)) order by ord) from sec))
  into v;
  return v;
end $$;
revoke all on function public.director_detail(text) from public, anon, authenticated;

create or replace function public.support_detail(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb; v_q jsonb; v_desk jsonb;
begin
  if p_key = 'CONTACT' then
    with co as (select c.*, agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent from companies c),
    nodm as (select co.* from co where co.universe_status = 'QUALIFIED' and relationship_state(co.id) = 'COLD'
                and not exists (select 1 from contacts k where k.company_id = co.id and k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3
                                 and coalesce(k.first_name, '') <> '' and not coalesce(k.do_not_contact, false))),
    found as (select k.*, c.name company from contacts k join companies c on c.id = k.company_id
               where k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3 and coalesce(k.first_name, '') <> '' and k.created_at > now() - interval '7 days')
    select jsonb_build_object('key', p_key, 'sections', jsonb_build_array(
      jsonb_build_object('key', 'no_dm', 'title', 'Companies still missing the right decision maker', 'kind', 'companies', 'total', (select count(*) from nodm),
        'items', coalesce((select jsonb_agg(jsonb_build_object('company_id', id, 'company', name, 'country', country, 'type', company_type, 'status', universe_status,
                   'director', agent, 'attempts', enrichment_attempts, 'last_enriched', last_enriched_at, 'found_at', created_at) order by created_at desc) from nodm), '[]')),
      jsonb_build_object('key', 'people', 'title', 'Decision makers confirmed in the last 7 days', 'kind', 'people', 'total', (select count(*) from found),
        'items', coalesce((select jsonb_agg(jsonb_build_object('contact_id', f.id, 'name', btrim(coalesce(f.first_name, '') || ' ' || coalesce(f.last_name, '')), 'role', f.position,
                   'company', f.company, 'company_id', f.company_id, 'country', f.country, 'email', f.email,
                   'email_state', email_state_v3(f.email, f.email_status, f.email_source_url, f.email_verification_provider),
                   'linkedin', nullif(f.linkedin, ''), 'instagram', nullif(f.instagram, ''), 'phone', nullif(f.phone, ''), 'source', coalesce(f.source_url, f.email_source_url),
                   'confidence', case when role_score(f.position) >= 4 then 'HIGH' else 'MEDIUM' end, 'found_at', f.created_at) order by f.created_at desc)
                 from (select * from found order by created_at desc limit 150) f), '[]'))))
    into v;
  elsif p_key = 'EMAIL' then
    v_q := email_verification_queue(0);
    select jsonb_build_object('key', p_key, 'sections', jsonb_build_array(
      jsonb_build_object('key', 'verify_queue', 'title', 'Waiting for SMTP verification', 'kind', 'verify', 'total', (v_q->>'waiting')::int, 'items', coalesce(v_q->'waiting_list', '[]')),
      jsonb_build_object('key', 'verifications', 'title', 'Verification results (7 days)', 'kind', 'verifications',
        'total', (select count(*) from contact_email_verifications where created_at > now() - interval '7 days' and provider_status is not null),
        'items', coalesce((select jsonb_agg(jsonb_build_object('email', ev.email, 'name', nullif(btrim(coalesce(ev.first_name, '') || ' ' || coalesce(ev.last_name, '')), ''),
                   'position', ev.position, 'company', c.name, 'company_id', ev.company_id, 'result', ev.provider_status, 'score', ev.provider_score, 'at', ev.created_at) order by ev.created_at desc)
                 from contact_email_verifications ev left join companies c on c.id = ev.company_id
                where ev.created_at > now() - interval '7 days' and ev.provider_status is not null), '[]')),
      jsonb_build_object('key', 'email_gaps', 'title', 'Email gap queue', 'kind', 'gaps', 'total', jsonb_array_length(email_gap_list(1000)->'items'),
        'items', email_gap_list(1000)->'items')))
    into v;
  elsif p_key = 'WRITER' then
    select jsonb_build_object('key', p_key, 'sections', jsonb_build_array(
      jsonb_build_object('key', 'drafts', 'title', 'Drafts written (14 days)', 'kind', 'drafts',
        'total', (select count(*) from outreach_candidates where not dry_run and draft is not null and created_at > now() - interval '14 days'),
        'items', coalesce((select jsonb_agg(jsonb_build_object('company', c.name, 'company_id', oc.company_id,
                   'person', nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), ''), 'channel', oc.channel, 'status', oc.status,
                   'qa', oc.qa_status, 'subject', oc.subject, 'hold_reason', oc.hold_reason, 'edited', oc.review_action = 'EDITED', 'at', oc.created_at) order by oc.created_at desc)
                 from outreach_candidates oc join companies c on c.id = oc.company_id left join contacts k on k.id = oc.contact_id
                where not oc.dry_run and oc.draft is not null and oc.created_at > now() - interval '14 days'), '[]'))))
    into v;
  elsif p_key = 'DIRECTOR' then
    v := daily_action_queue(20);
    select jsonb_build_object('key', p_key, 'sections', jsonb_build_array(
      jsonb_build_object('key', 'plans', 'title', 'Daily plans (14 days)', 'kind', 'plans',
        'total', (select count(distinct run_date) from outreach_candidates where not dry_run and run_date > current_date - 14),
        'items', coalesce((select jsonb_agg(jsonb_build_object('run_date', run_date, 'touches', n, 'email', e, 'linkedin', l, 'instagram', i, 'ready', r, 'held', h) order by run_date desc)
                 from (select run_date, count(*) n, count(*) filter (where channel = 'EMAIL') e, count(*) filter (where channel = 'LINKEDIN') l,
                              count(*) filter (where channel = 'INSTAGRAM') i, count(*) filter (where status in ('READY', 'APPROVED', 'SENT')) r,
                              count(*) filter (where status = 'HOLD') h
                         from outreach_candidates where not dry_run and run_date > current_date - 14 group by run_date) z), '[]')),
      jsonb_build_object('key', 'actions', 'title', 'Today''s commercial actions for Adam', 'kind', 'actions', 'total', (v->>'count')::int, 'items', coalesce(v->'items', '[]'))))
    into v;
  elsif p_key = 'REPLY' then
    v_desk := outreach_desk();
    select jsonb_build_object('key', p_key, 'sections', jsonb_build_array(
      jsonb_build_object('key', 'replies', 'title', 'Replies (60 days)', 'kind', 'replies', 'total', jsonb_array_length(v_desk->'replied'), 'items', v_desk->'replied'),
      jsonb_build_object('key', 'followups', 'title', 'Follow-ups', 'kind', 'followups', 'total', jsonb_array_length(v_desk->'followups'), 'items', v_desk->'followups'),
      jsonb_build_object('key', 'sent', 'title', 'Sent (60 days)', 'kind', 'sent', 'total', jsonb_array_length(v_desk->'sent'), 'items', v_desk->'sent')))
    into v;
  elsif p_key = 'MEMORY' then
    select jsonb_build_object('key', p_key, 'sections', jsonb_build_array(
      jsonb_build_object('key', 'threads', 'title', 'Relationships summarised from Gmail history', 'kind', 'threads',
        'total', (select count(*) from relationship_reviews where summary is not null),
        'items', coalesce((select jsonb_agg(jsonb_build_object('key', r.key, 'summary', r.summary, 'their_position', r.their_position,
                   'suggested', r.suggested_status, 'status', r.status, 'last_at', r.summary_basis->>'last_at', 'messages', r.summary_basis->'messages',
                   'basis', r.summary_basis->>'source') order by r.summary_basis->>'last_at' desc nulls last)
                 from relationship_reviews r where r.summary is not null), '[]'))))
    into v;
  elsif p_key = 'RESEARCH' then
    select jsonb_build_object('key', p_key, 'sections', jsonb_build_array(
      jsonb_build_object('key', 'runs', 'title', 'Department runs (7 days)', 'kind', 'runs',
        'total', (select count(*) from department_run_metrics where recorded_at > now() - interval '7 days'),
        'items', coalesce((select jsonb_agg(jsonb_build_object('at', r.recorded_at, 'workflow', r.workflow_name, 'searches', r.metrics->'serper_searches',
                   'candidates', r.metrics->'candidates_found', 'researched', r.metrics->'deep_researched', 'qualified', r.metrics->'qualified',
                   'known_skipped', r.metrics->'known_skipped') order by r.recorded_at desc)
                 from department_run_metrics r where r.recorded_at > now() - interval '7 days'), '[]'))))
    into v;
  end if;
  return v;
end $$;
revoke all on function public.support_detail(text) from public, anon, authenticated;

create or replace function public.hq_director(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); r agent_registry%rowtype;
begin
  select * into r from agent_registry where key = p_key and v3_role is not null;
  if r.key is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if r.key = 'GROWTH' then return jsonb_build_object('key', r.key, 'growth', hq_growth()); end if;
  if r.v3_role in ('DIRECTOR', 'MANAGER') then return director_detail(r.key); end if;
  return support_detail(r.key);
end $$;
revoke all on function public.hq_director(text) from public, anon;
grant execute on function public.hq_director(text) to authenticated;

-- Security advisor: helper functions added by V3 carry a fixed search_path.
alter function public.task_field(text, text) set search_path = public;
alter function public.task_message(text) set search_path = public;
alter function public.partnership_values(text) set search_path = public;
alter function public.agent_key_of(text, text, text) set search_path = public;
