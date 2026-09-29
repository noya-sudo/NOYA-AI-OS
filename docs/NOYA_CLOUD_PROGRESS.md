# NOYA Cloud Progress

Last updated: 2026-09-29 ~18:20 UTC (21:20 Cairo) — see COMMERCIAL ENGINE FINAL GATE below

## CURRENT PRODUCTION STATE

- **n8n (29 Sep)**: AI now runs on n8n AI gateway credits: Gemini 3.1 Flash-Lite, with GPT-5 mini for drafting, judgement and fallback. Anthropic is not required.
  - Published 29 Sep: 00b, 02, 03, 04, 05, 06, 07, 08, 09, 10a, 10b, 10c, 11, 12 and 13.
  - 00 and 10d are unchanged. 01 is inactive by design.
  - **12 - NOYA Outbound Email Executor v1** (`HOQIzE9gRKmeoz1G`): **ACTIVE (published 26 Sep)**. It is triggered only by the CEO Command Centre (`hq_approve_draft` via `pg_net`) for a single approved outbound id. It creates Gmail drafts only; no SEND row can be created from the dashboard.
  - **13 - NOYA Gmail Interaction Sync v1** (`lcc7sb28itQaTubO`): **ACTIVE**, every 15 minutes. The first scheduled run succeeded at 19:30 UTC (exec 293).
- **CEO Command Centre**: LIVE at `hq.noyaconcierge.com` (CNAME → Cloudflare Pages `noya-hq-dashboard.pages.dev`, serving the committed `hq/dist`). **PRODUCTION ARCHITECTURE FROZEN — 27 Sep 2026 (final live gate PASS).**
  - Server side: migration `20260926200000_hq_command_centre.sql`, plus the hardening migration `20260926201000_pin_helper_search_path.sql`.
  - Admin: `adam.elshazly1012@gmail.com` (Supabase Auth user `0d858bd9-…`, in `hq_admins`). Adam has signed in and set his own password.
- **Supabase `noya-ai-hq`**: CRM at real baseline, with no test records. At 27 Sep 17:45 UTC: 31 opportunities, 28 tasks, 37 contacts, 47 companies, 0 interactions, 0 outbound, 0 audit, 0 revenue. The rise since 26 Sep comes from the scheduled discovery runs 324, 330 and 339 on 27 Sep and from the creators watchlist.
- **Gmail**: `noya@noyaconcierge.com`. Nothing was sent from the mailbox in the last day.
- **Prospect auto-send: OFF. APPROVE & SEND: not exposed. Auto-reply: OFF.**

## COMPLETED THIS SESSION

1. Read-only audit.
2. Outbound email layer (workflow 12) — proven on 26 Sep (git `14297c8`).
3. Gmail Interaction Sync (workflow 13) — proven and active (git `363b16f`).
4. **CEO Command Centre** (this revision)
   - **Server API** (Postgres, `SECURITY DEFINER`, admin allowlist bound to the auth user id and email, audit on every decision):
     - `hq_dashboard`
     - `hq_save_draft` (EDIT; versioned, original kept)
     - `hq_approve_draft` (APPROVE & DRAFT: gates → `outbound_approve` → `pg_net` → workflow 12)
     - `hq_hold`
     - `hq_reject`
     - `hq_redispatch`
   - **New tables**: `hq_admins`, `outreach_drafts`, `approval_queue_state`. `pg_net` enabled.
   - **Structured approval data**: parsed from the workflow 05 draft already stored in each approval task. All 15 drafts parse: subject, body, follow-up plan, why now, why NOYA, outreach mode.
   - **Frontend** `hq/` — static and self-contained:
     - Build: `npm run build` → `hq/dist`.
     - Views: Today, Approvals, Pipeline, Tasks, Completed, Inbound, Marketing, Intelligence, System Health, CEO Brief.
     - Security: strict CSP; all CRM text is HTML-escaped.
     - Mobile-ready.

5. **Cloudflare deployment config** (this revision)
   - `wrangler.jsonc` at the repo root: `name` noya-hq, `assets.directory` `./hq/dist`, `not_found_handling` single-page-application. No Worker script, bindings or secrets.
   - `hq/src/index.html` now loads `/app.js` and `/styles.css` with absolute paths, so deep URLs served by the SPA fallback still load the app. `hq/dist` was rebuilt.
   - A root `.gitignore` excludes `.wrangler/` and `node_modules/`.
   - **Verified locally with wrangler 4.141.0**:
     - `wrangler deploy --dry-run`: 5 asset files read, no bindings.
     - `wrangler dev`:
       - `/`, `/approvals` and `/some/deep/path` return index.html (200).
       - `/app.js` and `/styles.css` return 200 with the correct content types.
       - The `_headers` security headers are applied (X-Frame-Options DENY, nosniff, no-referrer, HSTS, noindex), and the `_headers` file itself is not served.
     - Secret scan: PASS. UI checks: 31/31.

## NOYA HQ BUILD (from 30 Sep 2026)

