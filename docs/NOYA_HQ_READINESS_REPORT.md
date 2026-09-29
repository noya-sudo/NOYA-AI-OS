# NOYA HQ — Commercial Operating System Readiness Report
30 Sep 2026. Every figure below is live from Supabase.

## CEO Overview (Today)
**Ready.**
- A single queue, ranked P1 / P2 / P3, written in business language ("Reply to Magali Rady — meeting requested").
- Each item's buttons do the work in place: open email, record meeting, copy, mark sent, done, snooze, or not needed (with a reason).
- **Now:**
  - 1 P1: YKONE Middle East, meeting requested.
  - 13 email approvals ready.
  - 14 LinkedIn and 6 Instagram messages ready.

## Outreach
**Ready.** Eight tabs: Ready, Follow-up, LinkedIn, Instagram, Sent, Replied, Hold, Researching.
- **Cards show:**
  - company, person, role, vertical;
  - origin → destination market;
  - best channel, evidence, last contact;
  - email status (VERIFIED / RISKY / UNKNOWN);
  - estimated value, why now, and the message.
- **Actions:** approve, edit, hold, reject, change channel, add note, snooze, copy, open channel, mark sent.
- There is no send button anywhere.

## LinkedIn
**Ready, and waiting for your data export.**
- **Method:** your LinkedIn data export, drafts in HQ, you send. Cost £0, nothing stored except the needed columns.
- 0 connections imported, so "People you already know" is empty until you upload Connections.csv.
- **Drafting:**
  - Workflow 14 is live and was tested end to end: a Gemini draft passed the quality gate, then was discarded.
  - Voice: you personally, or NOYA.
  - 10 message types.

## Contacts
**Ready.** 70 people.
- Email status: 23 VERIFIED and 23 risky / unknown / unverified; the rest have none.
- The evidence behind each email (provider, date, workflow, source) is on hover and in the record.

## Companies
**Ready.** 91 accounts.
- Quick filters: Partnerships, Production, Hospitality, Private, Corporate, Weddings, Sports.
- You can reclassify any account.
- 25 companies have no country recorded, so their market shows as Unknown.

## Pipeline
**Ready.** 72 active opportunities.
- Table and board views.
- Filters: stage, vertical, market, stale.
- **Values:**
  - USD 5,805,000 ESTIMATE across 32 opportunities;
  - 40 opportunities have no estimate (UNKNOWN).
- None of this is shown as revenue.

## Replies
**Ready.** Grouped by meaning, with the suggested reply shown as a draft only. You can record the meeting from a reply.

## Website leads
**Ready. No submissions yet.**
- The intake (workflow 10d) is live.
- It waits for the new website form, which is not connected.

## Finance
**Ready. 0 records.**
- **Statuses:** Draft / Sent / Part-paid / Paid / Overdue / Cancelled. Paid = the sum of payments. The issued amount is locked.
- Collected / Outstanding / Won / Pipeline / Forecast are kept separate, by currency.
- Forecast is "not set".
- No FX conversion.

## Markets
**Ready.**
- **Where clients are based:** Europe 27 companies, North America 19, GCC 10, Egypt 2, Unknown 25.
- **Main bridges:** Europe → Egypt 19 active, GCC → Egypt 8.

## Costs
**Ready.** 13 dependencies registered, each with plan, limit, what breaks, the alternative, where the credential is kept, and renewal date.

## System health
**Ready.**
- Workflow signals, failure alerts and known blockers.
- Workflow 14 reports failures to the shared error workflow.

## Mobile
**Ready.**
- A bottom tab bar and a menu sheet replace the cramped pill row.
- The 10-step 09:00 routine passed at 390 px with no horizontal scrolling:
  1. P1 first
  2. record meeting
  3. Replies
  4. approve
  5. LinkedIn copy
  6. mark sent
  7. search
  8. pipeline board
  9. finance
  10. new opportunity

## Security
- The browser holds only the publishable key and your session.
- 26 allow-listed RPCs, all admin-checked and audited. Workflow 14's functions are service-role only.
- No send path.
- **XSS:** hostile CRM text is escaped (tested).
- The LinkedIn CSV is read in the browser; no credentials are stored.

## Outstanding blockers
1. **LinkedIn connections:** your export upload is needed for the warm network.
2. **Website form:** not connected, so 0 website leads.
3. **Company country:** 25 companies have none, so their market is Unknown.
4. **Costs:** 11 services have UNKNOWN cost or plan, including the n8n execution limit. Verify these before raising volume.
5. **Marketing data** (Windsor free plan) is stale. This is outside this phase.

## Monthly known software cost
None confirmed. **Known fixed monthly: £0 / $0 confirmed.**

## Unknown cost exposure
11 services, marked "UNKNOWN — VERIFY BEFORE SCALE".

## Paid services awaiting approval
None.

## Recommended next build
1. **n8n execution snapshot** (workflow health per workflow). It uses the existing n8n API; no paid service.
2. **Website form → 10d**, once you approve the form placement.
3. **FX method for combined reporting**, when you choose one: a fixed monthly rate is recommended.
