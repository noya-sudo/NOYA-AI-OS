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
const qItem = (i, o = {}) => ({ id: uid(800 + i), rank: i + 1, state: 'QUEUED', opportunity_id: uid(100 + i), company_id: uid(500 + i), person: `Test Person ${String.fromCharCode(65 + i)}`, position: 'Founder',
  company: `Example Atelier ${i}`, stream: 'WEDDINGS', stream_label: 'Weddings', category: 'WEDDINGS_EVENTS', category_label: 'Wedding planners / private events', market: 'EGYPT',
  project_idea: `A three-day destination celebration in Egypt for Example Atelier ${i}'s clients.`, why_now: 'They announced an international wedding season with new destinations.',
  route_email: `office${i}@example-atelier.com`, route_canonical: 'OFFICIAL_PUBLISHED_INBOX', route_label: 'Official published inbox · for their attention', route_source_type: 'OFFICIAL_WEBSITE',
  route_source_url: `https://example-atelier-${i}.com/contact`, confidence: 'MEDIUM', draft_subject: `Example Atelier ${i} and NOYA`, draft_excerpt: 'For the attention of Test Person… A short, specific note.',
  draft_status: 'READY_FOR_REVIEW', has_gmail_draft: false, task_id: uid(700 + i), next_action: 'Review in Supabase and approve before any outreach',
  next_step: 'Review the draft in the approval desk; approving creates an unsent Gmail draft', failed: [], score: 60 - i, sendable_today: true, send_window: 'Today', ...o });
const LANE_BASE = () => ({ ok: true, date: day(0), built_at: now(), morning_at: now(), stale: false,
  counts: { act_now: 5, today: 3, today_sent: 1, reserve: 2, needs_contact: 2, needs_draft: 7, follow_ups: 2, replies: 2 },
  allowance: { mode: 'ACTIVE', stage: 1, stages: [5, 10, 15, 20, 25], daily_cap: 5, stage_cap: 5, sent_today: 1, remaining: 4, slots: ['11:05', '12:40', '14:15', '15:50'], slot_zone: 'Cairo',
    markets_today: ['EGYPT', 'GCC'], warm_pending: 5, reasons: [], rule: 'Nothing is sent automatically.' },
  funnel: { considered: 849, screened: 754, researched: 70, ready: 25, ready_unique_companies: 25 },
  coverage: { WEDDINGS_EVENTS: { label: 'Wedding planners / private events', considered: 100, ready: 21, today: 3 }, HOTELS_RESIDENCES: { label: 'Hotels / branded residences', considered: 50, ready: 4, today: 1 } },
  shortfall: 0, bottleneck: 'personalised_draft', learning: { clean_sends: 0, excluded_21_nov: 35, weights_active: 0 }, total: 0, limit: 25, offset: 0, extra: {} });
