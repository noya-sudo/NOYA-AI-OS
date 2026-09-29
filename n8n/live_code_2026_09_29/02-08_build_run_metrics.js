// RUN METRICS (28 Sep 2026): usage + funnel counts for cost observability and
// discovery diagnostics. Read-only over this run's own node outputs; never blocks
// the department (errors are swallowed and the logging branch simply ends).
function pick(fn) { try { return fn(); } catch (e) { return null; } }
function num(v) { return (typeof v === 'number' && isFinite(v)) ? v : null; }
var report = pick(function () { return $('Final Report').first().json; }) || {};
var flat = {};
var rejectReasons = {};
function walk(o, depth) {
  if (!o || typeof o !== 'object' || depth > 1) return;
  Object.keys(o).forEach(function (k) {
    var v = o[k];
    if (typeof v === 'number') { if (!(k in flat)) flat[k] = v; }
    else if (k === 'reject_reasons' && v && typeof v === 'object' && !Array.isArray(v)) { rejectReasons = v; }
    else if (v && typeof v === 'object' && !Array.isArray(v)) { walk(v, depth + 1); }
  });
}
walk(report, 0);
function rr(keys) { var t = 0; keys.forEach(function (k) { t += Number(rejectReasons[k] || 0); }); return t; }
var researchedKey = Object.keys(flat).filter(function (k) { return /_researched$/.test(k); })[0];
var norm = pick(function () { return $('Normalise Candidates').first().json; }) || {};
var cap = pick(function () { return $('Merge & Cap Candidates').first().json; }) || {};
// Firecrawl and throttle counters also live in this run's static data (the Track Firecrawl
// nodes increment them). 04 and 06 never copied them into their Final Report, so the
// report-only read logged null there (29 Sep fix).
var runCounters = pick(function () {
  var s = $getWorkflowStaticData('global');
  var rid = $('Mission Configuration').first().json.run_id;
  return (s.runs && s.runs[rid]) || null;
}) || {};
function firstNum() { for (var i = 0; i < arguments.length; i++) { var v = num(arguments[i]); if (v !== null) return v; } return null; }
// AI calls: one call per item processed by each AI node in this run (estimate).
function itemsOf(name) { return pick(function () { return $(name).all().length; }) || 0; }
var aiCalls = itemsOf('AI Entity Extraction') + itemsOf('AI Direct Entity Extraction') + itemsOf('AI Qualification');
var metrics = {
  candidates_found: num(norm.discoveredCount),
  serper_searches: num(norm.searchesExecuted),
  known_skipped: num(cap.recently_researched_skipped),
  deep_researched: researchedKey ? flat[researchedKey] : num(cap.finalCount),
  wrong_entity_type: rr(['WRONG_MISSION_TYPE', 'WRONG_ENTITY_TYPE', 'INVALID_ENTITY', 'NOT_A_COMPANY']),
  failed_noya_fit: rr(['BELOW_SCORE_THRESHOLD', 'LOW_FIT', 'NO_NOYA_FIT']),
  failed_signal: rr(['STALE_SIGNAL', 'NO_SIGNAL', 'WEAK_SIGNAL']),
  qualified: num(flat.qualified),
  duplicates: num(flat.duplicates),
  firecrawl_calls: firstNum(flat.firecrawl_calls_attempted, runCounters.firecrawlCallsAttempted),
  firecrawl_rate_limited: firstNum(flat.firecrawl_rate_limited, runCounters.firecrawlRateLimited),
  known_account_skipped: num(cap.known_account_skipped),
  throttle_level: cap.throttle_level || null,
  research_cap: num(cap.research_cap),
  backlog_total: num(cap.backlog_total),
  ai_calls_estimated: aiCalls,
  ai_model: 'gateway:gemini-3.1-flash-lite (fallback gpt-5-mini)',
  provider_failures: num(flat.provider_failures),
  reject_reasons: rejectReasons,
  report_counts: flat
};
return [{ json: { body: { workflow_id: $workflow.id, workflow_name: $workflow.name, run_id: String($execution.id), metrics: metrics } } }];
