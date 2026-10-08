const mission = $json.mission;
const maxResults = $json.max_results;
const countryFocus = $json.country_focus;
const egyptOpportunity = $json.egypt_opportunity;
const runId = $json.run_id;
const minimumScore = $json.minimum_score;

// NOYA 06 -- Corporate & Private Client Growth: direct-target discovery queries,
// grouped by sector family and tagged with that family for the downstream soft
// diversity allocator (Merge & Cap Candidates) and the Final Report's sector
// diversity assessment. Query allocation only -- this does not create a
// qualification quota; every candidate must still clear the same minimum_score
// and mission-fit gates regardless of which family its query came from.
// Calibrated 2026-09 (FINAL COMMERCIAL CALIBRATION) to spread discovery across:
// PRIVATE_BANK_WEALTH ~21%, CORPORATE_PROFESSIONAL_SERVICES ~21%,
// SPORTS_TALENT ~18%, LUXURY_REAL_ESTATE ~14%, FAMILY_OFFICE_INVESTMENT ~21%,
// PREMIUM_CORPORATE_OTHER ~14% of the direct query bank.
const directQueryBank = {
  CORPORATE_PRIVATE_CLIENT_GROWTH: [
    // -- PRIVATE_BANK_WEALTH --
    { q: '"private bank" OR "private banking" client experience team Middle East -job -jobs -careers', sector: 'PRIVATE_BANK_WEALTH' },
    { q: '"wealth management" firm "family office services" international clients -job -careers', sector: 'PRIVATE_BANK_WEALTH' },
    { q: '"private client" division bank Europe OR "United States" -job -careers', sector: 'PRIVATE_BANK_WEALTH' },
    // -- FAMILY_OFFICE_INVESTMENT (family offices) --
    { q: '"family office" principal OR "chief of staff" international travel -job -careers -directory', sector: 'FAMILY_OFFICE_INVESTMENT' },
    { q: 'single family office OR multi-family office London OR Geneva OR "New York" -job -careers', sector: 'FAMILY_OFFICE_INVESTMENT' },
    { q: '"multi-family office" "client services" OR "family office services" international -job -careers', sector: 'FAMILY_OFFICE_INVESTMENT' },
    // -- FAMILY_OFFICE_INVESTMENT (private equity / venture capital / investment firms) --
    { q: '"private equity" firm portfolio "annual retreat" OR "executive offsite" -job -careers', sector: 'FAMILY_OFFICE_INVESTMENT' },
    { q: '"venture capital" firm "founder retreat" OR "LP summit" -job -careers', sector: 'FAMILY_OFFICE_INVESTMENT' },
    { q: 'investment firm managing partner international travel program -job -careers', sector: 'FAMILY_OFFICE_INVESTMENT' },
    // -- CORPORATE_PROFESSIONAL_SERVICES (law / consulting / professional services) --
    { q: '"law firm" "partner retreat" OR "client hospitality" international -job -careers', sector: 'CORPORATE_PROFESSIONAL_SERVICES' },
    { q: 'consulting firm "partner offsite" OR "leadership retreat" global -job -careers', sector: 'CORPORATE_PROFESSIONAL_SERVICES' },
    { q: 'professional services firm executive client entertainment program -job -careers', sector: 'CORPORATE_PROFESSIONAL_SERVICES' },
    { q: 'international law firm "Middle East office" OR "Dubai office" -job -careers', sector: 'CORPORATE_PROFESSIONAL_SERVICES' },
    { q: 'management consulting firm "chief of staff" OR "executive office" international -job -careers', sector: 'CORPORATE_PROFESSIONAL_SERVICES' },
    { q: 'accounting OR advisory firm "global mobility" OR "partner travel" program -job -careers', sector: 'CORPORATE_PROFESSIONAL_SERVICES' },
    // -- SPORTS_TALENT (sports / talent / entertainment / production) --
    { q: 'football club OR "sports club" "player welfare" OR "player care" international -job -careers', sector: 'SPORTS_TALENT' },
    { q: 'sports agency OR "athlete management" lifestyle services players -job -careers', sector: 'SPORTS_TALENT' },
    { q: 'talent agency client lifestyle OR travel management -job -careers', sector: 'SPORTS_TALENT' },
    { q: 'entertainment company executive travel OR "artist logistics" -job -careers', sector: 'SPORTS_TALENT' },
    { q: 'production company international shoot location scouting Egypt OR "Middle East" -job -careers', sector: 'SPORTS_TALENT' },
    // -- LUXURY_REAL_ESTATE (developers) --
    { q: '"luxury real estate" developer international buyer VIP services -job -careers', sector: 'LUXURY_REAL_ESTATE' },
    { q: 'property developer "VIP client experience" OR "buyer hospitality" -job -careers', sector: 'LUXURY_REAL_ESTATE' },
    { q: 'luxury property developer "client relations" OR "private office" international -job -careers', sector: 'LUXURY_REAL_ESTATE' },
    { q: 'branded residences OR "luxury residential development" international buyer services -job -careers', sector: 'LUXURY_REAL_ESTATE' },
    // -- PREMIUM_CORPORATE_OTHER (private aviation / yachting / members clubs / corporate events) --
    { q: '"private aviation" OR "business jet" charter company partnership concierge -job -careers', sector: 'PREMIUM_CORPORATE_OTHER' },
    { q: '"private members club" OR "members club" concierge partnership international -job -careers', sector: 'PREMIUM_CORPORATE_OTHER' },
    { q: 'corporate incentive travel buyer OR "corporate events" agency client roster -job -careers', sector: 'PREMIUM_CORPORATE_OTHER' },
    { q: 'yacht charter OR "superyacht" company partnership concierge -job -careers', sector: 'PREMIUM_CORPORATE_OTHER' }
  ]
};

