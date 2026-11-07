# n8n workflows (none yet)

Marketing OS workflows will run on NOYA's existing n8n instance, in a dedicated folder `Marketing OS`. No workflow has been
created. Exported workflow definitions will be committed here, with no credentials (n8n exports credential *names* only).

## Conventions

| Prefix | Kind | Tag | LLM node allowed | Credentials |
|---|---|---|---|---|
| `MKT-R` | Reader | `mkt-reader` | No | Read tokens |
| `MKT-A` | Agent | `mkt-agent` | Yes | Read tokens + Claude |
| `MKT-M` | Monitor | `mkt-monitor` | No | Read tokens |
| `MKT-X` | Executor | `mkt-executor` | **Never** | Write tokens (from Phase 6/7/8 only) |

## Executor contract (every `MKT-X` workflow)

1. Trigger: a queue poll (every 1–5 minutes) or a database webhook on `queued`.
2. Check env: `MKT_ENV`, `MKT_EXTERNAL_WRITES_ENABLED` (and `MKT_SPEND_ENABLED` for ads). If any of them denies, run dry.
3. `api.executor_claim(executor_code, request_id)`. On `ok:false`, stop; the refusal is already audited.
4. Make exactly **one** platform call, using the claimed payload unchanged, with the idempotency key.
5. Write `gov.external_call_log` (redacted).
6. `api.executor_report(...)` with success or failure, `dry_run` and the external id.
7. Never retry a write whose outcome is unknown without first reading the platform for the idempotency key or external id.
8. On any error, report to the existing workflow 00 error pattern. Three failures within an hour trip `executor_failures`.

Unpublishing every workflow tagged `mkt-executor` is kill-switch layer L2.
