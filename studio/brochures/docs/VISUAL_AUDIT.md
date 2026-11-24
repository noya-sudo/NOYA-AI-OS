# NOYA Visual Asset Audit & Shortlist (r2 · 24 Nov 2026)

## 1. What was reviewed

| Source | Reviewed | Access | Outcome |
|---|---|---|---|
| The four 2026 brochures | All embedded images (pdfimages) | Local | 27 images; most only 600–1400 px. Used where no better original exists. |
| NOYA website library | 66 photographs (every page scraped; numbered `nw-` series probed 01–40) | Downloaded (network access added for this purpose) | **The core of r2**: 39 new high-resolution photographs (1128–2560 px), including originals of images the brochures held at low resolution. |
| Canva | 32 designs, 343 pages reviewed; 27 shortlisted pages exported at 2400 px | Exported | Giza hospitality photographs (brand content), the Dior/Jacquemus panels at ~2.5× the previous size, and phone photographs from the Cairo wedding. Canva exports are upscaled; real detail ~900–1300 px. |
| Google Drive | Metadata search (images, wedding, brand trip, SAGE, Giza, campaign) | Metadata only; this session cannot download from Drive | Camera originals and PNG masters located (see section 4). Not used yet. |
| Instagram | — | Not reachable from this environment | Not reviewed. |

## 2. Shortlist: strongest photographs and their roles

| Photograph | Why it earns its place | Role in r2 |
|---|---|---|
| `yacht-tray-tall` | The brand in one frame: NOYA towels, Red Sea, hospitality | 01 cover (kept per brief) |
| `airport-arrival-bw` | Executive travel without luxury clichés; black and white reads corporate | 03 cover (replaces the building-and-car image) |
| `robes-glasses` | Private, intimate, warm | 02 cover |
| `pyramid-woman` | Egypt as a creative setting | 04 cover (kept) |
| `sage-table-sea` | NOYA-branded dining by the sea (high-res original of the r1 cover) | 05 cover |
| `giza-terrace-lunch`, `giza-toast`, `giza-guests` | Real hospitality at Giza, not stock monuments | 01 Egypt, 04 locations, 05 destinations |
| `beach-dinner-hd`, `sage-table-row`, `sage-long-table` | Occasions and hosting at scale | 01 occasions, 03 hospitality, 04 brand programmes |
| `sage-fire`, `sage-carving`, `sage-grill`, `sage-plating`, `sage-dishes` | Craft, service, production of an experience | 04 project types and closing, 01 organisations |
| `towel-chair-sea`, `towel-lounger-beach`, `loungers-tray`, `loungers-garden`, `tender-picnic` | Branded detail and attention to the guest | 01, 02, 05 |
| `robe-terrace`, `robes-pair`, `flutes-close`, `car-flutes` | Personal service and privacy | 01 closing, 02 |
| `wembley-dusk` | Event access, the "seats for the final" line made visible | 01 lifestyle |
| `jet-dusk` | International movement | 03 closing (international capability) |
| `alpine-chalet`, `st-tropez-bay` | International identity beyond Egypt | 01 stays, 01 worldwide |
| `table-flowers-dusk`, `car-night` | Organisational care, executive arrivals | 03 |
| `shoot-villa`, `shoot-yacht`, `yacht-guests`, `yacht-pour` | Production environments and talent hospitality | 04 |
| `ref-dior-giza`, `ref-jacquemus-egypt` | Independent creative references | 04 p7 (third-party; permission pending) |

## 3. Deliberately not used

- **Cairo wedding photographs** (Canva DAG3MlX-gGg p01–p05): genuine documentary images of the engagement, but phone quality, a NOYA
  overlay already baked in, and the couple's monogram and names visible; no client consent. Selected Work therefore stays text-led.
  With the couple's written consent and an untouched original, p02 (NOYA welcome sign) or p04 (reception table) could illustrate entry 01.
- Third-party events (drone show, Keinemusik), venue-branded photographs (Pier 88 boat), hotel/stock collages, phone screenshots.
- Villa-agency Mykonos photographs and other property imagery where NOYA's own photography does the job better.
- "Lifestyle" images used only to fill space: r1's drinks-in-a-car for private sourcing is replaced by a typographic treatment (02) and
  event access (01), because no authentic sourcing photography exists and none is staged.

## 4. Higher-resolution originals to obtain (Drive)

| Drive location | Contents | Would upgrade |
|---|---|---|
| *Noya Website › Branded content* (1aBcy0EOMpQLLtO3dMbg57m0nL9Ze1ovJ) | 37 PNG masters, 12–37 MB | Every branded shot; in particular the 01 cover (`yacht-tray-tall`, 123 ppi digital / 119 print) |
| *NOYA Website Masters (approved)* (1nAHJPHF4KBOJic76C06vIjnZuUqeuG_U) | 14 full-resolution JPGs (SAGE, "edge") | SAGE and Red Sea set for print at 300 ppi |
| *Pier 88 x Noya* (1ohwZ0fmARID1oKRW9CiyHtP26tpOlthm) | ~150 Sony camera JPG + RAW (El Gouna, Pyramid Hills) | New hospitality and Egypt material; not yet reviewed visually |
| `branded-content-16` (14TUlMnLxTSsspBcN0qteNqqyVzJrffbc) | 1920×2400 web master of the yacht-tray scene | 01 cover |

To use them, download the files to this repository's `studio/brochures/images_print/` (same key names), or start a session in the
`noya-marketing-os` environment, which holds a Drive read token, and rebuild with `VARIANT=print`.
