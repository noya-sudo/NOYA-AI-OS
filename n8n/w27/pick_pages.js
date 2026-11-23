// W27 step 2: from each company's homepage, choose up to MAX commercial pages on its own site (contact, partnerships, trade,
// events, press, management, team). Never support, careers, legal, login or shop pages. When nothing qualifies (or the
// homepage could not be read), the homepage is fetched once more so the outcome is still recorded.
var MAX = 4;
var src = $('Next Batch').all();
var PRI = [/contact|enquir|inquir|get-in-touch/i, /partner|collaborat|work-with-us|business-development|new-business|brand-partner|affiliat/i,
  /vendor|supplier|trade|travel-advisor|advisors?|agents?|b2b|wholesale/i, /events?|groups|private-events|weddings|corporate|membership|experiences/i,
  /press|media|management|talent|roster|representation/i, /team|about|leadership|people|founders?|who-we-are/i];
var SKIP = /(privacy|cookie|terms|legal|careers?|jobs|vacanc|login|log-in|signin|sign-in|account|cart|checkout|basket|returns?|shipping|delivery|faq|help|support|\/shop\/|\/product|\/blog\/.|\/news\/.|\.(pdf|jpe?g|png|gif|svg|webp|zip|mp4)(\?|$))/i;
function hostOf(u) { var m = String(u || '').match(/^https?:\/\/([^\/?#:]+)/i); return m ? m[1].toLowerCase().replace(/^www\./, '') : ''; }
function regdom(h) {
  var p = h.split('.'); if (p.length <= 2) return h;
  if (p[p.length - 1].length === 2 && /^(co|com|org|net|ac|gov|edu)$/.test(p[p.length - 2])) return p.slice(-3).join('.');
  return p.slice(-2).join('.');
}
function originOf(u) { var m = String(u || '').match(/^(https?:\/\/[^\/?#]+)/i); return m ? m[1] : ''; }
function abs(href, origin) {
  href = String(href || '').trim().replace(/&amp;/g, '&');
  if (!href || /^(mailto|tel|javascript|data):/i.test(href) || href.charAt(0) === '#') return '';
  if (/^https?:\/\//i.test(href)) return href;
  if (href.indexOf('//') === 0) return 'https:' + href;
  if (href.charAt(0) === '/') return origin + href;
  return origin + '/' + href.replace(/^\.\//, '');
}
var out = [];
$input.all().forEach(function (x, i) {
  var c = (src[i] || {}).json || {};
  if (!c.company_id) return;
  var html = typeof x.json.data === 'string' ? x.json.data : '';
  var origin = originOf(c.website), dom = regdom(hostOf(c.website));
  var seen = {}, cands = [], re = /<a\b[^>]*?href\s*=\s*["']([^"'#]+)[^"']*["']/gi, m;
  while ((m = re.exec(html)) && cands.length < 400) {
    var u = abs(m[1], origin); if (!u) continue;
    var h = hostOf(u); if (!h || regdom(h) !== dom) continue;
    var path = (u.replace(/^https?:\/\/[^\/]+/i, '').split('?')[0].replace(/\/+$/, '')) || '/';
    if (path === '/' || SKIP.test(path)) continue;
    var key = h + path.toLowerCase(); if (seen[key]) continue; seen[key] = 1;
    var pr = -1;
    for (var k = 0; k < PRI.length; k++) { if (PRI[k].test(path)) { pr = k; break; } }
    if (pr < 0) continue;
    cands.push({ url: u.split('#')[0], pr: pr, depth: path.split('/').length });
  }
  cands.sort(function (a, b) { return a.pr - b.pr || a.depth - b.depth; });
  var pick = cands.slice(0, MAX);
  if (!pick.length) pick = [{ url: c.website, retry: true }];
  pick.forEach(function (p) { out.push({ json: { company_id: c.company_id, url: p.url, retry: !!p.retry } }); });
});
return out;
