# SEO Migration Map — noyaconcierge.com
Source: live sitemap.xml + crawl, 2026-09-28. All "current" values are EXTRACTED. "Intended new URL" is PROPOSED.

Principle: every indexed URL keeps its path. Redirects only for duplicates and system pages.

| # | Current URL | Page title (nav) | Current SEO title | Current meta description | Current H1 | Intended new URL | Redirect |
|---|---|---|---|---|---|---|---|
| 1 | `/` | Home | N O Y A | Noya tailors your exclusive travel, premium accommodations, and VIP experiences across Egypt. Elevate your journey with seamless luxury and world-class service. | none (H2 "Beyond Luxury.") | `/` | NO |
| 2 | `/home` *(in sitemap, priority 1.0)* | — (duplicate of /) | N O Y A | same as / | none | `/` | **YES — 301 → /** |
| 3 | `/what-we-do` | What We Do | What We Do — NOYA Concierge | Private travel, villas, dining, access and lifestyle management, arranged by NOYA Concierge for private clients, families and corporate teams. | none (H3 "What We Do") | `/what-we-do` | NO |
| 4 | `/what-we-do-folder` *(not in sitemap; mobile nav)* | — (duplicate) | What We Do — NOYA Concierge | same as #3 | none | `/what-we-do` | **YES — 301** |
| 5 | `/bespoke-travel` | Bespoke Travel | Bespoke Travel — NOYA Concierge | Tailor-made private travel arranged end to end by NOYA Concierge: itineraries, hotels, villas, aviation and ground, with specialist execution in Egypt. | none | `/bespoke-travel` | NO |
| 6 | `/hotels-villas-and-residences` | Hotels, Villas and Residences | Hotels, Villas and Residences — NOYA Concierge | Private villas, residences and hotel access sourced and arranged by NOYA Concierge, from Courchevel to the Red Sea. | none | `/hotels-villas-and-residences` | NO |
| 7 | `/lifestyle-services` | Lifestyle Services | Lifestyle Services — NOYA Concierge | Ongoing lifestyle management from NOYA Concierge: reservations, access, logistics and everyday support for private clients. | none | `/lifestyle-services` | NO |
| 8 | `/yacht-charter-private-aviation` | Yacht Charter & Private Aviation | Yacht Charter & Private Aviation — NOYA Concierge | Yacht charter and private aviation arranged by NOYA Concierge, with vetted operators and full ground coordination. | none | `/yacht-charter-private-aviation` | NO |
| 9 | `/exclusive-access` | Exclusive Access | Exclusive Access — NOYA Concierge | **(empty)** | none | `/exclusive-access` | NO |
| 10 | `/corporate-concierge` | Corporate Concierge | Corporate Concierge — NOYA Concierge | **(empty)** | none | `/corporate-concierge` | NO |
| 11 | `/about` | About us | About us — NOYA Concierge | **(empty)** | none (H2 "About us") | `/about` | NO |
| 12 | `/contact` | Contact | Contact — NOYA Concierge | Contact NOYA Concierge for private enquiries - bespoke travel, lifestyle services, and events. Every conversation is held in confidence. | none | `/contact` | NO |
| 13 | `/membership` | Become a member | Apply for Membership — NOYA Concierge | **(empty)** | none | `/membership` | NO |
| 14 | `/privacy-policy` | Privacy Policy | Privacy Policy — NOYA Concierge | **(empty)** | Privacy Policy | `/privacy-policy` | NO |
| 15 | `/terms-conditions` | Terms & Conditions | Terms & Conditions — NOYA Concierge | **(empty)** | Terms & Conditions | `/terms-conditions` | NO |
| 16 | `/cart` *(Squarespace commerce default)* | header "0" link | not crawled | — | — | none | **YES — 301 → /** |

## Squarespace system paths to cover on cut-over (standard platform URLs, not observed as linked)
`/search`, `/config`, `/s/*` (file storage), `/blog?format=rss` — 301 to `/` or return 410. Confirm in Squarespace analytics / Google Search Console before cut-over whether any are receiving traffic.

## Required on the new build (PROPOSED)
1. Replace homepage title "N O Y A" — spaced letters are unreadable to search engines. Proposed: `NOYA Concierge — Private Concierge, Travel & Lifestyle Management`.
2. Write meta descriptions for the 6 empty pages (#9–11, #13–15).
3. One real H1 per page (currently no H1 on 13 of 15 content pages).
4. Homepage meta says "across Egypt" while the site positions globally — decide (see audit, CEO decision 1).
5. Unique OG images per page (all pages share one: `Beyond Luxury.-2 2.jpg`).
6. New sitemap.xml without `/home`; canonical tags on every page; `Organization` + `LocalBusiness` JSON-LD.
7. Image URLs: Squarespace image URLs are not indexed as pages but Google Images may hold them; low priority, no redirect needed.
8. New pages (proposed in architecture) get new URLs — no redirect implications.

## Pre-cut-over checklist
- Export Search Console "Pages" and "Links" reports (needs Adam's GSC access) to catch any external backlinks to unlisted URLs.
- Keep DNS/SSL cut-over and redirects in the same deploy.
- Resubmit sitemap on launch day; monitor 404s for 30 days.
