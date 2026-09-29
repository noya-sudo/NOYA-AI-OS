// DETERMINISTIC CEO BRIEF (29 Sep 2026). Runs whenever the AI writer fails, for any
// reason (provider billing, outage, empty output). The brief must always arrive: it is
// written straight from the verified action facts with no AI judgement, and labelled
// AI ENRICHMENT DEGRADED. Nothing is rejected, downgraded or discarded by a provider
// failure.
const facts = $('Assemble CEO Facts').first().json.facts;
const errItem = $input.first() ? $input.first().json : {};
const rawMessage = (errItem && errItem.error && errItem.error.message) ? errItem.error.message
  : (errItem && typeof errItem.error === 'string') ? errItem.error
  : (errItem && errItem.message) ? errItem.message
  : 'ai_brief_generation_failed';
const probe = String(rawMessage).toLowerCase();
const isBilling = /credit balance|insufficient|billing|quota|payment required|plans & billing|402/.test(probe)
  || probe === 'bad request - please check your parameters';
const failureClass = isBilling ? 'PROVIDER_BILLING_ERROR' : 'PROVIDER_ERROR';

let af = {};
try { af = JSON.parse($('Attach Daily Action Facts').first().json.action_facts_json) || {}; } catch (e) { af = {}; }
const hasActions = Array.isArray(af.adam_actions);

function s(v) { return v === null || v === undefined ? '' : String(v).replace(/\s+/g, ' ').trim(); }
function clip(v, n) { const t = s(v); return t.length > n ? t.slice(0, n - 1) + '…' : t; }
function money(label, value, cur) {
  if (label === 'MODEL_ESTIMATE' && value) return 'MODEL_ESTIMATE ' + (cur || 'USD') + ' ' + Math.round(Number(value)).toLocaleString('en-GB');
  return 'value UNKNOWN';
}
function channelOf(a) {
  if (a.email_status === 'VERIFIED') return 'Email';
  if (a.linkedin) return 'LinkedIn';
  if (a.instagram) return 'Instagram';
  return 'Channel to resolve';
}
function exactAction(a) {
  const src = String(a.task_latest || a.task_head || '');
  const m = src.match(/EXACT ACTION:\s*([^\n]+)/i) || src.match(/NEXT (?:STEP|ACTION):\s*([^\n]+)/i);
  return clip(m ? m[1] : (a.next_action || a.title || ''), 220);
}
function vertical(type, ctype) {
  const o = String(type || ''), c = String(ctype || '');
  if (/MEMBER|COMMUNITY|CLUB/i.test(c) || /MEMBER/i.test(o)) return 'MEMBER COMMUNITIES';
  if (/WEDDING/i.test(c) || /WEDDING/i.test(o)) return 'WEDDINGS / PRIVATE EVENTS';
  if (/CONCIERGE|TRAVEL_PARTNER|TRAVEL_ADVISOR|TRAVEL_AGENCY|DMC|DESTINATION_PARTNER/i.test(c) || /CONCIERGE|TRAVEL_TRADE|WHITE_LABEL|REFERRAL|DESTINATION_PARTNER/i.test(o)) return 'DESTINATION / CONCIERGE PARTNERS';
  if (/CORPORATE|EVENT_AGENCY|FAMILY_OFFICE|BANK|WEALTH|LAW|CONSULT|INVEST/i.test(c) || /CORPORATE|RETREAT|EXECUTIVE|INCENTIVE|FAMILY_OFFICE|PRIVATE_BANK/i.test(o)) return 'CORPORATE / EVENTS';
  if (/HOTEL|RESORT|HOSPITALITY/i.test(c) || /HOTEL/i.test(o)) return 'HOTELS / CONTENT';
  if (/BRAND|PRODUCTION|AGENCY|PR_|CREATIVE|FASHION|BEAUTY|AUTOMOTIVE|LUXURY|MEDIA/i.test(c) || /BRAND|PRODUCTION|CAMPAIGN|SHOOT|ACTIVATION|CREATOR_TRIP|LAUNCH/i.test(o)) return 'BRAND & PRODUCTION';
  return 'OTHER';
}

const L = [];
L.push('# NOYA — DAILY COMMERCIAL ACTION BRIEF');
L.push('**' + s(af.brief_date_cairo || String(facts.period_end).slice(0, 10)) + '**');
L.push('');
L.push('> **AI ENRICHMENT DEGRADED** — the AI writer was unavailable (' + failureClass + '), so this brief was assembled directly from verified CRM facts by a fixed template. Every company, person, status and date below comes from the database. Values are MODEL_ESTIMATE unless marked ACTUAL. Nothing was rejected or downgraded because of the provider failure.');
L.push('');
if (!hasActions) {
  L.push('> The daily action facts could not be read this run. The summary figures below are still verified.');
  L.push('');
}

const actions = hasActions ? af.adam_actions.slice() : [];
actions.sort(function (a, b) { return (a.rank_bucket || 9) - (b.rank_bucket || 9) || (b.task_priority || 0) - (a.task_priority || 0); });
const doToday = actions.filter(function (a) { return a.task_type !== 'PROVIDER_HEALTH_ALERT' && a.task_type !== 'SYSTEM_ALERT' && a.task_type !== 'SYSTEM_FAILURE_ALERT'; }).slice(0, 7);

