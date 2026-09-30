-- Fixes found by the commercial acceptance test (supabase/tests/commercial_acceptance.sql):
-- 1. {{proof}} is optional. With no recorded case study it blocked the Event Concierge and Athlete desks from producing any
--    outreach (HYROX, El Gouna). It now renders as nothing; a real, approved proof line can still be supplied later.
-- 2. A product sold as a PARTNERSHIP (e.g. NOYA Private to a property developer) used the private-client email.
--    Products can now carry a partner version; the partnership track uses it.
alter table public.commercial_products add column if not exists partner_email_template jsonb;

update public.commercial_products set partner_email_template = jsonb_build_object(
  'subject', '{{company}} buyers in Egypt',
  'body', E'Hi {{first_name}},\n\n{{trigger_detail}} — congratulations.\n\nBuyers at this level expect more than the keys: arrivals handled, a villa while they visit, the right tables, drivers.\n\nNOYA does this in Egypt for private clients. We could be the concierge your sales team introduces to buyers — working to your standards, reporting back to you.\n\nWorth 15 minutes to see if it fits the launch?\n\nAdam Elshazly\nFounder, NOYA Concierge')
where code = 'NOYA_PRIVATE';

create or replace function public.opportunity_outreach(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare o opportunities%rowtype; i intelligence%rowtype; p commercial_products%rowtype; k contacts%rowtype; v jsonb; t jsonb; subj text; body text; dm text; missing text[];
begin
  select * into o from opportunities where id = p_id; if o.id is null then return null; end if;
  select * into i from intelligence where id = o.signal_id;
  select * into p from commercial_products where code = o.product_code;
  select * into k from contacts where id = o.contact_id;
  if p.code is null then return jsonb_build_object('ready', false, 'missing', jsonb_build_array('product')); end if;
  t := coalesce(case when o.track = 'PARTNERSHIP' then p.partner_email_template end, p.email_template);
  v := jsonb_build_object(
    'first_name', coalesce(k.first_name, o.contact_first_name),
    'company', coalesce(o.company_name, (select name from companies where id = o.company_id)),
    'event', coalesce(i.analysis->>'event_name', regexp_replace(coalesce(i.title, ''), '\s*(will|is|has|announces|opens|to host|takes place).*$', '', 'i')),
    'event_date', to_char(i.event_date, 'FMDD Month'),
    'destination', coalesce(i.destination, o.destination, 'Egypt'),
    'trigger_detail', coalesce(o.commercial_trigger, i.title));
  -- proof is optional: only an approved, real proof line is ever inserted; otherwise the sentence slot disappears
  subj := render_template(t->>'subject', v);
  body := regexp_replace(render_template(replace(replace(t->>'body', ' {{proof}}', ''), '{{proof}}', ''), v), ' \n', E'\n', 'g');
  dm := render_template(replace(coalesce(p.dm_template, ''), ' {{proof}}', ''), v);
  select array_agg(distinct r.m[1]) into missing from regexp_matches(subj || ' ' || body, '\{\{([a-z_]+)\}\}', 'g') as r(m);
  return jsonb_build_object('ready', missing is null and k.id is not null, 'subject', subj, 'body', body, 'dm', dm,
    'follow_ups', (select jsonb_agg(f || jsonb_build_object('message', render_template(replace(f->>'message', ' {{proof}}', ''), v))) from jsonb_array_elements(p.follow_up_sequence) f),
    'missing', to_jsonb(coalesce(missing, '{}') || case when k.id is null then array['contact'] else '{}'::text[] end),
    'product', p.name, 'template', case when t = p.email_template then 'client' else 'partner' end, 'angle', coalesce(o.angle, i.commercial_angle));
end $$;
revoke all on function public.opportunity_outreach(uuid) from public, anon, authenticated;

-- 3. Cold-email review of the acceptance drafts:
--    * dates rendered as "14 November ," (Month is space-padded) → FMMonth;
--    * Event Concierge Desk opened with the whole news headline + "congratulations" and repeated the event name three times;
--    * a hotel / Nile operator (supply partner) received the travel-agency pitch → supply version.
alter table public.commercial_products add column if not exists supply_email_template jsonb;

update public.commercial_products set email_template = email_template || jsonb_build_object(
  'subject', 'Guests arriving for {{event}}',
  'body', E'Hi {{first_name}},\n\nWith international guests arriving for {{event}}, most of what they remember happens outside the venue: arrivals, transfers, where they stay, where they eat.\n\nNOYA runs that layer on the ground in Egypt — one desk, one named lead, a 24/7 line for your guests, with our hotel and transport partners behind it. {{proof}}\n\nWould a 15-minute call next week be useful to see whether a guest desk makes sense this year?\n\nAdam Elshazly\nFounder, NOYA Concierge')
where code = 'EVENT_CONCIERGE_DESK';

update public.commercial_products set supply_email_template = jsonb_build_object(
  'subject', '{{company}} and NOYA clients',
  'body', E'Hi {{first_name}},\n\n{{trigger_detail}} — congratulations.\n\nNOYA plans Egypt for private clients and families who travel at this level, and new openings are what they ask us about first.\n\nWe would like to introduce {{company}} to them properly: one contact on your sales team, agreed partner terms, and our clients looked after before and after their stay.\n\nCould we find 15 minutes in the next few weeks?\n\nAdam Elshazly\nFounder, NOYA Concierge')
where code = 'EGYPT_DESTINATION_DESK';

create or replace function public.opportunity_outreach(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare o opportunities%rowtype; i intelligence%rowtype; p commercial_products%rowtype; k contacts%rowtype; v jsonb; t jsonb; subj text; body text; dm text; missing text[];
begin
  select * into o from opportunities where id = p_id; if o.id is null then return null; end if;
  select * into i from intelligence where id = o.signal_id;
  select * into p from commercial_products where code = o.product_code;
  select * into k from contacts where id = o.contact_id;
  if p.code is null then return jsonb_build_object('ready', false, 'missing', jsonb_build_array('product')); end if;
  t := coalesce(case when o.target_role in ('HOTEL', 'OPERATOR', 'VENUE') then p.supply_email_template end,
                case when o.track = 'PARTNERSHIP' then p.partner_email_template end, p.email_template);
  v := jsonb_build_object(
    'first_name', coalesce(k.first_name, o.contact_first_name),
    'company', coalesce(o.company_name, (select name from companies where id = o.company_id)),
    'event', coalesce(i.analysis->>'event_name', regexp_replace(coalesce(i.title, ''), '\s*(will|is|has|announces|opens|to host|takes place).*$', '', 'i')),
    'event_date', to_char(i.event_date, 'FMDD FMMonth'),
    'destination', coalesce(i.destination, o.destination, 'Egypt'),
    'trigger_detail', coalesce(o.commercial_trigger, i.title));
  -- proof is optional: only an approved, real proof line is ever inserted; otherwise the sentence slot disappears
  subj := render_template(t->>'subject', v);
  body := regexp_replace(render_template(replace(replace(t->>'body', ' {{proof}}', ''), '{{proof}}', ''), v), ' \n', E'\n', 'g');
  dm := render_template(replace(coalesce(p.dm_template, ''), ' {{proof}}', ''), v);
  select array_agg(distinct r.m[1]) into missing from regexp_matches(subj || ' ' || body, '\{\{([a-z_]+)\}\}', 'g') as r(m);
  return jsonb_build_object('ready', missing is null and k.id is not null, 'subject', subj, 'body', body, 'dm', dm,
    'follow_ups', (select jsonb_agg(f || jsonb_build_object('message', render_template(replace(f->>'message', ' {{proof}}', ''), v))) from jsonb_array_elements(p.follow_up_sequence) f),
    'missing', to_jsonb(coalesce(missing, '{}') || case when k.id is null then array['contact'] else '{}'::text[] end),
    'product', p.name, 'template', case when t = p.email_template then 'client' when t = p.supply_email_template then 'supply' else 'partner' end, 'angle', coalesce(o.angle, i.commercial_angle));
end $$;
revoke all on function public.opportunity_outreach(uuid) from public, anon, authenticated;

-- 4. Relationship strength counts replies logged outside Gmail as a conversation (and for recency).
create or replace function public.relationship_strength(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e record; v_iw boolean; v_ilast timestamptz; v_two int; v_last timestamptz; v_in int := 0; v_meet int := 0; v_proj int := 0; v_paid int := 0; v_intro int := 0; v_li int := 0; c jsonb := '[]'; s int := 0; p int;
begin
  select * into e from company_email_stats(p_company);
  -- replies logged outside Gmail (WhatsApp, phone, LinkedIn, CRM) count as a conversation too
  v_iw := exists (select 1 from interactions i where i.company_id = p_company and i.direction = 'INBOUND' and i.channel <> 'MEETING')
      and exists (select 1 from interactions i where i.company_id = p_company and i.direction = 'OUTBOUND');
  v_ilast := case when v_iw then (select max(occurred_at) from interactions i where i.company_id = p_company and i.direction = 'INBOUND') end;
  v_two := coalesce(e.two_way, 0) + case when v_iw then 1 else 0 end;
  v_last := greatest(e.last_two_way, v_ilast);
  v_in := coalesce(e.inbound, 0) + (select count(*) from interactions i where i.company_id = p_company and i.direction = 'INBOUND' and i.channel <> 'MEETING');
  v_meet := (select count(*) from interactions i where i.company_id = p_company and i.channel = 'MEETING')
          + (select count(*) from opportunities o where o.company_id = p_company and o.status in ('CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON'));
  v_proj := (select count(*) from projects pr where pr.company_id = p_company and pr.status in ('DELIVERED', 'CLOSED'));
  v_paid := (select count(*) from revenue r where r.company_id = p_company and r.payment_status in ('PAID', 'PART_PAID'));
  v_intro := (select count(*) from relationship_edges x where x.relation in ('INTRODUCED', 'REFERRED')
               and ((x.from_type = 'COMPANY' and x.from_id = p_company) or (x.to_type = 'COMPANY' and x.to_id = p_company)));
  v_li := (select count(*) from linkedin_connections l where l.matched_company_id = p_company);
  if v_in > 0 then p := least(v_in * 4, 20); s := s + p; c := c || jsonb_build_object('key', 'replies', 'points', p, 'max', 20, 'evidence', v_in || ' emails from them (Gmail / CRM)'); end if;
  if v_two > 0 then p := least(v_two * 5, 10); s := s + p; c := c || jsonb_build_object('key', 'conversations', 'points', p, 'max', 10, 'evidence', v_two || ' two-way conversations (email threads / logged replies)'); end if;
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
