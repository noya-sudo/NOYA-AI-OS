const staticData = $getWorkflowStaticData('global');
const runId = $('Mission Configuration').first().json.run_id;
const runData = (staticData.runs && staticData.runs[runId]) ? staticData.runs[runId] : {};
// RECENTLY-RESEARCHED SKIP (28 Sep 2026): a domain already in the CRM (seeded below) or
// sent to research in the last 60 days never takes one of today's research slots again.
// Before this, re-discovered companies filled the slots and were only rejected as
// duplicates after the paid research calls (run 328: 4 of 4 slots were duplicates).
const RECENT_SKIP_DAYS = 60;
const SEED_KNOWN_DOMAINS = ["aldoshoes.com", "aman.com", "apparelgroup.com", "arabbank.ch", "armanihotels.com", "bezanzibar.com", "buubble.com", "cambridgeassociates.com", "charleskeith.com", "charlesrussellspeechlys.com", "chase.com", "citrincooperman.com", "colincowie.com", "davidtutera.com", "db.com", "divaforevents.com", "emiratesnbd.sg", "etihad.com", "hawksford.com", "hilton.com", "ir.noahgroup.com", "jetex.com", "jpmorgan.com", "juliusbaer.com", "letshyde.com", "lombardodier.com", "maerki-baumann.ch", "mandarinoriental.com", "nobuhotels.com", "northerntrust.com", "oliveam.com", "qode.world", "quintessentially.com", "radissonhotels.com", "rafanellievents.com", "rainmakerevents.ae", "raymondjames.com", "redcarpetevents.in", "rothschildandco.com", "scarletevents.com", "septem-event-services.com", "tartecosmetics.com", "themusehotel.com", "toyota.com", "ubp.com", "ubs.com"];
if (!staticData.researchedDomains) { staticData.researchedDomains = {}; }
if (!staticData.researchedDomainsSeeded) {
  SEED_KNOWN_DOMAINS.forEach(function (d) { staticData.researchedDomains[d] = Date.now(); });
  staticData.researchedDomainsSeeded = true;
}
function domainKey(c) { return (c.domain || '').toLowerCase().replace(/^www\./, ''); }

