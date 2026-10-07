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
- **Follow-ups.** Marking a hand-sent LinkedIn / WhatsApp / Instagram / email task *done* logs the send and books follow-up 1 for +4 days. Marking follow-up 1 done books follow-up 2 for +6 days (changed 4 Oct). A reply, a call, a proposal, a decline or do-not-contact cancels whatever is pending. Nothing is ever sent automatically. *Dismiss* means it wasn't sent, and books nothing.
- **Queue order.** 1) warm relationships; 2) people who replied before; 3) repeat-referral B2B partners; 4) high-quality new accounts; 5) speculative cold targets last. Celebrity cold DMs with no warm route are parked (status WAITING).
- **Working universe.** A company counts only with a written reason (`companies.universe_status = 'QUALIFIED'` plus `universe_reason`). The target is 300–500, built progressively. Batch 1 (3 Oct) added 39 researched accounts: 8 private office, 8 travel partners, 7 brand/PR/production (shortfall of 1, shown honestly), 6 weddings, 6 hotels and 4 live signals.
- **Hunter.** LinkedIn first. Hunter is used only for high-priority named people with no public email. No paid plan (decision: wait two weeks, 4 Oct). New prospect opportunities are created as READY or RESEARCHING (never NEW), so workflow 05 doesn't spend credits on them.
- **Measurement.** `commercial_weekly_metrics()` gives weekly figures by segment: new accounts, contacts, verified emails, LinkedIn-ready, sends, replies, positive replies, meetings, proposals, wins and revenue. It appears under Performance → Finance. Allocation changes are recommendations for Adam only.

## Operating standard (4 Oct 2026)

Migration `20261004100000_operating_standard.sql`; check `supabase/tests/operating_standard.sql` (rolled back, 5/5 pass).

**Working account universe** (`companies.universe_status`, re-run with `universe_reclassify()`):

| Status | Rule | 4 Oct |
|---|---|---|
| QUALIFIED | written reason + confirmed decision maker + usable channel (verified personal email, LinkedIn profile or prepared LinkedIn message, or Instagram for a non-formal sector) | 64 |
| NEEDS_REVIEW | person exists but unconfirmed, or confirmed with no usable channel | 21 |
| RESEARCHING | no named person yet | 51 |
| PARKED / EXCLUDED | Adam's decision; never overwritten | 0 |

Before 4 Oct all 136 were counted as qualified. That was wrong.

**People.** `contacts.identity_status` is CONFIRMED or NEEDS_VERIFICATION. It is set from evidence: an inferred title, "needs verification", an appointment date to re-check, or a person who has left. A send task (LinkedIn / Instagram / WhatsApp / email READY) for an unconfirmed person becomes **VERIFY FIRST** (trigger `verify_first_gate`), so it never counts as send-ready.

- Mark it done when the person is confirmed: they become CONFIRMED and the message returns to the send queue.
- Dismiss it if it is the wrong person.

`hq_prepare_outreach` refuses unconfirmed people (`PERSON_NOT_CONFIRMED`).

**Cold-email standard.**

- *Structure:* Hi [First Name] → why them (one real sentence) → who NOYA is (one sentence) → commercial fit → one CTA. 90–130 words.
- *Subject:* short and professional, for example "NOYA x [Company]", "Egypt partnership" or "Egypt production support".
- *Signature:*
  ```
  Best,
  Adam Elshazly
  Founder, NOYA Concierge
  Global concierge & lifestyle management
  noyaconcierge.com · @noyaconcierge
  adam@noyaconcierge.com
  ```
  Workflow 12 makes the website, Instagram and email clickable. No logo, banner or images.
- *Where it applies:* workflow 05's prompt and code (gate flags anything under 85 or over 140 words, banned phrases, links or images, no CTA) and the 13 playbook templates.
- `outreach_quality(subject, body)` → PASS / NEEDS_EDIT / BLOCKED:
  - BLOCKED: wrong signature, unfilled placeholder, banned phrase, or a link or image in the body;
  - NEEDS_EDIT: length, greeting, more than one question, no CTA, or subject.
- `queue_health()` counts an email only if its draft is not BLOCKED, and counts a draft already in Gmail only once.

**Hunter ROI** (`hunter_roi()`, on Command):

| Credits | Usable emails | Sent | Replies | Meetings |
|---|---|---|---|---|
| 48 | 11 (34%, 4.4 credits each) | 5 | 1 | 0 |

Workflow 05 has an IF gate: Hunter runs only for priority ≥ 85, a confirmed contact (confidence ≥ 85) and no verified email. Search candidates never reach Hunter.

**Follow-ups.** Two steps, both from actual sends: +4 days, then +6 days after follow-up 1 is sent. Both cancel automatically on a reply, a call, a proposal, a decline or do-not-contact.

