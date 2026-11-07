# Database

Phase 1 schema for the **NOYA Marketing OS** Supabase project. It is separate from NOYA HQ and is never applied to the HQ project.
Source of truth: `supabase/migrations/` (three files, applied in order). `supabase/proposed/` holds the Phase 0 design; it is
superseded and kept for history.

## Status (7 Nov 2026)

| Item | State |
|---|---|
| Migrations | Written. They apply cleanly on PostgreSQL 16 together with a Supabase stub (`supabase/tests/00_supabase_stub.sql`) |
| Tests | 28 / 28 pass (`scripts/test-db.sh`): 26 behavioural checks, a 10-way concurrency race, and an advisor-equivalent lint |
| Supabase project | **Not created yet.** Creation was blocked by this session's permission classifier (see the completion report). Once it exists, the same three migrations go on through the Supabase migration tool, and Supabase's security and performance advisors run |

## Layout

| Schema | Exposed to the Data API? | Holds |
|---|---|---|
| `gov` | No | Governance: identities, audit, configuration, registries, kill switches, approvals, executions, safety events, notifications, tripwires, budget caps |
| `ops` | No | Operations: agents, agent runs, system health |
| `public` | Yes (functions only) | **No tables.** Only `mos_*` SECURITY DEFINER functions with a pinned `search_path` |

## Tables

| Table | Purpose | Write rules |
|---|---|---|
| `gov.members` | Humans and roles. Adam is the sole owner (unique index: one active owner) | Service setup only |
| `gov.service_identities` | Agents, executors, monitors, dispatchers. Agents may only *request*; only executors *execute* (check constraints) | Migration |
| `gov.audit_log` | Every decision, execution and refusal; hash-chained | Append-only (triggers refuse update, delete and truncate). `seq` is assigned after the chain lock is taken |
| `gov.external_call_log` | Every platform HTTP call (metadata, redacted) | Append-only; rejects credentials in query strings |
| `gov.configuration` | Non-secret settings | Keys that look like secrets are rejected by a check constraint |
| `gov.kill_switches` | 8 switches, all `disabled` at install | Enabling is refused unless done by the owner function (trigger plus a transaction-local flag) |
| `gov.integration_registry` | Every connector: current, prepared and future | `read_only` / `read_write` need a verification time and evidence (check constraint) |
| `gov.secrets_registry` | Where each credential lives and what it can do | Has no column that could hold a value |
| `gov.permission_registry` | Every external action: mode, approver role, approval TTL, money / risk flags, D4 auto-pause flag | There is no automatic mode; `auto_safety_allowed` is only possible on `*.pause` (check constraint) |
| `gov.budget_caps` | Daily / monthly caps; `platform_native_cap_confirmed` | Needed before any paid switch can be enabled |
| `gov.approval_requests` | The request: action, target, status, current version | Status machine trigger; identity fields frozen; never deleted |
| `gov.approval_versions` | Every content version with its payload SHA-256 (computed by trigger) | Immutable |
| `gov.approvals` | Decisions bound to request, version, hash, action, platform, target, actor, time, expiry and a single-use nonce | Only revocation or invalidation can be written later, once |
| `gov.execution_requests` | One queued execution per approval (`approval_id` unique; idempotency key = nonce) | Frozen except status; status machine |
| `gov.execution_results` | The outcome of an execution (one per execution) | Immutable; results redacted |
| `gov.safety_events` | Kill switch changes, bypass attempts, unauthorised attempts, automatic pauses, breaches | Immutable except acknowledgement |
| `gov.notifications` | Alert outbox for the Resend dispatcher. Recipient is always `owner`, resolved at send time | `[TEST]` subject enforced for tests |
| `gov.tripwires` | Conditions a monitor reports; each can only disable a switch (and for spend, raise D4 pauses) | Migration |
| `ops.agents`, `ops.agent_runs` | Agent registry (all disabled) and run log with cost | Via `mos_agent_run_*` |
| `ops.system_health` | Results of health checks, kept 30 days | Via health check |

## Status machines

```
approval_requests:  draft → submitted → approved → executing → executed
                              ↘ rejected   ↘ revoked / expired          ↘ failed
                    (edit from submitted/approved/rejected/revoked/expired → draft, version + 1, approvals invalidated)

execution_requests: queued → claimed → succeeded | failed
                    queued → refused | cancelled   (kill switch, revoke, edit, expiry)
```

