-- Private Calendar on the radar (website V3; Adam's decision 2A, 3 Oct 2026).
--
-- The website's Private Calendar draws on the existing radar (public.intelligence), not a
-- separate table. A radar row becomes a calendar candidate when calendar_status is set; every
-- other row (workflow 09 news, research) is untouched, and every new column is nullable.
--
--   CANDIDATE  found by research, not yet checked against an official source
--   VERIFIED   dates and place checked against the official source (source_url, source_checked_at)
--   APPROVED   approved for the website: only through hq_calendar_approve (an HQ admin), never
--              by a research agent writing to the table
--   PUBLISHED  in the Studio (sanity_document_id); set by the Studio sync once it exists
--   REJECTED   not for the website
--   COMPLETED  the event has taken place
--
-- website_enquiries gains the fields the V3 site sends with "Plan around this event"
-- (source = website_calendar). Workflow 10d writes them only once its prepared draft is
-- published at the V3 merge; until then the live intake ignores them and nothing changes.

-- Fail fast rather than queue behind a live intake write.
set lock_timeout = '5s';

alter table public.intelligence
  add column if not exists calendar_status text,
  add column if not exists calendar_category text,
  add column if not exists city text,
  add column if not exists venue text,
  add column if not exists source_checked_at timestamptz,
  add column if not exists egypt_relevance smallint,
  add column if not exists access_potential smallint,
  add column if not exists travel_opportunity smallint,
  add column if not exists notes text,
  add column if not exists approved_by text,
  add column if not exists approved_at timestamptz,
  add column if not exists sanity_document_id text,
  add column if not exists calendar_slug text,
  add column if not exists dedupe_key text;

comment on column public.intelligence.calendar_status is 'Private Calendar lifecycle: CANDIDATE → VERIFIED → APPROVED (hq_calendar_approve only) → PUBLISHED; or REJECTED / COMPLETED. Null = not a calendar candidate.';
comment on column public.intelligence.calendar_category is 'Website category: EGYPT, SPORT, FASHION_CULTURE, MOTORSPORT, ENTERTAINMENT, SEASONAL.';
comment on column public.intelligence.source_checked_at is 'When the dates were last checked against source_url (an official organiser, governing body, venue or primary source).';
comment on column public.intelligence.egypt_relevance is '0–100: how much the event matters to NOYA''s Egypt business.';
comment on column public.intelligence.access_potential is '0–100: VIP / hospitality / access potential.';
comment on column public.intelligence.travel_opportunity is '0–100: travel and accommodation opportunity around the event.';
comment on column public.intelligence.sanity_document_id is 'The Studio document for the published event (calendarEvent.<slug>).';
comment on column public.intelligence.calendar_slug is 'The event''s page: noyaconcierge.com/calendar/<slug>. Website enquiries carry it as event_id.';
comment on column public.intelligence.dedupe_key is 'Duplicate guard for research agents, e.g. "art-basel-paris|2026-10".';

do $$ begin
  alter table public.intelligence add constraint intelligence_calendar_status_check
    check (calendar_status is null or calendar_status in ('CANDIDATE','VERIFIED','APPROVED','PUBLISHED','REJECTED','COMPLETED'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.intelligence add constraint intelligence_calendar_category_check
    check (calendar_category is null or calendar_category in ('EGYPT','SPORT','FASHION_CULTURE','MOTORSPORT','ENTERTAINMENT','SEASONAL'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.intelligence add constraint intelligence_calendar_scores_check
    check ((egypt_relevance is null or egypt_relevance between 0 and 100)
       and (access_potential is null or access_potential between 0 and 100)
       and (travel_opportunity is null or travel_opportunity between 0 and 100));
exception when duplicate_object then null; end $$;

-- A calendar row needs its website category; dates must run forwards.
do $$ begin
  alter table public.intelligence add constraint intelligence_calendar_shape_check
    check (calendar_status is null
       or (calendar_category is not null and (event_end is null or event_date is null or event_end >= event_date)));
exception when duplicate_object then null; end $$;

-- Never invent dates: from VERIFIED on, the date, the official source and when it was checked are required.
do $$ begin
  alter table public.intelligence add constraint intelligence_calendar_verified_check
    check (calendar_status is null or calendar_status in ('CANDIDATE','REJECTED')
       or (event_date is not null and nullif(btrim(coalesce(source_url, '')), '') is not null and source_checked_at is not null));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.intelligence add constraint intelligence_calendar_approved_check
    check (calendar_status is null or calendar_status not in ('APPROVED','PUBLISHED')
       or (approved_by is not null and approved_at is not null));
exception when duplicate_object then null; end $$;

create unique index if not exists intelligence_dedupe_key_key on public.intelligence (dedupe_key) where dedupe_key is not null;
create unique index if not exists intelligence_calendar_slug_key on public.intelligence (calendar_slug) where calendar_slug is not null;
create unique index if not exists intelligence_sanity_document_id_key on public.intelligence (sanity_document_id) where sanity_document_id is not null;
create index if not exists intelligence_calendar_idx on public.intelligence (calendar_status, event_date) where calendar_status is not null;

-- The approval gate. Research agents write CANDIDATE or VERIFIED rows; only an HQ admin
-- (hq_calendar_approve) can make one APPROVED. APPROVED → PUBLISHED stays open for the
-- Studio sync, which only ever publishes what was already approved.
create or replace function public.intelligence_calendar_gate()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.calendar_status in ('APPROVED', 'PUBLISHED')
     and (tg_op = 'INSERT' or old.calendar_status is distinct from new.calendar_status)
     and not (tg_op = 'UPDATE' and old.calendar_status = 'APPROVED' and new.calendar_status = 'PUBLISHED')
     and coalesce(current_setting('noya.calendar_gate', true), '') <> 'on' then
    raise exception 'Calendar approval goes through hq_calendar_approve (an HQ admin), never a direct write'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace trigger intelligence_calendar_gate
  before insert or update of calendar_status on public.intelligence
  for each row execute function public.intelligence_calendar_gate();

create or replace function public.hq_calendar_approve(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin text := hq_admin_email();
  r intelligence%rowtype;
begin
  select * into r from intelligence where id = p_id for update;
  if r.id is null then
    return jsonb_build_object('ok', false, 'reason', 'event not found');
  end if;
  if r.calendar_status is distinct from 'VERIFIED' then
    insert into approval_audit (action, result, actor, detail)
    values ('CALENDAR_APPROVE', 'BLOCKED', v_admin,
            jsonb_build_object('intelligence_id', p_id, 'event', r.title, 'calendar_status', r.calendar_status,
                               'reason', 'only a VERIFIED event (dates checked against the official source) can be approved'));
    return jsonb_build_object('ok', false, 'reason', 'only a verified event can be approved', 'calendar_status', r.calendar_status);
  end if;
  perform set_config('noya.calendar_gate', 'on', true);
  update intelligence set calendar_status = 'APPROVED', approved_by = v_admin, approved_at = now() where id = p_id;
  perform set_config('noya.calendar_gate', 'off', true);
  insert into approval_audit (action, result, actor, detail)
  values ('CALENDAR_APPROVE', 'OK', v_admin,
          jsonb_build_object('intelligence_id', p_id, 'event', r.title, 'event_date', r.event_date,
                             'event_end', r.event_end, 'source_url', r.source_url, 'calendar_slug', r.calendar_slug));
  return jsonb_build_object('ok', true, 'id', p_id, 'calendar_status', 'APPROVED');
end;
$$;

create or replace function public.hq_calendar_reject(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin text := hq_admin_email();
  r intelligence%rowtype;
begin
  select * into r from intelligence where id = p_id for update;
  if r.id is null or r.calendar_status is null then
    return jsonb_build_object('ok', false, 'reason', 'not a calendar candidate');
  end if;
  update intelligence
     set calendar_status = 'REJECTED',
         notes = concat_ws(E'\n', notes, 'Rejected by ' || v_admin || ' on ' || to_char(now(), 'DD Mon YYYY') || coalesce(': ' || hq_trim(p_reason), ''))
   where id = p_id;
  insert into approval_audit (action, result, actor, detail)
  values ('CALENDAR_REJECT', 'OK', v_admin, jsonb_build_object('intelligence_id', p_id, 'event', r.title, 'reason', hq_trim(p_reason)));
  return jsonb_build_object('ok', true, 'id', p_id, 'calendar_status', 'REJECTED');
end;
$$;

revoke all on function public.hq_calendar_approve(uuid) from public, anon;
revoke all on function public.hq_calendar_reject(uuid, text) from public, anon;
grant execute on function public.hq_calendar_approve(uuid) to authenticated;
grant execute on function public.hq_calendar_reject(uuid, text) to authenticated;

-- ---------------------------------------------------------------- website enquiries

alter table public.website_enquiries
  add column if not exists source_detail text,
  add column if not exists event_id text,
  add column if not exists event_name text,
  add column if not exists event_city text,
  add column if not exists event_dates text,
  add column if not exists signal_id uuid references public.intelligence(id) on delete set null;

comment on column public.website_enquiries.source_detail is 'Where on the website the enquiry began: PRIVATE_CALENDAR for "Plan around this event". Null for every other form.';
comment on column public.website_enquiries.event_id is 'The calendar event''s slug (noyaconcierge.com/calendar/<event_id>), as sent by the website.';
comment on column public.website_enquiries.event_dates is 'The event''s dates as the website sent them (YYYY-MM-DD/YYYY-MM-DD).';
comment on column public.website_enquiries.signal_id is 'The radar row for the event (intelligence.calendar_slug = event_id), linked automatically.';

-- Tidy the event fields and link the radar row. Never allowed to stop an enquiry being saved.
create or replace function public.website_enquiries_calendar_link()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    new.source_detail := nullif(btrim(coalesce(new.source_detail, '')), '');
    new.event_id := nullif(btrim(coalesce(new.event_id, '')), '');
    new.event_name := nullif(btrim(coalesce(new.event_name, '')), '');
    new.event_city := nullif(btrim(coalesce(new.event_city, '')), '');
    new.event_dates := nullif(btrim(coalesce(new.event_dates, '')), '');
    if new.event_id is not null and new.signal_id is null then
      select i.id into new.signal_id from intelligence i where i.calendar_slug = new.event_id limit 1;
    end if;
  exception when others then
    null;
  end;
  return new;
end;
$$;

create or replace trigger website_enquiries_calendar_link
  before insert or update of source_detail, event_id, event_name, event_city, event_dates on public.website_enquiries
  for each row execute function public.website_enquiries_calendar_link();

-- When workflow 10d links the opportunity, carry the event's radar row onto it (opportunities.signal_id).
create or replace function public.website_enquiries_calendar_opportunity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    if new.signal_id is not null and new.created_opportunity_id is not null
       and (old.created_opportunity_id is distinct from new.created_opportunity_id or old.signal_id is distinct from new.signal_id) then
      update opportunities set signal_id = new.signal_id where id = new.created_opportunity_id and signal_id is null;
    end if;
  exception when others then
    null;
  end;
  return null;
end;
$$;

create or replace trigger website_enquiries_calendar_opportunity
  after update of created_opportunity_id, signal_id on public.website_enquiries
  for each row execute function public.website_enquiries_calendar_opportunity();

insert into approval_audit (action, result, actor, detail)
values ('PRIVATE_CALENDAR_SCHEMA', 'OK', 'system (Adam''s decision 2A, 3 Oct 2026)',
        jsonb_build_object('intelligence', 'calendar_status, calendar_category, city, venue, source_checked_at, egypt_relevance, access_potential, travel_opportunity, notes, approved_by, approved_at, sanity_document_id, calendar_slug, dedupe_key',
                           'website_enquiries', 'source_detail, event_id, event_name, event_city, event_dates, signal_id',
                           'approval', 'hq_calendar_approve / hq_calendar_reject (HQ admin only); trigger intelligence_calendar_gate',
                           'workflow_10d', 'draft prepared, unpublished until the V3 merge'));
