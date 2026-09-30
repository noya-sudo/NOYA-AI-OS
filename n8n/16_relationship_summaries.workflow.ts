// 16 - NOYA Relationship Summaries. Writes a short, clearly-labelled AI summary for each real two-way
// email relationship found in NOYA Gmail, using ONLY the metadata already imported (date, direction,
// sender name, subject, Gmail's ~200-character preview). The Gmail thread stays the evidence; the
// summary is stored separately with its model and basis. Never contacts anyone.
// Order: relationships where they wrote last, then the strongest reconnects.
import { workflow, node, trigger, languageModel, expr } from '@n8n/workflow-sdk';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co/rest/v1/rpc/';
const supabase = { supabaseApi: { id: 'EkLYXHBGqNUjAGKP', name: 'Supabase account' } };

const daily = trigger({ type: 'n8n-nodes-base.scheduleTrigger', version: 1.2, config: { name: 'Daily 06:50 Cairo', parameters: { rule: { interval: [{ field: 'cronExpression', expression: '50 6 * * *' }] } } } });
const manual = trigger({ type: 'n8n-nodes-base.manualTrigger', version: 1, config: { name: 'Manual Run' } });

const queue = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Get Relationships To Summarise', parameters: { method: 'POST', url: SUPA + 'relationship_summary_queue', authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
    sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: '{"p_limit": 15}', options: { timeout: 30000 } }, credentials: supabase },
});

const build = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Build Prompts', parameters: { mode: 'runOnceForAllItems', jsCode: `var rows = $input.all().map(function (i) { return i.json; });
if (rows.length === 1 && Array.isArray(rows[0])) rows = rows[0];
return rows.filter(function (r) { return r && r.key; }).map(function (r) {
  var msgs = r.messages || [];
  var lines = msgs.map(function (m) {
    return m.date + ' ' + (m.dir === 'OUTBOUND' ? 'NOYA -> them' : 'them -> NOYA' + (m.from ? ' (' + m.from + ')' : '')) + ' | subject: ' + (m.subject || '') + ' | preview: ' + String(m.preview || '').slice(0, 220);
  }).join('\\n');
  var last = msgs.slice(-1)[0] || {};
  var prompt = [
    'You summarise one business email relationship for Adam, CEO of NOYA Concierge (luxury concierge and destination management, strongest in Egypt).',
    'You only see email metadata: date, direction, sender name, subject and the first ~200 characters of each email. Do not invent anything the previews do not show. If something is unclear, say it is unclear.',
    'Fact: the most recent email (' + (last.date || 'unknown date') + ') was sent by ' + (last.dir === 'OUTBOUND' ? 'NOYA' : 'them') + '.',
    'Return ONLY a JSON object with keys:',
    '"summary": max 45 words - what the exchange was about and where it stands;',
    '"their_position": max 30 words - what they said or asked, from their previews only (empty string if unknown);',
    '"suggested_status": one of REPLY_NOW, RECONNECT, FOLLOW_UP_LATER, LONG_TERM, EXISTING_PARTNER, CLIENT, NOT_RELEVANT;',
    '"reason": max 20 words.',
    'Status guide: REPLY_NOW = they sent the most recent email and are waiting on Adam (never when NOYA sent the last email). RECONNECT = a real two-way conversation that went quiet and is worth restarting. FOLLOW_UP_LATER = they asked to talk later, or NOYA wrote last and is waiting. LONG_TERM = low near-term value. EXISTING_PARTNER = an agreed collaboration, or a supplier NOYA books or buys from for its clients (hotel, venue, restaurant, transport). CLIENT = only when they pay NOYA for services. NOT_RELEVANT = a clear decline, a delivery failure, spam or unrelated.',
    '', 'Organisation: ' + (r.company || r.domain || r.key) + ' | NOYA emails: ' + r.sent + ' | their emails: ' + r.received,
    'Emails (oldest first):', lines
  ].join('\\n');
  return { json: { key: r.key, prompt: prompt, threads: r.threads, count: msgs.length, last_at: r.last_at, sent: r.sent, received: r.received,
    last_in: msgs.filter(function (m) { return m.dir === 'INBOUND'; }).slice(-1)[0] || null, last_dir: last.dir || '' } };
});` } },
});

const gemini = languageModel({ type: '@n8n/n8n-nodes-langchain.lmChatGoogleGemini', version: 1.1,
  config: { name: 'Summary Model (Gemini Flash-Lite)', parameters: { modelName: 'models/gemini-3.1-flash-lite', options: { maxOutputTokens: 500, temperature: 0 } } } });
const gpt = languageModel({ type: '@n8n/n8n-nodes-langchain.lmChatOpenAi', version: 1.3,
  config: { name: 'Summary Backup Model (GPT-5 mini)', parameters: { model: { __rl: true, mode: 'id', value: 'gpt-5-mini' }, responsesApiEnabled: false, options: { reasoningEffort: 'low' } } } });

const write = node({
  type: '@n8n/n8n-nodes-langchain.chainLlm', version: 1.9,
  config: { name: 'Summarise (AI)', parameters: { promptType: 'define', text: expr('{{ $json.prompt }}'), needsFallback: true, batching: { batchSize: 3, delayBetweenBatches: 500 } },
    onError: 'continueRegularOutput', retryOnFail: true, maxTries: 2, waitBetweenTries: 2000, subnodes: { model: [gemini, gpt] } },
});

const parse = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Check And Package', parameters: { mode: 'runOnceForEachItem', jsCode: `// AI output is checked; if unusable, a factual fallback line is stored instead (labelled as such).
var req = $('Build Prompts').item.json;
var text = String(($json && ($json.text || $json.output)) || '');
var out = null;
try { var s = text.indexOf('{'), e = text.lastIndexOf('}'); if (s >= 0 && e > s) out = JSON.parse(text.slice(s, e + 1)); } catch (err) { out = null; }
var allowed = ['REPLY_NOW', 'RECONNECT', 'FOLLOW_UP_LATER', 'LONG_TERM', 'EXISTING_PARTNER', 'CLIENT', 'NOT_RELEVANT'];
var model = 'Gemini 3.1 Flash-Lite / GPT-5 mini fallback';
if (!out || !out.summary || String(out.summary).split(/\\s+/).length > 70) {
  var li = req.last_in;
  out = { summary: 'No AI summary available. Facts: ' + req.sent + ' emails from NOYA, ' + req.received + ' from them.' + (li ? ' Their last email (' + li.date + '): "' + String(li.preview || '').slice(0, 140) + '"' : ''),
          their_position: '', suggested_status: null, reason: null };
  model = 'NONE (factual fallback)';
}
if (allowed.indexOf(out.suggested_status) < 0) out.suggested_status = null;
return { json: { p_key: req.key, p_summary: String(out.summary).slice(0, 600), p_position: String(out.their_position || '').slice(0, 400),
  p_suggested: out.suggested_status, p_reason: out.reason ? String(out.reason).slice(0, 300) : null, p_model: model,
  p_basis: { source: 'subject + Gmail preview only', threads: req.threads, messages: req.count, last_at: req.last_at } } };` } },
});

const save = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Save Summary', parameters: { method: 'POST', url: SUPA + 'relationship_summary_save', authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
    sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: expr('{{ JSON.stringify($json) }}'), options: { timeout: 30000 } },
    retryOnFail: true, maxTries: 3, waitBetweenTries: 2000, credentials: supabase },
});

export default workflow('noya-16-relationship-summaries', '16 - NOYA Relationship Summaries v1')
  .add(daily).to(queue).to(build).to(write).to(parse).to(save)
  .add(manual).to(queue);
