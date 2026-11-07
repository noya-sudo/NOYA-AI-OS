# NOYA Marketing OS

The AI-native marketing operating system for NOYA Concierge. It covers brand, Instagram, LinkedIn, intelligence, content, organic
growth, paid acquisition, analytics, attribution and marketing-generated leads.

**This is not NOYA HQ.** HQ runs clients, suppliers, bookings, itineraries, payments and operations. Marketing OS hands HQ only
qualified commercial opportunities, through one approved and audited interface.

## Status: Phase 0 (architecture)

- No platform is connected. No credential exists. Nothing can publish or spend.
- The schema is a **proposal** (`supabase/proposed/`), checked on a throwaway local Postgres. It is not applied to any database.
- No NOYA HQ file, table or workflow has been changed.

## Safety model in one paragraph

Agents (LLM) **propose**. Adam **approves** the exact payload, bound by its SHA-256. A separate **executor** (no LLM) carries it
out, only if every gate passes:
- policy;
- approval on these bytes;
- not expired;
- confirmed;
- kill switch armed;
- connection verified;
- within budget.

Every kill-switch control is installed **halted**. Halting cancels queued work; arming never resumes it. Money-moving actions can
never be automatic. Every decision and every refusal is written to a hash-chained, append-only audit log.

## Map

| Path | What |
|---|---|
| `docs/architecture.md` | System design, boundary with HQ, components, agents, action pipeline, security |
| `docs/operating-manual.md` | Daily and weekly rhythm, content workflow, leads, channel connection, incidents |
| `docs/approvals-and-permissions.md` | Tiers, roles, policies, what an approval means, non-configurable boundaries |
| `docs/kill-switch.md` | Four layers, controls, tripwires, runbook |
| `docs/audit-logging.md` | What is logged, the hash chain, redaction, retention, export |
| `docs/environment.md` | Every variable and secret: where it lives, which phase, read vs write |
| `docs/hq-handoff-contract.md` | The only interface to NOYA HQ |
| `docs/implementation-plan.md` | Phases 0–9 with exit gates |
| `docs/decisions.md` | Architecture decisions and open CEO decisions (D1–D8) |
| `supabase/proposed/` | Proposed schema + governance tests |
| `agents/` | Agent charters |
| `workflows/` | n8n workflow conventions (no workflows yet) |
| `console/` | Marketing Console (Phase 1) |
| `scripts/check-secrets.mjs` | Secret scanner: run before every commit |

## Check the proposal locally

```bash
node scripts/check-secrets.mjs
```

Then see `supabase/README.md` to run the governance tests on a local Postgres.
