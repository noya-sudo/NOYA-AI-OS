-- FINAL ACCEPTANCE PASS (21 Nov 2026): the three intentionally specified capabilities plus an auditable duplicate merge.
--   1. Seasonal commercial engine: source-backed windows (NO SOURCE = NO DATE), rolling 30/60/90/180-day read; Today only when timely.
--   2. Quiet tool / source scout: gated recommendations (evidence + sourced price); research and recommend only, never buy.
--   3. Partnership agreements + term-sheet preparation (draft for Adam / legal review; NON-EXCLUSIVE by default; nothing binding).
--   4. company_merge(): idempotent, auditable merge of exact duplicate companies; deletes nothing, moves every reference.
-- Admin-gated reads (hq_admin_email), internal functions revoked from public/anon/authenticated, RLS on every new table.

-- ============================================================== 1. SEASONAL ENGINE
alter table public.seasonal_windows add column if not exists category text;
alter table public.seasonal_windows add column if not exists outreach_from date;
alter table public.seasonal_windows add column if not exists outreach_to date;
alter table public.seasonal_windows add column if not exists verification_note text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'seasonal_windows_source_required') then
    -- NO SOURCE = NO DATE: a dated window needs a source URL and a verification date.
    alter table public.seasonal_windows add constraint seasonal_windows_source_required
      check (starts_on is null or (source_url ~ '^https?://' and last_verified_at is not null));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'seasonal_windows_category_ok') then
    alter table public.seasonal_windows add constraint seasonal_windows_category_ok check (category is null or category in (
      'EGYPT_WINTER','NILE','NORTH_COAST','EL_GOUNA','MEDITERRANEAN_SUMMER','SKI','RAMADAN_EID','FESTIVE','WEDDING_SEASON','FASHION_WEEK',
      'FILM_FESTIVAL','ART_FAIR','F1','FOOTBALL','TRANSFER_WINDOW','PRE_SEASON','INTERNATIONAL_BREAK','CORPORATE_PLANNING','EXECUTIVE_RELOCATION',
      'SCHOOL_YEAR','GIFTING','BRAND_LAUNCH','TRADE_SHOW','YACHTING','CULTURAL'));
  end if;
end $$;
-- Recommended outreach window: opens lead_time_days before the start, closes a third of the lead time before it (at least 7 days).
create or replace function public.seasonal_windows_outreach() returns trigger language plpgsql set search_path to 'public' as $$
begin
  if new.starts_on is not null and new.lead_time_days is not null then
    new.outreach_from := coalesce(new.outreach_from, new.starts_on - new.lead_time_days);
    new.outreach_to := coalesce(new.outreach_to, new.starts_on - greatest(new.lead_time_days / 3, 7));
  end if;
  return new;
end $$;
drop trigger if exists seasonal_windows_outreach on public.seasonal_windows;
create trigger seasonal_windows_outreach before insert or update on public.seasonal_windows for each row execute function public.seasonal_windows_outreach();

create or replace function public.hq_seasons(p_horizon int default 180)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); v jsonb;
begin
  p_horizon := least(greatest(coalesce(p_horizon, 180), 7), 366);
  with w as (
    select s.*, st.label stream_label, (s.starts_on - current_date) days_to_start,
           current_date between coalesce(s.outreach_from, s.starts_on) and coalesce(s.outreach_to, s.starts_on) act_now
      from seasonal_windows s left join commercial_streams st on st.code = s.stream
     where s.status = 'ACTIVE' and s.starts_on is not null and coalesce(s.ends_on, s.starts_on) >= current_date and s.starts_on <= current_date + p_horizon)
  select jsonb_build_object('generated_at', now(), 'horizon', p_horizon,
    'windows', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'category', category, 'market', market, 'stream', stream, 'stream_label', stream_label,
                 'starts_on', starts_on, 'ends_on', ends_on, 'lead_time_days', lead_time_days, 'outreach_from', outreach_from, 'outreach_to', outreach_to,
                 'angle', commercial_angle, 'accounts', accounts_hint, 'source_url', source_url, 'source_title', source_title, 'verified', last_verified_at,
                 'confidence', confidence, 'days_to_start', days_to_start, 'act_now', act_now,
                 'bucket', case when days_to_start <= 30 then 30 when days_to_start <= 60 then 60 when days_to_start <= 90 then 90 else 180 end)
               order by starts_on) from w), '[]'::jsonb),
    'counts', jsonb_build_object('d30', (select count(*) from w where days_to_start <= 30), 'd60', (select count(*) from w where days_to_start <= 60),
                                 'd90', (select count(*) from w where days_to_start <= 90), 'd180', (select count(*) from w), 'act_now', (select count(*) from w where act_now)),
    'undated_rule', 'NO SOURCE = NO DATE: windows without a verified source are not shown.') into v;
  return v;
