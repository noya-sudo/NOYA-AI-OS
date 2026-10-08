-- NOYA HQ V3: the AI workforce as Adam's company (9 Oct 2026)
-- Ten business Directors, one Strategic Partnerships Manager and seven shared specialist agents. The n8n workflows stay
-- underneath; this layer only translates them into departments Adam understands. Every number is a live query.
--   1. agent_registry: V3 names, missions and roles (v3_role DIRECTOR / MANAGER / SUPPORT). ENRICHMENT and DRAFTING stay
--      for the legacy snapshot only (v3_role null).
--   2. agent_key_of(): Private Membership & Network (PRIVATE) gets its own companies: members clubs and communities,
--      family and private offices, PA / EA routes, UHNW introducers.
--   3. email_state_v3(): VALID_VERIFIED / ACCEPT_ALL / PUBLIC_UNVERIFIED / UNKNOWN / INVALID / NOT_FOUND.
--   4. directors_snapshot() / hq_directors(): status (WORKING / SCHEDULED / BLOCKED / ERROR), mission derived from real
--      state, last completed action, last and next run, today and 3-day high-value output, genuine blockers, the CEO
--      floor strip and the real activity feed.

-- ---------------------------------------------------------------- 1. registry
alter table public.agent_registry add column if not exists v3_role text check (v3_role in ('DIRECTOR', 'MANAGER', 'SUPPORT'));
alter table public.agent_registry add column if not exists mission text;

insert into public.agent_registry (key, name, kind, sort, scope, focus, workflows, schedule, every_minutes, max_gap_hours, run_logged, ai_workflows, v3_role, mission) values
 ('PRIVATE', 'Private Membership & Network', 'ACQUISITION', 1,
  'Private offices, family offices, founders, executives, executive assistants and private PAs, private members clubs, premium communities, luxury residential communities and UHNW introducers.',
  'Working inside workflows 06 (corporate & private client) and 07 (global partnerships): communities, private offices and introducers',
  '{"06 -","07 -"}', '{"08:00","08:30","14:00","14:30","20:00","20:30"}', null, 14, true, '{}', 'DIRECTOR',
  'Build the future NOYA Private / NOYA Club ecosystem through credible professional routes and introducers — never scraped individuals.'),
 ('GROWTH', 'Growth, Social & Paid Media', 'SUPPORT', 10,
  'Instagram strategy, content calendar, concepts and captions, collaborations, content performance, paid-media analysis and lead attribution across every department.',
  'Reads Instagram and paid-media performance (10a, 10b) and competitor patterns (10c); recommends, never publishes or spends',
  '{"10a","10b","10c"}', '{"10:30","10:45"}', null, 30, false, '{}', 'DIRECTOR',
  'Turn NOYA''s real business activity into demand, credibility and audience growth. Recommends and prepares; never launches spend or publishes without Adam.'),
 ('PARTNERSHIPS', 'Strategic Partnerships Manager', 'SUPPORT', 11,
  'Referral, reciprocal, preferred stay, member benefit, commissionable experience, white-label, corporate, sponsorship and content partnerships found by every Director.',
  'Reviews every partnership-model prospect across the Directors: commercial model, value both ways, right contact, next step',
  '{}', '{}', null, 48, false, '{}', 'MANAGER',
  'Can this relationship make NOYA stronger repeatedly? Network building, not supplier sourcing.'),
 ('RESEARCH', 'Research Intelligence', 'SUPPORT', 20,
  'Finds evidence-backed organisations and opportunities for every Director.',
  'Discovery runs 02–09 and the Egypt signal analyst (17)',
  '{"02 -","03 -","04 -","06 -","07 -","08 -","09 -","17 -"}', '{"06:00","06:30","07:00","08:00","08:30","09:00","10:00","10:45","12:00","12:30","13:00","14:00","14:30","18:00","18:30","19:00","20:00","20:30"}',
  null, 14, true, '{}', 'SUPPORT', 'Find real organisations with a commercial reason to work with NOYA, with the source kept.'),
 ('CONTACT', 'Contact Intelligence', 'SUPPORT', 21,
  'Finds the commercially correct person at every qualified company.',
  'Workflow 19: LinkedIn, official pages and Instagram, with an anti-fabrication check',
  '{"19 -"}', '{"11:00","17:00","21:00"}', null, 14, false, '{"19"}', 'SUPPORT', 'Right person first: no verification or outreach spend before the correct decision maker is known.'),
 ('EMAIL', 'Email Intelligence & Verification', 'SUPPORT', 22,
  'Finds published business email routes and validates them.',
  'Workflow 23 (official contact, team, press pages, indexed addresses) and workflow 24 (Hunter verification inside a daily cap)',
  '{"23 -","24 -"}', '{"03:15","08:40","09:45","15:45","20:40","23:15"}', null, 14, false, '{"23"}', 'SUPPORT', 'Only a VALID_VERIFIED address ever becomes EMAIL READY.'),
 ('WRITER', 'Outreach Writer', 'SUPPORT', 23,
  'Writes professional, personalised outreach and revalidates ageing drafts.',
  'Workflow 18 (daily drafts with a quality gate), 14 (drafts Adam requests), 20 (14-day revalidation)',
  '{"18 -","14 -","20 -"}', '{"10:15","21:30","22:00","22:30"}', null, 30, false, '{"18"}', 'SUPPORT', 'Short, specific, evidence-led messages Adam would send himself.')
