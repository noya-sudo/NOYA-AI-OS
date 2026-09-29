// 14 - NOYA Message Drafting. Drafts LinkedIn / email / Instagram / WhatsApp messages that Adam
// requested in HQ. Never sends anything: it writes the draft back for Adam to copy and send himself.
// Low-cost models only (Gemini Flash-Lite, then GPT-5 mini); if both fail, a deterministic
// template is stored and the request is marked PROVIDER_UNAVAILABLE so HQ can say so.
import { workflow, node, trigger, languageModel, expr } from '@n8n/workflow-sdk';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co/rest/v1/rpc/';
const supabase = { supabaseApi: { id: 'EkLYXHBGqNUjAGKP', name: 'Supabase account' } };

const every5 = trigger({ type: 'n8n-nodes-base.scheduleTrigger', version: 1.2, config: { name: 'Every 5 Minutes', parameters: { rule: { interval: [{ field: 'minutes', minutesInterval: 5 }] } } } });
const manual = trigger({ type: 'n8n-nodes-base.manualTrigger', version: 1, config: { name: 'Manual Run' } });

const claim = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: {
    name: 'Claim Draft Requests',
    parameters: { method: 'POST', url: SUPA + 'message_draft_claim', authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: '{"p_limit": 5}', options: { timeout: 30000 } },
    credentials: supabase,
  },
});

const build = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Build Prompts',
    parameters: { mode: 'runOnceForAllItems', jsCode: `// One item per claimed request. Only the minimal facts stored with the request are used.
var drafts = ($input.first().json.drafts) || [];
var TYPE = {
  FIRST_MESSAGE: 'a first message to someone NOYA has not spoken to before',
  RECONNECTION: 'a reconnection with someone Adam already knows but has not spoken to for a while',
  FOLLOW_UP: 'a short follow-up to an earlier message that had no reply',
  INTRODUCTION_REQUEST: 'a request for an introduction to the right person at their company',
  PARTNERSHIP: 'an opening for a referral / partnership relationship between two service businesses',
  EGYPT_OPPORTUNITY: 'an opening about a specific Egypt opportunity relevant to them',
  CORPORATE: 'an opening about corporate travel, incentives or events',
  HOSPITALITY: 'an opening to a hotel / hospitality contact about collaboration',
  BRAND_PRODUCTION: 'an opening about brand trips, shoots or production in Egypt',
  PRIVATE_CLIENT_INTRO: 'a discreet introduction relevant to private clients'
};
var LIMIT = { LINKEDIN: 600, INSTAGRAM: 500, WHATSAPP: 500, EMAIL: 1200 };
return drafts.map(function (d) {
  var c = d.context || {};
  var voice = d.voice === 'ADAM_PERSONAL'
    ? 'Write in the first person singular as Adam Elshazly, founder of NOYA Concierge. Personal, warm, brief.'
    : 'Write as NOYA Concierge ("we"). Professional, warm, brief.';
  var facts = Object.keys(c).filter(function (k) { return c[k] !== null && c[k] !== ''; }).map(function (k) { return '- ' + k + ': ' + String(c[k]).slice(0, 400); }).join('\\n');
  var prompt = [
    'You write short outreach messages for NOYA Concierge: luxury concierge, travel and destination management, with deep expertise and relationships in Egypt, working globally.',
    voice,
    'Channel: ' + d.channel + '. Maximum ' + (LIMIT[d.channel] || 600) + ' characters.' + (d.channel === 'EMAIL' ? ' Start with a line "Subject: ..." then a blank line, then the email.' : ''),
    'Purpose: ' + (TYPE[d.message_type] || d.message_type) + '.',
    'Style: refined, understated, confident, concise. No luxury cliches, no hype, no exclamation marks, no emojis, no flattery. One clear, easy next step (e.g. a short call). Never desperate.',
    'Use ONLY the facts below. Never invent names, shared history, mutual contacts, prices, dates, availability or clients. If a fact is missing, leave it out. No placeholders like [Name].',
    'Return only the message text.',
    '', 'Facts:', facts || '- (none beyond the company name)',
    d.adam_note ? '\\nAdam asks you to include: ' + String(d.adam_note).slice(0, 500) : ''
  ].join('\\n');
  return { json: { id: d.id, channel: d.channel, voice: d.voice, message_type: d.message_type, context: c, limit: LIMIT[d.channel] || 600, prompt: prompt } };
});` },
  },
});

const gemini = languageModel({
  type: '@n8n/n8n-nodes-langchain.lmChatGoogleGemini', version: 1.1,
  config: { name: 'Draft Model (Gemini Flash-Lite)', parameters: { modelName: 'models/gemini-3.1-flash-lite', options: { maxOutputTokens: 700, temperature: 0.4 } } },
});
const gpt = languageModel({
  type: '@n8n/n8n-nodes-langchain.lmChatOpenAi', version: 1.3,
  config: { name: 'Draft Backup Model (GPT-5 mini)', parameters: { model: { __rl: true, mode: 'id', value: 'gpt-5-mini' }, responsesApiEnabled: false, options: { reasoningEffort: 'low' } } },
});

