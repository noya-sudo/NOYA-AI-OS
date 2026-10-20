-- LinkedIn data archive (Adam, 20 Oct 2026, decision A). Adam downloads his own LinkedIn archive (Connections and Messages) and
-- uploads it in HQ → LinkedIn. It is read-only historical relationship context: Supabase stays the source of truth, no CRM person
-- or company is created from it, nothing is sent, and an old conversation is never read as a current opportunity without its date.
-- No new CRM: people stay in linkedin_connections (the warm-network table HQ already has), messages are kept as an archive linked to
-- them, and the results flow into what exists: CRM matching, the warm route, the LinkedIn Relationship Agent and the Top 5.
--
-- Upload flow (HQ, each call its own request, every one well under the 8-second request limit at 60,000 messages):
--   hq_linkedin_archive('start', {self_hint}) → hq_import_connections (500 rows a call) → hq_import_linkedin_messages (400 a call)
--   → hq_linkedin_archive('self' | 'people' | 'history' | 'match') → hq_linkedin_archive('states', {import counts}) returns the report.

-- ---------------------------------------------------------------- 1. people: history summary and the LinkedIn relationship state
alter table public.linkedin_connections
  add column if not exists connected boolean not null default true,      -- false: known only from messages (not a 1st-degree connection)
  add column if not exists li_state text,
  add column if not exists li_state_reason text,
  add column if not exists li_conversations int not null default 0,
  add column if not exists li_messages int not null default 0,
  add column if not exists li_out int not null default 0,
  add column if not exists li_in int not null default 0,
  add column if not exists li_in_chars int not null default 0,
  add column if not exists li_first_at timestamptz,
  add column if not exists li_last_at timestamptz,
  add column if not exists li_last_in_at timestamptz,
  add column if not exists li_last_dir text,
  add column if not exists li_intro jsonb,
  add column if not exists li_opt_out_at timestamptz,
  add column if not exists match_method text,
  add column if not exists review_reason text;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'linkedin_connections_li_state_check') then
    alter table public.linkedin_connections add constraint linkedin_connections_li_state_check
      check (li_state is null or li_state in ('CONNECTED', 'MESSAGED_BEFORE', 'REPLIED_BEFORE', 'WARM', 'DORMANT', 'ACTIVE', 'DO_NOT_CONTACT'));
  end if;
end $c$;
create index if not exists linkedin_connections_contact_idx on public.linkedin_connections (matched_contact_id);
create index if not exists linkedin_connections_company_idx on public.linkedin_connections (matched_company_id);
comment on column public.linkedin_connections.li_state is 'LinkedIn relationship state from the archive: CONNECTED, MESSAGED_BEFORE, REPLIED_BEFORE, WARM, DORMANT, ACTIVE, DO_NOT_CONTACT.';
comment on column public.linkedin_connections.connected is 'True when the person is in Adam''s Connections export. False for people seen only in messages.';

-- ---------------------------------------------------------------- 2. the message archive (read-only history, original dates kept)
create table if not exists public.linkedin_messages (
  id uuid primary key default gen_random_uuid(),
  msg_key text not null unique,                 -- conversation, time, sender and text: re-importing never duplicates
  conversation_id text not null,
  conversation_title text,
  sent_at timestamptz not null,                 -- LinkedIn's own timestamp, never the import time
  sender_name text, sender_url text,
  recipient_names text, recipient_urls text[] not null default '{}',
  subject text, content text, folder text,
  direction text check (direction is null or direction in ('OUTBOUND', 'INBOUND')),
  imported_at timestamptz not null default now());
create index if not exists linkedin_messages_conv_idx on public.linkedin_messages (conversation_id, sent_at);
create index if not exists linkedin_messages_sender_idx on public.linkedin_messages (sender_url);
alter table public.linkedin_messages enable row level security;
revoke all on public.linkedin_messages from anon, authenticated;
comment on table public.linkedin_messages is 'Read-only archive of Adam''s own LinkedIn messages (from his LinkedIn data download). Original dates kept. Never a live lead without a recency check.';

-- Who took part in each conversation (Adam excluded), resolved to a person in linkedin_connections.
create table if not exists public.linkedin_conversation_people (
  conversation_id text not null,
  profile_url text not null,
  connection_id uuid references public.linkedin_connections(id) on delete cascade,
  resolved_by text,                              -- URL, or NAME when the archive used a different link for the same person
  primary key (conversation_id, profile_url));
alter table public.linkedin_conversation_people add column if not exists name text;
create index if not exists linkedin_conversation_people_conn_idx on public.linkedin_conversation_people (connection_id);
alter table public.linkedin_conversation_people enable row level security;
revoke all on public.linkedin_conversation_people from anon, authenticated;
comment on table public.linkedin_conversation_people is 'Who took part in each archived LinkedIn conversation (Adam excluded), resolved to linkedin_connections by profile link or a unique full name.';

-- ---------------------------------------------------------------- 3. import (the browser parses the files; rows arrive in batches)
-- One parsed row per message. The key hashes conversation, time, sender and text (chr(31) separated), so a re-upload adds nothing.
create or replace function public.linkedin_archive_rows(p_rows jsonb)
returns table (msg_key text, cid text, title text, at timestamptz, sname text, surl text, rnames text, rurls text[], subj text, body text, folder text)
language sql immutable set search_path = public as $$
  select md5(concat_ws(chr(31), x.cid, x.at::text, coalesce(x.surl, x.sname), x.body)), x.*
    from (select nullif(btrim(r->>'conversation_id'), '') cid, hq_trim(r->>'title') title, (r->>'sent_at')::timestamptz at, hq_trim(r->>'from') sname,
                 linkedin_canonical_url(r->>'sender_url') surl, hq_trim(r->>'to') rnames,
                 coalesce((select array_agg(distinct u) from (select linkedin_canonical_url(v) u from jsonb_array_elements_text(coalesce(r->'recipient_urls', '[]'::jsonb)) v) y where u is not null), '{}') rurls,
                 hq_trim(r->>'subject') subj, left(hq_trim(r->>'content'), 4000) body, upper(hq_trim(r->>'folder')) folder
            from jsonb_array_elements(p_rows) r
           where coalesce(r->>'sent_at', '') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}') x
   where x.cid is not null and coalesce(x.folder, '') <> 'SPAM' and coalesce(x.surl, x.sname) is not null
