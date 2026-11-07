# Implementation plan

Ten phases. Each phase ends at an exit gate that Adam approves. External-write capability arrives late and one surface at a time:
reading comes before writing, organic before paid, and paused campaigns before live ones.

| Phase | Name | External writes | Money | Main exit test |
|---|---|---|---|---|
| 0 | Foundations (this commit) | None | None | Adam approves the architecture and D1–D7 |
| 1 | Control plane | None | None | Governance tests pass on the real project; console login works |
| 2 | Brand & knowledge | None | None | Brand Guardian catches seeded bad drafts |
| 3 | Intelligence | None (reads public web) | Research credits within budget | Two weeks of signals Adam finds useful |
| 4 | Content studio | None (Adam posts by hand) | None | Four weeks of calendar shipped through the queue |
| 5 | Read connections | None (read tokens only) | None | Verified read connections; first weekly review with real numbers |
| 6 | Leads & HQ hand-off | Hand-off to HQ (approved) | None | First qualified lead delivered and acknowledged by HQ |
| 7 | Governed publishing | Instagram / LinkedIn Page posts (approved, confirmed) | None | Ten posts executed with zero discrepancies |
| 8 | Governed paid media | Ads: paused-create, then activation | Within caps | First test campaign run inside its kill criteria |
| 9 | Earned autonomy | Narrow, time-boxed, risk-reducing only | Never automatic | Case-by-case, Adam in writing |

---

## Phase 0: Foundations (this commit)
**Delivered:**
- repository structure;
- architecture, operating manual, approvals and permissions, audit logging, kill switch, environment, HQ hand-off contract,
  decisions and this plan;
- the proposed schema (`supabase/proposed/0001`, `0002`) with 13 governance tests passing on local Postgres 16;
- a secret scanner.

**Not done:** no Supabase project, no connection, no workflow, no UI.

**Exit:** Adam answers D1–D7.

## Phase 1: Control plane
**Build:**
- Adam creates the Supabase project (D2) and the repo (D1).
- Promote `0001_governance.sql` to the first real migration. Tests run in CI against a Supabase branch.
- Seed Adam as owner. All controls `halted`.
- Console v0 (static, Cloudflare): login, kill switch panel, audit viewer, empty review queue.
- pg_cron: `gov.expire_approvals()` every 15 minutes, nightly `gov.verify_audit_chain()`.
- n8n folder `Marketing OS`, error reporting into the existing workflow 00 pattern, and the weekly audit export to Drive.
- CI: `check-secrets.mjs`, the governance tests, and a console build scan.

**Exit:**
- tests green on the real project;
- Adam can log in and halt, and cannot arm without the typed phrase;
- the audit log shows all of it.

**Adam decides:** nothing new.

## Phase 2: Brand & knowledge
**Build:**
- `0002` brand tables;
- seed `brand.voice_rules` from NOYA's voice (the user preferences and HQ Studio's editorial master), with Adam reviewing the list
  once;
- the asset library, with private storage and rights fields. The existing visual tokens (navy `#061422`, paper `#F7F7F7`,
  Cormorant Garamond and Jost) are **copied**, not linked, from HQ Studio;
- pillars;
- the Brand Guardian agent: deterministic checks first (banned phrases, rights, length, hashtags), then a model check for tone and
  claims.

**Exit:** Brand Guardian fails 10 of 10 seeded bad drafts and passes 10 of 10 good ones; Adam agrees with its reasons.

**Adam decides:** the pillars and their target shares; the banned-phrase list.

## Phase 3: Intelligence
**Build:**
- `intel` tables;
- the watched-sources list (competitors, hotels, openings, publications, event calendars);
- the Intelligence Analyst on a weekly cadence, using the existing Firecrawl and Serper accounts within their current budgets;
- every signal labelled verified, inferred or unverified, with evidence links;
- on-demand research briefs from the console.

**Exit:** two weeks of signals, and at least five that Adam marks "actioned" or turns into content.

