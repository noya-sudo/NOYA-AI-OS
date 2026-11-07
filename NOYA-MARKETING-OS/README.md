# NOYA Marketing OS

The AI-native marketing operating system for NOYA Concierge. It covers brand, Instagram, LinkedIn, intelligence, content, organic
growth, paid media, analytics, attribution and marketing-generated leads.

**A separate product from NOYA HQ.** HQ runs clients, bookings, suppliers, payments, itineraries and concierge operations. The
only bridge, later, is qualified commercial opportunities that Adam approves.

## Status: Phase 1 built and tested (7 Nov 2026)

- Control plane migrations written: approval engine, kill switches (all disabled), hash-chained audit, safety, alerts, registries,
  health, agent runs. **28 / 28 database checks pass**, including a 10-way race.
- Internal console built: headless checks pass on desktop and mobile.
- Resend alert dispatcher prepared.
- **Pending:** creation of the Supabase project (needs one permission for this session's `create_project` call); moving to the
  private repo `noya-marketing-os` (automated task queued).
- Nothing is connected, nothing can publish, nothing can spend. No NOYA HQ file has changed (`scripts/check-hq-untouched.sh`).

## Run every check

```bash
PGHOST=… PGPORT=… PGUSER=postgres scripts/test-all.sh
```

## Map

| Path | What |
|---|---|
| `docs/architecture.md` | System design and boundary with HQ |
| `docs/security-model.md` | Threats → controls → tests |
| `docs/database.md` | Tables, status machines, the gate, API, roles |
| `docs/integrations.md` | Every connector and its real status |
| `docs/operating-manual.md` | How the desk and the department run |
| `docs/implementation-plan.md` | Phases, with what is done and what is next |
| `docs/zero-manual-policy.md` | When Adam is (and is not) interrupted |
| `docs/decisions.md` | D1–D8 |
| `docs/kill-switch.md`, `docs/approvals-and-permissions.md`, `docs/audit-logging.md`, `docs/hq-handoff-contract.md`, `docs/environment.md` | Phase 0 design detail (with Phase 1 notes) |
| `supabase/` | Migrations, tests, alert dispatcher |
| `console/` | Internal operating desk |
| `scripts/` | `test-all.sh`, `test-db.sh`, `check-secrets.mjs`, `check-hq-untouched.sh` |
