// NOYA CEO Command Centre.
// Reads one RPC (hq_dashboard) and writes only through hq_save_draft / hq_approve_draft /
// hq_hold / hq_reject / hq_redispatch. There is deliberately no "send" action in this UI:
// APPROVE & DRAFT creates a Gmail draft; Adam presses Send in Gmail; workflow 13 logs it.
import { createClient } from '@supabase/supabase-js';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, GMAIL_DRAFTS_URL, GMAIL_THREAD_URL } from './config.js';

const sb = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
});

const TABS = [
  ['today', 'Today'], ['approvals', 'Approvals'], ['pipeline', 'Pipeline'], ['tasks', 'Tasks'],
  ['completed', 'Completed'], ['inbound', 'Inbound'], ['marketing', 'Marketing'],
  ['intelligence', 'Intelligence'], ['health', 'System Health'], ['brief', 'CEO Brief'],
];
const STAGES = ['NEW', 'RESEARCHING', 'READY', 'CONTACTED', 'INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST', 'FOLLOW_UP', 'LONG_TERM', 'ARCHIVED'];
const LOOP = [['PENDING_APPROVAL', 'Pending approval'], ['DRAFT_CREATED', 'Draft created'], ['SENT', 'Sent'], ['REPLIED', 'Replied'], ['NEXT', 'Follow-up / meeting / proposal']];
const REPLY_ORDER = { MEETING_REQUEST: 0, POSITIVE: 1, NEEDS_INFO: 2, REFERRAL: 3, UNKNOWN: 4, BOUNCE: 5, NOT_NOW: 6, DECLINED: 7, OUT_OF_OFFICE: 8, UNRELATED: 9 };

