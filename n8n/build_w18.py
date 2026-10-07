#!/usr/bin/env python3
"""Generate n8n/workflow_18_daily_outreach.js (Workflow SDK source) with the gate library embedded.

Usage: python3 n8n/build_w18.py   (then validate/create with the n8n MCP tools)
"""
import json
import pathlib

HERE = pathlib.Path(__file__).parent
GATE = (HERE / 'w18_gate.js').read_text()

BUILD_PROMPTS = r"""
var settings = $('Run Settings').first().json;
var plan = $input.first().json || {};
var items = plan.items || [];
var LANE = {
  BRANDS: 'Brand or campaign opportunity. Suggest one specific idea in Egypt (a shoot, creator or athlete trip, activation) that fits THIS brand, based only on the evidence. NOYA handles the Egypt side: locations, permits, stays, movement, production support, hospitality.',
  PARTNERSHIPS: 'Partnership, not client acquisition. They keep their client; NOYA is their Egypt partner on the ground (Cairo, the Nile, the Red Sea, the North Coast, VIP handling), working under their name.',
  WEDDINGS: 'Wedding or private-event planner. The planner keeps the client and the design; NOYA is the Egypt destination concierge and guest-logistics partner (guest travel, room blocks, transfers, guest concierge).',
  EGYPT_EVENTS: 'Egypt event partnership. NOYA can look after the international guests, sponsors, players or press who fly in, and can bring its own clients to the event.',
  CORPORATE: 'Corporate or agency. NOYA is the Egypt delivery partner for incentives, leadership offsites, conferences and executive visits.',
  SPORTS_PRIVATE: 'Sports or private client. Discreet and low-key. NOYA supports players and families privately in Egypt (villas, privacy, security, transfers). No hype.'
};
var FORMAT = {
  EMAIL: 'EMAIL. subject: plain, under 60 characters. message: 90-130 words in three short paragraphs: (1) the reason, citing one concrete fact from EVIDENCE; (2) the opportunity and how NOYA fits, in one or two sentences; (3) one easy next step. Start with "Hi FIRSTNAME,". No sign-off or signature.',
  LINKEDIN: 'LINKEDIN connection note. message: 220-280 characters including spaces (LinkedIn rejects more than 300). Two or three sentences. Start with "Hi FIRSTNAME,". subject: "".',
  INSTAGRAM: 'INSTAGRAM DM. message: 150-380 characters, conversational. No links, hashtags or emojis. subject: "".'
};
var CTA = [
  'offer to send three specific ideas (locations, venues or routes) that fit them',
  'offer a one-page outline of how NOYA would run it',
  'suggest a 15-minute call at a time that suits them',
  'offer to send a short shortlist (properties, venues or settings)',
  'offer a short note on how NOYA would handle the guest side',
  'if the evidence names an upcoming event or trade show, suggest meeting there; otherwise offer to send two outline ideas'
];
var SYSTEM = [
  'You write one short outreach message from Adam Elshazly, founder of NOYA Concierge, a global concierge and lifestyle management company with specialist capability across Egypt.',
  'Hard rules:',
  '1. Use ONLY facts in EVIDENCE. Every name, place, number, date, campaign or event you mention about the recipient must appear in EVIDENCE. If a detail is not there, leave it out.',
  '2. Never state or imply what the recipient, their clients, players or guests need, lack, want, plan, prefer or usually do. No "may require", "you need", "remains untapped", "suggests a focus", "as you expand", "your upcoming", "logical next step", "few brands have", "competitors". Offer ideas as possibilities ("could", "if useful").',
  '3. The first sentence is about them and cites one concrete fact from EVIDENCE. If the company name were swapped for another, the message must stop making sense.',
  '4. NOYA appears once (twice at most in an email). No service lists, no company biography, no claims about NOYA clients or track record.',
  '5. Never write: reaching out, wanted to introduce, been following, love what you, big fan, I hope, world-class, unparalleled, elevate, seamless, bespoke, synergy, partnership opportunities, exclusive access, luxury experiences, end-to-end, leverage. No flattery, no exclamation marks, no emojis, at most one question.',
  '6. Understated, confident, concise British English. Plain words.',
  'Return JSON {"subject": "...", "message": "..."} only.'
].join('\n');
var out = items.map(function (it, i) {
  var first = it.first_name || '';
  var evidence = [
    'Company: ' + it.company + (it.country ? ' (' + it.country + ')' : '') + (it.company_type ? ', ' + it.company_type : ''),
    'Person: ' + [it.first_name, it.last_name].filter(Boolean).join(' ') + (it.position ? ', ' + it.position : ''),
    'Facts: ' + (it.evidence || ''),
    it.why_now ? 'Why now: ' + it.why_now : '',
    it.contact_notes ? 'About the person: ' + it.contact_notes : '',
    it.warm_route ? 'Warm route (real): ' + it.warm_route : 'No prior relationship. Do not imply one.'
  ].filter(Boolean).join('\n');
  var user = [
    'LANE: ' + (LANE[it.lane] || LANE.CORPORATE),
    'FORMAT: ' + (FORMAT[it.channel] || FORMAT.LINKEDIN).replace('FIRSTNAME', first),
    'NEXT STEP for this message: ' + CTA[i % CTA.length] + '.',
    'ANGLE (a hypothesis; use only the parts EVIDENCE supports): ' + (it.angle || ''),
    '', 'EVIDENCE:', evidence
  ].join('\n');
  var request = {
    systemInstruction: { parts: [{ text: SYSTEM }] },
    contents: [{ role: 'user', parts: [{ text: user }] }],
    generationConfig: {
      temperature: 0.4, maxOutputTokens: settings.max_output_tokens,
      responseMimeType: 'application/json',
      responseSchema: { type: 'OBJECT', properties: { subject: { type: 'STRING' }, message: { type: 'STRING' } }, required: ['subject', 'message'] },
      thinkingConfig: { thinkingLevel: settings.thinking_level }
    }
  };
  return { json: Object.assign({}, it, { first_name: first, user_prompt: user, request: request, batch: settings.batch }) };
});
return out;
"""

