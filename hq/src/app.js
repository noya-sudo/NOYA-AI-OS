// NOYA HQ — CEO operating terminal.
// Reads two admin-gated RPCs: hq_overview() (Overview: action queue, scorecard, money, replies,
// website, system — computed server-side) and hq_dashboard() (section views). Writes only through
// hq_save_draft / hq_approve_draft / hq_hold / hq_reject / hq_redispatch (outreach approval) and
// hq_task_action (complete / snooze an ordinary task). There is deliberately no "send" action:
// APPROVE & DRAFT creates a Gmail draft; Adam presses Send in Gmail; workflow 13 logs it.
import { createClient } from '@supabase/supabase-js';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, GMAIL_DRAFTS_URL, GMAIL_THREAD_URL } from './config.js';

const sb = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
});

// Navigation. Items without a view are later build phases: shown, never faked.
const NAV = [
  ['Today', [['overview', 'Overview']]],
  ['Commercial', [['outreach', 'Outreach'], ['pipeline', 'Pipeline'], ['inbox', 'Inbox'], ['tasks', 'Tasks'], ['website', 'Website leads'], ['finance', 'Finance']]],
  ['Insight', [['intelligence', 'Intelligence'], ['reports', 'Reports'], ['system', 'System']]],
  ['Next phases', [['contacts', 'Contacts', 'P4'], ['companies', 'Companies', 'P4'], ['partnerships', 'Partnerships', 'P10'], ['production', 'Production', 'P10'], ['hospitality', 'Hospitality / Creators', 'P10'], ['settings', 'Settings', 'P12']]],
];
const STAGES = ['NEW', 'RESEARCHING', 'READY', 'CONTACTED', 'FOLLOW_UP', 'INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST', 'LONG_TERM', 'ARCHIVED'];
const LOOP = [['PENDING_APPROVAL', 'Pending approval'], ['DRAFT_CREATED', 'Draft created'], ['SENT', 'Sent'], ['REPLIED', 'Replied'], ['NEXT', 'Follow-up / meeting / proposal']];
const REPLY_ORDER = { MEETING_REQUEST: 0, POSITIVE: 1, NEEDS_INFO: 2, REFERRAL: 3, UNKNOWN: 4, BOUNCE: 5, NOT_NOW: 6, DECLINED: 7, OUT_OF_OFFICE: 8, UNRELATED: 9 };
const REPLY_GROUP = { MEETING_REQUEST: 'Meeting request', POSITIVE: 'Positive', NEEDS_INFO: 'Needs information', REFERRAL: 'Referral', DECLINED: 'Not interested', NOT_NOW: 'Not now', OUT_OF_OFFICE: 'Out of office', BOUNCE: 'Bounce', UNKNOWN: 'Other / human review', UNRELATED: 'Other / human review' };

const state = {
  session: null, data: null, ov: null, error: null, ovError: null, notice: null, tab: 'overview', loading: false,
  modal: null, drawer: null, q: '', queueAll: false, queueP3: false,
  taskFilter: { when: 'all', dept: '', prio: '', owner: '', status: '' }, pipeStage: '', pipeQ: '', pollUntil: 0,
};

// ---------------------------------------------------------------- utils
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const $ = (sel) => document.querySelector(sel);
const fmtDate = (d) => (d ? new Date(d).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Cairo' }) : '—');
const fmtDay = (d) => (d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'Africa/Cairo' }) : '—');
const money = (v, cur) => (v == null || v === '' ? '—' : `${cur || ''} ${Number(v).toLocaleString('en-GB', { maximumFractionDigits: 0 })}`.trim());
const cairoDay = (d) => new Date(d).toLocaleDateString('en-CA', { timeZone: 'Africa/Cairo' });
const todayKey = () => cairoDay(new Date());
const daysAgo = (d) => (Date.now() - new Date(d).getTime()) / 86400000;
const isToday = (d) => d && cairoDay(d) === todayKey();
const isThisWeek = (d) => d && daysAgo(d) <= 7 && daysAgo(d) >= -0.01;
const pill = (text, cls = '') => `<span class="pill ${cls}">${esc(text)}</span>`;

function department(createdBy) {
  const s = String(createdBy || '');
  const m = s.match(/^(\d{2})/);
  const map = { '02': 'Brand & Production', '03': 'Hotels & Content', '04': 'Weddings & Events', '05': 'Sales & Outreach', '06': 'Corporate & Private Clients', '07': 'Global Partnerships', '08': 'Creators & Talent', '09': 'Egypt Intelligence', '10': 'Marketing', '11': 'CEO Brief', '12': 'Email', '13': 'Email' };
  if (m && map[m[1]]) return map[m[1]];
  if (/command centre/i.test(s)) return 'CEO Command Centre';
  return s ? 'System' : 'Unassigned';
}
const taskColumn = (s) => ({ OPEN: 'TO DO', IN_PROGRESS: 'IN PROGRESS', WAITING: 'WAITING / BLOCKED', COMPLETED: 'DONE' }[s] || s);
const prioBand = (p) => (p >= 80 ? 'High' : p >= 50 ? 'Medium' : 'Low');


const shortDay = (d) => (d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', timeZone: 'Africa/Cairo' }) : '—');
const lbl = (kind) => ({ ACTUAL: '<span class="lbl actual">Actual</span>', ESTIMATE: '<span class="lbl est">Estimate</span>', UNKNOWN: '<span class="lbl unk">Unknown</span>' }[kind] || '');
const openStatuses = ['OPEN', 'IN_PROGRESS', 'WAITING'];

// ---------------------------------------------------------------- data
async function load(silent = false) {
  if (!silent) { state.loading = true; render(); }
  const [dash, ov] = await Promise.all([sb.rpc('hq_dashboard'), sb.rpc('hq_overview')]);
  state.loading = false;
  if (dash.error) {
    state.error = /not authorised/i.test(dash.error.message)
      ? 'This account is not authorised for NOYA HQ.'
      : `Could not load live data: ${dash.error.message}`;
  } else {
    state.data = dash.data;
    state.error = null;
  }
  if (ov.error) state.ovError = `Overview unavailable: ${ov.error.message}`;
  else { state.ov = ov.data; state.ovError = null; }
  render();
}

async function call(fn, args, successText) {
  state.notice = null;
  const { data, error } = await sb.rpc(fn, args);
  if (error) { state.notice = { err: true, text: error.message }; render(); return null; }
  if (data && data.ok === false) {
    state.notice = { err: true, text: explain(data) };
  } else {
    state.notice = { err: false, text: successText };
  }
  await load(true);
  return data;
}

function explain(r) {
  const reason = r.reason || '';
  const map = {
    ALREADY_PROCESSED: 'Already approved — a draft exists or is being created. Nothing new was done.',
    ALREADY_APPROVED: 'This outreach is already approved; it can no longer be edited, held or rejected.',
    DRAFT_CHANGED_REFRESH: 'The draft changed since you opened it. The latest version is now shown — please review and approve again.',
    REJECTED: 'This outreach was rejected and cannot be approved.',
    REASON_REQUIRED: 'Please give a reason for rejecting.',
    INVALID_DATE: 'Review date must be between today and one year ahead.',
    INVALID_CONTENT: 'Subject and body are required (subject up to 200 characters).',
    NO_DRAFT: 'No draft exists for this opportunity.',
    OPPORTUNITY_NOT_FOUND: 'This opportunity no longer exists.',
    HUMAN_ONLY_DRAFT_ONLY: 'Human-only opportunity: draft only.',
    NOT_ELIGIBLE: 'Not eligible for retry yet.',
  };
  if (reason.startsWith('EMAIL_NOT_VERIFIED')) return `Blocked: the contact email is ${reason.split(':')[1] || 'not verified'}. Only VERIFIED emails can be drafted.`;
  if (reason === 'DO_NOT_CONTACT') return 'Blocked: this contact is marked do-not-contact.';
  if (reason === 'NO_CONTACT' || reason === 'NO_EMAIL') return 'Blocked: no contact email on record.';
  return map[reason] || `Not done: ${reason}`;
}


// ---------------------------------------------------------------- auth
async function initAuth() {
  const { data } = await sb.auth.getSession();
  state.session = data.session;
  sb.auth.onAuthStateChange((_evt, session) => {
    const was = !!state.session;
    state.session = session;
    if (!session) { state.data = null; render(); }
    else if (!was && !mustChangePassword()) { load(); } else { render(); }
  });
  if (state.session && !mustChangePassword()) load(); else render();
}

function mustChangePassword() {
  return !!state.session?.user?.user_metadata?.must_change_password;
}

function renderLogin() {
  $('#app').innerHTML = `
    <form class="login" id="login">
      <h1>NOYA</h1>
      <p>HQ · Operating terminal</p>
      ${state.error ? `<div class="banner err">${esc(state.error)}</div>` : ''}
      <label class="field"><span>Email</span><input name="email" type="email" autocomplete="username" required></label>
      <label class="field"><span>Password</span><input name="password" type="password" autocomplete="current-password" required></label>
      <button class="btn primary full" type="submit">Sign in</button>
    </form>`;
  $('#login').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    const { error } = await sb.auth.signInWithPassword({ email: String(f.get('email')).trim(), password: String(f.get('password')) });
    state.error = error ? 'Sign-in failed. Check your email and password.' : null;
    if (error) renderLogin();
  });
}