const state = {
  session: null, data: null, error: null, notice: null, tab: 'today', loading: false, modal: null,
  taskFilter: { when: 'all', dept: '', prio: '', owner: '', status: '' }, pipeStage: '', pollUntil: 0,
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

// ---------------------------------------------------------------- data
async function load(silent = false) {
  if (!silent) { state.loading = true; render(); }
  const { data, error } = await sb.rpc('hq_dashboard');
  state.loading = false;
  if (error) {
    state.error = /not authorised/i.test(error.message)
      ? 'This account is not authorised for NOYA HQ.'
      : `Could not load live data: ${error.message}`;
  } else {
    state.data = data;
    state.error = null;
  }
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
      <p>CEO Command Centre</p>
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

// ---------------------------------------------------------------- render
function render() {
  if (!state.session) return renderLogin();
  if (mustChangePassword()) return renderPasswordChange(true);
  if (state.modal === 'password') return renderPasswordChange(false);
  const d = state.data;
  const approvalsReady = d ? d.approvals.filter((a) => a.loop_stage === 'PENDING_APPROVAL' && !a.block_reason).length : 0;
  const repliesOpen = d ? repliesForAdam(d).length : 0;
  $('#app').innerHTML = `
    <header class="top">
      <div class="top-row">
        <div class="brand">NOYA<small>CEO Command Centre</small></div>
        <div class="top-meta">
          <span class="small">${d ? `Live · ${esc(fmtDate(d.generated_at))} Cairo` : state.loading ? 'Loading…' : ''}</span>
          <button class="btn small" id="refresh">Refresh</button>
          <button class="btn small" id="menu" title="Account">⋯</button>
        </div>
      </div>
      <nav class="tabs">${TABS.map(([k, l]) => `<button data-tab="${k}" class="${state.tab === k ? 'active' : ''}">${l}${k === 'approvals' && approvalsReady ? `<span class="badge">${approvalsReady}</span>` : ''}${k === 'inbound' && repliesOpen ? `<span class="badge">${repliesOpen}</span>` : ''}</button>`).join('')}</nav>
    </header>
    <main>
      ${state.notice ? `<div class="banner ${state.notice.err ? 'err' : 'ok'}">${esc(state.notice.text)}</div>` : ''}
      ${state.error ? `<div class="banner err">${esc(state.error)}</div>` : ''}
      ${d ? VIEWS[state.tab](d) : `<p class="muted">${state.loading ? 'Loading live CRM…' : 'No data.'}</p>`}
    </main>
    ${state.modal && typeof state.modal === 'object' ? renderModal(state.modal) : ''}`;
  bind();
}

// ---------------------------------------------------------------- TODAY
function repliesForAdam(d) {
  return d.inbound.filter((r) => r.task_id && ['OPEN', 'IN_PROGRESS', 'WAITING'].includes(r.task_status)
    && !['OUT_OF_OFFICE', 'UNRELATED'].includes(r.classification))
    .sort((a, b) => (REPLY_ORDER[a.classification] ?? 9) - (REPLY_ORDER[b.classification] ?? 9));
}
const openTasks = (d) => d.tasks.filter((t) => ['OPEN', 'IN_PROGRESS', 'WAITING'].includes(t.status));

function viewToday(d) {
  const ready = d.approvals.filter((a) => a.loop_stage === 'PENDING_APPROVAL' && !a.block_reason);
  const drafted = d.approvals.filter((a) => a.loop_stage === 'DRAFT_CREATED');
  const replies = repliesForAdam(d);
  const endOfToday = new Date(); endOfToday.setHours(23, 59, 59, 999);
  const followUps = openTasks(d).filter((t) => t.task_type === 'OUTREACH_FOLLOW_UP' && t.due_at && new Date(t.due_at) <= endOfToday);
  const meetings = d.opportunities.filter((o) => o.status === 'CALL_REQUIRED');
  const proposals = d.opportunities.filter((o) => ['PROPOSAL', 'NEGOTIATION'].includes(o.status));
  const enquiries = d.enquiries.filter((e) => daysAgo(e.created_at) <= 7);
  const revenueDone = d.completions.filter((c) => c.revenue_impacting && isThisWeek(c.at));
  const alerts = healthAlerts(d);

  const actions = [];
  replies.slice(0, 3).forEach((r) => actions.push({ t: `${r.classification.replace('_', ' ')} — ${r.company_name || r.from}`, m: r.task_title || r.summary, go: 'inbound' }));
  drafted.forEach((a) => actions.push({ t: `Send approved draft — ${a.company_name}`, m: 'Draft is waiting in noya@ Gmail Drafts. Review and press Send.', go: 'approvals' }));
  ready.slice(0, 3).forEach((a) => actions.push({ t: `Approve outreach — ${a.company_name}`, m: `${a.contact_name || ''} · ${a.contact_position || ''}`, go: 'approvals' }));
  followUps.slice(0, 2).forEach((t) => actions.push({ t: t.title, m: `Due ${fmtDay(t.due_at)}`, go: 'tasks' }));
  alerts.slice(0, 1).forEach((a) => actions.push({ t: `System: ${a}`, m: 'See System Health', go: 'health' }));

  const tile = (n, l, go, alert = false) => `<div class="tile link ${alert && n ? 'alert' : ''}" data-go="${go}"><div class="n">${n}</div><div class="l">${l}</div></div>`;
  return `
    <h2>Today</h2>
    <div class="tiles">
      ${tile(ready.length, 'Approvals waiting', 'approvals')}
      ${tile(replies.length, 'Replies for Adam', 'inbound')}
      ${tile(followUps.length, 'Follow-ups due', 'tasks')}
      ${tile(meetings.length, 'Meetings to arrange', 'pipeline')}
      ${tile(proposals.length, 'Proposals open', 'pipeline')}
      ${tile(enquiries.length, 'Website enquiries (7d)', 'inbound')}
      ${tile(revenueDone.length, 'Revenue-impacting wins (7d)', 'completed')}
      ${tile(alerts.length, 'System alerts', 'health', true)}
    </div>
    <h3>Top CEO actions</h3>
    <div class="list">${actions.slice(0, 5).map((a, i) => `<div class="row clickable" data-go="${a.go}"><div class="t">${i + 1}. ${esc(a.t)}</div><div class="meta">${esc(a.m)}</div></div>`).join('') || '<p class="muted">Nothing needs you right now.</p>'}</div>
    <h3>Email loop</h3>
    ${loopSummary(d)}`;
}

function loopSummary(d) {
  const count = (s) => d.approvals.filter((a) => a.loop_stage === s && (s !== 'PENDING_APPROVAL' || !a.block_reason)).length;
  const blocked = d.approvals.filter((a) => a.loop_stage === 'PENDING_APPROVAL' && a.block_reason).length;
  return `<div class="tiles">
    <div class="tile link" data-go="approvals"><div class="n">${blocked}</div><div class="l">Blocked — contact needed</div></div>
    ${[['PENDING_APPROVAL', 'Ready to approve'], ['APPROVED', 'Draft being created'], ['DRAFT_CREATED', 'Draft in Gmail'], ['SENT', 'Sent'], ['REPLIED', 'Replied'], ['ON_HOLD', 'On hold'], ['REJECTED', 'Rejected']]
      .map(([s, l]) => `<div class="tile link" data-go="approvals"><div class="n">${count(s)}</div><div class="l">${l}</div></div>`).join('')}
  </div>`;
}

// ---------------------------------------------------------------- APPROVALS
function viewApprovals(d) {
  const a = d.approvals;
  const ready = a.filter((x) => x.loop_stage === 'PENDING_APPROVAL' && !x.block_reason);
  const blocked = a.filter((x) => x.loop_stage === 'PENDING_APPROVAL' && x.block_reason);
  const inFlight = a.filter((x) => ['APPROVED', 'DRAFT_CREATED', 'SENT', 'REPLIED', 'FAILED', 'DRAFT_DISCARDED'].includes(x.loop_stage));
  const held = a.filter((x) => x.loop_stage === 'ON_HOLD');
  const rejected = a.filter((x) => x.loop_stage === 'REJECTED');
  return `
    <h2>Approvals</h2>
    <p class="muted small">Approving creates a Gmail draft in noya@noyaconcierge.com. Nothing is sent from here — you press Send in Gmail, and the CRM updates itself.</p>
    <h3>Ready to approve (${ready.length})</h3>
    ${ready.map(approvalCard).join('') || '<p class="muted">No approval-ready outreach.</p>'}
    ${inFlight.length ? `<h3>In progress (${inFlight.length})</h3>${inFlight.map(approvalCard).join('')}` : ''}
    ${held.length ? `<h3>On hold (${held.length})</h3>${held.map(approvalCard).join('')}` : ''}
    <h3>Blocked — contact not usable (${blocked.length})</h3>
    <details><summary>Show ${blocked.length} opportunities that need a verified contact first</summary>${blocked.map(approvalCard).join('')}</details>
    ${rejected.length ? `<h3>Rejected (${rejected.length})</h3><details><summary>Show</summary>${rejected.map(approvalCard).join('')}</details>` : ''}`;
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
  const est = {};
  d.opportunities.filter((o) => !['LOST', 'ARCHIVED', 'WON'].includes(o.status)).forEach((o) => {
    if (o.estimated_value) est[o.currency || '?'] = (est[o.currency || '?'] || 0) + Number(o.estimated_value);
  });
  const actual = d.revenue.actual.length ? d.revenue.actual.map((r) => money(r.amount, r.currency)).join(' · ') : '0';
  const rows = d.opportunities.filter((o) => !state.pipeStage || o.status === state.pipeStage);
  return `
    <h2>Pipeline</h2>
    <div class="tiles">
      <div class="tile"><div class="n">${esc(Object.entries(est).map(([c, v]) => money(v, c)).join(' · ') || '0')}</div><div class="l">ESTIMATED pipeline (open opportunities)</div></div>
      <div class="tile"><div class="n">${esc(actual)}</div><div class="l">ACTUAL revenue received (${d.revenue.rows} revenue records)</div></div>
      <div class="tile"><div class="n">${d.opportunities.length}</div><div class="l">Opportunities</div></div>
    </div>
    <p class="muted small">Estimated values are research estimates, never revenue. Actual revenue counts only paid records in the revenue table.</p>
    <h3>Stages</h3>
    <div class="filters"><div class="seg">
      <button data-stage="" class="${!state.pipeStage ? 'on' : ''}">All</button>
      ${STAGES.filter((s) => by[s]).map((s) => `<button data-stage="${s}" class="${state.pipeStage === s ? 'on' : ''}">${s.replace('_', ' ')} · ${by[s].length}</button>`).join('')}
    </div></div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>Company</th><th>Stage</th><th>Contact</th><th class="num">Estimated</th><th class="num">Priority</th><th>Next action</th></tr></thead>
      <tbody>${rows.map((o) => `<tr><td>${esc(o.company_name)}<div class="muted small">${esc(String(o.opportunity_type || '').slice(0, 60))}</div></td>
        <td>${pill(o.status)} ${o.approval_status !== 'PENDING' ? pill(o.approval_status, o.approval_status === 'REJECTED' ? 'bad' : 'ok') : ''}</td>
        <td>${esc(o.contact_name || '—')}<div class="muted small">${esc(o.email_status || 'no contact')}</div></td>
        <td class="num">${esc(money(o.estimated_value, o.currency))}</td><td class="num">${esc(o.priority ?? '—')}</td>
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
        return `<div class="row"><div class="t small">${esc(t.title)}</div><div class="meta">${pill(prioBand(t.priority ?? 0), t.priority >= 80 ? 'gold' : '')} ${esc(department(t.created_by))} · ${esc(t.assigned_to || '—')}</div>
          <div class="meta">${t.status === 'COMPLETED' ? `Done ${esc(t.completed_at ? fmtDate(t.completed_at) : '(time not recorded)')}` : `Due ${esc(fmtDay(t.due_at))}${overdue ? ' · <span class="bad-text">overdue</span>' : ''}`}</div></div>`;
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

// ---------------------------------------------------------------- INBOUND
function suggestedReply(desc) {
  const i = String(desc || '').indexOf('--- SUGGESTED REPLY');
  return i >= 0 ? String(desc).slice(i).split('\n').slice(1).join('\n').trim() : '';
}
function viewInbound(d) {
  const replies = [...d.inbound].sort((a, b) => (REPLY_ORDER[a.classification] ?? 9) - (REPLY_ORDER[b.classification] ?? 9) || new Date(b.received_at) - new Date(a.received_at));
  const cls = (c) => ({ MEETING_REQUEST: 'gold', POSITIVE: 'ok', NEEDS_INFO: 'info', UNKNOWN: 'warn', BOUNCE: 'bad', DECLINED: 'bad' }[c] || '');
  return `
    <h2>Inbound</h2>
    <p class="muted small">Replies to NOYA outreach, logged by workflow 13. Nothing is ever replied to automatically — suggested replies are drafts for you.</p>
    <h3>Replies (${replies.length})</h3>
    <div class="list">${replies.map((r) => {
      const sug = suggestedReply(r.task_description);
      return `<div class="row"><div class="t">${pill(r.classification || r.outcome, cls(r.classification))} ${esc(r.company_name || 'Unmatched — needs review')}</div>
        <div class="meta">${esc(fmtDate(r.received_at))} · from ${esc(r.from || '')} · ${esc(r.subject || '')}</div>
        <div class="small mt6">${esc(r.summary || '')}</div>
        <div class="small mt6"><b>Next:</b> ${esc(r.task_title || r.next_action || 'No action needed')}${r.task_status ? ` (${esc(r.task_status)})` : ''}</div>
        ${sug ? `<details><summary>Suggested reply (not sent)</summary><pre class="text">${esc(sug)}</pre></details>` : ''}
        ${r.thread_id ? `<div class="small"><a href="${GMAIL_THREAD_URL}${esc(r.thread_id)}" target="_blank" rel="noopener noreferrer">Open in Gmail</a></div>` : ''}</div>`;
    }).join('') || '<p class="muted">No replies yet since go-live.</p>'}</div>
    <h3>Website enquiries (60 days, ${d.enquiries.length})</h3>
    <div class="list">${d.enquiries.map((e) => `<div class="row"><div class="t">${esc(e.name || e.company || 'Enquiry')} ${pill(e.status)} ${pill(e.lead_type)}</div>
      <div class="meta">${esc(fmtDate(e.created_at))} · ${esc(e.reference || '')} ${e.destination ? `· ${esc(e.destination)}` : ''} ${e.budget ? `· budget ${esc(e.budget)}` : ''}</div>
      ${e.message ? `<div class="small">${esc(e.message)}</div>` : ''}</div>`).join('') || '<p class="muted">No website enquiries in the last 60 days.</p>'}</div>`;
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

// ---------------------------------------------------------------- HEALTH / BRIEF
function healthAlerts(d) {
  const h = d.health; const out = [];
  if (!h.gmail_sync_last_run || daysAgo(h.gmail_sync_last_run) * 1440 > 45) out.push('Gmail sync (workflow 13) has not run in the last 45 minutes');
  if (h.outbound_stuck > 0) out.push(`${h.outbound_stuck} approved draft(s) not created yet`);
  if (h.outbound_failed_7d > 0) out.push(`${h.outbound_failed_7d} draft creation failure(s) this week`);
  if (!h.last_daily_brief || daysAgo(h.last_daily_brief.generated_at) > 1.2) out.push('Daily CEO brief is late');
  else if (h.last_daily_brief.delivery_status !== 'DELIVERED') out.push(`Daily CEO brief status: ${h.last_daily_brief.delivery_status}`);
  (h.open_alerts || []).forEach((a) => out.push(a.title));
  return out;
}
function viewHealth(d) {
  const h = d.health; const alerts = healthAlerts(d);
  const line = (k, v, ok) => `<div class="row"><div class="t">${esc(k)} ${ok === true ? pill('OK', 'ok') : ok === false ? pill('Check', 'bad') : ''}</div><div class="meta">${v}</div></div>`;
  return `
    <h2>System Health</h2>
    ${alerts.length ? `<div class="banner err">${alerts.map(esc).join('<br>')}</div>` : '<div class="banner ok">No issues requiring Adam.</div>'}
    <div class="list">
      ${line('Gmail interaction sync (workflow 13)', `Last run ${esc(fmtDate(h.gmail_sync_last_run))} · go-live ${esc(fmtDate(h.gmail_sync_go_live))}${h.gmail_sync_summary ? ` · ${esc(Object.entries(h.gmail_sync_summary).map(([k, v]) => `${k.replace(/_/g, ' ')} ${v}`).join(', '))}` : ''}`, !!h.gmail_sync_last_run && daysAgo(h.gmail_sync_last_run) * 1440 <= 45)}
      ${line('Outbound executor (workflow 12)', `${h.outbound_stuck} waiting · ${h.outbound_failed_7d} failed in 7 days`, h.outbound_stuck === 0 && h.outbound_failed_7d === 0)}
      ${line('Daily CEO brief (workflow 11)', h.last_daily_brief ? `${esc(fmtDate(h.last_daily_brief.generated_at))} · ${esc(h.last_daily_brief.delivery_status)}` : 'none', !!h.last_daily_brief && h.last_daily_brief.delivery_status === 'DELIVERED')}
      ${line('Weekly CEO review (workflow 11)', h.last_weekly_brief ? `${esc(fmtDate(h.last_weekly_brief.generated_at))} · ${esc(h.last_weekly_brief.delivery_status)}` : 'none', null)}
      ${line('Signed in as', esc(d.admin), true)}
    </div>
    <p class="muted small">Workflow execution history lives in n8n; this page shows the business-level signals those workflows write to the CRM. Failures also email Adam through workflow 00.</p>`;
}
function viewBrief(d) {
  const b = d.brief;
  const block = (t, x) => `<h3>${t}${x ? ` · ${esc(fmtDate(x.generated_at))} · ${esc(x.delivery_status)}` : ''}</h3>${x ? `<div class="row"><pre class="text">${esc(x.text || '')}</pre></div>` : '<p class="muted">None yet.</p>'}`;
  return `<h2>CEO Brief</h2>${block('Latest daily brief', b.daily)}${block('Latest weekly review', b.weekly)}`;
}

const VIEWS = { today: viewToday, approvals: viewApprovals, pipeline: viewPipeline, tasks: viewTasks, completed: viewCompleted, inbound: viewInbound, marketing: viewMarketing, intelligence: viewIntelligence, health: viewHealth, brief: viewBrief };

// ---------------------------------------------------------------- modals & actions
function findApproval(id) { return state.data.approvals.find((a) => a.id === id); }

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
  document.querySelectorAll('[data-tab]').forEach((b) => b.addEventListener('click', () => { state.tab = b.dataset.tab; state.notice = null; render(); window.scrollTo(0, 0); }));
  document.querySelectorAll('[data-go]').forEach((b) => b.addEventListener('click', () => { state.tab = b.dataset.go; render(); window.scrollTo(0, 0); }));
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

// Refresh: every 60s normally, every 5s for two minutes after an approval.
setInterval(() => {
  if (!state.session || state.modal || mustChangePassword()) return;
  const fast = Date.now() < state.pollUntil;
  const tick = Math.floor(Date.now() / 5000);
  if (fast || tick % 12 === 0) load(true);
}, 5000);

initAuth();
