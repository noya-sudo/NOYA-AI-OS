-- One commercial attribution model for all of HQ (Adam, 19 Oct 2026): "I do not want competing definitions across HQ."
-- Every screen (Dashboard funnel and top row, Director scorecards, weekly review, the segment table, the Advisor, work orders,
-- the commercial performance review) reads these three functions. Historical evidence is never changed to make figures agree.
--
-- MESSAGE COUNT vs UNIQUE COMPANY COUNT:
--   messages  = every recorded message (interactions, plus mailbox messages on CRM-linked threads not yet logged).
--   companies = each company counted once, on the date it FIRST reached the step. Weeks therefore add up to the all-time totals.
--
-- Message kinds (commercial_messages):
--   FIRST         outreach message that starts a sequence (no outreach to that company in the previous 120 days)
--   FOLLOW_UP     outreach message before the company's first reply, inside a sequence
--   REPLY         inbound message after NOYA's first outreach
--   CONVERSATION  NOYA message after the company replied (relationship work, not outreach)
--   INBOUND       inbound message from a company that wrote to NOYA first (inbound lead, not a reply)
--   RESPONSE      NOYA message to a company that wrote first

create or replace function public.commercial_messages()
returns table(company_id uuid, channel text, direction text, at timestamptz, kind text, source text, ref text)
language sql stable security definer set search_path = public, extensions as $$
  with co as materialized (
    select c.id, registrable_domain(c.website) dom, c.created_at from companies c where coalesce(c.notes, '') not like '%MERGED_INTO:%'),
  dm as materialized (select distinct on (dom) dom, id from co where dom is not null order by dom, created_at, id),
  gm as materialized (  -- mailbox messages on threads not yet logged in the CRM
    select g.gmail_message_id, g.direction, g.sent_at, g.company_id gcid, t.company_id tcid, registrable_domain(g.counterpart_domains[1]) gdom
      from gmail_history_messages g left join gmail_history_threads t on t.gmail_thread_id = g.gmail_thread_id
     where g.category = 'COMMERCIAL' and g.direction in ('INBOUND', 'OUTBOUND') and g.sent_at is not null and g.interaction_id is null
       and coalesce(t.relevant, true) and coalesce(t.hq_status, '') <> 'DISMISSED'
       and not exists (select 1 from interactions i where i.external_message_id = g.gmail_message_id)),
  raw as materialized (
    select i.company_id cid, i.channel ch, i.direction dir, i.occurred_at at_, 'CRM'::text src, i.id::text ref
      from interactions i join co on co.id = i.company_id
     where i.channel in ('EMAIL', 'LINKEDIN', 'INSTAGRAM') and i.direction in ('INBOUND', 'OUTBOUND') and i.occurred_at is not null
    union all
    select coalesce(c1.id, c2.id, dm.id), 'EMAIL', gm.direction, gm.sent_at, 'MAILBOX', gm.gmail_message_id
      from gm left join co c1 on c1.id = gm.gcid left join co c2 on c2.id = gm.tcid left join dm on dm.dom = gm.gdom),
  m as materialized (select * from raw where cid is not null),
  f as materialized (
    select m.cid, min(m.at_) filter (where m.dir = 'OUTBOUND') first_out, min(m.at_) filter (where m.dir = 'INBOUND') first_in from m group by m.cid),
  r as materialized (
    select f.cid, f.first_out is not null and (f.first_in is null or f.first_out < f.first_in) outreach_led,
           (select min(m.at_) from m where m.cid = f.cid and m.dir = 'INBOUND' and m.at_ > f.first_out) first_reply
      from f)
  select m.cid, m.ch, m.dir, m.at_,
    case when not r.outreach_led then case when m.dir = 'INBOUND' then 'INBOUND' else 'RESPONSE' end
         when m.dir = 'INBOUND' then 'REPLY'
         when r.first_reply is not null and m.at_ > r.first_reply then 'CONVERSATION'
         when exists (select 1 from m p where p.cid = m.cid and p.dir = 'OUTBOUND' and p.at_ < m.at_ and p.at_ > m.at_ - interval '120 days') then 'FOLLOW_UP'
         else 'FIRST' end,
    m.src, m.ref
    from m join r on r.cid = m.cid
$$;

-- One row per company that has any commercial evidence: when it first reached each step.
--   positive = a reply classified positive / meeting request / needs information / referral, a meeting or call requested, a thread
--              at meeting stage, an opportunity moved to interested, call, proposal, negotiation or won, or any meeting
--   meeting  = booked or held: a recorded meeting, or a dated meeting task (a request is positive, not a meeting)
--   brief    = a Studio level 2-3 document actually sent, a concept used with the counterpart, or a project brief
--   proposal = an opportunity at proposal, negotiation or won, a recorded proposal value, or a Studio proposal sent
--   won      = an opportunity won (won_at) or a Studio output marked won
create or replace function public.commercial_facts()
returns table(company_id uuid, name text, dir text, universe_status text, source text,
              first_outreach_at timestamptz, last_outreach_at timestamptz, outreach_msgs int, first_msgs int, follow_up_msgs int,
              first_reply_at timestamptz, reply_msgs int, inbound_first_at timestamptz,
              last_inbound_at timestamptz, last_outbound_at timestamptz,
              positive_at timestamptz, meeting_at timestamptz, brief_at timestamptz, proposal_at timestamptz, won_at timestamptz,
              open_opp boolean, any_opp boolean, closed boolean)
