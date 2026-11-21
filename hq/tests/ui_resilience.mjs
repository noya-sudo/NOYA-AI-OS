// HQ resilience (20 Nov production fix): no user-facing read may leave HQ on "Loading" for good. Synthetic fixtures only (no live
// data): every Supabase call is intercepted, and a test can make one hang, fail, return 401 or return an unexpected shape.
import http from 'node:http';
import { readFileSync, existsSync, statSync } from 'node:fs';
import { extname, join } from 'node:path';
import { chromium } from 'playwright-core';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co';
const CHROME = process.env.CHROME_PATH || (existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : '/opt/pw-browsers/chromium-1194/chrome-linux/chrome');
const now = () => new Date().toISOString();
// Minimal, fictional shapes of the reads the HQ shell needs.
export const FX = {
  hq_dashboard: () => ({ admin: 'test@example.com', brief: {}, tasks: [], health: {}, inbound: [], revenue: {}, approvals: [], enquiries: [], marketing: {}, completions: [], generated_at: now(), intelligence: {}, opportunities: [] }),
  hq_outreach_desk: () => ({ held: [], sent: [], top5: [], counts: { needs_review: { total: 0, EMAIL: 0, LINKEDIN: 0 }, followups_due: 0 }, next20: [], status: {}, replied: [], approved: [], linkedin: [], rejected: [], followups: [], researching: [], generated_at: now(), needs_review: [], studio_ready: [], meeting_assist: [] }),
  // Production shape since 30 Oct: ceo.pipeline is the ready-pool OBJECT, not a list of stages (the 20 Nov crash).
  ceo: () => ({ money: { revenue: [] }, funnel: { week: { sent_email: 1, replies: 1, revenue: [] }, d30: {}, by_director_week: {} }, pipeline: { ready_pool: 3, qualified: 10, ready_list: [] }, companies: {}, directors: {}, operations: {}, generated_at: now(), top_opportunities: [{ company: 'Test Co', project: 'CONTENT_PRODUCTION', stage: 'CONTACTED' }], active_opportunities: 1 }),
  command: () => ({ kpis: {}, funnel: { stages: [{ stage: 'CONTACTED', label: 'Contacted', n: 2, stuck: 1 }] }, revenue: {}, directors: [], integrity: {}, scorecards: { directors: [] }, work_orders: [], generated_at: now(), opportunities: [], recommendations: [], destination_egypt: null }),
  hq_relationships: () => ({ groups: [], by_company: {}, by_contact: {} }),
  hq_overview: () => ({ actions: [], scorecard: { approvals_ready: { n: 0 } }, website: [], system: { failures: [], signals: [] }, generated_at: now() }),
  network: () => ({ generated_at: now() }), advisor: () => ({ observations: [], brief: [] }), directors: () => ({ members: [] }), execution: () => ({}),
};
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.woff2': 'font/woff2' };
const server = http.createServer((req, res) => {
  const p = join('dist', req.url === '/' ? 'index.html' : req.url.split('?')[0]);
  if (!existsSync(p) || !statSync(p).isFile()) { res.writeHead(200, { 'content-type': 'text/html' }); return res.end(readFileSync('dist/index.html')); }
  res.writeHead(200, { 'content-type': types[extname(p)] || 'application/octet-stream' }); res.end(readFileSync(p));
});
await new Promise((r) => server.listen(4181, r));
const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`); };
const b64url = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
function session() {
  const user = { id: '00000000-0000-0000-0000-00000000ad01', aud: 'authenticated', role: 'authenticated', email: 'test@example.com', user_metadata: {}, app_metadata: { provider: 'email' } };
  const exp = Math.floor(Date.now() / 1000) + 3600;
  return { access_token: `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url({ sub: user.id, email: user.email, role: 'authenticated', exp })}.sig`, token_type: 'bearer', expires_in: 3600, expires_at: exp, refresh_token: 'test-refresh', user };
}
// behave(fn, body) may return: undefined (default fixture), { hang: true }, { status, json }, or a JSON value.
// These checks cover the classic Dashboard (More → Dashboard), opened by its deep link; the V4 screens are covered in ui_v4.mjs.
async function open({ viewport = { width: 1280, height: 860 }, behave = () => undefined, timeoutMs = 1500, hash = 'dashboard' } = {}) {
  const browser = await chromium.launch({ executablePath: CHROME });
  const page = await (await browser.newContext({ viewport })).newPage(); const errors = []; const calls = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.addInitScript((ms) => { localStorage.setItem('hq.rpcTimeoutMs', String(ms)); }, timeoutMs);
  await page.route(`${SUPA}/**`, async (route) => {
    const url = route.request().url();
    if (url.includes('/auth/v1/token')) return route.fulfill({ json: session() });
    if (url.includes('/auth/v1/user')) return route.fulfill({ json: session().user });
    const m = url.match(/\/rest\/v1\/rpc\/([a-z_]+)/);
    if (!m) return route.fulfill({ status: 404, body: '' });
    const body = route.request().postDataJSON?.() ?? null; const fn = m[1] === 'hq_cached' ? `cached:${body?.p_key}` : m[1]; calls.push(fn);
    const b = behave(fn, body);
    if (b?.hang) return; // never answer: the client's bound must end it
    if (b?.status) return route.fulfill({ status: b.status, json: b.json || { message: 'error' } });
    if (b !== undefined) return route.fulfill({ json: b });
    if (m[1] === 'hq_cached') { const f = FX[body?.p_key]; return route.fulfill({ json: f ? { ...f(), _cache: { built_at: now(), age_s: 60 } } : { ok: false, reason: 'NOT_READY' } }); }
    if (FX[m[1]]) return route.fulfill({ json: FX[m[1]]() });
    return route.fulfill({ json: m[1].startsWith('hq_') ? {} : null });
  });
  await page.goto(`http://localhost:4181/${hash ? `#${hash}` : ''}`);
  await page.fill('input[name=email]', 'test@example.com'); await page.fill('input[name=password]', 'not-a-real-password');
  await page.click('button[type=submit]');
  return { browser, page, errors, calls };
}
const mainText = (page) => page.locator('main').innerText().catch(() => '');
const errs = (page) => page.evaluate(() => globalThis.__hq?.errors?.() || {});

// 1. The 20 Nov production crash: ceo.pipeline is an object. The Dashboard must draw, including the weekly review.
{
  const { browser, page, errors } = await open();
  await page.waitForSelector('.kpis', { timeout: 8000 }).catch(() => {});
  const t = await mainText(page); const e = await errs(page);
  check('Production regression: Dashboard draws when ceo.pipeline is an object (no permanent "Loading HQ…")', !/Loading HQ…/.test(t) && /Weekly CEO review/.test(t), JSON.stringify(e).slice(0, 300));
  check('Production regression: the weekly review section did not fail', !e['section:weekly'] && !e.render, e['section:weekly'] || e.render || '');
  check('No uncaught page errors on a normal load', errors.length === 0, errors.join(' | '));
  await browser.close();
}
// 2. The main read hangs: HQ must end in a friendly unavailable state with Retry, then recover on Retry.
{
  let hang = true;
  const { browser, page, calls } = await open({ behave: (fn) => (fn === 'hq_dashboard' && hang ? { hang: true } : undefined) });
  await page.waitForSelector('main .unavail [data-retry]', { timeout: 9000 }).catch(() => {});
  const t = await mainText(page);
  check('Hanging main read ends in "temporarily unavailable" + Retry (bounded, not infinite)', /temporarily unavailable/i.test(t) && await page.locator('main [data-retry]').count() > 0, t.slice(0, 120));
  check('The hang is recorded for diagnostics as a timeout', /timeout/i.test(JSON.stringify(await errs(page))));
  hang = false; const before = calls.filter((c) => c === 'hq_dashboard').length;
  await page.locator('main [data-retry]').first().click();
  await page.waitForSelector('.kpis', { timeout: 8000 }).catch(() => {});
  check('Retry re-requests the read and the Dashboard recovers', calls.filter((c) => c === 'hq_dashboard').length > before && !/temporarily unavailable/i.test(await mainText(page)));
  await browser.close();
}
// 3. Partial failure: one snapshot errors, one read hangs; the rest of the Dashboard still draws.
{
  const { browser, page } = await open({ behave: (fn) => (fn === 'cached:command' ? { status: 500, json: { message: 'boom' } } : fn === 'hq_outreach_desk' ? { hang: true } : undefined) });
  await page.waitForSelector('.kpis', { timeout: 9000 }).catch(() => {});
  const t = await mainText(page);
  check('Partial failure: Dashboard draws with one failed and one hanging read', /Weekly CEO review/.test(t) && !/Loading HQ…/.test(t));
  check('Partial failure: the failed section offers Retry instead of blanking HQ', await page.locator('main [data-retry]').count() > 0);
  await browser.close();
}
// 4. A section that throws on unexpected data is contained to that section.
{
  const { browser, page } = await open({ behave: (fn) => (fn === 'cached:ceo' ? { ...FX.ceo(), top_opportunities: 'not-a-list', _cache: { built_at: now(), age_s: 1 } } : undefined) });
  await page.waitForSelector('.kpis', { timeout: 8000 }).catch(() => {});
  const t = await mainText(page); const e = await errs(page);
  check('A throwing section shows "could not be displayed"; the rest of the Dashboard draws', /could not be displayed/.test(t) && /Pipeline/.test(t), Object.keys(e).filter((k) => k.startsWith('section:')).join(', '));
  await browser.close();
}
// 5. Session failure (401) on the main read: plain message, never infinite loading.
{
  const { browser, page } = await open({ behave: (fn) => (fn === 'hq_dashboard' ? { status: 401, json: { message: 'JWT expired', code: 'PGRST301' } } : undefined) });
  await page.waitForSelector('main .unavail', { timeout: 8000 }).catch(() => {});
  const t = await mainText(page);
  check('Auth/session failure ends in a plain unavailable message with Retry', /temporarily unavailable/i.test(t) && !/Loading HQ…/.test(t), t.slice(0, 120));
  await browser.close();
}
// 6. Refresh is never blocked: after a failed load, Refresh issues new requests.
{
  const { browser, page, calls } = await open({ behave: (fn) => (fn === 'hq_dashboard' ? { status: 503, json: { message: 'upstream' } } : undefined) });
  await page.waitForSelector('main .unavail', { timeout: 8000 }).catch(() => {});
  const n = calls.filter((c) => c === 'hq_dashboard').length;
  await page.click('#refresh'); await page.waitForTimeout(800);
  check('Refresh after a failure issues a new main read (no stuck in-flight flag)', calls.filter((c) => c === 'hq_dashboard').length > n);
  await browser.close();
}
// 7. Mobile: the bottom navigation is usable and the page has no horizontal scroll.
{
  const { browser, page } = await open({ viewport: { width: 390, height: 844 } });
  await page.waitForSelector('.kpis', { timeout: 8000 }).catch(() => {});
  const ov = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  check('Mobile: bottom navigation present and no horizontal page scroll', await page.locator('.bnav button').count() >= 4 && ov <= 1, `overflow ${ov}px`);
  await browser.close();
}
server.close();
const failed = results.filter((r) => !r.ok);
console.log(`\nui_resilience: ${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
