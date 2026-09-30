// 17 - NOYA Signal Analyst. After workflow 09 finds Egypt signals, this reads each new signal's STORED text
// (title, summary, source name) and proposes: the organisations named in it, the event name, why NOYA should
// care, the problem NOYA solves, the angle and the likely decision roles. The database keeps an organisation
// only if its name appears in the stored source text; dates are never taken from the model. Never contacts anyone.
import { workflow, node, trigger, languageModel, expr } from '@n8n/workflow-sdk';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co/rest/v1/rpc/';
const supabase = { supabaseApi: { id: 'EkLYXHBGqNUjAGKP', name: 'Supabase account' } };

const daily = trigger({ type: 'n8n-nodes-base.scheduleTrigger', version: 1.2, config: { name: 'Daily 10:45 Cairo (after 09)', parameters: { rule: { interval: [{ field: 'cronExpression', expression: '45 10 * * *' }] } } } });
const manual = trigger({ type: 'n8n-nodes-base.manualTrigger', version: 1, config: { name: 'Manual Run' } });

const queue = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Get New Signals', parameters: { method: 'POST', url: SUPA + 'signal_analysis_queue', authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
    sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: '{"p_limit": 10}', options: { timeout: 30000 } }, credentials: supabase },
});

const build = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Build Prompts', parameters: { mode: 'runOnceForAllItems', jsCode: `var rows = $input.all().map(function (i) { return i.json; });
if (rows.length === 1 && Array.isArray(rows[0])) rows = rows[0];
var playbooks = ['SPORTS_EVENT_EGYPT', 'FESTIVAL_ENTERTAINMENT', 'FILM_FESTIVAL', 'BRAND_ACTIVATION', 'HOTEL_OPENING', 'HOSPITALITY_EXPANSION', 'PRODUCTION_SHOOT',
  'CORPORATE_DELEGATION', 'DESTINATION_WEDDING', 'PROPERTY_LAUNCH', 'VIP_VISIT', 'CONCIERGE_EGYPT_SUPPORT', 'CONTENT_TRIP'];
return rows.filter(function (r) { return r && r.id; }).map(function (r) {
  var prompt = [
    'You analyse one market signal for NOYA Concierge (luxury concierge, VIP guest services, events, hospitality and destination management, strongest in Egypt).',
    'Use ONLY the text below. Never invent organisations, people, dates or facts. If something is not stated, leave it empty.',
    'Return ONLY a JSON object with keys:',
    '"event_name": short name of the event/project (max 8 words, from the text);',
    '"organisations": array of {"name", "role", "evidence"} for organisations NAMED in the text (role one of ORGANISER, PROMOTER, SPONSOR, BRAND, AGENCY, PR, HOTEL, VENUE, OPERATOR, DEVELOPER, PRODUCTION, TALENT_AGENCY, TEAM, GOVERNMENT, OTHER; evidence = the exact phrase naming them);',
    '"why_noya": max 35 words — why this creates a reason for NOYA to contact someone;',
    '"problem": max 25 words — the operational problem NOYA could solve for them;',
    '"angle": max 35 words — the commercial angle for the first approach (specific, not generic luxury language);',
    '"decision_roles": up to 4 job titles likely to decide;',
    '"playbook": one of ' + playbooks.join(', ') + ' or empty;',
    '"next_action": max 20 words;',
    '"not_commercially_relevant": true only if there is clearly nothing for NOYA.',
    '', 'Signal:', 'Title: ' + (r.title || ''), 'Summary: ' + (r.summary || ''), 'Source: ' + (r.source_name || '') + ' ' + (r.source_url || ''),
    'Destination: ' + (r.destination || ''), 'Existing notes: ' + String(r.opportunity_text || '').slice(0, 600)
  ].join('\\n');
  return { json: { id: r.id, prompt: prompt } };
});` } },
});

const gemini = languageModel({ type: '@n8n/n8n-nodes-langchain.lmChatGoogleGemini', version: 1.1,
  config: { name: 'Analyst Model (Gemini Flash-Lite)', parameters: { modelName: 'models/gemini-3.1-flash-lite', options: { maxOutputTokens: 700, temperature: 0 } } } });
const gpt = languageModel({ type: '@n8n/n8n-nodes-langchain.lmChatOpenAi', version: 1.3,
  config: { name: 'Analyst Backup Model (GPT-5 mini)', parameters: { model: { __rl: true, mode: 'id', value: 'gpt-5-mini' }, responsesApiEnabled: false, options: { reasoningEffort: 'low' } } } });

const analyse = node({
  type: '@n8n/n8n-nodes-langchain.chainLlm', version: 1.9,
  config: { name: 'Analyse (AI)', parameters: { promptType: 'define', text: expr('{{ $json.prompt }}'), needsFallback: true, batching: { batchSize: 3, delayBetweenBatches: 500 } },
    onError: 'continueRegularOutput', retryOnFail: true, maxTries: 2, waitBetweenTries: 2000, subnodes: { model: [gemini, gpt] } },
});

const parse = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Check And Package', parameters: { mode: 'runOnceForEachItem', jsCode: `// Unusable AI output is saved as an empty analysis (so the signal is not retried forever); nothing is invented.
var req = $('Build Prompts').item.json;
var text = String(($json && ($json.text || $json.output)) || '');
var out = null;
try { var s = text.indexOf('{'), e = text.lastIndexOf('}'); if (s >= 0 && e > s) out = JSON.parse(text.slice(s, e + 1)); } catch (err) { out = null; }
var model = out ? 'Gemini 3.1 Flash-Lite / GPT-5 mini fallback' : 'NONE (AI output unusable)';
out = out || {};
var orgs = Array.isArray(out.organisations) ? out.organisations.slice(0, 8).map(function (o) { return { name: String(o.name || '').slice(0, 120), role: String(o.role || 'OTHER'), evidence: String(o.evidence || '').slice(0, 300) }; }) : [];
return { json: { p_id: req.id, p_model: model, p: { event_name: out.event_name || null, organisations: orgs, why_noya: out.why_noya || null, problem: out.problem || null,
  angle: out.angle || null, decision_roles: Array.isArray(out.decision_roles) ? out.decision_roles.slice(0, 4) : [], playbook: out.playbook || null,
  next_action: out.next_action || null, not_commercially_relevant: out.not_commercially_relevant === true } } };` } },
});

const save = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Save Analysis', parameters: { method: 'POST', url: SUPA + 'signal_analysis_save', authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
    sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: expr('{{ JSON.stringify($json) }}'), options: { timeout: 30000 } },
    retryOnFail: true, maxTries: 3, waitBetweenTries: 2000, credentials: supabase },
});

export default workflow('noya-17-signal-analyst', '17 - NOYA Signal Analyst v1')
  .add(daily).to(queue).to(build).to(analyse).to(parse).to(save)
  .add(manual).to(queue);
