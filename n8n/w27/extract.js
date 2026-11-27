// W27 step 4: extract the public routes each company prints on its own site: emails (mailto, text, Cloudflare-protected),
// commercial web forms (fields, required fields, length limits, captcha, upload, login) and the company's Instagram and
// LinkedIn company page. Nothing is guessed or inferred: route_research_ingest keeps only same-domain emails, drops support,
// careers, privacy and similar inboxes, attaches a personal address only to a known person whose name it spells, and rejects
// non-commercial or login-only forms.
var comps = $('Next Batch').all();
// Pages arrive trimmed (head + tail, about 500 KB) by the Trim nodes: whole multi-megabyte retail pages pushed this node past its
// time and memory limits (27 Nov), and the same batch then failed on every run because nothing was saved.
var homes = $('Trim Homepage').all();
var plan = $('Pick Commercial Pages').all();
var pages = $input.all();
// Time budget: stop reading at 35 s so the node always returns; an account not read in time is saved as FETCH_FAILED (TIME_BUDGET),
// which moves the next batch on instead of retrying the same heavy sites forever.
var T0 = Date.now(), BUDGET = 35000;
function decodeCf(hex) {
  try { var k = parseInt(hex.substr(0, 2), 16), s = ''; for (var i = 2; i < hex.length; i += 2) s += String.fromCharCode(parseInt(hex.substr(i, 2), 16) ^ k); return s; }
  catch (e) { return ''; }
}
// Inline base64 (images, fonts) and other very long tokens make the email regex quadratic: one 400 KB data URI pushes the
// Code node past its 60-second limit, and the same batch then fails on every run. Strip them and cap the page first.
function clean(html) {
  return String(html || '')
    .replace(/data:[a-z0-9.+\/-]+;base64,[A-Za-z0-9+\/=]+/gi, ' ')
    .replace(/[A-Za-z0-9+\/=_%.-]{300,}/g, ' ')
    .slice(0, 600000)
    .replace(/data-cfemail="([0-9a-f]+)"/gi, function (m, h) { return '>' + decodeCf(h) + '<'; })
    .replace(/&#(\d+);/g, function (m, d) { return String.fromCharCode(+d); })
    .replace(/&#x([0-9a-f]+);/gi, function (m, h) { return String.fromCharCode(parseInt(h, 16)); })
    .replace(/&amp;/g, '&').replace(/&nbsp;/g, ' ').replace(/%40/g, '@')
    .replace(/\s*(\[at\]|\(at\))\s*/gi, '@').replace(/\s*(\[dot\]|\(dot\))\s*/gi, '.');
}
function textOf(s) {
  return String(s || '').replace(/<script[\s\S]*?<\/script>/gi, ' ').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ')
    .replace(/&amp;/g, '&').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim();
}
function attr(s, name) {
  var m = new RegExp('\\b' + name + '\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))', 'i').exec(s || '');
  return m ? (m[2] || m[3] || m[4] || '') : '';
}
var EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,24}/g;
var BADEXT = /\.(png|jpe?g|gif|svg|webp|css|js|ico|mp4|woff2?)$/i;
function emailsIn(html, page) {
  var out = [], seen = {};
  (clean(html).match(EMAIL) || []).forEach(function (e) {
    e = e.toLowerCase().replace(/^mailto:/, '').replace(/\.+$/, '');
    if (BADEXT.test(e) || seen[e] || e.length > 80 || /^[0-9a-f]{16,}@/.test(e)) return;
    seen[e] = 1; out.push({ email: e, page: page });
  });
  return out;
}
function formsIn(html, page) {
  var out = [], fm, h = String(html || '').slice(0, 800000);
  var title = textOf((h.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || ['', ''])[1]).slice(0, 120);
  var heads = (h.match(/<h[1-3][^>]*>[\s\S]*?<\/h[1-3]>/gi) || []).slice(0, 4).map(textOf).join(' | ').slice(0, 200);
  var labels = {}, lr = /<label\b([^>]*)>([\s\S]*?)<\/label>/gi, lm;
  while ((lm = lr.exec(h))) { var lf = attr(lm[1], 'for'); if (lf) labels[lf] = textOf(lm[2]).slice(0, 80); }
  var fr = /<form\b([^>]*)>([\s\S]*?)<\/form>/gi;
  while ((fm = fr.exec(h)) && out.length < 4) {
    var fa = fm[1], inner = fm[2], fields = [], im, file = false, pw = false, ir = /<(input|textarea|select)\b([^>]*)>/gi;
    while ((im = ir.exec(inner)) && fields.length < 30) {
      var tag = im[1].toLowerCase(), a = im[2];
      var type = tag === 'input' ? (attr(a, 'type') || 'text').toLowerCase() : tag;
      if (/^(hidden|submit|button|image|reset)$/.test(type)) continue;
      if (type === 'file') file = true;
      if (type === 'password') pw = true;
      var id = attr(a, 'id');
      var fld = { name: attr(a, 'name').slice(0, 80), type: type,
        required: /\brequired\b/i.test(a) || /aria-required\s*=\s*["']true/i.test(a),
        label: (labels[id] || attr(a, 'aria-label') || attr(a, 'placeholder') || '').slice(0, 80) };
      var ml = attr(a, 'maxlength'); if (/^\d+$/.test(ml)) fld.maxlength = ml;
      if (tag === 'select') {
        var close = inner.indexOf('</select>', im.index), body = close > 0 ? inner.slice(im.index, close) : '';
        fld.options = (body.match(/<option\b[^>]*>([\s\S]*?)<\/option>/gi) || []).map(textOf).filter(Boolean).slice(0, 15);
      }
      fields.push(fld);
    }
    var all = fa + inner;
    var captcha = /g-recaptcha|grecaptcha|recaptcha/i.test(all) ? 'RECAPTCHA' : /h-captcha|hcaptcha/i.test(all) ? 'HCAPTCHA'
      : /cf-turnstile|turnstile/i.test(all) ? 'TURNSTILE' : (/recaptcha|hcaptcha|turnstile/i.test(h) ? 'UNKNOWN' : 'NONE');
    out.push({ page: page, action: attr(fa, 'action').slice(0, 300),
      label: (title + ' | ' + heads + ' | ' + attr(fa, 'id') + ' ' + attr(fa, 'class') + ' ' + attr(fa, 'aria-label')).slice(0, 400),
      fields: fields, captcha: captcha, file: file, password: pw });
  }
  return out;
}
function social(html) {
  var h = String(html || '').slice(0, 800000), ig = '', li = '', m;
  var r1 = /https?:\/\/(?:www\.)?instagram\.com\/([A-Za-z0-9_.]{2,30})\/?(?=["'?#\s<])/gi;
  while ((m = r1.exec(h))) { if (!/^(p|reel|reels|explore|accounts|stories|tv|about|developer|legal)$/i.test(m[1])) { ig = 'https://www.instagram.com/' + m[1]; break; } }
  var r2 = /https?:\/\/(?:[a-z]{2,3}\.)?linkedin\.com\/company\/([A-Za-z0-9_%-]{2,80})/i.exec(h);
  if (r2) li = 'https://www.linkedin.com/company/' + r2[1];
  return { instagram: ig, linkedin: li };
}
// The company's own one-line description of itself (meta / og description on the homepage): a citable public fact.
function siteDesc(h) {
  var tags = String(h || '').match(/<meta\b[^>]*>/gi) || [];
  for (var i = 0; i < tags.length; i++) {
    var n = (attr(tags[i], 'name') || attr(tags[i], 'property')).toLowerCase(), c = attr(tags[i], 'content');
    if ((n === 'description' || n === 'og:description') && c.length >= 40)
      return c.replace(/&amp;/g, '&').replace(/&#0?39;|&apos;|&rsquo;/g, "'").replace(/&quot;|&ldquo;|&rdquo;/g, '"')
        .replace(/&nbsp;/g, ' ').replace(/&ndash;|&mdash;/g, '-').replace(/&[a-z]+;|&#[0-9]+;/gi, ' ').replace(/\s+/g, ' ').trim().slice(0, 500);
  }
  return '';
}
function errOf(j, dflt) { var e = j && j.error; return String((e && (e.message || e)) || dflt).slice(0, 160); }
var by = {};
comps.forEach(function (c, i) {
  var cj = c.json || {}; if (!cj.company_id) return;
  var hj = (homes[i] || {}).json || {};
  var html = typeof hj.data === 'string' ? hj.data : '';
  by[cj.company_id] = { company_id: cj.company_id, htmls: html ? [{ url: cj.website, html: html }] : [], errors: html ? [] : [errOf(hj, 'homepage not readable')] };
});
pages.forEach(function (x, i) {
  var p = (plan[i] || {}).json || {}, b = by[p.company_id]; if (!b) return;
  var html = typeof x.json.data === 'string' ? x.json.data : '';
  if (html) { if (!b.htmls.some(function (z) { return z.url === p.url; })) b.htmls.push({ url: p.url, html: html }); }
  else b.errors.push(errOf(x.json, 'page not readable'));
});
return Object.keys(by).map(function (k) {
  var b = by[k], emails = [], forms = [], ig = '', li = '', seenE = {}, home = b.htmls[0] || null, read = [], late = false;
  var desc = home && Date.now() - T0 <= BUDGET ? siteDesc(home.html) : '';
  b.htmls.forEach(function (z) {
    if (Date.now() - T0 > BUDGET) { late = true; return; }
    read.push(z.url);
    emailsIn(z.html, z.url).forEach(function (e) { if (!seenE[e.email]) { seenE[e.email] = 1; emails.push(e); } });
    formsIn(z.html, z.url).forEach(function (f) { forms.push(f); });
    var s = social(z.html); ig = ig || s.instagram; li = li || s.linkedin;
  });
  var err = read.length ? (late ? 'TIME_BUDGET: some pages not read in this run' : '')
    : (late ? 'TIME_BUDGET: the run ran out of time before this site was read' : (b.errors[0] || 'site not readable'));
  return { json: { p: { company_id: b.company_id, method: 'W27_SITE', pages: read,
    emails: emails.slice(0, 25), forms: forms.slice(0, 6), instagram: ig, linkedin: li, site_description: desc, site_description_url: desc && home ? home.url : '',
    error: err } } };
});
