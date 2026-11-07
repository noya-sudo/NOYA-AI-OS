# NOYA Marketing OS: Operating manual

How the marketing department runs day to day, who does what, and what Adam needs to do (as little as possible).
Status: proposal. Sections marked *(Phase N)* apply from that phase.

---

## 1. Adam's role

Adam does four things in Marketing OS. Everything else is prepared for him or done without him.

| Adam does | Time |
|---|---|
| Approve or reject content, replies, hand-offs and (later) spend in the review queue | ~10 min a day, on a phone |
| Answer grouped CEO decisions (QUESTION / CONTEXT / RECOMMENDATION / OPTIONS) | A few a week |
| Arm or halt controls | Rare |
| Read the weekly marketing review and pick next week's three priorities | 15 min a week |

Adam never needs to copy data between tools, write first drafts or compile reports.

## 2. Daily rhythm

| Time (Cairo) | What happens | Who |
|---|---|---|
| 06:00 | Readers pull yesterday's insights, comments, DMs and spend *(Phase 5)* | Readers (n8n) |
| 06:30 | Monitors check tripwires and the audit chain | Monitors |
| 07:00 | Intelligence Analyst scans watched sources; files signals with confidence labels | Agent |
| 07:30 | Community Triage classifies new comments and DMs: lead / question / praise / spam / risk | Agent |
| 08:00 | **Morning marketing block** in the CEO daily: what changed, what is in the queue, what needs a decision | Chief of Staff |
| Any time | Adam clears the review queue | Adam |
| Scheduled slots | Approved and confirmed posts go out. Until Phase 7 Adam posts by hand and taps **Mark published** | Executor / Adam |
| 18:00 | Lead Qualifier scores the day's leads; prepares hand-offs | Agent |

Agents skip a run (recorded `skipped_paused` / `skipped_budget`) rather than run degraded.

## 3. Weekly rhythm

| Day | What |
|---|---|
| Monday | **Weekly marketing review** (format in §9). Content Strategist proposes the week's calendar (for example 3–4 Instagram, 2 LinkedIn Page, 1 draft for Adam's LinkedIn) |
| Monday | Adam approves the calendar ideas (not final posts) |
| Tue–Thu | Drafts produced, Brand Guardian checked, sent to the queue at least 48 h before their slot |
| Friday | Analytics & Attribution updates cost per qualified enquiry and channel contribution; flags what to stop |
| Sunday | Weekly audit export to Drive; secrets rotation reminders if due |

Monthly: brand rules review, asset rights expiries (30-day warning), agent cost against budget, competitor landscape summary.

## 4. Content workflow

```
signal / idea ──► brief ──► draft (version 1..n) ──► Brand Guardian ──► review queue ──► approved ──► scheduled ──► published ──► measured
```

1. **Idea.** From a signal (an opening, a season, an event), a pillar gap or Adam. Every idea names its objective: awareness,
   engagement, enquiry, partnership or proof.
2. **Brief.** The angle, the audience, the asset needs and the call to action. Rights for every asset are checked before drafting.
3. **Draft.** The caption or body, alt text, hashtags (few, specific), CTA and UTM link. Each edit is a new immutable version.
4. **Brand Guardian.** Checks voice, banned phrases, claims (no unverifiable superlatives, no "best", no invented partnerships),
   asset rights and releases, platform rules and privacy (no client named without consent). A `fail` cannot be submitted.
5. **Review.** Adam sees the rendered post. **Approve**, **Request changes** (note) or **Reject** (note).
6. **Publish.** Until Phase 7, Adam posts from his phone. Marketing OS gives one-tap **Copy caption** and **Download assets**, and
   Adam taps **Mark published** with the link. From Phase 7, the executor publishes at the slot after **Run now / Schedule**.
7. **Measure.** At 24 h, 7 days and 28 days: reach, saves, shares, profile visits, link clicks, enquiries.

### NOYA voice

Editorial luxury hospitality, not influencer marketing. Concise, understated and specific: names, places and details, not
adjectives. Never desperate, never "DM us now", no luxury clichés ("unparalleled", "curated experiences", "hidden gem",
"bespoke luxury").

These rules are stored as `brand.voice_rules`, so Brand Guardian enforces them. Adam can add a banned phrase in one line.

## 5. Community and leads

