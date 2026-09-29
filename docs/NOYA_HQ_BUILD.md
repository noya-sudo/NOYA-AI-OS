# NOYA HQ — build log and architecture

Status as of 30 Sep 2026 (01:00 Cairo). HQ is the control layer over Supabase and n8n. It is not another database.

## Status

| Item | Designed | Coded | Tested | Connected to live data | Production-ready | Live |
|---|---|---|---|---|---|---|
| Phase 1: data and architecture audit | ✓ | — | ✓ | ✓ | — | — |
| Phase 2: HQ shell (navigation, auth, layout, search, record drawer) | ✓ | ✓ | ✓ | ✓ | ✓ | **no** |
| Phase 3: CEO Overview V1 | ✓ | ✓ | ✓ | ✓ | ✓ | **no** |
| `hq_overview()`, `hq_task_action()`, `system_blockers` (database) | ✓ | ✓ | ✓ | ✓ | ✓ | yes (additive, admin-only) |
| Phase 4: Contacts and Companies record views | ✓ | — | — | — | — | — |
| Phases 5–12 | outlined below | — | — | — | — | — |

**"Live: no" means:**
- The new frontend is in `hq/src`, and `npm test` passes: 42/42 browser checks against a live snapshot, plus the security scan.
- `hq/dist`, the build Cloudflare serves at hq.noyaconcierge.com, is deliberately left at the 27 Sep build.
- The remote has no `main`. Production may deploy from this branch, so committing a new `hq/dist` could switch Adam's live dashboard without his approval.

**To go live:** run `cd hq && npm run build`, commit `hq/dist`, then push. The database side is already live and is backward compatible; the current dashboard still uses `hq_dashboard()` unchanged.

## Visual system (Adam's brief, 30 Sep)
- **Colours:**
  - NOYA Navy `#061422` frames the system: sidebar, top bar, mobile nav and sign-in.
  - Content sits on off-white (`#f4f3ef`) with white panels, dark navy text (`#0f1c2a`) and light grey borders.
  - Colour is used only for priority (P1 filled, P2 outlined) and status (ok / warn / bad / info), all muted and readable on white.
- **Type:** Inter (variable font, bundled locally at `dist/fonts/` because the CSP allows no third-party font host).
- **Shape and effects:** small radii (4–6 px), no gradients, no glass effects, no gold-on-black.
- **Logo:** no clean vector NOYA mark exists in the repo or in Drive. The live site's header logo is a screenshot PNG, and Drive holds only the brochure PDF. The sidebar uses a discreet letter-spaced NOYA wordmark. When `hq/src/noya-mark.svg` is added, the build places the mark beside the wordmark automatically.
- **Tested:** Inter loads under the CSP; shell is `rgb(6, 20, 34)` and panels are white. 44/44 browser checks pass.

## A. Database audit (live, 30 Sep)

| Object | Rows | HQ use |
|---|---|---|
| `opportunities` | 73 | Pipeline, stages (`NEW` … `ARCHIVED`), estimate + currency, next action. 40 active have no estimate (UNKNOWN); 32 have USD estimates. GBP rows carry no value. |
| `companies` | 92 | Accounts. `relationship_status` ∈ prospect / client / partner / supplier / mixed / inactive. |
| `contacts` | 70 | People. Email status and provenance (`contact_email_provenance` view). 19 have no company (person-led: talent, creators). |
| `tasks` | 115 | The unified action system: approval, contact, follow-up, reply, meeting and alert types. |
| `interactions` / `gmail_sync_ledger` | 12 / 14 | Sends and replies, via workflow 13. |
| `outbound_emails`, `outreach_drafts`, `approval_queue_state`, `approval_audit` | 9 / 8 / 0 / 43 | Approval loop and audit. |
| `contact_email_verifications` | 14 | Hunter evidence log (provenance). |
| `website_enquiries`, `marketing_attribution` | 0 / 0 | Workflow 10d intake. Live, but no submissions yet. |
| `revenue` | 0 | Finance. `payment_status` ∈ PENDING / PART_PAID / PAID / REFUNDED / CANCELLED. |
| `cost_ledger` | 0 | Finance costs, not yet used. |
| `ceo_reports` | 21 | Workflow 11 briefs. |
| `intelligence`, `competitor_intelligence` | 13 / 17 | Workflows 09 and 10c. |
| `content_performance`, `paid_media_performance` | 11 / 11 | 10a/10b. Stale: Windsor account limit. |
| `department_run_metrics`, `cost_observability` (view) | 13 | Discovery usage, Hunter, reply AI, briefs. Money is UNKNOWN. |
| `system_config`, `system_blockers` | 4 / 3 | Model routing, throttle, budget, unit costs; data-backed blockers. |

**Data quality at audit time:**
- Found and fixed: 8 duplicate open outreach tasks. Curated `OUTREACH_READY` tasks sat alongside 05's tasks, because 05's dedupe did not know that type.
  - Data merged in `20260930090000`.
  - Cause fixed in 05, published as `62988121`.
- Zero rows: orphan tasks, opportunities pointing at missing contacts, invalid stages or currencies (GBP/USD only), account duplicates, false VERIFIED.
- 3 opportunities have no company (person-led).
- 3 overdue open tasks.

## B. Workflow map → HQ

