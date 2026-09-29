-- HQ V2: previous NOYA relationships (from the Gmail history import), add-to-CRM / dismiss,
-- email evidence in record timelines, LinkedIn connection → contact matching, company country edits,
-- and a quick "add contact". All admin-gated and audited; nothing sends.

-- Relationships grouped by who they are with: CRM company / contact first, otherwise the business
-- domain, otherwise the address. Only threads Adam actually wrote in (Gmail SENT) are included.
create or replace function public.hq_relationships()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  with t as (
    select t.*, coalesce('co:' || t.company_id::text, 'ct:' || t.contact_id::text,
             case when cardinality(t.counterpart_domains) > 0 and not email_is_freemail(t.counterpart_domains[1]) then 'd:' || registrable_domain(t.counterpart_domains[1]) end,
             'e:' || t.counterpart_emails[1]) as gkey
      from gmail_history_threads t where t.relevant and t.outbound > 0
  ), g as (
    select gkey, count(*) threads, sum(outbound) sent, sum(inbound) received, min(first_at) first_at, max(last_at) last_at,
           max(last_outbound_at) last_out, max(last_inbound_at) last_in,
           (array_agg(gmail_thread_id order by last_at desc))[1] last_thread,
           (array_agg(gmail_thread_id order by last_inbound_at desc nulls last))[1] last_reply_thread,
           (array_agg(left(subject, 90) order by last_at desc))[1] last_subject,
           (array_agg(company_id::text) filter (where company_id is not null))[1]::uuid company_id,
           (array_agg(contact_id::text) filter (where contact_id is not null))[1]::uuid contact_id,
           (array_agg(opportunity_id::text order by last_at desc) filter (where opportunity_id is not null))[1]::uuid opportunity_id,
           bool_or(relationship_state = 'MEETING') meeting, bool_or(relationship_state = 'DO_NOT_CONTACT') dnc,
           bool_or(hq_status = 'DISMISSED') dismissed, bool_or(hq_status = 'ADDED_TO_CRM') added
      from t group by gkey
  )
  select jsonb_build_object('generated_at', now(),
    'state', (select jsonb_build_object('mode', mode, 'scanned', scanned, 'window_start', window_start, 'backfill_done_at', backfill_done_at,
                'last_run_at', last_run_at, 'last_error', last_error) from gmail_backfill_state limit 1),
    'groups', coalesce((select jsonb_agg(jsonb_build_object(
        'key', g.gkey, 'threads', g.threads, 'sent', g.sent, 'received', g.received, 'first_at', g.first_at, 'last_at', g.last_at,
        'last_out', g.last_out, 'last_in', g.last_in, 'last_thread', g.last_thread, 'reply_thread', case when g.received > 0 then g.last_reply_thread end,
        'subject', g.last_subject, 'company_id', g.company_id, 'contact_id', g.contact_id, 'opportunity_id', g.opportunity_id,
        'in_crm', g.company_id is not null or g.contact_id is not null, 'dismissed', g.dismissed, 'added', g.added,
        'state', case when g.dnc then 'DO_NOT_CONTACT' when g.meeting then 'MEETING'
                      else gmail_relationship_state(g.sent::int, g.received::int, case when g.last_in > coalesce(g.last_out, '-infinity') then 'INBOUND' else 'OUTBOUND' end,
                                                    g.last_out, g.last_in, g.last_at) end,
        'name', coalesce(c.name, nullif(btrim(concat_ws(' ', k.first_name, k.last_name)), ''),
                  (select m.from_name from gmail_history_messages m where m.gmail_thread_id = g.last_reply_thread and m.direction = 'INBOUND' and m.from_name is not null limit 1),
                  substr(g.gkey, 3)),
        'domain', case when g.gkey like 'd:%' then substr(g.gkey, 3) else (select registrable_domain(d) from gmail_history_threads x, unnest(x.counterpart_domains) d where x.gmail_thread_id = g.last_thread limit 1) end,
        'emails', (select jsonb_agg(distinct e) from t x, unnest(x.counterpart_emails) e where x.gkey = g.gkey),
        'from_name', (select m.from_name from gmail_history_messages m where m.gmail_thread_id = g.last_reply_thread and m.direction = 'INBOUND' and m.from_name is not null limit 1),
        'reply_from', (select m.from_email from gmail_history_messages m where m.gmail_thread_id = g.last_reply_thread and m.direction = 'INBOUND' and m.from_email is not null order by m.sent_at desc limit 1),
        'snippet', case when g.received > 0 then (select m.snippet from gmail_history_messages m where m.gmail_thread_id = g.last_reply_thread and m.direction = 'INBOUND' order by m.sent_at desc limit 1) end,
        'summary', (select x.summary from gmail_history_threads x where x.gmail_thread_id = g.last_thread),
        'company', c.name, 'vertical', coalesce(c.vertical_override, hq_vertical(c.company_type, null, c.sector)), 'market', hq_market(c.country),
        'opportunity_status', (select o.status from opportunities o where o.id = g.opportunity_id))
      order by (g.received > 0) desc, g.last_at desc) from g
      left join companies c on c.id = g.company_id left join contacts k on k.id = g.contact_id), '[]'::jsonb),
    'by_company', coalesce((select jsonb_object_agg(company_id, jsonb_build_object('threads', n, 'sent', s, 'received', r, 'last_at', l, 'thread', th))
        from (select company_id, count(*) n, sum(outbound) s, sum(inbound) r, max(last_at) l, (array_agg(gmail_thread_id order by last_at desc))[1] th
                from gmail_history_threads where relevant and company_id is not null group by company_id) x), '{}'::jsonb),
    'by_contact', coalesce((select jsonb_object_agg(contact_id, jsonb_build_object('threads', n, 'sent', s, 'received', r, 'last_at', l, 'thread', th))
        from (select contact_id, count(*) n, sum(outbound) s, sum(inbound) r, max(last_at) l, (array_agg(gmail_thread_id order by last_at desc))[1] th
                from gmail_history_threads where relevant and contact_id is not null group by contact_id) x), '{}'::jsonb),
    'prior', coalesce((select jsonb_object_agg(id, jsonb_build_object('state', prior_relationship, 'at', prior_relationship_at, 'thread', prior_thread_id))
        from opportunities where prior_relationship is not null), '{}'::jsonb)
  ) into v;
  return v;
