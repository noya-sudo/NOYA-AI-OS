# Implementation plan

Ten phases. Each phase ends at an exit gate that Adam approves. External-write capability arrives late and one surface at a time:
reading comes before writing, organic before paid, and paused campaigns before live ones.

| Phase | Name | External writes | Money | Main exit test |
|---|---|---|---|---|
| 0 | Foundations (this commit) | None | None | Adam approves the architecture and D1–D7 |
| 1 | Control plane **(built; project pending)** | None | None | Governance tests pass on the real project; console login works |
| 2 | Brand, knowledge, worker plumbing | Test alert only | None | Brand Guardian catches seeded bad drafts; [TEST] alert received |
| 3 | Intelligence | None (reads public web) | Research credits within budget | Two weeks of signals Adam finds useful |
| 4 | Content studio | None (Adam posts by hand) | None | Four weeks of calendar shipped through the queue |
| 5 | Read connections | None (read tokens only) | None | Verified read connections; first weekly review with real numbers |
| 6 | Leads & HQ hand-off | Hand-off to HQ (approved) | None | First qualified lead delivered and acknowledged by HQ |
| 7 | Governed publishing | Instagram / LinkedIn Page posts (approved, confirmed) | None | Ten posts executed with zero discrepancies |
| 8 | Governed paid media | Ads: paused-create, then activation | Within caps | First test campaign run inside its kill criteria |
| 9 | Earned autonomy | Narrow, time-boxed, risk-reducing only | Never automatic | Case-by-case, Adam in writing |

---

## Phase 0: Foundations (this commit)
**Delivered:**
- repository structure;
- architecture, operating manual, approvals and permissions, audit logging, kill switch, environment, HQ hand-off contract,
  decisions and this plan;
- the proposed schema (`supabase/proposed/0001`, `0002`) with 13 governance tests passing on local Postgres 16;
- a secret scanner.

**Not done:** no Supabase project, no connection, no workflow, no UI.

**Exit:** Adam answers D1–D7.

## Phase 1: Control plane — BUILT, awaiting the Supabase project (7 Nov 2026)
**Done (automated):**
- Migrations `supabase/migrations/2026110710000{0,1,2}_*.sql`:
  - identities, with Adam as sole owner (seeded when the project exists);
  - approval requests, immutable versions, hash-bound approvals, execution requests and results;
  - 8 kill switches, all disabled;
  - safety events, the alert outbox and tripwires;
  - the hash-chained audit log and its chain verification;
  - the integration, permission and secrets registries;
  - configuration, system health and agent runs;
  - worker roles and pg_cron schedules.
- 28 automated database checks (`scripts/test-db.sh`), including a 10-way concurrency race and an advisor-equivalent lint. All pass.
- The internal console (`console/`): system status, kill switches, pending approvals, audit, services, database health, agents
  and runs, security alerts, the alert outbox, and configuration and secrets. Headless checks pass on desktop and mobile.
- The Resend alert dispatcher (`supabase/functions/mos-alert-dispatcher/`), prepared.
- `.env.example`, the secret scanner, the HQ-untouched check, `scripts/test-all.sh`, and the CI workflow for the future repo.
- Docs: security model, database, integrations, zero-manual policy, plus updates.

**Found and fixed by the tests:**
- Refusals were rolled back with their audit rows (Phase 0). They are now returned, not raised.
- The audit chain forked under concurrent writers. Fixed: `seq` is assigned after the chain lock.

**Blocked:**
- Supabase project creation was denied by the session's permission classifier. The org is on the Free plan with one active
  project, so a second project is expected to be quoted at $0.
- GitHub repository creation is not available to this session (automated migration task queued).

**To finish Phase 1, once `create_project` is permitted (all automated):**
1. Create "NOYA Marketing OS" in "Noya Concierge", eu-west-2. Proceed only if the quote is $0.
2. Wait for ACTIVE_HEALTHY.
3. Apply the three migrations through the Supabase migration tool.
4. Seed Adam as the owner member. His Auth user is created through the admin API with an invite email, so he never handles a
   password in chat.
5. Run the behavioural suite against the real project inside a transaction that is rolled back, so no test data persists. Then
   run the Supabase security and performance advisors and fix the findings.
6. Build the console with the project URL and publishable key.
7. Mark `integration_registry.supabase` verified.

**Exit:**
- the advisors are clean;
- the tests pass on the real project;
- Adam can sign in and see the desk with every switch disabled.

## Phase 2: Brand, knowledge and first worker plumbing (recommended next)
**Build:**
1. **Worker identity plumbing.**
   - Mint `mos_agent`, `mos_monitor` and `mos_dispatcher` JWTs, stored as n8n credentials and Supabase secrets.
   - Create the n8n folder "Marketing OS" with a heartbeat workflow that calls `mos_agent_run_start` / `_finish`.
   - Deploy the alert dispatcher; Adam enters the Resend key once in the secure secret form; set `alerts.enabled = true`; send
     **one** `[TEST]` alert.
2. **Weekly audit export** to a private Drive folder (chain head + CSV), with a monitor comparing it to the database.
3. **Brand tables** (from `proposed/0002`, brand schema only):
   - `brand.voice_rules`, seeded from NOYA's voice;
   - `brand.assets`, with rights and releases, in a private storage bucket;
   - `content.pillars`.
