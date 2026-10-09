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
const POSITIVE_SIGNALS = ['destination wedding','luxury wedding','UHNW','ultra high net worth','private event','celebrity wedding','athlete wedding','brand activation','brand event','corporate event','luxury celebration','private celebration','expansion','new market','new office','appointed','appointment','director of events','head of events','partnership','collaboration','collab','launch','egypt','red sea','el gouna','north coast','dubai','saudi','riyadh','doha','abu dhabi','mena','lake como','south of france','amalfi','mykonos','marbella','st tropez','st barth','courchevel','st moritz','maldives','luxury', YEAR];
const NEGATIVE_SIGNALS = ['how to','buying guide','best wedding planners','top wedding planners','best event agencies','best of','top 10','top 5','cheapest','deals','discount','coupon','promo code','hall of fame','roundup','guide','tips','ideas','inspiration','ultimate guide','directory','job','jobs','career','careers','definition','what is','recipe','review:',' vs ','wikipedia','glossary','magazine','publication','vendor directory','vendor list','compare quotes','things to do','budget wedding','affordable wedding','diy wedding','backyard wedding'];
const NEGATIVE_SIGNALS_STRONG = ['tourism board','tourism authority','ministry of tourism','department of tourism','destination marketing organisation','destination marketing organization','convention and visitors bureau','national tourism organisation','national tourism organization','government of','real estate','realty','brokerage','branded residences'];
const PREFERRED_SOURCE_DOMAINS = ['vogue.com','brides.com','tatler.com','harpersbazaar.com','thewed.com','weddingstyle.com','bizbash.com','travelandleisure.com','cntraveler.com','robbreport.com','hospitalitynet.org'];

function domainOf(c) {
  if (c.domain) { return c.domain.toLowerCase(); }
  const m = (c.source_url || '').match(/^https?:\/\/([^\/]+)/i);
  return m ? m[1].replace(/^www\./i, '').toLowerCase() : '';
}
const NOYA_PREMIUM_KEYWORDS = ['ultra-luxury','seven-figure','six-figure','celebrity','royal wedding','exclusive','bespoke','multi-day wedding','private island','chartered yacht','michelin','couture','white-glove','a-list'];
const BUDGET_PENALTY_KEYWORDS = ['budget','affordable','discount','economy','diy','backyard wedding','potluck','small-budget','low-cost'];

function scoreItem(c) {
  const text = ((c.company_name || '') + ' ' + (c.search_evidence || '') + ' ' + (c.search_query || '')).toLowerCase();
  const d = domainOf(c);
  let score = 0;
  POSITIVE_SIGNALS.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score += 1; } });
  NEGATIVE_SIGNALS.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score -= 3; } });
  NEGATIVE_SIGNALS_STRONG.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score -= 8; } });
  NOYA_PREMIUM_KEYWORDS.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score += 1; } });
  BUDGET_PENALTY_KEYWORDS.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score -= 5; } });
  if (d && (d.indexOf('.gov') !== -1 || d.indexOf('tourism') !== -1 || d.indexOf('ministry') !== -1)) { score -= 8; }
  PREFERRED_SOURCE_DOMAINS.forEach(function (pd) { if (d && (d === pd || d.indexOf('.' + pd) === (d.length - pd.length - 1))) { score += 2; } });
  return score;
}

const FLEXIBLE_ARTICLE_PATTERNS = [
  /\bbest\b[\s\S]{0,30}\bwedding planners\b/i,
  /\bbest\b[\s\S]{0,30}\bevent (agencies|planners)\b/i,
  /\btop\b[\s\S]{0,20}\bwedding planners\b/i,
  /\btop\b[\s\S]{0,20}\bevent (agencies|planners)\b/i,
  /\bmost anticipated\b[\s\S]{0,40}\bweddings\b/i,
  /\bwedding planners\b[\s\S]{0,20}\bto watch\b/i,
  /\bevent agencies\b[\s\S]{0,20}\bto watch\b/i,
  /\bhow to (choose|find|hire)\b[\s\S]{0,20}\bwedding planner\b/i,
  /\bwedding planners\b[\s\S]{0,20}\b20\d{2}\b/i
];
const MEDIA_ENTITY_PATTERNS = [/\bblog\b/i, /\bmagazine\b/i, /\btravel (publication|guide|agency|advisor)\b/i, /\bnews article\b/i, /\broundup\b/i, /\blistic(le|les)\b/i, /\beditorial\b/i, /\bdirectory\b/i];
function looksLikeArticleNotProperty(c) {
  const text = ((c.company_name || '') + ' ' + (c.search_evidence || '')).toLowerCase();
  for (let i = 0; i < FLEXIBLE_ARTICLE_PATTERNS.length; i++) { if (FLEXIBLE_ARTICLE_PATTERNS[i].test(text)) { return true; } }
  for (let i = 0; i < MEDIA_ENTITY_PATTERNS.length; i++) { if (MEDIA_ENTITY_PATTERNS[i].test(text)) { return true; } }
  return false;
}

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

// Volume (9 Oct 2026): 4 -> 14 so the Merge & Cap research cap (10) can fill after known accounts are skipped.
const MAX_DIRECT_CANDIDATES = 14;
const directRejectedAsArticles = directItemsRaw.filter(looksLikeArticleNotProperty).length;
const cappedDirectItems = directItemsRaw
  .filter(function (c) { return !looksLikeArticleNotProperty(c); })
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
return [{ json: { run_id: runId, directCount: cappedDirectItems.length, signalCount: cappedSignalItems.length, signalDiscoveredBeforeCap: signalItemsRaw.length } }];