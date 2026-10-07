# Live n8n code — 7 Oct 2026

Exact copies of the department Code nodes published on 7 Oct 2026. n8n is the source of truth; these
files are the reviewed record. They cover search efficiency and Instagram discovery.

- `0x_generate_search_queries.js` (02, 03, 04, 06, 07):
  - each run takes a rotating slice of a larger query bank, using `RUN_IDX = floor(now / 6 h)` and
    `rotateSlice(list, n, salt)`. Consecutive runs search different queries and none repeats within
    the bank;
  - this cuts discovery searches by about 45% and gives about 1.5× more unique coverage;
  - 03 and 07 add partnership banks: boutique hotel groups, villa portfolios, serviced residences,
    branded residences, aparthotels, advisor networks, concierge firms, private clubs and DMCs;
  - 02 adds media, podcast and production banks.
- `0x_normalise_results.js` (02, 03, 04, 07): Instagram discovery.
  - A public `instagram.com/<handle>` result counts as a candidate only when the profile text
    exposes a business route: an email, a website, a booking or contact route, a named founder, a
    partnerships contact or a management company.
  - The source URL is kept, and nothing is inferred beyond the profile text.
  - Emails are stripped before the website match, so `gmail.com` is never taken for a website.
- `03_merge_and_cap_candidates.js` and `07_merge_and_cap_candidates.js`:
  - the research cap is raised from 4 to 6 accounts per run;
  - branded residences are no longer rejected.
- `02_finalise_qualification.js`: agencies, production companies and media are valid types for the
  brand lane. They were being rejected as `WRONG_MISSION_TYPE`.