end $$;
revoke all on function public.hq_seasons(int) from public, anon;
grant execute on function public.hq_seasons(int) to authenticated;
revoke all on function public.seasonal_windows_outreach() from public, anon, authenticated;

-- ============================================================== 2. TOOL / SOURCE SCOUT
create table if not exists public.tool_scout (
  id uuid primary key default gen_random_uuid(),
  tool text not null unique,
  vendor_url text,
  capability_area text not null check (capability_area in ('COMPANY_DISCOVERY','DECISION_MAKER_DISCOVERY','PUBLIC_EMAIL_RESEARCH','INSTAGRAM_INTELLIGENCE',
    'FOOTBALL_AGENT_INTELLIGENCE','TALENT_MANAGEMENT_MAPPING','LUXURY_TRAVEL_INTELLIGENCE','HOTEL_RESIDENCE_OPENINGS','EXECUTIVE_APPOINTMENTS','EVENTS',
    'EMAIL_VERIFICATION','DELIVERABILITY','SOURCING_AUTHENTICATION','VEHICLE_PROVENANCE','WATCH_BAG_AUTHENTICATION','PARTNERSHIP_INTELLIGENCE')),
  capability_gap text not null check (length(btrim(capability_gap)) >= 20),
  why_noya text not null check (length(btrim(why_noya)) >= 20),
  improves_replaces text not null,
  price_model text, price_source_url text, price_verified_at date,
  privacy_risk text not null check (privacy_risk in ('LOW','MEDIUM','HIGH')), privacy_note text,
  integration_effort text not null check (integration_effort in ('LOW','MEDIUM','HIGH')),
  expected_benefit text not null check (length(btrim(expected_benefit)) >= 20),
  recommendation text not null check (recommendation in ('ADOPT','TEST','HOLD','REJECT')),
  evidence_urls text[] not null default '{}',
  status text not null default 'PROPOSED' check (status in ('PROPOSED','APPROVED_BY_ADAM','REJECTED_BY_ADAM','PARKED')),
  decided_at timestamptz, decided_note text,
  source text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  -- Gating: every recommendation carries evidence; a stated price carries its official source and date.
  constraint tool_scout_evidence check (coalesce(array_length(evidence_urls, 1), 0) >= 1),
  constraint tool_scout_price_sourced check (price_model is null or (price_source_url ~ '^https?://' and price_verified_at is not null)),
  constraint tool_scout_decision_recorded check (status in ('PROPOSED','PARKED') or decided_at is not null)
);
alter table public.tool_scout enable row level security;

create or replace function public.hq_tool_scout()
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email();
begin
  -- Surfaced only when there is a genuine case: ADOPT or TEST, still awaiting Adam. HOLD / REJECT stay quiet (counts only).
  return jsonb_build_object('generated_at', now(),
    'surfaced', coalesce((select jsonb_agg(to_jsonb(t) - 'created_at' order by case t.recommendation when 'ADOPT' then 0 else 1 end, t.created_at desc)
                            from tool_scout t where t.recommendation in ('ADOPT','TEST') and t.status = 'PROPOSED'), '[]'::jsonb),
    'quiet', jsonb_build_object('hold', (select count(*) from tool_scout where recommendation = 'HOLD'), 'reject', (select count(*) from tool_scout where recommendation = 'REJECT'),
                                'decided', (select count(*) from tool_scout where status in ('APPROVED_BY_ADAM','REJECTED_BY_ADAM'))),
    'rule', 'Research and recommend only. Never purchase, subscribe, enter payment details, increase spend, grant broad access or share client data.');
end $$;
revoke all on function public.hq_tool_scout() from public, anon;
grant execute on function public.hq_tool_scout() to authenticated;

-- Adam's decision on a recommendation (records it; nothing is bought or connected).
create or replace function public.hq_tool_scout_decide(p_id uuid, p_decision text, p_note text default null)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); v tool_scout%rowtype;
begin
  if p_decision not in ('APPROVED_BY_ADAM','REJECTED_BY_ADAM','PARKED') then return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_DECISION'); end if;
  update tool_scout set status = p_decision, decided_at = now(), decided_note = nullif(btrim(p_note), ''), updated_at = now() where id = p_id returning * into v;
  if v.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  insert into approval_audit (opportunity_id, action, result, actor, detail) values (null, 'TOOL_SCOUT_DECISION', p_decision, v_admin, jsonb_build_object('tool', v.tool, 'note', p_note));
  return jsonb_build_object('ok', true, 'status', v.status);
