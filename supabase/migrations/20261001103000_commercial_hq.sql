-- HQ access to the commercial core: one read (hq_commercial), one account briefing (hq_account), audited writes.
-- Every write is admin-checked (hq_admin_email) and audited; none of them sends anything.

-- Faster email matching for strength / paths (plain domain compare instead of per-thread parsing).
create or replace function public.company_email_stats(p_company uuid)
returns table (inbound bigint, outbound bigint, two_way bigint, last_two_way timestamptz, last_at timestamptz, threads bigint)
language plpgsql stable security definer set search_path = public as $$
declare v_dom text;
begin
  select registrable_domain(website) into v_dom from companies where id = p_company;   -- once per call, not per thread (was 125 ms → <1 ms)
  return query
  select coalesce(sum(t.inbound), 0)::bigint, coalesce(sum(t.outbound), 0)::bigint, count(*) filter (where t.inbound > 0 and t.outbound > 0),
         max(least(t.last_inbound_at, t.last_outbound_at)) filter (where t.inbound > 0 and t.outbound > 0), max(t.last_at), count(*)
    from gmail_history_threads t
   where t.relevant and (t.company_id = p_company
         or (v_dom is not null and (t.counterpart_domains[1] = v_dom or t.counterpart_domains[1] like '%.' || v_dom)));
end $$;

