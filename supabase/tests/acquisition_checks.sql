-- Daily acquisition policy: read-only database checks (22 Nov 2026). Run as one statement (Supabase SQL editor or MCP execute_sql).
-- Returns one row per check with ok = true/false and the observed value. Changes nothing.
with
d as (select max(run_date) dt from daily_outreach_runs where run_date <= (now() at time zone 'Africa/Cairo')::date),
q as (select q.* from daily_outreach_queue q, d where q.run_date = d.dt),
live as (select * from q where lane in ('TODAY', 'RESERVE') and state = 'QUEUED'),
ready as (select * from q where lane in ('TODAY', 'RESERVE') and state in ('QUEUED', 'SENT')),
run as (select r.* from daily_outreach_runs r, d where r.run_date = d.dt),
fns as (select p.proname, has_function_privilege('anon', p.oid, 'execute') anon_x, has_function_privilege('authenticated', p.oid, 'execute') auth_x,
               pg_get_functiondef(p.oid) def
          from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('outreach_queue_build', 'hq_outreach_lanes', 'hq_outreach_draft', 'outreach_learning_refresh', 'outreach_learning_weights',
                             'outreach_ramp_review', 'outreach_send_allowance', 'outreach_send_health', 'outreach_act_now_count', 'email_auth_state')),
ramp as (select
   (outreach_ramp_decide('{"stage":0}', '{"pass":true,"fresh":true}', '{}')->>'allowed')::int healthy_s1,
   (outreach_ramp_decide('{"stage":4}', '{"pass":true,"fresh":true}', '{}')->>'allowed')::int healthy_s5,
   (outreach_ramp_decide('{"stage":9}', '{"pass":true,"fresh":true}', '{}')->>'allowed')::int clamped,
   (outreach_ramp_decide('{"stage":2}', '{"pass":false,"fresh":true}', '{}')->>'allowed')::int auth_fail,
   (outreach_ramp_decide('{"stage":2}', '{"pass":true,"fresh":false}', '{}')->>'allowed')::int auth_stale,
   (outreach_ramp_decide('{"stage":2}', '{"pass":true,"fresh":true}', '{"clean_sends":10,"clean_bounces":2}')->>'allowed')::int bounce_small,
   (outreach_ramp_decide('{"stage":2}', '{"pass":true,"fresh":true}', '{"clean_sends":40,"clean_bounces":1}')->>'allowed')::int bounce_ok,
   (outreach_ramp_decide('{"stage":2}', '{"pass":true,"fresh":true}', '{"clean_sends":40,"clean_bounces":2}')->>'allowed')::int bounce_rate,
   (outreach_ramp_decide('{"stage":2}', '{"pass":true,"fresh":true}', '{"bounces_3d":2}')->>'allowed')::int spike,
   (outreach_ramp_decide('{"stage":2,"flags":{"spam_complaints":1}}', '{"pass":true,"fresh":true}', '{}')->>'allowed')::int spam,
   (outreach_ramp_decide('{"stage":2,"flags":{"reputation_warning":true}}', '{"pass":true,"fresh":true}', '{}')->>'allowed')::int reputation,
   (outreach_ramp_decide('{"stage":2,"stopped":"Adam"}', '{"pass":true,"fresh":true}', '{}')->>'allowed')::int stopped),