$$;
revoke all on function public.linkedin_archive_rows(jsonb) from public, anon, authenticated;

create or replace function public.hq_import_linkedin_messages(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_rows int; v_ok int; v_new int;
        v_hint text := (select linkedin_canonical_url(value->>'self_hint') from system_config where key = 'linkedin_archive');
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 1000 then return jsonb_build_object('ok', false, 'reason', 'INVALID_ROWS'); end if;
  v_rows := jsonb_array_length(p_rows);
  select count(*) into v_ok from linkedin_archive_rows(p_rows);
  -- Direction from the browser's reading of whose profile is in every conversation. The rebuild checks it and corrects any row.
  insert into linkedin_messages (msg_key, conversation_id, conversation_title, sent_at, sender_name, sender_url, recipient_names, recipient_urls, subject, content, folder, direction)
  select x.msg_key, x.cid, x.title, x.at, x.sname, x.surl, x.rnames, x.rurls, x.subj, x.body, x.folder,
         case when v_hint is null then null when x.surl = v_hint then 'OUTBOUND' else 'INBOUND' end
    from linkedin_archive_rows(p_rows) x
  on conflict (msg_key) do nothing;
  get diagnostics v_new = row_count;
  return jsonb_build_object('ok', true, 'received', v_rows, 'new', v_new, 'already_imported', v_ok - v_new, 'skipped', v_rows - v_ok);
end $$;
revoke all on function public.hq_import_linkedin_messages(jsonb) from public, anon;
grant execute on function public.hq_import_linkedin_messages(jsonb) to authenticated;

-- Connections.csv (existing import): a person first seen in messages becomes a connection when the export lists them.
do $patch$
declare src text := pg_get_functiondef('public.hq_import_connections(jsonb)'::regprocedure);
  a text := $a$vertical = excluded.vertical, updated_at = now()$a$;
  b text := $a$vertical = excluded.vertical, connected = true, updated_at = now()$a$;
begin
  if strpos(src, b) > 0 then return; end if;
  if strpos(src, a) = 0 then raise exception 'hq_import_connections() changed: anchor not found'; end if;
  execute replace(src, a, b);
end $patch$;

-- ---------------------------------------------------------------- 4. matching people to CRM contacts, strictest evidence first
-- 1 the same LinkedIn profile link on one CRM contact; 2 the export's email on one CRM contact (linkedin_match_all); 3 the same full
-- name at the same CRM company. A name alone never links: it goes to review. Several CRM contacts with one link: review, never guessed.
create or replace function public.linkedin_match_contacts()
returns integer language plpgsql security definer set search_path = public as $$
declare n int := 0; m int;
begin
  with ck as materialized (select linkedin_canonical_url(k.linkedin) u, k.id from contacts k where coalesce(k.linkedin, '') <> ''),
       one as (select u, min(id::text)::uuid id, count(*) n from ck where u is not null group by u)
  update linkedin_connections l set matched_contact_id = one.id, match_method = 'URL', review_reason = null, updated_at = now()
    from one where one.u = l.profile_url and one.n = 1 and l.matched_contact_id is null;
  get diagnostics m = row_count; n := n + m;
  with ck as materialized (select linkedin_canonical_url(k.linkedin) u from contacts k where coalesce(k.linkedin, '') <> ''),
       many as (select u from ck where u is not null group by u having count(*) > 1)
  update linkedin_connections l set review_reason = 'Several CRM contacts carry this LinkedIn profile: merge the duplicates first', updated_at = now()
    from many where many.u = l.profile_url and l.matched_contact_id is null and l.review_reason is null;
  update linkedin_connections l set match_method = 'EMAIL'
   where l.matched_contact_id is not null and l.match_method is null and l.email is not null
     and exists (select 1 from contacts k where k.id = l.matched_contact_id and lower(k.email) = l.email);
  with c as (select l.id, min(k.id::text)::uuid kid, count(*) n
               from linkedin_connections l
               join contacts k on lower(btrim(k.first_name)) = lower(btrim(l.first_name)) and lower(btrim(coalesce(k.last_name, ''))) = lower(btrim(l.last_name))
                              and k.company_id = l.matched_company_id
              where l.matched_contact_id is null and l.first_name is not null and l.last_name is not null and l.matched_company_id is not null
              group by l.id)
  update linkedin_connections l set matched_contact_id = c.kid, match_method = 'NAME_COMPANY', review_reason = null, updated_at = now()
    from c where c.id = l.id and c.n = 1;
  get diagnostics m = row_count; n := n + m;
  with x as (select l.id, string_agg(distinct coalesce(co.name, 'no company'), ', ') cos
               from linkedin_connections l
               join contacts k on lower(btrim(k.first_name)) = lower(btrim(l.first_name)) and lower(btrim(coalesce(k.last_name, ''))) = lower(btrim(l.last_name))
               left join companies co on co.id = k.company_id
              where l.matched_contact_id is null and l.first_name is not null and l.last_name is not null
              group by l.id)
  update linkedin_connections l set review_reason = 'Same name as a CRM contact (' || left(x.cos, 120) || '): confirm before linking', updated_at = now()
    from x where x.id = l.id and l.review_reason is null;
  update linkedin_connections l set matched_company_id = k.company_id, updated_at = now()
    from contacts k where k.id = l.matched_contact_id and l.matched_company_id is null and k.company_id is not null;
  update linkedin_connections l set review_reason = null where l.matched_contact_id is not null and l.review_reason is not null;
  return n;
end $$;
revoke all on function public.linkedin_match_contacts() from public, anon, authenticated;

-- ---------------------------------------------------------------- 5. rebuild pieces: Adam, participants, history, introductions, opt-outs
-- Adam is the profile present in (nearly) every conversation of his own archive (at least 60%). Unknown: null, and the history waits.
create or replace function public.linkedin_archive_self()
returns text language plpgsql security definer set search_path = public as $$
declare v_self text; v_n int; v_convs int; v_name text;
begin
  select count(distinct conversation_id) into v_convs from linkedin_messages;
  select u, n into v_self, v_n from (
    select u, count(distinct conversation_id) n from (
      select conversation_id, sender_url u from linkedin_messages where sender_url is not null
      union all select conversation_id, unnest(recipient_urls) from linkedin_messages) x
     group by u order by 2 desc limit 1) y;
  if v_self is null or v_n < v_convs * 0.6 then return null; end if;
  select sender_name into v_name from linkedin_messages where sender_url = v_self and sender_name is not null group by sender_name order by count(*) desc limit 1;
  update linkedin_messages set direction = case when sender_url = v_self or (sender_url is null and sender_name = v_name) then 'OUTBOUND' else 'INBOUND' end
   where direction is distinct from (case when sender_url = v_self or (sender_url is null and sender_name = v_name) then 'OUTBOUND' else 'INBOUND' end);
  return v_self;
end $$;
revoke all on function public.linkedin_archive_self() from public, anon, authenticated;

-- Everyone else in each conversation, with their latest name, resolved to a person: the same link, else one connection with exactly
-- that full name (the archive can use another link form). Someone seen only in messages is kept as connected = false, never in the CRM.
create or replace function public.linkedin_archive_participants(p_self text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_new int := 0; v_by_name int := 0;
begin
  insert into linkedin_conversation_people (conversation_id, profile_url)
  select distinct conversation_id, u from (
    select conversation_id, sender_url u from linkedin_messages
    union all select conversation_id, unnest(recipient_urls) from linkedin_messages) x
   where u is not null and u is distinct from p_self
  on conflict (conversation_id, profile_url) do nothing;
  with nm as materialized (select distinct on (sender_url) sender_url u, sender_name n from linkedin_messages
               where sender_url is not null and sender_name is not null order by sender_url, sent_at desc)
  update linkedin_conversation_people p set name = nm.n from nm where nm.u = p.profile_url and p.name is distinct from nm.n;
  with one as materialized (select distinct on (m.recipient_urls[1]) m.recipient_urls[1] u, m.recipient_names n from linkedin_messages m
                where array_length(m.recipient_urls, 1) = 1 and m.recipient_names is not null and m.recipient_names !~ ','
                order by m.recipient_urls[1], m.sent_at desc)
  update linkedin_conversation_people p set name = one.n from one where p.name is null and one.u = p.profile_url;
  update linkedin_conversation_people p set connection_id = l.id, resolved_by = 'URL'
    from linkedin_connections l where l.profile_url = p.profile_url and p.connection_id is distinct from l.id;
  with nk as materialized (select lower(btrim(concat_ws(' ', first_name, last_name))) k, min(id::text)::uuid id, count(*) n from linkedin_connections where connected group by 1)
  update linkedin_conversation_people p set connection_id = nk.id, resolved_by = 'NAME'
    from nk where p.connection_id is null and p.name is not null and nk.k = lower(btrim(p.name)) and nk.n = 1;
  select count(distinct profile_url) into v_by_name from linkedin_conversation_people where resolved_by = 'NAME';
  insert into linkedin_connections (first_name, last_name, profile_url, connected, source)
  select distinct on (p.profile_url) split_part(btrim(p.name), ' ', 1), nullif(btrim(substr(btrim(p.name), length(split_part(btrim(p.name), ' ', 1)) + 1)), ''),
         p.profile_url, false, 'LINKEDIN_MESSAGES'
    from linkedin_conversation_people p where p.connection_id is null
  on conflict (profile_url) do nothing;
  get diagnostics v_new = row_count;
  update linkedin_conversation_people p set connection_id = l.id, resolved_by = 'URL'
    from linkedin_connections l where p.connection_id is null and l.profile_url = p.profile_url;
  return jsonb_build_object('people_from_messages', v_new, 'people_linked_by_name', v_by_name);
end $$;
revoke all on function public.linkedin_archive_participants(text) from public, anon, authenticated;

-- History per person: Adam's messages in their conversations and their own messages, with the original dates.
create or replace function public.linkedin_archive_history()
returns integer language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update linkedin_connections c set li_conversations = 0, li_messages = 0, li_out = 0, li_in = 0, li_in_chars = 0, li_first_at = null, li_last_at = null,
         li_last_in_at = null, li_last_dir = null
   where c.li_messages > 0;
  with pm as materialized (
    select p.connection_id cid, m.conversation_id, m.sent_at, (m.sender_url = p.profile_url) from_them, length(coalesce(m.content, '')) len
      from linkedin_conversation_people p join linkedin_messages m on m.conversation_id = p.conversation_id
     where p.connection_id is not null and (m.direction = 'OUTBOUND' or m.sender_url = p.profile_url)),
  a as materialized (select cid, count(distinct conversation_id) convs, count(*) msgs, count(*) filter (where not from_them) o, count(*) filter (where from_them) i,
               coalesce(sum(len) filter (where from_them), 0) ichars, min(sent_at) f, max(sent_at) l, max(sent_at) filter (where from_them) li,
               (array_agg(case when from_them then 'INBOUND' else 'OUTBOUND' end order by sent_at desc))[1] ld
          from pm group by cid)
  update linkedin_connections c set li_conversations = a.convs, li_messages = a.msgs, li_out = a.o, li_in = a.i, li_in_chars = a.ichars,
         li_first_at = a.f, li_last_at = a.l, li_last_in_at = a.li, li_last_dir = a.ld, updated_at = now()
    from a where a.cid = c.id;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.linkedin_archive_history() from public, anon, authenticated;

-- Introductions and referrals: someone else opened a group conversation, or a message introduces or refers.
-- Opt-outs: the person's most recent message asks not to be contacted.
create or replace function public.linkedin_archive_signals(p_self text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_intro text := '(introduc(e|ing) you|introduce (you|him|her|them) to|connect(ing)? you (two|both|with)|putting you (two |both )?in touch|copying in|cc.?ing in|looping in|you (two|both) should (meet|speak|talk|connect)|referr(ed|ing) you|recommended (you|me) to|suggested (i|that i) (reach out|contact|speak))';
        v_optout text := '(please (remove|stop)|not interested|stop (messaging|contacting|sending)|unsubscribe|do not (contact|message)|don.?t (contact|message) me|remove me)';
        n_i int; n_o int;
begin
  update linkedin_connections c set li_intro = null, li_opt_out_at = null where c.li_intro is not null or c.li_opt_out_at is not null;
  with conv as materialized (select conversation_id, count(distinct profile_url) np from linkedin_conversation_people group by 1),
  firstm as materialized (select distinct on (conversation_id) conversation_id, sender_url, sender_name, sent_at, conversation_title from linkedin_messages order by conversation_id, sent_at),
  hit as materialized (select distinct on (m.conversation_id) m.conversation_id, m.sender_name, m.sent_at, m.conversation_title from linkedin_messages m
           where coalesce(m.content, '') ~* v_intro order by m.conversation_id, m.sent_at),
  intro as materialized (select f.conversation_id, coalesce(h.sender_name, f.sender_name) by_name, coalesce(h.sent_at, f.sent_at) at, coalesce(h.conversation_title, f.conversation_title) title
              from conv c join firstm f on f.conversation_id = c.conversation_id left join hit h on h.conversation_id = c.conversation_id
             where h.conversation_id is not null or (c.np >= 2 and f.sender_url is distinct from p_self)),
  per as materialized (select p.connection_id cid, jsonb_agg(jsonb_build_object('at', i.at, 'by', i.by_name, 'title', i.title, 'conversation_id', i.conversation_id) order by i.at desc) j
            from intro i join linkedin_conversation_people p on p.conversation_id = i.conversation_id where p.connection_id is not null group by p.connection_id)
  update linkedin_connections c set li_intro = per.j from per where per.cid = c.id;
  get diagnostics n_i = row_count;
  with lastin as materialized (select distinct on (p.connection_id) p.connection_id cid, m.sent_at, m.content
                    from linkedin_conversation_people p join linkedin_messages m on m.conversation_id = p.conversation_id and m.sender_url = p.profile_url
                   where p.connection_id is not null order by p.connection_id, m.sent_at desc)
  update linkedin_connections c set li_opt_out_at = lastin.sent_at from lastin where lastin.cid = c.id and coalesce(lastin.content, '') ~* v_optout;
  get diagnostics n_o = row_count;
  return jsonb_build_object('introductions', n_i, 'opt_outs', n_o);
end $$;
revoke all on function public.linkedin_archive_signals(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- 6. the relationship state, with its reason and dates
-- DO_NOT_CONTACT (they asked, or the CRM says so) > ACTIVE (two-way, last 30 days) > WARM (real two-way exchange, last 12 months)
-- > DORMANT (real two-way exchange, older) > REPLIED_BEFORE (they answered, thinly) > MESSAGED_BEFORE (one-way) > CONNECTED.
create or replace function public.linkedin_archive_states()
returns jsonb language plpgsql security definer set search_path = public as $$
declare n_st int; n_ev int;
begin
  update linkedin_connections c set li_state = s.st, li_state_reason = s.why, updated_at = now()
    from (select c2.id,
            case when c2.status = 'DO_NOT_CONTACT' or c2.li_opt_out_at is not null or coalesce(k.do_not_contact, false) then 'DO_NOT_CONTACT'
                 when c2.li_out > 0 and c2.li_in > 0 and c2.li_last_at >= now() - interval '30 days' then 'ACTIVE'
                 when c2.li_out > 0 and c2.li_in > 0 and (c2.li_in >= 2 or c2.li_in_chars >= 160) and c2.li_last_at >= now() - interval '365 days' then 'WARM'
                 when c2.li_out > 0 and c2.li_in > 0 and (c2.li_in >= 2 or c2.li_in_chars >= 160) then 'DORMANT'
                 when c2.li_out > 0 and c2.li_in > 0 then 'REPLIED_BEFORE'
                 when c2.li_messages > 0 then 'MESSAGED_BEFORE'
                 when c2.connected then 'CONNECTED' end st,
            nullif(concat_ws(' · ',
              case when c2.li_opt_out_at is not null then 'asked not to be contacted on ' || to_char(c2.li_opt_out_at, 'DD Mon YYYY') end,
              case when coalesce(k.do_not_contact, false) then 'do not contact in the CRM' end,
              case when c2.li_messages > 0 then c2.li_messages || ' message' || case when c2.li_messages = 1 then '' else 's' end || ' (' || c2.li_in || ' from them)' end,
              case when c2.li_last_at is not null then 'last ' || to_char(c2.li_last_at, 'DD Mon YYYY')
                     || case c2.li_last_dir when 'INBOUND' then ', they wrote last' when 'OUTBOUND' then ', you wrote last' else '' end end,
              case when c2.li_intro is not null then 'introduction or referral' end,
              case when c2.connected and c2.connected_on is not null then 'connected since ' || to_char(c2.connected_on, 'Mon YYYY')
                   when c2.connected then 'connected' else 'not a connection' end), '') why
          from linkedin_connections c2 left join contacts k on k.id = c2.matched_contact_id) s
   where s.id = c.id and (c.li_state is distinct from s.st or c.li_state_reason is distinct from s.why);
  get diagnostics n_st = row_count;

  -- Relationship Memory: the LinkedIn history joins the person's evidence list (linkedin_match_all rebuilds that list first).
  update linkedin_connections c set match_evidence =
         coalesce((select jsonb_agg(e) from jsonb_array_elements_text(coalesce(c.match_evidence, '[]'::jsonb)) e where e not like 'LinkedIn:%'), '[]'::jsonb)
         || case when c.li_messages > 0 then jsonb_build_array('LinkedIn: ' || c.li_messages || ' messages (' || c.li_in || ' from them), last ' || to_char(c.li_last_at, 'DD Mon YYYY'))
                 else '[]'::jsonb end
   where c.li_messages > 0 or c.match_evidence::text like '%LinkedIn:%';
  get diagnostics n_ev = row_count;
  return jsonb_build_object('states_changed', n_st, 'evidence_rows', n_ev);
end $$;
revoke all on function public.linkedin_archive_states() from public, anon, authenticated;

-- ---------------------------------------------------------------- 7. the rebuild, in steps short enough for one HQ request each
-- ANALYZE first: rows were just loaded by separate requests, and stale statistics turn the name joins into nested loops.
create or replace function public.linkedin_archive_step(p_step text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_self text; r jsonb := '{}'::jsonb; n_conn int; n_hold int;
begin
  if p_step = 'self' then
    -- Adam is the person present in (nearly) every conversation of his own archive. If he cannot be identified, the history waits.
    if exists (select 1 from linkedin_messages) then
      analyze linkedin_messages;
      r := jsonb_build_object('self_known', linkedin_archive_self() is not null);
    end if;
  elsif p_step = 'people' then
    if exists (select 1 from linkedin_messages) then
      analyze linkedin_connections;
      v_self := linkedin_archive_self();
      r := jsonb_build_object('self_known', v_self is not null);
      if v_self is not null then r := r || linkedin_archive_participants(v_self); end if;
    end if;
  elsif p_step = 'history' then
    analyze linkedin_conversation_people;
    v_self := linkedin_archive_self();
    if v_self is not null then
      r := jsonb_build_object('people_with_history', linkedin_archive_history()) || linkedin_archive_signals(v_self);
    end if;
  elsif p_step = 'match' then
    -- CRM matching: companies by name or email domain, people by profile link, email, then the same name at the same company.
    analyze linkedin_connections;
    r := coalesce(linkedin_match_all(null), '{}'::jsonb);
  elsif p_step = 'states' then
    r := linkedin_archive_states();
    -- The LinkedIn Relationship Agent: a 1st-degree connection needs no connection request, and an opt-out holds the item.
    update linkedin_actions a set connection = 'CONNECTED', updated_at = now()
      from linkedin_connections l where l.matched_contact_id = a.contact_id and l.connected and a.connection = 'UNKNOWN';
    get diagnostics n_conn = row_count;
    update linkedin_actions a set state = 'HELD', updated_at = now(), next_action = 'On hold: they asked not to be contacted',
           hold_reason = 'They asked not to be contacted on LinkedIn' || coalesce(' (' || to_char(l.li_opt_out_at, 'DD Mon YYYY') || ')', '') || ': check before any message'
      from linkedin_connections l where l.matched_contact_id = a.contact_id and l.li_state = 'DO_NOT_CONTACT' and a.state in ('READY', 'CONNECTED');
    get diagnostics n_hold = row_count;
    r := r || jsonb_build_object('agent_marked_connected', n_conn, 'agent_held_opt_out', n_hold, 'rebuilt_at', now(),
                                 'messages', (select count(*) from linkedin_messages), 'conversations', (select count(distinct conversation_id) from linkedin_messages));
  else
    raise exception 'linkedin_archive_step: unknown step %', p_step;
  end if;
  insert into system_config (key, value, note) values ('linkedin_archive', r, 'LinkedIn data archive: last rebuild and import counts')
  on conflict (key) do update set value = coalesce(system_config.value, '{}'::jsonb) || excluded.value, updated_at = now();
  return r;
end $$;
revoke all on function public.linkedin_archive_step(text) from public, anon, authenticated;

-- All steps in one call, for the daily check and service use (no request time limit there).
create or replace function public.linkedin_archive_rebuild()
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb := '{}'::jsonb;
begin
  r := r || linkedin_archive_step('self');
  r := r || linkedin_archive_step('people');
  r := r || linkedin_archive_step('history');
  r := r || linkedin_archive_step('match');
  r := r || linkedin_archive_step('states');
  return r || jsonb_build_object('ok', true);
end $$;
revoke all on function public.linkedin_archive_rebuild() from public, anon, authenticated;

-- ---------------------------------------------------------------- 8. the warm route counts real relationships only
-- A plain connection or a one-way message is not a warm route: it would take the company out of EMAIL READY and change its first
-- email. A real two-way exchange (ACTIVE, WARM, or DORMANT to reopen personally) is, with its date.
create or replace function public.company_warm_route(p_company uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select 'LinkedIn connection: ' || btrim(concat_ws(' ', l.first_name, l.last_name))
            || ' (' || case l.li_state when 'ACTIVE' then 'in conversation on LinkedIn' when 'WARM' then 'two-way on LinkedIn' else 'dormant on LinkedIn, reopen personally' end
            || coalesce(', last ' || to_char(l.li_last_at, 'Mon YYYY'), '') || ')'
       from linkedin_connections l
      where l.matched_company_id = p_company and l.li_state in ('ACTIVE', 'WARM', 'DORMANT')
      order by case l.li_state when 'ACTIVE' then 1 when 'WARM' then 2 else 3 end, l.li_last_at desc nulls last limit 1),
    (select 'Previous email relationship (' || coalesce(r.status, 'reviewed') || ')' from relationship_reviews r join companies c on c.id = p_company
      where c.website is not null and r.key = 'd:' || lower(regexp_replace(c.website, '^(https?://)?(www\.)?([^/?#]+).*$', '\3'))
        and coalesce(r.status, '') not in ('NOT_RELEVANT') limit 1),
    (select 'Replied to NOYA before (' || to_char(max(i.occurred_at), 'Mon YYYY') || ')' from interactions i where i.company_id = p_company and i.direction = 'INBOUND' and i.channel <> 'WEBSITE' having count(*) > 0))
$$;
revoke all on function public.company_warm_route(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- 9. the LinkedIn agent, the Top 5 and the LinkedIn page see the history
create or replace function public.linkedin_board()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id, 'state', a.state, 'connection', a.connection, 'person', btrim(coalesce(k.first_name, '') || ' ' || coalesce(k.last_name, '')),
      'first_name', k.first_name, 'role', k.position, 'linkedin', nullif(k.linkedin, ''), 'company', c.name, 'company_id', a.company_id, 'contact_id', a.contact_id,
      'opportunity_id', a.opportunity_id, 'task_id', a.task_id, 'director', a.director, 'project', a.project, 'why_them', a.why_them, 'why_now', a.why_now,
      'relationship', relationship_state(a.company_id), 'message', a.message, 'connection_note', a.connection_note, 'followup', a.followup,
      'next_action', a.next_action, 'sent_at', a.sent_at, 'connection_sent_at', a.connection_sent_at, 'connected_at', a.connected_at,
      'replied_at', a.replied_at, 'reply_text', a.reply_text, 'reply_class', a.reply_class, 'response_draft', a.response_draft,
      'meeting_task_id', a.meeting_task_id, 'hold_reason', a.hold_reason, 'created_at', a.created_at,
      'li_state', h.li_state, 'li_reason', h.li_state_reason, 'li_last_at', h.li_last_at, 'li_connected', h.connected,
      'words', array_length(regexp_split_to_array(btrim(coalesce(a.message, '')), '\s+'), 1))
    order by case a.state when 'REPLIED' then 0 when 'CONNECTED' then 1 when 'READY' then 2 when 'CONNECTION_SENT' then 3 when 'SENT' then 4 when 'MEETING' then 5 else 6 end,
             a.updated_at desc), '[]'::jsonb)
    from linkedin_actions a left join contacts k on k.id = a.contact_id left join companies c on c.id = a.company_id
    left join lateral (select l.li_state, l.li_state_reason, l.li_last_at, l.connected from linkedin_connections l
                        where l.matched_contact_id = a.contact_id order by l.connected desc, l.li_last_at desc nulls last limit 1) h on true
   where a.state <> 'CLOSED' or a.updated_at > now() - interval '14 days'
$$;
revoke all on function public.linkedin_board() from public, anon, authenticated;

-- Warmth: warm on LinkedIn counts like a warm CRM relationship; spoken before 8; already connected 6. They asked to stop: never in the five.
create or replace function public.outreach_top5(d jsonb)
returns jsonb language sql stable security definer set search_path = public as $$
  with it as (
    select e, e->>'ref' ref, coalesce(e->>'channel', 'EMAIL') ch, e->>'director' dir, nullif(e->>'opportunity_id', '')::uuid opp,
           nullif(e->>'company_id', '')::uuid co, nullif(e->>'contact_id', '')::uuid ct, e->>'role' role, coalesce((e->>'age_days')::int, 0) age,
           nullif(e->>'why_now', '') why, coalesce(e->>'angle', '') angle
      from jsonb_array_elements(coalesce(d->'needs_review', '[]'::jsonb)) e),
  s as (
    select it.*, o.egypt eg, o.mission, coalesce(o.priority, 50) pr, c.partnership_model pm, relationship_state(it.co) rel,
           least(coalesce(role_score(it.role), 0), 5) rs, (select k.identity_status from contacts k where k.id = it.ct) idst,
           (select l.li_state from linkedin_connections l where l.matched_contact_id = it.ct order by l.connected desc, l.li_last_at desc nulls last limit 1) li
      from it left join opportunities o on o.id = it.opp left join companies c on c.id = it.co
     where coalesce(o.egypt->>'sprint', '') <> 'HOLD' and coalesce(it.e->>'qa', 'PASS') <> 'FLAGGED'),
  sc as (
    select s.*,
      case when s.eg ? 'scores' then (coalesce((s.eg->'scores'->>'project_generation')::numeric, 0) * 4 + coalesce((s.eg->'scores'->>'repeat')::numeric, 0) * 3 + coalesce((s.eg->'scores'->>'network')::numeric, 0) * 3) * 0.6
           else s.pr * 0.2 end potential,
      case when s.li in ('ACTIVE', 'WARM') then 15
           when s.rel in ('ACTIVE_CONVERSATION', 'THEY_WROTE_LAST', 'MEETING_BOOKED', 'PROPOSAL', 'CLIENT', 'PARTNER_ACTIVE', 'TWO_WAY', 'RECONNECT', 'FOLLOW_UP') then 15
           when s.li in ('DORMANT', 'REPLIED_BEFORE') then 8
           when s.li = 'CONNECTED' then 6
           when s.rel = 'COLD' then 0 else 4 end warmth,
      (case when s.why is not null then 8 else 0 end) + (case when s.age <= 7 then 4 when s.age > 21 then -4 else 0 end) + (case when s.mission = 'DESTINATION_EGYPT' then 6 else 0 end) timing,
      s.rs * 3 + case when s.idst = 'CONFIRMED' then 3 else 0 end dm,
      case when s.eg ? 'scores' then (coalesce((s.eg->'scores'->>'egypt_relevance')::numeric, 0) + coalesce((s.eg->'scores'->>'destination_evidence')::numeric, 0)) * 2
           when (s.angle || ' ' || coalesce(s.why, '')) ~* '(egypt|cairo|nile|giza|red sea|luxor|aswan|pyramid)' then 8 else 2 end egypt,
      case when s.eg ? 'scores' then coalesce((s.eg->'scores'->>'repeat')::numeric, 0) * 2 when s.pm is not null then 6 else 2 end rep,
      case when s.ch = 'EMAIL' then 5 else 0 end chan
      from s where coalesce(s.li, '') <> 'DO_NOT_CONTACT'),
  r as (
    select sc.*, round(potential + warmth + timing + dm + egypt + rep + chan) score,
           row_number() over (partition by coalesce(dir, '-') order by potential + warmth + timing + dm + egypt + rep + chan desc) per_dir
      from sc)
  select coalesce(jsonb_agg(jsonb_build_object('ref', ref, 'score', score, 'channel', ch,
           'why', array_to_string(array_remove(array[
             case when mission = 'DESTINATION_EGYPT' then 'Destination Egypt' end,
             case when li in ('ACTIVE', 'WARM') then 'warm on LinkedIn' when warmth >= 15 then 'warm relationship'
                  when li in ('DORMANT', 'REPLIED_BEFORE') then 'spoke before on LinkedIn' when li = 'CONNECTED' then 'already connected on LinkedIn' end,
             case when rs >= 4 then 'senior decision maker' when rs >= 3 then 'right person' end,
             case when why is not null then 'clear why-now' end,
             case when ch = 'EMAIL' then 'email route' else 'LinkedIn (email exhausted)' end], null), ' · '))
           order by score desc), '[]'::jsonb)
    from (select * from r where per_dir <= 2 order by score desc limit 5) q
$$;
revoke all on function public.outreach_top5(jsonb) from public, anon, authenticated;

-- The LinkedIn page lists people with a link to NOYA or a history, plus the total (everyone stays in the database for matching and reports).
do $patch$
declare src text := pg_get_functiondef('public.hq_directory()'::regprocedure);
  a1 text := $a$'email_history', l.history_threads, 'vertical', l.vertical, 'status', l.status,$a$;
  b1 text := $a$'email_history', l.history_threads, 'vertical', l.vertical, 'status', l.status,
        'connected', l.connected, 'li_state', l.li_state, 'li_reason', l.li_state_reason, 'li_last_at', l.li_last_at, 'li_messages', l.li_messages, 'review_reason', l.review_reason,$a$;
  a2 text := $a$      from linkedin_connections l left join companies mc on mc.id = l.matched_company_id), '[]'::jsonb),$a$;
  b2 text := $a$      from linkedin_connections l left join companies mc on mc.id = l.matched_company_id
     where l.matched_company_id is not null or l.matched_contact_id is not null or l.li_messages > 0 or l.status <> 'NEW' or l.how_we_know is not null
        or l.review_reason is not null), '[]'::jsonb),
    'connections_total', (select count(*) from linkedin_connections where connected),$a$;