**Clean-out (4 Oct).**

- Celebrity cold approaches with no warm route (Huda Kattan, Samih Sawiris, Kendall Jenner) moved to LONG_TERM.
- Five opportunities with unconfirmed contacts moved from READY to RESEARCHING.
- El Gouna duplicate signal (lineup article) dismissed as `DUPLICATE_OF` the active festival signal. It had no opportunities, so nothing was merged, and the evidence is kept in its notes.

**Two-week operating period (4–18 Oct).**

- No building, no purchases, no automatic sends.
- About 15 actions a day, warm first. Shortfalls stay visible.
- Weekly clean-out check-in on 11 Oct; NOYA Commercial Performance Review on 18 Oct.

## Commercial Engine V2 (7 Oct 2026)

**Lanes.** `companies.acquisition_lane` holds one of six lanes. The daily mix lives in `system_config.acquisition_mix`, with floor 15 and target 20 in `daily_touch_target`.

| Lane | Daily slots |
|---|---|
| BRANDS | 6 |
| PARTNERSHIPS | 4 |
| WEDDINGS | 3 |
| CORPORATE | 3 |
| EGYPT_EVENTS | 2 |
| SPORTS_PRIVATE | 2 |

Unused slots are refilled from other lanes, warm routes first.

**Commercial Director.** `commercial_director_plan(p_dry_run, p_target, p_replan)` picks the day's accounts. The pool is QUALIFIED accounts whose relationship state is COLD. It excludes anyone who has an open ready/verify/review/follow-up task, was planned in the last 30 days, or was emailed in the last 60 days. A company that is a CLIENT, PARTNER_ACTIVE, PROPOSAL, MEETING_BOOKED or ACTIVE_CONVERSATION is never planned. Each pick needs a CONFIRMED person with a position. Picks are written to `outreach_candidates`.

**Workflow 18 (Daily Outreach).** Runs weekdays at 08:15 Cairo and defaults to DRY RUN. Each pick goes through:
1. Plan.
2. Prompt.
3. Draft, using the drafting model in `system_config.drafting_model`.
4. Fact check with Flash-Lite, looking for unsupported claims and presumptions about the recipient.
5. Hard gate: banned phrases, false familiarity, length, personalisation, and the company-name swap test.
6. One redraft with the failure reasons.
7. Save: `READY`, or `DRAFT_REVIEW_REQUIRED` if it still fails.

If the fact check is unavailable, the gate fails closed. In live mode the save creates a `<CHANNEL> READY` or `DRAFT REVIEW` task. When that task is completed the candidate is marked SENT; when it is cancelled, SKIPPED. Nothing sends automatically.

**Dashboard.** `commercial_today()` feeds the HQ "Today · commercial engine" panel. `commercial_learning(weeks)` breaks results down by lane, channel, angle and model.

**Acceptance test (6 Oct).** 16 of 20 accounts were planned (shortfall: Weddings 1, Corporate 2, Sports 1). The free Gemini tier rate-limited the fact-check pass, so all 16 were held for review. Moving the key to billing is the open decision.

## Commercial Engine V2.1: cost controls and honest metrics (7–8 Oct 2026)

**Decisions (Adam, 7 Oct).** D1 A: paid Gemini billing, with NOYA-side hard controls. D2 A: load the 13 reviewed drafts as HUMAN_REVIEWED. D3 B: search-only discovery; no Firecrawl top-up.

**AI cost guardrail.**
- Every Gemini call workflow 18 makes is logged in `ai_usage` with input, output and thinking tokens and an estimated cost.
- Prices live in `system_config.ai_pricing`: Gemini 3 Flash at $0.50 / $3.00 per 1M tokens; output includes thinking.
- Limits live in `ai_budget`:
  - target $5 a month;
  - approved ceiling $10 a month, which only Adam raises;
  - daily hold $0.75.
- `ai_budget_status()` returns OK, OVER_TARGET, DAILY_HOLD or HOLD. Workflow 18 checks it before planning. On a hold it stops drafting and raises one `AI BUDGET HOLD` alert task (`ai_budget_hold_alert`).
- A Google Cloud budget alert only warns. This guardrail is the stop.
- No auto-recharge and no other paid Google services.

**Workflow 18 v2** (same ID, `wqg2YVulPaqj61rq`). It makes one Gemini call per account:
- direct HTTP call;
- `thinkingLevel: minimal`;
- JSON response schema;
- exact `usageMetadata`.