// Signal mining: commercial-signal search queries (news/press, not directories),
// also sector-tagged. Broadened beyond wealth/family-office/bank-expansion
// signals to cover corporate MENA expansion, leadership delegations, executive
// retreats/offsites, sports/talent regional expansion, luxury real-estate
// launches, production delegations, and premium membership/private-office
// expansion -- private-bank signals are kept but no longer dominate the bank.
const signalQueryBank = {
  CORPORATE_PRIVATE_CLIENT_GROWTH: [
    // -- PRIVATE_BANK_WEALTH --
    { q: '"private bank" "opens office" OR "expands" Dubai OR Cairo OR "Middle East" 2026', sector: 'PRIVATE_BANK_WEALTH' },
    { q: '"private bank" OR wealth manager "hosts" client retreat OR summit 2026', sector: 'PRIVATE_BANK_WEALTH' },
    { q: 'private bank OR wealth manager "appoints regional head" OR "hires" Middle East 2026', sector: 'PRIVATE_BANK_WEALTH' },
    // -- FAMILY_OFFICE_INVESTMENT --
    { q: '"family office" "opens office" OR "establishes presence" Dubai OR "Middle East" 2026', sector: 'FAMILY_OFFICE_INVESTMENT' },
    { q: '"family office" "hosts" OR "hosted" client retreat OR summit 2026', sector: 'FAMILY_OFFICE_INVESTMENT' },
    { q: 'private equity OR "venture capital" firm "closes fund" OR "raises fund" 2026 press release', sector: 'FAMILY_OFFICE_INVESTMENT' },
    { q: 'private equity OR investment firm "portfolio company" Egypt OR MENA expansion 2026', sector: 'FAMILY_OFFICE_INVESTMENT' },
    // -- CORPORATE_PROFESSIONAL_SERVICES --
    { q: 'law firm OR "consulting firm" "opens Dubai office" OR "opens Cairo office" 2026', sector: 'CORPORATE_PROFESSIONAL_SERVICES' },
    { q: 'company "opens regional headquarters" OR "new MENA office" OR "appointed regional head" 2026', sector: 'CORPORATE_PROFESSIONAL_SERVICES' },
    { q: 'international company "announces expansion" Egypt OR "Middle East" investment 2026', sector: 'CORPORATE_PROFESSIONAL_SERVICES' },
    { q: 'company "corporate retreat" OR "executive offsite" OR "leadership delegation" Egypt OR Dubai 2026', sector: 'CORPORATE_PROFESSIONAL_SERVICES' },
    // -- SPORTS_TALENT --
    { q: 'sports club OR "sports agency" "signs partnership" travel OR hospitality 2026', sector: 'SPORTS_TALENT' },
    { q: 'talent agency OR "entertainment company" "expands into" Middle East 2026', sector: 'SPORTS_TALENT' },
    { q: 'film OR production company "delegation" OR "location scouting" Egypt 2026', sector: 'SPORTS_TALENT' },
    // -- LUXURY_REAL_ESTATE --
    { q: 'luxury real estate developer "launches" project Egypt OR "Red Sea" OR "North Coast" 2026', sector: 'LUXURY_REAL_ESTATE' },
    { q: 'property developer "hospitality event" OR "VIP launch" Middle East 2026', sector: 'LUXURY_REAL_ESTATE' },
    // -- PREMIUM_CORPORATE_OTHER --
    { q: 'private aviation OR "business jet" company "expands" Middle East fleet 2026', sector: 'PREMIUM_CORPORATE_OTHER' },
    { q: 'members club OR "private office" "opens" OR "launches" Middle East 2026', sector: 'PREMIUM_CORPORATE_OTHER' },
    { q: '"corporate event" OR "corporate conference" Middle East 2026 sponsorship OR host', sector: 'PREMIUM_CORPORATE_OTHER' }
  ]
};

const directBank = directQueryBank[mission] ? directQueryBank[mission].slice() : directQueryBank.CORPORATE_PRIVATE_CLIENT_GROWTH.slice();
const signalBank = signalQueryBank[mission] ? signalQueryBank[mission].slice() : signalQueryBank.CORPORATE_PRIVATE_CLIENT_GROWTH.slice();

