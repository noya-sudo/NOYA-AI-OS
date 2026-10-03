# NOYA Commercial Operating System

Status: live in Supabase and HQ as of 30 Sep 2026. Acceptance test: `supabase/tests/commercial_acceptance.sql`. It runs against live data and rolls itself back.

## The chain

SIGNAL → OPPORTUNITY → COMPANY → PEOPLE → RELATIONSHIP → SERVICE → ANGLE → OUTREACH → CONVERSATION → PROPOSAL/PARTNERSHIP → PROJECT → REVENUE → EXPANSION

| Link | Where it lives | What moves it forward |
|---|---|---|
| Signal | `intelligence` (+ stage, category, region, dates, playbook, products, provenance) | Workflow 09 finds it. Workflow 17 analyses it. Capture by hand in Radar needs a source link. |
| Organisations | `signal_organisations` | Kept only if named in the stored source text. Person names are rejected. |
| Qualification | `signal_qualification()` — 10 questions | Promotion is blocked until all 10 are answered (`QUALIFICATION_INCOMPLETE`). |
| Opportunity | `opportunities` (+ signal, product, playbook, track, angle, trigger) | `hq_signal_promote`. One opportunity per signal × company × product, never duplicated. |
| People | `contacts` | A CONTACT_RESEARCH task is raised when no verified person exists. People are never invented. |
| Relationship | `relationship_strength()`, `relationship_edges`, `account_paths()` | Behaviour only: replies, conversations, meetings, projects, revenue, introductions, recency. |
| Outreach | `hq_prepare_outreach` → `outreach_drafts` → approval task | Approve → Gmail draft (workflow 12) → Adam sends. Nothing is sent automatically. |
| Conversation | workflow 13, every 30 min | A reply moves the stage to ENGAGED and lifts relationship strength. |
| Proposal / partnership | `hq_opportunity_commercial` | Money needs currency + written evidence (`VALUE_NEEDS_EVIDENCE`). |
| Project | `projects`, `project_items` | Won (sales/event track) → project + kickoff task. Won (partnership track) → partnership ACTIVE + activation task. |
| Revenue | `revenue` (+ project_id) | Invoice → payment → project gross profit. |
| Expansion | `project_delivered_flow` | Delivered → client feedback task (+2 days) and expansion review (+14 days), deduplicated. |

## The eight sections (frozen)

01 Command · 02 Intelligence & Opportunities · 03 Sales & Outreach · 04 Partnerships · 05 Events & Experiences · 06 Clients & Relationships · 07 Operations · 08 Performance & System

There is no ninth section. New capability goes into one of these as a tab.

## Rules the database enforces (not the UI)

- **No fake pipeline.** `estimated_value` is derived from client budget / proposal / contract only, each with evidence. AI estimates are kept in `legacy_ai_estimate` and never shown. 33 old AI values (5.985M) were moved; live fake pipeline = 0.
- **Score is not money.** `opportunity_score()` uses weights 25/20/20/15/10/10 (stored in `system_config`) and explains every component. An override needs a reason and is audited.
- **Partner stages are earned.** PRODUCTIVE needs an opportunity, project or paid revenue through the partner. STRATEGIC needs paid revenue plus two or more of those. Otherwise the stage is refused with `STAGE_NEEDS_EVIDENCE`.
- **Provenance on everything:** VERIFIED / SOURCE_BACKED / INFERRED / NEEDS_VERIFICATION / MANUALLY_CONFIRMED.
- **Every item has an owner:** routed by role via `role_routing`. Adam currently holds all eight roles.

## Cold-email templates

Each of the 11 products carries a subject, a body under 90 words, a DM, three follow-ups, objections, call points, a proposal outline and upsells. Principles:

- one specific trigger;
- one operational problem;
- one concrete offer;
- one low-friction question;
- no luxury clichés.

Template selection:

- `supply_email_template` for hotels, operators and venues (NOYA sends them clients);
- `partner_email_template` for the partnership track (for example, a developer introducing buyers);
- otherwise the client template.

`{{proof}}` is optional. It stays blank until a real, approved proof line exists.

