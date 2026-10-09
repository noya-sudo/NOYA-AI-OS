const staticData = $getWorkflowStaticData('global');
const runId = $('Normalise Candidates').first().json.run_id;
const items = $input.all();
const directItemsRaw = [];
const signalItemsRaw = [];
for (let i = 0; i < items.length; i++) {
  const c = items[i].json;
  if (c.lane === 'SIGNAL') { signalItemsRaw.push(c); } else { directItemsRaw.push(c); }
}

const POSITIVE_SIGNALS = ['brand trip','creator trip','destination campaign','middle east campaign','mena launch','mena expansion','mena','activation','international shoot','brand event','experiential activation','influencer campaign','hospitality collaboration','hotel collaboration','resort collaboration','campaign','launch','partnership','collaboration','collab','expansion','pop-up','pop up','shoot','production','creator retreat','announces','unveils','appoints','debuts','partners with','dubai','saudi','riyadh','uae','influencer','creator','2026'];
const NEGATIVE_SIGNALS = ['how to','buying guide','best of','best campaigns','best examples','top campaigns','top 10','top 5','hall of fame','campaign examples','marketing examples','roundup','guide','tips','ideas','inspiration','case studies collection','ultimate guide','directory','job','jobs','career','careers','definition','what is','recipe','review:',' vs ','wikipedia','glossary','magazine','publication'];
const NEGATIVE_SIGNALS_STRONG = ['tourism board','tourism authority','ministry of tourism','department of tourism','destination marketing organisation','destination marketing organization','convention and visitors bureau','national tourism organisation','national tourism organization','government of'];
const PREFERRED_SOURCE_DOMAINS = ['prnewswire.com','businesswire.com','globenewswire.com','campaignlive.com','campaignme.com','wwd.com','voguebusiness.com','beautymatter.com','glossy.co','businessoffashion.com'];

function domainOf(c) {
  if (c.domain) { return c.domain.toLowerCase(); }
  const m = (c.source_url || '').match(/^https?:\/\/([^\/]+)/i);
  return m ? m[1].replace(/^www\./i, '').toLowerCase() : '';
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
  return score;
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

// Volume (9 Oct 2026): 4 -> 14 so the Merge & Cap research cap (10) can fill after known accounts are skipped; sports / talent agencies (NOYA Private) and consulting firms are targets here, so neither word counts against a candidate.
const MAX_DIRECT_CANDIDATES = 14;
const cappedDirectItems = directItemsRaw
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
}
return [{ json: { run_id: runId, directCount: cappedDirectItems.length, signalCount: cappedSignalItems.length, signalDiscoveredBeforeCap: signalItemsRaw.length } }];