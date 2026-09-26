# NOYA HQ — CEO Command Centre

A static site for `hq.noyaconcierge.com`. The browser holds only the Supabase **publishable** key and Adam's own login token. All reads and writes go through six authenticated Postgres functions, defined in `supabase/migrations/20260926200000_hq_command_centre.sql`:

| Function | Used for |
|---|---|
| `hq_dashboard()` | Everything the views show (live CRM) |
| `hq_save_draft(opp, subject, body, note)` | EDIT. The original draft is kept as v1 |
| `hq_approve_draft(opp, version)` | APPROVE & DRAFT. Runs the gates, then asks workflow 12 to create one Gmail draft |
| `hq_hold(opp, review_date, reason)` | HOLD |
| `hq_reject(opp, reason)` | REJECT (a reason is required) |
| `hq_redispatch(outbound_id)` | Retry draft creation if the hand-off to workflow 12 was lost |

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

`npm test` runs its browser checks only if `tests/fixtures/snapshot.json` exists. That file is a live `hq_dashboard()` response and is git-ignored, so it is never committed.

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