language sql stable security definer set search_path = public, extensions as $$
  with co as materialized (
    select c.id, c.name, c.universe_status,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) dir
      from companies c where coalesce(c.notes, '') not like '%MERGED_INTO:%'),
  m as materialized (select * from commercial_messages()),
  ma as materialized (
    select m.company_id cid,
      min(m.at) filter (where m.kind in ('FIRST', 'FOLLOW_UP')) first_out, max(m.at) filter (where m.kind in ('FIRST', 'FOLLOW_UP')) last_out,
      count(*) filter (where m.kind in ('FIRST', 'FOLLOW_UP')) out_n, count(*) filter (where m.kind = 'FIRST') first_n, count(*) filter (where m.kind = 'FOLLOW_UP') fu_n,
      min(m.at) filter (where m.kind = 'REPLY') first_reply, count(*) filter (where m.kind = 'REPLY') reply_n,
      min(m.at) filter (where m.kind = 'INBOUND') inbound_first,
      max(m.at) filter (where m.direction = 'INBOUND') last_in, max(m.at) filter (where m.direction = 'OUTBOUND') last_outb
      from m group by m.company_id),
  gt as materialized (
    select t.company_id cid, min(t.last_inbound_at) at_ from gmail_history_threads t
     where t.company_id is not null and t.relationship_state = 'MEETING' and coalesce(t.relevant, true) and coalesce(t.hq_status, '') <> 'DISMISSED' group by 1),
  pos as materialized (  -- positive: classified positive reply, a meeting or call requested, or a thread at meeting stage
    select x.cid, min(x.at_) at_ from (
      select i.company_id cid, i.occurred_at at_ from interactions i
       where i.direction = 'INBOUND' and i.company_id is not null and coalesce(i.summary, '') ~ '^(POSITIVE|MEETING_REQUEST|NEEDS_INFO|REFERRAL)'
      union all select t.company_id, t.created_at from tasks t where t.company_id is not null and t.title like 'MEETING REQUESTED%'
      union all select gt.cid, gt.at_ from gt) x group by 1),
  opp as materialized (
    select o.company_id cid,
      min(o.updated_at) filter (where o.status in ('INTERESTED', 'CALL_REQUIRED', 'MEETING', 'PROPOSAL', 'NEGOTIATION', 'WON')) pos_at,
      min(o.updated_at) filter (where o.status in ('PROPOSAL', 'NEGOTIATION', 'WON') or o.proposal_value is not null) prop_at,
      min(coalesce(o.won_at, o.updated_at)) filter (where o.status = 'WON' or o.won_at is not null) won_at,
      bool_or(o.status not in ('LOST', 'ARCHIVED', 'LONG_TERM')) open_opp
      from opportunities o where o.company_id is not null group by 1),
  mt as materialized (  -- meeting booked or held: a recorded meeting, or a meeting task with a date (not a request)
    select x.cid, min(x.at_) at_ from (
      select i.company_id cid, i.occurred_at at_ from interactions i where i.channel = 'MEETING' and i.company_id is not null
      union all select t.company_id, t.created_at from tasks t where t.company_id is not null and t.title like 'MEETING --%') x group by 1),
  br as materialized (
    select x.cid, min(x.at_) at_ from (
      select s.company_id cid, s.sent_at at_ from studio_outputs s where s.level >= 2 and s.sent_at is not null and s.company_id is not null
      union all select cc.company_id, cc.created_at from creative_concepts cc where cc.status = 'USED' and cc.company_id is not null
      union all select p.company_id, p.created_at from projects p where p.brief is not null and p.company_id is not null) x group by 1),
  sp as materialized (
    select s.company_id cid, min(s.proposal_at) prop_at, min(s.won_at) won_at from studio_outputs s where s.company_id is not null group by 1)
  select co.id, co.name, co.dir, co.universe_status,
    case when ma.first_out is not null then 'OUTREACH' when ma.inbound_first is not null then 'INBOUND' end,
    ma.first_out, ma.last_out, coalesce(ma.out_n, 0)::int, coalesce(ma.first_n, 0)::int, coalesce(ma.fu_n, 0)::int,
    ma.first_reply, coalesce(ma.reply_n, 0)::int, ma.inbound_first, ma.last_in, ma.last_outb,
    nullif(least(coalesce(pos.at_, 'infinity'), coalesce(opp.pos_at, 'infinity'), coalesce(mt.at_, 'infinity')), 'infinity'),
    mt.at_, br.at_,
    nullif(least(coalesce(opp.prop_at, 'infinity'), coalesce(sp.prop_at, 'infinity')), 'infinity'),
    nullif(least(coalesce(opp.won_at, 'infinity'), coalesce(sp.won_at, 'infinity')), 'infinity'),
    coalesce(opp.open_opp, false), opp.cid is not null,
    (opp.cid is not null and not coalesce(opp.open_opp, false)) or coalesce(co.universe_status, '') in ('PARKED', 'EXCLUDED')
    from co
    left join ma on ma.cid = co.id left join pos on pos.cid = co.id left join opp on opp.cid = co.id
    left join mt on mt.cid = co.id left join br on br.cid = co.id left join sp on sp.cid = co.id
   where ma.cid is not null or pos.cid is not null or mt.cid is not null or br.cid is not null or sp.cid is not null
      or opp.pos_at is not null or opp.prop_at is not null or opp.won_at is not null
$$;

