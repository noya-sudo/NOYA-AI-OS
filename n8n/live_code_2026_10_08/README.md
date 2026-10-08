# Live n8n code — 8 Oct 2026 (volume through the email-first engine)

Exact copies of the department Code nodes published on 8 Oct 2026, verified byte-for-byte against n8n after
publishing. n8n is the source of truth; these files are the reviewed record.

- `02_generate_search_queries.js` (Brands & Production) — two new rotated banks:
  - brand signals: fashion, jewellery, clothing, beauty, watches, automotive and luxury lifestyle brands running
    destination campaigns, fashion and jewellery shoots, creator trips, international campaigns, GCC / MENA expansion
    and campaign production abroad;
  - agencies: marketing, PR, creative and influencer agencies, and production companies.
  - Before this, the agency and production lists were never searched: the mission is BRAND, and only the BRAND list
    and the extra banks ran.
- `04_generate_search_queries.js` (Weddings) — planners already running international multi-day weddings and UHNW
  celebrations.
- `07_generate_search_queries.js` (Travel & Concierge, Private Founders) — boutique travel firms, luxury travel
  designers, lifestyle management, DMCs; founder clubs, business and executive communities, members clubs and
  family-office networks that run retreats, dinners, trips and off-sites.
- `03_generate_search_queries.js` (Hospitality) — hotels, villas, resorts and residences open to creator stays, talent
  stays, brand shoots, production accommodation and content collaborations (the CONTENT_TALENT model, kept apart from
  preferred-stay outreach).
- `02_merge_and_cap_candidates.js`, `04_merge_and_cap_candidates.js` — the research ceiling rises from 4 to 12. Every
  Brands and Weddings run was filling exactly to 4. The live cap comes from `system_config.discovery_throttle`
  (`normal_research_cap`, 10), so it can be tuned without touching code.
- Discovery never pauses because drafts are waiting: `discovery_throttle` pauses only at a backlog of 100,000.
- Each run adds about 7–9 searches (Serper), and research uses Gemini Flash-Lite. The old Hunter nodes in the
  departments stay disabled, so more research spends no Hunter credits.
