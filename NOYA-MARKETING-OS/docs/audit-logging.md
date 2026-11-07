# Audit logging

> **Phase 1 implementation note (7 Nov 2026).** Implemented in `supabase/migrations/20261107100000_foundation.sql`. Each row now also records tool, target platform, payload hash, approval id and decision. `seq` is assigned after the chain lock so the chain stays linear under concurrent writers (found by the race test).

Status: proposal. Enforced by `gov.audit_log`, `gov.audit()`, `gov.verify_audit_chain()` and `gov.external_call_log`.

## 1. What must be answerable, at any time

- Who approved this post, and did they see exactly what was published?
- Why did this campaign's budget change, and who allowed it?
- Who armed publishing, when and why?
- What did agent X do last Tuesday, and what did it cost?
- What was attempted and **refused**?
- Has anyone altered the record?

## 2. Two logs

| Log | Holds | Volume |
|---|---|---|
| `gov.audit_log` | Decisions and state changes: submit, approve, reject, confirm, claim, succeed, fail, halt, arm, policy change, member change, connection verified or revoked, hand-off, agent run start and end. **Including blocked attempts.** | Low (hundreds a day) |
| `gov.external_call_log` | Every HTTP call to a platform or model: platform, read / write, method, endpoint path, status, platform object id, duration, cost, dry-run flag, redacted summaries | Higher |

Agent cost and activity also land in `ops.agent_runs`. Business history (versions, approvals, publications) stays in its own
tables. The audit log is the cross-cutting index of who did what.

## 3. Audit row

| Field | Example |
|---|---|
| `seq`, `id` | 1042, uuid |
| `occurred_at` | set by the database (`clock_timestamp()`), never by the caller |
| `actor_type` / `actor_id` | `human` / `adam@…`, `agent` / `agent.content_strategist`, `executor` / `executor.publisher`, `monitor` / `monitor.spend` |
| `action` | `action_request.approve`, `kill_switch.halt`, `policy.set` |
| `entity_type` / `entity_id` | `gov.action_requests` / uuid |
| `result` | `ok`, `blocked`, `error`, `info` |
| `reason` | the human note, or the refusal reason |
| `correlation_id` | ties one request's whole lifecycle, or one agent run, together |
| `before_state` / `after_state` / `detail` | jsonb, redacted |
| `prev_hash` / `row_hash` | hash chain |

## 4. Guarantees

| Guarantee | How |
|---|---|
| **Append-only** | Triggers refuse UPDATE, DELETE and TRUNCATE for every role. Privileges are also revoked from `service_role` |
| **Tamper-evident** | Each row's `row_hash = sha256(prev_hash ∣ row content)`, with timestamps rendered in UTC. `gov.verify_audit_chain()` returns the first broken row. A nightly monitor runs it; a break trips `audit_chain_broken` and halts `global` |
| **No forks** | Writers take a transaction-scoped advisory lock, so the chain is strictly linear |
| **Blocked attempts are kept** | API functions return `{ok:false, reason}` and **commit** the audit row instead of raising. A raised error would roll the audit row back with everything else |
| **No secrets** | `gov.redact()` replaces the value of any key that looks like a token, secret, password, authorization, API key, cookie, session or signature, recursively, before insert. `external_call_log` also refuses endpoints carrying credentials in a query string |
| **No caller-supplied truth** | Time, hashes and actor identity come from the database and the JWT, not from parameters |

The tests (`supabase/proposed/tests/10_governance_test.sql`) check:
- update and delete are refused;
- the chain verifies, in any session time zone;
- a superuser edit made with triggers disabled is detected at the exact row;
- every refusal leaves a `blocked` row;
- tokens in results are redacted.

## 5. Limits, stated honestly

- A Postgres superuser (the Supabase project owner) can still disable triggers. The hash chain makes that **detectable**, but not
  impossible. For stronger assurance, the weekly export below gives an off-database copy to compare against.
- An HTTP call already in flight when a halt lands will still complete. It is logged.

## 6. Retention and export

| Data | Retention |
|---|---|
| `gov.audit_log` | Indefinite (small) |
| `gov.external_call_log` | 18 months, then summarised monthly |
| `ops.agent_runs` | 18 months |
| Lead personal data | 12 months by default (`leads.inbound.retention_until`), then minimised. The audit row keeps ids, not personal details |

**Weekly export (Phase 1):**
1. A scheduled n8n workflow writes the week's audit rows as CSV to a private Google Drive folder ("Marketing OS / Audit").
2. It also writes the last `row_hash`.
3. Comparing the Drive copy with the database proves the history was not rewritten.
4. Free, using existing tools.

## 7. Where Adam sees it

- **Console → Audit**: filter by action, actor, result or date. Every review card links to its own history.
- **Weekly marketing review**: approvals given, refusals, halts, spend changes and agent cost.
- **CEO daily (System activity)**: one line per material event, for example "2 posts published (approved by Adam), 1 hand-off
  delivered to HQ, 0 blocked attempts".