**Adam decides:** the watch list and the monthly research budget.

## Phase 4: Content studio (no API publishing)
**Build:**
- `content` tables and the Content Strategist;
- the calendar, briefs, drafts and versions;
- the review queue on mobile;
- **manual publish flow**: Copy caption, Download assets, Mark published (with the permalink) → `content.publications` (method
  `manual`);
- the UTM link generator.

**Exit:** four consecutive weeks of the planned calendar shipped through the queue; average review time under 10 minutes a day.

**Adam decides:** the posting cadence per channel.

## Phase 5: Read connections
**Build:**
- the channel verification procedure (operating manual §7);
- readers for Instagram insights, comments and DMs (read), LinkedIn Page analytics (if LinkedIn grants access), Meta Ads read, and
  GA4 / Search Console;
- `analytics` tables;
- the Analytics & Attribution agent and the weekly marketing review with real numbers;
- the `unknown_post_detected` monitor (needs read access).

**Exit:** each connected account shows `read_only` with evidence; one weekly review built only from database numbers.

**Adam decides:**
- create the Meta app and system user in NOYA's Business portfolio (about 30 minutes, guided);
- whether to apply for LinkedIn Community Management API access.

## Phase 6: Leads & HQ hand-off
**Build:**
- `leads` tables, Community Triage and the Lead Qualifier;
- the hand-off outbox;
- **separately approved HQ change**: the intake function (`docs/hq-handoff-contract.md` §5);
- the courier workflow;
- arm `handoff.hq`.

**Exit:** the first qualified lead is delivered, acknowledged with an `hq_reference`, and shows up correctly in HQ with no
duplicate.

**Adam decides:** approve the HQ intake change; D3-B if wanted.

## Phase 7: Governed publishing
**Build:**
- the write tokens (separate credentials) and the `read_write` verification;
- the publisher executor (no LLM node; one API call; idempotency; report);
- staged roll-out:
  - **7a:** 5 posts in dry-run (`MKT_EXTERNAL_WRITES_ENABLED=false`), comparing payloads with what Adam would have posted;
  - **7b:** arm `publish.instagram` and execute 10 approved and confirmed posts, with Adam watching;
  - **7c:** the same for the LinkedIn Page (if access was granted);
- engagement executor (replies) behind its own controls.

**Exit:** ten executed posts, each one identical to its approved payload, all audited, with zero tripwire events.

**Adam decides:** arm each control (typed phrase).

## Phase 8: Governed paid media
**Build:**
- Adam sets the **platform-native account spending limits** first;
- the budget caps (`platform_native_cap_confirmed`);
- the separate ads write token;
- the ads executor;
- the spend monitors (cap, velocity, unknown change);
- D4 auto-pause.

**Order:**
- **8a:** `*.create_paused` only, so campaigns are built on the platform at zero spend;
- **8b:** owner-only, confirmed activation within the cap, for one test campaign with written kill criteria;
- **8c:** the optimisation loop. The analyst proposes; Adam approves.

The policies for `*.activate` and `*.increase_budget` move from `blocked` to `approval_required` by Adam's own `api.set_policy`
call, audited.

**Exit:** the test campaign runs to its kill criteria or its target. Spend never exceeds the cap; every change has an approval.

**Adam decides:** D8 (budget), the platforms and arming `spend.*`.

## Phase 9: Earned autonomy (optional)
Only where the record supports it (approvals-and-permissions §8): narrow, risk-reducing, time-boxed (30 days at most), with
limits, a weekly sample review and automatic fall-back. Never money. Never without Adam's written decision.

---

## Cross-cutting, every phase
- No HQ file, table or workflow is touched (Phase 6's intake is a separate HQ change).
- `check-secrets.mjs` and the governance tests run in CI.
- Each new external action type is added to `gov.action_types` with its policy defaulting to `approval_required` (or `blocked`).
- Costs are tracked per agent; the paid-software gate applies to any new tool.
- Docs are updated in the same commit as the behaviour they describe.
