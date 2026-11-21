// HQ V4 (21 Nov 2026): Today, Opportunities, Outreach and Streams. Synthetic, fictional fixtures modelled on the live RPC shapes
// (hq_today, hq_opportunities, hq_streams, hq_email_summary, hq_email_routes); no live data. Every Supabase call is intercepted.
// Replaces the coverage of the legacy suites that need live fixtures (ui.mjs, ui_v3.mjs, ui_command.mjs skip without them).
import http from 'node:http';
import { readFileSync, existsSync, statSync } from 'node:fs';
import { extname, join } from 'node:path';
import { chromium } from 'playwright-core';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co';
const CHROME = process.env.CHROME_PATH || (existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : '/opt/pw-browsers/chromium-1194/chrome-linux/chrome');
const now = () => new Date().toISOString();
const day = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const PILLARS = ['PRIVATE_TALENT', 'BRANDS_CULTURE', 'EVENTS_CORPORATE', 'TRAVEL_DISTRIBUTION'];
const STREAMS = Array.from({ length: 36 }, (_, i) => ({ code: `STREAM_${i + 1}`, label: `Stream ${i + 1}`, pillar: PILLARS[Math.floor(i / 9)] }));
const opp = (i, stage = 'PROJECT_READY') => ({ id: uid(100 + i), company_id: uid(500 + i), company: `Example Company ${i}`, status: 'READY', stream: STREAMS[i % 36].code, stream_label: STREAMS[i % 36].label,
  project: 'BRAND_PRODUCTION_PARTNER', market: 'EUROPE', relationship: i % 5 === 0 ? 'WARM' : 'COLD', person: `Test Person ${i}`, position: 'Director', route: 'Named public email', route_state: 'PUBLIC_NAMED_EMAIL', usable: true,
  next_action: `Prepare the first note for Example Company ${i}.`, next_action_due: day(3), priority: 80 - i, blocker: null, why_now: 'Public launch announced.', stage, rank: 4, missing_next: false, overdue: false });
const route = (i) => ({ opportunity_id: uid(100 + i), company_id: uid(500 + i), company: `Example Company ${i}`, person: `Test Person ${i}`, position: 'Director', email: `person${i}@example.com`, label: 'Named public email',
  route_state: 'PUBLIC_NAMED_EMAIL', bucket: 3, status: 'READY', stream: STREAMS[i % 36].label, priority: 70, sent: false, warm: i === 0, next_action: 'Held until SPF and DKIM pass.', next_action_due: null, source_url: null });
