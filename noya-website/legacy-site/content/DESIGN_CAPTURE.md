# Legacy Design Capture — noyaconcierge.com (Squarespace 7.1, Fluid Engine)
Captured 2026-09-28. Source: Firecrawl branding extraction + 12 full-page screenshots in `../screenshots/`.
Values marked **(measured)** come from computed styles; **(observed)** from screenshots.

## Colour
| Token | Value | Use |
|---|---|---|
| Background / primary | `#061422` (measured) | Every section — very dark navy, near-black |
| Secondary | `#313D48` (measured) | Secondary surfaces |
| Muted / link / button border | `#4E5862` (measured) | Secondary button outline, links |
| Text | `#F7F7F7` (measured) | All body and headings |
| Primary button | white fill `#FFFFFF`, dark text (observed on hero, forms) | "Make an Enquiry", "Submit" |

Single dark theme sitewide. No accent colour. No light sections.

## Typography
| Role | Font | Notes |
|---|---|---|
| Headings | **Libre Baskerville** (serif) (measured) | H2 ≈ 44px desktop, sentence/title case, regular weight |
| Body / UI | **Inter** (measured) | Body ≈ 17px; nav and button labels uppercase with tracking |
| Other | Almarai (loaded, role unclear — likely unused Arabic-capable fallback) | |

## Components (observed)
- **Header:** logo mark left (crossed-keys icon, see logo assets) · nav centred-left (HOME · WHAT WE DO ▾ · CORPORATE CONCIERGE · ABOUT US · CONTACT, uppercase serif-small) · outlined pill "Become a member" right.
- **Buttons:** fully rounded pills (radius 300px). Primary = white fill. Secondary = transparent with thin light border, uppercase tracked label (e.g. EXPLORE PRIVATE TRAVEL).
- **Floating button:** "• SPEAK TO NOYA" pill, fixed right-middle on every page; opens a "Private enquiry / Speak to NOYA" popup.
- **Cards:** square-crop image, serif title, 2–4 lines body, outlined pill CTA. Presented in horizontal carousels with arrow controls ("Item 1 of N").
- **Hero:** split layout — text left, image right (full-bleed to edge) on most pages.
- **Feature blocks:** heading + 2 paragraphs left, 2×2 / 3-image mosaic right, followed by full-width scrolling gallery strip (Hotels page).
- **Forms:** underline-only inputs (no boxes, radius 0), small "(required)" labels, white pill Submit. Centred, ~40% width.
- **FAQ:** accordion with "+" icons and hairline dividers, heading left / list right.
- **Footer:** logo mark left · "Explore" column · "Follow us" column (Instagram only). Explore links What We Do / About Us / Corporate Concierge / Contact are styled as underlined text but are NOT hyperlinks.
- **Image treatment:** straight corners (one exception: About image has rounded corners), no filters, no overlays except a dark overlay on the First/Business Class banner. Mixed quality: many uploads are screenshots.
- **Spacing:** base unit ≈ 12px (measured); generous vertical section padding (~120–160px desktop).

## Mobile (observed, 360px)
- Logo centred, hamburger right; nav collapses into full-screen menu with "What We Do" as a folder (URL `/what-we-do-folder`).
- Hero image stacks above text; buttons become full-width pills.
- Carousels become single-card swipe with arrow buttons.
- Floating "Speak to NOYA" persists and overlaps content.

## Brand assets
- **Logo:** crossed-keys mark (icon only in header). Wordmark "NOYA CONCIERGE" appears on physical goods in photography (towels, robes, business cards) — no vector wordmark found on the site.
- Header logo files are named `Screenshot 2026-01-15 at 19.54.04.png` — i.e. a screenshot, not a vector. **A clean SVG master must be sourced from the brand files.**
- Footer logo is served from a different Squarespace site (`696944e5…`); it failed to render in one of two captures.

## What to keep for the rebuild
Keep: dark navy + off-white palette, Libre Baskerville/Inter pairing (or an upgraded serif), restrained layout, pill CTAs, "Speak to NOYA" private-enquiry pattern, underline forms.
Drop: carousels for primary service navigation, screenshot-grade imagery, duplicated hero images, unlinked footer text.
