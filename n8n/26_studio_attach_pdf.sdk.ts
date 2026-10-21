// NOYA 26 — Studio: attach an approved PDF to its Gmail draft, verify it, then READY TO SEND (Adam, 21 Oct: 1A 2A 3A).
// Build brief → Quality review → Approved → Gmail draft → PDF attached → READY TO SEND. A Claude Studio session posts the PDF
// (multipart: file, slug, version) with n8n/attach_pdf.mjs. Supabase decides whether it may be attached
// (studio_attachment_target): the latest version, APPROVED, unsent, exactly the approved PDF (its exact fingerprint, or its
// render-proof fingerprint, which ignores only the render timestamp), and the one unsent Gmail draft recorded for that
// document; the caller never chooses a draft. n8n uses the existing NOYA Gmail and Supabase credentials; the caller holds none.
// The draft is never sent. After the upload the draft is re-read, the attachment is downloaded back from Gmail and matched byte
// for byte to the file that was posted; only then does studio_attachment_verified write READY TO SEND.
// Run data is not stored (settings: no saved executions), so the PDF does not stay in n8n. The live webhook path is random and
// kept out of this public repo.
import { workflow, node, trigger, ifElse, expr } from '@n8n/workflow-sdk';

const SUPABASE = 'https://gagbhykzmtstekpqujyl.supabase.co/rest/v1/rpc';
const GMAIL = 'https://gmail.googleapis.com';
const gmail = { gmailOAuth2: { id: 'OMGm2CkcvDKbJTr3', name: 'NOYA Gmail' } };
const supabase = { supabaseApi: { id: 'EkLYXHBGqNUjAGKP', name: 'Supabase account' } };

const receive = trigger({
  type: 'n8n-nodes-base.webhook',
  version: 2.2,
  config: { name: 'Receive the approved PDF', parameters: { httpMethod: 'POST', path: 'noya-studio-attach-<secret-path>', responseMode: 'responseNode', options: {} } },
});

const fingerprint = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Fingerprint the PDF',
    onError: 'continueErrorOutput',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode: `const crypto = require('crypto');
const item = $input.first();
const body = item.json.body || {};
const key = Object.keys(item.binary || {})[0];
if (!key) return [{ json: { ok: false, reason: 'NO_FILE' } }];
const slug = String(body.slug || ''); const version = parseInt(body.version, 10);
if (!/^[a-z0-9-]{3,80}$/.test(slug) || !(version > 0)) return [{ json: { ok: false, reason: 'SLUG_AND_VERSION_REQUIRED' } }];
const buf = await this.helpers.getBinaryDataBuffer(0, key);
if (buf.length > 8 * 1024 * 1024 || buf.slice(0, 5).toString('latin1') !== '%PDF-') return [{ json: { ok: false, reason: 'NOT_A_PDF_UNDER_8MB' } }];
const sha256 = crypto.createHash('sha256').update(buf).digest('hex');
const fp = crypto.createHash('sha256').update(buf.toString('latin1').replace(/\\(D:\\d{14}[^)]*\\)/g, '(D:)'), 'latin1').digest('hex');
return [{ json: { ok: true, slug, version, sha256, fingerprint: fp, bytes: buf.length, pdf_b64: buf.toString('base64') } }];`,
    },
  },
});

const isPdf = ifElse({
  version: 2.2,
  config: {
    name: 'A PDF under 8 MB?',
    parameters: {
      conditions: {
        options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
        conditions: [{ leftValue: expr('{{ $json.ok }}'), operator: { type: 'boolean', operation: 'true', singleValue: true } }],
        combinator: 'and',
      },
    },
  },
});

const checkDocument = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.5,
  config: {
    name: 'Check the document',
    onError: 'continueErrorOutput',
    parameters: {
      method: 'POST', url: `${SUPABASE}/studio_attachment_target`, authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendBody: true, contentType: 'json', specifyBody: 'json',
      jsonBody: expr('{{ JSON.stringify({ p_slug: $json.slug, p_version: $json.version, p_sha256: $json.sha256, p_fingerprint: $json.fingerprint, p_bytes: $json.bytes }) }}'),
      options: {},
    },
    credentials: supabase,
  },
});

