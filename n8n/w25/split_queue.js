// The queue applies the daily finder cap; the live credits and the reserve (kept for verification) can only shorten it.
var q = $input.first().json || {};
var plan = $('Plan Run').first().json;
var n = Math.max(0, Math.min((q.items || []).length, plan.room - Number(q.reserve_credits || 0)));
if (!plan.ok) n = 0;
return (q.items || []).slice(0, n).map(function (i) { return { json: i }; });
