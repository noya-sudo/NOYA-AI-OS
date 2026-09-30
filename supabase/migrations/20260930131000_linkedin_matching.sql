-- LinkedIn connections are matched to what NOYA already knows, with the evidence recorded for each
-- match. Relationship strength is never inferred: it stays UNKNOWN unless Adam records how he knows
-- someone. Re-importing never duplicates (profile URL is normalised and unique).

-- Comparable company name: lower case, legal / generic suffixes removed, letters and digits only.
create or replace function public.company_name_key(p text)
returns text language sql immutable as $$
  select case when length(k) >= 3 then k end from (
    select lower(regexp_replace(regexp_replace(coalesce(p, ''),
      '\m(ltd|limited|llc|inc|incorporated|plc|gmbh|sas|srl|spa|ag|bv|llp|pte|pty|co|company|group|holdings?|the|international|intl)\M', '', 'gi'),
      '[^a-z0-9]', '', 'gi')) k) x
$$;

alter table public.linkedin_connections add column if not exists matched_history_key text;
alter table public.linkedin_connections add column if not exists match_evidence jsonb not null default '[]'::jsonb;

create or replace function public.linkedin_match_all()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare n_co int; n_ct int; n_h int;
begin
  -- 1. Company: exact comparable name, or the business domain of an email in Adam's own export.
  update linkedin_connections l set matched_company_id = c.id, updated_at = now()
    from companies c
   where l.matched_company_id is null and coalesce(c.notes, '') not like '%MERGED_INTO:%'
     and ((company_name_key(l.company) is not null and company_name_key(l.company) = company_name_key(c.name))
          or (l.email is not null and not email_is_freemail(split_part(l.email, '@', 2)) and c.website is not null
              and registrable_domain(split_part(l.email, '@', 2)) = registrable_domain(c.website)));
  get diagnostics n_co = row_count;

  -- 2. Person: same email, or same full name at the matched company (or anywhere if no company).
  update linkedin_connections l set matched_contact_id = k.id, updated_at = now()
    from contacts k
   where l.matched_contact_id is null and l.email is not null and lower(k.email) = lower(l.email);
  perform linkedin_match_contacts();
  select count(*) into n_ct from linkedin_connections where matched_contact_id is not null;

  -- 3. NOYA Gmail relationship: the same person wrote to NOYA (sender name), or the company name is the
  --    email domain of a relationship group, or the matched company / contact already has email history.
  update linkedin_connections l set matched_history_key = x.gkey, updated_at = now()
    from (
      select l2.id, coalesce(
        (select g.gkey from gmail_history_messages m join gmail_thread_groups g using (gmail_thread_id)
          where m.direction = 'INBOUND' and m.category = 'COMMERCIAL' and l2.first_name is not null and l2.last_name is not null
            and lower(btrim(regexp_replace(m.from_name, '\s*[|(].*$', ''))) = lower(btrim(l2.first_name || ' ' || l2.last_name)) limit 1),
        (select g.gkey from gmail_thread_groups g where company_name_key(l2.company) is not null
            and g.gkey = 'd:' || (select registrable_domain(d) from gmail_history_threads t, unnest(t.counterpart_domains) d
                                   where t.gmail_thread_id = g.gmail_thread_id limit 1)
            and company_name_key(split_part(substr(g.gkey, 3), '.', 1)) = company_name_key(l2.company) limit 1),
        (select g.gkey from gmail_thread_groups g where g.gkey in ('co:' || l2.matched_company_id::text, 'ct:' || l2.matched_contact_id::text) limit 1)) gkey
      from linkedin_connections l2) x
   where l.id = x.id and x.gkey is not null and l.matched_history_key is distinct from x.gkey;
  select count(*) into n_h from linkedin_connections where matched_history_key is not null;

  -- 4. Evidence, in words, for every connection.
  update linkedin_connections l set match_evidence = coalesce((select jsonb_agg(e) from (
      select 'Company matches CRM account: ' || c.name as e from companies c where c.id = l.matched_company_id
      union all select 'Same person as CRM contact: ' || nullif(btrim(concat_ws(' ', k.first_name, k.last_name)), '') from contacts k where k.id = l.matched_contact_id
      union all select 'Active opportunity at their company: ' || count(*) from opportunities o
                 where o.company_id = l.matched_company_id and o.status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM') having count(*) > 0
      union all select 'Emailed with NOYA (Gmail): ' || sum(t.outbound) || ' sent, ' || sum(t.inbound) || ' received'
                 from gmail_thread_groups g join gmail_history_threads t using (gmail_thread_id) where g.gkey = l.matched_history_key having count(*) > 0
    ) ev where e is not null), '[]'::jsonb)
   where true;
  return jsonb_build_object('companies_newly_matched', n_co, 'contacts_matched', n_ct, 'history_matched', n_h);
end $$;
revoke all on function public.linkedin_match_all() from public, anon, authenticated;

do $$
declare d text;
begin
  -- import: normalise the profile URL (no query string, no trailing slash) and run the full matcher
  d := pg_get_functiondef('public.hq_import_connections(jsonb)'::regprocedure);
  d := replace(d, $x$v_url := lower(btrim(coalesce(r->>'url', '')));$x$,
                  $x$v_url := regexp_replace(regexp_replace(lower(btrim(coalesce(r->>'url', ''))), '[?#].*$', ''), '/+$', '');$x$);
  d := replace(d, $x$  perform linkedin_match_contacts();
  perform hq_audit('LINKEDIN_IMPORT', null,$x$, $x$  perform linkedin_match_all();
  perform hq_audit('LINKEDIN_IMPORT', null,$x$);
  if d not like '%linkedin_match_all()%' or d not like '%[?#].*$%' then raise exception 'import patch failed'; end if;
  execute d;

  -- directory: evidence + Gmail relationship key per connection
  d := pg_get_functiondef('public.hq_directory()'::regprocedure);
  d := replace(d, $x$'matched_contact_id', l.matched_contact_id,$x$,
                  $x$'matched_contact_id', l.matched_contact_id, 'history_key', l.matched_history_key, 'evidence', l.match_evidence,$x$);
  d := replace(d, $x$(select count(*) from gmail_history_threads t where t.relevant and (t.company_id = l.matched_company_id or t.contact_id = l.matched_contact_id))$x$,
                  $x$(select count(*) from gmail_thread_groups g where g.gkey = l.matched_history_key)$x$);
  if d not like '%''history_key''%' then raise exception 'directory patch failed'; end if;
  execute d;
end $$;
