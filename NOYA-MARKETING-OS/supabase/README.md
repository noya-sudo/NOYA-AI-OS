# Supabase: proposed schema

**Proposal only.** These files are not migrations and have not been applied to any Supabase project. They target a **new,
separate** project for Marketing OS (decision D2). They must never be run against the NOYA HQ project.

| File | Contents |
|---|---|
| `proposed/0001_governance.sql` | `gov` and `api`: members, service identities, audit log (hash chain), external call log, system controls (kill switch), tripwires, channel accounts, budget caps, secrets registry, action types, policies, action requests, approvals, `gov.can_execute()`, and the console / executor / monitor API |
| `proposed/0002_marketing_domains.sql` | `brand`, `intel`, `content`, `paid`, `analytics`, `leads`, `ops` |
| `proposed/tests/00_supabase_stub.sql` | Local stand-in for Supabase roles and `auth.*`. Local use only |
| `proposed/tests/10_governance_test.sql` | 13 behavioural checks of the safety properties |

## Design notes

- **No direct table access from the browser.** RLS is enabled on every table, and privileges are revoked from `anon` and
  `authenticated`. The console calls `api.*` functions only (security definer, pinned `search_path`), the same pattern as HQ.
- **Refusals return, they do not raise.** API functions return `{ok:false, reason}` and commit a `blocked` audit row. Raising
  would roll the audit row back.
- **No extensions required.** `sha256()` and `gen_random_uuid()` are built into Postgres 13+.
- **Money in minor units** (`bigint`) with an ISO currency code.
- **Status and enum values** are `text` with `check` constraints, so they are easy to evolve in a migration.
- **Read API per phase.** Console read functions (`api.review_queue()`, `api.calendar()`, …) are added in the phase that needs
  them, not speculatively.

## Run the checks locally

Needs Postgres 13+ (`psql` and a server you can create a database on):

```bash
createdb mkt_check
psql -d mkt_check -v ON_ERROR_STOP=1 -f supabase/proposed/tests/00_supabase_stub.sql
psql -d mkt_check -v ON_ERROR_STOP=1 -f supabase/proposed/0001_governance.sql
psql -d mkt_check -v ON_ERROR_STOP=1 -f supabase/proposed/0002_marketing_domains.sql
psql -d mkt_check -v ON_ERROR_STOP=1 -f supabase/proposed/tests/10_governance_test.sql   # prints ALL GOVERNANCE CHECKS PASSED
dropdb mkt_check
```

Last run: 7 Nov 2026, PostgreSQL 16.15, all 13 checks passed (12 ok and 9 blocked audit rows written, chain intact).

## What the tests prove

1. An editor can submit but not approve.
2. An approval on a payload the approver did not see is refused.
3. The payload cannot change after submission.
4. An approved request still cannot run without confirmation, or while halted. A refused confirmation is not left recorded.
5. Arming needs the owner and the typed phrase. Halting blocks queued work.
6. Re-arming does not resume blocked work.
7. The happy path works end to end. An unknown executor is refused. Tokens in results are redacted.
8. Money-moving actions cannot be made automatic, and the refused change leaves the policy untouched. Spend cannot be armed
   without caps.
9. A monitor tripwire halts.
10. The audit log refuses update and delete; the chain verifies.
11. The browser role cannot read governance tables.
12. An HQ hand-off is refused unless every qualification gate is true.
13. The chain verifies in any time zone, and a superuser edit with triggers disabled is detected at the exact row.

## Promotion path (Phase 1)

1. Adam creates the project.
2. Copy `0001` into `supabase/migrations/<timestamp>_governance.sql`.
3. Remove the "PROPOSAL ONLY" header.
4. Run the tests against a Supabase branch in CI.
5. Apply.

`0002` is promoted table group by table group in the phase that uses it.