const write = node({
  type: '@n8n/n8n-nodes-langchain.chainLlm', version: 1.9,
  config: {
    name: 'Write Draft (AI)',
    parameters: { promptType: 'define', text: expr('{{ $json.prompt }}'), needsFallback: true, batching: { batchSize: 2, delayBetweenBatches: 500 } },
    onError: 'continueRegularOutput', retryOnFail: true, maxTries: 2, waitBetweenTries: 2000,
    subnodes: { model: [gemini, gpt] },
  },
});

const gate = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Quality Gate',
    parameters: { mode: 'runOnceForEachItem', jsCode: `// Checks the AI text; falls back to a deterministic template. Status READY or PROVIDER_UNAVAILABLE.
var req = $('Build Prompts').item.json;
var c = req.context || {};
var text = String(($json && ($json.text || $json.output)) || '').trim().replace(/^"|"$/g, '');
var issues = [];
var hard = false;
var banned = [/hope (this|you) (finds|are)/i, /unparalleled/i, /world[- ]class/i, /elevate/i, /unforgettable/i, /once[- ]in[- ]a[- ]lifetime/i,
  /exclusive access/i, /synergy/i, /dear sir/i, /to whom it may concern/i, /I came across your profile/i, /bespoke experiences/i, /luxury redefined/i];
if (!text) { hard = true; issues.push('AI provider unavailable'); }
else {
  if (/\\[[^\\]]{1,30}\\]|\\{\\{|<[A-Z_ ]+>/.test(text)) { hard = true; issues.push('placeholder left in text'); }
  banned.forEach(function (r) { if (r.test(text)) issues.push('cliche: ' + r.source.replace(/\\\\/g, '')); });
  if (/!/.test(text)) issues.push('exclamation mark');
  if (/[\\u{1F300}-\\u{1FAFF}]/u.test(text)) issues.push('emoji');
  if (/[£$€]\\s?\\d/.test(text) && !/[£$€]/.test(JSON.stringify(c))) { hard = true; issues.push('price not in the facts'); }
  if (text.length > req.limit * 1.25) issues.push('long (' + text.length + ' chars)');
  if (issues.filter(function (i) { return /^cliche|emoji|exclamation/.test(i); }).length >= 2) hard = true;
}
function template() {
  var first = c.first_name ? 'Hi ' + c.first_name + ',' : 'Hello,';
  var co = c.company || 'your team';
  var me = req.voice === 'ADAM_PERSONAL' ? 'I run NOYA Concierge' : 'NOYA Concierge is';
  var body = {
    RECONNECTION: 'It has been a while. ' + me + (req.voice === 'ADAM_PERSONAL' ? ' now' : '') + ' — concierge, travel and destination management, with deep roots in Egypt. I would be glad to catch up and hear what ' + co + ' is working on.',
    FOLLOW_UP: 'A short follow-up on my earlier note. If Egypt or concierge support is ever useful for ' + co + ', I would be glad to help. Happy to leave it there otherwise.',
    INTRODUCTION_REQUEST: me + ' — concierge and destination management with deep roots in Egypt. Could you point me to the right person at ' + co + ' for travel or events? A name is plenty.',
    PARTNERSHIP: me + ' — concierge and destination management, strongest in Egypt. There may be a simple referral fit with ' + co + '. Open to a short call?'
  }[req.message_type] || (me + ' — concierge, travel and destination management with deep expertise in Egypt. ' + (c.opportunity ? 'I thought of ' + co + ' in connection with ' + String(c.opportunity).slice(0, 140) + '. ' : '') + 'Would a short call be useful?');
  var sign = req.voice === 'ADAM_PERSONAL' ? '\\n\\nAdam' : '\\n\\nNOYA Concierge';
  var t = first + '\\n\\n' + body + sign;
  return req.channel === 'EMAIL' ? 'Subject: NOYA Concierge — ' + co + '\\n\\n' + t : t;
}
var provider = !text;
var draft = hard ? template() : text;
if (hard && !provider) issues.push('AI draft failed checks — deterministic template used');
if (provider) issues.push('deterministic template used');
return { json: { p_id: req.id, p_status: provider ? 'PROVIDER_UNAVAILABLE' : 'READY', p_draft: draft, p_issues: issues.length ? issues : null,
  p_model: provider || hard ? 'TEMPLATE' : 'Gemini 3.1 Flash-Lite / GPT-5 mini fallback' } };` },
  },
});

const complete = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: {
    name: 'Save Draft',
    parameters: { method: 'POST', url: SUPA + 'message_draft_complete', authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: expr('{{ JSON.stringify($json) }}'), options: { timeout: 30000 } },
    retryOnFail: true, maxTries: 3, waitBetweenTries: 3000,
    credentials: supabase,
  },
});

export default workflow('noya-14-message-drafting', '14 - NOYA Message Drafting v1')
  .add(every5).to(claim).to(build).to(write).to(gate).to(complete)
  .add(manual).to(claim);