## Acceptance result (30 Sep 2026, 19 steps × 6 real signals)

| Scenario | Playbook | Result |
|---|---|---|
| HYROX Cairo, 14–15 Nov | SPORTS_EVENT_EGYPT | All 19 steps pass. Two opportunities from one event (Athlete & Team Desk, Event Concierge Desk). Won → project → paid → GP 12,500 → feedback and expansion tasks. |
| El Gouna Film Festival, 15–23 Oct | FILM_FESTIVAL | All 19 steps pass. Event Concierge + VIP Guest Desk. The event is not duplicated. |
| Starlight Festival, Pyramids, 9–10 Oct | FESTIVAL_ENTERTAINMENT | All 19 steps pass via the promoter (EXIT Festival). |
| The Oberoi Melouk / Malekat | HOTEL_OPENING | Partnership track: supply email → won → partnership ACTIVE. STRATEGIC was correctly refused. |
| DAMAC Cairo launch at GEM | PROPERTY_LAUNCH | Partnership (NOYA Private, partner email) plus a sales opportunity (VIP Guest Desk). STRATEGIC was correctly refused. |
| Mel Gibson shooting in Egypt | PRODUCTION_SHOOT | Correctly stays in RESEARCH: no organisation is named in the source (`QUALIFICATION_INCOMPLETE`). |

Defects found by the test and fixed (migration `20261001106000_acceptance_fixes.sql`):

1. `{{proof}}` blocked two products from producing any email.
2. A developer partner received a private-client email.
3. The Oberoi, a supplier, received the travel-agency pitch.
4. Dates rendered as "14 November ,".
5. The festival email repeated the event name three times.
6. Replies logged outside Gmail did not count as conversations.

The acceptance test's contacts are labelled TEST and rolled back. A real run needs a real decision-maker for each organisation.

## Known limits

- One reply alone scores 19/100 (COLD). A second reply or a meeting makes it WARM. This is deliberate: strength measures the relationship, and the deal stage measures the deal.
- Partners: 0. The CRM has no company marked partner or supplier. Partnerships appear as they are won or recorded, never guessed.
- Decision makers for the five qualified signals are not yet identified. The CONTACT_RESEARCH tasks are open in Sales & Outreach.

## Execution rules (3 Oct 2026)

- **Daily target: 15 quality actions.** 5 new emails, 5 LinkedIn messages, 3 follow-ups, 2 warm reconnects, with 3 working days (45) kept ready. `queue_health()` shows each line's shortfall on Command. A shortfall is shown, never filled with weak prospects.
- **Follow-ups.** Marking a hand-sent LinkedIn / WhatsApp / Instagram / email task *done* logs the send and books follow-up 1 for +4 days. Marking follow-up 1 done books follow-up 2 for about +10 days. A reply, a call, a proposal, a decline or do-not-contact cancels whatever is pending. Nothing is ever sent automatically. *Dismiss* means it wasn't sent, and books nothing.
- **Queue order.** 1) warm relationships; 2) people who replied before; 3) repeat-referral B2B partners; 4) high-quality new accounts; 5) speculative cold targets last. Celebrity cold DMs with no warm route are parked (status WAITING).
- **Working universe.** A company counts only with a written reason (`companies.universe_status = 'QUALIFIED'` plus `universe_reason`). The target is 300–500, built progressively. Batch 1 (3 Oct) added 39 researched accounts: 8 private office, 8 travel partners, 7 brand/PR/production (shortfall of 1, shown honestly), 6 weddings, 6 hotels and 4 live signals.
- **Hunter.** LinkedIn first. Hunter is used only for high-priority named people with no public email, after Adam approves a paid plan. New prospect opportunities are created as READY or RESEARCHING (never NEW), so workflow 05 doesn't spend credits on them.
- **Measurement.** `commercial_weekly_metrics()` gives weekly figures by segment: new accounts, contacts, verified emails, LinkedIn-ready, sends, replies, positive replies, meetings, proposals, wins and revenue. It appears under Performance → Finance. Allocation changes are recommendations for Adam only.