-- Windowed figures, overall and by Director. A company counts in the window in which it FIRST reached a step.
-- reply_rate is a cohort rate (of the companies first contacted in the window, how many have replied since) and is only given
-- from 20 companies contacted.
create or replace function public.commercial_metrics(p_since timestamptz, p_until timestamptz default null)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  with w as (select coalesce(p_since, '-infinity'::timestamptz) s, coalesce(p_until, now()) u),
  f as materialized (select f.*, coalesce(f.dir, 'UNATTRIBUTED') d from commercial_facts() f),
  m as materialized (select m.*, coalesce(f.d, 'UNATTRIBUTED') d from commercial_messages() m left join f on f.company_id = m.company_id),
  mg as (
    select grouping(m.d) g, m.d,
      count(*) filter (where m.kind = 'FIRST') first_messages, count(*) filter (where m.kind = 'FOLLOW_UP') follow_ups,
      count(*) filter (where m.kind in ('FIRST', 'FOLLOW_UP') and m.channel = 'EMAIL') email,
      count(*) filter (where m.kind in ('FIRST', 'FOLLOW_UP') and m.channel = 'LINKEDIN') linkedin,
      count(*) filter (where m.kind in ('FIRST', 'FOLLOW_UP') and m.channel = 'INSTAGRAM') instagram,
      count(*) filter (where m.kind = 'REPLY') reply_messages, count(*) filter (where m.kind = 'INBOUND') inbound_messages
      from m, w where m.at >= w.s and m.at < w.u group by rollup(m.d)),
  cg as (
    select grouping(f.d) g, f.d,
      count(*) filter (where f.first_outreach_at >= w.s and f.first_outreach_at < w.u) contacted,
      count(*) filter (where f.first_reply_at >= w.s and f.first_reply_at < w.u) replied,
      count(*) filter (where f.inbound_first_at >= w.s and f.inbound_first_at < w.u) inbound_leads,
      count(*) filter (where f.positive_at >= w.s and f.positive_at < w.u) positive,
      count(*) filter (where f.meeting_at >= w.s and f.meeting_at < w.u) meetings,
      count(*) filter (where f.brief_at >= w.s and f.brief_at < w.u) briefs,
      count(*) filter (where f.proposal_at >= w.s and f.proposal_at < w.u) proposals,
      count(*) filter (where f.won_at >= w.s and f.won_at < w.u) wins,
      count(*) filter (where f.first_outreach_at >= w.s and f.first_outreach_at < w.u and f.first_reply_at is not null) cohort_replied,
      count(*) filter (where f.first_outreach_at >= w.s and f.first_outreach_at < w.u and f.positive_at is not null) cohort_positive
      from f, w group by rollup(f.d)),
  rv as (
    select grouping(x.d) g, x.d, jsonb_object_agg(x.currency, x.amt) filter (where x.currency is not null) revenue from (
      select coalesce(r.director, f.d, 'UNATTRIBUTED') d, r.currency, sum(r.amount) amt
        from revenue r left join f on f.company_id = r.company_id, w
       where r.payment_status <> 'CANCELLED' and coalesce(r.revenue_date::timestamptz, r.received_at, r.created_at) >= w.s
         and coalesce(r.revenue_date::timestamptz, r.received_at, r.created_at) < w.u group by 1, 2) x group by rollup(x.d)),
  obj as (
    select coalesce(cg.g, mg.g, 1) g, coalesce(cg.d, mg.d) d, jsonb_build_object(
      'messages', jsonb_build_object('outreach', coalesce(mg.first_messages, 0) + coalesce(mg.follow_ups, 0), 'first', coalesce(mg.first_messages, 0),
                                     'follow_ups', coalesce(mg.follow_ups, 0), 'email', coalesce(mg.email, 0), 'linkedin', coalesce(mg.linkedin, 0),
                                     'instagram', coalesce(mg.instagram, 0), 'replies', coalesce(mg.reply_messages, 0), 'inbound', coalesce(mg.inbound_messages, 0)),
      'companies', jsonb_build_object('contacted', coalesce(cg.contacted, 0), 'replied', coalesce(cg.replied, 0), 'inbound_leads', coalesce(cg.inbound_leads, 0),
                                      'positive', coalesce(cg.positive, 0), 'meetings', coalesce(cg.meetings, 0), 'briefs', coalesce(cg.briefs, 0),
                                      'proposals', coalesce(cg.proposals, 0), 'wins', coalesce(cg.wins, 0)),
      'cohort', jsonb_build_object('contacted', coalesce(cg.contacted, 0), 'replied', coalesce(cg.cohort_replied, 0), 'positive', coalesce(cg.cohort_positive, 0),
                                   'reply_rate_pct', case when coalesce(cg.contacted, 0) >= 20 then round(100.0 * cg.cohort_replied / cg.contacted) end),
      'revenue', coalesce((select rv.revenue from rv where rv.g = coalesce(cg.g, mg.g, 1) and rv.d is not distinct from coalesce(cg.d, mg.d)), '{}'::jsonb)) j
      from cg full join mg on mg.g = cg.g and mg.d is not distinct from cg.d)
  select jsonb_build_object('since', (select s from w), 'until', (select u from w), 'model', 'canonical v1 (19 Oct 2026)',
    'totals', coalesce((select j from obj where g = 1), '{}'::jsonb),
    'by_director', coalesce((select jsonb_object_agg(d, j) from obj where g = 0), '{}'::jsonb))
$$;

