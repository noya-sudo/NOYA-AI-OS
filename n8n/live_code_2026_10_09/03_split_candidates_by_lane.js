const staticData = $getWorkflowStaticData('global');
const runId = $('Normalise Candidates').first().json.run_id;
const items = $input.all();
const directItemsRaw = [];
const signalItemsRaw = [];
for (let i = 0; i < items.length; i++) {
  const c = items[i].json;
  if (c.lane === 'SIGNAL') { signalItemsRaw.push(c); } else { directItemsRaw.push(c); }
}

const YEAR = String(new Date().getFullYear());
const POSITIVE_SIGNALS = ['creator trip','influencer trip','brand trip','hosted stay','content creator stay','fam trip','familiarisation trip','press trip','preferred rates','travel trade','trade partnership','partnership','collaboration','collab','opening','reopening','relaunch','renovation','expansion','new property','new resort','new destination','appointed','appointment','director of sales','general manager','dosm','activation','campaign','launch','egypt','red sea','el gouna','north coast','dubai','saudi','riyadh','doha','abu dhabi','mena','luxury', YEAR];
const NEGATIVE_SIGNALS = ['how to','buying guide','best hotels','best resorts','best of','top 10','top 5','cheapest','deals','discount','coupon','promo code','hall of fame','roundup','guide','tips','ideas','inspiration','case studies collection','ultimate guide','directory','job','jobs','career','careers','definition','what is','recipe','review:',' vs ','wikipedia','glossary','agency','consulting','magazine','publication','book now','compare prices','things to do','most anticipated','hotels opening','resorts opening','opening in 20','new hotels','where to stay','hotels to watch','resorts to watch','anticipated hotels','anticipated resorts'];
const NEGATIVE_SIGNALS_STRONG = ['tourism board','tourism authority','ministry of tourism','department of tourism','destination marketing organisation','destination marketing organization','convention and visitors bureau','national tourism organisation','national tourism organization','government of'];
const PREFERRED_SOURCE_DOMAINS = ['hoteliermiddleeast.com','hospitalitynet.org','sleepermagazine.com','hospitalitydesign.com','travelweekly.com','travelandleisure.com','cntraveler.com','cntraveller.com','robbreport.com','luxurytraveladvisor.com','breakingtravelnews.com','forbestravelguide.com','prnewswire.com','businesswire.com','globenewswire.com'];
const NOYA_PREMIUM_BRANDS = ['aman','four seasons','fourseasons','rosewood','cheval blanc','one&only','oneandonly','one & only','mandarin oriental','belmond','nobu','bulgari','six senses','maybourne','raffles','capella','oetker','dorchester collection','auberge resorts','auberge'];
const NOYA_PREMIUM_KEYWORDS = ['ultra-luxury','ultra luxury','five-star','5-star','five star','design hotel','boutique luxury','private island','private villa','award-winning luxury','all-suite luxury','members-only'];
const BUDGET_PENALTY_KEYWORDS = ['budget hotel','economy hotel','3-star','3 star','value hotel','hostel','motel','low-cost','discount hotel'];

const FLEXIBLE_ARTICLE_PATTERNS = [
  /\bbest\b[\s\S]{0,30}\bhotels\b/i,
  /\bbest\b[\s\S]{0,30}\bresorts\b/i,
  /\bnew\b[\s\S]{0,30}\bhotels\b/i,
  /\bnew\b[\s\S]{0,30}\bresorts\b/i,
  /\btop\b[\s\S]{0,20}\bhotels\b/i,
  /\btop\b[\s\S]{0,20}\bresorts\b/i,
  /\bluxury\b[\s\S]{0,30}\bhotels\b[\s\S]{0,20}\b20\d{2}\b/i,
  /\bmost anticipated\b[\s\S]{0,40}\b(hotels|resorts|openings)\b/i,
  /\banticipated\b[\s\S]{0,30}\b(hotels|resorts|openings)\b/i,
  /\bhotel\s+openings?\b/i,
  /\bresort\s+openings?\b/i,
  /\bhotels\b[\s\S]{0,20}\bto watch\b/i,
  /\bresorts\b[\s\S]{0,20}\bto watch\b/i,
  /\bwhere to stay\b/i,
  /\bopening in 20\d{2}\b/i
];
const MEDIA_ENTITY_PATTERNS = [
  /\bblog\b/i,
  /\bmagazine\b/i,
  /\btravel (publication|guide|agency|advisor)\b/i,
  /\bnews article\b/i,
  /\broundup\b/i,
  /\blistic(le|les)\b/i,
  /\beditorial\b/i
];

