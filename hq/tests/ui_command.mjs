// HQ Command Centre acceptance (professional operating mode, 18-19 Oct): the seven top numbers, the pipeline with owner / next
// action / date / blocker, HQ Advisor's five recommendations and the approvals waiting for Adam, CEO work orders, Director
// scorecards, revenue and its reconciliation, and Admin → System health. Reads are live captures (tests/fixtures, git-ignored);
// every write is recorded to prove exactly what each button sends. Nothing here can send an email.
import http from 'node:http';
import { readFileSync, existsSync, mkdirSync, statSync, writeFileSync } from 'node:fs';
import { extname, join } from 'node:path';
import { chromium } from 'playwright-core';
import { withMorning } from './morning_fixture.mjs';
import { createHash } from 'node:crypto';
import { pdfFingerprint } from '../../studio/record.mjs';

const SUPA = 'https://gagbhykzmtstekpqujyl.supabase.co';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const fx = (f) => (existsSync(`tests/fixtures/${f}.json`) ? JSON.parse(readFileSync(`tests/fixtures/${f}.json`, 'utf8')) : null);
const need = ['snapshot', 'overview', 'directory', 'insight', 'relationships', 'desk', 'directors', 'club', 'operations', 'advisor', 'weekly', 'ceo', 'network', 'command', 'health', 'integrity', 'studio'];
if (need.some((f) => !fx(f))) { console.log(`SKIP ui_command: live fixtures missing (${need.filter((f) => !fx(f)).join(', ')})`); process.exit(0); }
const F = Object.fromEntries(need.map((f) => [f, fx(f)]));
F.execution = fx('execution');
F.desk = withMorning(F.desk, F.snapshot.opportunities);
// 19 Oct capture of the Director cards and the email-ready reserve (Directors in priority order); the 16 Oct captures stay for the other suites
const AL = fx('agents_live');
if (AL) { F.directors = AL.directors; F.execution = { ...F.execution, queue: { ...(F.execution?.queue || {}), acquisition: AL.acquisition } }; }
mkdirSync('tests/out/command', { recursive: true });

const SNAP = { ceo: F.ceo, command: F.command, network: F.network, advisor: F.advisor, directors: F.directors, execution: F.execution, health: F.health, integrity: F.integrity };
const READS = {
  hq_follow_up_board: () => ({ due: [], replies_owed: [], reopen: [], meetings: [], counts: {} }),
  hq_dashboard: () => F.snapshot, hq_overview: () => F.overview, hq_directory: () => F.directory, hq_insight: () => F.insight, hq_relationships: () => F.relationships,
  hq_commercial: () => ({ generated_at: new Date().toISOString(), team: { members: [], routing: {} }, weights: {}, products: [], playbooks: [], signals: [], queue: [], partners: [], projects: [], supply_partners: {} }),
  hq_outreach_desk: () => F.desk, hq_operations: () => F.operations, hq_club: () => F.club, hq_weekly_review: () => F.weekly, hq_studio: () => STUDIO || F.studio,
  hq_cached: (b) => { const v = SNAP[b?.p_key] || (String(b?.p_key).startsWith('director:') ? { key: b.p_key.slice(9), sections: [] } : null);
    return v ? { ...v, _cache: { built_at: new Date(Date.now() - 120000).toISOString(), age_s: 120 } } : { ok: false, reason: 'UNKNOWN_KEY' }; },
  hq_cache_status: () => ({ generated_at: new Date().toISOString(), items: [], jobs: [] }),
  // Why this lead (29 Oct): fictional evidence for one Top 5 opportunity.
  hq_lead_card: () => ({ ok: true, company: 'Orbit Weddings', person: 'Ana Test', role: 'Founder', source: 'PRESS · https://example.com/orbit',
    why_qualified: 'Plans multi-day weddings abroad.', why_now: 'Planning 2027 seasons now.', project_idea: 'An Egypt wedding option for their clients',
    channel: 'EMAIL_FIRST', channel_reasons: ['Email route: verified'], relationship_state: 'COLD', contact_confidence: 'Confirmed from a source',
    email_state: 'Verified personal address', linkedin_state: null, recommended_message: 'Hi Ana, one idea for Egypt.', message_subject: 'Egypt for your 2027 couples',
    message_status: 'READY', supporting_asset: { asset: 'NONE', format: 'PLAIN', reason: 'First touch: a plain founder email with one idea; no attachment' },
    next_action: 'Approve the email', if_they_respond: 'Offer a 20-minute call, then a one-page Egypt wedding outline',
    readiness: { ready: true, missing: [], answers: {} } }), hq_timeline: () => ({ events: [], notes: [] }), hq_account: () => null,
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
  hq_studio_request: { ok: true, id: '00000000-0000-0000-0000-0000000000s1', level: 2 }, hq_studio_request_action: { ok: true },
  hq_linkedin_action: { ok: true, state: 'SENT', words: 60 }, hq_linkedin_reply: { ok: true, class: 'QUESTION', response: 'Thank you.', meeting_task: null },
  hq_meeting_confirm: { ok: true, meeting_task: '00000000-0000-0000-0000-0000000000m2', briefing: {} },
  hq_studio_pdf_stored: { ok: true }, hq_studio_attach: { ok: true, request_id: 77, draft_id: 'r-test-draft-1' }, hq_studio_document_action: { ok: true } };
