# Supabase

Target: the separate **NOYA Marketing OS** project (organisation "Noya Concierge", region eu-west-2). **Never** the NOYA HQ project.

| Path | What |
|---|---|
| `migrations/20261107100000_foundation.sql` | Schemas `gov` / `ops`, helpers, members, service identities, hash-chained audit log, external call log, configuration, kill switches (all disabled), integration / secrets / permission registries, budget caps |
| `migrations/20261107100100_approval_engine.sql` | Approval requests, immutable versions, hash-bound approvals, execution requests / results, the gate, safety events, notifications, tripwires, agents, agent runs, system health, seed identities |
| `migrations/20261107100200_api_and_lockdown.sql` | `public.mos_*` API, worker roles (`mos_agent`, `mos_executor`, `mos_monitor`, `mos_dispatcher`), kill switch / monitor / D4 pause logic, health checks, console snapshot, forced RLS, grants, pg_cron schedules |
| `functions/mos-alert-dispatcher/` | Resend alert dispatcher (Edge Function), prepared, not deployed |
| `tests/00_supabase_stub.sql` | Local stand-in for Supabase roles and `auth.*`. Local only |
| `tests/10_phase1_test.sql` | Behavioural suite (run by `scripts/test-db.sh`, which adds the race and lint checks) |
| `proposed/` | Phase 0 design. Superseded for the control plane; `0002` still holds the marketing domain designs |

Reference: `docs/database.md`. Run: `PGHOST=… PGPORT=… PGUSER=postgres scripts/test-db.sh`.

Last run: 7 Nov 2026, PostgreSQL 16.15. **28 / 28 pass.**
