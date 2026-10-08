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
