// Proof check before anything is saved. Addresses come only from the deterministic list (the model cannot add one).
// An owner is accepted only if both names appear in the text around the address, or the address itself spells the
// person's name (first.last@, flast@, firstlast@, first_last@...) for someone named in the evidence. A role is kept only if
// its words appear in the evidence. People from team pages must have name and role printed on that page.
var src = $('Has Evidence?').all(0);
function norm(s) { return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[’]/g, "'").replace(/[^a-z0-9@._' -]/g, ' ').replace(/\s+/g, ' ').trim(); }
function alpha(s) { return norm(s).replace(/[^a-z]/g, ''); }
function roleScore(p) {
  p = String(p || '').toLowerCase();
  if (!p.trim()) return 1;
  if (/\b(assistant to|executive assistant|pa to)\b/.test(p)) return 3;
  if (/\b(founder|co-founder|cofounder|owner|ceo|chief|president|managing director|managing partner|proprietor|chairman|chairwoman)\b/.test(p)) return 5;
  if (/\b(guest relations|concierge)\b/.test(p) && /\b(director|head|chef|chief|manager)\b/.test(p)) return 4;
  if (/\b(hr|human resources|recruit\w*|talent acquisition|front office|guest relations?|reception\w*|housekeeping|engineer\w*|maintenance|accountant|accounting|payroll|intern|trainee|student|waiter|waitress|chef|cook|barista|bartender|sommelier|kitchen|restaurant|brasserie|f&b|food (and|&) beverage|spa|therapist|security officer|driver|legal|counsel|compliance|procurement|purchasing|developer|software|night manager|cashier|butler|valet|board member|non-executive)\b/.test(p)) return 0;
  if (/\b(general manager|gm|partner|principal)\b/.test(p)) return 5;
  if (/\b(director|head|vp|vice president|svp|evp)\b/.test(p)) return 4;
  if (/\b(partnerships?|business development|commercial|experiential|influencer|brand|marketing|sales|pr|communications|press|events?|production|creative)\b/.test(p) && /\b(manager|lead)\b/.test(p)) return 4;
  if (/\b(manager|lead|producer|planner|designer|curator|editor|buyer)\b/.test(p)) return 3;
  return 2;
}
function spells(local, f, l) {
  f = alpha(f); l = alpha(l); var lp = String(local || '').toLowerCase().replace(/[^a-z._-]/g, '');
  if (f.length < 2 || l.length < 2) return false;
  var flat = lp.replace(/[._-]/g, '');
  return [f + l, f[0] + l, l + f, l + f[0], f + l[0]].indexOf(flat) >= 0 && (flat.length >= 5)
      || lp === f + '.' + l || lp === f + '_' + l || lp === f + '-' + l || lp === f[0] + '.' + l || lp === l + '.' + f;
}
function roleOk(role, text) { var t = norm(text); return !!role && norm(role).split(' ').some(function (w) { return w.length >= 4 && t.indexOf(w) >= 0; }); }
return $input.all().map(function (x, i) {
  var it = src[i].json, c = it.company, r = x.json || {};
  var err = r.error ? (typeof r.error === 'string' ? r.error : (r.error.message || JSON.stringify(r.error))) : '';
  var u = r.usageMetadata || {};
  var text = ''; try { text = (r.candidates[0].content.parts || []).map(function (p) { return p.text || ''; }).join(''); } catch (e) { text = ''; }
  var o = {}; try { o = JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1)); } catch (e) { o = {}; }
  var rejected = 0;
  // people printed on the team / press pages
  var people = [];
  (o.people || []).forEach(function (p) {
    var d = it.docs[(p.page || 0) - 1]; if (!d) { rejected++; return; }
    var t = norm(d.text); var fn = norm(p.first_name), ln = norm(p.last_name);
    if (fn.length < 2 || alpha(ln).length < 2 || t.indexOf(fn) < 0 || t.indexOf(ln) < 0 || !roleOk(p.position, d.text) || roleScore(p.position) === 0) { rejected++; return; }
    people.push({ first_name: String(p.first_name).trim(), last_name: String(p.last_name).trim(), position: String(p.position).trim(), source_url: d.url, source_type: d.type });
  });
  var named = (c.people || []).map(function (p) { return { first_name: p.first_name, last_name: p.last_name, position: p.position }; }).concat(people);
  var emails = it.emails.map(function (e, j) {
    var a = (o.emails || []).filter(function (z) { return z.id === j + 1; })[0] || {};
    var local = e.email.split('@')[0]; var ctx = norm(e.ctx);
    var owner = null;
    if (e.cls === 'PERSONAL' || (e.type === 'INSTAGRAM')) {
      var f = a.owner_first, l = a.owner_last;
      if (f && l && ((ctx.indexOf(norm(f)) >= 0 && ctx.indexOf(norm(l)) >= 0) || spells(local, f, l))) owner = { first: String(f).trim(), last: String(l).trim(), role: a.owner_role || '' };
      if (!owner) named.some(function (p) { if (spells(local, p.first_name, p.last_name)) { owner = { first: p.first_name, last: p.last_name, role: p.position || '' }; return true; } return false; });
      if (owner && owner.role && !roleOk(owner.role, e.ctx + ' ' + it.docs.map(function (d) { return d.text; }).join(' ')) &&
          !named.some(function (p) { return norm(p.first_name) === norm(owner.first) && norm(p.last_name) === norm(owner.last) && norm(p.position) === norm(owner.role); })) owner.role = '';
      if (owner && owner.role && roleScore(owner.role) === 0) { rejected++; owner = null; }
    }
    if (e.cls === 'PERSONAL' && !owner && e.type !== 'INSTAGRAM') { rejected++; return null; } // a personal-looking address nobody can be tied to
    return { email: e.email, owner_first: owner ? owner.first : '', owner_last: owner ? owner.last : '', owner_role: owner ? owner.role : '',
             department: owner ? '' : (String(a.department || local).replace(/[._-]+/g, ' ').slice(0, 40).replace(/^./, function (ch) { return ch.toUpperCase(); }) + ' inbox'),
             source_url: e.url, source_type: e.type, evidence: e.ctx.slice(0, 200) };
  }).filter(Boolean);
  var rl = /429|too many requests|resource[_ ]exhausted|quota|rate limit/i.test(err);
  return { json: { p: { company_id: c.company_id, test_tag: c.test_tag || '', found_domain: it.found_domain || '', people: people, emails: emails,
      research: Object.assign({}, it.research, { rejected: rejected }),
      usage: [{ model: 'models/gemini-3.1-flash-lite', input_tokens: u.promptTokenCount || 0, output_tokens: u.candidatesTokenCount || 0,
                thinking_tokens: u.thoughtsTokenCount || 0, status: err ? (rl ? 'RATE_LIMITED' : 'ERROR') : 'OK' }] },
    company: c.company, emails: emails.length, people: people.length, error: err.slice(0, 160) } };
});
