# Marketing OS console

The internal operating desk. Static HTML, CSS and JS: no framework, no CDN, no secrets. It signs in with Supabase Auth and calls
only `public.mos_*` functions.

| Shows | |
|---|---|
| System status | phase, external execution, open critical alerts, pending approvals, audit chain |
| Kill switches | Stop everything / Disable only; enabling is deliberately not in the console in Phase 1 |
| Pending approvals | read-only |
| Recent audit events | |
| Connected services | |
| Database health | run checks |
| Agents and runs | |
| Security alerts | acknowledge |
| Alert outbox | queue a [TEST] alert |
| Environment and configuration | secrets by name only |

There are no publishing or ad controls.

```bash
node console/build.mjs                       # demo mode: real snapshot from the local test DB, no network
MOS_SUPABASE_URL=https://<ref>.supabase.co MOS_SUPABASE_PUBLISHABLE_KEY=sb_publishable_... node console/build.mjs
node console/tests/ui.mjs                    # headless checks, desktop + mobile; screenshots in console/tests/out/
```

The build writes `dist/_headers` with a strict CSP (scripts, styles and fonts from self only; connect only to the project URL),
and refuses to build with a secret key. Hosting: Cloudflare static assets, same pattern as HQ, once the project and repository
exist.
