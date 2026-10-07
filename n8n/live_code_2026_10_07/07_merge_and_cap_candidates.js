const staticData = $getWorkflowStaticData('global');
const runId = $('Mission Configuration').first().json.run_id;
const runData = (staticData.runs && staticData.runs[runId]) ? staticData.runs[runId] : {};
const direct = runData.directCandidates || [];
const resolvedRaw = runData.signalResolvedCandidates || [];

// 07 -- soft diversity allocator (reused from the proven 06 FINAL COMMERCIAL
// CALIBRATION design). Single quality-ranked pool across both lanes, then
// diversity applied only among genuinely comparable-quality candidates:
//   1. rank by quality
//   2. always keep the single strongest candidate overall
//   3. among candidates within DIVERSITY_TOLERANCE of the next pick, prefer
//      a partnership family not yet represented in the selection
//   4. never replace a clearly stronger candidate with a weaker one
// Allocation only -- does not touch qualification, scoring, minimum_score, or
// the PARTNERSHIP QUALITY GATE downstream of Score Prospect.
// Partnerships lane carries extra weight (Adam, 7 Oct): 6 companies researched per run.
const FINAL_RESEARCH_CAP = 6;
const DIVERSITY_TOLERANCE = 20;

const POSITIVE_WORDS = ['partnership','referral','white label','white-label','expansion','expands','opens office','new office','regional headquarters','announces','launch','launches','appoints','appointment','collaboration','joint venture','preferred partner','distribution agreement','membership','concierge','private client','uhnw','roster','charter','villa','destination management','2026','middle east','mena','dubai','cairo','egypt','riyadh','uae'];
const NEGATIVE_WORDS = ['how to','buying guide','best of','top 10','top 5','directory','glossary','wikipedia','definition','what is','review:',' vs ','job','jobs','career','careers','recipe','ultimate guide','tips','ideas'];
const NEGATIVE_STRONG_WORDS = ['tourism board','tourism authority','ministry of','government of','embassy of'];
const STRENGTH_BONUS = { HIGH: 20, MEDIUM: 10, LOW: 0 };

function textOf(c) { return [c.company_name, c.search_evidence, c.search_query, c.campaign_type, c.commercial_signal].filter(Boolean).join(' ').toLowerCase(); }
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
direct.forEach(function (c) { const key = domainOf(c); if (!key) { return; } const scored = { candidate: Object.assign({}, c, { lane: 'DIRECT' }), sector: sectorOf(c), score: qualityScore(c) }; if (!pool[key] || pool[key].score < scored.score) { pool[key] = scored; } });
resolvedRaw.forEach(function (c) { const key = domainOf(c); if (!key) { return; } const scored = { candidate: Object.assign({}, c, { lane: 'SIGNAL_RESOLVED' }), sector: sectorOf(c), score: qualityScore(c) }; if (!pool[key] || pool[key].score < scored.score) { pool[key] = scored; } });

const ranked = Object.keys(pool).map(function (k) { return pool[k]; }).sort(function (a, b) { return b.score - a.score; });

const selected = [];
const selectedSectors = {};
let diversitySwaps = 0;
const remaining = ranked.slice();

if (remaining.length > 0) { const first = remaining.shift(); selected.push(first); selectedSectors[first.sector] = (selectedSectors[first.sector] || 0) + 1; }

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

const sectorsDiscoveredPool = {};
ranked.forEach(function (s) { sectorsDiscoveredPool[s.sector] = (sectorsDiscoveredPool[s.sector] || 0) + 1; });

if (staticData.runs && staticData.runs[runId]) {
  staticData.runs[runId]._finalCandidates = capped;
  staticData.runs[runId].directBrandCandidatesFinal = capped.filter(function (c) { return c.lane === 'DIRECT'; }).length;
  staticData.runs[runId].signalBrandCandidatesFinal = capped.filter(function (c) { return c.lane === 'SIGNAL_RESOLVED'; }).length;
  staticData.runs[runId].combinedBeforeCap = ranked.length;
  staticData.runs[runId].signalBrandsResolvedTotal = resolvedRaw.length;
  staticData.runs[runId].sectorsDiscoveredPool = sectorsDiscoveredPool;
  staticData.runs[runId].sectorsInFinalPool = selectedSectors;
  staticData.runs[runId].diversitySwaps = diversitySwaps;
}

return [{ json: { run_id: runId, finalCount: capped.length, diversity_swaps: diversitySwaps, sectors_in_final_pool: selectedSectors, sectors_discovered_pool: sectorsDiscoveredPool } }];