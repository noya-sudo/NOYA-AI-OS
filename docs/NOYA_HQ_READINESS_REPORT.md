# NOYA HQ — Commercial Operating System Readiness Report (V2.1)
30 Sep 2026. Every figure comes from live Supabase.

## V2.1 — relationship layer activated
**Relationship summaries (workflow 16, `Gh4IYcQNfQJFrts3`, published):**
- All 44 two-way relationships now have a short AI summary.
  - Source: subjects and Gmail previews already imported. No message bodies.
  - The Gmail thread stays the evidence. HQ labels the summary as AI and shows the facts (counts, dates, who wrote last, verbatim preview) separately.
- Fact guards run on the server:
  - "Reply now" only when they genuinely wrote last within 60 days.
  - "Client" only when the CRM already says client. Otherwise it is shown as a partner / supplier.
- Suggested status: Reply now 8, Reconnect 8, Partner 3, Later 20, Long term 1, Not relevant 4. **Adam's status is separate and has not been set yet.**
- Runs daily at 06:50, at most 15 a day, only for new or changed relationships.

**Past relationships → Review:**
- One card at a time, most urgent first. Seven status chips; one tap saves and moves to the next.
- Reply now / Reconnect / Later create internal tasks. Partner / Client update the CRM. Not relevant hides the item.
- Nothing is ever sent. Every change is audited.

**Outreach:** "One at a time" mode on the phone (Back / Skip). Approve still asks for confirmation.

**LinkedIn: ready for the export.**
- Each connection is matched against CRM companies, CRM people, active opportunities and NOYA Gmail relationships, and the evidence is shown in words.
- "Linked to NOYA" ranks people by that evidence only. Relationship strength stays Unknown.
- Re-importing never duplicates (profile link normalised).
- Tested on rolled-back data:
  - 5 rows became 3 people;
  - YKONE matched on company, person, opportunity and Gmail;
  - Purple Ski matched through Gmail;
  - the stranger got no evidence.

**Countries:** UNKNOWN went from 25 to 4 companies.
- 21 were set from real evidence (website, address, public listing), each noted and audited.
- The 4 left have no reliable evidence: Beyond Members Club, Double Culture Films, Sporting Founders, Summits (Pangea).

**Costs:** reconciled from NOYA's billing emails. See the dependency register. Every service can now be corrected in HQ with **Update from invoice**; an amount without a currency is refused, and every change is audited.

**Tests:** 118/118 UI checks. The security scan passes with 30 allow-listed functions and no send path.

## Historical email reconciliation — results
Source: NOYA's own Gmail (noya@noyaconcierge.com), read through the existing Google connection.
- Headers and Gmail's short preview only. Message bodies are never read and no password is stored.
- Window: 29 Sep 2025 to 29 Sep 2026, all 12 months. The mailbox holds 1,732 messages in total.

| Measure | Result |
|---|---|
| EMAILS SCANNED | 1,223 |
| COMMERCIAL THREADS IMPORTED | 451 threads Adam wrote in (727 commercial messages) |
| IGNORED (not stored beyond ID and reason) | 496 (promotions 174, updates/forums 264, bounces 23, automatic replies 19, internal 10, bulk 4, other 2) |
| CONTACTS MATCHED | 9 |
| COMPANIES MATCHED | 11 |
| RELATIONSHIPS RECOVERED | 44 real two-way relationships: 2 already in the CRM, 42 not yet (Past relationships → Not in CRM yet) |
| SENT EMAILS RECORDED | 15 in CRM timelines (EMAIL / OUTBOUND / manual, Gmail Sent Mail only) |
| DUPLICATES PREVENTED | 12 messages already logged by the email workflows were linked, not re-logged. Replaying 200 imported messages created 0 new rows. |
| OLD COLD OUTREACH SUPPRESSED | 1 pending cold introduction held (The Arts Club), plus 1 future cold introduction prevented (Manchester City FC) |
| REACTIVATION OPPORTUNITIES FOUND | 41 conversations worth restarting; 10 relationships where the other side wrote last |

**Proved on real threads:**
- **YKONE:** Magali Rady matched to her contact record. Her reply is joined to Adam's email in one timeline (1 sent, 1 received, meeting stage).
- **The Arts Club:**
  - A cold introduction was waiting for approval, but Adam exchanged emails with them in May 2026.
  - The introduction is now held with the reason shown, and a reconnect task replaces it.
- **Manchester City FC:** emailed twice in Dec 2025, no reply. Marked LONG_TERM.
- **Workflow 05:** cannot draft a cold introduction to either company. It now has a "Prior relationship guard": any earlier email, however old, routes to follow-up or reconnect.
- **Add to CRM:** tested on a real unmatched relationship (Purple Ski, 8 sent / 10 received). One click created the company and person and linked all 18 emails into their timeline. The test was rolled back, so Adam decides.

**Defects found and fixed during the build:**
- **05 rule:** the prior-contact rule only blocked a cold intro if NOYA had emailed the company in the last **3 days**.
- **Multi-send outreach:** Adam's multi-send outreach carries a List-Unsubscribe header, which would have been misread as a newsletter. The bulk filters now apply to incoming mail only.
- **Misfiled replies:** replies that Gmail files under "Updates" are now kept when Adam wrote in the thread.
- **Bounces:** 23 delivery-failure notices had been counted as replies. They are now excluded from replies (seen on the review screenshot and fixed).

