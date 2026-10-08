const mission = $json.mission;
const maxResults = $json.max_results;
const countryFocus = $json.country_focus;
const egyptOpportunity = $json.egypt_opportunity;
const runId = $json.run_id;
const minimumScore = $json.minimum_score;

// 07 -- Global Partnerships: direct-target discovery queries grouped by
// partnership family and tagged with that family for the downstream soft
// diversity allocator (Merge & Cap Candidates) and the Final Report's sector
// diversity assessment. Query allocation only -- every candidate still has to
// clear the same minimum_score, mission-fit and PARTNERSHIP QUALITY GATE
// regardless of which family its query came from. Roughly balanced across:
// CONCIERGE_MEMBERSHIP, TRAVEL_DMC_MICE, SPORTS_TALENT_ENTERTAINMENT,
// MEMBER_COMMUNITY, DESTINATION_PARTNER, EVENTS_WEDDINGS_PRODUCTION_PR,
// FAMILY_OFFICE_PRIVATE_CLIENT_SERVICES.
// 29 Sep 2026: aviation/yachting and real-estate slots were swapped for member
// communities (founder/athlete/member clubs) and destination partners (3-5 trusted
// operators per destination, incl. public site:instagram.com discovery). Same query count.
const directQueryBank = {
  GLOBAL_PARTNERSHIPS: [
    { q: '"luxury concierge" company international clients OR "private members club" -job -careers', sector: 'CONCIERGE_MEMBERSHIP' },
    { q: '"lifestyle management" company UHNW clients international -job -careers', sector: 'CONCIERGE_MEMBERSHIP' },
    { q: '"private membership" network luxury travel benefits -job -careers', sector: 'CONCIERGE_MEMBERSHIP' },
    { q: '"private members club" travel benefits network international -job -careers', sector: 'CONCIERGE_MEMBERSHIP' },
    { q: '"luxury travel advisor" OR "luxury travel agency" international clients -job -careers', sector: 'TRAVEL_DMC_MICE' },
    { q: '"travel management company" OR TMC premium corporate clients -job -careers', sector: 'TRAVEL_DMC_MICE' },
    { q: '"destination management company" OR DMC international OR global network -job -careers', sector: 'TRAVEL_DMC_MICE' },
    { q: '"MICE agency" OR "incentive travel" agency corporate clients -job -careers', sector: 'TRAVEL_DMC_MICE' },
    { q: '"premium travel agency" corporate executive clients -job -careers', sector: 'TRAVEL_DMC_MICE' },
    { q: 'sports agency OR "athlete management" client roster international -job -careers', sector: 'SPORTS_TALENT_ENTERTAINMENT' },
    { q: 'talent agency OR "entertainment agency" client roster travel -job -careers', sector: 'SPORTS_TALENT_ENTERTAINMENT' },
    { q: 'football OR "sports management" agency "player services" -job -careers', sector: 'SPORTS_TALENT_ENTERTAINMENT' },
    { q: 'entertainment company "artist logistics" OR "client travel" -job -careers', sector: 'SPORTS_TALENT_ENTERTAINMENT' },
    { q: 'site:instagram.com "luxury concierge" Mallorca OR Ibiza OR Marbella', sector: 'DESTINATION_PARTNER' },
    { q: 'site:instagram.com "villa concierge" OR "lifestyle concierge" Mykonos OR "Saint-Tropez" OR Monaco', sector: 'DESTINATION_PARTNER' },
    { q: '"luxury concierge" Courchevel OR "St Moritz" OR Cannes private clients -job -careers', sector: 'DESTINATION_PARTNER' },
    { q: '"founders club" OR "founder community" members retreat OR "member trips" -job -careers', sector: 'MEMBER_COMMUNITY' },
    { q: '"members club" "member trips" OR "members retreat" OR "group journeys" -job -careers', sector: 'MEMBER_COMMUNITY' },
    { q: 'athlete OR players community "members" experiences OR retreats -job -careers', sector: 'MEMBER_COMMUNITY' },
    { q: '"luxury event agency" OR "destination wedding planner" international clients -job -careers', sector: 'EVENTS_WEDDINGS_PRODUCTION_PR' },
    { q: '"production agency" OR "luxury PR agency" international clients -job -careers', sector: 'EVENTS_WEDDINGS_PRODUCTION_PR' },
    { q: '"corporate event agency" international client roster -job -careers', sector: 'EVENTS_WEDDINGS_PRODUCTION_PR' },
    { q: '"family office services" OR "private client services" firm multiple clients -job -careers', sector: 'FAMILY_OFFICE_PRIVATE_CLIENT_SERVICES' },
    { q: '"multi-family office" client services international -job -careers', sector: 'FAMILY_OFFICE_PRIVATE_CLIENT_SERVICES' },
    { q: '"UHNW services" firm multiple private clients -job -careers', sector: 'FAMILY_OFFICE_PRIVATE_CLIENT_SERVICES' }
  ]
};

