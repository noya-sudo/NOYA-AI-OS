const mission = $json.mission;
const maxResults = $json.max_results;
const countryFocus = $json.country_focus;
const egyptOpportunity = $json.egypt_opportunity;
const runId = $json.run_id;
const minimumScore = $json.minimum_score;

const directQueryBank = {
  BRAND: [
    '"beauty brand" "creator trip" Dubai -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"fashion brand" "Middle East campaign" -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"cosmetics brand" "influencer trip" -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"luxury brand" "destination campaign" -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"jewellery brand" "Middle East activation" -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"watch brand" "brand event" Middle East -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"automotive brand" "experiential launch" -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"swimwear brand" "resort campaign" -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"skincare brand" "brand trip" -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"fashion brand" "campaign in Egypt" -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"beauty brand" "hotel collaboration" -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"luxury brand" "creator retreat" -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"beauty brand" "Dubai activation" -agency -consulting -magazine -publication -directory -"marketing agency"',
    '"fashion brand" "Saudi activation" -agency -consulting -magazine -publication -directory -"marketing agency"'
  ],
  MARKETING_AGENCY: ['experiential marketing agency destination activation client','influencer marketing agency Middle East expansion','creative agency luxury brand campaign production','brand experience agency international shoot location','marketing agency destination campaign case study'],
  PR_AGENCY: ['luxury PR agency Middle East client roster','lifestyle PR agency press trip destination','fashion PR agency international press event','communications agency brand launch Middle East'],
  HOTEL: ['luxury hotel opening 2026 Red Sea OR Egypt OR Middle East','boutique hotel group expanding internationally','hotel brand creator collaboration content stay','luxury resort new opening press trip','hospitality group new property announcement'],
  HOSPITALITY_GROUP: ['luxury hospitality group international expansion','hotel management company new markets 2026'],
  WEDDING_EVENT: ['luxury destination wedding planner international clients','luxury event agency destination production','wedding planner Middle East destination weddings','celebration planner international clientele'],
  CORPORATE: ['private equity firm executive travel program','family office concierge travel partnership','corporate client entertainment executive travel','football club OR sports organisation international travel partnership'],
  TRAVEL_CONCIERGE: ['luxury travel advisory Egypt destination partner','concierge company seeking local execution partner','DMC destination management company Egypt partnership','private club travel concierge partnership'],
  CREATOR: ['luxury travel creator destination collaboration','fashion creator Middle East brand trip','hospitality creator hotel content collaboration'],
  PRODUCTION: ['production company international shoot location scouting','creative production agency destination shoot Egypt OR Middle East','photographer OR director location scouting international campaign']
};

const signalQueryBank = {
  BRAND: [
    'brand "announces" campaign Egypt 2026',
    'brand "unveils" campaign Dubai 2026',
    'brand "partners with" hotel Middle East press release 2026',
    'brand "launches" creator trip 2026 press release',
    'brand "appoints" ambassador Middle East 2026',
    'brand "debuts" campaign Saudi Arabia 2026',
    'fashion brand "shot in Egypt" campaign 2026',
    'beauty brand "shot in Dubai" campaign 2026',
    'luxury brand "brand trip" influencers 2026',
    'brand campaign "Red Sea" OR "North Coast" OR "Cairo" 2026',
    'cosmetics brand "flew influencers to" 2026',
    'fashion brand "hosted creators in" Middle East 2026',
    'brand "Dubai activation" press release 2026',
    'brand "Saudi Arabia expansion" press release 2026',
    'watch OR jewellery brand "campaign shoot" Middle East 2026',
    'automotive brand "experiential launch" Middle East 2026',
    'swimwear OR resortwear brand "resort campaign" 2026',
    'consumer brand "MENA expansion" announcement 2026',
    'beauty OR fashion brand "hotel collaboration" press release 2026'
  ]
};

let directQueries = directQueryBank[mission] ? directQueryBank[mission].slice() : directQueryBank.BRAND.slice();
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
signalQueries = rotateSlice(signalQueries, 6, 3);

