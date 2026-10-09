# Live n8n code — 9 Oct 2026

Exact copies of the "Split Candidates By Lane" Code node, as published on 9 Oct 2026 in workflows 02, 03, 04 and 06.
n8n is the source of truth; these files are the reviewed record.

**Why.** Raising the Merge & Cap research cap to 10 on 8 Oct changed nothing. This node, which runs before Merge &
Cap, passed at most 4 direct candidates. After known accounts and recently researched domains were skipped, each run
deep-researched 1–4 companies.

- `MAX_DIRECT_CANDIDATES`:
  - 02, 04 and 06: 4 → 14, so a cap of 10 can fill after the skips;
  - 03: 4 → 8, for its cap of 6;
  - 07 already passes 8.
- **Scoring words.**
  - 02 no longer scores "agency" down: agencies and production companies have been valid brand-lane types since
    7 Oct.
  - 06 no longer scores "agency" or "consulting" down. Sports and talent agencies (NOYA Private) and consulting firms
    are its targets. Every NOYA Private query contains "agency", so those candidates always ranked last and were cut
    by the old cap of 4.
- **Cost.** Each extra candidate adds a few Serper searches and AI calls. The Hunter nodes in these workflows are
  disabled, so no Hunter credit is spent.
