-- NOYA commercial core — logic. Deterministic, explainable, traceable. AI output (workflow 17) only fills
-- fields that rules cannot, and is labelled INFERRED; facts from sources are SOURCE_BACKED; team input is
-- MANUALLY_CONFIRMED. Nothing here sends a message.

-- ================================================================ classification helpers
create or replace function public.signal_category_of(p_type text, p_text text)
returns text language sql immutable as $$
  select case
    when t ~* 'film festival|cinema|premiere|red carpet' then 'ENTERTAINMENT'
    when t ~* 'hyrox|marathon|championship|tournament|grand prix|world cup|padel|golf|tennis|triathlon|ironman|football|squash|athlete|fitness rac' then 'SPORTS'
    when t ~* 'festival|concert|(^|[^a-z])dj([^a-z]|$)|music|line-?up|live show' then 'ENTERTAINMENT'
    when t ~* 'wedding' then 'WEDDINGS'
    when t ~* 'shoot(ing)? in|filming|film commission|production company|on location|film set' then 'PRODUCTION'
    when t ~* 'residential|residences|real estate|property|compound|sales office|developer|damac|emaar' then 'REAL_ESTATE'
    when t ~* 'activation|pop-up|brand launch|boutique|flagship|fashion show|collection' then 'BRANDS'
    when ty ~* 'HOTEL|RESORT|BEACH_CLUB|RESTAURANT|DAHABEYA|CRUISE' or t ~* 'hotel|resort|beach club|restaurant|dahabeya|nile cruise' then 'HOSPITALITY'
    when ty ~* 'CONFERENCE|SUMMIT' or t ~* 'conference|summit|forum|delegation|congress|expo|exhibition' then 'CORPORATE'
    when ty ~* 'AVIATION|YACHT|MARINA|TOURISM|ROUTE' or t ~* 'airline|flight route|marina|yacht' then 'TRAVEL'
    when ty ~* 'EVENT' then 'EVENTS'
    else 'OTHER' end
  from (select coalesce(p_type, '') ty, coalesce(p_text, '') t) x
$$;

create or replace function public.signal_region_of(p_country text, p_destination text)
returns text language sql immutable as $$
  select case
    when hq_market(concat_ws(' ', p_destination, p_country)) = 'EGYPT' then 'EGYPT'
    when concat_ws(' ', p_destination, p_country) ~* 'united kingdom|(^|[^a-z])uk([^a-z]|$)|england|london|scotland' then 'UK'
    when hq_market(concat_ws(' ', p_destination, p_country)) = 'EUROPE' then 'EUROPE'
    when hq_market(concat_ws(' ', p_destination, p_country)) = 'GCC' or concat_ws(' ', p_destination, p_country) ~* 'jordan|lebanon|morocco|middle east' then 'MIDDLE_EAST'
    when coalesce(btrim(concat_ws(' ', p_destination, p_country)), '') = '' then 'EGYPT'   -- workflow 09 only covers Egypt
    else 'GLOBAL' end
$$;

create or replace function public.playbook_for(p_category text, p_text text)
returns text language sql stable set search_path = public as $$
  select p.code from commercial_playbooks p
   cross join lateral (select count(*) hits from unnest(p.keywords) k where coalesce(p_text, '') ~* ('(^|[^a-z])' || k)) h
   where h.hits > 0 or p_category = any(p.categories)
   order by (p_category = any(p.categories)) desc, h.hits desc, p.priority desc
   limit 1
$$;

-- First explicit date in the source text ("2 to 4 October 2026", "October 15th to 23rd 2026", "14-15 November 2026").
create or replace function public.extract_event_dates(p_text text)
returns date[] language plpgsql immutable as $$
declare m text[]; mon text; months text := 'january|february|march|april|may|june|july|august|september|october|november|december'; d1 int; d2 int; y int;
begin
  -- 1) "2 to 4 October 2026" / "14–15 November 2026" / "8 October 2026"
  m := regexp_match(lower(coalesce(p_text, '')), '(\d{1,2})(?:st|nd|rd|th)?(?:\s*(?:–|-|to|and)\s*(\d{1,2})(?:st|nd|rd|th)?)?\s+(' || months || ')\s+(\d{4})');
  if m is not null then
    d1 := m[1]::int; d2 := coalesce(m[2]::int, d1); mon := m[3]; y := m[4]::int;
  else
    -- 2) "October 15th to 23rd 2026" / "October 1, 2026"
    m := regexp_match(lower(coalesce(p_text, '')), '(' || months || ')\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s*(?:–|-|to)\s*(\d{1,2})(?:st|nd|rd|th)?)?,?\s+(\d{4})');
    if m is null then return null; end if;
    mon := m[1]; d1 := m[2]::int; d2 := coalesce(m[3]::int, d1); y := m[4]::int;
  end if;
  begin
    return array[to_date(d1 || ' ' || mon || ' ' || y, 'DD month YYYY'), to_date(d2 || ' ' || mon || ' ' || y, 'DD month YYYY')];
  exception when others then return null; end;
end $$;