function domainOf(c) {
  if (c.domain) { return c.domain.toLowerCase(); }
  const m = (c.source_url || '').match(/^https?:\/\/([^\/]+)/i);
  return m ? m[1].replace(/^www\./i, '').toLowerCase() : '';
}
function looksLikeArticleNotProperty(c) {
  const text = ((c.company_name || '') + ' ' + (c.search_evidence || '')).toLowerCase();
  for (let i = 0; i < FLEXIBLE_ARTICLE_PATTERNS.length; i++) {
    if (FLEXIBLE_ARTICLE_PATTERNS[i].test(text)) { return true; }
  }
  for (let i = 0; i < MEDIA_ENTITY_PATTERNS.length; i++) {
    if (MEDIA_ENTITY_PATTERNS[i].test(text)) { return true; }
  }
  return false;
}
function scoreItem(c) {
  const text = ((c.company_name || '') + ' ' + (c.search_evidence || '') + ' ' + (c.search_query || '')).toLowerCase();
  const d = domainOf(c);
  let score = 0;
  POSITIVE_SIGNALS.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score += 1; } });
  NEGATIVE_SIGNALS.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score -= 3; } });
  NEGATIVE_SIGNALS_STRONG.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score -= 8; } });
  if (d && (d.indexOf('.gov') !== -1 || d.indexOf('tourism') !== -1 || d.indexOf('ministry') !== -1)) { score -= 8; }
  PREFERRED_SOURCE_DOMAINS.forEach(function (pd) { if (d && (d === pd || d.indexOf('.' + pd) === (d.length - pd.length - 1))) { score += 2; } });
  NOYA_PREMIUM_BRANDS.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score += 4; } });
  NOYA_PREMIUM_KEYWORDS.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score += 1; } });
  BUDGET_PENALTY_KEYWORDS.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score -= 5; } });
  return score;
}

let directRejectedAsArticles = 0;
const directItemsFiltered = directItemsRaw.filter(function (c) {
  if (looksLikeArticleNotProperty(c)) { directRejectedAsArticles++; return false; }
  return true;
});

const SIGNAL_SOURCE_CAP = 4;
const signalRanked = signalItemsRaw
  .map(function (c, idx) { return { c: c, score: scoreItem(c), idx: idx }; })
  .sort(function (a, b) { return (b.score - a.score) || (a.idx - b.idx); });
const seenSignalDomains = {};
const signalDiverse = [];
signalRanked.forEach(function (r) {
  const d = domainOf(r.c);
  if (d && seenSignalDomains[d]) { return; }
  if (d) { seenSignalDomains[d] = true; }
  signalDiverse.push(r.c);
});
const cappedSignalItems = signalDiverse.slice(0, SIGNAL_SOURCE_CAP);

// Volume (9 Oct 2026): 4 -> 8 so the Merge & Cap research cap (6) can fill after known accounts are skipped.
const MAX_DIRECT_CANDIDATES = 8;
const cappedDirectItems = directItemsFiltered
  .map(function (c, idx) { return { c: c, score: scoreItem(c), idx: idx }; })
  .sort(function (a, b) { return (b.score - a.score) || (a.idx - b.idx); })
  .map(function (r) { return r.c; })
  .slice(0, MAX_DIRECT_CANDIDATES);

if (staticData.runs && staticData.runs[runId]) {
  staticData.runs[runId].directCandidates = cappedDirectItems;
  staticData.runs[runId]._pendingSignalSources = cappedSignalItems;
  staticData.runs[runId].signalSourcesDiscovered = signalItemsRaw.length;
  staticData.runs[runId].signalSourcesDeprioritised = signalItemsRaw.length - cappedSignalItems.length;
  staticData.runs[runId].directCandidatesDiscovered = directItemsRaw.length;
  staticData.runs[runId].directRejectedAsArticles = directRejectedAsArticles;
}
return [{ json: { run_id: runId, directCount: cappedDirectItems.length, signalCount: cappedSignalItems.length, signalDiscoveredBeforeCap: signalItemsRaw.length, directRejectedAsArticles: directRejectedAsArticles } }];