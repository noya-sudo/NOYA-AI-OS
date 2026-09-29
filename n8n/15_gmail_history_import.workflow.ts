// 15 - NOYA Gmail History Import. Reads noya@noyaconcierge.com (GET only, never sends) through the
// existing "NOYA Gmail" OAuth credential. First a 12-month backfill in pages of up to 500 messages,
// then incremental changes through Gmail history IDs. Metadata only (headers + Gmail's snippet);
// message bodies are never requested. All filtering, matching and CRM updates happen in Supabase
// (gmail_history_ingest), idempotent on the Gmail message id.
import { workflow, node, trigger, ifElse, expr } from '@n8n/workflow-sdk';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co/rest/v1/rpc/';
const supabase = { supabaseApi: { id: 'EkLYXHBGqNUjAGKP', name: 'Supabase account' } };
const gmail = { gmailOAuth2: { id: 'OMGm2CkcvDKbJTr3', name: 'NOYA Gmail' } };
const G = 'https://gmail.googleapis.com/gmail/v1/users/me/';

const schedule = trigger({ type: 'n8n-nodes-base.scheduleTrigger', version: 1.2, config: { name: 'Every 3 Hours 07-22 Cairo', parameters: { rule: { interval: [{ field: 'cronExpression', expression: '10 7-22/3 * * *' }] } } } });
const manual = trigger({ type: 'n8n-nodes-base.manualTrigger', version: 1, config: { name: 'Manual Run' } });

const profile = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Verify NOYA Mailbox', parameters: { method: 'GET', url: G + 'profile', authentication: 'predefinedCredentialType', nodeCredentialType: 'gmailOAuth2', options: { timeout: 20000 } }, credentials: gmail },
});

const isNoya = ifElse({
  version: 2.2,
  config: { name: 'Mailbox Is NOYA?', parameters: { conditions: { options: { caseSensitive: false, leftValue: '', typeValidation: 'loose' },
    conditions: [{ leftValue: expr('{{ $json.emailAddress }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'noya@noyaconcierge.com' }], combinator: 'and' } } },
});

const stop = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Stop - Wrong Mailbox', parameters: { mode: 'runOnceForAllItems', jsCode: "throw new Error('Workflow 15 stopped: Gmail credential is not noya@noyaconcierge.com (got ' + $json.emailAddress + ')');" } },
});

const cursor = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Get Cursor', parameters: { method: 'POST', url: SUPA + 'gmail_history_next', authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
    sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: expr('{{ JSON.stringify({ p_mailbox: $json.emailAddress, p_profile_history_id: String($json.historyId) }) }}'), options: { timeout: 30000 } }, credentials: supabase },
});

const listReq = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Build List Request', parameters: { mode: 'runOnceForAllItems', jsCode: `var c = $input.first().json;
var url;
if (c.mode === 'BACKFILL') {
  url = '${G}messages?maxResults=500&q=' + encodeURIComponent(c.q) + (c.page_token ? '&pageToken=' + encodeURIComponent(c.page_token) : '');
} else {
  url = '${G}history?maxResults=500&historyTypes=messageAdded&startHistoryId=' + encodeURIComponent(c.history_id) + (c.page_token ? '&pageToken=' + encodeURIComponent(c.page_token) : '');
}
return [{ json: { mode: c.mode, url: url } }];` } },
});

const list = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'List Messages', parameters: { method: 'GET', url: expr('{{ $json.url }}'), authentication: 'predefinedCredentialType', nodeCredentialType: 'gmailOAuth2',
    options: { timeout: 30000, response: { response: { fullResponse: true, neverError: true } } } }, credentials: gmail },
});

const collect = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Collect Message IDs', parameters: { mode: 'runOnceForAllItems', jsCode: `// One item per message id (or one empty item so the cursor still advances).
var mode = $('Build List Request').first().json.mode;
var prof = $('Verify NOYA Mailbox').first().json;
var r = $input.first().json || {};
var code = Number(r.statusCode || 0);
var b = r.body || {};
var ids = [], next = null, hist = null, error = null, expired = false;
if (mode === 'BACKFILL') {
  if (code === 200) { ids = (b.messages || []).map(function (m) { return m.id; }); next = b.nextPageToken || null; }
  else error = 'Gmail list HTTP ' + code;
} else {
  if (code === 404) expired = true;
  else if (code === 200) {
    var seen = {};
    (b.history || []).forEach(function (h) { (h.messagesAdded || []).forEach(function (a) { if (a.message && !seen[a.message.id]) { seen[a.message.id] = 1; ids.push(a.message.id); } }); });
    next = b.nextPageToken || null; hist = b.historyId ? String(b.historyId) : null;
  } else error = 'Gmail history HTTP ' + code;
}
var meta = { mailbox: prof.emailAddress, mode: expired ? 'HISTORY_EXPIRED' : mode, next_page_token: next,
  new_history_id: expired ? String(prof.historyId) : hist, error: error, scanned: ids.length };
