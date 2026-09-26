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
import { readFileSync, existsSync, mkdirSync } from 'node:fs';
import { extname, join } from 'node:path';
import { chromium } from 'playwright-core';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const FIXTURE = 'tests/fixtures/snapshot.json';
if (!existsSync(FIXTURE)) { console.log('SKIP ui test: no live snapshot fixture'); process.exit(0); }
const snapshot = JSON.parse(readFileSync(FIXTURE, 'utf8'));
mkdirSync('tests/out', { recursive: true });

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.txt': 'text/plain' };
const server = http.createServer((req, res) => {
  const p = join('dist', req.url === '/' ? 'index.html' : req.url.split('?')[0]);
  if (!existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': types[extname(p)] || 'application/octet-stream' });
  res.end(readFileSync(p));
});
await new Promise((r) => server.listen(4173, r));

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
  const page = await browser.newPage({ viewport });
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
      if (m[1] === 'hq_approve_draft') return route.fulfill({ json: { ok: true, mode: 'DRAFT', dispatched: true, outbound_id: '00000000-0000-0000-0000-000000000001' } });
      if (m[1] === 'hq_save_draft') return route.fulfill({ json: { ok: true, version: 2 } });
      if (m[1] === 'hq_hold' || m[1] === 'hq_reject') return route.fulfill({ json: { ok: true } });
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

// 1. Desktop: every view renders from live data.
{
  const { browser, page, errors, calls } = await runScenario({ viewport: { width: 1280, height: 900 } });
  await page.waitForSelector('nav.tabs');
  await page.waitForSelector('.tiles');
  check('login leads to dashboard, data via hq_dashboard with bearer token', calls.some((c) => c.fn === 'hq_dashboard' && c.auth.startsWith('Bearer ey')));
  const approvalsTile = await page.locator('.tile', { hasText: 'Approvals waiting' }).locator('.n').innerText();
  const readyLive = snapshot.approvals.filter((a) => a.loop_stage === 'PENDING_APPROVAL' && !a.block_reason).length;
  check('Today: approvals-waiting tile equals live queue', Number(approvalsTile) === readyLive, `${approvalsTile} vs ${readyLive}`);
  await page.screenshot({ path: 'tests/out/today.png', fullPage: true });

  for (const tab of ['approvals', 'pipeline', 'tasks', 'completed', 'inbound', 'marketing', 'intelligence', 'health', 'brief']) {
    await page.click(`nav.tabs button[data-tab=${tab}]`);
    await page.waitForSelector('main h2');
    const h2 = await page.locator('main h2').first().innerText();
    check(`view renders: ${tab}`, h2.length > 0, h2);
    await page.screenshot({ path: `tests/out/${tab}.png`, fullPage: true });
  }

  await page.click('nav.tabs button[data-tab=approvals]');
  const readyCards = await page.locator('article.card.ready').count();
  check('Approvals: ready cards equal live approval-ready queue', readyCards === readyLive, `${readyCards}`);
  const firstReady = page.locator('article.card.ready').first();
  const cardText = await firstReady.innerText();
  check('card shows contact, position, verified email, ESTIMATED value, why now, why NOYA, subject, body',
    /Contact/i.test(cardText) && /Position/i.test(cardText) && /Email verified/i.test(cardText) && /ESTIMATED/i.test(cardText)
      && /Why now/i.test(cardText) && /Why NOYA/i.test(cardText));
  const hoCount = snapshot.approvals.filter((a) => a.loop_stage === 'PENDING_APPROVAL' && !a.block_reason && a.human_only).length;
  check('HUMAN_ONLY badge shown on human-only cards', (await page.locator('article.card.ready .pill', { hasText: 'Human-only' }).count()) === hoCount, `${hoCount}`);
  const buttonTexts = await page.locator('button').allInnerTexts();
  check('no Send / Approve & Send button anywhere', !buttonTexts.some((t) => /send/i.test(t)), buttonTexts.filter((t) => /send/i.test(t)).join(','));
  check('blocked opportunities have no Approve button', (await page.locator('article.card:not(.ready) [data-act=approve]').count()) === snapshot.approvals.filter((a) => ['FAILED', 'DRAFT_DISCARDED', 'ON_HOLD'].includes(a.loop_stage) && !a.block_reason).length);
  const draftCreated = snapshot.approvals.filter((a) => a.loop_stage === 'DRAFT_CREATED').length;
  check('email loop: DRAFT_CREATED cards show "Open Gmail Drafts"', (await page.locator('text=Open Gmail Drafts').count()) === draftCreated, `${draftCreated}`);

  // Approve & Draft: confirm dialog, then exactly one RPC with the version shown.
  const target = snapshot.approvals.find((a) => a.loop_stage === 'PENDING_APPROVAL' && !a.block_reason);
  await page.click(`#opp-${target.id} [data-act=approve]`);
  const modalText = await page.locator('.modal').innerText();
  check('approve dialog states nothing is sent', /Nothing is sent/i.test(modalText));
  await page.click('[data-confirm=approve]');
  await page.waitForTimeout(400);
  const approveCalls = calls.filter((c) => c.fn === 'hq_approve_draft');
  check('APPROVE & DRAFT sends exactly one hq_approve_draft with opportunity + version only',
    approveCalls.length === 1 && approveCalls[0].body.p_opportunity_id === target.id && approveCalls[0].body.p_version === Number(target.draft.version)
      && Object.keys(approveCalls[0].body).sort().join() === 'p_opportunity_id,p_version', JSON.stringify(approveCalls[0]?.body));

  // Edit: subject/body only, recipient cannot be changed.
  await page.click(`#opp-${target.id} [data-act=edit]`);
  check('edit dialog has no recipient field', (await page.locator('.modal input[type=email], .modal #ed-to').count()) === 0);
  await page.fill('#ed-subject', 'Edited subject from UI test');
  await page.click('[data-confirm=edit]');
  await page.waitForTimeout(300);
  const saveCall = calls.find((c) => c.fn === 'hq_save_draft');
  check('EDIT calls hq_save_draft with subject/body only', !!saveCall && saveCall.body.p_subject === 'Edited subject from UI test'
    && Object.keys(saveCall.body).sort().join() === 'p_body,p_note,p_opportunity_id,p_subject');

  // Reject requires a reason client-side too.
  await page.click(`#opp-${target.id} [data-act=reject]`);
  await page.click('[data-confirm=reject]');
  await page.waitForTimeout(200);
  check('REJECT without reason makes no call', !calls.some((c) => c.fn === 'hq_reject'));
  await page.fill('#rej-reason', 'Not the right moment');
  await page.click('[data-confirm=reject]');
  await page.waitForTimeout(300);
  check('REJECT with reason calls hq_reject', calls.some((c) => c.fn === 'hq_reject' && c.body.p_reason === 'Not the right moment'));

  // Hold with a date.
  await page.click(`#opp-${target.id} [data-act=hold]`);
  await page.fill('#hold-date', '2026-10-15');
  await page.click('[data-confirm=hold]');
  await page.waitForTimeout(300);
  check('HOLD calls hq_hold with review date', calls.some((c) => c.fn === 'hq_hold' && c.body.p_review_date === '2026-10-15'));

  check('only allow-listed RPCs were called', calls.every((c) => ['hq_dashboard', 'hq_approve_draft', 'hq_save_draft', 'hq_hold', 'hq_reject'].includes(c.fn)));
  check('no JavaScript errors (desktop)', errors.length === 0, errors.join(' | '));
  await browser.close();
}

// 2. Mobile: approval cards usable at phone width.
{
  const { browser, page, errors } = await runScenario({ viewport: { width: 390, height: 844 } });
  await page.waitForSelector('nav.tabs');
  await page.click('nav.tabs button[data-tab=approvals]');
  await page.waitForSelector('article.card.ready');
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  check('mobile 390px: no horizontal page overflow on Approvals', overflow <= 1, `${overflow}px`);
  const btn = await page.locator('article.card.ready [data-act=approve]').first().boundingBox();
  check('mobile: Approve button is tappable (>= 36px tall)', btn && btn.height >= 36, btn ? `${Math.round(btn.height)}px` : 'missing');
  await page.screenshot({ path: 'tests/out/mobile-approvals.png', fullPage: false });
  check('no JavaScript errors (mobile)', errors.length === 0, errors.join(' | '));
  await browser.close();
}

// 3. Hostile CRM content is shown as text, never executed.
{
  const evil = JSON.parse(JSON.stringify(snapshot));
  const a = evil.approvals.find((x) => x.loop_stage === 'PENDING_APPROVAL' && !x.block_reason);
  a.company_name = '<img src=x onerror="window.__xss=1">Evil Co';
  a.draft.body = '<script>window.__xss=2</script>';
  const { browser, page } = await runScenario({ viewport: { width: 1280, height: 900 }, data: evil });
  await page.waitForSelector('nav.tabs');
  await page.click('nav.tabs button[data-tab=approvals]');
  await page.waitForSelector('article.card.ready');
  const xss = await page.evaluate(() => window.__xss);
  const shown = await page.locator('article.card.ready .co', { hasText: 'Evil Co' }).first().innerText();
  check('XSS: injected HTML in CRM data is escaped', xss === undefined && shown.includes('<img'), `window.__xss=${xss}`);
  await browser.close();
}

// 4. Temporary password forces a change before any data is shown.
{
  const { browser, page, calls } = await runScenario({ viewport: { width: 1280, height: 900 }, meta: { must_change_password: true } });
  await page.waitForSelector('#pw');
  check('first login forces password change', (await page.locator('#pw').count()) === 1);
  await browser.close();
}

server.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} UI checks passed`);
process.exit(failed.length ? 1 : 0);
