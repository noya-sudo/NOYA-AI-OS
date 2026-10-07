# Website: image rights, masters and design freeze (6 Oct 2026)

**WEBSITE DESIGN FROZEN — CONTENT & GROWTH MODE.** No new design phase. The website repo's `CLAUDE.md` holds the rules; its `docs/QA_REPORT.md` and `docs/IMAGE_RIGHTS.md` hold the detail.

## What changed (live since 6 Oct 2026, commit `052bc2b` on noya-website `main`)

**Withdrawn, CEO decision 4B.**
- Old-site photographs whose source was never recorded: 25 keys, plus their crops.
- They are no longer deployed (404). The Studio ignores them if it still holds them.

**Replaced: 16 slots.**
- **NOYA's own first:** two El Gouna frames from the Edge Studios shoot (27 Apr 2025), faces unseen.
- **Then open-licence originals, credited on the Terms page:**
  - El Gouna lagoon (Marc Ryckaert, CC BY 4.0);
  - Aegean anchorages (dronepicr, CC BY 2.0);
  - a helicopter landing (Antti Leppänen, CC BY 4.0);
  - the Red Sea coast from the air (Tanya Dedyukhina, CC BY 3.0).
- **Text-led where no cleared photograph explains the words:**
  - the Bespoke Travel and Corporate heroes;
  - the chauffeurs card;
  - the Corporate card on Home and What We Do.

**Private Calendar.** The 9 events approved under 2A are on the site. Their HQ status waits on the SQL paste (`supabase/migrations/20261006090000_hq_pending_writes.sql`, NOT YET APPLIED).

**QA: all green.**
- 0 audit failures; 160/160 pages; SEO 145/145; end-to-end 46/46; Studio flow 30/30.
- Studio smoke test passed.
- One visual audit at 1440 and 390.
- Live smoke check 18/18.

## Still temporary or awaiting a supplier

- **Dinaia, 5 photographs:** upscaled screenshots, "Replace soon — master requested" (The Cyan; draft in noya@, not sent).
- **The Cyan:** written permission and credits for Dinaia, Wind of Fortune and Villa Serenade.
- **Consensio:** written permission and high-resolution files for Chalet Le Grenier (draft in noya@, not sent).
- **Grace La Margna:** media kit (permission needed; not used).
- **Pier 88 Pyramid Hills stills:** not reviewed (private folder).
- **Edge Studios shoot:** model consent not recorded, so only frames with faces unseen are used.

## Master-asset audit (6 Oct 2026, in progress)

CEO instruction: treat the Mac folder "NOYA Website", Google Drive and Canva as primary sources, and find the best original of every photograph before sourcing anything new. All reading is read-only; nothing is renamed, moved, deleted or published. Tools and findings live in the noya-website repo (`scripts/asset-audit/`, `docs/asset-audit/`).

**Done**
- **Website:** all 160 library photographs are fingerprinted. 76 of 123 photo slots could be improved by a stronger NOYA original (`docs/asset-audit/CURATION_TARGETS.md`):
  - 12 text-led;
  - 9 supplier screenshots awaiting masters;
  - 10 below ideal width;
  - 33 licensed stand-ins;
  - 26 repeats.
- **Drive (noya@):** 787 files indexed. The Edge Studios originals give exact masters for 23 site photographs (VERIFIED by fingerprint). 14 of those originals are copied into "NOYA Website Masters (approved)".
- **Old Squarespace site:** 119 of 120 uploads fingerprinted. These old-site photographs are traced:
  - `el-gouna-aerial` is a Mac screenshot;
  - `abu-simbel-facade` is a web download, so it is now rights-unconfirmed (it is not on the site);
  - the old Edge-3/7/42/93 files come from NOYA's own Edge Studios shoots.
- **Wind of Fortune:** its 4 yacht photographs are macOS screenshots. They are flagged "replace soon", and the masters are requested in The Cyan draft.
- **Canva (read-only):** 1,962 images and 226 designs inventoried. Client and personal designs are recorded by id only.
  - 625 camera and phone images were fingerprinted and matched (`docs/asset-audit/MASTER_CATALOGUE.md`).
  - Canva holds larger copies of 8 site photographs: the Edge Studios pool and boat set, 3,600 px against the site's 3,000.
