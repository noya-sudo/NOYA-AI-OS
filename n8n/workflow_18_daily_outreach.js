import { workflow, node, trigger, ifElse, languageModel, expr } from '@n8n/workflow-sdk';

// 18 - NOYA Commercial Director: Daily Outreach (Commercial Engine V2, 7 Oct 2026)
// Plan (Supabase commercial_director_plan) -> draft (Gemini 3 Flash) -> hard quality gate ->
// one automatic redraft with the exact failure reasons -> save (READY / REVIEW_REQUIRED).
// Never sends anything. Dry run writes outreach_candidates only; live mode creates hand-send tasks for Adam.

const SUPABASE = 'https://gagbhykzmtstekpqujyl.supabase.co/rest/v1/rpc/';
const supabaseCred = { supabaseApi: { id: 'EkLYXHBGqNUjAGKP', name: 'Supabase account' } };
const geminiCred = { googlePalmApi: { id: 'tqsVAbFrBUJsN3Y0', name: 'Google Gemini(PaLM) Api account' } };

const manualRun = trigger({ type: 'n8n-nodes-base.manualTrigger', version: 1, config: { name: 'Manual Dry Run' } });
const weekday = trigger({
  type: 'n8n-nodes-base.scheduleTrigger', version: 1.2,
  config: { name: 'Weekdays 08:15 Cairo', parameters: { rule: { interval: [{ field: 'cronExpression', expression: '15 8 * * 1-5' }] } } }
});

// DRY RUN is the default everywhere until Adam approves live mode after reviewing the dry run.
const settings = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Run Settings',
    parameters: { mode: 'runOnceForAllItems', jsCode: "return [{ json: { p_dry_run: true, p_target: null, p_replan: false } }];" }
  }
});

const plan = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: {
    name: 'Commercial Director Plan',
    parameters: {
      method: 'POST', url: SUPABASE + 'commercial_director_plan',
      authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: expr('{{ JSON.stringify($json) }}'),
      options: { timeout: 60000 }
    },
    credentials: supabaseCred
  }
});