on conflict (key) do update set name = excluded.name, kind = excluded.kind, sort = excluded.sort, scope = excluded.scope, focus = excluded.focus,
  workflows = excluded.workflows, schedule = excluded.schedule, max_gap_hours = excluded.max_gap_hours, v3_role = excluded.v3_role, mission = excluded.mission;

update public.agent_registry set v3_role = 'DIRECTOR', sort = v.sort, name = v.name, mission = v.mission from (values
  ('HOSPITALITY', 2, 'Hospitality & Stays', 'Build one of the strongest international accommodation networks available to an independent concierge: hotels, villas, residences, resorts and hospitality groups — independents as much as famous brands.'),
  ('TRAVEL', 3, 'Travel & Concierge Network', 'Make NOYA the trusted Egypt execution partner for international travel and concierge companies. The partner keeps the client; NOYA executes Egypt.'),
  ('BRANDS', 4, 'Brands & Production', 'Bring campaigns, brand trips, productions, launches, activations and shoots into NOYA''s ecosystem. Why not Egypt?'),
  ('WEDDINGS', 5, 'Weddings & Private Events', 'Be the preferred Egypt destination-execution and guest-concierge partner for international planners. The planner keeps the client and creative control.'),
  ('CORPORATE', 6, 'Corporate & White-Label', 'Build recurring institutional revenue: corporate concierge, white-label, executive travel, VIP client programmes and client hospitality.'),
  ('MEDIA', 7, 'Media & Culture', 'Grow NOYA through culturally relevant media and exceptional Egypt content concepts — never "can Adam come on your podcast?".'),
  ('SPORTS', 8, 'Sports & Talent', 'Selective, high-quality sports and talent relationships through agents, managers and commercial teams — never random celebrity messages.'),
  ('EGYPT', 9, 'Egypt Growth', 'Identify why Egypt matters now and route every signal to the Director who can turn it into commercial action.')
) v(key, sort, name, mission) where agent_registry.key = v.key;

update public.agent_registry set v3_role = 'SUPPORT', sort = 24, name = 'Relationship Memory', workflows = '{"15 -","16 -"}',
  schedule = '{"06:50","07:00","10:00","13:00","16:00","19:00","22:00"}', every_minutes = null, max_gap_hours = 12,
  scope = 'Checks Gmail history, the CRM, previous conversations, LinkedIn and suppression before anyone is contacted.',
  focus = 'Gmail history import every 3 hours (15) and relationship summaries daily (16)',
  mission = 'Never treat a known relationship as a cold lead.'
 where key = 'REPLY' and v3_role is null and name <> 'Relationship Memory';
-- the existing REPLY row becomes Relationship Memory (MEMORY); Reply & Follow-up gets its own row on workflow 13
update public.agent_registry set key = 'MEMORY' where key = 'REPLY' and name = 'Relationship Memory';
insert into public.agent_registry (key, name, kind, sort, scope, focus, workflows, schedule, every_minutes, max_gap_hours, run_logged, ai_workflows, v3_role, mission) values
 ('REPLY', 'Reply & Follow-up', 'SUPPORT', 25, 'Detects replies and sends from Gmail, starts follow-up timers from the actual send and cancels them when someone answers.',
  'Workflow 13: Gmail sync every 30 minutes', '{"13 -"}', '{}', 30, 2, false, '{}', 'SUPPORT', 'Follow up from the real send time; stop the moment they answer.')
on conflict (key) do update set name = excluded.name, workflows = excluded.workflows, every_minutes = excluded.every_minutes, v3_role = excluded.v3_role, mission = excluded.mission, sort = excluded.sort;
update public.agent_registry set v3_role = 'SUPPORT', sort = 26, name = 'Commercial Director', workflows = '{"18 -","11 -"}', schedule = '{"18:00","21:30"}',
  mission = 'Prioritise the most valuable actions across every department and decide what reaches Adam.'
 where key = 'DIRECTOR';
update public.agent_registry set v3_role = null where key in ('ENRICHMENT', 'DRAFTING');

