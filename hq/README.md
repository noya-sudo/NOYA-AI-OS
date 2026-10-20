# NOYA HQ — CEO Command Centre

A static site for `hq.noyaconcierge.com`. The browser holds only the Supabase **publishable** key and Adam's own login token. All reads and writes go through authenticated Postgres functions, defined in `supabase/migrations/20260926200000_hq_command_centre.sql` and `20260930091000_hq_overview.sql`. See `docs/NOYA_HQ_BUILD.md` for status and architecture.

| Function | Used for |
|---|---|
| `hq_overview()` | The Overview: action queue, scorecard, money, replies, website, system (computed server-side) |
| `hq_dashboard()` | The section views (live CRM) |
| `hq_task_action(task, action, until, assignee, note)` | COMPLETE / SNOOZE / ASSIGN an ordinary task (approval tasks refused) |
| `hq_save_draft(opp, subject, body, note)` | EDIT. The original draft is kept as v1 |
| `hq_approve_draft(opp, version)` | APPROVE & DRAFT. Runs the gates, then asks workflow 12 to create one Gmail draft |
| `hq_hold(opp, review_date, reason)` | HOLD |
| `hq_reject(opp, reason)` | REJECT (a reason is required) |
| `hq_redispatch(outbound_id)` | Retry draft creation if the hand-off to workflow 12 was lost |
| `hq_cached('command')` | Dashboard top row, 15-stage funnel, live opportunities, revenue and reconciliation, scorecards, work orders (`hq_command()`, refreshed every 5 minutes and right after each action below) |
| `hq_cached('health')`, `hq_cached('integrity')` | Admin → System health and the daily integrity check |
| `hq_work_order(director, mission, target, metric, goal, deadline, priority)` / `hq_work_order_action(id, CANCEL\|CLOSE, note)` | CEO work orders to a Director |
| `hq_opportunity_plan(opp, next_action, due, owner, blocker, clear_blocker)` | Owner, next action, date and blocker on a live opportunity |
| `hq_recommendation_action(id, APPROVE\|DECLINE, note)` | Approve or decline an Advisor recommendation (allowlisted changes only; never sends) |
| `hq_revenue_import(rows, apply)` | Historical revenue: dry run by default; each row needs evidence |
| `hq_studio()` | Studio page and the Studio team under Agents: six columns (Needs brief, Drafting, Needs review, Approved, Sent, Superseded), the eight Studio roles, the Brief & Proposal Architect's work, the three levels and the nine create actions |
| `hq_studio_request(kind, company, opportunity, note)` / `hq_studio_request_action(id, CANCEL)` | Ask the Studio for an idea, one-page concept, brief, proposal, itinerary or a retreat / wedding / brand campaign / media concept. Queued for the Studio; nothing is sent |
| `hq_cached('command')` → `destination_egypt` | Dashboard Destination Egypt panel: mission funnel, top opportunities, research by programme (`destination_egypt_mission()`) |
| `hq_outreach_desk()` → `top5`, `linkedin`, `meeting_assist`, `studio_ready` | The Dashboard's five morning lists and Outreach → Today's five / LinkedIn (same read, no extra call) |
| `hq_linkedin_action(id, action, text, date)` | LinkedIn agent: EDIT, EDIT_NOTE, EDIT_FOLLOWUP, CONNECTION_SENT, CONNECTED, SENT, HOLD, RELEASE, CLOSE. Records what Adam did; never sends |
| `hq_linkedin_reply(id, text, class)` | Log a LinkedIn reply Adam pasted: classified (or his class), logged, follow-ups cancelled, response suggested, Meeting Assist on a meeting intent |
| `hq_meeting_confirm(task, start, minutes, where)` | Confirm meeting: the meeting record, briefing, relationship note and opportunity update; the calendar entry is added without guests |
| `hq_import_linkedin_messages(rows)` | LinkedIn data download: up to 1,000 parsed messages a call (400 from HQ); a message already imported is never added twice |
| `hq_linkedin_archive(step, stats)` | LinkedIn data download: `start` before the upload, then `self`, `people`, `history`, `match`, `states` (one short call each); no step reads the report |
| `hq_linkedin_history(connection)` | A person's last twelve LinkedIn messages with Adam, newest first, read-only (their drawer) |

Each function:
- checks that the signed-in user is in `hq_admins`, matching both the user id and the email;
- writes an `approval_audit` row.

There is **no send action**. Adam sends the approved draft from Gmail, and workflow 13 logs it.

## Build

```
cd hq
npm install
npm run build    # outputs dist/ (self-contained, no CDN)
npm test         # build + security scan of dist/ + headless browser checks
```

`npm test` runs `tests/ui.mjs`, `tests/ui_v3.mjs` and `tests/ui_command.mjs` (Command Centre: top row, funnel, work orders, scorecards, revenue, System health; screenshots in `tests/out/command/`). Browser checks run only if `tests/fixtures/snapshot.json` exists. That file is a live `hq_dashboard()` response and is git-ignored, so it is never committed.

## Deploy (Cloudflare Workers Static Assets)

The repo root has a `wrangler.jsonc` for the existing Worker `noya-hq`. It is assets-only: no Worker script, no bindings and no secrets. It serves the committed `hq/dist` with single-page-application fallback.

Cloudflare Git deployment settings:
- Root directory `/`.
- No build command, because `hq/dist` is committed.
- Deploy command `npx wrangler deploy`.

After changing `hq/src`, run `npm run build` in `hq/` and commit `hq/dist`. `hq/dist/_headers` applies the security headers.

## Access

- Adam signs in with email and password. The first sign-in forces him to set his own password.
- To add another admin, create their Supabase Auth user, then insert their `user_id` and email into `public.hq_admins` (a service-role step).
