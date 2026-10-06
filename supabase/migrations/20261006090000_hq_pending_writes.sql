-- NOT YET APPLIED (6 Oct 2026). One paste, safe to re-run in full:
--   Supabase dashboard -> project gagbhykzmtstekpqujyl -> SQL editor -> paste this whole file -> Run.
-- The Supabase connector in Claude's session holds approval and update writes for a confirmation it
-- cannot show, so this one step is Adam's. Everything below only touches rows still in the state
-- it expects, and the audit insert skips events that already have a row.
--
-- 1. CEO decision 2A (6 Oct 2026): approve the 9 VERIFIED Private Calendar events, after a final
--    re-check on each organiser's own source on 6 Oct 2026 (all dates unchanged):
--      LGCT Cairo 22–24 Oct 2026 (gcglobalchampions.com) · Gala de Danza at the GEM 5 Nov 2026
--      (official ticketing) · El Gouna IGFA Red Sea Championship 4–7 Feb 2027 (igfa.org) ·
--      Total solar eclipse, Luxor, 2 Aug 2027 (NASA) · Sun Festival at Abu Simbel 22 Oct 2027
--      (Ministry, recurring) · Snow Polo World Cup St. Moritz 22–24 Jan 2027 · Goodwood Festival of
--      Speed 15–18 Jul 2027 · Ryder Cup, Adare Manor, 17–19 Sep 2027 (week from 13 Sep) ·
--      Monaco Yacht Show 22–25 Sep 2027.
--    Same steps as hq_calendar_approve: gate on, approve, gate off, audit.
-- 2. The playbook correction from 20261004090000 (held on 4 Oct).
-- 3. Shakira's "held" note and its BLOCKED audit row from 20261003093000 (held on 3 Oct).
begin;
set local lock_timeout = '5s';

-- 1. Approvals
select set_config('noya.calendar_gate', 'on', true);
update public.intelligence
set calendar_status = 'APPROVED',
    approved_by = 'Adam Elshazly (decision 2A, 6 Oct 2026)',
    approved_at = now(),
    source_checked_at = '2026-10-06',
    notes = coalesce(notes, '') || ' · Re-checked 6 Oct 2026 on the official source, dates unchanged; approved by the CEO (2A, 6 Oct 2026).'
where calendar_status = 'VERIFIED'
  and captured_by = 'Claude (Private Calendar research, 4 Oct 2026)'
  and calendar_slug in ('lgct-cairo-2026', 'gala-de-danza-grand-egyptian-museum-2026', 'el-gouna-igfa-red-sea-championship-2027',
    'total-solar-eclipse-luxor-2027', 'abu-simbel-sun-festival-october-2027', 'snow-polo-world-cup-st-moritz-2027',
    'goodwood-festival-of-speed-2027', 'ryder-cup-2027', 'monaco-yacht-show-2027');
select set_config('noya.calendar_gate', 'off', true);

insert into public.approval_audit (action, result, actor, detail)
select 'CALENDAR_APPROVE', 'OK', 'Adam Elshazly (written approval 2A, 6 Oct 2026)',
       jsonb_build_object('intelligence_id', i.id, 'calendar_slug', i.calendar_slug, 'rechecked', '2026-10-06')
from public.intelligence i
where i.calendar_status = 'APPROVED'
  and i.calendar_slug in ('lgct-cairo-2026', 'gala-de-danza-grand-egyptian-museum-2026', 'el-gouna-igfa-red-sea-championship-2027',
    'total-solar-eclipse-luxor-2027', 'abu-simbel-sun-festival-october-2027', 'snow-polo-world-cup-st-moritz-2027',
    'goodwood-festival-of-speed-2027', 'ryder-cup-2027', 'monaco-yacht-show-2027')
  and not exists (select 1 from public.approval_audit a where a.action = 'CALENDAR_APPROVE' and a.detail->>'intelligence_id' = i.id::text);

-- 2. Playbooks (as for the launch set)
update public.intelligence set
  playbook_code = 'EVENT_TRAVEL', product_codes = '{}', decision_roles = '{}', services = '{}',
  commercial_angle = null, problem_noya_solves = null,
  next_action = 'Approved for the Private Calendar: shortlist the clients and EAs to offer it to.'
where calendar_slug in ('total-solar-eclipse-luxor-2027', 'abu-simbel-sun-festival-october-2027', 'snow-polo-world-cup-st-moritz-2027',
  'goodwood-festival-of-speed-2027', 'ryder-cup-2027', 'monaco-yacht-show-2027', 'art-basel-qatar-2027', 'frieze-abu-dhabi-2026')
  and captured_by = 'Claude (Private Calendar research, 4 Oct 2026)'
  and coalesce(playbook_code, '') <> 'EVENT_TRAVEL';
update public.intelligence set playbook_code = 'SPORTS_EVENT_EGYPT'
where calendar_slug = 'lgct-cairo-2026' and playbook_code is null and captured_by = 'Claude (Private Calendar research, 4 Oct 2026)';

-- 3. Shakira at the Pyramids: held (date moved once), stays VERIFIED and off the public calendar
update public.intelligence
set notes = 'Held at launch (3 Oct 2026): the date has already moved once (7 Apr -> 28 Nov 2026, regional situation) and only the promoter''s official ticketing confirms it. Not approved and not on the public calendar; re-check with the artist''s and promoter''s channels before approving.'
where calendar_slug = 'shakira-pyramids-of-giza-2026' and calendar_status = 'VERIFIED' and coalesce(notes, '') not like 'Held at launch%';
insert into public.approval_audit (action, result, actor, detail)
select 'CALENDAR_APPROVE', 'BLOCKED', 'Adam Elshazly (written approval, APPROVE V3 FINAL)',
       jsonb_build_object('intelligence_id', i.id, 'calendar_slug', i.calendar_slug, 'reason', 'date moved once (7 Apr -> 28 Nov 2026); held until re-confirmed')
from public.intelligence i
where i.calendar_slug = 'shakira-pyramids-of-giza-2026'
  and not exists (select 1 from public.approval_audit a where a.action = 'CALENDAR_APPROVE' and a.detail->>'intelligence_id' = i.id::text);

commit;

-- Check (should read 26 APPROVED: 17 launch + 9 today; 1 VERIFIED: Shakira; 4 CANDIDATE)
select calendar_status, count(*) from public.intelligence where calendar_status is not null group by 1 order by 1;
