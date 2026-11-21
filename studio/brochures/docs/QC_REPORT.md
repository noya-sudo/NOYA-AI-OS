# NOYA Brochure Collection · Quality-Control Report

*Final build 2026-11-21 13:12 UTC · draft markers ON · `node studio/brochures/build.mjs`*

## 1. Build results

| # | File | Pages | Size | Overflow / clipping | Fonts embedded | Links |
|---|---|---|---|---|---|---|
| 01 | `NOYA_01_Concierge_Overview_v2026-11.pdf` | 10 | 1.72 MB | none | Cormorant Garamond, Jost | 4 live |
| 02 | `NOYA_02_Private_Desk_v2026-11.pdf` | 9 | 1.07 MB | none | Cormorant Garamond, Jost | 4 live |
| 03 | `NOYA_03_Corporate_v2026-11.pdf` | 10 | 1.35 MB | none | Cormorant Garamond, Jost | 4 live |
| 04 | `NOYA_04_Brands_and_Productions_v2026-11.pdf` | 11 | 1.71 MB | none | Cormorant Garamond, Jost | 4 live |
| 05 | `NOYA_05_Trade_and_Partners_v2026-11.pdf` | 9 | 1.4 MB | none | Cormorant Garamond, Jost | 4 live |
| 06 | `NOYA_06_Selected_Work_Q4-2026.pdf` | 5 | 0.26 MB | none | Cormorant Garamond, Jost | 4 live |

Every PDF embeds its fonts and photos (self-contained), is A4 portrait for screen and phone reading, and is under 2 MB, so it
can be emailed or sent on WhatsApp. Contact links tested in every file: `mailto:noya@noyaconcierge.com`, `https://wa.me/447864569006`,
`https://noyaconcierge.com/`, `https://www.instagram.com/noyaconcierge/`.

## 2. Checks performed

