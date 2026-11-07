# NOYA Marketing OS: Architecture

Status: **Phase 1 built and tested; Supabase project pending one permission.** Nothing connects to any platform, publishes
or spends. Last updated: 7 Nov 2026.

## Phase 1 at a glance

| Piece | Where | State |
|---|---|---|
| Control plane (approval engine, kill switches, audit, registries, safety, alerts outbox, health) | `supabase/migrations/` → `docs/database.md` | Written; 28/28 tests pass on PostgreSQL 16 |
| Internal console | `console/` | Built; headless-browser checks pass (desktop + mobile); demo mode until the project exists |
| Alert dispatcher (Resend, D6) | `supabase/functions/mos-alert-dispatcher/` | Written, not deployed |
| Security model | `docs/security-model.md` | Threat → control → test mapping |
| Integrations | `docs/integrations.md` | Nothing connected; registry tracks current, prepared and future connectors |

Decisions D1–D7 are taken (see `docs/decisions.md`). The Phase 0 names in sections below have been superseded where they differ:
the implementation uses `approval_requests` / `approval_versions` / `execution_requests` / `execution_results`, kill switches
`global`, `organic.*`, `paid.*`, `integration.*`, and worker Postgres roles instead of a shared service key.

---

## 1. What this system is

Marketing OS is NOYA's marketing department, built to be AI-native. It owns:

| Owns | Examples |
|---|---|
| Brand | Voice rules, visual tokens, asset library and usage rights |
| Intelligence | Openings, competitors, destinations, trends, platform changes |
| Content | Instagram, LinkedIn Company Page, drafts for Adam's personal LinkedIn, journal |
| Organic growth | Calendar, community, collaborations, creators |
| Paid acquisition | Media plans, campaign mirrors, spend, tests |
| Analytics and attribution | Metrics, UTM links, touchpoints, cost per qualified enquiry |
| Marketing-generated leads | DMs, comments, forms and lead ads, up to qualification |

What it does **not** own: clients, suppliers, bookings, itineraries, payments, operations, outbound sales. Those stay in **NOYA HQ**.

```
                    ┌───────────────────────────── NOYA MARKETING OS ─────────────────────────────┐
  Instagram ─┐      │                                                                              │
  LinkedIn  ─┤ read │  Intelligence ─► Content ─► Brand Guardian ─► Approval ─► Executor (gated)  ─┼─► platforms (write)
  Meta Ads  ─┤─────►│        │            │                              ▲                         │
  GA4 / web ─┘      │        ▼            ▼                              │                         │
                    │   Analytics ◄── Publications / Spend          Adam (owner)                    │
                    │        │                                           │                          │
                    │        ▼                                           │                          │
                    │  Inbound leads ─► Qualification ─► HQ hand-off outbox ─► Approval ─► Courier ─┼─► NOYA HQ
                    └──────────────────────────────────────────────────────────────────────────────┘
                                                                        ▲
                                     outcome (won / lost / value) ──────┘   (read back for attribution)
```

## 2. The boundary with NOYA HQ

The two systems are **separate products with one narrow, one-way interface.**

| Rule | Why |
|---|---|
| Separate Supabase project, separate keys, separate auth users | A bug, a leaked key or a bad migration in one system cannot touch the other |
| Marketing OS **never** writes to HQ tables and holds **no** HQ service key | HQ is the commercial source of truth; marketing noise must not reach it |
| Only a **qualified commercial opportunity** crosses, via the hand-off contract (`docs/hq-handoff-contract.md`) | Adam's HQ queue stays commercial |
| The hand-off is an action request like any other external write: approval required, kill-switchable (`handoff.hq`) | Same safety model everywhere |
| HQ returns only an acknowledgement and, later, the outcome (won / lost / value) | Closes the attribution loop without exposing HQ data |
| No HQ file, table, function or workflow is changed by Marketing OS work | Instruction from Adam; HQ-side intake is a separate, separately approved HQ change |

**What crosses and what stays.**

| Stays in Marketing OS | Crosses to HQ |
|---|---|
| Followers, likes, comments, general DMs | A named person or company with a real NOYA service need |
| Creator and press enquiries with no revenue attached | A paid brand trip, a production with budget, a corporate programme |
| Unqualified or nurture leads | A lead that passes all five qualification gates |
| Content collaborations (hotel shoots, editorial) | A hotel or partner proposing commercial terms (commission, retainer) |
| Audience and campaign data | Only what HQ needs to act: contact, need, context, source |

**Existing HQ marketing pieces (left untouched).** HQ already has `content_performance`, `paid_media_performance`,
`competitor_intelligence`, `marketing_attribution`, `website_enquiries` and workflows 10a–10d. 10a–10c are paused (Windsor plan)
and 10d (website intake) is live. Marketing OS does not modify any of them. The proposed path is in the implementation plan:
Marketing OS becomes the source of truth for marketing data, 10a–10c stay paused, and 10d stays in HQ until the hand-off is proven.
This is decision D3 in `docs/decisions.md`.

