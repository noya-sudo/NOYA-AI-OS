const mission = $json.mission;
const maxResults = $json.max_results;
const countryFocus = $json.country_focus;
const egyptOpportunity = $json.egypt_opportunity;
const runId = $json.run_id;
const minimumScore = $json.minimum_score;
const YEAR = new Date().getFullYear();

const DIRECT_NEGATIVE_SUFFIX = '-"best wedding planners" -"top wedding planners" -"best event agencies" -directory -weddingwire -theknot -zola -pinterest -blog -magazine -listicle -guide -"vendor directory" -"vendor list"';

const directQueryBank = {
  WEDDINGS: [
    '"luxury destination wedding planner" Egypt ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury wedding planner" Middle East ' + DIRECT_NEGATIVE_SUFFIX,
    '"destination wedding planner" Dubai luxury ' + DIRECT_NEGATIVE_SUFFIX,
    '"UHNW event planner" ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury event agency" London ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury wedding planner" Lake Como ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury wedding planner" South of France ' + DIRECT_NEGATIVE_SUFFIX,
    '"private event planner" UHNW ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury event production agency" ' + DIRECT_NEGATIVE_SUFFIX,
    '"destination wedding agency" international ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury celebration planner" ' + DIRECT_NEGATIVE_SUFFIX,
    '"celebrity wedding planner" ' + DIRECT_NEGATIVE_SUFFIX,
    '"high-end private event agency" ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury wedding planner" Mykonos ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury wedding planner" Marbella ' + DIRECT_NEGATIVE_SUFFIX,
    '"destination wedding planner" Amalfi Coast ' + DIRECT_NEGATIVE_SUFFIX,
    '"luxury event agency" New York ' + DIRECT_NEGATIVE_SUFFIX
  ]
};

const signalQueryBank = {
  WEDDINGS: [
    'luxury wedding Egypt ' + YEAR + ' planner',
    'celebrity wedding planner ' + YEAR,
    'destination wedding agency Middle East expansion',
    'luxury wedding agency Dubai event',
    'high-end wedding planner destination event',
    'private event agency UHNW client',
    'luxury wedding planner hotel partnership',
    'event agency brand activation Middle East',
    'luxury event production Egypt',
    'international wedding planner Egypt',
    'wedding planner Red Sea Egypt',
    'luxury event agency Cairo partnership',
    'destination wedding company new market',
    'private celebration luxury resort event',
    'event agency appointed luxury brand',
    'wedding planner Vogue wedding',
    "wedding planner Harper's Bazaar wedding",
    'luxury wedding planner Four Seasons',
    'luxury event agency Mandarin Oriental',
    'luxury planner Aman wedding',
    'luxury planner Lake Como celebrity wedding',
    'wedding planner appointed director of events ' + YEAR,
    'luxury event agency office expansion ' + YEAR
  ]
};

let directQueries = directQueryBank[mission] ? directQueryBank[mission].slice() : directQueryBank.WEDDINGS.slice();
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
directQueries = rotateSlice(directQueries, 6, 0);
signalQueries = rotateSlice(signalQueries, 5, 3);

// New ground at no extra volume: wedding planner markets (London, Gulf, Lebanon, India, Europe, US), Instagram discovery (wedding planners).
const EXTRA_BANKS = [
  { n: 8, sector: null, q: expand(['"luxury wedding planner" {m} "destination weddings" -directory', '"wedding planner" {m} international weddings luxury -directory', '"event designer" {m} weddings luxury destination'], ['London', 'Dubai', 'Riyadh', 'Jeddah', 'Kuwait', 'Doha', 'Beirut', 'Mumbai', 'Delhi', 'Paris', 'Lake Como', 'Mykonos', 'New York', 'Los Angeles', 'Miami']) },
  { n: 4, sector: null, q: expand(['site:instagram.com "wedding planner" {m} "destination"', 'site:instagram.com "luxury weddings" {m} "planner" "enquiries"'], ['London', 'Dubai', 'Riyadh', 'Jeddah', 'Kuwait', 'Doha', 'Beirut', 'Mumbai', 'Delhi', 'Paris', 'Lake Como', 'Mykonos', 'New York', 'Los Angeles', 'Miami']) },
  // Weddings volume (Adam, 8 Oct 2026): planners already running international multi-day weddings and UHNW celebrations.
  { n: 5, sector: null, q: [
    '"multi-day wedding" planner international luxury -directory',
    '"three-day wedding" OR "multi-day celebration" planner destination luxury -directory',
    'UHNW weddings planner destination international -directory',
    'wedding planner "weddings worldwide" OR "weddings across Europe" luxury -directory',
    '"Indian wedding" destination planner Europe OR "Middle East" luxury -directory',
    'event designer "private celebrations" UHNW international -directory',
    'wedding planner Vogue destination wedding ' + YEAR,
    'luxury wedding planner Morocco OR Jordan OR Oman destination wedding -directory',
    'wedding planner "Lake Como" OR Amalfi OR Provence "three days" luxury',
    'luxury event planner "milestone birthday" OR "private party" destination -directory'
  ] },
];
EXTRA_BANKS.forEach(function (bank, b) {
  rotateSlice(bank.q, bank.n, 7 + b).forEach(function (q) {
    if (directQueries.indexOf(q) < 0) { directQueries.push(q); }
  });
});

if (egyptOpportunity === true) { directQueries.push('luxury destination wedding OR event Egypt opportunity partnership ' + YEAR); }
if (countryFocus && countryFocus !== 'GLOBAL') {
  directQueries = directQueries.map(function (q) { return q + ' ' + countryFocus; });
  signalQueries = signalQueries.map(function (q) { return q + ' ' + countryFocus; });
}

const queryLaneMap = {};
directQueries.forEach(function (q) { queryLaneMap[q] = 'DIRECT'; });
signalQueries.forEach(function (q) { queryLaneMap[q] = 'SIGNAL'; });

const queries = directQueries.concat(signalQueries);

return [{ json: { queries: queries, queryLaneMap: queryLaneMap, mission: mission, max_results: maxResults, minimum_score: minimumScore, country_focus: countryFocus, egypt_opportunity: egyptOpportunity, run_id: runId } }];