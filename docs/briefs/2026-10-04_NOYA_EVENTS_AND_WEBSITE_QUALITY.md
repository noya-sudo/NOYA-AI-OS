# NOYA: events and website quality (4 Oct 2026)

Prepared after the CEO's note of 4 Oct: "the website can be amazing and something out of this world for a hospitality concierge firm and lifestyle management, think long term and the quality of this. Follow MasterClass and Forbes hospitality and best events suitable for NOYA and Egypt."

It contains three things:
- research into the best events for NOYA and Egypt;
- a benchmark against MasterClass and Forbes Travel Guide;
- the risks that research turned up.

On the Private Calendar, nothing is approved or published. Approval stays with the CEO, through `hq_calendar_approve` in HQ; publishing happens in the Studio.

Labels used throughout:
- **VERIFIED:** dates confirmed on the organiser's own site or official ticketing, checked 4 Oct 2026.
- **INFERRED:** dates from press only, or a recurring fixed date.
- **ESTIMATE:** astronomical projection.
- The GBP figures in section 6 are estimates, not quotes.

## 1. The opportunity: the total solar eclipse over Luxor, 2 Aug 2027

A total solar eclipse crosses Upper Egypt on Monday 2 August 2027. NASA gives a central duration of 6 min 23 s. Near Luxor, totality lasts about six minutes, the longest on land until 2114. Forbes covered it on 16 Aug 2026, and Egypt's tourism ministry has a hosting committee (reported).

What it means for NOYA:
- It is NOYA's flagship Egypt moment of 2027.
- It suits private clients, family offices, groups, brands and press.
- It brings Nile hotels, dahabiyas, private flights, a desert viewing site and guides.
- Rooms and boats will go early. The lead time is the advantage, if NOYA secures holds now.
- August heat is above 40°C, so plan early starts, shade and air-conditioned transfers.