create or replace function public.relationship_strength(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e record; v_in int := 0; v_meet int := 0; v_proj int := 0; v_paid int := 0; v_intro int := 0; v_li int := 0; c jsonb := '[]'; s int := 0; p int;
begin
  select * into e from company_email_stats(p_company);
  v_in := coalesce(e.inbound, 0) + (select count(*) from interactions i where i.company_id = p_company and i.direction = 'INBOUND' and i.channel <> 'MEETING');
  v_meet := (select count(*) from interactions i where i.company_id = p_company and i.channel = 'MEETING')
          + (select count(*) from opportunities o where o.company_id = p_company and o.status in ('CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON'));
  v_proj := (select count(*) from projects pr where pr.company_id = p_company and pr.status in ('DELIVERED', 'CLOSED'));
  v_paid := (select count(*) from revenue r where r.company_id = p_company and r.payment_status in ('PAID', 'PART_PAID'));
  v_intro := (select count(*) from relationship_edges x where x.relation in ('INTRODUCED', 'REFERRED')
               and ((x.from_type = 'COMPANY' and x.from_id = p_company) or (x.to_type = 'COMPANY' and x.to_id = p_company)));
  v_li := (select count(*) from linkedin_connections l where l.matched_company_id = p_company);
  if v_in > 0 then p := least(v_in * 4, 20); s := s + p; c := c || jsonb_build_object('key', 'replies', 'points', p, 'max', 20, 'evidence', v_in || ' emails from them (Gmail / CRM)'); end if;
  if e.two_way > 0 then p := least(e.two_way * 5, 10); s := s + p; c := c || jsonb_build_object('key', 'conversations', 'points', p, 'max', 10, 'evidence', e.two_way || ' two-way email threads'); end if;
  if v_meet > 0 then p := least(v_meet * 8, 15); s := s + p; c := c || jsonb_build_object('key', 'meetings', 'points', p, 'max', 15, 'evidence', v_meet || ' meetings / call-stage deals recorded'); end if;
  if v_proj > 0 then p := least(v_proj * 10, 20); s := s + p; c := c || jsonb_build_object('key', 'projects', 'points', p, 'max', 20, 'evidence', v_proj || ' delivered projects'); end if;
  if v_paid > 0 then s := s + 15; c := c || jsonb_build_object('key', 'revenue', 'points', 15, 'max', 15, 'evidence', v_paid || ' paid invoices'); end if;
  if v_proj + v_paid >= 2 then s := s + 10; c := c || jsonb_build_object('key', 'repeat_work', 'points', 10, 'max', 10, 'evidence', 'repeat work (projects + paid invoices = ' || (v_proj + v_paid) || ')'); end if;
  if v_intro > 0 then p := least(v_intro * 5, 10); s := s + p; c := c || jsonb_build_object('key', 'introductions', 'points', p, 'max', 10, 'evidence', v_intro || ' recorded introductions / referrals'); end if;
  if e.last_two_way is not null then
    p := case when e.last_two_way > now() - interval '30 days' then 10 when e.last_two_way > now() - interval '90 days' then 5 when e.last_two_way > now() - interval '365 days' then 2 else 0 end;
    if p > 0 then s := s + p; c := c || jsonb_build_object('key', 'recency', 'points', p, 'max', 10, 'evidence', 'last two-way contact ' || to_char(e.last_two_way, 'DD Mon YYYY')); end if;
  end if;
  if v_li > 0 then s := s + 3; c := c || jsonb_build_object('key', 'linkedin', 'points', 3, 'max', 3, 'evidence', v_li || ' LinkedIn connection(s) at the company (how well you know them is not measured)'); end if;
  s := least(s, 100);
  return jsonb_build_object('score', s, 'label', case when s = 0 then 'NONE' when s < 20 then 'COLD' when s < 45 then 'WARM' else 'STRONG' end,
    'components', c, 'method', 'Behaviour only: replies, conversations, meetings, projects, revenue, repeat work, introductions, recency, LinkedIn. Seniority is not measured.');
end $$;

create or replace function public.account_paths(p_company uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(p order by (p->>'rank')::int), '[]'::jsonb) from (
    select jsonb_build_object('rank', 1, 'route', 'Direct email history', 'detail', e.outbound || ' sent · ' || e.inbound || ' received · last ' || to_char(e.last_at, 'DD Mon YYYY'),
                              'evidence', 'NOYA Gmail (' || e.threads || ' threads)', 'provenance', 'VERIFIED') p
      from company_email_stats(p_company) e where e.threads > 0
    union all
    select jsonb_build_object('rank', 2, 'route', 'Person on file: ' || nullif(btrim(concat_ws(' ', k.first_name, k.last_name)), ''),
                              'detail', concat_ws(' · ', k.position, case when k.email_status = 'VERIFIED' then 'verified email' when k.email is not null then 'email not verified' end, case when k.linkedin is not null then 'LinkedIn on file' end),
                              'evidence', 'CRM contact', 'provenance', case when k.email_status = 'VERIFIED' then 'VERIFIED' else 'NEEDS_VERIFICATION' end)
      from contacts k where k.company_id = p_company and not coalesce(k.do_not_contact, false)
    union all
    select jsonb_build_object('rank', 3, 'route', 'LinkedIn connection: ' || concat_ws(' ', l.first_name, l.last_name), 'detail', coalesce(l.position, '') || ' — you know them on LinkedIn (strength unknown)',
                              'evidence', l.profile_url, 'provenance', 'VERIFIED')
      from linkedin_connections l where l.matched_company_id = p_company
    union all
    select jsonb_build_object('rank', 4, 'route', lower(replace(x.relation, '_', ' ')) || ' — ' || x.from_label, 'detail', x.from_label || ' ' || lower(replace(x.relation, '_', ' ')) || ' ' || x.to_label,
                              'evidence', coalesce(x.evidence_ref, x.evidence_source), 'provenance', x.provenance)
      from relationship_edges x where x.to_type = 'COMPANY' and x.to_id = p_company and x.relation in ('INTRODUCED', 'REFERRED', 'WORKS_WITH')
    union all
    select jsonb_build_object('rank', 5, 'route', 'Partner at the same event: ' || pc.name, 'detail', pc.name || ' (NOYA partner) is also involved in "' || i.title || '"',
                              'evidence', coalesce(so2.source_url, i.source_url), 'provenance', so2.provenance)
      from signal_organisations so1 join signal_organisations so2 on so2.signal_id = so1.signal_id and so2.company_id is distinct from so1.company_id
      join companies pc on pc.id = so2.company_id join company_relationships cr on cr.company_id = pc.id and cr.stage in ('ACTIVE', 'PRODUCTIVE', 'STRATEGIC', 'PILOT')
      join intelligence i on i.id = so1.signal_id
     where so1.company_id = p_company
  ) x
$$;

-- ================================================================ read: everything the 8 sections need (one call)
create or replace function public.hq_commercial()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with
  opp as (
    select o.*, f.vertical, f.origin_market, f.opportunity_market,
           c.first_name as k_first, c.last_name as k_last, c.position as k_position, c.email as k_email, c.email_status as k_email_status,
           exists (select 1 from outreach_drafts d where d.opportunity_id = o.id) or exists (select 1 from tasks t where t.opportunity_id = o.id and t.task_type = 'SALES_OUTREACH_APPROVAL') as has_draft,
           i.title as signal_title, i.stage as signal_stage, i.event_date as signal_event_date,
           opportunity_score(o.id) as score,
           case when o.company_id is not null then relationship_strength(o.company_id) end as strength,
           greatest((select max(occurred_at) from interactions x where x.opportunity_id = o.id or (o.company_id is not null and x.company_id = o.company_id)),
                    (select max(t.last_at) from gmail_history_threads t where o.company_id is not null and t.company_id = o.company_id)) as last_touch
      from opportunities o
      left join hq_opportunity_facts f on f.opportunity_id = o.id
      left join contacts c on c.id = o.contact_id
      left join intelligence i on i.id = o.signal_id
     where o.status not in ('ARCHIVED')
  ),
  sig as (
    select i.*, signal_urgency(i.event_date, i.event_end, i.category, i.intelligence_type) urgency, signal_qualification(i.id) qual
      from intelligence i where i.stage <> 'DISMISSED' or i.stage_changed_at > now() - interval '30 days'
  )
  select jsonb_build_object(
    'generated_at', now(),
    'team', jsonb_build_object('members', (select coalesce(jsonb_agg(to_jsonb(m) - 'id'), '[]') from team_members m where active),
                               'routing', (select coalesce(jsonb_object_agg(role, member_name), '{}') from role_routing)),
    'weights', (select value from system_config where key = 'opportunity_score_weights'),
    'products', (select coalesce(jsonb_agg(to_jsonb(p) order by p.name), '[]') from commercial_products p),
    'playbooks', (select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('performance', jsonb_build_object(
          'opportunities', (select count(*) from opportunities o where o.playbook_code = p.code),
          'contacted', (select count(*) from opportunities o where o.playbook_code = p.code and o.status not in ('NEW', 'RESEARCHING', 'READY')),
          'engaged', (select count(*) from opportunities o where o.playbook_code = p.code and o.status in ('INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON')),
          'won', (select count(*) from opportunities o where o.playbook_code = p.code and o.status = 'WON'),
          'lost', (select count(*) from opportunities o where o.playbook_code = p.code and o.status = 'LOST'),
          'signals', (select count(*) from intelligence i where i.playbook_code = p.code)))
        order by p.priority desc), '[]') from commercial_playbooks p),
    'signals', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', s.id, 'title', s.title, 'summary', s.summary, 'source_name', s.source_name, 'source_url', s.source_url, 'discovered_at', s.discovered_at,
          'event_date', s.event_date, 'event_end', s.event_end, 'destination', s.destination, 'category', s.category, 'region', s.region,
          'relevance', s.relevance_score, 'confidence', s.confidence_score, 'urgency', s.urgency, 'stage', s.stage, 'provenance', s.provenance,
          'why', coalesce(s.commercial_relevance, s.analysis->>'why_noya'), 'problem', s.problem_noya_solves, 'angle', s.commercial_angle,
          'services', s.services, 'products', s.product_codes, 'playbook', s.playbook_code, 'roles', s.decision_roles,
          'owner', s.owner, 'next_action', s.next_action, 'next_action_due', s.next_action_due, 'captured_by', s.captured_by,
          'analysed', s.analysed_at is not null, 'analysis_model', s.analysis_model, 'dismissed_reason', s.dismissed_reason,
          'qualification', s.qual, 'ai', case when s.analysed_at is not null then s.analysis - 'orgs_kept' end,
          'orgs', (select coalesce(jsonb_agg(jsonb_build_object('id', so.id, 'name', so.org_name, 'role', so.org_role, 'company_id', so.company_id,
                      'evidence', so.evidence, 'provenance', so.provenance, 'partner', exists (select 1 from company_relationships cr where cr.company_id = so.company_id and cr.stage in ('PILOT', 'ACTIVE', 'PRODUCTIVE', 'STRATEGIC')))
                      order by so.org_role, so.org_name), '[]') from signal_organisations so where so.signal_id = s.id),
          'opportunities', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'company', o.company_name, 'product', o.product_code, 'status', o.status, 'track', o.track)), '[]')
                            from opportunities o where o.signal_id = s.id),
          'projects', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'status', p.status)), '[]') from projects p where p.signal_id = s.id))
        order by case s.urgency when 'NOW' then 0 when 'D7' then 1 when 'D30' then 2 when 'D90' then 3 when 'LATER' then 4 else 5 end,
                 s.relevance_score desc nulls last), '[]') from sig s),
    'queue', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', o.id, 'company', o.company_name, 'company_id', o.company_id, 'contact_id', o.contact_id,
          'person', nullif(btrim(concat_ws(' ', coalesce(o.k_first, o.contact_first_name), coalesce(o.k_last, o.contact_last_name))), ''),
          'role', coalesce(o.k_position, o.contact_position), 'email_status', coalesce(o.k_email_status, o.email_status),
          'segment', o.vertical, 'market', o.opportunity_market, 'type', o.opportunity_type, 'track', o.track,
          'trigger', coalesce(o.commercial_trigger, o.signal_title), 'signal_id', o.signal_id, 'product', o.product_code, 'playbook', o.playbook_code,
          'reason', o.reason, 'angle', coalesce(o.angle, o.suggested_approach),
          'path', coalesce((o.strength->>'label'), 'NONE'), 'strength', o.strength,
          'last_touch', o.last_touch, 'next_action', o.next_action, 'owner', o.owner, 'due', o.next_action_due,
          'status', o.status, 'stage', opportunity_sales_stage(o.status, o.contact_id is not null or o.contact_email is not null, o.has_draft, o.signal_stage),
          'partner_stage', case when o.track = 'PARTNERSHIP' then partner_stage_of_opp(o.status, o.contact_id is not null or o.contact_email is not null) end,
          'score', o.score, 'client_budget', o.client_budget, 'proposal_value', o.proposal_value, 'contracted_value', o.contracted_value,
          'currency', o.currency, 'value_evidence', o.value_evidence, 'provenance', o.provenance, 'has_draft', o.has_draft, 'won_at', o.won_at)
        order by (o.score->>'score')::int desc, o.updated_at desc), '[]') from opp o),
    'partners', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', cr.id, 'company_id', cr.company_id, 'name', c.name, 'class', cr.partner_class, 'category', coalesce(cr.partner_category, c.company_type),
          'stage', cr.stage, 'geography', coalesce(cr.geography, c.country), 'provides_noya', cr.provides_noya, 'noya_provides', cr.noya_provides,
          'terms', cr.commercial_terms, 'rates', cr.preferred_rates, 'commission', cr.commission_structure, 'exclusivity', cr.exclusivity,
          'services', cr.services, 'owner', cr.owner, 'next_action', cr.next_action, 'next_action_due', cr.next_action_due,
          'stage_evidence', cr.stage_evidence, 'provenance', cr.provenance,
          'opportunities', (select count(*) from opportunities o where o.source_partner_id = cr.id),
          'projects', (select count(*) from project_items pi where pi.supplier_company_id = cr.company_id),
          'revenue_invoices', (select count(*) from revenue r join opportunities o on o.id = r.opportunity_id where o.source_partner_id = cr.id and r.payment_status in ('PAID', 'PART_PAID')),
          'last_interaction', e.last_at,
          'health', case when e.last_at is null then 'NO_CONTACT' when e.last_at > now() - interval '60 days' then 'GOOD' when e.last_at > now() - interval '180 days' then 'COOLING' else 'DORMANT' end,
          'events', (select coalesce(jsonb_agg(distinct i.title), '[]') from signal_organisations so join intelligence i on i.id = so.signal_id where so.company_id = cr.company_id))
        order by cr.stage, c.name), '[]')
        from company_relationships cr join companies c on c.id = cr.company_id cross join lateral company_email_stats(cr.company_id) e where cr.partner_class is not null),
    'projects', (select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object(
          'company', (select name from companies where id = p.company_id),
          'items', (select coalesce(jsonb_agg(to_jsonb(pi) || jsonb_build_object('supplier', (select name from companies where id = pi.supplier_company_id)) order by pi.starts_at nulls last, pi.created_at), '[]') from project_items pi where pi.project_id = p.id),
          'open_tasks', (select count(*) from tasks t where t.project_id = p.id and t.status in ('OPEN', 'IN_PROGRESS', 'WAITING')),
          'issues', (select count(*) from project_items pi where pi.project_id = p.id and pi.status = 'ISSUE'),
          'invoiced', (select coalesce(jsonb_agg(jsonb_build_object('currency', r.currency, 'amount', r.amount, 'status', r.invoice_status)), '[]') from revenue r where r.opportunity_id = p.opportunity_id or r.project_id = p.id),
          'collected', (select coalesce(jsonb_agg(jsonb_build_object('currency', r.currency, 'amount', rp.amount)), '[]') from revenue_payments rp join revenue r on r.id = rp.revenue_id where r.opportunity_id = p.opportunity_id or r.project_id = p.id))
        order by case p.status when 'LIVE' then 0 when 'PLANNING' then 1 when 'CONFIRMED' then 2 when 'DELIVERED' then 3 else 4 end, p.starts_on nulls last), '[]') from projects p),
    'supply_partners', (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(cr.partner_category, 'OTHER') k, count(*) n from company_relationships cr
                          where cr.partner_class = 'SUPPLY' and cr.stage in ('PILOT', 'ACTIVE', 'PRODUCTIVE', 'STRATEGIC') group by 1) x)
  ) into v;
  return v;
