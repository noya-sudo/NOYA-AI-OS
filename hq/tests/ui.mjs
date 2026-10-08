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
const relationships = JSON.parse(readFileSync('tests/fixtures/relationships.json', 'utf8'));
// Test-only variant: live data can hold no ready approval (every pending one blocked for a reason). The approval-loop checks need one,
// so a real blocked draft whose address was unverified is treated as verified in memory only, and the Today scorecard counts it too.
if (!snapshot.approvals.some((a) => a.loop_stage === 'PENDING_APPROVAL' && !a.block_reason)) {
  const a = snapshot.approvals.find((x) => x.loop_stage === 'PENDING_APPROVAL' && /^EMAIL_NOT_VERIFIED/.test(x.block_reason || '') && x.draft?.subject && x.draft?.body);
  if (a) {
    Object.assign(a, { block_reason: null, email_status: 'VERIFIED' });
    overview.scorecard.approvals_ready.n += 1;
    console.log(`NOTE  no ready approval in the live data; the test treats ${a.company_name}'s draft as verified (in memory only)`);
  }
}
// Agents fixtures: a trimmed live agents_snapshot() and agent_detail('HOSPITALITY') (git-ignored, real data only).
const agentsFx = existsSync('tests/fixtures/agents.json') ? JSON.parse(readFileSync('tests/fixtures/agents.json', 'utf8')) : null;
const agentFx = existsSync('tests/fixtures/agent_hospitality.json') ? JSON.parse(readFileSync('tests/fixtures/agent_hospitality.json', 'utf8')) : null;
// Email review fixture: a live hq_email_review() read (git-ignored, real data only). Test-only variant: the same real draft once its
// address is SMTP-verified, so the Approve path can be exercised next to the unverified one.
const erFx = existsSync('tests/fixtures/email_review.json') ? JSON.parse(readFileSync('tests/fixtures/email_review.json', 'utf8')) : null;
const ER_TEST_ID = '00000000-0000-0000-0000-0000000000e1';
const erTest = erFx ? { ...erFx, needs_review: [...erFx.needs_review,
  ...erFx.needs_review.slice(0, 1).map((x) => ({ ...x, candidate_id: ER_TEST_ID, task_id: null, email_state: 'VERIFIED', verified_at: erFx.verification.last_run, verified_score: 100 }))] } : null;
mkdirSync('tests/out', { recursive: true });

// Execution fixture (shaped like hq_execution: queue health + weekly metrics by segment).
const execution = {
  actions: { target: '15-20 commercial actions a working day', count: 4, waiting_revalidation: 2, waiting_for_person: 16,
    by_group: { Reply: 1, 'Warm opportunity': 1, 'Follow up': 1, 'Partnership outreach': 1 },
    items: [{ rank: 1, group: 1, action: 'Reply', company: 'YKONE Middle East', lane: 'BRANDS', channel: 'EMAIL', detail: 'Asked for rates for a March shoot' },
      { rank: 2, group: 2, action: 'Warm opportunity', company: 'Baron Hotels', lane: 'PARTNERSHIPS', channel: null, detail: 'WARM ROUTE — reconnect' },
      { rank: 3, group: 3, action: 'Follow up', company: 'Lightfoot Travel', lane: 'TRAVEL_PRIVATE', channel: null, detail: 'FOLLOW UP — day 4' },
      { rank: 4, group: 4, action: 'Partnership outreach', company: 'Cheval Collection', lane: 'PARTNERSHIPS', channel: 'LINKEDIN', detail: 'LINKEDIN MESSAGE READY — Cheval Collection' }] },
  scorecard: { new_companies: 43, new_companies_by_source: { Agents: 13, ChatGPT: 13, 'Other research': 17 }, new_decision_makers: 116, new_public_emails: 19, new_linkedin_routes: 121,
    new_instagram_routes: 27, outreach_ready: 26, hospitality_partnerships: 10, media_concepts: 4, wedding_prospects: 5, brands_production_prospects: 14, sends: 6, replies: 5, calls: 1,
    serper: { balance: 41045, per_cycle: 1950, cycle_usd: 1.95, runway_days: 63, per_day_basis: 'PLANNED (under a day of readings)' } },
  today: { date: '2026-10-07', target: { floor: 15, target: 20 }, totals: { discovered: 16, send_ready: 51, awaiting_approval: 8, linkedin: 46, instagram: 3, emails: 9, follow_ups_due: 18, sent_today: 0, replies_today: 2, meetings_today: 0 },
    planned_today: { planned: 16, ready: 12, review_required: 4, dry_run: true },
    lanes: [{ lane: 'BRANDS', discovered: 7, send_ready: 3, awaiting_approval: 0, linkedin: 3, instagram: 1, emails: 0, follow_ups_due: 0, sent_today: 0, replies_today: 0, meetings_today: 0 }],
    conversations: [{ company: 'YKONE Middle East', state: 'MEETING_BOOKED' }] },
  cycle: { target: { cycle_floor: 60, cycle_target: 75 }, totals: { outreach_ready: 41, discovered: 88, qualified: 52, confirmed_people: 49, email_ready: 6, linkedin_ready: 40, research_required: 30 },
    agents: [{ lane: 'PARTNERSHIPS', discovered: 30, qualified: 18, confirmed_people: 17, outreach_ready: 14 }, { lane: 'TRAVEL_PRIVATE', discovered: 9, qualified: 5, confirmed_people: 5, outreach_ready: 4 }] },
  ai_budget: { mtd_usd: 0.42, today_usd: 0.03, target_usd: 5, ceiling_usd: 10, status: 'OK' },
  engine: { drafted: 16, system_ready: 0, system_ready_pct: 0, final_ready_after_human_review: 13, avg_calls: 1.4, avg_cost_usd: 0.0021 },
  hunter: { credits: 48, usable_emails: 11, usable_rate: 34, credits_per_usable: 4.4, sent: 5, replies: 1, meetings: 0, gate: 'Hunter runs only for a confirmed, high-priority decision maker.' },
  queue: { ready: 42, target: 45, universe: 64, universe_target: '300–500 named accounts, built progressively', verify_first: 4,
  universe_by_status: { QUALIFIED: 64, NEEDS_REVIEW: 21, RESEARCHING: 51 },
  rule: 'Quality first: a shortfall is shown, never filled with weak prospects.',
  lines: [{ key: 'email', label: 'New emails', per_day: 5, ready: 15, target: 15, shortfall: 0 }, { key: 'linkedin', label: 'LinkedIn / DM', per_day: 5, ready: 37, target: 15, shortfall: 0 },
    { key: 'follow_up', label: 'Follow-ups due', per_day: 3, ready: 10, target: 9, shortfall: 0 }, { key: 'warm', label: 'Warm reconnects / replies', per_day: 2, ready: 3, target: 6, shortfall: 3 }] },
  weekly: { weeks: ['28 Sep'], note: 'Allocation changes are recommendations only.', rows: [
    { week: '28 Sep', week_start: '2026-09-28', segment: 'BRAND_PR_PRODUCTION', qualified: 11, contacts: 5, verified: 4, linkedin_ready: 2, sends: 5, replies: 2, positive: 2, meetings: 0, proposals: 0, wins: 0, revenue: null },
    { week: '28 Sep', week_start: '2026-09-28', segment: 'TRAVEL_PARTNER', qualified: 8, contacts: 8, verified: 0, linkedin_ready: 3, sends: 0, replies: 0, positive: 0, meetings: 0, proposals: 0, wins: 0, revenue: null }] } };

// Commercial core fixture (self-contained, shaped like hq_commercial / hq_account).
const cOpps = snapshot.opportunities.slice(0, 3);
const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Africa/Cairo' });
const qs = (answered, missing) => ({ answered, of: 10, complete: answered === 10, missing, urgency: 'NOW',
  questions: ['What happened?', 'Why should NOYA care?', 'Who is behind it?', 'What problem could NOYA solve?', 'Which NOYA product?', 'Who likely decides?', 'Why would they care about NOYA?', 'Can we reach them?', 'When should we approach?', 'What happens next?']
    .map((q) => ({ q, a: missing.includes(q) ? null : 'answer', ok: !missing.includes(q) })) });