A deterministic gate (`n8n/w18_gate.js`) replaces the AI fact-checker. It checks:
- banned phrases;
- presumptions about the recipient ("may require", "remains untapped", "suggests a", "few brands have", "as you expand", and similar);
- that every capitalised name and every number in the draft appears in the stored evidence (or the Egypt/NOYA allow-list);
- length: LinkedIn 200–300 characters (target 220–280), email 85–140 words (target 90–130);
- personalisation and the company-name swap test;
- repeated calls to action across a batch.

A failed draft gets one redraft that names the exact failures and unsupported words, then is saved as `READY` or `DRAFT_REVIEW_REQUIRED`. The workflow source is generated by `n8n/build_w18.py`. Pacing is 4 seconds between calls on the free tier; drop it to 0.5 seconds once billing is on.

**Two measurements, never merged.**
- `outreach_candidates.system_*` freezes what the workflow produced.
- `review_source = HUMAN_REVIEWED` marks a human rewrite (`outreach_candidate_human_ready`).
- `engine_metrics(from, to, batch)` reports separately:
  - system first pass;
  - redraft success;
  - evidence failures;
  - rate limits;
  - review required;
  - final ready after human review;
  - average calls, tokens and cost.
- Acceptance run 1 (6 Oct): system send-ready 0/16; ready after human review 13/16. Gymshark, NEWGIZA and Base Soccer are held, each with a research task.

**Discovery (D3).** The production search path is Serper (google.serper.dev) in workflows 02, 03, 04, 06, 07 and 08.
- Firecrawl scrape and tracking nodes are disabled, so the search item passes through. Qualification and entity extraction use the Serper snippet plus the decision-maker search.
- Firecrawl waits are cut to 1 second.
- Verified 7 Oct: 0 Firecrawl calls, 34 searches, 10 signals and 8 brands extracted from snippets.
- Scraping can be re-enabled per department later, only for candidates whose search evidence is thin.
- The backlog throttle no longer counts overdue tasks twice. When paused, it still researches 2 candidates per department per day.

**Planner refresh (dry run only).** `system_config.planner_options.refresh_stale_drafts` lets a dry run re-draft accounts whose hand-send draft has sat unsent for more than 3 days, for comparison. Tasks are never touched.

**Send queue.** On 7 Oct, 59 LinkedIn drafts were ready and unsent (46 older than 3 days). That queue, not supply, is the constraint on the 15–20 a day target.

## Growth Engine: continuous agents (7 Oct 2026)

**Target.** 60–75 new outreach-ready prospects per rolling 3-day cycle (about 23 a day), building a universe of 500+ companies. A prospect counts only when HQ holds a READY task with:
- company;
- confirmed person and role;
- evidence;
- commercial reason;
- channel;
- finished message.

A shortfall is shown, never padded.

**Agents (lane in `companies.acquisition_lane`).**

| # | Agent | Lane | Workflow |
|---|---|---|---|
| 1 | Hospitality & strategic partnerships (hotels, boutique/independent, villas, serviced/branded residences, groups, aviation, yachts, chauffeur, security, DMCs, event hospitality) | PARTNERSHIPS | 03, plus supply-side 07 |
| 2 | Brands / PR / production | BRANDS | 02 |
| 3 | Weddings & events | WEDDINGS | 04 |
| 4 | Travel / concierge / private network (advisors, travel designers, concierge and lifestyle firms, clubs, family and private offices, EAs) | TRAVEL_PRIVATE | 07 client-side, private-client side of 06 |
| 5 | Corporate | CORPORATE | 06 |
| 6 | Sports / talent / entertainment | SPORTS_PRIVATE | 08, once a day, selective |

Egypt event signals use workflow 17 (EGYPT_EVENTS).

**Daily mix.** `acquisition_mix`: Partnerships 6, Brands 4, Travel 3, Weddings 3, Corporate 3, Sports 1, Egypt events 0. Scaled to `daily_touch_target.target` = 23, with leftovers filled.

**Cadence (Cairo).** Departments 02/03/04/06/07 run three times a day, staggered:

| Workflow | Runs |
|---|---|
| 02 | 06:00, 12:00, 18:00 |
| 03 | 06:30, 12:30, 18:30 |
| 04 | 07:00, 13:00, 19:00 |
| 06 | 08:00, 14:00, 20:00 |
| 07 | 08:30, 14:30, 20:30 |
| 08 | 09:00 (once a day) |

Each run researches the next 4 best new candidates; already-researched domains are skipped. Mission `max_results` is 10.

Research never pauses because messages are waiting. `discovery_throttle` sets cap 10 with no pause threshold.

Workflow 18 drafts nightly at 21:30 in live mode. Passing drafts become hand-send READY tasks; failures become DRAFT REVIEW. Nothing sends. Workflow 05's schedule is paused, so workflow 18 is the single drafter.