function renderPasswordChange(forced) {
  $('#app').innerHTML = `
    <form class="login" id="pw">
      <h1>NOYA</h1>
      <p>${forced ? 'Set your own password before continuing.' : 'Change password'}</p>
      ${state.error ? `<div class="banner err">${esc(state.error)}</div>` : ''}
      <label class="field"><span>New password (min 12 characters)</span><input name="p1" type="password" autocomplete="new-password" minlength="12" required></label>
      <label class="field"><span>Repeat</span><input name="p2" type="password" autocomplete="new-password" minlength="12" required></label>
      <button class="btn primary full" type="submit">Save password</button>
      ${forced ? '' : '<button class="btn full mt8" type="button" id="pwcancel">Cancel</button>'}
    </form>`;
  $('#pw').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    const p1 = String(f.get('p1')); const p2 = String(f.get('p2'));
    if (p1.length < 12 || p1 !== p2) { state.error = 'Passwords must match and be at least 12 characters.'; return renderPasswordChange(forced); }
    const { data, error } = await sb.auth.updateUser({ password: p1, data: { must_change_password: false } });
    if (error) { state.error = error.message; return renderPasswordChange(forced); }
    state.error = null; state.session = { ...state.session, user: data.user }; state.modal = null;
    state.notice = { err: false, text: 'Password updated.' };
    load();
  });
  $('#pwcancel')?.addEventListener('click', () => { state.modal = null; render(); });
}


// ---------------------------------------------------------------- shell
function navBadge(key) {
  const ov = state.ov; const d = state.data;
  if (key === 'overview' && ov) { const p1 = ov.actions.filter((a) => a.prio === 'P1').length; return p1 ? `<span class="badge hot">${p1}</span>` : ''; }
  if (key === 'outreach' && ov) { const n = ov.scorecard.approvals_ready.n; return n ? `<span class="badge">${n}</span>` : ''; }
  if (key === 'inbox' && d) { const n = repliesForAdam(d).length; return n ? `<span class="badge hot">${n}</span>` : ''; }
  if (key === 'website' && ov) { const n = ov.website.filter((w) => w.status === 'NEW').length; return n ? `<span class="badge hot">${n}</span>` : ''; }
  if (key === 'system' && ov) { const n = ov.system.failures.length + ov.system.signals.filter((s) => !s.ok).length; return n ? `<span class="badge hot">${n}</span>` : ''; }
  return '';
}

function render() {
  document.body.classList.toggle('auth', !state.session || mustChangePassword() || state.modal === 'password');
  if (!state.session) return renderLogin();
  if (mustChangePassword()) return renderPasswordChange(true);
  if (state.modal === 'password') return renderPasswordChange(false);
  const d = state.data;
  const live = state.ov || d;
  const view = VIEWS[state.tab];
  const flat = NAV.flatMap(([, items]) => items).filter((i) => !i[2]);
  $('#app').innerHTML = `
    <div class="shell">
      <div class="side-col"><aside class="side">
        <div class="brand">${__HAS_LOGO__ ? '<img src="/noya-mark.svg" alt="">' : ''}<span class="word">NOYA<small>HQ · Private office</small></span></div>
        ${NAV.map(([g, items]) => `<div class="nav-group"><h6>${g}</h6>${items.map(([k, l, phase]) => phase
          ? `<div class="nav-item off" title="Not built yet (build phase ${phase})"><span>${l}</span><span class="soon">${phase}</span></div>`
          : `<button class="nav-item ${state.tab === k ? 'active' : ''}" data-tab="${k}"><span>${l}</span>${navBadge(k)}</button>`).join('')}</div>`).join('')}
      </aside></div>
      <div>
        <div class="topbar"><div class="mbrand">NOYA</div>
          <div class="search"><input id="q" type="search" placeholder="Search companies, people, opportunities, tasks…" value="${esc(state.q)}" autocomplete="off">${state.q.trim().length >= 2 ? searchResults(state.q) : ''}</div>
          <div class="meta">
            <span>${live ? `Live · ${esc(fmtDate(live.generated_at))} Cairo` : state.loading ? 'Loading…' : ''}</span>
            <button class="btn small" id="refresh">Refresh</button>
            <button class="btn small" id="menu" title="Account">⋯</button>
          </div>
        </div>
        <nav class="mnav">${flat.map(([k, l]) => `<button data-tab="${k}" class="${state.tab === k ? 'active' : ''}">${l}</button>`).join('')}</nav>
        <main>
          ${state.notice ? `<div class="banner ${state.notice.err ? 'err' : 'ok'}">${esc(state.notice.text)}</div>` : ''}
          ${state.error ? `<div class="banner err">${esc(state.error)}</div>` : ''}
          ${d && view ? view(d) : `<p class="muted">${state.loading ? 'Loading live CRM…' : 'No data.'}</p>`}
        </main>
      </div>
    </div>
    ${state.drawer ? renderDrawer(state.drawer) : ''}
    ${state.modal && typeof state.modal === 'object' ? renderAnyModal(state.modal) : ''}`;
  bind();
  if (state.focusSearch) { const q = $('#q'); q.focus(); q.setSelectionRange(q.value.length, q.value.length); state.focusSearch = false; }
}

// ---------------------------------------------------------------- search (records already loaded)
function searchResults(raw) {
  const q = raw.trim().toLowerCase(); const d = state.data; if (!d) return '';
  const has = (...v) => v.some((x) => String(x ?? '').toLowerCase().includes(q));
  const opps = d.opportunities.filter((o) => has(o.company_name, o.contact_name, o.opportunity_type, o.next_action)).slice(0, 8);
  const people = [...new Map(d.opportunities.filter((o) => o.contact_name && has(o.contact_name)).map((o) => [o.contact_name, o])).values()].slice(0, 6);
  const tasks = d.tasks.filter((t) => t.status !== 'CANCELLED' && has(t.title, t.company_name)).slice(0, 8);
  const replies = d.inbound.filter((r) => has(r.from, r.company_name, r.subject, r.summary)).slice(0, 5);
  const enq = d.enquiries.filter((e) => has(e.name, e.company, e.reference, e.destination)).slice(0, 5);
  const group = (title, rows) => (rows.length ? `<h6>${title}</h6>${rows.join('')}` : '');
  const html = [
    group('Opportunities', opps.map((o) => `<button class="hit" data-open-opp="${o.id}"><div>${esc(o.company_name)}</div><div class="s">${esc(o.status)} · ${esc(o.contact_name || 'no contact')} · ${esc(String(o.opportunity_type || '').slice(0, 60))}</div></button>`)),
    group('People', people.map((o) => `<button class="hit" data-open-opp="${o.id}"><div>${esc(o.contact_name)}</div><div class="s">${esc(o.contact_position || '')} · ${esc(o.company_name)} · email ${esc(o.email_status || 'none')}</div></button>`)),
    group('Tasks', tasks.map((t) => `<button class="hit" ${t.opportunity_id ? `data-open-opp="${t.opportunity_id}"` : 'data-go="tasks"'}><div>${esc(t.title)}</div><div class="s">${esc(t.status)} · ${esc(t.task_type)} · due ${esc(fmtDay(t.due_at))}</div></button>`)),
    group('Replies', replies.map((r) => `<button class="hit" ${r.opportunity_id ? `data-open-opp="${r.opportunity_id}"` : 'data-go="inbox"'}><div>${esc(r.company_name || r.from)} — ${esc(r.classification || '')}</div><div class="s">${esc(fmtDate(r.received_at))} · ${esc(r.subject || '')}</div></button>`)),
    group('Website leads', enq.map((e) => `<button class="hit" data-go="website"><div>${esc(e.name || e.company)}</div><div class="s">${esc(e.lead_type)} · ${esc(fmtDate(e.created_at))}</div></button>`)),
  ].join('');
  return `<div class="results">${html || '<div class="hit s">No matching records.</div>'}</div>`;
}

// ---------------------------------------------------------------- OVERVIEW
function actionRow(a) {
  const due = a.due_at ? `${a.overdue ? '<span class="od">overdue · ' : ''}due ${esc(shortDay(a.due_at))}${a.overdue ? '</span>' : ''}` : '';
  const value = a.value != null ? `${esc(money(a.value, a.currency))}${lbl('ESTIMATE')}` : '';
  const who = [a.company, a.person].filter(Boolean).map(esc).join(' · ');
  const canTask = a.task_id && a.task_type !== 'SALES_OUTREACH_APPROVAL';
  return `<div class="q-row">
    <div class="prio ${a.prio}">${a.prio}</div>
    <div><div class="q-act">${esc(a.action)}</div>
      <div class="q-meta">${who || '—'}${due ? ` · ${due}` : ''}${value ? ` · ${value}` : ''}</div>
      <div class="q-meta src">${esc(a.source)}${a.next_action ? ` · next: ${esc(a.next_action)}` : ''}</div></div>
    <div class="q-btns">
      ${a.opportunity_id ? `<button class="btn small" data-open-opp="${a.opportunity_id}">Open</button>` : `<button class="btn small" data-go="${a.go}">Open</button>`}
      ${a.kind === 'APPROVE' ? `<button class="btn small" data-go="outreach" data-anchor="opp-${a.opportunity_id}">Review</button>` : ''}
      ${canTask ? `<button class="btn small" data-task="done" data-id="${a.task_id}">Done</button><button class="btn small" data-task="snooze" data-id="${a.task_id}">Snooze</button>` : ''}
    </div></div>`;
}

