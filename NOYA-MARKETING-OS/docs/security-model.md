# Security model

How Marketing OS prevents unapproved publishing, unapproved spend and silent changes, and how it proves that it did.
Implementation: `supabase/migrations/`. Evidence: `scripts/test-all.sh`.

## 1. Threats and the controls against them

| Threat | Control | Test |
|---|---|---|
| An agent (LLM) publishes or spends on its own | Agents have **no** privilege on approval, execution or enable functions (role `mos_agent`). An agent identity passed into the executor path is refused and flagged as a bypass attempt. `service_identities` forbids agents from executing (check constraint) | 11 |
| Prompt injection in a DM or web page steers an agent | Agents can only create drafts within their `may_request` list. Every draft needs Adam's approval of the exact hash | 11, 12 |
| Content is changed after approval | Versions are immutable. An edit creates version n+1 and invalidates every approval. The gate requires an approval for the current version and hash | 08, 14 |
| An approval is reused (replay) | `execution_requests.approval_id` is unique, and the idempotency key is the approval's single-use nonce. Executed requests are terminal | 13 |
| The same work is executed twice | The claim locks the row (`FOR UPDATE SKIP LOCKED`); only `queued` can be claimed; there is one result per execution | 13, 26 (10-way race) |
| Execution after revocation or expiry | The gate checks `revoked_at`, `invalidated_at` and `expires_at` at queue time and at claim. Revocation cancels queued work; the cron job expires stale approvals | 15, 16 |
| Execution after the kill switch | The gate requires `global` + `integration.external_writes` + the action's switch. Disabling cancels queued work. A disabled switch blocks claims | 07, 17 |
| The system re-enables itself | Only `mos_kill_switch_enable` (owner, typed phrase, reason) can enable. A trigger refuses any other enable, even a direct SQL update. Monitors have no enable function | 18 |
| Automatic spend increase | There is no automatic mode. D4 allows monitors to raise **pause only** (check constraint plus function check). Activate and increase are refused and alerted | 19, 21 |
| Spend without guard rails | Money-moving actions are `blocked` in Phase 1. Enabling a paid switch requires a daily cap plus a confirmed platform-native cap | 09, 21 |
| Unauthorised person | Every function checks `gov.members` (user id **and** email). Refusals are audited and raise an `unauthorised_attempt` safety event | 03 |
| Browser reads or writes tables | Private schemas, forced RLS, no table privileges; `anon` can execute nothing | 04, 28 |
| A connection claimed that does not exist | `integration_registry` requires verification evidence for `read_only` / `read_write` | 02 |
| A history rewrite | Append-only audit with a hash chain. Verification is timezone-safe; tampering is detected at the exact row; the chain stays linear under concurrency | 24a, 24b, 27 |
| A blocked attempt disappears | Refusals are returned, not raised, so their audit rows commit | 03–21 (each refusal is asserted audited) |
| Secrets in git | `.gitignore`, `scripts/check-secrets.mjs` (CI and pre-commit), the console build refuses secret-shaped output, `configuration` rejects secret-like keys | test-all |
| Marketing OS touches HQ | Separate Supabase project, no HQ credentials, `scripts/check-hq-untouched.sh` | test-all |

## 2. Layers of "no"

An external write needs **every** layer to say yes:

1. **Environment**: the executor runs with `MOS_ENV=production` and `MOS_EXTERNAL_WRITES_ENABLED=true` (and
   `MOS_SPEND_ENABLED=true` for ads). Otherwise it runs dry.
2. **Credentials**: write tokens exist only from the phase that needs them, only in executor credentials.
3. **Kill switches**: `global`, `integration.external_writes` and the action's own switch, all enabled by Adam.
4. **Permission**: the action is registered and not `blocked`.
5. **Approval**: Adam's approval of this version and hash, not expired, revoked or invalidated, used at most once.
6. **Integration**: verified `read_write`.
7. **Money**: a cap with a confirmed platform-native limit.
8. **Executor identity**: active, and allowed this action.

The only exception is risk reduction. Pause, lower budget and hide skip layer 3, so stopping is always possible. D4 lets
monitors raise pauses (and only pauses) without a human.

## 3. Roles

| Who | Can | Cannot |
|---|---|---|
| Adam (owner) | Everything human: approve, revoke, queue, enable (typed), disable, acknowledge | Bypass the gate; enable Adam's personal LinkedIn automation; approve money-moving actions in Phase 1 |
| Approver (none yet) | Approve where the permission allows; disable switches | Enable switches; queue executions |
| Editor (none yet) | Draft, edit, submit | Approve, execute, enable |
| Agents | Propose within their list; log runs | Approve, execute, enable, read tables |
| Executors | Claim and report approved executions within their list | Create, approve or alter requests |
| Monitors | Disable switches; raise D4 pauses | Enable, resume, activate, increase |
| Dispatcher | Claim and mark alerts | Anything else |

## 4. Secrets

- Stored only in Supabase Edge Function secrets or n8n credentials. They are entered by the account owner in those secure
  forms, never in chat, never in files.
- `gov.secrets_registry` records name, location, access level, rotation and `is_set`, never the value.
- Marketing OS has its own credentials, separate from HQ's:
  - its own Resend send-only key and sender (`mos-alerts@noyaconcierge.com`);
  - its own Claude key and budget (D7);
  - its own Supabase project and keys.
- The console ships only the project URL and the **publishable** key. `console/build.mjs` refuses to build with a secret key.

## 5. Alerts (D6)

Critical events create a `gov.notifications` row in the same transaction. The Resend dispatcher (Edge Function, role
`mos_dispatcher`) sends them to the active owner's address, with an idempotency key per notification.

| Event | Source |
|---|---|
| Kill switch triggered | A tripwire, or disabling a switch that was enabled |
| Unexpected external write | `unexpected_external_write`, `meta_unknown_change` tripwires |
| Approval bypass attempt | Agent proposing outside its list, wrong identity on the executor path, replay, hash mismatch, automatic spend attempt |
| Audit-chain integrity failure | Hourly health check → `audit_chain_broken` |
| Daily spend cap breach | `*_spend_over_daily_cap`, `meta_spend_velocity` |
| Unknown publishing activity | `unknown_publication` tripwire |

Phase 1: the outbox works and is tested. Sending stays off (`alerts.enabled = false`) until the dispatcher is deployed with its
key.

## 6. Known limits

- A Postgres superuser (the Supabase project owner) can disable triggers. The hash chain makes that detectable (test 24b), not
  impossible. A weekly off-database export of the chain head is planned for Phase 2.
- An HTTP call already in flight when a switch is disabled will complete. It is logged.
- Worker JWTs are minted from the project's JWT secret. Whoever holds that secret holds every role, so it is stored only as an
  n8n credential and rotated on any suspicion.
