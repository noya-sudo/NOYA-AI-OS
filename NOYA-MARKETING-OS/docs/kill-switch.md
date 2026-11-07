# Kill switch

> **Phase 1 implementation note (7 Nov 2026).** Implemented in `supabase/migrations/` as `gov.kill_switches` with keys `global`, `integration.external_writes`, `integration.hq_handoff`, `organic.instagram`, `organic.linkedin_noya`, `organic.linkedin_adam`, `paid.meta_ads`, `paid.linkedin_ads`, all initialised **disabled** (= halted). "Arm" is `mos_kill_switch_enable` (owner, typed `ENABLE <key>`); "halt" is `mos_kill_switch_disable`. D4 is decided: tripwires may raise automatic PAUSE requests only. Tests: `docs/security-model.md`.

Status: proposal. Enforced by `gov.system_controls`, `gov.halt()`, `api.kill_switch_*`, `api.monitor_trip()` and `gov.can_execute()`.

## 1. Purpose

One action stops every publishing, engagement, hand-off and ad-spend automation within seconds. It needs no engineer, no second
person and no explanation of what went wrong first.

## 2. Four independent layers

A single layer can fail, so there are four. Any one of them is enough to stop external writes.

| Layer | What it is | Who can pull it | How fast | Survives a bug in our code? |
|---|---|---|---|---|
| **L1 Database control** | `gov.system_controls`: `global` plus one per channel / platform | Console button (approver+); monitors via tripwires | Instant | Yes; every gate reads it in the same transaction |
| **L2 Executor off** | Unpublish the executor workflows in n8n | Adam in n8n | ~1 minute | Yes; no executor means no writes |
| **L3 Credentials out** | Delete or revoke the write tokens (n8n credential, Meta system user, LinkedIn app) | Adam | Minutes | Yes; the API refuses us |
| **L4 Platform-native caps** | Meta account spending limit, LinkedIn campaign group budget, Google account budget | Adam in each platform | Set in advance | Yes; enforced by the platform even if all our layers failed |

**L4 is required before any spend control can be armed.** `api.kill_switch_arm('spend.*')` refuses unless a daily cap exists and
Adam has confirmed (`platform_native_cap_confirmed = true`) that the platform's own spending limit is set.

## 3. Controls

| Key | Stops |
|---|---|
| `global` | Everything below |
| `publish.instagram`, `publish.linkedin_page`, `publish.website` | Publishing and deletion on that surface |
| `engagement.instagram`, `engagement.linkedin` | Replies, DMs, hides |
| `spend.meta`, `spend.linkedin`, `spend.google` | Every ads change on that platform except risk-reducing ones |
| `handoff.hq` | Deliveries to NOYA HQ |
| `email.marketing` | Marketing email |

An action runs only if **both** `global` **and** its own control are `armed`. A missing row reads as halted (fail-closed).

## 4. Installed state

**All eleven controls are `halted` at install.** Nothing external can run until Adam arms the specific control, in the phase that
needs it. During development there are no write credentials at all, so L3 is effectively pulled too.

## 5. Halting

Who: any **approver** or the **owner** in the console, any **monitor** through a tripwire, or Adam directly in SQL in an emergency.

What happens, in one transaction:
1. The control is set `halted`, with who, when and why.
2. Every `approved` or `queued` request under that control becomes `blocked` (terminal). The number is returned and logged.
3. A `gov.kill_switch_events` row and an audit row are written.
4. Any executor mid-flight finds the control halted when it reports or retries. A claimed request already in `executing` finishes
   its single API call, which is unavoidable once the HTTP request is in flight. Nothing new starts.

Risk-reducing actions (`*.pause`, `*.decrease_budget`, `instagram.hide_comment`) are **not** blocked by a halt and can still be
approved and run while halted. Stopping spend must stay possible when everything else is frozen.

## 6. Arming

Who: **owner only**.

Requirements:
- the typed phrase `ARM <key>` (for example `ARM publish.instagram`);
- a written reason;
- for `spend.*`: an active daily cap and a confirmed platform-native cap.

Arming **never resumes** work that the halt blocked. Those requests are terminal and must be raised and approved again. This
prevents a stale approval from firing days later in a different context.

## 7. Tripwires (automatic halts)

Monitors evaluate `gov.tripwires` and call `api.monitor_trip()`. **A tripwire can halt; nothing automatic can ever arm.**

| Code | Fires when | Halts |
|---|---|---|
| `spend_over_daily_cap` | Platform-reported spend today ≥ daily cap | `spend.meta` (per platform) |
| `spend_velocity` | More than 40% of the daily cap spent within one hour | `spend.meta` |
| `unknown_campaign_change` | A campaign or budget changed on the platform with no matching request | `spend.meta` |
| `unknown_post_detected` | A post appeared on a NOYA account that is not in `content.publications` | `global` |
| `executor_failures` | Three or more executor failures within one hour | `global` |
| `audit_chain_broken` | `gov.verify_audit_chain()` finds a broken row | `global` |
| `token_scope_changed` | A platform token gained scopes it did not have when registered | `global` |

When a tripwire fires, the console shows a red banner. In-console alerts work from day one. Email or push alerts to Adam are
decision D6.

## 8. Emergency auto-pause of live ads (Phase 8, decision D4)

A halt stops *our* changes, but live campaigns keep spending on the platform. Two options for when ads are live:

- **A: Freeze only.** The halt stops our system. Adam pauses campaigns himself (one click per campaign in the console, using the
  risk-reducing `*.pause` action, or directly in Ads Manager).
- **B: Freeze and pause.** On `spend_over_daily_cap`, `spend_velocity` or `unknown_campaign_change`, the monitor also raises
  `*.pause` requests that are pre-approved by a standing owner policy. This would be the only pre-authorised external write in
  the system, and it can only ever reduce spend.

Recommendation: **B**, enabled only when the first campaign goes live. Until then the question does not arise.

## 9. Runbook: "Something is wrong, stop everything"

1. **Console → Kill switch → Halt everything** (halts `global`). Takes one tap.
2. If ads are live: **Console → Paid → Pause all**, or Ads Manager → select all → Off.
3. If you cannot reach the console: n8n → Workflows → filter tag `mkt-executor` → unpublish all.
4. If you suspect a leaked token: revoke it at the platform (Meta Business Settings → System users → Revoke tokens;
   LinkedIn Developer portal → app → Auth → regenerate), then delete the n8n credential.
5. Tell Claude what happened. The audit log and `gov.external_call_log` show exactly what ran, when and on whose approval.
6. Re-arm only after the cause is understood, one control at a time, with a reason.

## 10. Tests

`supabase/proposed/tests/10_governance_test.sql` covers:
- installed halted;
- editor cannot arm;
- the typed phrase is required;
- halting blocks queued work;
- re-arming does not resume it;
- spend cannot be armed without caps;
- a tripwire halts;
- every refusal is audited.
