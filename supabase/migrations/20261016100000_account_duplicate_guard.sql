-- Account identity guard (16 Oct 2026, data integrity; found in the freeze sanity check).
-- Defect: Workflow 23 corrects a wrong website (the news or trade site a discovery run saved) to the official domain
-- through company_correct(), without checking whether that domain already belongs to an account. The record became a
-- second copy of the account: Aman (hotelmanagement-network.com -> aman.com), Maybourne (hotelnewsresource.com ->
-- maybourne.com) and Mandarin Oriental (jardines.com -> mandarinoriental.com). Workflow 07 saved Ten Lifestyle Group
-- although Ten Technologies Group, its new name, was already the account on tenlifestylegroup.com.
-- 1. The four duplicates are merged the 29 Sep way: nothing is deleted, the older record stays the account, people it
--    did not already have move across, the duplicate's opportunity is archived, and the duplicate keeps its row with
--    MERGED_INTO:<id> and universe EXCLUDED (out of planning, verification and drafting).
-- 2. Two pairs share a domain but are separate businesses (two Four Seasons hotels; MCI's Middle East and UK offices):
--    marked SEPARATE_ACCOUNT.
-- 3. company_account_guard(): when a website correction or an agent save lands on a domain that already belongs to a
--    live account, the newer record is PARKED as a possible duplicate (no cold outreach, no verification spend) with the
--    reason on the record. The daily operating check merges it or marks it SEPARATE_ACCOUNT. Nothing merges by itself.

-- ---------------------------------------------------------------- 3. guard
create or replace function public.company_account_guard(p_company uuid, p_by text default 'Account identity guard')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_dom text; c record; o record; d record; k record;
begin
  select id, name, notes, created_at, registrable_domain(website) dom into c from companies where id = p_company;
  v_dom := c.dom;
  if v_dom is null or coalesce(c.notes, '') ~ '(SEPARATE_ACCOUNT|MERGED_INTO:)' then return null; end if;
  -- the oldest other live record on the same domain
  select id, name, notes, created_at, universe_status into o from companies
   where id <> c.id and registrable_domain(website) = v_dom
     and coalesce(notes, '') !~ '(SEPARATE_ACCOUNT|MERGED_INTO:)' and coalesce(universe_status, '') <> 'EXCLUDED'
   order by created_at, id limit 1;
  if o.id is null then return null; end if;
  -- the newer of the two is the possible duplicate; the older stays the account
  if (o.created_at, o.id) < (c.created_at, c.id) then
    select c.id, c.name, c.notes into d; select o.id, o.name into k;
  else
    select o.id, o.name, o.notes into d; select c.id, c.name into k;
  end if;
  if coalesce(d.notes, '') ~ 'POSSIBLE_DUPLICATE_OF:' then return k.id; end if;
  perform company_correct(d.id, 'universe_status', 'PARKED', 'Possible duplicate of ' || k.name || ' (same website, ' || v_dom || ')', null, p_by);
  perform company_correct(d.id, 'universe_reason',
    'Possible duplicate of ' || k.name || ' (same website, ' || v_dom || '). Held from cold outreach until merged or marked SEPARATE_ACCOUNT.',
    'Account identity guard', null, p_by);
  perform company_correct(d.id, 'notes', concat_ws(chr(10), d.notes, 'POSSIBLE_DUPLICATE_OF:' || k.id),
    'Account identity guard', null, p_by);
  return k.id;
end $$;
revoke all on function public.company_account_guard(uuid, text) from public, anon, authenticated;

-- company_correct: unchanged, plus the guard after a website change.
create or replace function public.company_correct(p_company uuid, p_field text, p_new text, p_reason text, p_source text, p_by text)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare v_old text; v_type text;
begin
  if p_field not in ('website', 'website_confirmed_at', 'instagram', 'universe_status', 'universe_reason', 'notes', 'outreach_hold_until', 'outreach_hold_reason') then
    raise exception 'company_correct: field % is not correctable here', p_field; end if;
  if coalesce(btrim(p_reason), '') = '' or coalesce(btrim(p_by), '') = '' then raise exception 'company_correct: reason and decided_by are required'; end if;
  v_type := case when p_field in ('website_confirmed_at', 'outreach_hold_until') then 'timestamptz' else 'text' end;
  if not exists (select 1 from companies where id = p_company) then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  execute format('select %I::text from companies where id = $1', p_field) into v_old using p_company;
  if v_old is not distinct from p_new then return jsonb_build_object('ok', true, 'changed', false); end if;
  insert into company_field_history (company_id, field, old_value, new_value, reason, source_url, decided_by)
  values (p_company, p_field, v_old, p_new, p_reason, nullif(btrim(coalesce(p_source, '')), ''), p_by);
  execute format('update companies set %I = $1::%s where id = $2', p_field, v_type) using p_new, p_company;
  -- a new website is unconfirmed until someone confirms it
  if p_field = 'website' then update companies set website_confirmed_at = null where id = p_company; end if;
  -- a corrected website that already belongs to a live account must not become a second copy of it (16 Oct 2026)
  if p_field = 'website' and p_new is not null then perform company_account_guard(p_company, p_by); end if;
  return jsonb_build_object('ok', true, 'changed', true, 'old', v_old, 'new', p_new);
end $function$;
revoke all on function public.company_correct(uuid, text, text, text, text, text) from public, anon, authenticated;

-- company_intake: unchanged, plus the same guard for agent saves (the row does not exist yet, so it is set inline).
create or replace function public.company_intake()
returns trigger language plpgsql security definer set search_path = public as $function$
declare o record;
begin
  if new.acquisition_lane is null then
    new.acquisition_lane := coalesce(agent_lane(new.source, new.company_type, new.sector),
                                     company_lane(null, new.prospect_segment, new.vertical_override, new.company_type));
  end if;
  if coalesce(new.source, '') ~* 'NOYA .*Department' then
    if new.universe_status is null then
      new.universe_status := case when new.source ~* 'watchlist' then 'PARKED' else 'RESEARCHING' end;
    end if;
    new.universe_added_at := coalesce(new.universe_added_at, now());
    new.universe_reason := coalesce(nullif(btrim(new.universe_reason), ''),
      nullif(btrim(substring(coalesce(new.notes, '') from 'Why NOYA:\s*([^\n]+)')), ''),
      nullif(btrim(substring(coalesce(new.notes, '') from 'Research summary:\s*([^\n]+)')), ''));
    -- an agent save on a domain that already belongs to a live account is held as a possible duplicate (16 Oct 2026)
    if registrable_domain(new.website) is not null then
      select id, name into o from companies
       where registrable_domain(website) = registrable_domain(new.website)
         and coalesce(notes, '') !~ '(SEPARATE_ACCOUNT|MERGED_INTO:)' and coalesce(universe_status, '') <> 'EXCLUDED'
       order by created_at, id limit 1;
      if o.id is not null then
        new.universe_status := 'PARKED';
        new.universe_reason := 'Possible duplicate of ' || o.name || ' (same website, ' || registrable_domain(new.website)
                               || '). Held from cold outreach until merged or marked SEPARATE_ACCOUNT.';
        new.notes := concat_ws(chr(10), new.notes, 'POSSIBLE_DUPLICATE_OF:' || o.id);
      end if;
    end if;
  end if;
  return new;
end $function$;

-- ---------------------------------------------------------------- 1. merge the four duplicates
do $merge$
declare m record; v_by text := 'NOYA system review (freeze sanity check, 16 Oct 2026)';
begin
  for m in select * from (values
      ('3292a73b-abb3-4179-8efd-b519a1acd205'::uuid, 'fc71b95b-7dc5-4de5-a8b2-a3960f14297d'::uuid),  -- Aman Group -> Aman Resorts, Hotels & Residences
      ('39e2e820-e860-492b-8f58-fb62f925b215'::uuid, 'a9893b36-c0da-442e-a2ed-67ce51c56a42'::uuid),  -- Mandarin Oriental Hotel Group (14 Oct) -> (7 Sep)
      ('c2b6ac44-5d32-4634-acfd-b741c9475676'::uuid, '4eb1b05d-aa93-4d82-b7a2-c85ada9eec9e'::uuid),  -- Maybourne Hotel Group (12 Oct) -> (7 Oct)
      ('c2a025aa-5b61-4f9b-86a1-883324abbcf4'::uuid, '665d9f76-824f-4f38-a19b-c53fc29ee280'::uuid)   -- Ten Lifestyle Group -> Ten Technologies Group (renamed Sep 2026)
    ) v(dup_id, keep_id)
  loop
    if exists (select 1 from companies where id = m.dup_id and coalesce(notes, '') like '%MERGED_INTO:%') then continue; end if;
    -- out of planning, verification and drafting first, so moving people does not requalify it
    perform company_correct(m.dup_id, 'universe_status', 'EXCLUDED', 'Duplicate account merged', null, v_by);
    perform company_correct(m.dup_id, 'universe_reason',
      'Duplicate of ' || (select name from companies where id = m.keep_id) || ' (same account, '
        || (select registrable_domain(website) from companies where id = m.keep_id) || '); merged 16 Oct 2026.', 'Duplicate account merged', null, v_by);
    perform company_correct(m.dup_id, 'notes',
      concat_ws(chr(10), (select notes from companies where id = m.dup_id), 'MERGED_INTO:' || m.keep_id), 'Duplicate account merged', null, v_by);
    -- people the account does not already have (same email, or same name) move across; exact duplicates stay as evidence
    update contacts k set company_id = m.keep_id,
           notes = concat_ws(chr(10), k.notes, 'Moved 16 Oct 2026 from duplicate account ' || m.dup_id || ' (merged).')
     where k.company_id = m.dup_id
       and not exists (select 1 from contacts x where x.company_id = m.keep_id and (
             (coalesce(btrim(k.email), '') <> '' and lower(btrim(x.email)) = lower(btrim(k.email)))
          or (btrim(coalesce(k.first_name, '') || coalesce(k.last_name, '')) <> ''
              and lower(btrim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '')))
                = lower(btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, ''))))));
    -- the duplicate's opportunity is archived on the duplicate (kept as evidence)
    update opportunities set status = 'ARCHIVED',
           next_action = 'Merged 16 Oct 2026: duplicate account; the live opportunity is on company ' || m.keep_id || '.'
     where company_id = m.dup_id and status <> 'ARCHIVED';
  end loop;