See `docs/NOYA_HQ_BUILD.md`:
- Phases 1–3 are coded and tested; Overview V1 is verified against live data.
- The database layer is live and additive.
- HQ is live from this branch (Cloudflare auto-deploys the committed `hq/dist`).
- 30 Sep, operating layer:
  - Outreach HQ, LinkedIn (export + drafts + manual send), contacts/companies, pipeline board;
  - finance ledger, markets/growth, system costs + dependency register, help/playbooks, mobile nav.
  - Workflow 14, message drafting (`MUL5q7pTLMQwINiU`), is published.
- 30 Sep, V2: Gmail history import (workflow 15), prior-contact suppression (05 guard), Past relationships view, event-driven drafting (14).
  - See `docs/NOYA_HQ_READINESS_REPORT.md`, `docs/NOYA_HQ_PLAYBOOK.md` and `docs/NOYA_SYSTEM_DEPENDENCY_REGISTER.md`.
- Production fix the same day: Workflow 05 dedupe now recognises curated `OUTREACH_READY` tasks (published `62988121`); 8 duplicate tasks were merged.

## COMMERCIAL ENGINE FINAL GATE — PASS (29 Sep 2026, 18:20 UTC)

### Live evidence
- **05 production run 641** (success, 17:50–18:04 UTC). It ran on the published version `fb7b0f25` and produced 30 drafts.
  - **Drafts:** every salutation is a name or "Hello,". Length is 75–101 words, with no triple blank lines and the exact 4-line sign-off.
  - **Quality gate:** 29 PASS. 1 NEEDS_EDIT (Insider Expeditions, "elevate"), correctly flagged.
  - **Approval tasks:** 13 new ones, each with a sendable recipient in HQ (block reason = none):
    - Founders Forum, EO Dubai, The Arts Club, Home House, Soho House, 67 Pall Mall and GPJ Dubai (curated 29 Sep);
    - Founders Club, Sporting Founders, Vivaah, LINKVIVA, CRUSH and Sarah Haywood.
  - **LinkedIn / Instagram:** ready tasks were re-titled and lead with the message.
  - **Hunter results** in `contact_email_verifications`:
    - 7 applied or created (VERIFIED with provenance);
    - 3 catch-all → RISKY, not applied;
    - 1 invalid → not applied.
- **YKONE (Brand/Production), end to end:**
  1. Hunter-verified email.
  2. HQ approval.
  3. Adam sent manually at 17:00 UTC.
  4. Magali Rady replied at 17:33 asking for a call next week.
  5. Workflow 13 classified it MEETING_REQUEST on the AI gateway (no Anthropic).
  6. The opportunity is now CALL_REQUIRED, with a MEETING_ACTION task. No auto-reply.
- **MCI (Corporate/Events):** Hunter-verified email, then HQ approval. Adam sent at 17:00; a follow-up task is open.
- **Alice Wilkes (Wedding), Beyond Members Club (Member community), Medina Mallorca (Destination):** each has an `INSTAGRAM DM READY` task that opens with the DM, for Adam to send by hand. Email is not used (no verified address).
- **Workflow 13:** deterministic handling as follows:
  - manual-send detection and thread matching run in SQL;
  - bounce and out-of-office labels come from headers and subject, and always override the model; a model may never declare a bounce;
  - own-mailbox and internal mail is skipped.
  - AI is used only for reply meaning and the out-of-office return date.
- **Sends:** all 3 today (YKONE, MCI, Wealth Access) were approved by Adam in HQ, created as DRAFT and sent by Adam himself. Auto-sent prospect emails: 0.

### Data quality (all live)
- **Counts:** false VERIFIED 0; malformed contacts 0; shifted curated records 0; duplicate open tasks 0; account duplicates 0; sequence conflicts 0; READY without a usable channel 0; test rows 0.
- **Duplicate tasks:** Beyond and Medina had a curated research task alongside 05's task. They were merged; the research notes were kept and the curated task cancelled.
- **Julius Baer and Rothschild:** moved READY → RESEARCHING (no contact on file). Their parked tasks are untouched.
- **Role-named contacts** ("Partnerships Team", "Marketing Team", "Membership Team"): the names were cleared, and the published inbox and role were kept.
- **Quintessentially:** two open tasks by design, a committee follow-up due 27 Oct and Adam's LinkedIn touch to Hannah Felt.
- **Curated backlog:** the 29 Sep member-community and brand accounts (8) were released to 05. The 5 football clubs stay RESEARCHING; they are outside the 5 commercial priorities.
- **Temporary workflow** "ZZ - AI gateway probe" archived.

### Remaining risks (not blockers)
1. The n8n AI gateway credit allowance and price are UNKNOWN, so the AI budget cannot be enforced in money. Adam should confirm the plan's AI credits, or add his own Gemini/OpenAI key as an independent backup.
2. The Anthropic top-up never reached the n8n key. It matters only for the manual premium tier.
3. Windsor's free plan allows 1 account and 3 are connected, so 10a/10b get no Instagram data until 2 are disconnected or the plan is upgraded.

## COMMERCIAL ENGINE COMPLETION (29 Sep 2026)

