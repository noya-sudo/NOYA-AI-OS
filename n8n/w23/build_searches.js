// Email-first research plan per company (Adam, 8 Oct 2026). Search finds the official pages and the indexed addresses;
// the pages themselves are read in the next steps. 2-4 searches a company:
//  S1 the company's own contact / team / partnerships / press / media-kit pages (plain OR list: a grouped query returns nothing)
//  S2 addresses on the company's domain printed anywhere (press releases, speaker bios, PDFs, interviews, exhibitor directories)
//  S3 the named decision makers we already know, with an address on the domain
//  S4 the company's Instagram profile (bios often carry the business email)
var items = ($input.first().json.items) || [];
var out = [];
items.forEach(function (c, i) {
  var nm = String(c.company || '').replace(/\(.*?\)/g, ' ').replace(/"/g, '').replace(/\s+/g, ' ').trim();
  var d = c.domain && !/(instagram|linkedin|facebook|wixsite|squarespace|linktr)/.test(c.domain) ? c.domain : '';
  if (d) {
    out.push({ json: { ci: i, kind: 'SITE', q: 'site:' + d + ' contact OR team OR about OR press OR partnerships OR sales' } });
    out.push({ json: { ci: i, kind: 'INDEXED', q: '"' + d + '" email press OR partnerships OR sales OR events OR contact -jobs -careers' } });
    var ppl = (c.people || []).filter(function (p) { return p.first_name && p.last_name && !p.email; }).slice(0, 2);
    if (ppl.length) out.push({ json: { ci: i, kind: 'PERSON', q: '(' + ppl.map(function (p) { return '"' + p.first_name + ' ' + p.last_name + '"'; }).join(' OR ') + ') "@' + d + '"' } });
  } else {
    out.push({ json: { ci: i, kind: 'SITE', q: '"' + nm + '" contact email' } });
    out.push({ json: { ci: i, kind: 'INDEXED', q: '"' + nm + '" (partnerships OR sales OR press OR events) email' } });
  }
  var ig = String(c.instagram || '').replace(/^@/, '').replace(/^https?:\/\/(www\.)?instagram\.com\//, '').replace(/[/?#].*$/, '').trim();
  if (ig) out.push({ json: { ci: i, kind: 'INSTAGRAM', q: 'site:instagram.com "' + ig + '"' } });
});
return out;