function viewOverview(d) {
  const ov = state.ov;
  if (!ov) return `<div class="banner err">${esc(state.ovError || 'Overview not loaded.')}</div>`;
  const P = (p) => ov.actions.filter((a) => a.prio === p);
  const p1 = P('P1'); const p2 = P('P2'); const p3 = P('P3');
  const p2shown = state.queueAll ? p2 : p2.slice(0, 8);
  const s = ov.scorecard; const m = ov.money;
  const stageOrder = STAGES.filter((k) => s.stages[k]);
  const total = stageOrder.reduce((n, k) => n + s.stages[k], 0) || 1;
  const sc = (label, n, def, go) => `<div class="k ${go ? 'clk' : ''}" title="${esc(def)}" ${go ? `data-go="${go}"` : ''}>${label}</div><div class="v">${esc(n)}</div>`;
  const sigBad = ov.system.signals.filter((x) => !x.ok).length + ov.system.failures.length;
  const replies = ov.replies;
  const day = new Date(`${ov.today}T12:00:00Z`).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' });
  return `
    <div class="ov-head"><h1>Today</h1><span class="sub">${esc(day)} · every figure is a live query; hover a label for its definition</span></div>
    ${state.ovError ? `<div class="banner err">${esc(state.ovError)}</div>` : ''}
    <div class="ov-grid">
      <section class="panel">
        <header><h3>Action queue</h3><div class="counts"><span>P1 ${p1.length}</span><span>P2 ${p2.length}</span><span>P3 ${p3.length}</span></div></header>
        <div class="body">
          ${p1.length ? p1.map(actionRow).join('') : '<div class="empty">No P1 items — nothing urgent or revenue-critical is waiting.</div>'}
          ${p2shown.map(actionRow).join('')}
          ${p2.length > 8 ? `<button class="linkish" id="queue-all">${state.queueAll ? 'Show fewer' : `Show all ${p2.length} P2 actions`}</button>` : ''}
          ${p3.length ? `<div><button class="linkish" id="queue-p3">${state.queueP3 ? 'Hide' : 'Show'} ${p3.length} P3 (operational)</button></div>${state.queueP3 ? p3.map(actionRow).join('') : ''}` : ''}
        </div>
      </section>
      <div>
        <section class="panel">
          <header><h3>Scorecard</h3><span class="small faint">records, not estimates</span></header>
          <div class="body">
            <div class="stagebar" title="${esc(stageOrder.map((k) => `${k} ${s.stages[k]}`).join(' · '))}">${stageOrder.map((k) => `<span class="${['CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON', 'INTERESTED'].includes(k) ? 'hot' : ''}" data-flex="${(s.stages[k] / total).toFixed(4)}"></span>`).join('')}</div>
            <div class="small faint">${esc(stageOrder.map((k) => `${k.replace('_', ' ').toLowerCase()} ${s.stages[k]}`).join(' · '))}</div>
            <div class="score mt8">
              ${sc('Active opportunities', s.active_opportunities.n, s.active_opportunities.def, 'pipeline')}
              ${sc('In conversation', s.in_conversation.n, s.in_conversation.def, 'pipeline')}
              ${sc('Call required', s.call_required.n, s.call_required.def, 'pipeline')}
              ${sc('Proposals open', s.proposals.n, s.proposals.def, 'pipeline')}
              ${sc('Won', s.won.n, s.won.def, 'pipeline')}
              ${sc('Approvals ready', s.approvals_ready.n, s.approvals_ready.def, 'outreach')}
              ${sc('Positive replies · 7d', s.positive_replies_7d.n, s.positive_replies_7d.def, 'inbox')}
              ${sc('Website enquiries · 7d', s.website_7d.n, `${s.website_7d.def} (all-time ${s.website_7d.total})`, 'website')}
              ${sc('Overdue tasks', s.overdue_tasks.n, s.overdue_tasks.def, 'tasks')}
              ${sc('System', sigBad ? `${sigBad} issue${sigBad > 1 ? 's' : ''}` : 'OK', 'workflow signals + failure alerts', 'system')}
            </div>
          </div>
        </section>
        <section class="panel mt8">
          <header><h3>Money</h3><button class="btn small ghost" data-go="finance">Finance</button></header>
          <div class="body">${moneyBlock(m)}</div>
        </section>
      </div>
    </div>
    <div class="ov-grid3">
      <section class="panel"><header><h3>Replies · 14 days</h3><button class="btn small ghost" data-go="inbox">Inbox</button></header>
        <div class="body">${replies.length ? replies.slice(0, 5).map((r) => `<div class="mini clickable" ${r.opportunity_id ? `data-open-opp="${r.opportunity_id}"` : ''}>
          <div class="t">${esc(r.company || r.from)} ${pill(REPLY_GROUP[r.classification] || r.classification, r.classification === 'MEETING_REQUEST' ? 'bad' : r.deterministic ? '' : 'info')}</div>
          <div class="m">${esc(fmtDate(r.received_at))} · ${esc(r.person || r.from || '')}${r.deterministic ? ' · rule-based label' : ''}</div>
          <div class="m">${esc(r.summary || '')}</div></div>`).join('') : '<div class="empty">No replies in the last 14 days.</div>'}</div></section>
      <section class="panel"><header><h3>Website · 30 days</h3><button class="btn small ghost" data-go="website">Leads</button></header>
        <div class="body">${ov.website.length ? ov.website.slice(0, 5).map((w) => `<div class="mini"><div class="t">${esc(w.name || w.company || 'Enquiry')} ${pill(w.lead_type)}</div>
          <div class="m">${esc(fmtDate(w.created_at))} · ${esc(w.status)}${w.destination ? ` · ${esc(w.destination)}` : ''}${w.guests ? ` · ${esc(w.guests)} guests` : ''}</div></div>`).join('')
          : `<div class="empty">No website enquiries in the last 30 days (all-time: ${esc(s.website_7d.total)}). Intake (workflow 10d) is live and waiting for the new website form.</div>`}</div></section>
      <section class="panel"><header><h3>System</h3><button class="btn small ghost" data-go="system">Details</button></header>
        <div class="body">
          ${ov.system.failures.map((f) => `<div class="sig"><span><span class="dot bad"></span>${esc(f.title)}</span></div>`).join('')}
          ${ov.system.signals.map((x) => `<div class="sig" title="${esc(x.rule)}"><span><span class="dot ${x.ok ? '' : 'bad'}"></span>${esc(x.name)}</span><span class="faint">${esc(x.last ? fmtDate(x.last) : 'never')}</span></div>`).join('')}
          ${ov.system.blockers.length ? `<div class="small faint mt8">${ov.system.blockers.length} known blocker${ov.system.blockers.length > 1 ? 's' : ''} (not failures): ${esc(ov.system.blockers.map((b) => b.title).join(' · '))}</div>` : ''}
        </div></section>
    </div>`;
}

function moneyBlock(m) {
  const cur = m.by_currency || [];
  const line = (k, v, kind) => `<div class="money-line"><span>${k}${lbl(kind)}</span><span class="v">${v}</span></div>`;
  const rev = m.revenue_records === 0
    ? line('Collected', '<span class="muted">none recorded</span>', 'ACTUAL') + line('Outstanding', '<span class="muted">none recorded</span>', 'ACTUAL')
    : cur.map((c) => line(`Collected (${esc(c.currency)})`, c.collected != null ? esc(money(c.collected, c.currency)) : '<span class="muted">none</span>', 'ACTUAL')
        + line(`Outstanding (${esc(c.currency)})`, c.outstanding != null ? esc(money(c.outstanding, c.currency)) : '<span class="muted">none</span>', 'ACTUAL')
        + (c.part_paid_records ? line(`Part-paid (${esc(c.currency)})`, `${c.part_paid_records} record(s), paid portion`, 'UNKNOWN') : '')).join('');
  const pipe = (m.pipeline_estimate || []).map((p) => line(`Pipeline (${esc(p.currency)})`, `${esc(money(p.amount, p.currency))} <span class="faint small">(${p.opportunities} opps)</span>`, 'ESTIMATE')).join('');
  return `${rev}${line('Won deals', esc(m.won_deals), 'ACTUAL')}${pipe}
    ${m.pipeline_unknown_value ? line('Pipeline value not estimated', `${esc(m.pipeline_unknown_value)} opps`, 'UNKNOWN') : ''}
    <div class="src mt6">Revenue records: ${esc(m.revenue_records)}. Pipeline is a research estimate, never revenue. Currencies are shown separately.</div>`;
}

// ---------------------------------------------------------------- OUTREACH
function repliesForAdam(d) {
  return d.inbound.filter((r) => r.task_id && openStatuses.includes(r.task_status)
    && !['OUT_OF_OFFICE', 'UNRELATED'].includes(r.classification))
    .sort((a, b) => (REPLY_ORDER[a.classification] ?? 9) - (REPLY_ORDER[b.classification] ?? 9));
}
const openTasks = (d) => d.tasks.filter((t) => openStatuses.includes(t.status));

function manualChannelRows(d, kind) {
  const acts = (state.ov?.actions || []).filter((a) => a.kind === kind);
  if (!acts.length) return '<p class="muted small">None.</p>';
  return acts.map((a) => {
    const t = d.tasks.find((x) => x.id === a.task_id);
    const msg = t ? String(t.description || '').split('--- MESSAGE ---')[1]?.split('\n\nAfter sending')[0]?.trim() : '';
    return `<div class="row"><div class="t">${esc(a.company || '')}${a.person ? ` · ${esc(a.person)}` : ''}</div>
      <div class="meta">${esc(a.source)} · due ${esc(shortDay(a.due_at))}</div>
      ${msg ? `<div class="email"><pre>${esc(msg)}</pre></div>` : `<div class="small muted mt6">${esc(a.action)}</div>`}
      <div class="btn-row">${a.opportunity_id ? `<button class="btn small" data-open-opp="${a.opportunity_id}">Open record</button>` : ''}
      <button class="btn small" data-task="done" data-id="${a.task_id}">Sent — mark done</button><button class="btn small" data-task="snooze" data-id="${a.task_id}">Snooze</button></div></div>`;
  }).join('');
}