end $$;

-- ================================================================ read: account intelligence (the pre-call briefing)
create or replace function public.hq_account(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); c companies%rowtype;
begin
  select * into c from companies where id = p_company; if c.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  return jsonb_build_object(
    'company', jsonb_build_object('id', c.id, 'name', c.name, 'website', c.website, 'country', c.country, 'city', c.city, 'sector', c.sector,
                                  'type', c.company_type, 'relationship', c.relationship_status, 'fit', c.noya_fit, 'source', c.source, 'notes', c.notes),
    'strength', relationship_strength(c.id),
    'paths', account_paths(c.id),
    'people', (select coalesce(jsonb_agg(jsonb_build_object('id', k.id, 'name', nullif(btrim(concat_ws(' ', k.first_name, k.last_name)), ''), 'position', k.position,
                  'email', k.email, 'email_status', k.email_status, 'linkedin', k.linkedin, 'last_contact', k.last_contact_at, 'dnc', k.do_not_contact)), '[]')
               from contacts k where k.company_id = c.id),
    'linkedin', (select coalesce(jsonb_agg(jsonb_build_object('name', concat_ws(' ', l.first_name, l.last_name), 'position', l.position, 'url', l.profile_url)), '[]')
                 from linkedin_connections l where l.matched_company_id = c.id),
    'open_opportunities', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'type', o.opportunity_type, 'product', o.product_code, 'status', o.status,
                  'score', (opportunity_score(o.id)->>'score')::int, 'next_action', o.next_action, 'trigger', o.commercial_trigger, 'angle', o.angle)), '[]')
               from opportunities o where o.company_id = c.id and o.status not in ('WON', 'LOST', 'ARCHIVED')),
    'past_opportunities', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'type', o.opportunity_type, 'status', o.status, 'updated_at', o.updated_at)), '[]')
               from opportunities o where o.company_id = c.id and o.status in ('WON', 'LOST', 'ARCHIVED')),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'title', i.title, 'role', so.org_role, 'event_date', i.event_date, 'source_url', i.source_url,
                  'urgency', signal_urgency(i.event_date, i.event_end, i.category, i.intelligence_type))), '[]')
               from signal_organisations so join intelligence i on i.id = so.signal_id where so.company_id = c.id),
    'partnership', (select to_jsonb(cr) from company_relationships cr where cr.company_id = c.id and cr.partner_class is not null order by cr.updated_at desc limit 1),
    'projects', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'status', p.status, 'gross_profit', p.gross_profit, 'currency', p.currency)), '[]') from projects p where p.company_id = c.id),
    'services', (select coalesce(jsonb_agg(distinct x), '[]') from (
                  select unnest(pr.included_services) x from opportunities o join commercial_products pr on pr.code = o.product_code where o.company_id = c.id and o.status not in ('LOST', 'ARCHIVED')) s),
    'why_now', (select coalesce(o.commercial_trigger, i.title) from opportunities o left join intelligence i on i.id = o.signal_id
                 where o.company_id = c.id and o.status not in ('WON', 'LOST', 'ARCHIVED') order by (o.signal_id is not null) desc, o.updated_at desc limit 1),
    'outreach_history', (select coalesce(jsonb_agg(h order by h->>'at' desc), '[]') from (
        select jsonb_build_object('at', x.occurred_at, 'channel', x.channel, 'direction', x.direction, 'subject', x.subject, 'summary', x.summary) h
          from interactions x where x.company_id = c.id
        union all
        select jsonb_build_object('at', t.last_at, 'channel', 'EMAIL', 'direction', case when t.last_inbound_at >= coalesce(t.last_outbound_at, '-infinity') then 'INBOUND' else 'OUTBOUND' end,
                                  'subject', t.subject, 'summary', t.outbound || ' sent · ' || t.inbound || ' received', 'thread', t.gmail_thread_id)
          from gmail_history_threads t where t.relevant and t.company_id = c.id) y),
    'notes', (select coalesce(jsonb_agg(jsonb_build_object('kind', n.kind, 'body', n.body, 'at', n.created_at) order by n.created_at desc), '[]') from relationship_notes n where n.company_id = c.id),
    'sources', (select coalesce(jsonb_agg(distinct u), '[]') from (select i.source_url u from signal_organisations so join intelligence i on i.id = so.signal_id where so.company_id = c.id
                 union select c.website) s where u is not null));
