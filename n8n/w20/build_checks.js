// Drafts older than 14 days are revalidated, never blindly redrafted (Adam, 7 Oct 2026). Deterministic checks come from
// revalidation_queue (company still qualified, still cold, no new Gmail, no newer duplicate); here we add the date test on the
// why-now line and build the one search that confirms the person still holds the role.
var items = ($input.first().json.items) || [];
var MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, sept: 8, oct: 9, nov: 10, dec: 11 };
var now = new Date(), year = now.getUTCFullYear();
function latestDate(text) {
  text = String(text || '');
  var best = null, m;
  var re = /\b(\d{1,2})(?:\s*[-–]\s*(\d{1,2}))?\s+(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*\.?(?:\s+(20\d\d))?/gi;
  while ((m = re.exec(text))) {
    var d = new Date(Date.UTC(m[4] ? +m[4] : year, MONTHS[m[3].toLowerCase()], +(m[2] || m[1])));
    if (!best || d > best) best = d;
  }
  var re2 = /\b(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*\.?\s+(20\d\d)\b/gi;
  while ((m = re2.exec(text))) {
    var d2 = new Date(Date.UTC(+m[2], MONTHS[m[1].toLowerCase()] + 1, 0));
    if (!best || d2 > best) best = d2;
  }
  return best;
}
return items.map(function (it) {
  var last = latestDate(it.why_now);
  var stale = !!(last && last < now);
  var name = [it.first_name, it.last_name].filter(Boolean).join(' ').trim();
  var company = String(it.company || '').replace(/\(.*?\)/g, ' ').replace(/"/g, '').replace(/\s+/g, ' ').trim();
  var searchable = it.company_relevant && it.relationship_state === 'COLD' && !it.gmail_since && !it.duplicate_open
    && String(it.first_name || '').length >= 2 && String(it.last_name || '').length >= 2;
  return { json: Object.assign({}, it, { why_now_stale: stale, why_now_latest: last ? last.toISOString().slice(0, 10) : null,
    has_name: searchable, q: searchable ? 'site:linkedin.com/in "' + name + '" "' + company + '"' : '' }) };
});