revoke all on function public.commercial_messages(), public.commercial_facts(), public.commercial_metrics(timestamptz, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------- Read models on the canonical layer
-- Director scorecards: same definitions as the Dashboard. Sent = first messages (new outreach); every other column counts each
-- company once, in the window where it first reached the step. Reply rate = of the companies first contacted in the window, the
-- share that replied; only from 20 companies.
create or replace function public.director_scorecards()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  with dirs as (select key, name, sort from agent_registry where v3_role = 'DIRECTOR' and kind = 'ACQUISITION'),
  per(p, since) as (values ('d7', now() - interval '7 days'), ('d30', now() - interval '30 days'), ('all', '-infinity'::timestamptz)),
  f as materialized (select * from commercial_facts()),
  m as materialized (select m.*, f.dir from commercial_messages() m join f on f.company_id = m.company_id),
  q as materialized (
    select agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) dir, c.universe_added_at
      from companies c where c.universe_status = 'QUALIFIED' and coalesce(c.notes, '') not like '%MERGED_INTO:%'),
  cov as (select coalesce((select payload->'coverage' from hq_read_cache where key = 'advisor'), '{}'::jsonb) j),
  card as (
    select d.key, per.p, jsonb_build_object(
      'qualified', (select count(*) from q where q.dir = d.key and q.universe_added_at >= per.since),
      'sent_email', (select count(*) from m where m.dir = d.key and m.kind = 'FIRST' and m.channel = 'EMAIL' and m.at >= per.since),
      'sent_other', (select count(*) from m where m.dir = d.key and m.kind = 'FIRST' and m.channel <> 'EMAIL' and m.at >= per.since),
      'follow_ups', (select count(*) from m where m.dir = d.key and m.kind = 'FOLLOW_UP' and m.at >= per.since),
      'contacted', (select count(*) from f where f.dir = d.key and f.first_outreach_at >= per.since),
      'replies', (select count(*) from f where f.dir = d.key and f.first_reply_at >= per.since),
      'cohort_replied', (select count(*) from f where f.dir = d.key and f.first_outreach_at >= per.since and f.first_reply_at is not null),
      'positive', (select count(*) from f where f.dir = d.key and f.positive_at >= per.since),
      'meetings', (select count(*) from f where f.dir = d.key and f.meeting_at >= per.since),
      'briefs', (select count(*) from f where f.dir = d.key and f.brief_at >= per.since),
      'proposals', (select count(*) from f where f.dir = d.key and f.proposal_at >= per.since),
      'wins', (select count(*) from f where f.dir = d.key and f.won_at >= per.since),
      'revenue', (select coalesce(jsonb_object_agg(currency, amt), '{}'::jsonb) from (
                    select r.currency, sum(r.amount) amt from revenue r left join f on f.company_id = r.company_id
                     where coalesce(r.director, f.dir) = d.key and r.payment_status <> 'CANCELLED'
                       and coalesce(r.revenue_date::timestamptz, r.received_at, r.created_at) >= per.since group by 1) x)) j
      from dirs d cross join per),
  card2 as (
    select key, p, j || jsonb_build_object('sent', (j->>'sent_email')::int + (j->>'sent_other')::int,
      'reply_rate_pct', case when (j->>'contacted')::int >= 20 then round(100.0 * (j->>'cohort_replied')::int / (j->>'contacted')::int) end,
      'sample', case when (j->>'contacted')::int >= 20 then 'OK' else 'INSUFFICIENT' end) j
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
    'method', 'Canonical model (same as the Dashboard). Sent = first messages of a sequence (follow-ups shown separately). Replied, positive, meetings, briefs, proposals and wins count each company once, in the window where it first reached the step. Reply rate = of the companies first contacted in the window, the share that has replied, only from 20 companies. Briefs = Studio level 2-3 documents actually sent, concepts used and project briefs.')
$$;

-- The Dashboard table "From outreach to business" (this week, last 30 days, by Director) in the keys the screen reads.
-- sent_* = first messages by channel; replies, positive, meetings, concepts (briefs), proposals and won = companies.
create or replace function public.commercial_funnel_compat(p_since timestamptz)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  with f as materialized (select f.*, coalesce(f.dir, 'UNATTRIBUTED') d from commercial_facts() f),
  m as materialized (select m.*, coalesce(f.d, 'UNATTRIBUTED') d from commercial_messages() m left join f on f.company_id = m.company_id where m.at >= p_since),
  ds as (select distinct d from f union select distinct d from m),
  one as (
    select ds.d, jsonb_build_object(
      'sent_email', (select count(*) from m where m.d = ds.d and m.kind = 'FIRST' and m.channel = 'EMAIL'),
      'sent_linkedin', (select count(*) from m where m.d = ds.d and m.kind = 'FIRST' and m.channel = 'LINKEDIN'),
      'sent_instagram', (select count(*) from m where m.d = ds.d and m.kind = 'FIRST' and m.channel = 'INSTAGRAM'),
      'sent', (select count(*) from m where m.d = ds.d and m.kind = 'FIRST'),
      'follow_ups', (select count(*) from m where m.d = ds.d and m.kind = 'FOLLOW_UP'),
      'contacted', (select count(*) from f where f.d = ds.d and f.first_outreach_at >= p_since),
      'replies', (select count(*) from f where f.d = ds.d and f.first_reply_at >= p_since),
      'positive', (select count(*) from f where f.d = ds.d and f.positive_at >= p_since),
      'meetings', (select count(*) from f where f.d = ds.d and f.meeting_at >= p_since),
      'concepts', (select count(*) from f where f.d = ds.d and f.brief_at >= p_since),
      'proposals', (select count(*) from f where f.d = ds.d and f.proposal_at >= p_since),
      'won', (select count(*) from f where f.d = ds.d and f.won_at >= p_since),
      'wins', (select count(*) from f where f.d = ds.d and f.won_at >= p_since)) j
      from ds),
  tot as (
    select jsonb_build_object(
      'sent_email', (select count(*) from m where m.kind = 'FIRST' and m.channel = 'EMAIL'),
      'sent_linkedin', (select count(*) from m where m.kind = 'FIRST' and m.channel = 'LINKEDIN'),
      'sent_instagram', (select count(*) from m where m.kind = 'FIRST' and m.channel = 'INSTAGRAM'),
      'follow_ups', (select count(*) from m where m.kind = 'FOLLOW_UP'),
      'contacted', (select count(*) from f where f.first_outreach_at >= p_since),
      'replies', (select count(*) from f where f.first_reply_at >= p_since),
      'inbound_leads', (select count(*) from f where f.inbound_first_at >= p_since),
      'positive', (select count(*) from f where f.positive_at >= p_since),
      'meetings', (select count(*) from f where f.meeting_at >= p_since),
      'concepts', (select count(*) from f where f.brief_at >= p_since),
      'proposals', (select count(*) from f where f.proposal_at >= p_since),
      'won', (select count(*) from f where f.won_at >= p_since),
      'revenue', (select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amt)), '[]'::jsonb)
                    from (select currency, sum(amount) amt from revenue where coalesce(revenue_date::timestamptz, received_at, created_at) >= p_since
                            and payment_status <> 'CANCELLED' group by 1) r)) j)
  select jsonb_build_object('totals', (select j from tot), 'by_director', coalesce((select jsonb_object_agg(d, j) from one), '{}'::jsonb))
$$;
revoke all on function public.commercial_funnel_compat(timestamptz) from public, anon, authenticated;

