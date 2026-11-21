# Workflow 10d: owner alert (DRAFT, tested 21 Nov 2026; NOT YET PUBLISHED)

- Workflow: **10d - NOYA Website Enquiry Intake** (`eLucjNPgTRKS5nBC`).
- Draft version with the alert: `a6fc1824-e978-4c4c-b30e-75401ea70715`.
- Live (active) version, unchanged until the CEO approves: `8512b736-7de8-483a-8b64-bf9b2ecdf909`. This is also the rollback.

## What it does

Once **Insert Website Enquiry Row** succeeds (the enquiry is saved in HQ), one internal email goes to `noya@noyaconcierge.com`:

- **Build Owner Alert** (Code, `build_owner_alert.js`) writes a plain-text alert with these fields:
  - name;
  - service (the form category in plain words, plus the client's sub-choice);
  - destination/context;
  - dates;
  - phone (a `wa.me` link only for a number in international format, marked "WhatsApp use not confirmed");
  - email;
  - message preview (280 characters);
  - source/campaign (UTMs, "Google Ads click id present" when a gclid/gbraid/wbraid is in the landing page, form page, referrer);
  - the HQ reference.

  A record named "… PRODUCTION TEST — DO NOT ACTION" gets a `[TEST]` subject prefix.
- **Send Owner Alert** (Gmail, credential "NOYA Gmail"): sender name "NOYA HQ", to noya@ only, no n8n attribution.
- Both nodes continue on error, so a failed alert never blocks the intake or the CRM branch.
- It runs after **Respond Success**, so the website gets its answer first. It runs before the contact/opportunity/task branch.
- **The client receives nothing from this workflow: no email and no WhatsApp.**
- A duplicate submission never reaches the insert, so it sends no second alert.
- Workflow 13 (Gmail sync) reads only tracked threads and replies from contacted senders, so the alert never becomes a CRM interaction.

`update_ops.json` holds the exact `update_workflow` operations that produced the draft.

## Why email, not WhatsApp

n8n holds no WhatsApp Business (Meta Cloud API) or Twilio credential. A WhatsApp alert to the owner, and logging direct WhatsApp chats into HQ, both need the WhatsApp Business Platform first. That is a CEO decision: spend, and which number. The alert's text is ready to send as a WhatsApp template once that exists.

## Tested (21 Nov 2026, manual run of the draft, execution 4888)

One synthetic travel enquiry: NOYA-HDPMJ9, "NOYA WEBSITE PRODUCTION TEST — DO NOT ACTION", `qa+journey-20261121@example.com`, a fictional Ofcom drama number, utm google/cpc/qa-journey-test, term "private concierge cairo", and a gclid in the landing page.

- website_enquiries: ROUTED, with `utm_term` stored.
- marketing_attribution: source, medium, campaign and term stored; ESTIMATED; gclid kept in the landing page.
- opportunity PRIVATE_CONCIERGE_ENQUIRY, contact, task "New website enquiry — PRIVATE_CONCIERGE_ENQUIRY (NOYA-HDPMJ9)" and interaction all created.
- Alert delivered to the noya@ inbox, unread, from "NOYA HQ" (Gmail message `1a1fdcc212329eab`), with every field correct.
- Order confirmed: Respond Success, then Build Owner Alert, then Send Owner Alert (0.6 s), then the CRM branch.
- Closed afterwards: task COMPLETED, opportunity ARCHIVED, contact DO_NOT_CONTACT.

## To publish / roll back

- Publish: `publish_workflow` on `eLucjNPgTRKS5nBC` (the current draft).
- Roll back: `publish_workflow` with `versionId = 8512b736-7de8-483a-8b64-bf9b2ecdf909`.
- To redirect the alert, change **Send Owner Alert → To**. One field.