const buildPrompts = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Build Prompts',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode: `
var items = ($input.first().json.items) || [];
var LANE = {
  BRANDS: 'Brand / campaign opportunity. Suggest a specific campaign, creator, athlete or production idea in Egypt that fits THIS brand. NOYA handles the destination side end to end: locations, stays, movement, permits/local coordination, production support, hospitality.',
  PARTNERSHIPS: 'Partnership, NOT client acquisition. Answer: why would this company send business to NOYA? They keep their client; NOYA is their trusted Egypt specialist and on-ground execution partner (Cairo, Nile, Red Sea, North Coast, private-client handling, VIP requests).',
  WEDDINGS: 'Wedding / private event planner. The planner keeps the client and the creative direction; NOYA is the Egypt destination concierge and guest-logistics partner (guest travel, room blocks, VIP arrivals, transfers, guest concierge, pre/post experiences).',
  EGYPT_EVENTS: 'Egypt event partnership. NOYA can host and look after the international guests, VIPs, players or participants who fly in, and can also bring its own clients to the event.',
  CORPORATE: 'Corporate / agency. NOYA is the Egypt delivery partner for incentives, leadership retreats, conferences and executive visits.',
  SPORTS_PRIVATE: 'Sports / private. Discreet and low-key. NOYA supports players and families privately in Egypt (villas, privacy, security, movement). No hype, no name-dropping.'
};
var FORMAT = {
  EMAIL: 'An email body of 80-120 words (excluding greeting and sign-off) plus a short professional subject under 60 characters (e.g. "NOYA x [Company]", "Egypt production support", "Egypt partnership"). Start with "Hi [First name],". End with the call to action; do NOT add a sign-off or signature.',
  LINKEDIN: 'A LinkedIn connection note of 200-300 characters (hard limit 300). Start with "Hi [First name],". No signature, no links. subject must be "".',
  INSTAGRAM: 'An Instagram DM of 150-380 characters, conversational, founder-to-founder. No links, no hashtags, no emojis. subject must be "".'
};
return items.map(function (it) {
  var first = it.first_name || '';
  var facts = [
    'Company: ' + it.company + (it.country ? ' (' + it.country + ')' : '') + (it.company_type ? ' - ' + it.company_type : ''),
    'Person: ' + [it.first_name, it.last_name].filter(Boolean).join(' ') + (it.position ? ', ' + it.position : ''),
    'Verified evidence: ' + (it.evidence || ''),
    'Why now: ' + (it.why_now || ''),
    'Proposed angle (a hypothesis - use it only if the evidence supports it): ' + (it.angle || ''),
    it.warm_route ? 'Warm route (real): ' + it.warm_route : 'No prior relationship: do not imply one.'
  ].join('\\n');
  var prompt = [
    'You write one short outreach message for Adam Elshazly, founder of NOYA Concierge (a global concierge and lifestyle management company with specialist on-ground capability throughout Egypt).',
    LANE[it.lane] || LANE.CORPORATE,
    'Channel: ' + it.channel + '. ' + (FORMAT[it.channel] || FORMAT.LINKEDIN),
    'Structure, in this order: 1) REASON - why this company/person specifically, citing a concrete fact from the evidence (a campaign, launch, location, appointment, event, destination). 2) OPPORTUNITY - what NOYA sees that could genuinely be useful to them. 3) NOYA RELEVANCE - one concise line on how NOYA fits (no service lists, no company biography). 4) ONE easy next step (a short call, a few ideas, a conversation).',
    'The first sentence must be about THEM, not about NOYA or Adam. If the company name were swapped for another, the message must no longer make sense.',
    'Never write: "I am reaching out", "I\\'m reaching out", "I wanted to reach out", "I wanted to introduce", "I\\'ve been following", "we\\'ve been following", "love what you\\'re doing", "I hope", "big fan", "world-class", "unparalleled", "elevate", "seamless", "bespoke", "synergy", "partnership opportunities", "exclusive access", "luxury experiences". No flattery, no fake familiarity, no exclamation marks, no emojis, at most one question.',
    'Use ONLY the facts below. Never invent clients, projects, numbers, dates or a relationship. Understated, confident, concise British English.',
    'Return ONLY JSON: {"subject": "...", "message": "..."}',
    '', facts
  ].join('\\n');
  return { json: Object.assign({}, it, { first_name: first, prompt: prompt }) };
});`
    }
  }
});

const draftModel = languageModel({
  type: '@n8n/n8n-nodes-langchain.lmChatGoogleGemini', version: 1.1,
  config: { name: 'Draft Model (Gemini 3 Flash)', parameters: { modelName: 'models/gemini-3-flash-preview', options: { maxOutputTokens: 1500, temperature: 0.5 } }, credentials: geminiCred }
});
const redraftModel = languageModel({
  type: '@n8n/n8n-nodes-langchain.lmChatGoogleGemini', version: 1.1,
  config: { name: 'Redraft Model (Gemini 3 Flash)', parameters: { modelName: 'models/gemini-3-flash-preview', options: { maxOutputTokens: 1500, temperature: 0.4 } }, credentials: geminiCred }
});

const draft = node({
  type: '@n8n/n8n-nodes-langchain.chainLlm', version: 1.9,
  config: {
    name: 'Draft (AI)', onError: 'continueRegularOutput', retryOnFail: true, maxTries: 2, waitBetweenTries: 3000,
    parameters: { promptType: 'define', text: expr('{{ $json.prompt }}'), batching: { batchSize: 3, delayBetweenBatches: 1000 } },
    subnodes: { model: draftModel }
  }
});

// Deterministic gate shared by both passes (kept identical in both nodes).
const GATE = `
function parse(t) {
  t = String(t || '');
  var s = t.indexOf('{'), e = t.lastIndexOf('}');
  try { if (s >= 0 && e > s) { var o = JSON.parse(t.slice(s, e + 1)); return { subject: String(o.subject || '').trim(), message: String(o.message || '').trim() }; } } catch (err) {}
  return { subject: '', message: t.trim() };
}
var STOP = ('the and for with from that this their they have has into over across after before about which while where there these those based brand brands company '
  + 'campaign campaigns travel luxury egypt noya would could should more most such other also been being per new using used through including include').split(' ');