function viewOutreach(d) {
  const a = d.approvals;
  const ready = a.filter((x) => x.loop_stage === 'PENDING_APPROVAL' && !x.block_reason);
  const blocked = a.filter((x) => x.loop_stage === 'PENDING_APPROVAL' && x.block_reason);
  const inFlight = a.filter((x) => ['APPROVED', 'DRAFT_CREATED', 'FAILED', 'DRAFT_DISCARDED'].includes(x.loop_stage));
  const sent = a.filter((x) => ['SENT', 'REPLIED'].includes(x.loop_stage));
  const held = a.filter((x) => x.loop_stage === 'ON_HOLD');
  const rejected = a.filter((x) => x.loop_stage === 'REJECTED');
  const followUps = openTasks(d).filter((t) => t.task_type === 'OUTREACH_FOLLOW_UP').sort((x, y) => new Date(x.due_at) - new Date(y.due_at));
  const researching = d.opportunities.filter((o) => ['NEW', 'RESEARCHING'].includes(o.status));
  return `
    <h2>Outreach</h2>
    <p class="muted small">Approving creates a Gmail draft in noya@noyaconcierge.com. Nothing is sent from HQ — you press Send in Gmail and workflow 13 logs it. LinkedIn and Instagram messages are sent by you from your own accounts.</p>
    <h3>Ready for approval (${ready.length})</h3>
    ${ready.map(approvalCard).join('') || '<p class="muted">No approval-ready email outreach.</p>'}
    ${inFlight.length ? `<h3>In progress (${inFlight.length})</h3>${inFlight.map(approvalCard).join('')}` : ''}
    <h3>LinkedIn — ready (${(state.ov?.actions || []).filter((x) => x.kind === 'LINKEDIN').length})</h3>${manualChannelRows(d, 'LINKEDIN')}
    <h3>Instagram — ready (${(state.ov?.actions || []).filter((x) => x.kind === 'INSTAGRAM').length})</h3>${manualChannelRows(d, 'INSTAGRAM')}
    <h3>Follow-ups (${followUps.length})</h3>
    <div class="list">${followUps.map((t) => `<div class="row"><div class="t">${esc(t.title)}</div><div class="meta">due ${esc(fmtDay(t.due_at))}${new Date(t.due_at) < new Date() ? ' · <span class="bad-text">overdue</span>' : ''}</div></div>`).join('') || '<p class="muted small">None.</p>'}</div>
    <h3>Sent (${sent.length})</h3>
    <details><summary>Show ${sent.length} sent outreach</summary>${sent.map(approvalCard).join('')}</details>
    ${held.length ? `<h3>On hold (${held.length})</h3>${held.map(approvalCard).join('')}` : ''}
    <h3>Email route blocked — contact needed (${blocked.length})</h3>
    <details><summary>Show ${blocked.length} opportunities that need a verified contact first</summary>${blocked.map(approvalCard).join('')}</details>
    ${rejected.length ? `<h3>Rejected (${rejected.length})</h3><details><summary>Show</summary>${rejected.map(approvalCard).join('')}</details>` : ''}
    <h3>Researching (${researching.length})</h3>
    <p class="muted small">Prospects not yet ready — workflow 05 resolves contacts and drafts them (up to 10 a day, highest commercial priority first).</p>`;
}

function loopBar(stage) {
  const order = ['PENDING_APPROVAL', 'DRAFT_CREATED', 'SENT', 'REPLIED', 'NEXT'];
  const idx = stage === 'APPROVED' ? 0.5 : order.indexOf(stage);
  return `<div class="loop">${LOOP.map(([k, l], i) => `<span class="${i < idx ? 'done' : i === idx || (idx === 0.5 && i === 1) ? 'now' : ''}">${l}</span>`).join('')}</div>`;
}

function approvalCard(a) {
  const dr = a.draft || {};
  const ready = a.loop_stage === 'PENDING_APPROVAL' && !a.block_reason;
  const editable = ['PENDING_APPROVAL', 'ON_HOLD'].includes(a.loop_stage) || (a.loop_stage === 'DRAFT_DISCARDED' || a.loop_stage === 'FAILED');
  const emailPill = a.email_status === 'VERIFIED' ? pill('Email verified', 'ok') : pill(`Email ${a.email_status || 'missing'}`, 'bad');
  const stagePill = {
    PENDING_APPROVAL: pill('Pending approval', 'gold'), APPROVED: pill('Creating Gmail draft…', 'info'), DRAFT_CREATED: pill('Draft in Gmail — ready to send', 'ok'),
    SENT: pill('Sent', 'ok'), REPLIED: pill(`Replied${a.last_class ? ` · ${a.last_class}` : ''}`, 'gold'), ON_HOLD: pill(`On hold${a.review_at ? ` until ${fmtDay(a.review_at)}` : ''}`, 'warn'),
    REJECTED: pill('Rejected', 'bad'), FAILED: pill('Draft failed', 'bad'), DRAFT_DISCARDED: pill('Draft deleted unsent', 'warn'),
  }[a.loop_stage] || '';
  let status = '';
  if (a.loop_stage === 'DRAFT_CREATED') status = `<div class="banner ok">Draft created in Gmail${a.gmail_draft_id ? ` (${esc(a.gmail_draft_id)})` : ''}. <a href="${GMAIL_DRAFTS_URL}" target="_blank" rel="noopener noreferrer">Open Gmail Drafts</a> — review, then press Send.</div>`;
  if (a.loop_stage === 'APPROVED') status = `<div class="banner">Approved ${esc(fmtDate(a.outbound_created_at))}. Creating the Gmail draft… ${daysAgo(a.outbound_created_at) * 1440 > 2 ? `<button class="btn small" data-act="redispatch" data-id="${a.outbound_id}">Retry draft creation</button>` : ''}</div>`;
  if (a.loop_stage === 'SENT' || a.loop_stage === 'REPLIED') status = `<div class="banner ok">Sent ${esc(fmtDate(a.sent_at))}${a.sent_via === 'MANUAL_GMAIL' ? ' by Adam from Gmail' : ''}. ${a.gmail_thread_id ? `<a href="${GMAIL_THREAD_URL}${esc(a.gmail_thread_id)}" target="_blank" rel="noopener noreferrer">Open thread</a>` : ''} ${esc(a.next_action || '')}</div>`;
  if (a.loop_stage === 'FAILED') status = `<div class="banner err">Draft creation failed: ${esc(a.outbound_error || 'unknown error')}. You can approve again.</div>`;
  if (a.loop_stage === 'DRAFT_DISCARDED') status = `<div class="banner">The approved Gmail draft was deleted without sending. Approve again if still wanted.</div>`;
  if (a.loop_stage === 'REJECTED' || a.loop_stage === 'ON_HOLD') status = a.queue_reason ? `<div class="banner">${esc(a.queue_reason)}</div>` : '';
  if (a.block_reason && a.loop_stage === 'PENDING_APPROVAL') status = `<div class="banner err">${esc(explain({ reason: a.block_reason }))}</div>`;

  const canApprove = (a.loop_stage === 'PENDING_APPROVAL' || a.loop_stage === 'ON_HOLD' || a.loop_stage === 'FAILED' || a.loop_stage === 'DRAFT_DISCARDED') && !a.block_reason && dr.subject && dr.body;
  const canHoldReject = ['PENDING_APPROVAL', 'ON_HOLD', 'FAILED', 'DRAFT_DISCARDED'].includes(a.loop_stage);
  return `
  <article class="card ${ready ? 'ready' : ''}" id="opp-${a.id}">
    <div class="card-head">
      <div><div class="co">${esc(a.company_name)}</div><div class="muted small">${esc(a.opportunity_type)}</div></div>
      <div class="pills">${stagePill}${a.human_only ? pill('Human-only · draft only', 'gold') : ''}${pill(`Priority ${a.priority ?? '—'}`)}</div>
    </div>
    ${loopBar(a.loop_stage)}
    ${status}
    <div class="grid2">
      <div class="kv"><div class="k">Contact</div><div class="v">${esc(a.contact_name || '—')}</div></div>
      <div class="kv"><div class="k">Position</div><div class="v">${esc(a.contact_position || '—')}</div></div>
      <div class="kv"><div class="k">Email</div><div class="v">${esc(a.contact_email || '—')} ${emailPill}</div></div>
      <div class="kv"><div class="k">Estimated value</div><div class="v">${esc(money(a.estimated_value, a.currency))} <span class="pill warn">ESTIMATED</span>${a.probability != null ? ` <span class="muted small">${esc(a.probability)}% probability</span>` : ''}</div></div>
      <div class="kv"><div class="k">Approval state</div><div class="v">${esc(a.approval_status)} · CRM stage ${esc(a.status)}</div></div>
      <div class="kv"><div class="k">Draft version</div><div class="v">v${esc(dr.version || 1)} ${dr.source === 'ADAM_EDIT' ? pill('Edited by Adam', 'info') : pill('Original (workflow 05)')}</div></div>
    </div>
    <div class="kv"><div class="k">Why now</div><div class="v">${esc(dr.why_now || dr.signal || 'Not stated in the draft.')}</div></div>
    <div class="kv mt8"><div class="k">Why NOYA</div><div class="v">${esc(dr.why_noya || dr.primary_angle || 'Not stated in the draft.')}</div></div>
    ${a.human_only && dr.human_only_reason ? `<details><summary>Why this is human-only</summary><p>${esc(dr.human_only_reason)}</p></details>` : ''}
    <div class="email"><div class="subj">${esc(dr.subject || '(no subject)')}</div><pre>${esc(dr.body || '(no draft body found)')}</pre></div>
    ${dr.follow_up_plan ? `<details><summary>Follow-up plan</summary><pre class="text">${esc(dr.follow_up_plan)}</pre></details>` : ''}
    ${dr.original_subject && dr.source === 'ADAM_EDIT' ? `<details><summary>Original subject (kept for audit)</summary><p>${esc(dr.original_subject)}</p></details>` : ''}
    ${canHoldReject || canApprove ? `<div class="btn-row">
      ${canApprove ? `<button class="btn primary" data-act="approve" data-id="${a.id}">Approve &amp; Draft</button>` : ''}
      ${editable && canHoldReject ? `<button class="btn" data-act="edit" data-id="${a.id}">Edit</button>` : ''}
      ${canHoldReject && a.loop_stage !== 'ON_HOLD' ? `<button class="btn" data-act="hold" data-id="${a.id}">Hold</button>` : ''}
      ${canHoldReject ? `<button class="btn danger" data-act="reject" data-id="${a.id}">Reject</button>` : ''}
    </div>` : ''}
  </article>`;
}


