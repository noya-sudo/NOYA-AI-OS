-- NOYA Studio operating mode (17 Oct 2026). Adam: "The purpose of Studio is not document volume. The purpose is conversion into
-- real projects and revenue." Three output levels (1 email idea, 2 one-page concept, 3 full brief / proposal), and every output
-- that goes to a company is tracked: sent → reply → meeting → proposal → won project. Steps are filled from evidence only
-- (the NOYA mailbox import, CRM interactions, meeting tasks, opportunities, projects); nothing is estimated. Nothing sends from here.

-- Documents carry their level and, when prepared ahead of the relationship, why they are held.
alter table public.studio_documents drop constraint if exists studio_documents_doc_type_check;
alter table public.studio_documents add constraint studio_documents_doc_type_check
  check (doc_type in ('OPPORTUNITY_NOTE', 'EMAIL_IDEA', 'ONE_PAGE_CONCEPT', 'CONCEPT', 'BRIEF', 'PROPOSAL', 'PROJECT', 'ITINERARY', 'OPS_ITINERARY', 'DESK_BRIEF', 'PARTNER_DECK'));
alter table public.studio_documents add column if not exists level smallint check (level between 0 and 3);
alter table public.studio_documents add column if not exists hold_reason text;

-- One row per Studio output prepared for a company: the email (Level 1 idea, or the cover note) and its attachment.
create table if not exists public.studio_outputs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  opportunity_id uuid references public.opportunities(id),
  case_slug text not null,
  level smallint not null check (level between 1 and 3),
  email_slug text,
  document_slug text,
  channel text not null default 'EMAIL' check (channel in ('EMAIL', 'LINKEDIN', 'IN_PERSON')),
  recipients text[] not null default '{}',
  gmail_draft_id text,
  gmail_thread_id text,
  status text not null default 'PREPARED' check (status in ('PREPARED', 'HELD', 'SENT', 'CANCELLED')),
  hold_reason text,
  send_after date,
  prepared_at timestamptz not null default now(),
  sent_at timestamptz,
  reply_at timestamptz,
  meeting_at timestamptz,
  proposal_at timestamptz,
  won_at timestamptz,
  project_id uuid references public.projects(id),
  evidence jsonb not null default '{}'::jsonb,
  notes text,
  updated_at timestamptz not null default now()
);
create unique index if not exists studio_outputs_unit_idx on public.studio_outputs (case_slug, coalesce(email_slug, ''), coalesce(document_slug, ''));
create index if not exists studio_outputs_company_idx on public.studio_outputs (company_id);
alter table public.studio_outputs enable row level security;
revoke all on table public.studio_outputs from public, anon, authenticated;
comment on table public.studio_outputs is 'NOYA Studio outputs sent (or to be sent) to a company, with the conversion steps sent, reply, meeting, proposal and won filled from evidence. Adam sends; nothing sends from here.';