Context: Anthropic's API key in n8n kept returning "credit balance too low" on 28 and 29 Sep, even after the reported top-up. The check was on org `a79626e9…`, workspace `wrkspc_014URL…`. The 10:15 brief on both days went out without its narrative. This run removed the dependency instead of waiting for credit.

### AI routing — Anthropic no longer required
- **Provider path:** n8n AI gateway credits (managed credentials auto-assigned by n8n). No new SaaS and no new API key.
- **Benchmark on real NOYA work (29 Sep):**
  - *Reply classification:* both Gemini 3.1 Flash-Lite and GPT-5 mini returned the correct NEEDS_INFO.
  - *Drafting (YKONE, real 05 prompt):* GPT-5 mini was clearly better. It positioned NOYA correctly and was specific.
  - *Flash-Lite drafting:* fake-familiarity opener, and the IG DM duplicated the LinkedIn message.

| Tier | Model | Used for |
|---|---|---|
| 0 (deterministic) | SQL / JS | Dedupe, registrable domains, throttle, channel routing, quality gate, typography, dates, metrics, provider health, bounce/OOO/thread matching (WF13 triage), degraded CEO brief |
| 1 primary | Gemini 3.1 Flash-Lite | Entity extraction (02/03/04/06/07/08), reply classification (13, 05), contact-candidate extraction (05), content classification (10a), competitor extraction (10c) |
| 1 drafting / judgement | GPT-5 mini | AI Qualification (02/03/04/06/07/08), outreach drafting (05), CEO brief (11), Egypt intelligence (09), Windsor retrieval agents (10a/10b) |
| Backup | GPT-5 mini ↔ Gemini Flash-Lite | Fallback model on every chain node that supports it (entity extraction, 11 brief, 13 replies) |
| 2 premium | Claude Sonnet (existing Anthropic key) | Escalation only; not wired into any automatic path. 00b reports it as PREMIUM_OPTIONAL. |

- Anthropic removed from 02, 03, 04, 05, 06, 07, 08, 09, 10a, 10b, 10c, 11 and 13. All were published and verified.
- **07 publish:** 07 was published, which also shipped its 23 Sep serialization-only edits (reviewed SAFE on 28 Sep).
- **Final fallback:** deterministic or human review. Provider failure never equals commercial rejection.
  - WF11 → deterministic brief (below).
  - WF13 → UNKNOWN / human review, and confidence below 0.6 → human review.
  - Discovery → provider_failures counted, not rejected.

### Workflow 11 — brief always arrives
- Writer: GPT-5 mini, with Gemini fallback.
- **Guard:** `AI Brief Has Text?` routes an empty or short AI output to the deterministic template.
- **Deterministic template:** built from `daily_action_brief_facts`, labelled **AI ENRICHMENT DEGRADED**. Sections:
  - DO TODAY
  - Replies needing action
  - Ready to approve
  - Follow-ups due
  - Contacts to resolve
  - Meetings & proposals
  - Opportunities by vertical
  - Discovery
  - System / cost
- **Proven:**
  - Exec 620 (production, 29 Sep): AI_OK brief with PDF delivered.
  - Exec 623 (pinned test with an empty AI result): degraded brief flows through PDF → email preparation.
- Found and fixed: GPT-5 mini spent all 6k output tokens on reasoning over a 36k-token fact set. The budget is now 20k, and the empty-output guard covers any recurrence.

### 00b provider health
- Probes the AI gateway with a real one-token completion, plus Serper.
- Anthropic is shown as PREMIUM_OPTIONAL and no longer raises a blocking alert.
- Exec 626: operational providers OK, and no false billing alert.
- Old alerts:
  - Superseded alerts closed.
  - 7d8d18b0 kept open at priority 40 so Adam knows the top-up did not reach this key.

### Data repair (curated 28 Sep imports)
- **Column shift:** 17 opportunities from `CHATGPT_RESEARCH_2026_09_28` had shifted contact columns (next_action = first name, first_name = surname, last_name = role). They were repaired structurally (migration `20260929090000`); no names were invented.
- **Named rows:** 13 now have contacts linked (confidence 60, email NOT_FOUND).
- **Role-only rows:** the target role moved to next_action, with a CONTACT_RESEARCH task where none existed.
- **Summits:** founders named only as "Lukas and Jonas", so no contact was created.
- **YKONE:** a personal LinkedIn URL had been stored as the company page; that field is cleared.
- Malformed records remaining: 0.

### Account dedupe
- **New objects:** `registrable_domain()` (eTLD+1; two-part suffixes; shared hosts and social handles keep the tenant) and the `company_account_duplicates` view. The view is empty, and `MERGED_INTO:` / `SEPARATE_ACCOUNT` notes are respected.
- **J.P. Morgan:** one account (8472657f).
  - The Private Bank row is kept as `MERGED_INTO`.
  - McCree was moved as the secondary contact.
  - The duplicate opportunity is LONG_TERM and its WAITING task closed.
  - Kate Randolph (LinkedIn) leads.
- **Discovery 02/03/04/06:** `Read Discovery Context` (RPC `discovery_context`) feeds `Merge & Cap`.
  - A candidate whose registrable domain is already in the CRM is skipped before paid research.
  - Live: 04 skipped 6 known accounts, 06 skipped 3.

