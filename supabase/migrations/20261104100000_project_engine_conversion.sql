-- Project engine conversion (4 Nov 2026). Applied live in five parts; each part is idempotent.
-- 1. Follow-up tiers: the 73 open follow-ups are ranked HOT / WARM / STRATEGIC / NORMAL / LOW_VALUE / CLOSE_HOLD, not by date alone.
-- 2. Contact gate: Today's five and Next 20 rank only verified email routes or LinkedIn-ready people (an official inbox that is
--    not verified waits under Outreach > Official inbox until Adam approves using it); at most one item per Director in
--    Today's five and four in Next 20; an internal opportunity brief counts as project evidence.
-- 3. Ready pool = verified routes only; official / self-published inboxes are counted as CONTACT_READY.
-- 4. Studio shows the internal opportunity brief (studio_documents OPPORTUNITY_NOTE, content.brief).
-- 5. Director scorecards carry each Director's top 3 live project opportunities (from those briefs).

-- 1 ----------------------------------------------------------------------------------------------------------------------------
create or replace function public.follow_up_tier(p_task uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t tasks%rowtype; c companies%rowtype; v_in int; v_last_in timestamptz; v_last_out timestamptz; v_out_since int;
        v_close text; v_pg numeric; v_brief boolean; v_meet boolean;
  function_tier text; function_why text;
begin
  select * into t from tasks where id = p_task;
  if t.company_id is null then return jsonb_build_object('tier', 'NORMAL', 'rank', 4, 'why', 'No company on record'); end if;
  select * into c from companies where id = t.company_id;
  select count(*), max(occurred_at) into v_in, v_last_in from interactions
   where company_id = t.company_id and direction = 'INBOUND' and channel <> 'WEBSITE';
  select max(occurred_at) into v_last_out from interactions where company_id = t.company_id and direction = 'OUTBOUND';
  select count(*) into v_out_since from interactions
   where company_id = t.company_id and direction = 'OUTBOUND' and occurred_at > coalesce(v_last_in, '-infinity'::timestamptz);
  select m.outcome into v_close from commercial_next_moves m
   where m.rel_key = 'co:' || t.company_id and m.action in ('CLOSE', 'HOLD') and m.status in ('CLOSED', 'PROPOSED', 'CHOSEN')
   order by m.updated_at desc limit 1;
  select max((o.egypt->'scores'->>'project_generation')::numeric) into v_pg from opportunities o where o.company_id = t.company_id;
  v_brief := exists (select 1 from studio_documents d where d.company_id = t.company_id and d.doc_type = 'OPPORTUNITY_NOTE'
                       and d.status <> 'SUPERSEDED' and d.content ? 'brief');
  v_meet := exists (select 1 from interactions i join gmail_sync_ledger l on l.gmail_message_id = i.external_message_id
                     where i.company_id = t.company_id and l.classification = 'MEETING_REQUEST' and i.occurred_at > now() - interval '60 days');

  if coalesce(c.outreach_hold_until, '-infinity'::timestamptz) > now() then
    function_tier := 'CLOSE_HOLD'; function_why := 'On hold until ' || to_char(c.outreach_hold_until, 'DD Mon') || coalesce(': ' || c.outreach_hold_reason, '');
  elsif v_close is not null then
    function_tier := 'CLOSE_HOLD'; function_why := 'Closed: ' || v_close;
  elsif v_out_since >= 3 then
    function_tier := 'CLOSE_HOLD'; function_why := v_out_since || ' NOYA messages without a reply: stop chasing';
  elsif v_meet then
    function_tier := 'HOT'; function_why := 'Asked for a meeting';
  elsif v_last_in is not null and v_last_in > coalesce(v_last_out, '-infinity'::timestamptz) then
    function_tier := 'HOT'; function_why := 'They wrote last (' || to_char(v_last_in, 'DD Mon') || '): the reply is owed';
  elsif v_in > 0 and v_last_in > now() - interval '180 days' then
    function_tier := 'WARM'; function_why := 'Replied on ' || to_char(v_last_in, 'DD Mon') || '; ' || v_out_since || ' NOYA message(s) since';
  elsif c.commercial_class in ('SUPPLIER', 'NOT_RELEVANT', 'COMPETITOR')
     or (coalesce(c.commercial_class, '') not in ('BUYER', 'DISTRIBUTION_PARTNER')
         and coalesce(c.company_type, '') ~* '(hotel|resort|aviation|serviced|villa operator|hospitality group|luxury_concierge)') then
    function_tier := 'LOW_VALUE'; function_why := 'Supplier, venue or competitor rather than a project buyer';
  elsif v_brief or coalesce(v_pg, 0) >= 4 then
    function_tier := 'STRATEGIC';
    function_why := case when v_brief then 'Internal opportunity brief on file' else 'Strong project generator (Egypt score ' || v_pg || '/5)' end;
  else
    function_tier := 'NORMAL'; function_why := 'Cold email, no reply yet';
  end if;
  return jsonb_build_object('tier', function_tier, 'why', function_why,
    'rank', case function_tier when 'HOT' then 1 when 'WARM' then 2 when 'STRATEGIC' then 3 when 'NORMAL' then 4 when 'LOW_VALUE' then 5 else 6 end);
end $$;
revoke all on function public.follow_up_tier(uuid) from public, anon, authenticated;

do $patch$
declare src text := pg_get_functiondef('public.outreach_desk()'::regprocedure);
  a1 text := $a$    select t.*, co.name company, k.first_name, k.last_name, k.position,
           agent_key_of(company_lane(co.acquisition_lane, co.prospect_segment, co.vertical_override, co.company_type), co.company_type, co.notes) director
      from tasks t left join companies co on co.id = t.company_id left join contacts k on k.id = t.contact_id
     where t.task_type = 'OUTREACH_FOLLOW_UP'$a$;
  b1 text := $a$    select t.*, follow_up_tier(t.id) tr, co.name company, k.first_name, k.last_name, k.position,
           agent_key_of(company_lane(co.acquisition_lane, co.prospect_segment, co.vertical_override, co.company_type), co.company_type, co.notes) director
      from tasks t left join companies co on co.id = t.company_id left join contacts k on k.id = t.contact_id
     where t.task_type = 'OUTREACH_FOLLOW_UP'$a$;
  a2 text := $a$'thread_id', substring(f.description from 'Gmail thread: ([0-9a-f]+)'))
          order by f.due_at nulls last) from fu f), '[]') followups,$a$;
  b2 text := $a$'thread_id', substring(f.description from 'Gmail thread: ([0-9a-f]+)'), 'tier', f.tr->>'tier', 'tier_why', f.tr->>'why')
          order by (f.tr->>'rank')::int, f.due_at nulls last) from fu f), '[]') followups,$a$;
  a3 text := $a$      'followups', jsonb_array_length(l.followups),$a$;
  b3 text := $a$      'followups', jsonb_array_length(l.followups),
      'followups_top', (select count(*) from jsonb_array_elements(l.followups) e where e->>'tier' in ('HOT', 'WARM', 'STRATEGIC')),$a$;
