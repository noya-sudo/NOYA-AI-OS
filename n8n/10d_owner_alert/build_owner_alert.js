// Owner alert: one internal email to noya@ the moment an enquiry is saved.
// Internal only. Nothing here ever goes to the client.
const row = $input.first().json;
const v = $('Validate & Normalize Enquiry').first().json;
let raw = {};
try { const w = $('Website Enquiry Webhook').first().json; raw = (w && w.body) ? w.body : (w || {}); } catch (e) { raw = {}; }
const s = (x) => (x === undefined || x === null) ? '' : String(x).trim();

const ref = s(row.reference) || s(v.reference);
const name = s(row.full_name) || s(v.fullName);
const email = s(row.email) || s(v.email);

// Service: the form category in plain words, plus the sub-choice the client picked.
const prefixLabel = { 'CORPORATE': 'Corporate', 'BRAND PRODUCTION': 'Brands & production', 'PARTNERSHIP': 'Partnerships' };
const categoryLabel = {
  PRIVATE_VILLAS: 'Villas & residences', TRAVEL_LIFESTYLE: 'Travel & lifestyle', CORPORATE_BRAND: 'Corporate',
  WEDDING_EVENT: 'Weddings & events', MEMBERSHIP: 'Membership application', OTHER: 'General enquiry',
};
const req = s(raw.requirement_type);
const cut = req.indexOf(':');
const reqPrefix = (cut >= 0 ? req.slice(0, cut) : req).trim().toUpperCase();
const reqSub = cut >= 0 ? req.slice(cut + 1).trim() : '';
let service = prefixLabel[reqPrefix] || categoryLabel[s(row.menu_category) || v.menuCategory] || 'General enquiry';
const detail = reqSub || s(v.occasion);
if (detail) service += ' — ' + detail;
if (v.isCalendar) service = 'Private Calendar — ' + v.eventName;

// Destination / context
const ctx = [];
if (v.isCalendar && v.eventLabel) ctx.push(v.eventLabel);
if (s(v.destination)) ctx.push(s(v.destination));
if (s(v.companyName)) ctx.push('Company: ' + s(v.companyName));
if (v.guests) ctx.push(v.guests + ' guests');
if (s(v.budget)) ctx.push('Budget: ' + s(v.budget));

const dates = (v.dateFrom || v.dateTo) ? (s(v.dateFrom) || '?') + ' to ' + (s(v.dateTo) || '?') : 'Not given';

// Phone: a WhatsApp link only for a number already in international format.
const phoneRaw = s(row.phone) || s(v.phone);
let phoneLine = 'Not given';
if (phoneRaw) {
  let p = phoneRaw.replace(/[\s().\-]/g, '');
  if (p.startsWith('00')) p = '+' + p.slice(2);
  if (/^\+[1-9]\d{7,14}$/.test(p)) phoneLine = p + '  ·  https://wa.me/' + p.slice(1) + '  (international format; WhatsApp use not confirmed)';
  else phoneLine = phoneRaw + '  (no country code: confirm before messaging)';
}

const msg = s(v.message).replace(/\s+/g, ' ');
const preview = msg ? (msg.length > 280 ? msg.slice(0, 277) + '…' : msg) : 'No message';

const utm = [['source', v.utmSource], ['medium', v.utmMedium], ['campaign', v.utmCampaign], ['term', v.utmTerm], ['content', v.utmContent]]
  .filter((p) => s(p[1])).map((p) => p[0] + '=' + s(p[1]));
const landing = s(v.landingPage);
const gclid = /[?&](gclid|gbraid|wbraid)=/.test(landing);
let source = utm.length ? utm.join(', ') : 'No campaign tags';
if (gclid) source += ' · Google Ads click id present';
const sourceLines = [source];
if (s(v.sourcePage)) sourceLines.push('Form page: ' + s(v.sourcePage));
if (s(v.referrer)) sourceLines.push('Referrer: ' + s(v.referrer));

const isTest = /DO NOT ACTION|PRODUCTION TEST/i.test(name + ' ' + msg);
const subject = (isTest ? '[TEST] ' : '') + 'NEW NOYA ENQUIRY · ' + service.split(' — ')[0] + ' · ' + name + ' · ' + ref;

const text = [
  'NEW NOYA ENQUIRY' + (isTest ? ' (TEST: do not action)' : ''),
  '',
  'Name: ' + name,
  'Service: ' + service,
  'Destination / context: ' + (ctx.join(' · ') || 'Not given'),
  'Dates: ' + dates,
  'Phone / WhatsApp: ' + phoneLine,
  'Email: ' + email,
  'Message: ' + preview,
  'Source / campaign: ' + sourceLines.join('\n    '),
  '',
  'HQ: reference ' + ref + ' · https://hq.noyaconcierge.com (Today, task "New website enquiry … (' + ref + ')")',
  '',
  'The enquiry is saved in HQ. The client has seen the on-screen confirmation only; nothing has been sent to them.',
].join('\n');

return [{ json: { reference: ref, subject, text, isTest } }];