GATE1 = GATE + r"""
// One gate for both passes: run 0 checks first drafts, run 1 checks redrafts (Draft -> Gate loop, max one redraft).
var settings = $('Run Settings').first().json;
var second = $runIndex > 0;
var src = second ? $('Redraft Prompt').all(0, 0) : $('Build Prompts').all(0, 0);
var seen = {};
return $input.all().map(function (x, i) {
  var it = src[i].json;
  var r = readGemini(x.json, it.model || settings.model, second ? 'REDRAFT' : 'DRAFT');
  var d = parseDraft(r.text);
  var g = gate(it, d);
  if (r.error) g.issues.unshift(r.rate_limited ? 'RATE_LIMITED' : 'MODEL_ERROR: ' + r.error.slice(0, 120));
  var ls = lastSentence(it, d.message);
  if (ls) { seen[ls] = (seen[ls] || 0) + 1; if (seen[ls] > 2) g.issues.push('REPEATED_CTA'); }
  var ok = g.issues.length === 0;
  return { json: Object.assign({}, it, { subject: d.subject, message: d.message, issues: g.issues, unsupported: g.unsupported,
    evidence_terms: g.evidence_terms, usage: (second ? (it.usage || []) : []).concat([r.usage]),
    first_pass_ok: second ? false : ok, redraft_ok: second ? ok : null, attempts: second ? 2 : 1, passed: ok, done: ok || second }) };
});
"""