begin
  if strpos(src, 'follow_up_tier') > 0 then return; end if;
  if strpos(src, a1) = 0 or strpos(src, a2) = 0 or strpos(src, a3) = 0 then raise exception 'outreach_desk changed: anchors not found'; end if;
  execute replace(replace(replace(src, a1, b1), a2, b2), a3, b3);
end $patch$;

-- 2 ----------------------------------------------------------------------------------------------------------------------------
do $patch$
declare f text; src text;
  a1 text := $a$      from jsonb_array_elements(coalesce(d->'needs_review', '[]'::jsonb)) e),$a$;
  b1 text := $a$      from jsonb_array_elements(coalesce(d->'needs_review', '[]'::jsonb)) e
     where coalesce(e->>'channel', 'EMAIL') <> 'EMAIL' or (e->'route'->>'email_state') in ('VALID_VERIFIED', 'VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL')),$a$;
  a2 text := $a$case when s.ch = 'EMAIL' then 5 else 0 end chan$a$;
  b2 text := $a$case when exists (select 1 from studio_documents b where b.doc_type = 'OPPORTUNITY_NOTE' and b.status <> 'SUPERSEDED' and b.content ? 'brief'
                            and (b.opportunity_id = s.opp or b.company_id = s.co)) then 15 else 0 end chan$a$;
  a3 text := $a$case when ch = 'EMAIL' then 'email route' else 'LinkedIn (email exhausted)' end$a$;
  b3 text := $a$case when chan >= 15 then 'project brief on file' end,
             case when ch = 'EMAIL' then 'verified email' else 'LinkedIn (email exhausted)' end$a$;
  a4 text := $a$from (select * from r where per_dir <= 2 order by score desc limit 5) q$a$;
  b4 text := $a$from (select * from r where per_dir <= 1 order by score desc limit 5) q$a$;
  a5 text := $a$from (select * from r where ref not in (select x->>'ref' from jsonb_array_elements(outreach_top5(d)) x) order by score desc limit 20) q$a$;
  b5 text := $a$from (select * from (select r.*, row_number() over (partition by coalesce(dir, '-') order by score desc) pd2 from r
                     where ref not in (select x->>'ref' from jsonb_array_elements(outreach_top5(d)) x)) r2
             where pd2 <= 4 order by score desc limit 20) q$a$;
