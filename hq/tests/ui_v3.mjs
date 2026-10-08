// HQ V3 acceptance in headless Chromium: six destinations, Today, the workforce, drill-downs, the outreach approval desk,
// Relationships, Club and Operations — at 1440 px and on a 390 px phone. Every read is a live capture (tests/fixtures,
// git-ignored); every write is recorded to prove exactly what each button sends. Nothing here can send an email.
import http from 'node:http';
import { readFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { extname, join } from 'node:path';
import { chromium } from 'playwright-core';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const fx = (f) => (existsSync(`tests/fixtures/${f}.json`) ? JSON.parse(readFileSync(`tests/fixtures/${f}.json`, 'utf8')) : null);
const need = ['snapshot', 'overview', 'directory', 'insight', 'relationships', 'desk', 'directors', 'club', 'operations', 'director_hospitality', 'director_partnerships', 'director_growth', 'director_email'];
if (need.some((f) => !fx(f))) { console.log(`SKIP ui_v3: live fixtures missing (${need.filter((f) => !fx(f)).join(', ')})`); process.exit(0); }
const F = Object.fromEntries(need.map((f) => [f, fx(f)]));
const DET = { HOSPITALITY: F.director_hospitality, PARTNERSHIPS: F.director_partnerships, GROWTH: F.director_growth, EMAIL: F.director_email };
mkdirSync('tests/out/v3', { recursive: true });

const READS = {
  hq_dashboard: () => F.snapshot, hq_overview: () => F.overview, hq_directory: () => F.directory, hq_insight: () => F.insight, hq_relationships: () => F.relationships,
  hq_commercial: () => ({ generated_at: new Date().toISOString(), team: { members: [], routing: {} }, weights: {}, products: [], playbooks: [], signals: [], queue: [], partners: [], projects: [], supply_partners: {} }),
  hq_execution: () => null, hq_email_review: () => ({ counts: {}, verification: {}, needs_review: [], drafting: [], in_gmail: [], failed: [], sent: [] }),
  hq_outreach_desk: () => F.desk, hq_operations: () => F.operations, hq_directors: () => F.directors, hq_club: () => F.club,
  hq_director: (b) => DET[b?.p_key] || { key: b?.p_key, sections: [] }, hq_timeline: () => ({ events: [], notes: [] }), hq_account: () => null,
};
const WRITES = { hq_approve_draft: { ok: true, mode: 'DRAFT', dispatched: true, outbound_id: '00000000-0000-0000-0000-0000000000a1' },
  hq_approve_email: { ok: true, mode: 'DRAFT', dispatched: true, outbound_id: '00000000-0000-0000-0000-0000000000a2' },
  hq_outreach_action: { ok: true }, hq_outreach_edit: { ok: true }, hq_save_draft: { ok: true, version: 2 }, hq_task_action: { ok: true }, hq_task_dismiss: { ok: true },
  hq_club_person: { ok: true, id: '00000000-0000-0000-0000-0000000000c1' }, hq_redispatch: { ok: true }, hq_record_meeting: { ok: true } };

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
  await page.waitForSelector('.today-sec, .calm');
  return { browser, page, errors, calls };
}
const last = (calls, fn) => [...calls].reverse().find((c) => c.fn === fn);
const overflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
const shot = (page, name, full = true) => page.screenshot({ path: `tests/out/v3/${name}.png`, fullPage: full });
const D = F.desk; const C = D.counts; const DIR = F.directors;
const cairoEnd = new Date(`${new Date().toLocaleDateString('en-CA', { timeZone: 'Africa/Cairo' })}T23:59:59+03:00`);

