-- Past relationships become an actionable review layer.
-- * Adam's own status per relationship: REPLY_NOW / RECONNECT / FOLLOW_UP_LATER / LONG_TERM /
--   EXISTING_PARTNER / CLIENT / NOT_RELEVANT. Setting a status never contacts anyone; it can only
--   book an internal task (reply now, follow up later) and mark a CRM company as client / partner.
-- * A system suggestion kept separate from Adam's decision.
-- * Optional AI summary (workflow 16) built only from the metadata already imported (subject, date,
--   direction, sender name and Gmail's preview). Stored apart from facts, with its model and basis;
--   the Gmail thread stays the evidence.

-- One key per relationship group (same rule as hq_relationships).
create or replace view public.gmail_thread_groups
with (security_invoker = true) as
select t.gmail_thread_id,
       coalesce('co:' || t.company_id::text, 'ct:' || t.contact_id::text,
                case when cardinality(t.counterpart_domains) > 0 and not email_is_freemail(t.counterpart_domains[1]) then 'd:' || registrable_domain(t.counterpart_domains[1]) end,
                'e:' || t.counterpart_emails[1]) as gkey
  from gmail_history_threads t where t.relevant and t.outbound > 0;
revoke all on public.gmail_thread_groups from anon, authenticated;

create table if not exists public.relationship_reviews (
  key text primary key,
  status text check (status in ('REPLY_NOW', 'RECONNECT', 'FOLLOW_UP_LATER', 'LONG_TERM', 'EXISTING_PARTNER', 'CLIENT', 'NOT_RELEVANT')),
  status_by text,
  status_at timestamptz,
  task_id uuid,
  suggested_status text check (suggested_status in ('REPLY_NOW', 'RECONNECT', 'FOLLOW_UP_LATER', 'LONG_TERM', 'EXISTING_PARTNER', 'CLIENT', 'NOT_RELEVANT')),
  suggested_reason text,
  summary text,            -- AI: what the exchange was about (from subjects + previews only)
  their_position text,     -- AI: what they said / asked, from previews only
  summary_model text,
  summary_at timestamptz,
  summary_basis jsonb,     -- threads, message count and last message used
  updated_at timestamptz not null default now()
);
alter table public.relationship_reviews enable row level security;
revoke all on public.relationship_reviews from anon, authenticated;

-- Rule-based suggestion (used until / unless the AI suggests otherwise).
create or replace function public.relationship_rule_status(p_state text, p_rel text)
returns text language sql immutable as $$
  select case
    when p_rel = 'client' then 'CLIENT'
    when p_rel = 'partner' then 'EXISTING_PARTNER'
    when p_state in ('REPLIED', 'MEETING') then 'REPLY_NOW'
    when p_state = 'RECONNECT' then 'RECONNECT'
    when p_state in ('FOLLOW_UP', 'WAIT') then 'FOLLOW_UP_LATER'
    when p_state = 'DO_NOT_CONTACT' then 'NOT_RELEVANT'
    else 'LONG_TERM' end
$$;

-- Queue for workflow 16: two-way relationships whose summary is missing or older than the last email.
-- Priority: they wrote last first, then the strongest reconnects (most replies, most recent).
create or replace function public.relationship_summary_queue(p_limit int default 12)
returns jsonb language sql stable security definer set search_path = public as $$
  with g as (
    select k.gkey, array_agg(t.gmail_thread_id) threads, sum(t.outbound) sent, sum(t.inbound) received, max(t.last_at) last_at,
           max(t.last_inbound_at) last_in, max(t.last_outbound_at) last_out,
           (array_agg(t.company_id::text) filter (where t.company_id is not null))[1]::uuid company_id,
           bool_and(coalesce(t.hq_status, '') = 'DISMISSED') dismissed
      from gmail_thread_groups k join gmail_history_threads t using (gmail_thread_id)
     group by k.gkey
  )
  select coalesce(jsonb_agg(x order by x.pri, x.received desc, x.last_at desc), '[]'::jsonb) from (
    select g.gkey as key, g.sent, g.received, g.last_at,
           case when g.last_in > coalesce(g.last_out, '-infinity') and g.last_in > now() - interval '60 days' then 0 else 1 end as pri,
           (select c.name from companies c where c.id = g.company_id) as company,
           (select registrable_domain(d) from gmail_history_threads x, unnest(x.counterpart_domains) d where x.gmail_thread_id = g.threads[1] limit 1) as domain,
           (select jsonb_agg(jsonb_build_object('dir', m.direction, 'date', to_char(m.sent_at at time zone 'Africa/Cairo', 'YYYY-MM-DD'),
                    'from', case when m.direction = 'INBOUND' then m.from_name end, 'subject', m.subject,
                    'preview', replace(replace(replace(m.snippet, '&#39;', ''''), '&quot;', '"'), '&amp;', '&')) order by m.sent_at)
              from (select * from gmail_history_messages m where m.gmail_thread_id = any(g.threads) and m.category = 'COMMERCIAL'
                     order by m.sent_at desc limit 12) m) as messages,
           g.threads
      from g left join relationship_reviews r on r.key = g.gkey
     where g.received > 0 and not g.dismissed and (r.summary_at is null or r.summary_at < g.last_at)
     order by pri, received desc, last_at desc limit greatest(1, least(coalesce(p_limit, 12), 50))
  ) x
$$;

create or replace function public.relationship_summary_save(p_key text, p_summary text, p_position text, p_suggested text, p_reason text,
  p_model text, p_basis jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_last_in timestamptz; v_last_out timestamptz; v_sent int; v_recv int; v_last timestamptz; v_rule text; v_rel text;
begin
  if p_suggested is not null and p_suggested not in ('REPLY_NOW', 'RECONNECT', 'FOLLOW_UP_LATER', 'LONG_TERM', 'EXISTING_PARTNER', 'CLIENT', 'NOT_RELEVANT') then
    p_suggested := null;
  end if;
  -- Facts outrank the model: "reply now" only when they genuinely wrote last within 60 days;
  -- "client" only when the CRM already records them as a client.
  select max(t.last_inbound_at), max(t.last_outbound_at), sum(t.outbound), sum(t.inbound), max(t.last_at),
         (select c.relationship_status from companies c where c.id = (array_agg(t.company_id::text) filter (where t.company_id is not null))[1]::uuid)
    into v_last_in, v_last_out, v_sent, v_recv, v_last, v_rel
    from gmail_thread_groups g join gmail_history_threads t using (gmail_thread_id) where g.gkey = p_key;
  v_rule := relationship_rule_status(gmail_relationship_state(v_sent, v_recv, case when v_last_in > coalesce(v_last_out, '-infinity') then 'INBOUND' else 'OUTBOUND' end,
                                                             v_last_out, v_last_in, v_last), v_rel);
  if p_suggested = 'REPLY_NOW' and not (v_last_in > coalesce(v_last_out, '-infinity') and v_last_in > now() - interval '60 days') then
    p_reason := 'Adjusted to the facts (' || case when v_last_in > coalesce(v_last_out, '-infinity') then 'their last email is over 60 days old' else 'NOYA sent the last email' end || '). AI said: ' || coalesce(p_reason, '');
    p_suggested := case when v_rule = 'REPLY_NOW' then 'RECONNECT' else v_rule end;
  elsif p_suggested = 'CLIENT' and coalesce(v_rel, '') <> 'client' then
    p_reason := 'Not recorded as a client in the CRM; shown as partner/supplier. AI said: ' || coalesce(p_reason, '');
    p_suggested := 'EXISTING_PARTNER';
  end if;
  insert into relationship_reviews (key, summary, their_position, suggested_status, suggested_reason, summary_model, summary_at, summary_basis)
  values (p_key, left(nullif(btrim(p_summary), ''), 600), left(nullif(btrim(p_position), ''), 400), p_suggested, left(nullif(btrim(p_reason), ''), 300),
          p_model, now(), p_basis)
  on conflict (key) do update set summary = excluded.summary, their_position = excluded.their_position,
     suggested_status = coalesce(excluded.suggested_status, relationship_reviews.suggested_status),
     suggested_reason = coalesce(excluded.suggested_reason, relationship_reviews.suggested_reason),
     summary_model = excluded.summary_model, summary_at = now(), summary_basis = excluded.summary_basis, updated_at = now();
  return jsonb_build_object('ok', true, 'suggested', p_suggested);
end $$;

revoke all on function public.relationship_summary_queue(int) from public, anon, authenticated;
revoke all on function public.relationship_summary_save(text, text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.relationship_summary_queue(int) to service_role;
grant execute on function public.relationship_summary_save(text, text, text, text, text, text, jsonb) to service_role;

-- Adam sets a status. Internal effects only; never a message.
create or replace function public.hq_relationship_status(p_key text, p_status text, p_label text default null, p_follow_up date default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_st text := upper(p_status); v_threads text[]; v_co uuid; v_ct uuid; v_old relationship_reviews%rowtype;
  v_task uuid; v_last_thread text; v_label text := coalesce(nullif(btrim(p_label), ''), substr(p_key, 3));
begin
  if v_st not in ('REPLY_NOW', 'RECONNECT', 'FOLLOW_UP_LATER', 'LONG_TERM', 'EXISTING_PARTNER', 'CLIENT', 'NOT_RELEVANT') then
    return jsonb_build_object('ok', false, 'reason', 'INVALID_STATUS');
  end if;
  select array_agg(g.gmail_thread_id) into v_threads from gmail_thread_groups g where g.gkey = p_key;
  if v_threads is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  select (array_agg(company_id::text) filter (where company_id is not null))[1]::uuid, (array_agg(contact_id::text) filter (where contact_id is not null))[1]::uuid,
         (array_agg(gmail_thread_id order by last_at desc))[1]
    into v_co, v_ct, v_last_thread from gmail_history_threads where gmail_thread_id = any(v_threads);
  select * into v_old from relationship_reviews where key = p_key;

  -- A changed decision closes the task the previous one booked.
  if v_old.task_id is not null then
    update tasks set status = 'CANCELLED', description = coalesce(description, '') || E'\n\nClosed in HQ: relationship status changed to ' || v_st
     where id = v_old.task_id and status in ('OPEN', 'IN_PROGRESS', 'WAITING');
  end if;

  update gmail_history_threads set hq_status = case when v_st = 'NOT_RELEVANT' then 'DISMISSED'
                                                    when hq_status = 'DISMISSED' then null else hq_status end, updated_at = now()
   where gmail_thread_id = any(v_threads);

  if v_st in ('REPLY_NOW', 'FOLLOW_UP_LATER', 'RECONNECT') then
    insert into tasks (company_id, contact_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
    values (v_co, v_ct,
      case v_st when 'REPLY_NOW' then 'REPLY NOW -- ' when 'RECONNECT' then 'RECONNECT -- ' else 'FOLLOW UP -- ' end || v_label || ' (past relationship)',
      'Set in HQ Past relationships by ' || v_admin || '. Nothing has been sent.' || E'\nGmail thread: ' || v_last_thread,
      'OUTREACH_FOLLOW_UP', 'Adam', 'HQ (Past relationships)',
      case v_st when 'REPLY_NOW' then 85 when 'RECONNECT' then 65 else 55 end, 'OPEN',
      case v_st when 'REPLY_NOW' then now()
                when 'RECONNECT' then ((current_date + 2)::timestamp + time '09:00') at time zone 'Africa/Cairo'
                else ((coalesce(p_follow_up, current_date + 14))::timestamp + time '09:00') at time zone 'Africa/Cairo' end)
    returning id into v_task;
  end if;

  if v_co is not null and v_st in ('EXISTING_PARTNER', 'CLIENT') then
    update companies set relationship_status = case v_st when 'CLIENT' then 'client' else 'partner' end, updated_at = now() where id = v_co;
  end if;

  insert into relationship_reviews (key, status, status_by, status_at, task_id)
  values (p_key, v_st, v_admin, now(), v_task)
  on conflict (key) do update set status = excluded.status, status_by = excluded.status_by, status_at = now(), task_id = excluded.task_id, updated_at = now();
  perform hq_audit('RELATIONSHIP_STATUS', null, jsonb_build_object('key', p_key, 'from', v_old.status, 'to', v_st, 'task_id', v_task, 'company_id', v_co));
  return jsonb_build_object('ok', true, 'task_id', v_task);
end $$;
revoke all on function public.hq_relationship_status(text, text, text, date) from public, anon;
grant execute on function public.hq_relationship_status(text, text, text, date) to authenticated;

-- Adding a group to the CRM changes its key (domain → company): carry the review across.
create or replace function public.relationship_review_rekey(p_old text, p_new text)
returns void language sql volatile security definer set search_path = public as $$
  insert into relationship_reviews (key, status, status_by, status_at, task_id, suggested_status, suggested_reason, summary, their_position,
                                    summary_model, summary_at, summary_basis)
  select p_new, status, status_by, status_at, task_id, suggested_status, suggested_reason, summary, their_position, summary_model, summary_at, summary_basis
    from relationship_reviews where key = p_old and p_old <> p_new
  on conflict (key) do nothing;
$$;
revoke all on function public.relationship_review_rekey(text, text) from public, anon, authenticated;

do $$
declare d text;
begin
  -- hq_relationships: add the review (Adam status, suggestion, AI summary) to each group.
  d := pg_get_functiondef('public.hq_relationships()'::regprocedure);
  d := replace(d, $x$        'opportunity_status', (select o.status from opportunities o where o.id = g.opportunity_id))$x$,
                  $x$        'opportunity_status', (select o.status from opportunities o where o.id = g.opportunity_id),
        'relationship', c.relationship_status,
        'review', (select jsonb_build_object('status', r.status, 'status_at', r.status_at, 'suggested', r.suggested_status, 'suggested_reason', r.suggested_reason,
                     'summary', r.summary, 'their_position', r.their_position, 'summary_at', r.summary_at, 'summary_model', r.summary_model)
                     from relationship_reviews r where r.key = g.gkey),
        'rule_status', relationship_rule_status(case when g.dnc then 'DO_NOT_CONTACT' when g.meeting then 'MEETING'
                      else gmail_relationship_state(g.sent::int, g.received::int, case when g.last_in > coalesce(g.last_out, '-infinity') then 'INBOUND' else 'OUTBOUND' end,
                                                    g.last_out, g.last_in, g.last_at) end, c.relationship_status))$x$);
  if d not like '%relationship_rule_status(%' then raise exception 'hq_relationships patch failed'; end if;
  execute d;

  -- hq_history_action: keep the review when a group moves into the CRM.
  d := pg_get_functiondef('public.hq_history_action(text,text,text,text,text,text,text,text)'::regprocedure);
  d := replace(d, $x$  update gmail_history_threads set hq_status = 'ADDED_TO_CRM' where gmail_thread_id = any(v_threads);$x$,
                  $x$  update gmail_history_threads set hq_status = 'ADDED_TO_CRM' where gmail_thread_id = any(v_threads);
  perform relationship_review_rekey(p_key, coalesce('co:' || v_co::text, 'ct:' || v_ct::text));$x$);
  if d not like '%relationship_review_rekey%' then raise exception 'hq_history_action patch failed'; end if;
  execute d;
end $$;