begin
  foreach f in array array['outreach_top5(jsonb)', 'outreach_next20(jsonb)'] loop
    src := pg_get_functiondef(('public.' || f)::regprocedure);
    if strpos(src, 'VALID_VERIFIED') > 0 then continue; end if;
    if strpos(src, a1) = 0 or strpos(src, a2) = 0 or strpos(src, a3) = 0 then raise exception '% changed: anchors not found', f; end if;
    src := replace(replace(replace(src, a1, b1), a2, b2), a3, b3);
    if f = 'outreach_top5(jsonb)' then
      if strpos(src, a4) = 0 then raise exception 'outreach_top5 changed: limit anchor not found'; end if;
      src := replace(src, a4, b4);
    else
      if strpos(src, a5) = 0 then raise exception 'outreach_next20 changed: limit anchor not found'; end if;
      src := replace(src, a5, b5);
    end if;
    execute src;
  end loop;
end $patch$;

-- 3 ----------------------------------------------------------------------------------------------------------------------------
do $patch$
declare src text := pg_get_functiondef('public.commercial_pipeline()'::regprocedure);
  a1 text := $a$when e.es in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL') then 'READY_POOL'$a$;
  b1 text := $a$when e.es in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL') then 'READY_POOL'
                         when e.es in ('OFFICIAL_PUBLISHED_INBOX', 'PUBLIC_NAMED_EMAIL') then 'CONTACT_READY'$a$;
  a2 text := $a$    'ready_pool', count(*) filter (where tier = 'READY_POOL'),$a$;
  b2 text := $a$    'ready_pool', count(*) filter (where tier = 'READY_POOL'),
    'contact_ready', count(*) filter (where tier = 'CONTACT_READY'),
    'contact_ready_by_route', (select coalesce(jsonb_object_agg(es, n), '{}'::jsonb) from (select es, count(*) n from t where tier = 'CONTACT_READY' group by es) x),$a$;
begin
  if strpos(src, 'CONTACT_READY') > 0 then return; end if;
  if strpos(src, a1) = 0 or strpos(src, a2) = 0 then raise exception 'commercial_pipeline changed: anchors not found'; end if;
  execute replace(replace(src, a1, b1), a2, b2);
end $patch$;

-- 4 ----------------------------------------------------------------------------------------------------------------------------
do $patch$
declare src text := pg_get_functiondef('public.hq_studio()'::regprocedure);
  a1 text := $a$sd.ready_class, sd.ready_reason, c.name company,$a$;
  b1 text := $a$sd.ready_class, sd.ready_reason, case when sd.doc_type = 'OPPORTUNITY_NOTE' then sd.content->'brief' end brief, c.name company,$a$;
  a2 text := $a$'ready_reason', d.ready_reason, 'file', d.file_name,$a$;
  b2 text := $a$'ready_reason', d.ready_reason, 'brief', d.brief, 'file', d.file_name,$a$;
begin
  if strpos(src, '''brief'', d.brief') > 0 then return; end if;
  if strpos(src, a1) = 0 or strpos(src, a2) = 0 then raise exception 'hq_studio changed: anchors not found'; end if;
  execute replace(replace(src, a1, b1), a2, b2);
end $patch$;

-- 5 ----------------------------------------------------------------------------------------------------------------------------
-- A Director's live project opportunities: its internal opportunity briefs, strongest first. A company with no credible project
-- concept has no brief, so it is not a top opportunity.
create or replace function public.director_projects(p_dir text) returns jsonb
language sql stable security definer set search_path = public as $$
  with b as (
    select d.id, d.slug, d.company_id, d.opportunity_id, d.content->'brief' br, c.name company
      from studio_documents d join companies c on c.id = d.company_id
     where d.doc_type = 'OPPORTUNITY_NOTE' and d.status <> 'SUPERSEDED' and d.content ? 'brief'
       and coalesce(d.content->'brief'->>'status', 'LIVE') = 'LIVE'
       and coalesce(d.content->'brief'->>'director',
                    agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes)) = p_dir)
  select jsonb_build_object('count', (select count(*) from b),
    'top', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'company', x.company, 'company_id', x.company_id, 'opportunity_id', x.opportunity_id,
               'person', x.br->>'person', 'project', x.br->>'project_short', 'next_action', x.br->>'next_action',
               'confidence', x.br->>'confidence', 'score', x.br->'score') order by (x.br->>'score')::numeric desc nulls last)
       from (select * from b order by (br->>'score')::numeric desc nulls last limit 3) x), '[]'::jsonb))
$$;
revoke all on function public.director_projects(text) from public, anon, authenticated;

do $patch$
declare src text := pg_get_functiondef('public.director_scorecards()'::regprocedure);
  a text := $a$'coverage', (select cov.j->d.key from cov)) order by d.sort) from dirs d),$a$;
  b text := $a$'coverage', (select cov.j->d.key from cov), 'projects', director_projects(d.key)) order by d.sort) from dirs d),$a$;
begin
  if strpos(src, 'director_projects') > 0 then return; end if;
  if strpos(src, a) = 0 then raise exception 'director_scorecards changed: anchor not found'; end if;
  execute replace(src, a, b);
end $patch$;
