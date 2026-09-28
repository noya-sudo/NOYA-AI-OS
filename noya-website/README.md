# NOYA Website — rebuild workspace

Replacement for the Squarespace site at https://www.noyaconcierge.com. **Nothing here is published, and the live site has not been changed.**

| File | Purpose |
|---|---|
| `CURRENT_SITE_AUDIT.md` | Source of truth: pages, services, destinations, strengths, weaknesses, gaps |
| `CONTENT_INVENTORY.md` | Every section classified KEEP / REWRITE / REMOVE / REPOSITION |
| `SEO_MIGRATION_MAP.md` | Current URL → new URL, titles, meta, H1, redirects |
| `SITE_ARCHITECTURE_PROPOSAL.md` | Proposed new structure (Phase 7 — proposal only) |
| `legacy-site/pages/` | Verbatim copy of every live page (EXTRACTED) |
| `legacy-site/content/pages.json` | Machine-readable inventory: metadata, headings, CTAs, forms, images |
| `legacy-site/content/DESIGN_CAPTURE.md` | Current colours, type, components, mobile behaviour |
| `legacy-site/screenshots/` | 12 full-page screenshots of the live site (2026-09-28) |
| `legacy-site/assets/images/IMAGE_MANIFEST.csv` | All 120 image URLs with page, role and rights flag |
| `legacy-site/assets/download_assets.sh` | Downloads every original image into `assets/images/` |
| `legacy-site/assets/video/` | Empty — the live site has no video |
| `legacy-site/tools/build_inventory.py` | Regenerates `pages.json`, the manifest and the download script |

Extraction method: live crawl via Firecrawl (`maxAge=0`) because this environment's network policy blocks direct access to the site and the Squarespace CDN.

To pull the original images: `bash legacy-site/assets/download_assets.sh` from a machine that can reach `images.squarespace-cdn.com`.
