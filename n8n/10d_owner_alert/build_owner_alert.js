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
const menu = s(row.menu_category) || s(v.menuCategory);

// Service: the form category in plain words, plus the client's own choice.
// requirement_type is "<PREFIX>: <choice>" from the corporate, brands and partnerships forms.
const prefixLabel = { 'CORPORATE': 'Corporate', 'BRAND PRODUCTION': 'Brands & production', 'PARTNERSHIP': 'Partnerships' };
const categoryLabel = {
  PRIVATE_VILLAS: 'Villas & residences', TRAVEL_LIFESTYLE: 'Travel & lifestyle', CORPORATE_BRAND: 'Corporate',
  WEDDING_EVENT: 'Weddings & events', MEMBERSHIP: 'Membership application', OTHER: 'General enquiry',
};
const req = s(raw.requirement_type) || s(v.requirementType);
const cut = req.indexOf(':');
const reqPrefix = (cut >= 0 ? req.slice(0, cut) : req).trim().toUpperCase();
const reqSub = cut >= 0 ? req.slice(cut + 1).trim() : '';
const isBusiness = menu === 'CORPORATE_BRAND';
let service = prefixLabel[reqPrefix] || categoryLabel[menu] || 'General enquiry';
// On the business forms "occasion" is the client's role, not a service.
const detail = reqSub || (isBusiness ? '' : s(v.occasion));
if (detail) service += ' — ' + detail;
if (v.isCalendar) service = 'Private Calendar — ' + v.eventName;

// Destination / context
const ctx = [];
if (v.isCalendar && v.eventLabel) ctx.push(v.eventLabel);
if (s(v.destination)) ctx.push(s(v.destination));
if (s(v.companyName)) ctx.push('Company: ' + s(v.companyName));
if (isBusiness && s(v.occasion)) ctx.push('Role: ' + s(v.occasion));
if (isBusiness && reqPrefix === 'CORPORATE' && s(v.propertyPreferences)) ctx.push('One-off or recurring: ' + s(v.propertyPreferences));
if (menu === 'MEMBERSHIP' && s(v.specialRequirements)) ctx.push('Heard of NOYA via: ' + s(v.specialRequirements));
if (v.guests) ctx.push(v.guests + ' guests');
if (v.bedrooms) ctx.push(v.bedrooms + ' bedrooms');
if (s(v.budget)) ctx.push('Budget: ' + s(v.budget));

let dates = (v.dateFrom || v.dateTo) ? (s(v.dateFrom) || '?') + ' to ' + (s(v.dateTo) || '?') : 'Not given';
if (dates === 'Not given' && v.isCalendar && s(v.eventDates)) dates = 'Event dates ' + s(v.eventDates).replace('/', ' to ');

// Phone: a WhatsApp link only for a number already in international format.
// A national trunk 0 written after the country code ("+44 (0)7…", "+20 010…") is dropped first.
const TRUNK_ZERO = /^\+(971|966|974|965|973|968|962|961|353|212|44|20|33|49|41|31|32|43|61|27|90|91|234|254)0(\d+)$/;
const phoneRaw = s(row.phone) || s(v.phone);
let phoneLine = 'Not given';
if (phoneRaw) {
  let p = phoneRaw.replace(/\(0\)/g, '').replace(/[\s().\-]/g, '');
  if (p.startsWith('00')) p = '+' + p.slice(2);
  const t = p.match(TRUNK_ZERO);
  if (t) p = '+' + t[1] + t[2];
  if (/^\+[1-9]\d{7,14}$/.test(p)) phoneLine = p + '  ·  https://wa.me/' + p.slice(1) + '  (international format; WhatsApp use not confirmed)';
  else if (p.startsWith('+')) phoneLine = phoneRaw + '  (not a valid international number: confirm before messaging)';
  else phoneLine = phoneRaw + '  (no country code: confirm before messaging)';
}

// Message preview: the client's own words, whichever field the form used for them
// (villas, weddings and membership keep their main text in property_preferences).
const mainInPreferences = ['PRIVATE_VILLAS', 'WEDDING_EVENT', 'MEMBERSHIP'].includes(menu);
const prefs = (isBusiness && reqPrefix === 'CORPORATE') ? '' : s(v.propertyPreferences);
const parts = mainInPreferences ? [prefs, s(v.message)] : [s(v.message), prefs];
if (menu !== 'MEMBERSHIP') parts.push(s(v.specialRequirements));
const words = parts.filter((x, i) => x && parts.indexOf(x) === i).join(' · ').replace(/\s+/g, ' ');
const preview = words ? (words.length > 280 ? words.slice(0, 277) + '…' : words) : 'No message';

const utm = [['source', v.utmSource], ['medium', v.utmMedium], ['campaign', v.utmCampaign], ['term', v.utmTerm], ['content', v.utmContent]]
  .filter((p) => s(p[1])).map((p) => p[0] + '=' + s(p[1]));
const landing = s(v.landingPage);
const gclid = /[?&](gclid|gbraid|wbraid)=/.test(landing);
let source = utm.length ? utm.join(', ') : 'No campaign tags';
if (gclid) source += ' · Google Ads click id present';
const sourceLines = [source];
if (s(v.sourcePage)) sourceLines.push('Form page: ' + s(v.sourcePage));
if (s(v.referrer)) sourceLines.push('Referrer: ' + s(v.referrer));

const isTest = /DO NOT ACTION|PRODUCTION TEST/i.test(name + ' ' + words);
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