const commercial = {
  generated_at: new Date().toISOString(),
  team: { members: [{ name: 'Adam', roles: ['CEO', 'SALES'] }], routing: { CEO: 'Adam', SALES: 'Adam', PARTNERSHIPS: 'Adam', SDR: 'Adam', EVENTS: 'Adam', OPERATIONS: 'Adam', ACCOUNT_MANAGEMENT: 'Adam', REVOPS: 'Adam' } },
  weights: { strategic_fit: 25, timing: 20, service_fit: 20, access: 15, commercial_evidence: 10, source_confidence: 10 },
  products: [{ code: 'EVENT_CONCIERGE_DESK', name: 'NOYA Event Concierge Desk', summary: 'On-ground guest desk.', email_template: { subject: '{{event}} guests', body: 'Hi {{first_name}},' }, dm_template: 'Hi', follow_up_sequence: [{ day: 3, channel: 'EMAIL', purpose: 'Idea', message: 'One idea' }], objections: [{ objection: 'Agency handles it', response: 'We are their ground layer' }], call_points: ['Guest volumes'], included_services: ['24/7 guest line'], upsells: ['Sponsor guest programme'] },
    { code: 'VIP_GUEST_DESK', name: 'NOYA VIP Guest Desk', summary: 'Discreet VIP host.', email_template: { subject: 'VIP guests', body: 'Hi' }, follow_up_sequence: [], objections: [], call_points: [], included_services: [], upsells: [] }],
  playbooks: [{ code: 'FILM_FESTIVAL', name: 'Film festival', trigger_desc: 'A film festival with international guests.', track: 'EVENT', product_codes: ['VIP_GUEST_DESK', 'EVENT_CONCIERGE_DESK'], value_proposition: 'More than cars and tables.',
    decision_roles: ['Head of Guest Relations'], services: ['VIP handling', 'Room blocks'], research_questions: ['Who runs guest relations?'], objections: [], proof_required: [], upsells: [],
    target_orgs: [{ org_role: 'ORGANISER', why: 'VIP guest services', product: 'VIP_GUEST_DESK', track: 'EVENT' }], performance: { signals: 2, opportunities: 1, contacted: 0, engaged: 0, won: 0, lost: 0 } }],
  signals: [
    { id: 's1', title: 'El Gouna Film Festival 2026 takes place 15–23 October', source_name: 'CairoScene', source_url: 'https://cairoscene.com/x', discovered_at: new Date().toISOString(), event_date: '2026-10-15', event_end: '2026-10-23',
      destination: 'El Gouna', category: 'ENTERTAINMENT', region: 'EGYPT', relevance: 90, confidence: 85, urgency: 'NOW', stage: 'RESEARCH', provenance: 'SOURCE_BACKED', why: 'International guests for nine days.',
      playbook: 'FILM_FESTIVAL', products: ['VIP_GUEST_DESK'], owner: 'Adam', next_action: 'Find the Head of Guest Relations', qualification: qs(9, ['Can we reach them?']),
      ai: { angle: 'VIP guest desk for talent and sponsors', decision_roles: ['Head of Guest Relations'], provenance: 'INFERRED (AI from stored source text)' },
      orgs: [{ id: 'org-1', name: 'El Gouna Film Festival', role: 'ORGANISER', company_id: null, provenance: 'SOURCE_BACKED', partner: false }], opportunities: [], projects: [] },
    { id: 's2', title: 'HYROX Cairo 2026, 14–15 November', source_name: 'HYROX', source_url: 'https://hyrox.com/event/hyrox-cairo/', discovered_at: new Date().toISOString(), event_date: '2026-11-14', event_end: '2026-11-15',
      destination: 'Cairo', category: 'SPORTS', region: 'EGYPT', relevance: 85, confidence: 80, urgency: 'NOW', stage: 'QUALIFIED', provenance: 'SOURCE_BACKED', why: 'First race in Egypt.',
      playbook: 'FILM_FESTIVAL', products: ['EVENT_CONCIERGE_DESK'], owner: 'Adam', next_action: 'Create opportunities', qualification: qs(10, []),
      orgs: [{ id: 'org-2', name: 'HYROX', role: 'ORGANISER', company_id: directory.companies[0].id, provenance: 'SOURCE_BACKED', partner: false }], opportunities: [], projects: [] },
    { id: 's3', title: 'Old airshow', source_url: 'https://x', urgency: 'PASSED', stage: 'DISMISSED', category: 'TRAVEL', region: 'EGYPT', qualification: qs(7, []), orgs: [], opportunities: [], projects: [] }],
  queue: cOpps.map((o, i) => ({ id: o.id, company: o.company_name, company_id: directory.companies[0].id, person: 'Sara Khalil', role: 'Director', segment: 'HOSPITALITY', track: i ? 'SALES' : 'EVENT',
    trigger: 'El Gouna Film Festival 2026', product: 'VIP_GUEST_DESK', playbook: 'FILM_FESTIVAL', angle: 'VIP guest services', path: i ? 'NONE' : 'WARM',
    strength: { label: i ? 'NONE' : 'WARM', score: i ? 0 : 25, components: i ? [] : [{ evidence: '3 emails from them', points: 12 }] }, next_action: 'Prepare outreach', owner: 'Adam', due: today,
    status: 'RESEARCHING', stage: 'CONTACT_IDENTIFIED', has_draft: false, provenance: 'SOURCE_BACKED',
    score: { score: 80 - i * 10, computed: 80 - i * 10, components: [{ key: 'timing', label: 'Timing / urgency', points: 20, max: 20, why: 'Act now' }], note: 'Priority score, not money and not a probability of winning.' } })),
  partners: [{ id: 'p1', company_id: directory.companies[1].id, name: directory.companies[1].name, class: 'SUPPLY', category: 'Hotel', stage: 'ACTIVE', health: 'GOOD', opportunities: 0, projects: 0, revenue_invoices: 0, events: [], provenance: 'MANUALLY_CONFIRMED' }],
  projects: [{ id: 'pr1', name: 'Test Co — VIP Guest Desk', status: 'PLANNING', company: 'Test Co', items: [{ id: 'it1', item_type: 'HOTEL', title: 'Suites block', status: 'CONFIRMED' }], open_tasks: 1, issues: 0,
    invoiced: [], collected: [], currency: 'EUR', client_charge: 10000, supplier_cost: 6500, gross_profit: 3500, opportunity_id: cOpps[0].id, signal_id: 's1', project_type: 'VIP_GUEST_DESK' }],
  supply_partners: { Hotel: 1 },
};
const account = { company: { id: directory.companies[0].id, name: directory.companies[0].name }, strength: { score: 25, label: 'WARM', components: [{ points: 12, evidence: '3 emails from them' }], method: 'Behaviour only' },
  paths: [{ route: 'Direct email history', detail: '2 sent · 3 received', provenance: 'VERIFIED' }], people: [], linkedin: [], open_opportunities: [], past_opportunities: [],
  events: [{ title: 'El Gouna Film Festival 2026', role: 'ORGANISER', urgency: 'NOW' }], services: ['VIP handling'], why_now: 'El Gouna Film Festival 2026', outreach_history: [], notes: [], sources: ['https://cairoscene.com/x'] };

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.txt': 'text/plain', '.woff2': 'font/woff2', '.svg': 'image/svg+xml' };
const server = http.createServer((req, res) => {
  const p = join('dist', req.url === '/' ? 'index.html' : req.url.split('?')[0]);
  if (!existsSync(p) || !statSync(p).isFile()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': types[extname(p)] || 'application/octet-stream' });
  res.end(readFileSync(p));
});
await new Promise((r) => server.listen(4173, r));

// HQ V3 reads (live captures, git-ignored): the desk, the workforce, drill-downs, club, operations.
const fx = (f) => (existsSync(`tests/fixtures/${f}.json`) ? JSON.parse(readFileSync(`tests/fixtures/${f}.json`, 'utf8')) : null);
const V3FX = { desk: fx('desk'), ops: fx('operations'), directors: fx('directors'), club: fx('club'),
  HOSPITALITY: fx('director_hospitality'), PARTNERSHIPS: fx('director_partnerships'), GROWTH: fx('director_growth'), EMAIL: fx('director_email') };
const V3 = { hq_outreach_desk: () => V3FX.desk, hq_operations: () => V3FX.ops, hq_directors: () => V3FX.directors, hq_club: () => V3FX.club,
  hq_director: (b) => V3FX[b?.p_key] || { key: b?.p_key, sections: [] }, hq_growth: () => V3FX.GROWTH?.growth,
  hq_advisor: () => fx('advisor'), hq_weekly_review: () => fx('weekly') };
const WRITES = ['hq_task_dismiss', 'hq_opportunity_update', 'hq_add_note', 'hq_log_touch', 'hq_record_meeting', 'hq_change_channel', 'hq_connection_update',
  'hq_request_draft', 'hq_draft_action', 'hq_finance_upsert', 'hq_record_payment', 'hq_company_update', 'hq_history_action', 'hq_add_contact', 'hq_relationship_status', 'hq_service_update',
  'hq_signal_update', 'hq_signal_org', 'hq_signal_capture', 'hq_signal_promote', 'hq_signal_org_to_crm', 'hq_prepare_outreach', 'hq_opportunity_commercial', 'hq_partner_upsert',
  'hq_project_update', 'hq_project_item', 'hq_edge_add', 'hq_role_route', 'hq_outreach_action', 'hq_outreach_edit', 'hq_club_person', 'hq_redispatch',
  'hq_advisor_seen'];
const ALLOWED = ['hq_dashboard', 'hq_overview', 'hq_directory', 'hq_insight', 'hq_timeline', 'hq_relationships', 'hq_commercial', 'hq_execution', 'hq_account', 'hq_task_action', 'hq_approve_draft', 'hq_save_draft', 'hq_hold', 'hq_reject',
  'hq_create_opportunity', 'hq_import_connections', 'hq_agents', 'hq_agent', 'hq_email_review', 'hq_approve_email', ...Object.keys(V3), ...WRITES];
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
      if (m[1] === 'hq_relationships') return route.fulfill({ json: relationships });
      if (m[1] === 'hq_commercial') return route.fulfill({ json: commercial });
      if (m[1] === 'hq_execution') return route.fulfill({ json: execution });
      if (m[1] === 'hq_agents') return route.fulfill({ json: agentsFx });
      if (m[1] === 'hq_email_review') return route.fulfill({ json: erTest || { counts: {}, verification: {}, needs_review: [], drafting: [], in_gmail: [], failed: [], sent: [] } });
      if (m[1] === 'hq_approve_email') return route.fulfill({ json: { ok: true, mode: 'DRAFT', dispatched: true, outbound_id: '00000000-0000-0000-0000-000000000002' } });
      if (m[1] === 'hq_agent') return route.fulfill({ json: body?.p_key === 'HOSPITALITY' ? agentFx : { key: body?.p_key, sections: [] } });
      if (m[1] === 'hq_account') return route.fulfill({ json: account });
      if (V3[m[1]]) return route.fulfill({ json: V3[m[1]](body) });
      if (m[1] === 'hq_signal_promote') return route.fulfill({ json: { ok: true, created: [{ opportunity_id: cOpps[0].id, company: 'HYROX', product: body.p_targets[0]?.product, track: 'EVENT', has_contact: false }] } });
      if (m[1] === 'hq_timeline') return route.fulfill({ json: { events: [{ at: '2026-09-29T10:00:00Z', channel: 'Reply', direction: 'INBOUND', title: 'MEETING_REQUEST — Re: NOYA', detail: 'Timeline stub', src: 'reply' }], notes: [] } });
      if (m[1] === 'hq_create_opportunity') return route.fulfill({ json: { ok: true, opportunity_id: data.opportunities[0].id, company_id: null, company_reused: true } });
      if (m[1] === 'hq_import_connections') return route.fulfill({ json: { ok: true, new: body.p_rows.length - 1, updated: 1, duplicates: 0, skipped: 0, upserted: body.p_rows.length } });
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
const closeDrawer = async (page) => { if (await page.locator('.drawer').count()) await page.click('.drawer [data-close-drawer]'); };
// V3: six primary destinations; everything older sits under "More" in the sidebar (opened on demand).
async function go(page, tab) {
  if (!(await page.locator(`.side [data-tab=${tab}]`).count())) await page.click('#nav-more');
  await page.click(`.side [data-tab=${tab}]`);
}
async function sheet(page, tab) { await page.click('#bmenu'); await page.click(`.sheet [data-tab=${tab}]`); }
const noOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);

