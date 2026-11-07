# Environment variables and secrets

> **Phase 1 implementation note (7 Nov 2026).** Variable names changed from `MKT_*` to `MOS_*`; the authoritative template is `.env.example`. Workers use per-role database JWTs (`MOS_AGENT_JWT`, `MOS_EXECUTOR_JWT`, `MOS_MONITOR_JWT`), not the service key. Status of each integration: `docs/integrations.md`.


Status: proposal. **None of the platform credentials below exist yet.** Nothing in this repository is connected to any platform.
A variable listed here is a plan, not a connection.

## 1. Rules

1. **Secrets are never committed.** `.env`, `.env.*` (except `.env.example`) and `*.local` are git-ignored. Run
   `node scripts/check-secrets.mjs` before every commit; CI runs it too (Phase 1).
2. **Secrets live in exactly one managed place.** n8n credentials (default), Supabase Edge Function secrets or Vault, or GitHub
   Actions secrets for migrations. The static console has **no** secrets, only the publishable key.
3. **Read and write are separate credentials.** Readers and agents get `*_READ_*` only. Write tokens exist only in executor
   workflows, and only from the phase that needs them.
4. **No write credential exists during development.** Not "switched off": not created.
5. **Every secret is registered** in `gov.secrets_registry`: its name, where it is stored, read or write, scopes, owner and
   rotation. The value is never registered.
6. **Least scope.** Request only the scopes the phase needs. Record granted scopes on `gov.channel_accounts.granted_scopes`. Scope
   drift trips `token_scope_changed`.
7. **Rotation.** Write tokens every 90 days, read tokens every 180 days, immediately on suspicion.
8. **No personal-account automation.** No session cookies, no unofficial APIs, no tokens for Adam's personal LinkedIn.

## 2. Safety flags (not secret, but critical)

Executors read these **in addition to** the database controls. All three must allow a write. The defaults deny.

| Variable | Default | Allowed values | Where | Effect |
|---|---|---|---|---|
| `MKT_ENV` | `development` | `development`, `staging`, `production` | n8n variables, console build | Executors refuse real writes unless `production` |
| `MKT_EXTERNAL_WRITES_ENABLED` | `false` | `true` / `false` | n8n variables | `false`: executors run in dry-run mode and record `dry_run = true` |
| `MKT_SPEND_ENABLED` | `false` | `true` / `false` | n8n variables | `false`: the ads executor refuses every `spend` request, even risk-reducing (those go through Ads Manager by hand) |

A real external write needs all of:
- `MKT_ENV=production`;
- `MKT_EXTERNAL_WRITES_ENABLED=true`;
- `MKT_SPEND_ENABLED=true`, for spend only;
- the database control armed;
- an approved and confirmed request that passes `gov.can_execute()`.

## 3. Variables by component

Legend: **S** = secret, **P** = public / non-secret. "Phase" = the earliest phase that needs it.

### Supabase (Marketing OS project, not HQ)

| Variable | S/P | Phase | Stored in | Used by | Notes |
|---|---|---|---|---|---|
| `MKT_SUPABASE_URL` | P | 1 | console build, n8n | all | New project. Not HQ's URL |
| `MKT_SUPABASE_PUBLISHABLE_KEY` | P | 1 | console build | console | Browser-safe; RLS + revoked tables + `api.*` only |
| `MKT_SUPABASE_SERVICE_ROLE_KEY` | S | 1 | n8n credential | readers, agents, executors, monitors | Never in the browser, never in the repo |
| `MKT_SUPABASE_DB_URL` | S | 1 | GitHub Actions secret / local only | migrations | Connection string with password |
| `MKT_SUPABASE_PROJECT_REF` | P | 1 | CI | migrations | |

### AI and research (existing NOYA accounts, reused)

| Variable | S/P | Phase | Stored in | Notes |
|---|---|---|---|---|
| `ANTHROPIC_API_KEY` | S | 2 | n8n credential | Claude for agents. A separate key from HQ's is preferred, for separate spend tracking (D7) |
| `MKT_AI_MONTHLY_BUDGET_USD` | P | 2 | n8n variables / `ops.agents` caps | Hard monthly ceiling across agents |
| `FIRECRAWL_API_KEY` | S | 3 | n8n credential | Existing account; respect the HQ budget |
| `SERPER_API_KEY` | S | 3 | n8n credential | Existing account; volume frozen per HQ standing decision until the plan is confirmed |

### Instagram (via Meta)

| Variable | S/P | Phase | Stored in | Scopes (indicative; confirm at setup) |
|---|---|---|---|---|
| `META_APP_ID` | P | 5 | n8n variables | NOYA-owned Meta app, in NOYA's Business portfolio |
| `META_APP_SECRET` | S | 5 | n8n credential | |
| `META_BUSINESS_ID` | P | 5 | n8n variables | |
| `IG_BUSINESS_ACCOUNT_ID` | P | 5 | n8n variables, `gov.channel_accounts.external_id` | |
| `FB_PAGE_ID` | P | 5 | n8n variables | Linked Facebook Page, if the Facebook Login route is used |
| `IG_READ_TOKEN` | S | 5 | n8n credential (readers) | insights, comments, messages: read only |
| `IG_WRITE_TOKEN` | S | **7** | n8n credential (executor only) | content publish, comment management, messaging |

