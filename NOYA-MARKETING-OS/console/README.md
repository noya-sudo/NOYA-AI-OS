# Marketing Console (Phase 1, not built)

A static site, same pattern as `hq.noyaconcierge.com`:
- Cloudflare static assets, no server, no secrets;
- the Supabase publishable key plus the signed-in user's token;
- every read and write goes through `api.*` functions.

Proposed address: `marketing.noyaconcierge.com` (to be confirmed).

| Screen | Phase | Purpose |
|---|---|---|
| Kill switch | 1 | Every control's state; **Halt everything** (one tap); arm (owner, typed phrase) |
| Audit | 1 | Filterable log; each review card links to its history |
| Review queue | 4 | Rendered previews, Brand Guardian results, Approve / Request changes / Reject, then Run now / Schedule |
| Calendar | 4 | Planned, approved, scheduled, published |
| Intelligence | 3 | Signals with confidence and evidence; research briefs |
| Assets | 2 | Library with rights status and expiries |
| Leads | 6 | Inbound, qualification, hand-offs and HQ outcomes |
| Paid | 8 | Plans, live entities, spend against caps, Pause all |
| Analytics | 5 | Channel, pillar and post performance; cost per qualified enquiry |

Design: NOYA's tokens, copied from HQ Studio (navy `#061422`, paper `#F7F7F7`, Cormorant Garamond for display, Jost for text),
mobile-first for the review queue.
