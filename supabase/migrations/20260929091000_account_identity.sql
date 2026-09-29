-- Account identity: one commercial account per registrable domain unless the
-- companies are genuinely separate businesses.
--
-- registrable_domain() reduces a URL or host to its eTLD+1
-- ("privatebank.jpmorgan.com" -> "jpmorgan.com", "x.co.uk" stays "x.co.uk").
-- Shared hosting and social platforms return the full host instead, because two
-- tenants of wixsite.com or two Instagram accounts are never the same company.
--
-- company_account_duplicates lists companies that share a registrable domain.
-- It is read-only: nothing is merged automatically. A real subsidiary or separate
-- brand is recorded with companies.notes containing 'SEPARATE_ACCOUNT'; a merged
-- duplicate keeps its row with 'MERGED_INTO:<id>'. Both drop out of the list.

create or replace function public.registrable_domain(p text)
returns text
language sql
immutable
as $$
  with u as (
    select lower(regexp_replace(regexp_replace(coalesce(p, ''), '^[a-z]+://', '', 'i'), '^www\d?\.', '')) as url
  ), h as (
    select regexp_replace(url, '[/?#:].*$', '') as host,
           coalesce(substring(regexp_replace(url, '^[^/]*/?', '') from '^[^/?#]+(?:/[^/?#]+)?'), '') as seg1
    from u
  ), parts as (
    select host, seg1, string_to_array(host, '.') as a from h
  )
  select case
    when host = '' or host !~ '\.' then nullif(host, '')
    -- shared hosting / social / link platforms: the tenant is the identity
    when host ~ '(^|\.)(wixsite\.com|squarespace\.com|myshopify\.com|blogspot\.com|github\.io|wordpress\.com|webflow\.io|carrd\.co|linktr\.ee|instagram\.com|linkedin\.com|facebook\.com|tiktok\.com|x\.com|twitter\.com|google\.com|sites\.google\.com|notion\.site|beacons\.ai)$'
      then host || case when seg1 <> '' and host ~ '(instagram|linkedin|facebook|tiktok|x|twitter|linktr)\.' then '/' || seg1 else '' end
    -- two-part public suffixes (co.uk, com.eg, com.sa, com.au ...)
    when array_length(a, 1) >= 3 and a[array_length(a, 1) - 1] in ('co','com','org','net','gov','ac','edu','ltd','plc','me')
         and length(a[array_length(a, 1)]) = 2
      then a[array_length(a, 1) - 2] || '.' || a[array_length(a, 1) - 1] || '.' || a[array_length(a, 1)]
    else a[array_length(a, 1) - 1] || '.' || a[array_length(a, 1)]
  end
  from parts;
$$;

create or replace view public.company_account_duplicates
with (security_invoker = true) as
select registrable_domain(c.website) as account_domain,
       count(*) as companies,
       array_agg(c.id order by c.created_at) as company_ids,
       array_agg(c.name order by c.created_at) as names
from public.companies c
where registrable_domain(c.website) is not null
  and coalesce(c.notes, '') not like '%SEPARATE_ACCOUNT%'
  and coalesce(c.notes, '') not like '%MERGED_INTO:%'
group by 1
having count(*) > 1;

revoke all on public.company_account_duplicates from anon, authenticated;

-- One-off consolidation (applied 29 Sep): J.P. Morgan Private Bank (privatebank.jpmorgan.com,
-- discovered 28 Sep) is the same commercial account as J.P. Morgan (jpmorgan.com).
-- Nothing deleted: the contact moves to the main account as a secondary contact, the
-- duplicate opportunity is parked LONG_TERM, and its WAITING task is closed.
update public.contacts set company_id = '8472657f-f1fa-48de-816a-5edaf7903fe4'
where id = '4429450d-3e55-4753-9231-a5ddfa779654' and company_id = '78512b83-4ee9-42e8-8c34-171b7d5aab48';
update public.opportunities set company_id = '8472657f-f1fa-48de-816a-5edaf7903fe4', status = 'LONG_TERM'
where id = '070608c4-1d53-4761-8bde-a6e135366d0d' and company_id = '78512b83-4ee9-42e8-8c34-171b7d5aab48';
update public.companies set notes = coalesce(notes || E'\n', '') || 'MERGED_INTO:8472657f-f1fa-48de-816a-5edaf7903fe4'
where id = '78512b83-4ee9-42e8-8c34-171b7d5aab48' and coalesce(notes, '') not like '%MERGED_INTO:%';
update public.tasks set status = 'CANCELLED', completed_at = now()
where id = '4d37bdfd-b4cc-4e07-b23c-1d91b3b6b410' and status = 'WAITING';