-- When to ACT, not when the event is: events need a ~45-day approach window, other signals ~14 days.
create or replace function public.signal_urgency(p_event date, p_event_end date, p_category text, p_type text)
returns text language sql stable as $$
  select case
    when coalesce(p_event_end, p_event) is not null and coalesce(p_event_end, p_event) < current_date then 'PASSED'
    when p_event is not null then
      case when (p_event - case when p_category in ('SPORTS', 'ENTERTAINMENT', 'EVENTS', 'CORPORATE', 'WEDDINGS', 'PRODUCTION') then 45 else 14 end) - current_date <= 0 then 'NOW'
           when (p_event - case when p_category in ('SPORTS', 'ENTERTAINMENT', 'EVENTS', 'CORPORATE', 'WEDDINGS', 'PRODUCTION') then 45 else 14 end) - current_date <= 7 then 'D7'
           when (p_event - case when p_category in ('SPORTS', 'ENTERTAINMENT', 'EVENTS', 'CORPORATE', 'WEDDINGS', 'PRODUCTION') then 45 else 14 end) - current_date <= 30 then 'D30'
           when (p_event - case when p_category in ('SPORTS', 'ENTERTAINMENT', 'EVENTS', 'CORPORATE', 'WEDDINGS', 'PRODUCTION') then 45 else 14 end) - current_date <= 90 then 'D90'
           else 'LATER' end
    when coalesce(p_type, '') ~* 'THIS_WEEK' then 'D7'
    when coalesce(p_type, '') ~* 'THIS_MONTH' then 'D30'
    else 'LATER' end
$$;

-- ================================================================ signal enrichment (runs on every insert / update)
create or replace function public.intelligence_enrich()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_text text := concat_ws(' ', new.title, new.summary, new.potential_opportunity, new.commercial_relevance, new.destination);
        pb commercial_playbooks%rowtype; d date[];
begin
  if new.category is null then new.category := signal_category_of(new.intelligence_type, v_text); end if;
  if new.region is null then new.region := signal_region_of(new.country, new.destination); end if;
  if new.event_date is null then
    d := extract_event_dates(concat_ws(' ', new.title, new.summary));
    if d is not null and d[1] >= coalesce(new.discovered_at, now())::date - 60 then new.event_date := d[1]; new.event_end := nullif(d[2], d[1]); end if;
  end if;
  if new.playbook_code is null then new.playbook_code := playbook_for(new.category, v_text); end if;
  select * into pb from commercial_playbooks where code = new.playbook_code;
  if pb.code is not null then
    if coalesce(array_length(new.product_codes, 1), 0) = 0 then new.product_codes := pb.product_codes; end if;
    if coalesce(array_length(new.decision_roles, 1), 0) = 0 then new.decision_roles := pb.decision_roles; end if;
    if coalesce(array_length(new.services, 1), 0) = 0 then new.services := pb.services; end if;
    if new.problem_noya_solves is null then new.problem_noya_solves := (select client_problems[1] from commercial_products where code = pb.product_codes[1]); end if;
    if new.commercial_angle is null then new.commercial_angle := pb.value_proposition; end if;
  end if;
  if new.owner is null then new.owner := owner_for_role(coalesce(pb.owner_role, 'SALES')); end if;
  if tg_op = 'INSERT' then
    if new.provenance = 'INFERRED' and nullif(btrim(coalesce(new.source_url, '')), '') is not null then new.provenance := 'SOURCE_BACKED'; end if;
    if new.stage = 'WATCH' and coalesce(new.relevance_score, 0) >= 60 then new.stage := 'RESEARCH'; end if;
    new.captured_by := coalesce(new.captured_by, 'workflow 09');
  end if;
  if new.next_action is null then
    new.next_action := case when new.stage in ('WATCH') then 'Watch: re-check when more is known'
                            else 'Confirm who is behind it and the decision makers (' || coalesce(array_to_string(new.decision_roles[1:3], ', '), 'commercial lead') || ')' end;
  end if;
  if new.stage = 'DISMISSED' and (tg_op = 'INSERT' or old.stage is distinct from 'DISMISSED') then new.status := 'IGNORED'; end if;
  if tg_op = 'UPDATE' and new.stage is distinct from old.stage then new.stage_changed_at := now(); end if;
  return new;
end $$;
drop trigger if exists intelligence_enrich on public.intelligence;
create trigger intelligence_enrich before insert or update on public.intelligence
  for each row execute function public.intelligence_enrich();

-- Organisations: link to an existing company by comparable name (never creates one).
create or replace function public.signal_org_link()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.company_id is null and company_name_key(new.org_name) is not null then
    select c.id into new.company_id from companies c
     where company_name_key(c.name) = company_name_key(new.org_name) and coalesce(c.notes, '') not like '%MERGED_INTO:%'
     order by c.created_at limit 1;
  end if;
  return new;
end $$;
drop trigger if exists signal_org_link on public.signal_organisations;
create trigger signal_org_link before insert or update on public.signal_organisations
  for each row execute function public.signal_org_link();

