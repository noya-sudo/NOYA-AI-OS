# Proposed Site Architecture — NOYA Concierge (PROPOSAL, not built)
Phase 7. Based on CURRENT_SITE_AUDIT.md. All copy direction here is PROPOSED; nothing below is extracted content.
Rule: every existing URL keeps its slug (see SEO_MIGRATION_MAP.md). New pages are additive.

## Audiences → entry points
| Audience | Needs | Lands on |
|---|---|---|
| Private clients / HNWIs / families | Trust, discretion, fast contact | Home → Private Clients services → WhatsApp/enquiry |
| Executives & EAs / corporates | Reliability, invoicing, one point of contact | Corporate Concierge |
| Brands, PR & marketing agencies, production cos | Egypt capability, permits, talent, proof | Brand Trips & Production (NEW) |
| Travel advisors, hotels, concierge peers | Commission, rates, DMC capability | Partners (NEW) |
| Members / applicants | What membership gives | Membership |

## Sitemap
```
/                                   Home (KEEP URL)
├─ /what-we-do                      Services index (KEEP) — static grid, no carousels
│  ├─ /bespoke-travel               (KEEP) incl. First & Business Class rates
│  ├─ /hotels-villas-and-residences (KEEP) property showcases
│  ├─ /lifestyle-services           (KEEP) dining, gifting, everyday
│  ├─ /yacht-charter-private-aviation (KEEP) expanded
│  ├─ /exclusive-access             (KEEP) member-only
│  ├─ /ground-services              NEW — chauffeurs, transfers, airport meet & assist, security
│  └─ /private-events               NEW — private events, celebrations, weddings & groups
├─ /corporate-concierge             (KEEP) executives, EAs, corporate gifting, retreats
├─ /brand-trips-production          NEW — brand trips, launches, influencer/talent sourcing, shoots & permits
├─ /egypt                           NEW — Egypt hub: Cairo & Giza · Red Sea (El Gouna) · Nile (Luxor & Aswan) · North Coast
├─ /partners                        NEW — travel advisors, hotels, agencies, concierge peers (referral/commission)
├─ /about                           (KEEP) rewritten: founder, base, network
├─ /membership                      (KEEP) + inclusions
├─ /contact                         (KEEP) + WhatsApp, email, response time
├─ /journal                         LATER — destination notes & openings (only if we can publish monthly)
├─ /privacy-policy · /terms-conditions (KEEP) placeholders filled
301s: /home → /, /what-we-do-folder → /what-we-do, /cart → /
```

## Navigation (proposed)
Header: **Private Clients ▾** (the 7 service pages) · **Corporate** · **Brands & Production** · **Egypt** · About · Contact · [Apply for membership]
Persistent: "Speak to NOYA" → choice of WhatsApp or private enquiry form.
Footer: all pages linked · Partners · Instagram · email · WhatsApp · legal entity line.

## Page template (all service pages)
1. H1 + one-paragraph proposition
2. What we arrange (3–6 items, plain)
3. Selected work / destinations (owned imagery only)
4. How it works (enquiry → proposal → confirmation)
5. Enquiry form variant routed by page (private / corporate / brand)
6. Related services

## Lead capture (proposed, no new SaaS)
Forms post to one endpoint → existing NOYA CRM (Supabase) + Gmail notification via existing n8n; field `source_page` + `enquiry_type` (private / corporate / brand / partner / membership). WhatsApp click-to-chat with prefilled page context.

## Content to reuse (from inventory)
KEEP-classified sections carry over verbatim where noted; REWRITE sections keep facts only. Owned imagery prioritised; third-party and screenshot images excluded until rights are confirmed.

## Open CEO decisions (blocking final copy, not blocking build start)
1. **Egypt emphasis** — Homepage meta says "across Egypt"; site body is global. Recommendation: global brand, Egypt as named specialism (own hub + nav item).
2. **Membership** — publish tiers/fees, or keep "by application" only? Recommendation: publish inclusions, not prices.
3. **Legal entity** — name, jurisdiction, registered address, enquiries email for Privacy/Terms (urgent on current site too).
4. **Contact channels** — which WhatsApp number and email go public.
5. **Image rights** — confirm usage for Consensio chalet set (22), event imagery (10) and screenshot uploads (31), or replace.
