// Deterministic evidence: every address printed on the pages read and in the search snippets, with the text around it.
// Handles mailto links, HTML entities, Cloudflare-protected addresses and "[at]" spelling. Nothing is constructed: an address
// is kept only if it is written in the evidence. Addresses must sit on the company's domain, except one printed in the
// company's own Instagram bio. Then one Flash-Lite request per company to say who owns each address and who is on the team pages.
// Property scope: when the company is one property of a chain domain (Kempinski Nile Hotel on kempinski.com), an address is kept
// only if its page, its local part or the text around it names the property, so another hotel's inbox is never saved.
var queue = $('Email Gap Queue').first().json.items || [];
var plan = $('Plan Pages').all(0);
var pages = $input.all();
var qs = $('Build Searches').all();
var serp = $('Serper Search').all();
var ASSET = /\.(png|jpe?g|gif|webp|svg|css|js|ico|woff2?|mp4|pdf)$/i;
// email-format and data-broker sites publish guessed patterns (john.doe@, jdoe@), never a real published address
var BROKER = /(rocketreach|prospeo|datanyze|aeroleads|zoominfo|signalhire|lusha|contactout|apollo\.io|hunter\.io|emailformat|email-format|leadiq|snov\.io|clearbit|voilanorbert|anymailfinder|skrapp|getprospect|uplead|adapt\.io|kaspr|seamless\.ai|salesintel|theorg\.com|crunchbase|dnb\.com|cbinsights|pitchbook|unifers|contactlevel|leadgenius|peoplefinder|emailsherlock|findymail|getemail)/i;
// people-search pages that sell contact details read like this even when the host is new to us
var BROKER_TEXT = /(reveal (contact|email|phone)|email (&|and) phone number|email format|work emails? found|emails? found at|get (verified )?(email|contact) (address|details)|\*{4,})/i;
var PLACEHOLDER = /^((john|jane|j)[._-]?(doe|smith)|john|jane|doe|smith|first|last|firstname|lastname|first[._-]last|flast|firstl|name|yourname|youremail|email|user|username|someone|test)$/;
function host(u) { return String(u || '').toLowerCase().replace(/^https?:\/\//, '').replace(/^www\./, '').replace(/[/?#].*$/, ''); }
function regDomain(h) { var a = String(h || '').toLowerCase().split('.'); if (a.length < 2) return h; var sld = a[a.length - 2];
  if (a.length >= 3 && a[a.length - 1].length === 2 && /^(co|com|org|net|gov|ac|edu|ltd|plc|me)$/.test(sld)) return a.slice(-3).join('.'); return a.slice(-2).join('.'); }
var STOP = ' the and hotel hotels resort resorts group groups club clubs collection collections luxury travel travels residence residences inn inns spa members member global international company worldwide world lifestyle hospitality management house villa villas beach grand palace private boutique apartments suites island city royal del des les for mgmt ltd llc inc plc limited official ';
function nameTokens(n) { return String(n || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, ' ').trim().split(' ').filter(function (t) { return t.length >= 3 && STOP.indexOf(' ' + t + ' ') < 0; }); }
// words of the company name that the domain does not carry (the property within a chain domain)
function scopeTokens(name, d) { var lbl = String(d || '').split('.')[0].replace(/[^a-z0-9]/g, '');
  return nameTokens(name).filter(function (t) { return !lbl || lbl.indexOf(t) < 0; }); }
function words(s) { return ' ' + String(s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, ' ') + ' '; }
var KEYWORD = /^(info|hello|hi|contact|contactus|enquire|inquire|global|international|intl|emea|apac|mena|gcc|americas|europe|asia|africa|uk|us|usa|uae|enquiries|enquiry|inquiries|inquiry|reservations?|res|bookings?|book|stay|welcome|office|reception|frontdesk|front|desk|sales|partners?|partnerships?|press|media|events?|weddings?|concierge|marketing|sponsorships?|collab\w*|commercial|groups?|pr|guest|relations|guestrelations|leisure|mice|meetings|business|bd|comms|communications|brands?|trade|team|admin|general|mail|hotel|ask|experiences?)$/;
function inScope(scope, e, ctx, url) {
  if (!scope.length) return true;
  var lp = e.split('@')[0], toks = lp.split(/[._-]+/).filter(Boolean);
  // a department / general inbox qualified with another property's name (info.adlon@ on the Nile page) is that property's
  if (cls(e) !== 'PERSONAL' && toks.some(function (t) { return !KEYWORD.test(t) && scope.indexOf(t) < 0; })) return false;
  var w = words(ctx) + words(lp) + words(url);
  return scope.some(function (t) { return w.indexOf(' ' + t + ' ') >= 0; });
}
// an inbox qualified with a sub-unit (fb.reservations.tswq@, mandarina.concierge@, info-retail-rny@) serves one outlet or
// property, not the company: kept only when the qualifier is part of the company's own name
function subUnit(e, name) {
  var toks = e.split('@')[0].split(/[._-]+/).filter(Boolean); if (toks.length < 2 || cls(e) === 'PERSONAL') return false;
  var nm = words(name);
  return toks.some(function (t) { return !KEYWORD.test(t) && nm.indexOf(' ' + t + ' ') < 0; });
}
function cls(e) {
  var lp = String(e).split('@')[0].toLowerCase();
  if (/(career|jobs?$|^jobs|recruit|^hr$|^hr\.|^joinus$|^join$|^apply$|privacy|gdpr|^dpo$|dataprotection|noreply|no-reply|donotreply|do-not-reply|support|customer|helpdesk|^help$|returns|orders|billing|invoice|^accounts?$|accounts?payable|finance|payroll|legal|abuse|webmaster|postmaster|security|unsubscribe|newsletter|subscribe|^test$)/.test(lp)) return 'EXCLUDED';
  if (/^(partnerships?|partners?|collab\w*|sales|commercial|business|bd|newbusiness|new\.business|marketing|brand|brands|pr|press|media|communications|comms|events?|weddings?|groups?|meetings|mice|concierge|sponsorships?|guestrelations|guest\.relations|experiences?|leisure|leisuresales|leisure\.sales|trade|tradesales|travelagents|agents|b2b|influencers?|creators?|production)$/.test(lp)
      || /(^|[._-])(partner\w*|sales|press|media|events?|weddings?|concierge|marketing|sponsor\w*|collab\w*|commercial|groups?|pr)([._-]|$)/.test(lp)) return 'DEPARTMENT';
  if (/^(info|hello|hi|hey|contact|contactus|contact\.us|enquire|enquiries|enquiry|inquire|inquiries|inquiry|reservations?|reserve|res|bookings?|book|office|team|admin|general|mail|studio|stay|hotel|frontdesk|front\.office|reception|welcome|ask|bonjour|ciao|hola|global|international|intl|headoffice|hq)$/.test(lp)
      || /(^|[._-])(info|hello|contact|enquire|enquiries|enquiry|inquire|inquiries|inquiry|reservations?|bookings?|stay|welcome|office|reception|frontdesk)([._-]|$)/.test(lp)) return 'GENERAL';
  return 'PERSONAL';
}
function decodeEntities(s) {
  return s.replace(/&#(\d+);/g, function (m, n) { return String.fromCharCode(+n); }).replace(/&#x([0-9a-f]+);/gi, function (m, h) { return String.fromCharCode(parseInt(h, 16)); })
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>');
}
function cf(hex) { try { var k = parseInt(hex.substr(0, 2), 16), o = ''; for (var i = 2; i < hex.length; i += 2) o += String.fromCharCode(parseInt(hex.substr(i, 2), 16) ^ k); return o; } catch (e) { return ''; } }
function toText(html) {
  var h = String(html || '');
  h = h.replace(/<script[\s\S]*?<\/script>/gi, ' ').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<noscript[\s\S]*?<\/noscript>/gi, ' ').replace(/<svg[\s\S]*?<\/svg>/gi, ' ');
  h = h.replace(/data-cfemail="([0-9a-f]+)"[^>]*>/gi, function (m, hex) { return '> ' + cf(hex) + ' '; })
       .replace(/\/cdn-cgi\/l\/email-protection#([0-9a-f]+)/gi, function (m, hex) { return 'mailto:' + cf(hex); });
  // keep the address of every mailto link in the visible text, next to its label
  h = h.replace(/<a[^>]+href=["']mailto:([^"'?]+)[^"']*["'][^>]*>/gi, function (m, e) { return ' ' + decodeURIComponent(e) + ' '; });
  h = h.replace(/<(br|p|div|li|tr|h[1-6]|section|article|footer|header)[^>]*>/gi, '\n').replace(/<[^>]+>/g, ' ');
  return decodeEntities(h).replace(/[ \t\r\f\v]+/g, ' ').replace(/\n\s*/g, '\n').trim();
}
function srcType(url, d) {
  var u = String(url || '').toLowerCase(); var h = host(u);
  if (/linkedin\.com/.test(h)) return 'LINKEDIN';
  if (/instagram\.com/.test(h)) return 'INSTAGRAM';
  if (/(media-kit|press-kit|presskit|\.pdf)/.test(u)) return 'MEDIA_KIT';
  var own = d && (h === d || h.slice(-(d.length + 1)) === '.' + d);
  if (own) return /(press|media|news)/.test(u) ? 'PRESS' : (/partner/.test(u) ? 'PARTNERSHIP_PAGE' : 'OFFICIAL_SITE');
  if (/(speaker|summit|conference|forum)/.test(u)) return 'SPEAKER_PAGE';
  if (/(interview|podcast|magazine|news|press|journal)/.test(u)) return 'INTERVIEW';
  return 'SEARCH_RESULT';
}
// the official domain: the trusted one on file, else the one Plan Pages found in the search results
var disc = {};
plan.forEach(function (p) { if (p.json && p.json.dom) disc[p.json.ci] = p.json.dom; });
function domOf(ci, c) { return c.domain || disc[ci] || ''; }
var byCo = {};
function co(ci) { return byCo[ci] || (byCo[ci] = { emails: {}, docs: [], fetched: 0, read: 0, searches: 0, scoped: 0, kinds: {}, urls: [] }); }
function harvest(ci, c, text, url, viaInstagram) {
  var b = co(ci); var d = domOf(ci, c); var t = String(text || ''); var scope = viaInstagram ? [] : scopeTokens(c.company, d);
  var found = t.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,24}/gi) || [];
  // "name [at] domain [dot] com" spellings, only on the company's own domain
  t.replace(/([a-z0-9._-]+)\s*(?:\[at\]|\(at\))\s*([a-z0-9-]+(?:\s*(?:\[dot\]|\(dot\)|\.)\s*[a-z0-9-]+)+)/gi, function (m, a, b2) {
    var e = (a + '@' + b2.replace(/\s*(?:\[dot\]|\(dot\))\s*/gi, '.').replace(/\s+/g, '')).toLowerCase(); if (d && regDomain(e.split('@')[1]) === d) found.push(e); return m; });
  if (BROKER.test(host(url)) || (!viaInstagram && BROKER_TEXT.test(t.slice(0, 600)) && !(d && regDomain(host(url)) === d))) return;
  found.forEach(function (raw) {
    var e = raw.toLowerCase().replace(/^[._-]+|[._-]+$/g, '');
    if (ASSET.test(e) || /(example|sentry|wixpress|domain\.com|email\.com|yourname)/.test(e) || PLACEHOLDER.test(e.split('@')[0])) return;
    var ed = regDomain(e.split('@')[1]);
    var igBio = viaInstagram && !!c.instagram;
    if (!(d && ed === d) && !igBio) return;
    if (cls(e) === 'EXCLUDED') return;
    var at = t.toLowerCase().indexOf(e);
    var ctx = at >= 0 ? t.slice(Math.max(0, at - 220), at + e.length + 220).replace(/\s+/g, ' ') : '';
    if (!inScope(scope, e, ctx, url) || subUnit(e, c.company)) { b.scoped++; return; }
    var cur = b.emails[e];
    if (!cur) b.emails[e] = { email: e, url: url, type: viaInstagram ? 'INSTAGRAM' : srcType(url, d), ctx: ctx, cls: cls(e) };
    else if (ctx.length > cur.ctx.length && srcType(url, d) === 'OFFICIAL_SITE') { cur.ctx = ctx; cur.url = url; cur.type = srcType(url, d); }
  });
}
// pages read
pages.forEach(function (p, i) {
  var meta = plan[i] && plan[i].json; if (!meta || meta.skip) return;
  var c = queue[meta.ci]; if (!c) return;
  var b = co(meta.ci); b.fetched++;
  var j = p.json || {};
  var body = typeof j.body === 'string' ? j.body : (typeof j.data === 'string' ? j.data : '');
  var ok = body && (!j.statusCode || j.statusCode < 400);
  if (!ok) return;
  b.read++; b.urls.push(meta.url);
  var text = toText(body);
  harvest(meta.ci, c, text, meta.url, false);
  var sc = scopeTokens(c.company, domOf(meta.ci, c));
  // team / press pages of a chain domain count only when they are about this property
  if ((/(team|leadership|people|management|who-we-are|our-story|about|press|media|contact|partner|founder)/i.test(meta.url) || b.docs.length === 0)
      && (!sc.length || sc.some(function (t) { return (words(meta.url) + words(text.slice(0, 4000))).indexOf(' ' + t + ' ') >= 0; }))) {
    var k = text.search(/(founder|director|manager|head of|chief|partner|owner|ceo|president)/i);
    b.docs.push({ url: meta.url, type: srcType(meta.url, domOf(meta.ci, c)), text: text.slice(Math.max(0, k - 300), Math.max(0, k - 300) + 3500) });
  }
});
// search snippets (indexed addresses, Instagram bios, speaker pages, press releases)
serp.forEach(function (r, i) {
  var meta = qs[i] && qs[i].json; if (!meta) return;
  var c = queue[meta.ci]; if (!c) return;
  co(meta.ci).searches++; co(meta.ci).kinds[meta.kind] = 1;
  ((r.json && r.json.organic) || []).slice(0, 10).forEach(function (o) {
    var ig = String(c.instagram || '').replace(/^@/, '').replace(/^https?:\/\/(www\.)?instagram\.com\//, '').replace(/[/?#].*$/, '').toLowerCase();
    var viaIg = meta.kind === 'INSTAGRAM' && !!ig && String(o.link || '').toLowerCase().indexOf('instagram.com/' + ig) >= 0;
    harvest(meta.ci, c, (o.title || '') + ' — ' + (o.snippet || ''), o.link, viaIg);
  });
});
var SYS = 'You read public evidence about one company and attribute its published email addresses. Use ONLY the evidence given. ' +
  'For each email id: give owner_first, owner_last and owner_role ONLY when the text around that address names the person who uses it ' +
  '(for example "Jane Smith, Director of Sales, jane.smith@..."); otherwise leave them empty and give the department the address serves ' +
  '(partnerships, sales, marketing, PR, events, weddings, concierge, reservations, general, other). Separately list up to 6 people from the PAGE excerpts who ' +
  'currently hold one of the priority roles, copying names and roles exactly as written, with the page number. Never invent or complete an email, name or role. JSON only.';
var out = [];
queue.forEach(function (c, ci) {
  var b = co(ci);
  var emails = Object.keys(b.emails).map(function (k) { return b.emails[k]; });
  // what this pass covered (version 2 = the full email-first checklist): the evidence behind any later LinkedIn fallback
  var research = { searches: b.searches, pages_fetched: b.fetched, pages_read: b.read, emails_seen: emails.length, out_of_scope: b.scoped,
    checked: { version: 2, kinds: Object.keys(b.kinds), pages: b.urls.slice(0, 8),
      people: (c.people || []).filter(function (p) { return p.first_name && p.last_name && !p.email; }).slice(0, 2).map(function (p) { return p.first_name + ' ' + p.last_name; }) } };
  var found = c.domain ? '' : (disc[ci] || '');
  if (!emails.length && !b.docs.length) { out.push({ json: { company: c, found_domain: found, emails: [], docs: [], research: research, has_evidence: false } }); return; }
  var prompt = 'Company: ' + c.company + (domOf(ci, c) ? ' (' + domOf(ci, c) + ')' : '') + (c.country ? ', ' + c.country : '') + (c.company_type ? ', ' + c.company_type : '') +
    '\nWhy NOYA wants them: ' + (c.model || '') + (c.angle ? ' — ' + c.angle : '') +
    '\nPriority roles (best first): ' + (c.role_focus || []).join(', ') +
    '\nAlready known people: ' + JSON.stringify((c.people || []).map(function (p) { return [p.first_name, p.last_name, p.position].join(' | '); })) +
    '\n\nEMAILS:\n' + emails.map(function (e, j) { return '[E' + (j + 1) + '] ' + e.email + ' | ' + e.url + ' | ' + e.ctx; }).join('\n') +
    '\n\nPAGES:\n' + b.docs.slice(0, 3).map(function (d, j) { return '[P' + (j + 1) + '] ' + d.url + ' :: ' + d.text; }).join('\n\n');
  var request = {
    systemInstruction: { parts: [{ text: SYS }] },
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: { temperature: 0, maxOutputTokens: 1200, responseMimeType: 'application/json',
      responseSchema: { type: 'OBJECT', properties: {
        emails: { type: 'ARRAY', items: { type: 'OBJECT', properties: { id: { type: 'INTEGER' }, owner_first: { type: 'STRING' }, owner_last: { type: 'STRING' },
          owner_role: { type: 'STRING' }, department: { type: 'STRING' } }, required: ['id'] } },
        people: { type: 'ARRAY', items: { type: 'OBJECT', properties: { first_name: { type: 'STRING' }, last_name: { type: 'STRING' }, position: { type: 'STRING' },
          page: { type: 'INTEGER' } }, required: ['first_name', 'last_name', 'page'] } }
      }, required: ['emails'] } }
  };
  out.push({ json: { company: c, found_domain: found, emails: emails, docs: b.docs.slice(0, 3), research: research, has_evidence: true, request: request } });
});
return out;