end $merge$;

-- ---------------------------------------------------------------- 2. separate businesses on a shared domain
do $sep$
declare r record; v_by text := 'NOYA system review (freeze sanity check, 16 Oct 2026)';
begin
  for r in select * from (values
      ('0d0aef05-7259-4e36-a3df-d1e71f71e7a5'::uuid, 'SEPARATE_ACCOUNT: Four Seasons Red Sea at Shura Island is its own hotel account (property-level).'),
      ('6086af42-f34d-48de-a211-947ebc48c0fb'::uuid, 'SEPARATE_ACCOUNT: Grand-Hôtel du Cap-Ferrat is its own hotel account (property-level).'),
      ('b51a9ff0-ee3d-46b2-9d7d-458625f1d2ca'::uuid, 'SEPARATE_ACCOUNT: MCI Middle East is a separate regional office from MCI UK.'),
      ('4e7d5297-df52-4e41-9d82-5852501621f3'::uuid, 'SEPARATE_ACCOUNT: MCI UK is a separate regional office from MCI Middle East.')
    ) v(id, note)
  loop
    perform company_correct(r.id, 'notes', concat_ws(chr(10), (select notes from companies where id = r.id), r.note),
      'Shared domain, separate business', null, v_by)
      from companies where id = r.id and coalesce(notes, '') not like '%SEPARATE_ACCOUNT%';
  end loop;
end $sep$;
