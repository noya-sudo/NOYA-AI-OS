"""Generates n8n/13_gmail_interaction_sync.workflow.ts (n8n Workflow SDK code).

Workflow 13 only READS Gmail (HTTP GET against the Gmail API) and writes CRM
through Supabase RPCs. It contains no send, draft or reply node.
"""
import json

SUPA = "https://gagbhykzmtstekpqujyl.supabase.co/rest/v1/rpc/"
SUPA_CRED = "{ supabaseApi: { id: 'EkLYXHBGqNUjAGKP', name: 'Supabase account' } }"
GMAIL_CRED = "{ gmailOAuth2: { id: 'OMGm2CkcvDKbJTr3', name: 'NOYA Gmail' } }"
ANTHROPIC_CRED = "{ anthropicApi: { id: 'f16OdoVzDPZKSgmG', name: 'Anthropic account' } }"
MODEL = "claude-sonnet-4-6"  # same model the rest of the NOYA estate already runs on

BUILD_SEARCH = r"""
// Reads only what NOYA itself emailed: tracked threads plus replies from contacted senders.
var t = $input.first().json;
var senders = (t.sender_emails || []).filter(function (e) { return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e); });
var q = senders.length
  ? 'from:(' + senders.join(' OR ') + ') after:' + t.after_epoch
  : 'from:(nobody@noya-sync.invalid) after:' + t.after_epoch;
return [{ json: {
  mailbox: t.mailbox,
  go_live_ms: Number(t.after_epoch) * 1000,
  tracked_threads: t.threads || [],
  search_url: 'https://gmail.googleapis.com/gmail/v1/users/me/threads?maxResults=50&q=' + encodeURIComponent(q)
} }];
"""

COLLECT = r"""
var base = $('Build Gmail Search').first().json;
var r0 = $input.first().json || {};
var found = ((r0.body && r0.body.threads) || []).map(function (t) { return t.id; });
var ids = {};
(base.tracked_threads || []).concat(found).forEach(function (id) { if (id) ids[id] = true; });
var list = Object.keys(ids);
if (!list.length) return [{ json: { has_threads: false } }];
return list.map(function (id) { return { json: { has_threads: true, thread_id: id } }; });
"""

EXTRACT = r"""
// Turns Gmail thread responses into compact message records. Messages before go-live are dropped here.
var base = $('Build Gmail Search').first().json;
var asked = $('Collect Thread Ids').all();
var responses = $input.all();

function header(h, name) {
  name = name.toLowerCase();
  for (var i = 0; i < (h || []).length; i++) if (String(h[i].name).toLowerCase() === name) return String(h[i].value || '');
  return '';
}
function emails(v) {
  var m = String(v || '').match(/[A-Za-z0-9._%+'-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g) || [];
  return m.map(function (e) { return e.toLowerCase(); });
}
function decode(data) {
  try { return Buffer.from(String(data).replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'); }
  catch (e) { return ''; }
}
function findPart(p, mime) {
  if (!p) return '';
  if (p.mimeType === mime && p.body && p.body.data) return decode(p.body.data);
  var parts = p.parts || [];
  for (var i = 0; i < parts.length; i++) { var r = findPart(parts[i], mime); if (r) return r; }
  return '';
}
function bodyText(payload) {
  var t = findPart(payload, 'text/plain');
  if (!t) t = findPart(payload, 'text/html').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ');
  // Keep the new text only: cut quoted history.
  var cut = t.search(/\n\s*On .{0,200}wrote:|\n-{2,}\s*Original Message|\nFrom: .*\nSent: /i);
  if (cut > 0) t = t.slice(0, cut);
  return t.replace(/\r/g, '').replace(/\n{3,}/g, '\n\n').trim().slice(0, 6000);
}

var threads = [];
var messages = [];
responses.forEach(function (r, idx) {
  var threadId = asked[idx] && asked[idx].json.thread_id;
  var code = Number(r.json.statusCode || 0);
  threads.push({ thread_id: threadId, http_status: code });
  if (code !== 200 || !r.json.body) return;
  (r.json.body.messages || []).forEach(function (m) {
    var internal = Number(m.internalDate || 0);
    if (internal < base.go_live_ms - 3600000) return;
    var h = (m.payload && m.payload.headers) || [];
    var fromRaw = header(h, 'From');
    var fromEmails = emails(fromRaw);
    messages.push({
      message_id: m.id,
      thread_id: m.threadId,
      label_ids: m.labelIds || [],
      internal_date: internal,
      from_email: fromEmails[0] || '',
      from_name: fromRaw.replace(/<[^>]*>/, '').replace(/"/g, '').trim().slice(0, 120),
      to_emails: emails(header(h, 'To')),
      subject: header(h, 'Subject').slice(0, 300),
      auto_submitted: header(h, 'Auto-Submitted'),
      x_failed_recipients: emails(header(h, 'X-Failed-Recipients'))[0] || '',
      snippet: String(m.snippet || '').slice(0, 500),
      body_text: bodyText(m.payload)
    });
  });
});
return [{ json: { mailbox: base.mailbox, threads: threads, messages: messages } }];
"""