// New ground at no extra volume: filmed-episode media and podcasts, brands shooting in competing destinations, Instagram discovery (brands, studios, creators).
const EXTRA_BANKS = [
  { n: 6, sector: null, q: [
    '"travel podcast" "video" episodes host destinations -spotify -apple',
    '"luxury travel" YouTube series "new episode" destinations ' + new Date().getFullYear(),
    '"hospitality podcast" hotel owners interviews video',
    '"entrepreneur podcast" "filmed" "on location" episodes',
    '"fashion podcast" video episodes designers interviews',
    '"design podcast" hotels architecture video series',
    '"travel show" production company series destinations ' + new Date().getFullYear(),
    '"food and travel" series "filmed in" Middle East OR Morocco OR Egypt',
    '"creator series" travel "episode" Egypt OR Morocco OR Jordan',
    '"podcast" "recorded in" Dubai OR Marrakech OR Greece episode',
    '"hotel review" YouTube channel luxury hotels',
    '"luxury lifestyle" magazine "video series" "on location"',
    '"travel documentary" production company Egypt',
    '"interview series" "filmed at" hotel luxury',
    '"wellness podcast" retreat episodes "on location"',
    '"travel publication" "video series" destinations editor',
    '"golf" OR "padel" travel series YouTube destinations',
    '"automotive" YouTube series "road trip" destinations luxury',
    '"architecture" YouTube series hotels destinations',
    '"business podcast" founders "on the road" episodes video'
  ] },
  { n: 6, sector: null, q: [
    '"campaign shot in Morocco" brand', '"shot in Marrakech" campaign fashion', '"shot in Jordan" campaign "Wadi Rum" brand',
    '"shot in Greece" campaign resortwear', '"shot in Ibiza" campaign brand', '"shot in Dubai" campaign luxury brand',
    '"shot on location" desert campaign fashion ' + new Date().getFullYear(), '"press trip" Morocco OR Jordan brand PR agency',
    '"MENA launch" luxury brand press', '"creator trip" Marrakech OR AlUla brand', '"production service company" Morocco OR Jordan shoot -jobs',
    '"location scouting" Middle East production company commercial', '"brand trip" AlUla OR "Wadi Rum" influencers', '"campaign film" desert luxury brand',
    '"lookbook shot in" Mykonos OR Santorini', '"experiential agency" press trip destination luxury', '"PR agency" "press trip" hotel destination luxury',
    '"production company" commercials "Middle East" luxury brands'
  ] },
  { n: 2, sector: null, q: [
    'site:instagram.com "production house" Dubai "info@"', 'site:instagram.com "creative agency" Riyadh "hello@"',
    'site:instagram.com "travel podcast" "business enquiries"', 'site:instagram.com "luxury travel" creator "partnerships@"',
    'site:instagram.com "production company" Cairo "info@"', 'site:instagram.com "creative studio" London "hello@" luxury'
  ] },
];
EXTRA_BANKS.forEach(function (bank, b) {
  rotateSlice(bank.q, bank.n, 7 + b).forEach(function (q) {
    if (directQueries.indexOf(q) < 0) { directQueries.push(q); }
  });
});

if (egyptOpportunity === true) { directQueries.push(mission + ' Egypt opportunity partnership 2026'); }
if (countryFocus && countryFocus !== 'GLOBAL') {
  directQueries = directQueries.map(function (q) { return q + ' ' + countryFocus; });
  signalQueries = signalQueries.map(function (q) { return q + ' ' + countryFocus; });
}

const queryLaneMap = {};
directQueries.forEach(function (q) { queryLaneMap[q] = 'DIRECT'; });
signalQueries.forEach(function (q) { queryLaneMap[q] = 'SIGNAL'; });

const queries = directQueries.concat(signalQueries);

return [{ json: { queries: queries, queryLaneMap: queryLaneMap, mission: mission, max_results: maxResults, minimum_score: minimumScore, country_focus: countryFocus, egypt_opportunity: egyptOpportunity, run_id: runId } }];