-- ---------------------------------------------------------------- 2. company → Director
create or replace function public.agent_key_of(p_lane text, p_type text, p_notes text)
returns text language sql immutable as $$
  select case
    when is_media_target(p_type, p_notes) then 'MEDIA'
    -- Private Membership & Network: communities, clubs, private and family offices, PA / EA routes, UHNW introducers
    when coalesce(p_type, '') ~* '(member|private club|social club|community|family office|private office|household|personal assistant|executive assistant|pa / ea|\mpa\M|uhnw|introducer|residential community)'
         and coalesce(p_type, '') !~* '(travel|advisor|hotel|resort|bank|wealth management|recruitment agency)' then 'PRIVATE'
    when p_lane = 'PARTNERSHIPS' then 'HOSPITALITY'
    when p_lane = 'TRAVEL_PRIVATE' then 'TRAVEL'
    when p_lane = 'BRANDS' then 'BRANDS'
    when p_lane = 'WEDDINGS' then 'WEDDINGS'
    when p_lane = 'CORPORATE' then 'CORPORATE'
    when p_lane = 'SPORTS_PRIVATE' then 'SPORTS'
    when p_lane = 'EGYPT_EVENTS' then 'EGYPT'
    else 'CORPORATE' end
$$;

-- ---------------------------------------------------------------- 3. email states (V3 names)
-- VALID_VERIFIED only with a provider-backed valid result; ACCEPT_ALL / UNKNOWN / PUBLIC_UNVERIFIED never count.
create or replace function public.email_state_v3(p_email text, p_status text, p_source_url text, p_provider text)
returns text language sql stable security definer set search_path = public as $$
  with v as (select provider_status from contact_email_verifications
              where lower(email) = lower(btrim(coalesce(p_email, ''))) and provider_status is not null
              order by coalesce(checked_at, created_at) desc limit 1)
  select case
    when coalesce(btrim(p_email), '') = '' then 'NOT_FOUND'
    when p_status = 'INVALID' or (select provider_status from v) in ('invalid', 'disposable') then 'INVALID'
    when email_state(p_status, p_source_url, p_provider) = 'VERIFIED' then 'VALID_VERIFIED'
    when (select provider_status from v) = 'accept_all' then 'ACCEPT_ALL'
    when p_status = 'RISKY' or (select provider_status from v) in ('unknown', 'webmail') then 'UNKNOWN'
    when email_state(p_status, p_source_url, p_provider) = 'PUBLICLY_LISTED' then 'PUBLIC_UNVERIFIED'
    else 'UNKNOWN' end
$$;
revoke all on function public.email_state_v3(text, text, text, text) from public, anon, authenticated;

-- What a partnership model is worth to each side (model terms, not company facts).
create or replace function public.partnership_values(p_model text)
returns jsonb language sql immutable as $$
  select case p_model
    when 'PREFERRED_STAY' then '{"to_noya":"Trusted, rate-advantaged stays for NOYA clients and referrals of Egypt or concierge requests","to_partner":"Qualified private-client bookings placed by NOYA"}'
    when 'RECIPROCAL' then '{"to_noya":"A trusted partner for NOYA clients in their destination","to_partner":"NOYA looks after their guests and clients in Egypt"}'
    when 'REFERRAL' then '{"to_noya":"Introductions to members or clients who need Egypt or a concierge","to_partner":"Introductions from NOYA''s private clients"}'
    when 'GUEST_CONCIERGE' then '{"to_noya":"Service revenue from their guests'' Egypt and concierge requests","to_partner":"A concierge service for their guests without hiring one"}'
    when 'WHITE_LABEL_CONCIERGE' then '{"to_noya":"Recurring white-label service revenue","to_partner":"A concierge product under their own brand"}'
    when 'EGYPT_EXECUTION' then '{"to_noya":"Egypt delivery revenue on their projects","to_partner":"They keep the client; NOYA handles Egypt on the ground"}'
    when 'CONTENT_TALENT' then '{"to_noya":"Content, visibility and destination credibility","to_partner":"Access, hospitality and logistics for their production or talent in Egypt"}'
    else null end::jsonb
$$;

-- email_verification_queue(): the same waiting list split by Director, so each Director's number adds up to the Email agent's
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.email_verification_queue(integer)'::regprocedure);
  n := replace(d, $a$'waiting', (select count(*) from q),$a$,
                  $a$'waiting', (select count(*) from q),
    'waiting_by_agent', coalesce((select jsonb_object_agg(agent, n) from (select agent, count(*) n from q group by agent) z), '{}'::jsonb),$a$);
  if n = d then raise exception 'email_verification_queue patch did not apply'; end if;
  execute n;