`executed`, `failed` and `cancelled` are terminal. The guard triggers reject anything else, including a direct SQL update.

## The gate (`gov.gate`)

Execution is allowed only when **all** of these hold. The gate is evaluated when the owner queues an execution, and again inside
the executor's claim transaction, with the row locked (`FOR UPDATE SKIP LOCKED`):

1. The action is registered; otherwise refused (fail-closed).
2. There is a valid approval for the **current** version:
   - decision is approve;
   - same version and same payload hash;
   - the hash still equals sha256(payload);
   - same action, platform and target;
   - not revoked, not invalidated, not expired.
3. A human approver's role meets the permission's minimum. A policy approval is allowed only for D4 pauses.
4. The permission is not `blocked`.
5. The request is `approved` / `executing`.
6. For anything not risk-reducing, kill switches `global`, `integration.external_writes` and the action's own switch are all enabled.
7. The integration is `read_write`, with verification evidence.
8. For money-moving actions, an active daily cap exists with `platform_native_cap_confirmed`, and the change is within it.

Then at claim:
- the executor identity must be active, of kind executor, and list the action;
- the execution must be `queued`;
- the gate's approval must be this execution's approval;
- the payload hash must match.

## API (public.mos_*)

| Function | Caller (Postgres role) | Purpose |
|---|---|---|
| `mos_console_snapshot()` | authenticated (member) | Everything the console shows |
| `mos_health_check()` | authenticated (member) | Run and return health checks |
| `mos_create_draft`, `mos_edit_draft`, `mos_submit` | authenticated (editor+) | Drafting; an edit invalidates approvals |
| `mos_decide`, `mos_revoke_approval`, `mos_request_execution` | authenticated (owner) | Approve or reject the exact version and hash; revoke; queue one execution |
| `mos_kill_switch_disable`, `mos_kill_switch_disable_all` | authenticated (approver+) | Stop |
| `mos_kill_switch_enable` | authenticated (owner) | Enable, with the typed phrase `ENABLE <key>` and a reason. Paid switches need caps. `organic.linkedin_adam` is never enabled |
| `mos_queue_test_alert`, `mos_acknowledge_safety_event` | authenticated (owner) | Alerts |
| `mos_agent_propose`, `mos_agent_run_start`, `mos_agent_run_finish` | `mos_agent` | Propose drafts within `may_request`; log runs |
| `mos_executor_claim`, `mos_executor_report` | `mos_executor` | Claim one approved execution; report its result |
| `mos_monitor_trip`, `mos_monitor_safety_pause` | `mos_monitor` | Disable switches; raise D4 pauses (pause only) |
| `mos_dispatcher_claim`, `mos_dispatcher_result` | `mos_dispatcher` | Alert outbox |

Every function returns `{ok, reason, ...}`. A refusal is returned rather than raised, so its audit row (and its safety event,
for bypass or unauthorised attempts) is **committed**.

## Roles and privileges

- `anon`: nothing.
- `authenticated`: only the human `mos_*` functions, each of which checks `gov.members`.
- `service_role`: **nothing**. Workers never use the service key.
- `mos_agent`, `mos_executor`, `mos_monitor` and `mos_dispatcher` are `NOLOGIN NOINHERIT` roles granted to `authenticator`.
  Workers present a JWT whose `role` claim names one of them, or (for the Edge Function) connect and `SET LOCAL ROLE`. Each role
  can execute only its own functions and has no table privileges.
- Every table has RLS enabled and **forced**, with a single policy for the table owner, which is what the SECURITY DEFINER
  functions run as. No other role holds privileges on any table.

## Schedules (pg_cron, created by migration 3 on Supabase)

| Job | Schedule | Does |
|---|---|---|
| `mos-expire-approvals` | every 15 minutes | Marks approvals whose time has passed as expired; cancels queued executions |
| `mos-health-checks` | hourly at :07 | Audit chain, RLS coverage, no public tables, switches, integrations, alert backlog. A broken chain trips `audit_chain_broken` |

## Running the tests

```bash
PGHOST=<socket-or-host> PGPORT=<port> PGUSER=postgres scripts/test-db.sh
```

The suite creates a throwaway database and drops it afterwards. Never point it at a Supabase project.