// The Studio read can be swapped by a test (the handoff states), and a write can move it on (as workflow 26 would).
let STUDIO = null; const ON_WRITE = {};

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
    // Supabase Storage (the private studio-pdfs bucket): a short-lived link to a stored PDF, and the one-time upload.
    const st = url.match(/\/storage\/v1\/object\/(sign\/)?studio-pdfs\/([^?]+)/);
    if (st) { calls.push({ fn: st[1] ? 'storage.sign' : 'storage.upload', path: decodeURIComponent(st[2]) });
      return route.fulfill({ json: st[1] ? { signedURL: `/object/sign/studio-pdfs/${st[2]}?token=test` } : { Key: `studio-pdfs/${st[2]}`, Id: 'test' } }); }
    const m = url.match(/\/rest\/v1\/rpc\/([a-z_]+)/);
    if (m) { const body = route.request().postDataJSON?.() ?? null; calls.push({ fn: m[1], body });
      if (READS[m[1]]) return route.fulfill({ json: READS[m[1]](body) });
      if (WRITES[m[1]]) { ON_WRITE[m[1]]?.(body); return route.fulfill({ json: WRITES[m[1]] }); }
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
  // 3b. The morning (Adam, 19 Oct; 21 Oct adds past relationships worth reopening): the lists in order; the five best new outreach
  // items, never the whole queue.
  const groups = (await page.locator('#needs .ngrp-h h3').allTextContents()).map((t) => t.replace(/\s*\d+$/, '').trim());
  const want = ['Replies owed', 'Meetings to schedule', 'Follow-ups due', 'Past relationships worth reopening', 'Top 5 new outreach to approve', 'Studio documents ready'];
  check('Morning: lists in order (replies owed, meetings to schedule, follow-ups due, past relationships worth reopening, top 5 new outreach, Studio documents ready)', JSON.stringify(groups.filter((g) => g !== 'Clients and proposals')) === JSON.stringify(want), groups.join(' | '));
  const topRows = await page.locator('#needs [data-need="outreach"] .act', { hasText: /\d of \d · / }).count();
  check('Morning: new outreach shows the ranked five from hq_outreach_desk, not the whole queue', topRows === F.desk.top5.length && topRows <= 5 && F.desk.needs_review.length > 5, `${topRows} of ${F.desk.needs_review.length} waiting`);
  check('Morning: "N waiting in Outreach" links to the rest', /waiting in Outreach/.test(await txt(page, '#needs [data-need="outreach"] .ngrp-h')));
  const liTop = F.desk.linkedin.find((a) => a.state === 'READY' && F.desk.top5.some((t) => F.desk.needs_review.find((x) => x.ref === t.ref)?.task_id === a.task_id));
  if (liTop) {
    const lnk = page.locator(`#needs [data-need="outreach"] a[data-copy][href="${liTop.linkedin}"]`).first();
    check('Morning: a LinkedIn item has Copy & open LinkedIn (copies the message, opens the profile; Adam sends)', (await lnk.count()) === 1 && (await lnk.getAttribute('data-copy')) === liTop.message && (await lnk.getAttribute('target')) === '_blank');
  }
  const liRep = F.desk.linkedin.find((a) => a.state === 'REPLIED');
  check('Morning: a LinkedIn reply is under Replies owed with the suggested response to copy', (await page.locator(`#needs [data-need="replies"] [data-copy="${liRep.response_draft}"]`).count()) === 1);
  const ma = F.desk.meeting_assist[0];
  check('Morning: Meeting Assist under Meetings to schedule, with the two times from the calendar', /Offered Thu 22 Oct.* or Fri 23 Oct.*\(UK\)/.test(await txt(page, `#needs [data-need="meetings"] .act:has([data-id="${ma.task_id}"])`)));
  check('Morning: Studio documents ready, one tap to the Studio', (await page.locator('#needs [data-need="studio"] .act').count()) === F.desk.studio_ready.length);
  await page.locator(`#needs [data-modal="meet-confirm"][data-id="${ma.task_id}"]`).click();
  check('Confirm meeting: the times offered are listed, the first preselected', (await page.locator('.modal input[name="mc-slot"]').count()) === 3 && await page.locator('.modal input[name="mc-slot"]').first().isChecked());
  await page.locator('.modal input[name="mc-slot"]').nth(1).check(); await page.selectOption('#mc-min', '30'); await page.click('#m-ok'); await page.waitForTimeout(250);
  const mc = last(calls, 'hq_meeting_confirm')?.body || {};
  check('Confirm meeting: one call with the picked time; the meeting, briefing and links are recorded server-side', mc.p_task === ma.task_id && mc.p_start === ma.slots[1].start && mc.p_minutes === 30, JSON.stringify(mc));
  await page.locator(`#needs [data-modal="meet-confirm"][data-id="${ma.task_id}"]`).click();
  await page.locator('.modal input[name="mc-slot"]').last().check(); await page.fill('#mc-date', '2026-10-28'); await page.fill('#mc-time', '16:30'); await page.click('#m-ok'); await page.waitForTimeout(250);
  check('Confirm meeting: another time is sent as UK time', last(calls, 'hq_meeting_confirm')?.body?.p_start === '2026-10-28 16:30 Europe/London', last(calls, 'hq_meeting_confirm')?.body?.p_start);
  // 4. Plan an opportunity: owner, next action, date, blocker.
  await page.locator('#pipeline tbody tr:has-text("CRUSH Agency") [data-modal="opp-plan"]').click();
  // The captured due date can fall behind the clock; pick a future date so the form's today-or-later rule passes.
  await page.fill('#op-due', new Date(Date.now() + 7 * 864e5).toISOString().slice(0, 10));
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
  check('Mission panel: conversion first (sprint, Adam 19 Oct): contacted, replied, positive, meetings, briefs, proposals, won, revenue', JSON.stringify(tiles) === JSON.stringify(['Contacted', 'Replied', 'Positive', 'Meetings', 'Briefs', 'Proposals', 'Projects won', 'Revenue']), tiles.join(' | '));
  const nums = (await page.locator('#mission .wk-t .n').allTextContents()).map((t) => t.trim());
  check('Mission panel: numbers come from the mission record (9 contacted, 3 replied, 2 positive, £0 revenue)', JSON.stringify(nums) === JSON.stringify(['9', '3', '2', '0', '0', '0', '0', '£0']), nums.join(' | '));
  const mission = await txt(page, '#mission');
  check('Mission panel: the conversion sprint line (conversations against the 10-15 target, new since the start)', /Destination Egypt conversion sprint/.test(mission) && /3 conversations of 10–15 \(0 new\)/.test(mission) && /starts 20 Oct/.test(mission), (mission.match(/Destination Egypt conversion sprint[^\n]*/) || [''])[0]);
  check('Mission panel: research is secondary (qualified and email-ready move to the pipeline line)', /Pipeline: 35 qualified · 14 email-ready/.test(mission));
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
// 11. The handoff on every Studio card (Adam, 21 Oct): RELATIONSHIP → DOCUMENT → PDF → EMAIL DRAFT → ATTACHMENT → SEND. A Studio
// with every state (fictional companies and example.com addresses): the buttons per state, the split header counts, Preview of
// the stored PDF, the one-time PDF check (a wrong file is refused before anything is uploaded), Attach → workflow 26 → verified
// → Open Gmail & send, Review (approve / request changes), history. Nothing is ever sent.
{
  const pdfA = Buffer.from('%PDF-1.4\n1 0 obj << /Title (Lumen brief) /CreationDate (D:20261021120000Z) >> endobj\n%%EOF\n', 'latin1');
  const pdfRerender = Buffer.from(pdfA.toString('latin1').replace('D:20261021120000Z', 'D:20261022093000Z'), 'latin1');
  const pdfWrong = Buffer.from('%PDF-1.4\n1 0 obj << /Title (Someone else) /CreationDate (D:20261021120000Z) >> endobj\n%%EOF\n', 'latin1');
  mkdirSync('tests/out/command/pdf', { recursive: true });
  const files = { right: 'tests/out/command/pdf/Lumen brief (re-rendered).pdf', wrong: 'tests/out/command/pdf/Other.pdf' };
  writeFileSync(files.right, pdfRerender); writeFileSync(files.wrong, pdfWrong);
  const sha = (b) => createHash('sha256').update(b).digest('hex');
  const iso = (days) => new Date(Date.now() + days * 86400000).toISOString().slice(0, 10);
  const G = 'https://mail.google.com/mail/?authuser=noya@noyaconcierge.com';
  const pdf = (slug, v, file, stored, b = pdfA) => ({ file_name: file, bytes: b.length, sha256: sha(b), fingerprint: pdfFingerprint(b), path: `${slug}/v${v}.pdf`, stored, stored_at: stored ? new Date().toISOString() : null });
  const draft = (id, thread, to, extra = {}) => ({ id, thread_id: thread, status: 'PREPARED', send_after: null, sent_at: null, to, url: `${G}#all?compose=${id}`, thread_url: `${G}#all/${thread}`, ...extra });
  const attach = (extra = {}) => ({ verified_at: null, requested_at: null, status_code: null, result: null, error: null, ...extra });
  const doc = (id, o) => ({ id, version: 1, level: 3, stage: 'master', doc_type: 'BRIEF', vertical: 'brand', created_at: '2026-10-20T19:00:00Z', approved_at: '2026-10-21T00:39:00Z', sent_at: null, hold_reason: null, ...o });
  const CO = { lumen: 'c0000000-0000-0000-0000-00000000000a', orbit: 'c0000000-0000-0000-0000-00000000000b', sable: 'c0000000-0000-0000-0000-00000000000c', vela: 'c0000000-0000-0000-0000-00000000000d' };
  const lumen = doc('d0000000-0000-0000-0000-000000000001', { slug: 'lumen-egypt-brief', version: 5, title: 'Egypt, under your creative lead.', company: 'Lumen Middle East', company_id: CO.lumen, status: 'APPROVED',
    file: 'Lumen x NOYA - Egypt Brief.pdf', ready_class: 'READY_FOR_ATTACHMENT', ready_reason: 'Approved by Adam, 21 Oct. Press Attach to Lumen email.',
    handoff: { external: true, email: false, pdf: pdf('lumen-egypt-brief', 5, 'Lumen x NOYA - Egypt Brief.pdf', false), draft: draft('r-test-draft-1', 't1', ['jad@example.com', 'amal@example.com', 'magali@example.com']), attach: attach() } });
  const orbit = doc('d0000000-0000-0000-0000-000000000002', { slug: 'orbit-egypt-brief', version: 3, title: 'Egypt as a stage.', company: 'Orbit Agency', company_id: CO.orbit, status: 'APPROVED', file: 'Orbit x NOYA - Egypt Brief.pdf',
    ready_class: 'READY_FOR_ATTACHMENT', ready_reason: 'Approved. For later, only if they have not replied.',
    handoff: { external: true, email: false, pdf: pdf('orbit-egypt-brief', 3, 'Orbit x NOYA - Egypt Brief.pdf', false), draft: draft('r-test-draft-2', 't2', ['sophie@example.com'], { send_after: iso(5) }), attach: attach() } });
  const sable = doc('d0000000-0000-0000-0000-000000000003', { slug: 'sable-onepage', title: 'A launch worth the journey.', company: "Sable's Jewellery", company_id: CO.sable, status: 'APPROVED', stage: 'onepage', doc_type: 'ONE_PAGE_CONCEPT', level: 2,
    file: "Sable's x NOYA - One-page concept.pdf", ready_class: 'READY_FOR_ATTACHMENT', ready_reason: 'Approved.',
    handoff: { external: true, email: false, pdf: pdf('sable-onepage', 1, "Sable's x NOYA - One-page concept.pdf", true), draft: draft('r-test-draft-3', 't3', ['raymond@example.com'], { send_after: iso(-2) }), attach: attach() } });
  const vela = doc('d0000000-0000-0000-0000-000000000004', { slug: 'vela-proposal', title: 'The Vela weekend.', company: 'Vela', company_id: CO.vela, status: 'APPROVED', doc_type: 'PROPOSAL', stage: 'proposal', file: 'Vela x NOYA - Proposal.pdf',
    ready_class: 'READY_TO_SEND', ready_reason: 'The PDF is on the Gmail draft, checked byte for byte.',
    handoff: { external: true, email: false, pdf: pdf('vela-proposal', 1, 'Vela x NOYA - Proposal.pdf', true), draft: draft('r-test-draft-4', 't4', ['events@example.com']), attach: attach({ verified_at: '2026-10-21T22:00:00Z' }) } });
  const cover = doc('d0000000-0000-0000-0000-000000000005', { slug: 'lumen-egypt-email', version: 4, title: 'Lumen cover email', company: 'Lumen Middle East', company_id: CO.lumen, status: 'FOR_REVIEW', stage: 'email', doc_type: 'EMAIL_IDEA',
    ready_class: 'READY_FOR_ATTACHMENT', ready_reason: 'Cover email for brief v5.', handoff: { external: false, email: true, pdf: null, draft: draft('r-test-draft-1', 't1', ['jad@example.com']), attach: attach() } });
  const review = doc('d0000000-0000-0000-0000-000000000006', { slug: 'vela-itinerary', title: 'Three days on the Nile.', company: 'Vela', company_id: CO.vela, status: 'FOR_REVIEW', doc_type: 'ITINERARY', stage: 'itinerary', approved_at: null,
    ready_class: 'READY_FOR_ATTACHMENT', ready_reason: 'Passed the quality review.', handoff: { external: true, email: false, pdf: pdf('vela-itinerary', 1, 'Vela x NOYA - Itinerary.pdf', true), draft: null, attach: attach() } });
  const note = doc('d0000000-0000-0000-0000-000000000007', { slug: 'lumen-egypt-note', title: 'Lumen opportunity note', company: 'Lumen Middle East', company_id: CO.lumen, status: 'FOR_REVIEW', doc_type: 'OPPORTUNITY_NOTE', stage: 'note',
    ready_class: 'INTERNAL_ONLY', ready_reason: 'Internal.', handoff: { external: false, email: false, pdf: null, draft: null, attach: attach() } });
  const drafting = doc('d0000000-0000-0000-0000-000000000008', { slug: 'lumen-egypt-proposal', title: 'Lumen proposal', company: 'Lumen Middle East', company_id: CO.lumen, status: 'DRAFT', doc_type: 'PROPOSAL', stage: 'proposal',
    ready_class: 'HOLD', ready_reason: 'Held until they ask for numbers.', handoff: { external: true, email: false, pdf: null, draft: null, attach: attach() } });
  const sent = doc('d0000000-0000-0000-0000-000000000009', { slug: 'orbit-egypt-email-v2', title: 'Orbit first email', company: 'Orbit Agency', company_id: CO.orbit, status: 'SENT', stage: 'email', doc_type: 'EMAIL_IDEA', sent_at: '2026-10-19T20:48:00Z',
    ready_class: null, handoff: { external: false, email: true, pdf: null, draft: draft('r-test-draft-0', 't2', ['sophie@example.com'], { status: 'SENT', sent_at: '2026-10-19T20:48:00Z' }), attach: attach() } });
  const old = doc('d0000000-0000-0000-0000-000000000010', { slug: 'lumen-egypt-brief', version: 4, title: 'Egypt, under your creative lead.', company: 'Lumen Middle East', company_id: CO.lumen, status: 'SUPERSEDED',
    ready_class: 'SUPERSEDED', ready_reason: 'Replaced by v5.', handoff: { external: true, email: false, pdf: null, draft: null, attach: attach() } });
  const base = { ...F.studio, columns: { NEEDS_BRIEF: F.studio.columns?.NEEDS_BRIEF || { requests: [], warmed: [] }, DRAFTING: [drafting], NEEDS_REVIEW: [cover, review, note],
    APPROVED: [lumen, orbit, sable, vela], SENT: [sent], SUPERSEDED: { count: 1, recent: [old] } } };
  const withLumen = (h) => ({ ...base, columns: { ...base.columns, APPROVED: [{ ...lumen, ...h(lumen) }, orbit, sable, vela] } });
  STUDIO = base;
  const { browser, page, errors, calls } = await open({ width: 1440, height: 900 });
  await page.click('.nav-primary [data-tab="studio"]'); await page.waitForSelector('.kanban .sd-acts'); await page.waitForTimeout(150);
  const card = (id) => page.locator(`.sd[data-sd="${id}"]`);
  const labels = async (id) => (await card(id).locator('.sd-acts .btn').allTextContents()).map((t) => t.trim());
  const head = await txt(page, '.sready');
  check('Studio header: READY FOR ATTACHMENT and READY TO SEND counted apart (3 · 1), never “ready to send now”', /3 ready for attachment/.test(head) && /1 ready to send/.test(head) && !/ready to send now/.test(await txt(page, 'main')), head);
  check('Approved brief (not yet attached): Preview brief · Attach to Lumen email · Open Gmail draft', JSON.stringify(await labels(lumen.id)) === JSON.stringify(['Preview brief', 'Attach to Lumen email', 'Open Gmail draft']), (await labels(lumen.id)).join(' | '));
  check('Open Gmail draft opens the exact recorded draft', await card(lumen.id).locator('a.btn', { hasText: 'Open Gmail draft' }).getAttribute('href') === lumen.handoff.draft.url);
  check('The card connects relationship → PDF → Gmail draft → attached → sent, and says who the draft is to', /PDF/.test(await txt(page, `.sd[data-sd="${lumen.id}"] .hchain`)) && /Gmail draft/.test(await txt(page, `.sd[data-sd="${lumen.id}"] .hchain`))
    && /Draft to jad@example.com \+2/.test(await txt(page, `.sd[data-sd="${lumen.id}"]`)) && await card(lumen.id).locator('[data-open="company"]').count() === 1);
  const orbitText = await txt(page, `.sd[data-sd="${orbit.id}"]`);
  check('Scheduled brief: Preview brief · Attach now · Open draft · Scheduled: <date>', JSON.stringify(await labels(orbit.id)) === JSON.stringify(['Preview brief', 'Attach now', 'Open draft']) && /Scheduled: \d{1,2} [A-Z][a-z]{2}/i.test(orbitText), `${(await labels(orbit.id)).join(' | ')} — ${orbitText.slice(-60)}`);
  check('One-page concept: Preview concept · Attach to Sable’s email · Open Gmail draft', JSON.stringify(await labels(sable.id)) === JSON.stringify(['Preview concept', "Attach to Sable's email", 'Open Gmail draft']), (await labels(sable.id)).join(' | '));
  check('Ready to send: Open Gmail & send (the exact draft), and it says the PDF was checked in Gmail', JSON.stringify(await labels(vela.id)) === JSON.stringify(['Preview proposal', 'Open Gmail & send'])
    && await card(vela.id).locator('a.btn', { hasText: 'Open Gmail & send' }).getAttribute('href') === vela.handoff.draft.url && /Attached and checked in Gmail/.test(await txt(page, `.sd[data-sd="${vela.id}"]`)));
  check('Cover email: Open email draft, and it points to the card that carries its PDF', JSON.stringify(await labels(cover.id)) === JSON.stringify(['Open email draft']) && /Carries Lumen x NOYA - Egypt Brief\.pdf: attach it on the “Egypt, under your creative lead\.” card/.test(await txt(page, `.sd[data-sd="${cover.id}"]`)));
  check('Needs review → Review · Internal only → View · Drafting → Continue', (await labels(review.id))[0] === 'Review' && JSON.stringify(await labels(note.id)) === JSON.stringify(['View']) && JSON.stringify(await labels(drafting.id)) === JSON.stringify(['Continue']));
  check('Sent → View sent email · History · Superseded → View history', JSON.stringify(await labels(sent.id)) === JSON.stringify(['View sent email', 'History']) && JSON.stringify(await labels(old.id)) === JSON.stringify(['View history']));
  await page.screenshot({ path: 'tests/out/command/studio-handoff-1440.png', fullPage: true });

  // Preview of a stored PDF: a short-lived private link, opened in a new tab.
  await page.context().route('**/storage/v1/object/sign/**', (r) => r.fulfill({ contentType: 'application/pdf', body: pdfA }));
  const [pop] = await Promise.all([page.waitForEvent('popup'), card(sable.id).locator('[data-studio-preview]').click()]);
  await pop.waitForURL(/storage\/v1\/object\/sign\/studio-pdfs\/sable-onepage\/v1\.pdf/, { timeout: 5000 }).catch(() => {});
  check('Preview concept opens the stored PDF (a private 10-minute link) in a new tab', /studio-pdfs\/sable-onepage\/v1\.pdf/.test(pop.url()) && calls.some((c) => c.fn === 'storage.sign' && c.path === 'sable-onepage/v1.pdf'), pop.url());
  await pop.close();

  // Attach with no stored PDF yet: HQ asks for the file once. A wrong file is refused before anything is uploaded or attached.
  let [chooser] = await Promise.all([page.waitForEvent('filechooser'), card(lumen.id).locator('[data-studio-attach]').click()]);
  await chooser.setFiles(files.wrong); await page.waitForTimeout(400);
  check('Attach: a wrong file is refused before anything is uploaded or attached', /That is not the approved PDF for this card\. Choose “Lumen x NOYA - Egypt Brief\.pdf”/.test(await txt(page, '.banner'))
    && !calls.some((c) => c.fn === 'storage.upload' || c.fn === 'hq_studio_attach' || c.fn === 'hq_studio_pdf_stored'), await txt(page, '.banner'));
  ON_WRITE.hq_studio_attach = () => { STUDIO = withLumen(() => ({ handoff: { ...lumen.handoff, pdf: { ...lumen.handoff.pdf, stored: true }, attach: attach({ requested_at: new Date().toISOString() }) } })); };
  [chooser] = await Promise.all([page.waitForEvent('filechooser'), card(lumen.id).locator('[data-studio-attach]').click()]);
  await chooser.setFiles(files.right); await page.waitForTimeout(700);
  const up = calls.find((c) => c.fn === 'storage.upload'); const stored = last(calls, 'hq_studio_pdf_stored')?.body || {}; const att = last(calls, 'hq_studio_attach')?.body || {};
  check('Attach: the approved PDF (a re-render with only new timestamps) is saved once to its own place', up?.path === 'lumen-egypt-brief/v5.pdf'
    && stored.p_slug === 'lumen-egypt-brief' && stored.p_version === 5 && stored.p_bytes === pdfRerender.length && stored.p_fingerprint === pdfFingerprint(pdfA) && stored.p_sha256 === sha(pdfRerender), JSON.stringify(stored).slice(0, 160));
  check('Attach: then one call to attach this document version to its recorded draft (HQ never chooses a draft)', JSON.stringify(att) === JSON.stringify({ p_slug: 'lumen-egypt-brief', p_version: 5 }), JSON.stringify(att));
  check('Attach: the card shows it is attaching and checking Gmail; the notice says nothing is sent', /Attaching… checking Gmail/.test(await txt(page, `.sd[data-sd="${lumen.id}"]`)) && /Nothing is sent/.test(await txt(page, '.banner')), await txt(page, '.banner'));
  STUDIO = withLumen(() => ({ ready_class: 'READY_TO_SEND', handoff: { ...lumen.handoff, pdf: { ...lumen.handoff.pdf, stored: true }, attach: attach({ requested_at: new Date().toISOString(), verified_at: new Date().toISOString(), status_code: 200, result: { ok: true } }) } }));
  await page.waitForFunction(() => /Attached and checked in Gmail/.test(document.querySelector('.banner')?.textContent || ''), null, { timeout: 12000 }).catch(() => {});
  check('Verified: READY TO SEND only after Gmail is checked; the card now offers Open Gmail & send (the same draft)', /Attached and checked in Gmail/.test(await txt(page, '.banner'))
    && JSON.stringify(await labels(lumen.id)) === JSON.stringify(['Preview brief', 'Open Gmail & send']) && await card(lumen.id).locator('a.btn', { hasText: 'Open Gmail & send' }).getAttribute('href') === lumen.handoff.draft.url
    && /2 ready for attachment/.test(await txt(page, '.sready')) && /2 ready to send/.test(await txt(page, '.sready')), (await labels(lumen.id)).join(' | '));
  STUDIO = withLumen(() => ({ handoff: { ...lumen.handoff, pdf: { ...lumen.handoff.pdf, stored: true }, attach: attach({ requested_at: '2026-10-21T22:00:00Z', status_code: 424, result: { ok: false, reason: 'STEP_FAILED', step: 'Read the Gmail draft', message: 'Not found' } }) } }));
  await page.click('#refresh'); await page.waitForTimeout(150); await page.click('.nav-primary [data-tab="dashboard"]'); await page.click('.nav-primary [data-tab="studio"]'); await page.waitForSelector('.kanban .sd-acts'); await page.waitForTimeout(400);
  check('A failed attachment says which step failed and keeps Attach available; nothing is marked READY TO SEND', /Not attached: the step “Read the Gmail draft” failed \(Not found\)/.test(await txt(page, `.sd[data-sd="${lumen.id}"]`)) && (await labels(lumen.id)).includes('Attach to Lumen email'));
  STUDIO = base;

  // Review on the card: Approve, or Request changes with a note (refused without one).
  await page.click('#refresh'); await page.waitForTimeout(300);
  await card(review.id).locator('[data-modal="studio-review"]').click(); await page.waitForSelector('.modal #sr-note');
  check('Review: the document, its PDF and its relationship, with Approve and Request changes', /Three days on the Nile\./i.test(await txt(page, '.modal')) && await page.locator('.modal [data-studio-preview]').count() === 1 && await page.locator('.modal #sr-changes').count() === 1);
  await page.click('#sr-changes'); await page.waitForTimeout(150);
  check('Request changes without a note is refused before anything is recorded', !calls.some((c) => c.fn === 'hq_studio_document_action'));
  await page.fill('#sr-note', 'Lead with the boat, not the hotel.'); await page.click('#sr-changes'); await page.waitForTimeout(300);
  const ch = last(calls, 'hq_studio_document_action')?.body || {};
  check('Request changes: one call with the document version, CHANGES and the note', ch.p_slug === 'vela-itinerary' && ch.p_version === 1 && ch.p_action === 'CHANGES' && ch.p_note === 'Lead with the boat, not the hotel.', JSON.stringify(ch));
  await card(review.id).locator('[data-modal="studio-review"]').click(); await page.waitForSelector('.modal #m-ok'); await page.click('.modal #m-ok'); await page.waitForTimeout(300);
  const ap = last(calls, 'hq_studio_document_action')?.body || {};
  check('Approve: one call with the document version and APPROVE; it says nothing was sent', ap.p_slug === 'vela-itinerary' && ap.p_action === 'APPROVE' && /Nothing was sent/.test(await txt(page, '.banner')), JSON.stringify(ap));
  await card(old.id).locator('[data-modal="studio-history"]').click(); await page.waitForSelector('.modal');
  const hist = await txt(page, '.modal');
  check('View history: every Studio document for the relationship (versions, cover email, note, proposal)', /Lumen Middle East · Studio history/i.test(hist) && (hist.match(/Egypt, under your creative lead\./g) || []).length === 2 && /Lumen opportunity note/.test(hist) && /Lumen proposal/.test(hist), hist.slice(0, 160));
  await page.click('.modal [data-close]');
  check('Studio handoff: nothing is ever sent (no send, approve-draft or approve-email call)', !calls.some((c) => /send|approve_draft|approve_email/.test(c.fn)));
  check('No browser errors (Studio handoff, 1440)', errors.length === 0, errors.slice(0, 3).join(' | '));
  await browser.close();
  const phone = await open({ width: 390, height: 844 });
  await phone.page.click('#bmenu'); await phone.page.click('.sheet [data-tab="studio"]'); await phone.page.waitForSelector('.kanban .sd-acts'); await phone.page.waitForTimeout(150);
  check('Phone 390: the card buttons fit the screen', (await overflow(phone.page)) <= 1, `${await overflow(phone.page)}px`);
  await phone.page.screenshot({ path: 'tests/out/command/studio-handoff-390.png', fullPage: true });
  await phone.browser.close();
  STUDIO = null;
}
// 12. Why this lead (29 Oct): every Top 5 item opens its evidence (company, person, source, why now, project, channel, asset,
// what happens if they respond), with no technical IDs and nothing sent.
{
  const { browser, page, errors, calls } = await open({ width: 1440, height: 900 });
  await page.click('[data-tab="desk"]'); await page.waitForTimeout(200);
  const tab = page.locator('[data-desk-tab="TOP5"]'); if (await tab.count()) { await tab.first().click(); await page.waitForTimeout(150); }
  const btns = page.locator('[data-modal="lead-card"]');
  check('Why this lead: a button on the Top 5 rows', (await btns.count()) >= 1, `${await btns.count()} buttons`);
  await btns.first().click(); await page.waitForSelector('.modal .lc .lc-row'); await page.waitForTimeout(150);
  const t = await txt(page, '.modal');
  check('Why this lead: company, person, source, why now, project, channel, asset and next step', ['Orbit Weddings', 'Ana Test', 'Source', 'Why now', 'Project idea', 'Email first', 'Nothing attached', 'If they respond'].every((w) => t.includes(w)), t.slice(0, 160));
  check('Why this lead: ready line, and no technical IDs on screen', /Ready: all seven questions answered/.test(t) && !/[0-9a-f]{8}-[0-9a-f]{4}-/.test(t));
  check('Why this lead: one read, nothing written or sent', calls.some((c) => c.fn === 'hq_lead_card') && !calls.some((c) => /send|approve/.test(c.fn)));
  await page.screenshot({ path: 'tests/out/command/lead-card-1440.png' });
  check('No browser errors (Why this lead)', errors.length === 0, errors.slice(0, 3).join(' | '));
  await browser.close();
}
server.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed${failed.length ? ` — ${failed.length} failed` : ''}`);
process.exit(failed.length ? 1 : 0);
