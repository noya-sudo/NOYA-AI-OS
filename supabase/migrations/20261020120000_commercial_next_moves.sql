-- NOYA HQ — Commercial Creative Operator (20 Oct 2026)
-- REPLY / MEETING → UNDERSTAND → RECOMMEND → CREATE → ADAM APPROVES → SEND → MEASURE, on the existing CRM, Gmail history,
-- LinkedIn connections and Studio records. No new CRM: one table holds the operator's recommendation per relationship, and
-- the read model falls back to a rule-based baseline (labelled as such) where no recommendation has been written yet.
-- Nothing here sends anything: every action records Adam's choice and hands work to the Studio, the drafter or a task.

-- 1. Studio readiness: what HQ's READY means (Adam could genuinely send it now). One class per document version.
alter table public.studio_documents
  add column if not exists ready_class text,
  add column if not exists ready_reason text,
  add column if not exists ready_checked_at timestamptz;
alter table public.studio_documents add constraint studio_documents_ready_class_check
  check (ready_class is null or ready_class in ('READY_TO_SEND', 'NEEDS_UPDATE', 'INTERNAL_ONLY', 'SUPERSEDED', 'HOLD'));

-- 2. The operator's recommended next move, one live row per relationship (rel_key: co:<company>, li:<connection>, e:<email>).
create table if not exists public.commercial_next_moves (
  id uuid primary key default gen_random_uuid(),
  rel_key text not null,
  kind text not null default 'LIVE' check (kind in ('LIVE', 'REOPEN', 'ACT_NOW')),
  company_id uuid references public.companies(id),
  opportunity_id uuid references public.opportunities(id),
  contact_id uuid references public.contacts(id),
  connection_id uuid references public.linkedin_connections(id),
  person text,
  channel text check (channel in ('EMAIL', 'LINKEDIN', 'CALL', 'MEETING')),
  situation text not null,
  need text,
  value_note text,
  action text not null check (action in ('DRAFT_REPLY', 'SEND_PREPARED', 'ASK_FOR_CALL', 'SEND_ONE_PAGE', 'BUILD_BRIEF', 'BUILD_CONCEPT',
    'BUILD_PROPOSAL', 'BUILD_ITINERARY', 'SCHEDULE_FOLLOWUP', 'RECONNECT', 'HOLD', 'CLOSE')),
  action_label text,
  why_now text,
  message_subject text,
  recommended_message text,
  asset_slug text,
  asset_note text,
  gmail_thread_id text,
  gmail_draft_id text,
  linkedin_url text,
  last_contact_at timestamptz,
  last_by text check (last_by in ('NOYA', 'THEM')),
  recency_band text check (recency_band in ('0-30', '31-90', '3-12M', '12M+')),
  signal jsonb,
  alternatives jsonb not null default '[]'::jsonb,
  sources jsonb not null default '[]'::jsonb,
  status text not null default 'PROPOSED' check (status in ('PROPOSED', 'CHOSEN', 'DONE', 'HELD', 'CLOSED', 'SUPERSEDED')),
  chosen_action text,
  decided_at timestamptz,
  decided_by text,
  hold_until date,
  outcome text,
  created_by text not null default 'Commercial Creative Operator',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.commercial_next_moves enable row level security;
create unique index if not exists commercial_next_moves_live on public.commercial_next_moves (rel_key) where status in ('PROPOSED', 'CHOSEN');
create index if not exists commercial_next_moves_company on public.commercial_next_moves (company_id);
create index if not exists commercial_next_moves_connection on public.commercial_next_moves (connection_id);

-- 3. Recency bands (Adam's rules): 0–30 days normal follow-up; 31–90 contextual reconnect; 3–12 months only with a credible new
-- reason; 12 months+ dormant, personal reconnection only.
create or replace function public.recency_band(p_at timestamptz) returns text
language sql stable set search_path = public as $$
  select case when p_at is null then null
    when p_at > now() - interval '30 days' then '0-30'
    when p_at > now() - interval '90 days' then '31-90'
    when p_at > now() - interval '365 days' then '3-12M'
    else '12M+' end
$$;

-- 4. The whole relationship in one read: CRM interactions, Gmail history, LinkedIn, the live opportunity, Studio documents and
-- outputs. Never treats an existing relationship as cold.
create or replace function public.next_move_context(p_company uuid) returns jsonb
language sql stable security definer set search_path = public as $$
with i as (
  select max(occurred_at) filter (where direction = 'INBOUND') as last_in, max(occurred_at) filter (where direction = 'OUTBOUND') as last_out,
         max(occurred_at) filter (where channel = 'MEETING') as last_meeting, count(*) filter (where channel = 'MEETING') as meetings,
         count(*) filter (where direction = 'INBOUND') as inbound
    from interactions where company_id = p_company and channel <> 'WEBSITE'
), g as (
  select max(last_inbound_at) as last_in, max(last_outbound_at) as last_out, sum(inbound) as inbound, count(*) as threads,
         (array_agg(gmail_thread_id order by last_at desc))[1] as thread,
         (array_agg(left(subject, 120) order by last_at desc))[1] as subject,
         bool_or(relationship_state = 'DO_NOT_CONTACT') as dnc
    from gmail_history_threads where company_id = p_company and relevant
), l as (
  select max(li_last_at) as last_at, max(li_last_in_at) as last_in, count(*) as people, sum(li_in) as inbound,
         (array_agg(li_state order by li_last_at desc nulls last))[1] as state,
         bool_or(li_state = 'DO_NOT_CONTACT' or li_opt_out_at is not null) as dnc
    from linkedin_connections where matched_company_id = p_company
), o as (
  select id, status, next_action, next_action_due, opportunity_type, blocker, proposal_value, contracted_value, currency
    from opportunities where company_id = p_company and status not in ('ARCHIVED', 'LOST', 'WON') order by updated_at desc limit 1
), d as (
  select jsonb_agg(jsonb_build_object('slug', x.slug, 'version', x.version, 'title', x.title, 'stage', x.stage, 'status', x.status,
           'ready_class', x.ready_class, 'ready_reason', x.ready_reason, 'level', x.level, 'audience', x.audience, 'sent_at', x.sent_at)
           order by x.created_at desc) as docs
    from (select distinct on (slug) * from studio_documents where company_id = p_company order by slug, version desc) x
), so as (
  select jsonb_agg(jsonb_build_object('level', level, 'status', status, 'document', document_slug, 'email', email_slug, 'draft', gmail_draft_id,
           'thread', gmail_thread_id, 'sent_at', sent_at, 'reply_at', reply_at, 'send_after', send_after) order by prepared_at desc) as outputs
    from studio_outputs where company_id = p_company
)
select jsonb_build_object(
  'company_id', p_company, 'company', (select name from companies where id = p_company),
  'last_in', greatest(i.last_in, g.last_in, l.last_in), 'last_out', greatest(i.last_out, g.last_out),
  'meetings', i.meetings, 'last_meeting', i.last_meeting,
  'inbound', coalesce(i.inbound, 0) + coalesce(g.inbound, 0) + coalesce(l.inbound, 0),
  'threads', g.threads, 'thread', g.thread, 'subject', g.subject,
  'dnc', coalesce(g.dnc, false) or coalesce(l.dnc, false) or exists (select 1 from companies c where c.id = p_company and c.relationship_status ~* 'do not contact'),
  'state', relationship_state(p_company),
  'linkedin', case when l.people > 0 then jsonb_build_object('people', l.people, 'state', l.state, 'last_at', l.last_at) end,
  'opportunity', (select to_jsonb(o) from o), 'docs', coalesce(d.docs, '[]'::jsonb), 'outputs', coalesce(so.outputs, '[]'::jsonb))
from i cross join g cross join l cross join d cross join so
$$;

-- A LinkedIn connection that is not linked to a CRM company (from Adam's own LinkedIn download).
create or replace function public.next_move_li_context(p_connection uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('connection_id', id, 'company', company,
    'last_in', li_last_in_at, 'last_out', case when li_last_dir in ('OUT', 'OUTBOUND') then li_last_at end,
    'inbound', coalesce(li_in, 0), 'meetings', 0,
    'dnc', coalesce(li_state = 'DO_NOT_CONTACT', false) or li_opt_out_at is not null,
    'linkedin', jsonb_build_object('state', li_state, 'last_at', li_last_at, 'messages', li_messages, 'url', profile_url,
      'person', concat_ws(' ', first_name, last_name), 'position', position),
    'docs', '[]'::jsonb, 'outputs', '[]'::jsonb)
  from linkedin_connections where id = p_connection
$$;

-- 5. The rule-based baseline: what HQ recommends when the operator has not written a recommendation yet (labelled BASELINE).
create or replace function public.next_move_baseline(p_ctx jsonb) returns jsonb
language sql stable set search_path = public as $$
with b as (
  select (p_ctx->>'last_in')::timestamptz as last_in, (p_ctx->>'last_out')::timestamptz as last_out,
         coalesce((p_ctx->>'dnc')::boolean, false) as dnc, p_ctx->>'state' as state,
         coalesce((p_ctx->>'meetings')::int, 0) > 0 or p_ctx #>> '{opportunity,status}' = 'CALL_REQUIRED' as met,
         coalesce((p_ctx->>'inbound')::int, 0) > 0 as replied_before,
         (select x from jsonb_array_elements(coalesce(p_ctx->'docs', '[]'::jsonb)) x
           where x->>'ready_class' = 'READY_TO_SEND' and x->>'sent_at' is null and x->>'stage' <> 'email' limit 1) as ready_doc,
         exists (select 1 from jsonb_array_elements(coalesce(p_ctx->'docs', '[]'::jsonb)) x
                  where x->>'audience' = 'CLIENT' and x->>'stage' in ('brief', 'master', 'concept', 'onepage')) as has_doc
), c as (
  select b.*, greatest(last_in, last_out) as last_at, last_in is not null and last_in >= coalesce(last_out, '-infinity'::timestamptz) as them_last from b
), r as (
  select c.*, recency_band(last_at) as band, current_date - last_at::date as days,
    case
      when dnc then 'CLOSE'
      when state = 'DECLINED_RECENTLY' then 'HOLD'
      when last_at is null then 'NONE'
      when them_last then 'DRAFT_REPLY'
      when ready_doc is not null then 'SEND_PREPARED'
      when met and not has_doc then 'BUILD_BRIEF'
      when last_at > now() - interval '7 days' then 'SCHEDULE_FOLLOWUP'
      when last_at > now() - interval '30 days' then case when replied_before then 'ASK_FOR_CALL' else 'SCHEDULE_FOLLOWUP' end
      when not replied_before then 'HOLD'
      else 'RECONNECT' end as action
    from c
)
select jsonb_build_object('source', 'BASELINE', 'action', action, 'band', band, 'days', days, 'last_at', last_at,
  'last_by', case when last_at is null then null when them_last then 'THEM' else 'NOYA' end, 'asset', ready_doc,
  'situation', case
      when dnc then 'Do not contact.'
      when state = 'DECLINED_RECENTLY' then 'They declined recently.'
      when last_at is null then 'No conversation yet.'
      when them_last then 'They wrote last, ' || days || ' days ago: NOYA owes a reply.'
      else 'NOYA wrote last, ' || days || ' days ago' || case when replied_before then ' (they have replied before).' else ' (no reply yet).' end end,
  'reason', case action
      when 'CLOSE' then 'Never revive a do-not-contact.'
      when 'HOLD' then case when state = 'DECLINED_RECENTLY' then 'A recent decline: reopen only if they come back.'
                            else 'No reply after the follow-up window: leave it, or reopen with a new reason.' end
      when 'NONE' then 'Cold: the Outreach desk handles first contact.'
      when 'DRAFT_REPLY' then 'Reply in the existing thread.'
      when 'SEND_PREPARED' then 'A document has passed review: approve it and send it with its email.'
      when 'BUILD_BRIEF' then 'After a meeting, a tailored brief turns the conversation into a project.'
      when 'SCHEDULE_FOLLOWUP' then 'Give it a week before following up.'
      when 'ASK_FOR_CALL' then 'They have engaged before: ask for twenty minutes with one idea.'
      else case band when '31-90' then 'Reconnect with context from the last conversation.'
                     when '3-12M' then 'Reconnect only with a credible new reason.'
                     else 'Dormant: a personal note only, never a sales follow-up.' end end)
from r
$$;

-- 6. Recommended next action panel (opportunity, company, contact and LinkedIn drawers): the operator's recommendation when there
-- is one, the baseline otherwise, the whole relationship behind it and dated Egypt events for the WHY NOW. Read-only.
create or replace function public.hq_next_move(p_company uuid default null, p_opportunity uuid default null, p_contact uuid default null, p_connection uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_company uuid := p_company; v_ctx jsonb; v_key text;
begin
  if v_company is null and p_opportunity is not null then select company_id into v_company from opportunities where id = p_opportunity; end if;
  if v_company is null and p_contact is not null then select company_id into v_company from contacts where id = p_contact; end if;
  if v_company is null and p_connection is not null then select matched_company_id into v_company from linkedin_connections where id = p_connection; end if;
  if v_company is null and p_connection is null then return jsonb_build_object('ok', false, 'reason', 'RECORD_REQUIRED'); end if;
  v_ctx := case when v_company is not null then next_move_context(v_company) else next_move_li_context(p_connection) end;
  v_key := case when v_company is not null then 'co:' || v_company::text else 'li:' || p_connection::text end;
  return jsonb_build_object('ok', true, 'key', v_key, 'company_id', v_company, 'connection_id', p_connection,
    'operator', (select to_jsonb(m) from commercial_next_moves m
                  where m.rel_key = v_key and (m.status in ('PROPOSED', 'CHOSEN') or (m.status = 'HELD' and coalesce(m.hold_until, current_date) >= current_date))
                  order by (m.status = 'HELD'), m.updated_at desc limit 1),
    'baseline', next_move_baseline(v_ctx),
    'context', v_ctx,
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', coalesce(h.decided_at, h.updated_at), 'action', coalesce(h.chosen_action, h.action), 'status', h.status,
                   'situation', h.situation, 'outcome', h.outcome) order by h.updated_at desc), '[]'::jsonb)
                  from (select * from commercial_next_moves where rel_key = v_key and status in ('DONE', 'CLOSED', 'SUPERSEDED') order by updated_at desc limit 5) h),
    'timing', (select coalesce(jsonb_agg(jsonb_build_object('title', x.title, 'date', x.event_date, 'end', x.event_end, 'city', x.city, 'source', x.source_url,
                   'linked', x.company_id is not distinct from v_company) order by x.event_date), '[]'::jsonb)
                 from (select * from intelligence where event_date between current_date and current_date + 120
                         and ((v_company is not null and company_id = v_company) or (egypt_relevance >= 90 and calendar_status in ('VERIFIED', 'APPROVED')))
                       order by (company_id is not distinct from v_company) desc, event_date limit 5) x));
end $$;

-- 7. Adam chooses. Each action records the choice and hands the work on; nothing is sent:
--    Studio actions → hq_studio_request · Draft reply / Ask for call / Reconnect → the prepared draft, or hq_request_draft ·
--    Schedule follow-up → a task · Hold / Close → recorded on the move.
-- p_key / p_kind: a past conversation that is not in the CRM (a Gmail key such as e:<address>) can still be held or closed.
-- (Live database: the first seven-argument version was renamed hq_next_move_action_v1_retired, with no grants, not dropped.)
create or replace function public.hq_next_move_action(p_action text, p_move uuid default null, p_company uuid default null, p_opportunity uuid default null,
  p_connection uuid default null, p_note text default null, p_until date default null, p_key text default null, p_kind text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_action text := upper(btrim(coalesce(p_action, ''))); m commercial_next_moves%rowtype;
  v_company uuid := p_company; v_ctx jsonb; v_base jsonb; v_key text; r jsonb; v_kind text;
begin
  if v_action not in ('DRAFT_REPLY', 'SEND_PREPARED', 'ASK_FOR_CALL', 'SEND_ONE_PAGE', 'BUILD_BRIEF', 'BUILD_CONCEPT', 'BUILD_PROPOSAL', 'BUILD_ITINERARY',
                      'SCHEDULE_FOLLOWUP', 'RECONNECT', 'HOLD', 'CLOSE') then
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION'); end if;
  if p_move is not null then
    select * into m from commercial_next_moves where id = p_move;
    if not found then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  else
    if v_company is null and p_opportunity is not null then select company_id into v_company from opportunities where id = p_opportunity; end if;
    if v_company is null and p_connection is null and nullif(btrim(coalesce(p_key, '')), '') is null then return jsonb_build_object('ok', false, 'reason', 'RECORD_REQUIRED'); end if;
    if v_company is null and p_connection is null and v_action not in ('HOLD', 'CLOSE', 'SCHEDULE_FOLLOWUP') then
      return jsonb_build_object('ok', false, 'reason', 'ADD_TO_CRM_FIRST'); end if;
    v_key := case when v_company is not null then 'co:' || v_company::text when p_connection is not null then 'li:' || p_connection::text else btrim(p_key) end;
    select * into m from commercial_next_moves where rel_key = v_key and status in ('PROPOSED', 'CHOSEN');
    if not found then
      -- No recommendation written yet: Adam's choice is recorded on a new move built from the baseline.
      if v_company is not null or p_connection is not null then
        v_ctx := case when v_company is not null then next_move_context(v_company) else next_move_li_context(p_connection) end;
        v_base := next_move_baseline(v_ctx);
      end if;
      insert into commercial_next_moves (rel_key, kind, company_id, opportunity_id, connection_id, situation, action, last_contact_at, last_by, recency_band, created_by)
      values (v_key, case when upper(coalesce(p_kind, '')) in ('LIVE', 'REOPEN', 'ACT_NOW') then upper(p_kind) else 'LIVE' end, v_company,
              coalesce(p_opportunity, (v_ctx #>> '{opportunity,id}')::uuid), p_connection,
              coalesce(v_base->>'situation', hq_trim(p_note), 'Past conversation in NOYA Gmail, not in the CRM'), v_action,
              (v_base->>'last_at')::timestamptz, v_base->>'last_by', v_base->>'band', 'HQ baseline (rule-based)')
      returning * into m;
    end if;
  end if;
  v_kind := case v_action when 'SEND_ONE_PAGE' then 'ONE_PAGE_CONCEPT' when 'BUILD_BRIEF' then 'BRIEF' when 'BUILD_PROPOSAL' then 'PROPOSAL'
    when 'BUILD_ITINERARY' then 'ITINERARY'
    when 'BUILD_CONCEPT' then (select case coalesce(c.vertical_override, hq_vertical(c.company_type, null, c.sector))
        when 'WEDDINGS_EVENTS' then 'WEDDING_CONCEPT' when 'CORPORATE' then 'RETREAT_CONCEPT' else 'BRAND_CAMPAIGN_CONCEPT' end
        from companies c where c.id = m.company_id) end;
  if v_action = 'BUILD_CONCEPT' and v_kind is null then v_kind := upper('one_page_concept'); end if;
  if v_kind is not null then
    if m.company_id is null then return jsonb_build_object('ok', false, 'reason', 'COMPANY_REQUIRED'); end if;
    r := hq_studio_request(v_kind, m.company_id, m.opportunity_id, coalesce(hq_trim(p_note), m.situation));
    if (r->>'ok')::boolean is not true and coalesce(r->>'reason', '') <> 'ALREADY_REQUESTED' then return r; end if;
  elsif v_action = 'SCHEDULE_FOLLOWUP' then
    insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
    values (m.company_id, m.contact_id, m.opportunity_id,
      'FOLLOW UP -- ' || coalesce((select name from companies where id = m.company_id), m.person, 'relationship'),
      coalesce(hq_trim(p_note), m.situation), 'NEXT_MOVE_FOLLOW_UP', 'Adam', 'HQ next move', 70, 'OPEN',
      (coalesce(p_until, current_date + 7)::timestamp + interval '9 hours') at time zone 'Europe/London')
    returning jsonb_build_object('task_id', id, 'due', due_at) into r;
  elsif v_action in ('HOLD', 'CLOSE') then
    r := jsonb_build_object('recorded', true);
  elsif m.gmail_draft_id is not null or m.recommended_message is not null or v_action = 'SEND_PREPARED' then
    r := jsonb_build_object('prepared', true, 'gmail_draft_id', m.gmail_draft_id, 'gmail_thread_id', m.gmail_thread_id, 'message', m.recommended_message,
      'subject', m.message_subject, 'linkedin_url', m.linkedin_url, 'asset', m.asset_slug, 'asset_note', m.asset_note);
  else
    r := hq_request_draft(p_channel => case when m.channel = 'LINKEDIN' or (m.company_id is null and m.connection_id is not null) then 'LINKEDIN' else 'EMAIL' end,
      p_voice => 'ADAM_PERSONAL', p_type => case when v_action = 'RECONNECT' then 'RECONNECTION' else 'FOLLOW_UP' end,
      p_connection => m.connection_id, p_contact => m.contact_id, p_company => m.company_id, p_opportunity => m.opportunity_id,
      p_note => coalesce(hq_trim(p_note), m.situation));
    if (r->>'ok')::boolean is not true then return r; end if;
  end if;
  update commercial_next_moves set
      status = case v_action when 'HOLD' then 'HELD' when 'CLOSE' then 'CLOSED' else 'CHOSEN' end,
      chosen_action = v_action, decided_at = now(), decided_by = v_admin,
      hold_until = case when v_action = 'HOLD' then coalesce(p_until, current_date + 14) else hold_until end,
      outcome = coalesce(hq_trim(p_note), outcome), updated_at = now()
    where id = m.id;
  perform hq_audit('NEXT_MOVE_CHOSEN', m.opportunity_id, jsonb_build_object('move_id', m.id, 'action', v_action, 'result', r));
  return jsonb_build_object('ok', true, 'id', m.id, 'action', v_action, 'result', r);
end $$;

-- 8. PAST CONVERSATION — OPPORTUNITY TO REOPEN: two-way Gmail relationships and LinkedIn conversations older than three weeks,
-- read before any cold outreach. Declines, do-not-contact, dismissed or not-relevant relationships and lost opportunities never
-- appear. A relationship the operator has assessed shows its written recommendation instead of the rule.
create or replace function public.hq_reopen_list(p_limit int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with t as (
    select t.*, coalesce('co:' || t.company_id::text, 'ct:' || t.contact_id::text,
             case when cardinality(t.counterpart_domains) > 0 and not email_is_freemail(t.counterpart_domains[1]) then 'd:' || registrable_domain(t.counterpart_domains[1]) end,
             'e:' || t.counterpart_emails[1]) as gkey
      from gmail_history_threads t where t.relevant and t.outbound > 0
  ), g as materialized (
    select gkey, count(*) as threads, sum(inbound) as received, sum(outbound) as sent, max(last_at) as last_at,
           max(last_inbound_at) as last_in, max(last_outbound_at) as last_out,
           (array_agg(gmail_thread_id order by last_inbound_at desc nulls last))[1] as thread,
           (array_agg(left(subject, 120) order by last_at desc))[1] as subject,
           (array_agg(summary order by last_at desc) filter (where summary is not null))[1] as summary,
           (array_agg(company_id::text) filter (where company_id is not null))[1]::uuid as company_id,
           (array_agg(contact_id::text) filter (where contact_id is not null))[1]::uuid as contact_id,
           (array_agg(opportunity_id::text order by last_at desc) filter (where opportunity_id is not null))[1]::uuid as opportunity_id,
           (array_agg(counterpart_emails[1] order by last_inbound_at desc nulls last))[1] as email,
           bool_or(relationship_state = 'DO_NOT_CONTACT') as dnc
      from t group by gkey having sum(inbound) > 0 and max(last_at) < now() - interval '21 days'
  ), c as materialized (
    select g.*, co.name as company, rv.status as review_status, rv.summary as review_summary, rv.their_position,
           coalesce(co.name, nullif(btrim(concat_ws(' ', k.first_name, k.last_name)), ''),
             (select m.from_name from gmail_history_messages m where m.gmail_thread_id = g.thread and m.direction = 'INBOUND' and m.from_name is not null limit 1), g.email) as name,
           g.last_in >= coalesce(g.last_out, '-infinity'::timestamptz) as them_last,
           recency_band(g.last_at) as band, current_date - g.last_at::date as days,
           case when g.company_id is not null then relationship_state(g.company_id) end as rel_state,
           (select o.status from opportunities o where o.id = g.opportunity_id) as opp_status
      from g left join companies co on co.id = g.company_id left join contacts k on k.id = g.contact_id
      left join relationship_reviews rv on rv.key = g.gkey
     where not g.dnc and coalesce(rv.status, '') not in ('NOT_RELEVANT', 'DISMISSED', 'DO_NOT_CONTACT', 'CLOSED', 'EXISTING_PARTNER')
       and (rv.status is not null or coalesce(rv.suggested_status, '') not in ('NOT_RELEVANT', 'EXISTING_PARTNER'))
       and not exists (select 1 from commercial_next_moves m where m.rel_key in (g.gkey, 'co:' || g.company_id::text)
                         and (m.status in ('PROPOSED', 'CHOSEN', 'CLOSED') or (m.status = 'HELD' and coalesce(m.hold_until, current_date) >= current_date)))
  ), gm as (
    select * from c where coalesce(rel_state, '') <> 'DECLINED_RECENTLY' and coalesce(opp_status, '') <> 'LOST'
     order by them_last desc, case band when '31-90' then 1 when '3-12M' then 2 when '12M+' then 3 else 4 end, received desc, last_at desc
     limit greatest(coalesce(p_limit, 30), 1)
  ), li as (
    select l.*, recency_band(l.li_last_at) as band, current_date - l.li_last_at::date as days
      from linkedin_connections l
     where coalesce(l.li_in, 0) > 0 and l.li_last_at < now() - interval '21 days' and l.li_opt_out_at is null
       and coalesce(l.li_state, '') <> 'DO_NOT_CONTACT'
       and not exists (select 1 from commercial_next_moves m where m.rel_key in ('li:' || l.id::text, 'co:' || l.matched_company_id::text)
                         and (m.status in ('PROPOSED', 'CHOSEN', 'CLOSED') or (m.status = 'HELD' and coalesce(m.hold_until, current_date) >= current_date)))
     order by l.li_in desc, l.li_last_at desc limit greatest(coalesce(p_limit, 30), 1)
  )
  select jsonb_build_object('generated_at', now(),
    'operator', (select coalesce(jsonb_agg(to_jsonb(m) || jsonb_build_object('company', co.name) order by m.status = 'HELD', m.updated_at desc), '[]'::jsonb)
                   from commercial_next_moves m left join companies co on co.id = m.company_id
                  where m.kind = 'REOPEN' and (m.status in ('PROPOSED', 'CHOSEN') or (m.status = 'HELD' and coalesce(m.hold_until, current_date) >= current_date))),
    'gmail', (select coalesce(jsonb_agg(jsonb_build_object('key', gkey, 'name', name, 'company', company, 'company_id', company_id, 'contact_id', contact_id,
                'opportunity_id', opportunity_id, 'email', email, 'threads', threads, 'sent', sent, 'received', received, 'last_at', last_at, 'last_in', last_in,
                'last_out', last_out, 'last_by', case when them_last then 'THEM' else 'NOYA' end, 'owes_reply', them_last, 'band', band, 'days', days,
                'thread', thread, 'subject', subject, 'summary', coalesce(review_summary, summary), 'their_position', their_position, 'relationship', rel_state,
                'recommended', case when them_last then 'DRAFT_REPLY' else 'RECONNECT' end,
                'rule', case band when '31-90' then 'Reconnect with context from the last conversation.'
                                  when '3-12M' then 'Only with a credible new reason.' else 'Dormant: a personal note only.' end)), '[]'::jsonb) from gm),
    'linkedin', (select coalesce(jsonb_agg(jsonb_build_object('key', 'li:' || id::text, 'connection_id', id, 'person', concat_ws(' ', first_name, last_name), 'company', company,
                'position', position, 'company_id', matched_company_id, 'url', profile_url, 'state', li_state, 'messages', li_messages, 'received', li_in,
                'last_at', li_last_at, 'band', band, 'days', days, 'recommended', 'RECONNECT',
                'rule', case band when '31-90' then 'Reconnect with context from the last conversation.'
                                  when '3-12M' then 'Only with a credible new reason.' else 'Dormant: a personal note only.' end)), '[]'::jsonb) from li),
    'counts', jsonb_build_object('gmail', (select count(*) from c where coalesce(rel_state, '') <> 'DECLINED_RECENTLY' and coalesce(opp_status, '') <> 'LOST'),
      'owes_reply', (select count(*) from c where them_last and coalesce(rel_state, '') <> 'DECLINED_RECENTLY' and coalesce(opp_status, '') <> 'LOST'),
      'linkedin', (select count(*) from linkedin_connections l where coalesce(l.li_in, 0) > 0 and l.li_last_at < now() - interval '21 days' and l.li_opt_out_at is null)))
  into v;
  return v;
end $$;

-- 9. Studio READY means Adam could genuinely send it now: the latest version, classed READY_TO_SEND, not sent. A cover email
-- travels with its document (one package), so it is not listed twice.
create or replace function public.studio_ready_board() returns jsonb
language sql stable security definer set search_path = public as $$
  with latest as (select distinct on (slug) * from studio_documents order by slug, version desc)
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'slug', s.slug, 'version', s.version, 'title', s.title, 'company', c.name, 'company_id', s.company_id,
           'opportunity_id', s.opportunity_id, 'status', s.status, 'level', s.level, 'doc_type', s.doc_type, 'ready_class', s.ready_class,
           'ready_reason', s.ready_reason, 'file', s.file_name, 'created_at', s.created_at,
           'cover', (select jsonb_build_object('email', o.email_slug, 'draft', o.gmail_draft_id, 'thread', o.gmail_thread_id, 'send_after', o.send_after)
                       from studio_outputs o where o.document_slug = s.slug and o.status in ('PREPARED', 'HELD') order by o.prepared_at desc limit 1))
         order by s.created_at desc), '[]'::jsonb)
    from latest s left join companies c on c.id = s.company_id
   where s.ready_class = 'READY_TO_SEND' and s.sent_at is null and s.status in ('FOR_REVIEW', 'APPROVED')
     and not exists (select 1 from studio_outputs o where o.status = 'SENT' and (o.document_slug = s.slug or (o.email_slug = s.slug and o.document_slug is null)))
     and not exists (select 1 from studio_outputs o join latest d on d.slug = o.document_slug where o.email_slug = s.slug and o.status in ('PREPARED', 'HELD'))
$$;

-- 10. The Studio page shows each document's readiness class and reason.
do $$
declare v text := pg_get_functiondef('public.hq_studio()'::regprocedure);
begin
  if position('ready_class' in v) = 0 then
    v := replace(v, 'sd.hold_reason, c.name company,', 'sd.hold_reason, sd.ready_class, sd.ready_reason, c.name company,');
    v := replace(v, '''hold_reason'', d.hold_reason, ''file'', d.file_name)', '''hold_reason'', d.hold_reason, ''ready_class'', d.ready_class, ''ready_reason'', d.ready_reason, ''file'', d.file_name)');
    execute v;
  end if;
end $$;