**Search first.** Serper is the production search layer; Firecrawl is off. Workflow 03 adds 24 rotating hospitality queries a day across 40 destinations in:
- Egypt;
- UK, France, Italy, Spain, Greece, Switzerland, Monaco;
- UAE, Saudi Arabia, Qatar, Kuwait.

Workflow 07 adds 16 rotating strategic-partner queries a day across 16 markets.

**Contacts.** Hunter is disabled in all departments; use it only for selected high-value people, by hand. Verified email makes a prospect email-ready; a confirmed person plus LinkedIn makes it LinkedIn-ready.

**Intake.** Triggers classify agent records on arrival:
- `company_intake`: lane, RESEARCHING (watchlist saves are PARKED), and the reason taken from the agent's "Why NOYA" line.
- `contact_intake`: CONFIRMED needs name, role and a source (LinkedIn profile URL or source-backed note). Otherwise NEEDS_VERIFICATION, shown as "Likely – verify". A company with no person stays RESEARCHING ("Person required").
- `contact_requalify`: re-runs the universe rules for that company.

**Duplicates and relationships.** Before research, departments skip known domains (CRM plus Gmail history), recently researched domains and existing relationships. The planner skips anything not COLD: clients, partners, proposals, meetings, active conversations, recent declines, contact in the last 60 days, open tasks, or candidates in the last 30 days.

**Reporting.**
- `growth_cycle_report(since)`: by agent, country and vertical; people, email-ready, LinkedIn-ready, research still required, outreach-ready, agent runs and cost.
- `agent_performance(weeks)`: discovered, qualified, decision makers, ready, sent, replies, positive, calls, proposals, wins and revenue.
- The HQ Today panel shows the 3-day cycle against 60–75 per agent, AI cost against budget, and system versus human-reviewed draft quality.

## Contact & partnership enrichment: workflow 19 (7 Oct 2026)

**Why.** Departments find companies faster than they find the route in. Workflow 19 finds the route for companies already in the universe. It enriches existing records and never duplicates them, because ChatGPT research writes to the same Supabase.

**Contact hierarchy.** Route types, best first:
1. Named decision maker plus publicly listed business email. A public email stays `UNVERIFIED`, with its source URL.
2. Named decision maker plus LinkedIn profile.
3. Instagram: the person's handle, else the company account.
4. The right company inbox: partnerships, sales, press, events or general. Never support, careers, privacy or admin addresses.

Hunter runs only after these fail, and only by hand for high-value people.

**Flow** (11:00 / 17:00 / 21:00 Cairo, 12 companies per run):
1. `enrichment_queue(12)` picks companies with no usable confirmed route, in weighted round robin: hospitality ×3, weddings and brands ×2, travel ×1.5, corporate and Egypt events ×1, sports ×0.5. Each company is retried at most 3 times, at least 14 days apart.
2. Three Serper searches per company:
   - LinkedIn profiles, using lane-specific role words;
   - the Instagram account;
   - `"Company" "@domain"` for published emails.
3. One Flash-Lite extraction call per company.
4. Deterministic anti-fabrication check in `n8n/w19/verify.js`:
   - every name must appear in the cited search result, and that result must name the company;
   - emails and handles must appear verbatim;
   - a role is kept only if it appears in the result;
   - a LinkedIn profile that names the company outside its headline, for example in education, past roles or memberships, is saved as `NEEDS_VERIFICATION`;
   - at most 4 people per company, ranked by role.
5. `enrich_company_routes(p)` saves the results:
   - matches existing people by LinkedIn URL, email, or company plus name, and fills gaps only;
   - keeps `source_url`, `source_type` and `route_type`;
   - accepts an email only on the company's own domain;
   - logs Flash-Lite usage against the AI budget.

**Role relevance.** `role_score(position)` rates how useful a role is as a route in:

| Score | Roles |
|---|---|
| 5 | Founder, owner, CEO, chief, managing director, general manager, partner |
| 4 | Director, head, VP; partnerships, PR, events, marketing, sales or production managers |
| 3 | Other managers, producers, planners, executive assistants |
| 0 | HR, front office, guest relations, F&B floor, spa, legal, procurement, board seats |

Score-0 roles are never saved and never planned. The planner prefers score 4 and above.

**Planner.** `commercial_director_plan` follows the hierarchy:
- a named person first: email, then LinkedIn, then Instagram, then LinkedIn by name;
- otherwise the company Instagram account (brands, weddings, hospitality, travel);
- otherwise the right company inbox.

A company with a named person always ranks above a company with only a company route. A dry-run test draft never blocks the live plan unless a person reviewed it. When every model call for an account was rate-limited, the candidate is set to `SKIPPED` and planned again the next day.

**Drafting without a person.** For a company inbox or company Instagram account, workflow 18 writes to the team, starting "Hello,". The evidence states that there is no named person, and the model must never invent one.