end $$;

-- Adam's decision on a previous relationship group: dismiss it, or add it to the CRM (company by
-- domain, reusing an existing account; contact by email, reusing an existing person). The Gmail
-- history relinks itself through the company/contact triggers.
create or replace function public.hq_history_action(p_key text, p_action text, p_company_name text default null, p_first text default null,
  p_last text default null, p_role text default null, p_email text default null, p_country text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_threads text[]; v_domain text; v_co uuid; v_ct uuid; v_email text := lower(nullif(btrim(p_email), ''));
begin
  select array_agg(gmail_thread_id) into v_threads from gmail_history_threads t
   where t.relevant and t.outbound > 0 and p_key = coalesce('co:' || t.company_id::text, 'ct:' || t.contact_id::text,
             case when cardinality(t.counterpart_domains) > 0 and not email_is_freemail(t.counterpart_domains[1]) then 'd:' || registrable_domain(t.counterpart_domains[1]) end,
             'e:' || t.counterpart_emails[1]);
  if v_threads is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if upper(p_action) = 'DISMISS' then
    update gmail_history_threads set hq_status = 'DISMISSED', updated_at = now() where gmail_thread_id = any(v_threads);
    perform hq_audit('HISTORY_DISMISSED', null, jsonb_build_object('key', p_key, 'threads', cardinality(v_threads)));
    return jsonb_build_object('ok', true);
  elsif upper(p_action) = 'RESTORE' then
    update gmail_history_threads set hq_status = null, updated_at = now() where gmail_thread_id = any(v_threads) and hq_status = 'DISMISSED';
    return jsonb_build_object('ok', true);
  elsif upper(p_action) <> 'ADD_TO_CRM' then
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_ACTION');
  end if;
  if v_email is not null and v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('ok', false, 'reason', 'INVALID_EMAIL'); end if;
  v_domain := case when p_key like 'd:%' then substr(p_key, 3) when v_email is not null and not email_is_freemail(split_part(v_email, '@', 2)) then registrable_domain(split_part(v_email, '@', 2)) end;
  if hq_trim(p_company_name) is not null or v_domain is not null then
    select c.id into v_co from companies c where coalesce(c.notes, '') not like '%MERGED_INTO:%' and (
        (v_domain is not null and c.website is not null and registrable_domain(c.website) = v_domain)
        or (hq_trim(p_company_name) is not null and lower(regexp_replace(c.name, '[^a-z0-9]', '', 'gi')) = lower(regexp_replace(p_company_name, '[^a-z0-9]', '', 'gi')))) limit 1;
    if v_co is null then
      if hq_trim(p_company_name) is null then return jsonb_build_object('ok', false, 'reason', 'COMPANY_REQUIRED'); end if;
      insert into companies (name, website, country, source, relationship_status, notes)
      values (hq_trim(p_company_name), v_domain, hq_trim(p_country), 'Gmail history (HQ)', 'prospect', 'Added from NOYA Gmail history by ' || v_admin)
      returning id into v_co;
    end if;
  end if;
  if v_email is not null then
    select id into v_ct from contacts where lower(email) = v_email limit 1;
    if v_ct is null then
      -- A real correspondent: their address is evidenced by the mailbox, not verified by a provider.
      insert into contacts (company_id, first_name, last_name, position, email, email_status, source, status, do_not_contact, notes)
      values (v_co, hq_trim(p_first), hq_trim(p_last), hq_trim(p_role), v_email, 'UNVERIFIED', 'Gmail history (HQ)', 'NEW', false,
              'Corresponded with NOYA by email (Gmail history). Address evidenced by the mailbox, not provider-verified.')
      returning id into v_ct;
    end if;
  end if;
  if v_co is null and v_ct is null then return jsonb_build_object('ok', false, 'reason', 'RECORD_REQUIRED'); end if;
  -- Make sure these specific threads are linked even when the domain/email rules would not reach them.
  update gmail_history_messages m set company_id = coalesce(m.company_id, v_co), contact_id = coalesce(m.contact_id, v_ct), match_method = coalesce(m.match_method, 'HQ_ADDED'), updated_at = now()
   where m.gmail_thread_id = any(v_threads) and m.category = 'COMMERCIAL';
  perform gmail_history_rebuild(v_threads);
  update gmail_history_threads set hq_status = 'ADDED_TO_CRM' where gmail_thread_id = any(v_threads);
  perform hq_audit('HISTORY_ADDED_TO_CRM', null, jsonb_build_object('key', p_key, 'company_id', v_co, 'contact_id', v_ct, 'threads', cardinality(v_threads)));
  return jsonb_build_object('ok', true, 'company_id', v_co, 'contact_id', v_ct);
end $$;

-- Quick "add contact" (reuses the person by email and the company by name/domain).
create or replace function public.hq_add_contact(p_company_id uuid, p_company_name text, p_first text, p_last text, p_role text,
  p_email text default null, p_linkedin text default null, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_co uuid := p_company_id; v_ct uuid; v_email text := lower(nullif(btrim(p_email), '')); v_reused boolean := false;
begin
  if hq_trim(p_first) is null and hq_trim(p_last) is null then return jsonb_build_object('ok', false, 'reason', 'NAME_REQUIRED'); end if;
  if v_email is not null and v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('ok', false, 'reason', 'INVALID_EMAIL'); end if;
  if v_co is null and hq_trim(p_company_name) is not null then
    select c.id into v_co from companies c where coalesce(c.notes, '') not like '%MERGED_INTO:%'
       and lower(regexp_replace(c.name, '[^a-z0-9]', '', 'gi')) = lower(regexp_replace(p_company_name, '[^a-z0-9]', '', 'gi')) limit 1;
    if v_co is null then
      insert into companies (name, website, source, relationship_status)
      values (hq_trim(p_company_name), case when v_email is not null and not email_is_freemail(split_part(v_email, '@', 2)) then split_part(v_email, '@', 2) end, 'HQ (Adam)', 'prospect')
      returning id into v_co;
    end if;
  end if;
  if v_email is not null then select id into v_ct from contacts where lower(email) = v_email limit 1; end if;
  if v_ct is null then
    select id into v_ct from contacts where company_id is not distinct from v_co and lower(coalesce(first_name, '')) = lower(coalesce(hq_trim(p_first), ''))
       and lower(coalesce(last_name, '')) = lower(coalesce(hq_trim(p_last), '')) limit 1;
  end if;
  if v_ct is not null then v_reused := true;
  else
    insert into contacts (company_id, first_name, last_name, position, email, email_status, linkedin, source, status, do_not_contact, notes)
    values (v_co, hq_trim(p_first), hq_trim(p_last), hq_trim(p_role), v_email, case when v_email is null then 'NOT_FOUND' else 'UNVERIFIED' end,
            hq_trim(p_linkedin), 'HQ (Adam)', 'NEW', false, hq_trim(p_note))
    returning id into v_ct;
  end if;
  perform hq_audit('CONTACT_ADDED', null, jsonb_build_object('contact_id', v_ct, 'company_id', v_co, 'reused', v_reused));
  return jsonb_build_object('ok', true, 'contact_id', v_ct, 'company_id', v_co, 'reused', v_reused);
end $$;

-- Company edit gains country and website (evidence-based data cleanup by Adam).
drop function if exists public.hq_company_update(uuid, text, text);
create or replace function public.hq_company_update(p_company uuid, p_vertical text default null, p_relationship text default null,
  p_country text default null, p_website text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_old companies%rowtype;
begin
  select * into v_old from companies where id = p_company;
  if v_old.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  update companies set vertical_override = case when p_vertical = 'AUTO' then null else coalesce(p_vertical, vertical_override) end,
         relationship_status = coalesce(p_relationship, relationship_status),
         country = coalesce(hq_trim(p_country), country), website = coalesce(hq_trim(p_website), website), updated_at = now()
   where id = p_company;
  perform hq_audit('COMPANY_UPDATE', null, jsonb_build_object('company_id', p_company, 'vertical', p_vertical, 'relationship', p_relationship,
    'country', jsonb_build_object('from', v_old.country, 'to', p_country), 'website', jsonb_build_object('from', v_old.website, 'to', p_website)));
  return jsonb_build_object('ok', true);
exception when check_violation then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;

-- LinkedIn connections also match existing CRM people (same name at the matched company).
alter table public.linkedin_connections add column if not exists matched_contact_id uuid references public.contacts(id) on delete set null;
create or replace function public.linkedin_match_contacts()
returns int language sql volatile security definer set search_path = public as $$
  with m as (
    select l.id, (select k.id from contacts k where lower(btrim(k.first_name)) = lower(btrim(l.first_name)) and lower(btrim(coalesce(k.last_name, ''))) = lower(btrim(coalesce(l.last_name, '')))
                    and (l.matched_company_id is null or k.company_id = l.matched_company_id) order by (k.company_id = l.matched_company_id) desc nulls last limit 1) cid
      from linkedin_connections l where l.matched_contact_id is null and l.first_name is not null
  )
  ), u as (
    update linkedin_connections l set matched_contact_id = m.cid, updated_at = now() from m where l.id = m.id and m.cid is not null
    returning 1)
  select count(*)::int from u
$$;
revoke all on function public.linkedin_match_contacts() from public, anon, authenticated;

do $$
declare d text;
begin
  -- import: match people too
  d := pg_get_functiondef('public.hq_import_connections(jsonb)'::regprocedure);
  d := replace(d, $x$  perform hq_audit('LINKEDIN_IMPORT', null,$x$, $x$  perform linkedin_match_contacts();
  perform hq_audit('LINKEDIN_IMPORT', null,$x$);
  if d not like '%linkedin_match_contacts()%' then raise exception 'import patch failed'; end if;
  execute d;

  -- directory: expose the matched person and the connection's email-history evidence
  d := pg_get_functiondef('public.hq_directory()'::regprocedure);
  d := replace(d, $x$'matched_company_id', l.matched_company_id, 'matched_company', mc.name,$x$,
                  $x$'matched_company_id', l.matched_company_id, 'matched_company', mc.name, 'matched_contact_id', l.matched_contact_id,
        'email_history', (select count(*) from gmail_history_threads t where t.relevant and (t.company_id = l.matched_company_id or t.contact_id = l.matched_contact_id)),$x$);
  if d not like '%matched_contact_id%' then raise exception 'directory patch failed'; end if;
  execute d;

  -- timeline: show the email snippet and a Gmail link for imported history
  d := pg_get_functiondef('public.hq_timeline(text,uuid)'::regprocedure);
  d := replace(d, $x$           i.direction, coalesce(i.subject, '') as title, coalesce(i.summary, '') as detail, 'interaction' as src$x$,
                  $x$           i.direction, coalesce(i.subject, '') as title,
           coalesce((select nullif(g.snippet, '') from gmail_history_messages g where g.gmail_message_id = i.external_message_id), i.summary, '') as detail,
           case when i.external_message_id is not null then 'gmail' else 'interaction' end as src,
           (select g.gmail_thread_id from gmail_history_messages g where g.gmail_message_id = i.external_message_id) as ref$x$);
  d := replace(d, $x$coalesce(l.detail->>'summary', ''), 'reply'$x$, $x$coalesce(l.detail->>'summary', ''), 'reply', l.gmail_thread_id$x$);
  d := replace(d, $x$n.body, 'note'$x$, $x$n.body, 'note', null::text$x$);
  d := replace(d, $x$t.status || ' — ' || t.title, '', 'task'$x$, $x$t.status || ' — ' || t.title, '', 'task', null::text$x$);
  d := replace(d, $x$coalesce(left(w.message, 300), ''), 'website'$x$, $x$coalesce(left(w.message, 300), ''), 'website', null::text$x$);
  d := replace(d, $x$coalesce(v.provider_status, ''), 'verification'$x$, $x$coalesce(v.provider_status, ''), 'verification', null::text$x$);
  if d not like '%as ref%' or d not like '%''verification'', null::text%' then raise exception 'timeline patch failed'; end if;
  execute d;
end $$;

do $$
declare f text;
begin
  foreach f in array array['public.hq_relationships()', 'public.hq_history_action(text, text, text, text, text, text, text, text)',
    'public.hq_add_contact(uuid, text, text, text, text, text, text, text)', 'public.hq_company_update(uuid, text, text, text, text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