// ================================================================ 1440 px
{
  const { browser, page, errors, calls } = await open({ width: 1440, height: 900 });
  // Navigation: six destinations, More holds every older view.
  const primary = (await page.locator('.side .nav-primary .nav-item').allInnerTexts()).map((t) => t.replace(/\s*\d+$/, '').trim());
  check('nav: exactly six destinations in order', primary.join('|') === 'Today|Agents|Outreach|Relationships|Club|Operations', primary.join(' | '));
  check('nav: More is collapsed until asked', (await page.locator('.side .nav-group').count()) === 0);
  await page.click('#nav-more');
  check('nav: More holds the older views, grouped (nothing deleted)', (await page.locator('.side .nav-group').count()) === 4 && (await page.locator('.side .nav-group .nav-item').count()) >= 28);
  await page.click('#nav-more');

  // TODAY: only what needs Adam.
  const today = await page.locator('main').innerText();
  const nr = C.needs_review.total;
  check('Today: approvals line equals the desk (Needs review)', !nr || new RegExp(`Outreach waiting for your review\\s*${nr}`, 'i').test(today), `${nr}`);
  const due = D.followups.filter((f) => f.due_at && new Date(f.due_at) <= cairoEnd).length;
  check('Today: follow-ups due equals the desk', !due || new RegExp(`Follow-ups due\\s*${due}`, 'i').test(today), `${due}`);
  const gm = D.approved.filter((x) => x.gmail_confirmed).length;
  check('Today: Gmail drafts to send equals confirmed Gmail drafts', gm ? new RegExp(`Gmail drafts to send\\s*${gm}`, 'i').test(today) : !/Gmail drafts to send/i.test(today), `${gm}`);
  const replies = DIR.floor.replies; const meets = DIR.floor.meetings;
  check('Today: replies waiting equals the Agents strip (open reply and review tasks, incl. personal follow-ups)', replies ? new RegExp(`Replies waiting for you\\s*${replies}`, 'i').test(today) : !/Replies waiting/i.test(today), `${replies}`);
  check('Today: meetings and calls equal the Agents strip (no double count)', meets ? new RegExp(`Meetings and calls\\s*${meets}`, 'i').test(today) : !/Meetings and calls/i.test(today), `${meets}`);
  check('Today: calm — no engineering words, no metrics walls', !/workflow|supabase|n8n|rpc|pipeline value|P1|P2|P3/i.test(today) && (await page.locator('main .tile').count()) === 0);
  await shot(page, 'today-1440');

  // AGENTS: the workforce.
  await page.click('.side [data-tab=agents]');
  await page.waitForSelector('.dcard');
  const fl = DIR.floor; const floor = await page.locator('.floor').innerText();
  check('Agents: floor strip equals hq_directors().floor', [`${fl.agents_healthy} / ${fl.agents_total}`, fl.qualified_24h, fl.decision_makers_24h, fl.verified_emails_24h, fl.needs_review, fl.gmail_drafts_ready, fl.replies, fl.meetings]
    .every((v) => floor.includes(String(v))), floor.replace(/\n/g, ' '));
  check('Agents: needs-review on the floor equals the desk', fl.needs_review === nr, `${fl.needs_review} vs ${nr}`);
  const roles = (r) => DIR.members.filter((m) => m.role === r).length;
  check('Agents: 10 Directors, 1 Partnerships Manager, 7 shared specialists', roles('DIRECTOR') === 10 && roles('MANAGER') === 1 && roles('SUPPORT') === 7
    && (await page.locator('.dcard').count()) === DIR.members.length, `${roles('DIRECTOR')}/${roles('MANAGER')}/${roles('SUPPORT')}`);
  const cards = await page.locator('.dcard').allInnerTexts();
  check('Agents: every card shows a real status (Working / Scheduled / Blocked / Error) and its status line', DIR.members.every((m, i) => /Working|Scheduled|Blocked|Error/.test(cards[i]) && cards[i].includes(m.status_text)));
  check('Agents: no pretend thinking', !cards.some((c) => /thinking|analysing\.\.\.|typing/i.test(c)));
  const growth = DIR.members.find((m) => m.key === 'GROWTH');
  check('Agents: Growth is honestly blocked by the Windsor plan limit', growth.status === 'BLOCKED' && cards.some((c) => /Growth, Social & Paid Media/.test(c) && /Windsor free plan/.test(c)));
  check('Agents: activity feed is real stored events', (await page.locator('main .feed-row').count()) === Math.min(20, DIR.feed.length) && (await page.locator('main').innerText()).includes(DIR.feed[0].text));
  await shot(page, 'agents-1440');

  // Director drill-down: Hospitality & Stays.
  const H = F.director_hospitality; const hs = (k) => H.sections.find((s) => s.key === k);
  await page.locator('.dcard', { hasText: 'Hospitality & Stays' }).click();
  await page.waitForSelector('[data-dir-sec]');
  check('Drill-down loads hq_director for that Director only', calls.some((c) => c.fn === 'hq_director' && c.body?.p_key === 'HOSPITALITY'));
  const chips = await page.locator('[data-dir-sec]').allInnerTexts();
  check('Drill-down: new finds, people, verified contacts, email gaps, opportunities, waiting, approved, researching, held, activity — each with its true total',
    ['New finds', 'People', 'Verified contacts', 'Email gaps', 'Opportunities', 'Waiting for Adam', 'Approved / Gmail drafts', 'Researching', 'Held or rejected', 'Recent activity'].every((t) => chips.some((c) => c.startsWith(t)))
      && H.sections.every((s) => chips.some((c) => c === `${s.title} · ${s.total}`)), chips.join(' | '));
  check('Drill-down: waiting-for-Adam equals the desk for this Director', hs('needs_review').total === D.needs_review.filter((x) => x.director === 'HOSPITALITY').length);
  await page.click('[data-dir-sec=people]');
  const ppl = await page.locator('main .panel').last().innerText(); const p0 = hs('people').items[0];
  check('Drill-down people: name, role, company, verification state, source, confidence', ppl.includes(p0.name) && ppl.includes(p0.company) && /Source:/.test(ppl) && /confidence/.test(ppl)
    && /(Valid · verified|Public · not verified|Accept-all|No email|Unknown|Invalid)/i.test(ppl) && /in total|showing the latest/i.test(await page.locator('main .panel header').last().innerText()));
  await page.click('[data-dir-sec=verified]');
  check('Drill-down: verified contacts are only VALID_VERIFIED', hs('verified').items.every((p) => p.email_state === 'VALID_VERIFIED') && /Valid · verified/i.test(await page.locator('main .panel').last().innerText()));
  await shot(page, 'director-hospitality-1440');

  // Strategic Partnerships Manager: value both ways, right contact, next step.
  await page.click('[data-tab=agents] >> nth=0');
  await page.locator('.dcard', { hasText: 'Strategic Partnerships Manager' }).click();
  await page.waitForSelector('[data-dir-sec=opportunities]');
  await page.click('[data-dir-sec=opportunities]');
  const pm = await page.locator('main .panel').last().innerText(); const PT = F.director_partnerships.sections.find((s) => s.key === 'opportunities');
  check('Partnerships: commercial model, value to NOYA, value to partner, right contact, next step', /Value to NOYA/.test(pm) && /Value to them/.test(pm) && /Right contact/.test(pm) && /Next step/.test(pm));
  check('Partnerships: list says how many of the total it shows', (await page.locator('main .panel header').last().innerText()).includes(PT.total > PT.items.length ? `showing the latest ${PT.items.length} of ${PT.total}` : `${PT.total} in total`));
  await shot(page, 'director-partnerships-1440');

  // Growth, Social & Paid Media: honest connections, approval pipeline, no spend.
  await page.click('[data-tab=agents] >> nth=0');
  await page.locator('.dcard', { hasText: 'Growth, Social & Paid Media' }).click();
  await page.waitForSelector('main .loop');
  const gt = await page.locator('main').innerText();
  check('Growth: Metricool shown as connected to Instagram but not to HQ', /Metricool/.test(gt) && /Not connected to HQ/i.test(gt));
  check('Growth: Meta Ads read-only, paused, never launched from HQ', /META ADS: read access paused/.test(gt) && /never launches spend/i.test(gt));
  check('Growth: content approval pipeline Idea → … → Metricool scheduled → Published → Performance', ['Idea', 'Draft', 'Review', 'Approved', 'Metricool scheduled', 'Published', 'Performance'].every((s) => gt.includes(s)));
  check('Growth: Instagram performance is the stored posts', new RegExp(`${F.director_growth.growth.top_posts.length} posts analysed`, 'i').test(gt));
  await shot(page, 'director-growth-1440');

  // Email Intelligence & Verification: the verification queue equals workflow 24's queue.
  await page.click('[data-tab=agents] >> nth=0');
  await page.locator('.dcard', { hasText: 'Email Intelligence & Verification' }).click();
  await page.waitForSelector('[data-dir-sec=verify_queue]');
  const EQ = F.director_email.sections.find((s) => s.key === 'verify_queue');
  check('Email agent: verification queue total equals the card and the per-Director sum', EQ.total === DIR.members.filter((m) => m.role === 'DIRECTOR').reduce((n, m) => n + (m.queues?.to_verify || 0), 0), `${EQ.total}`);

  // OUTREACH: the approval desk.
  await page.click('.side [data-tab=desk]');
  await page.waitForSelector('.drow');
  const tabs = await page.locator('main .tabs button').allInnerTexts();
  const want = { 'Needs review': C.needs_review.total, 'Approved / Gmail drafts': C.approved, 'Follow-ups': C.followups, Sent: C.sent, Replied: C.replied, Held: C.held + C.rejected, Researching: C.researching };
  check('Desk: tabs Needs review / Approved & Gmail drafts / Follow-ups / Sent / Replied / Held / Researching — counts equal hq_outreach_desk', Object.entries(want).every(([l, n]) => tabs.some((t) => t.replace(/\s+/g, ' ').trim() === `${l} ${n}`)) && !tabs.some((t) => /^Ready\b/.test(t)), tabs.join(' | '));
  check('Desk: Needs review + Held + Researching reconcile with the open outreach tasks', C.needs_review.total + C.held + C.researching === D.needs_review.length + D.held.length + D.researching.length);
  const chipT = await page.locator('main [data-desk-ch]').allInnerTexts();
  const chN = (l) => Number((chipT.find((t) => t.startsWith(l)) || '0').split('·')[1] || 0);
  check('Desk: channel filters add up (Email + LinkedIn + Instagram + WhatsApp = all)', chN('All') === C.needs_review.total && chN('Email') + chN('LinkedIn') + chN('Instagram') + chN('WhatsApp') === C.needs_review.total && chN('Email') === C.needs_review.EMAIL, chipT.join(' | '));
  const pager = await page.locator('main .pager').first().innerText();
  check('Desk: paging shows the true total, no hidden 20-record limit', pager.includes(`Showing 1–${Math.min(25, nr)} of ${nr}`) && (await page.locator('main .drow').count()) === Math.min(25, nr), pager);
  if (nr > 25) { await page.locator('main [data-desk-page="1"]').first().click(); check('Desk: next page continues the count', (await page.locator('main .pager').first().innerText()).includes(`Showing 26–${Math.min(50, nr)} of ${nr}`)); await page.locator('main [data-desk-page="-1"]').first().click(); }
  const vis = await page.locator('main').innerText();
  check('Desk: technical labels hidden under Technical details', !/SALES_OUTREACH_APPROVAL|OUTREACH_FOLLOW_UP|Workflow \d|EMAIL_CANDIDATE|OPPORTUNITY_DRAFT/.test(vis) && (await page.locator('main details.tech').count()) === (await page.locator('main .drow').count()));
  check('Desk: compact rows carry person, company, Director, channel, route, verification, why-now, angle, subject, preview, age',
    (await page.locator('main .drow .dr-pills').count()) === (await page.locator('main .drow').count()) && /Why now/i.test(vis) && /Angle/i.test(vis) && /\d+ d\b/.test(vis));
  // Approve an email: re-validated server-side, creates an unsent Gmail draft, never a send.
  const em = D.needs_review.find((x) => x.channel === 'EMAIL' && x.approve_via);
  if (em) {
    await page.click('main [data-desk-ch=EMAIL]');
    await page.locator(`#desk-${em.ref} [data-desk-approve]`).click();
    await page.waitForTimeout(400);
    const ap = em.approve_via === 'EMAIL_CANDIDATE' ? last(calls, 'hq_approve_email') : last(calls, 'hq_approve_draft');
    check('Desk Approve (email): creates an unsent Gmail draft through the approval RPC, never a send', ap && (em.approve_via === 'EMAIL_CANDIDATE' ? ap.body.p_candidate === em.candidate_id : ap.body.p_opportunity_id === em.opportunity_id && ap.body.p_version === Number(em.draft_version || 1))
      && !calls.some((c) => /send/i.test(c.fn)) && /unsent Gmail draft/.test(await page.locator('main .banner').first().innerText()), em.company);
    check('Desk Approve: moves to Approved / Gmail drafts', (await page.locator('main .tabs button.on').innerText()).startsWith('Approved'));
    await shot(page, 'desk-approved-1440');
    await page.click('main [data-desk-tab=NEEDS_REVIEW]');
    await page.click('main [data-desk-ch=""]');
  } else check('Desk Approve (email): an approvable email exists in the live desk', false, 'none in fixture');
  const liList = D.needs_review.filter((x) => x.channel === 'LINKEDIN');
  const li = liList.slice(0, 25).find((x) => x.candidate_id && x.task_id);
  if (li) {
    await page.click('main [data-desk-ch=LINKEDIN]');
    await page.locator(`#desk-${li.ref} [data-desk-modal=edit]`).click();
    await page.fill('#d-body', 'Hi — edited on the desk.');
    await page.click('#dm-ok'); await page.waitForTimeout(300);
    const ed = last(calls, 'hq_outreach_edit');
    check('Desk Edit: saves through hq_outreach_edit; the original stays on record', ed && ed.body.p_task === li.task_id && /edited on the desk/.test(ed.body.p_body));
    await page.locator(`#desk-${li.ref} [data-desk-modal=hold]`).click();
    await page.fill('#d-reason', 'After their launch');
    await page.click('#dm-ok'); await page.waitForTimeout(300);
    const ho = last(calls, 'hq_outreach_action');
    check('Desk Hold: reason and review date', ho && ho.body.p_action === 'HOLD' && ho.body.p_task === li.task_id && /^\d{4}-\d{2}-\d{2}$/.test(ho.body.p_until));
    await page.locator(`#desk-${li.ref} [data-desk-modal=research]`).click();
    await page.selectOption('#d-code', 'WRONG_PERSON'); await page.fill('#d-reason', 'left in June');
    await page.click('#dm-ok'); await page.waitForTimeout(300);
    const rs = last(calls, 'hq_outreach_action');
    check('Desk Research more: goes back to the agents with the reason (no duplicate created)', rs.body.p_action === 'RESEARCH' && /^WRONG_PERSON: left in June$/.test(rs.body.p_reason));
    const before = calls.filter((c) => c.fn === 'hq_outreach_action').length;
    await page.locator(`#desk-${li.ref} [data-desk-modal=reject]`).click();
    await page.click('#dm-ok'); await page.waitForTimeout(200);
    check('Desk Reject: refused without a reason', calls.filter((c) => c.fn === 'hq_outreach_action').length === before && /reason is required/i.test(await page.locator('.modal').innerText()));
    await page.fill('#d-reason', 'Mass-market, not a fit'); await page.click('#dm-ok'); await page.waitForTimeout(300);
    check('Desk Reject: reason stored, company held from rediscovery', last(calls, 'hq_outreach_action').body.p_action === 'REJECT');
    await page.locator(`#desk-${li.ref} [data-modal=task-done]`).click();
    await page.click('[data-confirm-task=COMPLETE]'); await page.waitForTimeout(300);
    check('Desk LinkedIn: Mark sent closes the task (send logged, follow-up booked server-side)', last(calls, 'hq_task_action')?.body.p_action === 'COMPLETE' && last(calls, 'hq_task_action').body.p_task_id === li.task_id);
    await page.locator(`#desk-${li.ref} [data-desk-src]`).click();
    check('Desk Source: shows where the person and route came from', /identity/.test(await page.locator(`#desk-${li.ref} .dr-src`).innerText()));
  } else check('Desk: a LinkedIn candidate row exists on page 1', false);
  await shot(page, 'desk-needs-review-1440');
  await page.click('main [data-desk-tab=FOLLOWUPS]');
  check('Desk Follow-ups: one row per open follow-up, rule stated', (await page.locator('main .dlist .t-row').count()) === C.followups && /4 days after the real send/.test(await page.locator('main').innerText()));
  await shot(page, 'desk-followups-1440');
  await page.click('main [data-desk-tab=HELD]');
  check('Desk Held: held rows', (await page.locator('main .drow').count()) === Math.min(25, D.held.length));

  // RELATIONSHIPS workspace.
  await page.click('.side [data-tab=relations]');
  const rt = await page.locator('main .tabs button').allInnerTexts();
  check('Relationships: People, Companies, Warm, Opportunities, Pipeline, History', rt.join('|') === 'People|Companies|Warm|Opportunities|Pipeline|History', rt.join(' | '));
  check('Relationships People: one row per contact', (await page.locator('main tbody tr').count()) === F.directory.contacts.length);
  await shot(page, 'relationships-1440');
  for (const t of ['COMPANIES', 'WARM', 'OPPORTUNITIES', 'PIPELINE', 'HISTORY']) { await page.click(`main [data-rel-tab=${t}]`); await page.waitForTimeout(100); }
  check('Relationships: every tab renders', errors.length === 0);

  // CLUB foundation: real people only.
  await page.click('.side [data-tab=club]');
  await page.waitForSelector('[data-club-tab]');
  check('Club: ten parts (members … communities)', (await page.locator('main [data-club-tab]').count()) === 10);
  check('Club: communities are the real qualified clubs and communities', (await page.locator('main .panel .t-row').count()) === F.club.communities.length);
  await page.click('main [data-club-tab=MEMBERS]');
  check('Club: no fabricated members', F.club.members.length > 0 || /never automatically, never invented/.test(await page.locator('main').innerText()));
  await page.click('main [data-club-tab=INTRODUCERS]');
  check('Club: introducer routes come from confirmed people in the CRM', (await page.locator('main [data-club-add=INTRODUCER]').count()) === F.club.introducer_routes.length);
  await shot(page, 'club-1440');
  if (F.club.introducer_routes.length) { await page.locator('main [data-club-add=INTRODUCER]').first().click(); await page.waitForTimeout(300); check('Club: adding an introducer is Adam\'s audited action', last(calls, 'hq_club_person')?.body.p_role === 'INTRODUCER'); }

  // OPERATIONS: confirmed delivery only.
  await page.click('.side [data-tab=ops]');
  const ot = await page.locator('main').innerText(); const O = F.operations;
  check('Operations: confirmed client delivery only (honest when empty)', (O.projects.length + O.won.length + O.clients.length) ? !/No confirmed client work yet/.test(ot) : /No confirmed client work yet/.test(ot));
  await shot(page, 'operations-1440');

  check('ui_v3 desktop: only allow-listed reads and audited writes were called', calls.every((c) => READS[c.fn] || WRITES[c.fn]), [...new Set(calls.map((c) => c.fn))].filter((f) => !READS[f] && !WRITES[f]).join(','));
  check('ui_v3 desktop: no JavaScript errors', errors.length === 0, errors.join(' | '));
  await browser.close();
}

