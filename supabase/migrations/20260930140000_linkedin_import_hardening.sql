-- LinkedIn import, hardened for a real export (thousands of rows, imported in batches of 500):
--  * one canonical profile link per person (https://www.linkedin.com/in/<slug>), so www / country
--    sub-domains / http / trailing slashes / query strings never create a second record;
--  * duplicates inside the same file are counted and ignored;
--  * new vs updated vs duplicate vs skipped are reported separately;
--  * a person who changed company is re-matched (old company / Gmail link cleared, evidence rebuilt);
--  * matching runs only for the rows in the batch, so large exports stay fast.
-- Relationship strength is still never inferred.

create or replace function public.linkedin_canonical_url(p text)
returns text language sql immutable as $$
  select 'https://www.linkedin.com/in/' || m[1]
    from (select regexp_match(lower(btrim(coalesce(p, ''))), '^(?:https?://)?(?:[a-z]{2,3}\.|www\.)?linkedin\.com/in/([^/?#\s]+)') m) x
   where m is not null
$$;

alter table public.linkedin_connections add column if not exists history_threads int not null default 0;

drop function if exists public.linkedin_match_all();
create or replace function public.linkedin_match_all(p_ids uuid[] default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare n_co int; n_ct int; n_h int;
begin
  -- 1. Company: exact comparable name, or the business domain of an email in Adam's own export.
  --    Company keys are computed once per call (hash join), not once per pair.
  with ck as materialized (select distinct on (company_name_key(c.name)) company_name_key(c.name) nk, c.id from companies c
                            where coalesce(c.notes, '') not like '%MERGED_INTO:%' and company_name_key(c.name) is not null order by company_name_key(c.name), c.created_at),
       lk as materialized (select l.id, company_name_key(l.company) nk from linkedin_connections l
                            where (p_ids is null or l.id = any(p_ids)) and l.matched_company_id is null)
  update linkedin_connections l set matched_company_id = ck.id, updated_at = now()
    from lk join ck using (nk) where l.id = lk.id;
  get diagnostics n_co = row_count;
  with cd as materialized (select distinct on (registrable_domain(c.website)) registrable_domain(c.website) dom, c.id from companies c
                            where coalesce(c.notes, '') not like '%MERGED_INTO:%' and c.website is not null order by registrable_domain(c.website), c.created_at),
       ld as materialized (select l.id, registrable_domain(split_part(l.email, '@', 2)) dom from linkedin_connections l
                            where (p_ids is null or l.id = any(p_ids)) and l.matched_company_id is null and l.email is not null
                              and not email_is_freemail(split_part(l.email, '@', 2)))
  update linkedin_connections l set matched_company_id = cd.id, updated_at = now()
    from ld join cd using (dom) where l.id = ld.id;

  -- 2. Person: same email, or same full name at the matched company.
  update linkedin_connections l set matched_contact_id = k.id, updated_at = now()
    from contacts k
   where (p_ids is null or l.id = any(p_ids))
     and l.matched_contact_id is null and l.email is not null and lower(k.email) = lower(l.email);
  perform linkedin_match_contacts();
  select count(*) into n_ct from linkedin_connections where matched_contact_id is not null and (p_ids is null or id = any(p_ids));

  -- 3. NOYA Gmail relationship: the same person wrote to NOYA (sender name), or the company name is the
  --    email domain of a relationship group, or the matched company / contact already has email history.
  --    Relationship groups are computed once per call (the view is costly per row).
  create temp table if not exists _li_grp (gmail_thread_id text, gkey text) on commit drop;
  truncate _li_grp;
  insert into _li_grp select gmail_thread_id, gkey from gmail_thread_groups;
  with senders as materialized (
    select distinct on (nm) nm, gkey from (
      select lower(btrim(regexp_replace(m.from_name, '\s*[|(].*$', ''))) nm, g.gkey, m.sent_at
        from gmail_history_messages m join _li_grp g using (gmail_thread_id)
       where m.direction = 'INBOUND' and m.category = 'COMMERCIAL' and m.from_name is not null) s
    order by nm, sent_at desc),
  dkeys as materialized (select distinct on (nk) nk, gkey from (
      select company_name_key(split_part(substr(gkey, 3), '.', 1)) nk, gkey from (select distinct gkey from _li_grp where gkey like 'd:%') d) k
    where nk is not null order by nk, gkey),
  gk as materialized (select distinct gkey from _li_grp),
  lk as materialized (select l0.id, company_name_key(l0.company) nk,
                             case when l0.first_name is not null and l0.last_name is not null then lower(btrim(l0.first_name || ' ' || l0.last_name)) end nm,
                             'co:' || l0.matched_company_id::text co, 'ct:' || l0.matched_contact_id::text ct
                        from linkedin_connections l0 where (p_ids is null or l0.id = any(p_ids))),
  -- plain hash joins on precomputed keys (a correlated lookup re-evaluated the name key per candidate)
  x as materialized (
    select lk.id, coalesce(s.gkey, d.gkey, gco.gkey, gct.gkey) gkey
      from lk left join senders s on s.nm = lk.nm left join dkeys d on d.nk = lk.nk
              left join gk gco on gco.gkey = lk.co left join gk gct on gct.gkey = lk.ct)
  update linkedin_connections l set matched_history_key = x.gkey, updated_at = now()
    from x where l.id = x.id and x.gkey is not null and l.matched_history_key is distinct from x.gkey;
  select count(*) into n_h from linkedin_connections where matched_history_key is not null and (p_ids is null or id = any(p_ids));

  -- 4. Evidence, in words, plus the email-history thread count HQ shows (stored, so reads stay fast).
  with hs as materialized (select g.gkey, count(*) n, sum(t.outbound) o, sum(t.inbound) i
                from _li_grp g join gmail_history_threads t using (gmail_thread_id) group by g.gkey)
  update linkedin_connections l set
    history_threads = coalesce((select hs.n from hs where hs.gkey = l.matched_history_key), 0),
    match_evidence = coalesce((select jsonb_agg(e) from (
      select 'Company matches CRM account: ' || c.name as e from companies c where c.id = l.matched_company_id
      union all select 'Same person as CRM contact: ' || nullif(btrim(concat_ws(' ', k.first_name, k.last_name)), '') from contacts k where k.id = l.matched_contact_id
      union all select 'Active opportunity at their company: ' || count(*) from opportunities o
                 where o.company_id = l.matched_company_id and o.status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM') having count(*) > 0
      union all select 'Emailed with NOYA (Gmail): ' || hs.o || ' sent, ' || hs.i || ' received' from hs where hs.gkey = l.matched_history_key
    ) ev where e is not null), '[]'::jsonb)
   where (p_ids is null or l.id = any(p_ids));
  return jsonb_build_object('companies_newly_matched', n_co, 'contacts_matched', n_ct, 'history_matched', n_h);
end $$;
revoke all on function public.linkedin_match_all(uuid[]) from public, anon, authenticated;

create or replace function public.hq_import_connections(p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); r jsonb; v_url text; v_co uuid; v_id uuid; v_ins boolean;
        v_new int := 0; v_upd int := 0; v_dup int := 0; v_skip int := 0; v_seen text[] := '{}'; v_ids uuid[] := '{}'; v_map jsonb;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 2000 then return jsonb_build_object('ok', false, 'reason', 'INVALID_ROWS'); end if;
  select coalesce(jsonb_object_agg(nk, id), '{}') into v_map from (
    select distinct on (company_name_key(c.name)) company_name_key(c.name) nk, c.id from companies c
     where coalesce(c.notes, '') not like '%MERGED_INTO:%' and company_name_key(c.name) is not null order by company_name_key(c.name), c.created_at) m;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_url := linkedin_canonical_url(r->>'url');
    if v_url is null then v_skip := v_skip + 1; continue; end if;
    if v_url = any(v_seen) then v_dup := v_dup + 1; continue; end if;
    v_seen := v_seen || v_url;
    v_co := (v_map->>company_name_key(r->>'company'))::uuid;
    insert into linkedin_connections (first_name, last_name, profile_url, email, company, position, connected_on, matched_company_id, vertical)
    values (hq_trim(r->>'first_name'), hq_trim(r->>'last_name'), v_url, nullif(lower(btrim(coalesce(r->>'email', ''))), ''),
            hq_trim(r->>'company'), hq_trim(r->>'position'),
            case when r->>'connected_on' ~ '^\d{4}-\d{2}-\d{2}$' then (r->>'connected_on')::date end, v_co,
            hq_vertical((select company_type from companies where id = v_co), r->>'position', r->>'company'))
    on conflict (profile_url) do update set
      first_name = coalesce(excluded.first_name, linkedin_connections.first_name),
      last_name = coalesce(excluded.last_name, linkedin_connections.last_name),
      email = coalesce(excluded.email, linkedin_connections.email),
      connected_on = coalesce(linkedin_connections.connected_on, excluded.connected_on),
      -- changed company: forget the old company / Gmail link and match again
      matched_company_id = case when company_name_key(excluded.company) is distinct from company_name_key(linkedin_connections.company)
                                then excluded.matched_company_id
                                else coalesce(linkedin_connections.matched_company_id, excluded.matched_company_id) end,
      matched_history_key = case when company_name_key(excluded.company) is distinct from company_name_key(linkedin_connections.company)
                                 then null else linkedin_connections.matched_history_key end,
      company = excluded.company, position = excluded.position, vertical = excluded.vertical, updated_at = now()
    returning id, (xmax = 0) into v_id, v_ins;
    if v_ins then v_new := v_new + 1; else v_upd := v_upd + 1; end if;
    v_ids := v_ids || v_id;
  end loop;
  perform linkedin_match_all(v_ids);
  perform hq_audit('LINKEDIN_IMPORT', null, jsonb_build_object('rows', jsonb_array_length(p_rows), 'new', v_new, 'updated', v_upd,
    'duplicates_in_file', v_dup, 'skipped', v_skip));
  return jsonb_build_object('ok', true, 'new', v_new, 'updated', v_upd, 'duplicates', v_dup, 'skipped', v_skip, 'upserted', v_new + v_upd);
end $$;
revoke all on function public.hq_import_connections(jsonb) from public, anon;
grant execute on function public.hq_import_connections(jsonb) to authenticated;

-- Existing rows (none at the time of writing) move to the canonical link; a clash keeps the older row.
update linkedin_connections l set profile_url = linkedin_canonical_url(l.profile_url)
 where linkedin_canonical_url(l.profile_url) is not null and l.profile_url <> linkedin_canonical_url(l.profile_url)
   and not exists (select 1 from linkedin_connections o where o.profile_url = linkedin_canonical_url(l.profile_url));

-- HQ directory: read the stored count instead of scanning the relationship view per connection.
do $$
declare d text;
begin
  d := pg_get_functiondef('public.hq_directory()'::regprocedure);
  d := replace(d, $x$(select count(*) from gmail_thread_groups g where g.gkey = l.matched_history_key)$x$, $x$l.history_threads$x$);
  if d not like '%l.history_threads%' then raise exception 'directory patch failed'; end if;
  execute d;
end $$;