const allowed = ifElse({
  version: 2.2,
  config: {
    name: 'Approved, matching and with a draft?',
    parameters: {
      conditions: {
        options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
        conditions: [{ leftValue: expr('{{ $json.ok }}'), operator: { type: 'boolean', operation: 'true', singleValue: true } }],
        combinator: 'and',
      },
    },
  },
});

const getDraft = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.5,
  config: {
    name: 'Read the Gmail draft',
    onError: 'continueErrorOutput',
    parameters: { method: 'GET', url: expr(`{{ '${GMAIL}/gmail/v1/users/me/drafts/' + $json.draft_id + '?format=raw' }}`), authentication: 'predefinedCredentialType', nodeCredentialType: 'gmailOAuth2', options: {} },
    credentials: gmail,
  },
});

const addPdf = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Add the PDF to the message',
    onError: 'continueErrorOutput',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode: `const target = $('Check the document').first().json;
const pdf = $('Fingerprint the PDF').first().json;
const draft = $input.first().json;
const mime = Buffer.from(draft.message.raw.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
if (mime.indexOf('\\uFFFD') >= 0) throw new Error('DRAFT_NOT_UTF8: the draft would not survive a rebuild; attach this one by hand');
const nl = mime.indexOf('\\r\\n') >= 0 ? '\\r\\n' : '\\n';
const sep = mime.indexOf(nl + nl);
const head = mime.slice(0, sep); const body = mime.slice(sep + 2 * nl.length);
const headers = [];
head.split(nl).forEach((l) => { if (/^[ \\t]/.test(l) && headers.length) headers[headers.length - 1] += nl + l; else headers.push(l); });
const get = (n) => { const h = headers.find((x) => x.toLowerCase().startsWith(n.toLowerCase() + ':')); return h ? h.slice(n.length + 1).trim() : ''; };
const file = target.file_name;
if (mime.indexOf('filename="' + file + '"') >= 0) return [{ json: { already: true } }];
const ctype = get('Content-Type') || 'text/plain; charset=UTF-8'; const cte = get('Content-Transfer-Encoding');
const part = 'Content-Type: application/pdf; name="' + file + '"' + nl + 'Content-Disposition: attachment; filename="' + file + '"' + nl + 'Content-Transfer-Encoding: base64' + nl + nl + pdf.pdf_b64.replace(/(.{76})/g, '$1' + nl) + nl;
const mixed = /^multipart\\/mixed/i.test(ctype) ? /boundary="?([^";\\s]+)"?/i.exec(ctype) : null;
let message;
if (mixed) { const close = body.lastIndexOf('--' + mixed[1] + '--'); message = head + nl + nl + body.slice(0, close) + '--' + mixed[1] + nl + part + body.slice(close); }
else { const B = 'noya_studio_' + Date.now().toString(36); const kept = headers.filter((x) => !/^(content-type|content-transfer-encoding|mime-version):/i.test(x));
  message = kept.join(nl) + nl + 'MIME-Version: 1.0' + nl + 'Content-Type: multipart/mixed; boundary="' + B + '"' + nl + nl + '--' + B + nl + 'Content-Type: ' + ctype + nl + (cte ? 'Content-Transfer-Encoding: ' + cte + nl : '') + nl + body + nl + '--' + B + nl + part + '--' + B + '--' + nl; }
const R = 'noya_rel_' + Date.now().toString(36);
const upload = '--' + R + '\\r\\nContent-Type: application/json; charset=UTF-8\\r\\n\\r\\n' + JSON.stringify({ id: target.draft_id, message: { threadId: draft.message.threadId } }) + '\\r\\n--' + R + '\\r\\nContent-Type: message/rfc822\\r\\n\\r\\n' + message + '\\r\\n--' + R + '--';
return [{ json: { already: false, contentType: 'multipart/related; boundary=' + R, upload } }];`,
    },
  },
});