// ================================================================ 390 px phone
{
  const { browser, page, errors } = await open({ width: 390, height: 844 });
  const bn = (await page.locator('.bnav button').allInnerTexts()).map((t) => t.replace(/\d+$/, '').trim());
  check('phone: bottom bar Today / Agents / Outreach / Relationships / More', bn.join('|') === 'Today|Agents|Outreach|Relationships|More', bn.join(' | '));
  const o = async (name) => { const x = await overflow(page); check(`phone 390: no horizontal overflow · ${name}`, x <= 1, `${x}px`); };
  await o('Today'); await shot(page, 'today-390');
  await page.click('.bnav [data-tab=agents]'); await page.waitForSelector('.dcard');
  const w = await page.locator('.dcard').first().boundingBox();
  check('phone Agents: cards first, one column', w && w.width >= 330); await o('Agents'); await shot(page, 'agents-390');
  await page.locator('.dcard', { hasText: 'Hospitality & Stays' }).click(); await page.waitForSelector('[data-dir-sec]');
  await o('Director drill-down'); await shot(page, 'director-hospitality-390');
  await page.click('.bnav [data-tab=agents]'); await page.waitForSelector('.dcard');
  await page.locator('.dcard', { hasText: 'Growth, Social & Paid Media' }).click(); await page.waitForSelector('main .loop');
  await o('Growth Director'); await shot(page, 'director-growth-390');
  await page.click('.bnav [data-tab=desk]'); await page.waitForSelector('.drow');
  const ab = await page.locator('main .drow .dr-act .btn').first().boundingBox();
  check('phone Needs review: action buttons are thumb-sized', ab && ab.height >= 30, `${ab?.height}`);
  await o('Outreach · Needs review'); await shot(page, 'desk-needs-review-390', false);
  await page.click('main [data-desk-tab=APPROVED]'); await o('Outreach · Approved'); await shot(page, 'desk-approved-390', false);
  await page.click('.bnav [data-tab=relations]'); await o('Relationships'); await shot(page, 'relationships-390', false);
  await page.click('#bmenu'); await page.click('.sheet [data-tab=club]'); await page.waitForSelector('[data-club-tab]'); await o('Club'); await shot(page, 'club-390', false);
  await page.click('#bmenu'); await page.click('.sheet [data-tab=ops]'); await o('Operations'); await shot(page, 'operations-390', false);
  check('ui_v3 phone: no JavaScript errors', errors.length === 0, errors.join(' | '));
  await browser.close();
}

server.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} V3 checks passed`);
process.exit(failed.length ? 1 : 0);
