// NOYA HQ — the CEO operating system for NOYA Concierge.
// Reads four admin-gated RPCs in parallel: hq_overview (Today), hq_dashboard (approvals, tasks,
// replies, briefs), hq_directory (companies, contacts, LinkedIn network, drafts, channel readiness)
// and hq_insight (markets, growth, finance, costs). Every write is an audited hq_* function.
// There is deliberately no automatic "send": email approval creates a Gmail draft Adam sends;
// LinkedIn / Instagram messages are copied and sent by Adam, then logged here.
import { createClient } from '@supabase/supabase-js';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, GMAIL_DRAFTS_URL, GMAIL_THREAD_URL } from './config.js';

const sb = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
});

// The permanent structure: eight sections, frozen. New capability goes inside one of them, never a ninth.
const NAV = [
  ['01 · Command', [['overview', 'Today'], ['reports', 'Reports']]],
  ['02 · Intelligence & Opportunities', [['radar', 'Opportunity radar'], ['intelligence', 'Market intel'], ['markets', 'Markets'], ['growth', 'Growth'], ['library', 'Products & playbooks']]],
  ['03 · Sales & Outreach', [['actions', 'Action queue'], ['inbox', 'Replies'], ['outreach', 'Outreach'], ['pipeline', 'Pipeline'], ['linkedin', 'LinkedIn'], ['website', 'Website leads']]],
  ['04 · Partnerships', [['partners', 'Partnerships']]],
  ['05 · Events & Experiences', [['events', 'Events']]],
  ['06 · Clients & Relationships', [['relationships', 'Past relationships'], ['companies', 'Companies'], ['contacts', 'Contacts']]],
  ['07 · Operations', [['projects', 'Projects'], ['tasks', 'Tasks']]],
  ['08 · Performance & System', [['finance', 'Finance'], ['costs', 'System costs'], ['system', 'System & team'], ['help', 'Help & playbook']]],
];
const STAGES = ['NEW', 'RESEARCHING', 'READY', 'CONTACTED', 'FOLLOW_UP', 'INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST', 'LONG_TERM', 'ARCHIVED'];
const STAGE_LABEL = { NEW: 'New', RESEARCHING: 'Researching', READY: 'Ready', CONTACTED: 'Contacted', FOLLOW_UP: 'Follow-up', INTERESTED: 'Interested', CALL_REQUIRED: 'Call required', PROPOSAL: 'Proposal', NEGOTIATION: 'Negotiation', WON: 'Won', LOST: 'Lost', LONG_TERM: 'Long term', ARCHIVED: 'Archived' };
const VERTICAL_LABEL = { PRIVATE_UHNW: 'Private / UHNW', CORPORATE: 'Corporate', BRAND_PRODUCTION: 'Brand / Production', HOSPITALITY: 'Hospitality', TRAVEL_CONCIERGE: 'Travel / Concierge partners', WEDDINGS_EVENTS: 'Weddings / Events', SPORTS_TALENT: 'Sports / Talent', OTHER: 'Other' };
const MARKET_LABEL = { EGYPT: 'Egypt', EUROPE: 'Europe', GCC: 'GCC', NORTH_AMERICA: 'North America', REST_OF_WORLD: 'Rest of world', GLOBAL: 'Global', UNKNOWN: 'Unknown' };
const LOOP = [['PENDING_APPROVAL', 'Pending approval'], ['DRAFT_CREATED', 'Draft created'], ['SENT', 'Sent'], ['REPLIED', 'Replied'], ['NEXT', 'Follow-up / meeting / proposal']];
const REPLY_ORDER = { MEETING_REQUEST: 0, POSITIVE: 1, NEEDS_INFO: 2, REFERRAL: 3, UNKNOWN: 4, BOUNCE: 5, NOT_NOW: 6, DECLINED: 7, OUT_OF_OFFICE: 8, UNRELATED: 9 };
const REPLY_GROUP = { MEETING_REQUEST: 'Meeting request', POSITIVE: 'Positive', NEEDS_INFO: 'Needs information', REFERRAL: 'Referral', DECLINED: 'Not interested', NOT_NOW: 'Not now', OUT_OF_OFFICE: 'Out of office', BOUNCE: 'Bounce', UNKNOWN: 'Other / human review', UNRELATED: 'Other / human review' };
const KIND_LABEL = { MEETING: 'Meeting requested', REPLY: 'Reply', WEBSITE: 'Website enquiry', SYSTEM: 'System', PROPOSAL: 'Proposal', PAYMENT: 'Payment', SEND_DRAFT: 'Send draft', APPROVE: 'Approve', FOLLOW_UP: 'Follow up', LINKEDIN: 'LinkedIn', INSTAGRAM: 'Instagram', MANUAL_ACTION: 'Your action', OVERDUE: 'Overdue' };
const MESSAGE_TYPES = [['FIRST_MESSAGE', 'First message'], ['RECONNECTION', 'Reconnection'], ['FOLLOW_UP', 'Follow-up'], ['INTRODUCTION_REQUEST', 'Introduction request'], ['PARTNERSHIP', 'Partnership'], ['EGYPT_OPPORTUNITY', 'Egypt opportunity'], ['CORPORATE', 'Corporate'], ['HOSPITALITY', 'Hospitality'], ['BRAND_PRODUCTION', 'Brand / production'], ['PRIVATE_CLIENT_INTRO', 'Private client introduction']];
const CONNECTION_STATUS = ['NEW', 'TO_CONTACT', 'CONTACTED', 'REPLIED', 'MEETING', 'INTRODUCED', 'OPPORTUNITY', 'NO_RESPONSE', 'LONG_TERM', 'DO_NOT_CONTACT'];

// Plain-language tooltips for the figures most easily misread.
const HELP = {
  pipeline: 'Potential opportunities being pursued, valued by research estimate. This is not revenue.',
  collected: 'Payments actually recorded as received (sum of recorded payments).',
  outstanding: 'Issued invoices not yet fully paid — money legitimately due.',
  won: 'Confirmed commercial revenue: issued (not draft, not cancelled) finance records.',
  forecast: 'A model or CEO estimate of future revenue. Not set until you set one; never shown as revenue.',
  call_required: 'The prospect asked for, or agreed to, a call. Book it and record it after.',
  approvals: 'Email outreach drafted for you, to a verified address, waiting for your approval. Approving creates a Gmail draft — nothing is sent until you press Send in Gmail.',
  unknown: 'No reliable figure exists yet. UNKNOWN is never counted as zero.',
  reconnect: 'A previous relationship worth restarting rather than cold outreach.',
  ready_outreach: 'Qualified outreach prepared for you to review. Nothing is sent until you act.',
  verified: 'VERIFIED means an email provider confirmed the address is deliverable, or it is published on the company\'s official site. Hover a contact for the evidence.',
};
const REL_STATE = {
  REPLIED: ['They wrote last', 'bad', 'They answered NOYA and the last message is theirs — you may owe a reply.'],
  RECONNECT: ['Reconnect', 'info', 'A real two-way conversation that has gone quiet for 60+ days. Restart it personally — never with a cold introduction.'],
  FOLLOW_UP: ['Follow up', 'warn', 'You emailed 7–60 days ago and have had no reply yet.'],
  LONG_TERM: ['Long term', '', 'Emailed over 60 days ago and never answered. Only reconnect with a real reason.'],
  WAIT: ['Wait', '', 'Emailed in the last 7 days — give it time.'],
  MEETING: ['Meeting stage', 'ok', 'An opportunity with them is at call / proposal stage.'],
  DO_NOT_CONTACT: ['Do not contact', 'bad', 'Marked do-not-contact.'],
  INBOUND_ONLY: ['They wrote to NOYA', 'info', 'They emailed NOYA; there is no reply from NOYA in this mailbox.'],
};
// Adam's relationship status (seven choices). Picking one creates internal tasks only — never a message.
const REL_STATUS = {
  REPLY_NOW: ['Reply now', 'bad', 'Creates a reply task due today.'],
  RECONNECT: ['Reconnect', 'info', 'Creates a reconnect task in 2 days.'],
  FOLLOW_UP_LATER: ['Later', 'warn', 'Creates a follow-up task in 14 days.'],
  LONG_TERM: ['Long term', '', 'No task. Stays in the history.'],
  EXISTING_PARTNER: ['Partner', 'ok', 'Marks them as a partner / supplier.'],
  CLIENT: ['Client', 'ok', 'Marks them as a client (handle personally).'],
  NOT_RELEVANT: ['Not relevant', '', 'Hides it. The email history is kept.'],
};
const REL_ORDER = ['REPLY_NOW', 'RECONNECT', 'EXISTING_PARTNER', 'CLIENT', 'FOLLOW_UP_LATER', 'LONG_TERM', 'NOT_RELEVANT'];
const relSuggested = (g) => g.review?.suggested || g.rule_status || null;
const relRank = (g) => { const i = REL_ORDER.indexOf(relSuggested(g)); return i < 0 ? 99 : i; };
const unesc = (t) => String(t ?? '').replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, '&');
const ANGLE = {
  BRAND_PRODUCTION: 'Local execution for shoots, creator trips and launches in Egypt: locations, permits, logistics, hospitality.',
  HOSPITALITY: 'Two-way partnership: NOYA sends clients; the property hosts brand and creator trips.',
  TRAVEL_CONCIERGE: 'Be their trusted Egypt execution partner, with clear referral terms.',
  PRIVATE_UHNW: 'Discreet private travel and lifestyle management; start with one trip.',
  CORPORATE: 'Executive travel, incentives and events in Egypt and beyond; propose one pilot.',
  WEDDINGS_EVENTS: 'Destination weddings and celebrations in Egypt: venues, permits, guest logistics.',
  SPORTS_TALENT: 'Private travel, security and experiences for talent and teams.',
};
const tip = (k) => (HELP[k] ? ` title="${esc(HELP[k])}"` : '');