export const FX = {
  hq_today: () => ({ generated_at: now(), gate: 'CLOSED', bottleneck: 'Conversion: 3 warm actions are prepared and waiting for you',
    actions: [
      { id: uid(1), kind: 'CALL', who: 'Test Person · Example Lodge', what_happened: 'Invited a call.', why: 'Preferred-stay partner.', todo: 'Call on the business mobile.', button_label: 'Call', button_url: 'tel:+10000000000', status: 'OPEN', due_on: day(-1), company_id: uid(501), opportunity_id: uid(101), source: 'test' },
      { id: uid(2), kind: 'DECIDE', who: 'Example Charter · option A or B', what_happened: 'Two options prepared.', why: 'Commits a client budget.', todo: 'Choose A or B.', button_label: null, button_url: null, status: 'OPEN', due_on: null, company_id: null, opportunity_id: null, source: 'test' },
      { id: uid(3), kind: 'SEND', who: 'Test Person · Example Agency', what_happened: 'Draft ready in Gmail.', why: 'Warm thread.', todo: 'Send the draft.', button_label: 'Open draft', button_url: 'https://mail.google.com/mail/u/0/#drafts', status: 'OPEN', due_on: day(2), company_id: uid(502), opportunity_id: uid(102), source: 'test' },
      { id: null, kind: 'ENQUIRY', who: 'Example · Private Concierge Enquiry', what_happened: 'Website enquiry NOYA-TEST01 on 21 Nov: Cairo & Giza, from 10 Dec, 2 guests', why: 'Inbound and qualified by the website.', todo: 'Reply personally within 24 hours', button_label: 'Find in Gmail', button_url: 'https://mail.google.com/mail/u/0/#search/NOYA-TEST01', status: 'OPEN', source: 'website', company_id: null, opportunity_id: uid(109) },
      { id: null, kind: 'REPLY', who: 'Example Club', what_happened: 'They wrote last on 20 Nov.', why: 'A reply is waiting.', todo: 'Reply in Gmail', button_label: 'Open the thread', button_url: 'https://mail.google.com/mail/u/0/#inbox', status: 'OPEN', source: 'gmail', company_id: uid(503), opportunity_id: null },
    ], actions_more: 0,
    live: [{ ...opp(1, 'MEETING'), decision_maker: 'Test Person 1', last_interaction: now(), prepared_docs: 2, action_open: true }, { ...opp(2, 'ACTIVE_CONVERSATION'), decision_maker: 'Test Person 2' }],
    best: null,
    week: { right_people_contacted: 12, emails_sent: 12, replies: 2, positive: 1, meetings: 1, briefs: 0, proposals: 1, wins: 0, revenue: [], as_of: now() },
    ready_unsent: { warm: 3, cold_gmail_drafts: 2, cold_held: 6, total: 11, gated: true },
    streams: [{ code: 'STREAM_1', label: 'Stream 1', pillar: 'PRIVATE_TALENT', live: 1, warm: 2, ready: 4, season: null }],
    blockers: [{ kind: 'DELIVERABILITY', text: 'Cold email held: SPF and DKIM do not pass yet', action: 'Fix SPF and DKIM' }],
    deadlines: [{ kind: 'OPPORTUNITY', what: 'Example Company 1', detail: 'Confirm the meeting slot.', due_on: day(-2), status: 'CALL_REQUIRED', company_id: uid(501), opportunity_id: uid(101) }, { kind: 'ACTION', what: 'Test Person · Example Agency', detail: 'Send the draft.', due_on: day(2), status: 'OPEN' }],
    waiting: [{ id: uid(4), who: 'Test Person · Example Residence', waiting_on: 'Their Teams slot', due_on: day(4), kind: 'SEND' }],
    follow_ups_due: [{ due_on: day(4), n: 37 }] }),
  hq_opportunities: (b) => {
    const all = Array.from({ length: 64 }, (_, i) => opp(i, i < 3 ? 'MEETING' : i < 10 ? 'CONTACTED' : 'PROJECT_READY'));
    let rows = all.filter((o) => (!b?.p_stream || o.stream === b.p_stream) && (!b?.p_relationship || o.relationship === b.p_relationship)
      && (!b?.p_q || o.company.toLowerCase().includes(String(b.p_q).toLowerCase())) && (!b?.p_stage || b.p_stage === 'ALL' || b.p_stage === 'PROJECT_READY_PLUS' || o.stage === b.p_stage));
    if (b?.p_q === 'zzz-no-match') rows = [];
    const off = b?.p_offset || 0; const lim = b?.p_limit || 30;
    return { rows: rows.slice(off, off + lim), total: rows.length, counts: { MEETING: 3, CONTACTED: 7, PROJECT_READY: 54, QUALIFIED_ACCOUNT: 400 }, missing_next: 0, stage: b?.p_stage, limit: lim, offset: off };
  },
  hq_streams: () => ({ generated_at: now(), streams: STREAMS.map((s, i) => ({ ...s, mission: `Mission of ${s.label}.`, director: 'TEST', universe: 10 + i, conversations: i % 4 === 0 ? 1 : 0, project_ready: 3, contacted: 2, meetings: i === 0 ? 1 : 0, proposals: 0, wins: 0, replies_30d: i === 0 ? 1 : 0, revenue: [], contact_gap: 4,
    top: [{ id: uid(100 + i), company_id: uid(500 + i), company: `Example Company ${i}`, project: 'BRAND_PRODUCTION_PARTNER', stage: 'PROJECT_READY', next_action: 'Prepare.' }], next_action: 'Prepare the first note.', season: null })) }),
  hq_email_summary: () => ({ actionable: 40, replies: 9, follow_ups: 3, ready: 31, public_named: 57, management_agent: 0, instagram: 0, clay: 15, official_inbox: 67, needs_research: 774, sent: 97, gate: 'CLOSED', computed_at: now() }),
  hq_email_routes: (b) => {
    let rows = Array.from({ length: 40 }, (_, i) => route(i));
    if (b?.p_filter === 'INSTAGRAM' || b?.p_q === 'zzz-no-match') rows = [];
    if (b?.p_filter === 'REPLIES') rows = rows.filter((r) => r.warm);
    const off = b?.p_offset || 0; const lim = b?.p_limit || 25;
    return { rows: rows.slice(off, off + lim), total: rows.length, limit: lim, offset: off, filter: b?.p_filter, computed_at: now() };
  },
  hq_ceo_action: () => ({ ok: true, status: 'DONE' }),
  hq_timeline: () => [],
  hq_dashboard: () => ({ admin: 'test@example.com', brief: {}, tasks: [], health: {}, inbound: [], revenue: {}, approvals: [], enquiries: [], marketing: {}, completions: [], generated_at: now(), intelligence: {}, opportunities: [] }),
  hq_outreach_desk: () => ({ held: [], sent: [], top5: [], counts: { needs_review: { total: 2, EMAIL: 2, LINKEDIN: 0 }, followups_due: 0 }, next20: [], status: {}, replied: [], approved: [], linkedin: [], rejected: [], followups: [], researching: [], generated_at: now(), needs_review: [], studio_ready: [], meeting_assist: [] }),
  hq_relationships: () => ({ groups: [], by_company: {}, by_contact: {} }),
  hq_overview: () => ({ actions: [], scorecard: { approvals_ready: { n: 0 } }, website: [], system: { failures: [], signals: [] }, generated_at: now() }),
};
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.woff2': 'font/woff2', '.svg': 'image/svg+xml' };
const server = http.createServer((req, res) => {
  const p = join('dist', req.url === '/' ? 'index.html' : req.url.split('?')[0].split('#')[0]);
  if (!existsSync(p) || !statSync(p).isFile()) { res.writeHead(200, { 'content-type': 'text/html' }); return res.end(readFileSync('dist/index.html')); }
  res.writeHead(200, { 'content-type': types[extname(p)] || 'application/octet-stream' }); res.end(readFileSync(p));
});
await new Promise((r) => server.listen(4182, r));
const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`); };
const b64url = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
function session() {
  const user = { id: '00000000-0000-0000-0000-00000000ad01', aud: 'authenticated', role: 'authenticated', email: 'test@example.com', user_metadata: {}, app_metadata: { provider: 'email' } };
  const exp = Math.floor(Date.now() / 1000) + 3600;
  return { access_token: `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url({ sub: user.id, email: user.email, role: 'authenticated', exp })}.sig`, token_type: 'bearer', expires_in: 3600, expires_at: exp, refresh_token: 'test-refresh', user };
}
async function open({ viewport = { width: 1280, height: 860 }, behave = () => undefined, timeoutMs = 2500, hash = '' } = {}) {
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
    const body = route.request().postDataJSON?.() ?? null; const fn = m[1] === 'hq_cached' ? `cached:${body?.p_key}` : m[1]; calls.push({ fn, body, at: Date.now() });
    const b = behave(fn, body);
    if (b?.hang) return;
    if (b?.status) return route.fulfill({ status: b.status, json: b.json || { message: 'error' } });
    if (b !== undefined) return route.fulfill({ json: b });
    if (m[1] === 'hq_cached') return route.fulfill({ json: { ok: false, reason: 'NOT_READY' } });
    if (FX[m[1]]) return route.fulfill({ json: FX[m[1]](body) });
    return route.fulfill({ json: m[1].startsWith('hq_') ? {} : null });
  });
  await page.goto(`http://localhost:4182/${hash ? `#${hash}` : ''}`);
  await page.fill('input[name=email]', 'test@example.com'); await page.fill('input[name=password]', 'not-a-real-password');
  await page.click('button[type=submit]');
  return { browser, page, errors, calls };
}
// textContent, not innerText: headings are uppercased by CSS and innerText would report the transformed text.
const mainText = (page) => page.locator('main').evaluate((el) => el.textContent.replace(/\s+/g, ' ')).catch(() => '');
const n = (calls, fn) => calls.filter((c) => c.fn === fn).length;
const last = (calls, fn) => [...calls].reverse().find((c) => c.fn === fn)?.body || {};
const noOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth <= 1);