SPLIT = r"""
// One item per inbound reply that matched NOYA outreach. Builds the classification request.
var rows = ($input.first().json.to_classify) || [];
var system = [
  'You classify replies to outreach emails sent by NOYA Concierge, a luxury concierge and destination-management company.',
  'Be conservative. If the intent is not clear, answer UNKNOWN with low confidence. Never invent facts, dates, names or emails.',
  'Categories:',
  'POSITIVE - interested, open to talking or working together.',
  'MEETING_REQUEST - asks for or proposes a call or meeting, or asks for availability.',
  'NEEDS_INFO - asks questions or wants more information before deciding.',
  'NOT_NOW - interested in principle but not at this time.',
  'REFERRAL - points NOYA to another person.',
  'DECLINED - not interested.',
  'OUT_OF_OFFICE - automatic absence reply.',
  'UNRELATED - unrelated to NOYA outreach (newsletters, notifications, other topics).',
  'UNKNOWN - anything unclear.',
  'Return ONLY a JSON object with keys:',
  'classification, confidence (0-1), summary (max 40 words, factual),',
  'return_date (YYYY-MM-DD only if the email explicitly states a return or revisit date, else null),',
  'referred_name and referred_email (only if explicitly written in the email, else null),',
  'decline_type (HARD, SOFT or null), unsubscribe_requested (true only if they explicitly ask not to be contacted),',
  'suggested_reply (a short, warm, understated reply Adam could send, for POSITIVE, MEETING_REQUEST, NEEDS_INFO, REFERRAL or UNKNOWN; otherwise empty).',
  'The suggested reply is only a draft for Adam; never promise prices, availability or commitments.'
].join('\n');
return rows.map(function (m) {
  var user = 'Deterministic pre-label: ' + (m.prelabel || 'none') + '\n' +
    'From: ' + m.from_name + ' <' + m.from_email + '>\n' +
    'Subject: ' + m.subject + '\n\n' +
    'Email (new text only):\n' + (m.body_text || m.snippet || '').slice(0, 4000);
  return { json: Object.assign({}, m, {
    anthropic_body: {
      model: '__MODEL__',
      max_tokens: 900,
      system: system,
      messages: [{ role: 'user', content: user }]
    }
  }) };
});
""".replace("__MODEL__", MODEL)

