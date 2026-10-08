const mission = $json.mission;
const maxResults = $json.max_results;
const countryFocus = $json.country_focus;
const egyptOpportunity = $json.egypt_opportunity;
const runId = $json.run_id;
const minimumScore = $json.minimum_score;
const YEAR = new Date().getFullYear();

const DIRECT_NEGATIVE_SUFFIX = '-booking -tripadvisor -expedia -agoda -blog -magazine -"best hotels" -"top hotels" -listicle -guide -directory -broker -"real estate" -"hotel openings list"';

const directQueryBank = {
  HOTELS: [
    '"luxury hotel" "official site" Dubai ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury resort" "official website" ' + YEAR + ' ' + DIRECT_NEGATIVE_SUFFIX,
    '"boutique hotel" "official site" Mykonos ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury hotel group" "new property" ' + YEAR + ' ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury resort" "now open" Middle East ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury hotel" opening Egypt "official" ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury resort" Marbella "official site" ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury hotel" St Tropez "official" ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury hotel group" expansion Middle East ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury hotel" appointed general manager ' + YEAR + ' ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury resort" appointed director of sales marketing ' + YEAR + ' ' + DIRECT_NEGATIVE_SUFFIX,
    '"private villa collection" new destination "official" ' + DIRECT_NEGATIVE_SUFFIX,
    'hospitality group new luxury property ' + YEAR + ' "official" ' + DIRECT_NEGATIVE_SUFFIX
  ]
};

const signalQueryBank = {
  HOTELS: [
    '"hotel" "creator trip" ' + YEAR,
    '"hotel" influencer partnership ' + YEAR,
    '"resort" influencer campaign ' + YEAR,
    '"hotel" brand collaboration ' + YEAR,
    '"hotel" fashion collaboration',
    '"hotel" beauty collaboration',
    '"hotel" appointed director of sales marketing',
    '"hotel" appointed general manager luxury ' + YEAR,
    '"hotel" travel advisor partnership',
    '"hotel" trade partnership',
    '"hotel" hosted creator trip',
    '"hotel" content creator stay',
    '"resort" "hosted stay" content creator',
    '"hotel" preferred rates travel advisors',
    '"resort" "brand trip" ' + YEAR,
    'luxury hotel Egypt press trip ' + YEAR,
    'hotel group MENA expansion press release ' + YEAR
  ]
};

let directQueries = directQueryBank[mission] ? directQueryBank[mission].slice() : directQueryBank.HOTELS.slice();
let signalQueries = signalQueryBank[mission] ? signalQueryBank[mission].slice() : [];

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
directQueries = rotateSlice(directQueries, 5, 0);
signalQueries = rotateSlice(signalQueries, 5, 3);

// GROWTH ENGINE (7 Oct 2026): rotating hospitality bank across NOYA destinations. 24 extra direct queries a day,
// spread across destinations and property types; the full bank rotates every 10 days. Hotels, boutique and
// independent hotels, villas, serviced/branded residences, villa managers, new openings.
const DEST = ['Cairo', 'El Gouna', 'Soma Bay', 'Sahl Hasheesh', 'North Coast Egypt', 'Luxor', 'Aswan', 'Sharm El Sheikh', 'London', 'Cotswolds',
  'Paris', 'Cote d Azur', 'Saint-Tropez', 'Courchevel', 'Provence', 'Amalfi Coast', 'Lake Como', 'Tuscany', 'Sardinia', 'Capri', 'Rome',
  'Marbella', 'Ibiza', 'Mallorca', 'Mykonos', 'Santorini', 'Athens Riviera', 'Paros', 'St Moritz', 'Gstaad', 'Zermatt', 'Geneva',
  'Dubai', 'Abu Dhabi', 'Riyadh', 'AlUla', 'Red Sea Saudi Arabia', 'Doha', 'Kuwait City', 'Monaco'];
const TPL = ['"boutique hotel" {d} "official site"', '"luxury villas" {d} "our villas" -airbnb', '"serviced residences" OR "branded residences" {d} luxury',
  '"luxury resort" {d} opening ' + YEAR, '"independent luxury hotel" {d}', '"villa management" {d} luxury concierge'];
