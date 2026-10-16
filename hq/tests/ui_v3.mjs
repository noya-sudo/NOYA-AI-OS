// HQ acceptance (CEO effectiveness pass, 16 Oct) in headless Chromium: Dashboard, the AI workforce and Director drill-downs,
// the outreach approval desk (email first), Relationships, Club and Operations — at 1440 px and on a 390 px phone. Every read
// is a live capture (tests/fixtures, git-ignored); every write is recorded to prove exactly what each button sends.
// Nothing here can send an email: Approve creates one unsent Gmail draft through the approval RPC.
import http from 'node:http';
import { readFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { extname, join } from 'node:path';
import { chromium } from 'playwright-core';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const fx = (f) => (existsSync(`tests/fixtures/${f}.json`) ? JSON.parse(readFileSync(`tests/fixtures/${f}.json`, 'utf8')) : null);
const need = ['snapshot', 'overview', 'directory', 'insight', 'relationships', 'desk', 'directors', 'club', 'operations', 'director_hospitality', 'director_partnerships', 'director_growth', 'director_email',
  'director_brands', 'director_weddings', 'director_media', 'director_sports', 'advisor', 'weekly', 'ceo', 'network'];
if (need.some((f) => !fx(f))) { console.log(`SKIP ui_v3: live fixtures missing (${need.filter((f) => !fx(f)).join(', ')})`); process.exit(0); }
const F = Object.fromEntries(need.map((f) => [f, fx(f)]));
F.execution = fx('execution'); // live hq_execution capture (queue health + acquisition split); optional
const DET = { HOSPITALITY: F.director_hospitality, PARTNERSHIPS: F.director_partnerships, GROWTH: F.director_growth, EMAIL: F.director_email,
  BRANDS: F.director_brands, WEDDINGS: F.director_weddings, MEDIA: F.director_media, SPORTS: F.director_sports };
// The live desk has no email in Needs review tonight (Hunter Free is used up until 27 Oct). To prove Approve on an email, one
// verified-email draft held for a quality edit is copied into Needs review in memory only, as an approvable candidate.
const QA = F.desk.held.filter((x) => x.channel === 'EMAIL' && x.status === 'OPEN' && /quality check/i.test(x.reason || ''));
if (!F.desk.needs_review.some((x) => x.channel === 'EMAIL' && x.approve_via) && QA[0]) {
  F.desk.needs_review.unshift({ ...QA[0], ref: `${QA[0].ref}-t`, bucket: 'NEEDS_REVIEW', reason: null, approve_via: 'EMAIL_CANDIDATE', candidate_id: '00000000-0000-0000-0000-0000000000e1' });
  F.desk.counts.needs_review.EMAIL += 1; F.desk.counts.needs_review.total += 1;
}
mkdirSync('tests/out/v3', { recursive: true });

const READS = {
  hq_dashboard: () => F.snapshot, hq_overview: () => F.overview, hq_directory: () => F.directory, hq_insight: () => F.insight, hq_relationships: () => F.relationships,
  hq_commercial: () => ({ generated_at: new Date().toISOString(), team: { members: [], routing: {} }, weights: {}, products: [], playbooks: [], signals: [], queue: [], partners: [], projects: [], supply_partners: {} }),
  hq_execution: () => F.execution, hq_email_review: () => ({ counts: {}, verification: {}, needs_review: [], drafting: [], in_gmail: [], failed: [], sent: [] }),
  hq_outreach_desk: () => F.desk, hq_operations: () => F.operations, hq_directors: () => F.directors, hq_club: () => F.club,
  hq_advisor: () => F.advisor, hq_weekly_review: () => F.weekly, hq_ceo_dashboard: () => F.ceo, hq_network: () => F.network,
  hq_director: (b) => DET[b?.p_key] || { key: b?.p_key, sections: [] }, hq_timeline: () => ({ events: [], notes: [] }), hq_account: () => null,
};
const WRITES = { hq_approve_draft: { ok: true, mode: 'DRAFT', dispatched: true, outbound_id: '00000000-0000-0000-0000-0000000000a1' },
  hq_approve_email: { ok: true, mode: 'DRAFT', dispatched: true, outbound_id: '00000000-0000-0000-0000-0000000000a2' },
  hq_outreach_action: { ok: true }, hq_outreach_edit: { ok: true }, hq_save_draft: { ok: true, version: 2 }, hq_task_action: { ok: true }, hq_task_dismiss: { ok: true },
  hq_club_person: { ok: true, id: '00000000-0000-0000-0000-0000000000c1' }, hq_redispatch: { ok: true }, hq_record_meeting: { ok: true }, hq_advisor_seen: { ok: true } };

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.txt': 'text/plain', '.woff2': 'font/woff2', '.svg': 'image/svg+xml' };
const server = http.createServer((req, res) => {
  const p = join('dist', req.url === '/' ? 'index.html' : req.url.split('?')[0]);
  if (!existsSync(p) || !statSync(p).isFile()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': types[extname(p)] || 'application/octet-stream' });
  res.end(readFileSync(p));
});
await new Promise((r) => server.listen(4174, r));

const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`); };
const b64url = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
function session() {
  const user = { id: '0d858bd9-4d03-482c-8d14-3237ac622bcc', aud: 'authenticated', role: 'authenticated', email: 'adam.elshazly1012@gmail.com', user_metadata: {}, app_metadata: { provider: 'email' } };
  const exp = Math.floor(Date.now() / 1000) + 3600;
  return { access_token: `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url({ sub: user.id, email: user.email, role: 'authenticated', exp })}.sig`, token_type: 'bearer', expires_in: 3600, expires_at: exp, refresh_token: 'r', user };
}
async function open(viewport) {
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport, permissions: ['clipboard-read', 'clipboard-write'] });
  const page = await ctx.newPage(); const errors = []; const calls = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.route(`${SUPA}/**`, async (route) => {
    const url = route.request().url();
    if (url.includes('/auth/v1/token')) return route.fulfill({ json: session() });
    if (url.includes('/auth/v1/user')) return route.fulfill({ json: session().user });
    const m = url.match(/\/rest\/v1\/rpc\/([a-z_]+)/);
    if (m) {
      const body = route.request().postDataJSON?.() ?? null; calls.push({ fn: m[1], body });
      if (READS[m[1]]) return route.fulfill({ json: READS[m[1]](body) });
      if (WRITES[m[1]]) return route.fulfill({ json: WRITES[m[1]] });
      return route.fulfill({ status: 404, json: { message: 'not allowed in test' } });
    }
    return route.fulfill({ status: 404, body: '' });
  });
  await page.goto('http://localhost:4174/');
  await page.fill('input[name=email]', 'adam.elshazly1012@gmail.com');
  await page.fill('input[name=password]', 'test-password-not-real');
  await page.click('button[type=submit]');
  await page.waitForSelector('.kpis');
  return { browser, page, errors, calls };
}
const last = (calls, fn) => [...calls].reverse().find((c) => c.fn === fn);
const overflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
const shot = (page, name, full = true) => page.screenshot({ path: `tests/out/v3/${name}.png`, fullPage: full });
const D = F.desk; const C = D.counts; const DIR = F.directors;
const cairoEnd = new Date(`${new Date().toLocaleDateString('en-CA', { timeZone: 'Africa/Cairo' })}T23:59:59+03:00`);

// ================================================================ 1440 px
const CEO = F.ceo; const NET = F.network; const A = F.advisor;
const tc = async (page, sel) => (await page.locator(sel).allTextContents()).map((t) => t.replace(/\s+/g, ' ').trim());
const DIRECTOR_SHOTS = [['BRANDS', 'Brands & Production', 'brands'], ['WEDDINGS', 'Weddings & Private Events', 'weddings'], ['MEDIA', 'Media & Culture', 'media'], ['SPORTS', 'NOYA Private', 'noya-private']];
{
  const { browser, page, errors, calls } = await open({ width: 1440, height: 900 });
  // NAVIGATION: Dashboard, Agents, Outreach, Relationships, Club, Operations, More / Admin.
  const primary = (await tc(page, '.side .nav-primary .nav-item')).map((t) => t.replace(/\s*\d+$/, ''));
  check('nav: Dashboard · Agents · Outreach · Relationships · Club · Operations, then More / Admin', primary.join('|') === 'Dashboard|Agents|Outreach|Relationships|Club|Operations'
    && (await page.locator('#nav-more').textContent()).trim() === 'More / Admin', primary.join(' | '));
  check('nav: More / Admin is collapsed until asked', (await page.locator('.side .nav-group').count()) === 0);
  await page.click('#nav-more');
  check('nav: More / Admin holds every older view, grouped (nothing deleted)', (await page.locator('.side .nav-group').count()) === 4 && (await page.locator('.side .nav-group .nav-item').count()) >= 28);
  await page.click('#nav-more');

  // DASHBOARD: what needs Adam, what the agents are doing, what could make money, who replied, what is developing, where it is stuck.
  await page.waitForSelector('main .ocard');
  const kl = await tc(page, 'main .kpi .kl'); const kn = await tc(page, 'main .kpi .kn');
  const K = Object.fromEntries(kl.map((l, i) => [l, kn[i]]));
  check('Dashboard strip: the seven numbers, in order', kl.join('|') === 'Emails needing review|Gmail drafts ready to send|Replies needing you|Meetings / calls|Active opportunities|Active projects|Won revenue', kl.join(' | '));
  check('Dashboard strip: emails needing review = email drafts in Needs review + verified email drafts waiting for a quality edit',
    Number(K['Emails needing review']) === C.needs_review.EMAIL + QA.length, `${K['Emails needing review']} vs ${C.needs_review.EMAIL}+${QA.length}`);
  check('Dashboard strip: Gmail drafts ready = Gmail-confirmed drafts on the desk', Number(K['Gmail drafts ready to send']) === C.gmail_drafts_confirmed, `${K['Gmail drafts ready to send']}`);
  check('Dashboard strip: active opportunities and projects are hq_ceo_dashboard()', Number(K['Active opportunities']) === CEO.active_opportunities && Number(K['Active projects']) === CEO.funnel.active_projects);
  const rev = (CEO.money?.revenue || []).length;
  check('Dashboard strip: revenue never invented — £0 / No recorded revenue when none is recorded', rev ? K['Won revenue'] !== '£0' : K['Won revenue'] === '£0' && /No recorded revenue/.test(await page.locator('main .kpi').last().textContent()));
  const acts = await page.locator('main #needs .act').count(); const why = await tc(page, 'main #needs .act-why');
  const nReplies = why.filter((w) => /reply waiting for you$|^Your own follow-up|^They asked for a meeting: the closest/.test(w)).length;
  const nMeet = why.filter((w) => w === 'They asked for a call: a project can start here' || w === 'They asked for a meeting').length;
  check('What needs you today: replies and meetings in the list equal the strip', Number(K['Replies needing you']) === nReplies && Number(K['Meetings / calls']) === nMeet, `${K['Replies needing you']}/${nReplies} · ${K['Meetings / calls']}/${nMeet}`);
  check('What needs you today: every row has who, why it matters, the next action, and one button', acts > 0 && (await page.locator('main #needs .act .act-who').count()) === acts
    && (await page.locator('main #needs .act .act-next').count()) === acts && (await page.locator('main #needs .act .act-cta .btn').count()) >= acts, `${acts} actions`);
  check('What needs you today: the Gmail drafts waiting for Send are listed', (await page.locator('main #needs .act', { hasText: 'only your Send is missing' }).count()) === C.gmail_drafts_confirmed);
  if (QA.length) check('What needs you today: verified email drafts that failed the quality check are listed for an edit', (await page.locator('main #needs .act', { hasText: 'failed the quality check' }).count()) === QA.length);
  const dash = await page.locator('main').innerText();
  check('Dashboard: no technical labels (no workflow, RPC, n8n, Supabase, task codes, P1/P2)', !/workflow \d|\brpc\b|supabase|n8n|EMAIL_CANDIDATE|NEEDS_REVIEW|SALES_OUTREACH|\bP[123]\b/i.test(dash));
  // HQ Advisor: 3-5 observations, situation -> meaning -> recommended action, verbatim from the data.
  const obs = await page.locator('main .advisor .adv-obs').count();
  const adv = await page.locator('main .advisor').innerText();
  check('HQ Advisor: 3–5 observations, each Situation / Meaning / Recommended action', obs === Math.min(5, A.observations.length) && obs >= 3 && obs <= 5
    && (await page.locator('main .advisor .adv-obs .adv-l').count()) === obs * 3, `${obs}`);
  check('HQ Advisor: situations and actions are the stored observations, nothing invented on the page', A.observations.slice(0, 5).every((o) => adv.includes(o.situation) && adv.includes(o.action)));
  // Top commercial opportunities: potential projects, no invented values.
  const cards = await page.locator('main .ocard').count(); const ocText = await tc(page, 'main .ocard');
  check('Top commercial opportunities: 5–10 potential projects from hq_ceo_dashboard()', cards === Math.min(10, CEO.top_opportunities.length) && cards >= 5, `${cards}`);
  check('Top commercial opportunities: company, project, Director, stage, why now, relationship, next move, evidence, strategic value',
    CEO.top_opportunities.slice(0, cards).every((o, i) => ocText[i].includes(o.company)) && ocText.every((t) => ['Why now', 'Relationship', 'Next move', 'Evidence', 'Strategic value'].every((w) => new RegExp(w, 'i').test(t))));
  check('Top commercial opportunities: no money figure is estimated', ocText.every((t) => !/[£$€]\s?\d/.test(t)));
  // Funnel: this week and the last 30 days, sent -> revenue.
  const fr = await page.$$eval('main table.funnel tbody tr', (trs) => trs.map((tr) => [...tr.children].map((c) => c.textContent.trim()).join(' ')));
  const sent30 = CEO.funnel.d30.sent_email + CEO.funnel.d30.sent_linkedin + (CEO.funnel.d30.sent_instagram || 0);
  check('Funnel: this week and last 30 days, sent → replies → positive → meetings → briefs → proposals → projects → won → revenue',
    (await tc(page, 'main table.funnel thead th')).slice(1).join('|') === 'Outreach sent|Replies|Positive|Meetings|Briefs / concepts|Proposals|Active projects|Won|Revenue'
      && fr.length === 2 && fr[1].startsWith(`Last 30 days ${sent30} ${CEO.funnel.d30.replies} ${CEO.funnel.d30.positive} ${CEO.funnel.d30.meetings}`), fr.join(' / '));
  const stuck = CEO.pipeline.filter((x) => x.stuck > 0);
  check('Pipeline: where prospects are stuck is stated', !stuck.length || stuck.every((x) => dash.includes(`${x.stuck} stuck`)), stuck.map((x) => `${x.stage}:${x.stuck}`).join(','));
  // AI workforce pulse: one row per Director; Working only while a scheduled run is actually in progress.
  const rows = DIR.members.filter((m) => m.role !== 'SUPPORT');
  const pst = await tc(page, 'main table.pulse tbody tr .st');
  check('AI workforce: one row per Director and the Partnerships Manager', (await page.locator('main table.pulse tbody tr').count()) === rows.length, `${rows.length}`);
  check('AI workforce: status is honest (Scheduled — HH:MM when not literally running; never Working unless a run is in progress)',
    rows.every((m, i) => (m.status === 'WORKING' ? /^Working/ : m.status === 'SCHEDULED' ? (m.next_run ? /^Scheduled — \d\d:\d\d$/ : /^Scheduled$/) : new RegExp(`^${m.status}`, 'i')).test(pst[i])), pst.join(' | '));
  check('AI workforce: no activity theatre', !/thinking|analysing\.\.\.|typing/i.test(dash));
  // Weekly CEO review.
  const wk = await tc(page, 'main .wk-t .l');
  check('Weekly CEO review: emails, LinkedIn fallbacks, replies, positive, meetings, briefs, proposals, won, revenue',
    wk.join('|') === 'Emails sent|LinkedIn fallbacks sent|Replies|Positive replies|Meetings|Briefs / concepts|Proposals|Projects won|Revenue', wk.join(' | '));
  const wkd = await page.locator('main .wk-dl').innerText();
  check('Weekly CEO review: top 5, biggest bottleneck, Director needing attention, Advisor recommendation, money as recorded',
    /Top 5 opportunities/i.test(wkd) && /Biggest bottleneck/i.test(wkd) && /Director needing attention/i.test(wkd) && /HQ Advisor recommendation/i.test(wkd) && (rev || /Not recorded/.test(wkd)));
  await shot(page, 'dashboard-1440');

  // AGENTS: the workforce.
  await page.click('.side [data-tab=agents]');
  await page.waitForSelector('.dcard');
  const roles = (r) => DIR.members.filter((m) => m.role === r).length;
  check('Agents: 10 Directors, 1 Strategic Partnerships Manager, 7 shared specialists', roles('DIRECTOR') === 10 && roles('MANAGER') === 1 && roles('SUPPORT') === 7
    && (await page.locator('.dcard').count()) === DIR.members.length, `${roles('DIRECTOR')}/${roles('MANAGER')}/${roles('SUPPORT')}`);
  const names = await tc(page, '.dcard .dc-name');
  check('Agents: the Directors by name', ['Private Membership & Network', 'Hospitality & Stays', 'Travel & Concierge Partnerships', 'Brands & Production', 'Weddings & Private Events', 'Corporate & White-Label',
    'Media & Culture', 'Egypt Growth', 'Strategic Partnerships Manager'].every((n) => names.some((x) => x.startsWith(n))) && names.some((x) => /^NOYA Private/.test(x)) && names.some((x) => /^Growth/.test(x)), names.join(' | '));
  const dc = await tc(page, '.dcard');
  check('Agents: every card shows status, current mission, last completed work and next run', DIR.members.every((m, i) => /Working on/i.test(dc[i]) && /Last completed/i.test(dc[i])
    && (m.status !== 'SCHEDULED' || !m.next_run || /Scheduled — \d\d:\d\d/.test(dc[i]))), DIR.members.filter((m, i) => !/Working on/i.test(dc[i])).map((m) => m.key).join(','));
  const commercial = DIR.members.filter((m) => m.role !== 'SUPPORT' && m.key !== 'GROWTH');
  check('Agents: every commercial Director shows Today (companies, people, verified emails, outreach ready, replies, opportunities) and 7 days (sent → wins)',
    commercial.every((m) => { const t = dc[DIR.members.indexOf(m)]; return ['qualified companies', 'correct people', 'verified emails', 'outreach ready', 'replies', 'opportunities'].every((w) => t.includes(w))
      && /Last 7 days/i.test(t) && ['sent', 'positive', 'meetings', 'proposals', 'wins'].every((w) => t.includes(w)); }));
  const brand = DIR.members.find((m) => m.key === 'BRANDS'); const bt = dc[DIR.members.indexOf(brand)];
  check('Agents: email health per Director (decision makers → found → verified · waiting verification · email ready · LinkedIn fallback)',
    bt.includes(`${brand.channel.with_dm} decision makers`) && bt.includes(`${brand.channel.verified} verified`) && bt.includes(`${brand.channel.needs_verification} waiting verification`)
      && bt.includes(`${brand.channel.email_ready} email ready`) && bt.includes(`${brand.channel.linkedin_fallback} LinkedIn fallback`), bt.slice(0, 200));
  check('Agents: every commercial Director names its top opportunity (or says none yet)', commercial.every((m) => /Top opportunity/i.test(dc[DIR.members.indexOf(m)])));
  const growth = DIR.members.find((m) => m.key === 'GROWTH');
  check('Agents: Growth is honestly blocked by the Windsor plan limit', growth.status === 'BLOCKED' && dc[DIR.members.indexOf(growth)].includes('Windsor free plan'));
  check('Agents: no activity theatre', !dc.some((c) => /thinking|analysing\.\.\.|typing/i.test(c)));
  await shot(page, 'agents-1440');

  // DIRECTOR DRILL-DOWNS: Overview · Opportunities · People · Emails · Outreach · Relationships · Projects.
  for (const [key, label, file] of DIRECTOR_SHOTS) {
    await page.click('.side [data-tab=agents]'); await page.waitForSelector('.dcard');
    await page.locator(`.dcard[data-director=${key}]`).click();
    await page.waitForSelector('[data-dir-sec]');
    check(`${label}: drill-down loads hq_director for that Director only`, calls.some((c) => c.fn === 'hq_director' && c.body?.p_key === key));
    const tabs = (await tc(page, 'main .tabs [data-dir-sec]')).map((t) => t.replace(/\s*\d+$/, ''));
    check(`${label}: tabs Overview · Opportunities · People · Emails · Outreach · Relationships · Projects`, tabs.join('|') === 'Overview|Opportunities|People|Emails|Outreach|Relationships|Projects', tabs.join(' | '));
    await shot(page, `director-${file}-1440`);
    await page.click('main [data-dir-sec=opportunities]');
    const ofr = await tc(page, 'main .ofr'); const OS = DET[key].sections.find((x) => x.key === 'opportunities');
    check(`${label}: every opportunity is framed as a project (what they did, who decides, what NOYA would handle, next step)`, ofr.length === (OS?.items || []).length
      && ofr.every((t) => /What they did/.test(t) && /Who decides/.test(t) && /NOYA would handle/.test(t) && /Next step/.test(t)), `${ofr.length}`);
    if (key === 'MEDIA') check('Media & Culture: concept-led opportunities carry the Egypt concept and why Egypt', OS.items.filter((o) => o.concept).every((o) => ofr.some((t) => t.includes(o.concept.concept)))
      && ofr.some((t) => /Concept/.test(t)), `${OS.items.filter((o) => o.concept).length} with concepts`);
    for (const s of ['people', 'emails', 'outreach', 'relationships', 'projects']) { await page.click(`main [data-dir-sec=${s}]`); await page.waitForTimeout(60); }
    check(`${label}: every tab renders`, errors.length === 0, errors.join(' | '));
  }

  // OUTREACH: approve communication. Email first.
  await page.click('.side [data-tab=desk]');
  await page.waitForSelector('main [data-desk-tab]');
  const dtabs = await tc(page, 'main .tabs button');
  const want = { 'Needs review': C.needs_review.total, 'Gmail drafts': C.approved, 'Follow-ups': C.followups, Sent: C.sent, Replied: C.replied, 'Researching / held': C.held + C.rejected + C.researching };
  check('Outreach: tabs Needs review · Gmail drafts · Follow-ups · Sent · Replied · Researching / held, counts from hq_outreach_desk', Object.entries(want).every(([l, n]) => dtabs.includes(`${l} ${n}`)) && dtabs.length === 6, dtabs.join(' | '));
  check('Outreach: Email is the default channel', (await page.locator('main [data-desk-ch=EMAIL]').getAttribute('class')).includes('on'));
  const projOpts = await tc(page, 'main select[data-desk-proj] option');
  check('Outreach: filters by Director, channel and project type (Brand shoot, Wedding, Travel partner, NOYA Private, Media / podcast, Hospitality partnership)',
    (await page.locator('main select[data-desk-dir]').count()) === 1 && ['Brand shoot / campaign', 'Wedding', 'Travel partner', 'NOYA Private', 'Media / podcast', 'Hospitality partnership'].every((o) => projOpts.includes(o)), projOpts.join(' | '));
  const em = D.needs_review.find((x) => x.channel === 'EMAIL' && x.approve_via);
  const card = page.locator(`#desk-${em.ref}`); const ct = await card.innerText();
  check('Email review card: person, company, role, Director, verified email, why them / why now, subject and a short preview', ct.includes(em.person) && ct.includes(em.company) && ct.includes(em.role)
    && /Verified email/i.test(ct) && ct.includes(em.route.email) && /Why (them|now)/i.test(ct) && ct.includes(em.subject) && (await card.locator('.dr-msg').count()) === 1, ct.slice(0, 160));
  const prim = (await card.locator('.dr-act > .btn').allTextContents()).map((t) => t.trim());
  check('Email review card: primary actions Approve · Edit · Hold; Research more · Source · Reject sit under •••', prim.slice(0, 3).join('|') === 'Approve|Edit|Hold' && prim.includes('•••')
    && (await card.locator('[data-desk-modal=research], [data-desk-modal=reject], [data-desk-src]').count()) === 0, prim.join(' | '));
  await card.locator('[data-desk-more]').click();
  const more = (await page.locator(`#desk-${em.ref} .more-menu .btn`).allTextContents()).map((t) => t.trim());
  check('Email review card: ••• opens Research more · Source · Reject', more.join('|') === 'Research more|Source|Reject', more.join(' | '));
  await shot(page, 'outreach-email-review-1440');
  await page.locator(`#desk-${em.ref} [data-desk-approve]`).click();
  await page.waitForTimeout(400);
  const ap = last(calls, 'hq_approve_email');
  check('Approve: creates an unsent Gmail draft through the approval RPC; nothing is ever sent', ap && ap.body.p_candidate === em.candidate_id && !calls.some((c) => /send/i.test(c.fn))
    && /unsent Gmail draft/.test(await page.locator('main .banner').first().innerText()), em.company);
  check('Approve: moves to Gmail drafts', (await page.locator('main .tabs button.on').innerText()).startsWith('Gmail drafts'));
  check('Gmail drafts: one row per approved email, Open in Gmail when the draft exists', (await page.locator('main .dlist .t-row').count()) === D.approved.length
    && (await page.locator('main .dlist a.btn', { hasText: 'Open in Gmail' }).count()) === D.approved.filter((x) => x.gmail_confirmed).length);
  await page.click('main [data-desk-tab=NEEDS_REVIEW]');
  // LinkedIn is a documented fallback; Adam sends it himself.
  await page.click('main [data-desk-ch=LINKEDIN]');
  const li = D.needs_review.filter((x) => x.channel === 'LINKEDIN').slice(0, 25).find((x) => x.candidate_id && x.task_id);
  if (li) {
    const lc = await page.locator(`#desk-${li.ref}`).innerText();
    check('LinkedIn fallback: says it is a fallback and what email research was done', !li.fallback || (/email checked/i.test(lc) && lc.toLowerCase().includes(li.fallback.label.split(' — ')[0].toLowerCase())), lc.slice(0, 160));
    await page.locator(`#desk-${li.ref} [data-desk-modal=edit]`).click();
    await page.fill('#d-body', 'Hi — edited on the desk.'); await page.click('#dm-ok'); await page.waitForTimeout(300);
    const ed = last(calls, 'hq_outreach_edit');
    check('Edit: saves through hq_outreach_edit; the original stays on record', ed && ed.body.p_task === li.task_id && /edited on the desk/.test(ed.body.p_body));
    await page.locator(`#desk-${li.ref} [data-desk-modal=hold]`).click();
    await page.fill('#d-reason', 'After their launch'); await page.click('#dm-ok'); await page.waitForTimeout(300);
    const ho = last(calls, 'hq_outreach_action');
    check('Hold: reason and review date', ho && ho.body.p_action === 'HOLD' && ho.body.p_task === li.task_id && /^\d{4}-\d{2}-\d{2}$/.test(ho.body.p_until));
    await page.locator(`#desk-${li.ref} [data-desk-more]`).click();
    await page.locator(`#desk-${li.ref} [data-desk-modal=research]`).click();
    await page.selectOption('#d-code', 'WRONG_PERSON'); await page.fill('#d-reason', 'left in June'); await page.click('#dm-ok'); await page.waitForTimeout(300);
    check('Research more (under •••): back to the agents with the reason', last(calls, 'hq_outreach_action').body.p_action === 'RESEARCH' && /^WRONG_PERSON: left in June$/.test(last(calls, 'hq_outreach_action').body.p_reason));
    if (!(await page.locator(`#desk-${li.ref} [data-desk-modal=reject]`).count())) await page.locator(`#desk-${li.ref} [data-desk-more]`).click();
    const before = calls.filter((c) => c.fn === 'hq_outreach_action').length;
    await page.locator(`#desk-${li.ref} [data-desk-modal=reject]`).click(); await page.click('#dm-ok'); await page.waitForTimeout(200);
    check('Reject (under •••): refused without a reason', calls.filter((c) => c.fn === 'hq_outreach_action').length === before && /reason is required/i.test(await page.locator('.modal').innerText()));
    await page.fill('#d-reason', 'Mass-market, not a fit'); await page.click('#dm-ok'); await page.waitForTimeout(300);
    check('Reject: reason stored', last(calls, 'hq_outreach_action').body.p_action === 'REJECT');
    await page.locator(`#desk-${li.ref} [data-modal=task-done]`).click(); await page.click('[data-confirm-task=COMPLETE]'); await page.waitForTimeout(300);
    check('LinkedIn: Mark sent closes the task (Adam sent it himself)', last(calls, 'hq_task_action')?.body.p_action === 'COMPLETE' && last(calls, 'hq_task_action').body.p_task_id === li.task_id);
  } else check('Outreach: a LinkedIn fallback exists on page 1', false);
  await page.click('main [data-desk-ch=EMAIL]');
  await page.click('main [data-desk-tab=FOLLOWUPS]');
  check('Follow-ups: one row per open follow-up, rule stated', (await page.locator('main .dlist .t-row').count()) === Math.min(C.followups, D.followups.filter((f) => (f.channel || 'EMAIL') === 'EMAIL').length) && /4 days after the real send/.test(await page.locator('main').innerText()));

  // RELATIONSHIPS: build the network; multipliers first.
  await page.click('.side [data-tab=relations]');
  await page.waitForSelector('main .nrow');
  const rt = (await tc(page, 'main .tabs button')).map((t) => t.replace(/\s*\d+$/, ''));
  check('Relationships: Important people · Companies · Warm relationships · Pipeline · Opportunities · Going cold', rt.join('|') === 'Important people|Companies|Warm relationships|Pipeline|Opportunities|Going cold', rt.join(' | '));
  check('Relationships: one row per important relationship from hq_network()', (await page.locator('main .nrow').count()) === NET.important.length);
  check('Relationships: multipliers are marked', (await page.locator('main .nrow.mult').count()) === NET.important.filter((x) => x.multiplier).length);
  const nr = await tc(page, 'main .nrow');
  check('Relationships: each row says who, company, why important, last interaction and owner', nr.every((t) => /owner /.test(t)) && NET.important.every((x, i) => nr[i].includes(x.company) && (!x.last_at || /last interaction/.test(nr[i]))));
  await shot(page, 'relationships-1440');
  for (const t of ['COMPANIES', 'WARM', 'PIPELINE', 'OPPORTUNITIES', 'COLD']) { await page.click(`main [data-rel-tab=${t}]`); await page.waitForTimeout(80); }
  check('Relationships: going cold lists hq_network().going_cold', (await page.locator('main .nrow').count()) === NET.going_cold.length);
  check('Relationships: every tab renders', errors.length === 0, errors.join(' | '));

  // CLUB: real people only.
  await page.click('.side [data-tab=club]');
  await page.waitForSelector('[data-club-tab]');
  const club = (await tc(page, 'main [data-club-tab]')).map((t) => t.replace(/\s*\d+$/, ''));
  check('Club: Private clients · Potential members · Introducers · Members · Benefits · Partner privileges · Events · Introductions', club.join('|') === 'Private clients|Potential members|Introducers|Members|Benefits|Partner privileges|Events|Introductions', club.join(' | '));
  await page.click('main [data-club-tab=MEMBERS]');
  check('Club: no fabricated members', F.club.members.length > 0 || /never automatically, never invented/.test(await page.locator('main').innerText()));
  await shot(page, 'club-1440');

  // OPERATIONS: confirmed delivery only, never prospects.
  await page.click('.side [data-tab=ops]');
  const ot = await page.locator('main').innerText(); const ops = CEO.operations;
  check('Operations: Active projects · Upcoming · Awaiting client · Awaiting supplier · Payment required · Completed',
    ['Active projects', 'Upcoming', 'Awaiting client', 'Awaiting supplier', 'Payment required', 'Completed'].every((w) => ot.includes(w)));
  check('Operations: confirmed client delivery only (honest when empty)', Object.values(ops).some((l) => l.length) ? !/No confirmed project yet/.test(ot) : /No confirmed project yet/.test(ot));
  await shot(page, 'operations-1440');

  check('desktop: only allow-listed reads and audited writes were called', calls.every((c) => READS[c.fn] || WRITES[c.fn]), [...new Set(calls.map((c) => c.fn))].filter((f) => !READS[f] && !WRITES[f]).join(','));
  check('desktop: no JavaScript errors', errors.length === 0, errors.join(' | '));
  await browser.close();
}

// ================================================================ 390 px phone
{
  const { browser, page, errors } = await open({ width: 390, height: 844 });
  const bn = (await page.locator('.bnav button').allTextContents()).map((t) => t.replace(/\d+$/, '').trim());
  check('phone: bottom bar Dashboard · Agents · Outreach · Relationships · More', bn.join('|') === 'Dashboard|Agents|Outreach|Relationships|More', bn.join(' | '));
  const o = async (name) => { const x = await overflow(page); check(`phone 390: no horizontal overflow · ${name}`, x <= 1, `${x}px`); };
  await page.waitForSelector('main .ocard');
  const kb = await page.locator('main .kpi').first().boundingBox();
  check('phone Dashboard: the strip is two columns of thumb-sized numbers', kb && kb.width >= 160 && kb.height >= 56, `${kb?.width}×${kb?.height}`);
  await o('Dashboard'); await shot(page, 'dashboard-390');
  await page.click('.bnav [data-tab=agents]'); await page.waitForSelector('.dcard');
  const w = await page.locator('.dcard').first().boundingBox();
  check('phone Agents: one card per row', w && w.width >= 330); await o('Agents'); await shot(page, 'agents-390');
  for (const [key, label, file] of DIRECTOR_SHOTS) {
    await page.click('.bnav [data-tab=agents]'); await page.waitForSelector('.dcard');
    await page.locator(`.dcard[data-director=${key}]`).click(); await page.waitForSelector('[data-dir-sec]');
    await o(label); await shot(page, `director-${file}-390`);
  }
  await page.click('.bnav [data-tab=desk]'); await page.waitForSelector('main .drow');
  const ab = await page.locator('main .drow .dr-act .btn').first().boundingBox();
  check('phone Outreach: review buttons are thumb-sized', ab && ab.height >= 30, `${ab?.height}`);
  await o('Outreach · Email review'); await shot(page, 'outreach-email-review-390');
  await page.click('.bnav [data-tab=relations]'); await page.waitForSelector('main .nrow'); await o('Relationships'); await shot(page, 'relationships-390');
  await page.click('#bmenu'); await page.click('.sheet [data-tab=club]'); await page.waitForSelector('[data-club-tab]'); await o('Club'); await shot(page, 'club-390');
  await page.click('#bmenu'); await page.click('.sheet [data-tab=ops]'); await o('Operations'); await shot(page, 'operations-390');
  check('phone: no JavaScript errors', errors.length === 0, errors.join(' | '));
  await browser.close();
}

server.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} HQ acceptance checks passed`);
process.exit(failed.length ? 1 : 0);