- **Master catalogue.**
  - 25 site photographs have their original in Drive.
  - 16 live NOYA photographs still need their originals found: the North Coast set, Abu Simbel, the pool and boat set, and the pyramid gift.
  - Quality question: for `north-coast-villa-dusk`, `north-coast-horizon` and `abu-simbel-ramses`, the only copies found are 1,179 px iPhone exports, while the site serves them at 2,400–2,892 px. If no full-size original exists, these files may be enlargements and will be graded again.
  - 61 of 119 old-site uploads are traced. The old site's "Fly web.jpg" was an Emirates marketing image.

- **The Mac folder "NOYA Website" (audited 7 Oct from Adam's Drive upload).** All 230 files were catalogued and the 96 under about 6 MB scanned. Findings: noya-website `docs/asset-audit/mac/2026-10-07-drive-copy/FINDINGS.md`.
  - It is a working collection: Canva page exports, screenshots of site photographs, web downloads, and 12 Edge Studios originals that are identical to Drive. It holds no new masters.
  - Adam's picks give five usable El Gouna frames with no faces showing (Edge-44, 45, 46, 101, 102). Edge-101 is now in the website library for dining.
  - The deck's "NOYA headrest" car image is AI-generated. Never show it as NOYA photography.
- **Weddings imagery (CEO, 7 Oct).**
  - Sage photographs show crafted dining, not weddings.
  - The five Pyramids wedding images Adam sent are other couples' weddings (most likely Jain–Hammond, April 2024) and one AI render, so they are not used.
  - The route, in order: NOYA's own events with consent → permissioned venue imagery (Pier 88 Pyramid Hills first) → licensed photography (needs CEO approval for spend).

**Canva conflicts to know about (do not reuse these designs as they are)**
- **Eclipse design `DAG7nT3qk0k`:** the cover says "2026 partial eclipse experience, August 10th–14th", but the inside says the journey is built around the total eclipse. The total eclipse over Luxor is 2 Aug 2027. Correct it before any reuse.
- **Monaco GP 2026 designs:** they give two different date ranges (4–7 vs 5–7 June).
- **"Noya Concierge Brands and Productions" (`DAHSLweLTGU`):** shows Jacquemus and Dior show imagery as examples. That imagery is third-party; never use it on the website.

**Waiting on the CEO**
- **Share the Drive folder.** Adam's Drive upload of the Mac folder needs sharing with noya@noyaconcierge.com as Viewer. It is not visible yet.
  - Once shared: list it, mirror photographs up to about 7 MB, and run the full read-only scan.
  - Larger files (RAW, video, large JPEG) need the n8n Google Drive credential (step 3 of the credential list below), or the Mac session in `docs/LOCAL_ASSET_AUDIT.md`.
- **Pier 88 x Noya shoot:** 314 files in noya@'s My Drive (Sony RAW + JPEG, Pyramid Hills and El Gouna, April 2025). Every file is over 7 MB, so it needs the same credential or the Mac.
  - Confirm that NOYA owns it, who the photographer is, and that models consented.

## Automation (approval-based; nothing publishes itself)

- **"NOYA – Drive masters → Sanity"** (n8n, inactive).
  - Reads the published rights register (`/seed/masters.json`) and uploads approved masters from the Drive folder "NOYA Website Masters (approved)" to Sanity as assets.
  - Mirrors open-licence originals into that folder.
  - 14 NOYA originals (Edge Studios, El Gouna) are already copied there.
  - Needs the two credentials below.
- **"HQ approved events → Sanity drafts"** (n8n, inactive).
  - Creates Studio drafts only; a person publishes.

**CEO, once (never paste a token into chat):**
1. sanity.io/manage → project `yb8ubrdw` → API → Tokens → Editor token.
2. n8n → Credentials → Bearer Auth "Sanity (NOYA website)": paste the token there only.
3. n8n → Credentials → Google Drive OAuth2 API: sign in as noya@noyaconcierge.com.