// ---------------------------------------------------------------- PIPELINE
function viewPipeline(d) {
  const by = {};
  d.opportunities.forEach((o) => { (by[o.status] = by[o.status] || []).push(o); });
  const q = state.pipeQ.trim().toLowerCase();
  const rows = d.opportunities.filter((o) => (!state.pipeStage || o.status === state.pipeStage)
    && (!q || [o.company_name, o.contact_name, o.opportunity_type, o.next_action].some((x) => String(x ?? '').toLowerCase().includes(q))));
  const stale = (o) => daysAgo(o.updated_at) > 14 && !['WON', 'LOST', 'ARCHIVED', 'LONG_TERM'].includes(o.status);
  return `
    <h2>Pipeline</h2>
    <p class="muted small">Estimated values are research estimates (ESTIMATE), never revenue; blank means UNKNOWN. Stale = no update in 14 days.</p>
    <div class="filters"><div class="seg">
      <button data-stage="" class="${!state.pipeStage ? 'on' : ''}">All · ${d.opportunities.length}</button>
      ${STAGES.filter((s) => by[s]).map((s) => `<button data-stage="${s}" class="${state.pipeStage === s ? 'on' : ''}">${s.replace('_', ' ')} · ${by[s].length}</button>`).join('')}
    </div><input id="pipe-q" placeholder="Filter…" value="${esc(state.pipeQ)}"></div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>Company</th><th>Stage</th><th>Contact</th><th class="num">Estimate</th><th class="num">Priority</th><th>Updated</th><th>Next action</th></tr></thead>
      <tbody>${rows.map((o) => `<tr class="clickable" data-open-opp="${o.id}"><td>${esc(o.company_name)}<div class="muted small">${esc(String(o.opportunity_type || '').slice(0, 60))}</div></td>
        <td>${pill(o.status)} ${stale(o) ? pill('stale', 'warn') : ''}</td>
        <td>${esc(o.contact_name || '—')}<div class="muted small">${esc(o.email_status || 'no contact')}</div></td>
        <td class="num">${o.estimated_value != null ? esc(money(o.estimated_value, o.currency)) : '<span class="faint">unknown</span>'}</td><td class="num">${esc(o.priority ?? '—')}</td>
        <td class="small">${esc(shortDay(o.updated_at))}</td>
        <td class="small">${esc(o.next_action || '')}</td></tr>`).join('')}</tbody>
    </table></div>`;
}

// ---------------------------------------------------------------- TASKS
function viewTasks(d) {
  const f = state.taskFilter;
  const now = new Date(); const eod = new Date(); eod.setHours(23, 59, 59, 999);
  const tasks = d.tasks.filter((t) => t.status !== 'CANCELLED').filter((t) => {
    const open = t.status !== 'COMPLETED';
    if (f.when === 'today' && !(open ? t.due_at && new Date(t.due_at) <= eod : isToday(t.completed_at))) return false;
    if (f.when === 'week' && !(open ? t.due_at && daysAgo(t.due_at) >= -7 : isThisWeek(t.completed_at))) return false;
    if (f.when === 'overdue' && !(open && t.due_at && new Date(t.due_at) < now)) return false;
    if (f.dept && department(t.created_by) !== f.dept) return false;
    if (f.prio && prioBand(t.priority ?? 0) !== f.prio) return false;
    if (f.owner && (t.assigned_to || 'Unassigned') !== f.owner) return false;
    return true;
  });
  const depts = [...new Set(d.tasks.map((t) => department(t.created_by)))].sort();
  const owners = [...new Set(d.tasks.map((t) => t.assigned_to || 'Unassigned'))].sort();
  const cols = ['TO DO', 'IN PROGRESS', 'WAITING / BLOCKED', 'DONE'];
  const opt = (v, cur, label = v) => `<option value="${esc(v)}" ${v === cur ? 'selected' : ''}>${esc(label)}</option>`;
  return `
    <h2>Tasks</h2>
    <div class="filters">
      <div class="seg">${[['all', 'All'], ['today', 'Today'], ['week', 'This week'], ['overdue', 'Overdue']].map(([k, l]) => `<button data-when="${k}" class="${f.when === k ? 'on' : ''}">${l}</button>`).join('')}</div>
      <select data-f="dept">${opt('', f.dept, 'All departments')}${depts.map((x) => opt(x, f.dept)).join('')}</select>
      <select data-f="prio">${opt('', f.prio, 'All priorities')}${['High', 'Medium', 'Low'].map((x) => opt(x, f.prio)).join('')}</select>
      <select data-f="owner">${opt('', f.owner, 'All owners')}${owners.map((x) => opt(x, f.owner)).join('')}</select>
    </div>
    <div class="cols">${cols.map((c) => {
      const list = tasks.filter((t) => taskColumn(t.status) === c).sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0));
      return `<div class="col"><h4><span>${c}</span><span>${list.length}</span></h4><div class="list">${list.map((t) => {
        const overdue = t.status !== 'COMPLETED' && t.due_at && new Date(t.due_at) < now;
        const acts = openStatuses.includes(t.status) ? `<div class="btn-row mt6">${t.opportunity_id ? `<button class="btn small" data-open-opp="${t.opportunity_id}">Open</button>` : ''}${t.task_type !== 'SALES_OUTREACH_APPROVAL' ? `<button class="btn small" data-task="done" data-id="${t.id}">Done</button>` : ''}<button class="btn small" data-task="snooze" data-id="${t.id}">Snooze</button></div>` : '';
        return `<div class="row"><div class="t small">${esc(t.title)}</div><div class="meta">${pill(prioBand(t.priority ?? 0), t.priority >= 80 ? 'gold' : '')} ${esc(department(t.created_by))} · ${esc(t.assigned_to || '—')}</div>
          <div class="meta">${t.status === 'COMPLETED' ? `Done ${esc(t.completed_at ? fmtDate(t.completed_at) : '(time not recorded)')}` : `Due ${esc(fmtDay(t.due_at))}${overdue ? ' · <span class="bad-text">overdue</span>' : ''}`}</div>${acts}</div>`;
      }).join('') || '<p class="muted small">None</p>'}</div></div>`;
    }).join('')}</div>`;
}

// ---------------------------------------------------------------- COMPLETED
function completionRow(c) {
  return `<div class="row"><div class="t">${esc(c.what)} — ${esc(c.company || '—')}</div>
    <div class="meta">${esc(fmtDate(c.at))} · ${esc(c.agent)} ${c.revenue_impacting ? pill('Revenue-impacting', 'gold') : ''}</div>
    ${c.result ? `<div class="small">Result: ${esc(c.result)}</div>` : ''}
    <div class="small muted">Evidence: ${esc(c.evidence)}</div>
    ${c.next_action ? `<div class="small">Next: ${esc(c.next_action)}</div>` : ''}</div>`;
}
function viewCompleted(d) {
  const today = d.completions.filter((c) => isToday(c.at));
  const week = d.completions.filter((c) => isThisWeek(c.at));
  const rev = d.completions.filter((c) => c.revenue_impacting);
  return `
    <h2>Completed</h2>
    <p class="muted small">Only commercial outcomes with evidence count here — never routine workflow runs.</p>
    <h3>Completed today (${today.length})</h3><div class="list">${today.map(completionRow).join('') || '<p class="muted">Nothing yet today.</p>'}</div>
    <h3>Completed this week (${week.length})</h3><div class="list">${week.map(completionRow).join('') || '<p class="muted">Nothing this week.</p>'}</div>
    <h3>Revenue-impacting (last 45 days, ${rev.length})</h3><div class="list">${rev.map(completionRow).join('') || '<p class="muted">None yet.</p>'}</div>`;
}


