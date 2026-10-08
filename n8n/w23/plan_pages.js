// Choose the official pages to read for each company (research order: contact, team / leadership, partnerships / sales,
// press / media, media kit, then the homepage). At most 7 pages a company; PDFs are not fetched (their indexed text
// still comes through the search snippets). With no team page in the results, /about is read too. Every company gets at least one item so none is dropped.
// A company without a trusted website (none on file, or one that does not carry its name, e.g. a news site saved by mistake)
// gets its official domain from the search results: the first result whose domain carries a distinctive word of the company
// name. Nothing is read or accepted from any other domain.
var queue = $('Email Gap Queue').first().json.items || [];
var qs = $('Build Searches').all();
var res = $input.all();
function host(u) { return String(u || '').toLowerCase().replace(/^https?:\/\//, '').replace(/^www\./, '').replace(/[/?#].*$/, ''); }
function onDomain(u, d) { var h = host(u); return !!d && (h === d || h.slice(-(d.length + 1)) === '.' + d); }
function regDomain(h) { var a = String(h || '').toLowerCase().split('.'); if (a.length < 2) return h; var sld = a[a.length - 2];
  if (a.length >= 3 && a[a.length - 1].length === 2 && /^(co|com|org|net|gov|ac|edu|ltd|plc|me)$/.test(sld)) return a.slice(-3).join('.'); return a.slice(-2).join('.'); }
// same rule as domain_trusted() in the database (the save re-checks it there)
var STOP = ' the and hotel hotels resort resorts group groups club clubs collection collections luxury travel travels residence residences inn inns spa members member global international company worldwide world lifestyle hospitality management house villa villas beach grand palace private boutique apartments suites island city royal del des les for mgmt ltd llc inc plc limited official ';
function nameTokens(n) { return String(n || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, ' ').trim().split(' ').filter(function (t) { return t.length >= 3 && STOP.indexOf(' ' + t + ' ') < 0; }); }
function domainTrusted(name, dom) {
  dom = String(dom || '').toLowerCase().replace(/^(https?:\/\/)?(www\.)?/, '');
  if (!dom || /(instagram|linkedin|facebook|wixsite|squarespace|linktr|booking|tripadvisor|wikipedia)/.test(dom)) return false;
  var lbl = dom.split('.')[0].replace(/[^a-z0-9]/g, ''); if (lbl.length < 2) return false;
  if (nameTokens(name).some(function (t) { return t.length >= 4 ? lbl.indexOf(t) >= 0 : lbl.indexOf(t) === 0; })) return true;
  var flat = String(name || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '');
  return lbl.length >= 5 && STOP.indexOf(' ' + lbl + ' ') < 0 && flat.indexOf(lbl) >= 0;
}
// a domain found in search must be (almost) entirely the company's name: kempinski.com for Kempinski Nile Hotel, never techsummits.io for Summits
function strongMatch(name, dom) {
  var rest = String(dom || '').toLowerCase().replace(/^(https?:\/\/)?(www\.)?/, '').split('.')[0].replace(/[^a-z0-9]/g, '');
  String(name || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, ' ').trim().split(' ')
    .filter(function (t) { return t.length >= 2; }).sort(function (x, y) { return y.length - x.length; }).forEach(function (t) { rest = rest.split(t).join(''); });
  return rest.length <= 3;
}
var BLOCK = /(unifers|contactlevel|prospeo|datanyze|aeroleads|hunter\.io|emailformat|email-format|leadiq|snov\.io|clearbit|voilanorbert|anymailfinder|skrapp|getprospect|uplead|adapt\.io|kaspr|seamless\.ai|booking|tripadvisor|expedia|hotels\.com|agoda|trivago|kayak|instagram|facebook|linkedin|wikipedia|youtube|twitter|x\.com|tiktok|pinterest|google|trip\.com|yelp|zoominfo|rocketreach|crunchbase|signalhire|apollo\.io|lusha|contactout|theorg)/;
function score(u, t) {
  var s = (String(u) + ' ' + String(t)).toLowerCase();
  if (/\.pdf($|\?)/.test(s) || /(career|jobs|vacanc|privacy|cookie|terms|login|cart|checkout|booking-engine|\/book\b|reservations?\/)/.test(s)) return -1;
  if (/contact/.test(s)) return 10;
  if (/(team|leadership|people|management|who-we-are|our-story|founder)/.test(s)) return 9;
  if (/(partner|trade|travel-agent|agents|sales|groups|meetings|events|weddings)/.test(s)) return 8;
  if (/(press|media|news|journal)/.test(s)) return 7;
  if (/(media-kit|press-kit|presskit)/.test(s)) return 7;
  if (/about/.test(s)) return 6;
  return 1;
}
var byCo = {};
res.forEach(function (r, i) {
  var meta = qs[i] && qs[i].json; if (!meta) return;
  (byCo[meta.ci] = byCo[meta.ci] || []).push({ kind: meta.kind, organic: ((r.json && r.json.organic) || []).slice(0, 10) });
});
// a one-word name (Summits, Locke) matches unrelated organisations: the result must also carry the company's sector, city or country
var SECTOR = /(hotel|resort|villa|residence|apartment|aparthotel|lodge|inn|travel|concierge|club|members|membership|hospitality|wedding|event|agency|collection|stay|suites|retreat)/i;
function contextOk(c, o) {
  if (nameTokens(c.company).length > 1) return true;
  var t = String((o.title || '') + ' ' + (o.snippet || '')).toLowerCase();
  return SECTOR.test(t) || [c.city, c.country].some(function (x) { return x && t.indexOf(String(x).toLowerCase()) >= 0; });
}
var out = [];
queue.forEach(function (c, ci) {
  var d = c.domain || '', found = '', origin = '';
  if (!d) (byCo[ci] || []).some(function (g) { return g.organic.some(function (o) {
    var h = host(o.link); if (!h || BLOCK.test(h) || !domainTrusted(c.company, regDomain(h)) || !strongMatch(c.company, regDomain(h)) || !contextOk(c, o)) return false;
    found = regDomain(h); origin = (String(o.link).match(/^https?:\/\/[^/?#]+/i) || [''])[0]; return true; }); });
  d = d || found;
  var picks = [];
  // official pages from every search (the domain-mention search often surfaces /contact-us, /about, /press)
  (byCo[ci] || []).forEach(function (g) {
    if (g.kind === 'INSTAGRAM') return;
    g.organic.forEach(function (o) { if (onDomain(o.link, d)) { var sc = score(o.link, o.title); if (sc > 0) picks.push({ url: o.link, sc: sc }); } });
  });
  picks.sort(function (a, b) { return b.sc - a.sc; });
  var urls = [];
  picks.forEach(function (p) { var u = p.url.split('#')[0]; if (urls.indexOf(u) < 0 && urls.length < 5) urls.push(u); });
  var home = c.website ? (/^https?:\/\//.test(c.website) ? c.website : 'https://' + c.website) : '';
  if (!onDomain(home, d)) home = origin;
  if (home && onDomain(home, d) && urls.indexOf(home) < 0) urls.push(home);
  // no contact page found by search: try the two conventional addresses
  if (home && onDomain(home, d) && !urls.some(function (u) { return /contact/i.test(u); })) {
    urls = urls.slice(0, 4); urls.push(home.replace(/\/+$/, '') + '/contact'); urls.push(home.replace(/\/+$/, '') + '/contact-us'); }
  if (home && onDomain(home, d) && !urls.some(function (u) { return /(team|about|people|leadership|founder|who-we-are|our-story)/i.test(u); }))
    urls.push(home.replace(/\/+$/, '') + '/about');
  urls = urls.slice(0, 7);
  if (!urls.length) out.push({ json: { ci: ci, url: '', skip: true, dom: found } });
  urls.forEach(function (u) { out.push({ json: { ci: ci, url: u, skip: false, dom: found } }); });
});
return out;