const state = {
  session: null, data: null, ov: null, dir: null, ins: null, errors: {}, notice: null, tab: 'overview', loading: false,
  modal: null, drawer: null, timeline: {}, q: '', queueAll: false, queueP3: false, menu: false,
  com: null, account: {}, radarF: { h: 'ALL', region: '', cat: '', q: '' }, actF: { view: 'TODAY', seg: '', owner: '', track: '' }, parF: { tab: 'DEVELOP', cls: '' }, evF: { tab: 'UPCOMING' },
  rel: null, relF: { tab: 'REVIEW', q: '', i: 0 }, oneByOne: (() => { try { return !!localStorage.getItem('hq.oneByOne'); } catch { return false; } })(), oIdx: 0, outreachTab: 'READY', pipeView: 'table', pipeF: { stage: '', vertical: '', market: '', q: '', stale: false },
  contactF: { q: '', email: '' }, companyF: { q: '', vertical: '', market: '' }, netF: { q: '', only: 'known' },
  taskFilter: { when: 'all', dept: '', prio: '', owner: '', status: '' }, pollUntil: 0,
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
const V = (v) => VERTICAL_LABEL[v] || v || '—';
const M = (m) => MARKET_LABEL[m] || m || '—';
const S = (s) => STAGE_LABEL[s] || s || '—';
const sentence = (t) => { const s = String(t || ''); return s === s.toUpperCase() ? s.charAt(0) + s.slice(1).toLowerCase() : s; };
const cur = (list) => (list || []).filter((x) => x && x.currency);
function sourceLabel(src) {
  const s = String(src || '');
  if (/Gmail history/.test(s)) return 'Previous conversation';
  if (/Workflow 13 \(Gmail reply\)/.test(s)) return 'New reply';
  if (/Workflow 13 \(follow-up\)/.test(s)) return 'Follow-up due';
  if (/Workflow 05 \(draft\)/.test(s)) return 'Outreach ready for approval';
  if (/Workflow 05 \(channel/.test(s)) return 'Message ready to send';
  if (/Workflow 12/.test(s)) return 'Draft waiting in Gmail';
  if (/10d/.test(s)) return 'Website enquiry';
  if (/Adam review|Adam's instruction|HQ \(Adam\)/.test(s)) return 'Your action';
  if (/^0\d|^1\d/.test(s)) return 'NOYA system';
  return s || 'Task';
}
function emailPill(status, kind) {
  const s = String(status || 'UNKNOWN').toUpperCase();
  const cls = s === 'VERIFIED' ? 'ok' : s === 'RISKY' || s === 'UNVERIFIED' ? 'warn' : s === 'INVALID' ? 'bad' : '';
  const label = s === 'NOT_FOUND' ? 'no email' : s.toLowerCase();
  return `${pill(`email ${label}`, cls)}${kind === 'OFFICIAL_COMPANY_INBOX' ? ' ' + pill('company inbox') : ''}`;
}
const facts = (oppId) => state.dir?.opportunity_facts?.[oppId] || {};
const ready = (oppId) => state.dir?.readiness?.[oppId] || {};
const company = (id) => state.dir?.companies?.find((c) => c.id === id);
const isClient = (companyId) => company(companyId)?.relationship_status === 'client';
const gmailLink = (thread, label = 'Open in Gmail') => (thread ? `<a href="${GMAIL_THREAD_URL}${esc(thread)}" target="_blank" rel="noopener noreferrer">${label}</a>` : '');
// Earlier email contact with this company / person, from the NOYA Gmail history (evidence: the thread).
function prevRel(companyId, contactId) {
  const r = state.rel; if (!r) return '';
  const h = (contactId && r.by_contact[contactId]) || (companyId && r.by_company[companyId]);
  if (!h) return '';
  return `<div class="prev small" title="${esc(HELP.reconnect)}"><b>Emailed before</b> · ${h.sent} sent · ${h.received} ${h.received === 1 ? 'reply' : 'replies'} · last ${esc(shortDay(h.last_at))} · ${gmailLink(h.thread, 'Open thread')}</div>`;
}
const opp = (id) => state.data?.opportunities?.find((o) => o.id === id);

// ---------------------------------------------------------------- data
async function load(silent = false) {
  if (!silent) { state.loading = true; render(); }
  const [dash, ov, dir, ins, rel, com] = await Promise.all([sb.rpc('hq_dashboard'), sb.rpc('hq_overview'), sb.rpc('hq_directory'), sb.rpc('hq_insight'), sb.rpc('hq_relationships'), sb.rpc('hq_commercial')]);
  state.loading = false;
  state.errors = {};
  if (dash.error) {
    state.errors.main = /not authorised/i.test(dash.error.message) ? 'This account is not authorised for NOYA HQ.' : `Could not load live data: ${dash.error.message}`;
  } else state.data = dash.data;
  if (ov.error) state.errors.ov = ov.error.message; else state.ov = ov.data;
  if (dir.error) state.errors.dir = dir.error.message; else state.dir = dir.data;
  if (ins.error) state.errors.ins = ins.error.message; else state.ins = ins.data;
  if (rel.error) state.errors.rel = rel.error.message; else state.rel = rel.data;
  if (com.error) state.errors.com = com.error.message; else state.com = com.data;
  render();
}

async function loadTimeline(kind, id) {
  const key = `${kind}:${id}`;
  const { data, error } = await sb.rpc('hq_timeline', { p_kind: kind, p_id: id });
  state.timeline[key] = error ? { error: error.message } : data;
  render();
}

async function call(fn, args, successText) {
  state.notice = null;
  const { data, error } = await sb.rpc(fn, args);
  if (error) { state.notice = { err: true, text: error.message }; render(); return null; }
  if (data && data.ok === false) state.notice = { err: true, text: explain(data) };
  else state.notice = { err: false, text: successText };
  state.timeline = {}; state.account = {};
  await load(true);
  if (state.drawer) loadTimeline(state.drawer.kind, state.drawer.id);
  if (state.drawer?.kind === 'company') loadAccount(state.drawer.id);
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
    INSTAGRAM_NOT_APPROPRIATE: 'Instagram is not used for banks, wealth, law or consulting firms. Choose LinkedIn or phone.',
    ISSUED_AMOUNT_LOCKED: 'This record has been issued, so its amount and currency are locked. Cancel it and create a new one.',
    RECORD_NOT_ISSUED: 'Payments can only be recorded against a record marked Sent.',
    MORE_THAN_OUTSTANDING: 'That is more than the amount outstanding.',
    INVALID_AMOUNT: 'Enter an amount greater than zero.',
    INVALID_CURRENCY: 'Currency must be a three-letter code, e.g. GBP, USD, EUR, EGP.',
    CLIENT_REQUIRED: 'Choose the client.',
    STATUS_IS_DERIVED: 'Part-paid, Paid and Overdue are set automatically from payments and the due date.',
    SUMMARY_REQUIRED: 'Say briefly what happened.',
    NOTE_REQUIRED: 'Write the note first.',
    RECORD_REQUIRED: 'This must be attached to a person, company or opportunity.',
    COMPANY_REQUIRED: 'Company name is required.',
    OPPORTUNITY_TYPE_REQUIRED: 'Describe the opportunity.',
    INVALID_EMAIL: 'That email address is not valid.',
    TASK_NOT_OPEN: 'This task is already closed.',
    USE_APPROVAL_FLOW: 'Outreach approvals are closed by Approve, Hold or Reject in Outreach.',
    NOT_ALLOWED_IN_THIS_STATE: 'Not possible in its current state — refresh and try again.',
    INVALID_ROWS: 'The file could not be read as a list of connections.',
    INVALID_STAGE: 'Unknown stage.', INVALID_CHANNEL: 'Unknown channel.', INVALID_STATUS: 'Unknown status.', INVALID_VALUE: 'Unknown value.',
    NOT_FOUND: 'Record not found — it may have been changed. Refresh.',
    OPPORTUNITY_REQUIRED: 'Open an opportunity first.',
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
  if (key === 'relationships' && state.rel) { const n = state.rel.groups.filter((g) => !g.dismissed && g.received > 0 && !g.review?.status && (relSuggested(g) === 'REPLY_NOW' || g.state === 'REPLIED')).length; return n ? `<span class="badge hot">${n}</span>` : ''; }
  if (key === 'linkedin' && ov) { const n = ov.actions.filter((a) => a.kind === 'LINKEDIN').length; return n ? `<span class="badge">${n}</span>` : ''; }
  if (key === 'inbox' && d) { const n = repliesForAdam(d).length; return n ? `<span class="badge hot">${n}</span>` : ''; }
  if (key === 'website' && ov) { const n = ov.website.filter((w) => w.status === 'NEW').length; return n ? `<span class="badge hot">${n}</span>` : ''; }
  if (key === 'finance' && state.ins) { const n = (state.ins.finance.records || []).filter((r) => r.status === 'OVERDUE').length; return n ? `<span class="badge hot">${n}</span>` : ''; }
  if (key === 'system' && ov) { const n = ov.system.failures.length + ov.system.signals.filter((s) => !s.ok).length; return n ? `<span class="badge hot">${n}</span>` : ''; }
  return '';
}
const navLabel = (k) => NAV.flatMap(([, i]) => i).find(([key]) => key === k)?.[1] || k;

function render() {
  document.body.classList.toggle('auth', !state.session || mustChangePassword() || state.modal === 'password');
  if (!state.session) return renderLogin();
  if (mustChangePassword()) return renderPasswordChange(true);
  if (state.modal === 'password') return renderPasswordChange(false);
  const d = state.data; const live = state.ov || d; const view = VIEWS[state.tab];
  const errs = Object.entries(state.errors).filter(([k]) => k !== 'main').map(([k, v]) => `${k}: ${v}`);
  $('#app').innerHTML = `
    <div class="shell">
      <div class="side-col"><aside class="side">
        <div class="brand">${__HAS_LOGO__ ? '<img src="/noya-mark.svg" alt="">' : ''}<span class="word">NOYA<small>HQ · Private office</small></span></div>
        ${NAV.map(([g, items]) => `<div class="nav-group"><h6>${g}</h6>${items.map(([k, l]) => `<button class="nav-item ${state.tab === k ? 'active' : ''}" data-tab="${k}"><span>${l}</span>${navBadge(k)}</button>`).join('')}</div>`).join('')}
      </aside></div>
      <div>
        <div class="topbar"><div class="mbrand">NOYA</div>
          <div class="search"><input id="q" type="search" placeholder="Search people, companies, markets, tasks…" value="${esc(state.q)}" autocomplete="off">${state.q.trim().length >= 2 ? searchResults(state.q) : ''}</div>
          <div class="meta">
            <span class="live">${live ? `Live · ${esc(fmtDate(live.generated_at))} Cairo` : state.loading ? 'Loading…' : ''}</span>
            <button class="btn small" id="quick" title="Quick actions">+ New</button>
            <button class="btn small" id="refresh">Refresh</button>
            <button class="btn small" id="menu" title="Account">⋯</button>
          </div>
        </div>
        <main>
          ${state.notice ? `<div class="banner ${state.notice.err ? 'err' : 'ok'}">${esc(state.notice.text)}</div>` : ''}
          ${state.errors.main ? `<div class="banner err">${esc(state.errors.main)}</div>` : ''}
          ${errs.length ? `<div class="banner err small">Some data could not load: ${esc(errs.join(' · '))}</div>` : ''}
          ${d && view ? view(d) : `<p class="muted">${state.loading ? 'Loading live CRM…' : 'No data.'}</p>`}
        </main>
      </div>
    </div>
    <nav class="bnav">
      ${[['overview', 'Today'], ['inbox', 'Replies'], ['outreach', 'Outreach']].map(([k, l]) => `<button data-tab="${k}" class="${state.tab === k ? 'active' : ''}">${l}${navBadge(k)}</button>`).join('')}
      <button id="bsearch">Search</button><button id="bmenu" class="${state.menu ? 'active' : ''}">Menu</button>
    </nav>
    ${state.menu ? `<div class="sheet-bg" data-close-menu></div><div class="sheet">${NAV.map(([g, items]) => `<h6>${g}</h6><div class="sheet-grid">${items.map(([k, l]) => `<button data-tab="${k}" class="${state.tab === k ? 'active' : ''}">${l}${navBadge(k)}</button>`).join('')}</div>`).join('')}</div>` : ''}
    ${state.drawer ? renderDrawer(state.drawer) : ''}
    ${state.modal && typeof state.modal === 'object' ? renderAnyModal(state.modal) : ''}`;
  bind();
  if (state.focusSearch) { const q = $('#q'); q.focus(); q.setSelectionRange(q.value.length, q.value.length); state.focusSearch = false; }
}

// ---------------------------------------------------------------- search
function searchResults(raw) {
  const q = raw.trim().toLowerCase(); const d = state.data; if (!d) return '';
  const has = (...v) => v.some((x) => String(x ?? '').toLowerCase().includes(q));
  const dir = state.dir || { companies: [], contacts: [], connections: [] };
  const opps = d.opportunities.filter((o) => { const f = facts(o.id); return has(o.company_name, o.contact_name, o.opportunity_type, o.next_action, f.destination, M(f.origin_market), M(f.opportunity_market), f.origin_country, V(f.vertical)); }).slice(0, 8);
  const cos = dir.companies.filter((c) => has(c.name, c.website, c.country, c.city, M(c.market), V(c.vertical), c.company_type)).slice(0, 6);
  const people = dir.contacts.filter((k) => has(k.name, k.email, k.position, k.company)).slice(0, 6);
  const net = dir.connections.filter((c) => has(c.name, c.company, c.position)).slice(0, 5);
  const tasks = d.tasks.filter((t) => t.status !== 'CANCELLED' && has(t.title, t.company_name)).slice(0, 6);
  const replies = d.inbound.filter((r) => has(r.from, r.company_name, r.subject, r.summary)).slice(0, 4);
  const enq = d.enquiries.filter((e) => has(e.name, e.company, e.reference, e.destination)).slice(0, 4);
  const rels = (state.rel?.groups || []).filter((g) => has(g.name, g.domain, g.subject, g.company, ...(g.emails || []))).slice(0, 5);
  const group = (title, rows) => (rows.length ? `<h6>${title}</h6>${rows.join('')}` : '');
  const html = [
    group('Companies', cos.map((c) => `<button class="hit" data-open="company" data-id="${c.id}"><div>${esc(c.name)}</div><div class="s">${esc(V(c.vertical))} · ${esc(M(c.market))}${c.country ? ` (${esc(c.country)})` : ''} · ${c.active_opps} active</div></button>`)),
    group('People', people.map((k) => `<button class="hit" data-open="contact" data-id="${k.id}"><div>${esc(k.name || k.email || 'Unnamed contact')}</div><div class="s">${esc(k.position || '')} · ${esc(k.company || '')} · email ${esc((k.email_status || 'none').toLowerCase())}</div></button>`)),
    group('Opportunities', opps.map((o) => `<button class="hit" data-open="opp" data-id="${o.id}"><div>${esc(o.company_name)}</div><div class="s">${esc(S(o.status))} · ${esc(o.contact_name || 'no contact')} · ${esc(String(o.opportunity_type || '').slice(0, 50))}</div></button>`)),
    group('LinkedIn network', net.map((c) => `<button class="hit" data-open="connection" data-id="${c.id}"><div>${esc(c.name)}</div><div class="s">${esc(c.position || '')} · ${esc(c.company || '')}</div></button>`)),
    group('Tasks', tasks.map((t) => `<button class="hit" ${t.opportunity_id ? `data-open="opp" data-id="${t.opportunity_id}"` : 'data-go="tasks"'}><div>${esc(sentence(t.title))}</div><div class="s">${esc(t.status.toLowerCase())} · due ${esc(fmtDay(t.due_at))}</div></button>`)),
    group('Replies', replies.map((r) => `<button class="hit" ${r.opportunity_id ? `data-open="opp" data-id="${r.opportunity_id}"` : 'data-go="inbox"'}><div>${esc(r.company_name || r.from)} — ${esc(REPLY_GROUP[r.classification] || r.classification || '')}</div><div class="s">${esc(fmtDate(r.received_at))} · ${esc(r.subject || '')}</div></button>`)),
    group('Previous relationships (email)', rels.map((g) => `<button class="hit" data-relq="${esc(g.domain || g.name)}"><div>${esc(g.name)}</div><div class="s">${esc(g.domain || '')} · ${g.sent} sent · ${g.received} replies · last ${esc(shortDay(g.last_at))}</div></button>`)),
    group('Website leads', enq.map((e) => `<button class="hit" data-go="website"><div>${esc(e.name || e.company)}</div><div class="s">${esc(e.lead_type)} · ${esc(fmtDate(e.created_at))}</div></button>`)),
  ].join('');
  return `<div class="results">${html || '<div class="hit s">No matching records.</div>'}</div>`;
}

// ---------------------------------------------------------------- TODAY
function prettyAction(a) {
  const who = a.person || a.company || '';
  switch (a.kind) {
    case 'MEETING': return `Reply to ${who} — meeting requested`;
    case 'APPROVE': return `Approve outreach to ${a.person ? `${a.person} (${a.company})` : a.company}${/Adam personal/.test(a.action) ? ' — personal' : ''}`;
    case 'LINKEDIN': return `Message ${who} on LinkedIn`;
    case 'INSTAGRAM': return `DM ${a.company || who} on Instagram`;
    case 'FOLLOW_UP': return `Follow up with ${who}`;
    case 'SEND_DRAFT': return `Send the approved email to ${who} (it is in Gmail Drafts)`;
    case 'WEBSITE': return `Review website enquiry — ${who}`;
    default: return sentence(String(a.action || '').replace(/ -- .*$/, '')) + (a.company && !String(a.action).includes(a.company) ? ` — ${a.company}` : '');
  }
}

function actionButtons(a) {
  const r = ready(a.opportunity_id);
  const b = [];
  const open = a.opportunity_id ? `<button class="btn small" data-open="opp" data-id="${a.opportunity_id}">Open</button>` : `<button class="btn small" data-go="${a.go}">Open</button>`;
  if (a.kind === 'APPROVE') { b.push(`<button class="btn small primary" data-go="outreach" data-otab="READY" data-anchor="opp-${a.opportunity_id}">Review</button>`, open); }
  else if (a.kind === 'LINKEDIN' || a.kind === 'INSTAGRAM') {
    const url = a.kind === 'LINKEDIN' ? r.linkedin : r.instagram;
    const msg = a.kind === 'LINKEDIN' ? r.ready_linkedin : r.ready_instagram;
    if (url) b.push(`<a class="btn small" href="${esc(url)}" target="_blank" rel="noopener noreferrer">Open ${a.kind === 'LINKEDIN' ? 'LinkedIn' : 'Instagram'}</a>`);
    if (msg) b.push(`<button class="btn small" data-copy="${esc(msg)}">Copy message</button>`);
    b.push(`<button class="btn small primary" data-modal="touch" data-channel="${a.kind === 'LINKEDIN' ? 'LINKEDIN' : 'INSTAGRAM_DM'}" data-task="${a.task_id || ''}" data-opp="${a.opportunity_id || ''}">Mark sent</button>`);
  } else if (a.kind === 'MEETING' || a.kind === 'REPLY') {
    const t = state.data.inbound.find((x) => x.opportunity_id === a.opportunity_id && x.thread_id);
    if (t) b.push(`<a class="btn small" href="${GMAIL_THREAD_URL}${esc(t.thread_id)}" target="_blank" rel="noopener noreferrer">Open email</a>`);
    if (a.opportunity_id) b.push(`<button class="btn small" data-modal="meeting" data-opp="${a.opportunity_id}" data-task="${a.task_id || ''}">Record meeting</button>`);
    b.push(open);
  } else b.push(open);
  if (a.task_id && a.task_type !== 'SALES_OUTREACH_APPROVAL' && !['LINKEDIN', 'INSTAGRAM'].includes(a.kind)) b.push(`<button class="btn small" data-modal="task-done" data-id="${a.task_id}">Done</button>`);
  if (a.task_id) b.push(`<button class="btn small" data-modal="task-snooze" data-id="${a.task_id}">Snooze</button>`);
  if (a.task_id && a.task_type !== 'SALES_OUTREACH_APPROVAL') b.push(`<button class="btn small ghost" data-modal="task-dismiss" data-id="${a.task_id}" title="Not relevant — close with a reason">✕</button>`);
  return b.join('');
}

function actionRow(a) {
  const due = a.due_at ? `${a.overdue ? '<span class="od">overdue · ' : ''}due ${esc(shortDay(a.due_at))}${a.overdue ? '</span>' : ''}` : '';
  const value = a.value != null ? `${esc(money(a.value, a.currency))}${lbl('ESTIMATE')}` : '';
  const f = facts(a.opportunity_id);
  const ctx = [a.company !== a.person ? a.company : '', f.vertical ? V(f.vertical) : '', f.origin_market && f.origin_market !== 'UNKNOWN' ? `${M(f.origin_market)} → ${M(f.opportunity_market)}` : ''].filter(Boolean).map(esc).join(' · ');
  return `<div class="q-row">
    <div class="prio ${a.prio}" title="${a.prio === 'P1' ? 'Urgent / revenue / client-critical' : a.prio === 'P2' ? 'Important commercial action' : 'Operational'}">${a.prio}</div>
    <div><div class="q-act">${esc(prettyAction(a))}</div>
      <div class="q-meta">${ctx || '—'}${due ? ` · ${due}` : ''}${value ? ` · ${value}` : ''}</div>
      <div class="q-meta src" title="${esc(a.source)}">${esc(sourceLabel(a.source))}${a.next_action ? ` · next: ${esc(a.next_action)}` : ''}</div></div>
    <div class="q-btns">${actionButtons(a)}</div></div>`;
}

function viewOverview(d) {
  const ov = state.ov;
  if (!ov) return `<div class="banner err">${esc(state.errors.ov || 'Today not loaded.')}</div>`;
  const P = (p) => ov.actions.filter((a) => a.prio === p);
  const p1 = P('P1'); const p2 = P('P2'); const p3 = P('P3');
  const p2shown = state.queueAll ? p2 : p2.slice(0, 8);
  const s = ov.scorecard;
  const stageOrder = STAGES.filter((k) => s.stages[k]);
  const total = stageOrder.reduce((n, k) => n + s.stages[k], 0) || 1;
  const sc = (label, n, def, go, help) => `<div class="k ${go ? 'clk' : ''}" title="${esc(help ? HELP[help] + ' — ' + def : def)}" ${go ? `data-go="${go}"` : ''}>${label}</div><div class="v">${esc(n)}</div>`;
  const sigBad = ov.system.signals.filter((x) => !x.ok).length + ov.system.failures.length;
  const replies = ov.replies;
  const day = new Date(`${ov.today}T12:00:00Z`).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' });
  return `
    <div class="ov-head"><h1>Today</h1><span class="sub">${esc(day)} · every figure is a live query; hover a label for what it means</span></div>
    <div class="ov-grid">
      <section class="panel">
        <header><h3>What needs you</h3><div class="counts"><span title="Urgent / revenue / client-critical">P1 ${p1.length}</span><span title="Important commercial action">P2 ${p2.length}</span><span title="Operational">P3 ${p3.length}</span></div></header>
        <div class="body">
          ${p1.length ? p1.map(actionRow).join('') : '<div class="empty">No P1 items — nothing urgent or revenue-critical is waiting.</div>'}
          ${p2shown.map(actionRow).join('')}
          ${p2.length > 8 ? `<button class="linkish" id="queue-all">${state.queueAll ? 'Show fewer' : `Show all ${p2.length} P2 actions`}</button>` : ''}
          ${p3.length ? `<div><button class="linkish" id="queue-p3">${state.queueP3 ? 'Hide' : 'Show'} ${p3.length} P3 (operational)</button></div>${state.queueP3 ? p3.map(actionRow).join('') : ''}` : ''}
        </div>
      </section>
      <div>
        <section class="panel">
          <header><h3>Pipeline</h3><button class="btn small ghost" data-go="pipeline">Open</button></header>
          <div class="body">
            <div class="stagebar" title="${esc(stageOrder.map((k) => `${S(k)} ${s.stages[k]}`).join(' · '))}">${stageOrder.map((k) => `<span class="${['CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON', 'INTERESTED'].includes(k) ? 'hot' : ''}" data-flex="${(s.stages[k] / total).toFixed(4)}"></span>`).join('')}</div>
            <div class="small faint">${esc(stageOrder.map((k) => `${S(k).toLowerCase()} ${s.stages[k]}`).join(' · '))}</div>
            <div class="score mt8">
              ${sc('Active opportunities', s.active_opportunities.n, s.active_opportunities.def, 'pipeline')}
              ${sc('In conversation', s.in_conversation.n, s.in_conversation.def, 'pipeline')}
              ${sc('Call required', s.call_required.n, s.call_required.def, 'pipeline', 'call_required')}
              ${sc('Proposals open', s.proposals.n, s.proposals.def, 'pipeline')}
              ${sc('Won', s.won.n, s.won.def, 'pipeline')}
              ${sc('Approvals ready', s.approvals_ready.n, s.approvals_ready.def, 'outreach', 'approvals')}
              ${sc('Positive replies · 7d', s.positive_replies_7d.n, s.positive_replies_7d.def, 'inbox')}
              ${sc('Website enquiries · 7d', s.website_7d.n, `${s.website_7d.def} (all-time ${s.website_7d.total})`, 'website')}
              ${sc('Overdue tasks', s.overdue_tasks.n, s.overdue_tasks.def, 'tasks')}
              ${sc('System', sigBad ? `${sigBad} issue${sigBad > 1 ? 's' : ''}` : 'OK', 'workflow signals + failure alerts', 'system')}
            </div>
          </div>
        </section>
        <section class="panel mt8">
          <header><h3>Money</h3><button class="btn small ghost" data-go="finance">Finance</button></header>
          <div class="body">${moneyBlock()}</div>
        </section>
      </div>
    </div>
    ${warmPanel()}
    ${commandPanels()}
    <div class="ov-grid3">
      <section class="panel"><header><h3>Replies · 14 days</h3><button class="btn small ghost" data-go="inbox">Replies</button></header>
        <div class="body">${replies.length ? replies.slice(0, 5).map((r) => `<div class="mini clickable" ${r.opportunity_id ? `data-open="opp" data-id="${r.opportunity_id}"` : ''}>
          <div class="t">${esc(r.company || r.from)} ${pill(REPLY_GROUP[r.classification] || r.classification, r.classification === 'MEETING_REQUEST' ? 'bad' : r.deterministic ? '' : 'info')}</div>
          <div class="m">${esc(fmtDate(r.received_at))} · ${esc(r.person || r.from || '')}${r.deterministic ? ' · automatic reply' : ''}</div>
          <div class="m">${esc(r.summary || '')}</div></div>`).join('') : '<div class="empty">No replies in the last 14 days.</div>'}</div></section>
      <section class="panel"><header><h3>Website · 30 days</h3><button class="btn small ghost" data-go="website">Leads</button></header>
        <div class="body">${ov.website.length ? ov.website.slice(0, 5).map((w) => `<div class="mini"><div class="t">${esc(w.name || w.company || 'Enquiry')} ${pill(w.lead_type)}</div>
          <div class="m">${esc(fmtDate(w.created_at))} · ${esc(w.status)}${w.destination ? ` · ${esc(w.destination)}` : ''}${w.guests ? ` · ${esc(w.guests)} guests` : ''}</div></div>`).join('')
          : `<div class="empty">No website enquiries in the last 30 days (all-time: ${esc(s.website_7d.total)}). The intake is live and waiting for the new website form.</div>`}</div></section>
      <section class="panel"><header><h3>System</h3><button class="btn small ghost" data-go="system">Details</button></header>
        <div class="body">
          ${ov.system.failures.map((f) => `<div class="sig"><span><span class="dot bad"></span>${esc(f.title)}</span></div>`).join('')}
          ${ov.system.signals.map((x) => `<div class="sig" title="${esc(x.rule)}"><span><span class="dot ${x.ok ? '' : 'bad'}"></span>${esc(signalName(x.name))}</span><span class="faint">${esc(x.last ? fmtDate(x.last) : 'never')}</span></div>`).join('')}
          ${ov.system.blockers.length ? `<div class="small faint mt8">${ov.system.blockers.length} known blocker${ov.system.blockers.length > 1 ? 's' : ''} (not failures) — see System health.</div>` : ''}
          ${(() => { const n = (state.ins?.services || []).filter((x) => x.status === 'ACTIVE' && (x.cost_type === 'UNKNOWN' || (x.cost_type !== 'FREE' && x.monthly_cost == null))).length; return n ? `<div class="small mt6"><button class="linkish" data-go="costs">${n} software costs UNKNOWN — verify before scale</button></div>` : ''; })()}
        </div></section>
    </div>`;
}
// Warm opportunities: existing relationships that deserve action now. Real evidence only
// (NOYA Gmail threads, CRM records, LinkedIn matches); your confirmed status outranks HQ's suggestion.
function warmOpportunities() {
  const out = []; const byKey = {};
  const days = (t) => (t ? Math.floor((Date.now() - new Date(t)) / 86400000) : 999);
  (state.rel?.groups || []).filter((g) => !g.dismissed && g.received > 0).forEach((g) => {
    const mine = g.review?.status; const sug = relSuggested(g); const st = mine || sug;
    if (!['REPLY_NOW', 'RECONNECT'].includes(st)) return;
    const theyLast = g.last_in && (!g.last_out || g.last_in > g.last_out);
    let score = (st === 'REPLY_NOW' ? 100 : 60) + (mine ? 10 : 0) + (g.opportunity_status ? 8 : 0) + Math.max(0, 30 - days(g.last_at) / 6);
    const facts = [`${theyLast ? 'They wrote last' : 'NOYA wrote last'} ${shortDay(g.last_at)}`, `${g.sent} sent · ${g.received} from them`];
    if (g.opportunity_status) facts.push(`deal: ${S(g.opportunity_status).toLowerCase()}`);
    const item = { key: g.key, name: g.name, st, mine: !!mine, score, facts, thread: g.reply_thread || g.last_thread, why: g.review?.their_position || '' };
    byKey[g.key] = item; out.push(item);
  });
  (state.dir?.connections || []).filter((c) => c.status !== 'DO_NOT_CONTACT' && (c.active_opps > 0 || c.email_history > 0)).forEach((c) => {
    if (c.history_key && byKey[c.history_key]) { byKey[c.history_key].facts.push(`LinkedIn: ${c.name}`); byKey[c.history_key].score += 5; return; }
    if (!c.active_opps) return; // LinkedIn alone is only warm when there is a live deal at their company
    out.push({ conn: c.id, name: `${c.name}${c.company ? ` · ${c.company}` : ''}`, st: 'LINKEDIN', mine: false, score: 40 + c.active_opps * 5,
      facts: (c.evidence || []).slice(0, 2), why: '' });
  });
  return out.sort((a, b) => b.score - a.score).slice(0, 6);
}
function warmPanel() {
  const w = warmOpportunities(); if (!state.rel) return '';
  const lbl2 = (x) => (x.st === 'LINKEDIN' ? pill('LinkedIn · you send', 'info') : x.mine ? pill(`You: ${REL_STATUS[x.st][0]}`, REL_STATUS[x.st][1]) : `<span class="pill ghost" title="HQ suggestion from the email facts — not confirmed by you">Suggested: ${esc(REL_STATUS[x.st][0])}</span>`);
  return `<section class="panel mt8"><header><h3>Warm opportunities</h3><button class="btn small ghost" data-go="relationships">Review all</button></header>
    <div class="body">${w.length ? w.map((x) => `<div class="mini warm"><div class="t">${esc(x.name)} ${lbl2(x)}</div>
      <div class="m">${esc(x.facts.join(' · '))}</div>${x.why ? `<div class="m faint">AI reading of their emails: ${esc(x.why)}</div>` : ''}
      <div class="btn-row mt6">${x.thread ? gmailLink(x.thread, 'Open in Gmail').replace('<a ', '<a class="btn small" ') : ''}${x.conn ? `<button class="btn small" data-open="connection" data-id="${x.conn}">Open</button>` : `<button class="btn small" data-relq="${esc(x.name)}">Review</button>`}</div></div>`).join('')
      : '<div class="empty">No warm relationship needs action right now.</div>'}
      <p class="src">Only existing relationships with real evidence: NOYA Gmail threads, CRM records and matched LinkedIn connections. Nothing is sent from here.</p></div></section>`;
}
const signalName = (n) => ({ 'Gmail sync (13)': 'Email reply tracking', 'Daily CEO brief (11)': 'Daily CEO brief', 'Outbound drafts (12)': 'Gmail drafts', 'Discovery (02/03/04/06/08)': 'Prospect research' }[n] || n);

function moneyBlock() {
  const ins = state.ins; const ov = state.ov;
  const line = (k, v, kind, help) => `<div class="money-line"><span${help ? tip(help) : ''}>${k}${lbl(kind)}</span><span class="v">${v}</span></div>`;
  if (!ins) return `<div class="empty">Finance not loaded.</div>`;
  const f = ins.finance; const byc = cur(f.by_currency);
  const rev = f.records.length === 0
    ? line('Collected', '<span class="muted">none recorded</span>', 'ACTUAL', 'collected') + line('Outstanding', '<span class="muted">none recorded</span>', 'ACTUAL', 'outstanding')
    : byc.map((c) => line(`Won (${esc(c.currency)})`, c.won != null ? esc(money(c.won, c.currency)) : '<span class="muted">none</span>', 'ACTUAL', 'won')
        + line(`Collected (${esc(c.currency)})`, c.collected != null ? esc(money(c.collected, c.currency)) : '<span class="muted">none</span>', 'ACTUAL', 'collected')
        + line(`Outstanding (${esc(c.currency)})`, c.outstanding != null ? esc(money(c.outstanding, c.currency)) + (c.overdue ? ` <span class="bad-text small">${esc(money(c.overdue, c.currency))} overdue</span>` : '') : '<span class="muted">none</span>', 'ACTUAL', 'outstanding')).join('');
  const pipe = cur(f.pipeline).map((p) => line(`Pipeline (${esc(p.currency)})`, `${esc(money(p.amount, p.currency))} <span class="faint small">(${p.opportunities} opps)</span>`, 'ESTIMATE', 'pipeline')).join('');
  return `${rev}${line('Won deals', esc(ov?.money.won_deals ?? 0), 'ACTUAL')}${pipe}
    ${f.pipeline_unknown ? line('Pipeline value not estimated', `${esc(f.pipeline_unknown)} opps`, 'UNKNOWN', 'unknown') : ''}
    <div class="src mt6">Finance records: ${esc(f.records.length)}. Pipeline is a research estimate, never revenue. Currencies are never added together.</div>`;
}

// ---------------------------------------------------------------- OUTREACH
function repliesForAdam(d) {
  return d.inbound.filter((r) => r.task_id && openStatuses.includes(r.task_status) && !['OUT_OF_OFFICE', 'UNRELATED'].includes(r.classification))
    .sort((a, b) => (REPLY_ORDER[a.classification] ?? 9) - (REPLY_ORDER[b.classification] ?? 9));
}
const openTasks = (d) => d.tasks.filter((t) => openStatuses.includes(t.status));

function manualChannelCard(a) {
  const r = ready(a.opportunity_id); const f = facts(a.opportunity_id); const o = opp(a.opportunity_id) || {};
  const t = state.data.tasks.find((x) => x.id === a.task_id);
  const isLi = a.kind === 'LINKEDIN';
  const msg = (isLi ? r.ready_linkedin : r.ready_instagram) || (t ? String(t.description || '').split('--- MESSAGE ---')[1]?.split('\n\nAfter sending')[0]?.trim() : '');
  const url = isLi ? r.linkedin : r.instagram;
  return `<article class="card" id="task-${a.task_id}">
    <div class="card-head"><div><div class="co">${esc(a.company || '')}</div><div class="muted small">${esc(a.person || 'account owner')}${r.contact_role ? ` · ${esc(r.contact_role)}` : ''}</div></div>
      <div class="pills">${pill(a.prio, a.prio === 'P1' ? 'bad' : '')}${f.vertical ? pill(V(f.vertical)) : ''}${f.origin_market ? pill(`${M(f.origin_market)} → ${M(f.opportunity_market)}`) : ''}${emailPill(r.email_status, r.email_kind)}</div></div>
    ${prevRel(f.company_id, null)}
    <div class="grid2">
      <div class="kv"><div class="k">Why now</div><div class="v small">${esc(r.why_now || o.next_action || '—')}</div></div>
      <div class="kv"><div class="k">Opportunity</div><div class="v small">${esc(String(o.opportunity_type || '—').slice(0, 140))}</div></div>
      <div class="kv"><div class="k">Last interaction</div><div class="v small">${esc(r.last_outbound_at ? `sent ${fmtDay(r.last_outbound_at)}` : 'none yet')}${r.last_inbound_at ? ` · reply ${esc(fmtDay(r.last_inbound_at))}` : ''}</div></div>
      <div class="kv"><div class="k">Sent from</div><div class="v small">${isLi ? 'Adam personally (LinkedIn)' : 'NOYA Instagram'}</div></div>
    </div>
    ${msg ? `<div class="email"><pre>${esc(msg)}</pre></div>` : '<p class="muted small">No prepared message — draft one.</p>'}
    <div class="btn-row">
      ${url ? `<a class="btn small" href="${esc(url)}" target="_blank" rel="noopener noreferrer">Open ${isLi ? 'LinkedIn' : 'Instagram'}</a>` : ''}
      ${msg ? `<button class="btn small" data-copy="${esc(msg)}">Copy message</button>` : ''}
      <button class="btn small primary" data-modal="touch" data-channel="${isLi ? 'LINKEDIN' : 'INSTAGRAM_DM'}" data-task="${a.task_id}" data-opp="${a.opportunity_id || ''}">Mark sent</button>
      <button class="btn small" data-modal="draft-request" data-channel="${isLi ? 'LINKEDIN' : 'INSTAGRAM'}" data-opp="${a.opportunity_id || ''}">Redraft</button>
      <button class="btn small" data-modal="task-snooze" data-id="${a.task_id}">Snooze</button>
      <button class="btn small" data-modal="note" data-opp="${a.opportunity_id || ''}">Add note</button>
      <button class="btn small ghost" data-modal="task-dismiss" data-id="${a.task_id}">Reject</button>
    </div></article>`;
}

function viewOutreach(d) {
  const a = d.approvals;
  const acts = state.ov?.actions || [];
  const tabs = {
    READY: a.filter((x) => x.loop_stage === 'PENDING_APPROVAL' && !x.block_reason),
    'FOLLOW-UP': openTasks(d).filter((t) => t.task_type === 'OUTREACH_FOLLOW_UP').sort((x, y) => new Date(x.due_at) - new Date(y.due_at)),
    LINKEDIN: acts.filter((x) => x.kind === 'LINKEDIN'),
    INSTAGRAM: acts.filter((x) => x.kind === 'INSTAGRAM'),
    SENT: a.filter((x) => ['APPROVED', 'DRAFT_CREATED', 'SENT', 'FAILED', 'DRAFT_DISCARDED'].includes(x.loop_stage)),
    REPLIED: a.filter((x) => x.loop_stage === 'REPLIED'),
    HOLD: a.filter((x) => x.loop_stage === 'ON_HOLD' || x.loop_stage === 'REJECTED' || (x.loop_stage === 'PENDING_APPROVAL' && x.block_reason)),
    RESEARCHING: d.opportunities.filter((o) => ['NEW', 'RESEARCHING'].includes(o.status)),
  };
  const t = state.outreachTab;
  const intro = {
    READY: 'Email outreach to a verified person, drafted and checked. Approve creates a Gmail draft — you press Send in Gmail.',
    'FOLLOW-UP': 'Conversations waiting on a follow-up. One follow-up, then an optional final one, then long term — never endless chasing.',
    LINKEDIN: 'Messages from you personally. Open the profile, paste the message, send it yourself, then press Mark sent so the follow-up is booked.',
    INSTAGRAM: 'Only Instagram-native accounts (weddings, clubs, hotels, brands). Never banks, law or wealth firms.',
    SENT: 'Outreach approved and sent (or in Gmail Drafts waiting for you).',
    REPLIED: 'Prospects who answered. See Replies for the message and next step.',
    HOLD: 'Parked: on hold, rejected, or the email route is blocked until a verified contact exists.',
    RESEARCHING: 'Still missing a verified person or channel. The research agents keep working on these (up to 10 a day, highest priority first).',
  }[t];
  let body = '';
  // One-at-a-time mode for phones: one card, Back / Skip; acting on it moves to the next automatically.
  const one = state.oneByOne && ['READY', 'LINKEDIN', 'INSTAGRAM'].includes(t) && tabs[t].length > 0;
  const oi = Math.min(state.oIdx || 0, Math.max(0, tabs[t].length - 1));
  const list = one ? [tabs[t][oi]] : tabs[t];
  const oneNav = ['READY', 'LINKEDIN', 'INSTAGRAM'].includes(t) && tabs[t].length > 1 ? `<div class="review-nav"><button class="btn small ${state.oneByOne ? 'primary' : 'ghost'}" data-one-toggle>${state.oneByOne ? 'One at a time: on' : 'One at a time'}</button>
    ${one ? `<span><span class="small"><b>${oi + 1}</b> of ${tabs[t].length}</span> <button class="btn small ghost" data-o-step="-1" ${oi === 0 ? 'disabled' : ''}>Back</button><button class="btn small ghost" data-o-step="1" ${oi >= tabs[t].length - 1 ? 'disabled' : ''}>Skip</button></span>` : ''}</div>` : '';
  if (t === 'READY') body = oneNav + (list.map(approvalCard).join('') || empty('No email outreach waiting for approval.'));
  else if (t === 'LINKEDIN' || t === 'INSTAGRAM') body = oneNav + (list.map(manualChannelCard).join('') || empty('Nothing ready on this channel.'));
  else if (t === 'FOLLOW-UP') body = `<div class="list">${tabs[t].map((x) => `<div class="row"><div class="t">${esc(sentence(x.title))}</div><div class="meta">${esc(x.company_name || '')} · due ${esc(fmtDay(x.due_at))}${new Date(x.due_at) < new Date() ? ' · <span class="bad-text">overdue</span>' : ''}</div>
      <div class="btn-row mt6">${x.opportunity_id ? `<button class="btn small" data-open="opp" data-id="${x.opportunity_id}">Open</button>` : ''}<button class="btn small primary" data-modal="touch" data-channel="EMAIL" data-task="${x.id}" data-opp="${x.opportunity_id || ''}">Followed up</button><button class="btn small" data-modal="task-snooze" data-id="${x.id}">Snooze</button><button class="btn small ghost" data-modal="task-dismiss" data-id="${x.id}">No longer needed</button></div></div>`).join('') || empty('No follow-ups due.')}</div>`;
  else if (t === 'RESEARCHING') body = `<div class="tbl-wrap"><table><thead><tr><th>Company</th><th>Vertical</th><th>Market</th><th>Contact</th><th class="num">Priority</th><th>Next</th></tr></thead><tbody>${tabs[t].sort((x, y) => (y.priority ?? 0) - (x.priority ?? 0)).map((o) => { const f = facts(o.id); return `<tr class="clickable" data-open="opp" data-id="${o.id}"><td>${esc(o.company_name)}</td><td>${esc(V(f.vertical))}</td><td>${esc(M(f.origin_market))} → ${esc(M(f.opportunity_market))}</td><td>${esc(o.contact_name || '—')}</td><td class="num">${esc(o.priority ?? '—')}</td><td class="small">${esc(o.next_action || '')}</td></tr>`; }).join('')}</tbody></table></div>`;
  else body = tabs[t].map(approvalCard).join('') || empty('None.');
  return `
    <h2>Outreach</h2>
    <div class="tabs">${Object.keys(tabs).map((k) => `<button data-otab="${k}" class="${t === k ? 'on' : ''}">${k.charAt(0) + k.slice(1).toLowerCase().replace('-up', '-up')} <span class="n">${tabs[k].length}</span></button>`).join('')}</div>
    <p class="muted small">${esc(intro)}</p>
    ${body}`;
}
const empty = (t) => `<div class="panel"><div class="body"><div class="empty">${esc(t)}</div></div></div>`;

function loopBar(stage) {
  const order = ['PENDING_APPROVAL', 'DRAFT_CREATED', 'SENT', 'REPLIED', 'NEXT'];
  const idx = stage === 'APPROVED' ? 0.5 : order.indexOf(stage);
  return `<div class="loop">${LOOP.map(([k, l], i) => `<span class="${i < idx ? 'done' : i === idx || (idx === 0.5 && i === 1) ? 'now' : ''}">${l}</span>`).join('')}</div>`;
}

function approvalCardBase(a) {
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
        const acts = openStatuses.includes(t.status) ? `<div class="btn-row mt6">${t.opportunity_id ? `<button class="btn small" data-open="opp" data-id="${t.opportunity_id}">Open</button>` : ''}${t.task_type !== 'SALES_OUTREACH_APPROVAL' ? `<button class="btn small" data-modal="task-done" data-id="${t.id}">Done</button>` : ''}<button class="btn small" data-modal="task-snooze" data-id="${t.id}">Snooze</button>${t.task_type !== 'SALES_OUTREACH_APPROVAL' ? `<button class="btn small ghost" data-modal="task-dismiss" data-id="${t.id}">✕</button>` : ''}</div>` : '';
        return `<div class="row"><div class="t small">${esc(sentence(t.title))}</div><div class="meta">${pill(prioBand(t.priority ?? 0), t.priority >= 80 ? 'gold' : '')} ${esc(department(t.created_by))} · ${esc(t.assigned_to || '—')}</div>
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
    <h2>Replies</h2>
    <p class="muted small">Replies to NOYA outreach, logged by workflow 13. Bounce and out-of-office labels come from delivery headers and always override the AI label. Nothing is replied to automatically — suggested replies are drafts for you.</p>
    ${Object.entries(groups).map(([g, list]) => `<h3>${esc(g)} (${list.length})</h3><div class="list">${list.map((r) => {
      const sug = suggestedReply(r.task_description);
      return `<div class="row"><div class="t">${pill(r.classification || r.outcome, cls(r.classification))} ${esc(r.company_name || 'Unmatched — needs review')}</div>
        <div class="meta">${esc(fmtDate(r.received_at))} · from ${esc(r.from || '')} · ${esc(r.subject || '')} · matched by ${esc(r.match_method || '—')}</div>
        <div class="small mt6">${esc(r.summary || '')}</div>
        <div class="small mt6"><b>Next:</b> ${esc(r.task_title || r.next_action || 'No action needed')}${r.task_status ? ` (${esc(r.task_status)})` : ''}</div>
        ${sug ? `<details><summary>Suggested reply (not sent)</summary><pre class="text">${esc(sug)}</pre></details>` : ''}
        <div class="btn-row mt6">${r.opportunity_id ? `<button class="btn small" data-open="opp" data-id="${r.opportunity_id}">Open record</button>` : ''}${r.opportunity_id ? `<button class="btn small" data-modal="meeting" data-opp="${r.opportunity_id}" data-task="${r.task_id || ''}">Record meeting</button>` : ''}${r.thread_id ? `<a class="btn small" href="${GMAIL_THREAD_URL}${esc(r.thread_id)}" target="_blank" rel="noopener noreferrer">Open in Gmail</a>` : ''}</div></div>`;
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
    <h2>System health</h2>
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
    <p class="src mt8">Per-workflow execution history (last success/failure per n8n workflow) is build phase 11; today these signals come from the records each workflow writes. Failures also email Adam through workflow 00. Signed in as ${esc(d.admin)}. Costs and dependencies: <button class="linkish" data-go="costs">System costs</button>.</p>`;
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
function findApproval(id) { return state.data.approvals.find((a) => a.id === id); }
function findTask(id) { return state.data.tasks.find((t) => t.id === id); }
function isoPlus(days) { const x = new Date(); x.setDate(x.getDate() + days); return x.toLocaleDateString('en-CA', { timeZone: 'Africa/Cairo' }); }
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

// Outreach card: the approval card plus market, channel and relationship context.
function approvalCard(a) {
  const f = facts(a.id); const r = ready(a.id);
  const ctx = [f.vertical ? V(f.vertical) : '', f.origin_market ? `${M(f.origin_market)} → ${M(f.opportunity_market)}` : '',
    r.primary_channel ? `best channel: ${String(r.primary_channel).toLowerCase()}` : '',
    r.last_outbound_at ? `last contact ${fmtDay(r.last_outbound_at)}` : 'no previous contact'].filter(Boolean);
  const extra = `<div class="ctx small">${ctx.map(esc).join(' · ')}${isClient(f.company_id) ? ` ${pill('Client — handle personally', 'bad')}` : ''}</div>${prevRel(f.company_id, a.contact_id)}${r.evidence ? `<div class="kv"><div class="k">Evidence</div><div class="v small">${esc(r.evidence)}</div></div>` : ''}`;
  const open = ['PENDING_APPROVAL', 'ON_HOLD'].includes(a.loop_stage);
  const more = `<div class="btn-row sub">
    <button class="btn small ghost" data-open="opp" data-id="${a.id}">Open record</button>
    ${open ? `<button class="btn small ghost" data-modal="channel" data-opp="${a.id}">Change channel</button>` : ''}
    <button class="btn small ghost" data-modal="note" data-opp="${a.id}">Add note</button>
    ${a.loop_stage === 'SENT' ? `<button class="btn small ghost" data-modal="meeting" data-opp="${a.id}">Record meeting</button>` : ''}
  </div>`;
  return approvalCardBase(a).replace('<div class="grid2">', `${extra}<div class="grid2">`).replace(/<\/article>\s*$/, `${more}</article>`);
}

// ---------------------------------------------------------------- PIPELINE
const ACTIVE = (s) => !['WON', 'LOST', 'ARCHIVED', 'LONG_TERM'].includes(s);
const stale = (o) => daysAgo(o.updated_at) > 14 && ACTIVE(o.status);
function pipeRows(d) {
  const f = state.pipeF; const q = f.q.trim().toLowerCase();
  return d.opportunities.filter((o) => {
    const x = facts(o.id);
    if (f.stage && o.status !== f.stage) return false;
    if (f.vertical && x.vertical !== f.vertical) return false;
    if (f.market && x.origin_market !== f.market && x.opportunity_market !== f.market) return false;
    if (f.stale && !stale(o)) return false;
    if (q && ![o.company_name, o.contact_name, o.opportunity_type, o.next_action, x.destination, x.origin_country].some((v) => String(v ?? '').toLowerCase().includes(q))) return false;
    return true;
  });
}
const opt = (v, curv, label = v) => `<option value="${esc(v)}" ${v === curv ? 'selected' : ''}>${esc(label)}</option>`;
function viewPipeline(d) {
  const f = state.pipeF; const rows = pipeRows(d);
  const by = {}; d.opportunities.forEach((o) => { by[o.status] = (by[o.status] || 0) + 1; });
  const est = (o) => (o.estimated_value != null ? `${esc(money(o.estimated_value, o.currency))}${lbl('ESTIMATE')}` : '<span class="faint">unknown</span>');
  const filters = `<div class="filters">
    <select data-pf="stage">${opt('', f.stage, `All stages · ${d.opportunities.length}`)}${STAGES.filter((s) => by[s]).map((s) => opt(s, f.stage, `${S(s)} · ${by[s]}`)).join('')}</select>
    <select data-pf="vertical">${opt('', f.vertical, 'All verticals')}${Object.entries(VERTICAL_LABEL).map(([k, l]) => opt(k, f.vertical, l)).join('')}</select>
    <select data-pf="market">${opt('', f.market, 'All markets')}${Object.entries(MARKET_LABEL).map(([k, l]) => opt(k, f.market, l)).join('')}</select>
    <label class="chk"><input type="checkbox" data-pf="stale" ${f.stale ? 'checked' : ''}> Stale only</label>
    <input data-pf="q" placeholder="Filter…" value="${esc(f.q)}">
    <div class="seg"><button data-pview="table" class="${state.pipeView === 'table' ? 'on' : ''}">Table</button><button data-pview="board" class="${state.pipeView === 'board' ? 'on' : ''}">Board</button></div></div>`;
  let body;
  if (state.pipeView === 'board') {
    const cols = STAGES.filter((s) => !['ARCHIVED'].includes(s) && rows.some((o) => o.status === s));
    body = `<div class="board">${cols.map((s) => { const list = rows.filter((o) => o.status === s).sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0));
      return `<div class="bcol"><h4><span>${esc(S(s))}</span><span>${list.length}</span></h4>${list.map((o) => { const x = facts(o.id);
        return `<div class="bcard clickable" data-open="opp" data-id="${o.id}"><div class="t">${esc(o.company_name)}</div><div class="m">${esc(V(x.vertical))} · ${esc(M(x.origin_market))}</div><div class="m">${est(o)}${stale(o) ? ` ${pill('stale', 'warn')}` : ''}</div></div>`; }).join('')}</div>`; }).join('')}</div>`;
  } else {
    body = `<div class="tbl-wrap"><table>
      <thead><tr><th>Company</th><th>Stage</th><th>Vertical</th><th>Market</th><th>Contact</th><th class="num">Estimate</th><th>Updated</th><th>Next action</th></tr></thead>
      <tbody>${rows.map((o) => { const x = facts(o.id); return `<tr class="clickable" data-open="opp" data-id="${o.id}"><td>${esc(o.company_name)}<div class="muted small">${esc(String(o.opportunity_type || '').slice(0, 60))}</div></td>
        <td>${pill(S(o.status))} ${stale(o) ? pill('stale', 'warn') : ''}</td><td class="small">${esc(V(x.vertical))}</td>
        <td class="small">${esc(M(x.origin_market))} → ${esc(M(x.opportunity_market))}</td>
        <td>${esc(o.contact_name || '—')}<div class="muted small">${esc((o.email_status || 'no contact').toLowerCase())}</div></td>
        <td class="num">${est(o)}</td><td class="small">${esc(shortDay(o.updated_at))}</td><td class="small">${esc(o.next_action || '')}</td></tr>`; }).join('') || '<tr><td colspan="8" class="muted">No opportunities match.</td></tr>'}</tbody></table></div>`;
  }
  return `<h2>Pipeline</h2>
    <p class="muted small"${tip('pipeline')}>${rows.length} shown. Values are research estimates (never revenue); blank = unknown. Stale = no update in 14 days. Click any row for the full record, history and actions.</p>
    ${filters}${body}`;
}

// ---------------------------------------------------------------- CONTACTS / COMPANIES
function provenanceTitle(k) {
  return [k.provenance && `Source: ${k.provenance}`, k.provider && `Checked by ${k.provider}`, k.verified_at && `on ${fmtDay(k.verified_at)}`,
    k.verified_by && `(${k.verified_by})`, k.quality_issue && `Issue: ${k.quality_issue}`].filter(Boolean).join(' ') || 'No verification record.';
}
function viewContacts() {
  const dir = state.dir; if (!dir) return empty('Contacts not loaded.');
  const f = state.contactF; const q = f.q.trim().toLowerCase();
  const rows = dir.contacts.filter((k) => (!f.email || String(k.email_status || 'NONE').toUpperCase() === f.email)
    && (!q || [k.name, k.email, k.position, k.company, k.country].some((v) => String(v ?? '').toLowerCase().includes(q))));
  const counts = {}; dir.contacts.forEach((k) => { const s = String(k.email_status || 'NONE').toUpperCase(); counts[s] = (counts[s] || 0) + 1; });
  return `<h2>Contacts</h2>
    <p class="muted small"${tip('verified')}>${dir.contacts.length} people. Email status: VERIFIED is confirmed deliverable; RISKY / UNKNOWN / UNVERIFIED are never emailed automatically. Hover an email for its evidence.</p>
    <div class="filters"><input data-cf="q" placeholder="Name, email, company…" value="${esc(f.q)}">
      <select data-cf="email">${opt('', f.email, 'Any email status')}${Object.keys(counts).sort().map((s) => opt(s, f.email, `${s.toLowerCase()} · ${counts[s]}`)).join('')}</select></div>
    <div class="tbl-wrap"><table><thead><tr><th>Person</th><th>Company</th><th>Email</th><th>Last interaction</th><th class="num">Active opps</th></tr></thead>
    <tbody>${rows.map((k) => `<tr class="clickable" data-open="contact" data-id="${k.id}"><td>${esc(k.name || '—')}<div class="muted small">${esc(k.position || '')}</div></td>
      <td>${esc(k.company || '—')}</td><td title="${esc(provenanceTitle(k))}"><span class="small">${esc(k.email || '—')}</span> ${emailPill(k.email_status, k.email_kind)}${k.do_not_contact ? ` ${pill('do not contact', 'bad')}` : ''}</td>
      <td class="small">${esc(k.last_interaction ? fmtDay(k.last_interaction) : '—')}</td><td class="num">${esc(k.active_opps)}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">No contacts match.</td></tr>'}</tbody></table></div>`;
}

const QUICK_VERTICALS = [['', 'All'], ['TRAVEL_CONCIERGE', 'Partnerships'], ['BRAND_PRODUCTION', 'Production'], ['HOSPITALITY', 'Hospitality'], ['PRIVATE_UHNW', 'Private / UHNW'], ['CORPORATE', 'Corporate'], ['WEDDINGS_EVENTS', 'Weddings'], ['SPORTS_TALENT', 'Sports / Talent']];
function viewCompanies() {
  const dir = state.dir; if (!dir) return empty('Companies not loaded.');
  const f = state.companyF; const q = f.q.trim().toLowerCase();
  const rows = dir.companies.filter((c) => (!f.vertical || c.vertical === f.vertical) && (!f.market || c.market === f.market)
    && (!q || [c.name, c.website, c.country, c.city, c.company_type].some((v) => String(v ?? '').toLowerCase().includes(q))));
  const n = (v) => dir.companies.filter((c) => !v || c.vertical === v).length;
  return `<h2>Companies</h2>
    <p class="muted small">${dir.companies.length} accounts. Vertical is set automatically from the company type; you can reclassify any company from its record.</p>
    <div class="tabs">${QUICK_VERTICALS.map(([k, l]) => `<button data-cof="vertical" data-v="${k}" class="${f.vertical === k ? 'on' : ''}">${l} <span class="n">${n(k)}</span></button>`).join('')}</div>
    <div class="filters"><input data-cof="q" placeholder="Name, website, country…" value="${esc(f.q)}">
      <select data-cof="market">${opt('', f.market, 'All markets')}${Object.entries(MARKET_LABEL).map(([k, l]) => opt(k, f.market, l)).join('')}</select></div>
    <div class="tbl-wrap"><table><thead><tr><th>Company</th><th>Vertical</th><th>Market</th><th>Relationship</th><th class="num">Active</th><th class="num">People</th><th>Last activity</th></tr></thead>
    <tbody>${rows.map((c) => `<tr class="clickable" data-open="company" data-id="${c.id}"><td>${esc(c.name)}<div class="muted small">${esc(c.website || '')}</div></td>
      <td class="small">${esc(V(c.vertical))}${c.vertical_override ? ' <span class="faint">(set by you)</span>' : ''}</td><td class="small">${esc(M(c.market))}${c.country ? ` · ${esc(c.country)}` : ''}</td>
      <td class="small">${esc(c.relationship_status || '—')}</td><td class="num">${esc(c.active_opps)}</td><td class="num">${esc(c.contacts)}</td>
      <td class="small">${esc(c.last_activity ? shortDay(c.last_activity) : '—')}</td></tr>`).join('') || '<tr><td colspan="7" class="muted">No companies match.</td></tr>'}</tbody></table></div>`;
}

// ---------------------------------------------------------------- PREVIOUS RELATIONSHIPS (NOYA Gmail history)
function relStatusChips(g) {
  const cur = g.review?.status; const sug = relSuggested(g);
  return `<div class="chips" role="group" aria-label="Set status">${REL_ORDER.map((k) => `<button class="chip ${cur === k ? 'on' : ''} ${!cur && sug === k ? 'sug' : ''}" data-rel-status="${k}" data-id="${esc(g.key)}" title="${esc(REL_STATUS[k][2])}">${esc(REL_STATUS[k][0])}</button>`).join('')}</div>`;
}
function relCard(g, review = false) {
  const [label, cls, why] = REL_STATE[g.state] || [g.state, '', ''];
  const rv = g.review || {}; const sug = relSuggested(g);
  const rec = g.company_id ? `data-open="company" data-id="${g.company_id}"` : g.contact_id ? `data-open="contact" data-id="${g.contact_id}"` : '';
  const draftTarget = g.contact_id ? `data-contact="${g.contact_id}"` : g.company_id ? `data-company="${g.company_id}"` : '';
  const lastBy = g.last_in && (!g.last_out || g.last_in > g.last_out) ? 'them' : 'NOYA';
  return `<article class="card rel${review ? ' review' : ''}">
    <div class="card-head"><div><div class="co">${esc(g.name)}</div><div class="muted small">${esc([g.company && g.company !== g.name ? g.company : '', g.domain].filter(Boolean).join(' · '))}</div></div>
      <div class="pills">${rv.status ? `<span class="pill ${REL_STATUS[rv.status]?.[1] || ''}" title="Set by you ${esc(rv.status_at ? shortDay(rv.status_at) : '')}">You: ${esc(REL_STATUS[rv.status]?.[0] || rv.status)}</span>` : sug ? `<span class="pill ghost" title="${esc(rv.suggested_reason || 'From the email facts')}">Suggested: ${esc(REL_STATUS[sug]?.[0] || sug)}</span>` : ''}
        <span class="pill ${cls}" title="${esc(why)}">${esc(label)}</span>${g.in_crm ? pill('in CRM', 'ok') : pill('not in CRM', 'warn')}${g.opportunity_status ? pill(S(g.opportunity_status)) : ''}</div></div>
    <div class="small"><b>Facts</b> · ${g.sent} sent by NOYA · ${g.received} from them · last ${esc(shortDay(g.last_at))} by ${lastBy} · ${g.threads} thread${g.threads > 1 ? 's' : ''} since ${esc(shortDay(g.first_at))}</div>
    ${g.subject ? `<div class="small mt6"><b>Subject:</b> ${esc(g.subject)}</div>` : ''}
    ${g.snippet ? `<div class="email small"><div class="faint">Latest preview (verbatim)</div><pre>${esc(unesc(g.snippet))}</pre></div>` : ''}
    ${rv.summary ? `<div class="ai small"><div class="faint">AI summary — from subjects and previews only; check the thread before acting</div>${esc(rv.summary)}${rv.their_position ? `<div class="mt6"><b>What they said:</b> ${esc(rv.their_position)}</div>` : ''}${sug && !rv.status && rv.suggested_reason ? `<div class="faint mt6">Why ${esc(REL_STATUS[sug]?.[0] || sug)}: ${esc(rv.suggested_reason)}</div>` : ''}</div>` : `<div class="small faint">${esc(why)}</div>`}
    ${g.received > 0 ? relStatusChips(g) : ''}
    <div class="btn-row mt6">${gmailLink(g.reply_thread || g.last_thread, 'Open in Gmail').replace('<a ', '<a class="btn small" ')}
      ${g.in_crm ? `<button class="btn small" ${rec}>Open record</button><button class="btn small primary" data-modal="draft-request" data-channel="EMAIL" data-type="${g.state === 'FOLLOW_UP' ? 'FOLLOW_UP' : 'RECONNECTION'}" ${draftTarget}>Draft ${g.state === 'FOLLOW_UP' ? 'follow-up' : 'reconnect'}</button>`
        : `<button class="btn small primary" data-modal="history-add" data-id="${esc(g.key)}">Add to CRM</button>`}
      ${g.received > 0 ? '' : g.dismissed ? `<button class="btn small ghost" data-hist-act="RESTORE" data-id="${esc(g.key)}">Restore</button>` : `<button class="btn small ghost" data-hist-act="DISMISS" data-id="${esc(g.key)}" title="Not relevant — hide it (the email history is kept)">Not relevant</button>`}
      ${g.received > 0 && g.dismissed ? `<button class="btn small ghost" data-hist-act="RESTORE" data-id="${esc(g.key)}">Restore</button>` : ''}
    </div></article>`;
}
function relReview(rows) {
  if (!rows.length) return empty('All two-way relationships have a status. See Reviewed.');
  const i = Math.min(state.relF.i || 0, rows.length - 1);
  return `<div class="review-nav"><span class="small"><b>${i + 1}</b> of ${rows.length} to review</span>
      <span><button class="btn small ghost" data-rel-step="-1" ${i === 0 ? 'disabled' : ''}>Back</button><button class="btn small ghost" data-rel-step="1" ${i >= rows.length - 1 ? 'disabled' : ''}>Skip</button></span></div>
    ${relCard(rows[i], true)}`;
}
function viewRelationships() {
  const rel = state.rel; if (!rel) return empty(`Email history not loaded${state.errors.rel ? `: ${state.errors.rel}` : ''}.`);
  const f = state.relF; const q = f.q.trim().toLowerCase(); const all = rel.groups;
  const live = all.filter((g) => !g.dismissed);
  const toReview = live.filter((g) => g.received > 0 && !g.review?.status)
    // Reply-now first (newest first); reconnects by depth of the exchange (their emails), then recency.
    .sort((a, b) => relRank(a) - relRank(b) || (relSuggested(a) === 'RECONNECT' ? b.received - a.received : 0) || String(b.last_at).localeCompare(String(a.last_at)));
  const tabs = {
    REVIEW: toReview,
    REVIEWED: all.filter((g) => g.review?.status).sort((a, b) => REL_ORDER.indexOf(a.review.status) - REL_ORDER.indexOf(b.review.status)),
    REPLIED: live.filter((g) => g.received > 0 && g.state === 'REPLIED'),
    RECONNECT: live.filter((g) => g.received > 0 && g.state !== 'REPLIED'),
    NOT_IN_CRM: live.filter((g) => g.received > 0 && !g.in_crm),
    NO_REPLY: live.filter((g) => g.received === 0),
    DISMISSED: all.filter((g) => g.dismissed),
    ALL: all,
  };
  const labels = { REVIEW: 'Review', REVIEWED: 'Reviewed', REPLIED: 'They wrote last', RECONNECT: 'Worth reconnecting', NOT_IN_CRM: 'Not in CRM yet', NO_REPLY: 'Emailed, no reply', DISMISSED: 'Hidden', ALL: 'All' };
  const intro = {
    REVIEW: 'One at a time, most urgent first. Tap a status — it saves and moves to the next. Nothing is ever sent.',
    REVIEWED: 'Relationships you have given a status. Change it any time.',
    REPLIED: 'People who answered NOYA and wrote last. Check whether you owe them a reply.',
    RECONNECT: 'Real two-way conversations from the last 12 months. Restart them personally — never with a cold introduction.',
    NOT_IN_CRM: 'Real conversations with people who are not in the CRM yet. Add the ones that matter; hide the rest.',
    NO_REPLY: 'People NOYA emailed who never answered. HQ will not send them another cold introduction.',
    DISMISSED: 'Hidden as not relevant. The email history is kept; restore any time.',
    ALL: 'Everything found in NOYA Gmail.',
  }[f.tab];
  const rows = (tabs[f.tab] || all).filter((g) => !q || [g.name, g.domain, g.subject, g.company, ...(g.emails || [])].some((v) => String(v ?? '').toLowerCase().includes(q)));
  const st = rel.state || {};
  return `<h2>Past relationships</h2>
    <p class="muted small">From NOYA's own Gmail (noya@noyaconcierge.com): ${esc(st.scanned ?? '—')} emails since ${esc(fmtDay(st.window_start))}, headers only. ${st.last_run_at ? `Last sync ${esc(fmtDate(st.last_run_at))}.` : ''} Every item links to the real email thread.</p>
    <div class="tabs">${Object.keys(tabs).map((k) => `<button data-rf="tab" data-v="${k}" class="${f.tab === k ? 'on' : ''}">${labels[k]} <span class="n">${tabs[k].length}</span></button>`).join('')}</div>
    <div class="filters"><input data-rf="q" placeholder="Name, company, domain, subject…" value="${esc(f.q)}"></div>
    <p class="muted small">${esc(intro)}</p>
    ${f.tab === 'REVIEW' && !q ? relReview(rows) : (rows.slice(0, 80).map((g) => relCard(g)).join('') || empty('Nothing here.'))}
    ${rows.length > 80 && f.tab !== 'REVIEW' ? `<p class="small faint">Showing 80 of ${rows.length}. Narrow with the filter.</p>` : ''}`;
}

// ---------------------------------------------------------------- LINKEDIN
const LI_OPTIONS = [
  ['1. Your LinkedIn data export + draft here + you send (recommended)', 'Your 1st-degree connections file (name, company, position, profile link, connected date; email only if the contact allowed it)', 'Nothing. HQ drafts; you open the profile and send yourself', 'No password, cookie or token is stored. You upload the file; only the needed columns are kept', 'Fully compliant — it is your own data export', '£0', '£0'],
  ['2. Official "Sign in with LinkedIn" API', 'Your own name, photo and email only', 'Posts to your own feed only', 'OAuth token kept server-side', 'Compliant, but cannot read connections or send messages (those APIs are partner-only)', '£0', '£0'],
  ['3. Sales Navigator (manual use)', 'Better search, lead lists, InMail credits inside LinkedIn', 'InMail by you, inside LinkedIn', 'None in HQ', 'Compliant; no API access for NOYA (SNAP partner programme is closed)', 'Paid — verify current price before any decision', 'None'],
  ['4. Browser-cookie automation tools (Phantombuster, Expandi, Dripify…)', 'Everything your account can see', 'Automated invites and messages', 'Requires your session cookie — account-takeover risk', 'Breaks LinkedIn User Agreement; account restriction risk. Not recommended', 'Paid — verify', 'Paid tiers'],
];
function viewLinkedin() {
  const dir = state.dir; if (!dir) return empty('LinkedIn data not loaded.');
  const conns = dir.connections; const f = state.netF; const q = f.q.trim().toLowerCase();
  const acts = (state.ov?.actions || []).filter((a) => a.kind === 'LINKEDIN');
  const due = conns.filter((c) => c.next_follow_up_at && c.next_follow_up_at <= todayKey() && c.status !== 'DO_NOT_CONTACT');
  // Evidence score: only real links count (active deal, email history, CRM person, CRM company). Strength is never inferred.
  const score = (c) => (c.active_opps > 0 ? 4 : 0) + (c.email_history > 0 ? 3 : 0) + (c.matched_contact_id ? 2 : 0) + (c.matched_company_id ? 1 : 0);
  const lists = {
    known: conns.filter((c) => score(c) > 0).sort((a, b) => score(b) - score(a) || String(a.name).localeCompare(String(b.name))),
    warm: conns.filter((c) => c.active_opps > 0).sort((a, b) => b.active_opps - a.active_opps),
    matched: conns.filter((c) => c.matched_company_id),
    emailed: conns.filter((c) => c.email_history > 0),
    followup: due,
    all: conns,
  };
  const rows = (lists[f.only] || conns).filter((c) => (!f.vertical || c.vertical === f.vertical) && (!q || [c.name, c.company, c.position].some((v) => String(v ?? '').toLowerCase().includes(q))));
  const drafts = (dir.drafts || []).filter((x) => x.channel === 'LINKEDIN' || x.channel === 'INSTAGRAM' || x.channel === 'WHATSAPP' || x.channel === 'EMAIL');
  return `<h2>LinkedIn</h2>
    <p class="muted small">Messages here are sent by you, personally, from LinkedIn. HQ prepares the words, opens the profile and books the follow-up. Nothing is ever sent automatically, and your LinkedIn password is never asked for or stored.</p>
    <section class="panel"><header><h3>Messages ready to send (${acts.length})</h3><button class="btn small ghost" data-go="outreach" data-otab="LINKEDIN">All in Outreach</button></header>
      <div class="body">${acts.slice(0, 3).map(manualChannelCard).join('') || '<div class="empty">No LinkedIn messages waiting.</div>'}${acts.length > 3 ? `<button class="linkish" data-go="outreach" data-otab="LINKEDIN">Show all ${acts.length}</button>` : ''}</div></section>
    <section class="panel mt8"><header><h3>Drafts (${drafts.length})</h3><span class="small faint">requested from HQ · written by the drafting workflow</span></header>
      <div class="body">${drafts.map(draftRow).join('') || '<div class="empty">No drafts. Use "Draft message" on any person, company or connection.</div>'}</div></section>
    <section class="panel mt8"><header><h3>People you already know</h3><span class="small faint">${conns.length} connections imported</span></header>
      <div class="body">${conns.length ? `
        <div class="tabs">${[['known', 'Linked to NOYA'], ['warm', 'At active prospects'], ['emailed', 'Also emailed NOYA'], ['followup', 'Follow-up due'], ['matched', 'At known companies'], ['all', 'All']].map(([k, l]) => `<button data-nf="only" data-v="${k}" class="${f.only === k ? 'on' : ''}">${l} <span class="n">${lists[k].length}</span></button>`).join('')}</div>
        <div class="filters"><input data-nf="q" placeholder="Name, company, role…" value="${esc(f.q)}"><select data-nf="vertical">${opt('', f.vertical || '', 'All verticals')}${Object.entries(VERTICAL_LABEL).map(([k, l]) => opt(k, f.vertical || '', l)).join('')}</select></div>
        <div class="tbl-wrap"><table><thead><tr><th>Person</th><th>Company</th><th>Status</th><th>Relationship</th><th>Next follow-up</th></tr></thead><tbody>
        ${rows.slice(0, 200).map((c) => `<tr class="clickable" data-open="connection" data-id="${c.id}"><td>${esc(c.name || '—')}<div class="muted small">${esc(c.position || '')}</div>${(c.evidence || []).length ? `<div class="small evidence">${(c.evidence || []).map((e) => `<div>✓ ${esc(e)}</div>`).join('')}</div>` : ''}</td>
          <td>${esc(c.company || '—')}${c.active_opps ? ` ${pill(`${c.active_opps} active opp${c.active_opps > 1 ? 's' : ''}`, 'info')}` : ''}${c.email_history ? ` ${pill('emailed before', 'ok')}` : ''}${c.matched_contact_id ? ` ${pill('in CRM')}` : ''}</td><td>${pill(sentence(c.status.replace(/_/g, ' ')))}</td>
          <td class="small" title="No data source measures relationship strength; it stays UNKNOWN until you describe how you know them.">${c.how_we_know ? esc(c.how_we_know) : 'Unknown'}</td>
          <td class="small">${esc(c.next_follow_up_at ? fmtDay(c.next_follow_up_at) : '—')}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">No connections match.</td></tr>'}</tbody></table></div>
        ${rows.length > 200 ? `<p class="small faint">Showing 200 of ${rows.length}. Narrow with the filter.</p>` : ''}`
        : `<div class="empty">No connections imported yet. Import your LinkedIn export below to see which prospects you already know.</div>`}</div></section>
    <section class="panel mt8"><header><h3>Import your LinkedIn connections</h3></header><div class="body">
      <ol class="small steps"><li>On LinkedIn: <b>Me → Settings &amp; Privacy → Data privacy → Get a copy of your data</b>.</li>
        <li>Choose <b>Connections</b> only (not the full archive, not messages), request it. LinkedIn emails a link (usually within 10–30 minutes).</li>
        <li>Download and unzip; choose <b>Connections.csv</b> below. It is read in your browser; only name, company, position, profile link and connected date are saved. Re-importing updates, never duplicates.</li></ol>
      <label class="btn">Choose Connections.csv<input type="file" id="li-file" accept=".csv,text/csv" hidden></label>
    </div></section>
    <details class="panel mt8"><summary><b>How HQ connects to LinkedIn — options and approval</b> (method 1 is in use; nothing else is connected)</summary><div class="body">
      <div class="tbl-wrap"><table><thead><tr><th>Option</th><th>Can read</th><th>Can write / send</th><th>Security</th><th>Platform / compliance risk</th><th>Monthly</th><th>Usage</th></tr></thead>
      <tbody>${LI_OPTIONS.map((r) => `<tr>${r.map((x, i) => `<td class="small">${i === 0 ? `<b>${esc(x)}</b>` : esc(x)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>
      <p class="small">No other method is connected or paid for without your explicit approval.</p></div></details>`;
}
function draftRow(x) {
  const st = { REQUESTED: pill('Drafting…', 'info'), DRAFTING: pill('Drafting…', 'info'), READY: pill('Ready', 'ok'), PROVIDER_UNAVAILABLE: pill('Provider unavailable', 'warn') }[x.status] || pill(x.status);
  const who = x.connection_id ? state.dir.connections.find((c) => c.id === x.connection_id)?.name : x.company_id ? company(x.company_id)?.name : '';
  const url = x.connection_id ? state.dir.connections.find((c) => c.id === x.connection_id)?.profile_url : x.opportunity_id ? ready(x.opportunity_id).linkedin : null;
  return `<div class="row"><div class="t">${esc(who || 'Message')} ${st} ${pill(sentence(x.message_type.replace(/_/g, ' ')))} ${pill(x.voice === 'ADAM_PERSONAL' ? 'Adam personally' : 'NOYA')}</div>
    <div class="meta">${esc(sentence(x.channel))} · requested ${esc(fmtDate(x.requested_at))}${x.quality_issues && x.quality_issues.length ? ` · checks: ${esc([].concat(x.quality_issues).join(', '))}` : ''}</div>
    ${x.draft ? `<div class="email"><pre>${esc(x.draft)}</pre></div>` : x.status === 'PROVIDER_UNAVAILABLE' ? '<p class="small muted">The AI provider was unavailable. Retry, or write it yourself with Edit.</p>' : '<p class="small muted">Being written — refresh in a few minutes.</p>'}
    <div class="btn-row">${x.draft ? `<button class="btn small" data-copy="${esc(x.draft)}">Copy</button>` : ''}
      ${url && x.channel === 'LINKEDIN' ? `<a class="btn small" href="${esc(url)}" target="_blank" rel="noopener noreferrer">Open in LinkedIn</a>` : ''}
      ${['READY', 'PROVIDER_UNAVAILABLE'].includes(x.status) ? `<button class="btn small" data-modal="draft-edit" data-id="${x.id}">Edit</button><button class="btn small primary" data-modal="touch" data-channel="${x.channel === 'INSTAGRAM' ? 'INSTAGRAM_DM' : x.channel}" data-opp="${x.opportunity_id || ''}" data-conn="${x.connection_id || ''}" data-draft="${x.id}">Mark sent</button>` : ''}
      ${x.status === 'PROVIDER_UNAVAILABLE' ? `<button class="btn small" data-draft-act="RETRY" data-id="${x.id}">Retry</button>` : ''}
      <button class="btn small ghost" data-draft-act="DISCARD" data-id="${x.id}">Discard</button></div></div>`;
}

// ---------------------------------------------------------------- FINANCE
const FIN_STATUS = { DRAFT: '', SENT: 'info', PART_PAID: 'warn', PAID: 'ok', OVERDUE: 'bad', CANCELLED: '' };
function viewFinance() {
  const ins = state.ins; if (!ins) return empty(`Finance not loaded${state.errors.ins ? `: ${state.errors.ins}` : ''}.`);
  const f = ins.finance; const recs = f.records; const byc = cur(f.by_currency);
  const def = (k, t) => `<div class="def"><b${tip(k)}>${t}</b><span>${esc(HELP[k])}</span></div>`;
  const line = (k, v, kind, help) => `<div class="money-line"><span${help ? tip(help) : ''}>${k}${lbl(kind)}</span><span class="v">${v}</span></div>`;
  return `<h2>Finance</h2>
    <div class="btn-row"><button class="btn primary" data-modal="finance">+ New record</button></div>
    <div class="ov-grid">
      <section class="panel"><header><h3>Money by currency</h3><span class="small faint">currencies are never added together</span></header><div class="body">
        ${byc.length ? byc.map((c) => `<h4>${esc(c.currency)}</h4>${line('Won', c.won != null ? esc(money(c.won, c.currency)) : '<span class="muted">none</span>', 'ACTUAL', 'won')}
          ${line('Collected', c.collected ? esc(money(c.collected, c.currency)) : '<span class="muted">none</span>', 'ACTUAL', 'collected')}
          ${line('Outstanding', c.outstanding ? esc(money(c.outstanding, c.currency)) : '<span class="muted">none</span>', 'ACTUAL', 'outstanding')}
          ${c.overdue ? line('of which overdue', `<span class="bad-text">${esc(money(c.overdue, c.currency))}</span>`, 'ACTUAL') : ''}`).join('')
          : line('Won / collected / outstanding', '<span class="muted">no finance records yet</span>', 'ACTUAL', 'won')}
        ${cur(f.pipeline).map((p) => line(`Pipeline (${esc(p.currency)})`, `${esc(money(p.amount, p.currency))} <span class="faint small">(${p.opportunities} opps)</span>`, 'ESTIMATE', 'pipeline')).join('')}
        ${f.pipeline_unknown ? line('Pipeline without an estimate', `${esc(f.pipeline_unknown)} opps`, 'UNKNOWN', 'unknown') : ''}
        ${line('Forecast', '<span class="muted">not set</span>', 'UNKNOWN', 'forecast')}
      </div></section>
      <section class="panel"><header><h3>What each word means</h3></header><div class="body">
        ${def('collected', 'Collected')}${def('outstanding', 'Outstanding')}${def('won', 'Won')}${def('pipeline', 'Pipeline')}${def('forecast', 'Forecast')}
        <p class="small faint mt6">A record starts as Draft. Mark it Sent when the invoice goes out; Part-paid, Paid and Overdue follow automatically from payments and the due date. An issued amount cannot be edited — cancel and re-issue instead.</p>
      </div></section></div>
    <h3>Records (${recs.length})</h3>
    ${recs.length ? `<div class="tbl-wrap"><table><thead><tr><th>Client</th><th>What</th><th>Status</th><th class="num">Gross</th><th class="num">Paid</th><th class="num">Outstanding</th><th>Due</th><th></th></tr></thead><tbody>
      ${recs.map((r) => `<tr><td>${esc(r.company || '—')}<div class="muted small">${esc(r.invoice_reference || '')}</div></td><td class="small">${esc(r.description || r.revenue_type || '—')}</td>
        <td>${pill(sentence(r.status.replace('_', ' ')), FIN_STATUS[r.status])}</td><td class="num">${esc(money(r.gross_amount, r.currency))}</td><td class="num">${esc(money(r.amount_paid, r.currency))}</td>
        <td class="num">${esc(money(r.outstanding, r.currency))}</td><td class="small">${esc(r.due_at ? fmtDay(r.due_at) : '—')}</td>
        <td><div class="btn-row">${['SENT', 'PART_PAID', 'OVERDUE'].includes(r.status) ? `<button class="btn small primary" data-modal="payment" data-id="${r.id}">Record payment</button>` : ''}
          ${r.status !== 'CANCELLED' && r.status !== 'PAID' ? `<button class="btn small" data-modal="finance" data-id="${r.id}">Edit</button>` : ''}</div></td></tr>`).join('')}</tbody></table></div>`
      : empty('No finance records yet. Add one when a client confirms — Won and Collected stay empty until then; nothing is estimated.')}
    <h3>Payments received (${f.payments.length})</h3>
    ${f.payments.length ? `<div class="tbl-wrap"><table><thead><tr><th>Date</th><th>Client</th><th class="num">Amount</th><th>Method</th><th>Reference</th><th>Recorded by</th></tr></thead><tbody>
      ${f.payments.map((p) => `<tr><td>${esc(fmtDay(p.paid_at))}</td><td>${esc(recs.find((r) => r.id === p.revenue_id)?.company || '—')}</td><td class="num">${esc(money(p.amount, p.currency))}</td><td class="small">${esc(p.method || '—')}</td><td class="small">${esc(p.reference || '—')}</td><td class="small">${esc(p.recorded_by)}</td></tr>`).join('')}</tbody></table></div>`
      : '<p class="muted small">None recorded.</p>'}`;
}

// ---------------------------------------------------------------- SYSTEM COSTS
const COST_TYPE = { FIXED_MONTHLY: 'Fixed monthly', PAY_AS_YOU_GO: 'Pay as you go', USAGE_LIMITED: 'Usage limited', FREE: 'Free', UNKNOWN: 'Unknown — verify before scale' };
function viewCosts() {
  const ins = state.ins; if (!ins) return empty('Cost data not loaded.');
  const sv = ins.services.filter((s) => s.status !== 'RETIRED');
  const active = sv.filter((s) => s.status === 'ACTIVE');
  const pending = sv.filter((s) => ['PROPOSED', 'AWAITING_APPROVAL'].includes(s.status));
  const fixed = {}; active.filter((s) => s.cost_type === 'FIXED_MONTHLY' && s.monthly_cost != null).forEach((s) => { fixed[s.currency || '?'] = (fixed[s.currency || '?'] || 0) + Number(s.monthly_cost); });
  const unknown = active.filter((s) => s.cost_type === 'UNKNOWN' || (s.cost_type !== 'FREE' && s.monthly_cost == null));
  const payg = active.filter((s) => s.cost_type === 'PAY_AS_YOU_GO');
  const usageBased = active.filter((s) => ['PAY_AS_YOU_GO', 'USAGE_LIMITED'].includes(s.cost_type));
  const fixedNoAmount = active.filter((s) => s.cost_type === 'FIXED_MONTHLY' && s.monthly_cost == null);
  const u = (p) => (ins.cost_usage || []).find((x) => x.period === p) || {};
  const usage = [['Google searches (Serper)', 'serper_searches'], ['Website reads (Firecrawl)', 'firecrawl_calls'], ['Email checks (Hunter)', 'hunter_checks'], ['AI research calls', 'ai_calls_discovery'], ['AI reply reading', 'reply_ai_calls'], ['CEO briefs', 'brief_runs']];
  const b = ins.budget || {};
  return `<h2>System costs</h2>
    <p class="muted small">Every service NOYA depends on, what it costs and what breaks without it. A cost is only filled in from an invoice or plan page — otherwise it stays UNKNOWN.</p>
    <div class="ov-grid3">
      <section class="panel"><header><h3>Known fixed monthly</h3></header><div class="body">${Object.keys(fixed).length ? Object.entries(fixed).map(([c, v]) => `<div class="money-line"><span>${esc(c)}${lbl('ACTUAL')}</span><span class="v">${esc(money(v, c))}</span></div>`).join('') : '<div class="muted">None confirmed yet</div>'}</div></section>
      <section class="panel"><header><h3>Unknown exposure</h3></header><div class="body"><div class="big bad-text">${unknown.length}</div><div class="small">service${unknown.length === 1 ? '' : 's'} with cost UNKNOWN — verify before scale</div></div></section>
      <section class="panel"><header><h3>Pay as you go</h3></header><div class="body"><div class="big">${payg.length}</div><div class="small">${esc(payg.map((s) => s.service).join(', ') || 'none')}</div>${b.monthly_budget_usd ? `<div class="small faint mt6">AI spend cap configured: USD ${esc(b.monthly_budget_usd)}/month (cheap models only above 100%).</div>` : ''}</div></section>
    </div>
    <h3>Cost reconciliation</h3>
    <div class="tbl-wrap"><table><tbody>
      <tr><th>Confirmed fixed monthly</th><td class="small">${Object.keys(fixed).length ? Object.entries(fixed).map(([c, v]) => esc(money(v, c))).join(' · ') : 'None confirmed.'}${fixedNoAmount.length ? ` Fixed, amount not yet read: ${esc(fixedNoAmount.map((s) => s.service).join(', '))}.` : ''}</td></tr>
      <tr><th>Usage-based</th><td class="small">${usageBased.map((s) => `${esc(s.service)} <span class="faint">(${esc(s.usage_limit || s.usage_cost || COST_TYPE[s.cost_type])})</span>`).join(' · ') || '—'}</td></tr>
      <tr><th>Remaining UNKNOWN</th><td class="small">${esc(unknown.map((s) => s.service).join(', ') || 'None')}</td></tr>
      <tr><th>Likely to grow with volume</th><td class="small">${active.filter((s) => s.scale_risk && !/healthy/i.test(s.scale_risk)).map((s) => `<div><b>${esc(s.service)}:</b> ${esc(s.scale_risk)}</div>`).join('') || '—'}</td></tr>
      <tr><th>Downgrade / remove candidates</th><td class="small">${active.filter((s) => s.downgrade_note && !/^Keep/.test(s.downgrade_note) && !/^Already/.test(s.downgrade_note)).map((s) => `<div><b>${esc(s.service)}:</b> ${esc(s.downgrade_note)}</div>`).join('') || '—'}</td></tr>
    </tbody></table></div>
    <h3>Paid services awaiting your approval (${pending.length})</h3>
    ${pending.length ? pending.map((s) => `<div class="row"><div class="t">${esc(s.service)}</div><div class="small">${esc(s.purpose)} · ${esc(s.usage_cost || '')}</div></div>`).join('') : '<p class="muted small">None. Nothing paid is pending.</p>'}
    <div class="banner small">Rule: before any paid service, plan upgrade, API credit or connector is added, HQ shows the tool, purpose, why the current stack cannot do it, the free option, the paid option, monthly and usage cost, and what happens if NOYA stops paying — then waits for your approval.</div>
    <h3>How often the automations run</h3>
    <div class="tbl-wrap"><table><thead><tr><th>Automation</th><th>When it runs</th><th class="num">Runs / month (max)</th></tr></thead><tbody>
      <tr><td>Reply tracking (Gmail)</td><td>Every 30 minutes (run it now from n8n → workflow 13 → Manual Sync)</td><td class="num">~1,440</td></tr>
      <tr><td>Email history sync (Gmail)</td><td>Every 3 hours, 07:00–22:00</td><td class="num">~180</td></tr>
      <tr><td>Message drafting</td><td>Only when you ask for a draft, plus 2 safety checks a day</td><td class="num">~60 + your requests</td></tr>
      <tr><td>Other workflows</td><td>See n8n → Executions</td><td class="num">UNKNOWN</td></tr>
    </tbody></table></div>
    <p class="src">n8n bills by runs (executions) on most plans; the plan's monthly allowance is UNKNOWN until the plan page is provided.</p>
    <h3>Usage (actual counts)</h3>
    <div class="tbl-wrap"><table><thead><tr><th>What</th><th class="num">Today</th><th class="num">7 days</th><th class="num">30-day projection</th></tr></thead><tbody>
      ${usage.map(([l, k]) => `<tr><td>${l}</td><td class="num">${esc(u('TODAY')[k] ?? '—')}</td><td class="num">${esc(u('7_DAYS')[k] ?? '—')}</td><td class="num">${esc(u('30_DAY_PROJECTION')[k] ?? '—')}</td></tr>`).join('')}</tbody></table></div>
    <p class="src">Money for usage is UNKNOWN until unit prices are entered from invoices. ${esc(u('TODAY').note || '')}</p>
    <h3>Dependency register (${sv.length})</h3>
    ${Object.keys(COST_TYPE).map((t) => { const list = sv.filter((s) => s.cost_type === t); if (!list.length) return '';
      return `<h4>${esc(COST_TYPE[t])} (${list.length})</h4><div class="list">${list.map((s) => `<details class="row"><summary><b>${esc(s.service)}</b> — ${esc(s.purpose)} ${s.verified ? pill('verified', 'ok') : pill('verify', 'warn')}</summary>
        <div class="grid2 small">
          <div class="kv"><div class="k">Plan</div><div class="v">${esc(s.current_plan || 'UNKNOWN')}</div></div>
          <div class="kv"><div class="k">Monthly cost</div><div class="v">${s.monthly_cost != null ? esc(money(s.monthly_cost, s.currency || '')) : 'UNKNOWN'}</div></div>
          <div class="kv"><div class="k">Usage cost</div><div class="v">${esc(s.usage_cost || '—')}</div></div>
          <div class="kv"><div class="k">Limit</div><div class="v">${esc(s.usage_limit || 'UNKNOWN')}</div></div>
          <div class="kv"><div class="k">Used by</div><div class="v">${esc(s.used_by || '—')}</div></div>
          <div class="kv"><div class="k">Owner</div><div class="v">${esc(s.owner)}</div></div>
          <div class="kv"><div class="k">If removed</div><div class="v">${esc(s.breaks_if_removed || '—')}</div></div>
          <div class="kv"><div class="k">Alternative</div><div class="v">${esc(s.alternative || '—')}</div></div>
          <div class="kv"><div class="k">Credential kept in</div><div class="v">${esc(s.credentials_location || '—')}</div></div>
          <div class="kv"><div class="k">Renewal</div><div class="v">${esc(s.renewal_date ? fmtDay(s.renewal_date) : 'UNKNOWN')}</div></div>
        </div>${s.verification_note ? `<p class="small faint"><b>Evidence:</b> ${esc(s.verification_note)}</p>` : ''}${s.scale_risk ? `<p class="small"><b>As volume grows:</b> ${esc(s.scale_risk)}</p>` : ''}${s.downgrade_note ? `<p class="small"><b>Downgrade / remove:</b> ${esc(s.downgrade_note)}</p>` : ''}
        <div class="btn-row"><button class="btn small" data-modal="service-edit" data-id="${s.id}">Update from invoice</button></div></details>`).join('')}</div>`; }).join('')}`;
}

// ---------------------------------------------------------------- MARKETS / GROWTH
function viewMarkets() {
  const ins = state.ins; if (!ins) return empty('Market data not loaded.');
  const mk = ins.markets.filter((m) => m.companies || m.active_opps_origin || m.active_opps_destination);
  const pipe = (p) => cur(p).map((x) => esc(money(x.amount, x.currency))).join(' · ') || '—';
  return `<h2>Markets</h2>
    <p class="muted small">Origin market = where the client or partner is based. Destination = where NOYA delivers. A bridge is the route from one to the other (for example Europe → Egypt). "Unknown" means the company's country is not recorded yet.</p>
    <div class="tbl-wrap"><table><thead><tr><th>Market</th><th class="num">Companies</th><th class="num">People</th><th class="num" title="Active opportunities with clients based here">Active (clients from)</th><th class="num" title="Active opportunities delivered here">Active (delivered in)</th><th class="num">Contacted</th><th class="num">Positive replies</th><th class="num">Calls+</th><th class="num">Won</th><th class="num">Pipeline${lbl('ESTIMATE')}</th></tr></thead><tbody>
      ${mk.map((m) => `<tr class="clickable" data-market="${m.market}"><td><b>${esc(M(m.market))}</b><div class="muted small">${esc(Object.entries(m.verticals || {}).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([v, n]) => `${V(v)} ${n}`).join(' · '))}</div></td>
        <td class="num">${m.companies}</td><td class="num">${m.contacts}</td><td class="num">${m.active_opps_origin}</td><td class="num">${m.active_opps_destination}</td><td class="num">${m.contacted}</td><td class="num">${m.positive_replies}</td><td class="num">${m.calls}</td><td class="num">${m.won}</td><td class="num small">${pipe(m.pipeline)}</td></tr>`).join('')}</tbody></table></div>
    <h3>Bridges</h3>
    <div class="tbl-wrap"><table><thead><tr><th>Route</th><th class="num">Active</th><th class="num">Contacted</th><th class="num">Positive</th><th class="num">Calls+</th></tr></thead><tbody>
      ${ins.bridges.map((b) => `<tr><td>${esc(b.route.split(' → ').map(M).join(' → '))}</td><td class="num">${b.active}</td><td class="num">${b.contacted}</td><td class="num">${b.positive}</td><td class="num">${b.calls}</td></tr>`).join('')}</tbody></table></div>
    <p class="src">Click a market to open the pipeline filtered to it.</p>`;
}

function growthActions() {
  const ins = state.ins; const ov = state.ov; const dir = state.dir; const out = [];
  const unk = ins.markets.find((m) => m.market === 'UNKNOWN');
  if (ov?.actions.some((a) => a.prio === 'P1')) out.push(['Answer the P1 replies first', 'A prospect who asked for a meeting is the closest thing to revenue in the system.', 'overview']);
  if (ins.stalled.length) out.push([`Re-open ${ins.stalled.length} stalled conversation${ins.stalled.length > 1 ? 's' : ''}`, 'They already engaged with NOYA; a short, useful follow-up costs minutes and restarts the most advanced deals.', 'growth']);
  if (ov?.scorecard.approvals_ready.n) out.push([`Clear ${ov.scorecard.approvals_ready.n} outreach approvals`, 'Each is drafted to a verified person. Unapproved drafts produce nothing.', 'outreach']);
  if (dir && !dir.connections.length) out.push(['Import your LinkedIn connections', 'Your existing relationships are currently invisible to HQ. A warm introduction is the shortest route to a first conversation.', 'linkedin']);
  if (unk && unk.companies) out.push([`Add the country for ${unk.companies} companies`, 'Without it their market is Unknown and the Europe / GCC → Egypt picture is incomplete.', 'companies']);
  const noVal = ins.finance.pipeline_unknown; if (noVal) out.push([`Put a value on the top opportunities (${noVal} have none)`, 'Unvalued deals cannot be prioritised by money. Estimates stay labelled ESTIMATE.', 'pipeline']);
  return out.slice(0, 6);
}
function viewGrowth() {
  const ins = state.ins; if (!ins) return empty('Growth data not loaded.');
  const caveat = (n) => (n < 10 ? ' <span class="faint small">(too early to judge — fewer than 10 contacted)</span>' : '');
  return `<h2>Growth</h2>
    <p class="muted small">What is working, what is stuck and what to do next — from real records only. Small samples are marked; nothing is extrapolated.</p>
    <section class="panel"><header><h3>Recommended next actions</h3></header><div class="body">
      ${growthActions().map(([t, why, go]) => `<div class="q-row"><div class="prio P2">→</div><div><div class="q-act">${esc(t)}</div><div class="q-meta"><b>Why:</b> ${esc(why)}</div></div><div class="q-btns"><button class="btn small" data-go="${go}">Go</button></div></div>`).join('') || '<div class="empty">Nothing pressing.</div>'}
    </div></section>
    <h3>By vertical</h3>
    <div class="tbl-wrap"><table><thead><tr><th>Vertical</th><th class="num">Active</th><th class="num">Contacted</th><th class="num">Positive replies</th><th class="num">Reply rate</th><th class="num">Calls+</th><th class="num">Won</th></tr></thead><tbody>
      ${ins.verticals.map((v) => `<tr><td>${esc(V(v.vertical))}</td><td class="num">${v.active}</td><td class="num">${v.contacted}</td><td class="num">${v.positive}</td><td class="num">${v.reply_rate != null ? `${v.reply_rate}%` : '—'}${v.contacted ? caveat(v.contacted) : ''}</td><td class="num">${v.calls}</td><td class="num">${v.won}</td></tr>`).join('')}</tbody></table></div>
    <h3>By channel</h3>
    <div class="tbl-wrap"><table><thead><tr><th>Channel</th><th class="num">Sent</th><th class="num">Replies</th></tr></thead><tbody>
      ${(ins.channels || []).map((c) => `<tr><td>${esc(sentence(c.channel))}</td><td class="num">${c.sent}</td><td class="num">${c.replies}${caveat(c.sent)}</td></tr>`).join('')}</tbody></table></div>
    <h3>Stalled (${ins.stalled.length})</h3>
    <div class="list">${ins.stalled.map((s) => `<div class="row clickable" data-open="opp" data-id="${s.id}"><div class="t">${esc(s.company)} ${pill(S(s.status))}</div><div class="meta">${s.days} days without an update${s.value != null ? ` · ${esc(money(s.value, s.currency))} estimate` : ''} · ${esc(s.next_action || '')}</div></div>`).join('') || '<p class="muted small">No engaged opportunity has gone quiet for 10+ days.</p>'}</div>
    <h3>Worth reactivating (${ins.reactivate.length})</h3>
    <div class="list">${ins.reactivate.slice(0, 15).map((s) => `<div class="row clickable" data-open="opp" data-id="${s.id}"><div class="t">${esc(s.company)} ${pill(S(s.status))}</div><div class="meta">last update ${s.days} days ago</div></div>`).join('') || '<p class="muted small">None.</p>'}</div>`;
}

// ---------------------------------------------------------------- HELP
const QA = [
  ['What do I do first each morning?', 'Open Today. Work top to bottom: P1 (replies, meetings, website enquiries), then approvals, then LinkedIn messages. Everything else can wait.'],
  ['What is the difference between Pipeline, Won and Collected?', 'Pipeline is possible business, valued by research estimate. Won is a confirmed deal with a finance record. Collected is money actually received. They are never added together.'],
  ['What does "email verified" mean?', HELP.verified],
  ['Does HQ ever send anything by itself?', 'No. Approving an email creates a Gmail draft that you send. LinkedIn and Instagram messages are copied and sent by you. Auto-reply is off.'],
  ['Why are some values "Unknown"?', HELP.unknown],
  ['How do I log a call or meeting?', 'Open the opportunity (search or Pipeline) → Record meeting. Write two lines, choose the outcome and the next step. HQ books the follow-up.'],
  ['How do I add a new lead I met?', '+ New → New opportunity. If the company already exists HQ reuses it — no duplicates. Emails you type are saved as unverified.'],
  ['What is Reconnect?', 'A previous relationship worth restarting rather than cold outreach. HQ finds these in NOYA Gmail (Past relationships) and never sends a cold introduction to someone NOYA already emailed.'],
  ['What is Ready outreach?', HELP.ready_outreach],
  ['Where does the email history come from?', 'NOYA\'s own Gmail (noya@noyaconcierge.com), read with the existing Google connection: senders, recipients, subject and Gmail\'s short preview only — never full message bodies, never passwords. Newsletters, receipts and system mail are ignored.'],
  ['A task is not relevant. What do I do?', 'Press ✕ on it and give a short reason. It is closed and kept in the history.'],
];
function viewHelp() {
  return `<h2>Help &amp; playbook</h2>
    <section class="panel"><header><h3>How to run NOYA from HQ</h3></header><div class="body playbook">
      <h4>Daily — 15 minutes (09:00)</h4><ol><li>Today → answer every P1 (replies, meetings, website enquiries).</li><li>Outreach → Ready: approve, edit or hold each email; then send the Gmail drafts.</li><li>Outreach → LinkedIn: copy, open profile, send, press Mark sent.</li><li>Past relationships → Review: Reply now first, one tap per relationship.</li><li>Record any call or meeting from yesterday.</li><li>Glance at System: green means nothing to do.</li></ol>
      <h4>Weekly — 45 minutes (Monday)</h4><ol><li>Pipeline → Stale only: move, follow up or close each.</li><li>Growth: act on the recommended actions; review what vertical / market is replying.</li><li>Finance: record payments; chase anything Overdue.</li><li>LinkedIn → People you already know: pick 5 warm people at active prospects.</li><li>Past relationships → Worth reconnecting: restart 3 real conversations; add the useful ones to the CRM.</li><li>Read the weekly review in Reports.</li></ol>
      <h4>Monthly — 1 hour</h4><ol><li>System costs: fill any Unknown cost from invoices; check renewals.</li><li>Markets: decide where to push next month (Europe, GCC, Egypt).</li><li>Re-import LinkedIn connections if you have added many.</li><li>Decide what to stop doing.</li></ol>
    </div></section>
    <section class="panel mt8"><header><h3>How to scale NOYA</h3></header><div class="body playbook">
      <ol><li><b>Prove one vertical and one bridge.</b> Wait for at least 10 contacted per vertical before judging reply rates.</li>
      <li><b>Raise volume only where replies come from.</b> The research agents run up to 10 new prospects a day; increase only after costs are verified (System costs shows Unknown exposure).</li>
      <li><b>Turn every reply into a relationship record.</b> Notes, meetings and follow-ups make the next conversation warmer.</li>
      <li><b>Automate one step at a time</b> using the levels below, and only after the manual version works.</li></ol></div></section>
    <section class="panel mt8"><header><h3>Automation levels</h3></header><div class="body">
      <div class="tbl-wrap"><table><thead><tr><th>Level</th><th>Meaning</th><th>Today</th></tr></thead><tbody>
        <tr><td><b>1 — Prepare</b></td><td>NOYA researches, drafts and recommends. You decide and send.</td><td>Prospect research, email drafts, LinkedIn / Instagram messages, reply reading, follow-up reminders, CEO brief</td></tr>
        <tr><td><b>2 — Act with approval</b></td><td>NOYA acts after your one-click approval.</td><td>Approve → Gmail draft created (you still press Send)</td></tr>
        <tr><td><b>3 — Act alone</b></td><td>NOYA acts without asking, within limits.</td><td>Nothing client-facing. Only internal bookkeeping (logging replies, booking follow-up tasks). Moving anything to level 3 needs your explicit approval.</td></tr>
      </tbody></table></div></div></section>
    <section class="panel mt8"><header><h3>Approval gates (always on)</h3></header><div class="body small"><ul>
      <li>No email, LinkedIn or Instagram message is ever sent automatically. Auto-reply is off.</li>
      <li>No paid tool, plan upgrade, API credit or connector without your approval — see System costs.</li>
      <li>Your LinkedIn password or session is never requested or stored.</li>
      <li>Only VERIFIED emails can be drafted for sending.</li></ul></div></section>
    <section class="panel mt8"><header><h3>Questions</h3></header><div class="body">${QA.map(([q, a]) => `<details class="qa"><summary>${esc(q)}</summary><p class="small">${esc(a)}</p></details>`).join('')}</div></section>`;
}

// ---------------------------------------------------------------- record drawers
const kv = (k, v) => `<div class="kv"><div class="k">${k}</div><div class="v">${v}</div></div>`;
function timelineBlock(kind, id) {
  const t = state.timeline[`${kind}:${id}`];
  if (!t) return '<p class="muted small">Loading history…</p>';
  if (t.error) return `<p class="bad-text small">History unavailable: ${esc(t.error)}</p>`;
  const ev = t.events || [];
  return ev.length ? `<div class="timeline">${ev.slice(0, 60).map((e) => `<div class="tl"><div class="tl-when">${esc(fmtDate(e.at))}</div><div><span class="pill ${e.direction === 'INBOUND' ? 'info' : ''}">${esc(e.channel)}${e.direction === 'INBOUND' ? ' · in' : e.direction === 'OUTBOUND' ? ' · out' : ''}</span> ${esc(e.title)}${e.ref ? ` · ${gmailLink(e.ref)}` : ''}${e.detail ? `<div class="small muted">${esc(String(e.detail).slice(0, 400))}</div>` : ''}</div></div>`).join('')}</div>`
    : '<p class="muted small">No history yet.</p>';
}
function meetingPrep(o, f, r) {
  const reply = state.data.inbound.filter((x) => x.opportunity_id === o.id).sort((a, b) => new Date(b.received_at) - new Date(a.received_at))[0];
  const h = state.rel && ((f.company_id && state.rel.by_company[f.company_id]) || null);
  const li = (k, v) => (v ? `<li><b>${k}:</b> ${esc(v)}</li>` : '');
  return `<h3>Prepare for the conversation</h3><div class="prep"><ul>
    ${li('What they said', reply ? `${REPLY_GROUP[reply.classification] || reply.classification || 'Reply'} — ${reply.summary || reply.subject || ''}` : '')}
    ${li('Why them', r.why_now || o.opportunity_type)}
    ${li('History', h ? `${h.sent} emails from NOYA, ${h.received} from them (last ${shortDay(h.last_at)})` : 'No earlier email in NOYA Gmail.')}
    ${li('Suggested angle (HQ template)', ANGLE[f.vertical] || '')}
    ${li('Next step to propose', o.next_action)}
    ${isClient(f.company_id) ? '<li><b>Client:</b> handle personally; no templates.</li>' : ''}
  </ul>${reply?.thread_id ? `<div class="small">${gmailLink(reply.thread_id, 'Open the conversation in Gmail')}</div>` : ''}</div>`;
}
function drawerShell(title, inner) {
  return `<div class="drawer-bg" data-close-drawer></div><aside class="drawer"><button class="btn small close" data-close-drawer>Close</button>${title}${inner}</aside>`;
}
function renderDrawer(dr) {
  const d = state.data; const dir = state.dir || { companies: [], contacts: [], connections: [], drafts: [] };
  if (dr.kind === 'opp') {
    const o = d.opportunities.find((x) => x.id === dr.id);
    if (!o) return drawerShell('', '<p class="muted">Record not found in the loaded data.</p>');
    const f = facts(o.id); const r = ready(o.id); const ap = d.approvals.find((x) => x.id === o.id); const co = company(f.company_id);
    const openT = d.tasks.filter((t) => t.opportunity_id === o.id && openStatuses.includes(t.status));
    const cq = (state.com?.queue || []).find((x) => x.id === o.id);
    return drawerShell(`<h2>${cq ? scoreBadge(cq.score) + ' ' : ''}${esc(o.company_name)}</h2><div class="pills">${pill(S(o.status))}${f.vertical ? pill(V(f.vertical)) : ''}${pill(`${M(f.origin_market)} → ${M(f.opportunity_market)}`)}${stale(o) ? pill('stale', 'warn') : ''}</div>`, `
      <div class="btn-row"><button class="btn small primary" data-modal="stage" data-opp="${o.id}">Change stage</button><button class="btn small" data-modal="meeting" data-opp="${o.id}">Record meeting</button>
        <button class="btn small" data-modal="touch" data-channel="PHONE" data-opp="${o.id}">Log call / message</button><button class="btn small" data-modal="note" data-opp="${o.id}">Add note</button>
        <button class="btn small" data-modal="draft-request" data-channel="LINKEDIN" data-opp="${o.id}">Draft message</button><button class="btn small" data-modal="channel" data-opp="${o.id}">Change channel</button>
        <button class="btn small" data-modal="finance" data-opp="${o.id}">Add finance record</button><button class="btn small" data-modal="opp-commercial" data-id="${o.id}">Commercial</button>
        ${cq && !cq.has_draft && cq.product ? `<button class="btn small primary" data-prep-outreach="${o.id}">Prepare outreach</button>` : ''}</div>
      ${cq?.trigger ? `<div class="small"><b>Why now:</b> ${esc(cq.trigger)}${cq.signal_id ? ' <button class="linkish" data-tab="radar">(signal)</button>' : ''}</div>` : ''}
      ${cq?.score ? `<details class="small"><summary>Priority ${esc(cq.score.score)} — why</summary>${scoreTable(cq.score)}</details>` : ''}
      <div class="grid2">
        ${kv('Opportunity', esc(o.opportunity_type || '—'))}
        ${kv('Company', co ? `<button class="linkish" data-open="company" data-id="${co.id}">${esc(co.name)}</button>` : esc(o.company_name))}
        ${kv('Contact', `${ap?.contact_id ? `<button class="linkish" data-open="contact" data-id="${ap.contact_id}">${esc(o.contact_name || '—')}</button>` : esc(o.contact_name || '—')}<div class="muted small">${esc(o.contact_position || '')}</div>`)}
        ${kv('Email', `${esc(ap?.contact_email || r.email || '—')} ${emailPill(ap?.email_status || o.email_status, r.email_kind)}`)}
        ${kv('Channels', `${r.linkedin ? `<a href="${esc(r.linkedin)}" target="_blank" rel="noopener noreferrer">LinkedIn</a> ` : ''}${r.instagram ? `<a href="${esc(r.instagram)}" target="_blank" rel="noopener noreferrer">Instagram</a> ` : ''}${r.primary_channel ? `<span class="muted small">best: ${esc(String(r.primary_channel).toLowerCase())}</span>` : ''}` || '—')}
        ${kv('Value', o.estimated_value != null ? `${esc(money(o.estimated_value, o.currency))} <span class="faint">(evidence-backed: ${esc(cq?.contracted_value != null ? 'contract' : cq?.proposal_value != null ? 'proposal' : 'client budget')})</span>` : '<span class="faint">none recorded — no estimate is ever shown</span>')}
        ${cq ? kv('Commercial', `${esc(PNAME(cq.product))} · ${esc(human(cq.track))} · ${esc(SALES_STAGE[cq.stage] || cq.stage)} · owner ${esc(cq.owner || '—')}`) : ''}
        ${kv('Destination', esc(f.destination || '—'))}
        ${kv('Next action', esc(o.next_action || '—'))}
        ${kv('Why now', esc(r.why_now || '—'))}
        ${kv('Last update', esc(fmtDate(o.updated_at)))}
      </div>
      ${prevRel(f.company_id, ap?.contact_id)}
      ${['INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION'].includes(o.status) || openT.some((t) => /MEETING/.test(t.title)) ? meetingPrep(o, f, r) : ''}
      ${ap ? `<h3>Email outreach</h3>${loopBar(ap.loop_stage)}<div class="small">${esc(ap.loop_stage.replace(/_/g, ' ').toLowerCase())}${ap.sent_at ? ` · sent ${esc(fmtDate(ap.sent_at))}` : ''}${ap.block_reason ? ` · ${esc(explain({ reason: ap.block_reason }))}` : ''}</div>
        ${ap.draft?.subject ? `<details><summary>Draft: ${esc(ap.draft.subject)}</summary><div class="email"><pre>${esc(ap.draft.body || '')}</pre></div></details>` : ''}` : ''}
      <h3>Open tasks (${openT.length})</h3>
      ${openT.map((t) => `<div class="mini"><div class="t">${esc(sentence(t.title))}</div><div class="m">due ${esc(fmtDay(t.due_at))}</div>
        <div class="btn-row mt6">${t.task_type !== 'SALES_OUTREACH_APPROVAL' ? `<button class="btn small" data-modal="task-done" data-id="${t.id}">Done</button><button class="btn small ghost" data-modal="task-dismiss" data-id="${t.id}">Not needed</button>` : '<button class="btn small" data-go="outreach">Approve in Outreach</button>'}<button class="btn small" data-modal="task-snooze" data-id="${t.id}">Snooze</button></div></div>`).join('') || '<p class="muted small">None.</p>'}
      <h3>History</h3>${timelineBlock('opportunity', o.id)}
      <p class="src mt8">Record ${esc(o.id)}</p>`);
  }
  if (dr.kind === 'company') {
    const c = company(dr.id); if (!c) return drawerShell('', '<p class="muted">Company not found.</p>');
    const opps = d.opportunities.filter((o) => facts(o.id).company_id === c.id);
    const people = dir.contacts.filter((k) => k.company_id === c.id);
    const net = dir.connections.filter((k) => k.matched_company_id === c.id);
    return drawerShell(`<h2>${esc(c.name)}</h2><div class="pills">${pill(V(c.vertical))}${pill(M(c.market))}${c.relationship_status ? pill(c.relationship_status, c.relationship_status === 'client' ? 'bad' : '') : ''}${c.relationship_status === 'client' ? pill('handle personally', 'bad') : ''}</div>`, `
      ${prevRel(c.id, null)}
      <div class="btn-row"><button class="btn small" data-modal="vertical" data-company="${c.id}">Edit details</button><button class="btn small" data-modal="draft-request" data-channel="EMAIL" data-company="${c.id}">Draft message</button><button class="btn small" data-modal="note" data-company="${c.id}">Add note</button>
        <button class="btn small" data-modal="finance" data-company="${c.id}">Add finance record</button></div>
      <div class="grid2">${kv('Website', c.website ? `<a href="${esc(/^https?:/.test(c.website) ? c.website : `https://${c.website}`)}" target="_blank" rel="noopener noreferrer">${esc(c.website)}</a>` : '—')}
        ${kv('Country', esc([c.city, c.country].filter(Boolean).join(', ') || 'Unknown'))}${kv('Type', esc(c.company_type || '—'))}${kv('Source', esc(c.source || '—'))}</div>
      ${accountBlock(c.id)}
      <div class="btn-row"><button class="btn small" data-modal="partner-edit" data-company="${c.id}">Track as partner</button><button class="btn small" data-modal="edge-add" data-company="${c.id}">Record an introduction</button></div>
      <h3>Opportunities (${opps.length})</h3>${opps.map((o) => `<div class="mini clickable" data-open="opp" data-id="${o.id}"><div class="t">${esc(String(o.opportunity_type || '').slice(0, 90))} ${pill(S(o.status))}</div><div class="m">${esc(o.next_action || '')}</div></div>`).join('') || '<p class="muted small">None.</p>'}
      <h3>People (${people.length})</h3>${people.map((k) => `<div class="mini clickable" data-open="contact" data-id="${k.id}"><div class="t">${esc(k.name || k.email || '—')} ${emailPill(k.email_status, k.email_kind)}</div><div class="m">${esc(k.position || '')}</div></div>`).join('') || '<p class="muted small">None.</p>'}
      ${net.length ? `<h3>You know here (${net.length})</h3>${net.map((k) => `<div class="mini clickable" data-open="connection" data-id="${k.id}"><div class="t">${esc(k.name)}</div><div class="m">${esc(k.position || '')} · LinkedIn connection</div></div>`).join('')}` : ''}
      <h3>History</h3>${timelineBlock('company', c.id)}`);
  }
  if (dr.kind === 'contact') {
    const k = dir.contacts.find((x) => x.id === dr.id); if (!k) return drawerShell('', '<p class="muted">Contact not found.</p>');
    const opps = d.approvals.filter((a) => a.contact_id === k.id);
    return drawerShell(`<h2>${esc(k.name || k.email || 'Contact')}</h2><div class="pills">${emailPill(k.email_status, k.email_kind)}${k.do_not_contact ? pill('do not contact', 'bad') : ''}</div>`, `
      ${prevRel(k.company_id, k.id)}
      <div class="btn-row"><button class="btn small" data-modal="touch" data-channel="PHONE" data-contact="${k.id}">Log call / message</button><button class="btn small" data-modal="note" data-contact="${k.id}">Add note</button>
        <button class="btn small" data-modal="draft-request" data-channel="LINKEDIN" data-contact="${k.id}">Draft message</button></div>
      <div class="grid2">${kv('Role', esc(k.position || '—'))}${kv('Company', k.company_id ? `<button class="linkish" data-open="company" data-id="${k.company_id}">${esc(k.company)}</button>` : '—')}
        ${kv('Email', esc(k.email || '—'))}${kv('Email evidence', esc(provenanceTitle(k)))}${k.email_source ? kv('Found at', `<a href="${esc(k.email_source)}" target="_blank" rel="noopener noreferrer">source</a>`) : ''}
        ${kv('LinkedIn', k.linkedin ? `<a href="${esc(k.linkedin)}" target="_blank" rel="noopener noreferrer">profile</a>` : '—')}${kv('Phone', esc(k.phone || '—'))}${kv('Last interaction', esc(k.last_interaction ? fmtDate(k.last_interaction) : '—'))}</div>
      <h3>Opportunities (${opps.length})</h3>${opps.map((o) => `<div class="mini clickable" data-open="opp" data-id="${o.id}"><div class="t">${esc(o.company_name)} ${pill(S(o.status))}</div></div>`).join('') || '<p class="muted small">None.</p>'}
      <h3>History</h3>${timelineBlock('contact', k.id)}`);
  }
  if (dr.kind === 'connection') {
    const c = dir.connections.find((x) => x.id === dr.id); if (!c) return drawerShell('', '<p class="muted">Connection not found.</p>');
    const drafts = (dir.drafts || []).filter((x) => x.connection_id === c.id);
    return drawerShell(`<h2>${esc(c.name || 'Connection')}</h2><div class="pills">${pill(sentence(c.status.replace(/_/g, ' ')))}${c.vertical ? pill(V(c.vertical)) : ''}</div>`, `
      <div class="btn-row"><a class="btn small" href="${esc(c.profile_url)}" target="_blank" rel="noopener noreferrer">Open in LinkedIn</a>
        <button class="btn small primary" data-modal="draft-request" data-channel="LINKEDIN" data-conn="${c.id}">Draft message</button>
        <button class="btn small" data-modal="touch" data-channel="LINKEDIN" data-conn="${c.id}">Mark sent</button>
        <button class="btn small" data-modal="conn-status" data-conn="${c.id}">Update status</button><button class="btn small" data-modal="note" data-conn="${c.id}">Add note</button></div>
      <div class="grid2">${kv('Role', esc(c.position || '—'))}${kv('Company', c.matched_company_id ? `<button class="linkish" data-open="company" data-id="${c.matched_company_id}">${esc(c.company)}</button>` : esc(c.company || '—'))}
        ${kv('Connected', esc(c.connected_on ? fmtDay(c.connected_on) : '—'))}${kv('Relationship strength', 'Unknown <span class="faint small">(no data source measures this)</span>')}
        ${kv('How you know them', esc(c.how_we_know || '—'))}${kv('Last contacted', esc(c.last_contacted_at ? fmtDate(c.last_contacted_at) : 'never (in HQ)'))}
        ${kv('Next follow-up', esc(c.next_follow_up_at ? fmtDay(c.next_follow_up_at) : '—'))}${kv('Active opportunities at company', esc(c.active_opps))}</div>
      ${drafts.length ? `<h3>Drafts</h3>${drafts.map(draftRow).join('')}` : ''}`);
  }
  return '';
}

// ---------------------------------------------------------------- COMMERCIAL CORE (inside the 8 frozen sections)
// signal → opportunity → company → people → relationship → service → angle → outreach → conversation → proposal /
// partnership → project → revenue → expansion. Data: hq_commercial (one read) + hq_account (per company, on open).
const URG = { NOW: ['Now', 'bad'], D7: ['7 days', 'warn'], D30: ['30 days', 'info'], D90: ['90 days', ''], LATER: ['Later / watch', ''], PASSED: ['Passed', ''] };
const REGION_LABEL = { EGYPT: 'Egypt', UK: 'UK', EUROPE: 'Europe', MIDDLE_EAST: 'Middle East', GLOBAL: 'Global' };
const CATEGORY_LABEL = { SPORTS: 'Sports', EVENTS: 'Events', HOSPITALITY: 'Hospitality', BRANDS: 'Brands', PRODUCTION: 'Production', CORPORATE: 'Corporate',
  PRIVATE_UHNW: 'Private / UHNW', ENTERTAINMENT: 'Entertainment', WEDDINGS: 'Weddings', TRAVEL: 'Travel', REAL_ESTATE: 'Real estate', LUXURY_GOODS: 'Luxury goods', OTHER: 'Other' };
const SIG_STAGE = { WATCH: ['Watch', ''], RESEARCH: ['Research', 'info'], QUALIFIED: ['Qualified opportunity', 'ok'], ACTIVE: ['Active commercial', 'ok'], DISMISSED: ['Dismissed', ''] };
const SALES_STAGE = { DISCOVERED: 'Discovered', QUALIFIED: 'Qualified', CONTACT_IDENTIFIED: 'Contact identified', OUTREACH_PREPARED: 'Outreach prepared', CONTACTED: 'Contacted',
  ENGAGED: 'Engaged', DISCOVERY: 'Discovery', OPPORTUNITY: 'Opportunity', PROPOSAL: 'Proposal', NEGOTIATION: 'Negotiation', WON: 'Won', LOST: 'Lost', NURTURE: 'Nurture' };
const PARTNER_STAGES = ['TARGET', 'QUALIFIED', 'CONTACTED', 'CONVERSATION', 'VALUE_EXCHANGE', 'PROPOSED', 'PILOT', 'ACTIVE', 'PRODUCTIVE', 'STRATEGIC', 'DORMANT', 'LOST'];
const ORG_ROLES = ['ORGANISER', 'PROMOTER', 'SPONSOR', 'BRAND', 'AGENCY', 'PR', 'HOTEL', 'VENUE', 'OPERATOR', 'DEVELOPER', 'PRODUCTION', 'TALENT_AGENCY', 'TEAM', 'GOVERNMENT', 'OTHER'];
const ITEM_TYPES = ['GUEST', 'VIP', 'FLIGHT', 'HOTEL', 'VILLA', 'TRANSFER', 'RESTAURANT', 'VENUE', 'ENTERTAINMENT', 'PRODUCTION', 'SECURITY', 'SUPPLIER', 'SCHEDULE', 'APPROVAL', 'RUN_OF_SHOW', 'ISSUE', 'FEEDBACK', 'OTHER'];
const ROLES = ['CEO', 'SALES', 'PARTNERSHIPS', 'SDR', 'EVENTS', 'OPERATIONS', 'ACCOUNT_MANAGEMENT', 'REVOPS'];
const PROV = { VERIFIED: ['verified', 'ok'], SOURCE_BACKED: ['source-backed', 'info'], INFERRED: ['inferred', 'warn'], NEEDS_VERIFICATION: ['needs verification', 'warn'], MANUALLY_CONFIRMED: ['confirmed in HQ', 'ok'] };
const provPill = (p) => (p ? pill(PROV[p]?.[0] || p, PROV[p]?.[1] || '') : '');
const human = (t) => sentence(String(t || '').replace(/_/g, ' '));
const product = (code) => (state.com?.products || []).find((p) => p.code === code);
const playbook = (code) => (state.com?.playbooks || []).find((p) => p.code === code);
const PNAME = (code) => (product(code)?.name || code || '—').replace(/^NOYA /, '');
const urgPill = (u) => pill(URG[u]?.[0] || u, URG[u]?.[1] || '');
const dateRange = (a, b) => (a ? `${fmtDay(a)}${b && b !== a ? ` – ${fmtDay(b)}` : ''}` : '');
const scoreTitle = (s) => (s ? [...(s.components || []).map((c) => `${c.label}: ${c.points}/${c.max} — ${c.why}`), s.override ? `Override ${s.override.score} (computed ${s.computed}): ${s.override.reason}` : '', s.note || ''].filter(Boolean).join('\n') : '');
const scoreBadge = (s) => (s ? `<span class="score-badge ${s.score >= 70 ? 'hi' : s.score >= 50 ? 'mid' : ''}" title="${esc(scoreTitle(s))}">${esc(s.score)}</span>` : '');
function scoreTable(s) {
  if (!s) return '';
  return `<div class="tbl-wrap"><table class="score-tbl"><tbody>${(s.components || []).map((c) => `<tr><td>${esc(c.label)}</td><td class="num">${esc(c.points)}/${esc(c.max)}</td><td class="small muted">${esc(c.why)}</td></tr>`).join('')}
    <tr><td><b>Priority</b></td><td class="num"><b>${esc(s.score)}</b></td><td class="small muted">${s.override ? `Override by ${esc(s.override.by || '')}: ${esc(s.override.reason || '')} (computed ${esc(s.computed)})` : esc(s.note || '')}</td></tr></tbody></table></div>`;
}
const teamOptions = () => ((state.com?.team?.members) || [{ name: 'Adam' }]).map((m) => [m.name, m.name]);
const companyOptions = () => [['', 'Choose…'], ...((state.dir?.companies || []).slice().sort((a, b) => a.name.localeCompare(b.name)).map((c) => [c.id, c.name]))];

// ---------------------------------------------------------------- 02 · Opportunity radar
function signalCard(s) {
  const q = s.qualification || {}; const pb = playbook(s.playbook);
  const orgs = s.orgs || [];
  return `<article class="card signal-card" id="sig-${s.id}">
    <div class="card-head"><div><div class="co">${esc(s.title)}</div>
      <div class="muted small">${s.source_url ? `<a href="${esc(s.source_url)}" target="_blank" rel="noopener noreferrer">${esc(s.source_name || 'source')}</a>` : 'No source link'} · found ${esc(shortDay(s.discovered_at))}${s.event_date ? ` · <b>${esc(dateRange(s.event_date, s.event_end))}</b>` : ''}${s.destination ? ` · ${esc(s.destination)}` : ''}</div></div>
      <div class="pills">${urgPill(s.urgency)}${pill(SIG_STAGE[s.stage]?.[0] || s.stage, SIG_STAGE[s.stage]?.[1] || '')}${s.category ? pill(CATEGORY_LABEL[s.category] || s.category) : ''}${s.region ? pill(REGION_LABEL[s.region] || s.region) : ''}${provPill(s.provenance)}</div></div>
    ${s.why ? `<div class="small"><b>Why NOYA should care:</b> ${esc(s.why)}</div>` : ''}
    ${pb ? `<div class="small mt6"><b>Playbook:</b> ${esc(pb.name)} · <b>Products:</b> ${esc((s.products || []).map(PNAME).join(', ') || '—')}</div>` : '<div class="small mt6 faint">No playbook matched yet — edit to choose one.</div>'}
    ${s.ai?.angle ? `<div class="ai small mt6"><div class="faint">AI reading of the source (${esc(s.ai.provenance || 'inferred')})</div>${esc(s.ai.angle)}${s.ai.decision_roles?.length ? `<div class="mt6"><b>Likely deciders:</b> ${esc(s.ai.decision_roles.join(', '))}</div>` : ''}</div>` : ''}
    <div class="qual mt6"><div class="qbar"><span data-w="${Math.round(((q.answered || 0) / 10) * 100)}"></span></div>
      <span class="small"><b>${esc(q.answered ?? 0)}/10</b> qualification answers${q.complete ? ' — complete' : q.missing?.length ? ` · missing: <span class="bad-text">${esc(q.missing.join(' · '))}</span>` : ''}</span>
      <details class="small"><summary>The 10 questions</summary><ol>${(q.questions || []).map((x) => `<li class="${x.ok ? '' : 'bad-text'}"><b>${esc(x.q)}</b> ${esc(x.a || '—')}</li>`).join('')}</ol></details></div>
    <div class="small mt6"><b>Organisations</b> ${orgs.length ? '' : '<span class="faint">none named yet</span>'}</div>
    <div class="orgs">${orgs.map((o) => `<div class="org"><span>${esc(o.name)} <span class="faint">(${esc(human(o.role))})</span>${o.partner ? ' ' + pill('NOYA partner', 'ok') : ''} ${provPill(o.provenance)}</span>
      ${o.company_id ? `<button class="btn small" data-open="company" data-id="${o.company_id}">Account</button>` : ''}<button class="btn small" data-org-crm="${o.id}" title="Put this organisation in the CRM and raise a find-the-decision-maker task">${o.company_id ? 'Find decision maker' : 'Add to CRM'}</button></div>`).join('')}</div>
    ${(s.opportunities || []).length ? `<div class="small mt6"><b>Opportunities from this signal:</b> ${s.opportunities.map((o) => `<button class="linkish" data-open="opp" data-id="${o.id}">${esc(o.company)} · ${esc(PNAME(o.product))}</button> ${pill(S(o.status))}`).join(' ')}</div>` : ''}
    <div class="small faint mt6">Owner ${esc(s.owner || '—')} · next: ${esc(s.next_action || '—')}${s.next_action_due ? ` (due ${esc(shortDay(s.next_action_due))})` : ''}</div>
    <div class="btn-row mt6">
      ${s.stage !== 'RESEARCH' && s.stage !== 'ACTIVE' ? `<button class="btn small" data-sig-stage="RESEARCH" data-id="${s.id}">Research</button>` : ''}
      ${s.stage !== 'WATCH' && s.stage !== 'ACTIVE' ? `<button class="btn small ghost" data-sig-stage="WATCH" data-id="${s.id}">Watch</button>` : ''}
      ${['WATCH', 'RESEARCH'].includes(s.stage) ? `<button class="btn small ${q.complete ? 'primary' : ''}" data-sig-stage="QUALIFIED" data-id="${s.id}" ${q.complete ? '' : 'title="Answer all 10 questions first"'}>Qualify</button>` : ''}
      ${['QUALIFIED', 'ACTIVE'].includes(s.stage) || q.complete ? `<button class="btn small primary" data-modal="sig-promote" data-id="${s.id}">Create opportunities</button>` : ''}
      <button class="btn small" data-modal="sig-org" data-id="${s.id}">Add organisation</button>
      <button class="btn small" data-modal="sig-edit" data-id="${s.id}">Edit</button>
      ${s.stage !== 'DISMISSED' ? `<button class="btn small ghost" data-modal="sig-dismiss" data-id="${s.id}">Dismiss</button>` : ''}
    </div></article>`;
}
function viewRadar() {
  const c = state.com; if (!c) return empty(`Intelligence not loaded${state.errors.com ? `: ${state.errors.com}` : ''}.`);
  const f = state.radarF; const q = f.q.trim().toLowerCase();
  const live = c.signals.filter((s) => s.stage !== 'DISMISSED');
  const tabs = { ALL: live.filter((s) => s.urgency !== 'PASSED'), NOW: live.filter((s) => s.urgency === 'NOW'), D7: live.filter((s) => s.urgency === 'D7'),
    D30: live.filter((s) => s.urgency === 'D30'), D90: live.filter((s) => s.urgency === 'D90'), LATER: live.filter((s) => ['LATER', 'PASSED'].includes(s.urgency)),
    DISMISSED: c.signals.filter((s) => s.stage === 'DISMISSED') };
  const labels = { ALL: 'All', NOW: 'Now / urgent', D7: '7 days', D30: '30 days', D90: '90 days', LATER: 'Longer term / watch', DISMISSED: 'Dismissed' };
  const rows = (tabs[f.h] || tabs.ALL).filter((s) => (!f.region || s.region === f.region) && (!f.cat || s.category === f.cat)
    && (!q || [s.title, s.summary, s.destination, ...(s.orgs || []).map((o) => o.name)].some((v) => String(v ?? '').toLowerCase().includes(q))));
  return `<h2>Opportunity radar</h2>
    <p class="muted small">Real-world developments that give NOYA a reason to contact someone. The horizon is when to <b>act</b> (events need ~45 days), not the event date. A signal becomes a qualified opportunity only when all 10 questions are answered — otherwise it stays in research.</p>
    <div class="tabs">${Object.keys(tabs).map((k) => `<button data-rdf="h" data-v="${k}" class="${f.h === k ? 'on' : ''}">${labels[k]} <span class="n">${tabs[k].length}</span></button>`).join('')}</div>
    <div class="filters"><input data-rdf="q" placeholder="Event, organisation, destination…" value="${esc(f.q)}">
      <select data-rdf="region">${opt('', f.region, 'All regions')}${Object.entries(REGION_LABEL).map(([k, l]) => opt(k, f.region, l)).join('')}</select>
      <select data-rdf="cat">${opt('', f.cat, 'All categories')}${Object.entries(CATEGORY_LABEL).map(([k, l]) => opt(k, f.cat, l)).join('')}</select>
      <button class="btn small" data-modal="sig-capture">+ Capture a signal</button></div>
    ${rows.map(signalCard).join('') || empty('Nothing on this horizon.')}
    <p class="src">Sources: workflow 09 (Egypt intelligence) daily, workflow 17 (AI analyst — organisations are kept only if named in the source), and signals captured by the team. No source link, no signal.</p>`;
}

// ---------------------------------------------------------------- 02 · Products & playbooks
function viewLibrary() {
  const c = state.com; if (!c) return empty('Library not loaded.');
  const w = c.weights || {};
  return `<h2>Products & playbooks</h2>
    <p class="muted small">Internal sales frameworks (not public). The radar recommends a playbook and products for every signal; every opportunity records which product it sells, so playbook results below are real outcomes, not estimates.</p>
    <h3>Playbooks (${c.playbooks.length})</h3>
    <div class="tbl-wrap"><table><thead><tr><th>Playbook</th><th class="num">Signals</th><th class="num">Opps</th><th class="num">Contacted</th><th class="num">Engaged</th><th class="num">Won</th><th class="num">Lost</th></tr></thead><tbody>
      ${c.playbooks.map((p) => `<tr><td><b>${esc(p.name)}</b><div class="muted small">${esc(p.trigger_desc)}</div></td>${['signals', 'opportunities', 'contacted', 'engaged', 'won', 'lost'].map((k) => `<td class="num">${esc(p.performance?.[k] ?? 0)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>
    ${c.playbooks.map((p) => `<details class="panel mt8"><summary><b>${esc(p.name)}</b> — ${esc(p.value_proposition || '')}</summary><div class="body small">
      ${kv('Ideal prospect', esc(p.ideal_prospect || '—'))}${kv('Decision makers', esc((p.decision_roles || []).join(', ')))}${kv('Products', esc((p.product_codes || []).map(PNAME).join(', ')))}
      ${kv('Services', esc((p.services || []).join(' · ')))}${kv('Research first', esc((p.research_questions || []).join(' · ')))}${kv('Outreach approach', esc(p.outreach_approach || '—'))}
      ${kv('Targets around one event', (p.target_orgs || []).map((t) => `${esc(human(t.org_role))} → ${esc(PNAME(t.product))} <span class="faint">(${esc(t.why)})</span>`).join('<br>') || '—')}
      ${kv('Proposal', esc(p.proposal_type || '—'))}${kv('Proof required', esc((p.proof_required || []).join(' · ')))}${kv('Upsells', esc((p.upsells || []).join(' · ')))}${kv('Partnership potential', esc(p.partnership_potential || '—'))}
      ${(p.objections || []).map((o) => `<div class="mini"><div class="t">“${esc(o.objection)}”</div><div class="m">${esc(o.response)}</div></div>`).join('')}</div></details>`).join('')}
    <h3>Products (${c.products.length})</h3>
    ${c.products.map((p) => `<details class="panel mt8"><summary><b>${esc(p.name)}</b> — ${esc(p.summary)}</summary><div class="body small">
      ${kv('Ideal client', esc(p.ideal_client || '—'))}${kv('Buyer roles', esc((p.buyer_roles || []).join(', ')))}${kv('Triggers', esc((p.trigger_events || []).join(' · ')))}
      ${kv('Their problems', esc((p.client_problems || []).join(' · ')))}${kv('NOYA solution', esc(p.solution || '—'))}${kv('Included', esc((p.included_services || []).join(' · ')))}
      ${kv('Proof', esc((p.proof_points || []).join(' · ')))}${kv('Upsells', esc((p.upsells || []).join(' · ')))}${kv('Recurring', esc(p.recurring_potential || '—'))}
      <h4>First email</h4><div class="email"><pre>Subject: ${esc(p.email_template?.subject || '')}\n\n${esc(p.email_template?.body || '')}</pre></div>
      <h4>LinkedIn / DM</h4><div class="email"><pre>${esc(p.dm_template || '')}</pre></div>
      <h4>Follow-ups</h4>${(p.follow_up_sequence || []).map((f) => `<div class="mini"><div class="t">Day +${esc(f.day)} · ${esc(human(f.channel))} · ${esc(f.purpose)}</div><div class="m">${esc(f.message)}</div></div>`).join('')}
      <h4>Call points</h4><ul>${(p.call_points || []).map((x) => `<li>${esc(x)}</li>`).join('')}</ul>
      ${(p.objections || []).map((o) => `<div class="mini"><div class="t">“${esc(o.objection)}”</div><div class="m">${esc(o.response)}</div></div>`).join('')}
      ${kv('Proposal', esc(p.proposal_template || '—'))}</div></details>`).join('')}
    <h3>Opportunity priority score</h3>
    <p class="small">Weights (configurable, total 100): ${Object.entries(w).map(([k, v]) => `${esc(human(k))} ${esc(v)}`).join(' · ')}. The score orders the work. It is <b>not money and not a probability of winning</b>; any override needs a written reason and is audited.</p>`;
}

// ---------------------------------------------------------------- 03 · Action queue (who to contact today, why, what to offer)
const SEGMENTS = [['', 'All'], ['PRIVATE', 'Private / UHNW'], ['CORPORATE', 'Corporate'], ['BRANDS', 'Brands'], ['PRODUCTION', 'Production'], ['SPORTS', 'Sports / Athletes'],
  ['EVENTS', 'Events'], ['HOSPITALITY', 'Hospitality'], ['WEDDINGS', 'Weddings'], ['AGENCIES', 'Agencies'], ['CONCIERGE', 'Concierge partners'], ['REAL_ESTATE', 'Real estate'], ['SOURCING', 'Luxury sourcing']];
function segOf(x) {
  const t = `${x.type || ''} ${x.company || ''}`;
  return {
    PRIVATE: x.segment === 'PRIVATE_UHNW' || x.product === 'NOYA_PRIVATE', CORPORATE: x.segment === 'CORPORATE' || x.product === 'CORPORATE_DESK',
    BRANDS: x.product === 'BRAND_EXPERIENCE_DESK' || (x.segment === 'BRAND_PRODUCTION' && x.product !== 'PRODUCTION_DESK'), PRODUCTION: x.product === 'PRODUCTION_DESK' || /production/i.test(t),
    SPORTS: x.segment === 'SPORTS_TALENT' || x.product === 'ATHLETE_TEAM_DESK', EVENTS: x.track === 'EVENT' || ['EVENT_CONCIERGE_DESK', 'VIP_GUEST_DESK'].includes(x.product),
    HOSPITALITY: x.segment === 'HOSPITALITY', WEDDINGS: x.product === 'WEDDING_GUEST_DESK' || x.segment === 'WEDDINGS_EVENTS', AGENCIES: /agency|agencies|pr |marketing/i.test(t),
    CONCIERGE: x.segment === 'TRAVEL_CONCIERGE' || x.product === 'EGYPT_DESTINATION_DESK', REAL_ESTATE: x.playbook === 'PROPERTY_LAUNCH' || /real estate|propert|developer/i.test(t),
    SOURCING: x.product === 'LUXURY_SOURCING',
  };
}
function actionCard(x) {
  const due = x.due && x.due <= todayKey();
  return `<article class="card act" id="act-${x.id}">
    <div class="card-head"><div><div class="co">${scoreBadge(x.score)} ${esc(x.company || '—')}</div>
      <div class="muted small">${esc(x.person || 'No named person yet')}${x.role ? ` · ${esc(x.role)}` : ''}${x.email_status ? ` · email ${esc(String(x.email_status).toLowerCase())}` : ''}</div></div>
      <div class="pills">${pill(SALES_STAGE[x.stage] || x.stage, ['ENGAGED', 'DISCOVERY', 'PROPOSAL', 'NEGOTIATION'].includes(x.stage) ? 'ok' : '')}${pill(human(x.track))}${x.segment ? pill(V(x.segment)) : ''}${provPill(x.provenance)}</div></div>
    <div class="grid2 small">
      ${kv('Why now', esc(x.trigger || x.reason || '—'))}${kv('Offer', esc(x.product ? PNAME(x.product) : 'No product chosen'))}
      ${kv('Angle', esc(x.angle || '—'))}${kv('Relationship path', `${pill(x.path, x.path === 'STRONG' ? 'ok' : x.path === 'WARM' ? 'info' : '')} <span class="faint" title="${esc((x.strength?.components || []).map((c) => `${c.evidence} (+${c.points})`).join('\n'))}">${esc((x.strength?.components || []).map((c) => c.evidence).slice(0, 2).join(' · ') || 'no history')}</span>`)}
      ${kv('Last interaction', esc(x.last_touch ? fmtDay(x.last_touch) : '—'))}${kv('Next', `${esc(x.next_action || '—')}${x.due ? ` <span class="${due ? 'bad-text' : 'faint'}">· due ${esc(shortDay(x.due))}</span>` : ''}`)}
      ${kv('Owner', esc(x.owner || '—'))}${x.contracted_value != null || x.proposal_value != null || x.client_budget != null ? kv('Value (evidence-backed)', `${esc(money(x.contracted_value ?? x.proposal_value ?? x.client_budget, x.currency))} <span class="faint">${x.contracted_value != null ? 'contract' : x.proposal_value != null ? 'proposal' : 'client budget'}</span>`) : ''}
    </div>
    <div class="btn-row mt6"><button class="btn small" data-open="opp" data-id="${x.id}">Open</button>${x.company_id ? `<button class="btn small" data-open="company" data-id="${x.company_id}">Account brief</button>` : ''}
      ${!x.has_draft && x.product && ['DISCOVERED', 'QUALIFIED', 'CONTACT_IDENTIFIED'].includes(x.stage) ? `<button class="btn small primary" data-prep-outreach="${x.id}">Prepare outreach</button>` : ''}
      ${x.has_draft && x.stage === 'OUTREACH_PREPARED' ? '<button class="btn small primary" data-go="outreach" data-otab="READY">Approve in Outreach</button>' : ''}
      <button class="btn small" data-modal="opp-commercial" data-id="${x.id}">Commercial</button></div></article>`;
}
function viewActions() {
  const c = state.com; if (!c) return empty(`Action queue not loaded${state.errors.com ? `: ${state.errors.com}` : ''}.`);
  const f = state.actF;
  const open = c.queue.filter((x) => !['WON', 'LOST', 'NURTURE'].includes(x.stage));
  const today = open.filter((x) => (x.due && x.due <= todayKey()) || ((x.score?.score || 0) >= 60 && !['CONTACTED'].includes(x.stage)));
  const tabs = { TODAY: today, OPEN: open, NURTURE: c.queue.filter((x) => x.stage === 'NURTURE'), WON: c.queue.filter((x) => x.stage === 'WON') };
  const labels = { TODAY: 'Today', OPEN: 'All open', NURTURE: 'Nurture', WON: 'Won' };
  const rows = (tabs[f.view] || today).filter((x) => (!f.seg || segOf(x)[f.seg]) && (!f.owner || x.owner === f.owner) && (!f.track || x.track === f.track));
  return `<h2>Action queue</h2>
    <p class="muted small">Who to contact, why, what to offer, what happened last and what to do next — ordered by the priority score (hover a score for its reasons). One shared CRM; the segment chips are views, not separate databases. Nothing is sent from here.</p>
    <div class="tabs">${Object.keys(tabs).map((k) => `<button data-acf="view" data-v="${k}" class="${f.view === k ? 'on' : ''}">${labels[k]} <span class="n">${tabs[k].length}</span></button>`).join('')}</div>
    <div class="chips">${SEGMENTS.map(([k, l]) => `<button class="chip ${f.seg === k ? 'on' : ''}" data-acf="seg" data-v="${k}">${esc(l)}</button>`).join('')}</div>
    <div class="filters"><select data-acf="owner">${opt('', f.owner, 'All owners')}${teamOptions().map(([k, l]) => opt(k, f.owner, l)).join('')}</select>
      <select data-acf="track">${opt('', f.track, 'Sales + partnerships + events')}${[['SALES', 'Sales'], ['PARTNERSHIP', 'Partnerships'], ['EVENT', 'Events']].map(([k, l]) => opt(k, f.track, l)).join('')}</select></div>
    ${rows.slice(0, 60).map(actionCard).join('') || empty('Nothing here.')}
    ${rows.length > 60 ? `<p class="small faint">Showing 60 of ${rows.length}.</p>` : ''}`;
}

// ---------------------------------------------------------------- 04 · Partnerships
function partnerCard(p) {
  return `<article class="card partner"><div class="card-head"><div><div class="co">${esc(p.name)}</div><div class="muted small">${esc(human(p.class))} · ${esc(p.category || '—')}${p.geography ? ` · ${esc(p.geography)}` : ''}</div></div>
    <div class="pills">${pill(human(p.stage), ['PRODUCTIVE', 'STRATEGIC', 'ACTIVE'].includes(p.stage) ? 'ok' : p.stage === 'DORMANT' ? 'warn' : '')}${pill(human(p.health), p.health === 'GOOD' ? 'ok' : p.health === 'DORMANT' ? 'bad' : 'warn')}${provPill(p.provenance)}</div></div>
    <div class="grid2 small">${kv('They give NOYA', esc(p.provides_noya || '—'))}${kv('NOYA gives them', esc(p.noya_provides || '—'))}${kv('Terms / rates', esc([p.terms, p.rates, p.commission && `commission: ${p.commission}`, p.exclusivity && `exclusivity: ${p.exclusivity}`].filter(Boolean).join(' · ') || '—'))}
      ${kv('Real activity', `${esc(p.opportunities)} opportunities · ${esc(p.projects)} project supplies · ${esc(p.revenue_invoices)} paid invoices`)}${kv('Last interaction', esc(p.last_interaction ? fmtDay(p.last_interaction) : 'none recorded'))}${kv('Next', esc(p.next_action || '—'))}
      ${p.events?.length ? kv('Events they are part of', esc(p.events.join(' · '))) : ''}${kv('Owner', esc(p.owner || '—'))}</div>
    ${p.stage_evidence ? `<div class="small faint">Stage evidence: ${esc(p.stage_evidence)}</div>` : ''}
    <div class="btn-row mt6"><button class="btn small" data-open="company" data-id="${p.company_id}">Account</button><button class="btn small" data-modal="partner-edit" data-company="${p.company_id}" data-type="${p.class}">Update</button></div></article>`;
}
function viewPartners() {
  const c = state.com; if (!c) return empty('Partnerships not loaded.');
  const f = state.parF;
  const recs = c.partners.filter((p) => !f.cls || p.class === f.cls);
  const pursuits = c.queue.filter((x) => x.track === 'PARTNERSHIP' && !['WON', 'LOST'].includes(x.stage));
  const eventOrgs = c.signals.filter((s) => s.stage !== 'DISMISSED' && s.urgency !== 'PASSED').flatMap((s) => (s.orgs || []).filter((o) => ['HOTEL', 'VENUE', 'AGENCY', 'OPERATOR', 'TALENT_AGENCY', 'PR'].includes(o.role)).map((o) => ({ ...o, signal: s })));
  const openers = recs.filter((p) => (p.events || []).length && ['ACTIVE', 'PRODUCTIVE', 'STRATEGIC', 'PILOT'].includes(p.stage));
  const tabs = { DEVELOP: pursuits.length + recs.filter((p) => ['TARGET', 'QUALIFIED', 'CONTACTED', 'CONVERSATION', 'VALUE_EXCHANGE', 'PROPOSED'].includes(p.stage)).length,
    ACTIVE: recs.filter((p) => ['PILOT', 'ACTIVE', 'PRODUCTIVE', 'STRATEGIC'].includes(p.stage)).length,
    DORMANT: recs.filter((p) => p.stage === 'DORMANT' || ['DORMANT', 'COOLING'].includes(p.health)).length, EVENTS: eventOrgs.length, OPENERS: openers.length };
  const labels = { DEVELOP: 'To develop', ACTIVE: 'Active', DORMANT: 'Dormant / cooling', EVENTS: 'Events creating partnerships', OPENERS: 'Can open accounts' };
  let body = '';
  if (f.tab === 'DEVELOP') body = `${recs.filter((p) => ['TARGET', 'QUALIFIED', 'CONTACTED', 'CONVERSATION', 'VALUE_EXCHANGE', 'PROPOSED'].includes(p.stage)).map(partnerCard).join('')}
      ${pursuits.length ? `<h3>Partnership pursuits in the CRM (${pursuits.length})</h3>${pursuits.slice(0, 40).map(actionCard).join('')}` : ''}`;
  else if (f.tab === 'ACTIVE') body = recs.filter((p) => ['PILOT', 'ACTIVE', 'PRODUCTIVE', 'STRATEGIC'].includes(p.stage)).map(partnerCard).join('');
  else if (f.tab === 'DORMANT') body = recs.filter((p) => p.stage === 'DORMANT' || ['DORMANT', 'COOLING'].includes(p.health)).map(partnerCard).join('');
  else if (f.tab === 'EVENTS') body = eventOrgs.map((o) => `<div class="mini"><div class="t">${esc(o.name)} <span class="faint">(${esc(human(o.role))})</span> ${provPill(o.provenance)}</div>
      <div class="m">${esc(o.signal.title)} · ${urgPill(o.signal.urgency)}</div><div class="btn-row mt6">${o.company_id ? `<button class="btn small" data-modal="partner-edit" data-company="${o.company_id}" data-type="${['HOTEL', 'VENUE', 'OPERATOR'].includes(o.role) ? 'SUPPLY' : 'DISTRIBUTION'}">Track as partner</button>` : `<button class="btn small" data-org-crm="${o.id}">Add to CRM</button>`}<button class="btn small ghost" data-tab="radar">Open radar</button></div></div>`).join('');
  else body = openers.map(partnerCard).join('');
  return `<h2>Partnerships</h2>
    <p class="muted small"><b>Supply partners</b> help NOYA deliver (hotels, villas, transport, yachts, security, venues…). <b>Distribution partners</b> send NOYA business repeatedly (concierge firms, family offices, agencies, planners, brands…). <b>Productive</b> and <b>Strategic</b> are earned only by real opportunities, projects and revenue through the partner — never by prestige.</p>
    <div class="tabs">${Object.keys(tabs).map((k) => `<button data-paf="tab" data-v="${k}" class="${f.tab === k ? 'on' : ''}">${labels[k]} <span class="n">${tabs[k]}</span></button>`).join('')}</div>
    <div class="filters"><select data-paf="cls">${opt('', f.cls, 'Supply + distribution')}${opt('SUPPLY', f.cls, 'Supply / delivery')}${opt('DISTRIBUTION', f.cls, 'Distribution / revenue')}</select>
      <button class="btn small" data-modal="partner-edit">+ Partner</button><button class="btn small" data-modal="edge-add">Record an introduction</button></div>
    ${body || empty('Nothing here yet.')}`;
}

// ---------------------------------------------------------------- 05 · Events & experiences
const EVENT_CATS = ['SPORTS', 'ENTERTAINMENT', 'EVENTS', 'CORPORATE', 'WEDDINGS', 'PRODUCTION'];
function viewEvents() {
  const c = state.com; if (!c) return empty('Events not loaded.');
  const f = state.evF;
  const events = c.signals.filter((s) => s.stage !== 'DISMISSED' && (EVENT_CATS.includes(s.category) || playbook(s.playbook)?.track === 'EVENT'));
  const upcoming = events.filter((s) => s.urgency !== 'PASSED').sort((a, b) => String(a.event_date || '9999').localeCompare(String(b.event_date || '9999')));
  const winnable = upcoming.filter((s) => (s.opportunities || []).some((o) => !['WON', 'LOST', 'ARCHIVED'].includes(o.status)) || s.qualification?.complete);
  const won = c.projects.filter((p) => p.signal_id || /EVENT|GUEST|DESK/.test(p.project_type || ''));
  const needs = c.projects.filter((p) => ['CONFIRMED', 'PLANNING', 'LIVE'].includes(p.status) && (p.issues > 0 || p.open_tasks > 0));
  const tabs = { UPCOMING: upcoming.length, WIN: winnable.length, WON: won.length, ACTION: needs.length };
  const labels = { UPCOMING: 'Upcoming', WIN: 'What we can win', WON: 'Won', ACTION: 'Needs action' };
  const supply = c.supply_partners || {};
  const eventRow = (s) => { const pb = playbook(s.playbook); return `<article class="card signal-card"><div class="card-head"><div><div class="co">${esc(s.title)}</div>
      <div class="muted small">${esc(dateRange(s.event_date, s.event_end) || 'date not confirmed')} · ${esc(s.destination || '—')}</div></div><div class="pills">${urgPill(s.urgency)}${pill(SIG_STAGE[s.stage]?.[0] || s.stage)}</div></div>
      <div class="small">${pb ? `<b>What NOYA can win:</b> ${(pb.target_orgs || []).map((t) => `${esc(human(t.org_role))} → ${esc(PNAME(t.product))}`).join(' · ')}` : ''}</div>
      <div class="small mt6"><b>Organisations:</b> ${esc((s.orgs || []).map((o) => `${o.name} (${human(o.role)})`).join(', ') || 'not identified yet')}</div>
      <div class="small mt6"><b>Opportunities:</b> ${(s.opportunities || []).map((o) => `<button class="linkish" data-open="opp" data-id="${o.id}">${esc(o.company)} · ${esc(PNAME(o.product))}</button> ${pill(S(o.status))}`).join(' ') || '<span class="faint">none yet</span>'}</div>
      ${pb ? `<details class="small mt6"><summary>Suppliers and partners it needs</summary>${esc((pb.services || []).join(' · '))}<div class="faint mt6">Active supply partners on file: ${esc(Object.entries(supply).map(([k, n]) => `${k} ${n}`).join(' · ') || 'none recorded yet')}</div></details>` : ''}
      <div class="btn-row mt6"><button class="btn small" data-radar-q="${esc(s.title.slice(0, 30))}">Open in radar</button></div></article>`; };
  let body;
  if (f.tab === 'UPCOMING') body = upcoming.map(eventRow).join('');
  else if (f.tab === 'WIN') body = winnable.map(eventRow).join('');
  else body = (f.tab === 'WON' ? won : needs).map(projectCard).join('');
  return `<h2>Events & experiences</h2>
    <p class="muted small">Before we win: every event is an intelligence signal with several possible commercial targets (one event, many opportunities — never duplicated). After we win: the project runs in Operations with its guests, suppliers, schedule, budget and margin.</p>
    <div class="tabs">${Object.keys(tabs).map((k) => `<button data-evf="tab" data-v="${k}" class="${f.tab === k ? 'on' : ''}">${labels[k]} <span class="n">${tabs[k]}</span></button>`).join('')}</div>
    ${body || empty('Nothing here yet.')}`;
}

// ---------------------------------------------------------------- 07 · Operations (won work)
const perCur = (list) => { const o = {}; (list || []).forEach((x) => { if (x && x.currency && x.amount != null) o[x.currency] = (o[x.currency] || 0) + Number(x.amount); }); return Object.entries(o).map(([k, v]) => money(v, k)).join(' · ') || '—'; };
function projectCard(p) {
  const groups = {}; (p.items || []).forEach((i) => { (groups[i.item_type] = groups[i.item_type] || []).push(i); });
  return `<article class="card proj"><div class="card-head"><div><div class="co">${esc(p.name)}</div><div class="muted small">${esc(p.company || '—')} · ${esc(dateRange(p.starts_on, p.ends_on) || 'dates tbc')}${p.destination ? ` · ${esc(p.destination)}` : ''} · owner ${esc(p.owner || '—')}</div></div>
    <div class="pills">${pill(human(p.status), p.status === 'LIVE' ? 'bad' : ['DELIVERED', 'CLOSED'].includes(p.status) ? 'ok' : 'info')}${p.issues ? pill(`${p.issues} issue${p.issues > 1 ? 's' : ''}`, 'bad') : ''}${p.open_tasks ? pill(`${p.open_tasks} open tasks`, 'warn') : ''}</div></div>
    <div class="grid2 small">${kv('Client charge', esc(p.client_charge != null ? money(p.client_charge, p.currency) : 'not recorded'))}${kv('Supplier cost', esc(p.supplier_cost != null ? money(p.supplier_cost, p.currency) : 'not recorded'))}
      ${kv('Gross profit', esc(p.gross_profit != null ? money(p.gross_profit, p.currency) : '—'))}${kv('Invoiced / collected', `${esc(perCur(p.invoiced))} / ${esc(perCur(p.collected))}`)}</div>
    ${p.brief ? `<div class="small"><b>Brief:</b> ${esc(p.brief)}</div>` : ''}
    ${Object.entries(groups).map(([t, list]) => `<div class="small mt6"><b>${esc(human(t))}</b> ${list.map((i) => `<span class="item ${i.status === 'ISSUE' ? 'bad-text' : ''}">${esc(i.title)}${i.supplier ? ` (${esc(i.supplier)})` : ''} · ${esc(human(i.status))}</span> <button class="linkish" data-modal="project-item" data-id="${p.id}" data-draft="${i.id}">edit</button>`).join(' · ')}</div>`).join('')}
    ${p.feedback ? `<div class="small mt6"><b>Feedback:</b> ${esc(p.feedback)}</div>` : ''}
    <div class="btn-row mt6"><button class="btn small" data-modal="project-item" data-id="${p.id}">+ Item (guest, hotel, transfer, supplier, issue…)</button><button class="btn small" data-modal="project-edit" data-id="${p.id}">Update project</button>
      ${p.status === 'CONFIRMED' ? `<button class="btn small" data-proj-status="PLANNING" data-id="${p.id}">Planning</button>` : ''}${['CONFIRMED', 'PLANNING'].includes(p.status) ? `<button class="btn small" data-proj-status="LIVE" data-id="${p.id}">Live</button>` : ''}
      ${['PLANNING', 'LIVE'].includes(p.status) ? `<button class="btn small primary" data-proj-status="DELIVERED" data-id="${p.id}" title="Creates a feedback task (+2 days) and an expansion review (+14 days). No client message.">Delivered</button>` : ''}
      ${p.status === 'DELIVERED' ? `<button class="btn small" data-proj-status="CLOSED" data-id="${p.id}">Close</button>` : ''}${p.opportunity_id ? `<button class="btn small ghost" data-open="opp" data-id="${p.opportunity_id}">Opportunity</button>` : ''}</div></article>`;
}
function viewProjects() {
  const c = state.com; if (!c) return empty('Projects not loaded.');
  const active = c.projects.filter((p) => ['CONFIRMED', 'PLANNING', 'LIVE'].includes(p.status)); const done = c.projects.filter((p) => ['DELIVERED', 'CLOSED'].includes(p.status));
  return `<h2>Projects</h2>
    <p class="muted small">Won work, created automatically when an opportunity is marked Won. Money is shown per currency and only from recorded figures: client charge (contract), supplier cost (confirmed), gross profit, invoiced and collected (Finance). Delivering a project raises a feedback task and, later, one contextual expansion review — never an automatic client message.</p>
    <h3>Active (${active.length})</h3>${active.map(projectCard).join('') || empty('No active projects. Win an opportunity to create one.')}
    <h3>Delivered (${done.length})</h3>${done.map(projectCard).join('') || '<p class="muted small">None yet.</p>'}`;
}

// ---------------------------------------------------------------- 06 · Account intelligence (company drawer)
function accountBlock(id) {
  const a = state.account[id];
  if (!a) return '<p class="muted small">Loading account intelligence…</p>';
  if (a.error) return `<p class="bad-text small">Account intelligence unavailable: ${esc(a.error)}</p>`;
  const s = a.strength || {};
  return `<h3>Account intelligence</h3>
    <div class="grid2 small">${kv('Relationship strength', `${pill(s.label || 'NONE', s.label === 'STRONG' ? 'ok' : s.label === 'WARM' ? 'info' : '')} ${esc(s.score ?? 0)}/100 <span class="faint">(behaviour only)</span>`)}
      ${kv('Why now', esc(a.why_now || '—'))}${kv('Relevant NOYA services', esc((a.services || []).slice(0, 8).join(' · ') || '—'))}${kv('Partnership', a.partnership ? esc(`${human(a.partnership.partner_class)} · ${human(a.partnership.stage)}`) : '—')}</div>
    ${(s.components || []).length ? `<details class="small"><summary>How the strength is built</summary>${s.components.map((c) => `<div>+${esc(c.points)} ${esc(c.evidence)}</div>`).join('')}<div class="faint">${esc(s.method || '')}</div></details>` : ''}
    <h4>Routes in</h4>${(a.paths || []).map((p) => `<div class="mini"><div class="t">${esc(p.route)} ${provPill(p.provenance)}</div><div class="m">${esc(p.detail || '')}</div></div>`).join('') || '<p class="muted small">No route yet — no email history, contact, LinkedIn connection, introduction or shared-event partner.</p>'}
    ${(a.events || []).length ? `<h4>Events / signals</h4>${a.events.map((e) => `<div class="mini"><div class="t">${esc(e.title)} ${urgPill(e.urgency)}</div><div class="m">${esc(human(e.role))}${e.event_date ? ` · ${esc(fmtDay(e.event_date))}` : ''}${e.source_url ? ` · <a href="${esc(e.source_url)}" target="_blank" rel="noopener noreferrer">source</a>` : ''}</div></div>`).join('')}` : ''}
    ${(a.open_opportunities || []).length ? `<h4>Open opportunities</h4>${a.open_opportunities.map((o) => `<div class="mini clickable" data-open="opp" data-id="${o.id}"><div class="t">${esc(PNAME(o.product) || o.type)} · score ${esc(o.score)} ${pill(S(o.status))}</div><div class="m">${esc(o.angle || o.next_action || '')}</div></div>`).join('')}` : ''}
    ${(a.past_opportunities || []).length ? `<div class="small faint">Past: ${a.past_opportunities.map((o) => `${esc(o.type)} (${esc(S(o.status))})`).join(' · ')}</div>` : ''}
    ${(a.outreach_history || []).length ? `<details class="small mt6"><summary>Outreach history (${a.outreach_history.length})</summary>${a.outreach_history.slice(0, 20).map((h) => `<div>${esc(shortDay(h.at))} · ${esc(h.channel)} ${esc(String(h.direction || '').toLowerCase())} · ${esc(h.subject || '')} <span class="faint">${esc(h.summary || '')}</span>${h.thread ? ` · ${gmailLink(h.thread, 'Gmail')}` : ''}</div>`).join('')}</details>` : ''}
    ${(a.sources || []).length ? `<div class="small faint mt6">Sources: ${a.sources.map((u) => `<a href="${esc(/^https?:/.test(u) ? u : `https://${u}`)}" target="_blank" rel="noopener noreferrer">${esc(String(u).replace(/^https?:\/\//, '').slice(0, 40))}</a>`).join(' · ')}</div>` : ''}`;
}
async function loadAccount(id) {
  const { data, error } = await sb.rpc('hq_account', { p_company: id });
  state.account[id] = error ? { error: error.message } : data;
  render();
}

// ---------------------------------------------------------------- 01 · Command additions (action first)
function commandPanels() {
  const c = state.com; if (!c) return '';
  const hot = c.signals.filter((s) => ['RESEARCH', 'QUALIFIED'].includes(s.stage) && ['NOW', 'D7'].includes(s.urgency) && (s.relevance || 0) >= 75).slice(0, 5);
  const deals = c.queue.filter((x) => ['PROPOSAL', 'NEGOTIATION', 'DISCOVERY'].includes(x.stage)).slice(0, 5);
  const engagedNoMeeting = c.queue.filter((x) => x.stage === 'ENGAGED').slice(0, 3);
  const strategic = c.partners.filter((p) => ['PRODUCTIVE', 'STRATEGIC'].includes(p.stage) || (p.class === 'DISTRIBUTION' && p.stage === 'ACTIVE')).slice(0, 5);
  const dormantProductive = c.partners.filter((p) => p.health === 'DORMANT' && (p.opportunities || p.revenue_invoices));
  const projects = c.projects.filter((p) => ['CONFIRMED', 'PLANNING', 'LIVE'].includes(p.status)).slice(0, 5);
  const risks = [...c.projects.filter((p) => p.issues > 0).map((p) => [`${p.name}: ${p.issues} unresolved issue${p.issues > 1 ? 's' : ''}`, 'projects']),
    ...dormantProductive.map((p) => [`${p.name}: partner has gone quiet but has produced business before`, 'partners']),
    ...c.signals.filter((s) => s.urgency === 'NOW' && s.stage === 'RESEARCH' && !(s.qualification?.questions || [])[7]?.ok).slice(0, 3).map((s) => [`${s.title.slice(0, 70)} — act now, but no route in yet`, 'radar'])];
  const teamLoad = {}; (state.data?.tasks || []).filter((t) => openStatuses.includes(t.status)).forEach((t) => { const k = t.assigned_to || 'Unassigned'; teamLoad[k] = (teamLoad[k] || 0) + 1; });
  const li = (t, go, sub = '') => `<div class="mini clickable" data-go="${go}"><div class="t">${t}</div>${sub ? `<div class="m">${sub}</div>` : ''}</div>`;
  return `<div class="ov-grid3 mt8">
    <section class="panel"><header><h3>New high-quality opportunities</h3><button class="btn small ghost" data-go="radar">Radar</button></header><div class="body">
      ${hot.map((s) => li(`${urgPill(s.urgency)} ${esc(s.title.slice(0, 90))}`, 'radar', `${esc(s.qualification?.answered ?? 0)}/10 answered${s.qualification?.missing?.length ? ` · missing: ${esc(s.qualification.missing.join(', '))}` : ''}`)).join('') || '<div class="empty">Nothing urgent on the radar.</div>'}</div></section>
    <section class="panel"><header><h3>Meetings · proposals · negotiations</h3><button class="btn small ghost" data-go="actions">Queue</button></header><div class="body">
      ${[...engagedNoMeeting.map((x) => li(`${esc(x.company)} replied positively — meeting not booked yet`, 'actions', esc(x.next_action || ''))), ...deals.map((x) => li(`${esc(x.company)} · ${esc(SALES_STAGE[x.stage])}`, 'actions', esc(x.next_action || '')))].join('') || '<div class="empty">No live deals at meeting or proposal stage.</div>'}</div></section>
    <section class="panel"><header><h3>Strategic partnerships</h3><button class="btn small ghost" data-go="partners">Partners</button></header><div class="body">
      ${strategic.map((p) => li(`${esc(p.name)} · ${esc(human(p.stage))}`, 'partners', `${esc(p.opportunities)} opps · ${esc(p.revenue_invoices)} paid · ${esc(human(p.health))}`)).join('') || '<div class="empty">No partner has earned Productive / Strategic yet (needs real business through them).</div>'}</div></section>
    <section class="panel"><header><h3>Active projects</h3><button class="btn small ghost" data-go="projects">Operations</button></header><div class="body">
      ${projects.map((p) => li(`${esc(p.name)} · ${esc(human(p.status))}`, 'projects', `${p.issues ? `<span class="bad-text">${esc(p.issues)} issue(s)</span> · ` : ''}${esc(p.open_tasks)} open tasks`)).join('') || '<div class="empty">No active projects.</div>'}</div></section>
    <section class="panel"><header><h3>Risks / blockers</h3></header><div class="body">
      ${risks.map(([t, go]) => li(esc(t), go)).join('') || '<div class="empty">No commercial risks flagged.</div>'}</div></section>
    <section class="panel"><header><h3>Team action</h3><button class="btn small ghost" data-go="tasks">Tasks</button></header><div class="body">
      ${Object.entries(teamLoad).map(([k, n]) => `<div class="sig"><span>${esc(k)}</span><span class="faint">${esc(n)} open</span></div>`).join('') || '<div class="empty">No open tasks.</div>'}
      <div class="small faint mt6">Roles: ${esc(Object.entries(c.team?.routing || {}).map(([r, m]) => `${human(r)} → ${m}`).join(' · '))}</div></div></section>
  </div>`;
}
function teamPanel() {
  const c = state.com; if (!c) return '';
  return `<h3>Team & roles</h3><p class="muted small">Every opportunity and action has an owner. New work is routed by role; one person can hold every role today and the team can grow without changing the system.</p>
    <div class="tbl-wrap"><table><thead><tr><th>Role</th><th>Owner</th></tr></thead><tbody>${ROLES.map((r) => `<tr><td>${esc(human(r))}</td><td>${esc(c.team?.routing?.[r] || '—')}</td></tr>`).join('')}</tbody></table></div>
    <div class="btn-row"><button class="btn small" data-modal="role-route">Assign a role</button></div>`;
}

// ---------------------------------------------------------------- modals
const fld = (label, id, type = 'text', val = '', attrs = '') => `<label class="field"><span>${label}</span><input id="${id}" type="${type}" value="${esc(val ?? '')}" ${attrs}></label>`;
const area = (label, id, val = '', attrs = '') => `<label class="field"><span>${label}</span><textarea id="${id}" ${attrs}>${esc(val ?? '')}</textarea></label>`;
const sel = (label, id, options, curv = '') => `<label class="field"><span>${label}</span><select id="${id}">${options.map(([v, l]) => opt(v, curv, l)).join('')}</select></label>`;
const form = (title, body, ok = 'Save', danger = false) => `<div class="modal-bg"><div class="modal"><h3>${title}</h3>${body}
  <div class="btn-row"><button class="btn ${danger ? 'danger' : 'primary'}" id="m-ok">${ok}</button><button class="btn" data-close>Cancel</button></div></div></div>`;
const val = (id) => { const el = $(`#${id}`); if (!el) return null; const v = String(el.value ?? '').trim(); return v === '' ? null : v; };
const CHANNELS = [['LINKEDIN', 'LinkedIn'], ['EMAIL', 'Email'], ['PHONE', 'Phone call'], ['WHATSAPP', 'WhatsApp'], ['INSTAGRAM_DM', 'Instagram DM'], ['MEETING', 'Meeting'], ['OTHER', 'Other']];
const NOTE_KINDS = [['NOTE', 'Note'], ['HOW_WE_MET', 'How we met'], ['REFERRAL', 'Referral'], ['PROMISE', 'Promise / commitment'], ['PRIOR_PROJECT', 'Previous project'], ['SHARED_CONNECTION', 'Shared connection']];

function modalTitle(m) {
  const o = m.opp && opp(m.opp); const c = m.company && company(m.company);
  const k = m.contact && state.dir?.contacts.find((x) => x.id === m.contact); const n = m.conn && state.dir?.connections.find((x) => x.id === m.conn);
  return esc(o?.company_name || c?.name || k?.name || n?.name || '');
}
function renderAnyModal(m) {
  const who = modalTitle(m);
  switch (m.kind) {
    case 'task-done': case 'task-snooze': {
      const t = findTask(m.id) || {};
      return m.kind === 'task-done'
        ? `<div class="modal-bg"><div class="modal"><h3>Mark done</h3><p>${esc(sentence(t.title || ''))}</p>${fld('Note (optional)', 'task-note', 'text', '', 'maxlength="300"')}
            <div class="btn-row"><button class="btn primary" data-confirm-task="COMPLETE">Mark done</button><button class="btn" data-close>Cancel</button></div></div></div>`
        : `<div class="modal-bg"><div class="modal"><h3>Snooze</h3><p>${esc(sentence(t.title || ''))}</p>${fld('Until', 'task-until', 'date', isoPlus(2), `min="${isoPlus(1)}" max="${isoPlus(90)}"`)}${fld('Note (optional)', 'task-note', 'text', '', 'maxlength="300"')}
            <div class="btn-row"><button class="btn primary" data-confirm-task="SNOOZE">Snooze</button><button class="btn" data-close>Cancel</button></div></div></div>`;
    }
    case 'task-dismiss': { const t = findTask(m.id) || {}; return form('Not needed', `<p>${esc(sentence(t.title || ''))}</p><p class="small muted">The task is closed and kept in the history with your reason.</p>${fld('Reason (required)', 'f-reason', 'text', '', 'maxlength="300"')}`, 'Close task'); }
    case 'touch': {
      const lab = { LINKEDIN: 'Sent LinkedIn message', INSTAGRAM_DM: 'Sent Instagram DM', EMAIL: 'Followed up by email', PHONE: 'Called' }[m.channel] || '';
      return form(`Log contact${who ? ` — ${who}` : ''}`, `<p class="small muted">Records what you did. Nothing is sent from HQ.</p>
        ${sel('Channel', 'f-channel', CHANNELS, m.channel || 'LINKEDIN')}${sel('Direction', 'f-dir', [['OUTBOUND', 'I contacted them'], ['INBOUND', 'They contacted me']])}
        ${area('What happened', 'f-summary', lab, 'maxlength="2000"')}${fld('Outcome (optional)', 'f-outcome', 'text', '', 'maxlength="200"')}
        ${fld('Follow up on (optional)', 'f-follow', 'date', m.channel === 'MEETING' ? '' : isoPlus(5), `min="${isoPlus(1)}"`)}`, 'Save');
    }
    case 'meeting':
      return form(`Record meeting${who ? ` — ${who}` : ''}`, `${area('Summary (two lines is enough)', 'f-summary', '', 'maxlength="3000"')}
        ${fld('Outcome', 'f-outcome', 'text', '', 'maxlength="200" placeholder="e.g. Wants a proposal for March trip"')}
        ${sel('Move stage to', 'f-stage', [['', 'Keep current stage'], ...STAGES.map((s) => [s, S(s)])])}
        ${fld('Follow up on (optional)', 'f-follow', 'date', isoPlus(3))}${fld('Next meeting (optional)', 'f-next', 'date')}`, 'Save meeting');
    case 'note':
      return form(`Add note${who ? ` — ${who}` : ''}`, `${sel('Type', 'f-kind', NOTE_KINDS)}${area('Note', 'f-body', '', 'maxlength="4000"')}${fld('Remind me on (optional)', 'f-follow', 'date')}`, 'Save note');
    case 'stage': { const o = opp(m.opp) || {};
      return form(`Change stage — ${who}`, `${sel('Stage', 'f-stage', STAGES.map((s) => [s, S(s)]), o.status)}${fld('Next action', 'f-next', 'text', o.next_action || '', 'maxlength="300"')}${area('Note (optional)', 'f-note', '', 'maxlength="2000"')}`, 'Save'); }
    case 'channel':
      return form(`Change channel — ${who}`, `<p class="small muted">Switching away from email puts the email approval on hold and creates one task with the prepared message for the new channel. Instagram is refused for banks, wealth, law and consulting firms.</p>
        ${sel('New channel', 'f-channel', [['LINKEDIN', 'LinkedIn (Adam personally)'], ['INSTAGRAM', 'Instagram (NOYA)'], ['PHONE', 'Phone call'], ['EMAIL', 'Back to email']])}${fld('Why (optional)', 'f-note', 'text', '', 'maxlength="300"')}`, 'Change channel');
    case 'draft-request': {
      const cid = m.company || (m.opp && facts(m.opp).company_id) || (m.contact && state.dir?.contacts.find((x) => x.id === m.contact)?.company_id);
      const hist = state.rel && ((m.contact && state.rel.by_contact[m.contact]) || (cid && state.rel.by_company[cid]));
      const defType = m.type || (m.conn || hist ? 'RECONNECTION' : 'FIRST_MESSAGE');
      return form(`Draft a message${who ? ` — ${who}` : ''}`, `<p class="small muted">Usually ready within a minute, using only the facts on this record. You review, copy and send it yourself.</p>
        ${hist ? `<p class="small"><b>NOYA has emailed them before</b> (${hist.sent} sent, ${hist.received} replies) — this should be a follow-up or reconnection, not a first introduction.</p>` : ''}
        ${isClient(cid) ? '<p class="small bad-text">Client — handle personally. Use the draft only as a starting point.</p>' : ''}
        ${sel('Channel', 'f-channel', [['LINKEDIN', 'LinkedIn'], ['EMAIL', 'Email'], ['INSTAGRAM', 'Instagram'], ['WHATSAPP', 'WhatsApp']], m.channel || 'LINKEDIN')}
        ${sel('Voice', 'f-voice', [['ADAM_PERSONAL', 'Adam personally'], ['NOYA', 'NOYA']])}${sel('Type', 'f-type', MESSAGE_TYPES, defType)}
        ${area('Anything to include (optional)', 'f-note', '', 'maxlength="500" placeholder="e.g. we met at ITB; mention the Siwa villa"')}`, 'Request draft'); }
    case 'draft-edit': { const x = (state.dir?.drafts || []).find((y) => y.id === m.id) || {};
      return form('Edit draft', `${area('Message', 'f-text', x.draft || '', 'maxlength="3000" rows="10"')}`, 'Save'); }
    case 'conn-status': { const c = state.dir?.connections.find((x) => x.id === m.conn) || {};
      return form(`Update — ${who}`, `${sel('Status', 'f-status', CONNECTION_STATUS.map((s) => [s, sentence(s.replace(/_/g, ' '))]), c.status)}${fld('How you know them', 'f-how', 'text', c.how_we_know || '', 'maxlength="300"')}${fld('Next follow-up (optional)', 'f-follow', 'date', c.next_follow_up_at || '')}`, 'Save'); }
    case 'vertical': { const c = company(m.company) || {};
      return form(`Edit — ${who}`, `${sel('Vertical', 'f-vertical', [['AUTO', 'Automatic (from company type)'], ...Object.entries(VERTICAL_LABEL)], c.vertical_override || 'AUTO')}
        ${sel('Relationship', 'f-rel', [['', `Keep (${c.relationship_status || 'none'})`], ['prospect', 'Prospect'], ['client', 'Client'], ['partner', 'Partner'], ['supplier', 'Supplier'], ['mixed', 'Mixed'], ['inactive', 'Inactive']])}
        <div class="grid2">${fld('Country (from a reliable source)', 'f-country', 'text', c.country || '', 'maxlength="80"')}${fld('Website', 'f-web', 'text', c.website || '', 'maxlength="200"')}</div>
        <p class="small muted">Only fill the country from real evidence (their website, a signature, a call). Unknown stays unknown.</p>`, 'Save'); }
    case 'sig-capture':
      return form('Capture a signal', `<p class="small muted">Only real, sourced developments. The source link is required. Name only organisations that the source itself names.</p>
        ${fld('What happened (title)', 'f-title', 'text', '', 'maxlength="200"')}${fld('Source link', 'f-url', 'url', '', 'placeholder="https://…"')}
        <div class="grid2">${fld('Source name', 'f-srcname')}${fld('Destination', 'f-dest')}</div>
        ${area('Summary — facts stated in the source', 'f-summary', '', 'rows="3"')}${area('Why NOYA should care', 'f-why', '', 'rows="2"')}
        <div class="grid2">${fld('Event start', 'f-d1', 'date')}${fld('Event end', 'f-d2', 'date')}</div>
        ${area('Organisations named in the source — one per line: Name | ROLE', 'f-orgs', '', 'rows="3" placeholder="El Gouna Film Festival | ORGANISER"')}`, 'Capture');
    case 'sig-edit': { const s = (state.com?.signals || []).find((x) => x.id === m.id) || {};
      return form('Edit signal', `<div class="grid2">${fld('Event start', 'f-d1', 'date', s.event_date || '')}${fld('Event end', 'f-d2', 'date', s.event_end || '')}</div>
        ${sel('Playbook', 'f-pb', [['', 'None'], ...(state.com?.playbooks || []).map((p) => [p.code, p.name])], s.playbook || '')}
        <div class="grid2">${sel('Category', 'f-cat', Object.entries(CATEGORY_LABEL), s.category || 'OTHER')}${sel('Region', 'f-region', Object.entries(REGION_LABEL), s.region || 'EGYPT')}</div>
        <div class="grid2">${sel('Owner', 'f-owner', teamOptions(), s.owner || 'Adam')}${fld('Next action due', 'f-due', 'date', s.next_action_due || '')}</div>
        ${fld('Next action', 'f-next', 'text', s.next_action || '', 'maxlength="300"')}
        ${area('Why NOYA should care', 'f-why', s.why || '', 'rows="2"')}${area('Problem NOYA solves for them', 'f-problem', s.problem || '', 'rows="2"')}${area('Commercial angle', 'f-angle', s.angle || '', 'rows="2"')}`, 'Save'); }
    case 'sig-dismiss':
      return form('Dismiss this signal', `${area('Why is it not worth pursuing? (kept, so the system learns)', 'f-reason', '', 'rows="2"')}`, 'Dismiss', true);
    case 'sig-org':
      return form('Add an organisation', `${fld('Organisation', 'f-org', 'text', '', 'maxlength="120"')}${sel('Role around this signal', 'f-role', ORG_ROLES.map((r) => [r, human(r)]), 'ORGANISER')}
        ${fld('Evidence — where it is named', 'f-evidence', 'text', '', 'maxlength="300"')}${sel('Existing company (optional)', 'f-company', companyOptions(), '')}`, 'Add');
    case 'sig-promote': { const s = (state.com?.signals || []).find((x) => x.id === m.id) || {}; const pb = playbook(s.playbook) || {};
      const prodFor = (role) => (pb.target_orgs || []).find((t) => t.org_role === role)?.product || (s.products || [])[0] || '';
      const trackFor = (role) => (pb.target_orgs || []).find((t) => t.org_role === role)?.track || pb.track || 'SALES';
      return form('Create commercial opportunities', `<p class="small muted">One event, several opportunities — one per organisation and product. The event itself is not duplicated. Organisations without a contact get a find-the-decision-maker task; nothing is sent.</p>
        ${(s.orgs || []).map((o, i) => `<div class="promote-row"><label class="check"><input type="checkbox" id="f-t-${i}" data-org="${o.id}" ${i < 4 ? 'checked' : ''}> <b>${esc(o.name)}</b> <span class="faint">(${esc(human(o.role))})</span></label>
          <div class="grid2">${sel('Product', `f-p-${i}`, (state.com?.products || []).map((p) => [p.code, PNAME(p.code)]), prodFor(o.role))}${sel('Track', `f-k-${i}`, [['EVENT', 'Event'], ['SALES', 'Sales'], ['PARTNERSHIP', 'Partnership']], trackFor(o.role))}</div></div>`).join('') || '<p class="bad-text small">Add at least one organisation named in the source first.</p>'}`, 'Create'); }
    case 'opp-commercial': { const x = (state.com?.queue || []).find((q) => q.id === m.id) || {};
      return form(`Commercial — ${esc(x.company || '')}`, `${scoreTable(x.score)}
        <div class="grid2">${sel('Product', 'f-prod', [['', 'None'], ...(state.com?.products || []).map((p) => [p.code, PNAME(p.code)])], x.product || '')}${sel('Playbook', 'f-pb', [['', 'None'], ...(state.com?.playbooks || []).map((p) => [p.code, p.name])], x.playbook || '')}</div>
        <div class="grid2">${sel('Track', 'f-track', [['SALES', 'Sales'], ['PARTNERSHIP', 'Partnership'], ['EVENT', 'Event']], x.track || 'SALES')}${sel('Owner', 'f-owner', teamOptions(), x.owner || 'Adam')}</div>
        <div class="grid2">${fld('Next action', 'f-next', 'text', x.next_action || '', 'maxlength="300"')}${fld('Due', 'f-due', 'date', x.due || '')}</div>
        ${area('Angle', 'f-angle', x.angle || '', 'rows="2"')}
        <h4>Money — only with evidence (never an estimate)</h4>
        <div class="grid2">${fld('Client-stated budget', 'f-budget', 'number', x.client_budget ?? '', 'min="0" step="0.01"')}${fld('Proposal value', 'f-proposal', 'number', x.proposal_value ?? '', 'min="0" step="0.01"')}</div>
        <div class="grid2">${fld('Contracted value', 'f-contract', 'number', x.contracted_value ?? '', 'min="0" step="0.01"')}${fld('Currency', 'f-cur', 'text', x.currency || '', 'maxlength="3" placeholder="GBP / USD / EUR / EGP"')}</div>
        ${fld('Evidence (who said it, where — e.g. "Proposal sent 3 Oct, email")', 'f-evidence', 'text', x.value_evidence || '', 'maxlength="300"')}
        <h4>Priority override (optional)</h4><div class="grid2">${fld('Override score (0–100, empty = none)', 'f-override', 'number', x.score?.override?.score ?? '', 'min="0" max="100"')}${fld('Reason (required with an override)', 'f-oreason', 'text', x.score?.override?.reason || '')}</div>`, 'Save'); }
    case 'partner-edit': { const p = (state.com?.partners || []).find((x) => x.company_id === m.company && (!m.type || x.class === m.type)) || {};
      return form(m.company ? `Partnership — ${esc(company(m.company)?.name || p.name || '')}` : 'New partner', `${m.company ? '' : sel('Company', 'f-company', companyOptions(), '')}
        <div class="grid2">${sel('Type', 'f-class', [['SUPPLY', 'Supply / delivery'], ['DISTRIBUTION', 'Distribution / revenue']], p.class || m.type || 'DISTRIBUTION')}${sel('Stage', 'f-stage', PARTNER_STAGES.map((s) => [s, human(s)]), p.stage || 'TARGET')}</div>
        <p class="small faint">Productive needs at least one opportunity, project or paid invoice through the partner; Strategic needs paid revenue plus two or more. The system checks.</p>
        <div class="grid2">${fld('Category', 'f-cat', 'text', p.category || '', 'placeholder="Hotel, yacht, concierge firm, agency…"')}${fld('Geography', 'f-geo', 'text', p.geography || '')}</div>
        ${area('What they provide NOYA', 'f-gives', p.provides_noya || '', 'rows="2"')}${area('What NOYA provides them', 'f-gets', p.noya_provides || '', 'rows="2"')}
        <div class="grid2">${fld('Commercial terms', 'f-terms', 'text', p.terms || '')}${fld('Preferred rates', 'f-rates', 'text', p.rates || '')}</div>
        <div class="grid2">${fld('Commission / referral', 'f-comm', 'text', p.commission || '')}${fld('Exclusivity', 'f-excl', 'text', p.exclusivity || '')}</div>
        <div class="grid2">${fld('Next action', 'f-next', 'text', p.next_action || '')}${fld('Due', 'f-due', 'date', p.next_action_due || '')}</div>${sel('Relationship owner', 'f-owner', teamOptions(), p.owner || 'Adam')}`, 'Save'); }
    case 'project-edit': { const p = (state.com?.projects || []).find((x) => x.id === m.id) || {};
      return form(`Project — ${esc(p.name || '')}`, `${sel('Status', 'f-status', ['CONFIRMED', 'PLANNING', 'LIVE', 'DELIVERED', 'CLOSED', 'CANCELLED'].map((s) => [s, human(s)]), p.status || 'CONFIRMED')}
        <div class="grid2">${fld('Starts', 'f-d1', 'date', p.starts_on || '')}${fld('Ends', 'f-d2', 'date', p.ends_on || '')}</div>
        <div class="grid2">${fld('Destination', 'f-dest', 'text', p.destination || '')}${fld('Attendees', 'f-att', 'number', p.attendees ?? '', 'min="0"')}</div>
        ${area('Brief', 'f-brief', p.brief || '', 'rows="3"')}
        <div class="grid2">${fld('Client charge (contract)', 'f-charge', 'number', p.client_charge ?? '', 'min="0" step="0.01"')}${fld('Supplier cost (confirmed)', 'f-cost', 'number', p.supplier_cost ?? '', 'min="0" step="0.01"')}</div>
        <div class="grid2">${fld('Currency', 'f-cur', 'text', p.currency || '', 'maxlength="3"')}${sel('Owner', 'f-owner', teamOptions(), p.owner || 'Adam')}</div>
        ${area('Client feedback', 'f-feedback', p.feedback || '', 'rows="2"')}`, 'Save'); }
    case 'project-item': { const p = (state.com?.projects || []).find((x) => x.id === m.id) || {}; const it = (p.items || []).find((i) => i.id === m.draft) || {};
      return form(it.id ? 'Edit item' : `Add to ${esc(p.name || 'project')}`, `<div class="grid2">${sel('Type', 'f-type', ITEM_TYPES.map((t) => [t, human(t)]), it.item_type || 'HOTEL')}${sel('Status', 'f-status', ['OPEN', 'CONFIRMED', 'DONE', 'ISSUE', 'CANCELLED'].map((s) => [s, human(s)]), it.status || 'OPEN')}</div>
        ${fld('Title', 'f-title', 'text', it.title || '', 'maxlength="160"')}${area('Detail', 'f-detail', it.detail || '', 'rows="2"')}
        <div class="grid2">${sel('Supplier (optional)', 'f-supplier', companyOptions(), it.supplier_company_id || '')}${fld('When', 'f-when', 'datetime-local', it.starts_at ? String(it.starts_at).slice(0, 16) : '')}</div>
        <div class="grid2">${fld('Cost', 'f-cost', 'number', it.cost ?? '', 'min="0" step="0.01"')}${fld('Charge', 'f-charge', 'number', it.charge ?? '', 'min="0" step="0.01"')}</div>
        ${fld('Currency', 'f-cur', 'text', it.currency || p.currency || '', 'maxlength="3"')}${it.id ? '<label class="check"><input type="checkbox" id="f-del"> Remove this item</label>' : ''}`, 'Save'); }
    case 'edge-add':
      return form('Record a real relationship', `<p class="small muted">Only what really happened — e.g. "Sara (Aman) introduced us to Brand X", "Agency Y works with Brand Z". Evidence is required.</p>
        ${sel('From (company)', 'f-from', companyOptions(), '')}${fld('…or from a person / name', 'f-fromlabel', 'text', '', 'maxlength="120"')}
        ${sel('Relationship', 'f-rel', [['INTRODUCED', 'Introduced NOYA to'], ['REFERRED', 'Referred business to NOYA from'], ['WORKS_WITH', 'Works with']], 'INTRODUCED')}
        ${sel('To (company)', 'f-to', companyOptions(), m.company || '')}${fld('Evidence', 'f-evidence', 'text', '', 'maxlength="300" placeholder="Email 12 Oct from Sara; meeting note…"')}`, 'Save');
    case 'role-route':
      return form('Assign a role', `${sel('Role', 'f-role', ROLES.map((r) => [r, human(r)]), 'SALES')}${fld('Team member name', 'f-member', 'text', '', 'maxlength="80"')}${fld('Email (optional)', 'f-email', 'email')}
        <p class="small faint">New work for this role is assigned to this person from now on. Existing owners are not changed.</p>`, 'Assign');
    case 'service-edit': { const v = (state.ins?.services || []).find((x) => x.id === m.id) || {};
      return form(`Update cost — ${esc(v.service || '')}`, `<p class="small muted">Only enter what an invoice or plan page shows. Leave the amount empty if it is not known — it stays UNKNOWN. This changes the register only; it never buys or upgrades anything.</p>
        ${fld('Plan', 'f-plan', 'text', v.current_plan || '', 'maxlength="160"')}
        <div class="grid2">${sel('Cost type', 'f-ctype', Object.entries(COST_TYPE), v.cost_type)}${sel('Confirmed from an invoice / plan page?', 'f-verified', [['true', 'Yes'], ['false', 'Not yet']], String(!!v.verified))}</div>
        <div class="grid2">${fld('Monthly cost (empty = UNKNOWN)', 'f-cost', 'number', v.monthly_cost ?? '', 'min="0" step="0.01"')}${fld('Currency', 'f-ccur', 'text', v.currency || '', 'maxlength="3" placeholder="GBP / USD / EUR"')}</div>
        <div class="grid2">${fld('Usage cost', 'f-ucost', 'text', v.usage_cost || '', 'maxlength="160"')}${fld('Limit / allowance', 'f-limit', 'text', v.usage_limit || '', 'maxlength="160"')}</div>
        ${fld('Renewal date', 'f-renew', 'date', v.renewal_date || '')}
        ${area('Evidence (invoice number, date, where you saw it)', 'f-evidence', v.verification_note || '', 'rows="3" maxlength="600"')}`, 'Save'); }
    case 'finance': {
      const r = m.id ? state.ins.finance.records.find((x) => x.id === m.id) || {} : {};
      const locked = r.id && r.status !== 'DRAFT';
      const cos = (state.dir?.companies || []).slice().sort((a, b) => a.name.localeCompare(b.name));
      const defCo = r.company_id || m.company || (m.opp && facts(m.opp).company_id) || '';
      return form(r.id ? 'Edit finance record' : 'New finance record', `
        ${sel('Client', 'f-company', [['', 'Choose…'], ...cos.map((c) => [c.id, c.name])], defCo)}
        <div class="grid2">${fld('Currency', 'f-cur', 'text', r.currency || 'GBP', `maxlength="3" ${locked ? 'disabled' : ''}`)}${fld('Gross amount', 'f-amount', 'number', r.gross_amount ?? '', `min="0" step="0.01" ${locked ? 'disabled' : ''}`)}</div>
        ${locked ? '<p class="small muted">Issued amount is locked. Cancel and re-issue to change it.</p>' : ''}
        ${fld('What for', 'f-desc', 'text', r.description || '', 'maxlength="300"')}
        <div class="grid2">${fld('Invoice reference', 'f-ref', 'text', r.invoice_reference || '', 'maxlength="60"')}${fld('Due date', 'f-due', 'date', r.due_at || '')}</div>
        ${sel('Status', 'f-status', [['DRAFT', 'Draft (not issued)'], ['SENT', 'Sent to client'], ['CANCELLED', 'Cancelled']], r.id ? (r.status === 'DRAFT' ? 'DRAFT' : r.status === 'CANCELLED' ? 'CANCELLED' : 'SENT') : 'DRAFT')}
        ${area('Notes (optional)', 'f-notes', r.notes || '', 'maxlength="1000"')}`, 'Save'); }
    case 'payment': { const r = state.ins.finance.records.find((x) => x.id === m.id) || {};
      return form(`Record payment — ${esc(r.company || '')}`, `<p class="small">Outstanding: <b>${esc(money(r.outstanding, r.currency))}</b></p>
        ${fld(`Amount received (${esc(r.currency || '')})`, 'f-amount', 'number', r.outstanding ?? '', `min="0.01" max="${r.outstanding ?? ''}" step="0.01"`)}
        ${fld('Date received', 'f-date', 'date', todayKey(), `max="${todayKey()}"`)}${fld('Method (optional)', 'f-method', 'text', '', 'maxlength="60" placeholder="Bank transfer"')}
        ${fld('Reference (optional)', 'f-ref', 'text', '', 'maxlength="100"')}`, 'Record payment'); }
    case 'new-opp':
      return form('New opportunity', `<p class="small muted">If the company already exists (same name or website) it is reused — no duplicates. Emails you enter are saved as unverified.</p>
        ${fld('Company', 'f-co', 'text', '', 'maxlength="200"')}<div class="grid2">${fld('Website', 'f-web')}${fld('Country', 'f-country')}</div>
        ${fld('What is the opportunity', 'f-type', 'text', '', 'maxlength="300" placeholder="e.g. Incentive trip to Egypt for 40 staff"')}
        <div class="grid2">${fld('Destination', 'f-dest', 'text', 'Egypt')}${fld('Next action', 'f-next', 'text', '', 'maxlength="300"')}</div>
        <div class="grid2">${fld('Contact first name', 'f-first')}${fld('Last name', 'f-last')}</div>
        <div class="grid2">${fld('Role', 'f-role')}${fld('Email', 'f-email', 'email')}</div>${fld('LinkedIn URL', 'f-li', 'url')}
        ${area('Note (optional)', 'f-note', '', 'maxlength="1000"')}`, 'Create');
    case 'quick':
      return `<div class="modal-bg"><div class="modal"><h3>New</h3><div class="quick">
        <button class="btn" data-modal="new-opp">Add opportunity</button><button class="btn" data-modal="new-contact">Add contact</button>
        <button class="btn" data-modal="followup">Add follow-up</button><button class="btn" data-modal="pick" data-next="draft-request">Draft LinkedIn / email message</button>
        <button class="btn" data-modal="pick" data-next="note">Add relationship note</button><button class="btn" data-modal="pick" data-next="meeting-pick">Record meeting</button>
        <button class="btn" data-go="finance">Record payment</button></div>
        <div class="btn-row"><button class="btn" data-close>Close</button></div></div></div>`;
    case 'pick': {
      const cos = (state.dir?.companies || []).slice().sort((a, b) => a.name.localeCompare(b.name));
      return form(m.next === 'note' ? 'Add relationship note — who?' : m.next === 'meeting-pick' ? 'Record meeting — which company?' : 'Draft a message — who?',
        `${sel('Company', 'f-company', [['', 'Choose…'], ...cos.map((c) => [c.id, c.name])])}<p class="small muted">Not in the list? Use Add contact or Add opportunity first.</p>`, 'Next'); }
    case 'new-contact': {
      const cos = (state.dir?.companies || []).slice().sort((a, b) => a.name.localeCompare(b.name));
      return form('Add contact', `<p class="small muted">Reuses an existing person (same email, or same name at the company). An email you type is saved as unverified.</p>
        <div class="grid2">${fld('First name', 'f-first')}${fld('Last name', 'f-last')}</div>
        ${sel('Company', 'f-company', [['', 'New or none (type below)'], ...cos.map((c) => [c.id, c.name])])}${fld('…or new company name', 'f-co', 'text', '', 'maxlength="200"')}
        <div class="grid2">${fld('Role', 'f-role')}${fld('Email', 'f-email', 'email')}</div>${fld('LinkedIn URL', 'f-li', 'url')}${area('Note (optional)', 'f-note', '', 'maxlength="1000"')}`, 'Add'); }
    case 'followup': {
      const cos = (state.dir?.companies || []).slice().sort((a, b) => a.name.localeCompare(b.name));
      return form('Add follow-up', `${sel('Company', 'f-company', [['', 'Choose…'], ...cos.map((c) => [c.id, c.name])], m.company || '')}
        ${area('What to follow up on', 'f-body', '', 'maxlength="1000"')}${fld('When', 'f-follow', 'date', isoPlus(3), `min="${isoPlus(0)}"`)}`, 'Add follow-up'); }
    case 'history-add': {
      const g = (state.rel?.groups || []).find((x) => x.key === m.id) || {};
      const guess = g.domain ? g.domain.split('.')[0].replace(/[-_]/g, ' ').replace(/\b\w/g, (ch) => ch.toUpperCase()) : '';
      const nm = String(g.from_name || '').replace(/\s*\(.*\)$/, '').split(/\s+/);
      return form(`Add to CRM — ${esc(g.name || '')}`, `<p class="small muted">Creates (or reuses) the company by its email domain and the person by email, then links the ${g.threads} email thread(s) to their record. The address is marked as evidenced by the mailbox, not provider-verified.</p>
        ${fld('Company name', 'f-co', 'text', g.company || guess, 'maxlength="200"')}${fld('Country (if known)', 'f-country', 'text', '', 'maxlength="80"')}
        <div class="grid2">${fld('First name', 'f-first', 'text', nm[0] || '')}${fld('Last name', 'f-last', 'text', nm.slice(1).join(' '))}</div>
        ${fld('Role (if known)', 'f-role')}${sel('Email', 'f-email', (g.emails || []).map((e) => [e, e]), g.reply_from || (g.emails || [])[0])}`, 'Add to CRM'); }
    case 'account':
      return `<div class="modal-bg"><div class="modal"><h3>Account</h3><p class="small muted">Signed in as ${esc(state.session?.user?.email || '')}</p>
        <div class="quick"><button class="btn" id="acct-pw">Change password</button><button class="btn danger" id="acct-out">Sign out</button></div>
        <div class="btn-row"><button class="btn" data-close>Close</button></div></div></div>`;
    case 'import': {
      const rows = m.rows || [];
      return form('Import LinkedIn connections', `<p><b>${rows.length}</b> connections found${m.skipped ? `, ${m.skipped} lines skipped (no profile link)` : ''}${m.dups ? `, ${m.dups} duplicate lines ignored` : ''}.</p>
        <p class="small muted">Saved: name, company, position, profile link, connected date${rows.some((r) => r.email) ? ', and email where the person shared it with you' : ''}. Nothing else. Re-importing updates existing people.</p>
        <p class="small">${rows.slice(0, 3).map((r) => esc(`${r.first_name || ''} ${r.last_name || ''} — ${r.company || ''}`)).join('<br>')}${rows.length > 3 ? '<br>…' : ''}</p>`, `Import ${rows.length}`);
    }
    default: return renderModal(m);
  }
}

async function submitModal() {
  const m = state.modal; const btn = $('#m-ok'); if (btn) btn.disabled = true;
  const done = async (fn, args, text) => { state.modal = null; return call(fn, args, text); };
  // Validation message shown inside the form — never re-render (that would wipe what was typed).
  const need = (v, msg) => {
    if (v) return true;
    const modal = $('.modal'); let el = modal && modal.querySelector('.m-err');
    if (modal && !el) { el = document.createElement('p'); el.className = 'm-err banner err small'; modal.insertBefore(el, modal.querySelector('.btn-row')); }
    if (el) el.textContent = msg; else { state.notice = { err: true, text: msg }; render(); }
    if (btn) btn.disabled = false; return false;
  };
  switch (m.kind) {
    case 'task-dismiss': { const r = val('f-reason'); if (!need(r, 'A reason is required.')) return; return done('hq_task_dismiss', { p_task: m.id, p_reason: r }, 'Task closed.'); }
    case 'touch': { const s = val('f-summary'); if (!need(s, 'Say briefly what happened.')) return;
      const r = await done('hq_log_touch', { p_channel: val('f-channel'), p_summary: s, p_company: m.company || null, p_contact: m.contact || null, p_opportunity: m.opp || null,
        p_connection: m.conn || null, p_task: m.task || null, p_follow_up: val('f-follow'), p_outcome: val('f-outcome'), p_direction: val('f-dir') },
        `Logged.${val('f-follow') ? '' : ''}`);
      if (r?.ok && m.draft) await call('hq_draft_action', { p_draft: m.draft, p_action: 'USED', p_text: null }, 'Logged, and the draft is marked as used.');
      return r; }
    case 'meeting': { const s = val('f-summary'); if (!need(s, 'A short summary is required.')) return;
      return done('hq_record_meeting', { p_opportunity: m.opp, p_summary: s, p_outcome: val('f-outcome'), p_new_status: val('f-stage'), p_follow_up: val('f-follow'), p_next_meeting: val('f-next'), p_task: m.task || null }, 'Meeting recorded.'); }
    case 'note': { const b = val('f-body'); if (!need(b, 'Write the note first.')) return;
      return done('hq_add_note', { p_kind: val('f-kind'), p_body: b, p_company: m.company || null, p_contact: m.contact || null, p_opportunity: m.opp || null, p_connection: m.conn || null, p_follow_up: val('f-follow') }, 'Note saved.'); }
    case 'stage': return done('hq_opportunity_update', { p_opportunity: m.opp, p_status: val('f-stage'), p_next_action: val('f-next'), p_note: val('f-note') }, 'Stage updated.');
    case 'channel': return done('hq_change_channel', { p_opportunity: m.opp, p_channel: val('f-channel'), p_note: val('f-note') }, 'Channel changed. The message task is in Outreach.');
    case 'draft-request': {
      const r = await done('hq_request_draft', { p_channel: val('f-channel'), p_voice: val('f-voice'), p_type: val('f-type'), p_connection: m.conn || null, p_contact: m.contact || null,
        p_company: m.company || null, p_opportunity: m.opp || null, p_note: val('f-note') }, 'Draft requested — it appears under LinkedIn → Drafts within about 15 minutes (08:00–22:00 Cairo).');
      if (r?.existing) state.notice = { err: false, text: 'A draft of this type is already requested for this person — see LinkedIn → Drafts.' };
      render(); return r; }
    case 'draft-edit': { const t = val('f-text'); if (!need(t, 'The message is empty.')) return; return done('hq_draft_action', { p_draft: m.id, p_action: 'SAVE', p_text: t }, 'Draft saved.'); }
    case 'conn-status': return done('hq_connection_update', { p_connection: m.conn, p_status: val('f-status'), p_how_we_know: val('f-how'), p_follow_up: val('f-follow') }, 'Updated.');
    case 'sig-capture': {
      if (!need(val('f-title') && val('f-url'), 'A title and a source link are required — no source, no signal.')) return;
      const orgs = String(val('f-orgs') || '').split('\n').map((l) => l.split('|').map((x) => x.trim())).filter((x) => x[0]).map(([name, role]) => ({ name, role: (role || 'OTHER').toUpperCase().replace(/\s+/g, '_') }));
      return done('hq_signal_capture', { p: { title: val('f-title'), source_url: val('f-url'), source_name: val('f-srcname'), destination: val('f-dest'), summary: val('f-summary'),
        why: val('f-why'), event_date: val('f-d1'), event_end: val('f-d2'), orgs } }, 'Signal captured — it is now on the radar with its playbook and qualification.'); }
    case 'sig-edit':
      return done('hq_signal_update', { p_id: m.id, p: { event_date: val('f-d1'), event_end: val('f-d2'), playbook_code: val('f-pb'), category: val('f-cat'), region: val('f-region'),
        owner: val('f-owner'), next_action: val('f-next'), next_action_due: val('f-due'), why: val('f-why'), problem_noya_solves: val('f-problem'), commercial_angle: val('f-angle') } }, 'Signal updated.');
    case 'sig-dismiss':
      if (!need(val('f-reason'), 'Say why — it is kept so the radar learns.')) return;
      return done('hq_signal_update', { p_id: m.id, p: { stage: 'DISMISSED', dismissed_reason: val('f-reason') } }, 'Signal dismissed (reason kept).');
    case 'sig-org':
      if (!need(val('f-org'), 'Name the organisation.')) return;
      return done('hq_signal_org', { p_signal: m.id, p_org_name: val('f-org'), p_role: val('f-role'), p_evidence: val('f-evidence'), p_company: val('f-company'), p_remove: null }, 'Organisation added.');
    case 'sig-promote': {
      const targets = [...document.querySelectorAll('.modal input[id^="f-t-"]')].filter((el) => el.checked).map((el) => { const i = el.id.slice(4);
        return { org_id: el.dataset.org, product: val(`f-p-${i}`), track: val(`f-k-${i}`) }; });
      if (!need(targets.length, 'Choose at least one organisation.')) return;
      const r = await done('hq_signal_promote', { p_signal: m.id, p_targets: targets }, 'Opportunities created in Sales & Outreach.');
      if (r?.ok) { state.notice = { err: false, text: `${r.created.length} opportunit${r.created.length === 1 ? 'y' : 'ies'} created (${r.created.map((x) => x.company).join(', ')}) — see Action queue.` }; render(); }
      return r; }
    case 'opp-commercial': {
      const x0 = (state.com?.queue || []).find((q) => q.id === m.id) || {};
      const money3 = [val('f-budget'), val('f-proposal'), val('f-contract')].some((v) => v != null);
      if (!need(!money3 || (val('f-cur') && val('f-evidence')), 'A money value needs its currency and written evidence.')) return;
      if (!need(val('f-override') == null || val('f-oreason'), 'An override needs a reason.')) return;
      return done('hq_opportunity_commercial', { p_opp: m.id, p: { product_code: val('f-prod'), playbook_code: val('f-pb'), track: val('f-track'), owner: val('f-owner'),
        next_action: val('f-next'), next_action_due: val('f-due'), angle: val('f-angle'), client_budget: val('f-budget'), proposal_value: val('f-proposal'),
        contracted_value: val('f-contract'), currency: val('f-cur'), value_evidence: val('f-evidence'),
        ...(String(val('f-override') ?? '') !== String(x0.score?.override?.score ?? '') || (val('f-override') != null && val('f-oreason') !== (x0.score?.override?.reason || null))
          ? { score_override: val('f-override'), score_override_reason: val('f-oreason') } : {}) } }, 'Saved.'); }
    case 'partner-edit': {
      const co = m.company || val('f-company'); if (!need(co, 'Choose the company.')) return;
      return done('hq_partner_upsert', { p_company: co, p_class: val('f-class'), p: { stage: val('f-stage'), category: val('f-cat'), geography: val('f-geo'), provides_noya: val('f-gives'),
        noya_provides: val('f-gets'), terms: val('f-terms'), rates: val('f-rates'), commission: val('f-comm'), exclusivity: val('f-excl'), next_action: val('f-next'), next_action_due: val('f-due'), owner: val('f-owner') } }, 'Partnership saved.'); }
    case 'project-edit':
      return done('hq_project_update', { p_project: m.id, p: { status: val('f-status'), starts_on: val('f-d1'), ends_on: val('f-d2'), destination: val('f-dest'), attendees: val('f-att'),
        brief: val('f-brief'), client_charge: val('f-charge'), supplier_cost: val('f-cost'), currency: val('f-cur'), owner: val('f-owner'), feedback: val('f-feedback') } }, 'Project updated.');
    case 'project-item':
      if (!need($('#f-del')?.checked || val('f-title'), 'Give the item a title.')) return;
      return done('hq_project_item', { p_project: m.id, p_item: m.draft || null, p: $('#f-del')?.checked ? { delete: true } : { item_type: val('f-type'), status: val('f-status'), title: val('f-title'),
        detail: val('f-detail'), supplier_company_id: val('f-supplier'), starts_at: val('f-when'), cost: val('f-cost'), charge: val('f-charge'), currency: val('f-cur') } }, 'Project item saved.');
    case 'edge-add': {
      const from = val('f-from'); const to = val('f-to');
      if (!need((from || val('f-fromlabel')) && to && val('f-evidence'), 'From, to and evidence are all required.')) return;
      return done('hq_edge_add', { p: { from_type: from ? 'COMPANY' : 'PERSON', from_id: from, from_label: from ? company(from)?.name : val('f-fromlabel'), relation: val('f-rel'),
        to_type: 'COMPANY', to_id: to, to_label: company(to)?.name, evidence: val('f-evidence') } }, 'Relationship recorded (with evidence).'); }
    case 'role-route':
      if (!need(val('f-member'), 'Name the team member.')) return;
      return done('hq_role_route', { p_role: val('f-role'), p_member: val('f-member'), p_email: val('f-email') }, 'Role assigned.');
    case 'service-edit': {
      const cost = val('f-cost'); const ccy = val('f-ccur');
      if (cost != null && !ccy) { // flag on the field itself so nothing typed is lost
        const el = $('#f-ccur'); el.setCustomValidity('Add the currency for this amount (no conversion is ever applied).'); el.reportValidity();
        el.addEventListener('input', () => el.setCustomValidity(''), { once: true }); if (btn) btn.disabled = false; return; }
      return done('hq_service_update', { p_id: m.id, p: { current_plan: val('f-plan'), cost_type: val('f-ctype'), verified: val('f-verified') === 'true', monthly_cost: cost,
        currency: ccy, usage_cost: val('f-ucost'), usage_limit: val('f-limit'), renewal_date: val('f-renew'), verification_note: val('f-evidence') } }, 'Cost register updated.'); }
    case 'vertical': return done('hq_company_update', { p_company: m.company, p_vertical: val('f-vertical'), p_relationship: val('f-rel'), p_country: val('f-country'), p_website: val('f-web') }, 'Company updated.');
    case 'finance': {
      const r = m.id ? state.ins.finance.records.find((x) => x.id === m.id) : null;
      const co = val('f-company'); if (!need(co || m.opp, 'Choose the client.')) return;
      const amount = r && r.status !== 'DRAFT' ? r.gross_amount : Number(val('f-amount'));
      const currency = r && r.status !== 'DRAFT' ? r.currency : (val('f-cur') || '').toUpperCase();
      return done('hq_finance_upsert', { p_id: m.id || null, p_company: co, p_opportunity: r?.opportunity_id || m.opp || null, p_currency: currency, p_amount: amount,
        p_description: val('f-desc'), p_invoice_ref: val('f-ref'), p_due: val('f-due'), p_invoice_status: val('f-status'), p_revenue_type: null, p_notes: val('f-notes') }, 'Finance record saved.'); }
    case 'payment': return done('hq_record_payment', { p_revenue: m.id, p_amount: Number(val('f-amount')), p_paid_at: val('f-date'), p_method: val('f-method'), p_reference: val('f-ref'), p_note: null }, 'Payment recorded.');
    case 'pick': {
      const co = val('f-company'); if (!need(co, 'Choose a company.')) return;
      if (m.next === 'meeting-pick') {
        const o = state.data.opportunities.filter((x) => facts(x.id).company_id === co).sort((a, b) => ACTIVE(b.status) - ACTIVE(a.status) || new Date(b.updated_at) - new Date(a.updated_at))[0];
        if (!o) { state.modal = null; state.notice = { err: true, text: 'This company has no opportunity yet — add one first (+ New → Add opportunity).' }; render(); return null; }
        state.modal = { kind: 'meeting', opp: o.id }; render(); return null;
      }
      state.modal = { kind: m.next, company: co, channel: m.next === 'draft-request' ? 'LINKEDIN' : null }; render(); return null; }
    case 'new-contact': {
      if (!need(val('f-first') || val('f-last'), 'A name is required.')) return;
      const r = await done('hq_add_contact', { p_company_id: val('f-company'), p_company_name: val('f-co'), p_first: val('f-first'), p_last: val('f-last'), p_role: val('f-role'),
        p_email: val('f-email'), p_linkedin: val('f-li'), p_note: val('f-note') }, 'Contact added.');
      if (r?.ok) { state.notice = { err: false, text: r.reused ? 'This person already existed — opened their record (no duplicate).' : 'Contact added.' }; openDrawer('contact', r.contact_id); }
      return r; }
    case 'followup': {
      const co = val('f-company'); const b = val('f-body'); if (!need(co && b && val('f-follow'), 'Company, what and when are required.')) return;
      return done('hq_add_note', { p_kind: 'NOTE', p_body: b, p_company: co, p_contact: null, p_opportunity: null, p_connection: null, p_follow_up: val('f-follow') }, 'Follow-up added — it will appear in Today on that date.'); }
    case 'history-add': {
      if (!need(val('f-co') || val('f-email'), 'A company name or an email is required.')) return;
      const r = await done('hq_history_action', { p_key: m.id, p_action: 'ADD_TO_CRM', p_company_name: val('f-co'), p_first: val('f-first'), p_last: val('f-last'),
        p_role: val('f-role'), p_email: val('f-email'), p_country: val('f-country') }, 'Added to the CRM with its email history.');
      if (r?.ok && r.company_id) openDrawer('company', r.company_id); else if (r?.ok && r.contact_id) openDrawer('contact', r.contact_id);
      return r; }
    case 'new-opp': {
      if (!need(val('f-co') && val('f-type'), 'Company and opportunity are required.')) return;
      const r = await done('hq_create_opportunity', { p_company_name: val('f-co'), p_website: val('f-web'), p_country: val('f-country'), p_opportunity_type: val('f-type'),
        p_next_action: val('f-next'), p_contact_first: val('f-first'), p_contact_last: val('f-last'), p_contact_role: val('f-role'), p_contact_email: val('f-email'),
        p_contact_linkedin: val('f-li'), p_destination: val('f-dest'), p_note: val('f-note') }, 'Opportunity created.');
      if (r?.ok) { state.notice = { err: false, text: r.company_reused ? 'Opportunity created under the existing company (no duplicate).' : 'Opportunity and company created.' }; openDrawer('opp', r.opportunity_id); }
      return r; }
    case 'import': {
      const rows = m.rows || []; state.modal = null; let nw = 0; let upd = 0; let dup = m.dups || 0; let skip = m.skipped || 0; let err = null;
      state.notice = { err: false, text: `Importing ${rows.length} connections…` }; render();
      for (let i = 0; i < rows.length; i += 500) {
        const { data, error } = await sb.rpc('hq_import_connections', { p_rows: rows.slice(i, i + 500) });
        if (error || data?.ok === false) { err = error?.message || explain(data); break; }
        nw += data.new ?? data.upserted ?? 0; upd += data.updated ?? 0; dup += data.duplicates ?? 0; skip += data.skipped ?? 0;
        state.notice = { err: false, text: `Importing… ${Math.min(i + 500, rows.length)} of ${rows.length}` }; render();
      }
      const summary = `${nw} new, ${upd} already known (updated)${dup ? `, ${dup} duplicates ignored` : ''}${skip ? `, ${skip} skipped (no profile link)` : ''}`;
      state.notice = err ? { err: true, text: `Import stopped after ${nw + upd}: ${err}` } : { err: false, text: `LinkedIn import done: ${summary}. People linked to NOYA are listed first.` };
      state.netF.only = 'known';
      await load(true); return null; }
    default: return null;
  }
}

// LinkedIn "Connections.csv": a few lines of notes, then the header row. Parsed in the browser.
function parseCsv(text) {
  const out = []; let row = []; let f = ''; let q = false;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (q) { if (ch === '"' && text[i + 1] === '"') { f += '"'; i += 1; } else if (ch === '"') q = false; else f += ch; }
    else if (ch === '"') q = true;
    else if (ch === ',') { row.push(f); f = ''; }
    else if (ch === '\n' || ch === '\r') { if (ch === '\r' && text[i + 1] === '\n') i += 1; row.push(f); out.push(row); row = []; f = ''; }
    else f += ch;
  }
  if (f || row.length) { row.push(f); out.push(row); }
  return out;
}
const MONTHS = { jan: '01', feb: '02', mar: '03', apr: '04', may: '05', jun: '06', jul: '07', aug: '08', sep: '09', oct: '10', nov: '11', dec: '12' };
function liDate(s) {
  const m = String(s || '').trim().match(/^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})$/);
  return m && MONTHS[m[2].toLowerCase()] ? `${m[3]}-${MONTHS[m[2].toLowerCase()]}-${m[1].padStart(2, '0')}` : null;
}
function parseConnections(text) {
  const rows = parseCsv(String(text).replace(/^﻿/, ''));
  const h = rows.findIndex((r) => r.some((c) => /^first name$/i.test(c.trim())) && r.some((c) => /^url$/i.test(c.trim())));
  if (h < 0) return { error: 'This does not look like LinkedIn\'s Connections.csv (no "First Name" / "URL" header).' };
  const idx = (n) => rows[h].findIndex((c) => c.trim().toLowerCase() === n);
  const I = { first: idx('first name'), last: idx('last name'), url: idx('url'), email: idx('email address'), company: idx('company'), position: idx('position'), on: idx('connected on') };
  const good = []; let skipped = 0; let dups = 0; const seen = new Set();
  rows.slice(h + 1).forEach((r) => {
    if (r.every((c) => !c.trim())) return;
    const url = (r[I.url] || '').trim();
    const slug = (url.toLowerCase().match(/linkedin\.com\/in\/([^/?#\s]+)/) || [])[1];
    if (!slug) { skipped += 1; return; }
    if (seen.has(slug)) { dups += 1; return; } // same person twice in the file (www / country sub-domain / trailing slash)
    seen.add(slug);
    good.push({ first_name: r[I.first] || null, last_name: r[I.last] || null, url, email: I.email >= 0 ? (r[I.email] || null) : null,
      company: r[I.company] || null, position: r[I.position] || null, connected_on: liDate(r[I.on]) });
  });
  return { rows: good, skipped, dups };
}

// ---------------------------------------------------------------- events
function openDrawer(kind, id) {
  state.drawer = { kind, id }; state.q = ''; state.menu = false; render();
  const tk = { opp: 'opportunity', company: 'company', contact: 'contact' }[kind];
  if (tk && !state.timeline[`${tk}:${id}`]) loadTimeline(tk, id);
  if (kind === 'company' && !state.account[id]) loadAccount(id);
}
async function copyText(t) {
  try { await navigator.clipboard.writeText(t); state.notice = { err: false, text: 'Copied. Paste it into LinkedIn / Instagram, send, then press Mark sent.' }; }
  catch { state.notice = { err: true, text: 'Could not copy automatically — select the message text and copy it.' }; }
  render();
}

function bind() {
  document.querySelectorAll('[data-flex]').forEach((el) => { el.style.flex = el.dataset.flex; });
  document.querySelectorAll('[data-w]').forEach((el) => { el.style.width = `${el.dataset.w}%`; });
  const on = (sel2, ev, fn) => document.querySelectorAll(sel2).forEach((el) => el.addEventListener(ev, (e) => fn(el, e)));
  on('[data-tab]', 'click', (b) => { state.tab = b.dataset.tab; state.notice = null; state.q = ''; state.menu = false; state.drawer = null; render(); window.scrollTo(0, 0); });
  on('[data-go]', 'click', (b, e) => {
    e.stopPropagation(); state.tab = b.dataset.go; if (b.dataset.otab) state.outreachTab = b.dataset.otab;
    state.drawer = null; state.modal = null; state.q = ''; state.menu = false; render();
    const anchor = b.dataset.anchor && document.getElementById(b.dataset.anchor);
    if (anchor) anchor.scrollIntoView({ block: 'start' }); else window.scrollTo(0, 0);
  });
  on('[data-otab]:not([data-go])', 'click', (b) => { state.outreachTab = b.dataset.otab; state.oIdx = 0; render(); });
  on('[data-open]', 'click', (b, e) => { e.stopPropagation(); openDrawer(b.dataset.open, b.dataset.id); });
  on('[data-close-drawer]', 'click', () => { state.drawer = null; render(); });
  on('[data-modal]', 'click', (b, e) => { e.stopPropagation(); const x = b.dataset; state.menu = false;
    state.modal = { kind: x.modal, id: x.id || null, opp: x.opp || null, task: x.task || null, channel: x.channel || null, conn: x.conn || null, contact: x.contact || null, company: x.company || null, draft: x.draft || null, next: x.next || null, type: x.type || null }; render(); });
  on('[data-hist-act]', 'click', (b) => call('hq_history_action', { p_key: b.dataset.id, p_action: b.dataset.histAct }, b.dataset.histAct === 'DISMISS' ? 'Hidden from the list (kept in the history).' : 'Restored.'));
  on('[data-relq]', 'click', (b, e) => { e.stopPropagation(); state.relF = { tab: 'ALL', q: b.dataset.relq }; state.tab = 'relationships'; state.q = ''; render(); window.scrollTo(0, 0); });
  on('button[data-rf]', 'click', (b) => { state.relF.tab = b.dataset.v; state.relF.i = 0; render(); });
  on('[data-one-toggle]', 'click', () => { state.oneByOne = !state.oneByOne; state.oIdx = 0; try { localStorage.setItem('hq.oneByOne', state.oneByOne ? '1' : ''); } catch { /* private mode */ } render(); });
  on('[data-o-step]', 'click', (b) => { state.oIdx = Math.max(0, (state.oIdx || 0) + Number(b.dataset.oStep)); render(); window.scrollTo(0, 0); });
  on('button[data-rdf]', 'click', (b) => { state.radarF[b.dataset.rdf] = b.dataset.v; render(); });
  on('input[data-rdf], select[data-rdf]', 'change', (el) => { state.radarF[el.dataset.rdf] = el.value; render(); });
  on('[data-radar-q]', 'click', (b) => { state.radarF = { h: 'ALL', region: '', cat: '', q: b.dataset.radarQ }; state.tab = 'radar'; render(); window.scrollTo(0, 0); });
  on('button[data-acf]', 'click', (b) => { state.actF[b.dataset.acf] = b.dataset.v; render(); });
  on('select[data-acf]', 'change', (el) => { state.actF[el.dataset.acf] = el.value; render(); });
  on('button[data-paf]', 'click', (b) => { state.parF[b.dataset.paf] = b.dataset.v; render(); });
  on('select[data-paf]', 'change', (el) => { state.parF[el.dataset.paf] = el.value; render(); });
  on('button[data-evf]', 'click', (b) => { state.evF[b.dataset.evf] = b.dataset.v; render(); });
  on('[data-sig-stage]', 'click', async (b) => {
    const r = await call('hq_signal_update', { p_id: b.dataset.id, p: { stage: b.dataset.sigStage } }, `Signal moved to ${SIG_STAGE[b.dataset.sigStage]?.[0] || b.dataset.sigStage}.`);
    if (r && r.ok === false && r.missing) { state.notice = { err: true, text: `Not qualified yet — still missing: ${r.missing.join(' · ')}` }; render(); }
  });
  on('[data-org-crm]', 'click', (b) => call('hq_signal_org_to_crm', { p_org: b.dataset.orgCrm }, 'In the CRM — a find-the-decision-maker task is in Tasks. Record a real person with Add contact.'));
  on('[data-prep-outreach]', 'click', async (b) => {
    const r = await call('hq_prepare_outreach', { p_opp: b.dataset.prepOutreach, p_contact: null }, 'Outreach drafted from the product template — approve it in Sales & Outreach → Outreach → Ready (nothing is sent).');
    if (r && r.ok === false) { state.notice = { err: true, text: `Not ready: missing ${(r.missing || []).join(', ') || r.reason}. ${(r.missing || []).includes('contact') ? 'Add a real contact at the company first.' : ''}` }; render(); }
  });
  on('[data-proj-status]', 'click', (b) => call('hq_project_update', { p_project: b.dataset.id, p: { status: b.dataset.projStatus } },
    b.dataset.projStatus === 'DELIVERED' ? 'Delivered — feedback task in 2 days, expansion review in 14 days (internal only).' : 'Project updated.'));
  on('[data-rel-step]', 'click', (b) => { state.relF.i = Math.max(0, (state.relF.i || 0) + Number(b.dataset.relStep)); render(); });
  on('[data-rel-status]', 'click', async (b) => {
    // Fast path for phone review: save, update the card in place, move on; refresh everything in the background.
    const k = b.dataset.relStatus; const g = (state.rel?.groups || []).find((x) => x.key === b.dataset.id); if (!g) return;
    document.querySelectorAll(`[data-rel-status][data-id="${CSS.escape(g.key)}"]`).forEach((el) => { el.disabled = true; });
    const { data, error } = await sb.rpc('hq_relationship_status', { p_key: g.key, p_status: k });
    if (error || data?.ok === false) { state.notice = { err: true, text: error ? error.message : explain(data) }; render(); return; }
    g.review = { ...(g.review || {}), status: k, status_at: new Date().toISOString() };
    g.dismissed = k === 'NOT_RELEVANT' ? 'DISMISSED' : null;
    state.notice = { err: false, text: `${g.name}: ${REL_STATUS[k][0]}. ${REL_STATUS[k][2]}` };
    render(); load(true);
  });
  on('input[data-rf]', 'change', (el) => { state.relF.q = el.value; render(); });
  on('[data-copy]', 'click', (b, e) => { e.stopPropagation(); copyText(b.dataset.copy); });
  on('[data-draft-act]', 'click', (b) => call('hq_draft_action', { p_draft: b.dataset.id, p_action: b.dataset.draftAct, p_text: null }, b.dataset.draftAct === 'RETRY' ? 'Draft re-requested.' : 'Draft discarded.'));
  on('[data-confirm-task]', 'click', (b) => confirmTask(b.dataset.confirmTask));
  $('#m-ok')?.addEventListener('click', submitModal);
  on('[data-act]', 'click', async (b) => {
    if (b.dataset.act === 'redispatch') { await call('hq_redispatch', { p_outbound_id: b.dataset.id }, 'Draft creation re-requested.'); state.pollUntil = Date.now() + 120000; return; }
    state.modal = { kind: b.dataset.act, id: b.dataset.id }; render();
  });
  on('[data-confirm]', 'click', (b) => confirmModal(b.dataset.confirm));
  on('[data-close]', 'click', () => { state.modal = null; render(); });
  on('[data-close-menu]', 'click', () => { state.menu = false; render(); });
  $('#queue-all')?.addEventListener('click', () => { state.queueAll = !state.queueAll; render(); });
  $('#queue-p3')?.addEventListener('click', () => { state.queueP3 = !state.queueP3; render(); });
  $('#q')?.addEventListener('input', (e) => { state.q = e.target.value; state.focusSearch = true; render(); });
  $('#q')?.addEventListener('keydown', (e) => { if (e.key === 'Escape') { state.q = ''; render(); } });
  $('#refresh')?.addEventListener('click', () => load());
  $('#quick')?.addEventListener('click', () => { state.modal = { kind: 'quick' }; render(); });
  $('#menu')?.addEventListener('click', () => { state.modal = { kind: 'account' }; render(); });
  $('#acct-pw')?.addEventListener('click', () => { state.modal = 'password'; render(); });
  $('#acct-out')?.addEventListener('click', async () => { state.modal = null; await sb.auth.signOut(); });
  $('#bmenu')?.addEventListener('click', () => { state.menu = !state.menu; render(); });
  $('#bsearch')?.addEventListener('click', () => { state.menu = false; render(); const q = $('#q'); q?.focus(); window.scrollTo(0, 0); });
  // tasks
  on('[data-when]', 'click', (b) => { state.taskFilter.when = b.dataset.when; render(); });
  on('[data-f]', 'change', (s) => { state.taskFilter[s.dataset.f] = s.value; render(); });
  // pipeline / directory filters
  on('[data-pf]', 'change', (el) => { state.pipeF[el.dataset.pf] = el.type === 'checkbox' ? el.checked : el.value; render(); });
  on('[data-pview]', 'click', (b) => { state.pipeView = b.dataset.pview; render(); });
  on('[data-cf]', 'change', (el) => { state.contactF[el.dataset.cf] = el.value; render(); });
  on('button[data-cof]', 'click', (b) => { state.companyF[b.dataset.cof] = b.dataset.v; render(); });
  on('input[data-cof], select[data-cof]', 'change', (el) => { state.companyF[el.dataset.cof] = el.value; render(); });
  on('button[data-nf]', 'click', (b) => { state.netF[b.dataset.nf] = b.dataset.v; render(); });
  on('input[data-nf], select[data-nf]', 'change', (el) => { state.netF[el.dataset.nf] = el.value; render(); });
  on('[data-market]', 'click', (r) => { state.pipeF = { stage: '', vertical: '', market: r.dataset.market, q: '', stale: false }; state.tab = 'pipeline'; render(); window.scrollTo(0, 0); });
  $('#li-file')?.addEventListener('change', async (e) => {
    const file = e.target.files?.[0]; if (!file) return;
    if (file.size > 20 * 1024 * 1024) { state.notice = { err: true, text: 'File is larger than 20 MB — choose Connections.csv only.' }; render(); return; }
    const res = parseConnections(await file.text());
    if (res.error) { state.notice = { err: true, text: res.error }; render(); return; }
    state.modal = { kind: 'import', rows: res.rows, skipped: res.skipped, dups: res.dups }; render();
  });
}

const VIEWS = { overview: viewOverview, outreach: viewOutreach, relationships: viewRelationships, linkedin: viewLinkedin, pipeline: viewPipeline, inbox: viewInbox, tasks: viewTasks, website: viewWebsite,
  contacts: viewContacts, companies: viewCompanies, finance: viewFinance, costs: viewCosts, markets: viewMarkets, growth: viewGrowth,
  intelligence: viewIntelligence, reports: viewReports, system: (d) => viewSystem(d) + teamPanel(), help: viewHelp,
  radar: viewRadar, library: viewLibrary, actions: viewActions, partners: viewPartners, events: viewEvents, projects: viewProjects };

// Refresh: every 60s normally, every 5s for two minutes after an approval. Paused while typing,
// or while a modal / record / menu is open.
setInterval(() => {
  if (!state.session || state.modal || state.drawer || state.menu || state.q || mustChangePassword()) return;
  const fast = Date.now() < state.pollUntil;
  const tick = Math.floor(Date.now() / 5000);
  if (fast || tick % 12 === 0) load(true);
}, 5000);

initAuth();
