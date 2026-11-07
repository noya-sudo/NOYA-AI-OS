# Approvals and permission boundaries

Status: proposal. Enforced by `supabase/proposed/0001_governance.sql` and checked by `supabase/proposed/tests/10_governance_test.sql`.

## 1. The rule

**Every external write requires approval by default.** This stays true until Adam changes a specific policy himself, in writing,
with an expiry. Money-moving actions can never become automatic.

"External write" means anything that changes something outside the Marketing OS database:
- a post, story, reel, article or deletion;
- a comment reply, DM or hide;
- any ads change;
- a hand-off to NOYA HQ;
- a marketing email.

Everything else is internal and needs no approval: research, drafting, analysis, scoring, calendar planning and reading platform
data through read-only tokens.

## 2. Risk tiers

| Tier | Meaning | Examples | Default policy |
|---|---|---|---|
| 0 | Internal, read-only | research, analysis, reading insights | No approval |
| 1 | Internal write | drafts, calendar, scores, signals | No approval |
| 2 | External, low reach | reply to a comment, hide spam | Owner approval + confirm |
| 3 | External, public or cross-system | publish a post, send a DM, create a PAUSED campaign, HQ hand-off | Owner approval + confirm |
| 4 | External, live spend or broadcast | edit a live ad, lower a budget, pause, marketing email | Owner approval + confirm (email: **blocked**) |
| 5 | Moves money | activate, resume, raise a budget | **Blocked** until Phase 8; then owner approval + confirm + cap |

Tiers 0–1 are not in `gov.action_types` at all: they never leave the database.

## 3. Roles

| Role | Who (at install) | Can |
|---|---|---|
| **owner** | Adam only (enforced: one active owner) | Everything below, plus approve tier 3–5, arm controls, change policies, add members |
| **approver** | nobody yet | Approve when a policy allows `min_approver_role = approver`; halt any control |
| **editor** | future content lead / freelancer | Create drafts, submit for approval; cannot approve |
| **analyst** | future | Read analytics, write analyses |
| **viewer** | future | Read only |

Non-human identities (`gov.service_identities`):

| Kind | Can request | Can execute | Holds |
|---|---|---|---|
| agent | Only the types in its `may_request` | **Never** (database check) | Read-only credentials |
| executor | Nothing | Only the types in its `may_execute`, only approved + confirmed + armed | Write credentials |
| monitor | Nothing | Nothing. It can **halt** through a tripwire | Read-only credentials |

## 4. Policies

One active row per action type in `gov.permission_policies`:

| Field | Default at install | Meaning |
|---|---|---|
| `mode` | `approval_required` (money and email: `blocked`) | `blocked` / `approval_required` / `auto_within_limits` |
| `min_approver_role` | `owner` | Lowest role that may approve |
| `approvals_required` | 1 | Raise to 2 once there is a second approver |
| `approval_ttl` | publish 48 h, spend 4 h, other 24 h | Approval lapses after this |
| `confirm_at_execution` | `true` | A second "run it now" click, after re-checking gates |
| `expires_at` | null | **Required** for `auto_within_limits`: autonomy is always time-boxed |

Changing a policy (`api.set_policy`):
- owner only;
- a written reason;
- to leave `approval_required`, Adam types the action code back (for example `instagram.hide_comment`);
- the old row is kept as superseded, and the change is audited with the before and after;
- `auto_within_limits` for a money-moving type is refused by a trigger. Allowing it needs a schema migration, a deliberate
  engineering change that cannot be done with a click.

## 5. What an approval means

An approval is a row in `gov.approvals` that records:
- who approved (user id, email, role);
- the decision (`approve` / `reject` / `request_changes`, with a note required for the last two);
- **the SHA-256 of the exact payload the approver saw.**

`gov.can_execute()` counts only approvals whose hash equals the current payload hash. The payload is frozen by trigger once it
leaves draft. To change anything (one word of a caption, a different image, a different time), cancel and raise a new request.

Other protections:
- **Segregation of duties.** A non-owner cannot approve their own request. Adam, as owner, may approve his own.
- **One decision per person per request.**
- **Expiry.** `gov.expire_approvals()` runs every 15 minutes and expires approved or queued work past its window.
- **Re-check at every step.** Confirm and claim each re-run every gate. The executor claims with `FOR UPDATE SKIP LOCKED`, so two
  executors can never run the same request.
- **Idempotency.** Every request has a unique `idempotency_key`. Executors pass it to the platform where the API supports it, and
  check `external_ref` before retrying.

## 6. What Adam sees in the review card

1. The rendered post as it will appear, with the account handle, the time, the asset thumbnails and the rights status of each asset.
2. The Brand Guardian results (pass / warn / fail, with reasons).
3. Why: the rationale, the source signal and the objective.
4. For spend: today's spend, the cap, the change and the projected daily exposure.
5. The payload hash, in small print.
6. Buttons: **Approve**, **Request changes** (note required), **Reject** (note required). After approval: **Run now** / **Schedule**.

Designed for a five-second decision on a phone. Batches (for example, "approve this week's six posts") are six approvals in one
screen. Each one is still bound to its own hash.

## 7. Boundaries that are not configurable

These are enforced in the schema, not in settings:

| Boundary | Where |
|---|---|
| Agents can never execute | `service_identities` check constraint |
| Money-moving actions can never be automatic | `permission_policies_guard` trigger |
| Autonomy must expire | `permission_policies` check constraint |
| Payload frozen after submission | `action_requests_guard` trigger |
| Illegal status transitions rejected (for example, blocked → queued) | `action_requests_guard` trigger |
| Connection status needs evidence | `channel_accounts` check constraint |
| Requests, approvals and audit rows cannot be deleted | immutability triggers |
| HQ hand-off needs every qualification gate true | `hq_handoffs_guard` trigger |
| Spend needs a daily cap and a confirmed platform-native cap | `can_execute` + `kill_switch_arm` |

## 8. How autonomy could be earned later (not now)

Only for tier 2 and only for risk-reducing actions first (for example, hiding obvious spam comments), and only:
- after at least 50 consecutive approved proposals of that type with no rejection for quality;
- with explicit limits (for example, at most 20 a day) and an expiry of at most 30 days;
- with a weekly sample review by Adam;
- with an immediate fall back to `approval_required` when a tripwire fires.

Publishing and spend stay approval-only unless Adam decides otherwise in writing.