alw as (select outreach_send_allowance() a, outreach_act_now_count() warm, (select value from system_config where key = 'send_ramp_state') st),
checks(name, ok, observed) as (
  select 'Daily task populated the queue (run recorded for the day, rows written)',
         (select count(*) from run) = 1 and (select count(*) from q) > 0,
         jsonb_build_object('date', (select dt from d), 'rows', (select count(*) from q), 'built_at', (select built_at from run), 'runs', (select runs from run))
  union all select 'Today''s 25: never more than 25, and every Today / Reserve record passed all 11 gates',
         (select count(*) from q where lane = 'TODAY' and state in ('QUEUED', 'SENT')) <= 25
           and not exists (select 1 from ready r where cardinality(r.failed) > 0 or exists (select 1 from jsonb_each(r.gates) g where g.value <> 'true'::jsonb))
           and exists (select 1 from pg_constraint where conname = 'daily_outreach_queue_ready_gates'),
         jsonb_build_object('today', (select count(*) from q where lane = 'TODAY' and state in ('QUEUED', 'SENT')), 'reserve', (select count(*) from q where lane = 'RESERVE' and state = 'QUEUED'),
                            'shortfall', (select shortfall from run))
  union all select 'Quality gates reject: Needs-contact rows fail a person/route gate; Needs-draft rows fail only the draft gate',
         not exists (select 1 from q where lane = 'NEEDS_CONTACT' and state = 'QUEUED'
                      and not (q.failed && array['real_account_person', 'decision_maker', 'contact_route', 'provenance', 'route_classification']))
           and not exists (select 1 from q where lane = 'NEEDS_DRAFT' and state = 'QUEUED' and q.failed <> array['personalised_draft']),
         jsonb_build_object('needs_contact', (select count(*) from q where lane = 'NEEDS_CONTACT' and state = 'QUEUED'),
                            'needs_draft', (select count(*) from q where lane = 'NEEDS_DRAFT' and state = 'QUEUED'), 'gate_failures', (select gate_failures from run))
  union all select 'One company, one active route (unique index present; no company twice among live rows of the day)',
         exists (select 1 from pg_indexes where indexname = 'daily_outreach_queue_one_route')
           and not exists (select 1 from q where state = 'QUEUED' group by company_id having count(*) > 1),
         jsonb_build_object('companies_twice', (select count(*) from (select company_id from q where state = 'QUEUED' group by company_id having count(*) > 1) x))
  union all select 'DNC: no live Today / Reserve record reaches a do-not-contact person or inbox',
         not exists (select 1 from live l join contacts c on c.id in (l.contact_id, l.route_contact_id) where c.do_not_contact),
         jsonb_build_object('dnc_hits', (select count(*) from live l join contacts c on c.id in (l.contact_id, l.route_contact_id) where c.do_not_contact))
  union all select 'Route provenance visible on every Today / Reserve record (address, label, source type, source link or Clay / provider)',
         not exists (select 1 from ready r where r.route_email is null or r.route_label is null or r.route_source_type is null
                      or not (coalesce(r.route_source_url, '') ~ '^https?://' or r.route_source_type in ('CLAY', 'VERIFICATION_PROVIDER'))),
         jsonb_build_object('by_source_type', (select jsonb_object_agg(coalesce(route_source_type, '-'), n) from (select route_source_type, count(*) n from ready group by 1) x))
  union all select 'Classifications truthful: Clay stays "not independently verified" (LOW); Instagram only when the address came from public Instagram',
         not exists (select 1 from q where route_canonical = 'CLAY_WORK_EMAIL' and (route_source_type <> 'CLAY' or confidence <> 'LOW' or route_label !~* 'not independently verified'))
           and not exists (select 1 from q where route_canonical = 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM' and route_source_type <> 'INSTAGRAM_PUBLIC')
           and not exists (select 1 from q join contacts c on c.id = q.route_contact_id
                            where q.route_source_type = 'INSTAGRAM_PUBLIC' and coalesce(q.route_source_url, '') !~* 'instagram\.com'
                              and coalesce(c.email_source_type, '') not in ('INSTAGRAM', 'INSTAGRAM_PROFILE'))
           and not exists (select 1 from q join contacts c on c.id = q.route_contact_id where q.route_source_type = 'CLAY' and coalesce(c.email_source_type, '') <> 'CLAY')
           and outreach_source_type('CLAY', null, null, null) = 'CLAY' and outreach_source_type('INSTAGRAM', null, null, null) = 'INSTAGRAM_PUBLIC'
           and outreach_source_type(null, 'https://www.instagram.com/x', null, null) = 'INSTAGRAM_PUBLIC'
           and outreach_source_type('OFFICIAL_SITE', 'https://x.com/contact', 'https://x.com', null) = 'OFFICIAL_WEBSITE'
           and outreach_source_type(null, null, null, null) is null,
         jsonb_build_object('clay_rows', (select count(*) from q where route_canonical = 'CLAY_WORK_EMAIL'), 'instagram_rows', (select count(*) from q where route_source_type = 'INSTAGRAM_PUBLIC'))
  union all select 'Warm outranks cold: no warm or active relationship in the cold queue; warm work counted first in the allowance',
         not exists (select 1 from live l where relationship_state(l.company_id) <> 'COLD')
           and ((select a from alw)->>'warm_pending')::int = (select warm from alw),
         jsonb_build_object('warm_pending', (select warm from alw))
  union all select 'Ramp: 5 -> 25 only on clean signals; auth, staleness, bounces, spikes, spam, reputation or a stop give 0',
         r.healthy_s1 = 5 and r.healthy_s5 = 25 and r.clamped = 25 and r.auth_fail = 0 and r.auth_stale = 0 and r.bounce_small = 0
           and r.bounce_ok = 15 and r.bounce_rate = 0 and r.spike = 0 and r.spam = 0 and r.reputation = 0 and r.stopped = 0,
         to_jsonb(r) from ramp r
  union all select 'Allowance never exceeds the current stage cap; remaining never negative',
         ((select a from alw)->>'daily_cap')::int <= ((select a from alw)->>'stage_cap')::int and ((select a from alw)->>'remaining')::int >= 0,
         (select a from alw) - array['auth', 'health', 'flags', 'rule']
  union all select 'Manual-send rule intact: no new function writes emails, tasks or drafts or calls out; policy text unchanged',
         not exists (select 1 from fns where def ~* '(insert\s+into\s+(public\.)?(outbound_emails|tasks|message_drafts|outreach_candidates)|update\s+(public\.)?outbound_emails|net\.http|http_post|pg_net)')
           and coalesce((select value->>'sending' from system_config where key = 'acquisition_engine'), '') ~ 'NO COLD AUTO-SEND',
         jsonb_build_object('functions_checked', (select count(*) from fns))
  union all select 'Grants: anon none; authenticated only hq_outreach_lanes and hq_outreach_draft',
         not bool_or(f.anon_x) and bool_and(case when f.proname in ('hq_outreach_lanes', 'hq_outreach_draft') then f.auth_x else not f.auth_x end),
         jsonb_object_agg(f.proname, f.auth_x) from fns f
  union all select 'RLS on every new table',
         bool_and(c.relrowsecurity), jsonb_object_agg(c.relname, c.relrowsecurity)
    from pg_class c where c.relnamespace = 'public'::regnamespace
     and c.relname in ('daily_outreach_queue', 'daily_outreach_runs', 'outreach_learning', 'outreach_categories', 'outreach_coverage')
  union all select 'Schedule: ramp review, morning build, hourly top-up and ledger refresh are active',
         (select count(*) from cron.job where active and jobname in ('outreach-ramp-review', 'outreach-queue-morning', 'outreach-queue-topup', 'outreach-learning')) = 4,
         (select jsonb_object_agg(jobname, schedule) from cron.job where jobname like 'outreach-%')
  union all select 'Coverage: all 36 active streams map to the 13 categories',
         (select count(*) from commercial_streams s join outreach_coverage c on c.stream_code = s.code where s.active) = (select count(*) from commercial_streams where active)
           and (select count(*) from outreach_categories) = 13,
         jsonb_build_object('mapped', (select count(*) from outreach_coverage), 'categories', (select count(*) from outreach_categories))
  union all select 'Learning ledger: 21 Nov batch excluded from the clean cohort; nothing earlier counted as clean',
         (select count(*) from outreach_learning where cohort = 'CLEAN' and (sent_at at time zone 'Africa/Cairo')::date < date '2026-11-22') = 0
           and (select count(*) from outreach_learning where (sent_at at time zone 'Africa/Cairo')::date = date '2026-11-21' and cohort <> 'EXCLUDED_21_NOV') = 0,
         (select jsonb_object_agg(cohort, n) from (select cohort, count(*) n from outreach_learning group by 1) x)
  union all select 'Email authentication gate reads PASS when SPF, DKIM and DMARC pass (OPEN is normalised)',
         (select value->'last_live_check'->>'gate' from system_config where key = 'email_authentication') in ('PASS', 'CLOSED')
           and (email_auth_state()->>'pass')::boolean = ((select value->'last_live_check'->>'gate' from system_config where key = 'email_authentication') = 'PASS'),
         email_auth_state() - 'checked_at'
)
select name, ok, observed from checks;