end $patch$;

-- ---------------------------------------------------------------- 4. Directors snapshot
-- Last real activity per V3 member (each from its own evidence table; no workflow keeps a universal run log).
create or replace function public.director_last_run(p_key text)
returns timestamptz language plpgsql stable security definer set search_path = public as $$
declare v timestamptz;
begin
  v := case p_key
    when 'GROWTH' then (select max(x) from (select max(last_synced_at) x from content_performance union all select max(last_synced_at) from paid_media_performance
                                            union all select max(created_at) from competitor_intelligence) s)
    when 'PARTNERSHIPS' then (select max(created_at) from companies where partnership_model is not null)
    when 'RESEARCH' then (select max(x) from (select max(recorded_at) x from department_run_metrics union all select max(created_at) from intelligence) s)
    when 'CONTACT' then (select max("at") from ai_usage where workflow = '19')
    when 'EMAIL' then (select max(x) from (select max(researched_at) x from email_research
                                           union all select max(created_at) from contact_email_verifications where source_workflow like '24 %'
                                           union all select (value->>'checked_at')::timestamptz from system_config where key = 'hunter_account') s)
    when 'WRITER' then (select max(x) from (select max("at") x from ai_usage where workflow in ('18', '14') union all select max(revalidated_at) from tasks) s)
    when 'MEMORY' then (select max(x) from (select max(last_run_at) x from gmail_backfill_state union all select max(updated_at) from relationship_reviews) s)
    when 'REPLY' then (select max(last_run_at) from gmail_sync_state)
    when 'DIRECTOR' then (select max(x) from (select max(created_at) x from outreach_candidates union all select max(created_at) from ceo_reports) s)
    -- 07 only started writing department_run_metrics on 7 Oct: until then its last saved opportunity is the evidence
    when 'TRAVEL' then coalesce((agent_last_run(p_key)->>'at')::timestamptz,
                                (select max(o.created_at) from opportunities o join companies c on c.id = o.company_id where c.source like '07 -%'))
    else (agent_last_run(p_key)->>'at')::timestamptz end;
  return v;
end $$;
revoke all on function public.director_last_run(text) from public, anon, authenticated;

create or replace function public.directors_snapshot()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_snap jsonb := agents_snapshot(); v_desk jsonb := outreach_desk(); v_queue jsonb := email_verification_queue(0);
        v_hunter jsonb := (select value from system_config where key = 'hunter_account');
        v_vcfg jsonb := (select value from system_config where key = 'email_verification');
        v_gaps jsonb := email_gap_list(1000)->'items'; v jsonb;
