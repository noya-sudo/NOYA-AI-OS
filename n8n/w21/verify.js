// Deterministic check: the backdrop must be one of the list, and every capitalised word or number in the concept must come
// from the evidence, the backdrop list or plain Egypt geography. Anything else is dropped, not saved.
var src = $('Build Prompts').all(0);
var ALLOWED = ('noya egypt egyptian cairo giza pyramids pyramid mena house grand museum gem nile aswan luxor el gouna red sea western desert white ' +
  'sahara siwa sinai upper private villa resort i a an the in at on from with for of and or this their its it we our').split(' ');
function inText(t, w) { return new RegExp('(^|[^a-z0-9])' + w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '([^a-z0-9]|$)').test(t); }
return $input.all().map(function (x, i) {
  var it = src[i].json, r = x.json || {};
  var err = r.error ? (typeof r.error === 'string' ? r.error : (r.error.message || JSON.stringify(r.error))) : '';
  var u = r.usageMetadata || {};
  var text = ''; try { text = (r.candidates[0].content.parts || []).map(function (p) { return p.text || ''; }).join(''); } catch (e) { text = ''; }
  var o = {}; try { o = JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1)); } catch (e) { o = {}; }
  var corpus = (it.company + ' ' + (it.company_type || '') + ' ' + (it.country || '') + ' ' + (it.evidence || '')).toLowerCase();
  var bad = [];
  (String(o.concept || '') + ' ' + String(o.commercial_value || '')).split(/(?<=[.?!])\s+/).forEach(function (sent) {
    (sent.match(/[A-Za-z][A-Za-z0-9'’&-]*/g) || []).forEach(function (w, k) {
      if (!/^[A-Z]/.test(w)) return;
      var b = w.toLowerCase().replace(/['’]s$/, '');
      if (ALLOWED.indexOf(b) >= 0 || inText(corpus, b) || (k === 0)) return;
      if (bad.indexOf(w) < 0) bad.push(w);
    });
  });
  ((String(o.concept || '') + ' ' + String(o.commercial_value || '')).match(/\d[\d,.]*/g) || []).forEach(function (n) { if (corpus.indexOf(n) < 0) bad.push(n); });
  var ok = !err && o.concept && it.backdrops.indexOf(o.backdrop) >= 0 && bad.length === 0;
  var rl = /429|too many requests|resource[_ ]exhausted|quota|rate limit/i.test(err);
  return { json: { ok: ok, company: it.company, unsupported: bad, error: err.slice(0, 160), p: { company_id: it.company_id, contact_id: it.contact_id || '',
    concept: ok ? o.concept : '', backdrop: o.backdrop || '', noya_role: o.noya_role || '', commercial_value: o.commercial_value || '',
    model: 'gemini-3.1-flash-lite',
    usage: [{ model: 'models/gemini-3.1-flash-lite', input_tokens: u.promptTokenCount || 0, output_tokens: u.candidatesTokenCount || 0,
              thinking_tokens: u.thoughtsTokenCount || 0, status: err ? (rl ? 'RATE_LIMITED' : 'ERROR') : 'OK' }] } } };
});
