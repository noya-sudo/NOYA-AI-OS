// One LinkedIn search per person. STILL_IN_ROLE only when a result's headline carries both the name and the company;
// MOVED only when the person's headline names another employer and nothing in the result mentions this company;
// anything else is NOT_FOUND (the draft is kept and the note says the role was not re-confirmed).
var src = $('Has Name?').all(0);
var STOPW = ('the and of hotel hotels resort resorts group collection travel events company club luxury villa villas residences ' +
  'international global limited ltd llc inc co uk london dubai').split(' ');
function norm(s) { return String(s || '').toLowerCase().replace(/[’]/g, "'").replace(/[^a-z0-9@._' -]/g, ' ').replace(/\s+/g, ' ').trim(); }
return $input.all().map(function (x, i) {
  var it = src[i].json, org = (x.json && x.json.organic) || [];
  var fn = norm(it.first_name), ln = norm(it.last_name);
  var full = norm(String(it.company).replace(/\(.*?\)/g, ' '));
  var toks = full.split(' ').filter(function (w) { return w.length >= 4 && STOPW.indexOf(w) < 0; });
  function names(b) { return b.indexOf(full) >= 0 || toks.some(function (w) { return b.indexOf(w) >= 0; }); }
  var check = 'NOT_FOUND', url = null;
  for (var k = 0; k < org.length; k++) {
    var t = norm(org[k].title), s = norm(org[k].snippet);
    if (t.indexOf(fn) < 0 || t.indexOf(ln) < 0) continue;
    if (names(t)) { check = 'STILL_IN_ROLE'; url = org[k].link; break; }
    if (check === 'NOT_FOUND' && / - /.test(org[k].title || '') && !names(s)) { check = 'MOVED'; url = org[k].link; }
  }
  return { json: { task_id: it.task_id, role_check: check, evidence_url: url, why_now_stale: it.why_now_stale } };
});