begin
  if strpos(src, $a$'li_state', l.li_state$a$) > 0 then return; end if;
  if strpos(src, a1) = 0 or strpos(src, a2) = 0 then raise exception 'hq_directory() changed: anchors not found'; end if;
  execute replace(replace(src, a1, b1), a2, b2);
end $patch$;

-- ---------------------------------------------------------------- 10. the report after each import
-- One row per person with the shape every report list uses, and the recency rule in plain words.
create or replace function public.linkedin_archive_people()
returns table (id uuid, j jsonb, state text, srank int, last_at timestamptz, company_id uuid, contact_id uuid, company_key text, company text,
               person text, role text, li_in int, li_out int, intro jsonb, opt_out_at timestamptz, review text, connected boolean)
language sql stable security definer set search_path = public as $$
  select l.id,
         jsonb_build_object('person', btrim(concat_ws(' ', l.first_name, l.last_name)), 'role', l.position, 'company', coalesce(mc.name, l.company),
           'crm_company', mc.name, 'state', l.li_state, 'reason', l.li_state_reason, 'last_at', l.li_last_at, 'in_crm', l.matched_contact_id is not null,
           'connection_id', l.id, 'profile_url', l.profile_url,
           'recency', case when l.li_last_at < now() - interval '365 days' then 'Last message ' || to_char(l.li_last_at, 'Mon YYYY') || ': old, reopen personally, not a live lead'
                           when l.li_last_at < now() - interval '90 days' then 'Last message ' || to_char(l.li_last_at, 'Mon YYYY') || ': check what changed before writing'
                           when l.li_last_at is not null then 'Recent: last message ' || to_char(l.li_last_at, 'DD Mon YYYY')
                           when l.connected then 'Connected, never messaged: a first message needs no connection request' end),
         l.li_state,
         case l.li_state when 'ACTIVE' then 1 when 'WARM' then 2 when 'DORMANT' then 3 when 'REPLIED_BEFORE' then 4 when 'MESSAGED_BEFORE' then 5 when 'CONNECTED' then 6 else 9 end,
         l.li_last_at, l.matched_company_id, l.matched_contact_id, company_name_key(l.company), l.company, btrim(concat_ws(' ', l.first_name, l.last_name)),
         l.position, l.li_in, l.li_out, l.li_intro, l.li_opt_out_at, l.review_reason, l.connected
    from linkedin_connections l left join companies mc on mc.id = l.matched_company_id