begin
  with
  co as (select c.id, c.created_at, c.universe_status, c.partnership_model, c.relationship_status,
                agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) agent
           from companies c),
  win(w, since) as (values ('today', ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo'), ('d3', now() - interval '3 days'), ('h24', now() - interval '24 hours')),
  reg as (select r.*, director_last_run(r.key) last_run, agent_next_run(r.schedule, r.every_minutes) next_run from agent_registry r where r.v3_role is not null),
  -- high-value output per Director (company attribution) and for the Partnerships Manager (every partnership-model company)
  m as (
    select r.key, win.w, jsonb_build_object(
      'companies_found', (select count(*) from co where (co.agent = r.key or (r.key = 'PARTNERSHIPS' and co.partnership_model is not null)) and co.created_at >= win.since and co.universe_status = 'QUALIFIED'),
      'people_confirmed', (select count(*) from contacts k join co on co.id = k.company_id where (co.agent = r.key or (r.key = 'PARTNERSHIPS' and co.partnership_model is not null))
                             and k.created_at >= win.since and k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3 and coalesce(k.first_name, '') <> ''),
      'verified_emails', (select count(*) from contact_email_verifications ev join co on co.id = ev.company_id where (co.agent = r.key or (r.key = 'PARTNERSHIPS' and co.partnership_model is not null))
                             and ev.created_at >= win.since and ev.provider_status = 'valid'),
      'outreach_drafts', (select count(*) from outreach_candidates oc join co on co.id = oc.company_id where (co.agent = r.key or (r.key = 'PARTNERSHIPS' and co.partnership_model is not null))
                             and not oc.dry_run and oc.created_at >= win.since and oc.status in ('READY', 'APPROVED', 'SENT')),
      'gmail_drafts', (select count(*) from outbound_emails o join co on co.id = o.company_id where (co.agent = r.key or (r.key = 'PARTNERSHIPS' and co.partnership_model is not null))
                             and o.completed_at >= win.since and o.status in ('DRAFTED', 'SENT')),
      'replies', (select count(*) from interactions i join co on co.id = i.company_id where (co.agent = r.key or (r.key = 'PARTNERSHIPS' and co.partnership_model is not null))
                             and i.direction = 'INBOUND' and i.channel <> 'WEBSITE' and i.occurred_at >= win.since),
      'opportunities', (select count(*) from opportunities o join co on co.id = o.company_id where (co.agent = r.key or (r.key = 'PARTNERSHIPS' and co.partnership_model is not null))
                             and o.created_at >= win.since)) s
    from reg r cross join win where r.v3_role in ('DIRECTOR', 'MANAGER') and r.key <> 'GROWTH'),
  -- what each shared specialist produced
  sm as (
    select r.key, win.w, case r.key
      when 'RESEARCH' then jsonb_build_object('companies_researched', (select coalesce(sum(nullif(d.metrics->>'deep_researched', '')::numeric), 0) from department_run_metrics d where d.recorded_at >= win.since),
                                              'companies_qualified', (select count(*) from co where co.created_at >= win.since and co.universe_status = 'QUALIFIED'),
                                              'signals', (select count(*) from intelligence i where i.created_at >= win.since))
      when 'CONTACT' then jsonb_build_object('companies_enriched', (select count(distinct company_id) from ai_usage where workflow = '19' and "at" >= win.since),
                                             'people_confirmed', (select count(*) from contacts k where k.created_at >= win.since and k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3 and coalesce(k.first_name, '') <> ''))
      when 'EMAIL' then jsonb_build_object('companies_researched', (select count(distinct company_id) from email_research where researched_at >= win.since),
                                           'public_emails_found', (select coalesce(sum(tier1 + tier2), 0) from email_research where researched_at >= win.since),
                                           'valid_verified', (select count(*) from contact_email_verifications where created_at >= win.since and provider_status = 'valid'),
                                           'accept_all', (select count(*) from contact_email_verifications where created_at >= win.since and provider_status = 'accept_all'),
                                           'invalid', (select count(*) from contact_email_verifications where created_at >= win.since and provider_status in ('invalid', 'disposable')))
      when 'WRITER' then jsonb_build_object('drafts_written', (select count(*) from outreach_candidates where not dry_run and draft is not null and updated_at >= win.since),
                                            'passed_quality', (select count(*) from outreach_candidates where not dry_run and qa_status = 'PASS' and updated_at >= win.since),
                                            'revalidated', (select count(*) from tasks where revalidated_at >= win.since))
      when 'MEMORY' then jsonb_build_object('gmail_messages', (select count(*) from gmail_history_messages where updated_at >= win.since),
                                            'relationships_summarised', (select count(*) from relationship_reviews where summary_at >= win.since))
      when 'REPLY' then jsonb_build_object('replies_detected', (select count(*) from interactions where direction = 'INBOUND' and channel = 'EMAIL' and occurred_at >= win.since),
                                           'sends_detected', (select count(*) from outbound_emails where sent_at >= win.since))
      when 'DIRECTOR' then jsonb_build_object('touches_planned', (select count(*) from outreach_candidates where not dry_run and created_at >= win.since),
                                              'briefs', (select count(*) from ceo_reports where created_at >= win.since))
      when 'GROWTH' then jsonb_build_object('posts_analysed', (select count(*) from content_performance where last_synced_at >= win.since),
                                            'concepts', (select count(*) from creative_concepts where created_at >= win.since),
                                            'content_items', (select count(*) from content where created_at >= win.since),
                                            'attributed_leads', (select count(*) from marketing_attribution where created_at >= win.since
                                               and not (coalesce(utm_source, '') ~* '^noya-(golive|v3-live)' or coalesce(utm_campaign, '') ~* '(test|release)')))
      end s
    from reg r cross join win where r.v3_role = 'SUPPORT' or r.key = 'GROWTH'),
  -- live work queues behind each Director's mission
  q as (
    select r.key,
      (select count(*) from jsonb_array_elements(v_gaps) g where g->>'agent' = r.key) gaps,
      (select count(*) from co where co.agent = r.key and co.universe_status = 'QUALIFIED' and relationship_state(co.id) = 'COLD'
          and not exists (select 1 from contacts k where k.company_id = co.id and k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3
                           and coalesce(k.first_name, '') <> '' and not coalesce(k.do_not_contact, false))) no_dm,
      coalesce((v_queue->'waiting_by_agent'->>r.key)::int, 0) to_verify,  -- the same queue workflow 24 works from
      (select count(*) from jsonb_array_elements(v_desk->'needs_review') e where e->>'director' = r.key) review
    from reg r where r.v3_role = 'DIRECTOR' and r.key <> 'GROWTH'),
  feed as (
    select x from (
      select jsonb_build_object('at', e->>'at', 'agent',
               case when e->>'agent' = 'ENRICHMENT' and (e->>'kind' = 'NO_EMAIL' or e->>'text' ~* '(email|inbox)') then 'EMAIL' when e->>'agent' = 'ENRICHMENT' then 'CONTACT' else e->>'agent' end,
               'kind', e->>'kind', 'text', e->>'text', 'company_id', e->'company_id') x
        from jsonb_array_elements(coalesce(v_snap->'feed', '[]')) e
      union all
      select jsonb_build_object('at', ev.created_at, 'agent', 'EMAIL', 'kind', 'VERIFIED', 'company_id', ev.company_id,
               'text', case ev.provider_status when 'valid' then 'verified ' when 'accept_all' then 'checked (accept-all, not verifiable) ' when 'invalid' then 'found invalid ' else 'checked ' end
                       || coalesce(nullif(btrim(coalesce(ev.first_name, '') || ' ' || coalesce(ev.last_name, '')), ''), ev.email) || ' — ' || coalesce((select name from companies where id = ev.company_id), ''))
        from contact_email_verifications ev where ev.created_at > now() - interval '7 days' and ev.provider_status is not null
      union all
      select jsonb_build_object('at', oc.updated_at, 'agent', 'WRITER', 'kind', 'DRAFT', 'company_id', oc.company_id,
               'text', 'prepared ' || lower(oc.channel) || ' outreach for ' || coalesce(nullif(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')), ''), 'the company') || ' — ' || c.name)
        from outreach_candidates oc join companies c on c.id = oc.company_id left join contacts k on k.id = oc.contact_id
       where not oc.dry_run and oc.draft is not null and oc.updated_at > now() - interval '7 days' and oc.status in ('READY', 'REVIEW_REQUIRED', 'HOLD', 'APPROVED', 'SENT')
      union all
      select jsonb_build_object('at', o.completed_at, 'agent', 'WRITER', 'kind', 'GMAIL_DRAFT', 'company_id', o.company_id,
               'text', 'unsent Gmail draft created for ' || o.to_email || ' — ' || coalesce((select name from companies where id = o.company_id), '') || ' (approved by Adam)')
        from outbound_emails o where o.completed_at > now() - interval '7 days' and o.status in ('DRAFTED', 'SENT')
      union all
      select jsonb_build_object('at', min(oc.created_at), 'agent', 'DIRECTOR', 'kind', 'PLAN', 'company_id', null,
               'text', 'planned ' || count(*) || ' touches for ' || to_char(oc.run_date, 'DD Mon') || ' (' || string_agg(distinct lower(oc.channel), ', ') || ')')
        from outreach_candidates oc where not oc.dry_run and oc.created_at > now() - interval '7 days' group by oc.run_date
      union all
      select jsonb_build_object('at', ev.first_seen_at, 'agent', 'GROWTH', 'kind', 'CONTENT', 'company_id', null,
               'text', 'logged Instagram performance: ' || left(split_part(coalesce(ev.caption, ''), chr(10), 1), 80))
        from content_performance ev where ev.first_seen_at > now() - interval '7 days'
    ) s order by (x->>'at')::timestamptz desc nulls last limit 200),
  dir as (
    select r.*, coalesce((select jsonb_agg(b) from jsonb_array_elements_text(coalesce(a.blk, '[]')) b where b !~* '^Note:'), '[]') snap_blockers,
           a.current_work, a.stuck
      from reg r left join lateral (select x->'blockers' blk, x->>'current_work' current_work, x->'stuck' stuck
                                      from jsonb_array_elements(coalesce(v_snap->'agents', '[]')) x where x->>'key' = r.key limit 1) a on true),
  blk as (
    select d.key, (
      d.snap_blockers
      || case when d.key = 'GROWTH' and exists (select 1 from system_blockers where blocker_key = 'WINDSOR_ACCOUNT_LIMIT' and status = 'OPEN')
              then jsonb_build_array(jsonb_build_object('text', 'Instagram and Meta Ads reads paused: the Windsor free plan allows 1 connected account and 3 are connected', 'hard', true)) else '[]' end
      || case when d.key = 'GROWTH' then jsonb_build_array(jsonb_build_object('text', 'Metricool is connected to Instagram but not to HQ yet', 'hard', false)) else '[]' end
      || case when d.key = 'EMAIL' and v_hunter is not null and coalesce((v_hunter->>'verifications_left')::int, 0) - coalesce((v_vcfg->>'reserve_verifications')::int, 0) <= 0
              then jsonb_build_array(jsonb_build_object('text', 'Hunter free verifications used up until ' || coalesce(v_hunter->>'reset_date', 'the monthly reset'), 'hard', true))
              when d.key = 'EMAIL' and coalesce(v_hunter->>'plan', 'Free') = 'Free'
              then jsonb_build_array(jsonb_build_object('text', 'Verification capacity: Hunter Free (' || coalesce(v_hunter->>'verifications_left', '?') || ' checks left this month) cannot support 40–50 verified emails a day — plan decision with Adam', 'hard', false))
              else '[]' end
      || case when d.key in ('WRITER', 'DIRECTOR', 'CONTACT') and coalesce(ai_budget_status()->>'status', 'OK') <> 'OK'
              then jsonb_build_array(jsonb_build_object('text', 'AI budget hold: ' || (ai_budget_status()->>'status'), 'hard', true)) else '[]' end
      || case when d.key = 'RESEARCH' and exists (select 1 from tasks where task_type = 'PROVIDER_HEALTH_ALERT' and status = 'OPEN' and created_at > now() - interval '30 hours')
              then jsonb_build_array(jsonb_build_object('text', 'A search or AI provider is refusing calls (provider health alert)', 'hard', true)) else '[]' end
    ) list from dir d),
  st as (
    select d.key,
      case when exists (select 1 from jsonb_array_elements(b.list) x where jsonb_typeof(x) = 'object' and (x->>'hard')::boolean) then 'BLOCKED'
           when d.last_run is not null and d.max_gap_hours is not null and d.last_run < now() - d.max_gap_hours * interval '1 hour' then 'ERROR'
           when d.last_run > now() - interval '20 minutes' then 'WORKING'
           else 'SCHEDULED' end status
      from dir d join blk b on b.key = d.key)
  select jsonb_build_object(
    'generated_at', now(),
    'floor', jsonb_build_object(
      'agents_total', (select count(*) from reg),
      'agents_healthy', (select count(*) from st where status in ('WORKING', 'SCHEDULED')),
      'qualified_24h', (select count(*) from co where co.created_at >= now() - interval '24 hours' and co.universe_status = 'QUALIFIED'),
      'decision_makers_24h', (select count(*) from contacts k where k.created_at >= now() - interval '24 hours' and k.identity_status = 'CONFIRMED' and role_score(k.position) >= 3 and coalesce(k.first_name, '') <> ''),
      'verified_emails_24h', (select count(*) from contact_email_verifications where created_at >= now() - interval '24 hours' and provider_status = 'valid'),
      'needs_review', (v_desk->'counts'->'needs_review'->>'total')::int,
      'gmail_drafts_ready', (v_desk->'counts'->>'gmail_drafts_confirmed')::int,
      'replies', (select count(*) from tasks where task_type in ('REPLY_ACTION', 'HUMAN_REVIEW') and status in ('OPEN', 'IN_PROGRESS')),
      'meetings', (select count(*) from tasks where task_type = 'MEETING_ACTION' and status in ('OPEN', 'IN_PROGRESS'))
                  + (select count(*) from opportunities where status = 'CALL_REQUIRED')),
    'members', (select jsonb_agg(jsonb_build_object(
        'key', d.key, 'name', d.name, 'role', d.v3_role, 'mission', d.mission, 'scope', d.scope, 'next_focus', coalesce(d.current_work, d.focus),
        'workflows', d.workflows, 'status', s.status,
        'status_text', case s.status when 'WORKING' then 'Working — last activity ' || to_char(d.last_run at time zone 'Africa/Cairo', 'HH24:MI')
                                     when 'BLOCKED' then 'Blocked'
                                     when 'ERROR' then 'Missed its schedule — last activity ' || coalesce(to_char(d.last_run at time zone 'Africa/Cairo', 'DD Mon HH24:MI'), 'never')
                                     else 'Scheduled' || coalesce(' — next run ' || to_char(d.next_run at time zone 'Africa/Cairo', 'HH24:MI'), '') end,
        'last_run', d.last_run, 'next_run', d.next_run,
        'working_on', case
            when d.key = 'GROWTH' then concat_ws(' · ',
                 case when exists (select 1 from system_blockers where blocker_key = 'WINDSOR_ACCOUNT_LIMIT' and status = 'OPEN') then 'Instagram reads paused' end,
                 (select count(*) || ' Instagram posts analysed (latest ' || coalesce(to_char(max(media_date), 'DD Mon'), '—') || ')' from content_performance),
                 (select count(*) || ' media concepts' from creative_concepts),
                 (select count(*) || ' content items in the pipeline' from content where status not in ('PUBLISHED', 'ARCHIVED')))
            when d.key = 'PARTNERSHIPS' then (select count(*) || ' partnership prospects across the Directors: ' ||
                 coalesce((select string_agg(n || ' ' || lower(replace(pm, '_', ' ')), ', ' order by n desc) from (
                   select c.partnership_model pm, count(*) n from companies c where c.universe_status = 'QUALIFIED' and c.partnership_model is not null group by 1) z), 'none')
                 from companies c where c.universe_status = 'QUALIFIED' and c.partnership_model is not null)
            when d.key = 'CONTACT' then (select coalesce(sum(no_dm), 0) || ' qualified cold companies still need the right decision maker' from q)
            when d.key = 'EMAIL' then concat_ws(' · ', (v_queue->>'waiting') || ' public decision-maker emails waiting for verification',
                 jsonb_array_length(v_gaps) || ' qualified companies in the email gap queue',
                 case when v_hunter is not null then 'Hunter ' || coalesce(v_hunter->>'plan', '') || ': ' || coalesce(v_hunter->>'verifications_left', '?') || ' verifications left' end)
            when d.key = 'WRITER' then concat_ws(' · ', (select count(*) || ' drafts written today' from outreach_candidates where not dry_run and draft is not null
                   and updated_at >= ((now() at time zone 'Africa/Cairo')::date)::timestamp at time zone 'Africa/Cairo'),
                 (v_desk->'counts'->'needs_review'->>'total') || ' waiting for Adam''s review')
            when d.key = 'MEMORY' then concat_ws(' · ', (select count(*) || ' Gmail threads in relationship memory' from gmail_history_threads),
                 (select count(*) || ' relationships summarised' from relationship_reviews where summary is not null))
            when d.key = 'REPLY' then concat_ws(' · ', (select count(*) || ' sent threads watched for replies' from outbound_emails where status in ('DRAFTED', 'SENT') and gmail_thread_id is not null),
                 (v_desk->'counts'->>'followups_due') || ' follow-ups due by tomorrow')
            when d.key = 'DIRECTOR' then (select 'Latest plan: ' || count(*) || ' touches for ' || to_char(max(run_date), 'DD Mon') ||
                   coalesce(' (' || string_agg(distinct lower(channel), ', ') || ')', '') || ' · email only to verified addresses'
                 from outreach_candidates where not dry_run and run_date = (select max(run_date) from outreach_candidates where not dry_run))
            when d.key = 'RESEARCH' then (select coalesce(sum(nullif(dm.metrics->>'deep_researched', '')::numeric), 0) || ' companies researched in 3 days · '
                   || (select count(*) from co where co.created_at >= now() - interval '3 days' and co.universe_status = 'QUALIFIED') || ' qualified'
                 from department_run_metrics dm where dm.recorded_at >= now() - interval '3 days')
            else (select nullif(concat_ws(' · ',
                   case when qq.review > 0 then qq.review || case when qq.review = 1 then ' outreach draft' else ' outreach drafts' end || ' waiting for Adam' end,
                   case when qq.to_verify > 0 then qq.to_verify || case when qq.to_verify = 1 then ' decision-maker email' else ' decision-maker emails' end || ' waiting for verification' end,
                   case when qq.gaps > 0 then 'finding emails for ' || qq.gaps || case when qq.gaps = 1 then ' qualified company' else ' qualified companies' end end,
                   case when qq.no_dm > 0 then 'finding the decision maker at ' || qq.no_dm || case when qq.no_dm = 1 then ' company' else ' companies' end end), '') from q qq where qq.key = d.key)
          end,
        'last_action', (select f.x from feed f where f.x->>'agent' = d.key limit 1),
        'today', coalesce((select s from m where m.key = d.key and m.w = 'today'), (select s from sm where sm.key = d.key and sm.w = 'today')),
        'd3', coalesce((select s from m where m.key = d.key and m.w = 'd3'), (select s from sm where sm.key = d.key and sm.w = 'd3')),
        'queues', (select to_jsonb(qq) - 'key' from q qq where qq.key = d.key),
        'blockers', (select coalesce(jsonb_agg(case when jsonb_typeof(x) = 'object' then x else jsonb_build_object('text', x #>> '{}', 'hard', false) end), '[]')
                       from blk, jsonb_array_elements(blk.list) x where blk.key = d.key))
        order by case d.v3_role when 'DIRECTOR' then 0 when 'MANAGER' then 1 else 2 end, d.sort) from dir d join st s on s.key = d.key),
    'feed', (select coalesce(jsonb_agg(x), '[]') from feed),
    'email_desk', v_snap->'email_desk', 'email_gaps', v_snap->'email_gaps', 'email_report', v_snap->'email_report', 'radar', v_snap->'radar')
  into v;
  return v;
end $$;
revoke all on function public.directors_snapshot() from public, anon, authenticated;

create or replace function public.hq_directors()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  return directors_snapshot();
end $$;
revoke all on function public.hq_directors() from public, anon;
grant execute on function public.hq_directors() to authenticated;