-- Reply attribution by send week: each company counted once, in the week of its first outreach message and the channel of that
-- message; replied / positive / meetings = whether that company has reached the step since.
create or replace function public.commercial_cohorts(p_weeks int default 8)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  with f as materialized (
    select f.*, (select m.channel from commercial_messages() m where m.company_id = f.company_id and m.kind = 'FIRST' order by m.at limit 1) ch
      from commercial_facts() f
     where f.first_outreach_at >= date_trunc('week', now()) - (greatest(least(coalesce(p_weeks, 8), 26), 1) - 1) * interval '1 week'),
  ch as (select coalesce(ch, 'EMAIL') ch, count(*) sent, count(*) filter (where first_reply_at is not null) replied,
                count(*) filter (where positive_at is not null) positive, count(*) filter (where meeting_at is not null) meetings
           from f group by 1)
  select jsonb_build_object('weeks', greatest(least(coalesce(p_weeks, 8), 26), 1),
    'by_channel', coalesce((select jsonb_object_agg(ch, jsonb_build_object('sent', sent, 'replied', replied, 'positive', positive, 'meetings', meetings,
                              'reply_rate_pct', case when sent >= 20 then round(100.0 * replied / sent) end)) from ch), '{}'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('cohort', w, 'director', d, 'channel', c, 'sent', n, 'replied', r, 'positive', p, 'meetings', mt) order by w desc, n desc)
                        from (select date_trunc('week', first_outreach_at)::date w, coalesce(dir, 'UNATTRIBUTED') d, coalesce(ch, 'EMAIL') c, count(*) n,
                                     count(*) filter (where first_reply_at is not null) r, count(*) filter (where positive_at is not null) p,
                                     count(*) filter (where meeting_at is not null) mt
                                from f group by 1, 2, 3) x), '[]'::jsonb),
    'method', 'Canonical model. Each company counts once, in the week and channel of its first outreach message. Replied, positive and meetings show whether that company has reached the step since. Rates only from 20 companies.')
$$;
revoke all on function public.commercial_cohorts(int) from public, anon, authenticated;

-- Weekly review: the last 7 days on the canonical model.
create or replace function public.hq_weekly_review()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_admin text := hq_admin_email(); v_health jsonb := director_channel_health(); v jsonb; v_weak record; v_best record;
begin
  with w(k, s, e) as (values ('this', now() - interval '7 days', now()), ('prev', now() - interval '14 days', now() - interval '7 days')),
  f as materialized (select * from commercial_facts()),
  mm as materialized (
    select m.*, f.dir, (select l.classification from gmail_sync_ledger l join interactions i on i.external_message_id = l.gmail_message_id
                         where m.source = 'CRM' and i.id::text = m.ref limit 1) cls
      from commercial_messages() m left join f on f.company_id = m.company_id where m.at > now() - interval '14 days'),
  m as (select w.k,
          count(*) filter (where mm.kind = 'FIRST' and mm.at >= w.s and mm.at < w.e) sent,
          count(*) filter (where mm.kind = 'FIRST' and mm.channel = 'EMAIL' and mm.at >= w.s and mm.at < w.e) sent_email,
          count(*) filter (where mm.kind = 'FIRST' and mm.channel = 'LINKEDIN' and mm.at >= w.s and mm.at < w.e) sent_linkedin,
          count(*) filter (where mm.kind = 'FOLLOW_UP' and mm.at >= w.s and mm.at < w.e) follow_ups,
          (select count(*) from f where f.first_outreach_at >= w.s and f.first_outreach_at < w.e) contacted,
          (select count(*) from f where f.first_reply_at >= w.s and f.first_reply_at < w.e) replies,
          (select count(*) from f where f.positive_at >= w.s and f.positive_at < w.e) positive,
          count(*) filter (where mm.kind = 'REPLY' and coalesce(mm.cls, 'UNKNOWN') = 'UNKNOWN' and mm.at >= w.s and mm.at < w.e) unclassified
          from w left join mm on true group by w.k, w.s, w.e)
  select jsonb_build_object(
    'period', jsonb_build_object('from', now() - interval '7 days', 'to', now()),
    'this_week', (select to_jsonb(m) - 'k' from m where k = 'this'), 'previous_week', (select to_jsonb(m) - 'k' from m where k = 'prev'),
    'reply_rate_pct', (select case when count(*) >= 20 then round(100.0 * count(*) filter (where first_reply_at is not null) / count(*)) end
                         from f where first_outreach_at > now() - interval '7 days'),
    'positive_reply_rate_pct', (select case when count(*) >= 20 then round(100.0 * count(*) filter (where positive_at is not null) / count(*)) end
                                  from f where first_outreach_at > now() - interval '7 days'),
    'meetings', (select count(*) from f where meeting_at > now() - interval '7 days'),
    'proposals', (select count(*) from f where proposal_at > now() - interval '7 days'),
    'wins', (select count(*) from f where won_at > now() - interval '7 days'),
    'verified_emails', (select count(*) from contact_email_verifications where provider_status = 'valid' and created_at > now() - interval '7 days'),
    'email_drafts', (select count(*) from outreach_candidates where not dry_run and channel = 'EMAIL' and draft is not null and created_at > now() - interval '7 days'),
    'linkedin_drafts', (select count(*) from outreach_candidates where not dry_run and channel = 'LINKEDIN' and draft is not null and created_at > now() - interval '7 days'),
    'by_director', (select jsonb_agg(jsonb_build_object('director', h.key, 'label', advisor_agent_label(h.key), 'coverage_pct', h.value->'coverage_pct',
                        'with_dm', h.value->'with_dm', 'verified', h.value->'verified', 'linkedin_fallback', h.value->'linkedin_fallback', 'target', (select value->'by_director'->h.key from system_config where key = 'weekly_send_targets'),
                        'sent', (select count(*) from mm where mm.dir = h.key and mm.kind = 'FIRST' and mm.at > now() - interval '7 days'),
                        'replies', (select count(*) from f where f.dir = h.key and f.first_reply_at > now() - interval '7 days'))
                        order by (h.value->>'with_dm')::int desc) from jsonb_each(v_health) h where h.key <> 'PARTNERSHIPS'),
    'strongest_opportunities', (select coalesce(jsonb_agg(jsonb_build_object('company', c.name, 'status', o.status, 'next', o.next_action) order by o.priority desc nulls last), '[]'::jsonb)
                                  from (select * from opportunities where status in ('CALL_REQUIRED', 'MEETING', 'PROPOSAL', 'NEGOTIATION', 'CONTACTED')
                                         order by case status when 'NEGOTIATION' then 0 when 'PROPOSAL' then 1 when 'MEETING' then 2 when 'CALL_REQUIRED' then 3 else 4 end, priority desc nulls last limit 3) o
                                  join companies c on c.id = o.company_id),
    'method', 'Canonical model, same as the Dashboard. Sent = first messages of a sequence (follow-ups shown separately). Replies, positive, meetings, proposals and wins = companies reaching the step for the first time in the period. Rates are cohort rates (of the companies first contacted in the period, how many replied), shown only from 20 companies.')
  into v;
  select key, (value->>'coverage_pct')::int cov, (value->>'with_dm')::int dm, (value->>'linkedin_fallback')::int li, (value->>'email_gap')::int gap,
         (value->>'needs_verification')::int nv into v_weak from jsonb_each(v_health)
   where key <> 'PARTNERSHIPS' and (value->>'with_dm')::int >= 8 and coalesce((value->>'coverage_pct')::int, 0) < 30
   order by array_position(array['BRANDS', 'WEDDINGS', 'TRAVEL', 'HOSPITALITY', 'CORPORATE'], key) nulls last, coalesce((value->>'coverage_pct')::int, 0), (value->>'with_dm')::int desc limit 1;
  select h.key into v_best from jsonb_each(v_health) h
   where h.key <> 'PARTNERSHIPS' order by coalesce((h.value->>'coverage_pct')::int, 0) desc, (h.value->>'verified')::int desc limit 1;
  return v || jsonb_build_object(
    'attribution', commercial_cohorts(8), 'hunter_funnel', hunter_daily_funnel(7), 'acquisition', acquisition_health(),
    'weakest_bottleneck', case when v_weak.key is not null then advisor_agent_label(v_weak.key) || ': ' || coalesce(v_weak.cov, 0) || '% email coverage across ' || v_weak.dm || ' companies with a decision maker' end,
    'recommended_allocation', case when v_weak.key is not null then
      'Next week: ' || case when v_weak.li > v_weak.gap + v_weak.nv then 'point the Email Finder and verification capacity at ' || advisor_agent_label(v_weak.key) || ' first ('
          || v_weak.li || ' with public email research exhausted)' else 'give Email Intelligence and verification capacity to ' || advisor_agent_label(v_weak.key) || ' first' end
      || '; keep discovery steady where coverage is already highest ('
      || advisor_agent_label(v_best.key) || ').' end);