-- Fill each step from evidence. Sent: an outbound message from the NOYA mailbox in the output's thread (or to the company) after
-- it was prepared. Reply: the company's first inbound message after that. Meeting: a recorded meeting, a meeting task or a thread
-- at meeting stage, after the send. Proposal: a Studio proposal marked SENT, or a proposal value recorded on the opportunity.
-- Won: the opportunity's won date, and its project. A step once filled is never cleared.
create or replace function public.studio_outputs_refresh()
returns integer
language plpgsql
set search_path = public
as $$
declare n integer := 0; k integer;
begin
  with m as (
    select o.id, x.sent_at, x.gmail_message_id, x.gmail_thread_id from studio_outputs o
     cross join lateral (select g.sent_at, g.gmail_message_id, g.gmail_thread_id from gmail_history_messages g
                          where g.direction = 'OUTBOUND' and g.sent_at >= o.prepared_at
                            and (g.labels is null or 'SENT' = any(g.labels)) and not coalesce('DRAFT' = any(g.labels), false)
                            and (case when o.gmail_thread_id is not null then g.gmail_thread_id = o.gmail_thread_id else g.company_id = o.company_id end)
                          order by g.sent_at limit 1) x
     where o.sent_at is null and o.status in ('PREPARED', 'HELD'))
  update studio_outputs o set sent_at = m.sent_at, status = 'SENT', updated_at = now(),
         evidence = o.evidence || jsonb_build_object('sent', jsonb_build_object('gmail_message_id', m.gmail_message_id, 'thread', m.gmail_thread_id))
    from m where m.id = o.id;
  get diagnostics k = row_count; n := n + k;

  with m as (
    select o.id, x.sent_at, x.gmail_message_id, x.from_email from studio_outputs o
     cross join lateral (select g.sent_at, g.gmail_message_id, g.from_email from gmail_history_messages g
                          where g.direction = 'INBOUND' and g.sent_at > o.sent_at
                            and (g.company_id = o.company_id or (o.gmail_thread_id is not null and g.gmail_thread_id = o.gmail_thread_id))
                          order by g.sent_at limit 1) x
     where o.reply_at is null and o.sent_at is not null)
  update studio_outputs o set reply_at = m.sent_at, updated_at = now(),
         evidence = o.evidence || jsonb_build_object('reply', jsonb_build_object('gmail_message_id', m.gmail_message_id, 'from', m.from_email))
    from m where m.id = o.id;
  get diagnostics k = row_count; n := n + k;

  with m as (
    select o.id, x.at_, x.src from studio_outputs o
     cross join lateral (select * from (
            select i.occurred_at at_, jsonb_build_object('interaction', i.id) src from interactions i
             where i.company_id = o.company_id and i.channel = 'MEETING' and i.occurred_at > o.sent_at
            union all
            select t.created_at, jsonb_build_object('task', t.id) from tasks t
             where t.company_id = o.company_id and (t.task_type = 'MEETING_ACTION' or t.title like 'MEETING --%') and t.created_at > o.sent_at
            union all
            select ht.last_inbound_at, jsonb_build_object('thread', ht.gmail_thread_id) from gmail_history_threads ht
             where ht.company_id = o.company_id and ht.relationship_state = 'MEETING' and ht.last_inbound_at > o.sent_at) y
          order by at_ limit 1) x
     where o.meeting_at is null and o.sent_at is not null)
  update studio_outputs o set meeting_at = m.at_, updated_at = now(), evidence = o.evidence || jsonb_build_object('meeting', m.src)
    from m where m.id = o.id;
  get diagnostics k = row_count; n := n + k;

  with m as (
    select o.id, x.at_, x.src from studio_outputs o
     cross join lateral (select * from (
            select d.sent_at at_, jsonb_build_object('studio_document', d.slug, 'version', d.version) src from studio_documents d
             where d.company_id = o.company_id and d.doc_type = 'PROPOSAL' and d.status = 'SENT' and d.sent_at >= o.sent_at
            union all
            select op.updated_at, jsonb_build_object('opportunity_proposal_value', op.proposal_value) from opportunities op
             where op.id = o.opportunity_id and op.proposal_value is not null and op.updated_at >= o.sent_at) y
          order by at_ limit 1) x
     where o.proposal_at is null and o.sent_at is not null)
  update studio_outputs o set proposal_at = m.at_, updated_at = now(), evidence = o.evidence || jsonb_build_object('proposal', m.src)
    from m where m.id = o.id;
  get diagnostics k = row_count; n := n + k;

  update studio_outputs o set won_at = op.won_at, updated_at = now(),
         project_id = coalesce(o.project_id, (select p.id from projects p where p.opportunity_id = op.id order by p.created_at limit 1)),
         evidence = o.evidence || jsonb_build_object('won', jsonb_build_object('opportunity', op.id, 'contracted_value', op.contracted_value))
    from opportunities op
   where op.id = o.opportunity_id and o.won_at is null and o.sent_at is not null and op.won_at is not null and op.won_at >= o.sent_at;
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.studio_outputs_refresh() from public, anon, authenticated;