// Signal mining: commercial-signal search queries (news/press, not
// directories), also sector-tagged, aimed at MENA/Egypt expansion, new
// offices, new divisions, leadership hires and partnership announcements
// across all seven partnership families.
const signalQueryBank = {
  GLOBAL_PARTNERSHIPS: [
    { q: '"luxury concierge" company "opens" OR "launches" Middle East 2026', sector: 'CONCIERGE_MEMBERSHIP' },
    { q: '"private members club" "launches" OR "opens" new city 2026', sector: 'CONCIERGE_MEMBERSHIP' },
    { q: '"travel advisory" OR "travel agency" "opens Dubai office" OR "opens Cairo office" 2026', sector: 'TRAVEL_DMC_MICE' },
    { q: 'DMC OR "destination management company" "announces partnership" 2026', sector: 'TRAVEL_DMC_MICE' },
    { q: '"travel management company" "expands" Middle East OR MENA 2026', sector: 'TRAVEL_DMC_MICE' },
    { q: 'sports agency OR "talent agency" "signs partnership" OR "expands into" Middle East 2026', sector: 'SPORTS_TALENT_ENTERTAINMENT' },
    { q: 'entertainment company "opens" OR "expands" Middle East office 2026', sector: 'SPORTS_TALENT_ENTERTAINMENT' },
    { q: '"private aviation" company "expands" OR "new route" Middle East 2026', sector: 'AVIATION_YACHTING' },
    { q: '"yacht charter" company "new region" OR "expands" Red Sea OR Mediterranean 2026', sector: 'AVIATION_YACHTING' },
    { q: '"members club" OR "founder community" announces retreat OR "members trip" 2026', sector: 'MEMBER_COMMUNITY' },
    { q: 'site:instagram.com "members club" OR "founders club" retreat 2026', sector: 'MEMBER_COMMUNITY' },
    { q: '"destination wedding" agency "expands" OR "launches" new destination 2026', sector: 'EVENTS_WEDDINGS_PRODUCTION_PR' },
    { q: '"production agency" OR "luxury PR agency" "opens" Middle East office 2026', sector: 'EVENTS_WEDDINGS_PRODUCTION_PR' },
    { q: '"family office services" firm "opens" OR "expands" Middle East 2026', sector: 'FAMILY_OFFICE_PRIVATE_CLIENT_SERVICES' },
    { q: '"private client services" firm "new offering" OR "launches" 2026', sector: 'FAMILY_OFFICE_PRIVATE_CLIENT_SERVICES' },
    { q: '"opens Egypt office" OR "Egypt partnership" luxury travel OR concierge 2026', sector: 'TRAVEL_DMC_MICE' },
    { q: 'company "appoints regional head" OR "hires" Middle East luxury travel OR concierge 2026', sector: 'CONCIERGE_MEMBERSHIP' }
  ]
};

const directBank = directQueryBank[mission] ? directQueryBank[mission].slice() : directQueryBank.GLOBAL_PARTNERSHIPS.slice();
const signalBank = signalQueryBank[mission] ? signalQueryBank[mission].slice() : signalQueryBank.GLOBAL_PARTNERSHIPS.slice();

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
directQueries = rotateSlice(directQueries, 6, 0);
signalQueries = rotateSlice(signalQueries, 5, 3);

const querySectorMap = {};
directBank.forEach(function (e) { querySectorMap[e.q] = e.sector; });
signalBank.forEach(function (e) { querySectorMap[e.q] = e.sector; });

// GROWTH ENGINE (7 Oct 2026): rotating strategic-partner bank across NOYA markets. 16 extra direct queries a day:
// concierge/lifestyle firms, travel designers, DMCs, members' clubs, private aviation, yacht charter, chauffeur,
// executive security, event hospitality. Full rotation every ~9 days.
const MARKETS = ['London', 'Paris', 'Geneva', 'Zurich', 'Monaco', 'Milan', 'Rome', 'Madrid', 'Athens', 'Dubai', 'Abu Dhabi', 'Riyadh', 'Doha', 'Kuwait', 'Cairo', 'New York'];
const PTPL = [['"lifestyle management" OR "luxury concierge" company {m} -job -careers', 'CONCIERGE_MEMBERSHIP'],
  ['"travel designer" OR "luxury travel advisor" {m} bespoke itineraries -job', 'TRAVEL_DMC_MICE'],
  ['"destination management company" {m} luxury incentives', 'TRAVEL_DMC_MICE'],
  ['"private members club" {m} reciprocal clubs', 'MEMBER_COMMUNITY'],
  ['"private jet charter" {m} operator -broker -job', 'AVIATION_YACHTING'],
  ['"yacht charter" company {m} luxury -job', 'AVIATION_YACHTING'],
  ['"chauffeur service" OR "executive chauffeur" {m} luxury -uber -job', 'DESTINATION_PARTNER'],
  ['"executive protection" OR "close protection" company {m} private clients -job', 'DESTINATION_PARTNER'],
  ['"event hospitality" OR "VIP hospitality" company {m} -tickets -job', 'EVENTS_WEDDINGS_PRODUCTION_PR']];