end $$;

-- ================================================================ writes
create or replace function public.hq_signal_update(p_id uuid, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); i intelligence%rowtype; q jsonb; v_stage text := nullif(p->>'stage', '');
begin
  select * into i from intelligence where id = p_id; if i.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if v_stage = 'DISMISSED' and nullif(btrim(coalesce(p->>'dismissed_reason', '')), '') is null then
    return jsonb_build_object('ok', false, 'reason', 'REASON_REQUIRED');
  end if;
  update intelligence set
    owner = coalesce(nullif(p->>'owner', ''), owner),
    next_action = case when p ? 'next_action' then hq_trim(p->>'next_action') else next_action end,
    next_action_due = case when p ? 'next_action_due' then nullif(p->>'next_action_due', '')::date else next_action_due end,
    event_date = case when p ? 'event_date' then nullif(p->>'event_date', '')::date else event_date end,
    event_end = case when p ? 'event_end' then nullif(p->>'event_end', '')::date else event_end end,
    category = coalesce(nullif(p->>'category', ''), category), region = coalesce(nullif(p->>'region', ''), region),
    playbook_code = case when p ? 'playbook_code' then nullif(p->>'playbook_code', '') else playbook_code end,
    product_codes = case when p ? 'product_codes' then array(select jsonb_array_elements_text(p->'product_codes')) else product_codes end,
    commercial_angle = case when p ? 'commercial_angle' then hq_trim(p->>'commercial_angle') else commercial_angle end,
    problem_noya_solves = case when p ? 'problem_noya_solves' then hq_trim(p->>'problem_noya_solves') else problem_noya_solves end,
    commercial_relevance = case when p ? 'why' then hq_trim(p->>'why') else commercial_relevance end,
    dismissed_reason = case when v_stage = 'DISMISSED' then hq_trim(p->>'dismissed_reason') else dismissed_reason end,
    updated_at = now()
  where id = p_id;
  if v_stage is not null and v_stage <> i.stage then
    if v_stage in ('QUALIFIED', 'ACTIVE') then
      q := signal_qualification(p_id);
      if not (q->>'complete')::boolean then
        return jsonb_build_object('ok', false, 'reason', 'QUALIFICATION_INCOMPLETE', 'missing', q->'missing');
      end if;
    end if;
    update intelligence set stage = v_stage, status = case when v_stage = 'DISMISSED' then 'IGNORED' when v_stage in ('QUALIFIED', 'ACTIVE') then 'REVIEWED' else status end where id = p_id;
  end if;
  perform hq_audit('SIGNAL_UPDATE', null, jsonb_build_object('signal_id', p_id, 'changes', p, 'stage_from', i.stage));
  return jsonb_build_object('ok', true, 'qualification', signal_qualification(p_id));
