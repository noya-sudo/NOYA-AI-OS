// HQ Command Centre acceptance (professional operating mode, 18-19 Oct): the seven top numbers, the pipeline with owner / next
// action / date / blocker, HQ Advisor's five recommendations and the approvals waiting for Adam, CEO work orders, Director
// scorecards, revenue and its reconciliation, and Admin → System health. Reads are live captures (tests/fixtures, git-ignored);
// every write is recorded to prove exactly what each button sends. Nothing here can send an email.
import http from 'node:http';
import { readFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { extname, join } from 'node:path';
import { chromium } from 'playwright-core';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const fx = (f) => (existsSync(`tests/fixtures/${f}.json`) ? JSON.parse(readFileSync(`tests/fixtures/${f}.json`, 'utf8')) : null);
const need = ['snapshot', 'overview', 'directory', 'insight', 'relationships', 'desk', 'directors', 'club', 'operations', 'advisor', 'weekly', 'ceo', 'network', 'command', 'health', 'integrity', 'studio'];
if (need.some((f) => !fx(f))) { console.log(`SKIP ui_command: live fixtures missing (${need.filter((f) => !fx(f)).join(', ')})`); process.exit(0); }
const F = Object.fromEntries(need.map((f) => [f, fx(f)]));
F.execution = fx('execution');
// 19 Oct capture of the Director cards and the email-ready reserve (Directors in priority order); the 16 Oct captures stay for the other suites
const AL = fx('agents_live');
if (AL) { F.directors = AL.directors; F.execution = { ...F.execution, queue: { ...(F.execution?.queue || {}), acquisition: AL.acquisition } }; }
mkdirSync('tests/out/command', { recursive: true });

const SNAP = { ceo: F.ceo, command: F.command, network: F.network, advisor: F.advisor, directors: F.directors, execution: F.execution, health: F.health, integrity: F.integrity };
const READS = {
  hq_dashboard: () => F.snapshot, hq_overview: () => F.overview, hq_directory: () => F.directory, hq_insight: () => F.insight, hq_relationships: () => F.relationships,
  hq_commercial: () => ({ generated_at: new Date().toISOString(), team: { members: [], routing: {} }, weights: {}, products: [], playbooks: [], signals: [], queue: [], partners: [], projects: [], supply_partners: {} }),
  hq_outreach_desk: () => F.desk, hq_operations: () => F.operations, hq_club: () => F.club, hq_weekly_review: () => F.weekly, hq_studio: () => F.studio,
  hq_cached: (b) => { const v = SNAP[b?.p_key] || (String(b?.p_key).startsWith('director:') ? { key: b.p_key.slice(9), sections: [] } : null);
    return v ? { ...v, _cache: { built_at: new Date(Date.now() - 120000).toISOString(), age_s: 120 } } : { ok: false, reason: 'UNKNOWN_KEY' }; },
  hq_cache_status: () => ({ generated_at: new Date().toISOString(), items: [], jobs: [] }), hq_timeline: () => ({ events: [], notes: [] }), hq_account: () => null,
  // dry-run import: the server's own rules (a row needs client, date, gross, currency, payment status and evidence)
  hq_revenue_import: (b) => {
    const rows = b?.p_rows || []; const valid = []; const errors = [];
    rows.forEach((r, i) => { const e = []; if (!r.client) e.push('client missing'); if (!/^\d{4}-\d\d-\d\d$/.test(r.date || '')) e.push('date missing'); if (!(Number(r.gross) > 0)) e.push('gross must be a positive amount');
      if (!/^[A-Z]{3}$/.test(r.currency || '')) e.push('currency must be a 3-letter code'); if (!['PAID', 'PART_PAID', 'PENDING'].includes(r.payment_status)) e.push('payment_status must be PAID, PART_PAID or PENDING');
      if (!r.evidence) e.push('evidence missing (invoice number, bank reference, contract or email)');
      if (e.length) errors.push({ row: i + 1, client: r.client, errors: e }); else valid.push({ row: i + 1, client: r.client, gross: Number(r.gross), currency: r.currency }); });
    const totals = {}; valid.forEach((v) => { totals[v.currency] = (totals[v.currency] || 0) + v.gross; });
    return { ok: !errors.length, applied: !!b?.p_apply && !errors.length, valid, errors, duplicates: [], totals };
  },
};
const WRITES = { hq_work_order: { ok: true, id: '00000000-0000-0000-0000-0000000000w1' }, hq_work_order_action: { ok: true }, hq_opportunity_plan: { ok: true },
  hq_recommendation_action: { ok: true, state: 'APPLIED' }, hq_advisor_seen: { ok: true },
  hq_studio_request: { ok: true, id: '00000000-0000-0000-0000-0000000000s1', level: 2 }, hq_studio_request_action: { ok: true } };

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.txt': 'text/plain', '.woff2': 'font/woff2', '.svg': 'image/svg+xml' };
const server = http.createServer((req, res) => {
  const p = join('dist', req.url === '/' ? 'index.html' : req.url.split('?')[0]);
  if (!existsSync(p) || !statSync(p).isFile()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': types[extname(p)] || 'application/octet-stream' }); res.end(readFileSync(p));
});
await new Promise((r) => server.listen(4176, r));

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
  const page = await (await browser.newContext({ viewport })).newPage(); const errors = []; const calls = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.route(`${SUPA}/**`, async (route) => {
    const url = route.request().url();
    if (url.includes('/auth/v1/token')) return route.fulfill({ json: session() });
    if (url.includes('/auth/v1/user')) return route.fulfill({ json: session().user });
    const m = url.match(/\/rest\/v1\/rpc\/([a-z_]+)/);
    if (m) { const body = route.request().postDataJSON?.() ?? null; calls.push({ fn: m[1], body });
      if (READS[m[1]]) return route.fulfill({ json: READS[m[1]](body) });
      if (WRITES[m[1]]) return route.fulfill({ json: WRITES[m[1]] });
      return route.fulfill({ status: 404, json: { message: 'not allowed in test' } }); }
    return route.fulfill({ status: 404, body: '' });
  });
  await page.goto('http://localhost:4176/');
  await page.fill('input[name=email]', 'adam.elshazly1012@gmail.com'); await page.fill('input[name=password]', 'test-password-not-real');
  await page.click('button[type=submit]'); await page.waitForSelector('.kpis'); await page.waitForSelector('#pipeline table'); await page.waitForTimeout(300);
  return { browser, page, errors, calls };
}
const last = (calls, fn) => [...calls].reverse().find((c) => c.fn === fn);
const txt = async (page, sel) => (await page.locator(sel).first().innerText()).replace(/\s+/g, ' ').trim();
const overflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
const C = F.command;

{
  const { browser, page, errors, calls } = await open({ width: 1440, height: 900 });
  // 1. The seven numbers, in Adam's order, each from a record.
  const labels = (await page.locator('.kpis .kl').allTextContents()).map((t) => t.trim());
  check('Top row: exactly the seven numbers Adam asked for, in order', JSON.stringify(labels) === JSON.stringify(['Actual revenue', 'Active projects', 'Open proposals', 'Meetings', 'Positive replies', 'Emails to send', 'Actions needing you']), labels.join(' | '));
  const kpi = async (i) => (await page.locator('.kpis .kpi').nth(i).innerText()).replace(/\s+/g, ' ');
  check('Top row: actual revenue is £0 (no record yet) and the stated £60,000 shows only as "to reconcile"', /£0/.test(await kpi(0)) && /£60,000 historical to reconcile/.test(await kpi(0)), await kpi(0));
  check('Top row: meetings and positive replies from the snapshot (2 and 2, last 30 days)', /^2 Meetings/i.test(await kpi(3)) && /^2 Positive replies/i.test(await kpi(4)));
  check('Top row: emails to send = approved Gmail drafts + Studio drafts due (2 + 2)', /^4 Emails to send 2 Gmail · 2 Studio · 2 later/i.test(await kpi(5)), await kpi(5));
  const acts = await page.locator('#needs .act').count();
  check('Top row: "Actions needing you" equals the rows in What needs you today', (await kpi(6)).startsWith(`${acts} `), `${await kpi(6)} vs ${acts} rows`);
  // 2. HQ Advisor: five slots and the approvals.
  const titles = (await page.locator('.advisor .adv-k').allTextContents()).map((t) => t.trim());
  check('Advisor: five daily recommendations in the fixed order', ['WHAT YOU SHOULD DO', 'BIGGEST BOTTLENECK', 'BEST OPPORTUNITY', 'AGENT TO CORRECT', 'WHAT SHOULD STOP'].every((t, i) => titles[i] === t), titles.join(' | '));
  check('Advisor: recommendations awaiting approval are listed with Approve / Decline', /Awaiting your approval · 4/i.test(await txt(page, '.recs')) && await page.locator('.recs [data-type="APPROVE"]').count() === 4);
  // 3. Pipeline: the 14 commercial stages, where business is lost, every live opportunity with its plan.
  check('Pipeline: 14 stages from Target to Paid (Lost / parked counted separately)', await page.locator('#pipeline .pst').count() === 14);
  const lost = await txt(page, '#pipeline p.small');
  check('Pipeline: "Where business is lost" names the lost / parked count and live opportunities without a next step', /105 lost or parked/.test(lost) && /every live opportunity has a next action and date|missing a next action or date/.test(lost), lost.slice(0, 160));
  const ever = await txt(page, '#pipeline .ever'); const CA = C.kpis?.canonical_all?.companies || {}; const M30 = C.kpis?.canonical_30?.messages || {};
  check('Pipeline: "now" per stage, plus ever reached (companies) and outreach messages from the one canonical model',
    /Where each company stands now/.test(await txt(page, '#pipeline header'))
      && ever.includes(`Contacted ${CA.contacted || 0} → Replied ${CA.replied || 0} → Positive ${CA.positive || 0} → Meeting ${CA.meetings || 0} → Brief ${CA.briefs || 0} → Proposal ${CA.proposals || 0} → Won ${CA.wins || 0}`)
      && ever.includes(`Outreach messages, last 30 days: ${M30.outreach || 0} (${M30.first || 0} first, ${M30.follow_ups || 0} follow-ups)`), ever);
  const rows = await page.locator('#pipeline tbody tr').count();
  check('Pipeline: every live opportunity listed with owner, next action, date and blocker', rows === C.opportunities.length && /CRUSH Agency/.test(await txt(page, '#pipeline tbody')), `${rows} rows`);
  check('Pipeline: an overdue next action is shown in red (The Arts Club, 30 Sep)', await page.locator('#pipeline tbody tr:has-text("The Arts Club") td.bad-text').count() === 1);
  await page.screenshot({ path: 'tests/out/command/dashboard-1440.png', fullPage: true });
  // 4. Plan an opportunity: owner, next action, date, blocker.
  await page.locator('#pipeline tbody tr:has-text("CRUSH Agency") [data-modal="opp-plan"]').click();
  await page.fill('#op-next', 'Send the concept, then book the call'); await page.fill('#op-blocker', 'Waiting for their production dates');
  await page.click('#m-ok'); await page.waitForTimeout(250);
  const plan = last(calls, 'hq_opportunity_plan')?.body || {};
  check('Plan: saves next action, date, owner and blocker for that opportunity', plan.p_opportunity === C.opportunities[0].opportunity_id && plan.p_next_action === 'Send the concept, then book the call'
    && plan.p_blocker === 'Waiting for their production dates' && /^\d{4}-\d\d-\d\d$/.test(plan.p_due) && plan.p_owner === 'Adam', JSON.stringify(plan));
  // 5. Approve a recommendation: a confirmation, then one call.
  await page.locator('.recs [data-type="APPROVE"]').first().click();
  check('Approve: confirmation explains what happens before anything changes', /Approving applies this now/.test(await txt(page, '.modal')));
  await page.click('#m-ok'); await page.waitForTimeout(250);
  const rec = last(calls, 'hq_recommendation_action')?.body || {};
  check('Approve: one call with the recommendation and APPROVE', rec.p_id === C.recommendations[0].id && rec.p_action === 'APPROVE', JSON.stringify(rec));

  // 6. Agents: work orders and scorecards.
  await page.click('[data-tab="agents"]'); await page.waitForSelector('.wo'); await page.waitForTimeout(200);
  const wo = await txt(page, '.wo');
  check('Work order: the Director, mission, target, deadline, priority and evidence-based status', /Brands & Production · P1 · target UK · due 30 Oct/.test(wo) && /Queued/i.test(wo) && /0 of 5 emails sent/.test(wo), wo.slice(0, 200));
  check('Work order: the specialist chain is shown (matching → email-ready → drafted → in review → sent → replies …)', /11 matching companies/.test(wo) && /2 email-ready/.test(wo) && /1 in your review/.test(wo));
  const sc = await page.locator('table.sc tbody tr').count();
  check('Scorecards: one row per acquisition Director (9)', sc === 9, `${sc}`);
  check('Scorecards: no reply rate on tiny samples ("n=" shown) and no ranking', await page.locator('table.sc td:has-text("n=")').count() === 9 && /No ranking yet/.test(await txt(page, '.dsec:has(table.sc)')));
  await page.click('[data-sc-win="all"]'); await page.waitForTimeout(150);
  check('Scorecards: the window switches to all time', /All time/.test(await txt(page, '.tabs.sm button.on')));
  check('Director cards: 7-day result includes briefs, and open work orders are shown on the card', /briefs/.test(await txt(page, '.dcard[data-director="BRANDS"]')) && /Queued: Open conversations with UK/.test(await txt(page, '.dcard[data-director="BRANDS"]')));
  await page.screenshot({ path: 'tests/out/command/agents-1440.png', fullPage: true });
  // 7. Issue a work order.
  await page.locator('.dsec:has(.wo-grid) [data-modal="work-order"]').first().click();
  await page.selectOption('#wo-dir', 'WEDDINGS'); await page.fill('#wo-mission', 'Destination wedding planners in the UK with Egypt-ready clients');
  await page.fill('#wo-target', 'wedding, UK'); await page.selectOption('#wo-metric', 'EMAILS_SENT'); await page.fill('#wo-goal', '4');
  await page.click('#m-ok'); await page.waitForTimeout(250);
  const iw = last(calls, 'hq_work_order')?.body || {};
  check('Issue work order: Director, mission, target, metric, number, deadline and priority are sent', iw.p_director === 'WEDDINGS' && iw.p_target === 'wedding, UK' && iw.p_metric === 'EMAILS_SENT' && iw.p_goal === 4
    && /^\d{4}-\d\d-\d\d$/.test(iw.p_deadline) && iw.p_priority === 'P2', JSON.stringify(iw));
  check('Issue work order: nothing is sent — the only write is hq_work_order', !calls.some((c) => /send|approve_draft|approve_email/.test(c.fn)));

  // 8. Revenue: actual revenue from records, and the historical reconciliation.
  await page.click('#nav-more'); await page.click('[data-tab="finance"]'); await page.waitForSelector('.hist');
  const hist = await txt(page, '.hist');
  check('Revenue: HISTORICAL REVENUE — TO BE RECONCILED with stated, reconciled and remaining amounts', /HISTORICAL REVENUE — TO BE RECONCILED/.test(hist) && /£60,000 stated/.test(hist) && /£0 reconciled from 0 records/.test(hist) && /£60,000 still to reconcile/.test(hist), hist.slice(0, 220));
  check('Revenue: the stated figure is never counted as revenue', /The stated figure is not counted as revenue/.test(hist) && /£0/.test(await txt(page, '.rv-grid .rv')));
  await page.screenshot({ path: 'tests/out/command/revenue-1440.png', fullPage: true });
  await page.click('[data-modal="revenue-import"]');
  await page.fill('#rv-text', 'client,date,gross,currency,payment_status,evidence\nExample Client,2026-03-14,12000,GBP,PAID,INV-001\nNo Evidence Ltd,2026-04-02,3000,GBP,PAID,');
  await page.click('#rv-check'); await page.waitForTimeout(250);
  check('Import: a row without evidence is refused and the Import button does not appear', /evidence missing/.test(await txt(page, '.modal')) && await page.locator('#m-ok').count() === 0);
  await page.fill('#rv-text', 'client,date,gross,currency,payment_status,evidence\nExample Client,2026-03-14,12000,GBP,PAID,INV-001');
  await page.click('#rv-check'); await page.waitForTimeout(250);
  check('Import: a valid row shows its total and can be imported', /1 rows ready · £12,000/.test(await txt(page, '.modal')) && await page.locator('#m-ok').count() === 1);
  await page.click('#m-ok'); await page.waitForTimeout(250);
  const imp = [...calls].filter((c) => c.fn === 'hq_revenue_import');
  check('Import: checked as a dry run first, then applied with the same rows', imp.length >= 3 && imp[imp.length - 1].body.p_apply === true && imp[imp.length - 2].body.p_apply === false && imp[imp.length - 1].body.p_rows[0].evidence === 'INV-001');

  // 9. System health (Admin): services, agents, AI calls, integrity.
  await page.click('[data-tab="system"]'); await page.waitForSelector('main .list .row');
  const svc = await txt(page, 'main .list');
  check('Health: Supabase, n8n, Gmail sync, Gmail import, Hunter, Serper, AI providers and Studio are each shown', ['Supabase', 'n8n workflows', 'Gmail sync', 'Gmail history import', 'Hunter', 'Serper', 'AI providers', 'Studio renderer'].every((s) => svc.includes(s)));
  check('Health: a workflow not running is named (Growth, Social & Paid Media, last run 26 Sep)', /1 of 18 agents behind schedule: Growth, Social & Paid Media/.test(svc), svc.slice(0, 300));
  check('Health: failure alerts and a model outage turn n8n and AI providers to Check, with the workflow named',
    /3 failure alerts in 7 days: 18 - NOYA Commercial Director: Daily Outreach v2, 12 - NOYA Outbound Email Executor v1/.test(svc)
    && /AI providers Check model unavailable on 2 runs in 3 days \(18 - NOYA Commercial Director: Daily Outreach v2\)/i.test(svc), svc.slice(0, 600));
  check('Health: integrity checks with counts and the automatic owner-name correction', /Follow-ups more than 2 days overdue/.test(await txt(page, 'main')) && /377 corrected automatically/.test(await txt(page, 'main')));
  check('Health: the Outreach Writer failures are listed', /18 - NOYA Commercial Director: Daily Outreach v2 \[PROVIDER_UNAVAILABLE\]/.test(await txt(page, 'main')));
  await page.screenshot({ path: 'tests/out/command/health-1440.png', fullPage: true });
  check('No browser errors (1440)', errors.length === 0, errors.slice(0, 3).join(' | '));
  await browser.close();
}
// 10. Destination Egypt mission and Studio (Adam, 19 Oct): Studio in the primary navigation, the Studio team under Agents with
// the Brief & Proposal Architect, the six Studio columns and nine create actions, and the compact mission panel on the Dashboard.
{
  const { browser, page, errors, calls } = await open({ width: 1440, height: 900 });
  const nav = (await page.locator('.nav-primary .nav-item > span:first-child').allTextContents()).map((t) => t.trim());
  check('Navigation: Studio is primary, between Outreach and Relationships', JSON.stringify(nav) === JSON.stringify(['Dashboard', 'Agents', 'Outreach', 'Studio', 'Relationships', 'Club', 'Operations']), nav.join(' | '));
  await page.waitForSelector('#mission');
  const tiles = (await page.locator('#mission .wk-t .l').allTextContents()).map((t) => t.trim());
  check('Mission panel: the nine numbers Adam asked for, in order', JSON.stringify(tiles) === JSON.stringify(['Qualified project opportunities', 'Email-ready', 'Contacted', 'Replied', 'Meetings', 'Briefs', 'Proposals', 'Projects won', 'Revenue']), tiles.join(' | '));
  const nums = (await page.locator('#mission .wk-t .n').allTextContents()).map((t) => t.trim());
  check('Mission panel: numbers come from the mission record (23 qualified, 14 email-ready, 9 contacted, 3 replied, £0 revenue)', JSON.stringify(nums) === JSON.stringify(['23', '14', '9', '3', '0', '0', '0', '0', '£0']), nums.join(' | '));
  const mission = await txt(page, '#mission');
  check('Mission panel: top opportunities only (5 shown, CRUSH first as an agency client project, Studio level and email state)', await page.locator('#mission tbody tr').count() === 5
    && /CRUSH Agency/.test(await txt(page, '#mission tbody tr:first-child')) && /Agency client project/.test(await txt(page, '#mission tbody tr:first-child')) && /Level 3/.test(await txt(page, '#mission tbody tr:first-child')) && /Verified email/i.test(await txt(page, '#mission tbody tr:first-child')));
  check('Mission panel: no deal value anywhere (the only money is recorded revenue)', (mission.match(/£/g) || []).length === 1);
  check('Mission panel: research progress by programme, not discovery volume', /Brand \/ production \/ marketing 7 of 20/.test(mission) && /Weddings \/ events 7 of 20/.test(mission));
  await page.click('[data-mission-all]'); await page.waitForTimeout(150);
  check('Mission panel: the full top list opens on request', await page.locator('#mission tbody tr').count() === 7);
  await page.locator('#mission').screenshot({ path: 'tests/out/command/mission-1440.png' });

  await page.click('.nav-primary [data-tab="agents"]'); await page.waitForSelector('.studio-role'); await page.waitForTimeout(150);
  check('Agents: the eight Studio roles are shown', await page.locator('.studio-role').count() === 8);
  check('Agents: the Brief & Proposal Architect is the main Studio employee', /Brief & Proposal Architect/.test(await txt(page, '.studio-role.main')) && /Main/i.test(await txt(page, '.studio-role.main')));
  await page.click('.studio-role.main'); await page.waitForSelector('.modal');
  const arch = await txt(page, '.modal');
  check('Architect: current work, briefs, concepts ready, proposals, needs Adam and last outputs', ['Current work', 'Briefs being produced', 'Concepts ready', 'Proposals', 'Needs you', 'Last outputs'].every((s) => arch.toLowerCase().includes(s.toLowerCase())) && /CRUSH x NOYA brief/.test(arch), arch.slice(0, 200));
  await page.screenshot({ path: 'tests/out/command/architect-1440.png' });
  await page.click('.modal [data-go="studio"]'); await page.waitForSelector('.kanban');
  const cols = (await page.locator('.kanban .kh span').allTextContents()).map((t) => t.trim());
  check('Studio: Needs brief, Drafting, Needs review, Approved, Sent, Superseded', JSON.stringify(cols) === JSON.stringify(['Needs brief', 'Drafting', 'Needs review', 'Approved', 'Sent', 'Superseded']), cols.join(' | '));
  const counts = (await page.locator('.kanban .kh b').allTextContents()).map((t) => t.trim());
  check('Studio: column counts from the Studio record (2 · 1 · 3 · 1 · 0 · 24)', JSON.stringify(counts) === JSON.stringify(['2', '1', '3', '1', '0', '24']), counts.join(' | '));
  check('Studio: the nine create actions and the three levels', await page.locator('.sacts [data-modal="studio-new"]').count() === 9 && await page.locator('.lvls .lvl').count() === 3);
  check('Studio: a held document shows why it is held', /Held until Level 3/.test(await txt(page, '.kanban')));
  await page.screenshot({ path: 'tests/out/command/studio-1440.png', fullPage: true });
  await page.click('.sacts [data-type="ONE_PAGE_CONCEPT"]'); await page.waitForSelector('#sn-company');
  await page.fill('#sn-company', 'Nobody Real Ltd'); await page.click('#m-ok'); await page.waitForTimeout(150);
  check('Create: an unknown company is refused before anything is requested', /Pick the company from the list/.test(await txt(page, '.modal')) && !calls.some((c) => c.fn === 'hq_studio_request'));
  await page.fill('#sn-company', 'CRUSH Agency'); await page.fill('#sn-note', 'Two shoot days at Giza for a beauty client'); await page.click('#m-ok'); await page.waitForTimeout(250);
  const req = last(calls, 'hq_studio_request')?.body || {};
  check('Create: one request with the kind, the company and the note', req.p_kind === 'ONE_PAGE_CONCEPT' && req.p_company === '2e46b475-7f3b-4461-815f-6b97475df90e' && req.p_note === 'Two shoot days at Giza for a beauty client', JSON.stringify(req));
  await page.locator('.kcol .sd.warm [data-modal="studio-new"]').first().click(); await page.waitForSelector('#sn-company');
  check('Create from a warm conversation: the company is pre-filled and the level is the one earned (brief)', await page.inputValue('#sn-company') === 'Greycoat Lumleys' && /Create brief/i.test(await txt(page, '.modal h3')));
  await page.click('.modal [data-close]'); await page.waitForTimeout(100);
  await page.click('[data-studio-cancel]'); await page.waitForTimeout(250);
  const can = last(calls, 'hq_studio_request_action')?.body || {};
  check('Cancel request: one call with the request and CANCEL', can.p_id === '00000000-0000-0000-0000-00000000r001' && can.p_action === 'CANCEL', JSON.stringify(can));
  check('Studio: nothing is sent from Studio', !calls.some((c) => /send|approve_draft|approve_email/.test(c.fn)));
  check('No browser errors (Studio, 1440)', errors.length === 0, errors.slice(0, 3).join(' | '));
  await browser.close();
}
{
  const { browser, page, errors } = await open({ width: 390, height: 844 });
  check('Phone 390: dashboard fits the screen (no sideways scroll)', (await overflow(page)) <= 1, `${await overflow(page)}px`);
  await page.screenshot({ path: 'tests/out/command/dashboard-390.png', fullPage: true });
  await page.click('.bnav [data-tab="agents"]'); await page.waitForSelector('.wo'); await page.waitForTimeout(200);
  check('Phone 390: Agents with work orders and scorecards fits the screen', (await overflow(page)) <= 1, `${await overflow(page)}px`);
  await page.screenshot({ path: 'tests/out/command/agents-390.png', fullPage: true });
  await page.click('#bmenu'); await page.click('.sheet [data-tab="studio"]'); await page.waitForSelector('.kanban'); await page.waitForTimeout(150);
  check('Phone 390: Studio is one tap from More and fits the screen', (await overflow(page)) <= 1, `${await overflow(page)}px`);
  await page.screenshot({ path: 'tests/out/command/studio-390.png', fullPage: true });
  check('No browser errors (390)', errors.length === 0, errors.slice(0, 3).join(' | '));
  await browser.close();
}
server.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed${failed.length ? ` — ${failed.length} failed` : ''}`);
process.exit(failed.length ? 1 : 0);
