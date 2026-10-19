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

Workflow 18 drafts nightly in live mode at 21:30, 22:00 and 22:30, at most 10 accounts per run. The instance stops any run at 300 seconds, and each run picks up whatever is still PLANNED. Passing drafts become hand-send READY tasks; failures become DRAFT REVIEW. Nothing sends. Workflow 05's schedule is paused, so workflow 18 is the single drafter.

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

**Planner guards (7 Oct).**
- An agent's own watchlist save (scored below its minimum) is never planned or enriched.
- A person route needs a first and last name.
- Leftover daily slots follow the agent weights, so sports stays selective.

**Gate additions (7 Oct).**
- Presumptions such as "frequent destination for your members" and "your clients often…" are caught.
- So is flattery ("is notable").
- Every channel must open with a greeting.
- Hyphenated compounds ("Egypt-based") are checked word by word.

**Drafting without a person.** For a company inbox or company Instagram account, workflow 18 writes to the team, starting "Hello,". The evidence states that there is no named person, and the model must never invent one.

## Execution and growth in parallel (7 Oct 2026)

Adam's decisions were D1 A, D2 B (modified) and D3 B. The aim is 15–20 commercial actions a working day, while the agents keep finding 60–75 new contactable prospects every 3 days. The sales backlog never pauses research.

**Daily action queue.** `daily_action_queue(20)` returns between 15 and 20 actions, never fewer than 15, in this order:
1. Replies needing action: inbound messages with no later outbound in 21 days, plus `REPLY_ACTION` tasks.
2. Warm opportunities: an active relationship, or a warm-route, reconnect, meeting or approval task.
3. Follow-ups due within a day, to cold or recently contacted accounts.
4. Partnership outreach: the partnerships and travel lanes.
5. New prospect outreach.

Groups 1 and 2 always appear in full. At least 3 outreach slots stay open so new prospects keep moving. Follow-ups fill the rest. Each company appears once, under its highest group.

A ready draft that Adam explicitly approved (`tasks.ceo_approved_at`, for example AC Milan and PSG under D3) always appears, as "Approved send", at the front of the outreach slots. Lane weighting does not apply to it. Adam still sends it himself.

Ready drafts are scored by four things:
- the lane weight, partnerships highest and sports lowest;
- `role_score` of the person;
- the route: a verified email first, then an email draft, a LinkedIn profile, Instagram, anything else;
- how recent the draft is.

A draft with no named person is not ready to send. It is held out of the queue and counted as `waiting_for_person`, and workflow 19 looks for a decision maker.

**Revalidation, not redrafting (workflow 20, 10:15 Cairo).** Ready drafts older than 14 days drop out of the queue until revalidated. `revalidation_queue(15)` runs the deterministic checks:
- is the company still qualified?
- is the relationship still cold?
- has there been no Gmail interaction since the draft?
- is there no newer draft for the same person?

The workflow adds two more:
- a date test on the why-now line;
- one Serper search, `site:linkedin.com/in "First Last" "Company"`, to confirm the person is still in role. The result is `STILL_IN_ROLE` only when a headline carries both the name and the company, and `MOVED` only when the headline names another employer and the result never mentions this company.

`revalidation_save` then decides:

| Decision | When | Effect |
|---|---|---|
| KEEP | Everything still holds | Draft kept; `revalidated_at` set; note added |
| FIND_PERSON | Still valid, but the draft names no person | Draft kept but out of the send queue; account re-queued for workflow 19 |
| REPLACE_PERSON | The person moved | Draft closed; account re-queued for workflow 19 |
| REDRAFT | The why-now date has passed | Draft closed so the planner drafts again from fresh evidence |
| CLOSE | Not qualified, no longer cold, new Gmail, or a newer duplicate | Draft closed |

First run: 5 drafts from 8–20 Sep. Tarte, Lombard Odier, ALDO and The Qode were set to FIND_PERSON. Scarlet Events was closed because the company is no longer qualified.

**Partnership model on every partner prospect.** `companies.partnership_model` takes one of:
- `REFERRAL`;
- `RECIPROCAL` (reciprocal destination support);
- `PREFERRED_STAY`;
- `EGYPT_EXECUTION`;
- `WHITE_LABEL_CONCIERGE`;
- `GUEST_CONCIERGE`;
- `CONTENT_TALENT`.

A trigger fills it on insert from lane, type and country (`partnership_model_guess`). A value set by a person or by research is never overwritten. Media, podcast, creator and production targets are `CONTENT_TALENT` in any lane. Client accounts (brands, corporate, sports) have no model by design. The planner puts the model, in words, at the start of the draft angle (`prospect_angle_prefix`).

**Creative concepts (workflow 21, 11:30 Cairo).** For media, podcast, YouTube, publication, creator and production targets:
- one Flash-Lite call produces CONCEPT (what could be filmed), BACKDROP, NOYA ROLE and COMMERCIAL VALUE;
- BACKDROP comes from a fixed list: Pyramids of Giza, Mena House, Grand Egyptian Museum, the Nile, Aswan, Luxor, El Gouna, Red Sea, Western Desert, Cairo, or a private villa or resort;
- the prompt allows only the stored evidence;
- a deterministic check drops any capitalised word or number that is not in the evidence, the backdrop list or Egypt geography;
- the budget guardrail runs first;
- concepts are stored in `creative_concepts` (one per company), and the planner adds the concept to the draft angle.

First run: 4 concepts, all passed, costing about $0.0003.

**Instagram discovery.** Departments 02, 03, 04 and 07 treat a public Instagram profile as a discovery source only when it exposes a business route: an email, a website, a booking or contact route, a founder, a partnerships contact or a management company. The source URL is kept, and nothing is inferred. Workflow 19 searches Instagram only for companies with no Instagram account recorded, and published emails only for companies with no email.

**Search efficiency.**
- Each department run takes a rotating slice of its query bank (`n8n/live_code_2026_10_07/`). Consecutive runs search different queries.
- Known accounts are de-duplicated before research.
- Workflow 19 searches only for the missing route.
- Deep research runs only on the capped shortlist (6 per run for hotels and partnerships, 4 elsewhere).
- Discovery searches fell about 45%, and unique coverage rose about 1.5×.

**Serper allowance and cost (workflow 22, every 6 hours).** The workflow reads `GET https://google.serper.dev/account`, which spends no search credit, and stores the balance in `provider_balances`.
- `serper_usage(3)` reports measured burn once a full day of readings exists. Until then it reports the plan.
- At 7 Oct 03:05 UTC the balance was 41,045 credits, with a rate limit of 50 a second.
- Pricing: Starter $50 for 50,000 credits ($1.00 per 1,000), Standard $375 for 500,000 ($0.75 per 1,000). Credits expire after 6 months.

Planned searches a day:

| Source | Searches a day |
|---|---|
| Departments 02/03/04/06/07/08 | ~412 |
| Research, decision maker and resolve passes | ~130 |
| Workflow 19 | ≤108 |
| Workflow 20 | ≤15 |
| **Total** | **~650** |

That is ~1,950 searches per 3-day cycle, about $1.95. Before rotation it was ~2,900 per cycle. The balance lasts about 63 days.

**Next report.** `growth_scorecard(since)` covers:
- new companies (by source: agents, ChatGPT, other research);
- new decision makers;
- new public emails;
- new company inboxes;
- new LinkedIn and Instagram routes;
- outreach-ready count, by lane;
- hospitality partnerships;
- partnership prospects with a model;
- media concepts;
- wedding prospects;
- brand and production prospects;
- sends, replies and calls;
- Serper usage and AI cost.

## Agents command centre (7 Oct 2026)

**Why.** The agents were producing far more than HQ showed: Today lists only what Adam must do now. **Agents** is a new top-level HQ section, placed after Command. It shows what the virtual commercial department is doing and producing. Today, CRM and Outreach are unchanged.

**Views.**
- **Agent floor:**
  - CEO strip: agents healthy, new companies / decision makers / emails in the last 24 hours, ready opportunities, replies and calls in the last 7 days;
  - targets: contactable opportunities against 60–75 per 3 days, hospitality and partnership against 20–25;
  - best opportunities found today;
  - 8 acquisition agents and 4 support agents as cards;
  - the latest activity.
- **Agent drill-down** (tap a card): new finds, people (name, role, company, country, email with its trust state, LinkedIn, Instagram, source, confidence), opportunities, ready for Adam, researching (route still missing), rejected or held, discard counts from run logs, recent runs.
- **Email opportunities:** every prospect with a usable email.
  - Each card shows person, company, role, agent, market, email, where it came from, verification state, why NOYA, the opportunity, why now, draft state, prior relationship and last contact.
  - "What to say" opens the finished draft.
  - Filters: new, public, verified, needs verification, ready, sent, replied, follow-up. Vertical filters: partnerships, hospitality, brands, weddings, corporate, travel, media, sports.
- **Opportunity radar:** routes to money. Partnership models in plain words ("NOYA places suitable clients in their properties → they refer Egypt requirements back") and filmed Egypt concepts.
- **Activity feed:** stored events from the last 72 hours: runs, finds, people and emails found, drafts, revalidations, replies, rejections.

**Agents and their evidence.**

| Agent | Territory | Run evidence |
|---|---|---|
| Hospitality & Partnerships | lane PARTNERSHIPS | 03 run log |
| Brands / PR / Production | BRANDS | 02 run log |
| Weddings & Events | WEDDINGS | 04 run log |
| Corporate & Private Client | CORPORATE | 06 run log |
| Travel & Concierge Partnerships | TRAVEL_PRIVATE | 07 run log (added 7 Oct) |
| Media / Podcast / Content | media targets in any lane | workflow 21 usage and concepts |
| Sports & Talent | SPORTS_PRIVATE | 08 run log |
| Egypt Opportunities / Events | EGYPT_EVENTS | last signal saved (09 keeps no run log) |
| Contact Enrichment | all | workflow 19 usage |
| Outreach Drafting | all | workflow 18 usage, drafts, revalidations |
| Reply & Relationship | all | Gmail sync state (13, 15) |
| Commercial Director | all | plans and today's actions |

**Status rules.** Status comes from stored records only; nothing is animated.
- **Error:** an open system failure alert for the agent's workflow, or a logged agent that has missed its schedule.
- **Blocked:** AI budget hold, a provider failure from the health check, or every model call in the last 24 hours refused.
- **Working:** ran within its expected gap.
- **Waiting:** otherwise, with the real reason.

Notes such as "drafts using the Flash-Lite fallback" never block.

**Email trust states.**

| State | Meaning |
|---|---|
| PUBLICLY LISTED | Printed on a public page, with the source URL. Not SMTP-verified. |
| SMTP VERIFIED | An email provider confirmed the mailbox. |
| NOT VERIFIABLE | A verification provider could not confirm the address. |
| SOURCE NOT RECORDED | No source stored. Check before sending. |

**Security.** Everything is read through `hq_agents()` and `hq_agent(key)`, both gated by `hq_admin_email()`. Helpers (`agents_snapshot`, `agent_detail`, `agent_last_run` and the rest) and `agent_registry` (configuration only) are revoked from anon and authenticated. No CRM data is copied.