exception when check_violation or invalid_text_representation or invalid_datetime_format then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;

create or replace function public.hq_signal_org(p_signal uuid, p_org_name text, p_role text, p_evidence text default null, p_company uuid default null, p_remove uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_id uuid;
begin
  if p_remove is not null then
    delete from signal_organisations where id = p_remove and signal_id = p_signal;
    perform hq_audit('SIGNAL_ORG_REMOVE', null, jsonb_build_object('signal_id', p_signal, 'org_id', p_remove));
    return jsonb_build_object('ok', true);
  end if;
  if hq_trim(p_org_name) is null then return jsonb_build_object('ok', false, 'reason', 'NAME_REQUIRED'); end if;
  insert into signal_organisations (signal_id, company_id, org_name, org_role, evidence, source_url, provenance)
  values (p_signal, p_company, hq_trim(p_org_name), coalesce(nullif(p_role, ''), 'OTHER'), hq_trim(p_evidence), (select source_url from intelligence where id = p_signal), 'MANUALLY_CONFIRMED')
  on conflict (signal_id, lower(org_name), org_role) do update set evidence = coalesce(excluded.evidence, signal_organisations.evidence), provenance = 'MANUALLY_CONFIRMED'
  returning id into v_id;
  perform hq_audit('SIGNAL_ORG_ADD', null, jsonb_build_object('signal_id', p_signal, 'org', p_org_name, 'role', p_role));
  return jsonb_build_object('ok', true, 'id', v_id, 'qualification', signal_qualification(p_signal));
exception when check_violation then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;

-- Capture a signal by hand (a source link is mandatory — no source, no signal).
create or replace function public.signal_capture(p jsonb, p_by text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_id uuid; o jsonb;
begin
  if hq_trim(p->>'source_url') is null or hq_trim(p->>'title') is null then return jsonb_build_object('ok', false, 'reason', 'SOURCE_REQUIRED'); end if;
  select id into v_id from intelligence where source_url = hq_trim(p->>'source_url') and lower(title) = lower(hq_trim(p->>'title'));
  if v_id is null then
    insert into intelligence (title, intelligence_type, country, destination, summary, source_name, source_url, commercial_relevance, relevance_score, confidence_score,
                              status, discovered_at, event_date, event_end, provenance, captured_by, stage)
    values (hq_trim(p->>'title'), coalesce(nullif(p->>'type', ''), 'MANUAL_CAPTURE'), coalesce(nullif(p->>'country', ''), 'Egypt'), hq_trim(p->>'destination'), hq_trim(p->>'summary'),
            hq_trim(p->>'source_name'), hq_trim(p->>'source_url'), hq_trim(p->>'why'), coalesce((p->>'relevance')::int, 70), coalesce((p->>'confidence')::int, 70),
            'NEW', now(), nullif(p->>'event_date', '')::date, nullif(p->>'event_end', '')::date, 'SOURCE_BACKED', p_by, 'RESEARCH')
    returning id into v_id;
  end if;
  for o in select * from jsonb_array_elements(coalesce(p->'orgs', '[]')) loop
    insert into signal_organisations (signal_id, org_name, org_role, evidence, source_url, provenance)
    values (v_id, hq_trim(o->>'name'), coalesce(nullif(o->>'role', ''), 'OTHER'), hq_trim(o->>'evidence'), coalesce(hq_trim(o->>'source_url'), hq_trim(p->>'source_url')), 'SOURCE_BACKED')
    on conflict (signal_id, lower(org_name), org_role) do nothing;
  end loop;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke all on function public.signal_capture(jsonb, text) from public, anon, authenticated;

create or replace function public.hq_signal_capture(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); r jsonb;
begin
  r := signal_capture(p, 'HQ (' || v_admin || ')');
  if (r->>'ok')::boolean then perform hq_audit('SIGNAL_CAPTURE', null, jsonb_build_object('signal_id', r->>'id', 'source_url', p->>'source_url')); end if;
  return r;
exception when check_violation or invalid_text_representation or invalid_datetime_format then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;

-- One signal → several commercial opportunities (one per organisation / product), without duplicating the event.
create or replace function public.hq_signal_promote(p_signal uuid, p_targets jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); i intelligence%rowtype; q jsonb; t jsonb; so signal_organisations%rowtype; pb commercial_playbooks%rowtype;
        v_co uuid; v_opp uuid; v_prod text; v_track text; created jsonb := '[]'; v_has_contact boolean;
begin
  select * into i from intelligence where id = p_signal; if i.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  q := signal_qualification(p_signal);
  if i.stage not in ('QUALIFIED', 'ACTIVE') then
    if not (q->>'complete')::boolean then return jsonb_build_object('ok', false, 'reason', 'QUALIFICATION_INCOMPLETE', 'missing', q->'missing'); end if;
    update intelligence set stage = 'QUALIFIED', status = 'REVIEWED' where id = p_signal;
  end if;
  select * into pb from commercial_playbooks where code = i.playbook_code;
  for t in select * from jsonb_array_elements(coalesce(p_targets, '[]')) loop
    select * into so from signal_organisations where id = (t->>'org_id')::uuid and signal_id = p_signal;
    if so.id is null then continue; end if;
    v_co := so.company_id;
    if v_co is null then
      insert into companies (name, country, source, notes, relationship_status)
      values (so.org_name, case when i.region = 'EGYPT' then 'Egypt' end, 'Signal: ' || left(i.title, 120),
              'Created from a source-backed signal (' || coalesce(i.source_url, 'no url') || '). Provenance: ' || so.provenance || '.', 'prospect')
      returning id into v_co;
      update signal_organisations set company_id = v_co where id = so.id;
    end if;
    v_prod := coalesce(nullif(t->>'product', ''), (select x->>'product' from jsonb_array_elements(pb.target_orgs) x where x->>'org_role' = so.org_role limit 1), i.product_codes[1]);
    v_track := coalesce(nullif(t->>'track', ''), (select x->>'track' from jsonb_array_elements(pb.target_orgs) x where x->>'org_role' = so.org_role and x->>'product' = v_prod limit 1), pb.track, 'SALES');
    v_has_contact := exists (select 1 from contacts k where k.company_id = v_co and k.email is not null and not coalesce(k.do_not_contact, false));
    v_opp := null;  -- ON CONFLICT DO NOTHING returns no row; never reuse the previous id
    insert into opportunities (company_id, company_name, signal_id, product_code, playbook_code, track, target_role, opportunity_type, destination, country,
                               description, reason, commercial_trigger, angle, suggested_approach, status, approval_status, provenance, next_action, next_action_due, priority)
    values (v_co, (select name from companies where id = v_co), p_signal, v_prod, i.playbook_code, v_track, so.org_role, v_prod, i.destination, 'Egypt',
            coalesce(hq_trim(t->>'why'), (select x->>'why' from jsonb_array_elements(pb.target_orgs) x where x->>'org_role' = so.org_role and x->>'product' = v_prod limit 1)),
            'Signal: ' || i.title, i.title, coalesce(i.commercial_angle, pb.value_proposition), pb.outreach_approach,
            'RESEARCHING', 'PENDING', 'SOURCE_BACKED',
            case when v_has_contact then 'Prepare outreach from the ' || coalesce((select name from commercial_products where code = v_prod), 'product') || ' template'
                 else 'Find the decision maker: ' || coalesce(array_to_string(pb.decision_roles[1:3], ' / '), 'commercial lead') end,
            case signal_urgency(i.event_date, i.event_end, i.category, i.intelligence_type) when 'NOW' then current_date when 'D7' then current_date + 3 else current_date + 7 end,
            50)
    on conflict (signal_id, company_id, coalesce(product_code, '')) where signal_id is not null and company_id is not null do nothing
    returning id into v_opp;
    if v_opp is not null then
      if not v_has_contact then
        insert into tasks (company_id, opportunity_id, signal_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
        values (v_co, v_opp, p_signal, 'Find decision maker at ' || so.org_name,
                'For "' || i.title || '". Roles to look for: ' || coalesce(array_to_string(pb.decision_roles, ', '), 'commercial lead') ||
                '. Only record a person from a real source (company site, LinkedIn, press release).', 'CONTACT_RESEARCH', owner_for_role('SDR'),
                'HQ (signal → opportunity)', 70, 'OPEN', now() + interval '2 days');
      end if;
      created := created || jsonb_build_object('opportunity_id', v_opp, 'company', so.org_name, 'product', v_prod, 'track', v_track, 'has_contact', v_has_contact);
    end if;
  end loop;
  update intelligence set stage = 'ACTIVE', status = 'OPPORTUNITY_CREATED', next_action = 'Work the opportunities in Sales & Outreach' where id = p_signal and jsonb_array_length(created) > 0;
  perform hq_audit('SIGNAL_PROMOTE', null, jsonb_build_object('signal_id', p_signal, 'created', created));
  return jsonb_build_object('ok', true, 'created', created);
end $$;

-- Prepare outreach from the product template → the existing approval queue (Approve → Gmail draft → you send).
create or replace function public.hq_prepare_outreach(p_opp uuid, p_contact uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); o opportunities%rowtype; r jsonb; v_ver int; k contacts%rowtype;
begin
  select * into o from opportunities where id = p_opp; if o.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if p_contact is not null then
    select * into k from contacts where id = p_contact;
    if k.id is null or k.company_id is distinct from o.company_id then return jsonb_build_object('ok', false, 'reason', 'CONTACT_NOT_AT_COMPANY'); end if;
    update opportunities set contact_id = k.id, contact_first_name = k.first_name, contact_last_name = k.last_name, contact_position = k.position,
           contact_email = k.email, email_status = k.email_status where id = p_opp;
  end if;
  r := opportunity_outreach(p_opp);
  if not coalesce((r->>'ready')::boolean, false) then return jsonb_build_object('ok', false, 'reason', 'OUTREACH_NOT_READY', 'missing', r->'missing', 'preview', r); end if;
  select coalesce(max(version), 0) + 1 into v_ver from outreach_drafts where opportunity_id = p_opp;
  insert into outreach_drafts (opportunity_id, version, subject, body, follow_up_plan, source, created_by)
  values (p_opp, v_ver, r->>'subject', r->>'body',
          (select string_agg('Day +' || (f->>'day') || ' · ' || (f->>'channel') || ' · ' || (f->>'purpose') || ': ' || (f->>'message'), E'\n') from jsonb_array_elements(r->'follow_ups') f),
          'PLAYBOOK_TEMPLATE', v_admin);
  insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
  select o.company_id, coalesce(p_contact, o.contact_id), p_opp, 'Approve outreach: ' || coalesce(o.company_name, 'opportunity'),
         'Playbook draft (' || coalesce(r->>'product', '') || '). Review, edit if needed, approve → Gmail draft → you send from Gmail.', 'SALES_OUTREACH_APPROVAL',
         o.owner, 'HQ (playbook template)', 75, 'OPEN', now()
  where not exists (select 1 from tasks where opportunity_id = p_opp and task_type = 'SALES_OUTREACH_APPROVAL' and status in ('OPEN', 'IN_PROGRESS'));
  update opportunities set status = 'READY', approval_status = 'PENDING', next_action = 'Approve the outreach draft (Sales & Outreach → Ready)', next_action_due = current_date where id = p_opp;
  perform hq_audit('OUTREACH_PREPARED', p_opp, jsonb_build_object('version', v_ver, 'product', o.product_code, 'source', 'PLAYBOOK_TEMPLATE'));
  return jsonb_build_object('ok', true, 'version', v_ver, 'subject', r->>'subject');
end $$;

create or replace function public.hq_opportunity_commercial(p_opp uuid, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); o opportunities%rowtype;
begin
  select * into o from opportunities where id = p_opp; if o.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if p ? 'score_override' and nullif(p->>'score_override', '') is not null and hq_trim(p->>'score_override_reason') is null then
    return jsonb_build_object('ok', false, 'reason', 'REASON_REQUIRED');
  end if;
  update opportunities set
    product_code = case when p ? 'product_code' then nullif(p->>'product_code', '') else product_code end,
    playbook_code = case when p ? 'playbook_code' then nullif(p->>'playbook_code', '') else playbook_code end,
    track = coalesce(nullif(p->>'track', ''), track),
    owner = coalesce(nullif(p->>'owner', ''), owner),
    angle = case when p ? 'angle' then hq_trim(p->>'angle') else angle end,
    commercial_trigger = case when p ? 'commercial_trigger' then hq_trim(p->>'commercial_trigger') else commercial_trigger end,
    next_action = case when p ? 'next_action' then hq_trim(p->>'next_action') else next_action end,
    next_action_due = case when p ? 'next_action_due' then nullif(p->>'next_action_due', '')::date else next_action_due end,
    client_budget = case when p ? 'client_budget' then nullif(p->>'client_budget', '')::numeric else client_budget end,
    proposal_value = case when p ? 'proposal_value' then nullif(p->>'proposal_value', '')::numeric else proposal_value end,
    contracted_value = case when p ? 'contracted_value' then nullif(p->>'contracted_value', '')::numeric else contracted_value end,
    currency = case when p ? 'currency' then upper(hq_trim(p->>'currency')) else currency end,
    value_evidence = case when p ? 'value_evidence' then hq_trim(p->>'value_evidence') else value_evidence end,
    source_partner_id = case when p ? 'source_partner_id' then nullif(p->>'source_partner_id', '')::uuid else source_partner_id end,
    score_override = case when p ? 'score_override' then nullif(p->>'score_override', '')::smallint else score_override end,
    score_override_reason = case when p ? 'score_override' then hq_trim(p->>'score_override_reason') else score_override_reason end,
    score_override_by = case when p ? 'score_override' then v_admin else score_override_by end,
    score_override_at = case when p ? 'score_override' then now() else score_override_at end,
    updated_at = now()
  where id = p_opp;
  perform hq_audit('OPPORTUNITY_COMMERCIAL', p_opp, jsonb_build_object('changes', p));
  return jsonb_build_object('ok', true, 'score', opportunity_score(p_opp));
exception
  when raise_exception then return jsonb_build_object('ok', false, 'reason', sqlerrm);
  when check_violation or invalid_text_representation or foreign_key_violation then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;

create or replace function public.hq_partner_upsert(p_company uuid, p_class text, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_id uuid;
begin
  if p_class not in ('SUPPLY', 'DISTRIBUTION') then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE'); end if;
  insert into company_relationships (company_id, relationship_type, relationship_status, owner, partner_class, stage, provenance)
  values (p_company, case when p_class = 'SUPPLY' then 'SUPPLIER' else 'PARTNER' end, 'POTENTIAL', coalesce(nullif(p->>'owner', ''), owner_for_role('PARTNERSHIPS')), p_class,
          'TARGET', 'MANUALLY_CONFIRMED')
  on conflict (company_id, partner_class) where partner_class is not null do nothing;
  update company_relationships set
    stage = coalesce(nullif(p->>'stage', ''), stage), owner = coalesce(nullif(p->>'owner', ''), owner),
    partner_category = case when p ? 'category' then hq_trim(p->>'category') else partner_category end,
    geography = case when p ? 'geography' then hq_trim(p->>'geography') else geography end,
    provides_noya = case when p ? 'provides_noya' then hq_trim(p->>'provides_noya') else provides_noya end,
    noya_provides = case when p ? 'noya_provides' then hq_trim(p->>'noya_provides') else noya_provides end,
    commercial_terms = case when p ? 'terms' then hq_trim(p->>'terms') else commercial_terms end,
    preferred_rates = case when p ? 'rates' then hq_trim(p->>'rates') else preferred_rates end,
    commission_structure = case when p ? 'commission' then hq_trim(p->>'commission') else commission_structure end,
    exclusivity = case when p ? 'exclusivity' then hq_trim(p->>'exclusivity') else exclusivity end,
    next_action = case when p ? 'next_action' then hq_trim(p->>'next_action') else next_action end,
    next_action_due = case when p ? 'next_action_due' then nullif(p->>'next_action_due', '')::date else next_action_due end,
    provenance = 'MANUALLY_CONFIRMED'
  where company_id = p_company and partner_class = p_class
  returning id into v_id;
  perform hq_audit('PARTNER_UPSERT', null, jsonb_build_object('company_id', p_company, 'class', p_class, 'changes', p));
  return jsonb_build_object('ok', true, 'id', v_id);
exception
  when raise_exception then return jsonb_build_object('ok', false, 'reason', sqlerrm);
  when check_violation or invalid_text_representation or invalid_datetime_format then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;

create or replace function public.hq_project_update(p_project uuid, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  if (nullif(p->>'client_charge', '') is not null or nullif(p->>'supplier_cost', '') is not null) and coalesce(hq_trim(p->>'currency'), (select currency from projects where id = p_project)) is null then
    return jsonb_build_object('ok', false, 'reason', 'CURRENCY_REQUIRED');
  end if;
  update projects set
    status = coalesce(nullif(p->>'status', ''), status), owner = coalesce(nullif(p->>'owner', ''), owner),
    brief = case when p ? 'brief' then hq_trim(p->>'brief') else brief end,
    destination = case when p ? 'destination' then hq_trim(p->>'destination') else destination end,
    starts_on = case when p ? 'starts_on' then nullif(p->>'starts_on', '')::date else starts_on end,
    ends_on = case when p ? 'ends_on' then nullif(p->>'ends_on', '')::date else ends_on end,
    attendees = case when p ? 'attendees' then nullif(p->>'attendees', '')::int else attendees end,
    currency = case when p ? 'currency' then upper(hq_trim(p->>'currency')) else currency end,
    client_charge = case when p ? 'client_charge' then nullif(p->>'client_charge', '')::numeric else client_charge end,
    supplier_cost = case when p ? 'supplier_cost' then nullif(p->>'supplier_cost', '')::numeric else supplier_cost end,
    feedback = case when p ? 'feedback' then hq_trim(p->>'feedback') else feedback end,
    updated_at = now()
  where id = p_project;
  perform hq_audit('PROJECT_UPDATE', null, jsonb_build_object('project_id', p_project, 'changes', p));
  return jsonb_build_object('ok', true);
exception when check_violation or invalid_text_representation or invalid_datetime_format then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;

create or replace function public.hq_project_item(p_project uuid, p_item uuid, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_id uuid := p_item;
begin
  if coalesce((p->>'delete')::boolean, false) then
    delete from project_items where id = p_item and project_id = p_project;
  elsif p_item is null then
    insert into project_items (project_id, item_type, title, detail, supplier_company_id, starts_at, status, cost, charge, currency, owner)
    values (p_project, coalesce(nullif(p->>'item_type', ''), 'OTHER'), hq_trim(p->>'title'), hq_trim(p->>'detail'), nullif(p->>'supplier_company_id', '')::uuid,
            nullif(p->>'starts_at', '')::timestamptz, coalesce(nullif(p->>'status', ''), 'OPEN'), nullif(p->>'cost', '')::numeric, nullif(p->>'charge', '')::numeric,
            upper(hq_trim(p->>'currency')), coalesce(nullif(p->>'owner', ''), owner_for_role('OPERATIONS')))
    returning id into v_id;
  else
    update project_items set item_type = coalesce(nullif(p->>'item_type', ''), item_type), title = coalesce(hq_trim(p->>'title'), title),
      detail = case when p ? 'detail' then hq_trim(p->>'detail') else detail end, status = coalesce(nullif(p->>'status', ''), status),
      supplier_company_id = case when p ? 'supplier_company_id' then nullif(p->>'supplier_company_id', '')::uuid else supplier_company_id end,
      starts_at = case when p ? 'starts_at' then nullif(p->>'starts_at', '')::timestamptz else starts_at end,
      cost = case when p ? 'cost' then nullif(p->>'cost', '')::numeric else cost end, charge = case when p ? 'charge' then nullif(p->>'charge', '')::numeric else charge end,
      currency = case when p ? 'currency' then upper(hq_trim(p->>'currency')) else currency end, updated_at = now()
    where id = p_item and project_id = p_project;
  end if;
  perform hq_audit('PROJECT_ITEM', null, jsonb_build_object('project_id', p_project, 'item_id', v_id, 'changes', p));
  return jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation or invalid_text_representation or invalid_datetime_format or not_null_violation then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;

-- Record a real relationship (an introduction, "works with") — evidence is required.
create or replace function public.hq_edge_add(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_id uuid;
begin
  if hq_trim(p->>'evidence') is null then return jsonb_build_object('ok', false, 'reason', 'EVIDENCE_REQUIRED'); end if;
  insert into relationship_edges (from_type, from_id, from_label, relation, to_type, to_id, to_label, evidence_source, evidence_ref, provenance, created_by)
  values (p->>'from_type', nullif(p->>'from_id', '')::uuid, hq_trim(p->>'from_label'), p->>'relation', p->>'to_type', nullif(p->>'to_id', '')::uuid, hq_trim(p->>'to_label'),
          'MANUAL', hq_trim(p->>'evidence'), 'MANUALLY_CONFIRMED', v_admin)
  on conflict do nothing returning id into v_id;
  perform hq_audit('RELATIONSHIP_EDGE', null, p);
  return jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation or not_null_violation or invalid_text_representation then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;

create or replace function public.hq_role_route(p_role text, p_member text, p_email text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  if hq_trim(p_member) is null then return jsonb_build_object('ok', false, 'reason', 'NAME_REQUIRED'); end if;
  insert into team_members (name, email, roles) values (hq_trim(p_member), hq_trim(p_email), array[p_role])
  on conflict (name) do update set roles = (select array_agg(distinct r) from unnest(team_members.roles || array[p_role]) r), email = coalesce(excluded.email, team_members.email);
  insert into role_routing (role, member_name) values (p_role, hq_trim(p_member))
  on conflict (role) do update set member_name = excluded.member_name, updated_at = now();
  perform hq_audit('ROLE_ROUTE', null, jsonb_build_object('role', p_role, 'member', p_member));
  return jsonb_build_object('ok', true);
exception when check_violation then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;

do $$
declare f text;
begin
  foreach f in array array['public.hq_commercial()', 'public.hq_account(uuid)', 'public.hq_signal_update(uuid, jsonb)',
    'public.hq_signal_org(uuid, text, text, text, uuid, uuid)', 'public.hq_signal_capture(jsonb)', 'public.hq_signal_promote(uuid, jsonb)',
    'public.hq_prepare_outreach(uuid, uuid)', 'public.hq_opportunity_commercial(uuid, jsonb)', 'public.hq_partner_upsert(uuid, text, jsonb)',
    'public.hq_project_update(uuid, jsonb)', 'public.hq_project_item(uuid, uuid, jsonb)', 'public.hq_edge_add(jsonb)', 'public.hq_role_route(text, text, text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.relationship_strength(uuid)', 'public.account_paths(uuid)', 'public.opportunity_score(uuid)', 'public.signal_qualification(uuid)',
    'public.opportunity_outreach(uuid)', 'public.company_email_stats(uuid)', 'public.owner_for_role(text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end $$;
