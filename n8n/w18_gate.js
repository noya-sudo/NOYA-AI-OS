// Workflow 18 deterministic quality gate (Commercial Engine V2.1, 8 Oct 2026).
// Embedded verbatim into the "Quality Gate" code node by n8n/build_w18.py.
// No AI fact-checker: every claim must be checkable against the evidence stored for the account.

var BANNED = [/i am reaching out/, /i'?m reaching out/, /wanted to reach out/, /reaching out to/, /wanted to introduce/, /been following/,
  /love what you/, /big fan/, /are you open to a (brief|quick) call/, /worth a (quick )?chat/, /let me know if you('d| would) be interested/,
  /end-to-end/, /infrastructure/, /i hope/, /world[- ]class/, /unparalleled/, /elevate/, /seamless/, /bespoke/, /synerg/, /exclusive access/,
  /luxury experiences/, /i came across/, /hope this (email|message) finds/, /partnership opportunit/, /mutually beneficial/, /leverage/];

// Presumptions about the recipient: what they need, lack, plan or feel. Not allowed unless quoted from evidence.
var PRESUME = [/\bmay (require|need|want|be looking)/, /\bmight (need|require|want)/, /\b(remains?|is|are) (an? )?(untapped|unclaimed|unexplored|overlooked)/,
  /\buntapped\b/, /\bsuggests? (a|an|that|your|you|potential|strong|clear)\b/, /\b(clear|strong|obvious) (focus|appetite|affinity|preference|need)\b/,
  /\byou(r team)? (need|require|are looking|are planning|will need|often|usually|lack)\b/,
  /\byour (clients|players|guests|customers|team|families|members)( often| usually| typically| regularly)? (need|want|seek|require|look for|ask for|prefer|use)\b/,
  /\b(requires?|creates?) (a |an )?((complex|significant|real|growing) )?(logistical|need|requirement|demand)/, /\blogical (frontier|next step|addition|fit)/,
  /\bnatural next step/, /\baligns? perfectly/, /\bperfect fit/, /\bcompetitors?\b/, /\b(lack|lacks|lacking)\b/, /\bgap in\b/, /\bstruggl/, /\bpain point/,
  /\bas you (expand|grow|plan|look|scale|move)/, /\byour (upcoming|planned) /, /\bwell[- ]positioned/, /\b(rising|increasing|growing) demand/,
  /\b(few|no other|none of the|not many) (\w+ )?(brands|companies|planners|agencies|operators|competitors|clubs)\b/, /\bfirst (brand|company|planner) to\b/];

// Proper nouns the draft may use without evidence: NOYA, its founder, Egypt geography and common place/channel names.
var ALLOWED = ('noya adam elshazly concierge egypt egyptian cairo giza luxor aswan nile red sea north coast sahel gouna el hurghada sharm sheikh sinai siwa ' +
  'alexandria western desert white soma bay marsa alam dahab gem grand museum pyramids pyramid upper london dubai uk europe european middle east gulf ' +
  'linkedin hi january february march april may june july august september october november december jan feb mar apr jun jul aug sep sept oct nov dec ' +
  'monday tuesday wednesday thursday friday saturday sunday i ss26 aw26 ss27').split(' ');
// Ordinary words that can start a sentence.
var COMMON = ('a an and as at but by for from given having here if in into it its no not of on one our so that the their then there these this those to ' +
  'two three four five we when where which while who with would could should shall can may might happy glad ahead after before since both each every ' +
  'also just congratulations thanks thank worth noted saw read seeing reading with what how why your you yours my me i ' +
  'egypt noya cairo').split(' ');
var STOP = ('the and for with from that this their they have has into over across after before about which while where there these those based brand brands company ' +
  'campaign campaigns travel luxury egypt noya would could should more most such other also been being per new using used through including include').split(' ');

function parseDraft(t) {
  t = String(t || '');
  var s = t.indexOf('{'), e = t.lastIndexOf('}');
  try { if (s >= 0 && e > s) { var o = JSON.parse(t.slice(s, e + 1)); return { subject: String(o.subject || '').trim(), message: String(o.message || '').trim() }; } } catch (err) {}
  return { subject: '', message: t.trim() };
}
// Gemini generateContent response (or an n8n error item) -> text + usage record.
function readGemini(r, model, purpose) {
  r = r || {};
  var err = r.error ? (typeof r.error === 'string' ? r.error : (r.error.message || JSON.stringify(r.error))) : '';
  var u = r.usageMetadata || {};
  var text = '';
  try { text = (r.candidates[0].content.parts || []).filter(function (p) { return !p.thought; }).map(function (p) { return p.text || ''; }).join(''); } catch (e2) { text = ''; }
  var rl = /429|too many requests|resource[_ ]exhausted|quota|rate limit/i.test(err);
  return { text: text, error: err, rate_limited: rl,
    usage: { purpose: purpose, model: model, input_tokens: u.promptTokenCount || 0, output_tokens: u.candidatesTokenCount || 0,
             thinking_tokens: u.thoughtsTokenCount || 0, status: err ? (rl ? 'RATE_LIMITED' : 'ERROR') : 'OK' } };
}
function tokens(s) { return (String(s || '').match(/[A-Za-z0-9][A-Za-z0-9'-]{3,}/g) || []).map(function (w) { return w.toLowerCase(); }); }
function corpusOf(it) {
  return [it.company, it.first_name, it.last_name, it.position, it.country, it.company_type, it.evidence, it.why_now, it.angle, it.contact_notes, it.warm_route]
    .filter(Boolean).join(' \n ').toLowerCase().replace(/[’]/g, "'");
}
function inCorpus(corpus, w) {
  w = w.toLowerCase().replace(/[’]/g, "'").replace(/'s$/, '');
  if (!w) return true;
  var re = new RegExp('(^|[^a-z0-9])' + w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '([^a-z0-9]|$)');
  return re.test(corpus);
}
// Capitalised words and numbers in the draft must come from the evidence (or the allowed lists).
function evidenceCheck(it, m) {
  var corpus = corpusOf(it), bad = [];
  var body = m.replace(/^hi [^,]+,\s*/i, '');
  body.split(/(?<=[.?!:;])\s+|\n+/).forEach(function (sentence) {
    var words = sentence.match(/[A-Za-z][A-Za-z0-9'’&+-]*/g) || [];
    words.forEach(function (w, i) {
      if (!/^[A-Z]/.test(w)) return;
      var base = w.replace(/['’]s$/, '').toLowerCase();
      if (ALLOWED.indexOf(base) >= 0) return;
      if (i === 0 && COMMON.indexOf(base) >= 0) return;
      if (inCorpus(corpus, base) || (/s$/.test(base) && inCorpus(corpus, base.slice(0, -1)))) return;
      if (bad.indexOf(w) < 0) bad.push(w);
    });
  });
  (body.match(/\d[\d,.%]*/g) || []).forEach(function (n) {
    var core = n.replace(/[.,]+$/, '');
    if (/^(1[05]|20|30)$/.test(core) && new RegExp(core + '[- ]?(minutes?|mins?)').test(body)) return;
    if (corpus.indexOf(core.toLowerCase()) >= 0) return;
    if (bad.indexOf(core) < 0) bad.push(core);
  });
  return bad;
}
function gate(it, d) {
  var m = d.message || '', low = m.toLowerCase().replace(/[’]/g, "'"), issues = [];
  if (!m) { issues.push('EMPTY'); return { issues: issues, evidence_terms: [], unsupported: [] }; }
  BANNED.forEach(function (r) { if (r.test(low)) issues.push('BANNED: ' + r.source); });
  PRESUME.forEach(function (r) { if (r.test(low)) issues.push('PRESUMPTUOUS: ' + (low.match(r) || [''])[0]); });
  if (/(admire|admired|i'?ve seen your|caught my eye|really enjoyed|so impressed)/.test(low)) issues.push('FALSE_FAMILIARITY');
  if (/(amazing|incredible|stunning|impressive|fantastic|beautiful|inspiring|iconic) (work|brand|campaign|collection|events?|weddings?)/.test(low)) issues.push('UNSUPPORTED_COMPLIMENT');
  var lux = (low.match(/\b(luxury|luxurious|exclusive|premium|curated|exquisite|elite|high-end|discerning)\b/g) || []).length;
  if (lux > 1) issues.push('TOO_MANY_LUXURY_ADJECTIVES(' + lux + ')');
  var noya = (m.match(/NOYA/g) || []).length;
  if (noya > (it.channel === 'EMAIL' ? 2 : 1)) issues.push('REPEATED_NOYA_BIOGRAPHY');
  if (/[!]|\[|\]|\{\{/.test(m)) issues.push('FORMAT(! or placeholder)');
  if ((m.match(/\?/g) || []).length > 1) issues.push('MORE_THAN_ONE_QUESTION');
  if (it.first_name && m.indexOf('Hi ' + it.first_name) !== 0 && it.channel !== 'INSTAGRAM') issues.push('GREETING');
  var words = m.split(/\s+/).filter(Boolean).length;
  if (it.channel === 'EMAIL' && (words < 85 || words > 140)) issues.push('LENGTH(' + words + ' words; email 90-130)');
  if (it.channel === 'LINKEDIN' && (m.length < 200 || m.length > 300)) issues.push('LENGTH(' + m.length + ' chars; LinkedIn 220-280)');
  if (it.channel === 'INSTAGRAM' && (m.length < 120 || m.length > 420)) issues.push('LENGTH(' + m.length + ' chars)');
  if (it.channel === 'EMAIL' && (!d.subject || d.subject.length > 60)) issues.push('SUBJECT');
  var unsupported = evidenceCheck(it, m);
  if (unsupported.length) issues.push('UNSUPPORTED_TERMS: ' + unsupported.slice(0, 6).join(', '));
  var nameT = tokens(it.company).concat(tokens(it.first_name), tokens(it.last_name));
  var ev = tokens((it.evidence || '') + ' ' + (it.why_now || '')).filter(function (w) { return STOP.indexOf(w) < 0 && nameT.indexOf(w) < 0; });
  var hit = ev.filter(function (w, i) { return ev.indexOf(w) === i && low.indexOf(w) >= 0; });
  if (hit.length < 2) issues.push('NOT_PERSONALISED(evidence terms used: ' + hit.length + ')');
  var swapped = low.split(String(it.company || '').toLowerCase()).join('acme');
  if (hit.length < 2 && swapped !== low) issues.push('COMPANY_NAME_SWAP_TEST_FAILED');
  return { issues: issues, evidence_terms: hit, unsupported: unsupported };
}
// Batch-level: the same closing line more than twice in one run reads as automation.
function lastSentence(it, m) {
  var s = String(m || '').split(/(?<=[.?!])\s+/).filter(Boolean);
  return (s[s.length - 1] || '').toLowerCase().replace(new RegExp(String(it.company || '#').toLowerCase(), 'g'), '').replace(/[^a-z ]/g, '').trim();
}
var SIG = '\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com';