const needsUpload = ifElse({
  version: 2.2,
  config: {
    name: 'Already on the draft?',
    parameters: {
      conditions: {
        options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
        conditions: [{ leftValue: expr('{{ $json.already }}'), operator: { type: 'boolean', operation: 'true', singleValue: true } }],
        combinator: 'and',
      },
    },
  },
});

const updateDraft = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.5,
  config: {
    name: 'Attach it to the same draft',
    onError: 'continueErrorOutput',
    parameters: {
      method: 'PUT',
      url: expr(`{{ '${GMAIL}/upload/gmail/v1/users/me/drafts/' + $('Check the document').first().json.draft_id + '?uploadType=multipart' }}`),
      authentication: 'predefinedCredentialType', nodeCredentialType: 'gmailOAuth2',
      sendBody: true, contentType: 'raw', rawContentType: expr('{{ $json.contentType }}'), body: expr('{{ $json.upload }}'),
      options: { timeout: 60000 },
    },
    credentials: gmail,
  },
});

const reread = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.5,
  config: {
    name: 'Re-read the draft',
    onError: 'continueErrorOutput',
    parameters: {
      method: 'GET',
      url: expr(`{{ '${GMAIL}/gmail/v1/users/me/drafts/' + $('Check the document').first().json.draft_id + '?format=full' }}`),
      authentication: 'predefinedCredentialType', nodeCredentialType: 'gmailOAuth2', options: {},
    },
    credentials: gmail,
  },
});

const findAttachment = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Find the attachment',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode: `const target = $('Check the document').first().json;
const msg = $input.first().json.message || {};
const parts = []; const walk = (p) => { if (!p) return; if (p.filename) parts.push(p); (p.parts || []).forEach(walk); }; walk(msg.payload);
const att = parts.filter((p) => p.filename === target.file_name && p.body && p.body.attachmentId);
return [{ json: { found: att.length === 1, message_id: msg.id || null, attachment_id: att.length === 1 ? att[0].body.attachmentId : null, attachments: parts.map((p) => p.filename), reason: att.length > 1 ? 'SAME_FILE_ATTACHED_TWICE' : 'NOT_ON_THE_DRAFT' } }];`,
    },
  },
});

const isFound = ifElse({
  version: 2.2,
  config: {
    name: 'On the draft?',
    parameters: {
      conditions: {
        options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
        conditions: [{ leftValue: expr('{{ $json.found }}'), operator: { type: 'boolean', operation: 'true', singleValue: true } }],
        combinator: 'and',
      },
    },
  },
});

const download = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.5,
  config: {
    name: 'Download it back from Gmail',
    onError: 'continueErrorOutput',
    parameters: {
      method: 'GET',
      url: expr(`{{ '${GMAIL}/gmail/v1/users/me/messages/' + $json.message_id + '/attachments/' + $json.attachment_id }}`),
      authentication: 'predefinedCredentialType', nodeCredentialType: 'gmailOAuth2', options: { timeout: 60000 },
    },
    credentials: gmail,
  },
});

const verify = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Match it to the approved file',
    parameters: {
      mode: 'runOnceForAllItems',
      jsCode: `const crypto = require('crypto');
