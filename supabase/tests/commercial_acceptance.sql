-- NOYA commercial core — acceptance test. Runs six real signals through the 19-step commercial chain against the live
-- database, then RAISES on purpose so the whole transaction rolls back: the test contacts, wins, revenue and projects
-- never persist, and no email request can leave the database (hq_approve_draft is never called).
-- Run with the Supabase SQL runner; the report is the JSON in the error message.
do $$
declare
  u record; sigs uuid[] := array['9da3c7f9-5eac-45c5-8b99-c9b6769ae214', '1218021c-645c-454f-97b7-47ead048da24', '83b4b521-e08f-46be-9c86-486177cbfecf',
                                 'e7e0d1e0-7215-4aae-a2c6-da189685a114', '59ff8e74-5018-4fa2-974b-de1e53ac12ad', 'f702f23e-fefd-4fae-9b4e-067b080bd2e9']::uuid[];
  s uuid; i intelligence%rowtype; so signal_organisations%rowtype; pb commercial_playbooks%rowtype; rep jsonb := '[]'; st jsonb; r jsonb; q jsonb;
  v_co uuid; v_ct uuid; v_opp uuid; v_opp2 uuid; targets jsonb; v_prods text[]; v_track text; d outreach_drafts%rowtype; x jsonb; v_proj uuid; v_rev uuid;
  s1 jsonb; s2 jsonb; n int; k int := 0;