end $$;
revoke all on function public.hq_tool_scout_decide(uuid, text, text) from public, anon;
grant execute on function public.hq_tool_scout_decide(uuid, text, text) to authenticated;

-- ============================================================== 3. PARTNERSHIP AGREEMENTS + TERM SHEETS
create table if not exists public.partnership_agreements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  partner_name text not null,
  partnership_type text not null check (partnership_type in ('REFERRAL','RECIPROCAL_REFERRAL','WHITE_LABEL','PREFERRED_PARTNER','COMMISSION','NET_RATE_MARKUP',
    'DISTRIBUTION','MEMBER_BENEFIT','EXECUTION_PARTNER','CONCIERGE_DESK','OWNER_RESIDENT_DESK','CO_MARKETING','SOURCING_PARTNER')),
  tier text not null default 'STRATEGIC' check (tier in ('MULTIPLIER','STRATEGIC','EXECUTION_SUPPLIER')),
  status text not null default 'DISCUSSION' check (status in ('NO_AGREEMENT_NEEDED','DISCUSSION','TERMS_REQUESTED','TERM_SHEET_PREPARED','LEGAL_REVIEW','SENT','SIGNED','EXPIRED_TERMINATED')),
  exclusivity text not null default 'NON_EXCLUSIVE' check (exclusivity in ('NON_EXCLUSIVE','EXCLUSIVE')),
  exclusivity_approved_at timestamptz, exclusivity_rationale text,
  -- Partnership intelligence: the eight questions.
  they_control text, noya_controls text, they_can_refer text, noya_can_refer text, first_test_project text, money_model text, conflict text,
  agreement_required text not null default 'UNKNOWN' check (agreement_required in ('YES','NO','UNKNOWN')),
  verification jsonb not null default '{}'::jsonb,
  term_sheet jsonb, term_sheet_prepared_at timestamptz,
  signed_at timestamptz, signed_note text,
  notes text, source text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint pa_exclusivity_needs_adam check (exclusivity = 'NON_EXCLUSIVE' or (exclusivity_approved_at is not null and length(btrim(coalesce(exclusivity_rationale, ''))) >= 20)),
  constraint pa_signed_recorded check (status <> 'SIGNED' or (signed_at is not null and length(btrim(coalesce(signed_note, ''))) >= 10)),
  constraint pa_term_sheet_present check (status not in ('TERM_SHEET_PREPARED','LEGAL_REVIEW','SENT','SIGNED') or term_sheet is not null),
  unique (partner_name, partnership_type)
);
alter table public.partnership_agreements enable row level security;

-- Which sections a term sheet carries for a partnership type (counsel completes law and dispute terms).
create or replace function public.partnership_term_sheet_sections(p_type text)
 returns text[] language sql immutable set search_path to 'public' as $$
  select array_remove(array[
    'PARTIES','PURPOSE','SCOPE','SERVICES','CLIENT_OWNERSHIP',
    case when p_type in ('REFERRAL','RECIPROCAL_REFERRAL','COMMISSION','DISTRIBUTION','MEMBER_BENEFIT') then 'REFERRAL_PROCESS' end,
    case when p_type in ('WHITE_LABEL','CONCIERGE_DESK','OWNER_RESIDENT_DESK') then 'WHITE_LABEL_POSITION' end,
    case when p_type in ('REFERRAL','RECIPROCAL_REFERRAL','COMMISSION','DISTRIBUTION','SOURCING_PARTNER','WHITE_LABEL') then 'NON_CIRCUMVENTION' end,
    'COMMERCIAL_MODEL',
    case when p_type in ('REFERRAL','RECIPROCAL_REFERRAL','COMMISSION','DISTRIBUTION','MEMBER_BENEFIT','PREFERRED_PARTNER') then 'COMMISSION' end,
    case when p_type in ('NET_RATE_MARKUP','PREFERRED_PARTNER','EXECUTION_PARTNER','SOURCING_PARTNER','WHITE_LABEL') then 'NET_RATE_MARKUP' end,
    'PAYMENT_TRIGGER','INVOICING','TAX_VAT_ASSUMPTION','CANCELLATION_REFUNDS',
    case when p_type in ('EXECUTION_PARTNER','CONCIERGE_DESK','OWNER_RESIDENT_DESK','WHITE_LABEL','SOURCING_PARTNER','PREFERRED_PARTNER') then 'SERVICE_LEVELS' end,
    'CONFIDENTIALITY','CLIENT_PRIVACY_DATA_PROTECTION','BRAND_LOGO_USE','MARKETING_APPROVAL','TERRITORY','EXCLUSIVITY','TERM','TERMINATION',
    case when p_type in ('EXECUTION_PARTNER','CONCIERGE_DESK','OWNER_RESIDENT_DESK','SOURCING_PARTNER','WHITE_LABEL') then 'INSURANCE' end,
    'LIABILITY','COMPLIANCE','ANTI_BRIBERY','SANCTIONS','FORCE_MAJEURE','GOVERNING_LAW_DISPUTE'], null) $$;

