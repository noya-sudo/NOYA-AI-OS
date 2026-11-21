# NOYA Brochure Collection

The five NOYA brochures and the Selected Work portfolio, generated from copy in `content/` with the Studio house style.

| # | Publication | Content |
|---|---|---|
| 01 | NOYA Concierge (flagship) | `content/01-concierge.mjs` |
| 02 | NOYA Private Desk | `content/02-private-desk.mjs` |
| 03 | NOYA Corporate | `content/03-corporate.mjs` |
| 04 | NOYA Brands & Productions | `content/04-brands-productions.mjs` |
| 05 | NOYA Trade & Partners (replaces the Partner Guide) | `content/05-trade-partners.mjs` |
| 06 | NOYA Selected Work (quarterly) | `content/06-selected-work.mjs` |

```
node studio/brochures/build.mjs          # all six, draft (red tags on pages awaiting approval)
node studio/brochures/build.mjs 02 06    # selected publications
DRAFT=0 node studio/brochures/build.mjs  # final export after sign-off
```

Output: `studio/out/brochures/` (PDFs, HTML, page PNGs, `build-report.json`). The build fails if any text overflows its page, if a
photo is missing or EXCLUDED in `assets.json`, and it regenerates `docs/COPY_MASTER.md` from the content.

Documents: `docs/ARCHITECTURE.md` (positioning and collection), `docs/COPY_MASTER.md` (every word, page by page),
`docs/EVIDENCE_REGISTER.md` (claims, case studies, permissions), `docs/ASSET_REGISTER.md` (images), `docs/CHANGE_LOG.md`,
`docs/QC_REPORT.md`.

Rules: no claim prints unless the evidence register supports it; no client, hotel or supplier named without written permission; no
published fees; no photo beside a case study unless it shows that engagement. Photos and approved PDFs are not committed (public repo).
