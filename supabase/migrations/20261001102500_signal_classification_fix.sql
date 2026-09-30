-- Classification uses the source facts (title + summary) and workflow 09's own type first; the AI-written
-- "potential opportunity" text is not used for classification (it mentions many services and misled it).
-- A date only counts as the event date if it is on/after the day the signal was found (announcement dates excluded).
create or replace function public.signal_category_of(p_type text, p_text text)
returns text language sql immutable as $$
  select case
    when t ~* 'film festival|cinema|premiere|red carpet' then 'ENTERTAINMENT'
    when t ~* 'hyrox|marathon|championship|tournament|grand prix|world cup|padel|golf|tennis|triathlon|ironman|football|squash|athlete|fitness rac' then 'SPORTS'
    when t ~* 'festival|concert|(^|[^a-z])dj([^a-z]|$)|line-?up|live show' then 'ENTERTAINMENT'
    when t ~* 'wedding' then 'WEDDINGS'
    when t ~* 'shoot(ing)? in|filming|film commission|production company|on location|film set' then 'PRODUCTION'
    when ty ~* 'CONFERENCE|SUMMIT' then 'CORPORATE'
    when ty ~* 'AVIATION|ROUTE|YACHT|MARINA' then 'TRAVEL'
    when ty ~* 'HOTEL|RESORT|BEACH_CLUB|RESTAURANT|DMC|CRUISE' then 'HOSPITALITY'
    when ty ~* 'REAL_ESTATE|RESIDENTIAL' or t ~* 'residential|residences|real estate|compound|sales office|damac|emaar' then 'REAL_ESTATE'
    when t ~* 'activation|pop-up|brand launch|boutique|flagship|fashion show' then 'BRANDS'
    when t ~* 'hotel|resort|beach club|restaurant|dahabeya|nile cruise' then 'HOSPITALITY'
    when t ~* 'conference|summit|forum|delegation|congress|expo|exhibition' then 'CORPORATE'
    when ty ~* 'TOURISM' or t ~* 'airline|flight|route|marina|yacht' then 'TRAVEL'
    when ty ~* 'EVENT' then 'EVENTS'
    else 'OTHER' end
  from (select coalesce(p_type, '') ty, coalesce(p_text, '') t) x
$$;

-- A playbook needs the category AND keyword evidence in the source text. Otherwise none (the analyst or a person decides).
create or replace function public.playbook_for(p_category text, p_text text)
returns text language sql stable set search_path = public as $$
  select p.code from commercial_playbooks p
   cross join lateral (select count(*) hits from unnest(p.keywords) k where coalesce(p_text, '') ~* ('(^|[^a-z])' || k)) h
   where p_category = any(p.categories) and h.hits > 0
   order by (p_category = any(p.categories)) desc, h.hits desc, p.priority desc
   limit 1
$$;

create or replace function public.intelligence_enrich()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_text text := concat_ws(' ', new.title, new.summary);
        pb commercial_playbooks%rowtype; d date[];
begin
  if new.category is null then new.category := signal_category_of(new.intelligence_type, v_text); end if;
  if new.region is null then new.region := signal_region_of(new.country, new.destination); end if;
  if new.event_date is null then
    d := extract_event_dates(v_text);
    if d is not null and d[1] >= coalesce(new.discovered_at, now())::date then new.event_date := d[1]; new.event_end := nullif(d[2], d[1]); end if;
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
    new.next_action := case when new.stage = 'WATCH' then 'Watch: re-check when more is known'
                            else 'Confirm who is behind it and the decision makers (' || coalesce(array_to_string(new.decision_roles[1:3], ', '), 'commercial lead') || ')' end;
  end if;
  if new.stage = 'DISMISSED' and (tg_op = 'INSERT' or old.stage is distinct from 'DISMISSED') then new.status := 'IGNORED'; end if;
  if tg_op = 'UPDATE' and new.stage is distinct from old.stage then new.stage_changed_at := now(); end if;
  return new;
end $$;

-- Re-derive the rule-based fields on the signals workflow 09 already stored (nothing was set by a person yet).
update public.intelligence set captured_by = 'workflow 09' where captured_by is null;
update public.intelligence set category = null, event_date = null, event_end = null, playbook_code = null, product_codes = '{}', decision_roles = '{}',
       services = '{}', commercial_angle = null, problem_noya_solves = null, next_action = null
 where captured_by = 'workflow 09' and analysed_at is null;
update public.intelligence set stage = 'RESEARCH' where captured_by = 'workflow 09' and stage = 'WATCH' and coalesce(relevance_score, 0) >= 60;
update public.intelligence set next_action = null where captured_by = 'workflow 09' and analysed_at is null;