-- Prepare (or refresh) a structured term sheet from what is known; unknowns are marked "To agree". Never sends, never signs.
create or replace function public.hq_prepare_term_sheet(p_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); a partnership_agreements%rowtype; secs text[]; s text; body jsonb := '[]'::jsonb; content text; v jsonb;
begin
  select * into a from partnership_agreements where id = p_id;
  if a.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  if a.status in ('SENT','SIGNED','EXPIRED_TERMINATED') then return jsonb_build_object('ok', false, 'reason', 'LOCKED_STATUS'); end if;
  secs := partnership_term_sheet_sections(a.partnership_type);
  foreach s in array secs loop
    content := case s
      when 'PARTIES' then 'NOYA Concierge and ' || a.partner_name || '. Legal entities, registration numbers and signatories: to be confirmed.'
      when 'PURPOSE' then coalesce(a.first_test_project, 'To agree: the first project the parties test together.')
      when 'SCOPE' then coalesce('They control: ' || a.they_control || '. NOYA controls: ' || a.noya_controls || '.', 'To agree.')
      when 'SERVICES' then coalesce('They can refer: ' || a.they_can_refer || '. NOYA can refer: ' || a.noya_can_refer || '.', 'To agree.')
      when 'CLIENT_OWNERSHIP' then 'Default: clients introduced by NOYA remain NOYA clients for all future requests; no direct solicitation of NOYA clients.'
      when 'COMMERCIAL_MODEL' then coalesce(a.money_model, 'To agree.')
      when 'EXCLUSIVITY' then case a.exclusivity when 'EXCLUSIVE' then 'Exclusive (approved by Adam): ' || a.exclusivity_rationale else 'NON-EXCLUSIVE (default). Exclusivity only for a narrow scope, strong upside and performance obligations, with Adam''s explicit approval.' end
      when 'NON_CIRCUMVENTION' then 'Mutual and proportionate, where commercially appropriate; must not restrict NOYA from suppliers or operators it already works with.'
      when 'GOVERNING_LAW_DISPUTE' then 'Placeholder for counsel.'
      when 'TAX_VAT_ASSUMPTION' then 'Assumption to confirm with accountant: prices quoted exclusive of VAT unless stated.'
      when 'SANCTIONS' then 'Each party screens counterparties and clients against applicable sanctions lists; no business with sanctioned persons or territories.'
      when 'ANTI_BRIBERY' then 'Each party complies with applicable anti-bribery law; no undisclosed payments or inducements.'
      when 'CLIENT_PRIVACY_DATA_PROTECTION' then 'Client data shared only as needed for the booking, under applicable data-protection law; no marketing use without consent.'
      when 'CONFLICT' then coalesce(a.conflict, 'None identified yet.')
      else 'To agree.' end;
    body := body || jsonb_build_object('key', s, 'title', initcap(replace(s, '_', ' ')), 'content', content);
  end loop;
  v := jsonb_build_object('title', 'COMMERCIAL PARTNERSHIP TERM SHEET: ' || a.partner_name,
         'status_note', 'DRAFT for Adam / legal review. Not legal advice. Not binding. Nothing is sent or signed by the system.',
         'partnership_type', a.partnership_type, 'exclusivity', a.exclusivity, 'prepared_at', now(), 'prepared_by', v_admin, 'sections', body,
         'verification', a.verification);
  update partnership_agreements set term_sheet = v, term_sheet_prepared_at = now(),
         status = case when status in ('NO_AGREEMENT_NEEDED','DISCUSSION','TERMS_REQUESTED') then 'TERM_SHEET_PREPARED' else status end, updated_at = now()
   where id = p_id;
  insert into approval_audit (opportunity_id, action, result, actor, detail) values (a.opportunity_id, 'TERM_SHEET_PREPARED', 'DRAFT', v_admin, jsonb_build_object('agreement', a.id, 'partner', a.partner_name, 'sections', array_length(secs, 1)));
  return jsonb_build_object('ok', true, 'sections', array_length(secs, 1));