-- Every output, where it stands, and what happens next.
create or replace view public.studio_output_status with (security_invoker = true) as
select o.id, c.name as company, o.case_slug, o.level,
       case o.level when 1 then 'Email idea' when 2 then 'One-page concept' else 'Full brief / proposal' end as level_label,
       o.document_slug, o.status, o.send_after, o.hold_reason, o.prepared_at, o.sent_at, o.reply_at, o.meeting_at, o.proposal_at, o.won_at,
       case when o.won_at is not null then 'Won'
            when o.proposal_at is not null then 'Proposal out: follow up'
            when o.meeting_at is not null then 'Meeting held: Level 3 brief or proposal'
            when o.reply_at is not null then 'Replied: answer and move to a meeting'
            when o.sent_at is not null then 'Sent: wait for a reply'
            when o.status = 'HELD' then 'Held: ' || coalesce(o.hold_reason, 'not yet')
            when o.status = 'PREPARED' and o.send_after > current_date then 'Draft ready: send on ' || to_char(o.send_after, 'DD Mon')
            when o.status = 'PREPARED' then 'Draft ready: Adam to send'
            else o.status end as next_step,
       op.contracted_value as won_value_recorded, o.gmail_draft_id, o.gmail_thread_id
  from studio_outputs o join companies c on c.id = o.company_id left join opportunities op on op.id = o.opportunity_id;
revoke all on public.studio_output_status from public, anon, authenticated;

-- The funnel by level: what Studio produced and what it turned into. Value counts only contracted values recorded on won work.
create or replace view public.studio_conversion with (security_invoker = true) as
select o.level,
       count(*) filter (where o.status <> 'CANCELLED') as outputs,
       count(*) filter (where o.status = 'HELD') as held,
       count(o.sent_at) as sent, count(o.reply_at) as replied, count(o.meeting_at) as meetings,
       count(o.proposal_at) as proposals, count(o.won_at) as won,
       sum(op.contracted_value) filter (where o.won_at is not null) as won_value_recorded
  from studio_outputs o left join opportunities op on op.id = o.opportunity_id
 group by o.level;
revoke all on public.studio_conversion from public, anon, authenticated;

-- Operating queue: companies that have warmed (a reply or a meeting in the last 30 days) with no Studio output since, and the
-- level they have earned. This is where the masters are used next.
create or replace view public.studio_queue with (security_invoker = true) as
with warm as (
  select ht.company_id, max(ht.last_inbound_at) as warmed_at,
         bool_or(ht.relationship_state = 'MEETING') as meeting
    from gmail_history_threads ht
   where ht.company_id is not null and ht.relationship_state in ('REPLIED', 'MEETING') and ht.last_inbound_at > now() - interval '30 days'
   group by ht.company_id
  union all
  select op.company_id, op.updated_at, true from opportunities op
   where op.status = 'CALL_REQUIRED' and op.company_id is not null and op.updated_at > now() - interval '30 days'
)
select c.id as company_id, c.name as company, c.acquisition_lane as lane, max(w.warmed_at) as warmed_at,
       case when bool_or(w.meeting) then 3 else 2 end as earned_level,
       case when bool_or(w.meeting) then 'Meeting: Level 3 brief (proposal once they brief)' else 'Reply: Level 2 one-page concept' end as next_output
  from warm w join companies c on c.id = w.company_id
 where not exists (select 1 from studio_outputs o where o.company_id = c.id and o.prepared_at >= w.warmed_at - interval '1 day')
   and not exists (select 1 from opportunities op where op.company_id = c.id and op.status in ('LOST', 'ARCHIVED'))
 group by c.id, c.name, c.acquisition_lane;
revoke all on public.studio_queue from public, anon, authenticated;

-- Steps fill themselves from the mailbox import every 30 minutes.
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'studio-outputs-refresh';
    perform cron.schedule('studio-outputs-refresh', '7,37 * * * *', $c$select public.studio_outputs_refresh()$c$);
  end if;
end $$;
