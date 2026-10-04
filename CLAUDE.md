# NOYA HQ (NOYA-AI-OS): rules for every session

This repo is NOYA Concierge's operating system:
- the HQ database: Supabase project `gagbhykzmtstekpqujyl` (CRM, opportunities, tasks, the intelligence radar, approvals);
- the n8n workflows (`n8n/`, running on noyaprivate.app.n8n.cloud);
- the HQ app (`hq/`);
- the operating docs (`docs/`, with daily and weekly briefs in `docs/briefs/`).

The website lives in the `noya-website` repo; follow its `CLAUDE.md` there.

## Approvals and outreach

- **Prepare freely.** Drafting, research, CRM entry and preparing work need no approval.
- **Ask first.** These need the CEO's approval unless he has authorised the workflow in writing:
  - sending external emails or messages;
  - spending money;
  - entering agreements;
  - publishing to the website;
  - approving calendar events.
- **Emails are drafts** in noya@ until approved.
- **Approvals are recorded** in `approval_audit`. Private Calendar approvals go through `hq_calendar_approve`, behind the `intelligence_calendar_gate` trigger.
- **Information is labelled** VERIFIED, INFERRED or UNVERIFIED. Contact details are never invented. Check the CRM for an existing contact, earlier contact and status before creating a lead or drafting outreach.

## Database work (Supabase connector)

- Never run `DROP` through the connector.
- If the connector holds a write for a confirmation it cannot show:
  - stop;
  - put the SQL in a migration file whose header says "NOT YET APPLIED", for a paste in the SQL editor;
  - never route around the hold with other tools.
- Migrations live in `supabase/migrations/`. Each header says what it does, and whether and how it was applied.
- **Test records** are named "NOYA WEBSITE PRODUCTION TEST — DO NOT ACTION". Close them afterwards:
  - task COMPLETED;
  - opportunity ARCHIVED;
  - contact DO_NOT_CONTACT.

## Private Calendar and its images

**Dates.** An event enters the radar as CANDIDATE or VERIFIED, with:
- the organiser's own source (official site or ticketing);
- the date it was checked.

Nothing with uncertain or moving dates is approved. Approval is the CEO's alone; publishing happens in the website's Studio.

**Images: hard rule** (CEO, 4 Oct 2026; full standard in `noya-website/docs/IMAGE_STANDARD.md`):
- One event, one visual idea. Fallback order: **exact event → exact venue/destination → exact category → text-led layout**. Never a generic luxury image.
- When proposing an event, record its visual intent (what a photograph must show) next to the copy intent.
- Official event websites verify facts only. Never use organiser or press imagery without written permission.
- Always the highest-quality original. Never a screenshot, a WhatsApp or social-media copy, a thumbnail or a low-resolution export when a master exists.
- Be strictest on high-intent pages: the Luxor eclipse, the Monaco Yacht Show, Snow Polo St. Moritz, LGCT Cairo.

## Secrets and git

- Never ask for, paste or commit secrets. Credentials live in n8n, Vercel or Supabase.
- Work on the session branch. No pull request unless asked.