end $$;
revoke all on function public.hq_prepare_term_sheet(uuid) from public, anon;
grant execute on function public.hq_prepare_term_sheet(uuid) to authenticated;

-- Adam moves the agreement status (SIGNED needs a note: who signed what, when). Audited.
create or replace function public.hq_partnership_status(p_id uuid, p_status text, p_note text default null)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email(); a partnership_agreements%rowtype;
begin
  if p_status not in ('NO_AGREEMENT_NEEDED','DISCUSSION','TERMS_REQUESTED','TERM_SHEET_PREPARED','LEGAL_REVIEW','SENT','SIGNED','EXPIRED_TERMINATED') then
    return jsonb_build_object('ok', false, 'reason', 'UNKNOWN_STATUS'); end if;
  if p_status = 'SIGNED' and length(btrim(coalesce(p_note, ''))) < 10 then return jsonb_build_object('ok', false, 'reason', 'SIGNATURE_NOTE_REQUIRED'); end if;
  update partnership_agreements set status = p_status, updated_at = now(),
         signed_at = case when p_status = 'SIGNED' then now() else signed_at end, signed_note = case when p_status = 'SIGNED' then btrim(p_note) else signed_note end,
         notes = case when nullif(btrim(p_note), '') is not null then coalesce(notes || E'\n', '') || to_char(now(), 'DD Mon') || ': ' || btrim(p_note) else notes end
   where id = p_id returning * into a;
  if a.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  insert into approval_audit (opportunity_id, action, result, actor, detail) values (a.opportunity_id, 'PARTNERSHIP_STATUS', p_status, v_admin, jsonb_build_object('agreement', a.id, 'partner', a.partner_name, 'note', p_note));
  return jsonb_build_object('ok', true, 'status', a.status);
end $$;
revoke all on function public.hq_partnership_status(uuid, text, text) from public, anon;
grant execute on function public.hq_partnership_status(uuid, text, text) to authenticated;

create or replace function public.hq_partnerships()
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $$
declare v_admin text := hq_admin_email();
begin
  return jsonb_build_object('generated_at', now(),
    'rows', coalesce((select jsonb_agg(to_jsonb(p) - 'created_at' order by case p.tier when 'MULTIPLIER' then 0 when 'STRATEGIC' then 1 else 2 end, p.updated_at desc) from partnership_agreements p), '[]'::jsonb),
    'counts', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from partnership_agreements group by status) x), '{}'::jsonb));
end $$;
revoke all on function public.hq_partnerships() from public, anon;
grant execute on function public.hq_partnerships() to authenticated;
revoke all on function public.partnership_term_sheet_sections(text) from public, anon;

-- ============================================================== 4. COMPANY MERGE (exact duplicates only)
alter table public.companies add column if not exists merged_into uuid references public.companies(id);
create table if not exists public.company_merges (
  id uuid primary key default gen_random_uuid(),
  keep_id uuid not null references public.companies(id),
  dup_id uuid not null unique references public.companies(id),
  reason text not null, actor text not null, merged_at timestamptz not null default now(),
  moved jsonb not null default '{}'::jsonb, conflicts jsonb not null default '{}'::jsonb, dup_snapshot jsonb not null
);
alter table public.company_merges enable row level security;

create or replace function public.company_merge(p_keep uuid, p_dup uuid, p_reason text, p_actor text default 'Chief of Staff')
 returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare k companies%rowtype; d companies%rowtype; r record; n int; moved jsonb := '{}'::jsonb; conflicts jsonb := '{}'::jsonb;
