// Only a definite Hunter answer is saved. 202 (still verifying), 429 and errors are left for the next run (no credit charged).
var src = $('Split Queue').all();
var out = [];
$input.all().forEach(function (x, i) {
  var it = src[i] && src[i].json; if (!it) return;
  var r = x.json || {}; var code = Number(r.statusCode || 0); var d = (r.body && r.body.data) || {};
  if (code !== 200 || !d.status) return;
  out.push({ json: { p: {
    contact_id: it.contact_id, email: it.email, status: d.status, result: d.result || null, score: d.score, accept_all: d.accept_all,
    sources: (d.sources || []).slice(0, 5).map(function (s) { return { uri: s.uri, domain: s.domain, extracted_on: s.extracted_on, still_on_page: s.still_on_page }; }),
    execution: String($execution.id) } } });
});
return out;