| Workflow | Feeds |
|---|---|
| 02 / 03 / 04 / 06 / 07 / 08 discovery | opportunities, companies, contacts, `department_run_metrics` → Pipeline, Companies, System, cost |
| 05 sales and outreach | approval / LinkedIn / Instagram / contact tasks, `contact_email_verifications` → Outreach, action queue |
| 12 outbound executor | `outbound_emails` (Gmail drafts only) → Outreach loop |
| 13 Gmail sync | `gmail_sync_ledger`, interactions, reply / meeting / follow-up tasks → Inbox, action queue |
| 10d website intake | `website_enquiries`, contact, company, opportunity, task, attribution → Website leads, action queue P1 |
| 11 CEO brief | `ceo_reports` → Reports, System signal |
| 09 / 10c intelligence | `intelligence`, `competitor_intelligence` → Intelligence |
| 10a / 10b marketing | `content_performance`, `paid_media_performance` → Reports |
| 00 / 00b alerts and health | alert tasks → System failures (priority ≥ 50); lower-priority notices become blockers |

## C. Gap analysis (only what is genuinely required)

1. **Done:**
   - A data-backed blockers list (`system_blockers`).
   - A single server-side Overview read (`hq_overview`).
   - Safe task writes (`hq_task_action`).
2. **Phase 4:** `hq_record(opportunity|company|contact)` and `hq_search(q)` RPCs. V1 search and the record drawer work over the data already loaded. Contacts/companies without an opportunity, and email provenance, need the new RPCs.
3. **Phase 9 (finance), schema needed:**
   - `revenue` has no amount-paid, due-date or invoice-status fields, so part-paid amounts are UNKNOWN;
   - no FX table.
   - Proposed: add `amount_paid`, `due_at` and `invoice_status` (DRAFT / SENT / PART_PAID / PAID / OVERDUE / CANCELLED) with backward-compatible defaults, and keep currency totals separate until an FX methodology exists. This needs Adam's finance classification before it is migrated.
4. **Phase 11 (system health):**
   - Per-workflow last success, last failure and error need n8n execution data in Supabase. Proposed: a small scheduled n8n workflow that reads the n8n API and upserts one row per workflow.
   - This needs an n8n API credential inside n8n; it is not exposed to the browser.
5. **Partnerships / Production / Hospitality:** these are views over existing companies and opportunities (`commercial_vertical()`, company types). No new tables unless partner capabilities or countries must be stored; `company_relationships` exists and is empty.

## D. Architecture (kept lean)

- **Frontend:** the existing static site, `hq/` (esbuild, no framework, no CDN). Deployed as static assets on Cloudflare; strict CSP (`script-src 'self'`, `style-src 'self'`, connect only to Supabase).
  - Next.js was not introduced: it would add a server with nothing to do.
- **Auth:** Supabase Auth, email and password. Only `hq_admins` (user id + email) can call any `hq_*` function.
- **Data:** the browser holds only the publishable key. RLS is deny-all on every table. All reads and writes go through SECURITY DEFINER `hq_*` functions that re-check the admin and audit every write in `approval_audit`.
- **Writes allowed:**
  - approval flow (edit / approve & draft / hold / reject / redispatch);
  - task complete / snooze / assign.
  - Approval tasks cannot be "completed"; they close only through the approval flow.
  - No send path.
- **Environments:**
  - Development: the local build plus `tests/ui.mjs`, with network-intercepted live snapshots and no writes.
  - Database write tests run inside rolled-back transactions.
  - Preview: the source on this branch.
  - Production: the committed `hq/dist`.

## E. CEO Overview V1 (built)

- **Action queue:** P1 / P2 / P3, ranked server-side. Every P1 is shown, then the top 8 P2 (the rest on click), with P3 collapsed.
  - **P1:** replies and meetings (workflow 13), new website enquiries, production failures, open proposals, invoices pending more than 30 days.
  - **P2:** approved Gmail drafts not yet sent, approvals ready (verified recipient, nothing in flight), follow-ups due, LinkedIn / Instagram messages ready, Adam-instructed personal actions.
  - **P3:** parked manual LinkedIn / warm-path actions, other overdue tasks.
  - Each row shows company, person, source, due date / overdue, an estimate labelled ESTIMATE (never shown as revenue), next action, and Open / Review / Done / Snooze.
- **Scorecard:** stage bar plus active, in conversation, call required, proposals, won, approvals ready, positive replies (7 days), website (7 days), overdue tasks and system. Each label carries its SQL definition.
- **Money:**
  - Collected / Outstanding (ACTUAL, from `revenue`) and Won deals.
  - Pipeline (ESTIMATE) per currency, plus a count of opportunities with UNKNOWN value.
  - Currencies are never added together. With 0 revenue records it says "none recorded", not "0".
- **Replies (14 days):** deterministic bounce / out-of-office labels are marked as rule-based.
- **Website (30 days):** an honest empty state while 10d has had no submissions.
- **System:** four workflow signals (13, 11, 12, discovery), failure alerts, and the blockers count.
- **Verification (30 Sep 00:00 Cairo):** every displayed number was re-counted with independent raw SQL and matched:
  - active 72, in conversation 8, call required 1 (YKONE), proposals 0, won 0;
  - positive replies 1, website 0, overdue 3, revenue records 0;
  - pipeline USD 5,805,000 across 32 opportunities, 40 UNKNOWN;
  - approvals ready 13.
- **Security tests:**
  - an anonymous caller has no execute rights;
  - a signed-in non-admin gets "not authorised";
  - task actions validate dates and actions, refuse approval tasks and audit every change.

## Phases after V1

4. Contacts and Companies: `hq_record` + `hq_search`, email provenance, duplicate guard, board view for the pipeline.
5. Tasks: assign in the UI, bulk snooze, owner filters.
6. Outreach: change channel, snooze an approval, prior-communication panel.
7. Inbox: reply groups with linked tasks and recommended actions (V1 grouping done).
8. Website leads: full enquiry record (dates, guests, attribution) once real submissions exist.
9. Finance: schema above, after Adam's classification decision.
10. Reports and intelligence: pipeline by vertical/country, response and conversion rates, the Partnerships / Production / Hospitality views.
11. System health: the n8n execution snapshot workflow.
12. Polish and mobile.