$$;
revoke all on function public.linkedin_archive_people() from public, anon, authenticated;

create or replace function public.linkedin_archive_report()
returns jsonb language sql stable security definer set search_path = public as $$
  with cfg as (select coalesce((select value from system_config where key = 'linkedin_archive'), '{}'::jsonb) v),
  p as materialized (select * from linkedin_archive_people()),
  de as (select o.id opp, o.company_id, coalesce(o.egypt->>'proposed_project', o.angle) project, o.status from opportunities o
          where o.mission = 'DESTINATION_EGYPT' and o.status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM') and coalesce(o.egypt->>'sprint', '') <> 'HOLD'),
  dep as (select distinct on (de.opp) p.j || jsonb_build_object('project', de.project, 'opportunity_id', de.opp, 'opportunity_status', de.status) j, p.srank, p.last_at
            from de join p on p.company_id = de.company_id and p.state <> 'DO_NOT_CONTACT'
           order by de.opp, p.srank, p.last_at desc nulls last)
  select jsonb_build_object(
    'imported_at', (select v->>'rebuilt_at' from cfg), 'self_known', (select (v->>'self_known')::boolean from cfg), 'last_import', (select v->'last_import' from cfg),
    'connections', (select count(*) from p where connected),
    'people_from_messages_only', (select count(*) from p where not connected),
    'messages', (select count(*) from linkedin_messages), 'conversations', (select count(distinct conversation_id) from linkedin_messages),
    'conversations_matched', (select count(distinct cp.conversation_id) from linkedin_conversation_people cp join linkedin_connections l on l.id = cp.connection_id
                               where l.matched_contact_id is not null or l.matched_company_id is not null),
    'states', coalesce((select jsonb_object_agg(state, n) from (select state, count(*) n from p where state is not null group by 1) x), '{}'::jsonb),
    'matched_contacts', (select count(*) from p where contact_id is not null),
    'match_methods', coalesce((select jsonb_object_agg(coalesce(match_method, 'OTHER'), n) from (select match_method, count(*) n from linkedin_connections where matched_contact_id is not null group by 1) x), '{}'::jsonb),
    'matched_companies', (select count(distinct company_id) from p where company_id is not null),
    'companies_spoken_to', jsonb_build_object(
       'count', (select count(distinct coalesce(company_id::text, company_key)) from p where li_in > 0 and li_out > 0 and coalesce(company_id::text, company_key) is not null),
       'in_crm', (select count(distinct company_id) from p where li_in > 0 and li_out > 0 and company_id is not null)),
    'companies_new', jsonb_build_object(
       'count', (select count(distinct company_key) from p where company_id is null and company_key is not null),
       'top', coalesce((select jsonb_agg(x order by x.best, x.two_way desc, x.people desc) from (
           select min(company) company, count(*) people, count(*) filter (where li_in > 0 and li_out > 0) two_way, min(srank) best,
                  (array_agg(state order by srank))[1] best_state, (array_agg(person order by srank, last_at desc nulls last))[1] person
             from p where company_id is null and company_key is not null group by company_key
            order by min(srank), count(*) filter (where li_in > 0 and li_out > 0) desc, count(*) desc limit 20) x), '[]'::jsonb)),
    'warm', coalesce((select jsonb_agg(j order by srank, last_at desc nulls last) from (select * from p where state in ('ACTIVE', 'WARM') order by srank, last_at desc nulls last limit 15) w), '[]'::jsonb),
    'warm_destination_egypt', coalesce((select jsonb_agg(j order by srank, last_at desc nulls last) from (select * from dep where srank <= 4 order by srank, last_at desc nulls last limit 15) w), '[]'::jsonb),
    'connected_destination_egypt', coalesce((select jsonb_agg(j order by srank) from (select * from dep where srank in (5, 6) order by srank limit 15) w), '[]'::jsonb),
    'dormant', coalesce((select jsonb_agg(j order by score desc) from (
        select p.j, (case when exists (select 1 from opportunities o where o.company_id = p.company_id and o.status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM')) then 20 else 0 end)
                    + least(coalesce(role_score(p.role), 0), 5) * 3 + least(p.li_in, 10) + (case when p.intro is not null then 5 else 0 end) score
          from p where p.state = 'DORMANT' order by 2 desc limit 15) d), '[]'::jsonb),
    'introductions', coalesce((select jsonb_agg(j || jsonb_build_object('intro', intro->0) order by last_at desc nulls last) from (select * from p where intro is not null order by last_at desc nulls last limit 15) i), '[]'::jsonb),
    'review', jsonb_build_object(
       'count', (select count(*) from p where review is not null),
       'top', coalesce((select jsonb_agg(j || jsonb_build_object('review', review) order by srank) from (select * from p where review is not null order by srank, last_at desc nulls last limit 20) r), '[]'::jsonb),
       'warm_not_in_crm', (select count(*) from p where contact_id is null and state in ('ACTIVE', 'WARM', 'DORMANT')),
       'warm_not_in_crm_top', coalesce((select jsonb_agg(j order by srank) from (select * from p where contact_id is null and state in ('ACTIVE', 'WARM', 'DORMANT') order by srank, last_at desc nulls last limit 15) r), '[]'::jsonb),
       'do_not_contact', coalesce((select jsonb_agg(j order by opt_out_at desc) from (select * from p where state = 'DO_NOT_CONTACT' and opt_out_at is not null order by opt_out_at desc limit 20) r), '[]'::jsonb)),
    'duplicates_prevented', jsonb_build_object(
       'in_files', coalesce(((select v from cfg)->'last_import'->>'file_duplicates')::int, 0),
       'connections_already_known', coalesce(((select v from cfg)->'last_import'->>'connections_updated')::int, 0),
       'messages_already_imported', coalesce(((select v from cfg)->'last_import'->>'messages_already_imported')::int, 0),
       'linked_to_existing_crm_contacts', (select count(*) from p where contact_id is not null),
       'message_people_linked_by_name', coalesce(((select v from cfg)->>'people_linked_by_name')::int, 0)),
    'note', 'Read-only history from Adam''s own LinkedIn download. No CRM person or company is created from it and nothing is sent. Every state carries its date: an old conversation is never a live lead until it is checked.')
$$;
revoke all on function public.linkedin_archive_report() from public, anon, authenticated;

-- ---------------------------------------------------------------- 11. the one admin call HQ uses
create or replace function public.hq_linkedin_archive(p_step text default null, p_stats jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); r jsonb;
begin
  -- HQ calls start before the upload, then the steps in order (self, people, history, match, states), each in its own request.
  if p_step = 'start' then
    insert into system_config (key, value, note)
    values ('linkedin_archive', jsonb_build_object('self_hint', linkedin_canonical_url(p_stats->>'self_hint'), 'import_started_at', now()), 'LinkedIn data archive: last rebuild and import counts')
    on conflict (key) do update set value = coalesce(system_config.value, '{}'::jsonb) || excluded.value, updated_at = now();
    return jsonb_build_object('ok', true, 'next', 'upload');
  elsif p_step in ('self', 'people', 'history', 'match') then
    r := linkedin_archive_step(p_step);
    return jsonb_build_object('ok', true, 'step', p_step, 'result', r,
                              'next', case p_step when 'self' then 'people' when 'people' then 'history' when 'history' then 'match' else 'states' end);
  elsif p_step = 'states' then
    update system_config set value = value || jsonb_build_object('last_import', coalesce(p_stats, '{}'::jsonb) || jsonb_build_object('at', now(), 'by', v_admin)), updated_at = now()
     where key = 'linkedin_archive';
    r := linkedin_archive_step('states');
    perform hq_audit('LINKEDIN_ARCHIVE_IMPORT', null, coalesce(p_stats, '{}'::jsonb) || jsonb_build_object('rebuild', r));
  elsif p_step is not null and p_step <> 'report' then
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_STEP');
  end if;
  return linkedin_archive_report() || jsonb_build_object('ok', true);
end $$;
revoke all on function public.hq_linkedin_archive(text, jsonb) from public, anon;
grant execute on function public.hq_linkedin_archive(text, jsonb) to authenticated;

-- A person's LinkedIn history in their HQ drawer: the last twelve messages between Adam and them, newest first, read-only.
create or replace function public.hq_linkedin_history(p_connection uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email();
begin
  -- The last messages between Adam and this person (their conversations, Adam's and their own lines), newest first, read-only.
  return coalesce((select jsonb_agg(jsonb_build_object('at', x.sent_at, 'out', x.direction = 'OUTBOUND', 'who', x.sender_name, 'title', nullif(x.conversation_title, ''),
                                                         'text', left(x.content, 700), 'group', x.np > 1) order by x.sent_at desc)
    from (select m.sent_at, m.direction, m.sender_name, m.conversation_title, m.content,
                 (select count(*) from linkedin_conversation_people c2 where c2.conversation_id = m.conversation_id) np
            from linkedin_messages m
           where m.conversation_id in (select cp.conversation_id from linkedin_conversation_people cp where cp.connection_id = p_connection)
             and (m.direction = 'OUTBOUND' or m.sender_url in (select cp.profile_url from linkedin_conversation_people cp where cp.connection_id = p_connection))
           order by m.sent_at desc limit 12) x), '[]'::jsonb);
end $$;
revoke all on function public.hq_linkedin_history(uuid) from public, anon;
grant execute on function public.hq_linkedin_history(uuid) to authenticated;