begin
  if exists (select 1 from company_merges where dup_id = p_dup) then return jsonb_build_object('ok', true, 'already_merged', true); end if;  -- idempotent
  select * into k from companies where id = p_keep; select * into d from companies where id = p_dup;
  if k.id is null or d.id is null or p_keep = p_dup then return jsonb_build_object('ok', false, 'reason', 'BAD_IDS'); end if;
  if k.merged_into is not null or d.merged_into is not null then return jsonb_build_object('ok', false, 'reason', 'ALREADY_MERGED_RECORD'); end if;
  if length(btrim(coalesce(p_reason, ''))) < 10 then return jsonb_build_object('ok', false, 'reason', 'REASON_REQUIRED'); end if;
  -- Every column that points at a company (declared foreign keys plus *company_id columns), except the merge bookkeeping itself.
  for r in
    select distinct t.tbl, t.col from (
      select conrelid::regclass::text tbl, a.attname::text col from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
       where c.contype = 'f' and c.confrelid = 'public.companies'::regclass and c.conrelid <> 'public.companies'::regclass and c.conrelid <> 'public.company_merges'::regclass
      union
      select 'public.' || quote_ident(table_name), column_name::text from information_schema.columns ic
       where table_schema = 'public' and data_type = 'uuid' and column_name ~ 'company_id$' and table_name not in ('companies','company_merges')
         and exists (select 1 from information_schema.tables it where it.table_schema = 'public' and it.table_name = ic.table_name and it.table_type = 'BASE TABLE')) t
  loop
    begin
      execute format('update %s set %I = $1 where %I = $2', r.tbl, r.col, r.col) using p_keep, p_dup;
      get diagnostics n = row_count;
      if n > 0 then moved := moved || jsonb_build_object(r.tbl || '.' || r.col, n); end if;
    exception when unique_violation then
      -- A row that would collide with the kept company's row stays on the duplicate (history retained via merged_into).
      conflicts := conflicts || jsonb_build_object(r.tbl || '.' || r.col, 'unique conflict: rows kept on the duplicate record');
    end;
  end loop;
  update ceo_actions set related_company_ids = array_replace(related_company_ids, p_dup, p_keep) where p_dup = any(related_company_ids);
  get diagnostics n = row_count; if n > 0 then moved := moved || jsonb_build_object('public.ceo_actions.related_company_ids', n); end if;
  -- Fill only empty fields on the kept record; never overwrite. Holds keep the later date. Fit scores keep the higher value.
  update companies set
    website = coalesce(nullif(website, ''), d.website), instagram = coalesce(nullif(instagram, ''), d.instagram), linkedin = coalesce(nullif(linkedin, ''), d.linkedin),
    country = coalesce(nullif(country, ''), d.country), city = coalesce(nullif(city, ''), d.city), sector = coalesce(nullif(sector, ''), d.sector),
    company_type = coalesce(nullif(company_type, ''), d.company_type), prospect_segment = coalesce(prospect_segment, d.prospect_segment),
    acquisition_lane = coalesce(acquisition_lane, d.acquisition_lane), partnership_model = coalesce(partnership_model, d.partnership_model),
    commercial_class = coalesce(commercial_class, d.commercial_class), vertical_override = coalesce(vertical_override, d.vertical_override),
    noya_fit = greatest(noya_fit, d.noya_fit), egypt_fit = greatest(egypt_fit, d.egypt_fit), global_fit = greatest(global_fit, d.global_fit),
    outreach_hold_until = greatest(outreach_hold_until, d.outreach_hold_until),
    outreach_hold_reason = case when d.outreach_hold_until is not null and (outreach_hold_until is null or d.outreach_hold_until > outreach_hold_until) then d.outreach_hold_reason else outreach_hold_reason end,
    notes = case when nullif(btrim(d.notes), '') is not null then coalesce(notes || E'\n', '') || '[Merged ' || to_char(now(), 'DD Mon YYYY') || ' from duplicate record ' || d.id || '] ' || d.notes else notes end,
    updated_at = now()
   where id = p_keep;
  update companies set merged_into = p_keep, universe_status = 'EXCLUDED',
         universe_reason = 'Merged into ' || p_keep || ' (exact duplicate: same company, same domain) on ' || to_char(now(), 'DD Mon YYYY'), updated_at = now()
   where id = p_dup;
  insert into company_merges (keep_id, dup_id, reason, actor, moved, conflicts, dup_snapshot) values (p_keep, p_dup, btrim(p_reason), p_actor, moved, conflicts, to_jsonb(d));
  insert into approval_audit (opportunity_id, action, result, actor, detail)
  values (null, 'COMPANY_MERGE', 'MERGED', p_actor, jsonb_build_object('keep', p_keep, 'dup', p_dup, 'name', d.name, 'moved', moved, 'conflicts', conflicts));
  return jsonb_build_object('ok', true, 'moved', moved, 'conflicts', conflicts);
end $$;
revoke all on function public.company_merge(uuid, uuid, text, text) from public, anon, authenticated;
