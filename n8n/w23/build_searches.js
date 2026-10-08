// Email-first research plan per company (Adam, 8 Oct 2026 — final amendment: exhaust public email research before LinkedIn).
// The pages themselves are read in the next steps. Up to 7 searches a company:
//  SITE       the company's own contact / team / partnerships / press / sales pages (plain OR list: a grouped query returns nothing)
//  INDEXED    addresses on the company's domain printed anywhere (press releases, speaker bios, interviews, exhibitor directories)
//  DOCS       documents on the domain: PDFs, media kits, press kits, brochures, fact sheets
//  PERSON     the named decision makers we already know, with an address on the domain
//  PEOPLE_WEB the top decision maker anywhere: speaker and conference pages, interviews, campaign credits, award listings
//  DIRECTORY  the sector's directories and trade press (wedding directories, travel trade, agency trade press, hotel press)
//  INSTAGRAM  the company's Instagram profile (business bios often carry the email)
// Only addresses printed on the company's own domain (or in its own Instagram bio) are ever kept; nothing is guessed.
var DIR = {
  WEDDINGS: '(site:hitched.co.uk OR site:bridebook.com OR site:weddingwire.com OR site:theknot.com OR site:junebugweddings.com OR site:rockmywedding.co.uk OR site:stylemepretty.com)',
  TRAVEL: '(site:virtuoso.com OR site:travelweekly.co.uk OR site:ttgmedia.com OR site:luxurytraveladvisor.com OR site:travelagentcentral.com OR site:breakingtravelnews.com)',
  BRANDS: '(site:campaignlive.co.uk OR site:thedrum.com OR site:prweek.com OR site:businessoffashion.com OR site:adage.com OR site:shots.net OR site:lbbonline.com)',
  HOTEL: '(site:hospitalitynet.org OR site:hoteliermiddleeast.com OR site:hotelmanagement.net OR site:travelweekly.com OR site:breakingtravelnews.com)',
  VILLA: '(site:hospitalitynet.org OR site:travelweekly.co.uk OR site:ttgmedia.com OR site:luxurytraveladvisor.com)',
  CLUB: '(site:prnewswire.com OR site:luxurytraveladvisor.com OR site:spearswms.com)',
  MEDIA: '(site:pressgazette.co.uk OR site:thedrum.com OR site:campaignlive.co.uk)',
  CORPORATE: '(site:prnewswire.com OR site:businesswire.com OR site:globenewswire.com)'
};
var items = ($input.first().json.items) || [];
var out = [];
items.forEach(function (c, i) {
  var nm = String(c.company || '').replace(/\(.*?\)/g, ' ').replace(/"/g, '').replace(/\s+/g, ' ').trim();
  var d = c.domain && !/(instagram|linkedin|facebook|wixsite|squarespace|linktr)/.test(c.domain) ? c.domain : '';
  var ppl = (c.people || []).filter(function (p) { return p.first_name && p.last_name && !p.email; });
  if (d) {
    out.push({ json: { ci: i, kind: 'SITE', q: 'site:' + d + ' contact OR team OR about OR press OR partnerships OR sales' } });
    out.push({ json: { ci: i, kind: 'INDEXED', q: '"' + d + '" email press OR partnerships OR sales OR events OR contact -jobs -careers' } });
    out.push({ json: { ci: i, kind: 'DOCS', q: 'site:' + d + ' filetype:pdf OR "media kit" OR "press kit" OR brochure OR "fact sheet" email' } });
    if (ppl.length) out.push({ json: { ci: i, kind: 'PERSON', q: '(' + ppl.slice(0, 2).map(function (p) { return '"' + p.first_name + ' ' + p.last_name + '"'; }).join(' OR ') + ') "@' + d + '"' } });
  } else {
    out.push({ json: { ci: i, kind: 'SITE', q: '"' + nm + '" contact email' } });
    out.push({ json: { ci: i, kind: 'INDEXED', q: '"' + nm + '" (partnerships OR sales OR press OR events) email' } });
  }
  if (ppl.length) out.push({ json: { ci: i, kind: 'PEOPLE_WEB', q: '"' + ppl[0].first_name + ' ' + ppl[0].last_name + '" "' + nm + '" email OR contact OR speaker OR interview' } });
  if (DIR[c.segment]) out.push({ json: { ci: i, kind: 'DIRECTORY', q: '"' + nm + '" ' + DIR[c.segment] + ' email OR contact' } });
  var ig = String(c.instagram || '').replace(/^@/, '').replace(/^https?:\/\/(www\.)?instagram\.com\//, '').replace(/[/?#].*$/, '').trim();
  if (ig) out.push({ json: { ci: i, kind: 'INSTAGRAM', q: 'site:instagram.com "' + ig + '"' } });
});
return out;