begin
  select a.* into u from hq_admins a limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', (select id from auth.users where lower(email) = lower(u.email) limit 1), 'email', u.email, 'role', 'authenticated')::text, true);
  foreach s in array sigs loop
    k := k + 1; st := '{}';
    select * into i from intelligence where id = s;
    select * into pb from commercial_playbooks where code = i.playbook_code;
    st := st || jsonb_build_object('scenario', left(i.title, 70),
      '01_signal', jsonb_build_object('source', i.source_url is not null, 'captured_by', i.captured_by),
      '02_classified', i.category || ' / ' || i.region,
      '03_playbook', i.playbook_code,
      '04_timing', jsonb_build_object('event', i.event_date, 'urgency', signal_urgency(i.event_date, i.event_end, i.category, i.intelligence_type)),
      '05_orgs', (select jsonb_agg(org_name || ' [' || org_role || ', ' || provenance || ']') from signal_organisations where signal_id = s),
      '06_products', i.product_codes,
      '07_angle', i.commercial_angle is not null and i.problem_noya_solves is not null);
    q := signal_qualification(s);
    st := st || jsonb_build_object('08_qualification_before', (q->>'answered') || '/10 missing ' || (q->'missing')::text);
    select * into so from signal_organisations where signal_id = s order by case org_role when 'ORGANISER' then 0 when 'PROMOTER' then 1 when 'OPERATOR' then 2 when 'DEVELOPER' then 3 else 9 end, created_at limit 1;
    if so.id is null then
      r := hq_signal_promote(s, '[]');
      st := st || jsonb_build_object('09_to_crm', 'no organisation named in the source — stays in RESEARCH', '10_promote', r);
      rep := rep || st; continue;
    end if;
    -- 09: organisation → CRM company (source-backed), then a clearly labelled TEST contact so "Can we reach them?" is answered
    r := hq_signal_org_to_crm(so.id); select company_id into v_co from signal_organisations where id = so.id;
    insert into contacts (company_id, first_name, last_name, position, email, email_status, source, notes)
    values (v_co, 'Test', 'Contact', 'Head of Partnerships (TEST)', 'acceptance.test+' || k || '@example.com', 'VERIFIED', 'ACCEPTANCE TEST', 'Rolled back — never persists')
    returning id into v_ct;
    q := signal_qualification(s);
    st := st || jsonb_build_object('09_to_crm', jsonb_build_object('rpc', r->'ok', 'company', v_co is not null, 'research_task', exists (select 1 from tasks where signal_id = s and task_type = 'CONTACT_RESEARCH'),
      'qualification_after', (q->>'answered') || '/10', 'paths', jsonb_array_length(coalesce(account_paths(v_co), '[]'))));
    -- 10–11: promote to opportunities (playbook products for the organisation's role; two products where the playbook offers two)
    select array_agg(distinct t_->>'product') into v_prods from jsonb_array_elements(pb.target_orgs) t_ where t_->>'org_role' = so.org_role;
    v_prods := coalesce(v_prods[1:2], array[i.product_codes[1]]);
    v_track := case when i.playbook_code in ('HOSPITALITY_EXPANSION', 'HOTEL_OPENING') then 'PARTNERSHIP' end;
    select jsonb_agg(jsonb_build_object('org_id', so.id, 'product', p, 'track', v_track)) into targets from unnest(v_prods) p;
    r := hq_signal_promote(s, targets);
    v_opp := (r->'created'->0->>'opportunity_id')::uuid; v_opp2 := (r->'created'->1->>'opportunity_id')::uuid;
    if v_opp is null then st := st || jsonb_build_object('10_promote', r); rep := rep || st; continue; end if;
    select stage into x from (select to_jsonb(stage) stage from intelligence where id = s) z;
    st := st || jsonb_build_object('10_promote', jsonb_build_object('created', r->'created', 'signal_stage', x),
      '11_score_owner', (select jsonb_build_object('score', opportunity_score(o.id)->'score', 'owner', o.owner, 'track', o.track, 'value', o.estimated_value, 'next', o.next_action) from opportunities o where o.id = v_opp));
    -- 12–14: outreach from the product template into the existing approval queue
    r := hq_prepare_outreach(v_opp, v_ct);
    select * into d from outreach_drafts where opportunity_id = v_opp order by created_at desc limit 1;
    select qq into x from jsonb_array_elements(hq_commercial()->'queue') qq where (qq->>'id')::uuid = v_opp;
    st := st || jsonb_build_object('12_outreach', jsonb_build_object('rpc', r->'ok', 'reason', r->'reason', 'subject', d.subject, 'template', opportunity_outreach(v_opp)->>'template', 'words', array_length(regexp_split_to_array(btrim(coalesce(d.body, '')), '\s+'), 1),
        'unfilled_placeholders', coalesce(d.subject, '') || coalesce(d.body, '') ~ '\{\{'),
      '13_approval_task', exists (select 1 from tasks where opportunity_id = v_opp and task_type = 'SALES_OUTREACH_APPROVAL' and status = 'OPEN'),
      '14_queue', jsonb_build_object('stage', x->>'stage', 'owner', x->>'owner', 'money', x->'money'));
    -- 15: reply arrives (what workflow 13 records) → stage and relationship strength move
    s1 := relationship_strength(v_co);
    insert into interactions (company_id, contact_id, opportunity_id, channel, direction, subject, summary)
    values (v_co, v_ct, v_opp, 'EMAIL', 'OUTBOUND', d.subject, 'TEST sent'), (v_co, v_ct, v_opp, 'EMAIL', 'INBOUND', 'Re: ' || d.subject, 'TEST reply: interested, send a proposal');
    update opportunities set status = 'INTERESTED' where id = v_opp;
    s2 := relationship_strength(v_co);
    select qq into x from jsonb_array_elements(hq_commercial()->'queue') qq where (qq->>'id')::uuid = v_opp;
    st := st || jsonb_build_object('15_reply', jsonb_build_object('stage', x->>'stage', 'strength', (s1->>'label') || ' → ' || (s2->>'label'), 'why', (select jsonb_agg(c_->>'key') from jsonb_array_elements(s2->'components') c_)));
    -- 16: proposal value — refused without evidence, stored with it
    begin r := hq_opportunity_commercial(v_opp, '{"proposal_value": 45000, "currency": "USD"}'); exception when others then r := jsonb_build_object('raised', sqlerrm); end;
    st := st || jsonb_build_object('16a_value_without_evidence', r);
    r := hq_opportunity_commercial(v_opp, '{"proposal_value": 45000, "currency": "USD", "value_evidence": "TEST proposal PDF v1 sent"}');
    update opportunities set status = 'PROPOSAL' where id = v_opp;
    st := st || jsonb_build_object('16b_proposal', (select jsonb_build_object('rpc', r->'ok', 'estimated_value', estimated_value, 'probability', probability) from opportunities where id = v_opp));
    -- 17: won → project + kickoff (sales) or ACTIVE partnership + activation task (partnership track)
    update opportunities set status = 'WON', contracted_value = 42000, value_evidence = 'TEST signed contract' where id = v_opp;
    select id into v_proj from projects where opportunity_id = v_opp;
    st := st || jsonb_build_object('17_won', jsonb_build_object('project', v_proj is not null,
      'partnership', (select stage from company_relationships where company_id = v_co order by updated_at desc nulls last limit 1),
      'tasks', (select jsonb_agg(task_type) from tasks where opportunity_id = v_opp and task_type in ('PROJECT_KICKOFF', 'PARTNERSHIP_ACTIVATION'))));
    if v_proj is null then  -- partnership track: the guard must refuse PRODUCTIVE until real activity flows through the partner
      x := hq_partner_upsert(v_co, (select partner_class from company_relationships where company_id = v_co and partner_class is not null limit 1), '{"stage": "STRATEGIC"}');
      st := st || jsonb_build_object('17b_strategic_without_revenue', x->>'reason');
      rep := rep || st; continue;
    end if;
    -- 18: invoice + payment + project economics
    r := hq_finance_upsert(null, v_co, v_opp, 'USD', 42000, 'TEST deposit invoice', 'TEST-001', current_date + 14, 'SENT', 'PROJECT', 'Rolled back');
    v_rev := (r->>'id')::uuid;
    if v_rev is null then select id into v_rev from revenue where opportunity_id = v_opp order by created_at desc limit 1; end if;
    update revenue set project_id = v_proj where id = v_rev;
    r := hq_record_payment(v_rev, 42000, current_date, 'BANK_TRANSFER', 'TEST', 'Rolled back');
    perform hq_project_update(v_proj, '{"client_charge": 42000, "supplier_cost": 29500, "currency": "USD", "status": "LIVE"}');
    st := st || jsonb_build_object('18_money', (select jsonb_build_object('invoice', rv.invoice_status, 'payment', rv.payment_status, 'gross_profit', p.gross_profit, 'pay_rpc', r->'ok')
      from projects p, revenue rv where p.id = v_proj and rv.id = v_rev));
    -- 19: delivered → feedback (+2d) and expansion review (+14d), deduplicated
    perform hq_project_update(v_proj, '{"status": "DELIVERED"}');
    perform hq_project_update(v_proj, '{"status": "DELIVERED"}');
    st := st || jsonb_build_object('19_expansion', (select jsonb_agg(task_type || ' due ' || to_char(due_at, 'DD Mon')) from tasks where project_id = v_proj and task_type in ('CLIENT_FEEDBACK', 'EXPANSION_REVIEW')));
    rep := rep || st;
  end loop;
  -- no-fake-money check: an AI estimate written directly is moved to legacy, never shown as pipeline
  insert into opportunities (company_name, opportunity_type, status, approval_status, estimated_value, probability, description)
  values ('TEST AI ESTIMATE', 'OTHER', 'NEW', 'PENDING', 250000, 60, 'TEST') returning id into v_opp;
  rep := rep || (select jsonb_build_object('money_guard', jsonb_build_object('estimated_value', estimated_value, 'probability', probability, 'legacy', legacy_ai_estimate)) from opportunities where id = v_opp);
  rep := rep || jsonb_build_object('live_fake_pipeline', (select count(*) from opportunities where estimated_value is not null and value_evidence is null));
  raise exception 'ACCEPTANCE %', rep;
end $$;