end $$;

-- ---------------------------------------------------------------- Screens patched onto the canonical layer (applied live in the
-- same order as canonical_hq_command .. canonical_directors_snapshot_replies). Each patch asserts its anchor matches once.

-- hq_command (Dashboard "Where each company stands now" and the top row): stages, reached counts and the 30-day
-- positive / meeting tiles come from commercial_facts / commercial_metrics. canonical_30 and canonical_all carry the totals.
do $do$
declare v_src text := pg_get_functiondef('hq_command()'::regprocedure); a text; b text; i int; pairs text[] := array[
$a$declare v_admin text := hq_admin_email(); v jsonb; v_ceo jsonb;$a$,
$a$declare v_admin text := hq_admin_email(); v jsonb; v_ceo jsonb; v_m30 jsonb := commercial_metrics(now() - interval '30 days'); v_mall jsonb := commercial_metrics(null);$a$,
$a$     where t.company_id is not null and t.inbound > 0 and t.outbound > 0 and coalesce(t.relevant, true) and coalesce(t.hq_status, '') <> 'DISMISSED'),
  ev as materialized ($a$,
$a$     where t.company_id is not null and t.inbound > 0 and t.outbound > 0 and coalesce(t.relevant, true) and coalesce(t.hq_status, '') <> 'DISMISSED'),
  cf as materialized (select * from commercial_facts()),
  ev as materialized ($a$,
$a$      exists (select 1 from studio_outputs s where s.company_id = co.id and s.level >= 2 and s.sent_at is not null)
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
        or exists (select 1 from opportunities o where o.company_id = co.id and o.status in ('CONTACTED', 'FOLLOW_UP')) outreach,$a$,
$a$      exists (select 1 from cf where cf.company_id = co.id and cf.brief_at is not null) brief,
      exists (select 1 from cf where cf.company_id = co.id and cf.meeting_at is not null) meeting,
      exists (select 1 from cf where cf.company_id = co.id and cf.positive_at is not null) positive,
      exists (select 1 from cf where cf.company_id = co.id and (cf.first_reply_at is not null or cf.inbound_first_at is not null)) replied,
      exists (select 1 from cf where cf.company_id = co.id and cf.first_outreach_at is not null) outreach,$a$,
$a$        when universe_status in ('RESEARCHING', 'NEEDS_REVIEW') or open_opp then 1 end rank
      from ev),$a$,
$a$        when universe_status in ('RESEARCHING', 'NEEDS_REVIEW') or open_opp then 1 end rank,
      case when paid then 14 when proj_done then 13 when proj_active then 12 when won then 11 when nego then 10 when prop then 9
        when brief and (replied or positive or meeting) then 8 when meeting then 7 when positive then 6 when replied then 5 when outreach then 4
        when universe_status = 'QUALIFIED' and contact_ready then 3 when universe_status = 'QUALIFIED' then 2 else 1 end peak
      from ev),$a$,
$a$'reached', case when n.rank > 0 then (select count(*) from stg where stg.rank >= n.rank) end,$a$,
$a$'reached', case when n.rank > 0 then (select count(*) from stg where stg.peak >= n.rank) end,$a$,
$a$      'meetings_30', coalesce((v_ceo->'funnel'->'d30'->>'meetings')::int, 0),
      'positive_30', coalesce((v_ceo->'funnel'->'d30'->>'positive')::int, 0),$a$,
