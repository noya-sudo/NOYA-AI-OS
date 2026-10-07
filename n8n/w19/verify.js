// Anti-fabrication: keep only what appears verbatim in the cited search result. Names must be in the result text,
// the result must name the company (or its domain), emails must be printed in the result, handles must be in it too.
var src = $('Has Results?').all(0);
var STOPW = ('the and of hotel hotels resort resorts group collection collections travel events event company club clubs luxury ' +
  'villa villas residences residence suites spa international global limited ltd llc inc co uk london dubai').split(' ');
// Same scale as role_score() in Supabase: 0 = not a route in (HR, front office, F&B floor, spa, board seats).
function roleScore(p) {
  p = String(p || '').toLowerCase();
  if (!p.trim()) return 1;
  if (/\b(assistant to|executive assistant|pa to)\b/.test(p)) return 3;
  if (/\b(founder|co-founder|cofounder|owner|ceo|chief|president|managing director|managing partner|proprietor|chairman|chairwoman)\b/.test(p)) return 5;
  if (/\b(hr|human resources|recruit\w*|talent acquisition|front office|guest relations?|reception\w*|housekeeping|engineer\w*|maintenance|accountant|accounting|payroll|intern|trainee|student|waiter|waitress|chef|cook|barista|bartender|sommelier|kitchen|restaurant|brasserie|f&b|food (and|&) beverage|spa|therapist|security officer|driver|legal|counsel|compliance|procurement|purchasing|developer|software|night manager|cashier|butler|valet|board member|non-executive)\b/.test(p)) return 0;
  if (/\b(general manager|gm|partner|principal)\b/.test(p)) return 5;
  if (/\b(director|head|vp|vice president|svp|evp)\b/.test(p)) return 4;
  if (/\b(partnerships?|business development|commercial|experiential|influencer|brand|marketing|sales|pr|communications|press|events?|production|creative)\b/.test(p) && /\b(manager|lead)\b/.test(p)) return 4;
  if (/\b(manager|lead|producer|planner|designer|curator|editor|buyer)\b/.test(p)) return 3;
  return 2;
}
var MAX_PEOPLE = 4;
function norm(s) { return String(s || '').toLowerCase().replace(/[’]/g, "'").replace(/[^a-z0-9@._' -]/g, ' ').replace(/\s+/g, ' ').trim(); }
return $input.all().map(function (x, i) {
  var it = src[i].json, c = it.company, R = it.results || [];
  var r = x.json || {};
  var err = r.error ? (typeof r.error === 'string' ? r.error : (r.error.message || JSON.stringify(r.error))) : '';
  var u = r.usageMetadata || {};
  var text = ''; try { text = (r.candidates[0].content.parts || []).map(function (p) { return p.text || ''; }).join(''); } catch (e) { text = ''; }
  var o = {}; try { o = JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1)); } catch (e) { o = {}; }
  var ctoks = norm(String(c.company).replace(/\(.*?\)/g, ' ')).split(' ').filter(function (w) { return w.length >= 4 && STOPW.indexOf(w) < 0; });
  var fullName = norm(String(c.company).replace(/\(.*?\)/g, ' '));
  function namesCompany(blob) { return blob.indexOf(fullName) >= 0 || (c.domain && blob.indexOf(String(c.domain).toLowerCase()) >= 0) || ctoks.some(function (w) { return blob.indexOf(w) >= 0; }); }
  function srcType(link) {
    link = String(link || '').toLowerCase();
    var host = (link.match(/^https?:\/\/([^\/?#]+)/) || ['', ''])[1].replace(/^www\./, '');
    if (/linkedin\.com\/in\//.test(link)) return 'LINKEDIN';
    if (/instagram\.com/.test(link)) return 'INSTAGRAM';
    // official only when the page is on the company's own host (trustpilot.com/review/<domain> is not)
    if (c.domain && (host === String(c.domain).toLowerCase() || host.slice(-String(c.domain).length - 1) === '.' + String(c.domain).toLowerCase())) return /press|news|media/.test(link) ? 'PRESS' : (/partner/.test(link) ? 'PARTNERSHIP_PAGE' : 'OFFICIAL_SITE');
    if (/speaker|summit|conference|forum/.test(link)) return 'SPEAKER_PAGE';
    if (/interview|podcast|magazine|news|press|journal/.test(link)) return 'INTERVIEW';
    return 'SEARCH_RESULT';
  }
  var people = [], inboxes = [], rejected = 0, igCompany = '';
  (o.people || []).forEach(function (p) {
    var res = R[(p.result || 0) - 1]; if (!res) { rejected++; return; }
    var raw = (res.title + ' ' + res.snippet + ' ' + res.link), blob = norm(raw);
    var fn = norm(p.first_name), ln = norm(p.last_name);
    if (fn.length < 2 || ln.replace(/[^a-z]/g, '').length < 2 || blob.indexOf(fn) < 0 || blob.indexOf(ln) < 0 || !namesCompany(blob)) { rejected++; return; }
    var st = srcType(res.link);
    var pos = String(p.position || '').trim();
    if (pos && !norm(pos).split(' ').some(function (w) { return w.length >= 4 && blob.indexOf(w) >= 0; })) pos = '';
    if (roleScore(pos) === 0) { rejected++; return; }
    // A LinkedIn headline reads "Name - Role - Company". If the company appears only in the snippet (education,
    // past roles, memberships), the current employer is not proven: keep the person for review, never as confirmed.
    var employerConfirmed = st !== 'LINKEDIN' || namesCompany(norm(res.title));
    var email = String(p.email || '').trim().toLowerCase();
    if (email && raw.toLowerCase().indexOf(email) < 0) email = '';
    var ig = String(p.instagram || '').replace(/^@/, '').trim();
    if (ig && blob.indexOf(ig.toLowerCase()) < 0) ig = '';
    people.push({ first_name: String(p.first_name).trim(), last_name: String(p.last_name).trim(), position: pos,
      linkedin: st === 'LINKEDIN' ? String(res.link).split('?')[0] : '', email: email, instagram: ig, source_url: res.link, source_type: st,
      employer_confirmed: employerConfirmed, score: roleScore(pos) + (employerConfirmed ? 3 : 0) });
  });
  // the few people who can actually decide, not everyone the search turned up
  people.sort(function (a, b) { return b.score - a.score; });
  if (people.length > MAX_PEOPLE) { rejected += people.length - MAX_PEOPLE; people = people.slice(0, MAX_PEOPLE); }
  people.forEach(function (x) { delete x.score; });
  var ci = String(o.company_instagram || '').replace(/^@/, '').trim().toLowerCase();
  if (ci && R.some(function (res) { return /instagram\.com/i.test(res.link) && String(res.link).toLowerCase().indexOf('/' + ci) >= 0; })) igCompany = ci;
  (o.inboxes || []).forEach(function (b) {
    var res = R[(b.result || 0) - 1]; var email = String(b.email || '').trim().toLowerCase();
    if (!res || !email || (res.title + ' ' + res.snippet).toLowerCase().indexOf(email) < 0) { rejected++; return; }
    // customer-service and admin inboxes are not a route to a partnership conversation
    if (/(support|customer|helpdesk|help@|returns|orders|billing|invoice|accounts@|careers|jobs|privacy|noreply|no-reply)/.test(email + ' ' + String(b.purpose || '').toLowerCase())) { rejected++; return; }
    inboxes.push({ email: email, purpose: String(b.purpose || 'Company inbox').slice(0, 60), source_url: res.link, source_type: srcType(res.link) });
  });
  var rl = /429|too many requests|resource[_ ]exhausted|quota|rate limit/i.test(err);
  return { json: { p: { company_id: c.company_id, company_instagram: igCompany, people: people, inboxes: inboxes,
    usage: [{ model: 'models/gemini-3.1-flash-lite', input_tokens: u.promptTokenCount || 0, output_tokens: u.candidatesTokenCount || 0,
              thinking_tokens: u.thoughtsTokenCount || 0, status: err ? (rl ? 'RATE_LIMITED' : 'ERROR') : 'OK' }] },
    company: c.company, kept: people.length + inboxes.length, rejected: rejected, error: err.slice(0, 160) } };
});
