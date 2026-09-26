# NOYA Cloud Progress

Last updated: 2026-09-26 ~19:45 UTC (22:45 Cairo)

## CURRENT PRODUCTION STATE

- **n8n**: workflows 00, 00b and 01–11 are unchanged (01 is inactive by design).
  - **12 - NOYA Outbound Email Executor v1** (`HOQIzE9gRKmeoz1G`): **ACTIVE (published 26 Sep)**. It is triggered only by the CEO Command Centre (`hq_approve_draft` via `pg_net`) for a single approved outbound id. It creates Gmail drafts only; no SEND row can be created from the dashboard.
  - **13 - NOYA Gmail Interaction Sync v1** (`lcc7sb28itQaTubO`): **ACTIVE**, every 15 minutes. The first scheduled run succeeded at 19:30 UTC (exec 293).
- **CEO Command Centre**: built in `hq/`. **Deployment-ready; not hosted yet.**
  - Server side: migration `20260926200000_hq_command_centre.sql`, plus the hardening migration `20260926201000_pin_helper_search_path.sql`.
  - Admin: `adam.elshazly1012@gmail.com` (Supabase Auth user `0d858bd9-…`, in `hq_admins`). The temporary password is flagged must-change.
- **Supabase `noya-ai-hq`**: CRM at baseline — 29 opportunities, 28 tasks, 33 contacts, 44 companies, 0 interactions, 0 outbound, 0 revenue.
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

1. **Hosting for `hq.noyaconcierge.com`.** Supabase Edge Functions cannot serve HTML, and no static host is connected. `hq/dist` is ready (see `hq/README.md`).
2. **Supabase security advisor warnings.**
   - Informational: "authenticated can execute SECURITY DEFINER" (the 6 `hq_*` functions, by design with an allowlist check).
   - Optional: turn on leaked-password protection in Supabase Auth settings.

## NEXT ACTION

Adam connects a static host for `hq/dist` and points `hq.noyaconcierge.com` at it. See `hq/README.md`; Cloudflare Pages is the suggested host.

His login is in an **unsent draft in noya@ Gmail Drafts**, subject "NOYA HQ — your login". He must change the password on first sign-in, then delete that draft.

## DO NOT TOUCH

- Workflows 00, 00b, 01–11, and the Squarespace site.
- `reports@noyaconcierge.com`: internal reporting only.
- Do not add an APPROVE & SEND path in this phase.
- Do not move `gmail_sync_state.go_live_at` earlier.

## KNOWN CREDENTIAL NAMES (names only)

- n8n: `NOYA Gmail` (gmailOAuth2), `Supabase account` (supabaseApi), `Anthropic account`, `NOYA Resend LIVE`, `NOYA Resend Header`, `NOYA Hunter` / `NOYA Hunter v2` / `Noya Hunter v2`, `NOYA Serper` / `Noya Serper v2` (x2), `NOYA Firecrawl`, `NOYA Windsor`.
- Supabase: project `gagbhykzmtstekpqujyl`.
  - The browser uses only the publishable key.
  - The service-role key lives only inside the n8n `Supabase account` credential.
