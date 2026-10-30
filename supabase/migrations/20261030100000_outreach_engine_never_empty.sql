-- Outreach engine (Adam, 30 Oct 2026, master outreach pass): the Outreach screen must never look empty while real opportunities,
-- drafts or contact-ready accounts exist. Today's five and Next 20 rank drafts awaiting review; when none are waiting, HQ now says
-- exactly why (accounts ready to draft, drafts queued, addresses waiting for verification, Gmail drafts, automation paused) and
-- lists the ready accounts themselves, strongest first, with the person and the route. Nothing is sent; Adam approves every email.

-- 1. Why the queue looks the way it does (cheap: reads the Dashboard snapshot for the pipeline counts).
create or replace function public.outreach_status() returns jsonb
language sql stable security definer set search_path = public as $$
  with g as (select last_run_at from gmail_sync_state where mailbox = 'noya@noyaconcierge.com' order by last_run_at desc nulls last limit 1),
       h as (select (value->>'at')::timestamptz at from system_config where key = 'heartbeat_w18'),
       p as (select payload->'pipeline' pl from hq_read_cache where key = 'ceo')
  select jsonb_build_object(
    'automation', case when coalesce((select last_run_at from g), '-infinity'::timestamptz) < now() - interval '3 hours' then 'PAUSED' else 'LIVE' end,
    'gmail_synced_at', (select last_run_at from g),
    'writer_ran_at', (select at from h),
    'planned_queued', (select count(*) from outreach_candidates where status = 'PLANNED' and not dry_run),
    'waiting_verification', (select count(*) from outreach_candidates where status = 'HOLD' and not dry_run and coalesce(hold_reason, '') like 'EMAIL_NOT_VERIFIED%'),
    'approved_waiting_draft', (select count(*) from outbound_emails where status in ('APPROVED', 'PROCESSING') and gmail_draft_id is null),
    'gmail_drafts_unsent', (select count(*) from outbound_emails where status = 'DRAFTED' and sent_at is null),
    'ready_pool', (select (pl->>'ready_pool')::int from p),
    'ready_undrafted', (select jsonb_array_length(coalesce(pl->'ready_list', '[]'::jsonb)) from p),
    'contact_research', (select (pl->>'contact_research')::int from p),
    'research_by_state', (select pl->'research_by_state' from p),
    'checked_at', now())
$$;
revoke all on function public.outreach_status() from public, anon, authenticated;

-- 2. The ready accounts themselves (in the Dashboard snapshot, rebuilt every 5 minutes): cold, spend allowed, not on hold, a usable
--    route, and no draft yet. A named person's own address ranks above a shared inbox; a shared inbox at a large organisation is
--    a fallback that Adam approves case by case (label says so).
do $patch$
declare src text := pg_get_functiondef('public.commercial_pipeline()'::regprocedure);
  a text := $a$    'computed_at', now())$a$;
  b text := $a$    'ready_list', (select coalesce(jsonb_agg(x.j order by x.rk desc), '[]'::jsonb) from (
        select jsonb_build_object('company_id', t.id, 'company', c.name, 'lane', t.lane, 'country', c.country,
                 'route', t.es, 'shared_inbox', email_local_class(es2.r->>'email') <> 'PERSONAL',
                 'person', (select nullif(btrim(concat_ws(' ', k.first_name, k.last_name)), '') from contacts k where k.id = (es2.r->>'contact_id')::uuid),
                 'role', (select k.position from contacts k where k.id = (es2.r->>'contact_id')::uuid),
                 'route_label', es2.r->>'label', 'opportunity_id', o.id, 'project', o.opportunity_type,
                 'why_now', left(coalesce(nullif(btrim(o.commercial_trigger), ''), o.reason), 220), 'score', coalesce(o.priority, 50)) j,
               coalesce(o.priority, 50) + case when email_local_class(es2.r->>'email') = 'PERSONAL' then 8 else 0 end rk
          from t join companies c on c.id = t.id
          cross join lateral (select company_email_state(t.id) r) es2
          left join lateral (select * from opportunities o where o.company_id = t.id and o.status not in ('WON', 'LOST', 'ARCHIVED')
                              order by coalesce(o.priority, 0) desc limit 1) o on true
         where t.tier = 'READY_POOL'
           and not exists (select 1 from outreach_candidates oc where oc.company_id = t.id and not oc.dry_run
                            and oc.status in ('PLANNED', 'READY', 'REVIEW_REQUIRED', 'APPROVED', 'HOLD'))
         order by rk desc limit 60) x),
    'computed_at', now())$a$;
begin
  if strpos(src, 'ready_list') > 0 then return; end if;
  if strpos(src, a) = 0 then raise exception 'commercial_pipeline changed: anchor not found'; end if;
  execute replace(src, a, b);
end $patch$;

-- 3. The live desk carries the status.
create or replace function public.hq_outreach_desk() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); d jsonb;
begin
  d := outreach_desk();
  return d || jsonb_build_object('top5', outreach_top5(d), 'next20', outreach_next20(d), 'linkedin', linkedin_board(),
                                 'meeting_assist', meeting_assist_board(), 'studio_ready', studio_ready_board(), 'status', outreach_status());
end $$;

-- 4. Defect (30 Oct): the send gate did not know the PUBLIC_NAMED_EMAIL route Adam approved on 29 Oct (a person's own address,
--    published on the company's own Instagram), so those drafts were held for Hunter and approvals refused. It is accepted exactly
--    like an official published inbox: never labelled VERIFIED, revoked by any provider result other than valid.
create or replace function public.outbound_recipient_block_reason(p_contact_id uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when c.id is null then 'NO_CONTACT'
    when coalesce(btrim(c.email), '') = '' then 'NO_EMAIL'
    when c.email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then 'MALFORMED_EMAIL'
    when c.do_not_contact then 'DO_NOT_CONTACT'
    when c.status = 'DO_NOT_CONTACT' then 'DO_NOT_CONTACT'
    when email_state(c.email_status, c.email_source_url, c.email_verification_provider) <> 'VERIFIED'
      and not exists (select 1 from email_official_inboxes o where o.contact_id = c.id and o.revoked_at is null and o.email = lower(btrim(c.email)))
      and not exists (select 1 from public_profiles pp
                       where pp.email_class = 'PUBLIC_NAMED_EMAIL' and lower(pp.public_email) = lower(btrim(c.email)) and pp.company_id = c.company_id
                         and not exists (select 1 from contact_email_verifications v where lower(v.email) = lower(btrim(c.email))
                                          and v.provider_status is not null and v.provider_status <> 'valid'))
      then 'EMAIL_NOT_VERIFIED:' || email_state(c.email_status, c.email_source_url, c.email_verification_provider)
    else null end
  from (select 1) one left join contacts c on c.id = p_contact_id
$$;
