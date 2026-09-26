# NOYA Cloud Progress

Last updated: 2026-09-26 ~19:20 UTC (21:20 Cairo)

## CURRENT PRODUCTION STATE

- **n8n** (noyaprivate.app.n8n.cloud): workflows 00, 00b and 01–11 are unchanged (01 is inactive by design).
- **12 - NOYA Outbound Email Executor v1** (`HOQIzE9gRKmeoz1G`): **inactive / unpublished**. It is run deliberately for one approved outbound id at a time.
- **13 - NOYA Gmail Interaction Sync v1** (`lcc7sb28itQaTubO`): **ACTIVE**, every 15 minutes, Africa/Cairo. It reads Gmail and writes CRM, and has no send, draft or reply node. Its error workflow is 00.
- **Gmail sync go-live boundary: `2026-09-26 19:00:00 UTC`** (in `gmail_sync_state`). Nothing earlier is ever processed.
- **Supabase `noya-ai-hq`** (`gagbhykzmtstekpqujyl`): CRM at baseline — 29 opportunities, 28 tasks, 33 contacts, 44 companies, 0 interactions, 0 revenue rows.
- **Mailbox**: `NOYA Gmail` = `noya@noyaconcierge.com`. Workflows 12 and 13 both check this before doing anything.
- **Prospect auto-send: OFF. Auto-reply: OFF.**

## COMPLETED THIS SESSION

1. Read-only production audit.
2. **Outbound email layer (workflow 12 + migration `20260926170000_outbound_email_layer.sql`)**: approval-gated Gmail draft or explicit send, with VERIFIED / HUMAN_ONLY / duplicate gates and CRM logging. Proven on 26 Sep (see the previous revision of this file in git, commit `14297c8`).
3. **Gmail Interaction Sync (workflow 13 + migration `20260926190000_gmail_interaction_sync.sql`)**
   - **Tables**:
     - `gmail_sync_state`: mailbox, go-live boundary, last run summary.
     - `gmail_sync_ledger`: one row per Gmail message acted on. The primary key is the duplicate guard.
   - **Changes to `outbound_emails`**: status `DISCARDED` added, plus `sent_via` / `sent_at` / `sent_to_email`.
   - **Functions** (service_role only):
     - `gmail_sync_targets`: returns only the threads and senders NOYA itself emailed.
     - `gmail_sync_triage`: logs manual sends and discarded drafts, and picks out inbound replies to classify.
     - `gmail_record_manual_send`
     - `gmail_ingest_inbound`: re-matches on the server side and applies the classification.
     - `gmail_match_inbound`: thread match, then failed-recipient match, then sender match; anything that isn't unique is AMBIGUOUS.
     - `gmail_prelabel`: deterministic BOUNCE / OUT_OF_OFFICE detection.
   - **Workflow 13 flow**: verify mailbox → targets → search contacted senders after go-live → read tracked threads (GET) → triage → classify each matched reply with Claude (`claude-sonnet-4-6`, the same model as the rest of the estate) → apply to CRM.
   - **Conservative rules**:
     - Confidence below 0.7 becomes UNKNOWN, which creates a HUMAN_REVIEW task.
     - The model can never declare a bounce; that needs delivery evidence.
     - A referred contact is captured (UNVERIFIED) only if its email literally appears in the reply.
     - Deals at PROPOSAL, NEGOTIATION or WON are never moved automatically.
     - Suggested replies are stored in the task as a draft for Adam. They are never sent.
   - **Test harness**: the temporary `ZZ TEST - WF13 Gmail Harness` (`7xKcDCtz4wHQW2uv`) is now **archived**.

## CURRENT TASK

Workflow 13: **built, proven and active**. Stopped here as instructed.

## TEST RESULTS — WORKFLOW 13 (26 Sep, internal test threads only)

Inbound replies were simulated with Gmail `messages.insert` into noya@, which delivers nothing to anyone. Test prospects used `@noya-test.invalid`. The only real send was one draft sent from noya@ to noya@.