| Check | Method | Result |
|---|---|---|
| Text overflow and clipping | Automatic: every text frame measured against the safe area above the running foot, every build | Pass, all 54 pages |
| Visual inspection | Every rendered page reviewed as page images, twice (author + independent reviewer), dense pages at full size | Pass after the fixes below |
| Independent proofread | Separate reviewer with no access to the author's reasoning: spelling, grammar, British English, repetition, tone, claims, consistency, visuals | 30 findings; all MUST FIX items resolved, SHOULD FIX items resolved or consciously kept (section 4) |
| Banned language | Scan for: passport, unforgettable, elevate, seamless, unparalleled, world-class, gateway, extraordinary, exclusive, leading, premier, fastest, bespoke, curated, iconic, effortless, 24/7, guarantee | None in print (only "do not offer guaranteed allocations") |
| British spelling | Scan for -ize, color, center, program, traveler | None |
| Ligatures | PDF text extraction checked for broken fi/ff/fl | Clean (old brochures' "eff iciently" defect gone) |
| Page numbering | Generated; cover unnumbered, pages 02 onward | Correct in all six |
| Contact block | One generated block, identical everywhere | Consistent |
| Colour and contrast | Navy #061422 / off-white; small print at 46% white on navy and 50% ink on paper | Legible on screen; the navy table on 05 p7 was invisible in the first build and is fixed |
| Running feet | Moved off photographs onto the text side of split pages | Fixed (were unreadable on 01 p8, 04 p3) |
| Line breaks | Balanced headings, no one-word last lines (CSS text-wrap balance / pretty) | Fixed across the set |
| Image resolution | Covers and half pages use ≥ 960 px sources; low-resolution images limited to small slots | Pass; `car-headrest` (615 px) used at half-page size on 03 p4 and 05 p3 is acceptable on screen, too soft for print |
| Image rights | Each photo checked against `assets.json`; EXCLUDED photos refused by the build | See section 5 |
| Claims | Every factual claim mapped in `EVIDENCE_REGISTER.md` | Unsupported claims removed; open items flagged on the pages |

## 3. Defects found and fixed in QC

- **Corporate cover showed "THE RITZ LONDON" and a legible number plate.** Image excluded; replaced. A second street image was cropped
  to remove a hotel sign (Bulgari).
- "Destination management" in Corporate's kicker and closing, and "destination business" in 04, read as a licensed DMC → reworded.
- 04: "filming permissions … issued … under their licences" was wrong: permissions are issued by the authorities → corrected in the
  table and the footnote.
- 04: "Celebrity and VIP guest attendance" under Sourcing implied booking talent → "VIP guest attendance, coordinated through representatives".
- 06: removed the promise of a Q1 edition and the mention of client referees (none confirmed); title now "Only work we can evidence."
- Eyebrows that read as client lists ("Who we look after", "Who we work with") → "Who the Desk is for", "Sectors we support", "Partners we support".
- "Most begin with an introduction from an existing client" → "Many begin with an introduction."; "Demand for Egypt is growing" → "Interest in Egypt has grown…".
- 05 heading "White-label or co-branded" did not match its text → "White-label or NOYA-branded"; 05 p7 renamed "Responsibilities, in writing."
- 01 p7 cross-references were invisible on navy → fixed. Empty label in the Corporate copy master → "Alongside your team".
- Repetition reduced: "when plans change" (6 uses → 2), duplicate provenance sentence, "as briefly as you like", repeated photos within a document.
- Puffery removed: "best hotels", "great hotels", "Everything your client needs", "Every cabin and every route", "Ideal for" ×4.
- Clarity: "A particular watch reference"; "Short-notice requests met wherever possible"; "players" → "athletes"; "Chairmen" → "Chairs"; the
  04 fees sentence split in two.

## 4. Reviewer suggestions consciously not taken

- *"Egypt rewards organisations that arrive well prepared and punishes those that do not."* (03 p5). Reviewer found it harsh. Kept: it is
  NOYA's own distinctive line and the brief asked to preserve those; it speaks to the buyer's risk, not against Egypt.
- *"A service built around people, not bookings."* (02 p2) and *"Luxury is not simply about access…"* (01 p2): kept as NOYA's signature
  lines; other rhetorical contrasts were removed so these stand alone.
- Two-part titles ("Clear scope. Clear costs.", "One country. Many looks."): kept where they are existing NOYA lines.
- Vehicle marques (Maybach seat emblem, Bentley grille, Rolls-Royce): incidental to chauffeur photography, not retouched; listed for sign-off.

## 5. Images printed, with status

| Key | Status | Uses | Where |
|---|---|---|---|
| `beach-dinner` | NOYA CONTENT | 3 | 01 p6, 03 p6, 05 p1 |
| `car-headrest` | NOYA CONTENT | 1 | 03 p4 |
| `car-night` | APPROVAL REQUIRED | 3 | 01 p3, 02 p3, 03 p2 |
| `car-street` | APPROVAL REQUIRED | 1 | 03 p1 |
| `champagne-car` | NOYA CONTENT | 5 | 01 p5, 01 p7, 02 p9, 04 p7, 05 p3 |
| `pyramid-woman` | APPROVAL REQUIRED | 5 | 01 p8, 03 p5, 04 p1, 04 p6, 05 p4 |
| `pyramids-camels` | APPROVAL REQUIRED | 2 | 03 p5, 04 p6 |
| `robe-pool` | NOYA CONTENT | 3 | 01 p10, 02 p1, 04 p7 |
| `robes-two` | NOYA CONTENT | 4 | 01 p7, 02 p5, 04 p11, 05 p8 |
| `shoot-villa` | APPROVAL REQUIRED | 1 | 04 p3 |
| `shoot-yacht` | APPROVAL REQUIRED | 1 | 04 p7 |
| `terrace-sea` | APPROVAL REQUIRED | 1 | 04 p4 |
| `towels-daybed` | NOYA CONTENT | 4 | 01 p7, 02 p4, 05 p4, 05 p8 |
| `yacht-tray-tall` | NOYA CONTENT | 2 | 01 p1, 05 p9 |
| `yacht-tray-wide` | NOYA CONTENT | 4 | 01 p4, 03 p10, 04 p6, 05 p4 |

## 6. Open approvals before release (red tags in the draft PDFs)

| Doc | Page: item |
|---|---|
| 01 | p3: photo rights (car image) |
| 01 | p6: case study (client courtesy approval) |
| 01 | p8: photo rights (Giza image) |
| 01 | p9: international destinations list |
| 02 | p3: photo rights (car image) |
| 02 | p6: sourcing supplier capability |
| 02 | p8: access wording |
| 03 | p1: photo rights (car image) |
| 03 | p2: photo rights (car image) |
| 03 | p5: photo rights (pyramids image) |
| 03 | p7: engagement model |
| 04 | p1: photo rights (cover image) |
| 04 | p3: photo rights (behind-the-scenes image) |
| 04 | p4: photo rights (terrace image) |
| 04 | p6: photo rights (Giza image) |
| 04 | p7: photo rights (behind-the-scenes image) |
| 05 | p4: photo rights (Giza image) |
| 05 | p5: partner terms |
| 05 | p6: partner terms |
| 06 | p3: case study (client courtesy approval) |

Plus, collection-wide: **Instagram handle** (@noyaconcierge vs @noya__egy, evidence register F5), and the **photographer and releases** for
NOYA's branded shoots before any print run.

## 7. Release procedure

1. Adam clears or rejects each open approval (record it in `EVIDENCE_REGISTER.md › Sign-off log`). A rejected item is cut from the content module.
2. `DRAFT=0 node studio/brochures/build.mjs` to export clean PDFs (no red tags); re-run the visual check.
3. Upload the final PDFs to Drive beside the drafts; send only the brochure for the buyer in front of you.
4. Print versions: no print specification was supplied. For print, request bleed (3 mm), CMYK conversion and higher-resolution originals
   of the branded shoots; the current files are optimised for screen.

## 8. Files

- Editable source: `studio/brochures/` (content, layout, build, registers) on branch `claude/lucid-gates-gw5yik`.
- Draft PDFs and the internal evidence register: private Drive folder *NOYA Brochure Collection 2026-11 (DRAFT, not for
  distribution)* (Drive 18KATRdDhjG9Et6Aa-4pCabqzqtNZuPXI), restricted, not shared.
- The prepared image set (27 JPEGs, 3.9 MB zip) was **not** uploaded: it exceeds the Drive connector's per-file limit from this session.
  It can be rebuilt from the 2026 PDFs (see ASSET_REGISTER) or uploaded in parts.
- Previous edition: the original Canva designs are unchanged.