const ROT = [];
DEST.forEach(function (d) { TPL.forEach(function (t) { ROT.push(t.replace('{d}', d) + ' ' + DIRECT_NEGATIVE_SUFFIX); }); });
const DAY_IDX = RUN_IDX, PER_DAY = 12;
for (let i = 0; i < PER_DAY; i++) { const q = ROT[((DAY_IDX * PER_DAY + i) * 7) % ROT.length]; if (directQueries.indexOf(q) < 0) directQueries.push(q); }

// New ground at no extra volume: partnership operators (boutique groups, independents, villa portfolios, serviced and branded residences, aparthotels), Instagram discovery (villas, boutique hotels).
const EXTRA_BANKS = [
  { n: 8, sector: null, q: expand(['"boutique hotel group" {m} collection properties', '"independent luxury hotel" {m} "member of"', '"luxury villa portfolio" OR "villa collection" {m} -airbnb', '"serviced residences" operator {m} luxury', '"branded residences" operator {m} "hotel services"', '"aparthotel" brand {m} design', '"luxury chalet" OR "luxury villa" collection {m} concierge', 'independent "hotel collection" {m} "Small Luxury Hotels" OR "Design Hotels"'], ['London', 'Paris', 'Lake Como', 'Amalfi Coast', 'Mykonos', 'Santorini', 'Ibiza', 'Marbella', 'Saint-Tropez', 'Courchevel', 'Gstaad', 'Dubai', 'Riyadh', 'AlUla', 'Cairo', 'El Gouna', 'North Coast Egypt', 'Marrakech', 'Lisbon', 'Athens Riviera']) },
  { n: 3, sector: null, q: expand(['site:instagram.com "luxury villa" {m} "reservations"', 'site:instagram.com "boutique hotel" {m} "book"', 'site:instagram.com "villa rentals" {m} "concierge"'], ['London', 'Paris', 'Lake Como', 'Amalfi Coast', 'Mykonos', 'Santorini', 'Ibiza', 'Marbella', 'Saint-Tropez', 'Courchevel', 'Gstaad', 'Dubai', 'Riyadh', 'AlUla', 'Cairo', 'El Gouna', 'North Coast Egypt', 'Marrakech', 'Lisbon', 'Athens Riviera']) },
  // Volume (Adam, 8 Oct 2026): hotels, villas, resorts and residences open to creator stays, talent stays, brand shoots,
  // production accommodation and content collaborations. Kept apart from preferred-stay outreach (CONTENT_TALENT model).
  { n: 4, sector: null, q: [
    'luxury hotel OR resort "content creators" collaboration "hosted stay" -jobs',
    'luxury villa "brand shoot" OR "photo shoot" location hire -jobs',
    'luxury resort "film and photo shoots" OR "location shoots" enquiries',
    'luxury hotel "creator partnership" OR "influencer collaboration" programme -jobs',
    'boutique hotel production crews accommodation "location shoots" -jobs',
    'private villa celebrities privacy "private villa" Mykonos OR Ibiza OR Marrakech -airbnb',
    'luxury hotel artist OR talent stays "private entrance" OR "private arrival"',
    'luxury resort "campaign" "shot at" ' + YEAR,
    'luxury hotel "partnerships manager" creators content collaboration',
    'luxury hotel Red Sea OR "El Gouna" OR "North Coast" OR "Sahl Hasheesh" content collaboration'
  ] },
];
EXTRA_BANKS.forEach(function (bank, b) {
  rotateSlice(bank.q, bank.n, 7 + b).forEach(function (q) {
    if (directQueries.indexOf(q) < 0) { directQueries.push(q); }
  });
});

if (egyptOpportunity === true) { directQueries.push('luxury hotel OR resort Egypt opportunity partnership ' + YEAR); }
if (countryFocus && countryFocus !== 'GLOBAL') {
  directQueries = directQueries.map(function (q) { return q + ' ' + countryFocus; });
  signalQueries = signalQueries.map(function (q) { return q + ' ' + countryFocus; });
}

const queryLaneMap = {};
directQueries.forEach(function (q) { queryLaneMap[q] = 'DIRECT'; });
signalQueries.forEach(function (q) { queryLaneMap[q] = 'SIGNAL'; });

const queries = directQueries.concat(signalQueries);

return [{ json: { queries: queries, queryLaneMap: queryLaneMap, mission: mission, max_results: maxResults, minimum_score: minimumScore, country_focus: countryFocus, egypt_opportunity: egyptOpportunity, run_id: runId } }];