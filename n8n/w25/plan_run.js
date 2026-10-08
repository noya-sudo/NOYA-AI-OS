// Live Hunter account -> how many Email Finder lookups this run may use (one credit each). Nothing is bought.
var r = $input.first().json || {};
var code = Number(r.statusCode || 0);
var d = (r.body && r.body.data) || {};
var req = d.requests || {};
function left(x) { return x && x.available != null ? Math.max(0, Number(x.available) - Number(x.used || 0)) : null; }
var cred = left(req.credits), srch = left(req.searches);
var room = cred == null ? (srch == null ? 0 : srch) : cred;
if (srch != null) room = Math.min(room, srch);
var ok = code >= 200 && code < 300 && !!d.plan_name;
return [{ json: { ok: ok, room: ok ? room : 0, plan: d.plan_name || null, http_status: code } }];