// ---------------------------------------------------------------- INBOX
function suggestedReply(desc) {
  const i = String(desc || '').indexOf('--- SUGGESTED REPLY');
  return i >= 0 ? String(desc).slice(i).split('\n').slice(1).join('\n').trim() : '';
}
function viewInbox(d) {
  const replies = [...d.inbound].sort((a, b) => (REPLY_ORDER[a.classification] ?? 9) - (REPLY_ORDER[b.classification] ?? 9) || new Date(b.received_at) - new Date(a.received_at));
  const cls = (c) => ({ MEETING_REQUEST: 'bad', POSITIVE: 'ok', NEEDS_INFO: 'info', UNKNOWN: 'warn', BOUNCE: 'bad', DECLINED: 'bad' }[c] || '');
  const groups = {};
  replies.forEach((r) => { const g = REPLY_GROUP[r.classification] || 'Other / human review'; (groups[g] = groups[g] || []).push(r); });
  return `
    <h2>Inbox</h2>
    <p class="muted small">Replies to NOYA outreach, logged by workflow 13. Bounce and out-of-office labels come from delivery headers and always override the AI label. Nothing is replied to automatically — suggested replies are drafts for you.</p>
    ${Object.entries(groups).map(([g, list]) => `<h3>${esc(g)} (${list.length})</h3><div class="list">${list.map((r) => {
      const sug = suggestedReply(r.task_description);
      return `<div class="row"><div class="t">${pill(r.classification || r.outcome, cls(r.classification))} ${esc(r.company_name || 'Unmatched — needs review')}</div>
        <div class="meta">${esc(fmtDate(r.received_at))} · from ${esc(r.from || '')} · ${esc(r.subject || '')} · matched by ${esc(r.match_method || '—')}</div>
        <div class="small mt6">${esc(r.summary || '')}</div>
        <div class="small mt6"><b>Next:</b> ${esc(r.task_title || r.next_action || 'No action needed')}${r.task_status ? ` (${esc(r.task_status)})` : ''}</div>
        ${sug ? `<details><summary>Suggested reply (not sent)</summary><pre class="text">${esc(sug)}</pre></details>` : ''}
        <div class="btn-row mt6">${r.opportunity_id ? `<button class="btn small" data-open-opp="${r.opportunity_id}">Open record</button>` : ''}${r.thread_id ? `<a class="btn small" href="${GMAIL_THREAD_URL}${esc(r.thread_id)}" target="_blank" rel="noopener noreferrer">Open in Gmail</a>` : ''}</div></div>`;
    }).join('')}</div>`).join('') || '<p class="muted">No replies yet since go-live.</p>'}`;
}

// ---------------------------------------------------------------- WEBSITE
function viewWebsite(d) {
  const e = d.enquiries;
  return `
    <h2>Website leads</h2>
    <p class="muted small">Submissions from the NOYA website, saved first by workflow 10d, then matched to a contact, company and opportunity with a task for you.</p>
    ${e.length ? `<div class="list">${e.map((x) => `<div class="row"><div class="t">${esc(x.name || x.company || 'Enquiry')} ${pill(x.status, x.status === 'NEW' ? 'bad' : '')} ${pill(x.lead_type)}</div>
      <div class="meta">${esc(fmtDate(x.created_at))} · ${esc(x.reference || '')} ${x.destination ? `· ${esc(x.destination)}` : ''} ${x.budget ? `· budget ${esc(x.budget)}` : ''}</div>
      ${x.message ? `<div class="small">${esc(x.message)}</div>` : ''}</div>`).join('')}</div>`
      : `<div class="panel"><div class="body"><div class="empty">No website enquiries in the last 60 days. The intake (10d) is live; enquiries will appear here the moment the new website form submits.</div></div></div>`}`;
}

// ---------------------------------------------------------------- FINANCE
function viewFinance() {
  const ov = state.ov; if (!ov) return '<p class="muted">Overview data not loaded.</p>';
  const c = ov.system.cost_today || {};
  return `
    <h2>Finance</h2>
    <p class="muted small">V1 reads the existing revenue table. Collected, outstanding, pipeline and costs are never blended, and currencies are never added together. Invoices, amount paid and FX come in build phase 9.</p>
    <div class="ov-grid"><section class="panel"><header><h3>Revenue &amp; pipeline</h3></header><div class="body">${moneyBlock(ov.money)}</div></section>
    <section class="panel"><header><h3>System usage today</h3><span class="small faint">counts actual · money unknown</span></header><div class="body">
      ${[['Serper searches', c.serper_searches], ['Firecrawl calls', c.firecrawl_calls], ['Discovery AI calls', c.ai_calls_discovery], ['Hunter checks (05)', c.hunter_checks], ['Reply classifications (13)', c.reply_ai_calls], ['CEO briefs (11)', c.brief_runs]]
        .map(([k, v]) => `<div class="money-line"><span>${k}${lbl('ACTUAL')}</span><span class="v">${esc(v ?? '—')}</span></div>`).join('')}
      <div class="money-line"><span>Spend${lbl('UNKNOWN')}</span><span class="v muted">unit prices not recorded</span></div>
      <div class="src mt6">${esc(c.note || '')}</div></div></section></div>`;
}

// ---------------------------------------------------------------- REPORTS / SYSTEM
function viewReports(d) {
  const b = d.brief;
  const block = (t, x) => `<h3>${t}${x ? ` · ${esc(fmtDate(x.generated_at))} · ${esc(x.delivery_status)}` : ''}</h3>${x ? `${/AI ENRICHMENT DEGRADED/.test(x.text || '') ? '<div class="banner err">AI enrichment degraded — this brief was built from deterministic facts only.</div>' : ''}<div class="row"><pre class="text">${esc(x.text || '')}</pre></div>` : '<p class="muted">None yet.</p>'}`;
  return `<h2>Reports</h2>${block('Latest daily brief', b.daily)}${block('Latest weekly review', b.weekly)}
    <details><summary>Completed outcomes (45 days)</summary>${viewCompleted(d)}</details>
    <details><summary>Marketing performance</summary>${viewMarketing(d)}</details>`;
}

function viewSystem(d) {
  const ov = state.ov; const h = d.health; const alerts = healthAlerts(d);
  return `
    <h2>System</h2>
    ${alerts.length ? `<div class="banner err">${alerts.map(esc).join('<br>')}</div>` : '<div class="banner ok">No production failures.</div>'}
    <h3>Workflow signals</h3>
    <div class="list">${(ov?.system.signals || []).map((x) => `<div class="row"><div class="t"><span class="dot ${x.ok ? '' : 'bad'}"></span>${esc(x.name)} ${x.ok ? pill('OK', 'ok') : pill('Check', 'bad')}</div><div class="meta">Last ${esc(x.last ? fmtDate(x.last) : 'never')} · rule: ${esc(x.rule)}${x.detail ? ` · ${esc(x.detail)}` : ''}</div></div>`).join('')}
      <div class="row"><div class="t">Gmail sync detail</div><div class="meta">go-live ${esc(fmtDate(h.gmail_sync_go_live))}${h.gmail_sync_summary ? ` · ${esc(Object.entries(h.gmail_sync_summary).map(([k, v]) => `${k.replace(/_/g, ' ')} ${v}`).join(', '))}` : ''}</div></div></div>
    <h3>Known blockers (${ov?.system.blockers.length || 0})</h3>
    <div class="list">${(ov?.system.blockers || []).map((b) => `<div class="row"><div class="t">${pill(b.severity, b.severity === 'BLOCKER' ? 'bad' : b.severity === 'RISK' ? 'warn' : '')} ${esc(b.title)}</div>
      <div class="small mt6">${esc(b.impact)}</div><div class="small mt6"><b>Action:</b> ${esc(b.owner_action)}</div><div class="src mt6">Evidence: ${esc(b.evidence || '—')} · source ${esc(b.source)} · since ${esc(fmtDay(b.detected_at))}</div></div>`).join('') || '<p class="muted">None.</p>'}</div>
    <h3>AI model architecture</h3>
    ${(() => { const r = ov?.system.models?.routing; if (!r) return '<p class="muted">Model routing not recorded.</p>';
      const row = (t, m, what) => `<div class="row"><div class="t">${t} · ${esc(m || 'not set')}</div><div class="meta">${what}</div></div>`;
      return `<div class="list">${row('Primary low-cost', r.primary, 'Extraction, classification, reply meaning')}
        ${row('Drafting', r.drafting, 'Outreach drafts, qualification, CEO brief')}
        ${row('Backup', r.backup, 'Fallback when the primary model fails')}
        ${row('Premium', r.premium, 'Manual escalation only — on no automatic path. Anthropic is optional.')}
        <div class="row"><div class="t">Final fallback</div><div class="meta">Deterministic rules or human review (the CEO brief is built from facts and labelled AI ENRICHMENT DEGRADED).</div></div></div>
        <p class="src mt6">From system_config.ai_model_routing · ${esc(r.provider_path || '')} · ${esc(ov.system.models.note || '')}</p>`; })()}
    <p class="src mt8">Per-workflow execution history (last success/failure per n8n workflow) is build phase 11; today these signals come from the records each workflow writes. Failures also email Adam through workflow 00. Signed in as ${esc(d.admin)}.</p>`;
}

