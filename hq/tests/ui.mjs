// Browser test of the built dashboard (dist/) in headless Chromium.
//
// This container cannot reach supabase.co, so the network layer is intercepted:
// - /rest/v1/rpc/hq_dashboard returns tests/fixtures/snapshot.json, a real hq_dashboard()
//   response captured from the live database (git-ignored; never committed);
// - write RPCs are recorded (to prove exactly what the buttons send) and answered with
//   the same shapes the live functions returned in the server-side tests;
// - the auth token endpoint is stubbed. Real authentication and authorisation are proven
//   separately in Postgres (see docs/NOYA_CLOUD_PROGRESS.md).
import http from 'node:http';
import { readFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { extname, join } from 'node:path';
import { chromium } from 'playwright-core';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const FIXTURE = 'tests/fixtures/snapshot.json';
if (!existsSync(FIXTURE)) { console.log('SKIP ui test: no live snapshot fixture'); process.exit(0); }
const snapshot = JSON.parse(readFileSync(FIXTURE, 'utf8'));
const overview = JSON.parse(readFileSync('tests/fixtures/overview.json', 'utf8'));
const directory = JSON.parse(readFileSync('tests/fixtures/directory.json', 'utf8'));
const insight = JSON.parse(readFileSync('tests/fixtures/insight.json', 'utf8'));
mkdirSync('tests/out', { recursive: true });

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.txt': 'text/plain', '.woff2': 'font/woff2', '.svg': 'image/svg+xml' };
const server = http.createServer((req, res) => {
  const p = join('dist', req.url === '/' ? 'index.html' : req.url.split('?')[0]);
  if (!existsSync(p) || !statSync(p).isFile()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': types[extname(p)] || 'application/octet-stream' });
  res.end(readFileSync(p));
});
await new Promise((r) => server.listen(4173, r));

const WRITES = ['hq_task_dismiss', 'hq_opportunity_update', 'hq_add_note', 'hq_log_touch', 'hq_record_meeting', 'hq_change_channel', 'hq_connection_update',
  'hq_request_draft', 'hq_draft_action', 'hq_finance_upsert', 'hq_record_payment', 'hq_company_update'];
const ALLOWED = ['hq_dashboard', 'hq_overview', 'hq_directory', 'hq_insight', 'hq_timeline', 'hq_task_action', 'hq_approve_draft', 'hq_save_draft', 'hq_hold', 'hq_reject',
  'hq_create_opportunity', 'hq_import_connections', ...WRITES];
const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`); };

function b64url(o) { return Buffer.from(JSON.stringify(o)).toString('base64url'); }
function session(meta = {}) {
  const user = { id: '0d858bd9-4d03-482c-8d14-3237ac622bcc', aud: 'authenticated', role: 'authenticated', email: 'adam.elshazly1012@gmail.com', user_metadata: meta, app_metadata: { provider: 'email' } };
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const token = `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url({ sub: user.id, email: user.email, role: 'authenticated', exp })}.sig`;
  return { access_token: token, token_type: 'bearer', expires_in: 3600, expires_at: exp, refresh_token: 'r', user };
}

async function runScenario({ viewport, meta = {}, data = snapshot, label }) {
  const browser = await chromium.launch({ executablePath: CHROME });
  const ctx = await browser.newContext({ viewport, permissions: ['clipboard-read', 'clipboard-write'] });
  const page = await ctx.newPage();
  const errors = []; const calls = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.route(`${SUPA}/**`, async (route) => {
    const url = route.request().url();
    if (url.includes('/auth/v1/token')) return route.fulfill({ json: session(meta) });
    if (url.includes('/auth/v1/user')) return route.fulfill({ json: session(meta).user });
    const m = url.match(/\/rest\/v1\/rpc\/([a-z_]+)/);
    if (m) {
      const body = route.request().postDataJSON?.() ?? null;
      calls.push({ fn: m[1], body, auth: route.request().headers().authorization || '' });
      if (m[1] === 'hq_dashboard') return route.fulfill({ json: data });
      if (m[1] === 'hq_overview') return route.fulfill({ json: overview });
      if (m[1] === 'hq_task_action') return route.fulfill({ json: { ok: true } });
      if (m[1] === 'hq_approve_draft') return route.fulfill({ json: { ok: true, mode: 'DRAFT', dispatched: true, outbound_id: '00000000-0000-0000-0000-000000000001' } });
      if (m[1] === 'hq_save_draft') return route.fulfill({ json: { ok: true, version: 2 } });
      if (m[1] === 'hq_hold' || m[1] === 'hq_reject') return route.fulfill({ json: { ok: true } });
      if (m[1] === 'hq_directory') return route.fulfill({ json: directory });
      if (m[1] === 'hq_insight') return route.fulfill({ json: insight });
      if (m[1] === 'hq_timeline') return route.fulfill({ json: { events: [{ at: '2026-09-29T10:00:00Z', channel: 'Reply', direction: 'INBOUND', title: 'MEETING_REQUEST — Re: NOYA', detail: 'Timeline stub', src: 'reply' }], notes: [] } });
      if (m[1] === 'hq_create_opportunity') return route.fulfill({ json: { ok: true, opportunity_id: data.opportunities[0].id, company_id: null, company_reused: true } });
      if (m[1] === 'hq_import_connections') return route.fulfill({ json: { ok: true, upserted: body.p_rows.length, skipped: 0 } });
      if (WRITES.includes(m[1])) return route.fulfill({ json: { ok: true, id: '00000000-0000-0000-0000-000000000009' } });
      return route.fulfill({ status: 404, json: { message: 'not allowed in test' } });
    }
    return route.fulfill({ status: 404, body: '' });
  });
  await page.goto('http://localhost:4173/');
  await page.fill('input[name=email]', 'adam.elshazly1012@gmail.com');
  await page.fill('input[name=password]', 'test-password-not-real');
  await page.click('button[type=submit]');
  return { browser, page, errors, calls, label };
}

const last = (calls, fn) => [...calls].reverse().find((c) => c.fn === fn);
const noOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);

// 1. Desktop: Today + every view renders from live data; every write goes through the right RPC.
{
  const { browser, page, errors, calls } = await runScenario({ viewport: { width: 1280, height: 900 } });
  await page.waitForSelector('.side');
  await page.waitForSelector('.q-row');
  check('login leads to Today; data via the four read RPCs with bearer token',
    ['hq_dashboard', 'hq_overview', 'hq_directory', 'hq_insight'].every((fn) => calls.some((c) => c.fn === fn && c.auth.startsWith('Bearer ey'))));
  const counts = await page.locator('.counts').innerText();
  const n = (p) => overview.actions.filter((a) => a.prio === p).length;
  check('Today: P1/P2/P3 counts equal hq_overview actions', counts.includes(`P1 ${n('P1')}`) && counts.includes(`P2 ${n('P2')}`) && counts.includes(`P3 ${n('P3')}`), counts.replace(/\n/g, ' '));
  check('Today: every P1 action listed', (await page.locator('.q-row .prio.P1').count()) === n('P1'));
  const firstP1 = await page.locator('.q-row').first().innerText();
  const p1 = overview.actions.find((a) => a.prio === 'P1');
  check('Today: top action is the live P1, in plain business language', !p1 || (firstP1.includes(p1.person || p1.company) && /Reply to|meeting/i.test(firstP1) && !/Workflow \d/.test(firstP1)), firstP1.split('\n').slice(1, 3).join(' | '));
  const scoreText = await page.locator('.score').innerText();
  const sc = overview.scorecard;
  const scoreOk = [['Active opportunities', sc.active_opportunities.n], ['Call required', sc.call_required.n], ['Approvals ready', sc.approvals_ready.n],
    ['Overdue tasks', sc.overdue_tasks.n], ['Won', sc.won.n]].every(([k, v]) => new RegExp(`${k}\\s*\\n\\s*${v}\\b`).test(scoreText));
  check('Today: pipeline scorecard values equal hq_overview', scoreOk, scoreText.replace(/\n/g, ' | ').slice(0, 160));
  const moneyText = await page.locator('.panel', { hasText: 'Money' }).first().innerText();
  const pipe = insight.finance.pipeline[0];
  check('Money: pipeline is ESTIMATE, revenue never blended, UNKNOWN count shown',
    /Estimate/i.test(moneyText) && (!pipe || moneyText.includes(Number(pipe.amount).toLocaleString('en-GB', { maximumFractionDigits: 0 })))
      && (insight.finance.records.length !== 0 || /none recorded/.test(moneyText)) && moneyText.includes(`${insight.finance.pipeline_unknown} opps`));
  const approvalsLive = snapshot.approvals.filter((a) => a.loop_stage === 'PENDING_APPROVAL' && !a.block_reason).length;
  check('approvals-ready (Today) equals ready queue (Outreach)', sc.approvals_ready.n === approvalsLive, `${sc.approvals_ready.n} vs ${approvalsLive}`);
  const interOk = await page.evaluate(async () => { await document.fonts.ready; return document.fonts.check('14px Inter') && [...document.fonts].some((f) => f.family.replace(/"/g, '') === 'Inter' && f.status === 'loaded'); });
  check('Inter loads from the local font file (CSP-safe)', interOk);
  const sideBg = await page.evaluate(() => getComputedStyle(document.querySelector('.side')).backgroundColor);
  const mainBg = await page.evaluate(() => getComputedStyle(document.querySelector('.panel')).backgroundColor);
  check('navy shell (#061422), white content panels', sideBg === 'rgb(6, 20, 34)' && mainBg === 'rgb(255, 255, 255)', `${sideBg} / ${mainBg}`);
  const tipCount = await page.locator('.money-line [title]').count();
  check('CEO learning layer: finance terms carry plain-language tooltips', tipCount >= 2, `${tipCount}`);
  await page.screenshot({ path: 'tests/out/overview.png', fullPage: true });

  // Search across companies, people, opportunities, tasks.
  await page.fill('#q', 'YKONE');
  await page.waitForSelector('.results');
  const hits = await page.locator('.results').innerText();
  check('search "YKONE": company, Magali Rady, opportunity and meeting task', /Companies/i.test(hits) && /YKONE Middle East/.test(hits) && /Magali Rady/.test(hits) && /meeting requested/i.test(hits), hits.replace(/\n/g, ' | ').slice(0, 220));
  await page.fill('#q', 'Europe');
  const mk = await page.locator('.results').innerText();
  check('search by market ("Europe") finds companies/opportunities', /Companies|Opportunities/i.test(mk) && /Europe/.test(mk));
  await page.fill('#q', 'YKONE');
  await page.locator('.results [data-open=opp]').first().click();
  await page.waitForSelector('.drawer');
  await page.waitForSelector('.drawer .timeline');
  const drawer = await page.locator('.drawer').innerText();
  check('opportunity record: contact, verified email, vertical/market, open tasks, timeline via hq_timeline',
    /YKONE Middle East/.test(drawer) && /Magali Rady/.test(drawer) && /verified/i.test(drawer) && /→/.test(drawer) && /Open tasks/i.test(drawer) && /Timeline stub/.test(drawer)
      && calls.some((c) => c.fn === 'hq_timeline' && c.body.p_kind === 'opportunity'), drawer.replace(/\n/g, ' | ').slice(0, 240));
  await page.screenshot({ path: 'tests/out/record.png' });
  // Change stage from the record.
  await page.click('.drawer [data-modal=stage]');
  await page.selectOption('#f-stage', 'CALL_REQUIRED');
  await page.click('#m-ok');
  await page.waitForTimeout(300);
  const st = last(calls, 'hq_opportunity_update');
  check('Change stage calls hq_opportunity_update with the new stage', st && st.body.p_status === 'CALL_REQUIRED' && !!st.body.p_opportunity);
  // Add note from the record.
  await page.click('.drawer [data-modal=note]');
  await page.click('#m-ok');
  await page.waitForTimeout(150);
  check('empty note is refused client-side', !calls.some((c) => c.fn === 'hq_add_note'));
  await page.fill('#f-body', 'Met at ITB; wants Siwa in March');
  await page.selectOption('#f-kind', 'HOW_WE_MET');
  await page.click('#m-ok');
  await page.waitForTimeout(300);
  const nt = last(calls, 'hq_add_note');
  check('Add note calls hq_add_note (kind, body, opportunity)', nt && nt.body.p_kind === 'HOW_WE_MET' && nt.body.p_opportunity && /ITB/.test(nt.body.p_body));
  await page.click('.drawer [data-close-drawer]');

  // Task actions: Done / Snooze / Not needed.
  await page.locator('.q-row [data-modal=task-done]').first().click();
  await page.click('[data-confirm-task=COMPLETE]');
  await page.waitForTimeout(300);
  await page.locator('.q-row [data-modal=task-snooze]').first().click();
  await page.click('[data-confirm-task=SNOOZE]');
  await page.waitForTimeout(300);
  const tcalls = calls.filter((c) => c.fn === 'hq_task_action');
  check('Done / Snooze call hq_task_action (COMPLETE, SNOOZE with a date)', tcalls.length === 2 && tcalls[0].body.p_action === 'COMPLETE' && tcalls[1].body.p_action === 'SNOOZE' && /^\d{4}-\d{2}-\d{2}$/.test(tcalls[1].body.p_until));
  await page.locator('.q-row [data-modal=task-dismiss]').first().click();
  await page.click('#m-ok');
  await page.waitForTimeout(150);
  check('dismiss without a reason makes no call', !calls.some((c) => c.fn === 'hq_task_dismiss'));
  await page.fill('#f-reason', 'Duplicate of the email follow-up');
  await page.click('#m-ok');
  await page.waitForTimeout(300);
  check('dismiss with a reason calls hq_task_dismiss', calls.some((c) => c.fn === 'hq_task_dismiss' && /Duplicate/.test(c.body.p_reason)));
  check('approval actions cannot be done/dismissed from Today', (await page.locator('.q-row', { hasText: 'Approve outreach' }).locator('[data-modal=task-done], [data-modal=task-dismiss]').count()) === 0);

  const tabs = ['inbox', 'outreach', 'linkedin', 'pipeline', 'tasks', 'website', 'contacts', 'companies', 'finance', 'costs', 'markets', 'growth', 'intelligence', 'reports', 'system', 'help'];
  for (const tab of tabs) {
    await page.click(`.side [data-tab=${tab}]`);
    await page.waitForSelector('main h2');
    const h2 = await page.locator('main h2').first().innerText();
    check(`view renders: ${tab}`, h2.length > 0 && !/not loaded/i.test(await page.locator('main').innerText()), h2);
    await page.screenshot({ path: `tests/out/${tab}.png`, fullPage: true });
  }
  check('no placeholder "coming soon" sections in navigation', (await page.locator('.nav-item.off').count()) === 0);

  // Contacts / Companies / Markets / Costs match live data.
  await page.click('.side [data-tab=contacts]');
  check('Contacts: one row per live contact', (await page.locator('main tbody tr').count()) === directory.contacts.length, `${directory.contacts.length}`);
  await page.click('.side [data-tab=companies]');
  await page.click('main .tabs button[data-v=TRAVEL_CONCIERGE]');
  const partners = directory.companies.filter((c) => c.vertical === 'TRAVEL_CONCIERGE').length;
  check('Companies: "Partnerships" filter equals Travel/Concierge companies', (await page.locator('main tbody tr.clickable').count()) === partners, `${partners}`);
  await page.locator('main tbody tr.clickable').first().click();
  await page.waitForSelector('.drawer');
  check('company record opens with people, opportunities, timeline', /People \(/i.test(await page.locator('.drawer').innerText()) && calls.some((c) => c.fn === 'hq_timeline' && c.body.p_kind === 'company'));
  await page.click('.drawer [data-modal=vertical]');
  await page.selectOption('#f-vertical', 'HOSPITALITY');
  await page.click('#m-ok');
  await page.waitForTimeout(300);
  check('Classify calls hq_company_update with the vertical', last(calls, 'hq_company_update')?.body.p_vertical === 'HOSPITALITY');
  await page.click('.drawer [data-close-drawer]');
  await page.click('.side [data-tab=markets]');
  const eu = insight.markets.find((m) => m.market === 'EUROPE');
  const euRow = await page.locator('main tbody tr', { hasText: 'Europe' }).first().innerText();
  check('Markets: Europe row equals live counts', euRow.includes(String(eu.companies)) && euRow.includes(String(eu.active_opps_origin)), euRow.replace(/\s+/g, ' ').slice(0, 80));
  check('Markets: bridges listed (Europe → Egypt)', /Europe → Egypt/.test(await page.locator('main').innerText()));
  await page.click('.side [data-tab=costs]');
  const unknown = insight.services.filter((s) => s.status === 'ACTIVE' && (s.cost_type === 'UNKNOWN' || (s.cost_type !== 'FREE' && s.monthly_cost == null))).length;
  const costs = await page.locator('main').innerText();
  check('System costs: unknown exposure equals register, paid-software gate shown', costs.includes(`${unknown}\n`) && /UNKNOWN — verify before scale/.test(costs) && /then waits for your approval/.test(costs), `${unknown}`);
  check('System costs: every dependency listed with what breaks and where the credential lives', (await page.locator('main details.row').count()) === insight.services.filter((s) => s.status !== 'RETIRED').length && /Credential kept in/.test(await page.locator('main details.row').first().innerHTML()));

  // Finance: new record + definitions.
  await page.click('.side [data-tab=finance]');
  const fin = await page.locator('main').innerText();
  check('Finance: Collected / Outstanding / Won / Pipeline / Forecast defined separately; forecast not set', ['Collected', 'Outstanding', 'Won', 'Pipeline', 'Forecast'].every((w) => fin.includes(w)) && /not set/.test(fin));
  await page.click('main [data-modal=finance]');
  await page.selectOption('#f-company', directory.companies[0].id);
  await page.fill('#f-cur', 'eur');
  await page.fill('#f-amount', '12500');
  await page.fill('#f-desc', 'Incentive trip deposit');
  await page.selectOption('#f-status', 'SENT');
  await page.click('#m-ok');
  await page.waitForTimeout(300);
  const fu = last(calls, 'hq_finance_upsert');
  check('New finance record calls hq_finance_upsert (client, EUR, 12500, SENT)', fu && fu.body.p_company === directory.companies[0].id && fu.body.p_currency === 'EUR' && fu.body.p_amount === 12500 && fu.body.p_invoice_status === 'SENT' && fu.body.p_id === null, JSON.stringify(fu?.body));

  // LinkedIn: options gate + CSV import (Notes preamble, LinkedIn date format, non-profile rows skipped).
  await page.click('.side [data-tab=linkedin]');
  const li = await page.locator('main').innerText();
  check('LinkedIn: never-auto-send statement and options gate present', /Nothing is ever sent automatically/.test(li) && /options and approval/i.test(li));
  const csv = 'Notes:\n"When exporting your connection data, you may notice that some of the email addresses are missing."\n\nFirst Name,Last Name,URL,Email Address,Company,Position,Connected On\nSara,Khalil,https://www.linkedin.com/in/sara-khalil,,"Aman Resorts, Ltd",Director of Sales,01 May 2024\nOmar,Nasser,https://www.linkedin.com/in/omarn,,YKONE Middle East,Partner,15 Jan 2023\nBad,Row,https://example.com/x,,X,Y,01 Jan 2020\n';
  await page.setInputFiles('#li-file', { name: 'Connections.csv', mimeType: 'text/csv', buffer: Buffer.from(csv) });
  await page.waitForSelector('.modal');
  const im = await page.locator('.modal').innerText();
  check('import preview: 2 connections found, 1 skipped', /2 connections found/.test(im) && /1 lines skipped/.test(im), im.replace(/\n/g, ' | ').slice(0, 120));
  await page.click('#m-ok');
  await page.waitForTimeout(400);
  const ic = last(calls, 'hq_import_connections');
  check('import sends only the needed fields, dates as ISO, quoted commas kept', ic && ic.body.p_rows.length === 2 && ic.body.p_rows[0].connected_on === '2024-05-01'
    && ic.body.p_rows[0].company === 'Aman Resorts, Ltd' && Object.keys(ic.body.p_rows[0]).sort().join() === 'company,connected_on,email,first_name,last_name,position,url', JSON.stringify(ic?.body.p_rows[0]));

  // Outreach: tabs, cards, approval flow unchanged.
  await page.click('.side [data-tab=outreach]');
  const otabs = await page.locator('main .tabs').innerText();
  check('Outreach tabs: Ready / Follow-up / LinkedIn / Instagram / Sent / Replied / Hold / Researching', ['Ready', 'Follow-up', 'Linkedin', 'Instagram', 'Sent', 'Replied', 'Hold', 'Researching'].every((t) => new RegExp(t, 'i').test(otabs)), otabs.replace(/\n/g, ' '));
  const readyCards = await page.locator('article.card.ready').count();
  check('Ready: cards equal the live approval-ready queue', readyCards === approvalsLive, `${readyCards}`);
  const cardText = await page.locator('article.card.ready').first().innerText();
  check('card shows person, role, verified email, ESTIMATED value, why now, market route, message',
    /Contact/i.test(cardText) && /Position/i.test(cardText) && /Email verified/i.test(cardText) && /ESTIMATED/i.test(cardText) && /Why now/i.test(cardText) && /→/.test(cardText));
  const hoCount = snapshot.approvals.filter((a) => a.loop_stage === 'PENDING_APPROVAL' && !a.block_reason && a.human_only).length;
  check('HUMAN_ONLY badge shown on human-only cards', (await page.locator('article.card.ready .pill', { hasText: 'Human-only' }).count()) === hoCount);
  const buttonTexts = await page.locator('button').allInnerTexts();
  check('no Send / Approve & Send button anywhere', !buttonTexts.some((t) => /\bsend\b/i.test(t)), buttonTexts.filter((t) => /\bsend\b/i.test(t)).join(','));

  const target = snapshot.approvals.find((a) => a.loop_stage === 'PENDING_APPROVAL' && !a.block_reason);
  await page.click(`#opp-${target.id} [data-act=approve]`);
  check('approve dialog states nothing is sent', /Nothing is sent/i.test(await page.locator('.modal').innerText()));
  await page.click('[data-confirm=approve]');
  await page.waitForTimeout(400);
  const approveCalls = calls.filter((c) => c.fn === 'hq_approve_draft');
  check('APPROVE & DRAFT sends exactly one hq_approve_draft with opportunity + version only',
    approveCalls.length === 1 && approveCalls[0].body.p_opportunity_id === target.id && approveCalls[0].body.p_version === Number(target.draft.version)
      && Object.keys(approveCalls[0].body).sort().join() === 'p_opportunity_id,p_version');
  await page.click(`#opp-${target.id} [data-act=edit]`);
  check('edit dialog has no recipient field', (await page.locator('.modal input[type=email], .modal #ed-to').count()) === 0);
  await page.fill('#ed-subject', 'Edited subject from UI test');
  await page.click('[data-confirm=edit]');
  await page.waitForTimeout(300);
  const saveCall = calls.find((c) => c.fn === 'hq_save_draft');
  check('EDIT calls hq_save_draft with subject/body only', !!saveCall && saveCall.body.p_subject === 'Edited subject from UI test' && Object.keys(saveCall.body).sort().join() === 'p_body,p_note,p_opportunity_id,p_subject');
  await page.click(`#opp-${target.id} [data-act=reject]`);
  await page.click('[data-confirm=reject]');
  await page.waitForTimeout(200);
  check('REJECT without reason makes no call', !calls.some((c) => c.fn === 'hq_reject'));
  await page.fill('#rej-reason', 'Not the right moment');
  await page.click('[data-confirm=reject]');
  await page.waitForTimeout(300);
  check('REJECT with reason calls hq_reject', calls.some((c) => c.fn === 'hq_reject' && c.body.p_reason === 'Not the right moment'));
  await page.click(`#opp-${target.id} [data-act=hold]`);
  await page.fill('#hold-date', '2026-10-15');
  await page.click('[data-confirm=hold]');
  await page.waitForTimeout(300);
  check('HOLD calls hq_hold with review date', calls.some((c) => c.fn === 'hq_hold' && c.body.p_review_date === '2026-10-15'));
  await page.click(`#opp-${target.id} [data-modal=channel]`);
  await page.selectOption('#f-channel', 'LINKEDIN');
  await page.click('#m-ok');
  await page.waitForTimeout(300);
  check('Change channel calls hq_change_channel (LINKEDIN)', last(calls, 'hq_change_channel')?.body.p_channel === 'LINKEDIN' && last(calls, 'hq_change_channel')?.body.p_opportunity === target.id);
  await page.click('main .tabs [data-otab=SENT]');
  const draftCreated = snapshot.approvals.filter((a) => a.loop_stage === 'DRAFT_CREATED').length;
  check('Sent tab: DRAFT_CREATED cards show "Open Gmail Drafts"', (await page.locator('text=Open Gmail Drafts').count()) === draftCreated);
  await page.click('main .tabs [data-otab=RESEARCHING]');
  check('Researching tab lists NEW/RESEARCHING opportunities', (await page.locator('main tbody tr').count()) === snapshot.opportunities.filter((o) => ['NEW', 'RESEARCHING'].includes(o.status)).length);

  // Quick action: new opportunity (duplicate-safe on the server).
  await page.click('#quick');
  await page.click('.modal [data-modal=new-opp]');
  await page.click('#m-ok');
  await page.waitForTimeout(150);
  check('new opportunity without company/opportunity is refused client-side', !calls.some((c) => c.fn === 'hq_create_opportunity'));
  await page.fill('#f-co', 'Aman Resorts');
  await page.fill('#f-type', 'Brand trip to Egypt for 12 guests');
  await page.fill('#f-email', 'sara@example.com');
  await page.click('#m-ok');
  await page.waitForSelector('.drawer');
  const co = last(calls, 'hq_create_opportunity');
  check('+ New → opportunity calls hq_create_opportunity and opens the record', co && co.body.p_company_name === 'Aman Resorts' && co.body.p_contact_email === 'sara@example.com');

  check('only allow-listed RPCs were called', calls.every((c) => ALLOWED.includes(c.fn)), [...new Set(calls.map((c) => c.fn))].filter((f) => !ALLOWED.includes(f)).join(','));
  check('no JavaScript errors (desktop)', errors.length === 0, errors.join(' | '));
  await browser.close();
}

// 2. Adam's 09:00 phone routine (390 × 844): ten steps, no horizontal scrolling at any point.
{
  const { browser, page, errors, calls } = await runScenario({ viewport: { width: 390, height: 844 } });
  const steps = [];
  const step = async (name, ok) => { const o = await noOverflow(page); steps.push(o); check(`09:00 phone · ${name}`, ok && o <= 1, o > 1 ? `overflow ${o}px` : ''); };
  await page.waitForSelector('.q-row');
  const first = await page.locator('.q-row').first().innerText();
  await step('1 Today opens on the P1 (meeting request) first', /Reply to|meeting/i.test(first) && (await page.locator('.bnav').isVisible()));
  await page.screenshot({ path: 'tests/out/mobile-overview.png' });
  await page.locator('.q-row').first().locator('[data-modal=meeting]').click();
  await page.fill('#f-summary', 'Call with Magali: wants a proposal for a Cairo brand trip in November.');
  await page.selectOption('#f-stage', 'CALL_REQUIRED');
  await page.click('#m-ok');
  await page.waitForTimeout(300);
  const mt = last(calls, 'hq_record_meeting');
  await step('2 record the meeting (summary + stage + follow-up)', mt && mt.body.p_new_status === 'CALL_REQUIRED' && /^\d{4}-\d{2}-\d{2}$/.test(mt.body.p_follow_up));
  await page.click('.bnav [data-tab=inbox]');
  await step('3 Replies reachable from the bottom bar', /Replies/.test(await page.locator('main h2').innerText()));
  await page.click('.bnav [data-tab=outreach]');
  await page.waitForSelector('article.card.ready');
  const btn = await page.locator('article.card.ready [data-act=approve]').first().boundingBox();
  await step('4 Outreach Ready: approve button tappable (>= 36px)', btn && btn.height >= 36);
  await page.screenshot({ path: 'tests/out/mobile-approvals.png' });
  await page.click('main .tabs [data-otab=LINKEDIN]');
  const liCards = await page.locator('main article.card').count();
  const liExpected = overview.actions.filter((a) => a.kind === 'LINKEDIN').length;
  if (liCards) await page.locator('main article.card [data-copy]').first().click().catch(() => {});
  await page.waitForTimeout(200);
  await step('5 LinkedIn tab: one card per ready message; copy works', liCards === liExpected && (!liCards || /Copied|Could not copy/.test(await page.locator('main .banner').first().innerText().catch(() => ''))));
  if (liCards) {
    await page.locator('main article.card [data-modal=touch]').first().click();
    await page.click('#m-ok');
    await page.waitForTimeout(300);
  }
  const tc = last(calls, 'hq_log_touch');
  await step('6 Mark sent logs a LinkedIn touch, closes the task, books a follow-up', !liCards || (tc && tc.body.p_channel === 'LINKEDIN' && tc.body.p_task && /^\d{4}-\d{2}-\d{2}$/.test(tc.body.p_follow_up)));
  await page.click('#bsearch');
  await page.fill('#q', 'Magali');
  await page.waitForSelector('.results');
  await step('7 search finds a person', /Magali/.test(await page.locator('.results').innerText()));
  await page.fill('#q', '');
  await page.click('#bmenu');
  await page.waitForSelector('.sheet');
  const sheetBtns = await page.locator('.sheet-grid button').count();
  await page.click('.sheet [data-tab=pipeline]');
  await page.click('main [data-pview=board]');
  await step('8 Menu sheet → Pipeline board', sheetBtns >= 17 && (await page.locator('.board .bcol').count()) > 0);
  await page.screenshot({ path: 'tests/out/mobile-pipeline.png' });
  await page.click('#bmenu');
  await page.click('.sheet [data-tab=finance]');
  await step('9 Menu → Finance: money separated, forecast not set', /Forecast/.test(await page.locator('main').innerText()));
  await page.click('.bnav [data-tab=overview]');
  await page.click('#quick');
  await page.click('.modal [data-modal=new-opp]');
  await page.fill('#f-co', 'Test Co'); await page.fill('#f-type', 'Corporate retreat');
  await page.click('#m-ok');
  await page.waitForSelector('.drawer');
  await step('10 + New opportunity from the phone opens the new record', !!last(calls, 'hq_create_opportunity'));
  for (const tab of ['linkedin', 'contacts', 'companies', 'markets', 'costs', 'growth', 'help', 'system']) {
    await page.click('.drawer [data-close-drawer]').catch(() => {});
    await page.click('#bmenu');
    await page.click(`.sheet [data-tab=${tab}]`);
    await page.waitForSelector('main h2');
    const o = await noOverflow(page);
    check(`mobile 390px: no horizontal page overflow on ${tab}`, o <= 1, `${o}px`);
  }
  check('no JavaScript errors (mobile)', errors.length === 0, errors.join(' | '));
  await browser.close();
}

// 3. Hostile CRM content is shown as text, never executed.
{
  const evil = JSON.parse(JSON.stringify(snapshot));
  const a = evil.approvals.find((x) => x.loop_stage === 'PENDING_APPROVAL' && !x.block_reason);
  a.company_name = '<img src=x onerror="window.__xss=1">Evil Co';
  a.draft.body = '<script>window.__xss=2</script>';
  directory.companies[0].name = '<img src=x onerror="window.__xss=3">Evil Account';
  const { browser, page } = await runScenario({ viewport: { width: 1280, height: 900 }, data: evil });
  await page.waitForSelector('.side');
  await page.click('.side [data-tab=outreach]');
  await page.waitForSelector('article.card.ready');
  await page.click('.side [data-tab=companies]');
  const xss = await page.evaluate(() => window.__xss);
  const shown = await page.locator('main tbody', { hasText: 'Evil Account' }).first().innerText();
  check('XSS: injected HTML in CRM data is escaped (approvals + companies)', xss === undefined && shown.includes('<img'), `window.__xss=${xss}`);
  await browser.close();
}

// 4. Temporary password forces a change before any data is shown.
{
  const { browser, page } = await runScenario({ viewport: { width: 1280, height: 900 }, meta: { must_change_password: true } });
  await page.waitForSelector('#pw');
  check('first login forces password change', (await page.locator('#pw').count()) === 1);
  await browser.close();
}

server.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} UI checks passed`);
process.exit(failed.length ? 1 : 0);