Source: [NASA eclipse page](https://eclipse.gsfc.nasa.gov/SEgoogle/SEgoogle2001/SE2027Aug02Tgoogle.html).

## 2. Added to the HQ radar on 4 Oct 2026

Migration: `supabase/migrations/20261004090000_private_calendar_research_candidates.sql`.

### VERIFIED, awaiting CEO approval (9)

| Event | Where | Dates | Official source | Playbook |
|---|---|---|---|---|
| Longines Global Champions Tour Cairo | Pyramids of Giza | 22–24 Oct 2026 | [gcglobalchampions.com](https://www.gcglobalchampions.com/news/lgct-2026) | Egypt sport |
| Gala de Danza at the Grand Egyptian Museum | Giza | 5 Nov 2026 | [official ticketing](https://www.ticketsmarche.com/event/gala_de_danza_8840) | Festival |
| El Gouna IGFA Red Sea Championship | El Gouna | 4–7 Feb 2027 | [igfa.org](https://igfa.org/igfa-red-sea-championship/) | Egypt sport |
| Total solar eclipse | Luxor | 2 Aug 2027 | [NASA](https://eclipse.gsfc.nasa.gov/SEgoogle/SEgoogle2001/SE2027Aug02Tgoogle.html) | Travel* |
| Sun Festival at Abu Simbel | Abu Simbel | 22 Oct 2027 | [Ministry](https://egymonuments.gov.eg/en/archaeological-sites/abu-simbel) | Travel* |
| Snow Polo World Cup | St. Moritz | 22–24 Jan 2027 | [snowpolo-stmoritz.com](https://www.snowpolo-stmoritz.com/tournament-2027/42nd-snow-polo-world-cup-st-moritz-2027/) | Travel* |
| Goodwood Festival of Speed | Chichester | 15–18 Jul 2027 | [goodwood.com](https://www.goodwood.com/grr/event-coverage/festival-of-speed/2027-fos-dates-revealed/) | Travel* |
| Ryder Cup (centenary) | Adare Manor, Ireland | 17–19 Sep 2027 (week from 13 Sep) | [rydercup.com](https://www.rydercup.com/news-media/dates-announced-for-the-2027-ryder-cup) | Travel* |
| Monaco Yacht Show | Port Hercule | 22–25 Sep 2027 (22nd by invitation) | [monacoyachtshow.com](https://www.monacoyachtshow.com/en/faq) | Travel* |

\* The enrich trigger set some of these playbooks wrongly; for example, it filed Snow Polo under the Egypt sport playbook. The correcting update is at the end of the migration. The Supabase connector held it, so paste it in the SQL editor once.

### CANDIDATE, not proposed yet (4)

- **Art Basel Qatar** (Doha, 28–30 Jan 2027) and **Frieze Abu Dhabi** (19–22 Nov 2026): held for the Gulf risk in section 4.
- **Zamna Sharm El-Sheikh** (20–22 Nov 2026): off-brand for the public calendar. Useful for villa and yacht demand that weekend.
- **Cairo Design Week** (press: 19–28 Nov 2026): the official site still shows 2025. Re-check weekly.

## 3. More options (agent-researched; dates not re-checked by hand)

**Options not added to HQ:**
- White Turf, St. Moritz: 7, 14 and 21 Feb 2027.
- Haute Couture FW 2027–28, Paris: 5–8 Jul 2027.
- Venice Architecture Biennale: 8 May–21 Nov 2027. Pair it with Cannes.
- Goodwood Revival: 17–19 Sep 2027. It clashes with the Ryder Cup.
- El Gouna Half Marathon: 21 Nov 2026.

**Gulf, held:**
- Qatar GP: 27–29 Nov 2026.
- Saudi Cup: 5–6 Feb 2027.
- AlUla: Winter at Tantora, then the Arts Festival.
- Art Dubai: 9–11 Apr 2027.
- Abu Dhabi GP 2027: 10–12 Dec, its first Sprint.

**Watch list:**

| Event | When to re-check | Note |
|---|---|---|
| LGCT Cairo 2027 | Nov–Dec 2026 | Five-year deal |
| El Gouna International squash | Jan 2027 | Usually April |
| CIB Egyptian Squash Open at the Pyramids | Apr–Jun 2027 | |
| PSA World Tour Finals | Mar 2027 | |
| Art Cairo 2027 | Dec 2026 | |
| El Gouna Beach Polo | Feb 2027 | |
| Alamein Festival 2027 | May 2027 | |
| El Gouna Film Festival, CIFF and Forever Is Now 07 | Apr–Jul 2027 | |
| Red Sea International Film Festival | Q2 2027 | Postponed to Q4 2027 |
| Pyramids concerts | Quarterly | None announced |
| Art Basel (Basel), Salzburg, Henley, the Arc, Venice Film Festival | Dec 2026–Mar 2027 | Dates not yet on organiser sites |

**Egypt seasons:**
- Coptic Christmas: 7 Jan 2027.
- Ramadan: from about 8 Feb 2027 (ESTIMATE); Eid al-Fitr about 10 Mar (ESTIMATE). Abu Simbel on 22 Feb falls inside Ramadan.
- Eid al-Adha: about 16 May 2027 (ESTIMATE). Peak Gulf family travel.
- Sham El-Nessim: 3 May 2027.
- Nile season, Red Sea winter sun and North Coast summer have no verifiable dates. Treat them as evergreen pages, not dated events.

## 4. Risks found

- **Gulf conflict.**
  - EASA's Conflict Zone Information Bulletin (CZIB-2026-07R1) rated UAE, Qatar, Bahrain and Kuwait airspace high-risk, extended to 30 Sep 2026. Check its current status before booking EU-operated private flights to the Gulf.
  - Art Dubai 2026 was postponed, and the Red Sea International Film Festival 2026 moved to Q4 2027.
  - On 3 Oct, Formula 1 re-confirmed Qatar (29 Nov) and Abu Dhabi (4–6 Dec) "as planned", calling the situation volatile.
  - The Abu Dhabi GP and the Dubai World Cup stay on the calendar. Re-check them weekly.
- **Shakira at the Pyramids:** still 28 Nov 2026 on the official ticketing. Keep it held (its date has moved once) and re-check weekly.
- **Existing calendar:** re-checked 4 Oct 2026. No dates have changed.
- **Legal entity:** the website's terms name "Adam Elshazly, trading as NOYA Concierge (sole trader)" (`noya-website/src/content/legal.ts`). Before pushing corporate clients or selling flight-inclusive trips, get UK travel-law advice on:
  - forming a company;
  - professional indemnity insurance;
  - whether ATOL or the Package Travel Regulations apply.
- **Image rights:** 16 photographs carried over from the old site have no recorded source; the list is in `noya-website/docs/IMAGE_RIGHTS.md`. This does not yet meet the 3 Oct "no rights uncertainty" rule.
- **Search Console:** the sitemap has not been submitted (go-live checklist).

## 5. Benchmark: what to take from MasterClass and Forbes Travel Guide

**MasterClass**
- **Film sells the product.** Every class has a trailer.
- **Credibility comes from real people.**
- **One promise, told in chapters.**
- **Search does the selling.** A large library of articles, each leading to one product.
- **Saying yes is easy.**

For NOYA:
- One documentary-grade film, plus trailer cut-downs.
- The founder, team and partners on camera: a hotel GM, an Egyptologist, a captain. Clients are never identifiable.
- Follow one request from the first message to the last transfer.
- Every article ends in one pre-filled enquiry, as "Plan around this event" already does.
- Make the membership offer clear.

**Forbes Travel Guide**
- **Independence.** Sponsored collections carry no stars.
- **Published standards.**
- **Yearly moments:** the Star Awards in February, the Edge List in August.
- **Badges that travel.**
- **Depth by destination.**

For NOYA:
- Disclose partner and commission relationships in editorial.
- Rewrite Membership's "NOYA standard" as commitments a client can check: reply times, suppliers already used, facts sourced and dated.
- Publish "The Egypt Season" edition of the Private Calendar every September.
- Earn proof that is NOYA's own: press, event partnerships, a hotel consortium.
- Cite Forbes Travel Guide ratings with a link and the date checked, never its logo.

## 6. Ten upgrades within the design freeze (ranked by impact against effort; GBP figures are estimates)

| # | Upgrade | Cost | Who |
|---|---|---|---|
| 1 | Fill the Egypt gap from Mar to Sep 2027 on the Private Calendar (started: section 2) | £0 | CEO approves in HQ, then publishes in the Studio |
| 2 | Arrivals shoot during El Gouna Film Festival week (15–23 Oct). It fixes the two weak photographs and the Corporate photograph. Model releases signed, faces unseen | £3–8k | Photographer |
| 3 | Trace or replace the 16 photographs with no recorded source | Staff time | Content team and CEO |
| 4 | Search markup: Organization (founder, Egypt as service area) and FAQ on What We Do. Submit the sitemap | £1–2.5k | Code (invisible) and CEO in Search Console |
| 5 | Client words, used only with written consent and anonymised (for example "Family office, Riyadh") | under £1.5k | Content team |
| 6 | Proof of hotel relationships: a consortium or brand partner programme. Name partners only with their written permission | Medium | CEO |
| 7 | "The Private Calendar, monthly" email (a policy change: nothing is sent automatically today) | £2–5k | Code and content |
| 8 | "Egypt, privately" journal: a new section built from existing patterns, so it is a CEO decision | £3–8k build, plus £400–900 per article | Code and content |
| 9 | One original film, about 3 minutes, plus cut-downs, played on click in the existing full-width band | £45–120k film, plus £15–35k photography | Film crew |
| 10 | PR, plus pitches to be official concierge for Art D'Égypte and the El Gouna and Cairo film festivals | £3–7k a month | CEO and agency |

Filming in Egypt (reported, unverified):
- Drones need Ministry of Defence approval and are banned over antiquities.
- Filming at sites needs a Ministry of Tourism and Antiquities permit.
- Route both through NOYA's licensed partners.

**Roadmap**
- **Q4 2026**
  - Upgrades 1–5.
  - Film brief, director and permits; a location visit during Forever Is Now 06.
  - Decide on the journal.
  - Start collecting client consent.
  - Get the legal advice in section 4.
- **Q1 2027**
  - Main shoot: Cairo and the Grand Egyptian Museum, Aswan, the Abu Simbel sunrise on 22 Feb, the Red Sea.
  - Launch the journal.
  - Hotel partnership approaches.
  - Send an Egypt partner pack to travel advisors.
- **Q2 2027**
  - Release the film with press.
  - North Coast and Eid guides for Gulf families.
  - Membership: publish response times.
  - First client quotes go live.
- **Q3 2027**
  - North Coast summer photography.
  - Publish "The Egypt Season 2027–28".
  - Review the freeze.

**When to lift the freeze:** only when two or more of these hold:
- Six months of data show a gap that content cannot fix.
- A format the current patterns cannot carry: a film hub, Arabic, a member login, payments.
- The assets exist: the film, 60 or more cleared photographs, 15 or more articles.
- It pays back within 12 months.

## 7. Forbes Travel Guide in Egypt (for partnerships)

**Verified:**
- Forbes Travel Guide has rated Egypt since its 2020 awards. Its destination pages cover Cairo, Alexandria and the North Coast.
- **Four Seasons Hotel Cairo at Nile Plaza:** Four-Star.
- **Mandarin Oriental Winter Palace, Luxor:** in the Debut Collection, which is sponsored and has no stars. Relevant to the eclipse.
- **Kazazian Cruises, Nile Journey (Luxor to Aswan):** on the 2026 Edge List, an editorial list rather than a rating. Relevant to the eclipse.

**Listed by Forbes Travel Guide, rating unverified (do not quote one):**
- Cairo: Four Seasons at the First Residence, The Nile Ritz-Carlton, The St. Regis Cairo, Fairmont Nile City, Waldorf Astoria Heliopolis, Mandarin Oriental Shepheard.
- Aswan: Mandarin Oriental Old Cataract.
- Alexandria: Four Seasons Alexandria at San Stefano.
- North Coast: Al Alamein Hotel, Palace Beach Resort Marassi, Address Beach Resort Marassi.

No Egyptian Five-Star was found for 2026.

## Sources (beyond those linked above)

- [Forbes: Luxor eclipse](https://www.forbes.com/sites/jamiecartereurope/2026/08/16/ancient-egypts-capital-will-soon-host-the-centurys-longest-total-solar-eclipse/)
- [NSO eclipse map](https://nso.edu/eclipse-map-2027-aug2/)
- [Horse & Hound: LGCT Cairo](https://www.horseandhound.co.uk/showjumping/longines-global-champions-tour-cairo-914720)
- [Egyptian Streets: Gala de Danza](https://egyptianstreets.com/2026/06/19/grand-egyptian-museum-and-gala-de-danza-announce-regional-debut-for-cairo-performance/)
- [EASA CZIB extension](https://avi-go.com/news/articles/8e0ea0814656d631f27182ba531aeaa7)
- [FTG Cairo](https://www.forbestravelguide.com/destinations/cairo-egypt)
- [FTG Nile Plaza](https://www.forbestravelguide.com/hotels/cairo-egypt/four-seasons-hotel-cairo-at-nile-plaza)
- [FTG Debut Collection](https://www.prnewswire.com/news-releases/forbes-travel-guide-expands-mandarin-oriental-headlines-inaugural-debut-collection-302841713.html)
- [FTG Edge List 2026](https://www.forbes.com/sites/forbestravelguide/2026/08/12/forbes-travel-guides-2026-edge-list/)