// 1. Desktop: Today + every view renders from live data; every write goes through the right RPC.
{
  const { browser, page, errors, calls } = await runScenario({ viewport: { width: 1280, height: 900 } });
  await page.waitForSelector('.side');
  await page.waitForSelector('.today-sec, .calm');
  await go(page, 'overview');
  await page.waitForSelector('.q-row');
  check('login leads to Today; data via the four read RPCs with bearer token',
    ['hq_dashboard', 'hq_overview', 'hq_directory', 'hq_insight', 'hq_relationships'].every((fn) => calls.some((c) => c.fn === fn && c.auth.startsWith('Bearer ey'))));
  const warm = await page.locator('main section.panel', { hasText: 'Warm opportunities' }).innerText();
  const warmFirst = await page.locator('main .mini.warm').first().innerText();
  check('Today: Warm opportunities lists reply-now relationships first, labelled as suggestion vs your status', /(Suggested|You): Reply now/i.test(warmFirst) && /They wrote last/.test(warmFirst), warmFirst.split('\n')[0]);
  check('Today: warm panel is evidence-only and never sends', (await page.locator('main .mini.warm').count()) <= 6 && /Nothing is sent from here/.test(warm) && (await page.locator('main .mini.warm a[href*="mail.google.com"]').count()) > 0);
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

  const tabs = ['inbox', 'outreach', 'relationships', 'linkedin', 'pipeline', 'tasks', 'website', 'contacts', 'companies', 'finance', 'costs', 'markets', 'growth', 'intelligence', 'reports', 'system', 'help'];
  for (const tab of tabs) {
    await go(page, tab);
    await page.waitForSelector('main h2');
    const h2 = await page.locator('main h2').first().innerText();
    check(`view renders: ${tab}`, h2.length > 0 && !/not loaded/i.test(await page.locator('main').innerText()), h2);
    await page.screenshot({ path: `tests/out/${tab}.png`, fullPage: true });
  }
  check('no placeholder "coming soon" sections in navigation', (await page.locator('.nav-item.off').count()) === 0);

  // Contacts / Companies / Markets / Costs match live data.
  await go(page, 'contacts');
  check('Contacts: one row per live contact', (await page.locator('main tbody tr').count()) === directory.contacts.length, `${directory.contacts.length}`);
  await go(page, 'companies');
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
  await go(page, 'markets');
  const eu = insight.markets.find((m) => m.market === 'EUROPE');
  const euRow = await page.locator('main tbody tr', { hasText: 'Europe' }).first().innerText();
  check('Markets: Europe row equals live counts', euRow.includes(String(eu.companies)) && euRow.includes(String(eu.active_opps_origin)), euRow.replace(/\s+/g, ' ').slice(0, 80));
  check('Markets: bridges listed (Europe → Egypt)', /Europe → Egypt/.test(await page.locator('main').innerText()));
  await go(page, 'costs');
  const unknown = insight.services.filter((s) => s.status === 'ACTIVE' && (s.cost_type === 'UNKNOWN' || (s.cost_type !== 'FREE' && s.monthly_cost == null))).length;
  const costs = await page.locator('main').innerText();
  check('System costs: unknown exposure equals register, paid-software gate shown', costs.includes(`${unknown}\n`) && /UNKNOWN — verify before scale/.test(costs) && /then waits for your approval/.test(costs), `${unknown}`);
  check('System costs: every dependency listed with what breaks and where the credential lives', (await page.locator('main details.row').count()) === insight.services.filter((s) => s.status !== 'RETIRED').length && /Credential kept in/.test(await page.locator('main details.row').first().innerHTML()));

  check('System costs: reconciliation shows fixed / usage / UNKNOWN / growth risks / downgrade candidates', ['Confirmed fixed monthly', 'Usage-based', 'Remaining UNKNOWN', 'Likely to grow with volume', 'Downgrade / remove candidates'].every((w) => costs.toLowerCase().includes(w.toLowerCase())) && /Serper:/.test(costs) && /Anthropic API:/.test(costs));
  const hunter = insight.services.find((s) => s.service === 'Hunter');
  await page.locator('main details.row', { hasText: 'Hunter' }).locator('summary').click();
  await page.locator('main details.row', { hasText: 'Hunter' }).locator('[data-modal=service-edit]').click();
  await page.waitForSelector('.modal');
  await page.fill('#f-cost', '34');
  await page.click('#m-ok');
  await page.waitForTimeout(200);
  check('Cost edit: an amount without a currency is refused on the field, typed amount kept', !last(calls, 'hq_service_update') && /currency/i.test(await page.$eval('#f-ccur', (e) => e.validationMessage)) && (await page.inputValue('#f-cost')) === '34');
  await page.fill('#f-ccur', 'usd');
  await page.fill('#f-evidence', 'Invoice INV-1, 1 Oct 2026');
  await page.click('#m-ok');
  await page.waitForTimeout(300);
  const su = last(calls, 'hq_service_update');
  check('Cost edit → hq_service_update (amount, currency, evidence), audited server-side', su && su.body.p_id === hunter.id && su.body.p.monthly_cost === '34' && su.body.p.currency === 'usd' && /INV-1/.test(su.body.p.verification_note), JSON.stringify(su?.body.p));

  // V3 navigation: six destinations, then More (every older view, grouped). Checked in detail in tests/ui_v3.mjs.
  const primary = await page.locator('.side .nav-primary .nav-item').allInnerTexts();
  const groups = await page.locator('.side .nav-group h6').allInnerTexts();
  check('Navigation: six destinations plus More (older views kept, grouped)', primary.map((t) => t.replace(/\d+$/, '').trim()).join('|') === 'Today|Agents|Outreach|Relationships|Club|Operations'
    && groups.join('|').toLowerCase() === 'agents & intelligence|sales|records|admin', `${primary.join(' | ')} // ${groups.join(' | ')}`);
  await go(page, 'radar');
  const radar = await page.locator('main').innerText();
  check('Radar: horizons Now / 7 / 30 / 90 / longer-term; region and category filters', ['Now / urgent', '7 days', '30 days', '90 days', 'Longer term'].every((w) => radar.includes(w)) && (await page.locator('main select[data-rdf=region] option').count()) === 6);
  check('Radar: signal shows source, qualification 9/10 and what is missing', /CairoScene/.test(radar) && /9\/10/.test(radar) && /Can we reach them\?/.test(radar) && (await page.locator('main a[href="https://cairoscene.com/x"]').count()) === 1);
  check('Radar: AI reading is labelled as AI, separate from source facts', /AI reading of the source/.test(radar));
  await page.locator('#sig-s1 [data-org-crm]').click(); await page.waitForTimeout(250);
  check('Radar: organisation → Add to CRM + find-decision-maker task (hq_signal_org_to_crm)', last(calls, 'hq_signal_org_to_crm')?.body.p_org === 'org-1');
  await page.locator('#sig-s1 [data-sig-stage=QUALIFIED]').click(); await page.waitForTimeout(250);
  check('Radar: Qualify goes through the server gate (hq_signal_update stage QUALIFIED)', last(calls, 'hq_signal_update')?.body.p.stage === 'QUALIFIED');
  await page.locator('#sig-s2 [data-modal=sig-promote]').click(); await page.waitForSelector('.modal');
  await page.click('#m-ok'); await page.waitForTimeout(300);
  const pr = last(calls, 'hq_signal_promote');
  check('Radar: one signal → opportunities per organisation + product (hq_signal_promote)', pr && pr.body.p_signal === 's2' && pr.body.p_targets[0].org_id === 'org-2' && pr.body.p_targets[0].product === 'VIP_GUEST_DESK', JSON.stringify(pr?.body));
  await page.click('main [data-modal=sig-capture]'); await page.waitForSelector('.modal');
  await page.fill('#f-title', 'Brand X opens in Cairo'); await page.click('#m-ok'); await page.waitForTimeout(200);
  check('Capture: a signal without a source link is refused, typed text kept', !last(calls, 'hq_signal_capture') && /source link/i.test(await page.locator('.modal .m-err').innerText().catch(() => '')) && (await page.inputValue('#f-title')) === 'Brand X opens in Cairo');
  await page.fill('#f-url', 'https://example.com/brand-x'); await page.fill('#f-orgs', 'Brand X | BRAND'); await page.click('#m-ok'); await page.waitForTimeout(300);
  const cap = last(calls, 'hq_signal_capture');
  check('Capture: source link + named organisations sent (hq_signal_capture)', cap && cap.body.p.source_url === 'https://example.com/brand-x' && cap.body.p.orgs[0].role === 'BRAND');
  await go(page, 'actions');
  const act = await page.locator('main').innerText();
  const firstAct = await page.locator('main article.card.act').first().innerText();
    check('Action queue: who / why / what to offer / path / next / owner / due, highest priority first', /80/.test(firstAct) && /Why now/i.test(firstAct) && /Offer/i.test(firstAct) && /Relationship path/i.test(firstAct) && /Owner/i.test(firstAct) && /due/i.test(firstAct));
  check('Action queue: one CRM, segment views (Private, Corporate, Brands, Production, Sports, Events, Hospitality, Weddings, Agencies, Concierge, Real estate, Sourcing)', ['Private / UHNW', 'Corporate', 'Brands', 'Production', 'Sports', 'Events', 'Hospitality', 'Weddings', 'Agencies', 'Concierge partners', 'Real estate', 'Luxury sourcing'].every((w) => act.includes(w)));
  await page.locator('main article.card.act [data-prep-outreach]').first().click(); await page.waitForTimeout(250);
  check('Action queue: Prepare outreach → hq_prepare_outreach (then the existing approval queue; nothing sent)', last(calls, 'hq_prepare_outreach')?.body.p_opp === cOpps[0].id);
  await page.locator('main article.card.act [data-modal=opp-commercial]').first().click(); await page.waitForSelector('.modal');
  check('Commercial: score breakdown shown, with "not money" note', /not money/i.test(await page.locator('.modal').innerText()));
  await page.fill('#f-proposal', '25000'); await page.click('#m-ok'); await page.waitForTimeout(200);
  check('Commercial: a money value without currency + evidence is refused (no fake pipeline)', !last(calls, 'hq_opportunity_commercial'));
  await page.fill('#f-cur', 'EUR'); await page.fill('#f-evidence', 'Proposal sent 3 Oct (email)'); await page.fill('#f-override', '95'); await page.click('#m-ok'); await page.waitForTimeout(200);
  check('Commercial: a score override without a reason is refused', !last(calls, 'hq_opportunity_commercial'));
  await page.fill('#f-oreason', 'Warm intro from their CEO'); await page.click('#m-ok'); await page.waitForTimeout(300);
  const oc = last(calls, 'hq_opportunity_commercial');
  check('Commercial: proposal value with currency + evidence, override with reason (hq_opportunity_commercial)', oc && oc.body.p.proposal_value === '25000' && oc.body.p.currency === 'EUR' && /Proposal sent/.test(oc.body.p.value_evidence) && oc.body.p.score_override === '95', JSON.stringify(oc?.body.p).slice(0, 200));
  await go(page, 'partners');
  const par = await page.locator('main').innerText();
  check('Partnerships: supply vs distribution explained; productive/strategic earned by activity only', /Supply partners/.test(par) && /Distribution partners/.test(par) && /never by prestige/.test(par));
  await page.click('main [data-paf=tab][data-v=ACTIVE]');
  await page.locator('main article.card.partner [data-modal=partner-edit]').first().click(); await page.waitForSelector('.modal');
  await page.selectOption('#f-stage', 'PRODUCTIVE'); await page.click('#m-ok'); await page.waitForTimeout(300);
  check('Partnerships: update → hq_partner_upsert (server checks the evidence for Productive)', last(calls, 'hq_partner_upsert')?.body.p.stage === 'PRODUCTIVE');
  await go(page, 'events');
  const ev = await page.locator('main').innerText();
  check('Events: upcoming events with what NOYA can win and the organisations', /El Gouna Film Festival/.test(ev) && /What NOYA can win/.test(ev) && /Organiser → VIP Guest Desk/i.test(ev));
  await go(page, 'projects');
  const pj = await page.locator('main').innerText();
  check('Operations: project with items, client charge, supplier cost and gross profit per currency', /Suites block/.test(pj) && /EUR 10,000/.test(pj) && /EUR 6,500/.test(pj) && /EUR 3,500/.test(pj));
  await page.click('main [data-proj-status=DELIVERED]'); await page.waitForTimeout(250);
  check('Operations: Delivered → hq_project_update (feedback + expansion tasks, no client message)', last(calls, 'hq_project_update')?.body.p.status === 'DELIVERED');
  await page.click('main [data-modal=project-item]'); await page.waitForSelector('.modal');
  await page.selectOption('#f-type', 'TRANSFER'); await page.fill('#f-title', 'Airport VIP arrivals'); await page.click('#m-ok'); await page.waitForTimeout(250);
  check('Operations: add item → hq_project_item', last(calls, 'hq_project_item')?.body.p.item_type === 'TRANSFER');
  await go(page, 'library');
  check('Library: products (templates, follow-ups, objections) and playbooks with real outcomes', /Film festival/.test(await page.locator('main').innerText()) && /not money and not a probability/.test(await page.locator('main').innerText()));
  await go(page, 'companies');
  await page.locator('main tr[data-open=company]').first().click(); await page.waitForSelector('.drawer'); await page.waitForTimeout(300);
  const drw = await page.locator('.drawer').innerText();
    check('Account intelligence in the company record (strength with evidence, routes in, why now)', calls.some((c) => c.fn === 'hq_account') && /Account intelligence/i.test(drw) && /Routes in/i.test(drw) && /Direct email history/.test(drw) && /WARM/i.test(drw));
  await page.click('.drawer [data-close-drawer]');
  await go(page, 'overview');
  const cmd = await page.locator('main').innerText();
  check('Command: queue health shows 15/day target and an honest shortfall (warm 3/6)', /Today's 15/i.test(cmd) && /short by 3/i.test(cmd) && /42 \/ 45/.test(cmd));
  check('Command: working universe by status (Qualified / Needs review / Researching) and VERIFY FIRST count', /Qualified 64/i.test(cmd) && /Needs review 21/i.test(cmd) && /Researching 51/i.test(cmd) && /4 people need verifying/i.test(cmd));
  check('Command: 3-day cycle shows outreach-ready vs 60–75 and per-agent output', /3-day cycle: 41 outreach-ready of 60–75/.test(cmd) && /Hospitality & partnerships/.test(cmd) && /Travel \/ concierge \/ private/.test(cmd));
  check('Command: drafting quality keeps system vs human-reviewed separate, and AI cost vs budget', /system ready on its own 0\/16/.test(cmd) && /ready after human review 13/.test(cmd) && /\$0\.42 of \$5\.00 target/.test(cmd) && /\$10\.00 ceiling/.test(cmd));
  check('Command: today\'s actions (15–20, priority groups, waiting counts) and the 3-day scorecard with search cost', /Today's actions/i.test(cmd) && /1\. Reply · YKONE Middle East/.test(cmd)
    && /4\. Partnership outreach · Cheval Collection/.test(cmd) && /16 drafts waiting for a named person/.test(cmd) && /43 new companies \(Agents 13, ChatGPT 13, Other research 17\)/.test(cmd)
    && /4 media concepts/.test(cmd) && /1950 searches per 3-day cycle ≈ \$1\.95/.test(cmd));
  check('Command: Today view (commercial engine by lane, Director plan, conversations paused)', /Today · commercial engine/i.test(cmd) && /16 planned/.test(cmd) && /Brands \/ PR \/ production/.test(cmd) && /YKONE Middle East/.test(cmd) && /dry run/i.test(cmd));
  check('Command: Hunter ROI chain (credits → usable → sent → replies → meetings)', /48 credits → 11 usable emails/.test(cmd) && /5 sent → 1 replies → 0 meetings/.test(cmd));
  await go(page, 'finance');
  const finW = await page.locator('main').innerText();
  check('Performance: weekly prospecting by segment (sends, replies, positive) — allocation never automatic', /Prospecting by segment/i.test(finW) && /Brands \/ PR \/ production/i.test(finW) && /Travel advisors/i.test(finW) && /recommendations only/i.test(finW));
  await go(page, 'overview');
  check('Command: action-first modules (opportunities, deals, partnerships, projects, risks, team)', ['New high-quality opportunities', 'Meetings · proposals · negotiations', 'Strategic partnerships', 'Active projects', 'Risks / blockers', 'Team action'].every((w) => cmd.toLowerCase().includes(w.toLowerCase())));

  // Finance: new record + definitions.
  await go(page, 'finance');
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
  await go(page, 'linkedin');
  const li = await page.locator('main').innerText();
  check('LinkedIn: never-auto-send statement and options gate present', /Nothing is ever sent automatically/.test(li) && /options and approval/i.test(li));
  const csv = 'Notes:\n"When exporting your connection data, you may notice that some of the email addresses are missing."\n\nFirst Name,Last Name,URL,Email Address,Company,Position,Connected On\nSara,Khalil,https://www.linkedin.com/in/sara-khalil,,"Aman Resorts, Ltd",Director of Sales,01 May 2024\nOmar,Nasser,https://www.linkedin.com/in/omarn,,YKONE Middle East,Partner,15 Jan 2023\nOmar,Nasser,https://uk.linkedin.com/in/OmarN/,,YKONE Middle East,Partner,15 Jan 2023\nBad,Row,https://example.com/x,,X,Y,01 Jan 2020\n';
  await page.setInputFiles('#li-file', { name: 'Connections.csv', mimeType: 'text/csv', buffer: Buffer.from(csv) });
  await page.waitForSelector('.modal');
  const im = await page.locator('.modal').innerText();
  check('import preview: 2 connections found, 1 skipped, same person twice counted once', /2 connections found/.test(im) && /1 lines skipped/.test(im) && /1 duplicate lines ignored/.test(im), im.replace(/\n/g, ' | ').slice(0, 120));
  // After import the server returns matches with evidence (simulated here: one connection linked to YKONE).
  directory.connections.push({ id: '00000000-0000-0000-0000-0000000000c1', name: 'Omar Nasser', first_name: 'Omar', last_name: 'Nasser', company: 'YKONE Middle East', position: 'Partner',
    profile_url: 'https://www.linkedin.com/in/omarn', status: 'NOT_CONTACTED', active_opps: 1, email_history: 1, matched_company_id: directory.companies[0].id, matched_contact_id: null,
    how_we_know: null, next_follow_up_at: null, vertical: 'BRAND_PRODUCTION', history_key: 'd:ykone.com',
    evidence: ['Company matches CRM account: YKONE Middle East', 'Active opportunity at their company: 1', 'Emailed with NOYA (Gmail): 1 sent, 1 received'] });
  await page.click('#m-ok');
  await page.waitForTimeout(400);
  const liAfter = await page.locator('main').innerText();
  check('import result reports new / already known / duplicates / skipped', /LinkedIn import done: 1 new, 1 already known \(updated\), 1 duplicates ignored, 1 skipped/.test(liAfter), liAfter.match(/LinkedIn import done[^\n]*/)?.[0]);
  check('LinkedIn: matched people listed first with their evidence; strength stays Unknown', /Linked to NOYA\s*1/i.test(liAfter) && /Company matches CRM account: YKONE/.test(liAfter) && /Emailed with NOYA \(Gmail\)/.test(liAfter) && /Unknown/.test(liAfter), liAfter.match(/Linked to NOYA\s*\d+/i)?.[0]);
  const ic = last(calls, 'hq_import_connections');
  check('import sends only the needed fields, dates as ISO, quoted commas kept', ic && ic.body.p_rows.length === 2 && ic.body.p_rows[0].connected_on === '2024-05-01'
    && ic.body.p_rows[0].company === 'Aman Resorts, Ltd' && Object.keys(ic.body.p_rows[0]).sort().join() === 'company,connected_on,email,first_name,last_name,position,url', JSON.stringify(ic?.body.p_rows[0]));

  // Outreach: tabs, cards, approval flow unchanged.
  await go(page, 'outreach');
  const otabs = await page.locator('main .tabs').innerText();
  check('Outreach tabs: Email review / Ready / Follow-up / LinkedIn / Instagram / Sent / Replied / Hold / Researching', ['Email review', 'Ready', 'Follow-up', 'Linkedin', 'Instagram', 'Sent', 'Replied', 'Hold', 'Researching'].every((t) => new RegExp(t, 'i').test(otabs)), otabs.replace(/\n/g, ' '));
  check('Outreach opens on Email review (verified emails waiting for Adam)', /email review/i.test(await page.locator('main .tabs button.on').innerText()));
  if (erFx) {
    const erText = await page.locator('main').innerText();
    check('Email review: separate counts — verified email / LinkedIn / Instagram — and the 40–50 email target', /verified emails ready today/i.test(erText) && /linkedin ready today/i.test(erText) && /instagram ready today/i.test(erText) && /40–50/.test(erText) && /not counted as email/i.test(erText));
    check('Email review: verification capacity from the live Hunter read (plan, left, reset)', erText.includes(erFx.verification.account.plan) && erText.includes(`${erFx.verification.account.verifications_left} verifications left`) && /resets/i.test(erText));
    const unv = page.locator(`#er-${erFx.needs_review[0].candidate_id}`);
    check('Email review: a publicly listed (unverified) address cannot be approved', (await unv.locator('[data-er-approve]').isDisabled()) && /not verified/i.test(await unv.innerText()));
    const ver = page.locator(`#er-${ER_TEST_ID}`);
    check('Email review: a verified address shows SMTP-verified and an Approve → Gmail draft button', /smtp-verified/i.test(await ver.innerText()) && !(await ver.locator('[data-er-approve]').isDisabled()));
    const erButtons = await page.locator('main button').allInnerTexts();
    check('Email review: no Send button (approve never sends)', !erButtons.some((t) => /\bsend\b/i.test(t)), erButtons.filter((t) => /\bsend\b/i.test(t)).join(','));
    const writesBeforeEr = calls.filter((c) => WRITES.includes(c.fn)).length;
    await page.fill(`#er-s-${ER_TEST_ID}`, 'Partnership enquiry: Cheval Collection (edited)');
    await page.click(`#er-${ER_TEST_ID} [data-er-approve]`);
    await page.waitForTimeout(400);
    const ea = calls.filter((c) => c.fn === 'hq_approve_email');
    check('Approve → exactly one hq_approve_email with the candidate and the edited subject + body',
      ea.length === 1 && ea[0].body.p_candidate === ER_TEST_ID && ea[0].body.p_subject === 'Partnership enquiry: Cheval Collection (edited)' && ea[0].body.p_body === erFx.needs_review[0].draft);
    check('Approve message says nothing was sent', /nothing was sent/i.test(await page.locator('main').innerText()));
    check('Approve made no other write', calls.filter((c) => WRITES.includes(c.fn)).length === writesBeforeEr);
  } else check('Email review fixture present', false, 'tests/fixtures/email_review.json missing');
  await page.click('main .tabs [data-otab=READY]');
  const readyCards = await page.locator('article.card.ready').count();
  check('Ready: cards equal the live approval-ready queue', readyCards === approvalsLive, `${readyCards}`);
  if (readyCards > 1) {
    await page.click('main [data-one-toggle]');
    const one = await page.locator('article.card.ready').count();
    await page.click('main [data-o-step="1"]');
    check('Outreach one at a time: one card, Skip advances', one === 1 && /2\s*of/.test(await page.locator('main .review-nav').innerText()) && (await page.locator('article.card.ready').count()) === 1);
    await page.click('main [data-one-toggle]');
  }
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


  // Past relationships (NOYA Gmail history).
  await closeDrawer(page);
  await go(page, 'relationships');
  const relText = await page.locator('main').innerText();
  const replied = relationships.groups.filter((g) => !g.dismissed && g.received > 0 && g.state === 'REPLIED').length;
  check('Past relationships: "They wrote last" count equals Gmail history', new RegExp(`They wrote last\\s*${replied}`).test(relText), `${replied}`);
  check('Past relationships: source and scan size stated (provenance)', /noya@noyaconcierge\.com/.test(relText) && relText.includes(String(relationships.state.scanned)));
  const toReview = relationships.groups.filter((g) => !g.dismissed && g.received > 0 && !g.review?.status);
  check('Review mode: opens one card at a time, most urgent first', (await page.locator('main article.card.rel').count()) === 1 && new RegExp(`1\\s*of ${toReview.length}`).test(relText), `${toReview.length}`);
  const firstCard = await page.locator('main article.card.rel').innerText();
  const g1 = toReview.find((g) => firstCard.split('\n')[0].includes(g.name));
  check('Review card: facts, verbatim preview and AI summary are labelled separately', !!g1 && /Facts/.test(firstCard) && /Latest preview \(verbatim\)/.test(firstCard)
    && (!g1.review?.summary || /AI summary — from subjects and previews only/.test(firstCard)), firstCard.split('\n')[0]);
  check('Review card: seven status choices, suggestion marked', (await page.locator('main article.card.rel [data-rel-status]').count()) === 7 && (await page.locator('main .chip.sug').count()) === 1);
  await page.click('main [data-rel-step="1"]');
  check('Review: Skip moves to the next relationship', /2\s*of/.test(await page.locator('main .review-nav').innerText()));
  await page.click('main [data-rel-status=RECONNECT]');
  await page.waitForTimeout(300);
  const rs = last(calls, 'hq_relationship_status');
  check('Status chip → hq_relationship_status (key + status), no send path', rs && rs.body.p_status === 'RECONNECT' && typeof rs.body.p_key === 'string' && !calls.some((c) => /send/.test(c.fn)), JSON.stringify(rs?.body));
  await page.click('main .tabs button[data-v=REVIEWED]');
  check('Reviewed tab lists relationships with your status', /you: /i.test(await page.locator('main').innerText()));
  await page.click('main .tabs button[data-v=NOT_IN_CRM]');
  const firstNotInCrm = relationships.groups.find((g) => !g.dismissed && g.received > 0 && !g.in_crm);
  await page.locator('main article.card.rel [data-modal=history-add]').first().click();
  await page.waitForSelector('.modal');
  check('Add to CRM: prefilled from the email (company guess + address)', (await page.inputValue('#f-co')).length > 0 && (await page.locator('#f-email option').count()) >= 1);
  await page.click('#m-ok');
  await page.waitForTimeout(400);
  const ha = last(calls, 'hq_history_action');
  check('Add to CRM calls hq_history_action ADD_TO_CRM with the group key', ha && ha.body.p_action === 'ADD_TO_CRM' && ha.body.p_key === firstNotInCrm.key, JSON.stringify(ha?.body).slice(0, 160));
  await closeDrawer(page);
  await go(page, 'relationships');
  await page.click('main .tabs button[data-v=NO_REPLY]');
  await page.locator('main article.card.rel [data-hist-act=DISMISS]').first().click();
  await page.waitForTimeout(300);
  check('Not relevant → hq_history_action DISMISS (history kept)', last(calls, 'hq_history_action')?.body.p_action === 'DISMISS');
  const gmailLinks = await page.locator('main article.card.rel a[href*="mail.google.com"]').count();
  check('every relationship card links to its real Gmail thread', gmailLinks === (await page.locator('main article.card.rel').count()) && gmailLinks > 0, `${gmailLinks}`);

  // Outreach knows the history: a held cold intro shows the earlier conversation.
  const heldPrior = snapshot.approvals.find((a) => a.loop_stage === 'ON_HOLD' && /Previously in contact/.test(a.queue_reason || ''));
  if (heldPrior) {
    await go(page, 'outreach');
    await page.click('main .tabs [data-otab=HOLD]');
    const card = await page.locator(`#opp-${heldPrior.id}`).innerText();
    check('Outreach: cold intro to a past contact is held, showing "Emailed before" + reason', /Emailed before/.test(card) && /Previously in contact/.test(card), heldPrior.company_name);
  } else check('Outreach: held prior-relationship example present in snapshot', false, 'no held example');

  // Data cleanup: company country from evidence.
  await page.fill('#q', directory.companies[0].name);
  await page.locator('.results [data-open=company]').first().click();
  await page.waitForSelector('.drawer');
  await page.click('.drawer [data-modal=vertical]');
  await page.fill('#f-country', 'United Kingdom');
  await page.click('#m-ok');
  await page.waitForTimeout(300);
  check('Edit details saves country via hq_company_update', last(calls, 'hq_company_update')?.body.p_country === 'United Kingdom');
  await closeDrawer(page);

  // Quick actions: add contact / follow-up.
  await page.click('#quick');
  await page.click('.modal [data-modal=new-contact]');
  await page.fill('#f-first', 'Sara'); await page.fill('#f-last', 'Khalil'); await page.fill('#f-co', 'Aman Resorts'); await page.fill('#f-email', 'sara@aman.com');
  await page.click('#m-ok');
  await page.waitForTimeout(400);
  const ac = last(calls, 'hq_add_contact');
  check('+ New → Add contact calls hq_add_contact (no duplicate by email/name server-side)', ac && ac.body.p_first === 'Sara' && ac.body.p_email === 'sara@aman.com');
  await closeDrawer(page);
  await page.click('#quick');
  await page.click('.modal [data-modal=followup]');
  await page.selectOption('#f-company', directory.companies[1].id);
  await page.fill('#f-body', 'Send the Siwa proposal');
  await page.click('#m-ok');
  await page.waitForTimeout(300);
  const fu2 = last(calls, 'hq_add_note');
  check('+ New → Add follow-up books a dated follow-up (hq_add_note with date)', fu2 && fu2.body.p_company === directory.companies[1].id && /^\d{4}-\d{2}-\d{2}$/.test(fu2.body.p_follow_up));

  // Search reaches email history.
  const g0 = relationships.groups.find((g) => g.domain && !g.in_crm && g.received > 0);
  await page.fill('#q', g0.domain);
  await page.waitForSelector('.results');
  check('search finds past email relationships by domain', /Previous relationships/i.test(await page.locator('.results').innerText()), g0.domain);
  await page.locator('.results [data-relq]').first().click();
  check('search result opens Past relationships filtered to it', (await page.locator('main h2').innerText()) === 'Past relationships' && (await page.locator('main article.card.rel').count()) >= 1);

  // AGENTS: the virtual commercial department, every figure from the live hq_agents() / hq_agent() shapes.
  if (agentsFx && agentFx) {
    const A = agentsFx; const writesBefore = calls.filter((c) => WRITES.includes(c.fn)).length;
    await closeDrawer(page);
    await go(page, 'agentfloor');
    await page.waitForSelector('.agent-card');
    const floor = await page.locator('main').innerText();
    check('Agents: every agent has a card (8 acquisition + 4 support)', (await page.locator('.agent-grid .agent-card').count()) === A.agents.length, `${A.agents.length}`);
    check('Agents: names and live statuses shown', A.agents.every((a) => floor.includes(a.name)) && A.agents.every((a) => floor.includes(a.status_reason)));
    const healthy = A.agents.filter((a) => ['WORKING', 'WAITING'].includes(a.status)).length;
    check('Agents: CEO view (healthy, 24h companies, decision makers, emails, ready)', floor.includes(`${healthy} / ${A.agents.length}`) && floor.includes(String(A.ceo.new_companies_24h))
      && floor.includes(String(A.ceo.new_decision_makers_24h)) && floor.includes(String(A.ceo.new_emails_24h)) && floor.includes(String(A.ceo.ready)));
    check('Agents: best opportunities found today', !A.ceo.best?.length || floor.includes(A.ceo.best[0].company), A.ceo.best?.[0]?.company);
    const waiting = A.agents.find((a) => a.status === 'WAITING');
    check('Agents: status is never faked (waiting agent shows its real reason)', !waiting || (await page.locator('.agent-card', { hasText: waiting.name }).innerText()).includes(waiting.status_reason), waiting?.name);
    check('Agents: activity feed from stored events', A.feed.slice(0, 3).every((f) => floor.includes(f.text)));
    // Email & Contact Intelligence (Adam, 8 Oct): a company-level email funnel on every acquisition card
    const hf = A.agents.find((a) => a.key === 'HOSPITALITY').email_funnel;
    const hcard = await page.locator('.agent-card', { hasText: 'Hospitality' }).first().innerText();
    check('Agents: email funnel on the Hospitality card (qualified → decision makers → direct + department → usable → email ready)',
      [`${hf.qualified} qualified`, `${hf.decision_makers} decision makers`, `${hf.direct_emails} direct`, `${hf.department_emails} department`, `${hf.usable_emails} usable`, `${hf.ready_email} email ready`, `${hf.email_gaps} email gaps`]
        .every((x) => hcard.replace(/\s+/g, ' ').includes(x)), JSON.stringify(hf));
    check('Agents: every acquisition card carries its funnel', (await page.locator('.agent-card .funnel').count()) === A.agents.filter((a) => a.kind === 'ACQUISITION').length);
    const enr = A.agents.find((a) => a.key === 'ENRICHMENT');
    const ecard0 = await page.locator('.agent-card', { hasText: enr.name }).first().innerText();
    check('Agents: Email & Contact Intelligence card reports named / department emails and no-email outcomes', /Email & Contact Intelligence/.test(ecard0)
      && ecard0.includes(String(enr.today.named_emails_found)) && /Named emails/.test(ecard0) && /Department emails/.test(ecard0) && /No public email/.test(ecard0));
    await page.screenshot({ path: 'tests/out/agents.png', fullPage: true });
    const hosp = A.agents.find((a) => a.key === 'HOSPITALITY');
    await page.locator('.agent-card', { hasText: hosp.name }).first().locator('[data-gaps]').click();
    await page.waitForSelector('.email-card');
    const hg = A.email_gaps.filter((g) => g.agent === 'HOSPITALITY');
    check('Agents: "email gaps" on a card opens that agent\'s gap queue', (await page.locator('.email-card').count()) === Math.min(30, hg.length)
      && (await page.locator('[data-emf=s][data-v=GAPS].on').count()) === 1, `${hg.length}`);
    await page.click('.agents-nav [data-tab=agentfloor]');
    await page.waitForSelector('.agent-card');
    await page.locator('.agent-card', { hasText: hosp.name }).first().click();
    await page.waitForSelector('[data-agent-sec]');
    check('Agent drill-down loads hq_agent for that agent only', calls.some((c) => c.fn === 'hq_agent' && c.body?.p_key === 'HOSPITALITY'));
    const chips = await page.locator('[data-agent-sec]').allInnerTexts();
    check('Drill-down: finds, people, opportunities, ready, researching, rejected', ['New finds', 'People', 'Opportunities', 'Ready for Adam', 'Researching', 'Rejected'].every((t) => chips.some((c) => c.startsWith(t))), chips.join(' | '));
    const sec = (k) => agentFx.sections.find((x) => x.key === k);
    check('Drill-down: new finds are real companies', (await page.locator('main .panel').last().innerText()).includes(sec('finds').items[0].company));
    await page.click('[data-agent-sec=people]');
    const ppl = await page.locator('main .panel').last().innerText();
    const p0 = sec('people').items[0];
    check('Drill-down: people with role, company, source and confidence', ppl.includes(p0.name || p0.email) && ppl.includes(p0.company) && /Source:/.test(ppl) && /confidence/i.test(ppl), p0.name);
    await page.click('[data-agent-sec=opportunities]');
    check('Drill-down: opportunities say what NOYA could do', (await page.locator('main .panel').last().innerText()).includes(sec('opportunities').items[0].company));
    await page.click('[data-agent-sec=ready]');
    check('Drill-down: READY outreach for Adam', (await page.locator('main .panel').last().innerText()).toLowerCase().includes(sec('ready').items[0].company.toLowerCase()));
    await page.click('[data-agent-sec=rejected]');
    check('Drill-down: rejected or held, with the reason', /watchlist|Parked/i.test(await page.locator('main .panel').last().innerText()));
    await page.screenshot({ path: 'tests/out/agent-hospitality.png', fullPage: true });
    await page.click('.agents-nav [data-tab=emails]');
    await page.waitForSelector('.email-card');
    await page.click('[data-emf=s][data-v=ALL]'); await page.click('[data-emf=v][data-v=""]');
    check('Email opportunities: one card per prospect with an email', (await page.locator('.email-card').count()) === Math.min(30, A.email_desk.length), `${A.email_desk.length}`);
    const e0 = A.email_desk[0];
    const ecard = await page.locator('.email-card').first().innerText();
    check('Email card: email, provenance and verification state', ecard.includes(e0.email) && /From:/.test(ecard) && /(Publicly listed|SMTP verified|Risky|Invalid|Unverified|Not verifiable|Source not recorded)/i.test(ecard), e0.email);
    const rep = A.email_report; const head = await page.locator('main').innerText();
    check('Email opportunities: 3-day email report (researched, decision makers, named, department, verified, missing, LinkedIn-only, Instagram-only, drafts)',
      [rep.companies_researched, rep.named_public_emails, rep.department_emails, rep.emails_still_missing, rep.ready_email_drafts].every((n) => head.includes(String(n)))
      && /Named public emails/i.test(head) && /LinkedIn-only/i.test(head) && /Instagram-only/i.test(head));
    await page.click('[data-emf=s][data-v=NAMED]');
    check('Email filter: Named person (tier 1)', (await page.locator('.email-card').count()) === Math.min(30, A.email_desk.filter((e) => e.tier === 1).length));
    await page.click('[data-emf=s][data-v=DEPT]');
    check('Email filter: Department (tier 2)', (await page.locator('.email-card').count()) === Math.min(30, A.email_desk.filter((e) => e.tier === 2).length));
    await page.click('[data-emf=s][data-v=GAPS]');
    const g0 = A.email_gaps[0]; const gtxt = await page.locator('main').innerText();
    check('Email gaps: the queue inside Email opportunities (company, decision maker, missing email, score)', (await page.locator('.email-card').count()) === Math.min(30, A.email_gaps.length)
      && gtxt.includes(g0.company) && /no named or department email yet/i.test(gtxt) && gtxt.toLowerCase().includes(`score ${g0.score}`), g0.company);
    await page.click('[data-emf=s][data-v=ALL]');
    const pub = A.email_desk.filter((e) => e.trust === 'PUBLICLY_LISTED').length;
    await page.click('[data-emf=s][data-v=PUBLIC]');
    check('Email filter: Public email', (await page.locator('.email-card').count()) === Math.min(30, pub), `${pub}`);
    await page.click('[data-emf=s][data-v=VERIFIED]');
    check('Email filter: Verified (SMTP) is separate from publicly listed', (await page.locator('.email-card').count()) === A.email_desk.filter((e) => e.trust === 'SMTP_VERIFIED').length);
    await page.click('[data-emf=s][data-v=ALL]');
    await page.locator('[data-email-open]').first().click();
    check('Email card: "What to say" opens the draft or says none exists', (await page.locator('.draft-box').count()) === 1);
    await page.click('.agents-nav [data-tab=agentradar]');
    await page.waitForSelector('.radar-card');
    const rad = await page.locator('main').innerText();
    check('Opportunity radar: routes to money, not records', (await page.locator('.radar-card').count()) === A.radar.length && A.radar.every((r) => rad.includes(r.company)) && rad.includes('→'));
    await page.click('.agents-nav [data-tab=feed]');
    check('Activity feed: every stored event listed', (await page.locator('main .feed-row').count()) === A.feed.length);
    check('Agents views made no write calls', calls.filter((c) => WRITES.includes(c.fn)).length === writesBefore);
  } else check('Agents fixtures present', false, 'tests/fixtures/agents.json missing');

  check('only allow-listed RPCs were called', calls.every((c) => ALLOWED.includes(c.fn)), [...new Set(calls.map((c) => c.fn))].filter((f) => !ALLOWED.includes(f)).join(','));
  check('no JavaScript errors (desktop)', errors.length === 0, errors.join(' | '));
  await browser.close();
}

// 2. Adam's 09:00 phone routine (390 × 844): ten steps, no horizontal scrolling at any point.
{
  const { browser, page, errors, calls } = await runScenario({ viewport: { width: 390, height: 844 } });
  const steps = [];
  const step = async (name, ok) => { const o = await noOverflow(page); steps.push(o); check(`09:00 phone · ${name}`, ok && o <= 1, o > 1 ? `overflow ${o}px` : ''); };
  await page.waitForSelector('.today-sec, .calm');
  await sheet(page, 'overview');
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
  await sheet(page, 'inbox');
  await step('3 Replies reachable from the More sheet', /Replies/.test(await page.locator('main h2').innerText()));
  await sheet(page, 'outreach');
  await page.click('main .tabs [data-otab=READY]');
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
  await page.fill('#q', 'Magali');
  await page.waitForSelector('.results');
  await step('7 search finds a person', /Magali/.test(await page.locator('.results').innerText()));
  await page.fill('#q', '');
  await page.click('#bmenu');
  await page.click('.sheet [data-tab=relationships]');
  await step('7b past relationships from the menu: who wrote last, with Gmail links', /They wrote last/.test(await page.locator('main').innerText()) && (await page.locator('main a[href*="mail.google.com"]').count()) > 0);
  const chip = await page.locator('main .chip').first().boundingBox();
  await page.click('main [data-rel-status=REPLY_NOW]');
  await page.waitForTimeout(300);
  await step('7c review one at a time: thumb-sized status chips, one tap saves', chip && chip.height >= 36 && last(calls, 'hq_relationship_status')?.body.p_status === 'REPLY_NOW');
  await sheet(page, 'outreach');
  await page.click('main .tabs [data-otab=READY]');
  const readyN = await page.locator('article.card.ready').count();
  if (readyN > 1) {
    await page.click('main [data-one-toggle]');
    await step('7d Outreach one at a time: a single card with Back / Skip', (await page.locator('article.card.ready').count()) === 1 && /1\s*of/.test(await page.locator('main .review-nav').innerText()));
    await page.click('main [data-one-toggle]');
  } else await step('7d Outreach one at a time (fewer than 2 ready cards — toggle hidden)', true);
  await page.click('#bmenu');
  await page.waitForSelector('.sheet');
  const sheetBtns = await page.locator('.sheet-grid button').count();
  await page.click('.sheet [data-tab=pipeline]');
  await page.click('main [data-pview=board]');
  await step('8 Menu sheet → Pipeline board', sheetBtns >= 18 && (await page.locator('.board .bcol').count()) > 0);
  await page.screenshot({ path: 'tests/out/mobile-pipeline.png' });
  await page.click('#bmenu');
  await page.click('.sheet [data-tab=finance]');
  await step('9 Menu → Finance: money separated, forecast not set', /Forecast/.test(await page.locator('main').innerText()));
  await page.click('.bnav [data-tab=today]');
  await page.click('#quick');
  await page.click('.modal [data-modal=new-opp]');
  await page.fill('#f-co', 'Test Co'); await page.fill('#f-type', 'Corporate retreat');
  await page.click('#m-ok');
  await page.waitForSelector('.drawer');
  await step('10 + New opportunity from the phone opens the new record', !!last(calls, 'hq_create_opportunity'));
  if (agentsFx) {
    await closeDrawer(page);
    await sheet(page, 'agentfloor');
    await page.waitForSelector('.agent-card');
    await step('11 Classic agent floor from the More sheet: cards first', (await page.locator('.agent-card').count()) === agentsFx.agents.length);
    const hosp = agentsFx.agents.find((a) => a.key === 'HOSPITALITY');
    await page.locator('.agent-card', { hasText: hosp.name }).first().click();
    await page.waitForSelector('[data-agent-sec]');
    const t = await page.locator('.agent-detail').innerText();
    await step('12 Tap Partnerships agent: new companies, decision makers, emails, ready, latest finds', t.includes(String(hosp.today.discovered)) && t.includes(String(hosp.today.decision_makers))
      && t.includes(String(hosp.today.public_emails)) && /ready for Adam/i.test(t) && (await page.locator('main .panel .mini').count()) > 0);
    await page.screenshot({ path: 'tests/out/mobile-agent.png', fullPage: true });
    for (const tab of ['emails', 'agentradar', 'feed']) {
      await page.click(`.agents-nav [data-tab=${tab}]`);
      await page.waitForTimeout(100);
      const o = await noOverflow(page);
      check(`mobile 390px: no horizontal page overflow on ${tab}`, o <= 1, `${o}px`);
    }
    await page.screenshot({ path: 'tests/out/mobile-emails.png', fullPage: false });
  }
  for (const tab of ['relationships', 'linkedin', 'contacts', 'companies', 'markets', 'costs', 'growth', 'help', 'system', 'radar', 'actions', 'partners', 'events', 'projects', 'library']) {
    await closeDrawer(page);
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
  await go(page, 'outreach');
  await page.click('main .tabs [data-otab=READY]');
  await page.waitForSelector('article.card.ready');
  await go(page, 'companies');
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