4. **Brand Guardian agent v1**:
   - deterministic checks first (banned phrases, length, hashtags, asset rights);
   - then a Claude check for tone and claims, on the separate Marketing OS key (D7) with a daily cost cap;
   - an evaluation set of 10 bad and 10 good drafts.
5. **Console**: a brand rules page, the asset library, and the Brand Guardian results.

**Exit:** Brand Guardian fails 10 of 10 bad drafts and passes 10 of 10 good ones; Adam agrees with its reasons; the `[TEST]` alert
is received; the first weekly audit export matches the chain.

**Adam decides:** the pillars and their shares; the banned-phrase list; one Anthropic key with a monthly limit (one owner action;
no tool can create it).

## Phase 3: Intelligence
**Build:**
- `intel` tables;
- the watched-sources list (competitors, hotels, openings, publications, event calendars);
- the Intelligence Analyst on a weekly cadence, using the existing Firecrawl and Serper accounts within their current budgets;
- every signal labelled verified, inferred or unverified, with evidence links;
- on-demand research briefs from the console.

**Exit:** two weeks of signals, and at least five that Adam marks "actioned" or turns into content.

**Adam decides:** the watch list and the monthly research budget.

## Phase 4: Content studio (no API publishing)
**Build:**
- `content` tables and the Content Strategist;
- the calendar, briefs, drafts and versions;
- the review queue on mobile;
- **manual publish flow**: Copy caption, Download assets, Mark published (with the permalink) → `content.publications` (method
  `manual`);
- the UTM link generator.

**Exit:** four consecutive weeks of the planned calendar shipped through the queue; average review time under 10 minutes a day.

**Adam decides:** the posting cadence per channel.

## Phase 5: Read connections
**Build:**
- the channel verification procedure (operating manual §7);
- readers for Instagram insights, comments and DMs (read), LinkedIn Page analytics (if LinkedIn grants access), Meta Ads read, and
  GA4 / Search Console;
- `analytics` tables;
- the Analytics & Attribution agent and the weekly marketing review with real numbers;
- the `unknown_post_detected` monitor (needs read access).

**Exit:** each connected account shows `read_only` with evidence; one weekly review built only from database numbers.

**Adam decides:**
- create the Meta app and system user in NOYA's Business portfolio (about 30 minutes, guided);
- whether to apply for LinkedIn Community Management API access.

## Phase 6: Leads & HQ hand-off
**Build:**
- `leads` tables, Community Triage and the Lead Qualifier;
- the hand-off outbox;
- **separately approved HQ change**: the intake function (`docs/hq-handoff-contract.md` §5);
- the courier workflow;
- arm `handoff.hq`.

**Exit:** the first qualified lead is delivered, acknowledged with an `hq_reference`, and shows up correctly in HQ with no
duplicate.

**Adam decides:** approve the HQ intake change; D3-B if wanted.

## Phase 7: Governed publishing
**Build:**
- the write tokens (separate credentials) and the `read_write` verification;
- the publisher executor (no LLM node; one API call; idempotency; report);
- staged roll-out:
  - **7a:** 5 posts in dry-run (`MKT_EXTERNAL_WRITES_ENABLED=false`), comparing payloads with what Adam would have posted;
  - **7b:** arm `publish.instagram` and execute 10 approved and confirmed posts, with Adam watching;
  - **7c:** the same for the LinkedIn Page (if access was granted);
- engagement executor (replies) behind its own controls.

**Exit:** ten executed posts, each one identical to its approved payload, all audited, with zero tripwire events.

**Adam decides:** arm each control (typed phrase).

## Phase 8: Governed paid media
**Build:**
- Adam sets the **platform-native account spending limits** first;
- the budget caps (`platform_native_cap_confirmed`);
- the separate ads write token;
- the ads executor;
- the spend monitors (cap, velocity, unknown change);
- D4 auto-pause.

**Order:**
- **8a:** `*.create_paused` only, so campaigns are built on the platform at zero spend;
- **8b:** owner-only, confirmed activation within the cap, for one test campaign with written kill criteria;
- **8c:** the optimisation loop. The analyst proposes; Adam approves.

The policies for `*.activate` and `*.increase_budget` move from `blocked` to `approval_required` by Adam's own `api.set_policy`
call, audited.

**Exit:** the test campaign runs to its kill criteria or its target. Spend never exceeds the cap; every change has an approval.

**Adam decides:** D8 (budget), the platforms and arming `spend.*`.

## Phase 9: Earned autonomy (optional)
Only where the record supports it (approvals-and-permissions §8): narrow, risk-reducing, time-boxed (30 days at most), with
limits, a weekly sample review and automatic fall-back. Never money. Never without Adam's written decision.

---

## Cross-cutting, every phase
- No HQ file, table or workflow is touched (Phase 6's intake is a separate HQ change).
- `check-secrets.mjs` and the governance tests run in CI.
- Each new external action type is added to `gov.action_types` with its policy defaulting to `approval_required` (or `blocked`).
- Costs are tracked per agent; the paid-software gate applies to any new tool.
- Docs are updated in the same commit as the behaviour they describe.
