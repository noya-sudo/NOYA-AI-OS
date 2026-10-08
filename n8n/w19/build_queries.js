// Up to three searches per company: named people on LinkedIn, the Instagram account (bios often carry the contact route),
// and emails published on the company's own domain. Role terms follow the company's vertical (Adam's priority roles per
// vertical, from role_focus() in the database: hotel GM / sales / commercial, villa founder / head of sales, travel trade and
// B2B partnerships, wedding founder / lead planner, brand partnerships / experiential / production, corporate travel / EA / events);
// the lane list is the fallback when the queue carries no segment.
var items = ($input.first().json.items) || [];
var ROLE = {
  PARTNERSHIPS: '"general manager" OR "director of sales" OR "commercial director" OR partnerships OR founder OR owner OR "managing director"',
  WEDDINGS: 'founder OR "creative director" OR "lead planner" OR owner OR partner',
  BRANDS: '"head of brand" OR "marketing director" OR PR OR partnerships OR experiential OR "influencer marketing" OR "creative producer" OR founder OR producer OR host',
  TRAVEL_PRIVATE: 'founder OR "managing director" OR partnerships OR "head of" OR director',
  CORPORATE: '"travel manager" OR "executive assistant" OR "head of events" OR "commercial director" OR partnerships',
  SPORTS_PRIVATE: '"commercial director" OR partnerships OR "player care" OR "head of" OR agent',
  EGYPT_EVENTS: 'founder OR director OR partnerships OR "head of"'
};
var out = [];
items.forEach(function (c, i) {
  var nm = String(c.company || '').replace(/\(.*?\)/g, ' ').replace(/"/g, '').replace(/\s+/g, ' ').trim();
  var name = '"' + nm + '"';
  var focus = (c.role_focus || []).slice(0, 7).map(function (r) { return /\s/.test(r) ? '"' + r + '"' : r; }).join(' OR ');
  out.push({ json: { ci: i, kind: 'LINKEDIN', q: 'site:linkedin.com/in ' + name + ' (' + (focus || ROLE[c.lane] || ROLE.TRAVEL_PRIVATE) + ')' } });
  // Search only for what is missing (Adam, 7 Oct: efficient searches): no Instagram search when the account is on file,
  // no email search when the company already has a published email or inbox.
  if (!c.instagram) out.push({ json: { ci: i, kind: 'INSTAGRAM', q: 'site:instagram.com ' + name } });
  if (!c.has_email) out.push({ json: { ci: i, kind: 'EMAIL', q: c.domain ? name + ' "@' + c.domain + '"' : name + ' email (partnerships OR sales OR press OR contact)' } });
});
return out;