if (!ids.length) return [{ json: { id: null, meta: meta } }];
return ids.map(function (id) { return { json: { id: id, meta: meta } }; });` } },
});

const meta = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Get Message Metadata', parameters: { method: 'GET',
    url: expr("{{ $json.id ? '" + G + "messages/' + $json.id + '?format=metadata&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Cc&metadataHeaders=Subject&metadataHeaders=List-Unsubscribe&metadataHeaders=List-Id&metadataHeaders=Precedence&metadataHeaders=Auto-Submitted' : '" + G + "profile' }}"),
    authentication: 'predefinedCredentialType', nodeCredentialType: 'gmailOAuth2',
    options: { timeout: 30000, batching: { batch: { batchSize: 20, batchInterval: 600 } }, response: { response: { fullResponse: true, neverError: true } } } }, credentials: gmail },
});

const payload = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Build Ingest Payload', parameters: { mode: 'runOnceForAllItems', jsCode: `// Headers only. Nothing from the message body is read.
var asked = $('Collect Message IDs').all();
var meta = asked[0].json.meta;
function hdr(h, name) { name = name.toLowerCase(); for (var i = 0; i < (h || []).length; i++) if (String(h[i].name).toLowerCase() === name) return String(h[i].value || ''); return ''; }
function emails(v) { return (String(v || '').match(/[A-Za-z0-9._%+'-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}/g) || []).map(function (e) { return e.toLowerCase(); }); }
var messages = [], failed = 0;
$input.all().forEach(function (it, i) {
  var id = asked[i] && asked[i].json.id;
  if (!id) return;
  var r = it.json || {}, code = Number(r.statusCode || 0), m = r.body || {};
  if (code === 404) return;               // deleted since listing
  if (code !== 200 || !m.id) { failed++; return; }
  var h = (m.payload && m.payload.headers) || [];
  var from = hdr(h, 'From');
  messages.push({ id: m.id, thread_id: m.threadId, internal_date: String(m.internalDate || ''), labels: m.labelIds || [],
    from_email: emails(from)[0] || '', from_name: from.replace(/<[^>]*>/, '').replace(/"/g, '').trim().slice(0, 120),
    to: emails(hdr(h, 'To')), cc: emails(hdr(h, 'Cc')), subject: hdr(h, 'Subject').slice(0, 300), snippet: String(m.snippet || '').slice(0, 300),
    list_unsubscribe: hdr(h, 'List-Unsubscribe') ? 'yes' : '', list_id: hdr(h, 'List-Id') ? 'yes' : '', precedence: hdr(h, 'Precedence'), auto_submitted: hdr(h, 'Auto-Submitted') });
});
var error = meta.error || (meta.scanned && failed > Math.max(5, meta.scanned * 0.2) ? 'Gmail metadata failures: ' + failed + ' of ' + meta.scanned : null);
return [{ json: { p_mailbox: meta.mailbox, p_mode: meta.mode, p_messages: messages, p_next_page_token: meta.next_page_token,
  p_new_history_id: meta.new_history_id, p_scanned: meta.scanned, p_error: error } }];` } },
});

const ingest = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Ingest To CRM', parameters: { method: 'POST', url: SUPA + 'gmail_history_ingest', authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
    sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: expr('{{ JSON.stringify($json) }}'), options: { timeout: 120000 } },
    retryOnFail: true, maxTries: 3, waitBetweenTries: 3000, credentials: supabase },
});

export default workflow('noya-15-gmail-history', '15 - NOYA Gmail History Import v1')
  .add(schedule).to(profile)
  .add(manual).to(profile)
  .add(profile).to(isNoya.onTrue(cursor.to(listReq).to(list).to(collect).to(meta).to(payload).to(ingest)).onFalse(stop));