// 1. Today is the default screen and draws from hq_today alone, even while the heavy dashboard read hangs.
{
  const { browser, page, errors, calls } = await open({ behave: (fn) => (fn === 'hq_dashboard' ? { hang: true } : undefined) });
  const t0 = Date.now(); await page.waitForSelector('.ca4', { timeout: 6000 }).catch(() => {});
  const ms = Date.now() - t0; const t = await mainText(page);
  check('Today is the default screen and paints from hq_today while hq_dashboard hangs', /Needs you/.test(t) && /Example Lodge/.test(t) && !/Loading HQ…/.test(t), `${ms} ms`);
  check('Today shows deadlines, waiting, this week, prepared-not-sent and blockers', ['Deadlines', 'Waiting on others', 'This week', 'Prepared, not sent', 'Blockers', '37 follow-ups due'].every((x) => t.includes(x)));
  check('Today: overdue items are marked late', await page.locator('.due.late, .dl-row.late').count() >= 2);
  check('Today: the gate shows cold email held', /Cold email held/i.test(t));
  check('Today: a new website enquiry appears as a New enquiry card', /New enquiry/.test(t) && /NOYA-TEST01/.test(t));
  check('Address follows the screen (#today deep link)', (await page.evaluate(() => location.hash)) === '#today');
  check('Primary navigation has the seven V4 destinations', (await page.locator('.nav-primary .nav-item').allInnerTexts()).map((x) => x.replace(/\d+/g, '').trim()).join('|') === 'Today|Opportunities|Outreach|Streams|Relationships|Projects|Agents');
  // Done → audited hq_ceo_action, then only hq_today is re-read.
  const before = n(calls, 'hq_today'); const dashBefore = n(calls, 'hq_dashboard');
  await page.locator(`[data-ceo-act="${uid(1)}"][data-to="DONE"]`).click(); await page.waitForTimeout(500);
  const a = last(calls, 'hq_ceo_action');
  check('Done calls hq_ceo_action(DONE) for that item and re-reads hq_today only', a.p_id === uid(1) && a.p_action === 'DONE' && n(calls, 'hq_today') > before && n(calls, 'hq_dashboard') === dashBefore);
  // A decision needs a note; saving records it (nothing is sent).
  await page.locator(`[data-act-note="${uid(2)}"]`).click();
  const nBefore = n(calls, 'hq_ceo_action');
  await page.locator('[data-with-note]').click(); await page.waitForTimeout(200);
  check('A decision cannot be saved without writing it', n(calls, 'hq_ceo_action') === nBefore);
  await page.fill('#act-note', 'B'); await page.locator('[data-with-note]').click(); await page.waitForTimeout(400);
  const d = last(calls, 'hq_ceo_action');
  check('Saving a decision records the note via hq_ceo_action', d.p_id === uid(2) && d.p_note === 'B' && d.p_action === 'DONE');
  // Light drawer opens from a live row without the heavy read.
  await page.locator('.row4[data-lopp]').first().click(); await page.waitForSelector('.drawer', { timeout: 3000 }).catch(() => {});
  const dt = await page.locator('.drawer').evaluate((el) => el.textContent).catch(() => '');
  check('A row opens its record drawer without the dashboard data', /Example Company 1/.test(dt) && /Next action/.test(dt) && /opens once the CRM data has loaded/.test(dt));
  check('No uncaught page errors on Today', errors.length === 0, errors.join(' | '));
  await browser.close();
}
// 2. Today read fails: plain unavailable + Retry, then recovery.
{
  let hang = true;
  const { browser, page, calls } = await open({ behave: (fn) => (fn === 'hq_today' && hang ? { hang: true } : undefined), timeoutMs: 1500 });
  await page.waitForSelector('main [data-retry="today"]', { timeout: 20000 }).catch(() => {});
  check('Hanging hq_today ends in "temporarily unavailable" + Retry (bounded)', /temporarily unavailable/i.test(await mainText(page)) && await page.locator('main [data-retry="today"]').count() === 1);
  hang = false; const before = n(calls, 'hq_today');
  await page.locator('main [data-retry="today"]').click(); await page.waitForSelector('.ca4', { timeout: 6000 }).catch(() => {});
  check('Retry re-reads hq_today and Today recovers', n(calls, 'hq_today') > before && /Needs you/.test(await mainText(page)));
  await browser.close();
}
// 3. Opportunities: server-side filters, pagination, zero-result state, search that keeps focus.
{
  const { browser, page, errors, calls } = await open({ hash: 'opps' });
  await page.waitForSelector('.row4[data-lopp]', { timeout: 6000 }).catch(() => {});
  let t = await mainText(page);
  check('Opportunities opens by deep link and lists rows from hq_opportunities', /Example Company 0/.test(t) && await page.locator('.row4[data-lopp]').count() === 30, `${await page.locator('.row4[data-lopp]').count()} rows`);
  check('Default filter is Project ready and above', last(calls, 'hq_opportunities').p_stage === 'PROJECT_READY_PLUS' && /1–30 of 64/.test(t));
  await page.locator('[data-page="opp"][data-dir="1"]').click(); await page.waitForTimeout(400);
  check('Next page asks the server for offset 30', last(calls, 'hq_opportunities').p_offset === 30 && /31–60 of 64/.test(await mainText(page)));
  await page.locator('[data-opp-stage="MEETING"]').click(); await page.waitForTimeout(400);
  check('Stage chip filters on the server and resets paging', last(calls, 'hq_opportunities').p_stage === 'MEETING' && last(calls, 'hq_opportunities').p_offset === 0 && await page.locator('.row4[data-lopp]').count() === 3);
  await page.selectOption('select[data-opp-stream]', 'STREAM_2'); await page.waitForTimeout(400);
  check('Stream filter is sent as the canonical stream code', last(calls, 'hq_opportunities').p_stream === 'STREAM_2');
  await page.locator('[data-opp-clear]').click().catch(() => {}); await page.waitForTimeout(300);
  await page.click('#opp-q'); await page.keyboard.type('zzz-no-match', { delay: 15 }); await page.waitForTimeout(800);
  t = await mainText(page);
  check('Search is sent once typing pauses (p_q)', last(calls, 'hq_opportunities').p_q === 'zzz-no-match');
  check('Search box keeps focus while results refresh', (await page.evaluate(() => document.activeElement?.id)) === 'opp-q');
  check('Zero results say so and offer a way out', /No opportunities match these filters/.test(t) && await page.locator('[data-opp-clear]').count() === 1);
  await page.locator('[data-opp-clear]').click(); await page.waitForTimeout(400);
  check('Clear filters restores the default list', last(calls, 'hq_opportunities').p_q === null && await page.locator('.row4[data-lopp]').count() === 30);
  check('No uncaught page errors on Opportunities', errors.length === 0, errors.join(' | '));
  await browser.close();
}
// 4. Opportunities read fails → Retry.
{
  let fail = true;
  const { browser, page, calls } = await open({ hash: 'opps', behave: (fn) => (fn === 'hq_opportunities' && fail ? { status: 500, json: { message: 'boom' } } : undefined) });
  await page.waitForSelector('main [data-retry="opps"]', { timeout: 8000 }).catch(() => {});
  check('Failed hq_opportunities shows unavailable + Retry, never raw errors', /temporarily unavailable/i.test(await mainText(page)) && !/boom/.test(await mainText(page)));
  fail = false; await page.locator('main [data-retry="opps"]').click(); await page.waitForSelector('.row4[data-lopp]', { timeout: 6000 }).catch(() => {});
  check('Retry recovers Opportunities', await page.locator('.row4[data-lopp]').count() > 0 && n(calls, 'hq_opportunities') >= 2);
  await browser.close();
}
// 5. Outreach: gate banner, approval-desk strip, filters with counts, zero-match fallback, one route per company.
{
  const { browser, page, errors, calls } = await open({ hash: 'mail' });
  await page.waitForSelector('.row4[data-lopp]', { timeout: 6000 }).catch(() => {});
  let t = await mainText(page);
  check('Outreach shows the cold-email gate and the approval desk count', /Cold email is held until SPF and DKIM pass/.test(t) && /waiting for your review in the approval desk/.test(t));
  check('Outreach filter chips carry server counts', /Actionable\s*40/.test(t) && /Needs research\s*774/.test(t));
  const emails = await page.locator('.row4[data-lopp] .mono').allInnerTexts(); const cos = await page.locator('.row4[data-lopp] .t4').allInnerTexts();
  check('One route per company: no company appears twice on the page', cos.length === 25 && new Set(cos.map((c) => c.replace(/Warm|Sent/g, '').trim())).size === cos.length && new Set(emails).size === emails.length);
  await page.locator('[data-route-filter="REPLIES"]').click(); await page.waitForTimeout(400);
  check('Route filter is sent to the server', last(calls, 'hq_email_routes').p_filter === 'REPLIES' && await page.locator('.row4[data-lopp]').count() === 1);
  await page.locator('[data-route-filter="INSTAGRAM"]').click(); await page.waitForTimeout(400);
  t = await mainText(page);
  check('Zero-match route filter explains itself and offers a fallback', /No contact routes match these filters/.test(t) && await page.locator('[data-route-reset]').count() === 1);
  await page.locator('[data-route-reset]').click(); await page.waitForTimeout(400);
  check('Fallback returns to actionable routes', last(calls, 'hq_email_routes').p_filter === 'ACTIONABLE' && await page.locator('.row4[data-lopp]').count() === 25);
  await page.locator('[data-page="route"][data-dir="1"]').click(); await page.waitForTimeout(400);
  check('Route paging asks for offset 25', last(calls, 'hq_email_routes').p_offset === 25);
  check('Gmail history link opens Gmail, not the drawer', await page.locator('.row4 a.link4[href^="https://mail.google.com"]').count() > 0);
  check('No uncaught page errors on Outreach', errors.length === 0, errors.join(' | '));
  await browser.close();
}
// 6. Outreach routes fail → Retry; the summary still draws.
{
  let fail = true;
  const { browser, page } = await open({ hash: 'mail', behave: (fn) => (fn === 'hq_email_routes' && fail ? { status: 503, json: { message: 'upstream' } } : undefined) });
  await page.waitForSelector('main [data-retry="routes"]', { timeout: 8000 }).catch(() => {});
  const t = await mainText(page);
  check('Failed route list shows Retry while filter counts still draw', /temporarily unavailable/i.test(t) && /Actionable\s*40/.test(t));
  fail = false; await page.locator('main [data-retry="routes"]').click(); await page.waitForSelector('.row4[data-lopp]', { timeout: 6000 }).catch(() => {});
  check('Retry recovers the route list', await page.locator('.row4[data-lopp]').count() === 25);
  await browser.close();
}
// 7. Streams: 36 streams in 4 pillars; a stream opens; its opportunities open with the stream filter.
{
  const { browser, page, errors, calls } = await open({ hash: 'streams' });
  await page.waitForSelector('.sm4-row', { timeout: 6000 }).catch(() => {});
  check('Streams lists all 36 streams in 4 pillars', await page.locator('.sm4-row').count() === 36 && await page.locator('main .v4').count() === 4);
  await page.locator('[data-pillar="EVENTS_CORPORATE"]').click(); await page.waitForTimeout(150);
  check('Pillar filter narrows to one pillar (9 streams)', await page.locator('.sm4-row').count() === 9);
  await page.locator('[data-pillar=""]').click(); await page.locator('[data-stream-open="STREAM_1"]').click(); await page.waitForTimeout(150);
  const body = await page.locator('.sm4.open').evaluate((el) => el.textContent).catch(() => '');
  check('Opening a stream shows its mission, next action and top accounts', /Mission of Stream 1/.test(body) && /Example Company 0/.test(body));
  await page.locator('.sm4.open [data-stream-go="STREAM_1"]').click(); await page.waitForTimeout(500);
  check('Open opportunities filters Opportunities by that stream (canonical code)', (await page.evaluate(() => location.hash)) === '#opps' && last(calls, 'hq_opportunities').p_stream === 'STREAM_1' && last(calls, 'hq_opportunities').p_stage === 'ALL');
  check('No uncaught page errors on Streams', errors.length === 0, errors.join(' | '));
  await browser.close();
}
// 8. Mobile (390 px): every V4 screen fits without horizontal scroll; bottom navigation has five targets.
{
  const { browser, page, errors } = await open({ viewport: { width: 390, height: 844 } });
  await page.waitForSelector('.ca4', { timeout: 6000 }).catch(() => {});
  const res = [];
  for (const tab of ['today', 'opps', 'mail', 'streams']) {
    if (tab !== 'today') { await page.locator(`.bnav [data-tab="${tab}"]`).click(); await page.waitForTimeout(700); }
    res.push(`${tab}:${await noOverflow(page) ? 'ok' : 'overflow'}`);
  }
  check('Mobile: Today, Opportunities, Outreach and Streams have no horizontal scroll', res.every((r) => r.endsWith('ok')), res.join(' '));
  check('Mobile: bottom navigation has five targets (four screens + More)', await page.locator('.bnav button').count() === 5);
  await page.locator('#bmenu').click(); await page.waitForTimeout(150);
  check('Mobile: More sheet reaches Relationships, Projects, Agents and the approval desk', await page.locator('.sheet [data-tab="relations"], .sheet [data-tab="projects"], .sheet [data-tab="agents"], .sheet [data-tab="desk"]').count() === 4);
  check('No uncaught page errors on mobile', errors.length === 0, errors.join(' | '));
  await browser.close();
}
server.close();
const failed = results.filter((r) => !r.ok);
console.log(`\nui_v4: ${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