PARSE = r"""
// Merges the model's JSON with the message. Any failure becomes UNKNOWN (human review).
var msg = $('Split For Classification').item.json;
var r = $json || {};
var out = { classification: 'UNKNOWN', confidence: 0, summary: '', suggested_reply: '' };
try {
  var text = (r.body && r.body.content && r.body.content[0] && r.body.content[0].text) || '';
  var s = text.indexOf('{'), e = text.lastIndexOf('}');
  if (Number(r.statusCode) === 200 && s >= 0 && e > s) out = Object.assign(out, JSON.parse(text.slice(s, e + 1)));
  else out.summary = 'Classifier unavailable (HTTP ' + r.statusCode + ') - needs human review.';
} catch (err) {
  out = { classification: 'UNKNOWN', confidence: 0, summary: 'Classifier output unreadable - needs human review.', suggested_reply: '' };
}
var p = Object.assign({}, msg);
delete p.anthropic_body;
['classification', 'confidence', 'summary', 'return_date', 'referred_name', 'referred_email',
 'decline_type', 'unsubscribe_requested', 'suggested_reply'].forEach(function (k) {
  p[k] = out[k] === undefined ? null : out[k];
});
return { json: { p: p } };
"""

WRONG = r"""
throw new Error('Workflow 13 stopped: Gmail credential is not noya@noyaconcierge.com (got ' + $json.emailAddress + ')');
"""


def rpc(var, fn, name, body, pos, extra=""):
    return f"""const {var} = node({{
  type: 'n8n-nodes-base.httpRequest',
  version: 4.5,
  config: {{
    name: '{name}',
    position: {pos},{extra}
    parameters: {{
      method: 'POST',
      url: '{SUPA}{fn}',
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true,
      contentType: 'json',
      specifyBody: 'json',
      jsonBody: {body},
      options: {{ timeout: 30000 }}
    }},
    credentials: {SUPA_CRED}
  }}
}});
"""


def code(var, name, js, pos, mode="runOnceForAllItems"):
    return f"""const {var} = node({{
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {{
    name: '{name}',
    position: {pos},
    parameters: {{ mode: '{mode}', jsCode: {json.dumps(js.strip())} }}
  }}
}});
"""


def gmail_get(var, name, url, pos, extra=""):
    return f"""const {var} = node({{
  type: 'n8n-nodes-base.httpRequest',
  version: 4.5,
  config: {{
    name: '{name}',
    position: {pos},{extra}
    parameters: {{
      method: 'GET',
      url: {url},
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'gmailOAuth2',
      options: {{ timeout: 30000, response: {{ response: {{ fullResponse: true, neverError: true }} }} }}
    }},
    credentials: {GMAIL_CRED}
  }}
}});
"""


def if_true(var, name, left, pos, op="true"):
    return f"""const {var} = ifElse({{
  version: 2.2,
  config: {{
    name: '{name}',
    position: {pos},
    parameters: {{
      conditions: {{
        options: {{ caseSensitive: false, leftValue: '', typeValidation: 'loose' }},
        conditions: [{left}],
        combinator: 'and'
      }}
    }}
  }}
}});
"""


e = lambda s: "expr(" + json.dumps("{{ " + s + " }}") + ")"
parts = ["""import { workflow, node, trigger, ifElse, expr } from '@n8n/workflow-sdk';

// 13 - NOYA Gmail Interaction Sync v1
// READS Gmail (GET only) and WRITES CRM through Supabase RPCs. It never sends, drafts or replies.
// Generated by n8n/gen_13_gmail_interaction_sync.py - edit that file, not this one.

const schedule = trigger({
  type: 'n8n-nodes-base.scheduleTrigger',
  version: 1.2,
  config: {
    name: 'Every 30 Minutes',
    position: [0, 200],
    parameters: { rule: { interval: [{ field: 'minutes', minutesInterval: 30 }] } }
  }
});

const manual = trigger({
  type: 'n8n-nodes-base.manualTrigger',
  version: 1,
  config: { name: 'Manual Sync', position: [0, 400] }
});
"""]
parts.append(f"""const verifyMailbox = node({{
  type: 'n8n-nodes-base.httpRequest',
  version: 4.5,
  config: {{
    name: 'Verify NOYA Mailbox',
    position: [220, 300],
    parameters: {{
      method: 'GET',
      url: 'https://gmail.googleapis.com/gmail/v1/users/me/profile',
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'gmailOAuth2',
      options: {{ timeout: 20000 }}
    }},
    credentials: {GMAIL_CRED}
  }}
}});
""")
parts.append(if_true("mailboxIsNoya", "Mailbox Is NOYA?",
    "{ leftValue: expr('{{ $json.emailAddress }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'noya@noyaconcierge.com' }",
    "[440, 300]"))