## 3. Design principles

1. **Propose → approve → execute.** Agents propose. Humans approve. A separate executor carries out exactly what was approved.
2. **The model never holds the pen.** LLM agents have no write credentials and no write tools. Executors hold write
   credentials and contain no LLM. A prompt injection in a DM or a scraped web page can therefore, at worst, produce a bad
   *proposal* that Adam sees and rejects.
3. **Approval is bound to bytes.** An approval covers the SHA-256 of the exact payload. Changing a single character
   invalidates it.
4. **Fail closed.** Missing policy, missing control row, unreachable database, unverified connection or expired approval all
   mean: do nothing.
5. **Installed halted.** Every kill-switch control starts `halted`. The owner arms each one, with a typed phrase and a reason.
6. **Halting cancels; arming never resumes.** Work approved before a halt must be approved again.
7. **Never fabricate a connection.** A channel account cannot be `read_only` or `read_write` without a recorded verification call.
8. **Everything is on the record.** Every decision, refusal, arm, halt and execution goes into a hash-chained, append-only audit log.
9. **Money is special.** Money-moving actions can never be automatic. That rule lives in the database and changes only by migration.
10. **Simple stack.** Supabase, n8n, Claude, Cloudflare static hosting, plus the platforms' own APIs. No new SaaS unless the
    paid-software gate (HQ dependency register) is passed.

## 4. Components

| Layer | Technology | Holds secrets? | Notes |
|---|---|---|---|
| **Control plane / data** | New Supabase project (Postgres, Auth, Storage, pg_cron) | Service key used by n8n only | All state, governance, audit. Proposed schema in `supabase/proposed/` |
| **Marketing Console** | Static site on Cloudflare (same pattern as `hq.noyaconcierge.com`) | Publishable key only | Review queue, calendar, kill switch, audit viewer. Calls `api.*` RPCs only |
| **Agents** | n8n workflows calling the Claude API (and existing research tools) | Read-only credentials only | Write their output to Supabase as proposals, signals, drafts, analyses. DB role `mos_agent` (can only propose) |
| **Readers** | n8n workflows, deterministic | Read-only platform tokens | Pull insights, spend, comments, DMs into Supabase |
| **Executors** | n8n workflows, deterministic, **no LLM node** | Write tokens, separate from read tokens | Claim one approved request, re-check every gate, call the API once, report. DB role `mos_executor` |
| **Monitors** | n8n workflows + pg_cron | Read-only | Evaluate tripwires; can disable switches and raise D4 pauses; never enable. DB role `mos_monitor` |
| **Alert dispatcher** | Supabase Edge Function | Marketing OS's own Resend send-only key | Sends the alert outbox to Adam (D6). DB role `mos_dispatcher` |
| **Courier** | n8n workflow | HQ hand-off signing secret | Delivers approved hand-offs to the HQ intake endpoint (Phase 6) |

### Why n8n, not a new runtime
NOYA already runs 33 workflows on n8n Cloud, with credentials, error reporting (workflow 00) and an existing operating rhythm.
A second runtime would double the maintenance for no capability gain. Each executor workflow is deliberately tiny and readable.

### Why a separate Supabase project
See D2 in `docs/decisions.md`. In short: a hard blast-radius boundary, independent keys, independent RLS. The Supabase
free tier allows two active projects. HQ's plan is recorded as Free (dependency register), so the second project is likely
free, but this is to be confirmed before creation.

## 5. Agents

Agents are workers under Adam's CEO Chief of Staff. Each one has a charter in `agents/README.md`. All start `enabled = false`.

| Agent | Department | Reads | Produces | May propose (needs approval) |
|---|---|---|---|---|
| Brand Guardian | brand | brand rules, assets, drafts | `content.checks` (pass / warn / fail) | nothing; it is a gate |
| Intelligence Analyst | intelligence | watched sources, web research | `intel.signals`, `intel.research_briefs` | nothing |
| Content Strategist | content | signals, pillars, performance | calendar, briefs, `content.versions` | `instagram.publish_*`, `linkedin_page.publish_post` |
| Community Triage | community | comments, DMs (read) | lead candidates, reply drafts | `instagram.reply_comment`, `instagram.send_dm`, `instagram.hide_comment` |
| Paid Media Analyst | paid | spend, insights, plans | `paid.media_plans`, optimisation notes | `meta_ads.create_paused`, `meta_ads.pause`, `meta_ads.decrease_budget` |
| Analytics & Attribution | analytics | snapshots, touchpoints, HQ outcomes | weekly marketing review, cost per qualified enquiry | nothing |
| Lead Qualifier | leads | inbound leads | `leads.qualifications`, hand-off drafts | `hq.handoff_opportunity` |

