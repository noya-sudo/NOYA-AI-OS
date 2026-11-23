-- Final acquisition engine (22 Nov 2026): read-only checks. Run with the MCP execute_sql (returns one row per check).
-- Nothing here writes, sends, submits or buys.
with
rd as (select max(run_date) d from daily_outreach_runs),
q as (select * from daily_outreach_queue where run_date = (select d from rd)),
inv as (select value->'inventory' v from system_config where key = 'acquisition_engine'),
fns as (
  select p.proname, pg_get_functiondef(p.oid) def,
         has_function_privilege('anon', p.oid, 'execute') anon_x, has_function_privilege('authenticated', p.oid, 'execute') auth_x
    from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('outreach_queue_build', 'route_rank_of', 'form_type_label', 'form_type_classify', 'route_research_next_batch', 'route_research_ingest',
                       'form_message_quality', 'form_draft_next_batch', 'form_prepare_save', 'hq_form_detail', 'hq_form_action', 'form_submission_record',
                       'outreach_draft_repair', 'research_credit_budget', 'engine_self_correct', 'hq_engine_health', 'discovery_next_batch', 'discovery_record',
                       'clay_spend_record', 'hq_outreach_lanes', 'hq_outreach_draft')),
checks(name, ok, observed) as (
  select 'Builder v2: every queue row carries the 14 READY gates',
         bool_and((select count(*) from jsonb_object_keys(q.gates)) = 14
                  and q.gates ?& array['real_account_person', 'stream', 'commercial_fit', 'project_hypothesis', 'commercial_reason', 'decision_maker', 'contact_route',
                                       'provenance', 'route_classification', 'personalised_draft', 'no_dnc', 'no_company_conflict', 'research_current', 'next_action']),
         jsonb_build_object('rows', count(*)) from q where q.state in ('QUEUED', 'SENT') and q.built_at > now() - interval '2 days'
  union all select 'READY lanes (Ready today, Form ready, Reserve) hold only records that pass all 14 gates',
         coalesce(bool_and(cardinality(q.failed) = 0 and not exists (select 1 from jsonb_each_text(q.gates) g where g.value <> 'true')), true),
         jsonb_object_agg(coalesce(q.lane, '?'), 1) from q where q.lane in ('TODAY', 'FORM_READY', 'RESERVE') and q.state = 'QUEUED'
  union all select 'Family cap: no family above its cap in Ready today + Form ready (25% of the target unless a documented override)',
         coalesce(bool_and(x.n <= coalesce(case when ((select v from inv)->'family_cap_overrides'->>x.family) ~ '^[0-9]+$' then ((select v from inv)->'family_cap_overrides'->>x.family)::int end,
                                           ceil(coalesce(((select v from inv)->>'family_cap_share')::numeric, 0.25) * coalesce(((select v from inv)->>'ready_target')::int, 75))::int)), true),
         coalesce(jsonb_object_agg(x.family, x.n), '{}'::jsonb)
    from (select family, count(*) n from q where lane in ('TODAY', 'FORM_READY') and state in ('QUEUED', 'SENT') group by family) x
  union all select 'Weddings override is documented (never dominant)',
         ((select v from inv)->'family_cap_overrides' ? 'WEDDINGS_EVENTS') and coalesce(((select v from inv)->'family_cap_overrides'->'_reason'->>'WEDDINGS_EVENTS'), '') <> '',
         (select v from inv)->'family_cap_overrides'
  union all select 'One account, one active cold route: a company appears at most once across the ready lanes',
         not exists (select 1 from q where lane in ('TODAY', 'FORM_READY', 'RESERVE') and state = 'QUEUED' group by company_id having count(*) > 1),
         jsonb_build_object('ready_rows', (select count(*) from q where lane in ('TODAY', 'FORM_READY', 'RESERVE') and state = 'QUEUED'))
  union all select 'An approved form locks the account: no email-ready row for a company whose form is approved',
         not exists (select 1 from q join contact_forms f on f.company_id = q.company_id and f.status = 'APPROVED'
                      where q.lane in ('TODAY', 'RESERVE') and q.state = 'QUEUED' and coalesce(q.route_channel, 'EMAIL') = 'EMAIL'),
         jsonb_build_object('approved_forms', (select count(*) from contact_forms where status = 'APPROVED'))
  union all select 'Best route recorded on every ready row (channel, rank, label, source)',
         coalesce(bool_and(q.route_channel is not null and q.route_rank between 1 and 11 and q.route_label is not null and q.route_source_type is not null), true),
         coalesce(jsonb_object_agg(q.route_channel, 1), '{}'::jsonb) from q where q.lane in ('TODAY', 'FORM_READY', 'RESERVE') and q.state = 'QUEUED'
  union all select 'Route ranking follows the configured order (named < management < validated < Instagram < commercial form < Clay < inbox < general form < LinkedIn)',
         route_rank_of('EMAIL', 'PUBLIC_NAMED_EMAIL') < route_rank_of('EMAIL', 'MANAGEMENT_EMAIL') and route_rank_of('EMAIL', 'MANAGEMENT_EMAIL') < route_rank_of('EMAIL', 'VALID_VERIFIED')
           and route_rank_of('EMAIL', 'VALID_VERIFIED') < route_rank_of('EMAIL', 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM')
           and route_rank_of('EMAIL', 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM') < route_rank_of('FORM', null, 'PARTNERSHIP')
           and route_rank_of('FORM', null, 'PARTNERSHIP') < route_rank_of('EMAIL', 'CLAY_WORK_EMAIL') and route_rank_of('EMAIL', 'CLAY_WORK_EMAIL') < route_rank_of('EMAIL', 'OFFICIAL_PUBLISHED_INBOX')
           and route_rank_of('EMAIL', 'OFFICIAL_PUBLISHED_INBOX') < route_rank_of('FORM', null, 'CONTACT') and route_rank_of('FORM', null, 'CONTACT') < route_rank_of('LINKEDIN', null),
         jsonb_build_object('named', route_rank_of('EMAIL', 'PUBLIC_NAMED_EMAIL'), 'form', route_rank_of('FORM', null, 'PARTNERSHIP'), 'inbox', route_rank_of('EMAIL', 'OFFICIAL_PUBLISHED_INBOX'))
  union all select 'Readiness holds stay out of READY (a held draft fails the gate it names, not the draft gate)',
         not exists (select 1 from q join outreach_candidates oc on oc.id = q.candidate_id
                      where q.lane in ('TODAY', 'RESERVE') and q.state = 'QUEUED' and oc.status = 'REVIEW_REQUIRED' and oc.review_reason is not null),
         jsonb_build_object('held_in_needs_contact', (select count(*) from q join outreach_candidates oc on oc.id = q.candidate_id
                                                         where q.lane = 'NEEDS_CONTACT' and oc.status = 'REVIEW_REQUIRED' and oc.review_reason is not null))
  union all select 'Failed-draft repair never re-drafts a deliberate hold or a passing draft',
         (select def from fns where proname = 'outreach_draft_repair') ~ 'oc\.review_reason is null' and (select def from fns where proname = 'outreach_draft_repair') ~ 'qa_status, ''''\) <> ''PASS''',
         (select value from system_config where key = 'draft_repair_last')
  union all select 'Forms: commercial only, approval before submission, prepared copy before approval (constraints present)',
         (select count(*) from pg_constraint where conrelid = 'public.contact_forms'::regclass and conname in ('contact_forms_commercial_only', 'contact_forms_approval_first', 'contact_forms_prepared_copy')) = 3
           and not exists (select 1 from contact_forms where status = 'SUBMITTED' and approved_at is null)
           and not exists (select 1 from contact_forms where status in ('QUALIFIED', 'PREPARED', 'APPROVED', 'SUBMITTED') and (form_type = 'NON_COMMERCIAL' or login_required)),
         (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from contact_forms group by 1) x)
  union all select 'Form classifier: partnership / vendor forms are commercial; careers, support and privacy forms are not',
         form_type_classify('https://x.com/partner-with-us', 'Partnership enquiries') <> 'NON_COMMERCIAL'
           and form_type_classify('https://x.com/careers', 'Apply for a job') = 'NON_COMMERCIAL'
           and form_type_classify('https://x.com/support', 'Customer support returns') = 'NON_COMMERCIAL',
         jsonb_build_object('partner', form_type_classify('https://x.com/partner-with-us', 'Partnership enquiries'), 'vendor', form_type_classify('https://x.com/vendors', 'Become a supplier'))
  union all select 'Form copy gate: links and banned phrases block; short copy needs an edit; a clean personalised note passes',
         form_message_quality('Egypt for Example Co', 'Hello, see https://example.com', 1000, 'Example Co')->>'status' = 'BLOCKED'
           and form_message_quality('Hi', 'Hello, a short note. Adam Elshazly', 1000, 'Example Co')->>'status' = 'NEEDS_EDIT'
           and form_message_quality('An Egypt programme for Example Co',
                 'Hello, Example Co announced a new private travel collection this autumn, with journeys designed around small groups and specialist guides. ' ||
                 'One idea: a four-day Cairo and Red Sea programme for your travel designers, with NOYA handling stays, movement, access and on-the-ground hosting quietly in your name. ' ||
                 'Would a short introduction call next week be useful? Adam Elshazly, Founder, NOYA Concierge', 1000, 'Example Co')->>'status' = 'PASS',
         form_message_quality('Hi', 'Hello, a short note. Adam Elshazly', 1000, 'Example Co')
  union all select 'Nothing submits a form without approval: submission record requires APPROVED; HQ action cannot set SUBMITTED',
         (select def from fns where proname = 'form_submission_record') ~ 'cf\.status <> ''APPROVED'''
           and (select def from fns where proname = 'hq_form_action') !~ 'v_new := ''SUBMITTED''',
         null::jsonb
  union all select 'No new function sends, calls out or buys (no HTTP from the database; outbound emails untouched)',
         not exists (select 1 from fns where def ~* '(net\.http|http_post|pg_net|insert\s+into\s+(public\.)?outbound_emails|update\s+(public\.)?outbound_emails)'),
         jsonb_build_object('functions_checked', (select count(*) from fns))
  union all select 'Grants: anon none; authenticated only the five HQ reads/actions',
         not bool_or(f.anon_x) and bool_and(case when f.proname in ('hq_outreach_lanes', 'hq_outreach_draft', 'hq_form_detail', 'hq_form_action', 'hq_engine_health') then f.auth_x else not f.auth_x end),
         jsonb_object_agg(f.proname, f.auth_x) from fns f
  union all select 'RLS on every new table',
         bool_and(c.relrowsecurity), jsonb_object_agg(c.relname, c.relrowsecurity)
    from pg_class c where c.relnamespace = 'public'::regnamespace
     and c.relname in ('contact_forms', 'route_research_log', 'discovery_queries', 'research_credit_ledger', 'outreach_families')
  union all select 'Schedule: draft repair (before W18) and self-correction (after the morning build) are active, with the existing builds',
         (select count(*) from cron.job where active and jobname in ('outreach-draft-repair', 'engine-self-correct', 'outreach-queue-morning', 'outreach-queue-topup')) = 4,
         (select jsonb_object_agg(jobname, schedule) from cron.job where jobname in ('outreach-draft-repair', 'engine-self-correct', 'outreach-queue-morning', 'outreach-queue-topup'))
  union all select 'Engine record: the latest build carries families, mix, channels and the self-correction',
         (select engine ? 'families' and engine ? 'families_ready' and engine ? 'channels' from daily_outreach_runs where run_date = (select d from rd)),
         (select engine - 'families' - 'routes_reserve' from daily_outreach_runs where run_date = (select d from rd))
  union all select 'Credit budget reads Serper, Firecrawl, Clay and Hunter and only recommends (never buys)',
         research_credit_budget() ?& array['serper', 'firecrawl', 'clay', 'hunter']
           and coalesce((select value->>'no_new_spend' from system_config where key = 'research_credits'), '') ~* 'never buys',
         research_credit_budget()->'serper'
  union all select 'Inventory targets: 75 ready (60-80), 100 reserve, 150 needs contact',
         ((select v from inv)->>'ready_target')::int = 75 and ((select v from inv)->>'reserve_target')::int = 100 and ((select v from inv)->>'needs_contact_target')::int = 150,
         (select v from inv) - 'family_cap_overrides'
)
select name, ok, observed from checks;
