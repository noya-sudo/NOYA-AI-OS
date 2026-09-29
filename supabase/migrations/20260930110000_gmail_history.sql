-- Historical NOYA email reconciliation (workflow 15).
-- Metadata only: headers + Gmail's own short snippet. Message bodies are never requested or stored.
-- Deterministic filtering decides what is commercial; nothing here uses AI.
-- Idempotent on Gmail message id; interactions share the existing unique external_message_id guard
-- used by workflows 12/13 (on conflict do nothing), so no path can double-log a message.
-- Only Gmail messages carrying the SENT label are ever recorded as sent.

create table if not exists public.gmail_history_messages (
  gmail_message_id text primary key,
  gmail_thread_id text not null,
  mailbox text not null,
  sent_at timestamptz not null,
  direction text check (direction in ('OUTBOUND', 'INBOUND')),
  category text not null,               -- COMMERCIAL or IGNORED_<reason> (ignored rows keep no content)
  from_email text,
  from_name text,
  to_emails text[],
  cc_emails text[],
  counterpart_emails text[] not null default '{}',
  counterpart_domains text[] not null default '{}',
  subject text,
  snippet text,
  labels text[],
  contact_id uuid references public.contacts(id) on delete set null,
  company_id uuid references public.companies(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  match_method text,
  interaction_id uuid,
  source text not null default 'GMAIL',
  first_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ghm_thread_idx on public.gmail_history_messages (gmail_thread_id);
create index if not exists ghm_company_idx on public.gmail_history_messages (company_id);
create index if not exists ghm_contact_idx on public.gmail_history_messages (contact_id);
create index if not exists ghm_emails_idx on public.gmail_history_messages using gin (counterpart_emails);
create index if not exists ghm_domains_idx on public.gmail_history_messages using gin (counterpart_domains);
alter table public.gmail_history_messages enable row level security;
revoke all on public.gmail_history_messages from anon, authenticated;

create table if not exists public.gmail_history_threads (
  gmail_thread_id text primary key,
  mailbox text not null,
  subject text,
  first_at timestamptz,
  last_at timestamptz,
  messages int not null default 0,
  outbound int not null default 0,
  inbound int not null default 0,
  last_direction text,
  last_outbound_at timestamptz,
  last_inbound_at timestamptz,
  counterpart_emails text[] not null default '{}',
  counterpart_domains text[] not null default '{}',
  company_id uuid references public.companies(id) on delete set null,
  contact_id uuid references public.contacts(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  relevant boolean not null default false,  -- Adam wrote in it, or it matches a CRM record
  relationship_state text,                  -- REPLIED / WAIT / FOLLOW_UP / RECONNECT / LONG_TERM / INBOUND_ONLY / MEETING / DO_NOT_CONTACT
  summary text,                             -- optional AI summary; the thread itself stays the evidence
  summary_source text,
  summary_at timestamptz,
  hq_status text,                           -- DISMISSED / ADDED_TO_CRM (Adam's decision in HQ)
  updated_at timestamptz not null default now()
);
create index if not exists ght_company_idx on public.gmail_history_threads (company_id);
create index if not exists ght_contact_idx on public.gmail_history_threads (contact_id);
create index if not exists ght_domains_idx on public.gmail_history_threads using gin (counterpart_domains);
alter table public.gmail_history_threads enable row level security;
revoke all on public.gmail_history_threads from anon, authenticated;

create table if not exists public.gmail_backfill_state (
  mailbox text primary key,
  mode text not null default 'BACKFILL' check (mode in ('BACKFILL', 'INCREMENTAL')),
  window_start date not null,
  page_token text,
  history_id text,
  pages int not null default 0,
  scanned int not null default 0,
  new_messages int not null default 0,
  duplicates int not null default 0,
  commercial int not null default 0,
  ignored int not null default 0,
  started_at timestamptz not null default now(),
  backfill_done_at timestamptz,
  last_run_at timestamptz,
  last_error text,
  last_summary jsonb
);
alter table public.gmail_backfill_state enable row level security;
revoke all on public.gmail_backfill_state from anon, authenticated;

-- CRM links for outreach decisions.
alter table public.opportunities add column if not exists prior_relationship text;
alter table public.opportunities add column if not exists prior_relationship_at timestamptz;
alter table public.opportunities add column if not exists prior_thread_id text;

create index if not exists companies_regdomain_idx on public.companies (registrable_domain(website));

create or replace function public.email_is_freemail(p_domain text)
returns boolean language sql immutable as $$
  select lower(coalesce(p_domain, '')) ~ '^(gmail\.com|googlemail\.com|hotmail\.[a-z.]+|outlook\.[a-z.]+|live\.[a-z.]+|msn\.com|yahoo\.[a-z.]+|ymail\.com|icloud\.com|me\.com|mac\.com|aol\.com|proton\.me|protonmail\.com|gmx\.[a-z.]+|yandex\.[a-z.]+|mail\.ru|web\.de|free\.fr|orange\.fr|btinternet\.com|sky\.com|virginmedia\.com)$'
$$;

create or replace function public.email_is_platform(p_domain text)
returns boolean language sql immutable as $$
  select lower(coalesce(p_domain, '')) ~ '(^|\.)(google\.com|youtube\.com|linkedin\.com|facebookmail\.com|facebook\.com|instagram\.com|meta\.com|apple\.com|stripe\.com|paypal\.com|wise\.com|revolut\.com|n8n\.io|n8n\.cloud|supabase\.(io|com)|github\.com|hunter\.io|serper\.dev|firecrawl\.dev|anthropic\.com|openai\.com|windsor\.ai|squarespace\.com|squarespace-mail\.com|wix\.com|godaddy\.com|cloudflare\.com|namecheap\.com|calendly\.com|zoom\.us|docusign\.(net|com)|dropbox\.com|notion\.so|slack\.com|canva\.com|shopify\.com|amazon\.[a-z.]+|amazonses\.com|mailchimp\.com|mcsv\.net|sendgrid\.net|hubspot\.com|hubspotemail\.net|intercom\.io|zendesk\.com|atlassian\.net|figma\.com|adobe\.com|microsoft\.com|office\.com|booking\.com|airbnb\.com|uber\.com|resend\.dev|mailgun\.org|postmarkapp\.com)$'
$$;

-- Relationship state for one thread (plain rules, explained in HQ).
create or replace function public.gmail_relationship_state(p_out int, p_in int, p_last_dir text, p_last_out timestamptz, p_last_in timestamptz, p_last timestamptz)
returns text language sql stable as $$
  select case
    when p_out = 0 then 'INBOUND_ONLY'
    when p_last_dir = 'INBOUND' and p_last_in > now() - interval '60 days' then 'REPLIED'
    when p_in > 0 and p_last < now() - interval '60 days' then 'RECONNECT'
    when p_last_dir = 'OUTBOUND' and p_last_out > now() - interval '7 days' then 'WAIT'
    when p_last_dir = 'OUTBOUND' and p_last_out > now() - interval '60 days' then 'FOLLOW_UP'
    when p_in > 0 then 'RECONNECT'
    else 'LONG_TERM' end
$$;

-- Rebuild the given threads: propagate matches within a thread, write interactions for matched
-- commercial messages, refresh the thread summary row and clear content from irrelevant threads.
create or replace function public.gmail_history_rebuild(p_threads text[])
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_int int := 0; v_linked int := 0;
begin
  if coalesce(cardinality(p_threads), 0) = 0 then return jsonb_build_object('threads', 0); end if;

  -- A reply that Gmail filed under Updates, or that carries list headers from the sender's mail system,
  -- is still a reply when Adam wrote in the thread.
  update gmail_history_messages m set category = 'COMMERCIAL', match_method = coalesce(m.match_method, 'THREAD'), updated_at = now()
   where m.gmail_thread_id = any(p_threads) and m.direction = 'INBOUND' and m.from_email is not null
     and m.category in ('IGNORED_BULK_CATEGORY', 'IGNORED_BULK', 'IGNORED_AUTOMATED_SENDER')
     and split_part(m.from_email, '@', 1) !~ '^(mailer-daemon|postmaster|bounces?|no-?reply|do-?not-?reply)'  -- delivery failures are never replies
     and exists (select 1 from gmail_history_messages o where o.gmail_thread_id = m.gmail_thread_id and o.direction = 'OUTBOUND' and o.category = 'COMMERCIAL');

  -- A thread that matched a CRM record through one message belongs to that record.
  update gmail_history_messages m set company_id = t.company_id, contact_id = coalesce(m.contact_id, t.contact_id),
         opportunity_id = coalesce(m.opportunity_id, t.opportunity_id), match_method = 'THREAD', updated_at = now()
    from (select gmail_thread_id,
                 (array_agg(company_id order by sent_at) filter (where company_id is not null))[1] company_id,
                 (array_agg(contact_id order by sent_at) filter (where contact_id is not null))[1] contact_id,
                 (array_agg(opportunity_id order by sent_at) filter (where opportunity_id is not null))[1] opportunity_id
            from gmail_history_messages where gmail_thread_id = any(p_threads) and category = 'COMMERCIAL' group by 1) t
   where m.gmail_thread_id = t.gmail_thread_id and m.category = 'COMMERCIAL' and m.company_id is null and m.contact_id is null
     and (t.company_id is not null or t.contact_id is not null);

  -- Link messages already logged by workflows 12/13, then log the rest (idempotent).
  update gmail_history_messages m set interaction_id = i.id
    from interactions i where i.external_message_id = m.gmail_message_id and m.interaction_id is null and m.gmail_thread_id = any(p_threads);
  get diagnostics v_linked = row_count;
  with ins as (
    insert into interactions (company_id, contact_id, opportunity_id, channel, direction, subject, summary, external_message_id, occurred_at)
    select m.company_id, m.contact_id, m.opportunity_id, 'EMAIL', m.direction, left(m.subject, 300),
           case m.direction
             when 'OUTBOUND' then 'Email sent by Adam from ' || m.mailbox || ' to ' || array_to_string(m.counterpart_emails, ', ')
                                  || ' (manual send; Gmail Sent Mail, historical import).'
             else 'Email received from ' || coalesce(m.from_email, 'unknown') || ' (Gmail, historical import).' end,
           m.gmail_message_id, m.sent_at
      from gmail_history_messages m
     where m.gmail_thread_id = any(p_threads) and m.category = 'COMMERCIAL' and m.interaction_id is null
       and (m.company_id is not null or m.contact_id is not null)
    on conflict do nothing
    returning id, external_message_id)
  update gmail_history_messages m set interaction_id = ins.id from ins where m.gmail_message_id = ins.external_message_id;
  get diagnostics v_int = row_count;

  -- Thread rows.
  insert into gmail_history_threads (gmail_thread_id, mailbox, subject, first_at, last_at, messages, outbound, inbound, last_direction,
      last_outbound_at, last_inbound_at, counterpart_emails, counterpart_domains, company_id, contact_id, opportunity_id, relevant, updated_at)
  select m.gmail_thread_id, max(m.mailbox), (array_agg(m.subject order by m.sent_at) filter (where m.subject is not null))[1],
         min(m.sent_at), max(m.sent_at), count(*), count(*) filter (where m.direction = 'OUTBOUND'), count(*) filter (where m.direction = 'INBOUND'),
         (array_agg(m.direction order by m.sent_at desc))[1],
         max(m.sent_at) filter (where m.direction = 'OUTBOUND'), max(m.sent_at) filter (where m.direction = 'INBOUND'),
         coalesce((select array_agg(distinct e) from gmail_history_messages x, unnest(x.counterpart_emails) e where x.gmail_thread_id = m.gmail_thread_id and x.category = 'COMMERCIAL'), '{}'),
         coalesce((select array_agg(distinct d) from gmail_history_messages x, unnest(x.counterpart_domains) d where x.gmail_thread_id = m.gmail_thread_id and x.category = 'COMMERCIAL'), '{}'),
         (array_agg(m.company_id order by m.sent_at) filter (where m.company_id is not null))[1],
         (array_agg(m.contact_id order by m.sent_at) filter (where m.contact_id is not null))[1],
         (array_agg(m.opportunity_id order by m.sent_at) filter (where m.opportunity_id is not null))[1],
         bool_or(m.direction = 'OUTBOUND') or bool_or(m.company_id is not null or m.contact_id is not null), now()
    from gmail_history_messages m
   where m.gmail_thread_id = any(p_threads) and m.category = 'COMMERCIAL'
   group by m.gmail_thread_id
  on conflict (gmail_thread_id) do update set subject = excluded.subject, first_at = excluded.first_at, last_at = excluded.last_at,
     messages = excluded.messages, outbound = excluded.outbound, inbound = excluded.inbound, last_direction = excluded.last_direction,
     last_outbound_at = excluded.last_outbound_at, last_inbound_at = excluded.last_inbound_at, counterpart_emails = excluded.counterpart_emails,
     counterpart_domains = excluded.counterpart_domains, company_id = excluded.company_id, contact_id = excluded.contact_id,
     opportunity_id = excluded.opportunity_id, relevant = excluded.relevant, updated_at = now();

  update gmail_history_threads t set relationship_state = case
      when exists (select 1 from contacts k where k.id = t.contact_id and (k.do_not_contact or k.status = 'DO_NOT_CONTACT')) then 'DO_NOT_CONTACT'
      when exists (select 1 from opportunities o where o.id = t.opportunity_id and o.status in ('CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION')) then 'MEETING'
      else gmail_relationship_state(t.outbound, t.inbound, t.last_direction, t.last_outbound_at, t.last_inbound_at, t.last_at) end
   where t.gmail_thread_id = any(p_threads);

  -- Privacy: content of threads NOYA never wrote in and that match no CRM record is not kept.
  update gmail_history_messages m set subject = null, snippet = null, from_name = null
   where m.gmail_thread_id = any(p_threads) and m.subject is not null
     and m.gmail_thread_id in (select gmail_thread_id from gmail_history_threads where gmail_thread_id = any(p_threads) and not relevant);

  update gmail_history_threads set subject = null, counterpart_emails = '{}'
   where gmail_thread_id = any(p_threads) and not relevant and subject is not null;

  -- Keep contact recency true to the mailbox.
  update contacts k set last_contact_at = x.last
    from (select contact_id, max(sent_at) last from gmail_history_messages where gmail_thread_id = any(p_threads) and contact_id is not null and category = 'COMMERCIAL' group by 1) x
   where k.id = x.contact_id and (k.last_contact_at is null or k.last_contact_at < x.last);

  return jsonb_build_object('threads', cardinality(p_threads), 'interactions_created', v_int, 'interactions_linked', v_linked);
end $$;

-- Cold outreach must never go to someone Adam has already emailed. For opportunities that have not
-- yet been contacted through the CRM, record the prior relationship, hold any pending cold email
-- approval (never overriding Adam's own hold/reject), park cold LinkedIn/Instagram intros, and book
-- one follow-up / reconnect task instead.
create or replace function public.gmail_history_apply_outreach()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare r record; v_held int := 0; v_tasks int := 0; v_parked int := 0; v_n int; v_marked int := 0; v_title text; v_prio int;
begin
  for r in
    select o.id, o.company_id, o.contact_id, o.status, coalesce(c.name, o.company_name) as company, t.gmail_thread_id, t.relationship_state, t.last_at,
           t.subject, t.outbound, t.inbound, t.last_outbound_at, t.last_inbound_at
      from opportunities o
      left join companies c on c.id = o.company_id
      join lateral (
        select * from gmail_history_threads t
         where t.relevant and coalesce(t.hq_status, '') <> 'DISMISSED'
           and ((o.contact_id is not null and t.contact_id = o.contact_id) or (o.company_id is not null and t.company_id = o.company_id))
         order by t.last_at desc limit 1) t on true
     where o.status in ('NEW', 'RESEARCHING', 'READY')
       and not exists (select 1 from outbound_emails e where e.opportunity_id = o.id and e.status = 'SENT')
  loop
    update opportunities set prior_relationship = r.relationship_state, prior_relationship_at = r.last_at, prior_thread_id = r.gmail_thread_id
     where id = r.id and prior_relationship is distinct from r.relationship_state;
    if found then v_marked := v_marked + 1; end if;

    insert into approval_queue_state (opportunity_id, state, reason, decided_by)
    select r.id, 'HOLD', 'Previously in contact (Gmail, last ' || to_char(r.last_at at time zone 'Africa/Cairo', 'DD Mon YYYY') || ', '
           || lower(replace(r.relationship_state, '_', ' ')) || '). Cold introduction suppressed — follow up or reconnect instead.', 'SYSTEM (Gmail history)'
     where exists (select 1 from tasks tk where tk.opportunity_id = r.id and tk.task_type = 'SALES_OUTREACH_APPROVAL' and tk.status in ('OPEN', 'IN_PROGRESS', 'WAITING'))
    on conflict (opportunity_id) do nothing;
    if found then v_held := v_held + 1; end if;

    update tasks set status = 'WAITING',
           description = coalesce(description, '') || E'\n\nParked by HQ: a previous Gmail conversation exists (last '
             || to_char(r.last_at at time zone 'Africa/Cairo', 'DD Mon YYYY') || '). This cold introduction is not sent; see the reconnect task.'
     where opportunity_id = r.id and status = 'OPEN' and (title like 'LINKEDIN MESSAGE READY%' or title like 'INSTAGRAM DM READY%')
       and coalesce(description, '') not like '%Parked by HQ: a previous Gmail conversation%';
    get diagnostics v_n = row_count;
    v_parked := v_parked + v_n;

    v_title := case r.relationship_state
      when 'REPLIED' then 'REPLY OWED -- ' || r.company || ' (they wrote last)'
      when 'FOLLOW_UP' then 'FOLLOW UP -- ' || r.company || ' (emailed, no reply yet)'
      when 'RECONNECT' then 'RECONNECT -- ' || r.company || ' (previous conversation)'
      when 'MEETING' then 'MEETING FOLLOW-UP -- ' || r.company
      when 'DO_NOT_CONTACT' then null
      when 'WAIT' then null
      when 'INBOUND_ONLY' then 'RECONNECT -- ' || r.company || ' (they emailed NOYA before)'
      else 'RECONNECT -- ' || r.company || ' (earlier email, no reply)' end;
    v_prio := case r.relationship_state when 'REPLIED' then 85 when 'MEETING' then 85 when 'FOLLOW_UP' then 70 when 'RECONNECT' then 65 else 45 end;
    if v_title is not null and not exists (select 1 from tasks tk where tk.opportunity_id = r.id and tk.created_by = 'HQ (Gmail history)'
                                             and tk.status in ('OPEN', 'IN_PROGRESS', 'WAITING')) then
      insert into tasks (company_id, contact_id, opportunity_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
      values (r.company_id, r.contact_id, r.id, v_title,
        'Found in NOYA Gmail history — not a cold prospect.' || E'\nThread: ' || coalesce(r.subject, '(no subject)')
        || E'\nNOYA emails: ' || r.outbound || ', their emails: ' || r.inbound
        || coalesce(E'\nLast sent: ' || to_char(r.last_outbound_at at time zone 'Africa/Cairo', 'DD Mon YYYY'), '')
        || coalesce(E'\nLast reply: ' || to_char(r.last_inbound_at at time zone 'Africa/Cairo', 'DD Mon YYYY'), '')
        || E'\nGmail thread: ' || r.gmail_thread_id,
        'OUTREACH_FOLLOW_UP', 'Adam', 'HQ (Gmail history)', v_prio, 'OPEN',
        ((current_date + 1)::timestamp + time '09:00') at time zone 'Africa/Cairo');
      v_tasks := v_tasks + 1;
    end if;
  end loop;
  return jsonb_build_object('opportunities_marked', v_marked, 'cold_approvals_held', v_held, 'cold_manual_parked', v_parked, 'tasks_created', v_tasks);
end $$;

-- Where the next run should read from. Creates the 12-month backfill cursor on first use.
create or replace function public.gmail_history_next(p_mailbox text, p_profile_history_id text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare s gmail_backfill_state%rowtype;
begin
  if p_mailbox is distinct from 'noya@noyaconcierge.com' then raise exception 'wrong mailbox %', p_mailbox; end if;
  insert into gmail_backfill_state (mailbox, window_start, history_id) values (p_mailbox, current_date - 365, p_profile_history_id)
  on conflict (mailbox) do nothing;
  select * into s from gmail_backfill_state where mailbox = p_mailbox;
  return jsonb_build_object('mode', s.mode, 'page_token', s.page_token, 'history_id', s.history_id,
    'q', 'after:' || to_char(s.window_start, 'YYYY/MM/DD') || ' -in:drafts -in:chats');
end $$;

-- Ingest one page of message metadata and advance the cursor, atomically.
create or replace function public.gmail_history_ingest(p_mailbox text, p_mode text, p_messages jsonb, p_next_page_token text,
  p_new_history_id text, p_scanned int, p_error text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare m jsonb; v_id text; v_labels text[]; v_from text; v_to text[]; v_cc text[]; v_dir text; v_cp text[]; v_dom text[]; v_reg text[];
  v_cat text; v_contact uuid; v_company uuid; v_opp uuid; v_method text; v_new boolean; v_threads text[] := '{}';
  v_keep boolean; n_new int := 0; n_dup int := 0; n_com int := 0; n_ign int := 0; v_rb jsonb; v_out jsonb; s gmail_backfill_state%rowtype;
begin
  if p_mailbox is distinct from 'noya@noyaconcierge.com' then raise exception 'wrong mailbox %', p_mailbox; end if;
  select * into s from gmail_backfill_state where mailbox = p_mailbox for update;
  if s.mailbox is null then return jsonb_build_object('ok', false, 'reason', 'NO_CURSOR'); end if;

  if p_mode = 'HISTORY_EXPIRED' then
    -- Gmail no longer has changes that old: re-scan a short window instead (still idempotent).
    update gmail_backfill_state set mode = 'BACKFILL', window_start = coalesce(last_run_at::date, current_date) - 3, page_token = null,
           history_id = p_new_history_id, last_run_at = now(), last_error = 'history expired; rescanning recent window' where mailbox = p_mailbox;
    return jsonb_build_object('ok', true, 'rescan', true);
  end if;

  for m in select * from jsonb_array_elements(coalesce(p_messages, '[]'::jsonb)) loop
    v_id := m->>'id';
    continue when v_id is null or coalesce(m->>'thread_id', '') = '' or coalesce(m->>'internal_date', '') = '';
    v_labels := array(select jsonb_array_elements_text(coalesce(m->'labels', '[]'::jsonb)));
    v_from := lower(nullif(btrim(m->>'from_email'), ''));
    v_to := array(select lower(e) from jsonb_array_elements_text(coalesce(m->'to', '[]'::jsonb)) e where e ~ '@');
    v_cc := array(select lower(e) from jsonb_array_elements_text(coalesce(m->'cc', '[]'::jsonb)) e where e ~ '@');
    v_dir := case when 'SENT' = any(v_labels) then 'OUTBOUND' else 'INBOUND' end;
    v_cp := case when v_dir = 'OUTBOUND'
                 then array(select distinct e from unnest(v_to || v_cc) e where e !~ '@noyaconcierge\.com$')
                 else array(select e from unnest(array[v_from]) e where e is not null and e !~ '@noyaconcierge\.com$') end;
    v_dom := array(select distinct split_part(e, '@', 2) from unnest(v_cp) e);
    v_cat := case
      when 'DRAFT' = any(v_labels) and not 'SENT' = any(v_labels) then 'IGNORED_DRAFT'
      when v_dir = 'INBOUND' and v_from ~ '@noyaconcierge\.com$' then 'IGNORED_NOT_SENT'
      when v_labels && array['SPAM', 'TRASH', 'CHAT'] then 'IGNORED_SPAM_TRASH'
      when v_dir = 'INBOUND' and v_labels && array['CATEGORY_PROMOTIONS', 'CATEGORY_SOCIAL'] then 'IGNORED_PROMOTIONAL'
      when v_dir = 'INBOUND' and v_labels && array['CATEGORY_FORUMS', 'CATEGORY_UPDATES'] then 'IGNORED_BULK_CATEGORY'
      -- Bulk markers apply to incoming mail only: Adam's own Gmail multi-send outreach carries List-Unsubscribe.
      when v_dir = 'INBOUND' and (coalesce(m->>'list_unsubscribe', '') <> '' or coalesce(m->>'list_id', '') <> '' or lower(coalesce(m->>'precedence', '')) in ('bulk', 'list', 'junk')) then 'IGNORED_BULK'
      when v_dir = 'INBOUND' and lower(coalesce(nullif(m->>'auto_submitted', ''), 'no')) <> 'no' then 'IGNORED_AUTOMATED'
      when v_dir = 'INBOUND' and split_part(coalesce(v_from, ''), '@', 1) ~ '^(no-?reply|do-?not-?reply|notifications?|notify|mailer-daemon|postmaster|bounces?|billing|invoices?|receipts?|alerts?|updates?|news|newsletters?|marketing|security|verify|verification|accounts?|team-noreply)' then 'IGNORED_AUTOMATED_SENDER'
      when cardinality(v_cp) = 0 then 'IGNORED_INTERNAL'
      when (select bool_and(email_is_platform(d)) from unnest(v_dom) d) then 'IGNORED_PLATFORM'
      else 'COMMERCIAL' end;

    -- Borderline incoming mail keeps its headers until its thread is judged (promoted if Adam wrote in the thread, cleared otherwise).
    v_keep := v_cat = 'COMMERCIAL' or (v_dir = 'INBOUND' and v_cat in ('IGNORED_BULK_CATEGORY', 'IGNORED_BULK', 'IGNORED_AUTOMATED_SENDER') and cardinality(v_cp) > 0);
    v_contact := null; v_company := null; v_opp := null; v_method := null;
    if v_cat = 'COMMERCIAL' then
      select k.id, k.company_id into v_contact, v_company from contacts k where lower(k.email) = any(v_cp)
       order by k.do_not_contact, k.updated_at desc limit 1;
      if v_contact is not null then v_method := 'CONTACT_EMAIL'; end if;
      if v_company is null then
        v_reg := array(select registrable_domain(d) from unnest(v_dom) d where not email_is_freemail(d));
        select c.id into v_company from companies c
         where coalesce(c.notes, '') not like '%MERGED_INTO:%' and c.website is not null and registrable_domain(c.website) = any(v_reg)
         order by c.updated_at desc limit 1;
        if v_company is not null and v_method is null then v_method := 'COMPANY_DOMAIN'; end if;
      end if;
      if v_contact is not null or v_company is not null then
        select o.id into v_opp from opportunities o
         where (v_contact is not null and o.contact_id = v_contact) or (v_company is not null and o.company_id = v_company)
         order by (o.status not in ('WON', 'LOST', 'ARCHIVED', 'LONG_TERM')) desc, o.updated_at desc limit 1;
      end if;
    end if;

    insert into gmail_history_messages (gmail_message_id, gmail_thread_id, mailbox, sent_at, direction, category, from_email, from_name,
        to_emails, cc_emails, counterpart_emails, counterpart_domains, subject, snippet, labels, contact_id, company_id, opportunity_id, match_method)
    values (v_id, m->>'thread_id', p_mailbox, to_timestamp((m->>'internal_date')::bigint / 1000.0), v_dir, v_cat,
        case when v_keep then v_from end, case when v_keep then left(m->>'from_name', 120) end,
        case when v_keep then v_to end, case when v_keep then v_cc end,
        case when v_keep then v_cp else '{}' end, case when v_keep then v_dom else '{}' end,
        case when v_keep then left(m->>'subject', 300) end, case when v_keep then left(m->>'snippet', 300) end,
        case when v_keep then v_labels end, v_contact, v_company, v_opp, v_method)
    -- Re-running is safe: an unchanged message is a no-op; a message whose classification changed
    -- (after a rule fix) is corrected in place. Never a second row.
    on conflict (gmail_message_id) do update set category = excluded.category, direction = excluded.direction, from_email = excluded.from_email,
        from_name = excluded.from_name, to_emails = excluded.to_emails, cc_emails = excluded.cc_emails, counterpart_emails = excluded.counterpart_emails,
        counterpart_domains = excluded.counterpart_domains, subject = excluded.subject, snippet = excluded.snippet, labels = excluded.labels,
        contact_id = excluded.contact_id, company_id = excluded.company_id, opportunity_id = excluded.opportunity_id, match_method = excluded.match_method, updated_at = now()
      where gmail_history_messages.category is distinct from excluded.category
    returning (xmax = 0) into v_new;
    if v_new is true then n_new := n_new + 1; else n_dup := n_dup + 1; end if;
    v_new := null;
    if v_cat = 'COMMERCIAL' then n_com := n_com + 1; else n_ign := n_ign + 1; end if;
    if v_keep then v_threads := v_threads || (m->>'thread_id'); end if;
  end loop;

  v_threads := array(select distinct unnest(v_threads));
  v_rb := gmail_history_rebuild(v_threads);
  v_out := gmail_history_apply_outreach();

  update gmail_backfill_state set
    pages = pages + 1, scanned = scanned + coalesce(p_scanned, 0), new_messages = new_messages + n_new, duplicates = duplicates + n_dup,
    commercial = commercial + n_com, ignored = ignored + n_ign, last_run_at = now(), last_error = p_error,
    mode = case when mode = 'BACKFILL' and p_next_page_token is null and p_error is null then 'INCREMENTAL' else mode end,
    backfill_done_at = case when mode = 'BACKFILL' and p_next_page_token is null and p_error is null then now() else backfill_done_at end,
    page_token = case when p_error is not null then page_token else p_next_page_token end,
    history_id = case when mode = 'INCREMENTAL' and p_next_page_token is null and p_error is null then coalesce(p_new_history_id, history_id) else history_id end,
    last_summary = jsonb_build_object('mode', mode, 'scanned', p_scanned, 'new', n_new, 'duplicates', n_dup, 'commercial', n_com, 'ignored', n_ign,
                                      'rebuild', v_rb, 'outreach', v_out, 'at', now())
  where mailbox = p_mailbox
  returning * into s;
  -- After the backfill, borderline mail in threads NOYA never wrote in is not kept.
  if s.mode = 'INCREMENTAL' then
    update gmail_history_messages m set from_email = null, from_name = null, to_emails = null, cc_emails = null, counterpart_emails = '{}',
           counterpart_domains = '{}', subject = null, snippet = null, labels = null, updated_at = now()
     where m.category like 'IGNORED%' and m.from_email is not null
       and not exists (select 1 from gmail_history_messages o where o.gmail_thread_id = m.gmail_thread_id and o.direction = 'OUTBOUND' and o.category = 'COMMERCIAL');
  end if;
  return jsonb_build_object('ok', true, 'mode', s.mode, 'new', n_new, 'duplicates', n_dup, 'commercial', n_com, 'ignored', n_ign,
    'more', s.page_token is not null, 'rebuild', v_rb, 'outreach', v_out);
end $$;

-- When a company or contact is added or corrected later, link it to the email history it already has.
create or replace function public.gmail_history_relink_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_threads text[];
begin
  if tg_table_name = 'companies' then
    if new.website is null or (tg_op = 'UPDATE' and registrable_domain(new.website) is not distinct from registrable_domain(old.website)) then return new; end if;
    update gmail_history_messages m set company_id = new.id, match_method = 'COMPANY_DOMAIN', updated_at = now()
     where m.category = 'COMMERCIAL' and m.company_id is null
       and exists (select 1 from unnest(m.counterpart_domains) d where not email_is_freemail(d) and registrable_domain(d) = registrable_domain(new.website));
  else
    if new.email is null or (tg_op = 'UPDATE' and lower(new.email) is not distinct from lower(old.email)) then return new; end if;
    update gmail_history_messages m set contact_id = new.id, company_id = coalesce(m.company_id, new.company_id), match_method = 'CONTACT_EMAIL', updated_at = now()
     where m.category = 'COMMERCIAL' and m.contact_id is null and lower(new.email) = any(m.counterpart_emails);
  end if;
  select array_agg(distinct gmail_thread_id) into v_threads from gmail_history_messages
   where updated_at > now() - interval '5 seconds' and (company_id = new.id or contact_id = new.id);
  if v_threads is not null then perform gmail_history_rebuild(v_threads); end if;
  return new;
end $$;
drop trigger if exists gmail_history_relink_company on public.companies;
create trigger gmail_history_relink_company after insert or update of website on public.companies
  for each row execute function public.gmail_history_relink_trigger();
drop trigger if exists gmail_history_relink_contact on public.contacts;
create trigger gmail_history_relink_contact after insert or update of email on public.contacts
  for each row execute function public.gmail_history_relink_trigger();

-- Outcome figures for the backfill test and HQ.
create or replace function public.gmail_history_report()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'state', (select to_jsonb(s) - 'page_token' from gmail_backfill_state s limit 1),
    'emails_scanned', (select coalesce(sum(scanned), 0) from gmail_backfill_state),
    'messages_stored', (select count(*) from gmail_history_messages),
    'commercial_messages', (select count(*) from gmail_history_messages where category = 'COMMERCIAL'),
    'ignored_by_reason', (select coalesce(jsonb_object_agg(category, n), '{}'::jsonb) from (select category, count(*) n from gmail_history_messages where category <> 'COMMERCIAL' group by 1) x),
    'commercial_threads', (select count(*) from gmail_history_threads where relevant),
    'threads_with_adam_sent', (select count(*) from gmail_history_threads where outbound > 0),
    'sent_emails_recorded', (select count(*) from gmail_history_messages where direction = 'OUTBOUND' and interaction_id is not null),
    'contacts_matched', (select count(distinct contact_id) from gmail_history_messages where contact_id is not null),
    'companies_matched', (select count(distinct company_id) from gmail_history_messages where company_id is not null),
    'relationships_recovered', (select count(distinct coalesce(company_id::text, contact_id::text)) from gmail_history_threads where relevant and outbound > 0 and (company_id is not null or contact_id is not null)),
    'unmatched_relationships', (select count(distinct counterpart_domains[1]) from gmail_history_threads where relevant and outbound > 0 and inbound > 0 and company_id is null and contact_id is null),
    'interactions_from_gmail', (select count(*) from gmail_history_messages where interaction_id is not null),
    'cold_outreach_suppressed', (select count(*) from approval_queue_state where decided_by = 'SYSTEM (Gmail history)'),
    'opportunities_with_prior_relationship', (select count(*) from opportunities where prior_relationship is not null),
    'reactivation_candidates', (select count(*) from gmail_history_threads where relevant and inbound > 0 and outbound > 0 and relationship_state in ('RECONNECT', 'FOLLOW_UP', 'LONG_TERM') and coalesce(hq_status, '') <> 'DISMISSED'),
    'states', (select coalesce(jsonb_object_agg(relationship_state, n), '{}'::jsonb) from (select relationship_state, count(*) n from gmail_history_threads where relevant group by 1) x))
$$;

revoke all on function public.gmail_history_rebuild(text[]) from public, anon, authenticated;
revoke all on function public.gmail_history_apply_outreach() from public, anon, authenticated;
revoke all on function public.gmail_history_next(text, text) from public, anon, authenticated;
revoke all on function public.gmail_history_ingest(text, text, jsonb, text, text, int, text) from public, anon, authenticated;
revoke all on function public.gmail_history_report() from public, anon, authenticated;
revoke all on function public.gmail_history_relink_trigger() from public, anon, authenticated;
grant execute on function public.gmail_history_next(text, text) to service_role;
grant execute on function public.gmail_history_ingest(text, text, jsonb, text, text, int, text) to service_role;
grant execute on function public.gmail_history_report() to service_role;

-- Applied live after the first backfill (30 Sep): delivery-failure notices that had been promoted as
-- replies were reclassified. Kept here so a fresh database reproduces the same data rules.
update gmail_history_messages set category = 'IGNORED_BOUNCE', interaction_id = null, company_id = null, contact_id = null, opportunity_id = null, updated_at = now()
 where direction = 'INBOUND' and split_part(coalesce(from_email, ''), '@', 1) ~ '^(mailer-daemon|postmaster|bounces?|no-?reply|do-?not-?reply)'
   and category <> 'IGNORED_BOUNCE';