REDRAFT_PROMPT = r"""
return $input.all().map(function (x) {
  var it = x.json;
  var fix = ['Your previous draft failed these checks: ' + it.issues.join('; ') + '.'];
  if (it.unsupported && it.unsupported.length) fix.push('These words are not in EVIDENCE and must not appear: ' + it.unsupported.join(', ') + '.');
  if (it.message) fix.push('Previous draft: ' + it.message);
  fix.push('Write a new draft that fixes every failure. Rewrite the opening rather than deleting a phrase. Do not add any fact that is not in EVIDENCE.');
  var req = JSON.parse(JSON.stringify(it.request));
  req.contents[0].parts[0].text = it.user_prompt + '\n\n' + fix.join('\n');
  req.generationConfig.temperature = 0.3;
  // Rate-limited on Gemini 3 Flash: the single redraft runs on Flash-Lite under the same gate (model recorded per draft).
  var lite = it.issues.indexOf('RATE_LIMITED') >= 0;
  if (lite) delete req.generationConfig.thinkingConfig;
  return { json: Object.assign({}, it, { request: req, first_issues: it.issues,
    model: lite ? 'models/gemini-3.1-flash-lite' : (it.model || 'models/gemini-3-flash-preview'),
    model_url: lite ? 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent' : it.model_url }) };
});
"""

PACKAGE = r"""
var SIG = '\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com';
var settings = $('Run Settings').first().json;
return $input.all().map(function (x) {
  var it = x.json;
  var draft = it.message + (it.channel === 'EMAIL' && it.message ? SIG : '');
  return { json: { p: { candidate_id: it.candidate_id, subject: it.channel === 'EMAIL' ? it.subject : '', draft: draft,
    qa_status: it.passed ? 'PASS' : 'DRAFT_REVIEW_REQUIRED',
    qa_issues: { final: it.issues, first_pass: it.first_issues || null, unsupported: it.unsupported || [], evidence_terms: it.evidence_terms || [] },
    first_pass_ok: it.first_pass_ok, redraft_ok: it.redraft_ok, attempts: it.attempts, usage: it.usage || [],
    model: (it.model || settings.model).replace('models/', ''), batch: it.batch } } };
});
"""

SETTINGS = r"""
// LIVE (Growth Engine, 7 Oct 2026): passing drafts become hand-send READY tasks, failures DRAFT REVIEW tasks. Nothing sends. Gemini call pacing: 4s between calls (free tier);
// drop pace_ms to 500 once billing is on.
var d = new Date().toISOString().slice(0, 10);
return [{ json: { p_dry_run: false, p_target: null, p_replan: false, batch: 'W18-' + d,
  model: 'models/gemini-3-flash-preview', thinking_level: 'minimal', max_output_tokens: 1024, pace_ms: 4000 } }];
"""

def js(s):
    return json.dumps(s)