-- ================================================================ relationship strength (behaviour only, explainable)
create or replace function public.relationship_strength(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_dom text; v_in int := 0; v_out int := 0; v_two int := 0; v_last timestamptz; v_meet int := 0; v_proj int := 0; v_paid int := 0;
        v_intro int := 0; v_li int := 0; c jsonb := '[]'; s int := 0; p int;
begin
  select registrable_domain(website) into v_dom from companies where id = p_company;
  select coalesce(sum(t.inbound), 0), coalesce(sum(t.outbound), 0), count(*) filter (where t.inbound > 0 and t.outbound > 0),
         max(least(t.last_inbound_at, t.last_outbound_at)) filter (where t.inbound > 0 and t.outbound > 0)
    into v_in, v_out, v_two, v_last
    from gmail_history_threads t
   where t.relevant and (t.company_id = p_company or (v_dom is not null and registrable_domain(t.counterpart_domains[1]) = v_dom));
  v_in := v_in + (select count(*) from interactions i where i.company_id = p_company and i.direction = 'INBOUND' and i.channel <> 'MEETING');
  v_meet := (select count(*) from interactions i where i.company_id = p_company and i.channel = 'MEETING')
          + (select count(*) from opportunities o where o.company_id = p_company and o.status in ('CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON'));
  v_proj := (select count(*) from projects pr where pr.company_id = p_company and pr.status in ('DELIVERED', 'CLOSED'));
  v_paid := (select count(*) from revenue r where r.company_id = p_company and r.payment_status in ('PAID', 'PART_PAID'));
  v_intro := (select count(*) from relationship_edges e where e.relation in ('INTRODUCED', 'REFERRED')
               and ((e.from_type = 'COMPANY' and e.from_id = p_company) or (e.to_type = 'COMPANY' and e.to_id = p_company)));
  v_li := (select count(*) from linkedin_connections l where l.matched_company_id = p_company);

  if v_in > 0 then p := least(v_in * 4, 20); s := s + p; c := c || jsonb_build_object('key', 'replies', 'points', p, 'max', 20, 'evidence', v_in || ' emails from them (Gmail / CRM)'); end if;
  if v_two > 0 then p := least(v_two * 5, 10); s := s + p; c := c || jsonb_build_object('key', 'conversations', 'points', p, 'max', 10, 'evidence', v_two || ' two-way email threads'); end if;
  if v_meet > 0 then p := least(v_meet * 8, 15); s := s + p; c := c || jsonb_build_object('key', 'meetings', 'points', p, 'max', 15, 'evidence', v_meet || ' meetings / call-stage deals recorded'); end if;
  if v_proj > 0 then p := least(v_proj * 10, 20); s := s + p; c := c || jsonb_build_object('key', 'projects', 'points', p, 'max', 20, 'evidence', v_proj || ' delivered projects'); end if;
  if v_paid > 0 then s := s + 15; c := c || jsonb_build_object('key', 'revenue', 'points', 15, 'max', 15, 'evidence', v_paid || ' paid invoices'); end if;
  if v_proj + v_paid >= 2 then s := s + 10; c := c || jsonb_build_object('key', 'repeat_work', 'points', 10, 'max', 10, 'evidence', 'repeat work (projects + paid invoices = ' || (v_proj + v_paid) || ')'); end if;
  if v_intro > 0 then p := least(v_intro * 5, 10); s := s + p; c := c || jsonb_build_object('key', 'introductions', 'points', p, 'max', 10, 'evidence', v_intro || ' recorded introductions / referrals'); end if;
  if v_last is not null then
    p := case when v_last > now() - interval '30 days' then 10 when v_last > now() - interval '90 days' then 5 when v_last > now() - interval '365 days' then 2 else 0 end;
    if p > 0 then s := s + p; c := c || jsonb_build_object('key', 'recency', 'points', p, 'max', 10, 'evidence', 'last two-way contact ' || to_char(v_last, 'DD Mon YYYY')); end if;
  end if;
  if v_li > 0 then s := s + 3; c := c || jsonb_build_object('key', 'linkedin', 'points', 3, 'max', 3, 'evidence', v_li || ' LinkedIn connection(s) at the company (how well you know them is not measured)'); end if;
  s := least(s, 100);
  return jsonb_build_object('score', s, 'label', case when s = 0 then 'NONE' when s < 20 then 'COLD' when s < 45 then 'WARM' else 'STRONG' end,
    'components', c, 'method', 'Behaviour only: replies, conversations, meetings, projects, revenue, repeat work, introductions, recency, LinkedIn. Seniority is not measured.');
end $$;

-- ================================================================ relationship graph (derived from records + manual edges)
create or replace view public.relationship_graph with (security_invoker = true) as
  select 'PERSON'::text from_type, k.id from_id, nullif(btrim(concat_ws(' ', k.first_name, k.last_name)), '') from_label, 'WORKS_AT'::text relation,
         'COMPANY'::text to_type, c.id to_id, c.name to_label, 'CRM'::text evidence_source, 'contacts.' || k.id evidence_ref,
         case when k.email_status = 'VERIFIED' then 'VERIFIED' else 'NEEDS_VERIFICATION' end provenance
    from contacts k join companies c on c.id = k.company_id
  union all
  select 'COMPANY', c.id, c.name, case when cr.partner_class is not null then 'PARTNER_OF_NOYA' else 'CLIENT_OF_NOYA' end, 'COMPANY', null, 'NOYA',
         'CRM', 'company_relationships.' || cr.id, cr.provenance
    from company_relationships cr join companies c on c.id = cr.company_id where cr.stage in ('PILOT', 'ACTIVE', 'PRODUCTIVE', 'STRATEGIC')
  union all
  select 'COMPANY', c.id, c.name, 'CLIENT_OF_NOYA', 'COMPANY', null, 'NOYA', 'CRM', 'companies.relationship_status', 'MANUALLY_CONFIRMED'
    from companies c where c.relationship_status = 'client'
  union all
  select 'COMPANY', so.company_id, so.org_name, case so.org_role when 'SPONSOR' then 'SPONSORS' when 'ORGANISER' then 'ORGANISES' else 'INVOLVED_IN' end,
         'EVENT', so.signal_id, i.title, 'SOURCE', coalesce(so.source_url, i.source_url), so.provenance
    from signal_organisations so join intelligence i on i.id = so.signal_id
  union all
  select 'TEAM_MEMBER', null, 'Adam', 'KNOWS', 'PERSON', l.id, concat_ws(' ', l.first_name, l.last_name) || coalesce(' (' || l.company || ')', ''), 'LINKEDIN', l.profile_url, 'VERIFIED'
    from linkedin_connections l
  union all
  select 'TEAM_MEMBER', null, 'NOYA (noya@)', 'EMAILED', 'COMPANY', t.company_id, coalesce(c.name, t.counterpart_domains[1]), 'EMAIL', 'gmail thread ' || t.gmail_thread_id, 'VERIFIED'
    from gmail_history_threads t left join companies c on c.id = t.company_id where t.relevant and t.inbound > 0 and t.outbound > 0
  union all
  select 'COMPANY', pi.supplier_company_id, sc.name, 'SUPPLIES', 'PROJECT', p.id, p.name, 'PROJECT', 'project_items.' || pi.id, 'MANUALLY_CONFIRMED'
    from project_items pi join projects p on p.id = pi.project_id join companies sc on sc.id = pi.supplier_company_id
  union all
  select from_type, from_id, from_label, relation, to_type, to_id, to_label, evidence_source, evidence_ref, provenance from relationship_edges;
revoke all on public.relationship_graph from anon, authenticated;

-- "How do we get into this account?" — only routes backed by a record.
create or replace function public.account_paths(p_company uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(p order by (p->>'rank')::int), '[]'::jsonb) from (
    select jsonb_build_object('rank', 1, 'route', 'Direct email history', 'detail', sum(t.outbound) || ' sent · ' || sum(t.inbound) || ' received · last ' || to_char(max(t.last_at), 'DD Mon YYYY'),
                              'evidence', 'NOYA Gmail', 'provenance', 'VERIFIED') p
      from gmail_history_threads t left join companies c on c.id = p_company
     where t.relevant and (t.company_id = p_company or registrable_domain(t.counterpart_domains[1]) = registrable_domain(c.website))
    having count(*) > 0
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
    select jsonb_build_object('rank', 4, 'route', e.relation || ' via ' || e.from_label, 'detail', e.from_label || ' ' || lower(replace(e.relation, '_', ' ')) || ' ' || e.to_label,
                              'evidence', coalesce(e.evidence_ref, e.evidence_source), 'provenance', e.provenance)
      from relationship_edges e where e.to_type = 'COMPANY' and e.to_id = p_company and e.relation in ('INTRODUCED', 'REFERRED', 'WORKS_WITH')
    union all
    select jsonb_build_object('rank', 5, 'route', 'Partner at the same event: ' || pc.name, 'detail', pc.name || ' (NOYA partner) is involved in "' || i.title || '"',
                              'evidence', coalesce(so2.source_url, i.source_url), 'provenance', so2.provenance)
      from signal_organisations so1 join signal_organisations so2 on so2.signal_id = so1.signal_id and so2.company_id is distinct from so1.company_id
      join companies pc on pc.id = so2.company_id join company_relationships cr on cr.company_id = pc.id and cr.stage in ('ACTIVE', 'PRODUCTIVE', 'STRATEGIC', 'PILOT')
      join intelligence i on i.id = so1.signal_id
     where so1.company_id = p_company
  ) x
$$;

-- ================================================================ sales stage (derived from the live status + evidence)
create or replace function public.opportunity_sales_stage(p_status text, p_has_contact boolean, p_has_draft boolean, p_signal_stage text)
returns text language sql immutable as $$
  select case p_status
    when 'WON' then 'WON' when 'LOST' then 'LOST' when 'LONG_TERM' then 'NURTURE' when 'ARCHIVED' then 'LOST'
    when 'NEGOTIATION' then 'NEGOTIATION' when 'PROPOSAL' then 'PROPOSAL' when 'CALL_REQUIRED' then 'DISCOVERY'
    when 'INTERESTED' then 'ENGAGED' when 'CONTACTED' then 'CONTACTED' when 'FOLLOW_UP' then 'CONTACTED'
    when 'READY' then case when p_has_draft then 'OUTREACH_PREPARED' else 'CONTACT_IDENTIFIED' end
    else case when p_has_contact then 'CONTACT_IDENTIFIED' when p_signal_stage in ('QUALIFIED', 'ACTIVE') or p_status = 'RESEARCHING' then 'QUALIFIED' else 'DISCOVERED' end
  end
$$;

create or replace function public.partner_stage_of_opp(p_status text, p_has_contact boolean)
returns text language sql immutable as $$
  select case p_status
    when 'WON' then 'ACTIVE' when 'LOST' then 'LOST' when 'ARCHIVED' then 'LOST' when 'LONG_TERM' then 'DORMANT'
    when 'NEGOTIATION' then 'PROPOSED' when 'PROPOSAL' then 'PROPOSED' when 'CALL_REQUIRED' then 'VALUE_EXCHANGE'
    when 'INTERESTED' then 'CONVERSATION' when 'CONTACTED' then 'CONTACTED' when 'FOLLOW_UP' then 'CONTACTED'
    when 'READY' then 'QUALIFIED'
    else case when p_has_contact then 'QUALIFIED' else 'TARGET' end end
$$;

-- ================================================================ opportunity score (0–100, explainable, never money)
create or replace function public.opportunity_score(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare o opportunities%rowtype; i intelligence%rowtype; w jsonb; c companies%rowtype; k contacts%rowtype; rs jsonb;
        f_fit numeric; f_time numeric; f_serv numeric; f_acc numeric; f_ev numeric; f_src numeric;
        why_fit text; why_time text; why_serv text; why_acc text; why_ev text; why_src text; tot numeric; v_urg text; v_replied boolean;
begin
  select * into o from opportunities where id = p_id; if o.id is null then return null; end if;
  select * into i from intelligence where id = o.signal_id;
  select * into c from companies where id = o.company_id;
  select * into k from contacts where id = o.contact_id;
  w := coalesce((select value from system_config where key = 'opportunity_score_weights'),
                '{"strategic_fit": 25, "timing": 20, "service_fit": 20, "access": 15, "commercial_evidence": 10, "source_confidence": 10}');
  -- Strategic fit: the research agents' fit score for the company, else the segment's priority.
  if c.noya_fit is not null then f_fit := c.noya_fit / 100.0; why_fit := 'Company fit ' || c.noya_fit || '/100 (research agents)';
  else f_fit := case coalesce(i.category, '') when 'SPORTS' then 0.85 when 'ENTERTAINMENT' then 0.85 when 'EVENTS' then 0.8 when 'BRANDS' then 0.8
                  when 'PRODUCTION' then 0.75 when 'CORPORATE' then 0.7 when 'PRIVATE_UHNW' then 0.85 when 'HOSPITALITY' then 0.6 when 'REAL_ESTATE' then 0.65 else 0.5 end;
       why_fit := 'No company fit score; segment priority for ' || coalesce(i.category, 'this segment'); end if;
  -- Timing
  v_replied := exists (select 1 from gmail_sync_ledger l where l.opportunity_id = o.id and l.kind = 'INBOUND_REPLY' and l.received_at > now() - interval '30 days'
                        and l.classification in ('POSITIVE', 'MEETING_REQUEST', 'NEEDS_INFO', 'REFERRAL'));
  if v_replied then f_time := 1; why_time := 'They replied positively in the last 30 days';
  elsif i.id is not null then
    v_urg := signal_urgency(i.event_date, i.event_end, i.category, i.intelligence_type);
    f_time := case v_urg when 'NOW' then 1 when 'D7' then 0.9 when 'D30' then 0.7 when 'D90' then 0.5 when 'LATER' then 0.3 else 0 end;
    why_time := case v_urg when 'PASSED' then 'Event date has passed' else 'Act ' || case v_urg when 'NOW' then 'now' when 'D7' then 'within 7 days' when 'D30' then 'within 30 days' when 'D90' then 'within 90 days' else 'later' end
                || coalesce(' (event ' || to_char(i.event_date, 'DD Mon YYYY') || ')', ' (source timing)') end;
  elsif o.status in ('CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION') then f_time := 0.9; why_time := 'Deal is at ' || lower(o.status);
  else f_time := 0.3; why_time := 'No time trigger recorded'; end if;
  -- Service fit
  if o.product_code is not null and o.playbook_code is not null then f_serv := 1; why_serv := 'Playbook ' || o.playbook_code || ' → ' || o.product_code;
  elsif o.product_code is not null then f_serv := 0.75; why_serv := 'Product ' || o.product_code || ' (no playbook)';
  else f_serv := 0.35; why_serv := 'No NOYA product matched yet'; end if;
  -- Access / relationship path
  rs := case when o.company_id is not null then relationship_strength(o.company_id) end;
  if coalesce((rs->>'score')::int, 0) >= 45 then f_acc := 1; why_acc := 'Strong relationship (' || (rs->>'score') || ')';
  elsif coalesce((rs->>'score')::int, 0) >= 20 then f_acc := 0.75; why_acc := 'Warm relationship (' || (rs->>'score') || ')';
  elsif k.email_status = 'VERIFIED' then f_acc := 0.55; why_acc := 'Verified decision-maker email';
  elsif exists (select 1 from linkedin_connections l where l.matched_company_id = o.company_id) then f_acc := 0.5; why_acc := 'LinkedIn connection at the company';
  elsif coalesce((rs->>'score')::int, 0) > 0 then f_acc := 0.4; why_acc := 'Some contact history (' || (rs->>'score') || ')';
  elsif o.contact_id is not null or o.contact_email is not null then f_acc := 0.3; why_acc := 'Named contact, email not verified';
  else f_acc := 0; why_acc := 'No route in yet — find the decision maker'; end if;
  -- Commercial evidence (never an AI guess)
  if o.contracted_value is not null then f_ev := 1; why_ev := 'Contract value recorded';
  elsif o.proposal_value is not null then f_ev := 0.8; why_ev := 'Proposal value recorded';
  elsif o.client_budget is not null then f_ev := 0.7; why_ev := 'Client stated a budget';
  elsif o.status in ('CALL_REQUIRED', 'INTERESTED') or v_replied then f_ev := 0.5; why_ev := 'Positive engagement, no money discussed yet';
  else f_ev := 0; why_ev := 'No financial evidence'; end if;
  -- Source confidence
  if i.id is not null then f_src := coalesce(i.confidence_score, 50) / 100.0; why_src := 'Signal source confidence ' || coalesce(i.confidence_score, 50) || '/100 (' || i.provenance || ')';
  else f_src := case o.provenance when 'VERIFIED' then 1 when 'MANUALLY_CONFIRMED' then 0.9 when 'SOURCE_BACKED' then 0.8 when 'INFERRED' then 0.5 else 0.4 end;
       why_src := 'Record provenance ' || o.provenance; end if;
  tot := f_fit * (w->>'strategic_fit')::numeric + f_time * (w->>'timing')::numeric + f_serv * (w->>'service_fit')::numeric
       + f_acc * (w->>'access')::numeric + f_ev * (w->>'commercial_evidence')::numeric + f_src * (w->>'source_confidence')::numeric;
  return jsonb_build_object('score', coalesce(o.score_override, round(tot)::int), 'computed', round(tot)::int,
    'override', case when o.score_override is not null then jsonb_build_object('score', o.score_override, 'reason', o.score_override_reason, 'by', o.score_override_by, 'at', o.score_override_at) end,
    'components', jsonb_build_array(
      jsonb_build_object('key', 'strategic_fit', 'label', 'Strategic fit', 'points', round(f_fit * (w->>'strategic_fit')::numeric), 'max', (w->>'strategic_fit')::int, 'why', why_fit),
      jsonb_build_object('key', 'timing', 'label', 'Timing / urgency', 'points', round(f_time * (w->>'timing')::numeric), 'max', (w->>'timing')::int, 'why', why_time),
      jsonb_build_object('key', 'service_fit', 'label', 'Service fit', 'points', round(f_serv * (w->>'service_fit')::numeric), 'max', (w->>'service_fit')::int, 'why', why_serv),
      jsonb_build_object('key', 'access', 'label', 'Access / relationship path', 'points', round(f_acc * (w->>'access')::numeric), 'max', (w->>'access')::int, 'why', why_acc),
      jsonb_build_object('key', 'commercial_evidence', 'label', 'Commercial evidence', 'points', round(f_ev * (w->>'commercial_evidence')::numeric), 'max', (w->>'commercial_evidence')::int, 'why', why_ev),
      jsonb_build_object('key', 'source_confidence', 'label', 'Source confidence', 'points', round(f_src * (w->>'source_confidence')::numeric), 'max', (w->>'source_confidence')::int, 'why', why_src)),
    'note', 'Priority score, not money and not a probability of winning.');
end $$;

-- ================================================================ signal qualification gate (10 questions)
create or replace function public.signal_qualification(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare i intelligence%rowtype; orgs text; reach text; v_urg text; qs jsonb; n int;
begin
  select * into i from intelligence where id = p_id; if i.id is null then return null; end if;
  select string_agg(org_name || ' (' || lower(org_role) || ')', ', ') into orgs from signal_organisations where signal_id = p_id;
  select string_agg(distinct x, '; ') into reach from (
    select 'contact on file at ' || c.name x from signal_organisations so join companies c on c.id = so.company_id
     where so.signal_id = p_id and exists (select 1 from contacts k where k.company_id = c.id and (k.email is not null or k.linkedin is not null) and not coalesce(k.do_not_contact, false))
    union all
    select 'email history with ' || c.name from signal_organisations so join companies c on c.id = so.company_id
     where so.signal_id = p_id and relationship_strength(c.id)->>'label' <> 'NONE'
    union all
    select 'LinkedIn connection at ' || c.name from signal_organisations so join companies c on c.id = so.company_id
     where so.signal_id = p_id and exists (select 1 from linkedin_connections l where l.matched_company_id = c.id)) r;
  v_urg := signal_urgency(i.event_date, i.event_end, i.category, i.intelligence_type);
  qs := jsonb_build_array(
    jsonb_build_object('q', 'What happened?', 'a', coalesce(i.summary, i.title), 'ok', coalesce(i.summary, i.title) is not null, 'source', i.source_url),
    jsonb_build_object('q', 'Why should NOYA care?', 'a', coalesce(i.commercial_relevance, i.analysis->>'why_noya'), 'ok', coalesce(i.commercial_relevance, i.analysis->>'why_noya') is not null),
    jsonb_build_object('q', 'Who is behind it?', 'a', orgs, 'ok', orgs is not null),
    jsonb_build_object('q', 'What problem could NOYA solve?', 'a', i.problem_noya_solves, 'ok', i.problem_noya_solves is not null),
    jsonb_build_object('q', 'Which NOYA product?', 'a', array_to_string(i.product_codes, ', '), 'ok', coalesce(array_length(i.product_codes, 1), 0) > 0),
    jsonb_build_object('q', 'Who likely decides?', 'a', array_to_string(i.decision_roles[1:4], ', '), 'ok', coalesce(array_length(i.decision_roles, 1), 0) > 0),
    jsonb_build_object('q', 'Why would they care about NOYA?', 'a', i.commercial_angle, 'ok', i.commercial_angle is not null),
    jsonb_build_object('q', 'Can we reach them?', 'a', coalesce(reach, 'No route yet — no contact, email history or LinkedIn connection at the organisations'), 'ok', reach is not null),
    jsonb_build_object('q', 'When should we approach?', 'a', case v_urg when 'PASSED' then 'Event has passed' when 'NOW' then 'Now' when 'D7' then 'Within 7 days' when 'D30' then 'Within 30 days' when 'D90' then 'Within 90 days' else 'Later / watch' end
                        || coalesce(' — event ' || to_char(i.event_date, 'DD Mon YYYY'), ''), 'ok', v_urg <> 'PASSED'),
    jsonb_build_object('q', 'What happens next?', 'a', i.next_action, 'ok', i.next_action is not null));
  select count(*) into n from jsonb_array_elements(qs) q where (q->>'ok')::boolean;
  return jsonb_build_object('answered', n, 'of', 10, 'complete', n = 10, 'urgency', v_urg, 'questions', qs,
    'missing', (select coalesce(jsonb_agg(q->>'q'), '[]'::jsonb) from jsonb_array_elements(qs) q where not (q->>'ok')::boolean));
end $$;

-- ================================================================ outreach from the product template (never sent from here)
create or replace function public.render_template(p_text text, p_vars jsonb)
returns text language plpgsql immutable as $$
declare k text; v text; r text := p_text;
begin
  for k, v in select key, value from jsonb_each_text(p_vars) loop
    if v is not null and btrim(v) <> '' then r := replace(r, '{{' || k || '}}', v); end if;
  end loop;
  return r;
end $$;

create or replace function public.opportunity_outreach(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare o opportunities%rowtype; i intelligence%rowtype; p commercial_products%rowtype; k contacts%rowtype; v jsonb; subj text; body text; dm text; missing text[];
begin
  select * into o from opportunities where id = p_id; if o.id is null then return null; end if;
  select * into i from intelligence where id = o.signal_id;
  select * into p from commercial_products where code = o.product_code;
  select * into k from contacts where id = o.contact_id;
  if p.code is null then return jsonb_build_object('ready', false, 'missing', jsonb_build_array('product')); end if;
  v := jsonb_build_object(
    'first_name', coalesce(k.first_name, o.contact_first_name),
    'company', coalesce(o.company_name, (select name from companies where id = o.company_id)),
    'event', coalesce(i.analysis->>'event_name', regexp_replace(coalesce(i.title, ''), '\s*(will|is|has|announces|opens|to host|takes place).*$', '', 'i')),
    'event_date', to_char(i.event_date, 'FMDD Month'),
    'destination', coalesce(i.destination, o.destination, 'Egypt'),
    'trigger_detail', coalesce(o.commercial_trigger, i.title),
    'proof', '');
  subj := render_template(p.email_template->>'subject', v);
  body := regexp_replace(render_template(p.email_template->>'body', v), ' \n', E'\n', 'g');
  dm := render_template(p.dm_template, v);
  select array_agg(distinct r.m[1]) into missing from regexp_matches(subj || ' ' || body, '\{\{([a-z_]+)\}\}', 'g') as r(m);
  return jsonb_build_object('ready', missing is null and k.id is not null, 'subject', subj, 'body', body, 'dm', dm,
    'follow_ups', (select jsonb_agg(f || jsonb_build_object('message', render_template(f->>'message', v))) from jsonb_array_elements(p.follow_up_sequence) f),
    'missing', to_jsonb(coalesce(missing, '{}') || case when k.id is null then array['contact'] else '{}'::text[] end),
    'product', p.name, 'angle', coalesce(o.angle, i.commercial_angle));
end $$;

-- ================================================================ conversion: won → operations / partnership; delivered → expansion
create or replace function public.opportunity_won_flow()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_proj uuid; v_partner uuid; v_owner text; v_name text;
begin
  if new.status <> 'WON' or old.status = 'WON' then return new; end if;
  v_name := coalesce(new.company_name, (select name from companies where id = new.company_id), 'Client');
  if new.track = 'PARTNERSHIP' and new.company_id is not null then
    insert into company_relationships (company_id, relationship_type, relationship_status, owner, started_at, partner_class, stage, stage_evidence, provenance, next_action, next_action_due)
    values (new.company_id, 'PARTNER', 'ACTIVE', owner_for_role('PARTNERSHIPS'), current_date,
            case when new.opportunity_type ~* 'hotel|venue|supplier' or new.target_role in ('HOTEL', 'VENUE', 'OPERATOR') then 'SUPPLY' else 'DISTRIBUTION' end,
            'ACTIVE', 'Agreement won in CRM (opportunity ' || new.id || ')', 'MANUALLY_CONFIRMED', 'Agree how referrals / bookings flow and the first joint client', current_date + 7)
    on conflict (company_id, partner_class) where partner_class is not null do update set stage = case when company_relationships.stage in ('PRODUCTIVE', 'STRATEGIC') then company_relationships.stage else 'ACTIVE' end,
      relationship_status = 'ACTIVE', updated_at = now()
    returning id into v_partner;
    insert into tasks (company_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
    values (new.company_id, new.id, 'Activate partnership: ' || v_name, 'Partnership agreed. Set terms, rates / commission and the first joint opportunity. Nothing is sent automatically.',
            'PARTNERSHIP_ACTIVATION', owner_for_role('PARTNERSHIPS'), 'System (won → partnership)', 80, 'OPEN', now() + interval '2 days');
  else
    v_owner := owner_for_role(case when new.track = 'EVENT' then 'EVENTS' else 'OPERATIONS' end);
    insert into projects (opportunity_id, company_id, signal_id, name, project_type, destination, owner, currency, client_charge, status, provenance)
    values (new.id, new.company_id, new.signal_id, v_name || ' — ' || coalesce((select name from commercial_products where code = new.product_code), new.opportunity_type, 'Project'),
            coalesce(new.product_code, new.opportunity_type), new.destination, v_owner, new.currency, new.contracted_value, 'CONFIRMED', 'MANUALLY_CONFIRMED')
    on conflict (opportunity_id) do nothing
    returning id into v_proj;
    if v_proj is not null then
      insert into tasks (company_id, opportunity_id, project_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
      values (new.company_id, new.id, v_proj, 'Kick-off: confirm brief and suppliers — ' || v_name,
              'Won. Confirm the brief, dates, guest list and suppliers; add items in Operations. Record the invoice in Finance when issued.' ||
              case when new.contracted_value is null then ' Contract value not recorded yet — add it with evidence.' else '' end,
              'PROJECT_KICKOFF', v_owner, 'System (won → operations)', 85, 'OPEN', now() + interval '1 day');
    end if;
  end if;
  insert into approval_audit (opportunity_id, action, result, actor, detail)
  values (new.id, 'OPPORTUNITY_WON_FLOW', 'OK', 'system', jsonb_build_object('track', new.track, 'project_id', v_proj, 'partnership_id', v_partner));
  return new;
end $$;
drop trigger if exists opportunity_won_flow on public.opportunities;
create trigger opportunity_won_flow after update of status on public.opportunities
  for each row execute function public.opportunity_won_flow();

create or replace function public.project_delivered_flow()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_paths text; v_am text := owner_for_role('ACCOUNT_MANAGEMENT');
begin
  if new.status <> 'DELIVERED' or old.status = 'DELIVERED' then return new; end if;
  new.delivered_at := coalesce(new.delivered_at, now());
  select string_agg(u, ' · ') into v_paths from (
    select unnest(p.upsells) u from opportunities o join commercial_products p on p.code = o.product_code where o.id = new.opportunity_id
    union select unnest(pb.upsells) from opportunities o join commercial_playbooks pb on pb.code = o.playbook_code where o.id = new.opportunity_id) x;
  -- Two internal tasks, spaced out; no client message is created. Duplicates are prevented per project.
  insert into tasks (company_id, opportunity_id, project_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
  select new.company_id, new.opportunity_id, new.id, 'Ask for feedback — ' || new.name,
         'Delivered. A short personal check-in: what went well, what to improve. Record it in the project.', 'CLIENT_FEEDBACK', v_am, 'System (delivered → expansion)', 70, 'OPEN', now() + interval '2 days'
  where not exists (select 1 from tasks where project_id = new.id and task_type = 'CLIENT_FEEDBACK');
  insert into tasks (company_id, opportunity_id, project_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
  select new.company_id, new.opportunity_id, new.id, 'Expansion review — ' || new.name,
         'Only if feedback was positive. Pick at most one natural next step from what was delivered: ' || coalesce(v_paths, 'next edition, referral, retainer') ||
         '. Also consider: next destination, referral to a peer, partner relationship, retainer.', 'EXPANSION_REVIEW', v_am, 'System (delivered → expansion)', 60, 'OPEN', now() + interval '14 days'
  where not exists (select 1 from tasks where project_id = new.id and task_type = 'EXPANSION_REVIEW');
  return new;
end $$;
drop trigger if exists project_delivered_flow on public.projects;
create trigger project_delivered_flow before update of status on public.projects
  for each row execute function public.project_delivered_flow();

-- Partnership stages PRODUCTIVE / STRATEGIC must be earned by activity, never by prestige.
create or replace function public.partnership_stage_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_opps int; v_proj int; v_rev int;
begin
  if new.stage in ('PRODUCTIVE', 'STRATEGIC') and (tg_op = 'INSERT' or old.stage is distinct from new.stage) then
    v_opps := (select count(*) from opportunities where source_partner_id = new.id);
    v_proj := (select count(*) from project_items where supplier_company_id = new.company_id) + (select count(*) from projects p join opportunities o on o.id = p.opportunity_id where o.source_partner_id = new.id);
    v_rev := (select count(*) from revenue r join opportunities o on o.id = r.opportunity_id where o.source_partner_id = new.id and r.payment_status in ('PAID', 'PART_PAID'));
    if new.stage = 'PRODUCTIVE' and v_opps + v_proj + v_rev = 0 then
      raise exception 'STAGE_NEEDS_EVIDENCE' using hint = 'PRODUCTIVE needs at least one opportunity, project or paid revenue generated through this partner.';
    end if;
    if new.stage = 'STRATEGIC' and not (v_rev > 0 and v_opps + v_proj >= 2) then
      raise exception 'STAGE_NEEDS_EVIDENCE' using hint = 'STRATEGIC needs paid revenue and at least two opportunities / projects through this partner.';
    end if;
    new.stage_evidence := format('%s opportunities, %s projects/supplies, %s paid invoices through this partner (checked %s)', v_opps, v_proj, v_rev, to_char(now(), 'DD Mon YYYY'));
  end if;
  new.relationship_status := case when new.stage in ('PILOT', 'ACTIVE', 'PRODUCTIVE', 'STRATEGIC') then 'ACTIVE' when new.stage = 'DORMANT' then 'PAUSED'
                                  when new.stage = 'LOST' then 'ENDED' else 'POTENTIAL' end;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists partnership_stage_guard on public.company_relationships;
create trigger partnership_stage_guard before insert or update on public.company_relationships
  for each row execute function public.partnership_stage_guard();

-- Owner is never empty: route by track / product role.
create or replace function public.opportunity_default_owner()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.owner is null or btrim(new.owner) = '' then
    new.owner := owner_for_role(coalesce((select owner_role from commercial_products where code = new.product_code),
                                         case new.track when 'PARTNERSHIP' then 'PARTNERSHIPS' when 'EVENT' then 'EVENTS' else 'SALES' end));
  end if;
  return new;
end $$;
drop trigger if exists opportunity_default_owner on public.opportunities;
create trigger opportunity_default_owner before insert or update of owner on public.opportunities
  for each row execute function public.opportunity_default_owner();

alter table public.outreach_drafts drop constraint if exists outreach_drafts_source_check;
alter table public.outreach_drafts add constraint outreach_drafts_source_check check (source in ('WF05_ORIGINAL', 'ADAM_EDIT', 'PLAYBOOK_TEMPLATE'));

-- Seed partnership records only where the CRM already records a partner / supplier (no prestige guesses).
insert into company_relationships (company_id, relationship_type, relationship_status, owner, partner_class, partner_category, stage, geography, stage_evidence, provenance)
select c.id, case c.relationship_status when 'supplier' then 'SUPPLIER' else 'PARTNER' end, 'ACTIVE', owner_for_role('PARTNERSHIPS'),
       case when c.relationship_status = 'supplier' or c.company_type ~* 'hotel|resort|restaurant|venue|transport|yacht|villa|security|beach' then 'SUPPLY' else 'DISTRIBUTION' end,
       c.company_type, 'ACTIVE', c.country, 'CRM relationship_status = ' || c.relationship_status, 'MANUALLY_CONFIRMED'
  from companies c where c.relationship_status in ('partner', 'supplier', 'mixed') and coalesce(c.notes, '') not like '%MERGED_INTO:%'
on conflict do nothing;

-- Re-run enrichment on the signals already stored.
update public.intelligence set updated_at = updated_at;
