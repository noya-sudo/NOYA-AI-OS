# Workflow 10d: Private Calendar attribution (LIVE since the V3 go-live, 3 Oct 2026)

- Workflow: **10d - NOYA Website Enquiry Intake** (`eLucjNPgTRKS5nBC`).
- Live (active) version: `bf8b216b-b0da-417d-9628-aedd1184d2c2`, published 3 Oct 2026 after APPROVE V3 FINAL and the merge to `main`.
- Previous version (rollback): `2ea5fdfe-f8a8-40c5-9749-547a0d65037a`.
- The folder keeps its `_draft` name so earlier links still resolve.

## Verified live (3 Oct 2026, www.noyaconcierge.com)

- Execution 976: a Private Calendar enquiry (NOYA-NGRAYT, Monaco Grand Prix 2027). In HQ: `source_detail = PRIVATE_CALENDAR`, `event_id = monaco-grand-prix-2027`, `signal_id` linked to the radar row with `calendar_slug = monaco-grand-prix-2027`. The opportunity carries the signal. The task reads "New website enquiry — Private Calendar: Monaco Grand Prix 2027 — …".
- Execution 977: a villa enquiry (NOYA-CHFX96, regression). Unchanged: no event fields, no signal.
- Both were production tests named "NOYA WEBSITE PRODUCTION TEST — DO NOT ACTION". Their tasks are COMPLETED, their opportunities ARCHIVED and their auto-created contacts DO_NOT_CONTACT, as are the two from the 30 Sep cutover check.

## What this version changes

An enquiry is treated as a Private Calendar enquiry only when it arrives with `source = website_calendar` and an `event_name`. Every other enquiry runs exactly as before. For a calendar enquiry:

- **Validate & Normalize Enquiry** (`validate_normalize.draft.js`): reads `event_id`, `event_name`, `event_city` and `event_dates`. The context begins "Channel: Website → Private Calendar → <event> (<city>, <dates>)", followed by "Event page: /calendar/<event_id>". It returns `isCalendar` and `sourceDetail = PRIVATE_CALENDAR`.
- **Insert website_enquiries**: also writes `source_detail`, `event_id`, `event_name`, `event_city` and `event_dates`. The Supabase triggers from migration `20261003090000_private_calendar.sql` link `signal_id` to the radar row (`intelligence.calendar_slug = event_id`) and copy it onto the opportunity.
- **Task title**: "New website enquiry — Private Calendar: <event> — <lead type> (<ref>)". The task description opens with "Source: Website → Private Calendar → <event>."
- **Opportunity reason**: "Inbound enquiry via NOYA website — Private Calendar: <event>".

`update_ops.json` holds the exact `update_workflow` operations that produced this version.

## Tested (n8n `test_workflow`, credentials pinned)

- Execution 958: a calendar enquiry. Success, with the context, task and fields as above.
- Execution 971: a villa enquiry (regression). Success, context unchanged.
- The website's `npm run verify:intake` runs the draft code (`qa/10d-validate-normalize.draft.snapshot.js`) and the live code side by side.

## Roll back

- Re-publish `2ea5fdfe…`: n8n MCP `publish_workflow` with `eLucjNPgTRKS5nBC` and that version, or in n8n: Workflow → History → that version → Publish. The website keeps sending the event fields; the old version ignores them.