- Community Triage reads comments and DMs *(Phase 5)* and classifies each one. It drafts replies; it never sends.
- A reply is an action request (tier 2–3). Adam approves it; until Phase 7 he sends it himself.
- **Lead path:** inbound → triage → qualification (five gates) → nurture or hand-off. Only a qualified lead becomes an HQ hand-off,
  and only after Adam approves it (`docs/hq-handoff-contract.md`).
- **Risk messages** (complaints, press, legal, safety) jump the queue to the top of Adam's list. They never get an agent reply.
- Do-not-contact requests are honoured immediately and permanently.

## 6. Paid media *(Phase 8)*

- Every campaign starts as a **media plan**: objective, audience, budget, the success metric (qualified enquiries, not reach),
  the target cost per result and **kill criteria written before launch**.
- Approving a plan spends nothing. Each platform change is its own approved request.
- Campaigns are created **PAUSED**. Activation is a separate, owner-only, confirmed request within the daily cap.
- The Paid Media Analyst monitors daily and proposes changes; it never executes.
- Pausing and lowering budgets remain possible while spend is halted.
- Platform-native spending limits must be set before `spend.*` can be armed.

## 7. Connecting a channel (the only way a connection becomes "real")

A channel shows **Not connected** until all of this is done. Nothing is assumed.

1. Adam creates or authorises the platform app in NOYA's own business account (Meta Business portfolio, LinkedIn Page).
2. The token is stored as an n8n credential. Its name, location, read/write and scopes are recorded in `gov.secrets_registry`.
3. A reader workflow makes one harmless verification call (for example `GET /me` or account info). The call is logged in
   `gov.external_call_log`.
4. Only then is `gov.channel_accounts` set to `read_only`, with `verified_at`, the evidence (call id, HTTP status) and the granted
   scopes. The database rejects the status without that evidence.
5. `read_write` is a separate step, in the publishing phase, with a separate write token, verified the same way.
6. If a later call fails with an authorisation error, the account goes to `error` and the console says so.

## 8. Members and access

- Adam is the only owner. Adding a person means a Supabase Auth user plus a `gov.members` row (owner action, audited).
- A freelancer or content lead would be an **editor**: they can draft and submit, but cannot approve or arm.
- Offboarding: set `active = false` (instant), then remove the Auth user. Any write tokens they could have seen are rotated.

## 9. Reporting

**Into the CEO daily** (the Marketing OS block, at most 5 lines):
```
MARKETING — 3 in queue (2 posts, 1 hand-off) · 1 qualified lead (Red Sea villa, ~£50k) · reach 7d +18% · spend £0 · all controls halted except publish.instagram
```

**Weekly marketing review** (Monday):
1. What produced enquiries, and at what cost (by channel, pillar and post).
2. What is gaining traction and what is not (stop list).
3. Hand-offs to HQ and their outcomes.
4. Content shipped against plan.
5. Intelligence: the three signals worth acting on.
6. Agent activity and cost, refusals and halts.
7. **Three marketing actions for next week** and any CEO decisions, each with a recommendation.

## 10. Incidents

| Situation | Do |
|---|---|
| Wrong or embarrassing post live | Halt `global` → delete through an approved `*.delete_*` request (or by hand in the app) → record it → review |
| Spend running away | Halt `spend.*` → pause (risk-reducing, still allowed) → check the platform-native cap → review |
| Token leaked or suspected | Revoke at the platform → delete the n8n credential → halt `global` → rotate → `token_scope_changed` review |
| Agent producing bad output | Set `ops.agents.enabled = false` with a `paused_reason` → review prompts and inputs |
| Audit chain broken | Automatic `global` halt → compare with the Drive export → find the row → do not re-arm until explained |
| Platform API change or outage | Readers record errors and accounts go to `error`. Nothing is guessed or back-filled with estimates |

Full runbook: `docs/kill-switch.md` §9.

## 11. Rules Claude follows when working on Marketing OS

- Never claim a connection, metric or result that is not in the database with a source.
- Never call write or spend tools on any connector (Metricool, Windsor, AdWhispr, Meta, LinkedIn) on Marketing OS's behalf.
- Never touch NOYA HQ files, tables or workflows from Marketing OS work.
- Never commit secrets; run `scripts/check-secrets.mjs`.
- Keep human approval on every external write until Adam explicitly changes a specific policy.
- Label every fact: verified, inferred or unverified.