$a$      'meetings_30', coalesce((v_m30->'totals'->'companies'->>'meetings')::int, 0),
      'positive_30', coalesce((v_m30->'totals'->'companies'->>'positive')::int, 0),
      'canonical_30', v_m30->'totals', 'canonical_all', v_mall->'totals',$a$,
$a$'method', 'Each company sits at the furthest stage it has reached$a$,
$a$'method', 'Canonical model, one definition across HQ. Now = where each company stands today (a company that moved on, or was lost or parked, leaves the earlier stage). Reached = every company that ever got to the stage, including those later lost or parked. Replied = replied to outreach or wrote to NOYA first. Meeting = booked or held (a request counts as positive). Each company sits at the furthest stage it has reached$a$];
begin
  for i in 0 .. array_length(pairs, 1) / 2 - 1 loop
    a := pairs[2*i+1]; b := pairs[2*i+2];
    if (length(v_src) - length(replace(v_src, a, ''))) / length(a) <> 1 then raise exception 'anchor % not unique', i; end if;
    v_src := replace(v_src, a, b);
  end loop;
  execute v_src;
end $do$;

-- hq_advisor: 30-day replies per Director count companies, and "messages sent" means outreach messages only.
do $do$
declare v_src text := pg_get_functiondef('hq_advisor()'::regprocedure); r text[]; i int; n int;
  pairs text[] := array[
$a$with ft as \(select i\.company_id, min\(i\.occurred_at\) first_at from interactions i\s+where i\.direction = 'OUTBOUND' and i\.channel <> 'WEBSITE' and i\.company_id is not null group by 1\)$a$,
$a$with ft as (select cf.company_id, cf.first_outreach_at first_at from commercial_facts() cf where cf.first_outreach_at is not null)$a$,
$a$for r in select agent_key_of\(company_lane\(c\.acquisition_lane, c\.prospect_segment, c\.vertical_override, c\.company_type\), c\.company_type, c\.notes\) agent,\s+count\(\*\) filter \(where i\.direction = 'INBOUND'\) replies, count\(\*\) filter \(where i\.direction = 'OUTBOUND'\) sent\s+from interactions i join companies c on c\.id = i\.company_id\s+where i\.occurred_at > now\(\) - interval '30 days' and i\.channel <> 'WEBSITE' group by 1 order by 2 desc, 3 desc loop$a$,
$a$for r in select cf.dir agent, count(*) filter (where cf.first_reply_at > now() - interval '30 days') replies, count(*) filter (where cf.first_outreach_at > now() - interval '30 days') sent
             from commercial_facts() cf where cf.dir is not null group by 1
            having count(*) filter (where cf.first_outreach_at > now() - interval '30 days' or cf.first_reply_at > now() - interval '30 days') > 0 order by 2 desc, 3 desc loop$a$,
$a$r\.replies \|\| ' repl' \|\| case when r\.replies = 1 then 'y' else 'ies' end\s+\|\| ' from ' \|\| r\.sent \|\| ' sent \(' \|\| round\(100\.0 \* r\.replies / nullif\(r\.sent, 0\)\) \|\| '%\)'$a$,
$a$r.replies || case when r.replies = 1 then ' company replied, ' else ' companies replied, ' end || r.sent || ' contacted in 30 days'$a$,
$a$' sent in 30 days, no reply yet — check targeting and angle'$a$,
$a$' companies contacted in 30 days, no reply yet — check targeting and angle'$a$,
$a$select count\(\*\) into v_n from interactions where occurred_at > v_since and direction = 'INBOUND' and channel <> 'WEBSITE'$a$,
$a$select count(*) into v_n from commercial_messages() cm where cm.at > v_since and cm.kind in ('REPLY', 'INBOUND')$a$,
$a$select count\(\*\) into v_n from interactions where occurred_at > v_since and direction = 'OUTBOUND'$a$,
$a$select count(*) into v_n from commercial_messages() cm where cm.at > v_since and cm.kind in ('FIRST', 'FOLLOW_UP')$a$,
$a$' message' \|\| case when v_n = 1 then '' else 's' end \|\| ' sent'$a$,
$a$' outreach message' || case when v_n = 1 then '' else 's' end || ' sent'$a$];
begin
  for i in 0 .. array_length(pairs, 1) / 2 - 1 loop
    n := regexp_count(v_src, pairs[2*i+1]);
    if n <> 1 then raise exception 'pattern % matched % times', i, n; end if;
    v_src := regexp_replace(v_src, pairs[2*i+1], replace(pairs[2*i+2], '\', '\\'));
  end loop;
  execute v_src;
end $do$;

-- commercial_weekly_metrics (segment table): new outreach and follow-ups from commercial_messages, the rest companies.
do $do$
declare v_src text := pg_get_functiondef('commercial_weekly_metrics(integer)'::regprocedure); i int; n int;
  pairs text[] := array[
$a$  wk as \(select generate_series$a$,
$a$  cf as materialized (select * from commercial_facts()),
  cm as materialized (select * from commercial_messages()),
  wk as (select generate_series$a$,
$a$    union all select date_trunc\('week', i\.occurred_at\), sg\.s, 'sends'[\s\S]*?where o\.won_at is not null\),$a$,
$a$    union all select date_trunc('week', m.at), sg.s, 'sends' from cm m join seg sg on sg.id = m.company_id where m.kind = 'FIRST'
    union all select date_trunc('week', m.at), sg.s, 'follow_ups' from cm m join seg sg on sg.id = m.company_id where m.kind = 'FOLLOW_UP'
    union all select date_trunc('week', f.first_reply_at), sg.s, 'replies' from cf f join seg sg on sg.id = f.company_id where f.first_reply_at is not null
    union all select date_trunc('week', f.positive_at), sg.s, 'positive' from cf f join seg sg on sg.id = f.company_id where f.positive_at is not null
    union all select date_trunc('week', f.meeting_at), sg.s, 'meetings' from cf f join seg sg on sg.id = f.company_id where f.meeting_at is not null
    union all select date_trunc('week', f.proposal_at), sg.s, 'proposals' from cf f join seg sg on sg.id = f.company_id where f.proposal_at is not null
    union all select date_trunc('week', f.won_at), sg.s, 'wins' from cf f join seg sg on sg.id = f.company_id where f.won_at is not null),$a$,
$a$'sends', count\(\*\) filter \(where ev\.k = 'sends'\),$a$,
$a$'sends', count(*) filter (where ev.k = 'sends'), 'follow_ups', count(*) filter (where ev.k = 'follow_ups'),$a$,
$a$'note', 'Sends/replies are logged interactions \(Gmail-tracked email \+ hand-logged LinkedIn/WhatsApp\)\. Allocation changes are recommendations only\.'$a$,
$a$'note', 'Canonical model, same as the Dashboard. New outreach = first messages of a sequence. Follow-ups = messages sent before a reply. Replied, positive, meetings, proposals and wins = companies, counted once in the week they first reached the step. Allocation changes are recommendations only.'$a$];
begin
  for i in 0 .. array_length(pairs, 1) / 2 - 1 loop
    n := regexp_count(v_src, pairs[2*i+1]);
    if n <> 1 then raise exception 'pattern % matched % times', i, n; end if;
    v_src := regexp_replace(v_src, pairs[2*i+1], pairs[2*i+2]);
  end loop;
  execute v_src;
end $do$;

-- work_order_eval: work-order progress on the same definitions.
do $do$
declare v_src text := pg_get_functiondef('work_order_eval(uuid)'::regprocedure); i int; n int;
  pairs text[] := array[
$a$  with mc as materialized \(select company_id from work_order_companies\(s\)\)$a$,
$a$  with mc as materialized (select company_id from work_order_companies(s)),
  cf as materialized (select f.* from commercial_facts() f join mc on mc.company_id = f.company_id),
  cm as materialized (select x.* from commercial_messages() x join mc on mc.company_id = x.company_id)$a$,
$a$    'sent', \(select count\(distinct i\.company_id\)[\s\S]*?where o\.won_at >= v_since\)\)$a$,
$a$    'sent', (select count(*) from cm where cm.kind = 'FIRST' and cm.channel = 'EMAIL' and cm.at >= v_since),
    'replies', (select count(*) from cf where cf.first_reply_at >= v_since),
    'positive', (select count(*) from cf where cf.positive_at >= v_since),
    'meetings', (select count(*) from cf where cf.meeting_at >= v_since),
    'proposals', (select count(*) from cf where cf.proposal_at >= v_since),
    'wins', (select count(*) from cf where cf.won_at >= v_since))$a$];