SRC = f"""import {{ workflow, node, trigger, ifElse, expr }} from '@n8n/workflow-sdk';

// 18 - NOYA Commercial Director: Daily Outreach (Commercial Engine V2.1, 8 Oct 2026)
// Budget guardrail -> plan (commercial_director_plan) -> ONE Gemini call per account (minimal thinking,
// JSON output, exact token usage) -> deterministic evidence gate (no AI fact-checker) -> at most one
// redraft with the exact failures -> save with usage and cost (outreach_candidate_save).
// Never sends anything. Generated by n8n/build_w18.py from n8n/w18_gate.js - edit those, not this file.

const SUPABASE = 'https://gagbhykzmtstekpqujyl.supabase.co/rest/v1/rpc/';
const GEMINI = "={{ $json.model_url || 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent' }}";
const supabaseCred = {{ supabaseApi: {{ id: 'EkLYXHBGqNUjAGKP', name: 'Supabase account' }} }};
const geminiCred = {{ googlePalmApi: {{ id: 'tqsVAbFrBUJsN3Y0', name: 'Google Gemini(PaLM) Api account' }} }};

function rpc(name, fn, body) {{
  return node({{
    type: 'n8n-nodes-base.httpRequest', version: 4.2,
    config: {{
      name: name, retryOnFail: true, maxTries: 3, waitBetweenTries: 2000,
      parameters: {{
        method: 'POST', url: SUPABASE + fn,
        authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
        sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: expr(body),
        options: {{ timeout: 60000 }}
      }},
      credentials: supabaseCred
    }}
  }});
}}
function gemini(name) {{
  return node({{
    type: 'n8n-nodes-base.httpRequest', version: 4.2,
    config: {{
      name: name, onError: 'continueRegularOutput', retryOnFail: true, maxTries: 3, waitBetweenTries: 5000,
      parameters: {{
        method: 'POST', url: GEMINI,
        authentication: 'predefinedCredentialType', nodeCredentialType: 'googlePalmApi',
        sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: expr('{{{{ JSON.stringify($json.request) }}}}'),
        options: {{ timeout: 60000, batching: {{ batch: {{ batchSize: 1, batchInterval: 4000 }} }} }}
      }},
      credentials: geminiCred
    }}
  }});
}}
function code(name, src) {{
  return node({{ type: 'n8n-nodes-base.code', version: 2, config: {{ name: name, parameters: {{ mode: 'runOnceForAllItems', jsCode: src }} }} }});
}}
function isTrue(name, field) {{
  return ifElse({{
    version: 2.2,
    config: {{
      name: name,
      parameters: {{
        conditions: {{
          options: {{ caseSensitive: true, leftValue: '', typeValidation: 'loose' }},
          conditions: [{{ leftValue: expr('{{{{ ' + field + ' }}}}'), operator: {{ type: 'boolean', operation: 'true', singleValue: true }} }}],
          combinator: 'and'
        }}
      }}
    }}
  }});
}}

const manualRun = trigger({{ type: 'n8n-nodes-base.manualTrigger', version: 1, config: {{ name: 'Manual Dry Run' }} }});
const weekday = trigger({{
  type: 'n8n-nodes-base.scheduleTrigger', version: 1.2,
  config: {{ name: 'Daily 10:15 Cairo', parameters: {{ rule: {{ interval: [{{ field: 'cronExpression', expression: '15 10 * * *' }}] }} }} }}
}});

const settings = code('Run Settings', {js(SETTINGS)});
const budget = rpc('AI Budget Check', 'ai_budget_status', '{{{{ "{{}}" }}}}');
const budgetOk = isTrue('Budget OK?', '["OK", "OVER_TARGET"].includes($json.status)');
const budgetHold = rpc('Budget Hold Alert', 'ai_budget_hold_alert', '{{{{ JSON.stringify({{ p_status: $json.status }}) }}}}');
const plan = rpc('Commercial Director Plan', 'commercial_director_plan',
  '{{{{ JSON.stringify({{ p_dry_run: $("Run Settings").first().json.p_dry_run, p_target: $("Run Settings").first().json.p_target, p_replan: $("Run Settings").first().json.p_replan }}) }}}}');
const buildPrompts = code('Build Prompts', {js(BUILD_PROMPTS)});
const draft = gemini('Gemini 3 Flash (draft / redraft)');
const gate1 = code('Quality Gate', {js(GATE1)});
const done = isTrue('Done?', '$json.done');
const redraftPrompt = code('Redraft Prompt', {js(REDRAFT_PROMPT)});
const packageSave = code('Package For Save', {js(PACKAGE)});
const save = node({{
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: {{
    name: 'Save Candidate', retryOnFail: true, maxTries: 3, waitBetweenTries: 2000,
    parameters: {{
      method: 'POST', url: SUPABASE + 'outreach_candidate_save',
      authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: expr('{{{{ JSON.stringify($json) }}}}'),
      options: {{ timeout: 30000 }}
    }},
    credentials: supabaseCred
  }}
}});

export default workflow('noya-18-daily-outreach-v2', '18 - NOYA Commercial Director: Daily Outreach v2')
  .add(manualRun)
  .to(settings)
  .add(weekday)
  .to(settings)
  .add(settings)
  .to(budget)
  .to(budgetOk
    .onTrue(plan.to(buildPrompts.to(draft.to(gate1.to(done
      .onTrue(packageSave.to(save))
      .onFalse(redraftPrompt.to(draft)))))))
    .onFalse(budgetHold));
"""

(HERE / 'workflow_18_daily_outreach.js').write_text(SRC)
print('wrote', len(SRC), 'chars')
