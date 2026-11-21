-- HQ TODAY v3 (21 Nov 2026): adds unanswered website enquiries (Marketing OS -> CRM, already deduplicated by the intake) to Adam's
-- "Needs you" list. Otherwise identical to v2. Read-only; same admin gate and grants. Idempotent (create or replace).
create or replace function public.hq_today()
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); ceo jsonb; auth jsonb; reserve jsonb; health jsonb; wk jsonb; gate text;
        v_actions jsonb; v_more int; v_live jsonb; v_streams jsonb; v_blockers jsonb := '[]'::jsonb;
        warm_open int; gmail_drafts int; held_cold int; v_bottleneck text; v_overdue int;
        v_deadlines jsonb; v_waiting jsonb; v_fu jsonb;
begin
  select payload into ceo from hq_read_cache where key = 'ceo';
  select payload into health from hq_read_cache where key = 'health';
  select value into auth from system_config where key = 'email_authentication';
  select value into reserve from system_config where key = 'email_reserve';
  wk := coalesce(ceo->'funnel'->'week', '{}'::jsonb);
  gate := coalesce(auth->'last_live_check'->>'gate', 'UNKNOWN');

  with covered as (
    select unnest(array_append(related_company_ids, company_id)) cid from ceo_actions where status in ('OPEN','WAITING')),
  manual as (
    select a.priority p, jsonb_build_object('id', a.id, 'kind', a.kind, 'who', a.who, 'what_happened', a.what_happened, 'why', a.why_it_matters,
             'todo', a.what_to_do, 'button_label', a.button_label, 'button_url', a.button_url, 'status', a.status, 'due_on', a.due_on,
             'company_id', a.company_id, 'opportunity_id', a.opportunity_id, 'source', a.source) j
      from ceo_actions a where a.status = 'OPEN'),
  replies as (
    select distinct on (g.company_id) 15 p, jsonb_build_object('id', null, 'kind', 'REPLY', 'who', c.name,
             'what_happened', 'They wrote last on ' || to_char(g.last_inbound_at at time zone 'Africa/Cairo', 'DD Mon') || ': ' || left(coalesce(g.summary, g.subject, ''), 140),
             'why', 'A reply is waiting: the warmest move available', 'todo', 'Reply in Gmail', 'button_label', 'Open the thread',
             'button_url', 'https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#all/' || g.gmail_thread_id, 'status', 'OPEN', 'source', 'gmail',
             'company_id', g.company_id, 'opportunity_id', g.opportunity_id) j
      from gmail_history_threads g join companies c on c.id = g.company_id left join opportunities o on o.id = g.opportunity_id
     where g.relevant and g.last_direction = 'INBOUND' and g.last_inbound_at > now() - interval '14 days'
       and coalesce(g.hq_status, '') <> 'DISMISSED' and coalesce(c.relationship_status, '') <> 'supplier'
       and (o.id is null or o.status in ('INTERESTED','CALL_REQUIRED','PROPOSAL','NEGOTIATION','WON'))
       and not exists (select 1 from covered v where v.cid = g.company_id)
     order by g.company_id, g.last_inbound_at desc),
  -- WEBSITE ENQUIRIES (21 Nov): marketing-qualified enquiries already routed into the CRM (matched contact, one opportunity) and not yet answered.
  -- Test submissions are archived by the intake and never appear.
  enquiries as (
    select 12 p, jsonb_build_object('id', null, 'kind', 'ENQUIRY',
             'who', coalesce(nullif(btrim(w.company_name), ''), nullif(split_part(btrim(w.full_name), ' ', 1), ''), 'Website enquiry') || ' · ' || initcap(replace(coalesce(w.lead_type, 'enquiry'), '_', ' ')),
             'what_happened', 'Website enquiry ' || coalesce(w.reference, '') || ' on ' || to_char(w.created_at at time zone 'Africa/Cairo', 'DD Mon')
                              || coalesce(': ' || nullif(btrim(w.destination), ''), '') || coalesce(', from ' || to_char(w.date_from, 'DD Mon'), '') || coalesce(', ' || w.guests || ' guests', ''),
             'why', 'Inbound and qualified by the website: the fastest route to revenue', 'todo', 'Reply personally within 24 hours',
             'button_label', 'Find in Gmail', 'button_url', 'https://mail.google.com/mail/u/0/#search/' || coalesce(w.email, w.reference, ''), 'status', 'OPEN', 'source', 'website',
             'company_id', w.matched_company_id, 'opportunity_id', w.created_opportunity_id) j
      from website_enquiries w join opportunities o on o.id = w.created_opportunity_id
     where w.created_at > now() - interval '14 days' and o.status in ('NEW','RESEARCHING','READY')
       and not exists (select 1 from covered v where v.cid = w.matched_company_id)),
  allx as (select p, j from manual union all select p, j from replies union all select p, j from enquiries)
  select coalesce(jsonb_agg(j order by p) filter (where rn <= 7), '[]'::jsonb), greatest(count(*) - 7, 0)
    into v_actions, v_more
    from (select j, p, row_number() over (order by p) rn from allx) s;

  select coalesce(jsonb_agg(to_jsonb(t) - 'rank' - 'updated_at' order by t.rank desc, t.priority desc nulls last, t.updated_at desc), '[]'::jsonb) into v_live
    from (select o.id, o.company_id, coalesce(c.name, o.company_name) company, o.primary_stream stream, st.label stream_label,
                 coalesce(nullif(o.angle, ''), nullif(o.opportunity_type, ''), o.project_type_canon) project,
                 hq_stage(o.status, coalesce(rc.usable, false), true, coalesce(o.next_action, '') <> '', c.universe_status = 'QUALIFIED') stage,
                 hq_stage_rank(hq_stage(o.status, coalesce(rc.usable, false), true, coalesce(o.next_action, '') <> '', c.universe_status = 'QUALIFIED')) rank,
                 coalesce(nullif(o.commercial_trigger, ''), nullif(o.reason, '')) why_now, o.relationship_type relationship,
                 greatest((select max(g.last_at) from gmail_history_threads g where g.company_id = o.company_id),
                          (select max(i.occurred_at) from interactions i where i.company_id = o.company_id)) last_interaction,
                 rc.person decision_maker, rc.position, rc.label route, o.next_action, o.next_action_due, o.priority, o.updated_at,
                 (select count(*) from studio_documents d where d.company_id = o.company_id) prepared_docs,
                 exists (select 1 from ceo_actions a where a.company_id = o.company_id and a.status = 'OPEN') action_open
            from opportunities o left join companies c on c.id = o.company_id
                 left join commercial_streams st on st.code = o.primary_stream left join hq_route_cache rc on rc.opportunity_id = o.id
           where o.status in ('INTERESTED','CALL_REQUIRED','PROPOSAL','NEGOTIATION','WON')
              or (o.status in ('FOLLOW_UP','CONTACTED') and o.relationship_type in ('WARM','PARTNER','CLIENT') and coalesce(o.next_action, '') <> '')
           order by rank desc, o.priority desc nulls last limit 8) t;

  select count(*) into warm_open from ceo_actions where status = 'OPEN' and kind in ('CALL','MEETING','REPLY','PROPOSAL','DECIDE','FOLLOW_UP','SEND','FORM');
  select count(*) into gmail_drafts from outbound_emails where status = 'DRAFTED' and sent_at is null;
  -- Live count (21 Nov): cold first touches still prepared and unsent (the reserve plan text went stale after the 21 Nov Gmail batch).
  select count(*) into held_cold from opportunities where status = 'READY' and next_action ~* '(draft r-?[0-9]|held until spf|wave [12])';

  select coalesce(jsonb_agg(z.j order by z.score desc), '[]'::jsonb) into v_streams from (
    select jsonb_build_object('code', s.code, 'label', s.label, 'pillar', s.pillar,
             'live', count(*) filter (where o.status in ('INTERESTED','CALL_REQUIRED','PROPOSAL','NEGOTIATION')),
             'warm', count(*) filter (where rc.warm), 'ready', count(*) filter (where o.status = 'READY'),
             'season', (select w.name from seasonal_windows w where w.stream = s.code and w.status = 'ACTIVE' and w.starts_on between current_date and current_date + 60 order by w.starts_on limit 1)) j,
           3 * count(*) filter (where o.status in ('INTERESTED','CALL_REQUIRED','PROPOSAL','NEGOTIATION')) + 2 * count(*) filter (where rc.warm)
             + least(count(*) filter (where o.status = 'READY'), 5)
             + 3 * (select count(*) from seasonal_windows w where w.stream = s.code and w.status = 'ACTIVE' and w.starts_on between current_date and current_date + 60) score
      from commercial_streams s join opportunities o on o.primary_stream = s.code left join hq_route_cache rc on rc.opportunity_id = o.id
     where o.status not in ('ARCHIVED','LOST')
     group by s.code, s.label, s.pillar order by score desc limit 6) z where z.score > 0;


  -- DEADLINES (21 Nov): what has a date in the next 7 days (or is past it) and needs Adam or a live account. Sourced dates only.
  select coalesce(jsonb_agg(d.j order by d.due, d.p), '[]'::jsonb) into v_deadlines from (
    select a.due_on due, a.priority p, jsonb_build_object('kind', 'ACTION', 'what', a.who, 'detail', coalesce(a.waiting_on, a.what_to_do), 'due_on', a.due_on,
             'status', a.status, 'company_id', a.company_id, 'opportunity_id', a.opportunity_id) j
      from ceo_actions a where a.status in ('OPEN','WAITING') and a.due_on is not null and a.due_on <= current_date + 7
    union all
    select o.next_action_due, 100 - coalesce(o.priority, 0), jsonb_build_object('kind', 'OPPORTUNITY', 'what', coalesce(c.name, o.company_name), 'detail', left(o.next_action, 160),
             'due_on', o.next_action_due, 'status', o.status, 'company_id', o.company_id, 'opportunity_id', o.id)
      from opportunities o left join companies c on c.id = o.company_id
     where o.status in ('INTERESTED','CALL_REQUIRED','PROPOSAL','NEGOTIATION') and o.next_action_due is not null and o.next_action_due <= current_date + 7
    union all
    select w.starts_on - coalesce(w.lead_time_days, 0), 50, jsonb_build_object('kind', 'SEASON', 'what', w.name, 'detail', w.commercial_angle, 'due_on', w.starts_on - coalesce(w.lead_time_days, 0),
             'status', w.confidence, 'source_url', w.source_url)
      from seasonal_windows w where w.status = 'ACTIVE' and w.starts_on - coalesce(w.lead_time_days, 0) between current_date - 3 and current_date + 7
    order by 1, 2 limit 8) d;

  -- WAITING ON OTHERS: Adam's items where the next move is theirs.
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'who', a.who, 'waiting_on', a.waiting_on, 'due_on', a.due_on, 'kind', a.kind) order by a.due_on nulls last, a.priority), '[]'::jsonb)
    into v_waiting from ceo_actions a where a.status = 'WAITING';

  -- FOLLOW-UPS DUE: one line per date (never a list of 40): sent first touches / follow-ups whose check date is within 7 days.
  select coalesce(jsonb_agg(jsonb_build_object('due_on', x.d, 'n', x.n) order by x.d), '[]'::jsonb) into v_fu from (
    select o.next_action_due d, count(*) n from opportunities o
     where o.status in ('CONTACTED','FOLLOW_UP') and o.next_action_due between current_date - 7 and current_date + 7
     group by o.next_action_due) x;

  if gate <> 'PASS' then
    v_blockers := v_blockers || jsonb_build_object('kind', 'DELIVERABILITY', 'text',
      'Cold email held: SPF and DKIM do not pass yet' || coalesce(' (checked ' || to_char((auth->'last_live_check'->>'at')::timestamptz at time zone 'Africa/Cairo', 'DD Mon HH24:MI') || ' Cairo)', ''),
      'action', 'Fix SPF and DKIM');
  end if;
  select count(*) into v_overdue from opportunities where status in ('PROPOSAL','NEGOTIATION') and next_action_due < current_date;
  if v_overdue > 0 then v_blockers := v_blockers || jsonb_build_object('kind', 'PROPOSAL_OVERDUE', 'text', v_overdue || ' proposal or negotiation past its next date'); end if;
  if jlen(health->'failures') > 0 then
    v_blockers := v_blockers || jsonb_build_object('kind', 'SYSTEM', 'text', jlen(health->'failures') || ' automation failure(s) recorded (More / Admin → System)');
  end if;

  v_bottleneck := case
    when warm_open >= 3 then 'Conversion: ' || warm_open || ' warm actions are prepared and waiting for you'
    when gate <> 'PASS' and held_cold + gmail_drafts > 0 then 'Deliverability: ' || (held_cold + gmail_drafts) || ' cold first touches held until SPF and DKIM pass'
    when jlen(v_live) = 0 then 'Pipeline: no live conversation yet'
    else 'No single bottleneck today' end;

  return jsonb_build_object(
    'generated_at', now(), 'gate', gate,
    'actions', v_actions, 'actions_more', v_more,
    'live', v_live, 'best', v_live->0,
    'week', jsonb_build_object('right_people_contacted', wk->'contacted', 'emails_sent', wk->'sent_email', 'replies', wk->'replies', 'positive', wk->'positive',
             'meetings', wk->'meetings', 'briefs', wk->'concepts', 'proposals', wk->'proposals', 'wins', wk->'won', 'revenue', coalesce(wk->'revenue', '[]'::jsonb),
             'as_of', ceo->>'generated_at'),
    'ready_unsent', jsonb_build_object('warm', warm_open, 'cold_gmail_drafts', gmail_drafts, 'cold_held', held_cold, 'total', warm_open + gmail_drafts + held_cold,
             'gated', gate <> 'PASS'),
    'bottleneck', v_bottleneck, 'streams', v_streams, 'blockers', v_blockers,
    'deadlines', v_deadlines, 'waiting', v_waiting, 'follow_ups_due', v_fu);
end $$;
revoke all on function public.hq_today() from public, anon;
grant execute on function public.hq_today() to authenticated;
