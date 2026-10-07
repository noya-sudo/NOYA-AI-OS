const blockedDomainsAll = ['linkedin.com','instagram.com','facebook.com','twitter.com','x.com','youtube.com','pinterest.com','tiktok.com','wikipedia.org','crunchbase.com','medium.com','reddit.com','quora.com','yahoo.com','google.com','apple.com','amazon.com','yelp.com','tripadvisor.com','trustpilot.com','glassdoor.com','indeed.com'];
const blockedDirectOnly = ['bloomberg.com','forbes.com','businessoffashion.com','vogue.com','wwd.com','glossy.co','prnewswire.com','businesswire.com','nytimes.com','cnn.com','techcrunch.com','wsj.com','globenewswire.com'];
const GENERIC_TITLE_DENYLIST = ['home','about','about us','contact','contact us','campaigns','campaign','news','blog','press','media','welcome','index','shop','store','products','services','portfolio','projects','careers','faq','sitemap','privacy policy','terms'];
function hostnameToName(domain) {
  const base = domain.split('.')[0];
  return base.split(/[-_]/).map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1); }).join(' ');
}
const config = $('Generate Search Queries').first().json;
const items = $input.all();
const seenDomains = {};
const candidates = [];
let totalOrganic = 0;
let serperErrorCount = 0;
let serperErrorSample = '';
const rawResultsByFamily = {};
function bump(map, fam, lane) { if (!map[fam]) { map[fam] = { direct: 0, signal: 0 }; } if (lane === 'SIGNAL') { map[fam].signal += 1; } else { map[fam].direct += 1; } }
for (let i = 0; i < items.length; i++) {
  const body = items[i].json;
  if (body && body.error) {
    serperErrorCount++;
    if (!serperErrorSample) { serperErrorSample = (body.error.message || JSON.stringify(body.error)).toString().slice(0, 300); }
    continue;
  }
  const organic = (body && body.organic) ? body.organic : [];
  const query = (body && body.searchParameters && body.searchParameters.q) ? body.searchParameters.q : '';
  const laneForQuery = (config.queryLaneMap && config.queryLaneMap[query]) ? config.queryLaneMap[query] : 'DIRECT';
  const sectorForQuery = (config.querySectorMap && config.querySectorMap[query]) ? config.querySectorMap[query] : 'UNCLASSIFIED';
  for (let j = 0; j < organic.length; j++) {
    totalOrganic++;
    bump(rawResultsByFamily, sectorForQuery, laneForQuery);
    const result = organic[j];
    if (!result.link) { continue; }
    const match = result.link.match(/^https?:\/\/([^\/]+)/i);
    if (!match) { continue; }
    let domain = match[1].replace(/^www\./i, '').toLowerCase();
    if (!domain) { continue; }

    // INSTAGRAM DISCOVERY (7 Oct 2026): a public Instagram profile becomes a lead only when its bio publishes the business
    // website or a business email; the candidate is that website and the Instagram page is kept as the source.
    let igSource = '', igName = '';
    if (domain === 'instagram.com') {
      const handleM = result.link.match(/instagram\.com\/([A-Za-z0-9_.]+)\/?(?:[?#]|$)/i);
      const bio = (result.title || '') + ' ' + (result.snippet || '');
      const mailDom = (bio.match(/[a-z0-9._%+-]+@([a-z0-9-]+(?:\.[a-z0-9-]+)+)/i) || [])[1];
      const site = (bio.replace(/[a-z0-9._%+-]+@[a-z0-9.-]+/gi, ' ').match(/\b(?:https?:\/\/)?(?:www\.)?((?:[a-z0-9-]+\.)+(?:com|co\.uk|co|net|org|uk|ae|sa|eg|fr|it|es|gr|ch|pt|qa|kw|lb|in|travel|events|studio|com\.eg))\b/i) || [])[1];
      const target = (mailDom && !/(gmail|hotmail|yahoo|outlook|icloud|live|aol)\./i.test(mailDom)) ? mailDom : site;
      if (!handleM || ['p', 'reel', 'reels', 'explore', 'stories', 'tv'].indexOf(handleM[1].toLowerCase()) >= 0 || !target
          || /(instagram|linktr|beacons|facebook|tiktok|later|lnk)\./i.test(target)) { continue; }
      igSource = result.link;
      igName = (result.title || '').split(' (@')[0].split(' • ')[0].trim();
      domain = target.toLowerCase().replace(/^www\./, '');
    }
    const lane = laneForQuery;
    const blockedDomains = lane === 'SIGNAL' ? blockedDomainsAll : blockedDomainsAll.concat(blockedDirectOnly);
    let blocked = false;
    for (let k = 0; k < blockedDomains.length; k++) { if (domain === blockedDomains[k] || domain.slice(-(blockedDomains[k].length + 1)) === ('.' + blockedDomains[k])) { blocked = true; break; } }
    if (blocked) { continue; }
    if (seenDomains[domain]) { continue; }
    seenDomains[domain] = true;
    let companyName = result.title ? result.title : domain;
    companyName = companyName.split(' | ')[0];
    companyName = companyName.split(' - ')[0];
    companyName = companyName.trim();
    if (igName) { companyName = igName; }
    if (!companyName || GENERIC_TITLE_DENYLIST.indexOf(companyName.toLowerCase()) !== -1 || companyName.length < 2) { companyName = hostnameToName(domain); }
    const sectorHint = sectorForQuery;
    candidates.push({ company_name: companyName, website: 'https://' + domain, domain: domain, source_url: result.link, search_evidence: (igSource ? 'Instagram profile ' + igSource + ': ' : '') + (result.snippet ? result.snippet : ''), search_query: query, lane: lane, sector_hint: sectorHint });
  }
}

// Family-aware normalisation -- replaces the old query-order-dependent
// global slice (directCap = max_results*3 taken in array order; signalCap
// flat 12 taken in array order). That slice filled entirely from whichever
// partnership family's queries returned usable results first (CONCIERGE_
// MEMBERSHIP is listed first in both query banks in Generate Search
// Queries), silently starving every other family before Merge & Cap
// Candidates ever saw them -- the confirmed root cause of the run 76/77
// diversity bottleneck (raw discovery pool was 100% CONCIERGE_MEMBERSHIP
// two runs in a row). Candidates are now grouped by sector_hint (the
// partnership-family metadata already carried end-to-end via
// config.querySectorMap) and capped PER FAMILY, independently for each
// lane, before any cross-family trimming -- so query order can no longer
// determine which families survive, only each candidate's own quality
// score can. Families are then visited strongest-best-candidate-first when
// filling the overall pool cap, so if a total cap is ever hit before every
// family gets a slot, the family dropped is the weakest one, never simply
// the one whose queries happened to run last.
const POSITIVE_SIGNALS = ['partnership','referral','white label','white-label','expansion','expands','opens office','new office','appoints','collaboration','joint venture','preferred partner','distribution agreement','launches service','launch','regional head','mena','middle east','dubai','riyadh','cairo','egypt','uae','uhnw','private client','concierge','membership'];
const NEGATIVE_SIGNALS = ['how to','buying guide','best of','top 10','top 5','directory','job','jobs','career','careers','definition','what is','recipe','review:',' vs ','wikipedia','glossary','magazine','publication'];
function scoreItem(c) {
  const text = ((c.company_name || '') + ' ' + (c.search_evidence || '') + ' ' + (c.search_query || '')).toLowerCase();
  let score = 0;
  POSITIVE_SIGNALS.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score += 1; } });
  NEGATIVE_SIGNALS.forEach(function (kw) { if (text.indexOf(kw) !== -1) { score -= 3; } });
  return score;
}
function familyBreakdown(items) { const out = {}; items.forEach(function (c) { const fam = c.sector_hint || 'UNCLASSIFIED'; out[fam] = (out[fam] || 0) + 1; }); return out; }
function pickFamilyAware(items, perFamilyCap, totalCap) {
  const groups = {};
  items.forEach(function (c) { const fam = c.sector_hint || 'UNCLASSIFIED'; if (!groups[fam]) { groups[fam] = []; } groups[fam].push(c); });
  const rankedGroups = {};
  Object.keys(groups).forEach(function (fam) {
    rankedGroups[fam] = groups[fam]
      .map(function (c, idx) { return { c: c, score: scoreItem(c), idx: idx }; })
      .sort(function (a, b) { return (b.score - a.score) || (a.idx - b.idx); })
      .slice(0, perFamilyCap)
      .map(function (r) { return r.c; });
  });
  const orderedFamilies = Object.keys(rankedGroups)
    .filter(function (fam) { return rankedGroups[fam].length > 0; })
    .sort(function (a, b) { return scoreItem(rankedGroups[b][0]) - scoreItem(rankedGroups[a][0]); });
  if (totalCap == null) {
    const flat = [];
    orderedFamilies.forEach(function (fam) { rankedGroups[fam].forEach(function (c) { flat.push(c); }); });
    return flat;
  }
  const result = [];
  let round = 0;
  let added = true;
  while (result.length < totalCap && added) {
    added = false;
    for (let i = 0; i < orderedFamilies.length && result.length < totalCap; i++) {
      const fam = orderedFamilies[i];
      if (rankedGroups[fam][round]) { result.push(rankedGroups[fam][round]); added = true; }
    }
    round++;
  }
  return result;
}