### Discovery throttling
- `system_config.discovery_throttle` sets a research cap by backlog:
  - backlog below 30: cap 4 (NORMAL);
  - backlog 30–49: cap 2 (REDUCED);
  - backlog 50 or more: cap 0 (PAUSED).
- Backlog = approval-ready + contact-blocked + open follow-ups + overdue.
- Live 29 Sep: backlog 46 → REDUCED. Runs 618, 621 and 622 each researched at most 2.

### Firecrawl metrics
- Build Run Metrics now falls back to the run's static-data counters (Track Firecrawl nodes).
- Live: 04 = 4 calls, 06 = 6 calls (previously null). Metrics also log `known_account_skipped`, `throttle_level`, `research_cap`, `backlog_total` and `ai_calls_estimated`.

### Channel routing, outreach-ready state, HQ data
- **View `outreach_readiness`:** one row per open opportunity, with vertical, contact, role, email, email status, email kind (DIRECT_PERSON_EMAIL / OFFICIAL_COMPANY_INBOX), LinkedIn, Instagram, the ONE primary channel, available channels, ready email / LinkedIn / Instagram, style, evidence, follow-up plan, last touch and next follow-up.
- **Rule:**
  1. VERIFIED direct email → EMAIL;
  2. named person with a LinkedIn profile → LINKEDIN;
  3. Instagram-native → INSTAGRAM. Never for banks, wealth, law, consulting or investment firms (`20260929097000`; same rule in 05);
  4. VERIFIED official inbox → EMAIL_COMPANY_INBOX. The inbox rule was widened, e.g. `sponsorshipenquiries@` is an inbox, not a person;
  5. otherwise → CONTACT_RESOLUTION.
- **`commercial_vertical()`:** BRAND_PRODUCTION, CORPORATE_EVENTS, WEDDINGS_PRIVATE_EVENTS, MEMBER_COMMUNITIES, DESTINATION_CONCIERGE_PARTNERS, HOTELS_CONTENT, TALENT_SUPPORT.
- **`account_sequence_conflicts`:** always empty. One account gets one sequence.
- **`commercial_funnel`:** vertical × channel.
- **No shadow CRM table:** ready messages live in the approval task as one `OUTREACH_READY_JSON:` line.

### Workflow 05 — three-channel drafts
- **Models:** GPT-5 mini drafts; Gemini Flash-Lite classifies.
- **New AI fields:** `linkedin_message` (250–500 chars) and `instagram_dm` (<400 chars, only when Instagram-native).
- **Deterministic post-processing:**
  - one primary channel plus a fallback list;
  - typography (non-breaking hyphens, NBSP);
  - blank-line collapse;
  - exact 3-line sign-off plus `noyaconcierge.com`;
  - email style (PLAIN_PERSONAL by default, MINIMAL_BRANDED only for a warm relationship);
  - quality gate: 55–150 words, CTA, "Hi" opening, banned phrases, "based in Egypt", LinkedIn/IG length, why-now, primary-channel copy present → PASS / NEEDS_EDIT;
  - a single-channel follow-up plan (initial → one follow-up → optional final → LONG_TERM).
- **HQ parsing preserved:** `--- EMAIL --- … --- FOLLOW-UP 1` is unchanged. Never sends.
- **Final pass (29 Sep evening, published version `fb7b0f25`):**
  - **Salutation:**
    - A role or team is never used ("Hi Founder / Creative Director,", "Hi the team…", "Hi Partnerships,").
    - The known person's first name is used when it is a real name; otherwise "Hello,".
  - **Company-inbox rule** matches SQL `email_kind()`.
  - **Email approval tasks:** only a VERIFIED address creates a `SALES_OUTREACH_APPROVAL`. An UNVERIFIED address takes the contact path, where LinkedIn or Instagram is the ready channel. HQ blocks unverified recipients anyway, so this removes dead-end approvals.
  - **LinkedIn / Instagram-ready tasks:**
    - titled `LINKEDIN MESSAGE READY -- X` or `INSTAGRAM DM READY -- X`;
    - open with the message, profile, why-now and quality gate, all within HQ's first 900 characters;
    - Adam sends by hand; nothing is automated.
  - **One open outreach task per opportunity:**
    - a curated `CONTACT_RESEARCH` task is refreshed in place, with its research notes kept under `--- ORIGINAL RESEARCH NOTES ---`;
    - a parked or converted approval task is left untouched;
    - a VERIFIED email closes a curated research task.
  - **Structured Hunter result** is written to `contact_email_verifications` (see below).
  - **Local suite 6/6 PASS:** role→name, team→Hello, sponsorship inbox, LinkedIn path, Instagram path, verified direct; no triple blank lines, exact sign-off, no NBSP or non-breaking hyphens.

