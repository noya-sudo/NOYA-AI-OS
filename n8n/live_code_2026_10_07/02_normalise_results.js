const blockedDomainsAll = ['linkedin.com','instagram.com','facebook.com','twitter.com','x.com','youtube.com','pinterest.com','tiktok.com','wikipedia.org','crunchbase.com','medium.com','reddit.com','quora.com','yahoo.com','google.com','apple.com','amazon.com','yelp.com','tripadvisor.com','trustpilot.com','glassdoor.com','indeed.com'];
const blockedDirectOnly = ['bloomberg.com','forbes.com','businessoffashion.com','vogue.com','wwd.com','glossy.co','prnewswire.com','businesswire.com','nytimes.com','cnn.com','techcrunch.com','wsj.com','globenewswire.com'];
const GENERIC_TITLE_DENYLIST = ['home','about','about us','contact','contact us','campaigns','campaign','news','blog','press','media','welcome','index','shop','store','products','services','portfolio','projects','careers','faq','sitemap','privacy policy','terms','become an ambassador','ambassador'];
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
for (let i = 0; i < items.length; i++) {
  const body = items[i].json;
  if (body && body.error) {
    serperErrorCount++;
    if (!serperErrorSample) {
      serperErrorSample = (body.error.message || JSON.stringify(body.error)).toString().slice(0, 300);
    }
    continue;
  }
  const organic = (body && body.organic) ? body.organic : [];
  const query = (body && body.searchParameters && body.searchParameters.q) ? body.searchParameters.q : '';
  for (let j = 0; j < organic.length; j++) {
    totalOrganic++;
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
    const lane = (config.queryLaneMap && config.queryLaneMap[query]) ? config.queryLaneMap[query] : 'DIRECT';
    const blockedDomains = lane === 'SIGNAL' ? blockedDomainsAll : blockedDomainsAll.concat(blockedDirectOnly);
    let blocked = false;
    for (let k = 0; k < blockedDomains.length; k++) {
      if (domain === blockedDomains[k] || domain.slice(-(blockedDomains[k].length + 1)) === ('.' + blockedDomains[k])) { blocked = true; break; }
    }
    if (blocked) { continue; }
    if (seenDomains[domain]) { continue; }
    seenDomains[domain] = true;
    let companyName = result.title ? result.title : domain;
    companyName = companyName.split(' | ')[0];
    companyName = companyName.split(' - ')[0];
    companyName = companyName.trim();
    if (igName) { companyName = igName; }
    if (!companyName || GENERIC_TITLE_DENYLIST.indexOf(companyName.toLowerCase()) !== -1 || companyName.length < 2) {
      companyName = hostnameToName(domain);
    }
    candidates.push({ company_name: companyName, website: 'https://' + domain, domain: domain, source_url: result.link, search_evidence: (igSource ? 'Instagram profile ' + igSource + ': ' : '') + (result.snippet ? result.snippet : ''), search_query: query, lane: lane });
  }
}
const directCap = (config.max_results ? config.max_results : 10) * 3;
const signalCap = 12;
const directCandidates = candidates.filter(function (c) { return c.lane === 'DIRECT'; }).slice(0, directCap);
const signalCandidates = candidates.filter(function (c) { return c.lane === 'SIGNAL'; }).slice(0, signalCap);
const finalCandidates = directCandidates.concat(signalCandidates);
return [{ json: { candidates: finalCandidates, discoveredCount: finalCandidates.length, directDiscoveredCount: directCandidates.length, signalDiscoveredCount: signalCandidates.length, rawResultsSeen: totalOrganic, searchesExecuted: items.length, serperErrorCount: serperErrorCount, serperErrorSample: serperErrorSample, mission: config.mission, max_results: config.max_results, minimum_score: config.minimum_score, country_focus: config.country_focus, egypt_opportunity: config.egypt_opportunity, run_id: config.run_id } }];