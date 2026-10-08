// A definite Hunter answer is saved (found + verification status, or not found). 202 / 429 are left for the next run.
// The database keeps a provider address only when Hunter verifies it valid on the company domain.
var src = $('Split Queue').all();
var out = [];
$input.all().forEach(function (x, i) {
  var it = src[i] && src[i].json; if (!it) return;
  var r = x.json || {}; var code = Number(r.statusCode || 0); var d = (r.body && r.body.data) || {};
  if (code === 202 || code === 429) return;
  out.push({ json: { p: {
    contact_id: it.contact_id, status_code: code, email: d.email || '', score: d.score,
    verification: (d.verification && d.verification.status) || '',
    sources: (d.sources || []).slice(0, 5).map(function (s) { return { uri: s.uri, domain: s.domain, extracted_on: s.extracted_on, still_on_page: s.still_on_page }; }),
    execution: String($execution.id) } } });
});
return out;