**Acceptance.** 186/186 HQ checks pass, including 26 for Agents run against a live snapshot (git-ignored):
- every agent card;
- statuses with real reasons;
- CEO figures;
- the drill-down (finds, people with sources, opportunities, READY, rejected);
- email filters and provenance;
- radar;
- feed;
- no write calls;
- the phone path (bottom-bar Agents → tap Partnerships → today's companies, decision makers, emails, ready);
- no horizontal overflow at 390px.

## Email & Contact Intelligence (8 Oct 2026)

**Why.** Qualified prospects were reaching the outreach desk with a LinkedIn route and no email. The enrichment agent is now **Email & Contact Intelligence**: the right person, the right email, the proof, and the strongest commercial angle. No new HQ section; the work shows on the Agents floor and inside Email opportunities.

**Workflow 23 — Email Intelligence** (03:15, 09:45, 15:45, 23:15 Cairo; 8 companies a run; `n8n/w23/*.js`, built by `n8n/build_w23.py`).
1. **Queue.** `email_gap_queue()`: qualified, cold, a commercial angle, no usable named or department email. Ranked by strategic value (hospitality first), decision-maker quality, partnership potential and the chance of a public email. A company is retried after 14 days, 3 attempts at most.
2. **Search (2–4 Serper calls).** The company's own contact / team / about / press / partnerships pages; its domain printed anywhere (press releases, exhibitor directories, speaker pages, PDFs); the known decision makers with the domain; the Instagram profile.
3. **Read up to 5 official pages** (contact first, then team, partnerships, press, homepage; `/contact` and `/contact-us` when search finds no contact page).
4. **Extract deterministically.** Mailto links, HTML entities, Cloudflare-protected addresses, "name [at] domain" spellings. Nothing is constructed: an address is kept only if it is printed.
5. **Attribute.** One Flash-Lite call per company says who owns each address and which priority-role people are printed on the pages.
6. **Proof check.** An owner must be named next to the address, or the address must spell a named person. A role is kept only if its words are in the evidence. A personal-looking address nobody can be tied to is dropped.
7. **Save** with `email_intel_save()`: person, role, exact email, source URL, source type, found date, tier, state. Every attempt goes into `email_research`, including NO_EMAIL_FOUND.

**Tiers.** 1 named person · 2 department (partnerships, sales, commercial, marketing, PR, press, media, events, weddings, concierge) · 3 company inbox (info, hello, reservations, enquire), only when nothing better exists · LinkedIn / Instagram are routes, never counted as email leads.

**Honest state.** PUBLICLY LISTED (printed on a public page, source kept, not SMTP-verified) · SMTP VERIFIED (a provider check on record; an imported "verified" with no provider stays unrecorded) · RISKY · INVALID · UNVERIFIED. Hunter is not used by workflow 23.

**What is never saved.**
- **Wrong domain.** Addresses from a domain that does not carry the company's name: `domain_trusted()`. A news site or awards page saved as the website is surfaced in the company notes, never used.
- **Discovered domain.** When no trusted website is on file, the official domain is taken from search only if it is almost entirely the company's name. For one-word names, the result must also carry the company's sector, city or country.
- **Another property's inbox.** For a property on a chain domain (Kempinski Nile Hotel on kempinski.com), an address must name the property.
- **Sub-unit inboxes.** One outlet or one property, not the company: `fb.reservations.tswq@`, `mandarina.concierge@`, `reservations.ny@`.
- **Broker addresses.** Data-broker and email-format sites (RocketReach, Datanyze, Prospeo, Unifers and similar), and pages that read like them ("Reveal contact details"). They are checked in the workflow and again in the database.
- **Placeholders and excluded addresses.** Placeholder patterns (`john.doe@`, `jdoe@`); careers, HR, privacy, support, billing, legal, no-reply.

**Commercial Director, email-first.** For each company the planner takes the first route that exists:
1. The named decision maker's own published or verified email.
2. The relevant department inbox, "for the attention of" that named person (stored as `route_contact_id`; the task reads "To: sales@… (Sales inbox, for the attention of …)").
3. Their LinkedIn profile.
4. The company inbox for their attention, when no LinkedIn profile is on file.
5. Instagram.
6. LinkedIn by name.

Companies with an email route rank first. Drafts keep the approved format: personal reason → NOYA in one sentence → specific fit → one CTA → signature, 90–130 words, no banners.

**Workflow 19, people by vertical.** The LinkedIn search uses each vertical's priority roles (`role_focus()`):
- hotel: GM, DOSM, commercial, partnerships, PR & communications, owner;
- villa / residences: founder, owner, MD, head of sales, partnerships, operations, guest experience;
- travel: founder, MD, partnerships, head of trade, B2B, product;
- weddings: founder, owner, creative director, lead planner, partner, events director;
- brands / production: brand partnerships, marketing, PR, experiential, influencer, creative director, executive producer, production, talent;
- corporate: travel manager, EA, chief of staff, events, workplace experience, travel procurement.

**HQ.**
- **Every acquisition card carries a company-level email funnel:** qualified → decision makers → direct + department → usable → email ready, plus SMTP-verified, LinkedIn ready and email gaps.
- **"Email gaps" opens that agent's gap queue inside Email opportunities.** Filters also include Named person and Department.
- **Email opportunities carry the 3-day email report:**
  - companies researched;
  - decision makers found;
  - named public emails;
  - department emails;
  - SMTP-verified;
  - emails still missing;
  - LinkedIn-only;
  - Instagram-only;
  - email and LinkedIn drafts ready.

**Acceptance test: 25 qualified Hospitality / Partnership companies with no strong email route** (`email_intel_tests`, tag `HOSP25_2026-10-08`; Starwood excluded as a defunct brand).

| Company-level route | Before | After |
|---|---|---|
| Named-person email | 1 (4%) | 10 (40%) |
| Named or department email | 1 (4%) | 11 (44%) |
| Any usable email (incl. company inbox) | 6 (24%) | 18 (72%) |
| No email, LinkedIn / Instagram only | 19 | 7 |

- **Saved:** 21 named emails, 4 department inboxes, 11 company inboxes and 8 people from official pages. All publicly listed with their source; none SMTP-verified.
- **Planner:** it now chooses email for 10 of the 25 (three of them to an inbox for the attention of a named person: two department inboxes, one company inbox).
- **Cost:** 29 Flash-Lite calls ($0.027) and 107 Serper searches, including a first pass that exposed two faults.
- **Fixed during the test:**
  - a grouped site query that returned nothing;
  - sub-unit inboxes;
  - broker sites;
  - a one-word-name domain match (Summits → summits.org, a charity);
  - empty-string emails (30 contacts) that hid a found address.

  Every wrong row was removed and the rule now rejects it automatically.
- **Limits:**
  - JavaScript-only sites (The Bowery Hotel) and big brands that publish forms, not addresses (St. Regis, Maybourne) stay LinkedIn-only.
  - Many named emails at chains are property PR / marketing contacts: real, published and dated by their source. The planner still prefers a sales or GM route when one exists.

## Verified email chain, hotel routing and domain provenance (8 Oct 2026)

Adam's decisions D1 A / D2 B. The final email flow:

**PUBLIC EMAIL → SMTP VERIFICATION → EMAIL READY → NEEDS REVIEW → ADAM APPROVES → UNSENT GMAIL DRAFT → OPEN IN GMAIL → ADAM SENDS.**

Approve never means send.

**Verification (workflow 24, `9k757A1TUpT6DDq2`, daily 08:40 / 20:40 Cairo, before the drafter)**
- Reads the live Hunter account first (`hunter_account_save` → `system_config.hunter_account`), then verifies the queue from `email_verification_queue()`:
  - publicly listed or unsourced addresses at qualified companies, never verified (or more than 90 days ago);
  - drafts waiting on verification first, then named people, then department inboxes, then general inboxes;
  - hotels in GM → Commercial → Sales → Partnerships order.
- PR / press addresses are verified only for content partnerships.
- Limits come from `system_config.email_verification`:
  - `daily_cap` 8 and `reserve_verifications` 5 on the Free plan;
  - `scope` NAMED_DECISION_MAKERS = confirmed named people with role score ≥ 4.
  - After Adam approves a plan: raise the cap and set `scope` to ALL.
- `email_verification_save()` maps Hunter results:

| Hunter result | Contact status |
|---|---|
| valid | VERIFIED |
| accept_all / webmail | RISKY |
| invalid / disposable | INVALID |
| unknown, 202 / 222 retry, errors | unchanged (free, retried later) |

- A verified address promotes any draft waiting on it to EMAIL READY. An invalid or risky one cancels the draft, and the company goes back to the planner.
- Never buys credits, never changes the plan, never contacts anyone.
- **First run (8 Oct, free allowance):** 7 definite answers on named decision makers:
  - 5 valid: Aman GM, Aman Head of Sales Americas, Preferred Hotels Senior Director Global Sales, Greycoat Lumleys MD, onefinestay Regional Director of Sales;
  - 1 accept-all: Oberoi Zahra GM;
  - 1 invalid: Brazen;
  - 1 Hunter "retry later".

**EMAIL READY means verified**
- The planner (`commercial_director_plan`) chooses EMAIL only for an SMTP-verified, provider-backed address: the person's own, or a verified department inbox for their attention.
- A publicly listed address is never EMAIL READY. If workflow 18 drafts to one, it saves `HOLD` and the task is titled **EMAIL NEEDS VERIFICATION** (WAITING). Workflow 24 then decides.
- `outbound_recipient_block_reason()` uses `email_state()`: VERIFIED requires a provider, not just a status.
- The Cheval Collection EMAIL READY task (publicly listed PR address) was relabelled, then cancelled under D2.

**Hotel routing (D2)**
- Applies to stay, reciprocal, referral, guest-concierge and white-label models at hotel / resort / hospitality companies (`partner_hotel_route`).
- Person order is GM → Commercial Director → Sales Director → Partnerships (`partner_route_rank`). Within that set, someone with a verified route comes first.
- The chosen person's confirmed LinkedIn beats any department inbox.
- PR / communications people and PR / press / media inboxes (`pr_role`) are skipped for every partnership model except CONTENT_TALENT: content, press, creator / talent stays, brand trips, editorial.
- Two open drafts to PR contacts were cancelled with that reason: Cheval Collection, and Four Seasons Red Sea (reciprocal).
- Dry-run check, rolled back:
  - Grand-Hôtel du Cap-Ferrat now routes to the GM's LinkedIn, not the two PR emails;
  - 0 email candidates on 8 Oct, because no planned company had a verified address yet.

**Approval → unsent Gmail draft**
- HQ › Sales & Outreach › Outreach › **Email review** (the default tab):
  - separate counts: verified emails ready today (target 40–50), LinkedIn ready, Instagram ready, addresses verified;
  - the live Hunter balance;
  - each verified draft with an editable subject and body;
  - **Approve → create Gmail draft** (`hq_approve_email`).
- Lists for drafts being created, unsent drafts in Gmail (**Open in Gmail**, `gmail_draft_url`), failures and sent.
- An unverified address shows the button disabled.
- `outbound_approve_candidate()` writes one DRAFT row (`outbound_emails.candidate_id`; `opportunity_id` is now optional). It moves the EMAIL READY task to WAITING (`ceo_approved_at`).
- Workflow 12 creates the Gmail draft, and `outbound_complete()` turns that same task into **SEND APPROVED DRAFT** with the Open in Gmail link.
- When Adam sends from Gmail, workflow 13 (`gmail_record_manual_send`) logs the interaction and follow-up, and closes the task. A draft deleted in Gmail cancels it.
- **Send is impossible in three places:**
  - constraint `outbound_emails_draft_only` (mode = DRAFT);
  - `outbound_approve()` and `outbound_claim()` refuse SEND;
  - workflow 12 has no send node (Explicit Send?, Gmail Send and their record / respond nodes removed; `n8n/gen_12_outbound_email_executor.py` regenerated).
- Rolled-back live test, every step as expected: approve → claim (DRAFT) → complete (task → SEND APPROVED DRAFT + link) → manual send (candidate SENT). SEND was refused, the SEND row was rejected by the constraint, and the unverified candidate was refused.

**Company corrections with provenance**
- `company_field_history` (old value, new value, reason, source, decided_by) is written by `company_correct()`, the one way corrections are applied.
- `companies.website_confirmed_at`: an official domain that does not spell the company name (db.com, ff.co, slh.com, ghmhotels.com, psg.fr…) is trusted for email research only once confirmed (`company_research_domain`).
- Workflow 23 no longer leaves a "please check" note. A name-matched official domain replaces an unconfirmed wrong website, with history.
- **Starwood Hotels & Resorts:** EXCLUDED (part of Marriott since 2016, source marriott.gcs-web.com). Its opportunity is ARCHIVED and its contacts are kept. Marriott work continues through St. Regis Hotels & Resorts and The St. Regis Cairo.
- **Corrected:**

| Company | From | To |
|---|---|---|
| Maybourne | hospitality-on.com | maybourne.com |
| Grand-Hôtel du Cap-Ferrat | worldtravelawards.com | fourseasons.com/capferrat |
| Jet Linx | wealthranking.org | jetlinx.com |
| Patterson Belknap | pplaw.com | pbwt.com |
| SNITCH | open.spotify.com | snitch.com (third-party listings, not first-party confirmed) |

- **Cleared and flagged** (no official site found):
  - Summits: pangeamembersclub.com is Pangea; now NEEDS_REVIEW, identity unresolved;
  - Beyond Members Club (Instagram URL);
  - Fait Accompli;
  - Seven Private Members Club;
  - Event Planet;
  - The Ritz-Carlton New York, Westchester (reported rebrand).
- 18 legitimate non-name domains confirmed.

## HQ V3 — six destinations, the AI workforce, the approval desk (8 Oct 2026) — FROZEN

Adam's final HQ instruction: consolidate, simplify, prove, freeze, operate. Nothing was restarted, no second CRM or database was
created, and no historical evidence was deleted. Every older screen still exists under **More**.

**Navigation.** Today · Agents · Outreach · Relationships · Club · Operations, then More (Agents & intelligence, Sales,
Records, Admin). Phone bottom bar: Today · Agents · Outreach · Relationships · More (Club and Operations sit in More).

**Today** shows only what needs Adam: replies, meetings and calls, Gmail drafts to send, failed Gmail drafts, outreach waiting
for review, due follow-ups, proposals and client issues. No metrics, no engineering warnings.

**Agents** (`hq_directors()`, `hq_director(key)`): ten Directors (Private Membership & Network, Hospitality & Stays, Travel &
Concierge Network, Brands & Production, Weddings & Private Events, Corporate & White-Label, Media & Culture, Sports & Talent,
Egypt Growth, Growth Social & Paid Media), the Strategic Partnerships Manager, and seven shared specialists (Research
Intelligence, Contact Intelligence, Email Intelligence & Verification, Outreach Writer, Relationship Memory, Reply &
Follow-up, Commercial Director). The n8n workflows stay underneath; `agent_registry.v3_role` / `mission` translate them.
- Status is derived, never animated: BLOCKED (a hard blocker), ERROR (last real activity older than `max_gap_hours`),
  WORKING (activity in the last 20 minutes), otherwise SCHEDULED with the next run time.
- Last run comes from each member's own evidence (`director_last_run`). Workflows 07 (7 Oct) and 09 (8 Oct) now log every
  run to `department_run_metrics`, so a run that saves nothing is still visible.
- Every per-Director number adds up to the support agent's total: verification queue (`email_verification_queue().waiting_by_agent`),
  decision makers missing, email gaps, outreach waiting for Adam.
- Drill-downs return true totals ("showing the latest 60 of 104"), never a silent cut.

**Outreach desk** (`hq_outreach_desk()`): Needs review / Approved & Gmail drafts / Follow-ups / Sent / Replied / Held /
Researching. Needs review = open outreach tasks with a usable route (email only when VALID_VERIFIED). Ordered email first,
then quality-gated drafts, newest first. Actions: Approve (re-checks the recipient, creates one unsent Gmail draft, stores the
draft id; never sends), Edit (`hq_outreach_edit`, original kept in `system_draft` / audit), Hold (date), Research more (back
to the agents, contact flagged on WRONG_PERSON / OUTDATED_ROLE, no duplicate), Reject (reason required; the company is held
from outreach for 180 days with provenance in `company_field_history`), Source. LinkedIn and Instagram: copy, open, Mark sent.
Every desk action is audited in `approval_audit` as `DESK_*`.

**Follow-ups:** follow-up 1 four days after the real send, follow-up 2 six days after follow-up 1 is sent, never more than
two; works without an opportunity; any reply cancels them (company / contact match when there is no opportunity).

**Email states:** VALID_VERIFIED, ACCEPT_ALL, PUBLIC_UNVERIFIED, UNKNOWN, INVALID, NOT_FOUND (`email_state_v3`). Only
VALID_VERIFIED counts toward the 40–50 a day target.

**Club** (`club_people`, `club_benefits`, `club_introductions`, `club_events`; `hq_club`, `hq_club_person`): structure only.
Nobody is added automatically; communities and introducer routes come from qualified CRM records.

**Operations** (`hq_operations`): confirmed delivery only — clients, won business, projects, revenue records, client issues.

**Growth, Social & Paid Media** (`hq_growth`): honest connection states (Instagram via Windsor paused by the free-plan account
limit; Metricool connected to Instagram but not readable by HQ; Meta Ads read-only and paused), the content approval pipeline
(Idea → Draft → Review → Approved → Metricool scheduled → Published → Performance), stored Instagram performance, concepts,
competitor patterns and attributed leads. Website go-live test enquiries are kept but never counted as leads.

**Acceptance (8 Oct):** A fresh prospect (Aman GM from the official media kit, Hunter-verified) · B outreach (two new verified
email drafts on the desk) · C approval created a real unsent Gmail draft with its id in 4 seconds (test record to NOYA's own
mailbox, then deleted) · D desk counts reconcile exactly with open outreach tasks · E/F real Gmail sends detected, follow-up
at +4.0 days, replies cancelled follow-ups · G every member shows real last/next run · H blocked by Metricool access ·
I 390 px screens without horizontal scroll. Tests: security scan, 202 classic UI checks, 70 V3 checks (Today and the Agents strip are held to the same reply and meeting counts).

**Freeze.** No new dashboards, agent categories, navigation redesigns or metrics unless something is broken or real commercial
performance proves a change is needed.

## Email-first outreach and the HQ Advisor (8 Oct 2026, final amendment)

Email is the primary cold-outreach channel. LinkedIn is a documented fallback; Instagram a selective lifestyle fallback.
Migration `20261010000000_email_first.sql`; workflows 23 (upgraded) and 25 (new).

**Route state per decision maker** (`contact_email_route`): VERIFIED (their own VALID_VERIFIED address) · VERIFIED_INBOX (a
verified partnerships / sales / events inbox for their attention) · NEEDS_VERIFICATION (an address found, waiting for the
provider check, at most 10 days) · RESEARCH_PENDING (full research has not covered this person: never run, run before they
were confirmed, older than 60 days, or run before the full checklist) · EXHAUSTED (research done, nothing verifiable).
`company_email_state` takes the best route across a company's decision makers; `prospect_routes()` lists every qualified company.

**LinkedIn fallback rule.** The planner (`commercial_director_plan`) emails VERIFIED / VERIFIED_INBOX prospects first in every
lane's quota; it chooses LinkedIn (or Instagram for lifestyle lanes) only for EXHAUSTED prospects and stores the reason
(`outreach_candidates.channel_reason`: "LINKEDIN FALLBACK — EMAIL EXHAUSTED. Email research DD Mon: N searches (site, indexed,
docs, person, people web, directory, instagram), M official pages read, K addresses seen. …"). RESEARCH_PENDING and
NEEDS_VERIFICATION prospects are not planned. A LinkedIn / Instagram message prepared before a verified email existed is
retired so the email replaces it. On the desk, a LinkedIn / Instagram message is in Needs review only as a fallback (label +
"Email checked" evidence); otherwise it waits in Researching with the reason.

**Email Intelligence (workflow 23), full checklist.** Per company, up to 7 searches — SITE (contact / team / partnerships /
press / sales pages), INDEXED (addresses on the domain anywhere: press releases, speaker bios, interviews, exhibitor pages),
DOCS (PDFs, media kits, press kits, brochures, fact sheets), PERSON (named decision makers + "@domain"), PEOPLE_WEB (the top
decision maker on speaker pages, interviews, credits, awards), DIRECTORY (wedding directories, travel trade press, agency
trade press, hotel press, by sector), INSTAGRAM (business bio) — and up to 7 official pages read (adds /about when no team
page is found). Only an address printed on the company's own domain (or its own Instagram bio) is kept; nothing is guessed or
built from a pattern; compliance / investor / careers / support inboxes are excluded. Each pass records what it checked
(`email_research.checked`, version 2). Queue: Brands, Weddings and Travel first, companies whose LinkedIn message is waiting
jump the queue, 12 companies a run, six runs a day (03:15, 09:45, 12:15, 15:45, 18:15, 23:15 Cairo).

**Provider step.** Verification (workflow 24) now covers every confirmed decision maker's address (role score 3+) and a
department inbox when no decision-maker address exists, cohort under test first, then Brands → Weddings → Travel →
Hospitality → Corporate. Workflow 25 (Hunter Email Finder, 20:55 Cairo) looks up a person by name + company domain only when
the company and person are established and public research is EXHAUSTED; the address is saved only when Hunter verifies it
valid on that domain (`email_finder_log`), after verification has used its share and with a credit reserve.

**Channel health and email coverage** (`director_channel_health`, on every Director card): verified email · needs
verification · email gap · LinkedIn fallback · Instagram fallback · needs review, and EMAIL COVERAGE = qualified prospects
with a VALID_VERIFIED email / qualified prospects with a confirmed decision maker.

**HQ Advisor** (`hq_advisor`, `hq_advisor_seen`, `hq_weekly_review`). Today opens with the greeting, a one-line brief (replies,
verified emails waiting for approval, approved Gmail drafts unsent, meetings, overdue follow-ups, Brands against its 8–12 a day
target) and at most five observations, each situation → meaning → recommended action, ranked: replies, unsent Gmail drafts,
emails to review, CONTACT ENRICHMENT BOTTLENECK (a Director with 8+ decision makers below 30% coverage), verification capacity,
research backlog, overdue follow-ups, prospect buffer. "Since your last visit" lists what changed. Agents carries the
bottlenecks and where NOYA is winning / wasting time (30 days of real replies and sends; LinkedIn reliance). The weekly
review: sent (email / LinkedIn), reply and positive-reply rate, meetings, proposals, wins, verified emails, email vs LinkedIn
drafts, coverage and results by Director, strongest opportunities, weakest bottleneck, recommended allocation. Rules fire only
on their numbers; nothing is invented.

**Cohort acceptance EF-COHORT-1008 (8 Oct 2026).** 60 qualified companies (20 Brands & Production, 20 Weddings & Events,
20 Travel & Concierge), each with a confirmed decision maker, all fully researched (average 6.0–6.5 searches and 4.3–5.0
official pages per company), then verified (workflow 24, 20:40 Cairo). `email_first_cohort_report('EF-COHORT-1008')`:

| Cohort | Qualified | Correct DM | Public email found (named / dept) | VALID_VERIFIED | LinkedIn fallback (with evidence) | Email in Needs review | Email coverage |
|---|---|---|---|---|---|---|---|
| Brands & Production | 20 | 20 | 6 | 2 | 16 (16) | 0 | 10% |
| Weddings & Events | 20 | 20 | 5 | 1 | 16 (16) | 0 | 5% |
| Travel & Concierge | 20 | 20 | 5 | 3 | 17 (17) | 0 | 15% |

Rule test: passed — every LinkedIn fallback carries its email-exhaustion evidence; no prospect was routed to LinkedIn before
research. Coverage test: low. Of the 54 companies where public research is exhausted, 23 publish a general inbox (info@ /
hello@ / enquiries@: Weddings 11, Travel 8, Brands 4), 21 publish no business address at all, and 10 publish only a press
address or an address that failed verification (accept-all domain or invalid). Remaining levers: provider lookup by name (workflow 25, capped by Hunter Free credits) and a policy on general inboxes for boutique
firms — both are CEO decisions, recorded in the acceptance report.

## Operating phase: volume through the email-first engine (8 Oct 2026)

No HQ redesign, no new agents. The goal is 75–100 new outreaches actually sent per working week, with email as the primary
channel. Migration `20261011000000_operating_volume_noya_private.sql`; live n8n code in `n8n/live_code_2026_10_08/`.

**Weekly targets** (`system_config.weekly_send_targets`). New outreaches sent per working week, Monday to Friday, Cairo; a
"new outreach" is the first message NOYA ever sent to that company:

| Director | Target |
|---|---|
| Brands & Production | 20–25 |
| Weddings | 12–18 |
| Travel & Concierge | 12–15 |
| Hospitality | 10–12 |
| Private Membership / Founders | 8–10 |
| NOYA Private — Athlete & Talent | 8–12 |
| Corporate | 3–5 |
| Media | 2–3 |
| **Total** | **75–100** |

Each Director keeps a buffer of at least two weeks of untouched qualified prospects with a confirmed decision maker.

**Planner.**

- The lane mix (`acquisition_mix`) is Brands 6, Weddings 4, Travel / Private 4, Hospitality 3, Talent 2, Corporate 1, out of
  23 touches a day; email fills each lane first.
- Every live run also retires LinkedIn and Instagram messages that a verified email now replaces (one cold touch per company).
- Every live run plans an email top-up: prospects that verified after the day's plan get an email draft the same day, at most
  10 a day (`planner_options.email_topup_per_day`).

**Discovery** (every working day, never paused for waiting drafts; `discovery_throttle` pauses only at 100,000):

- **Brands (02).** Fashion, jewellery, clothing, beauty, watches, automotive and luxury lifestyle brands running destination
  campaigns, shoots, creator trips, international campaigns, GCC / MENA expansion and production abroad. Also marketing, PR,
  creative and influencer agencies, and production companies.
- **Weddings (04).** Planners already running multi-day international weddings and UHNW celebrations.
- **Travel and Private Founders (07).** Boutique travel firms, luxury travel designers, lifestyle management and DMCs; founder
  clubs, business and executive communities, members clubs and family-office networks running retreats, dinners, trips and
  off-sites.
- **Hospitality (03).** Hotels, villas, resorts and residences open to creator and talent stays, brand shoots, production
  accommodation and content collaborations. This is the CONTENT_TALENT model, kept apart from preferred-stay outreach.
- **NOYA Private (06).** Representation agencies and the public Egypt occasions that bring talent.
- The research ceiling is 12 in 02, 04 and 06. The live cap is `discovery_throttle.normal_research_cap` (10). Each of those
  runs had been filling exactly to the old cap of 4.

**Drafting.** The W18 redraft states the email length as a hard number when the fallback model drafts. The drafting model's
free-tier daily quota (about 20 requests) is a known limit; see the operating report.

**HQ Advisor: five decisions a day**, in a fixed order:

1. What needs Adam.
2. Which Director is furthest under its pro-rated weekly target. It says whether sending or supply is the limit.
3. The weakest email coverage among the priority lanes.
4. The strongest commercial opportunities. A NOYA PRIVATE OPPORTUNITY leads when a representation agency has a verified
   decision-maker email and no NOYA contact yet.
5. Where to allocate effort, with each priority lane's prospect buffer in weeks of target.

Every line is a count or a record from the database.

**NOYA PRIVATE — ATHLETE & TALENT RELATIONS.** The Sports & Talent Director, upgraded:

- **Mission.** The trusted private concierge and on-ground Egypt partner for elite athletes, footballers, celebrities and
  artists, through their representatives. The representative keeps the client; NOYA privately handles Egypt, white-label
  where they prefer.
- **Representation first.** Roles in order:
  - agencies: founder / MD, senior agent, agent, player and personal managers, player care and services, lifestyle, client
    services, commercial, partnerships, operations, travel / logistics;
  - the celebrity side: talent and artist managers, publicists, tour managers, booking agents, PAs.
- **Excluded.** Scouting and recruitment are never a route; NOYA does not pitch transfers.
- **Outreach.** Short and discreet. One positioning sentence, no client names, no private-travel references. One question:
  would a short private-services overview be useful. The overview is `docs/NOYA_PRIVATE_EGYPT_DESK.md`, a draft for Adam's
  approval.
- **Measures.** 8–12 qualified agency outreaches a week. Success is agency relationships, referrals, Egypt trips and talent
  stays, not famous names.
- **Privacy.** Public, source-backed evidence only: no private travel data and no personal contact details.

**First operating night (8 Oct 2026).**

- **Approval → Gmail draft.** Two approvals made at 19:36 Cairo timed out inside workflow 12. The database answered slowly,
  and the claim and record steps each waited only 20 s. onefinestay's Gmail draft had been created and was recorded from the
  execution's provider ids. Preferred Hotels had no draft and was re-dispatched; both are now unsent drafts in
  noya@noyaconcierge.com.
  - Workflow 12 now waits 60 s on its database calls and retries recording the draft. A repeated `outbound_complete` returns
    NOT_PROCESSING, so the retry is harmless.
  - The claim is not retried, so it stays exactly-once.
  - An `outbound_emails` row left in PROCESSING with no `gmail_draft_id` for more than 10 minutes is the signal to check.
- **Email review desk, reconciled.**
  - Every EMAIL item awaiting approval has a VERIFIED route at both contact and company level.
  - Every LinkedIn item carries a documented email-exhaustion fallback, except four older curated tasks (J.P. Morgan,
    Etihad, Arab Bank, Mandarin Oriental). Their email research is queued; if it verifies, the planner's supersede rule
    replaces the LinkedIn task with an email.
  - Verified drafts that fail QA wait in Held with the gate's reason.
- **NOYA Private pool, cleaned.** The pool keeps representation only.
  - Parked, with history: LeoVegas (betting operator) and Collegiate Sports Connect (college-recruiting software).
  - gamma. (Larry Jackson's music and media company) carried a wrong website, gamma.app, which is a different company. It is
    corrected to thegamma.com per Wikipedia, still unconfirmed, and its LinkedIn draft is on hold to verify first.
- **Re-drafting a failed draft.** Cancelling a draft's review task marks its candidate SKIPPED through the task sync. To re-draft,
  cancel the task first, then set the candidate back to PLANNED; the next W18 run drafts it and opens a fresh review task.
- **Discovery cap, corrected (9 Oct 2026).** The 8 Oct research-cap raise had no effect because an earlier step, "Split
  Candidates By Lane", passed only 4 direct candidates a run. It now passes 14 in 02, 04 and 06, and 8 in 03. That step no
  longer scores "agency" down in 02 and 06, or "consulting" in 06, so NOYA Private's agency queries are no longer always
  cut. See `n8n/live_code_2026_10_09/`. The first measured runs are the 12:00 and 14:00 Cairo runs on 9 Oct.
  - **Measured on 9 Oct.** The 12:00–14:00 Cairo runs of 02, 03, 04 and 06 each researched up to their cap (10, 6, 10
    and 10 companies). They added 24 new companies; the six morning runs before the fix had added 10.
  - The extra volume also brought more article-sourced records whose saved "website" is a news site or an unrelated
    company. `company_research_domain` already keeps a domain that does not spell the company name out of email research,
    so those records are not emailable. The one exception was KOA (koa.com, which belongs to Kampgrounds of America).
  - Six such records were parked or cleared and flagged for review, with history kept.

## Final efficiency pass: email is the health metric (11 Oct 2026) — commercial architecture frozen

Migration `supabase/migrations/20261012000000_efficiency_pass.sql`. No new agents, no HQ redesign.

- **EMAIL READY is the KPI.** `acquisition_health()` splits qualified companies never contacted into: valid verified email
  ready (person or department inbox), verified general inbox ready, LinkedIn fallback, Instagram fallback, warm, and existing
  relationship. `queue_health()` leads with verified emails to approve or send; LinkedIn is a fallback line, never in the
  headline. HQ shows the split on Agents (not on Today) and in the weekly review. Reserve target: 100–150 email-ready
  prospects (`system_config.email_reserve`).
- **Backlog first, no expiry.** An address on file is a verification job, never a reason to fall back to LinkedIn. The
  10-day expiry in `contact_email_route` is gone. An unchecked address waits only when it sits on the company's confirmed
  domain (the same `company_research_domain` guard email research uses).
- **The verification queue works exactly what the route is waiting on.** `email_verification_queue` takes each cold,
  qualified company's best pending route: the decision maker's own address, then a department inbox, then a small firm's
  general inbox. Then come drafts held for verification, then department inboxes at companies with no decision maker yet.
  Rules:
  - one address per company;
  - company domain only;
  - no companies on hold, already verified, warm, or in Adam's own approach;
  - order: Brands, Weddings, Travel, NOYA Private, Hospitality, Private, Corporate, then Media and Egypt.
- **Hunter Starter (decided 11 Oct; Adam buys it, auto-recharge off).** `hunter_plan_caps()` reads the plan from workflow
  24's account snapshot, so caps change on their own when the plan changes.
  - Free: 8 verifications and 2 lookups a day.
  - Starter: 40 verifications and 25 lookups a day (at most ≈1,350 credits a month). The caps stop at a 1,500-credit
    monthly budget out of Starter's 2,000.
  - On a paid plan, a decision maker with no address gets a provider lookup (FINDER_PENDING) before any LinkedIn fallback.
  - Workflow 25 now asks for up to 25 lookups a run; the cap decides.
  - `hunter_daily_funnel()` tracks finder attempts and finds, then verifications, then VALID / RISKY / INVALID, credits,
    drafts, sends, replies and meetings.
- **Small founder-led firms (D4).** `general_route_eligible()` covers wedding, travel, concierge, creative, production,
  villa and lodge firms; brands, groups, hotels, banks, airlines and corporates are excluded.
  - Once named-person research has failed, a verified official general inbox is a route: VERIFIED_GENERAL.
  - Workflow 18 opens these emails "For the attention of <name>, <position>"; `outreach_quality` accepts that line before
    the greeting.
- **One company, one active cold route.** `cold_route_sweep()` runs in the nightly planner. It keeps a LinkedIn or
  Instagram task only where the person's and the company's email routes are exhausted with research evidence. Otherwise it:
  - supersedes the task with a verified email;
  - cancels duplicate cold touches;
  - or moves the company back to email research or verification.
  It writes the reason on the task and the candidate; nothing is deleted.
  Planner changes:
  - LinkedIn / Instagram is planned only when the whole company is exhausted;
  - Adam's own approaches block cold planning.
- **Reserve discipline.** The planner keeps at most 30 unsent email drafts and 20 open LinkedIn / Instagram drafts. Forty to
  fifty verified drafts a day is scaling capacity, not a quota.
- **Attribution.** `outreach_attribution()` attributes each reply to the message it answers (same Gmail thread first, else the
  latest earlier message to that company), then to the first message of that sequence. It reports email and LinkedIn
  sends → replies → positive → meetings by Director and send week.
- **Advisor.** The coverage observation is now the per-Director funnel: decision makers → emails found → valid verified → in
  Needs Review, marked CONTACT or VERIFICATION BOTTLENECK. It never praises LinkedIn volume. The brief carries
  "Email ready: n (target 100–150)".
- **Speed.** `prospect_routes()` evaluated the route once per output column; `offset 0` makes it once per company
  (5.4 s → 2.7 s with the richer route). This speeds up the desk, Advisor and planner.

**Measured on 11 Oct, after the pass.**
- **LinkedIn / Instagram cold tasks.** 116 tested.
  - 71 survived true email-exhaustion testing.
  - 42 moved back to email: 37 to verification, 5 to email research.
  - 3 duplicate cold touches cancelled (El Gouna Film Festival ×2, The TriFactory ×1).
- **Unverified addresses.** 305 unverified addresses sit at qualified companies.
  - 82 are worth a credit: the right person or inbox, own domain, cold, one per company. By Director: Weddings 21,
    Corporate 18, Hospitality 15, Travel 9, Brands 7, Media 6, Private 3, NOYA Private 2, Egypt 1.
  - The rest are second contacts, non-decision makers, press inboxes, held websites, or contacted companies.
- **Provider-lookup backlog.** 117 decision makers whose email research is exhausted, with no address.
- **Email ready.** 13, against a reserve target of 100–150. Hunter Free has about 2.5 credits left until 27 Oct.
- **The bottleneck is verification capacity, not discovery.** About 24 new qualified companies and 75 new decision makers
  arrive a day.

**Follow-up (11 Oct, evening).**
- **Hunter Starter approved by Adam.** It is bought in Hunter (monthly, auto-recharge off); no session has Hunter billing
  access. The plan is read at every workflow 24 run (08:40 and 20:40 Cairo), and the caps switch to Starter on their own.
  The 20:40 and 21:20 checks on 11 Oct still read Free.
- **Credit order.** Brands, Weddings, Travel, NOYA Private, Hospitality, Corporate, then Private Membership, Media and Egypt.
- **Media Director false error, fixed.** Workflow 21 now records a heartbeat on every run in system_config 'heartbeat_w21',
  which `agent_last_run('MEDIA')` reads. A stalled workflow still shows ERROR. See
  `supabase/migrations/20261012000100_media_heartbeat_credit_order.sql` and `n8n/build_w20_22.py`.

## Freeze: NOYA HQ — frozen and operating (16 Oct 2026)

Adam's final instruction: clean, verify, freeze, operate. From here HQ changes only for real bugs, security, data integrity,
or a commercial improvement proven by results. No redesign, no new primary navigation, CRMs, dashboards or agents.
The next major build is the NOYA Studio & Delivery Layer.

**Hunter decision (Adam, 16 Oct).** Hunter stays on Free until the 27 Oct allowance reset; no paid upgrade is recommended
before the post-reset numbers prove the case. It is stored in `system_config.hunter_decision`, and the Advisor reads its
wording from there (no "upgrade to Starter" prompts). Until the reset:
- research, qualification, public email discovery and correct-person research continue;
- the verification queue builds in Adam's order (Brands, Weddings, Travel, NOYA Private, Hospitality, Corporate);
- the final reserve (5 verifications, 3 Finder credits) is never spent.
A scheduled task runs the controlled test on 27 Oct (07:00 UTC): the best verification and Finder candidates first, then
a report with verification attempts, Finder attempts, credits, VALID / RISKY / INVALID, new EMAIL READY by Director,
remaining backlog, days until credits run out, and a verdict, with evidence: "Free is enough" or "Starter is justified".
Migration `20261016000000_freeze_hunter_hold.sql`.

**Production defect 1: AI qualification outage (fixed).** From about 02:30 UTC on 16 Oct, gemini-3.1-flash-lite answered
503 (high demand). Every discovery workflow's "backup" model was the same model, so qualification produced nothing.
Candidates were kept as NOT_EVALUATED_PROVIDER_FAILURE, never as rejections. The fix:
- discovery 02–08 now fall back to gemini-3.5-flash-lite;
- 09, 19, 21, 23 and the 00b health probe use it outright;
- drafting (18) is unchanged.
A live Brand & Production run at 17:40 UTC completed with 0 provider failures, and the provider alert was closed.

**Production defect 2: outage victims locked out for 60 days (fixed).** Merge & Cap in 02/03/04/06 marks each candidate
"researched" before qualification, and the 60-day skip then hid every company whose qualification failed on a provider
error. Merge & Cap now releases each recorded provider failure once, so the next discovery hit evaluates it. Live code is in
`n8n/live_code_2026_10_16/`; 07 and 08 have no such skip.

**Data-integrity defect 3: duplicate accounts from website corrections (fixed).** Workflow 23 corrected wrong websites (the
news site a discovery run saved) to the official domain without checking whether the domain was already an account, which
created second copies of Aman, Maybourne and Mandarin Oriental. Workflow 07 also saved Ten Lifestyle Group, although Ten
Technologies Group (its new name) was already the account. Migration `20261016100000_account_duplicate_guard.sql`:
- **Merged, the 29 Sep way; nothing deleted.**
  - The older record stays the account, and people it lacked move across: Aman +7, Ten +6, Mandarin +1, Maybourne +1.
  - The duplicate's opportunity is archived.
  - The duplicate keeps its row, with MERGED_INTO and universe EXCLUDED.
- **Marked SEPARATE_ACCOUNT.** Two Four Seasons hotels, and MCI Middle East vs MCI UK.
- **`company_account_guard()`.** A website correction (`company_correct`) or an agent save (`company_intake`) that lands on
  a live account's domain parks the newer record as POSSIBLE_DUPLICATE_OF, with the reason on the record. Parking means no
  cold outreach and no verification spend. The daily operating check merges it or marks it SEPARATE_ACCOUNT; nothing
  merges by itself.
- **Result.** `company_account_duplicates` is empty, and live accounts share no contact email.

**Sanity check (16 Oct, after the fixes).**
- **Navigation.** Today, Agents, Outreach, Relationships, Club, Operations, and More / Admin; technical items only under Admin.
- **Today.** Replies, emails to review, approved Gmail drafts, follow-ups, meetings, proposals, best opportunities and client
  issues. System alerts stay on the classic Command page under More.
- **Agents.** Agent labels say "Email Finder lookups", not "provider lookups".
- **Approval.** It creates an unsent Gmail draft in noya@ and never sends: workflow 12's only Gmail step is "create draft".
- **Security.** 0 SECURITY DEFINER functions are executable by anon. All 63 that authenticated users can call check
  `hq_admin_email()`. RLS is on every public table. The HQ security scan passes.
- **Tests.** `hq` `npm test`: 202/202 classic and 85/85 V3 UI checks, no horizontal overflow at 390 px. Fixtures were
  refreshed from live data. One V3 assertion now picks the first named person, because the people list legitimately
  includes team inboxes with no name.
- **Daily operating check.** Weekdays at 09:20 Cairo it also resolves possible duplicates and confirms provider-failure
  candidates are released.

## CEO effectiveness pass: Dashboard, visible workforce, revenue conversion (16 Oct 2026) — HQ frozen again

Adam's brief: keep the frozen architecture, but make HQ understandable in 10 seconds, make the AI workforce visible, and turn
outreach into projects. Nothing was rebuilt: no new Director, CRM or dashboard product. Migration
`20261016200000_ceo_effectiveness.sql` holds every database change (applied live; file and live bodies match by md5).

**Navigation.** Dashboard, Agents, Outreach, Relationships, Club, Operations, More / Admin. Dashboard replaces Today; the phone
bar is Dashboard, Agents, Outreach, Relationships, More. Each screen has one job:
- Dashboard: run the company.
- Agents: see the workforce.
- Outreach: approve communication.
- Relationships: build the network.
- Club: develop the private network.
- Operations: deliver projects.
- More / Admin: run the infrastructure.

**Dashboard (`hq_ceo_dashboard()`, admin-gated read).**
- **Strip.** Emails needing review, Gmail drafts ready to send, replies needing Adam, meetings and calls, active
  opportunities, active projects, won revenue. Revenue shows £0 / No recorded revenue until a revenue record exists.
  "Emails needing review" includes verified-email drafts that failed the quality check and wait under Held for Adam's edit.
- **What needs you today.** Each row has the person or company, why it matters, the next action, the age or due date, the
  Director, and one button. Stuck Gmail-draft approvals appear here with a Retry.
- **HQ Advisor.** 3–5 observations, each Situation / Meaning / Recommended action.
- **Top commercial opportunities.** Live conversations first, then the strongest verified-email prospects. Each has the
  project type, why now, relationship, next move (aware of who wrote last in Gmail), evidence, strategic value and contact.
  No deal value is estimated.
- **From outreach to business.** This week and the last 30 days, from sent to revenue, plus the pipeline with stuck counts.
  Briefs / concepts counts only concepts actually used with a counterpart and project briefs; internal AI concept ideas
  (status PROPOSED) are not progress.
- **AI workforce.** One row per Director: status, mission, today's output, blocker, top opportunity. Working is shown only
  while a scheduled run is in progress (`agent_prev_run` within 15 minutes and no newer activity); otherwise
  "Scheduled — HH:MM".
- **Weekly CEO review.** Emails, LinkedIn fallbacks, replies, positive replies, meetings, briefs, proposals, wins and
  revenue; then the top 5, biggest bottleneck, Director needing attention, the Advisor's recommendation, and money as
  recorded ("Not recorded" otherwise).

**Agents.** Each Director card shows:
- status, what it is working on, last completed work, next run;
- today: companies, people, verified emails, outreach ready, replies, opportunities;
- 7 days: sent, replies, positive, meetings, proposals, wins;
- the email funnel: decision makers → found → verified, plus waiting verification, email ready and LinkedIn fallback;
- blockers and the top opportunity.

Drill-down tabs: Overview, Opportunities, People, Emails, Outreach, Relationships, Projects. Opportunities are framed as
projects: what they did, the concept (Media), why Egypt, who decides, what NOYA would handle, next step. `project_type()`
derives the project from the opportunity type, company type and sector only, so boilerplate descriptions don't decide it.
Missions were rewritten for Brands, Weddings, Media, NOYA Private and Hospitality. Travel is now "Travel & Concierge
Partnerships". The Brands query bank gained activewear, swimwear, resortwear, womenswear, streetwear and premium clothing,
plus the lookalike seeds and lookbook / creator-trip signal queries.

**Outreach.** Tabs: Needs review, Gmail drafts, Follow-ups, Sent, Replied, Researching / held.
- Email is the default channel.
- Filters: Director, channel and project type.
- Compact card: person, company, role, Director, project, verified email, why them, why now, subject and preview.
- Primary actions are Approve, Edit and Hold; Research more, Source and Reject sit under •••.
- Approve creates one unsent Gmail draft and never sends.

**Relationships (`hq_network()`, admin-gated read).** Tabs: Important people, Companies, Warm relationships, Pipeline,
Opportunities, Going cold. Each row shows who, company, why important, last interaction (and who wrote last), current
opportunity, next action and owner. Multipliers (agencies, planners, private networks that repeatedly create work) are
marked and ranked first.

**Club and Operations.**
- **Club tabs.** Private clients, Potential members, Introducers, Members, Benefits, Partner privileges, Events,
  Introductions. Real people only, added by Adam.
- **Operations.** Active projects, Upcoming, Awaiting client, Awaiting supplier, Payment required, Completed. Never
  prospects; honest when empty.

**Real defects found and fixed in this pass.**
1. **Outreach Writer falsely in ERROR.** Workflow 18 ran on schedule but, with no verified email to draft, made no AI call;
   the status only read AI calls. `commercial_director_plan` now writes `system_config.heartbeat_w18` on every live run,
   and `director_last_run('WRITER')` reads it (the 11 Oct Media heartbeat pattern).
2. **Approved email stuck before Gmail (second time; first on 8 Oct).** Workflow 12's claim call timed out on the n8n
   side while the database committed the claim, leaving the row PROCESSING with no Gmail draft and no way back.
   - `hq_redispatch` now recovers a PROCESSING claim older than 10 minutes with no Gmail draft id: it resets it to
     APPROVED, audits RECOVER_CLAIM and dispatches workflow 12 again.
   - The desk offers Retry, and the Dashboard lists it.
   - Greycoat Lumleys (approved by Adam at 21:26 Cairo) was recovered this way, and its unsent Gmail draft exists.
3. **Briefs / concepts inflated.** The funnel counted 7 internal AI concepts that were never sent. It now counts only
   USED concepts and project briefs (0 today).
4. **W13 reply classifier backup.** The backup pointed at a model with no credential; it is now gemini-3.5-flash-lite.

**Security.**
- `hq_ceo_dashboard`, `hq_network` and `hq_redispatch` are SECURITY DEFINER, check `hq_admin_email()` and are not
  executable by anon.
- A signed-in non-admin is refused by all three (tested).
- 0 SECURITY DEFINER functions are executable by anon.
- The HQ security scan allow-lists the two new reads.
- No send path exists.

**Tests.** `hq` `npm test`: security scan pass, 202/202 classic UI checks, 94/94 HQ acceptance checks (`tests/ui_v3.mjs`,
rewritten for this pass). Screenshots at 1440 and 390 px cover Dashboard, Agents, Brands & Production, Weddings, Media &
Culture, NOYA Private, Outreach email review, Relationships, Club and Operations, with no horizontal overflow at 390 px.
The live desk had no email in Needs review that night, so to prove Approve on an email the test copies one verified-email
draft held for a quality edit into Needs review, in memory only.

**Known limits, reported rather than rebuilt.**
- **Discovery is saturating.** Brands ran four times on 16 Oct with 0 new qualified companies: 42 candidates a run, most
  already known. The daily check now reports two days at 0 with known accounts dominating as query-bank saturation.
- **Hunter Free is used up until the 27 Oct reset test.** Email Intelligence is therefore Blocked, and no new verified
  email reached Needs review that night.

From here HQ is frozen again. Changes are permitted only for real bugs, security, data integrity, or a commercial
improvement proven by operating results. The next build is the NOYA STUDIO & DELIVERY LAYER.

## Production fix: HQ statement timeouts (16–17 Oct 2026)

**Symptom.** The Agents page, and under load every screen, showed raw "canceling statement due to statement timeout"
errors.

**Cause.** From pg_stat_statements, the mean of the calls that finished (timed-out calls are not even counted), against an
8 s limit for the authenticated role:

| Read | Mean |
|---|---|
| hq_ceo_dashboard | 7.1 s |
| hq_advisor | 6.9 s |
| hq_director | 5.9 s |
| hq_directors | 4.1 s (18.7 s even with the database idle) |
| hq_outreach_desk | 3.7 s |
| hq_network | 3.5 s |

Three things multiplied the load:
- HQ fired about 14 of these reads in parallel on every load, every 60 s, and after every button press.
- For two minutes after an approval it fired them every 5 s.
- A failed section re-requested its read on every redraw.

The reads also repeat each other's work: directors_snapshot, director_detail, hq_advisor and director_channel_health each
re-run outreach_desk().

**Fix (migration `20261017100000_hq_read_cache.sql` plus client changes).**
- **Background snapshots.**
  - pg_cron (now enabled) runs `hq_cache_refresh('core')` every 5 minutes: Agents, Dashboard model, Advisor, network,
    execution.
  - `hq_cache_refresh('directors')` refreshes the three oldest Director pages each run.
  - Snapshots live in `hq_read_cache`: RLS on, no client access.
  - The browser reads them through the admin-gated `hq_cached(key)`: 0–12 ms against the 8 s limit, measured live.
  - The Agents snapshot drops the 665 KB email list that screen never shows (823 KB down to about 57 KB).
  - The live functions are unchanged. The Outreach desk stays live (about 1 s alone), because approvals must show at once.
- **Client loading.**
  - Reads go out in waves of at most 6.
  - Light refresh every 2 minutes (desk plus snapshots); full refresh every 10 minutes.
  - After a write, only the reads it can change reload. After an approval, only the desk polls (every 15 s for 2 minutes).
  - Nothing polls in a hidden tab, and a failed read waits for Retry.
  - `version.json` plus no-cache headers: an idle open tab reloads itself onto a new build. On 16 Oct an old tab kept the
    old 14-read polling alive after the deploy.
- **Display.**
  - CEO screens never show raw database text. A section without data shows "Some data is temporarily unavailable." with
    Retry.
  - Data on screen whose refresh failed shows "Some figures may be out of date".
  - A failed action says nothing was sent or changed.
  - Raw reasons, snapshot ages, build times and the pg_cron jobs appear only under More / Admin → System
    (`hq_cache_status`).
- **Agents.** Cards gain "Needs you" (emails to approve, email drafts to edit, LinkedIn / Instagram fallbacks to send by
  hand). A LinkedIn fallback is one step: Copy & open LinkedIn.
- **Tests.** Security scan pass, 202/202 classic checks, 108/108 acceptance checks. The new checks cover:
  - at most 6 reads in flight;
  - no heavy live reads;
  - a scoped reload after Approve;
  - a simulated database timeout: clean states, no loop, Retry recovers, a plain message for a failed action, raw reasons
    only under Admin.
- **Housekeeping.** `hq_perf_baseline` is a temporary 27-row monitoring table created during the diagnosis (RLS on, no
  client access). Dropping it through the tools waited for a confirmation and timed out; the daily check removes it.

**Email drought, measured 16 Oct (no Hunter upgrade).**
- **Hunter Free.** 5 of 100 verifications and 2.5 of 50 credits left until 27 Oct.
- **Routes.** Across 333 decision makers on qualified accounts:
  - 29 verified;
  - 118 with an email found but not verified;
  - 174 where no email was found (these are the LinkedIn fallbacks);
  - 12 with no person yet.
- **The 13 "email ready".** All are already in Gmail drafts, held for a quality edit, or blocked on identity. No new email
  was left to draft, so workflow 18 planned 0 that night.
- **Composition of the 118 waiting.**
  - 43 named personal addresses (30 published on the company's own website);
  - 28 department inboxes (23 published there);
  - 47 general inboxes addressed for a named person (39 published there; Weddings alone has 26).
- **Public discovery is not stalled.** Workflow 23 runs six times a day and finds an empty gap queue: every decision maker
  either has a candidate email or has been researched to exhaustion.

**Revenue-cycle leaks, in order.**
1. Verification: 118 found emails cannot pass the verified-only rule while Hunter is on Free.
2. Email not findable for 52% of decision makers.
3. Adam's Send and replies: 6 unsent Gmail drafts and 3 replies owed.
4. Meeting → brief: 2 meetings, 0 briefs, 0 proposals. Studio closes this gap.

## Email restart through official published inboxes, and NOYA Studio (17 Oct 2026)

**Adam's decisions (17 Oct).** EMAIL A: an inbox the company publishes on its own official website may be outreach-ready
without Hunter. STUDIO B: start Studio now with the logo from the latest approved brochure, replaced centrally when the master
SVG exists. FIRECRAWL: no upgrade; flag only a genuinely blocked revenue-critical workflow. The temporary `hq_perf_baseline`
table stays until a maintenance session can confirm the drop.

**OFFICIAL_PUBLISHED_INBOX** (`20261017200000_official_published_inbox.sql`):
- `email_official_inboxes` holds each classified inbox with its source URL, source and company domains, date found and the rule.
  The class is never VERIFIED and `contacts.email_status` is untouched.
- `official_inbox_classify()` picks inbox contacts (general or department local part) whose address and source page are both on
  the company's own website domain, never checked by the provider. It revokes an inbox whose address changes, becomes
  do-not-contact or is later checked and not found valid. The planner runs it before every live plan.
- `contact_email_route` returns OFFICIAL_PUBLISHED_INBOX for a usable classified inbox. A company where a confirmed decision maker's
  own address is still waiting for Hunter keeps waiting (named personal addresses wait until 27 Oct), so the company's one cold
  route is not spent on an inbox.
- `company_email_state` ranks it after a personal address waiting for verification and before an unclassified inbox.
- The planner, `cold_route_sweep`, `outbound_recipient_block_reason` (the Gmail-draft gate), `outreach_candidate_save` (task text:
  "OFFICIAL PUBLISHED INBOX: listed on the company's own website (url); not SMTP-verified"), `outreach_desk`,
  `director_channel_health` and `acquisition_health` all treat it as an email route; "verified" counts stay strictly verified.
- HQ labels it "Official inbox · company website · not verified" and never "Verified email" (`hq/src/app.js` ESTATE, deskRow).

**Two routing defects found and fixed on the way.**
- Press and media inboxes are used only for a recorded CONTENT_TALENT partnership model. An unknown model used to count as
  content, which would have pitched J.P. Morgan, KKR, Apex, Manchester City and Pacaso through their press offices
  (`20261017210000`).
- The planner's 30-day "already planned" exclusion counted dry-run candidates, so a dry run silently blocked its companies from
  the live plan for 30 days. Dry runs no longer count; dry-run rows are closed as SKIPPED / DRY_RUN (`20261017220000`).

**Result (17 Oct, 01:00 Cairo).**
- 183 inboxes classified at 148 companies; 55 qualified prospect companies now route to an official inbox (118 waiting → 61).
- Email-ready across the Directors went from 5 to 57: Brands 0→5, Weddings 0→29, Media 0→2, Travel 2→8, NOYA Private 0→0,
  Hospitality 3→10, Corporate 0→2, Sports 0→1, Egypt 0→0. Partnerships (cross-lane) 50.
- That night W18 drafted 25 emails into Needs review (17 ready, 8 flagged for an edit): Weddings 14, Brands 5, Partnerships 3,
  Travel 2, Corporate 1. All go to official inboxes, no company has a second open cold route, and nothing was sent or queued.
- NOYA Private stays at 0: its inboxes are general addresses (office@, info@) at clubs and family-office firms, which the small-firm
  rule for general inboxes (EP-3) keeps off email.

**NOYA Studio** (`studio/`, `20261017230000_studio_documents.sql`): documents are data (`studio/documents/<slug>.json`). The
templates turn them into A4 PDFs: navy and off-white, hairlines, Cormorant Garamond with Jost, fonts embedded. The renderer fails
any page that overflows, and each output is recorded in `studio_documents` with its content, sources, review notes and status.
Nothing sends. First outputs: the YKONE Egypt Brief and the CRUSH Egypt Concept, both FOR_REVIEW. See `studio/README.md`.
Limitation: this cloud environment cannot reach Drive, Google image hosts or noyaconcierge.com, and the Drive connector cannot
move multi-megabyte files. So the brochure logo and the approved photography are not in the renderer yet, and the typeset
wordmark is used until `studio/brand/logo.svg` exists.

## NOYA Studio master systems (17 Oct 2026)

Adam: "HQ is frozen. Continue Studio only… build the reusable premium master systems… Prioritise live commercial conversion:
Reply / Meeting → Concept → Brief → Proposal → Project. Keep YKONE and CRUSH as the first live acceptance cases. Next test one real
Brand opportunity, one Wedding opportunity, one Media opportunity and one NOYA Private opportunity. No generic Canva look, no
invented past work, no automatic sending."

**What exists** (`studio/`, see `studio/README.md`). Seven lane masters in `studio/masters/verticals.mjs` (Brand · Campaign ·
Production, Weddings, Media / Podcast, NOYA Private Egypt Desk, Travel / Concierge, Corporate / White-label, Founder retreats).
Each one is built on its CRM product desk (`commercial_products`), so the proposal shape and the objections match what the
Directors already use. Client and internal itineraries are stages that every lane shares. A live opportunity is one case file
(`studio/cases/<slug>.json`): the facts with their provenance, the people, the timeline, the status and the idea for each stage.
Eight stage builders turn a case into documents:
- internal: opportunity note, project book, operations itinerary;
- client: concept, brief, proposal, itinerary, NOYA Private overview.

Internal documents are flagged *Internal · not for client* on every page. A proposal stays *Draft · fees not approved* until Adam
records the fees. Covers differ by lane, all in one house style:
- navy: brand, media, private;
- paper: weddings, travel, retreats, itineraries, internal;
- split: corporate.

**Guard rails.**
- Builders refuse to invent: a concept without its own idea stops the build. So does a "why" row citing an INFERRED or
  UNVERIFIED fact, a fee without Adam's approval, or a brief field the master doesn't ask.
- `studio/tests/acceptance.mjs` builds and renders every case, then checks each output:
  - no overflow, brand fonts present;
  - no provenance labels in client documents;
  - no past-work, portfolio, guarantee or cliché claims;
  - no names from another case;
  - permit / indicative notes present;
  - the internal flag and the draft flag on every page;
  - no "To confirm" in a final client document;
  - no network or mail code in Studio.

  A planted-fault run confirmed the checks catch a past-work claim, a cliché, a name from another case and a broken value.

**Acceptance (17 Oct).** 9 cases, 22 outputs, all pass:
- YKONE (brand, live): note 5 pp, brief 5, proposal 5 (draft), project book 4, client itinerary 4, operations itinerary 3,
  internal pack 12.
- CRUSH (brand, live): note 6, concept 5, brief pre-filled from the concept 5.
- Brand test, Nado's Jewellery: note 5, and a guest-programme concept for the Meet Her launch at Forever Is Now (Giza, 4–28 Nov)
  5. Follow-up to Raymond Ayac is due 20 Oct.
- Wedding test, Sarah Haywood: note 5, concept with three Egypt settings 5. Held for the January revisit the CRM plans; earlier
  only if they write first.
- Media test, The Travel Diaries: note 5, Egypt destination-special concept 5. Video is not stated, because it isn't confirmed on
  public record.
- NOYA Private test, CAA Base: note 5, Egypt Desk overview 4. No client named; offered on request after a first discreet note.
- Template previews (Travel, Corporate brief and draft proposal, Retreat): 5 pp each, labelled "Template preview · no client".

**Records** (`20261017240000_studio_masters.sql`). `studio_documents` gains `vertical`, `stage`, `audience` and three document types:
OPPORTUNITY_NOTE, PROJECT and DESK_BRIEF. `studio/record.mjs` records each document version with its hash, sources and review
notes. All 17 live-case documents are recorded:
- FOR_REVIEW, except the YKONE proposal, which is DRAFT;
- the first YKONE brief and CRUSH concept are v1 SUPERSEDED, kept as evidence.

**Open.**
- Logo and photography: Drive and noyaconcierge.com can't be reached from this environment.
- The contact email differs between the approved material (noya@) and the Egypt Desk draft (adam@).
- No real past projects are on file for a portfolio, so concepts answer portfolio requests with a specific idea instead.

## Studio operating mode (17 Oct 2026)

Adam's decisions:
- Nado's: A, attach the concept to the 20 Oct follow-up.
- Client documents: A, `noya@noyaconcierge.com` is the standard document contact. The Egypt Desk draft was updated; the cold-email
  signature standard is unchanged.
- Sarah Haywood: A, hold until January unless a genuine relevant opportunity appears sooner.
- CAA Base: B, identify the right player-care / client-services lead before approaching.

Then: "Do not add more Studio modules now. Move Studio into OPERATING MODE… The purpose of Studio is not document volume. The
purpose is conversion into real projects and revenue."

**Three output levels**, enforced by the build (`studio/masters/stages.mjs`, `gate`):
- Level 1, email idea: a concept in the email itself, under 150 words. Allowed for any prospect.
- Level 2, one-page concept: for warm opportunities, or cold ones that are strong (they cite a dated public trigger).
- Level 3, full concept, brief or proposal: only after demonstrated interest, a meeting or an actual brief.

Each case records its relationship state with a verified fact as evidence. Anything above the earned level is built only as
*held*, and a declined company gets nothing sendable.

**Tracking** (`20261017250000_studio_operating_mode.sql`):
- `studio_outputs` is the ledger.
- `studio_outputs_refresh()` runs every 30 minutes. It fills sent → reply → meeting → proposal → won from the mailbox import, CRM
  meetings and tasks, Studio proposals, recorded proposal values and won dates. Nothing is estimated.
- `studio_output_status` shows each output's next step.
- `studio_conversion` shows the funnel by level.
- `studio_queue` lists companies that warmed in the last 30 days with no Studio output yet, and the level each has earned.
- `studio_documents` gains `level` and `hold_reason`, plus two document types: EMAIL_IDEA and ONE_PAGE_CONCEPT.

**Live conversion, 17 Oct.** Unsent Gmail drafts sit in each existing thread. Adam attaches the PDF and sends; the connector cannot
attach files from here.
- CRUSH: full concept (Level 3, engaged: Sophie asked for material and a call). Send now; the brief follows on the call.
- YKONE: Egypt brief (Level 3, a meeting was held). Send now; the draft proposal stays internal until YKONE briefs.
- Nado's: one-page concept with the 20 Oct follow-up (Level 2, cold but strong). The full concept is held until Raymond replies.
- Founders Club: one-page retreat concept for the 2027 calendar (Level 2, warm). Timing is Adam's call; first week of November is
  recommended.
- Sporting Founders: retreat concept held (declined 5 Oct; no chasing).
- Sarah Haywood: one-page concept held until January.
- The Travel Diaries: Level 1 email idea held until the route is confirmed; the full concept is held.
- CAA Base: no public player-care or client-services lead found (client care sits with their football consultants). The overview
  is held; next step is a LinkedIn search.

CRM next actions and due dates are set on each opportunity, so they surface in HQ without changing it.

**Acceptance.** 11 cases and 33 outputs pass the gate, including the level checks. A planted-fault run showed that past-work
claims, clichés, names from other cases and broken values are caught. Firecrawl ran out of credits during research; per Adam's rule
it was not upgraded, and web search covered the facts.

## CEO Command Centre and professional operating mode (18–19 Oct 2026)

Adam's brief: NOYA has about £60k of real revenue over roughly 18 months. Increase revenue and conversion, run the AI team like
employees, make founder decisions easy, keep data clean, improve from real results. "Do not rebuild the system from scratch. Do
not create duplicate architecture… This is a professionalisation pass." The cycle: STRATEGY → AGENT WORK → OUTREACH →
RELATIONSHIP → MEETING → STUDIO → PROPOSAL → PROJECT → DELIVERY → REVENUE → LEARNING.

Migrations: `20261019000000_command_centre_core.sql`, `20261019010000_integrity_health_advisor.sql`,
`20261019020000_audit_cleanup.sql`. One new read model (`hq_command()`, cached as `command`); everything else extends what was
there (tasks, revenue, the cache, the Advisor, the queues).

**Dashboard top row** (all from records, never invented): Actual revenue (from revenue records with evidence; the stated £60k
shows beneath as "historical to reconcile"), Active projects, Open proposals, Meetings (30 days), Positive replies (30 days),
Emails to send (approved Gmail drafts plus Studio drafts, with those held for later), Actions needing Adam.

**Revenue.** Each record carries client, project, date, service, Director, gross, supplier costs, gross profit (computed),
payment status, currency and evidence. The £60k is held in `system_config.historical_revenue` as TO_BE_RECONCILED and never
counted. Admin → Revenue & finance shows HISTORICAL REVENUE — TO BE RECONCILED (stated, reconciled from records, remaining) and
an import: paste rows, check them (dry run: every row needs client, date, gross, currency, payment status and evidence;
duplicates refused), then import. `hq_revenue_import(rows, apply)` writes historical records with their payments. Won without a
revenue record is an integrity error.

**Commercial funnel** (15 stages, by company): Target → Qualified → Contact ready (a verified or officially published email) →
Outreach sent → Replied → Positive → Meeting → Brief / concept → Proposal → Negotiation → Won → Project active → Completed → Paid,
plus Lost / parked. Each stage shows how many are there now, how many ever reached it and how many are stuck. Every live
opportunity shows owner, next action, date and blocker; a missing one is flagged and the Plan button sets it
(`hq_opportunity_plan`, the date cannot be in the past). Rule: REPLY → NOTHING and MEETING → NOTHING are integrity errors.

**Agents as employees.** Director scorecards (7 days, 30 days, all time): qualified, email coverage, first messages sent, reply
rate, replies, positive, meetings, briefs, proposals, wins, revenue. Rates and rankings appear only from 20 first messages in
the window ("n=" otherwise). Searches and contacts added are never rewarded.

**Work orders** (built on `tasks`, task_type WORK_ORDER): Director, mission, target, metric and number, deadline, priority. Status
comes from evidence, never from a claim: QUEUED until the Director's next real run, then WORKING, WAITING (on Adam or a blocker),
COMPLETE (goal met) or BLOCKED. The results chain runs matched → qualified → people → email research → verified → email-ready →
drafted → in review → Gmail drafts → sent → replies → positive → meetings → proposals → wins. The planner and the specialist queues
(enrichment, email gap, verification, finder) rank a work order's target companies first; discovery query banks live in n8n and
are not steered yet. Actions: issue, close, cancel (`hq_work_order`, `hq_work_order_action`).

Example, issued 19 Oct for acceptance and attributed to the System: Brands & Production, "Open conversations with UK fashion and
activewear brands that already shoot abroad", 5 emails sent by 30 Oct, P1. 11 matching companies (Adanola, Gymshark, LGK Apparel
Global, LIGHTBLUE, House of CB, Hackett London, The Couture Club, Augustinus Bader, Hunza G, Seven Media, Represent), 2 email-ready,
1 in Adam's review. Accepted at Brands & Production's next run.

**Priorities and capacity.** Lane order: Brand / production, Weddings, Media, Travel, Hospitality, NOYA Private; member and founder
communities are opportunistic. Email first. Weekly first-message targets 25–30 (Brands 8–10, Weddings 6–7, Travel 4–5, Hospitality
3–4, Sports 2–3, Media 1–2, Private 1–2, Corporate 0–1). Daily standard: at least 5 high-quality sends a working day; draft supply
matches review capacity (email reserve caps 10 / 5); 8–10 a day is a later test, never a jump back to 15. LinkedIn / Instagram
fallbacks capped at 5 open.

**HQ Advisor: five a day.** What you should do, Biggest bottleneck, Best opportunity, Agent to correct, What should stop; plus a
weekly allocation. Plain language: no workflow numbers or tool names on CEO screens.

**Improvement loop.** OBSERVE → DIAGNOSE → RECOMMEND → ADAM APPROVES → APPLY → MEASURE (`improvement_upsert`,
`hq_recommendation_action`, `improvements_refresh` daily). Approving applies only allowlisted changes (lane allocation, volume,
qualification threshold, follow-up cadence) or a prepared action (park excess fallbacks, close stale follow-ups); anything that
needs n8n or a purchase stays MANUAL. Approving never sends anything.

**Daily integrity check** (05:10 Cairo, `integrity_check`): duplicates, multiple cold routes, stuck approvals, approved emails with
no Gmail draft, sends with no time, replies or meetings with no next action, overdue live opportunities, won with no project or
revenue, projects with no owner, paid with no revenue, expired drafts, overdue follow-ups, fallbacks over the cap, Studio attachment
mismatches, owner-name variants, workflow failures. Only safe deterministic issues are fixed automatically (first run: 377
owner-name variants). Admin → System health shows services, agents on schedule, failures, AI calls by workflow and the integrity
results. CEO screens carry none of it.

**Audit.** `docs/NOYA_SYSTEM_AUDIT.md`: Supabase and n8n registers, cleanup done, items retained, decisions for Adam.

**Acceptance (19 Oct): mission → Director accepts → specialists → results → outreach review → Adam approves → Gmail draft →
reply detected → Studio → proposal / project → revenue recorded.**

| Step | State |
|---|---|
| Mission issued | Proven live: the work order above, status QUEUED from evidence. |
| Director accepts | Waits for Brands & Production's next run (06:00 Cairo); recorded automatically by `work_orders_refresh`. |
| Specialists | Proven: the finder queue already ranks the targets first. The planner boost acts at the next drafting run, but workflow 18 has been failing on its model provider since 17 Oct (backup model needs n8n access). |
| Results | Tracked live: 11 matched → 2 email-ready → 1 in review. |
| Outreach review → Adam approves → Gmail draft | The existing chain (approval → workflow 12 → unsent Gmail draft); not re-run, because only Adam approves. |
| Reply detected | Workflow 13 syncs every 30 minutes (last 19 Oct 00:30). |
| Studio → proposal / project | Studio outputs tracked (CRUSH, YKONE); no proposal or project yet. Won → project and won → revenue are checked daily. |
| Revenue recorded | Import validated by dry run; no record yet, waiting for Adam's evidence for the £60k. |

Tests: `ui.mjs` 202/202, `ui_v3.mjs` 108/108, `ui_command.mjs` 37/37, security scan PASS.

## One commercial attribution model, n8n live audit and Adam's decisions (19 Oct 2026)

Adam: "I do not want competing definitions across HQ." Dashboard, Director scorecards, weekly review, the segment table,
the Advisor, work orders and the commercial performance review now all read the same three functions
(`commercial_messages`, `commercial_facts`, `commercial_metrics`; migration `20261019030000_canonical_commercial_metrics.sql`).
Historical evidence was not changed to make figures agree.

**Definitions.**

| Measure | Counts | Rule |
|---|---|---|
| Outreach sent | MESSAGES | Every NOYA outreach message (email, LinkedIn, Instagram) before the company's first reply. Split into **new outreach** (first message of a sequence, nothing sent to that company in the previous 120 days) and **follow-ups**. |
| Companies contacted | COMPANIES | Each company once, on the date of its first outreach message. |
| Replies | COMPANIES (headline) and MESSAGES (detail) | A company replied when an inbound message follows NOYA's first outreach. Reply messages are shown separately. A company that wrote to NOYA first is an **inbound lead**, not a reply. |
| Positive replies | COMPANIES | Reply classified positive, meeting request, needs information or referral; a meeting or call requested; opportunity moved to interested, call, proposal, negotiation or won; or any meeting. |
| Meetings | COMPANIES | Booked or held only: a recorded meeting or a dated meeting task. A request is positive, not a meeting. |
| Briefs / concepts | COMPANIES | A Studio level 2–3 document actually sent, a concept used with the counterpart, or a project brief. |
| Proposals | COMPANIES | Opportunity at proposal, negotiation or won, a recorded proposal value, or a Studio proposal sent. |
| Wins | COMPANIES | Opportunity won (won_at) or a Studio output marked won. |
| Revenue | MONEY | Revenue rows with evidence only, per currency. The stated £60k is a reconciliation target, never counted. |

Windows count a company in the window in which it first reached a step, so weeks add up to the all-time totals. Reply rate is a
cohort rate (of the companies first contacted in the window, how many have replied since) and is only shown from 20 companies.
Messages count CRM interactions plus mailbox messages on CRM-linked threads that are not yet logged, never both.

**Why the old figures disagreed** (same report, 18 Oct): "34 outreach sent → 1 replied → 2 meetings" was the pipeline view, where
each company sits only at its furthest stage today, so a company that moved on left the earlier stage, and meeting requests were
counted as meetings. "37 companies contacted → 3 replies" counted companies that ever reached outreach but left out lost and parked
ones, and only replies logged as CRM interactions. Earlier commercial reviews counted Gmail threads, including companies that were
not in the CRM, inbound enquiries and opportunity status changes. The Advisor counted every message, follow-ups included, as
"sent". All four now read the canonical layer; the pipeline view keeps "now" per stage and adds "ever reached".

**Canonical numbers after today's data work** (19 Oct, all time): 44 companies contacted (47 new outreach messages, 7 follow-ups)
→ 10 replied (29 reply messages) → 2 positive → 1 meeting → 0 briefs sent → 0 proposals → 0 wins, plus 1 inbound lead. Last 30
days: 31 contacted (31 new, 2 follow-ups) → 7 replied → 2 positive → 1 meeting. The five Gmail relationships added today account
for the change from 40 → 44 contacted and 6 → 10 replied; their positive and meeting stages stay unset until Adam reviews them.

**Decisions applied (Adam, 19 Oct).**

- *n8n.* Live instance inspected (33 workflows). Outreach drafting (18): the 22:30 failures were the planner RPC exceeding
  PostgREST's 8 s limit, fixed with a 55 s function-level limit on the agent RPCs; the redraft step falls back to a second Gemini
  model on model errors and rate limits. Reply classifier (13) has run on Gemini since 16 Oct (Gemini backup, human review last).
  CEO brief (11): its fallback was the same model as the primary, now a different model; its billing alert named Anthropic, now
  Gemini. Provider health (00b): the informational Anthropic probe can no longer stop the run. Archived (inactive, never executed
  in retention, replaced): 01 Lead Engine skeleton, 05 Sales & Outreach (replaced by 18). No workflow reads from GitHub; every
  workflow reports failures to 00.
- *Growth Director paused* until marketing reporting is commercially relevant: 10a, 10b, 10c unpublished, 10d (website enquiries)
  stays live. `agent_registry.paused_reason`; HQ shows Paused, never late (migration `20261019040000_growth_paused.sql`).
- *Social backlog.* 69 open LinkedIn / Instagram items reviewed: 60 parked (re-openable), 9 kept (named senior decision-makers at
  priority 78+ and an Egypt flagship).
- *Stale follow-ups.* 26 reviewed one by one: 7 closed as cold, 1 kept as a relationship, 18 kept as live sequences.
- *Duplicates.* Mandarin Oriental (3 records) and Aman (3 records) merged into the canonical accounts: people the canonical record
  lacked moved across, duplicate opportunities archived under the canonical account, research and AI history moved, duplicate
  records kept with `MERGED_INTO` and excluded. Nothing deleted.
- *Gmail relationships.* Encore Lifestyle, Empiria Group, HIGHSTAY, Nouva Group and Purple Ski created from their Gmail threads
  only (company, people from the headers, opportunity `NEW` / `PENDING` / `SOURCE_BACKED`, threads linked, one review task each).
  Stage not assumed.
- *Historical revenue.* Workflow prepared: `docs/NOYA_REVENUE_RECONCILIATION.md`, an empty import template and a private Drive
  folder for the evidence. No row is created until Adam's evidence is matched and Adam approves the table.
- *Leaked-password protection.* Not available on the Supabase Free plan (Pro feature). Not enabled; a plan decision for Adam.
- *Repository private.* Deployment checked (Cloudflare Pages and Workers Builds deploy through the Cloudflare GitHub App, which
  keeps access when the repository is private). GitHub does not allow Claude sessions to change repository settings, so the switch
  itself is one click for Adam.

## Destination Egypt — Project Generation (19 Oct 2026)

Adam's mission: make NOYA the company international brands, agencies, wedding planners, private clubs, travel companies, media
companies and private-client representatives call when they want to do something exceptional in Egypt. Egypt is the destination;
NOYA is the execution layer. The question every Director asks: who already moves people, clients, members, brands or audiences
around the world, and how can NOYA bring their next project to Egypt?

**Architecture unchanged.** No new Director, no new CRM, no new primary page except Studio (a visibility correction Adam asked for).
The mission is a programme of work orders across the existing Directors.

| Piece | Where |
|---|---|
| Programme definition (buckets, project types, score weights, hosting rule, capacity) | `system_config.destination_egypt` |
| Seven work orders, one per bucket: Brands 20, Weddings 20, Private clubs 15, Travel 15, Media 15, NOYA Private 10, Corporate 5 (research targets, not outreach quotas; deadline 18 Nov) | `tasks` (WORK_ORDER, `spec.programme = DESTINATION_EGYPT`) |
| Egypt opportunity record: bucket, category, role (project generator / partner-supplier / amplifier / talent), what they do, audience, evidence with URLs, why Egypt, project type, proposed project, Egypt format, Studio level, six 0-5 scores, and (from 19 Oct, batch 2) the six answers Adam asks for on every account: `proposed_project` (what they could realistically bring to Egypt), `why_now`, `decision_maker`, `reach`, `noya_executes`, `next_commercial_action`. Never a deal value | `opportunities.mission`, `opportunities.egypt` (checked by a constraint) |
| Score: project generation and network leverage weigh most, then repeat potential and Egypt relevance, then destination evidence, warmth, contactability and a Studio-ready idea. Followers are never an input | `destination_egypt_score()` |
| Dashboard panel: qualified, email-ready, contacted, replied, meetings, briefs, proposals, won, revenue (canonical model, companies counted once), top opportunities, research by programme | `destination_egypt_mission()` in `hq_command` |
| Weekly CEO intelligence: replies by project type, Director, market and Studio level; Directors producing meetings; concepts with interest; where conversion stops; who gets more resources; what to stop (rates only after 5 contacted per Director, 8 per project type) | `destination_egypt_learning()` in `hq_weekly_review` |
| Hosting rule: a cold draft that offers a complimentary trip, stay, FAM visit or hosting goes to edit-before-approving with the reason. Adam's own edits and warm conversations are untouched | `outreach_hosting_guard` trigger on `outreach_candidates` |
| Lookalike discovery: Destination Egypt searches added to the rotating banks of 02 Brands, 04 Weddings and 07 Partnerships (same search volume per run) | n8n, versions of 19 Oct |
| Decision makers by category (founder, managing director or partner, experiential / production / partnerships for agencies; membership, experiences, partnerships and events for clubs; producer, partnerships, commercial and editor for media) | `role_focus` |
| Studio location intelligence: Giza, Grand Egyptian Museum, Cairo, Nile, Saqqara and the desert, Luxor, Aswan, El Gouna, Red Sea, North Coast, villas, resorts and yachts, each with sourced facts, suitable project types, formats and what must be verified. Permits and access are never promised | `studio/intelligence/egypt_locations.json` |

**Studio is primary** (Dashboard · Agents · Outreach · Studio · Relationships · Club · Operations · More / Admin; on the phone it
is the first item under More). The Studio page shows Needs brief, Drafting, Needs review, Approved, Sent and Superseded, the three
levels (email idea, one-page concept, full brief / proposal) and nine create actions. A request (`hq_studio_request`) is queued
for the Studio and prepared for Adam's review; it never sends, and a document above the level the relationship has earned is held.
Agents shows the eight Studio roles with the Brief & Proposal Architect first; clicking it shows current work, briefs being produced,
concepts ready, proposals, what needs Adam and the last outputs.

**First 25 accounts (19 Oct).** Sixteen existing CRM accounts with real evidence were tagged to the mission and nine new accounts
were researched from Adam's seeds and their lookalikes. Every record has evidence with a source, a project hypothesis, the right
person where one is confirmed (otherwise the next action is to confirm them before any Hunter credit is spent), the email route and
its honest state, a Studio level and a next action. Seeds that could not be verified from public sources (one agency name) and a
brand that has publicly pulled back from influencer trips were not loaded; they are listed in the acceptance report.

**Batch 2 (19 Oct): repeat project generators.** Adam: quality and project potential before filling the number, biased toward
businesses that can bring projects into Egypt more than once (marketing, PR and experiential agencies, destination wedding planners,
brand production agencies, private clubs and member networks, luxury travel networks, major podcasts and media producers, beauty,
fashion and jewellery brands that run international trips and shoots, corporate retreat and event companies). Fourteen new accounts
and three existing ones were researched to the six answers; Adam's three seed identities were researched and loaded in review (an
Egypt-based agency as a partner rather than a buyer, a club that runs member trips, and a social club parked until it runs trips).
A luxury agency network where an Egyptian DMC is already a preferred supplier was not loaded; NOYA reaches its agencies one by one.
The programme stood at 42 researched accounts, 34 qualified.

**Conversion sprint (20 to 28 Oct, review 29 Oct).** Adam, 19 Oct: "The research foundation is now strong enough. Do not
expand the account universe aggressively for the next 7 working days." The work moves to QUALIFIED ACCOUNT → CORRECT PERSON →
EMAIL → REPLY → MEETING → BRIEF, with 10-15 serious Destination Egypt conversations from the strongest existing accounts and the
first project moving toward proposal as the objective. No new table, page or agent:

| Piece | Where |
|---|---|
| Sprint definition (dates, 10-15 target, path, lane priorities, light research, about 5 excellent new emails a day, fewer when there are not five strong targets) | `system_config.destination_egypt.sprint` |
| Dashboard panel, conversion first: Contacted, Replied, Positive, Meetings, Briefs, Proposals, Won, Revenue; the sprint line (working day, conversations against 10-15, new since the start); qualified, email-ready and research by programme on a secondary line | `destination_egypt_mission()` (migration `20261019080000_destination_egypt_sprint.sql`), `dashMission()` |
| Ranked top 20: Destination Egypt buyers only (partners, amplifiers and accounts on hold left out), ranked by project generation, network leverage, repeat potential, Egypt relevance, evidence, warmth, contactability and a Studio-ready idea; never fame or followers | `destination_egypt_mission()->'top'` |
| Sprint flags on the Egypt record: `sprint` = HOLD (no outreach capacity: Surf Office, Get2Gether, Mason Rose), WARM_FIRST (YPO, TIGER 21: warm introduction first, otherwise one targeted approach), PARTNER (Camouflé, `partner_class` EGYPT_SIDE_PARTNER: referrals and local execution, not a buyer); `risk` and the opportunity blocker for reputational or credibility checks; `concept` for a media production concept (Goalhanger's Empire in Egypt) | `opportunities.egypt` |
| Daily sprint list for Adam (warm replies and scheduling, follow-ups as unsent Gmail replies in the thread, then up to five first emails), the 27 Oct Hunter test spending its first credits on the top 20's confirmed decision makers, and a one-off review on 29 Oct (contacted, replies, positive, meetings, concepts, briefs, project types, verticals, markets, where to put more attention, what to stop) | scheduled tasks |

Research note: the Firecrawl account used for interactive research ran out of credits on 19 Oct (no upgrade made). The production
departments are search-first and made no Firecrawl calls that day, so discovery is unaffected.