L.push('## 1. DO TODAY');
if (!doToday.length) L.push('- No open actions on file.');
doToday.forEach(function (a, i) {
  L.push('- **' + (a.p_level || ('P' + (i + 1))) + ' · ' + s(a.company || 'No company') + '** — ' + s(a.contact || 'no named contact') + (a.contact_role ? ' (' + clip(a.contact_role, 70) + ')' : '')
    + ' · ' + channelOf(a) + ' · ' + money(a.value_label, a.value, a.currency));
  L.push('  - Action: ' + exactAction(a));
  L.push('  - Task: ' + clip(a.title, 120) + (a.due_at ? ' · due ' + String(a.due_at).slice(0, 10) : ''));
});
L.push('');

const replies = (af.replies_14d || []).filter(function (r) { return r.is_human_actionable; });
L.push('## 2. REPLIES NEEDING ACTION');
if (!replies.length) L.push('- None. (Automatic replies, out-of-office and intake forms are excluded.)');
replies.slice(0, 6).forEach(function (r) { L.push('- **' + s(r.company) + '** — ' + s(r.classification) + ' · ' + clip(r.summary, 200)); });
L.push('');

const ready = (af.ready_to_send || []).concat(af.adam_review_required || []);
L.push('## 3. READY TO APPROVE / SEND');
if (!ready.length) L.push('- Nothing waiting for approval.');
ready.slice(0, 8).forEach(function (r) { L.push('- **' + s(r.company) + '** — ' + clip(r.title || r.subject, 120) + ' · ' + money(r.value_label, r.value, r.currency)); });
L.push('');

L.push('## 4. FOLLOW-UPS DUE');
const fus = af.follow_ups_due || [];
if (!fus.length) L.push('- None due.');
fus.slice(0, 8).forEach(function (f) { L.push('- **' + s(f.company) + '** — ' + clip(f.title, 120) + (f.due_at ? ' · due ' + String(f.due_at).slice(0, 10) : '')); });
L.push('');

L.push('## 5. CONTACTS TO RESOLVE');
const waiting = af.waiting_for_contact || [];
if (!waiting.length) L.push('- None.');
waiting.slice(0, 8).forEach(function (w) { L.push('- **' + s(w.company) + '** — ' + clip(w.title, 110) + ' · ' + money(w.value_label, w.value, w.currency)); });
L.push('');

const opps = af.active_opportunities || [];
const late = opps.filter(function (o) { return /CALL_REQUIRED|PROPOSAL|NEGOTIATION|INTERESTED/.test(String(o.status)); });
L.push('## 6. MEETINGS & PROPOSALS');
if (!late.length) L.push('- No meeting, proposal or negotiation stage opportunities on file.');
late.forEach(function (o) { L.push('- **' + s(o.company_name) + '** — ' + s(o.status) + ' · ' + clip(o.next_action, 140)); });
L.push('');

L.push('## 7. OPPORTUNITIES BY VERTICAL');
const ORDER = ['BRAND & PRODUCTION', 'CORPORATE / EVENTS', 'WEDDINGS / PRIVATE EVENTS', 'MEMBER COMMUNITIES', 'DESTINATION / CONCIERGE PARTNERS', 'HOTELS / CONTENT', 'OTHER'];
const byV = {};
opps.forEach(function (o) { const v = vertical(o.opportunity_type, o.company_type); (byV[v] = byV[v] || []).push(o); });
ORDER.forEach(function (v) {
  const list = (byV[v] || []).sort(function (a, b) { return (b.priority || 0) - (a.priority || 0); });
  if (!list.length) return;
  L.push('### ' + v + ' (' + list.length + ')');
  list.slice(0, 5).forEach(function (o) {
    L.push('- **' + s(o.company_name) + '** (' + (o.priority || '-') + ') — ' + clip(o.reason, 150) + ' · Next: ' + clip(o.next_action, 120));
  });
});
L.push('');

L.push('## 8. DISCOVERY (last 24h)');
const disc = af.discovery_last_24h || [];
if (!disc.length) L.push('- No new qualified opportunities in the last 24 hours.');
disc.forEach(function (d) { L.push('- ' + s(d.department) + ': ' + (d.qualified_opportunities || 0) + ' qualified, ' + (d.watchlist_companies || 0) + ' watchlist'); });
L.push('');

L.push('## 9. SYSTEM / COST');
const hy = af.task_hygiene || {};
L.push('- Tasks: ' + (hy.open || 0) + ' open · ' + (hy.overdue || 0) + ' overdue · ' + (hy.duplicate_groups || 0) + ' duplicate groups · ' + (hy.waiting || 0) + ' waiting');
L.push('- AI writer: ' + failureClass + ' — ' + clip(rawMessage, 160));
const rev = af.actual_revenue || [];
L.push('- ACTUAL revenue on file: ' + (rev.length ? rev.map(function (r) { return s(r.currency) + ' ' + s(r.amount); }).join(', ') : 'none recorded'));
L.push('- ' + s(af.value_policy || 'Opportunity values are MODEL_ESTIMATE.'));

return [{ json: {
  text: L.join('\n'),
  ai_status: 'AI_ENRICHMENT_DEGRADED',
  failure_class: failureClass,
  is_billing_failure: isBilling,
  error_message: rawMessage
} }];