export const LANE_FX = (lane) => {
  const B = LANE_BASE(); let items = [];
  if (lane === 'TODAY') items = [qItem(0, { draft_status: 'GMAIL_DRAFT', has_gmail_draft: true, next_step: 'Send the unsent Gmail draft yourself, in a send window' }),
    qItem(1, { route_email: 'test.person@example-house.com', route_canonical: 'CLAY_WORK_EMAIL', route_label: 'Clay work email · not independently verified', route_source_type: 'CLAY', route_source_url: null, confidence: 'LOW', market: 'UK', sendable_today: false, send_window: 'Mon 23 Nov' }),
    qItem(2, { route_canonical: 'PUBLIC_BUSINESS_EMAIL_INSTAGRAM', route_label: 'Public business email · Instagram · not SMTP-verified', route_source_type: 'INSTAGRAM_PUBLIC', route_source_url: 'https://www.instagram.com/example', confidence: 'MEDIUM' }),
    qItem(3, { state: 'SENT' })];
  if (lane === 'RESERVE') items = [qItem(4, { rank: 26 }), qItem(5, { rank: 27 })];
  if (lane === 'NEEDS_CONTACT') items = [qItem(6, { failed: ['contact_route', 'route_classification'], route_email: null, route_label: 'Not found', confidence: null, next_step: 'Find the right person and a sourced professional route' }), qItem(7, { person: null, failed: ['real_account_person', 'decision_maker'] })];
  if (lane === 'FOLLOW_UPS') { items = [{ opportunity_id: uid(130), company: 'Example Follow Co', person: 'Test Person F', stream_label: 'Brands', status: 'CONTACTED', due_on: day(1), next_action: 'Follow up if no reply.', last_sent: now() }]; B.extra = { held_21_nov: 38, hold_rule: 'Releasing them is Adam\'s decision.' }; }
  if (lane === 'REPLIES') items = [{ thread_id: 'thread-1', company: 'Example Reply Co', subject: 'Re: Example', summary: 'Interested in a call next week.', last_inbound_at: now(), classification: 'POSITIVE', supplier: false, url: 'https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#all/thread-1', opportunity_id: uid(131) }];
  if (lane === 'ACT_NOW') { items = FX.hq_today().actions; B.extra = { more: 0 }; }
  return { ...B, lane, items, total: items.length };
};
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
  hq_outreach_lanes: (b) => LANE_FX(b?.p_lane || 'TODAY'),
  hq_outreach_draft: (b) => ({ ok: true, id: b?.p_id, company: 'Example Atelier', person: 'Test Person A', to: 'office@example-atelier.com', route_label: 'Official published inbox · for their attention',
    subject: 'Example Atelier and NOYA', body: 'For the attention of Test Person A\n\nHi Test,\n\nA short, specific note about one project idea.\n\nBest,\nAdam', draft_status: 'GMAIL_DRAFT',
    gmail_draft_url: 'https://mail.google.com/mail/u/0/#drafts?compose=abc', rule: 'Unsent. Approving in the desk creates an unsent Gmail draft; Adam sends it himself.' }),
  hq_seasons: () => ({ generated_at: now(), horizon: 180, counts: { d30: 1, d60: 2, d90: 2, d180: 3, act_now: 1 }, undated_rule: 'NO SOURCE = NO DATE',
    windows: [
      { id: uid(901), name: 'Example Fashion Week', category: 'FASHION_WEEK', market: 'EUROPE', stream: 'STREAM_7', stream_label: 'Stream 7', starts_on: day(20), ends_on: day(26), lead_time_days: 45, outreach_from: day(-25), outreach_to: day(5), angle: 'Brand hospitality around the shows.', accounts: 'Example houses', source_url: 'https://example.org/fashion-calendar', source_title: 'Official calendar', verified: now(), confidence: 'VERIFIED', days_to_start: 20, act_now: true, bucket: 30 },
      { id: uid(902), name: 'Example Festival', category: 'FILM_FESTIVAL', market: 'EUROPE', stream: 'STREAM_18', stream_label: 'Stream 18', starts_on: day(50), ends_on: day(55), lead_time_days: 90, outreach_from: day(-40), outreach_to: day(20), angle: 'Talent hospitality.', accounts: null, source_url: 'https://example.org/festival', source_title: 'Festival site', verified: now(), confidence: 'ESTIMATE', days_to_start: 50, act_now: false, bucket: 60 },
      { id: uid(903), name: 'Example Yacht Show', category: 'YACHTING', market: 'EUROPE', stream: 'STREAM_1', stream_label: 'Stream 1', starts_on: day(150), ends_on: day(153), lead_time_days: 120, outreach_from: day(30), outreach_to: day(110), angle: 'Charter conversations.', accounts: null, source_url: 'https://example.org/yacht', source_title: 'Show site', verified: now(), confidence: 'ESTIMATE', days_to_start: 150, act_now: false, bucket: 180 },
    ] }),
  hq_tool_scout: () => ({ generated_at: now(), quiet: { hold: 2, reject: 1, decided: 0 }, rule: 'Research and recommend only.',
    surfaced: [{ id: uid(950), tool: 'Example Deliverability Tool', vendor_url: 'https://example.org/tool', capability_area: 'DELIVERABILITY', capability_gap: 'No visibility into spam placement for the clean cohort.', why_noya: 'Low-volume, high-value outreach needs early warning.', improves_replaces: 'Adds a deliverability signal.', price_model: null, price_source_url: null, price_verified_at: null, privacy_risk: 'LOW', privacy_note: 'Aggregate data only.', integration_effort: 'LOW', expected_benefit: 'Protects the clean cohort before damage.', recommendation: 'TEST', evidence_urls: ['https://example.org/docs'], status: 'PROPOSED' }] }),
  hq_tool_scout_decide: () => ({ ok: true, status: 'APPROVED_BY_ADAM' }),
  hq_partnerships: () => ({ generated_at: now(), counts: { DISCUSSION: 2 },
    rows: [
      { id: uid(970), partner_name: 'Example Agency', partnership_type: 'WHITE_LABEL', tier: 'MULTIPLIER', status: 'DISCUSSION', exclusivity: 'NON_EXCLUSIVE', they_control: 'Brand activation briefs', noya_controls: 'Egypt execution', they_can_refer: 'Activations in Egypt', noya_can_refer: 'Brands needing an agency', first_test_project: 'One activation', money_model: null, conflict: null, agreement_required: 'UNKNOWN', verification: {}, term_sheet: null, notes: null },
      { id: uid(971), partner_name: 'Example Broker', partnership_type: 'COMMISSION', tier: 'EXECUTION_SUPPLIER', status: 'DISCUSSION', exclusivity: 'NON_EXCLUSIVE', they_control: 'Charter supply', noya_controls: 'Client relationship', they_can_refer: null, noya_can_refer: 'Charter requests', first_test_project: null, money_model: '10% of broker net margin', conflict: null, agreement_required: 'YES',
        verification: { legal_identity: { claimed: 'Example SAS', status: 'CLAIMED_NOT_VERIFIED' }, role: { value: 'Broker, not an operator', status: 'SELF_DECLARED' } },
        term_sheet: { status_note: 'DRAFT for Adam / legal review. Not legal advice. Not binding.', sections: [{ key: 'PARTIES', title: 'Parties', content: 'NOYA Concierge and Example Broker.' }, { key: 'EXCLUSIVITY', title: 'Exclusivity', content: 'NON-EXCLUSIVE (default).' }] }, term_sheet_prepared_at: now(), notes: 'Verify, sign nothing.' },
    ] }),
  hq_prepare_term_sheet: () => ({ ok: true, sections: 31 }),
  hq_partnership_status: () => ({ ok: true, status: 'LEGAL_REVIEW' }),
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
  check('Primary navigation is Today, Opportunities, Outreach, Streams, Relationships, Projects (+ More)', (await page.locator('.nav-primary .nav-item').allInnerTexts()).map((x) => x.replace(/\d+/g, '').trim()).join('|') === 'Today|Opportunities|Outreach|Streams|Relationships|Projects' && await page.locator('#nav-more').count() === 1);
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
  await page.waitForSelector('[data-lane="ALL"]', { timeout: 6000 }).catch(() => {});
  await page.locator('[data-lane="ALL"]').click();
  await page.waitForSelector('.row4[data-lopp]', { timeout: 6000 }).catch(() => {});
  let t = await mainText(page);
  check('Outreach shows the send allowance and the approval desk count', /Send allowance today: 5 new first touches/.test(t) && /waiting for your review in the approval desk/.test(t));
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
// 5b. Daily acquisition policy: Outreach lanes (Act now, Today's 25, Reserve, Needs contact, Follow-ups, Replies), the send allowance,
// the ten fields on each Today card, truthful route classes, draft on demand, and no send button anywhere.
{
  const { browser, page, errors, calls } = await open({ hash: 'mail' });
  await page.waitForSelector('.q4', { timeout: 6000 }).catch(() => {});
  let t = await mainText(page);
  check('Outreach opens on Today’s 25 from one small lane read (no route explorer read)', last(calls, 'hq_outreach_lanes').p_lane === 'TODAY' && n(calls, 'hq_email_routes') === 0
    && await page.locator('.lane4.on[data-lane="TODAY"]').count() === 1);
  const lanes = (await page.locator('.lane4').allTextContents()).map((x) => x.replace(/\d+/g, '').trim());
  check('Lanes: Act now, Today’s 25, Reserve, Needs contact, Follow-ups, Replies (+ All routes) with counts', lanes.join('|') === 'Act now|Today’s|Reserve|Needs contact|Follow-ups|Replies|All routes'
    && /Act now\s*5/.test(t) && /Needs contact\s*2/.test(t), lanes.join('|'));
  check('Send allowance: stage, cap, sent, left, spread slots, warm first, manual-send rule', /Send allowance today: 5 new first touches/.test(t) && /ramp stage 1 of 5/.test(t) && /1 sent · 4 left/.test(t)
    && /11:05, 12:40, 14:15, 15:50 Cairo/.test(t) && /Warm first: 5 items in Act now come before any new send/.test(t) && /Nothing is sent automatically/.test(t));
  const card = page.locator('.q4').first(); const ct = await card.evaluate((el) => el.textContent.replace(/\s+/g, ' '));
  const dts = await card.locator('dt').allTextContents();
  check('Each Today card shows person, company, stream, project idea, why now, route, route source, confidence, draft and next action',
    dts.join('|') === 'Project idea|Why now|Contact route|Route source|Prepared draft|Next action' && /Test Person A/.test(ct) && /Example Atelier 0/.test(ct) && /Weddings/.test(ct) && /confidence/i.test(ct)
    && /office0@example-atelier.com/.test(ct) && /Official website/.test(ct) && /Unsent Gmail draft ready/.test(ct) && /Send the unsent Gmail draft yourself/.test(ct));
  check('Today shows four cards (three queued, one marked sent last)', await page.locator('.q4').count() === 4 && await page.locator('.q4.sent').count() === 1
    && /Sent/.test(await page.locator('.q4').nth(3).evaluate((el) => el.textContent)));
  const clay = await page.locator('.q4').nth(1).evaluate((el) => el.textContent.replace(/\s+/g, ' '));
  check('Clay route stays truthful: "not independently verified", Low confidence, no source link', /not independently verified/.test(clay) && /Low confidence/.test(clay) && await page.locator('.q4').nth(1).locator('a:has-text("where it was found")').count() === 0
    && /Send Mon 23 Nov/.test(clay), clay.slice(0, 400));
  check('Instagram route is labelled as public Instagram with its link', /Public Instagram business profile/.test(await page.locator('.q4').nth(2).evaluate((el) => el.textContent)) && await page.locator('.q4').nth(2).locator('a[href^="https://www.instagram.com"]').count() === 1);
  check('Route provenance link opens the page where the address was found', await page.locator('.q4').first().locator('a[href="https://example-atelier-0.com/contact"]').count() === 1);
  check('Funnel and mix are shown, never as a quota', /849\s*Considered/.test(t) && /25\s*Send-ready/.test(t) && /Mix today: Wedding planners \/ private events 3/.test(t) && /never forced into equal quotas/.test(t), t.slice(0, 900));
  check('No send button anywhere on Outreach (manual send in Gmail only)', await page.locator('main button, main a').filter({ hasText: /^\s*(send|send now|send email|send all)\s*$/i }).count() === 0
    && n(calls, 'hq_send') === 0);
  await page.locator('.q4').first().locator('[data-draft-open]').click(); await page.waitForSelector('.q4-dr pre', { timeout: 4000 }).catch(() => {});
  check('Read the full draft loads one draft on demand, with the unsent Gmail link', last(calls, 'hq_outreach_draft').p_id === uid(800) && /A short, specific note about one project idea/.test(await page.locator('.q4-dr pre').textContent().catch(() => ''))
    && await page.locator('.q4-dr a[href^="https://mail.google.com"]').count() === 1);
  await page.locator('[data-lane="NEEDS_CONTACT"]').click(); await page.waitForSelector('.row4[data-lopp]', { timeout: 4000 }).catch(() => {});
  t = await mainText(page);
  check('Needs contact lists accounts with the missing gates, nothing guessed', last(calls, 'hq_outreach_lanes').p_lane === 'NEEDS_CONTACT' && /Missing: professional route, route class/.test(t) && /No confirmed person yet/.test(t));
  await page.locator('[data-lane="FOLLOW_UPS"]').click(); await page.waitForTimeout(500); t = await mainText(page);
  check('Follow-ups shows due items and the held 21 Nov batch as Adam’s decision', /38 follow-ups from the 21 Nov batch are held/.test(t) && /Example Follow Co/.test(t));
  await page.locator('[data-lane="REPLIES"]').click(); await page.waitForTimeout(500);
  check('Replies opens the Gmail thread', await page.locator('main a[href*="#all/thread-1"]').count() === 1 && /Positive/.test(await mainText(page)));
  await page.locator('[data-lane="ACT_NOW"]').click(); await page.waitForTimeout(500);
  check('Act now shows the warm work first (the same cards as Today)', await page.locator('main .ca4').count() === 5 && /outrank every new send/.test(await mainText(page)));
  await page.locator('[data-lane="RESERVE"]').click(); await page.waitForTimeout(500);
  check('Reserve shows the send-ready records behind the 25', await page.locator('.q4').count() === 2 && /behind Today’s 25/.test(await mainText(page)));
  check('Primary navigation unchanged by the lanes', (await page.locator('.nav-primary .nav-item').allInnerTexts()).map((x) => x.replace(/\d+/g, '').trim()).join('|') === 'Today|Opportunities|Outreach|Streams|Relationships|Projects');
  check('No uncaught page errors on the Outreach lanes', errors.length === 0, errors.join(' | '));
  await browser.close();
}
// 5c. Shortfall and a paused ramp are stated plainly; the gap is never padded.
{
  const { browser, page, errors } = await open({ hash: 'mail', behave: (fn, b) => (fn === 'hq_outreach_lanes' ? { ...LANE_FX(b?.p_lane || 'TODAY'), shortfall: 22, bottleneck: 'contact_route',
    allowance: { mode: 'STOPPED', stage: 2, stages: [5, 10, 15, 20, 25], daily_cap: 0, stage_cap: 10, sent_today: 0, remaining: 0, slots: [], markets_today: ['UK'], warm_pending: 0, reasons: ['Bounce spike: 2 or more bounces in 3 days'] } } : undefined) });
  await page.waitForSelector('.q4', { timeout: 6000 }).catch(() => {});
  const t = await mainText(page);
  check('Shortfall says how many and why, and that nothing is padded', /Short of 25 by 22/.test(t) && /contact routes/.test(t) && /not filled with weaker accounts/.test(t));
  check('A stop signal pauses new first touches and says why', /New cold first touches are paused today/.test(t) && /Bounce spike/.test(t) && !/Send allowance today/.test(t));
  check('No uncaught page errors (shortfall / paused)', errors.length === 0, errors.join(' | '));
  await browser.close();
}
// 6. Outreach routes fail → Retry; the summary still draws.
{
  let fail = true;
  const { browser, page } = await open({ hash: 'mail', behave: (fn) => (fn === 'hq_email_routes' && fail ? { status: 503, json: { message: 'upstream' } } : undefined) });
  await page.waitForSelector('[data-lane="ALL"]', { timeout: 6000 }).catch(() => {}); await page.locator('[data-lane="ALL"]').click();
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
  check('Streams lists all 36 streams in 4 pillars', await page.locator('.sm4-row').count() === 36 && await page.locator('main .v4:has(.sm4-head)').count() === 4);
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
// 7b. Seasonal calendar on Streams: sourced windows only, rolling horizons, empty state.
{
  const { browser, page, errors } = await open({ hash: 'streams' });
  await page.waitForSelector('.se4', { timeout: 6000 }).catch(() => {});
  const n90 = await page.locator('.se4').count();
  const sourced = await page.locator('.se4 a[href^="https://"]').count();
  check('Seasonal calendar lists windows within 90 days by default, each with its source link', n90 === 2 && sourced === n90, `${n90} windows, ${sourced} sources`);
  check('Open outreach windows are flagged and confidence is labelled', /Outreach window open/.test(await mainText(page)) && await page.locator('.se4 .lbl.est').count() >= 1);
  await page.locator('[data-season-h="180"]').click(); await page.waitForTimeout(100);
  check('180-day horizon shows the later window too', await page.locator('.se4').count() === 3);
  await page.locator('[data-season-h="30"]').click(); await page.waitForTimeout(100);
  check('30-day horizon narrows the list', await page.locator('.se4').count() === 1);
  check('No uncaught page errors on the seasonal calendar', errors.length === 0, errors.join(' | '));
  await browser.close();
}
{
  const { browser, page } = await open({ hash: 'streams', behave: (fn) => (fn === 'hq_seasons' ? { generated_at: now(), horizon: 180, counts: { d30: 0, d60: 0, d90: 0, d180: 0, act_now: 0 }, windows: [] } : undefined) });
  await page.waitForSelector('.sm4-row', { timeout: 6000 }).catch(() => {}); await page.waitForTimeout(400);
  check('Seasonal empty state explains the rule (no source, no date)', /No sourced seasonal windows in the next 90 days/.test(await mainText(page)) && /No source, no date/.test(await mainText(page)));
  await browser.close();
}
// 7c. Tool / source scout under System / Admin: gated recommendations; a decision records only.
{
  const { browser, page, errors, calls } = await open({ hash: 'system' });
  await page.waitForSelector('.ts4', { timeout: 8000 }).catch(() => {});
  const t = await mainText(page);
  check('Tool scout shows only surfaced recommendations (TEST/ADOPT); held and rejected stay quiet', await page.locator('.ts4').count() === 1 && /2 held · 1 rejected \(not shown\)/.test(t));
  check('Recommendation shows the required fields (gap, benefit, price, privacy, effort, evidence)', ['Capability gap', 'Why NOYA benefits', 'Improves / replaces', 'Price', 'Data / privacy', 'Integration effort', 'Expected benefit', 'Evidence'].every((x) => t.includes(x)) && /Not verified/.test(t));
  await page.locator('[data-scout][data-to="APPROVED_BY_ADAM"]').click(); await page.waitForTimeout(400);
  const d = last(calls, 'hq_tool_scout_decide');
  check('Approve records the decision via hq_tool_scout_decide (nothing bought)', d.p_decision === 'APPROVED_BY_ADAM' && d.p_id === uid(950) && /Nothing was bought or connected/.test(await page.locator('.banner').innerText().catch(() => '')));
  check('No uncaught page errors on System / Admin', errors.length === 0, errors.join(' | '));
  await browser.close();
}
// 7d. Partnership agreements: eight questions, verification, term-sheet preparation, status rules.
{
  const { browser, page, errors, calls } = await open({ hash: 'partners' });
  await page.waitForSelector('.pa-row', { timeout: 8000 }).catch(() => {});
  check('Partnerships lists agreements with multipliers first', (await page.locator('.pa-row .sm4-name').allInnerTexts())[0]?.startsWith('Example Agency'));
  await page.locator(`[data-pa-open="${uid(970)}"]`).click(); await page.waitForTimeout(100);
  let t = await mainText(page);
  check('An agreement shows the eight partnership questions and NON-EXCLUSIVE default', ['What they control', 'What NOYA controls', 'What they can refer', 'What NOYA can refer', 'First project to test', 'How money works', 'Conflict', 'Agreement required'].every((x) => t.includes(x)) && /Non-exclusive \(default\)/.test(t) && /To agree; never assumed/.test(t));
  await page.locator(`[data-pa-sheet="${uid(970)}"]`).click(); await page.waitForTimeout(400);
  check('Prepare term sheet calls hq_prepare_term_sheet for that agreement', last(calls, 'hq_prepare_term_sheet').p_id === uid(970));
  await page.locator(`[data-pa-open="${uid(971)}"]`).click(); await page.waitForTimeout(100);
  t = await mainText(page);
  check('A prepared term sheet is a labelled draft; verification shows claimed vs verified', /Not legal advice\. Not binding/.test(t) && /Claimed not verified/.test(t));
  const before = calls.filter((c) => c.fn === 'hq_partnership_status').length;
  await page.selectOption(`[data-pa-status="${uid(971)}"]`, 'SIGNED'); await page.locator(`[data-pa-save="${uid(971)}"]`).click(); await page.waitForTimeout(200);
  check('Marking SIGNED without a note is blocked (no call)', calls.filter((c) => c.fn === 'hq_partnership_status').length === before);
  await page.selectOption(`[data-pa-status="${uid(971)}"]`, 'LEGAL_REVIEW'); await page.locator(`[data-pa-save="${uid(971)}"]`).click(); await page.waitForTimeout(400);
  check('Status change records via hq_partnership_status', last(calls, 'hq_partnership_status').p_status === 'LEGAL_REVIEW');
  check('No uncaught page errors on Partnerships', errors.length === 0, errors.join(' | '));
  await browser.close();
}
// 7e. Agents lives under More; its deep link still works and highlights it there.
{
  const { browser, page, errors } = await open({ hash: 'agents' });
  await page.waitForTimeout(1500);
  check('Agents opens from More (expanded, item active), not from the primary navigation', await page.locator('.nav-group .nav-item.active[data-tab="agents"]').count() === 1 && await page.locator('.nav-primary [data-tab="agents"]').count() === 0);
  check('No uncaught page errors on Agents', errors.length === 0, errors.join(' | '));
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