Agents report decisions, not raw output: "38 posts analysed, 3 formats outperform, here is the change I propose."

Money-moving actions (`*.activate`, `*.increase_budget`, `*.edit_targeting`) can be proposed only by a human in v1. No agent's
`may_request` includes them.

## 6. The action pipeline (the heart of the system)

```
 draft ──► pending_approval ──► approved ──► (confirm) ──► queued ──► executing ──► succeeded
   │              │                 │                         │            └──────► failed
   └► cancelled   ├► rejected       ├► expired                ├► blocked (kill switch)
                  ├► changes_requested                        └► expired
                  └► blocked
```

1. **Draft.** An agent or a person builds the exact payload: caption, asset ids, account and schedule.
2. **Checks.** Brand Guardian runs voice, banned phrases, claims, asset rights, platform rules and privacy. A `fail` blocks
   submission.
3. **Pending approval.** The payload is now frozen (database trigger). Its SHA-256 is computed by the database, not by the caller.
4. **Decide.** The approver sees the rendered payload and its hash. `api.decide` refuses if the hash changed since it was shown.
5. **Confirm.** For risky types (default: all of them), a second "run it now" click. Every gate is re-checked.
6. **Execute.** The executor calls `api.executor_claim`, which re-checks every gate in the same transaction and locks the row.
   The executor makes **one** API call with an idempotency key, then calls `api.executor_report`.
7. **Record.** The result goes to `content.publications` or `paid.entities`, plus `gov.external_call_log` and the audit log.

The single gate is `gov.can_execute()`. Policy, approvals on this exact payload, expiry, confirmation, kill switch, schedule,
verified `read_write` connection and budget cap all have to pass. The executor also checks environment flags the database cannot
see: `MKT_ENV=production` and `MKT_EXTERNAL_WRITES_ENABLED=true`. Otherwise it runs dry and records `dry_run = true`.

Details: `docs/approvals-and-permissions.md`, `docs/kill-switch.md`, `docs/audit-logging.md`.

## 7. Data model

Implemented in Phase 1 for the control plane: schemas `gov` and `ops`, no tables in `public`, only `public.mos_*` functions.
Full reference: `docs/database.md`. The marketing domain tables (brand, intel, content, paid, analytics, leads) remain designed in
`supabase/proposed/0002_marketing_domains.sql` and are added phase by phase.

## 8. Security model

| Concern | Control |
|---|---|
| Browser | Publishable key + user JWT; tables revoked from `anon` / `authenticated`; only `api.*` functions granted |
| Who may do what | `gov.members.role`: owner > approver > editor > analyst > viewer. One owner (Adam) enforced by a unique index |
| Non-humans | `gov.service_identities` plus dedicated Postgres roles (`mos_agent`, `mos_executor`, `mos_monitor`, `mos_dispatcher`); the service key is granted nothing. See `docs/security-model.md` |
| Secrets | n8n credential store and Supabase secrets only; `.env*` git-ignored; `scripts/check-secrets.mjs` scans the repo; `gov.secrets_registry` records names and locations, never values |
| Read vs write tokens | Separate credentials per platform (`*_READ_TOKEN`, `*_WRITE_TOKEN`). Readers and agents never receive write tokens |
| Prompt injection | Untrusted text (DMs, comments, web pages) is data. Agents cannot act on it; they can only propose, and proposals are reviewed |
| Personal data | Minimised excerpts, lawful basis per lead, 12-month default retention, do-not-contact honoured; data stays in the EU region project |
| Platform terms | Official APIs only. No scraping of logged-in sessions, no unofficial DM tools, no automation of Adam's personal LinkedIn |

## 9. Environments

| Env | Supabase | Platform credentials | External writes |
|---|---|---|---|
| `development` | Local Postgres or a branch | **None exist** | Impossible (no credentials; executors refuse) |
| `staging` | Supabase branch | Read-only tokens; write tokens only for **test** accounts | Test accounts only, dry run by default |
| `production` | Marketing OS project | Read + write, separately stored | Only approved, confirmed, armed requests |

During development there is no write path at all. Publishing and spend are not merely switched off; the credentials do not exist.

## 10. Costs and limits

- Every agent has `daily_cost_cap_usd`. A run that would exceed it is recorded as `skipped_budget`, never silently degraded.
- Research reuses NOYA's existing Firecrawl and Serper accounts, within the budgets already set in HQ.
- Platform APIs (Instagram Graph, LinkedIn, Meta Marketing API, GA4) cost nothing to call; the constraint is rate limits.
- No new paid tool without the paid-software gate.

## 11. Decisions

D1–D7 decided by Adam on 7 Nov 2026 (`docs/decisions.md`). D8 (first paid test budget) remains open until Phase 8.