const PROT = [];
MARKETS.forEach(function (m) { PTPL.forEach(function (t) { PROT.push([t[0].replace('{m}', m), t[1]]); }); });
const P_DAY = RUN_IDX, P_PER_DAY = 10;
for (let i = 0; i < P_PER_DAY; i++) { const e = PROT[((P_DAY * P_PER_DAY + i) * 7) % PROT.length]; if (directQueries.indexOf(e[0]) < 0) { directQueries.push(e[0]); querySectorMap[e[0]] = e[1]; } }

// New ground at no extra volume: partner networks (advisor networks, concierge firms, private clubs, DMCs).
const EXTRA_BANKS = [
  { n: 6, sector: "TRAVEL_DMC_MICE", q: expand(['"luxury travel advisor network" OR "host agency" {m}', '"travel advisor collective" luxury {m}', '"concierge company" {m} "lifestyle management" -job', '"private members club" {m} "reciprocal"', '"destination management company" {m} luxury FIT', 'luxury travel agency {m} Virtuoso OR "Signature Travel Network"'], ['London', 'New York', 'Los Angeles', 'Miami', 'Dubai', 'Riyadh', 'Doha', 'Kuwait', 'Geneva', 'Paris', 'Milan', 'Singapore', 'Hong Kong', 'Sydney', 'Toronto']) },
  // Volume (Adam, 8 Oct 2026). Travel / Concierge: luxury travel advisors, concierge firms, boutique travel firms, DMCs and
  // lifestyle management (they keep their client; NOYA executes Egypt). Private Founders / Events: founder clubs, business
  // communities, members clubs, family-office networks and executive communities that run retreats, dinners, trips, off-sites.
  { n: 4, sector: "TRAVEL_DMC_MICE", q: [
    'boutique luxury travel company "tailor-made" Middle East OR Africa itineraries -job -careers',
    '"luxury travel designer" independent agency UHNW clients -job -careers',
    '"lifestyle management" company "private clients" London OR Dubai OR Geneva -job -careers',
    '"concierge company" UHNW members travel "on the ground" partners -job -careers',
    'DMC luxury "Middle East" OR "North Africa" partner network incentive -job -careers',
    '"luxury tour operator" bespoke "Egypt" OR "Jordan" OR "Morocco" -job -careers',
    '"travel advisor" Virtuoso OR Signature OR "Serandipians" luxury agency -job -careers',
    '"private travel office" OR "travel concierge" family office clients -job -careers',
    'luxury safari OR expedition company "tailor-made" UHNW clients -job -careers',
    '"luxury travel club" members trips worldwide -job -careers'
  ] },
  { n: 4, sector: "MEMBER_COMMUNITY", q: [
    '"founders club" OR "founder network" "annual retreat" OR "members retreat" -job -careers',
    '"business community" CEOs OR founders "retreat" OR "offsite" abroad -job -careers',
    '"executive community" "members only" dinners OR retreats international -job -careers',
    '"YPO" OR "EO chapter" retreat abroad members trip',
    '"family office network" members summit OR retreat -job -careers',
    '"private members club" "member trips" OR "members journeys" -job -careers',
    '"entrepreneurs club" members "trip" OR "retreat" Morocco OR Dubai OR Greece',
    '"investor community" OR "angel network" members retreat OR "offsite" abroad',
    '"women founders" community retreat abroad members',
    'founders "private dinner series" OR "salon" members community international'
  ] },
];
EXTRA_BANKS.forEach(function (bank, b) {
  rotateSlice(bank.q, bank.n, 7 + b).forEach(function (q) {
    if (directQueries.indexOf(q) < 0) { directQueries.push(q); if (bank.sector) querySectorMap[q] = bank.sector; }
  });
});

if (egyptOpportunity === true) {
  const egyptQuery = mission + ' Egypt execution partner 2026';
  directQueries.push(egyptQuery);
  querySectorMap[egyptQuery] = 'TRAVEL_DMC_MICE';
}
if (countryFocus && countryFocus !== 'GLOBAL') {
  const remappedDirect = [];
  const remappedSignal = [];
  directQueries.forEach(function (q) { const nq = q + ' ' + countryFocus; querySectorMap[nq] = querySectorMap[q]; remappedDirect.push(nq); });
  signalQueries.forEach(function (q) { const nq = q + ' ' + countryFocus; querySectorMap[nq] = querySectorMap[q]; remappedSignal.push(nq); });
  directQueries = remappedDirect;
  signalQueries = remappedSignal;
}

const queryLaneMap = {};
directQueries.forEach(function (q) { queryLaneMap[q] = 'DIRECT'; });
signalQueries.forEach(function (q) { queryLaneMap[q] = 'SIGNAL'; });

const queries = directQueries.concat(signalQueries);

return [{ json: { queries: queries, queryLaneMap: queryLaneMap, querySectorMap: querySectorMap, mission: mission, max_results: maxResults, minimum_score: minimumScore, country_focus: countryFocus, egypt_opportunity: egyptOpportunity, run_id: runId } }];