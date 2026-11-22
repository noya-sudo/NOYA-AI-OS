# NOYA Brochure Collection · Quality-Control Report

*Final publication build 2026-11-22 15:27 UTC · `DRAFT=0` · no approval markers in any file.*

## 1. Final build results

| # | File | Pages | Size | Overflow / clipping | Links |
|---|---|---|---|---|---|
| 01 | `NOYA_01_Concierge_Overview_v2026-11.pdf` | 10 | 1.72 MB | none | 4 live |
| 02 | `NOYA_02_Private_Desk_v2026-11.pdf` | 9 | 1.06 MB | none | 4 live |
| 03 | `NOYA_03_Corporate_v2026-11.pdf` | 10 | 1.34 MB | none | 4 live |
| 04 | `NOYA_04_Brands_and_Productions_v2026-11.pdf` | 12 | 1.91 MB | none | 4 live |
| 05 | `NOYA_05_Trade_and_Partners_v2026-11.pdf` | 9 | 1.39 MB | none | 4 live |
| 06 | `NOYA_06_Selected_Work_Q4-2026.pdf` | 5 | 0.29 MB | none | 4 live |
| 04 | `NOYA_04_Brands_and_Productions_v2026-11_without-references.pdf` | 11 | 1.69 MB | none | 4 live |

All files embed their fonts and photos, are A4 portrait, and are 2 MB or less (email and WhatsApp friendly). Contact links in every file:
`mailto:noya@noyaconcierge.com`, `https://wa.me/447864569006`, `https://noyaconcierge.com/`, `https://www.instagram.com/noyaconcierge/`.
Final pages were reviewed rendered at full resolution (`studio/out/brochures/final/pages/`).

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

## 5. Images

All photographs approved by Adam on 22 Nov 2026 (see ASSET_REGISTER). The two creative reference panels in 04 are third-party material: see
RELEASE_REPORT for the dependency.

## 6. Open approvals

None in the copy. Remaining external dependencies are listed in `RELEASE_REPORT.md`.

## 7. Release procedure

1. Approvals recorded in `EVIDENCE_REGISTER.md › Sign-off log` (22 Nov 2026).
2. Clean PDFs exported with `DRAFT=0` (and `OMIT_REFS=1` for 04 without references); final pages reviewed at full resolution.
3. Publication copies are in their own Drive folder, separate from drafts and evidence. Send only the brochure for the buyer in front of you.
4. Print versions: no print specification was supplied. For print, request bleed (3 mm), CMYK conversion and higher-resolution originals
   of the branded shoots; the current files are optimised for screen.

## 8. Files

- Editable source: `studio/brochures/` on branch `claude/lucid-gates-gw5yik`.
- **Publication copies (final):** Drive folder *NOYA Brochure Collection 2026-11 · Publication copies (FINAL, not yet sent)*
  (1LIDD3nbadwZDB0PCqdm_9mzP8hmEpTA9), restricted; locally `studio/out/brochures/final/`.
- **Internal (drafts, evidence, legal):** Drive folder *NOYA Brochure Collection 2026-11 (DRAFT, not for distribution)*
  (18KATRdDhjG9Et6Aa-4pCabqzqtNZuPXI): the 21 Nov draft PDFs, the internal evidence register and the partner agreement draft.
- The prepared image set is not in Drive (over the connector's per-file limit); it is rebuilt from the 2026 PDFs (ASSET_REGISTER).
- Previous edition: the original Canva designs are unchanged.