const pdf = $('Fingerprint the PDF').first().json;
const found = $('Find the attachment').first().json;
const buf = Buffer.from(String($input.first().json.data || '').replace(/-/g, '+').replace(/_/g, '/'), 'base64');
const sha256 = crypto.createHash('sha256').update(buf).digest('hex');
const fp = crypto.createHash('sha256').update(buf.toString('latin1').replace(/\\(D:\\d{14}[^)]*\\)/g, '(D:)'), 'latin1').digest('hex');
const verified = buf.length === pdf.bytes && sha256 === pdf.sha256;
return [{ json: { verified, message_id: found.message_id, sha256, fingerprint: fp, bytes: buf.length, attachments: found.attachments, reason: verified ? null : 'ATTACHMENT_DOES_NOT_MATCH' } }];`,
    },
  },
});

const isVerified = ifElse({
  version: 2.2,
  config: {
    name: 'The approved file, byte for byte?',
    parameters: {
      conditions: {
        options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
        conditions: [{ leftValue: expr('{{ $json.verified }}'), operator: { type: 'boolean', operation: 'true', singleValue: true } }],
        combinator: 'and',
      },
    },
  },
});

const record = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.5,
  config: {
    name: 'Record READY TO SEND',
    onError: 'continueErrorOutput',
    parameters: {
      method: 'POST', url: `${SUPABASE}/studio_attachment_verified`, authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendBody: true, contentType: 'json', specifyBody: 'json',
      jsonBody: expr("{{ JSON.stringify({ p_slug: $('Fingerprint the PDF').first().json.slug, p_version: $('Fingerprint the PDF').first().json.version, p_draft_id: $('Check the document').first().json.draft_id, p_message_id: $json.message_id, p_sha256: $json.sha256, p_fingerprint: $json.fingerprint, p_bytes: $json.bytes }) }}"),
      options: {},
    },
    credentials: supabase,
  },
});

const recorded = ifElse({
  version: 2.2,
  config: {
    name: 'Recorded?',
    parameters: {
      conditions: {
        options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
        conditions: [{ leftValue: expr('{{ $json.ok }}'), operator: { type: 'boolean', operation: 'true', singleValue: true } }],
        combinator: 'and',
      },
    },
  },
});

const done = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.5,
  config: { name: 'Attached and verified', parameters: { respondWith: 'json', responseBody: expr("{{ JSON.stringify(Object.assign({}, $json, { sha256: $('Match it to the approved file').first().json.sha256, bytes: $('Match it to the approved file').first().json.bytes, attachments: $('Match it to the approved file').first().json.attachments })) }}"), options: { responseCode: 200 } } },
});
const notPdf = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.5,
  config: { name: 'Refused: not a PDF', parameters: { respondWith: 'json', responseBody: expr('{{ JSON.stringify({ ok: false, reason: $json.reason }) }}'), options: { responseCode: 400 } } },
});
const refused = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.5,
  config: { name: 'Refused: not allowed', parameters: { respondWith: 'json', responseBody: expr("{{ JSON.stringify({ ok: false, reason: $json.reason || 'NOT_ALLOWED' }) }}"), options: { responseCode: 409 } } },
});
const notVerified = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.5,
  config: { name: 'Not verified', parameters: { respondWith: 'json', responseBody: expr("{{ JSON.stringify({ ok: false, reason: $json.reason || 'NOT_VERIFIED', attachments: $json.attachments }) }}"), options: { responseCode: 422 } } },
});
const failed = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.5,
  config: { name: 'A step failed', parameters: { respondWith: 'json', responseBody: expr("{{ JSON.stringify({ ok: false, reason: 'STEP_FAILED', step: $prevNode.name, message: String(typeof $json.error === 'string' ? $json.error : (($json.error && ($json.error.message || $json.error.description)) || $json.message || '')).slice(0, 400) }) }}"), options: { responseCode: 502 } } },
});

export default workflow('noya-26-studio-attach-pdf', 'NOYA 26 — Studio: attach approved PDF to its Gmail draft')
  .add(receive)
  .to(fingerprint)
  .to(isPdf
    .onTrue(checkDocument.to(allowed
      .onTrue(getDraft.to(addPdf).to(needsUpload
        .onTrue(reread)
        .onFalse(updateDraft.to(reread))))
      .onFalse(refused)))
    .onFalse(notPdf))
  .add(reread)
  .to(findAttachment)
  .to(isFound
    .onTrue(download.to(verify).to(isVerified
      .onTrue(record.to(recorded
        .onTrue(done)
        .onFalse(refused)))
      .onFalse(notVerified)))
    .onFalse(notVerified))
  .add(fingerprint.onError(failed))
  .add(checkDocument.onError(failed))
  .add(getDraft.onError(failed))
  .add(addPdf.onError(failed))
  .add(updateDraft.onError(failed))
  .add(reread.onError(failed))
  .add(download.onError(failed))
  .add(record.onError(failed));
