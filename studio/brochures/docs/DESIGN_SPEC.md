# NOYA Brochure Collection · Typography & Editorial Design Specification (r2)

*Applies to all six A4 publications. Source of truth: `studio/brochures/brochure.css` (tokens on `:root`) and the layouts in `build.mjs`.*

## 1. Typefaces

| Role | Family | Instances embedded | Why |
|---|---|---|---|
| Display, headlines, introductions, numerals, captions in italic | **Cormorant Garamond** | 300, 400, 500; italic 300, 400 | NOYA's editorial voice. Kept. |
| Text, labels, tables, running feet | **Jost** | 350, 450, 550 | Clean geometric sans with good small-size legibility. Kept. |

Both are SIL Open Font Licence. r2 embeds **static instances** generated from the variable fonts (`fonts/*.ttf`). Chromium wrote the
variable fonts as Type 3, which some prepress systems rasterise or reject; the static instances embed as **CID TrueType** with Unicode maps
(text stays searchable and copyable).

## 2. Type scale (A4)

| Element | Font | Size | Leading | Tracking | Colour (paper / navy) |
|---|---|---|---|---|---|
| Cover title | Cormorant 300 | 42 pt | 1.07 | +0.005 em | white |
| Cover kicker | Jost 450 caps | 8.5 pt | — | 0.26 em | white 86% |
| Cover line | Cormorant 300 italic | 15 pt | 1.38 | — | white 86% |
| Page headline | Cormorant 300 | 31 pt (statement pages 34 pt; split pages 26 pt) | 1.07 | −0.005 em | ink / white |
| Secondary headline (cards, entries) | Cormorant 400 | 18–20 pt | 1.15 | — | ink |
| Introduction | Cormorant 400 | 13.5 pt (13 pt in split columns) | 1.42 | — | ink 84% / white 86% |
| Pull quote | Cormorant 300 italic | 19 pt | 1.30 | — | ink / white |
| Body | Jost 350 | 10.75 pt | 1.56 | — | ink 84% / white 86% |
| Service descriptions, lists, tables | Jost 350 | 10 pt | 1.45–1.52 | — | ink 84% / white 86% |
| Item heads | Jost 550 caps | 8.5 pt | — | 0.16 em | ink / white |
| Eyebrows | Jost 450 caps, 10 mm rule | 8.5 pt | — | 0.22 em | ink 62% / white 64% |
| Small print, notes | Jost 350 | 8.5 pt | 1.50 | — | ink 62% / white 64% |
| Running foot | Jost 450 caps + Cormorant italic numeral | 8 pt / 11.5 pt | — | 0.20 em | ink 62% / white 64% |
| Contact values | Cormorant 400 | 14.5 pt | — | — | white |

Rules: headings and introductions use balanced wrapping; body, lists and notes use "pretty" wrapping (no single-word last lines where
avoidable). Lining proportional numerals throughout. No text is ever reduced to fit: copy, composition or page count changes instead
(r2 added a page to 01 rather than shrink the "How we work" content).

## 3. Colour

| Token | Value | Use |
|---|---|---|
| Navy | `#061422` | NOYA navy: navy pages, overlays, ink |
| Navy 2 | `#0C2136` | Boxes on navy |
| Paper | `#F7F6F3` | Page white (a fraction warmer than r1's `#F7F7F7`, to sit better beside photography) |
| Tint | `#ECEAE5` | Boxes on paper |
| Ink 84% / 62% | `rgba(6,20,34,.84)` / `.62` | Body / small print (r1 used .74 / .50: small print was too faint) |
| White 86% / 64% | `rgba(247,246,243,.86)` / `.64` | Body / small print on navy |
| Rules | 18% ink, 22% white | Hairlines (0.25 mm) |

No gold, no gradients other than photographic overlays, no accent colour.

## 4. Page geometry

A4 trim 210 × 297 mm. Margins: 22 mm sides, 26 mm top, 25 mm above the running foot (foot at 12 mm). Print files add **3 mm bleed** on
every side (216 × 303 mm media); full-bleed photographs extend into it and every other position is offset by the bleed.

## 5. Layout family

| Layout | Use | Notes |
|---|---|---|
| **Cover** | One photograph, logo, kicker, title, line | Overlay limited to the top 24% (logo) and bottom 58% (title). No covers without photography except Selected Work. |
| **Statement** | Navy, one idea, no photo | Opening pages after the cover. |
| **Split** | Vertical photograph (96 mm) + text column (81 mm) | Running foot moves to the text side. |
| **Band** | Photograph across the top (78–118 mm) + content | Service pages. |
| **Cinematic** | Full-bleed photograph, minimal text over a soft gradient | International chapter (01); used sparingly. |
| **Text** | Editorial page, optically centred | Structured service, process and commercial pages. |
| **Closing** | Brand photograph (104–112 mm) fading to navy, logo, invitation, contact block | One different photograph per publication. |

## 6. Photography

- Selected for what it communicates (experience, place, hospitality detail, capability, discretion), not to fill space.
- One photograph per role per collection where possible; repetition across documents is limited to audiences that never receive both.
- No image is placed beside a case study unless it documents that engagement (none exists for the Cairo wedding, so Selected Work is text-led).
- SAGE and other event imagery is used as hospitality imagery only, never captioned as a client event.
- Effective resolution is measured on every build: digital ≥ 150 ppi at placed size is the target (≥ 110 acceptable for screen); print
  target 300 ppi. Below-target placements are listed in the QC report with the higher-resolution source to obtain.
- Photographs are not stretched, sharpened or upscaled. Overlays are gradients, never flat darkening of the whole frame.

## 7. Editorial rules

Understated, specific, personal. Describe what NOYA does and the practical difference; no superlatives, no "seamless", "exclusive",
"curated", "unforgettable". Each brochure is written for its buyer; shared caveats (licensed operators, availability, terms) are defined once
in `content/shared.mjs`.
