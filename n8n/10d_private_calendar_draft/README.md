# Workflow 10d: Private Calendar attribution (draft, publish at V3 go-live)

- Workflow: **10d - NOYA Website Enquiry Intake** (`eLucjNPgTRKS5nBC`).
- Live (active) version: `2ea5fdfe-f8a8-40c5-9749-547a0d65037a`. It is unchanged and still serving every website enquiry.
- Draft version: `bf8b216b-b0da-417d-9628-aedd1184d2c2`. **Not published.** Publish it only when V3 is approved and merged (CEO decision 2A, 3 Oct 2026).

## What the draft changes

An enquiry is treated as a Private Calendar enquiry only when it arrives with `source = website_calendar` and an `event_name`. Every other enquiry runs exactly as before. For a calendar enquiry:

- **Validate & Normalize Enquiry** (`validate_normalize.draft.js`): reads `event_id`, `event_name`, `event_city` and `event_dates`. The context begins "Channel: Website → Private Calendar → <event> (<city>, <dates>)", followed by "Event page: /calendar/<event_id>". It returns `isCalendar` and `sourceDetail = PRIVATE_CALENDAR`.
- **Insert website_enquiries**: also writes `source_detail`, `event_id`, `event_name`, `event_city` and `event_dates`. The Supabase triggers from migration `20261003090000_private_calendar.sql` link `signal_id` to the radar row (`intelligence.calendar_slug = event_id`) and copy it onto the opportunity.
- **Task title**: "New website enquiry — Private Calendar: <event> — <lead type> (<ref>)". The task description opens with "Source: Website → Private Calendar → <event>."
- **Opportunity reason**: "Inbound enquiry via NOYA website — Private Calendar: <event>".

`update_ops.json` holds the exact `update_workflow` operations applied to the draft.

## Tested (n8n `test_workflow`, credentials pinned)

- Execution 958: a calendar enquiry. Success, with the context, task and fields as above.
- Execution 971: a villa enquiry (regression). Success, context unchanged.
- The website's `npm run verify:intake` runs the draft code (`qa/10d-validate-normalize.draft.snapshot.js`) and the live code side by side.

## Publish / roll back

- Publish: n8n MCP `publish_workflow` with `eLucjNPgTRKS5nBC` and version `bf8b216b…`, or in n8n: Workflow → History → that version → Publish.
- Roll back: re-publish `2ea5fdfe…`.