## CEO Overview (Today)
**Ready.** One ranked queue, in business language.
- History-based tasks appear as "Previous conversation".
- The System panel now also shows how many software costs are UNKNOWN.

## Outreach
**Ready.** Eight tabs.
- Every card shows "Emailed before" (sent / replies / last date / Gmail link) whenever NOYA Gmail has history with that company or person.
- Cold intros to past contacts are held automatically, with the reason shown.
- Nothing is sent from HQ.

## Historical email
**Ready and live.**
- **Workflow 15:** Gmail history import (`VGNfoaqAMmQ5bZHA`). Backfill done; incremental via Gmail history IDs every 3 hours, 07:00–22:00.
- **Idempotent:** keyed on Gmail message ID.
- **Late matches:** new companies and contacts link to their past emails automatically.

## LinkedIn
**Ready. Waiting for Adam's export.**
- Import Connections.csv: LinkedIn → Me → Settings & Privacy → Data privacy → Get a copy of your data → Connections.
- Connections now match CRM **people** (name at the company) as well as companies.
- "Also emailed NOYA" shows who you know from both LinkedIn and email.
- Drafts in your voice or NOYA's; you send manually.

## Warm network
0 LinkedIn connections imported, so "People you already know" is empty until the export is uploaded. It will rank people at active prospects and those NOYA has emailed before.

## Previous relationships
**New view: Past relationships.** 334 groups in five tabs:
- They wrote last: 10
- Worth reconnecting: 44 two-way relationships
- Not in CRM yet: 42
- Emailed, no reply: 290
- Hidden

Every item links to its Gmail thread. Actions: Add to CRM, Draft reconnect / follow-up, Not relevant.

## Contacts
**Ready.** 70 people, each with email evidence and "Emailed before" where it applies. Add contact reuses a person by email or name, so no duplicates.

## Companies
**Ready.** 91 accounts.
- "Edit details" now sets the country and website from real evidence.
- Clients are flagged "handle personally".

## Pipeline
**Ready.** 72 active opportunities, table and board.
- Meeting-stage records show a "Prepare for the conversation" panel: what they said, why them, email history, suggested angle, next step.

## Replies
**Ready.** Grouped by meaning, with record-meeting on each reply.

## Website leads
**Ready. 0 submissions.** The new website form is not connected yet.
- It must connect to the existing workflow 10d intake; no second intake.
- It will be proven end to end at cutover.

## Finance
**Ready. 0 records.**
- Draft / Sent / Part-paid / Paid / Overdue / Cancelled.
- Collected, Outstanding, Won, Pipeline and Forecast are kept separate, per currency, with no FX.

## Markets
**Ready.** Europe 35 companies, GCC 21, North America 21, Rest of world 7, Egypt 2, Global 1, Unknown 4. Bridges are shown. Market-size data is never invented.

## Growth
**Ready.** Verticals, channels, stalled deals, reactivation and recommended actions, each with its reason.

## Costs
**Ready.**
- 13 services in the register.
- New "How often the automations run" table:
  - reply tracking: ~2,880 runs a month;
  - history sync: ~180 a month;
  - drafting: ~60 a month plus your requests.

## System health
**Ready.** Workflows 14 and 15 report failures to the shared error workflow.

## Security
- Browser: publishable key only; 30 allow-listed functions, all admin-checked and audited; no send path.
- Gmail: read-only, metadata only; ignored mail keeps no content.
- The drafting wake token lives in Supabase Vault. The webhook carries no data.
- LinkedIn: no password or cookie is stored.

## Mobile
**Ready.**
- The 09:00 phone routine passed at 390 px with no horizontal scrolling. Steps covered:
  - P1
  - meeting
  - replies
  - approve
  - LinkedIn copy / mark sent
  - search
  - past relationships
  - pipeline
  - finance
  - new opportunity
- Past relationships are in the Menu.

## Known software cost
- **Amounts:** none confirmed.
- **Free, with evidence:** Hunter (50 credits a month) and Firecrawl (free credits).
- **Fixed, amount in the PDF invoice:** Google Workspace Business Standard.

## Unknown cost exposure
7 services have no plan evidence: n8n Cloud, n8n AI credits, Serper, Supabase, Cloudflare, GitHub and the domain.
- The n8n plan is the most important unknown. The live instance is not billed to noya@.

## Paid services awaiting approval
None.

## Outstanding data gaps
1. **Unknown country:** 4 companies, with no reliable evidence yet.
2. **Relationship review:** 44 relationships have suggestions but no status from Adam. Past relationships → Review takes about 10 minutes on the phone.
3. **LinkedIn:** connections are not yet imported.
4. **Earlier mail:** mail older than 12 months was not imported. It can be extended on request.

## Remaining blockers
- **Adam:** upload the LinkedIn export.
- **Adam:** confirm the n8n plan (n8n → Settings → Usage and plan) and the Serper account. Neither is billed to noya@.
- **Website:** connect the new website form at cutover.

## Recommended next build
1. (Done in V2.1: AI relationship summaries.)
2. **n8n execution-health snapshot:** last success and failure per workflow.
3. **Website form cutover** to workflow 10d, with an end-to-end proof.
