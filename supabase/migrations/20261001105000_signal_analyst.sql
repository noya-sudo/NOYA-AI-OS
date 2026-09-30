-- Workflow 17 (Signal Analyst): AI reads each new signal's stored text and proposes the organisations involved,
-- the commercial angle and the likely decision roles. The database, not the model, decides what is kept:
--   * an organisation is kept only if its name appears verbatim in the stored source text (SOURCE_BACKED);
--   * dates are never taken from the model (rules extract them from the source text);
--   * the angle / problem / roles are stored as the AI's suggestion (INFERRED) and shown labelled as AI.
create or replace function public.signal_analysis_queue(p_limit int default 10)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'title', i.title, 'summary', i.summary, 'opportunity_text', i.potential_opportunity,
           'relevance_text', i.commercial_relevance, 'destination', i.destination, 'type', i.intelligence_type, 'source_name', i.source_name, 'source_url', i.source_url,
           'category', i.category, 'playbook', i.playbook_code) order by i.discovered_at desc), '[]'::jsonb)
  from (select * from intelligence where analysed_at is null and stage <> 'DISMISSED' order by discovered_at desc limit greatest(1, least(coalesce(p_limit, 10), 25))) i
$$;

create or replace function public.signal_analysis_save(p_id uuid, p jsonb, p_model text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare i intelligence%rowtype; o jsonb; v_text text; kept jsonb := '[]'; rejected jsonb := '[]'; v_role text; v_pb text;
begin
  select * into i from intelligence where id = p_id; if i.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  v_text := lower(concat_ws(' ', i.title, i.summary, i.potential_opportunity, i.commercial_relevance, i.source_name));
  for o in select * from jsonb_array_elements(coalesce(p->'organisations', '[]')) loop
    v_role := upper(coalesce(o->>'role', 'OTHER'));
    if v_role not in ('ORGANISER', 'PROMOTER', 'SPONSOR', 'BRAND', 'AGENCY', 'PR', 'HOTEL', 'VENUE', 'OPERATOR', 'DEVELOPER', 'PRODUCTION', 'TALENT_AGENCY', 'TEAM', 'GOVERNMENT', 'OTHER') then v_role := 'OTHER'; end if;
    if exists (select 1 from signal_organisations x where x.signal_id = p_id and lower(x.org_name) = lower(btrim(o->>'name'))) then
      continue;  -- already recorded (possibly with a role a person chose) — never duplicate an organisation
    elsif btrim(coalesce(o->>'name', '')) ~ '^[A-Z][a-z]+ [A-Z][a-z]+$' and v_role in ('TALENT_AGENCY', 'TEAM', 'OTHER')
       and btrim(o->>'name') !~* '(group|agency|festival|hotel|resort|studio|films?|media|events?|club|company|holding|properties|partners|management|travel|tours|museum|bank|authority)' then
      rejected := rejected || jsonb_build_object('name', o->>'name', 'why', 'looks like a person, not an organisation');
    elsif length(btrim(coalesce(o->>'name', ''))) >= 2 and position(lower(btrim(o->>'name')) in v_text) > 0 then
      insert into signal_organisations (signal_id, org_name, org_role, evidence, source_url, provenance)
      values (p_id, btrim(o->>'name'), v_role, left(coalesce(o->>'evidence', o->>'name'), 300), i.source_url, 'SOURCE_BACKED')
      on conflict (signal_id, lower(org_name), org_role) do nothing;
      kept := kept || jsonb_build_object('name', o->>'name', 'role', v_role);
    else
      rejected := rejected || jsonb_build_object('name', o->>'name', 'why', 'not named in the stored source text');
    end if;
  end loop;
  v_pb := nullif(p->>'playbook', '');
  if v_pb is not null and not exists (select 1 from commercial_playbooks where code = v_pb) then v_pb := null; end if;
  update intelligence set
    analysed_at = now(), analysis_model = left(p_model, 120),
    analysis = jsonb_build_object('event_name', left(p->>'event_name', 120), 'why_noya', left(p->>'why_noya', 500), 'problem', left(p->>'problem', 400),
                                  'angle', left(p->>'angle', 500), 'decision_roles', p->'decision_roles', 'next_action', left(p->>'next_action', 300),
                                  'playbook_suggested', v_pb, 'orgs_kept', kept, 'orgs_rejected', rejected, 'provenance', 'INFERRED (AI from stored source text)'),
    playbook_code = coalesce(playbook_code, v_pb),
    stage = case when coalesce((p->>'not_commercially_relevant')::boolean, false) and stage in ('WATCH', 'RESEARCH') then 'WATCH' else stage end,
    updated_at = now()
  where id = p_id;
  return jsonb_build_object('ok', true, 'kept', kept, 'rejected', rejected);
end $$;
revoke all on function public.signal_analysis_queue(int) from public, anon, authenticated;
revoke all on function public.signal_analysis_save(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.signal_analysis_queue(int) to service_role;
grant execute on function public.signal_analysis_save(uuid, jsonb, text) to service_role;

-- Clean-up of the first run: a person recorded as an organisation, and a duplicate of an organisation already on file.
delete from signal_organisations where org_name = 'Mel Gibson' and provenance = 'SOURCE_BACKED';
delete from signal_organisations a using signal_organisations b
 where a.signal_id = b.signal_id and lower(a.org_name) = lower(b.org_name) and a.id <> b.id and a.created_at > b.created_at;
