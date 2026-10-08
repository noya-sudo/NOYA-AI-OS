// Live Hunter account -> how many verifications this run may use. Nothing is bought: if the account is short, the run is short.
var r = $input.first().json || {};
var code = Number(r.statusCode || 0);
var d = (r.body && r.body.data) || {};
var req = d.requests || {};
function left(x) { return x && x.available != null ? Math.max(0, Number(x.available) - Number(x.used || 0)) : null; }
var ver = left(req.verifications), cred = left(req.credits);
var room = ver == null ? 0 : ver;
if (cred != null) room = Math.min(room, Math.floor(cred * 2)); // a verification costs half a credit
var ok = code >= 200 && code < 300 && !!d.plan_name;
var account = {
  ok: ok, http_status: code, plan: d.plan_name || null, reset_date: d.reset_date || null,
  verifications_used: req.verifications ? req.verifications.used : null, verifications_available: req.verifications ? req.verifications.available : null,
  credits_used: req.credits ? req.credits.used : null, credits_available: req.credits ? req.credits.available : null,
  searches_used: req.searches ? req.searches.used : null, searches_available: req.searches ? req.searches.available : null,
  verifications_left: ok ? room : null
};
return [{ json: { account: account, room: ok ? room : 0 } }];