### LinkedIn (Company Page only)

| Variable | S/P | Phase | Stored in | Notes |
|---|---|---|---|---|
| `LINKEDIN_CLIENT_ID` | P | 5 | n8n variables | App owned by the NOYA Company Page |
| `LINKEDIN_CLIENT_SECRET` | S | 5 | n8n credential | |
| `LINKEDIN_ORGANIZATION_URN` | P | 5 | n8n variables | `urn:li:organization:…` |
| `LINKEDIN_READ_TOKEN` | S | 5 | n8n credential | Page analytics. Needs LinkedIn's Community Management API approval, which is not guaranteed (see HQ `docs/LINKEDIN_OFFICIAL_ACCESS.md`) |
| `LINKEDIN_WRITE_TOKEN` | S | **7** | n8n credential (executor only) | Page posting. If LinkedIn does not grant access, Page posts stay manual |
| `LINKEDIN_ADS_ACCOUNT_ID` | P | 8 | n8n variables | Only if LinkedIn ads are approved |

Adam's **personal** LinkedIn is never automated. Marketing OS drafts; Adam posts.

### Meta Ads

| Variable | S/P | Phase | Stored in | Notes |
|---|---|---|---|---|
| `META_AD_ACCOUNT_ID` | P | 5 | n8n variables | `act_…` |
| `META_ADS_READ_TOKEN` | S | 5 | n8n credential | System user with read-only ads access |
| `META_ADS_WRITE_TOKEN` | S | **8** | n8n credential (ads executor only) | A **separate** system user with ads management. Created only in Phase 8 |
| `META_ADS_CURRENCY` | P | 5 | n8n variables | For minor-unit conversion |

### Google (optional, later)

| Variable | S/P | Phase | Stored in | Notes |
|---|---|---|---|---|
| `GA4_PROPERTY_ID` | P | 5 | n8n variables | Website analytics |
| `GA4_SERVICE_ACCOUNT_JSON` | S | 5 | n8n credential | Viewer role on the GA4 property only |
| `SEARCH_CONSOLE_SITE_URL` | P | 5 | n8n variables | |
| `GOOGLE_ADS_*` | S | 8+ | n8n credential | Only if search ads are approved |

### NOYA HQ hand-off (Phase 6; needs a separately approved HQ change)

| Variable | S/P | Phase | Stored in | Notes |
|---|---|---|---|---|
| `HQ_HANDOFF_URL` | P | 6 | n8n variables | HQ intake endpoint. Does not exist yet |
| `HQ_HANDOFF_SIGNING_SECRET` | S | 6 | n8n credential (courier only) and the HQ side | HMAC-SHA256 over the body. Shared only with the HQ intake. **Not** an HQ service key |

### Alerts (decision D6)

| Variable | S/P | Phase | Stored in | Notes |
|---|---|---|---|---|
| `MKT_ALERT_EMAIL` | P | 1 | n8n variables | Fixed recipient (Adam) for kill-switch and tripwire alerts |
| `RESEND_API_KEY` | S | 1 | n8n credential | Only if D6 = email alerts; existing account |

### Console build

| Variable | S/P | Notes |
|---|---|---|
| `MKT_SUPABASE_URL`, `MKT_SUPABASE_PUBLISHABLE_KEY`, `MKT_ENV` | P | Baked into the static build. **Nothing else.** The build fails if a secret-looking value appears (scan, as in HQ `tests/security-scan.mjs`) |

## 4. Services already connected to this Claude session (not to Marketing OS)

Adam's Claude workspace has connectors for Metricool, Windsor.ai, AdWhispr, Canva, Figma, Gmail, Drive, Supabase and n8n. Some of
them **can publish or spend** (for example, Metricool scheduling, Windsor write actions, AdWhispr campaign launch).

Rules:
- Marketing OS does **not** route any external write through these connectors. They bypass the approval pipeline and its audit trail.
- Claude sessions working on Marketing OS do not call write or spend tools on these connectors.
- Read-only use for research (for example, looking at competitor ads) is allowed and recorded as research.
- If one of them is ever adopted as a channel, it goes through the paid-software gate and becomes an executor behind
  `gov.can_execute()`.

## 5. Local development

```bash
cp .env.example .env.local     # git-ignored; fill only what you need locally
node scripts/check-secrets.mjs # must print "No secrets found"
```

Local development uses a local Postgres with `supabase/proposed/tests/00_supabase_stub.sql`. No platform credential is ever
needed locally.