### Verified email → canonical CRM contact (final design)
- **Problem found in the live test:** 05 resolved and verified emails (Serper → Hunter finder → Hunter verifier) but wrote them only into the draft. HQ approval reads `contacts.email`, so a verified draft could not be approved.
- **First fix, since retired:** `20260929095000` copied the address from the draft's `OUTREACH_READY_JSON` line. It was replaced because draft text must never be the source of a recipient.
- **Final fix (`20260929096000` + `096500`):**
  - New table `contact_email_verifications`. It is an append-only log of the structured Hunter provider result, not a CRM table. It records:
    - provider, status, result, score, finder score and accept-all;
    - the provider's verification date and NOYA's `checked_at`;
    - workflow and execution;
    - the public sources where the address was seen;
    - the outcome.
  - Workflow 05 writes one row per Hunter check (`Email Found To Record?` → `Record Email Verification - Supabase`), taken straight from the finder and verifier responses.
  - A BEFORE INSERT trigger applies a row to `contacts` only when **all** of these hold:
    - valid + deliverable + not catch-all;
    - a person's address (not an inbox);
    - first and last name are known;
    - the email's registrable domain equals the company website's;
    - it is the same person at the same company;
    - the contact has no email yet, or already has this exact address;
    - the contact is not do-not-contact.
  - When those hold, the trigger:
    - sets `email_status = VERIFIED`;
    - writes provenance into `email_source_url`: `hunter:email-verifier status=valid result=deliverable score=… checked_at=… workflow=… exec=… log=<id>`;
    - mirrors the address to the opportunity;
    - points the opportunity at the verified person only if it had no contact or an unnamed placeholder.
  - If no contact exists for that named person, one is created from the verified identity.
  - It never overwrites a different address; that case is logged as `SKIPPED:CONTACT_HAS_DIFFERENT_EMAIL` for Adam.
- **Backfill:** Magali Rady (YKONE) and Alexander John (MCI Middle East), from the real exec 628 Hunter responses. Outcome is `CONFIRMED_EXISTING_EMAIL` for both, with provenance recorded and no HQ block reason.
- **Tested** (10 cases in a rolled-back transaction):

  | Case | Outcome |
  |---|---|
  | New named person | Contact created and linked |
  | Existing person without email | Applied |
  | Different email on file | Never overwritten |
  | Catch-all | RISKY, not applied |
  | Invalid | INVALID, not applied |
  | Wrong domain | Skipped |
  | `info@` inbox | Skipped |
  | Do-not-contact | Skipped |
  | First name only | Skipped |
  | VERIFIED only in draft text | Contact unchanged |

- **Audit view `contact_email_provenance`:** each address is labelled PROVIDER_VERIFIED_LOGGED, PUBLISHED_ON_OFFICIAL_SOURCE or LEGACY_PROVIDER_VERIFIED_NO_STORED_EVIDENCE. `quality_issue` flags a false VERIFIED; today it flags none.
  - The 7 legacy rows were set by department workflows through the same Hunter `valid` rule before provenance logging existed: Nobu, Armani, Quintessentially, Rafanelli, David Tutera, Jetex, Wealth Access.

### Workflow 05 — channel facts for the drafter
- The AI now sees the person's LinkedIn profile and the Instagram account, and is told which channel copy is REQUIRED.
- Before this, the drafts for Instagram-primary accounts lacked a DM. The quality gate flagged it as `PRIMARY_INSTAGRAM_WITHOUT_DM`, so nothing was hidden.

### Workflow 07 — member communities and destination partners
- The aviation/yachting and real-estate query slots are replaced by:
  - member-community queries (founder, athlete and member clubs);
  - destination-partner queries: Mallorca, Ibiza, Marbella, Mykonos, Saint-Tropez, Monaco, Courchevel, St Moritz and Cannes, including public `site:instagram.com` discovery.
- Same query count; same quality gates.

### Conversion before discovery
- Two changes:
  - The remaining 21 curated 28 Sep prospects (priority ≥ 70) were moved RESEARCHING → NEW, so 05 resolves contacts and drafts them on the next scheduled runs.
  - Superseded contact-research tasks were closed once an approval draft exists.
- The backlog throttle keeps broad discovery REDUCED or PAUSED while this backlog is worked.

### Workflow 12 — email formatting
- Gmail draft and send now use minimal personal HTML: 14px system font, 1.5 line height, 12px paragraph spacing, no banner or image.
- Blank-line runs are collapsed and mid-sentence hard wraps joined; sign-off lines are kept.
- Cause: text/plain drafts were being hard-wrapped by Gmail, as seen in the 27 Sep Quintessentially send.

### Other fixes found during verification
- **WF13 07:00 failure:** a transient Supabase ECONNABORTED. Retries (3x) were added to Triage and Apply, and the alert was closed.
- **10a:** Windsor returned a free-plan paywall notice ("3 accounts connected, Free plan includes 1") that was stored as a media row. The bogus row was removed, and a deterministic guard now rejects notices posing as media.

### Cost observability and budget
- **`cost_observability` (v2, `20260929098000`):** TODAY / 7_DAYS / 30_DAY_PROJECTION.
  - It covers Serper, Firecrawl, discovery AI calls, Hunter checks (05, from `contact_email_verifications`), reply-classification AI calls (13) and CEO brief runs (11).
  - Counts are ACTUAL. Money is UNKNOWN until `system_config.unit_costs` is filled from invoices.
  - Not yet counted: 05 drafting calls, 09, 10a-c, and Hunter inside discovery.