// ---------------------------------------------------------------- MARKETING / INTELLIGENCE
function viewMarketing(d) {
  const c = d.marketing.content; const p = d.marketing.paid;
  return `
    <h2>Marketing</h2>
    <h3>Organic content (latest)</h3>
    <div class="tbl-wrap"><table><thead><tr><th>Date</th><th>Post</th><th class="num">Reach</th><th class="num">Saves</th><th class="num">Shares</th><th class="num">Interaction rate</th></tr></thead>
    <tbody>${c.map((x) => `<tr><td>${esc(fmtDay(x.media_date))}</td><td class="small">${esc(x.category || x.media_type || '')}<div class="muted">${esc(x.caption || '')}</div></td>
      <td class="num">${esc(x.reach ?? '—')}</td><td class="num">${esc(x.saved ?? '—')}</td><td class="num">${esc(x.shares ?? '—')}</td>
      <td class="num">${x.interaction_rate != null ? esc((Number(x.interaction_rate) * (x.interaction_rate < 1 ? 100 : 1)).toFixed(1)) + '%' : '—'}</td></tr>`).join('') || '<tr><td colspan="6" class="muted">No data.</td></tr>'}</tbody></table></div>
    <h3>Paid media (30 days)</h3>
    <div class="tbl-wrap"><table><thead><tr><th>Campaign / ad</th><th class="num">Spend</th><th class="num">Impressions</th><th class="num">Clicks</th><th class="num">CTR</th><th>Recommendation</th></tr></thead>
    <tbody>${p.map((x) => `<tr><td class="small">${esc(x.campaign || '')}<div class="muted">${esc(x.ad_name || '')}</div></td><td class="num">${esc(Number(x.spend || 0).toFixed(2))}</td>
      <td class="num">${esc(x.impressions ?? '—')}</td><td class="num">${esc(x.clicks ?? '—')}</td><td class="num">${esc(x.ctr ?? '—')}%</td><td>${esc(x.recommendation || '—')}</td></tr>`).join('') || '<tr><td colspan="6" class="muted">No paid media in the last 30 days.</td></tr>'}</tbody></table></div>`;
}
function viewIntelligence(d) {
  const s = d.intelligence.signals; const c = d.intelligence.competitors;
  return `
    <h2>Intelligence</h2>
    <h3>Market signals</h3>
    <div class="list">${s.map((x) => `<div class="row"><div class="t">${esc(x.title)} ${x.revenue_potential ? pill(x.revenue_potential, x.revenue_potential.includes('HIGH') ? 'gold' : '') : ''}</div>
      <div class="meta">${esc(fmtDay(x.discovered_at))} · ${esc(x.intelligence_type || '')} ${x.destination ? `· ${esc(x.destination)}` : ''} · ${esc(x.status)}</div>
      <div class="small">${esc(x.summary || '')}</div>${x.potential_opportunity ? `<div class="small"><b>Opportunity:</b> ${esc(x.potential_opportunity)}</div>` : ''}</div>`).join('') || '<p class="muted">No signals.</p>'}</div>
    <h3>Competitors</h3>
    <div class="list">${c.map((x) => `<div class="row"><div class="t">${esc(x.competitor_name)} ${x.recommended_action ? pill(x.recommended_action) : ''}</div>
      <div class="meta">${esc(fmtDay(x.discovered_at))} · ${esc(x.competitor_category || '')}</div><div class="small">${esc(x.why_it_matters || '')}</div></div>`).join('') || '<p class="muted">No competitor signals.</p>'}</div>`;
}


function healthAlerts(d) {
  const h = d.health; const out = [];
  if (!h.gmail_sync_last_run || daysAgo(h.gmail_sync_last_run) * 1440 > 45) out.push('Gmail sync (workflow 13) has not run in the last 45 minutes');
  if (h.outbound_stuck > 0) out.push(`${h.outbound_stuck} approved draft(s) not created yet`);
  if (h.outbound_failed_7d > 0) out.push(`${h.outbound_failed_7d} draft creation failure(s) this week`);
  if (!h.last_daily_brief || daysAgo(h.last_daily_brief.generated_at) > 1.2) out.push('Daily CEO brief is late');
  else if (h.last_daily_brief.delivery_status !== 'DELIVERED') out.push(`Daily CEO brief status: ${h.last_daily_brief.delivery_status}`);
  (h.open_alerts || []).filter((a) => (a.priority ?? 0) >= 50).forEach((a) => out.push(a.title)); // low-priority notices are blockers, not failures
  return out;
}

const VIEWS = { overview: viewOverview, outreach: viewOutreach, pipeline: viewPipeline, inbox: viewInbox, tasks: viewTasks, website: viewWebsite, finance: viewFinance, intelligence: viewIntelligence, reports: viewReports, system: viewSystem };

// ---------------------------------------------------------------- opportunity record drawer
function renderDrawer(dr) {
  const d = state.data; const o = d.opportunities.find((x) => x.id === dr.id);
  if (!o) return `<div class="drawer-bg" data-close-drawer></div><aside class="drawer"><button class="btn small close" data-close-drawer>Close</button><p class="muted">Record not found in the loaded data.</p></aside>`;
  const ap = d.approvals.find((x) => x.id === o.id);
  const tasks = d.tasks.filter((t) => t.opportunity_id === o.id);
  const openT = tasks.filter((t) => openStatuses.includes(t.status));
  const replies = d.inbound.filter((r) => r.opportunity_id === o.id);
  const kv = (k, v) => `<div class="kv"><div class="k">${k}</div><div class="v">${v}</div></div>`;
  return `<div class="drawer-bg" data-close-drawer></div>
  <aside class="drawer">
    <button class="btn small close" data-close-drawer>Close</button>
    <h2>${esc(o.company_name)}</h2>
    <div class="pills">${pill(o.status)} ${o.approval_status && o.approval_status !== 'PENDING' ? pill(`approval ${o.approval_status}`) : ''} ${pill(`priority ${o.priority ?? '—'}`)}</div>
    <div class="grid2">
      ${kv('Opportunity', esc(o.opportunity_type || '—'))}
      ${kv('Primary contact', `${esc(o.contact_name || '—')}<div class="muted small">${esc(o.contact_position || '')}</div>`)}
      ${kv('Email', ap ? `${esc(ap.contact_email || '—')} ${ap.email_status === 'VERIFIED' ? pill('verified', 'ok') : pill(ap.email_status || 'none', 'warn')}` : `${pill(o.email_status || 'none')}`)}
      ${kv('Estimated value', o.estimated_value != null ? `${esc(money(o.estimated_value, o.currency))}${lbl('ESTIMATE')}` : `unknown${lbl('UNKNOWN')}`)}
      ${kv('Actual revenue', d.revenue.rows ? 'see Finance' : `none recorded${lbl('ACTUAL')}`)}
      ${kv('Next action', esc(o.next_action || '—'))}
      ${kv('Created', esc(fmtDay(o.created_at)))}
      ${kv('Last update', esc(fmtDate(o.updated_at)))}
    </div>
    ${ap ? `<h3>Outreach</h3>${loopBar(ap.loop_stage)}<div class="small">${esc(ap.loop_stage.replace('_', ' ').toLowerCase())}${ap.sent_at ? ` · sent ${esc(fmtDate(ap.sent_at))}` : ''}${ap.block_reason ? ` · email route blocked: ${esc(explain({ reason: ap.block_reason }))}` : ''}</div>
      ${ap.draft?.subject ? `<details><summary>Draft: ${esc(ap.draft.subject)}</summary><div class="email"><pre>${esc(ap.draft.body || '')}</pre></div></details>` : ''}
      ${ap.draft?.why_now ? `<div class="small mt6"><b>Why now:</b> ${esc(ap.draft.why_now)}</div>` : ''}` : ''}
    <h3>Replies (${replies.length})</h3>
    ${replies.map((r) => `<div class="mini"><div class="t">${pill(REPLY_GROUP[r.classification] || r.classification)} ${esc(fmtDate(r.received_at))}</div><div class="m">${esc(r.summary || '')}</div></div>`).join('') || '<p class="muted small">None.</p>'}
    <h3>Open tasks (${openT.length})</h3>
    ${openT.map((t) => `<div class="mini"><div class="t">${esc(t.title)}</div><div class="m">${esc(t.task_type)} · ${esc(t.status)} · due ${esc(fmtDay(t.due_at))}</div>
      <div class="btn-row mt6">${t.task_type !== 'SALES_OUTREACH_APPROVAL' ? `<button class="btn small" data-task="done" data-id="${t.id}">Done</button>` : '<button class="btn small" data-go="outreach">Approve in Outreach</button>'}<button class="btn small" data-task="snooze" data-id="${t.id}">Snooze</button></div>
      <details><summary>Task detail</summary><pre class="text small">${esc(t.description || '')}</pre></details></div>`).join('') || '<p class="muted small">None.</p>'}
    <h3>History (${tasks.length - openT.length} closed tasks)</h3>
    ${tasks.filter((t) => !openStatuses.includes(t.status)).map((t) => `<div class="m small">${esc(fmtDay(t.completed_at || t.created_at))} · ${esc(t.status)} · ${esc(t.title)}</div>`).join('') || '<p class="muted small">None.</p>'}
    <p class="src mt8">Record ${esc(o.id)} · source: opportunities, tasks, gmail_sync_ledger, outbound_emails</p>
  </aside>`;
}

// ---------------------------------------------------------------- modals & actions
function findApproval(id) { return state.data.approvals.find((a) => a.id === id); }
function findTask(id) { return state.data.tasks.find((t) => t.id === id); }
function isoPlus(days) { const x = new Date(); x.setDate(x.getDate() + days); return x.toLocaleDateString('en-CA', { timeZone: 'Africa/Cairo' }); }