function tokens(s) { return (String(s || '').match(/[A-Za-z0-9][A-Za-z0-9'-]{3,}/g) || []).map(function (w) { return w.toLowerCase(); }); }
function gate(it, d) {
  var m = d.message, low = m.toLowerCase(), issues = [];
  var BANNED = [/i am reaching out/, /i'?m reaching out/, /wanted to reach out/, /reaching out to/, /wanted to introduce/, /been following/, /we'?ve been following/,
    /love what you/, /big fan/, /i hope/, /world[- ]class/, /unparalleled/, /elevate/, /seamless/, /bespoke/, /synerg/, /exclusive access/, /luxury experiences/,
    /i came across/, /hope this (email|message) finds/];
  BANNED.forEach(function (r) { if (r.test(low)) issues.push('BANNED: ' + r.source); });
  if (/(admire|admired|i'?ve seen your|caught my eye|really enjoyed|so impressed)/.test(low)) issues.push('FALSE_FAMILIARITY');
  if (/(amazing|incredible|stunning|impressive|fantastic|beautiful|inspiring|iconic) (work|brand|campaign|collection|events?|weddings?)/.test(low)) issues.push('UNSUPPORTED_COMPLIMENT');
  if (/(partnership opportunit|mutually beneficial|leverage|explore (potential )?synerg|explore opportunities)/.test(low)) issues.push('GENERIC_PARTNERSHIP_LANGUAGE');
  var lux = (low.match(/\\b(luxury|luxurious|exclusive|premium|curated|exquisite|elite|high-end|discerning)\\b/g) || []).length;
  if (lux > 2) issues.push('TOO_MANY_LUXURY_ADJECTIVES(' + lux + ')');
  var noya = (m.match(/NOYA/g) || []).length;
  if (noya > (it.channel === 'EMAIL' ? 2 : 1)) issues.push('REPEATED_NOYA_BIOGRAPHY');
  if (/[!]|\\[|\\]|\\{\\{/.test(m)) issues.push('FORMAT(! or placeholder)');
  if ((m.match(/\\?/g) || []).length > 1) issues.push('MORE_THAN_ONE_QUESTION');
  if (it.first_name && m.indexOf('Hi ' + it.first_name) !== 0 && it.channel !== 'INSTAGRAM') issues.push('GREETING');
  var words = m.split(/\\s+/).filter(Boolean).length;
  if (it.channel === 'EMAIL' && (words < 70 || words > 140)) issues.push('LENGTH(' + words + ' words)');
  if (it.channel === 'LINKEDIN' && (m.length < 150 || m.length > 300)) issues.push('LENGTH(' + m.length + ' chars)');
  if (it.channel === 'INSTAGRAM' && (m.length < 120 || m.length > 420)) issues.push('LENGTH(' + m.length + ' chars)');
  if (it.channel === 'EMAIL' && (!d.subject || d.subject.length > 60)) issues.push('SUBJECT');
  // Personalisation: the draft must use a specific fact from the evidence, not just the company name.
  var nameT = tokens(it.company).concat(tokens(it.first_name), tokens(it.last_name));
  var ev = tokens((it.evidence || '') + ' ' + (it.why_now || '')).filter(function (w) { return STOP.indexOf(w) < 0 && nameT.indexOf(w) < 0; });
  var hit = ev.filter(function (w, i) { return ev.indexOf(w) === i && low.indexOf(w) >= 0; });
  if (hit.length < 2) issues.push('NOT_PERSONALISED(evidence terms used: ' + hit.length + ')');
  var swapped = low.split(String(it.company || '').toLowerCase()).join('acme');
  if (hit.length < 2 && swapped !== low) issues.push('COMPANY_NAME_SWAP_TEST_FAILED');
  if (!m) issues.push('EMPTY');
  return { issues: issues, words: words, evidence_terms: hit };
}
var SIG = '\\n\\nBest,\\nAdam Elshazly\\nFounder, NOYA Concierge\\nGlobal concierge & lifestyle management\\nnoyaconcierge.com \\u00b7 @noyaconcierge\\nadam@noyaconcierge.com';
`;

const gate1 = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Quality Gate',
    parameters: {
      mode: 'runOnceForEachItem',
      jsCode: GATE + `
var it = $('Build Prompts').item.json;
var d = parse($json.text || $json.output);
var g = gate(it, d);
return { json: Object.assign({}, it, { subject: d.subject, message: d.message, issues: g.issues, evidence_terms: g.evidence_terms, attempts: 1, passed: g.issues.length === 0 }) };`
    }
  }
});

const passed = ifElse({
  version: 2.2,
  config: {
    name: 'Passed?',
    parameters: {
      conditions: {
        options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
        conditions: [{ leftValue: expr('{{ $json.passed }}'), operator: { type: 'boolean', operation: 'true', singleValue: true } }],
        combinator: 'and'
      }
    }
  }
});

const redraftPrompt = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Redraft Prompt',
    parameters: {
      mode: 'runOnceForEachItem',
      jsCode: `
var it = $json;
var p = it.prompt + '\\n\\nYOUR PREVIOUS DRAFT FAILED these checks: ' + it.issues.join('; ') + '.\\nPrevious draft: ' + it.message +
  '\\nWrite a NEW draft that fixes every failure. Rewrite the opening completely (do not just delete a phrase). Use at least two specific facts from the evidence.';
return { json: Object.assign({}, it, { prompt: p, first_issues: it.issues }) };`
    }
  }
});

const redraft = node({
  type: '@n8n/n8n-nodes-langchain.chainLlm', version: 1.9,
  config: {
    name: 'Redraft (AI)', onError: 'continueRegularOutput', retryOnFail: true, maxTries: 2, waitBetweenTries: 3000,
    parameters: { promptType: 'define', text: expr('{{ $json.prompt }}'), batching: { batchSize: 3, delayBetweenBatches: 1000 } },
    subnodes: { model: redraftModel }
  }
});

const gate2 = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Quality Gate 2',
    parameters: {
      mode: 'runOnceForEachItem',
      jsCode: GATE + `
var it = $('Redraft Prompt').item.json;
var d = parse($json.text || $json.output);
var g = gate(it, d);
return { json: Object.assign({}, it, { subject: d.subject, message: d.message, issues: g.issues, evidence_terms: g.evidence_terms, attempts: 2, passed: g.issues.length === 0 }) };`
    }
  }
});

const packageSave = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Package For Save',
    parameters: {
      mode: 'runOnceForEachItem',
      jsCode: `
var it = $json;
var SIG = '\\n\\nBest,\\nAdam Elshazly\\nFounder, NOYA Concierge\\nGlobal concierge & lifestyle management\\nnoyaconcierge.com \\u00b7 @noyaconcierge\\nadam@noyaconcierge.com';
var draft = it.message + (it.channel === 'EMAIL' && it.message ? SIG : '');
return { json: { p: { candidate_id: it.candidate_id, subject: it.channel === 'EMAIL' ? it.subject : '', draft: draft,
  qa_status: it.passed ? 'PASS' : 'DRAFT_REVIEW_REQUIRED',
  qa_issues: { final: it.issues, first_pass: it.first_issues || null, evidence_terms: it.evidence_terms || [] },
  attempts: it.attempts, model: 'gemini-3-flash-preview' } } };`
    }
  }
});

const save = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: {
    name: 'Save Candidate',
    retryOnFail: true, maxTries: 3, waitBetweenTries: 2000,
    parameters: {
      method: 'POST', url: SUPABASE + 'outreach_candidate_save',
      authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: expr('{{ JSON.stringify($json) }}'),
      options: { timeout: 30000 }
    },
    credentials: supabaseCred
  }
});

export default workflow('noya-18-daily-outreach', '18 - NOYA Commercial Director: Daily Outreach v1')
  .add(manualRun)
  .to(settings)
  .add(weekday)
  .to(settings)
  .add(settings)
  .to(plan)
  .to(buildPrompts)
  .to(draft)
  .to(gate1)
  .to(passed
    .onTrue(packageSave.to(save))
    .onFalse(redraftPrompt.to(redraft.to(gate2.to(packageSave)))));