- **`system_config.ai_budget`:** PROPOSED USD 30/month, with 50/75/90/100% guardrails.
  - Not enforceable in money yet, because gateway credit prices are not exposed.
  - Premium is already outside every automatic path.
  - CRM, Gmail and tasks never depend on it.

### Future modules — NOTE ONLY (not built)
- **NOYA MEMBERSHIP PLATFORM:** corporate and private/lifestyle memberships.
  - Recurring billing, member profile, benefits, priority service, usage, renewal, corporate account usage, retention, member requests.
- **INVESTOR / FOUNDER SHOWCASE VIEW:** real traction, the commercial engine, relationship graph, membership economics, revenue and repeat business.
- Build neither until core production has real operating data.

## FINAL LIVE GATE — PASS (27 Sep 2026, 17:33–17:45 UTC) — FROZEN

Adam clicked **Approve & Draft** on the live site, on the internal card "ZZ INTERNAL LIVE TEST". The dashboard replied: "Approved. Creating the Gmail draft…".

| Check | Evidence | Result |
|---|---|---|
| HQ live | `hq.noyaconcierge.com` → Pages; the live `app.js` is byte-identical to the committed build | PASS |
| Auth | Adam signed in and changed his password; the `hq_admins` gate holds | PASS |
| Live data | Live `hq_dashboard` shows 4 approval-ready and 11 blocked | PASS |
| Live Approve & Draft | `outbound_emails` `b867eb0f…`, mode DRAFT, approved_by Adam, key `hq-4104402a…-v1-a0` | PASS |
| Audit log | APPROVE_DRAFT/APPROVED → DISPATCH_TO_WORKFLOW_12/QUEUED (pg_net #3, HTTP 200) → COMPLETE_DRAFT/DRAFTED (n8n-12) | PASS |
| Workflow 12 | Exactly 1 execution (395, webhook, success, 17:33:20–17:33:23) | PASS |
| Gmail draft | Exactly 1 draft, to `noya@noyaconcierge.com` | PASS |
| Emails sent | `in:sent newer_than:3d` is empty | 0 |
| Duplicate safety | A second `hq_approve_draft` as Adam returned ALREADY_PROCESSED and logged audit DUPLICATE_IGNORED. There was no new dispatch and WF12 stayed at 1 execution | PASS |
| Workflow 13 | 80+ consecutive scheduled runs since 26 Sep 21:45, all success (latest 394 at 17:30) | PASS |
| Test cleanup | Test draft and the old "NOYA HQ — your login" draft were deleted. All TEST_HQ_LIVE_20260926 rows were removed (opportunity, contact, company, 2 tasks, outbound, 4 audit rows) | PASS |
| Security | The bundle holds the publishable key only; RLS is deny-all; hq_* functions are admin-gated; there is no send path | PASS |

**Frozen:** the HQ frontend, the `hq_*` functions, WF12 and WF13, and the outbound, sync and audit schema. Change them only with Adam's explicit approval.

## DAILY OPERATING LAYER — FINALISED (28 Sep 2026, ~03:50 Cairo)

- **11 converted** to **NOYA — DAILY COMMERCIAL ACTION BRIEF** at **10:15 Cairo**; the 18:00 daily run is removed and the Sunday 19:00 weekly review is kept.
  - A new read-only function, `daily_action_brief_facts()`, supplies ranked existing tasks, drafts, replies and opportunities to the single AI call. Every value is labelled MODEL_ESTIMATE, ACTUAL or UNKNOWN. Nothing is re-researched.
  - PDF cover and email are retitled. "Open pipeline (estimated)" is relabelled "Model estimates (NOT pipeline)".
  - First live run: exec 430, AI_OK, PDF built, DELIVERED to Adam.
- **05 dedup:** approval, contact and entity task checks now treat OPEN, IN_PROGRESS and WAITING as existing, so parked tasks are never re-created.
- **Task review (11 overdue):**
  - 6 are STILL_ACTIONABLE. They were converted in place to LinkedIn or warm-path actions with scripts: Aman, Colin Cowie, Etihad, Mandarin Oriental, J.P. Morgan and Arab Bank.
  - 5 are WAITING_FOR_CONTACT and 1 is parked for capacity, all set to WAITING: Julius Baer, Rothschild, UBP, UBS, Northern Trust and Cambridge Associates.
  - 0 were closed; none were done or superseded. Overdue open tasks are now 0.
- **Aman:** the 27 Sep draft is rejected (unverified greeting, unsupported claims). Jihane Mamouri's identity is verified via public LinkedIn; her title (VP Global Sales) is inferred from RocketReach. The redraft from verified facts is stored as outreach_drafts v2; the channel is LinkedIn first. No paid verification.
- **Free research:** Colin Cowie (founder; site shows Dubai office and Middle East partnerships, Egypt not named) and Ashik Ali (Mandarin Oriental Director of Global Sales; Middle East inferred). Neither has an email; none invented.
- **07 review:** its pending 23 Sep changes are serialisation only (defaults stripped, unused output labels, sticky height). SAFE and functionally identical. Not published or overwritten.
- **Cost observability:**
  - New `department_run_metrics` table and `discovery_yield_daily` view.
  - A fail-safe logging step at the end of 02, 03, 04, 06 and 08 records candidates, known-skipped, deep-researched, wrong-type, failed-fit, failed-signal, qualified, Serper searches and Firecrawl calls.
  - Hunter and Anthropic token usage are not yet counted.
- **Verification** of the real schedule is set for 28 Sep 10:30 Cairo.

## DAILY COMMERCIAL ENGINE — ACTIVATED (28 Sep 2026)

- **Schedule (Cairo, unchanged, staggered):** 05:30 00b health · 06:00 02 Brand · 06:30 03 Hotels · 07:00 04 Weddings · 08:00 06 Corporate · 08:30 07 Partnerships · 09:00 08 Talent · 09:30 05 Sales & Outreach · 10:00 09 Egypt Intel · 18:00 11 CEO brief. 13 Gmail sync runs every 15 minutes. 01 is inactive by design.
- **Fix 1 (05):** "Load All Person Interactions / Person Sibling Opportunities" had no alwaysOutputData, so every run stopped silently whenever the result was empty. No drafts had been produced since about 21 Sep. Fixed and published. Test run 412: 20 opportunities loaded, 18 drafts, 4 new tasks, 9 refreshed, 0 errors, 0 sent.
- **Fix 2 (02, 03, 04, 06):** Merge & Cap now skips domains already in the CRM or researched in the last 60 days, so the 4 daily research slots go to new companies. Test run 411: 7 known domains skipped and 2 new candidates researched.
- **Not changed:** 07 (it has unpublished 23 Sep edits to duplicate-matching parameters that need review first) and 08 (a different shortlist design).
- **Quintessentially:** the committee submission (27 Sep) and the partnerships@ send are logged at company level. Hannah Felt is captured as a contact with a verified role and no email. There is one follow-up (27 Oct) plus one LinkedIn task.
- **First daily brief:** `docs/briefs/2026-09-28_NOYA_DAILY_COMMERCIAL_ACTION_BRIEF.md`
- **Morning brief:** automated since 28 Sep (see above).

## LIVE PRODUCTION VERIFICATION — 26 Sep 21:05 UTC (historical; superseded by the final live gate above)

**Result: `hq.noyaconcierge.com` is not reachable on the public internet yet.**

Public DNS (Google DNS resolver, `dns.google`) returns **NXDOMAIN** for `hq.noyaconcierge.com` (A, AAAA and CNAME). The `noyaconcierge.com` zone is authoritative on **Google Cloud DNS** (`ns-cloud-b1..b4.googledomains.com`), not Cloudflare. A Workers Custom Domain can only attach to a hostname in a zone that is active on Cloudflare, so the domain has not been connected to the `noya-hq` Worker.

**Corroborating evidence:**
- Adam's HQ account has never signed in (`last_sign_in_at` null, must-change-password still true, 0 sessions).
- The Supabase edge logs show no `hq_*` or auth-token calls in the last 24 hours.

**Could not be verified from this session:**
- The live build, live login and the forced password change.
- The 10 views against live data from the browser.
- The live-dashboard APPROVE & DRAFT test.

Two reasons: the hostname does not resolve, and this cloud session's network policy also blocks `hq.noyaconcierge.com` and `gagbhykzmtstekpqujyl.supabase.co`. No test data was created, so nothing needed cleaning.

**Verified now:**

| Check | Evidence | Result |
|---|---|---|
| Workflow 13 active and healthy | 7 consecutive scheduled runs, 19:30–21:00 UTC, all success; `gmail_sync_state.last_run_at` 21:00:30 | PASS |
| Workflow 12 active, idle | Published; 0 executions since 19:40 UTC (no approvals were made) | PASS |
| Zero emails sent | Gmail `in:sent newer_than:2d` is empty | PASS |
| CRM baseline intact | 29 opportunities / 28 tasks / 33 contacts / 44 companies, 0 interactions, 0 outbound, 0 audit, 0 ledger rows | PASS |
| Committed bundle secret-free | `hq/tests/security-scan.mjs` PASS (commit `374b111`) | PASS |
| Private / authenticated | Server-side auth tests of 26 Sep still apply: anon has no hq_* execute, non-admin JWTs denied, tables RLS deny-all | PASS (server side) |
| Approval-ready live queue | Quintessentially, Armani, Rafanelli, Nobu (4; all HUMAN_ONLY, VERIFIED) | 4 |

## TEST RESULTS — CEO COMMAND CENTRE (26 Sep)

**Server side, live database, tested as Adam's JWT (`authenticated` role):**

| Test | Result |
|---|---|
| Admin reads `hq_dashboard` (live: 15 approval cards, 29 opportunities) | PASS |
| Stranger JWT / admin user id with a different email / stranger approving → `not authorised` | PASS |
| Direct table SELECT/UPDATE as authenticated → 0 rows (RLS deny-all); service functions not executable; anon cannot execute any hq_* | PASS |
| EDIT → v2 saved, v1 original kept, audited | PASS |
| Approve with a stale version → `DRAFT_CHANGED_REFRESH` | PASS |
| **APPROVE & DRAFT → pg_net → workflow 12 (production) → Gmail draft `r-5428149251673574274` with the edited subject; outbound DRAFTED** | PASS |
| Double approve → `ALREADY_PROCESSED`; edit, hold or reject after approval → `ALREADY_APPROVED` | PASS |
| HUMAN_ONLY → draft created (`r8976678650222521199`); never a send | PASS |
| HOLD with a review date → HOLD state + WAITING review task; past date rejected | PASS |
| REJECT needs a reason; approval after rejection blocked; no draft created | PASS |
| UNVERIFIED contact → `EMAIL_NOT_VERIFIED`; unknown opportunity → `OPPORTUNITY_NOT_FOUND` | PASS |
| Every decision (including blocked and duplicate attempts) in `approval_audit` with actor = Adam's email | PASS |
| Nothing sent: Gmail `in:sent newer_than:1d` is empty | PASS |

**Browser** (`hq/tests/ui.mjs`, headless Chromium, 31/31):
- The network layer is intercepted and replays a live `hq_dashboard()` snapshot, because this container cannot reach supabase.co.
- The snapshot is git-ignored.

| Check | Result |
|---|---|
| Every view renders; "approvals waiting" matches the live queue (4) | PASS |
| Cards show contact, position, VERIFIED email, ESTIMATED value, why now, why NOYA, subject, body, HUMAN_ONLY | PASS |
| No Send button anywhere; the approve dialog states nothing is sent | PASS |
| Approve calls only `{p_opportunity_id, p_version}`; edit has no recipient field; reject requires a reason; hold passes the date | PASS |
| Only allow-listed RPCs are called; no JS or CSP errors | PASS |
| Mobile 390px: no horizontal overflow; buttons are tappable | PASS |
| Injected HTML in CRM data is escaped (XSS test) | PASS |
| First login forces a password change | PASS |

**Security scan of `dist/`**: no secret keys, no non-anon JWTs, no direct table access, no send RPC.

**Cleanup:**
- The 2 test Gmail drafts were deleted.
- All `TEST_HQ_20260926` CRM rows were deleted.
- The CRM is at exact baseline.

**Real prospect emails sent: 0.**

## LIVE APPROVAL QUEUE (fetched 26 Sep, live)

- **4 approval-ready**: Quintessentially, Armani Hotels & Resorts, Rafanelli Events, Nobu Hotels.
  - All 4 are HUMAN_ONLY, so draft only.
  - All 4 have VERIFIED emails.
- **11 blocked**, each with the specific reason shown in the dashboard:
  - Missing contact: Mandarin Oriental, Colin Cowie, Julius Baer, Rothschild.
  - UNVERIFIED email: J.P. Morgan, Arab Bank, UBP, Etihad, UBS, Northern Trust, Cambridge Associates.

## BLOCKERS

None required.

Optional:
- Enable leaked-password protection in Supabase Auth.
- Retire whichever of the duplicate Cloudflare projects is unused. `noya-hq-dashboard` (Pages) serves the live domain; the `noya-hq` Worker is unused.

## NEXT ACTION

29 Sep: reply to Magali Rady (YKONE) with call times for next week. Then review the 13 new approvals in HQ and send the ready LinkedIn/Instagram messages by hand. HQ CRM/Finance completion is the next build phase; it has not started.

Earlier (27 Sep): Adam opens HQ → APPROVALS and approves his first real draft. There are 4 ready: Quintessentially, Armani Hotels & Resorts, Rafanelli Events and Nobu Hotels. All are HUMAN_ONLY, so each approval creates a Gmail draft that Adam reviews and sends himself. Workflow 13 logs the send and any reply.

## DO NOT TOUCH

- The Squarespace site and `noya-website/` (separate workstream).
- Do not re-wire Anthropic back into automatic paths; premium escalation is manual only.
- `reports@noyaconcierge.com`: internal reporting only.
- Do not add an APPROVE & SEND path in this phase.
- Frozen production architecture (27 Sep): the HQ frontend and the hq_* functions. On 29 Sep WF12 changed only its email body format and WF13 changed only its classifier model and retries.
- Do not move `gmail_sync_state.go_live_at` earlier.

## KNOWN CREDENTIAL NAMES (names only)

- n8n: `NOYA Gmail` (gmailOAuth2), `Supabase account` (supabaseApi), `Anthropic account`, `NOYA Resend LIVE`, `NOYA Resend Header`, `NOYA Hunter` / `NOYA Hunter v2` / `Noya Hunter v2`, `NOYA Serper` / `Noya Serper v2` (x2), `NOYA Firecrawl`, `NOYA Windsor`.
- Supabase: project `gagbhykzmtstekpqujyl`.
  - The browser uses only the publishable key.
  - The service-role key lives only inside the n8n `Supabase account` credential.