const perFamilyCap = config.max_results ? config.max_results : 3;
const FAMILY_COUNT_CEILING = 7;
const directPoolAll = candidates.filter(function (c) { return c.lane === 'DIRECT'; });
const signalPoolAll = candidates.filter(function (c) { return c.lane === 'SIGNAL'; });
const directCandidates = pickFamilyAware(directPoolAll, perFamilyCap, perFamilyCap * FAMILY_COUNT_CEILING);
const signalCandidates = pickFamilyAware(signalPoolAll, perFamilyCap, perFamilyCap * FAMILY_COUNT_CEILING);
const finalCandidates = directCandidates.concat(signalCandidates);

return [{ json: {
  candidates: finalCandidates,
  discoveredCount: finalCandidates.length,
  directDiscoveredCount: directCandidates.length,
  signalDiscoveredCount: signalCandidates.length,
  rawResultsSeen: totalOrganic,
  searchesExecuted: items.length,
  serperErrorCount: serperErrorCount,
  serperErrorSample: serperErrorSample,
  mission: config.mission,
  max_results: config.max_results,
  minimum_score: config.minimum_score,
  country_focus: config.country_focus,
  egypt_opportunity: config.egypt_opportunity,
  run_id: config.run_id,
  raw_results_by_family: rawResultsByFamily,
  valid_candidates_by_family_direct: familyBreakdown(directPoolAll),
  valid_candidates_by_family_signal: familyBreakdown(signalPoolAll),
  preserved_after_family_cap_direct: familyBreakdown(directCandidates),
  preserved_after_family_cap_signal: familyBreakdown(signalCandidates)
} }];