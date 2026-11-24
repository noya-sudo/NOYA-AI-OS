# NOYA Brochure Collection · Publication QC Report (r2)

*Edition v2026-11-r2 · built 2026-11-24 02:37 UTC · previous final PDFs archived unchanged in `studio/out/brochures/baseline_v2026-11/`.*

## 1. Build results

| # | Digital file | Pages | Digital | Print | Overflow / clipping | Digital < 150 ppi | Print < 250 ppi |
|---|---|---|---|---|---|---|---|
| 01 | `NOYA_01_Concierge_Overview_v2026-11-r2.pdf` | 11 | 2.98 MB | 6.63 MB | none | p1 yacht-tray-tall 123, p3 towel-chair-sea 137 | yacht-tray-tall 119, towel-chair-sea 143, alpine-chalet 226 |
| 02 | `NOYA_02_Private_Desk_v2026-11-r2.pdf` | 9 | 1.66 MB | 3.15 MB | none | p5 robes-pair 137 | robes-pair 143, robes-glasses 201, flutes-close 201, car-flutes 204 |
| 03 | `NOYA_03_Corporate_v2026-11-r2.pdf` | 10 | 1.36 MB | 2.29 MB | none | p1 airport-arrival-bw 133, p4 car-night 146 | airport-arrival-bw 139, car-night 143, pyramids-camels 205, table-flowers-dusk 215 |
| 04 | `NOYA_04_Brands_and_Productions_v2026-11-r2.pdf` | 12 | 2.97 MB | 5.18 MB | none | p1 pyramid-woman 119, p3 shoot-villa 138, p5 shoot-yacht 148 | pyramid-woman 117, shoot-villa 135, shoot-yacht 145 |
| 05 | `NOYA_05_Trade_and_Partners_v2026-11-r2.pdf` | 9 | 2.04 MB | 4.01 MB | none | p1 sage-table-sea 137, p3 towel-lounger-beach 137 | sage-table-sea 143, towel-lounger-beach 143, giza-guests 153 |
| 06 | `NOYA_06_Selected_Work_Q4-2026_v2026-11-r2.pdf` | 5 | 0.06 MB | 0.06 MB | none | none | none |
| 04 | `NOYA_04_Brands_and_Productions_without-references_v2026-11-r2.pdf` | 11 | 2.62 MB | 4.51 MB | none | p1 pyramid-woman 119, p3 shoot-villa 138, p5 shoot-yacht 148 | pyramid-woman 117, shoot-villa 135, shoot-yacht 145 |

Digital: A4 (595 × 842 pt), every file under 3 MB (email, WhatsApp and Drive friendly). Print: 216 × 303 mm (A4 + 3 mm bleed on every side;
trim to A4), full-resolution photographs. No print specification was supplied: printers should confirm stock, CMYK conversion and any
required crop marks; the files are RGB.

## 2. Technical inspection

| Check | Method | Result |
|---|---|---|
| Font embedding | `pdffonts` on all 14 files | **CID TrueType only, no Type 3** (r1 was entirely Type 3 because Chromium embedded the variable fonts). Static Cormorant/Jost instances now embedded with Unicode maps. |
| Text overflow and clipping | Every text frame measured against the safe area on every build | None, at the larger r2 type sizes |
| Effective image resolution | Measured per placement (cover-fit scale) | Digital: all 41 placements ≥ 119 ppi; 31 ≥ 150 and 33 ≥ 140. Eight half-page crops of landscape photographs sit at 133–138 ppi (sharp at 100% on screen; the digital set caps sources at 2400 px to keep files under 3 MB). The lowest are the 01 cover (123) and the 04 cover (119), limited by their originals (section 4). Print: listed above. |
| Links | Extracted from each PDF | mailto, WhatsApp, website and Instagram live in every closing page |
| Page numbering | Generated; cover unnumbered | Correct in all documents |
| Bleed | Print pages rendered; photographs run to the media edge, text inside the trim | Correct |
| Visual inspection | Every page rendered and reviewed; crops corrected where subjects or branding were lost (01 p3, 01 p6, 01 p8, 02 p3, 04 p12, 05 p3, 05 p4); covers and closings reviewed side by side | Pass |
| Contrast | Small print raised to 62% ink / 64% white (r1: 50% / 46%); body 84% / 86% | Legible at 100% on desktop and phone |
| Line endings | Balanced headings, pretty wrapping; split column widened to 81 mm to avoid one-word lines | Pass |
| Copy | Automated scan for clichés, superlatives, US spelling and doubled words on the regenerated copy master | Clean |
| Repetition | Image use across the collection | 40 photographs, 41 placements; one repeat (Red Sea pool, 02 and 03) |

## 3. Typography

Implemented to the brief's targets (see DESIGN_SPEC): cover 42 pt, headlines 31 pt (26 pt in split columns, 34 pt on statement pages), secondary
headlines 18–20 pt, introductions 13.5 pt, body 10.75 pt, service text 10 pt, labels 8.5 pt, small print 8.5 pt, running foot 8 pt.
No text was shrunk to fit; 01 gained a page instead.

## 4. Remaining issues

**Third-party rights (blocks external use of the full 04).** Dior and Jacquemus imagery: still no licence or permission for commercial brochure
distribution. Use `NOYA_04_Brands_and_Productions_without-references_v2026-11-r2.pdf` until permission is in writing. The r2 crops are larger
(1135 px) but come from the same Canva collage; real detail is modest (~650–900 px).

**Partner imagery (confirm, not blocking).** Saint-Tropez and Alpine property photographs are published on NOYA's website from listing or partner
material; confirm the listing/partner terms cover PDF brochures.

**Resolution for print (not blocking digital).** The 01 cover and the 04 cover are limited by their originals (~120 ppi). Higher-resolution masters
exist in Drive (VISUAL_AUDIT §4). Print versions should not go to press until those are swapped in.

**Case-study photography.** Genuine wedding photographs exist but are not used (phone quality, client monogram, no consent). Selected Work
remains text-led.

**Factual and contractual dependencies carried from the release report:** partner agreement legal review and NOYA's contracting entity (05);
courtesy note to the wedding couple (06).
