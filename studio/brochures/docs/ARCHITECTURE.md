# NOYA Publication Architecture & Positioning

*Edition 2026-11. Approved strategic direction; this document records how it is expressed in the collection.*

## Positioning

**NOYA is an independent concierge and lifestyle management business with international reach and particular expertise in Egypt.**
Its advantage is the combination of hospitality judgement, local operating knowledge and personal coordination: one accountable
person who knows the client, the place and the people to call.

NOYA is **not** positioned as a travel agency, tour operator, DMC, events company, talent agency or luxury reseller. Each of those is
a service NOYA coordinates within the concierge proposition. Every document states NOYA's role against licensed operators.

**One sentence, used consistently:** *One trusted point of contact for travel, hospitality and private life. Expert in Egypt. Arranging worldwide.*

## The collection

| # | Publication | Buyer | Job it does | Pages | Sent when |
|---|---|---|---|---|---|
| 01 | **NOYA Concierge** (flagship) | Private clients, introductions, partners, general prospects | What NOYA is, why clients choose it, the full range once, then routing to 02–05 | 11 | Anyone asks "what do you do?" |
| 02 | **NOYA Private Desk** | Private clients, families, executives, athletes, public figures | A dedicated relationship: travel, lifestyle, family, relocation, **private sourcing**; access *by introduction or application* | 9 | A private individual or their office enquires |
| 03 | **NOYA Corporate** | Companies, executive offices, family offices | Executive travel, delegations, hospitality, Egypt DMC capability; **engagement model** (account / retained / project) | 10 | A company or EA enquires |
| 04 | **NOYA Brands & Productions** | Luxury brands, agencies, PR, production, talent managers | Brand experiences, talent and creator sourcing, locations and logistics; creative references (Dior, Jacquemus); **who does what**; commercial scope | 12 (11 without references) | An agency, brand or producer enquires |
| 05 | **NOYA Trade & Partners** | Travel advisors, concierge firms, agencies, hospitality partners | Egypt delivery partner: what we deliver, client ownership, net or commission, handover, escalation. **Replaces the Partner Guide.** | 9 | A trade partner enquires |
| 06 | **NOYA Selected Work** | Prospects at proposal stage, partners doing diligence | Evidenced, anonymised completed engagements, shown as real delivery; updated quarterly | 5 | Shared privately on request, never routinely |

**Rule of thumb:** send one brochure, the one for that buyer, never the set. Add 06 when credentials are asked for.

## How the documents divide the content (no duplication)

| Topic | Lives in | Mentioned (one line, pointing) in |
|---|---|---|
| Private sourcing | 02 (full page) | 01 |
| Relocation, family | 02 | 01 |
| Executive travel, delegations, engagement model | 03 | 01 |
| Egypt as a destination for organisations ("Egypt, handled properly") | 03 | — |
| Egypt as locations ("One country. Many looks.") | 04 | — |
| Egypt destinations for trade ("Egypt, in four chapters") | 05 | 01 (short list) |
| Talent and creators, responsibilities table | 04 | 01 |
| Net / commission / white-label | 05 | — |
| Completed work | 06 | 01 (one panel, the verified wedding) |
| Licensed-operator role statement · availability caveat · contact block | `content/shared.mjs`: identical everywhere by design | |

## Visual system

Refinement, not a rebrand: NOYA navy (#061422) and off-white, the key emblem and wordmark (now a vector, `studio/brand/logo.svg`),
Cormorant Garamond for display and Jost for text (the Studio house fonts), hairline rules instead of bullets, generous margins, and
photographs given whole half-pages or full-width bands rather than collages. Covers share one composition (photo, centred logo,
title low on the page) so the five read as a family; each has its own cover image and tone of page sequence.

## Commercial positioning rules

- No published fees, retainers, commissions or sourcing margins anywhere.
- Private Desk: access considered individually, by introduction or application; terms in writing.
- Corporate: ongoing arrangements distinguished from defined assignments; fees reflect scope, volume and availability required.
- Brands & Productions: fees follow the approved brief, delivery requirements and commercial scope; costs itemised transparently.
- Trade & Partners: net or commission, by written agreement; no unsupported response times or rates.
- Fares, rooms, venues, allocations and permissions: always "subject to availability, confirmed at booking".
- No unrestricted 24/7 promise.

## Contact and conversion

One contact block, generated centrally (`build.mjs › contactBlock`), live-linked in every PDF:
NOYA Concierge · Adam Elshazly, Founder · noya@noyaconcierge.com · WhatsApp +44 786 456 9006 · noyaconcierge.com · @noyaconcierge.
Every closing page carries an invitation tailored to its buyer, not a sales line.

## Source of truth and editing

- Copy: `studio/brochures/content/0N-*.mjs` (the copy master in `docs/COPY_MASTER.md` is generated from these).
- Layout: `studio/brochures/brochure.css`; fonts and colours from `studio/brand/brand.css`.
- Photos: `assets.json` (register) + `images/` (git-ignored).
- Build: `node studio/brochures/build.mjs` → `studio/out/brochures/*.pdf`, page previews and `build-report.json`.
- r2 build: `node studio/brochures/build.mjs` (digital) and `VARIANT=print node studio/brochures/build.mjs` (print, 3 mm bleed) →
  `studio/out/brochures/r2/`; add `OMIT_REFS=1` for 04 without the third-party reference page. Design system: `docs/DESIGN_SPEC.md`.
- The 2026 Canva designs are untouched and remain the backup of the previous edition.