parts.append(code("wrongMailbox", "Stop - Wrong Mailbox", WRONG, "[660, 460]"))
parts.append(rpc("getTargets", "gmail_sync_targets", "Get Sync Targets", "'{}'", "[660, 300]"))
parts.append(code("buildSearch", "Build Gmail Search", BUILD_SEARCH, "[880, 300]"))
parts.append(gmail_get("searchThreads", "Search Contacted Senders", e("$json.search_url"), "[1100, 300]"))
parts.append(code("collect", "Collect Thread Ids", COLLECT, "[1320, 300]"))
parts.append(if_true("anyThreads", "Any Threads?",
    "{ leftValue: expr('{{ $json.has_threads }}'), operator: { type: 'boolean', operation: 'true', singleValue: true }, rightValue: '' }",
    "[1540, 300]"))
parts.append(gmail_get("getThread", "Read Gmail Thread",
    e("'https://gmail.googleapis.com/gmail/v1/users/me/threads/' + $json.thread_id + '?format=full'"), "[1760, 200]"))
parts.append(code("extract", "Extract Messages", EXTRACT, "[1980, 200]"))
parts.append(rpc("triage", "gmail_sync_triage", "Triage (log manual sends)",
    e("JSON.stringify({ p_mailbox: $json.mailbox, p_threads: $json.threads, p_messages: $json.messages })"), "[2200, 200]"))
parts.append(rpc("idleRun", "gmail_sync_triage", "Record Idle Run",
    e("JSON.stringify({ p_mailbox: 'noya@noyaconcierge.com', p_threads: [], p_messages: [] })"), "[1760, 420]"))
parts.append(code("split", "Split For Classification", SPLIT, "[2420, 200]"))
parts.append(f"""const classify = node({{
  type: 'n8n-nodes-base.httpRequest',
  version: 4.5,
  config: {{
    name: 'Classify Reply (Claude)',
    position: [2640, 200],
    parameters: {{
      method: 'POST',
      url: 'https://api.anthropic.com/v1/messages',
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'anthropicApi',
      sendHeaders: true,
      headerParameters: {{ parameters: [{{ name: 'anthropic-version', value: '2023-06-01' }}] }},
      sendBody: true,
      contentType: 'json',
      specifyBody: 'json',
      jsonBody: {e("JSON.stringify($json.anthropic_body)")},
      options: {{ timeout: 60000, response: {{ response: {{ fullResponse: true, neverError: true }} }} }}
    }},
    credentials: {ANTHROPIC_CRED}
  }}
}});
""")
parts.append(code("parse", "Parse Classification", PARSE, "[2860, 200]", mode="runOnceForEachItem"))
parts.append(rpc("ingest", "gmail_ingest_inbound", "Apply Reply To CRM", e("JSON.stringify($json)"), "[3080, 200]"))
parts.append("""
export default workflow('noya-13-gmail-interaction-sync', '13 - NOYA Gmail Interaction Sync v1')
  .add(schedule)
  .to(verifyMailbox)
  .to(mailboxIsNoya
    .onTrue(getTargets.to(buildSearch.to(searchThreads.to(collect.to(anyThreads
      .onTrue(getThread.to(extract.to(triage.to(split.to(classify.to(parse.to(ingest)))))))
      .onFalse(idleRun))))))
    .onFalse(wrongMailbox))
  .add(manual)
  .to(verifyMailbox);
""")
open("n8n/13_gmail_interaction_sync.workflow.ts", "w").write("\n".join(parts))
print("ok")