begin
  for i in 0 .. array_length(pairs, 1) / 2 - 1 loop
    n := regexp_count(v_src, pairs[2*i+1]);
    if n <> 1 then raise exception 'pattern % matched % times', i, n; end if;
    v_src := regexp_replace(v_src, pairs[2*i+1], pairs[2*i+2]);
  end loop;
  execute v_src;
end $do$;

-- ops_metric EMAIL_SENDS_7D: first email messages in 7 days.
do $do$
declare v_src text := pg_get_functiondef('ops_metric(text)'::regprocedure); n int;
  pat text := $a$when 'EMAIL_SENDS_7D' then \(select count\(\*\)::numeric from interactions i where i\.direction = 'OUTBOUND'[\s\S]*?\)\)\s*\n(\s*)when 'OPEN_SOCIAL_DRAFTS'$a$;
begin
  n := regexp_count(v_src, pat);
  if n <> 1 then raise exception 'EMAIL_SENDS_7D pattern matched % times', n; end if;
  v_src := regexp_replace(v_src, pat, $r$when 'EMAIL_SENDS_7D' then (select count(*)::numeric from commercial_messages() m where m.kind = 'FIRST' and m.channel = 'EMAIL' and m.at > now() - interval '7 days')
\1when 'OPEN_SOCIAL_DRAFTS'$r$);
  execute v_src;
end $do$;

-- directors_snapshot: Director card "replies" = companies that first replied in the window.
do $do$
declare v_src text := pg_get_functiondef('directors_snapshot()'::regprocedure); i int; n int;
  pairs text[] := array[
$a$\n  win\(w, since\) as \(values$a$,
$a$
  cfx as materialized (select company_id, first_reply_at from commercial_facts() where first_reply_at is not null),
  win(w, since) as (values$a$,
$a$'replies', \(select count\(\*\) from interactions i join co on co\.id = i\.company_id where \(co\.agent = r\.key or \(r\.key = 'PARTNERSHIPS' and co\.partnership_model is not null\)\)\s+and i\.direction = 'INBOUND' and i\.channel <> 'WEBSITE' and i\.occurred_at >= win\.since\),$a$,
$a$'replies', (select count(*) from cfx join co on co.id = cfx.company_id where (co.agent = r.key or (r.key = 'PARTNERSHIPS' and co.partnership_model is not null))
                             and cfx.first_reply_at >= win.since),$a$];
begin
  for i in 0 .. array_length(pairs, 1) / 2 - 1 loop
    n := regexp_count(v_src, pairs[2*i+1]);
    if n <> 1 then raise exception 'pattern % matched % times', i, n; end if;
    v_src := regexp_replace(v_src, pairs[2*i+1], pairs[2*i+2]);
  end loop;
  execute v_src;
end $do$;

-- Not a metric change: the agent RPCs called by n8n run under PostgREST's 8 s statement timeout. commercial_director_plan
-- took longer than that in workflow 18's 22:30 run (two failures, 18 Oct), so these RPCs get a function-level 55 s limit,
-- which PostgREST honours. Applied as agent_rpc_statement_timeouts.
do $do$
declare r record;
begin
  for r in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('commercial_director_plan', 'email_finder_queue', 'email_verification_queue', 'email_gap_queue',
                                                          'email_gap_list', 'enrichment_queue', 'cold_route_sweep', 'official_inbox_classify')
  loop
    execute format('alter function %s set statement_timeout = %L', r.fn, '55s');
  end loop;
end $do$;
notify pgrst, 'reload config';