// ACCOUNT IDENTITY + THROTTLE (29 Sep 2026): the CRM's registrable domains come from
// "Read Discovery Context" (discovery_context RPC). A subdomain of a known account
// (privatebank.jpmorgan.com vs jpmorgan.com) is the same account and is skipped before
// any paid research. Shared hosting / social hosts keep the tenant as the identity.
// research_cap shrinks when Adam's conversion backlog is high (conversion first).
const discoveryCtx = (function () { try { return $('Read Discovery Context').first().json || {}; } catch (e) { return {}; } })();
const knownAccounts = {};
(Array.isArray(discoveryCtx.known_domains) ? discoveryCtx.known_domains : []).forEach(function (d) { if (d) knownAccounts[String(d).toLowerCase()] = true; });
const SHARED_HOSTS = /(^|\.)(wixsite\.com|squarespace\.com|myshopify\.com|blogspot\.com|github\.io|wordpress\.com|webflow\.io|carrd\.co|linktr\.ee|instagram\.com|linkedin\.com|facebook\.com|tiktok\.com|x\.com|twitter\.com|google\.com|notion\.site|beacons\.ai)$/;
function registrableDomain(host) {
  host = String(host || '').toLowerCase().replace(/^[a-z]+:\/\//, '').replace(/^www\d?\./, '').replace(/[\/?#:].*$/, '');
  if (!host || host.indexOf('.') < 0) return host || '';
  if (SHARED_HOSTS.test(host)) return host;
  const a = host.split('.');
  const n = a.length;
  if (n >= 3 && ['co','com','org','net','gov','ac','edu','ltd','plc','me'].indexOf(a[n - 2]) >= 0 && a[n - 1].length === 2) return a.slice(n - 3).join('.');
  return a.slice(n - 2).join('.');
}
let knownAccountSkipped = 0;
function notKnownAccount(c) {
  const r = registrableDomain(domainKey(c));
  if (r && knownAccounts[r]) { knownAccountSkipped++; return false; }
  return true;
}
let recentlyResearchedSkipped = 0;
function notRecentlyResearched(c) {
  const k = domainKey(c);
  const rk = registrableDomain(k);
  const t = k ? (staticData.researchedDomains[k] || staticData.researchedDomains[rk]) : null;
  if (t && (Date.now() - t) < RECENT_SKIP_DAYS * 86400000) { recentlyResearchedSkipped++; return false; }
  return true;
}
function markResearched(list) {
  list.forEach(function (c) { const k = domainKey(c); if (k) { staticData.researchedDomains[k] = Date.now(); const rk = registrableDomain(k); if (rk) { staticData.researchedDomains[rk] = Date.now(); } } });
}
const direct = (runData.directCandidates || []).filter(notKnownAccount).filter(notRecentlyResearched);
const resolvedRaw = (runData.signalResolvedCandidates || []).filter(notKnownAccount).filter(notRecentlyResearched);

// Volume (Adam, 8 Oct 2026): the ceiling is 12; discovery_throttle.normal_research_cap in system_config sets the live cap.
const BASE_RESEARCH_CAP = 12;
const FINAL_RESEARCH_CAP = (typeof discoveryCtx.research_cap === 'number') ? Math.max(0, Math.min(BASE_RESEARCH_CAP, discoveryCtx.research_cap)) : BASE_RESEARCH_CAP;
const DIVERSITY_TOLERANCE = 20;

const POSITIVE_WORDS = ['expansion','expands','opens office','new office','regional headquarters','announces','launch','launches','appoints','appointment','partnership','partners with','retreat','offsite','summit','hosts','hosted','client experience','private client','family office','wealth management','delegation','relocates','hires','raises fund','closes fund','portfolio company','2026','middle east','mena','dubai','cairo','egypt','riyadh','uae'];
const NEGATIVE_WORDS = ['how to','buying guide','best of','top 10','top 5','directory','glossary','wikipedia','definition','what is','review:',' vs ','job','jobs','career','careers','recipe','ultimate guide','tips','ideas'];
const NEGATIVE_STRONG_WORDS = ['tourism board','tourism authority','ministry of','government of','embassy of'];
const STRENGTH_BONUS = { HIGH: 20, MEDIUM: 10, LOW: 0 };

function textOf(c) {
  return [c.company_name, c.search_evidence, c.search_query, c.campaign_type, c.commercial_signal].filter(Boolean).join(' ').toLowerCase();
}
function qualityScore(c) {
  const text = textOf(c);
  let score = 50;
  POSITIVE_WORDS.forEach(function (w) { if (text.indexOf(w) !== -1) { score += 8; } });
  NEGATIVE_WORDS.forEach(function (w) { if (text.indexOf(w) !== -1) { score -= 15; } });
  NEGATIVE_STRONG_WORDS.forEach(function (w) { if (text.indexOf(w) !== -1) { score -= 30; } });
  if (c.signal_strength) { score += STRENGTH_BONUS[(c.signal_strength || '').toUpperCase()] || 0; }
  return Math.max(0, Math.min(130, score));
}
function domainOf(c) { return (c.domain || '').toLowerCase(); }
function sectorOf(c) { return c.sector_hint || 'UNCLASSIFIED'; }

const pool = {};
direct.forEach(function (c) {
  const key = domainOf(c);
  if (!key) { return; }
  const scored = { candidate: Object.assign({}, c, { lane: 'DIRECT' }), sector: sectorOf(c), score: qualityScore(c) };
  if (!pool[key] || pool[key].score < scored.score) { pool[key] = scored; }
});
resolvedRaw.forEach(function (c) {
  const key = domainOf(c);
  if (!key) { return; }
  const scored = { candidate: Object.assign({}, c, { lane: 'SIGNAL_RESOLVED' }), sector: sectorOf(c), score: qualityScore(c) };
  if (!pool[key] || pool[key].score < scored.score) { pool[key] = scored; }
});

const ranked = Object.keys(pool).map(function (k) { return pool[k]; }).sort(function (a, b) { return b.score - a.score; });

const selected = [];
const selectedSectors = {};
let diversitySwaps = 0;
const remaining = ranked.slice();

if (FINAL_RESEARCH_CAP > 0 && remaining.length > 0) {
  const first = remaining.shift();
  selected.push(first);
  selectedSectors[first.sector] = (selectedSectors[first.sector] || 0) + 1;
}

while (selected.length < FINAL_RESEARCH_CAP && remaining.length > 0) {
  const best = remaining[0];
  const bestSectorSeen = !!selectedSectors[best.sector];
  let pick = best;
  let pickIdx = 0;
  if (bestSectorSeen) {
    for (let i = 1; i < remaining.length; i++) {
      const alt = remaining[i];
      if ((best.score - alt.score) > DIVERSITY_TOLERANCE) { break; }
      if (!selectedSectors[alt.sector]) { pick = alt; pickIdx = i; diversitySwaps++; break; }
    }
  }
  selected.push(pick);
  selectedSectors[pick.sector] = (selectedSectors[pick.sector] || 0) + 1;
  remaining.splice(pickIdx, 1);
}

const capped = selected.map(function (s) { return s.candidate; });
markResearched(capped);

const sectorsDiscoveredPool = {};
ranked.forEach(function (s) { sectorsDiscoveredPool[s.sector] = (sectorsDiscoveredPool[s.sector] || 0) + 1; });

if (staticData.runs && staticData.runs[runId]) {
  staticData.runs[runId].recentlyResearchedSkipped = recentlyResearchedSkipped;
  staticData.runs[runId]._finalCandidates = capped;
  staticData.runs[runId].directBrandCandidatesFinal = capped.filter(function (c) { return c.lane === 'DIRECT'; }).length;
  staticData.runs[runId].signalBrandCandidatesFinal = capped.filter(function (c) { return c.lane === 'SIGNAL_RESOLVED'; }).length;
  staticData.runs[runId].combinedBeforeCap = ranked.length;
  staticData.runs[runId].signalBrandsResolvedTotal = resolvedRaw.length;
  staticData.runs[runId].sectorsDiscoveredPool = sectorsDiscoveredPool;
  staticData.runs[runId].sectorsInFinalPool = selectedSectors;
  staticData.runs[runId].diversitySwaps = diversitySwaps;
}

return [{ json: { run_id: runId, finalCount: capped.length, recently_researched_skipped: recentlyResearchedSkipped + knownAccountSkipped, known_account_skipped: knownAccountSkipped, throttle_level: discoveryCtx.throttle_level || 'UNKNOWN', research_cap: FINAL_RESEARCH_CAP, backlog_total: (discoveryCtx.backlog && discoveryCtx.backlog.total != null) ? discoveryCtx.backlog.total : null, diversity_swaps: diversitySwaps, sectors_in_final_pool: selectedSectors, sectors_discovered_pool: sectorsDiscoveredPool } }];