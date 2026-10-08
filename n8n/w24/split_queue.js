// The queue already applies the daily cap; here the live account and the reserve can only shorten it.
var q = $input.first().json || {};
var plan = $('Plan Run').first().json;
var reserve = Number(q.reserve_verifications || 0);
var n = Math.max(0, Math.min((q.items || []).length, plan.room - reserve));
if (!q.enabled || !plan.account.ok) n = 0;
return (q.items || []).slice(0, n).map(function (i) { return { json: i }; });
