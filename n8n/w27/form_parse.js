// W27 forms: read the Flash-Lite copy and map every form field deterministically from the sender profile (name, company, email,
// website, subject, message, sensible dropdown choice). Fields that need Adam (a required phone number with none on record, a
// consent box, dates or budgets) are listed in _needs_adam and left empty. form_prepare_save then runs the quality check.
var src = $('Build Form Prompts').all();
function fillField(fl, s, subject, message) {
  var k = ((fl.name || '') + ' ' + (fl.label || '')).toLowerCase(), t = fl.type, lab = String(fl.label || '').toLowerCase().replace(/[^a-z ]/g, ' ').trim();
  // Anti-spam honeypot fields must stay empty (filling one marks the enquiry as spam).
  if (/(^|[\[_-])(hp|honeypot|bot-?field|trap|website_url_hp)([\]_-]|$)/i.test(fl.name || '') || /honeypot|leave (this )?(field )?(blank|empty)/.test(k)) return '';
  if (t === 'textarea') return message;
  if (/^first( name)?$/.test(lab)) return s.first_name || '';
  if (/^(last|surname|family)( name)?$/.test(lab)) return s.last_name || '';
  if (t === 'checkbox' || t === 'radio') { if (/newsletter|marketing|subscribe|updates/.test(k)) return ''; return fl.required ? null : ''; }
  if (/e-?mail/.test(k)) return s.email || '';
  if (/first.?name|fname|given.?name|forename/.test(k)) return s.first_name || '';
  if (/last.?name|lname|surname|family.?name/.test(k)) return s.last_name || '';
  if (/phone|\btel\b|mobile|whatsapp/.test(k)) return s.phone || (fl.required ? null : '');
  if (t === 'select') {
    var opts = (fl.options || []).filter(function (o) { return o && !/^(select|choose|please|--|-)/i.test(o); });
    var hit = opts.filter(function (o) { return /partner|collaborat|business|trade|commercial|b2b|corporate|agency|supplier|vendor|press|media|general|other/i.test(o); })[0];
    if (/country/.test(k)) hit = opts.filter(function (o) { return /egypt/i.test(o); })[0] || hit;
    return hit || (fl.required ? null : '');
  }
  if (/company|organi[sz]ation|business.?name|brand|agency|firm/.test(k)) return s.company || '';
  if (/website|url|\bsite\b|domain/.test(k)) return s.website || '';
  if (/subject|topic|regarding|reason/.test(k)) return subject;
  if (/job|position|role|title/.test(k)) return s.role || '';
  if (/country/.test(k)) return s.country || '';
  if (/date|budget|guests|arrival|departure|check.?in|nights|people|number|city/.test(k)) return fl.required ? null : '';
  if (/name/.test(k)) return s.name || '';
  return fl.required ? null : '';
}
return $input.all().map(function (x, i) {
  var f = (src[i] || {}).json || {}, r = x.json || {};
  var err = r.error ? (typeof r.error === 'string' ? r.error : (r.error.message || JSON.stringify(r.error))) : '';
  var text = '';
  try { text = (r.candidates[0].content.parts || []).filter(function (p) { return !p.thought; }).map(function (p) { return p.text || ''; }).join(''); } catch (e) { text = ''; }
  var o = {};
  try { o = JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1)); } catch (e) { o = {}; }
  var subject = String(o.subject || '').trim().slice(0, 120), message = String(o.message || '').trim();
  var fields = {}, needs = [], s = f.sender || {};
  (f.fields || []).forEach(function (fl) {
    if (!fl || !fl.name) return;
    var v = fillField(fl, s, subject, message);
    if (v === null) { needs.push(fl.label || fl.name); return; }
    if (v !== '') fields[fl.name] = v;
  });
  if (needs.length) fields._needs_adam = needs;
  return { json: { company: f.company, error: err.slice(0, 160),
    p: { form_id: f.form_id, subject: subject, message: message, fields: fields, model: 'gemini-3.5-flash-lite',
      fit: o.fit === false ? 'false' : (o.fit === true ? 'true' : ''), fit_reason: String(o.fit_reason || '').slice(0, 240) } } };
});