function renderAnyModal(m) {
  if (m.kind === 'task-done' || m.kind === 'task-snooze') {
    const t = findTask(m.id) || {};
    return m.kind === 'task-done'
      ? `<div class="modal-bg"><div class="modal"><h3>Mark done</h3><p>${esc(t.title || '')}</p>
          <label class="field"><span>Note (optional)</span><input id="task-note" maxlength="300"></label>
          <div class="btn-row"><button class="btn primary" data-confirm-task="COMPLETE">Mark done</button><button class="btn" data-close>Cancel</button></div></div></div>`
      : `<div class="modal-bg"><div class="modal"><h3>Snooze</h3><p>${esc(t.title || '')}</p>
          <label class="field"><span>Until</span><input id="task-until" type="date" min="${isoPlus(1)}" max="${isoPlus(90)}" value="${isoPlus(2)}"></label>
          <label class="field"><span>Note (optional)</span><input id="task-note" maxlength="300"></label>
          <div class="btn-row"><button class="btn primary" data-confirm-task="SNOOZE">Snooze</button><button class="btn" data-close>Cancel</button></div></div></div>`;
  }
  return renderModal(m);
}

async function confirmTask(action) {
  const m = state.modal; const note = $('#task-note')?.value || null; const until = $('#task-until')?.value || null;
  const btn = document.querySelector('[data-confirm-task]'); if (btn) btn.disabled = true;
  state.modal = null;
  const r = await call('hq_task_action', { p_task_id: m.id, p_action: action, p_until: until, p_assignee: null, p_note: note },
    action === 'COMPLETE' ? 'Task marked done.' : `Task snoozed to ${until}.`);
  if (r && r.ok === false && r.reason === 'USE_APPROVAL_FLOW') state.notice = { err: true, text: 'Outreach approvals are closed by Approve, Hold or Reject in Outreach.' };
}

function renderModal(m) {
  const a = findApproval(m.id);
  if (!a) return '';
  const dr = a.draft || {};
  if (m.kind === 'approve') {
    return `<div class="modal-bg"><div class="modal"><h3>Approve &amp; Draft — ${esc(a.company_name)}</h3>
      <p>This creates <b>one Gmail draft</b> in noya@noyaconcierge.com addressed to <b>${esc(a.contact_email)}</b> (${esc(a.email_status)}).</p>
      <p><b>Nothing is sent.</b> You open Gmail, review, and press Send yourself. The CRM then updates automatically.</p>
      ${a.human_only ? '<p class="muted">Human-only opportunity: draft only, as required.</p>' : ''}
      <div class="email"><div class="subj">${esc(dr.subject)}</div><pre>${esc(dr.body)}</pre></div>
      <div class="btn-row"><button class="btn primary" data-confirm="approve">Create Gmail draft</button><button class="btn" data-close>Cancel</button></div></div></div>`;
  }
  if (m.kind === 'edit') {
    return `<div class="modal-bg"><div class="modal"><h3>Edit draft — ${esc(a.company_name)}</h3>
      <p class="muted small">Recipient is fixed to the verified contact (${esc(a.contact_email || 'none')}). The original version is kept for audit.</p>
      <label class="field"><span>Subject</span><input id="ed-subject" maxlength="200" value="${esc(dr.subject || '')}"></label>
      <label class="field"><span>Email</span><textarea id="ed-body" maxlength="8000">${esc(dr.body || '')}</textarea></label>
      <label class="field"><span>Note (optional)</span><input id="ed-note" maxlength="500"></label>
      <div class="btn-row"><button class="btn primary" data-confirm="edit">Save as approved version</button><button class="btn" data-close>Cancel</button></div></div></div>`;
  }
  if (m.kind === 'hold') {
    return `<div class="modal-bg"><div class="modal"><h3>Hold — ${esc(a.company_name)}</h3>
      <label class="field"><span>Review date (optional)</span><input id="hold-date" type="date"></label>
      <label class="field"><span>Reason (optional)</span><input id="hold-reason" maxlength="500"></label>
      <div class="btn-row"><button class="btn primary" data-confirm="hold">Hold</button><button class="btn" data-close>Cancel</button></div></div></div>`;
  }
  if (m.kind === 'reject') {
    return `<div class="modal-bg"><div class="modal"><h3>Reject — ${esc(a.company_name)}</h3>
      <p class="muted small">No draft is created. The opportunity and its history are kept.</p>
      <label class="field"><span>Reason (required)</span><input id="rej-reason" maxlength="500" required></label>
      <div class="btn-row"><button class="btn danger" data-confirm="reject">Reject</button><button class="btn" data-close>Cancel</button></div></div></div>`;
  }
  return '';
}


async function confirmModal(kind) {
  const m = state.modal; const a = findApproval(m.id); if (!a) return;
  const btn = document.querySelector('[data-confirm]'); if (btn) btn.disabled = true;
  if (kind === 'approve') {
    state.modal = null;
    const r = await call('hq_approve_draft', { p_opportunity_id: a.id, p_version: Number(a.draft?.version || 1) },
      `Approved. Creating the Gmail draft for ${a.company_name} — it will appear here within a minute.`);
    if (r && r.ok) state.pollUntil = Date.now() + 120000;
  } else if (kind === 'edit') {
    const subject = $('#ed-subject').value; const body = $('#ed-body').value; const note = $('#ed-note').value;
    state.modal = null;
    await call('hq_save_draft', { p_opportunity_id: a.id, p_subject: subject, p_body: body, p_note: note || null }, `Saved the edited draft for ${a.company_name}. Review it, then Approve & Draft.`);
  } else if (kind === 'hold') {
    const date = $('#hold-date').value || null; const reason = $('#hold-reason').value || null;
    state.modal = null;
    await call('hq_hold', { p_opportunity_id: a.id, p_review_date: date, p_reason: reason }, `${a.company_name} is on hold.`);
  } else if (kind === 'reject') {
    const reason = $('#rej-reason').value.trim();
    if (!reason) { state.notice = { err: true, text: 'A reason is required.' }; if (btn) btn.disabled = false; return; }
    state.modal = null;
    await call('hq_reject', { p_opportunity_id: a.id, p_reason: reason }, `${a.company_name} rejected. No draft was created.`);
  }
}


function bind() {
  // Proportions are applied through the CSSOM (allowed by the strict CSP; inline style attributes are not).
  document.querySelectorAll('[data-flex]').forEach((el) => { el.style.flex = el.dataset.flex; });
  document.querySelectorAll('[data-tab]').forEach((b) => b.addEventListener('click', () => { state.tab = b.dataset.tab; state.notice = null; state.q = ''; render(); window.scrollTo(0, 0); }));
  document.querySelectorAll('[data-go]').forEach((b) => b.addEventListener('click', (e) => {
    e.stopPropagation(); state.tab = b.dataset.go; state.drawer = null; state.q = ''; render();
    const anchor = b.dataset.anchor && document.getElementById(b.dataset.anchor);
    if (anchor) anchor.scrollIntoView({ block: 'start' }); else window.scrollTo(0, 0);
  }));
  document.querySelectorAll('[data-open-opp]').forEach((b) => b.addEventListener('click', (e) => { e.stopPropagation(); state.drawer = { id: b.dataset.openOpp }; state.q = ''; render(); }));
  document.querySelectorAll('[data-close-drawer]').forEach((b) => b.addEventListener('click', () => { state.drawer = null; render(); }));
  document.querySelectorAll('[data-task]').forEach((b) => b.addEventListener('click', (e) => { e.stopPropagation(); state.modal = { kind: `task-${b.dataset.task}`, id: b.dataset.id }; render(); }));
  document.querySelectorAll('[data-confirm-task]').forEach((b) => b.addEventListener('click', () => confirmTask(b.dataset.confirmTask)));
  $('#queue-all')?.addEventListener('click', () => { state.queueAll = !state.queueAll; render(); });
  $('#queue-p3')?.addEventListener('click', () => { state.queueP3 = !state.queueP3; render(); });
  $('#q')?.addEventListener('input', (e) => { state.q = e.target.value; state.focusSearch = true; render(); });
  $('#q')?.addEventListener('keydown', (e) => { if (e.key === 'Escape') { state.q = ''; render(); } });
  $('#pipe-q')?.addEventListener('change', (e) => { state.pipeQ = e.target.value; render(); });
  $('#refresh')?.addEventListener('click', () => load());
  $('#menu')?.addEventListener('click', async () => {
    const choice = window.prompt('Type "password" to change your password, or "logout" to sign out.');
    if (choice === 'password') { state.modal = 'password'; render(); }
    if (choice === 'logout') { await sb.auth.signOut(); }
  });
  document.querySelectorAll('[data-act]').forEach((b) => b.addEventListener('click', async () => {
    if (b.dataset.act === 'redispatch') { await call('hq_redispatch', { p_outbound_id: b.dataset.id }, 'Draft creation re-requested.'); state.pollUntil = Date.now() + 120000; return; }
    state.modal = { kind: b.dataset.act, id: b.dataset.id }; render();
  }));
  document.querySelectorAll('[data-confirm]').forEach((b) => b.addEventListener('click', () => confirmModal(b.dataset.confirm)));
  document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => { state.modal = null; render(); }));
  document.querySelectorAll('[data-when]').forEach((b) => b.addEventListener('click', () => { state.taskFilter.when = b.dataset.when; render(); }));
  document.querySelectorAll('[data-f]').forEach((s) => s.addEventListener('change', () => { state.taskFilter[s.dataset.f] = s.value; render(); }));
  document.querySelectorAll('[data-stage]').forEach((b) => b.addEventListener('click', () => { state.pipeStage = b.dataset.stage; render(); }));
}

// Refresh: every 60s normally, every 5s for two minutes after an approval. Paused while typing,
// or while a modal / record is open.
setInterval(() => {
  if (!state.session || state.modal || state.drawer || state.q || mustChangePassword()) return;
  const fast = Date.now() < state.pollUntil;
  const tick = Math.floor(Date.now() / 5000);
  if (fast || tick % 12 === 0) load(true);
}, 5000);

initAuth();