let directQueries = directBank.map(function (e) { return e.q; });
let signalQueries = signalBank.map(function (e) { return e.q; });

// SEARCH ROTATION (Adam, 7 Oct 2026: efficient searches). Each scheduled run (one per 6-hour window) takes a different
// slice of every list, so the three daily runs never repeat a search; a query only comes back after its list has cycled.
const RUN_IDX = Math.floor(Date.now() / 21600000);
function rotateSlice(list, n, salt) {
  if (list.length <= n) return list.slice();
  const out = [], start = ((RUN_IDX + salt) * n) % list.length;
  for (let i = 0; i < n; i++) out.push(list[(start + i) % list.length]);
  return out;
}
function expand(templates, places) { const out = []; places.forEach(function (p) { templates.forEach(function (t) { out.push(t.split('{m}').join(p)); }); }); return out; }
directQueries = rotateSlice(directQueries, 9, 0);
signalQueries = rotateSlice(signalQueries, 6, 3);

const querySectorMap = {};
directBank.forEach(function (e) { querySectorMap[e.q] = e.sector; });
signalBank.forEach(function (e) { querySectorMap[e.q] = e.sector; });

// NOYA PRIVATE — ATHLETE & TALENT RELATIONS (Adam, 8 Oct 2026). Representation first, never the celebrity: football and
// athlete agencies, player care, talent / celebrity / music management, booking agencies, publicists, sports marketing,
// athlete concierge, sports law and private offices. Plus public Egypt occasions that bring talent (concerts, launches,
// festivals, premieres, sports events), to name the promoter, booking agency or production company behind them.
// Never private travel data and never personal contact details: organisations and their published business routes only.
const NOYA_PRIVATE_BANK = [
  'football agency OR "football representation" "player services" OR "player care" -job -careers',
  '"athlete management" firm "off-field" OR lifestyle OR "player care" -job -careers',
  '"player care" company footballers relocation OR lifestyle OR concierge -job -careers',
  '"talent management" agency actors OR celebrities "client services" -job -careers',
  '"artist management" OR "music management" company roster international -job -careers',
  '"booking agency" artists international tours roster -job -careers',
  '"celebrity publicist" OR "entertainment PR" agency clients -job -careers',
  '"sports marketing agency" athletes partnerships international -job -careers',
  '"athlete concierge" OR "concierge for athletes" OR "VIP athlete services" -job -careers',
  'football agents agency "Premier League" players represented -job -careers',
  '"sports law" firm "athlete representation" OR "player representation" -job -careers',
  '"private office" athletes OR entertainers "family office" services -job -careers',
  'international artist concert Egypt OR Cairo OR Pyramids ' + new Date().getFullYear(),
  '"Grand Egyptian Museum" gala OR event OR launch ' + new Date().getFullYear(),
  '"El Gouna Film Festival" OR "Cairo International Film Festival" stars ' + new Date().getFullYear(),
  'luxury brand launch OR show Egypt celebrities ' + new Date().getFullYear(),
  'football friendly OR tournament OR exhibition match Egypt international ' + new Date().getFullYear(),
  'festival Egypt international headliners promoter ' + new Date().getFullYear()
];
rotateSlice(NOYA_PRIVATE_BANK, 5, 11).forEach(function (q) {
  if (directQueries.indexOf(q) < 0) { directQueries.push(q); querySectorMap[q] = 'SPORTS_TALENT'; }
});

if (egyptOpportunity === true) {
  const egyptQuery = mission + ' Egypt opportunity partnership 2026';
  directQueries.push(egyptQuery);
  querySectorMap[egyptQuery] = 'CORPORATE_PROFESSIONAL_SERVICES';
}
if (countryFocus && countryFocus !== 'GLOBAL') {
  const remappedDirect = [];
  const remappedSignal = [];
  directQueries.forEach(function (q) {
    const nq = q + ' ' + countryFocus;
    querySectorMap[nq] = querySectorMap[q];
    remappedDirect.push(nq);
  });
  signalQueries.forEach(function (q) {
    const nq = q + ' ' + countryFocus;
    querySectorMap[nq] = querySectorMap[q];
    remappedSignal.push(nq);
  });
  directQueries = remappedDirect;
  signalQueries = remappedSignal;
}

const queryLaneMap = {};
directQueries.forEach(function (q) { queryLaneMap[q] = 'DIRECT'; });
signalQueries.forEach(function (q) { queryLaneMap[q] = 'SIGNAL'; });

const queries = directQueries.concat(signalQueries);

return [{ json: { queries: queries, queryLaneMap: queryLaneMap, querySectorMap: querySectorMap, mission: mission, max_results: maxResults, minimum_score: minimumScore, country_focus: countryFocus, egypt_opportunity: egyptOpportunity, run_id: runId } }];