| Scenario | Evidence | Result |
|---|---|---|
| A. Manual send of an approved draft | WF12 draft `r-7099529814807353295` → sent as message `1a0df1e3bdf75280`, same thread. WF13 (exec 276) logged an OUTBOUND interaction with that id and last_contact_at from Gmail; contact CONTACTED; opportunity CONTACTED/APPROVED; exactly 1 follow-up task; draft-ready and approval tasks completed | PASS |
| A. Reply in the same thread from a different person | Thread match. The model returned confidence 0.6 because the subject read "[NOYA INTERNAL TEST]", so it became UNKNOWN → HUMAN_REVIEW. This is correct conservative behaviour | PASS (fallback) |
| B. Out of office (`Auto-Submitted`) | OUT_OF_OFFICE; return date 2026-10-05 → follow-up moved to 06 Oct; no interaction, no status change | PASS |
| C. Bounce (mailer-daemon, `X-Failed-Recipients`) | BOUNCE; contact email_status INVALID; follow-up CANCELLED; CONTACT_RESOLUTION task | PASS |
| D. Meeting request | MEETING_REQUEST 0.95; contact and opportunity CALL_REQUIRED; MEETING_ACTION task; follow-up completed | PASS |
| E. Not now ("15 January 2027") | NOT_NOW 0.97; contact and opportunity FOLLOW_UP; new follow-up due 15 Jan 2027 | PASS |
| F. Vague ("Noted.") | UNKNOWN 0.2 → HUMAN_REVIEW task; interaction logged | PASS |
| G. Referral with an explicit email | REFERRAL 0.99; referred contact created as UNVERIFIED (source REFERRAL); REPLY_ACTION task | PASS |
| H. New thread from a contacted sender | SENDER match; POSITIVE 0.95; contact and opportunity INTERESTED; REPLY_ACTION task with a suggested reply (not sent) | PASS |
| I. Sender linked to 2 opportunities | AMBIGUOUS → HUMAN_REVIEW task; no status changed | PASS |
| J. Message dated before go-live | ignored (not in the ledger); calling the function directly returns `NOT_ELIGIBLE` | PASS |
| K. Stranger never contacted | never read (not in the search), not in the ledger | PASS |
| Draft deleted unsent | outbound → DISCARDED; draft-ready task CANCELLED (exec 290) | PASS |
| Duplicate: full re-run | exec 290: 0 re-classified; ledger 10→10, interactions 7→7 | PASS |
| Duplicate: direct replays | inbound replay → `DUPLICATE_MESSAGE`; manual-send replay → `NOT_DRAFTED` | PASS |
| Never sends | WF13 contains only Gmail GET requests and has no send, draft or reply node | PASS |

**Cleanup:**
- All 14 test Gmail threads were trashed and the test draft deleted.
- All test CRM rows and ledger rows were deleted.
- The CRM is back to exactly 29 / 28 / 33 / 44 with 0 interactions, 0 outbound and 0 ledger rows.

**Real prospect emails sent: 0.**

## BLOCKERS

1. **No approval UI yet.** For now, an approval means Adam tells Claude "approve & draft X"; Claude runs `outbound_approve` and triggers workflow 12. Workflow 12 stays unpublished until the dashboard exists.
2. **Replies are suggested, not staged.** A suggested reply sits as text in the task; it is not yet a Gmail draft in the thread. Adam replies himself from Gmail, and workflow 13 does not log his own replies unless they come from an approved draft.

## NEXT ACTION

Waiting for Adam. First real outreach:
- Adam picks one of the 4 verified opportunities: Quintessentially, Armani, Rafanelli or Nobu. All are HUMAN_ONLY, so draft only.
- Claude creates the approved Gmail draft.
- Adam reviews it and presses Send in Gmail.
- Workflow 13 logs the send and tracks replies automatically.

## DO NOT TOUCH

- Workflows 00, 00b, 01–11, and the Squarespace site.
- `reports@noyaconcierge.com`: internal CEO reporting only.
- Do not publish workflow 12 until the dashboard calls it.
- Do not move `gmail_sync_state.go_live_at` earlier; that would import historical mail.

## KNOWN CREDENTIAL NAMES (names only)

- n8n: `NOYA Gmail` (gmailOAuth2), `Supabase account` (supabaseApi), `Anthropic account`, `NOYA Resend LIVE`, `NOYA Resend Header`, `NOYA Hunter` / `NOYA Hunter v2` / `Noya Hunter v2`, `NOYA Serper` / `Noya Serper v2` (x2), `NOYA Firecrawl`, `NOYA Windsor`.
- Supabase: project `gagbhykzmtstekpqujyl`. Service-role key lives only inside the n8n `Supabase account` credential.
