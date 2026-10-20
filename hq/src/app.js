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

// HQ V3 (Adam, 9 Oct): six destinations — one screen, one job. Everything that existed before stays reachable under More,
// unchanged; nothing was deleted. Agents' old floor, email desk, radar and feed live under More → Agents & intelligence.
// Studio joined the primary navigation on 19 Oct (Destination Egypt mission): it is operational, so it is no longer under More.
const PRIMARY = [['dashboard', 'Dashboard'], ['agents', 'Agents'], ['desk', 'Outreach'], ['studio', 'Studio'], ['relations', 'Relationships'], ['club', 'Club'], ['ops', 'Operations']];
const MORE = [
  ['Agents & intelligence', [['emails', 'Email opportunities'], ['agentradar', 'Opportunity radar'], ['feed', 'Activity feed (classic)'], ['agentfloor', 'Agent floor (classic)'], ['radar', 'Signal radar'], ['intelligence', 'Market intel'], ['markets', 'Markets'], ['growth', 'Growth reports'], ['library', 'Products & playbooks']]],
  ['Sales', [['overview', 'Command (classic)'], ['actions', 'Action queue'], ['inbox', 'Replies'], ['outreach', 'Outreach (classic)'], ['linkedin', 'LinkedIn'], ['website', 'Website leads'], ['partners', 'Partnerships'], ['events', 'Events']]],
  ['Records', [['relationships', 'Past relationships'], ['companies', 'Companies'], ['contacts', 'Contacts'], ['pipeline', 'Pipeline'], ['projects', 'Projects'], ['tasks', 'Tasks']]],
  ['Admin', [['reports', 'Reports'], ['finance', 'Revenue & finance'], ['costs', 'System costs'], ['system', 'System health'], ['help', 'Help & playbook']]],
];
const NAV = [['HQ', PRIMARY], ...MORE];
const MORE_KEYS = MORE.flatMap(([, items]) => items.map(([k]) => k));
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
  session: null, data: null, ov: null, dir: null, ins: null, errors: {}, notice: null, tab: 'dashboard', loading: false,
  desk: null, ops: null, directors: null, club: null, busy: {}, dirKey: null, dirDetail: {}, dirSec: {}, more: false, feedAll: false, feedDir: '',
  deskTab: 'TOP5', deskCh: 'EMAIL', deskDir: '', deskProj: '', deskMore: null, ceo: null, net: null, deskPage: 0, deskOpen: {}, deskSrc: {}, relTab: 'IMPORTANT', clubTab: 'PRIVATE',
  modal: null, drawer: null, timeline: {}, q: '', queueAll: false, queueP3: false, menu: false,
  com: null, account: {}, radarF: { h: 'ALL', region: '', cat: '', q: '' }, actF: { view: 'TODAY', seg: '', owner: '', track: '' }, parF: { tab: 'DEVELOP', cls: '' }, evF: { tab: 'UPCOMING' },
  rel: null, relF: { tab: 'REVIEW', q: '', i: 0 }, oneByOne: (() => { try { return !!localStorage.getItem('hq.oneByOne'); } catch { return false; } })(), oIdx: 0, outreachTab: 'EMAIL REVIEW', pipeView: 'table', pipeF: { stage: '', vertical: '', market: '', q: '', stale: false },
  contactF: { q: '', email: '' }, companyF: { q: '', vertical: '', market: '' }, netF: { q: '', only: 'known' }, liHist: {},
  taskFilter: { when: 'all', dept: '', prio: '', owner: '', status: '' }, pollUntil: 0,
  cmd: null, health: null, integ: null, scWin: 'd7', studio: null, studioAll: {},
  agents: null, agentsLoading: false, agentDetail: {}, agentSec: {}, agentKey: null, emailF: { s: 'ALL', v: '' }, emailN: 30, emailOpen: null, gapOpen: null, radarAg: '', feedAg: '',
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
const pill = (text, cls = '') => `<span class="pill ${cls}">${esc(String(text ?? '').replace(/_/g, ' '))}</span>`;
// Human text: drop a leading internal code ("CODE_NAME — …") and spell out any remaining SNAKE_CASE token.
const plainText = (t) => String(t || '').replace(/^[A-Z0-9]+(?:_[A-Z0-9]+)+\s*[—:-]+\s*/, '').replace(/\b[A-Z0-9]+(?:_[A-Z0-9]+)+\b/g, (m) => m.toLowerCase().replace(/_/g, ' '));

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
  const label = { VERIFIED: 'Email verified', UNVERIFIED: 'Public · not verified', NOT_FOUND: 'No email', INVALID: 'Email invalid', RISKY: 'Email risky' }[s] || 'Email unknown';
  return `${pill(label, cls)}${kind === 'OFFICIAL_COMPANY_INBOX' ? ' ' + pill('company inbox') : ''}`;
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
// ---------------------------------------------------------------- DATA LOADING (17 Oct production fix)
// The heavy CEO reads (Dashboard model, network, Advisor, the workforce, execution) are served from background snapshots
// (hq_cached, refreshed by pg_cron every 5 minutes); everything else is read live. Reads go out in small waves, never 14 at
// once, and each section shows its own state, so one slow read never blanks a screen. Raw errors stay in state.errors for
// More / Admin → System; CEO screens only ever say "Some data is temporarily unavailable" with a Retry.
const READS = { data: 'hq_dashboard', ov: 'hq_overview', dir: 'hq_directory', ins: 'hq_insight', rel: 'hq_relationships', com: 'hq_commercial',
  er: 'hq_email_review', desk: 'hq_outreach_desk', ops: 'hq_operations', club: 'hq_club', studio: 'hq_studio' };
const SNAPSHOTS = { ceo: 'ceo', cmd: 'command', net: 'network', advisor: 'advisor', directors: 'directors', exec: 'execution', health: 'health', integ: 'integrity' };
const COM_TABS = ['radar', 'library', 'actions', 'partners', 'events', 'projects', 'system'];
const errKey = (k) => (k === 'data' ? 'main' : k);
async function readKey(k) {
  if (state.busy[k]) return false;
  state.busy[k] = true;
  const snap = SNAPSHOTS[k];
  const { data, error } = snap ? await sb.rpc('hq_cached', { p_key: snap }) : await sb.rpc(READS[k]);
  state.busy[k] = false;
  const notReady = snap && data && data.ok === false && data.reason && Object.keys(data).length <= 2;
  if (error || notReady) { state.errors[errKey(k)] = error ? error.message : `snapshot ${data.reason}`; return false; }
  state[k] = data; delete state.errors[errKey(k)]; return true;
}
const WAVES = {
  full: () => [['data', 'desk', 'ceo', 'cmd', 'net'], ['ov', 'dir', 'rel', 'ops', 'directors', 'exec'], ['ins', 'advisor', 'com', ...(state.tab === 'outreach' ? ['er'] : [])]],
  light: () => [['desk', 'ceo', 'cmd', 'net', 'directors', 'advisor']],
  write: () => [['data', 'desk', 'cmd'], ['ov', 'dir', 'rel', 'ops', ...(COM_TABS.includes(state.tab) ? ['com'] : []), ...(state.tab === 'outreach' ? ['er'] : [])]],
  desk: () => [['desk']],
};
async function load(silent = false, scope = 'full') {
  if (state.inflight) return;
  state.inflight = true;
  if (!silent) { state.loading = true; render(); }
  if (scope === 'full' || scope === 'light') { if (!state.advisorSeen) { state.advisorSeen = true; sb.rpc('hq_advisor_seen'); } }
  for (const wave of WAVES[scope]()) { await Promise.all(wave.map(readKey)); state.loading = false; render(); }
  state.inflight = false;
  if (state.tab === 'club' && state.club) readKey('club').then(render);
  if (['studio', 'agents'].includes(state.tab) && state.studio) readKey('studio').then(render);
  if (state.tab === 'director' && state.dirKey) loadDirector(state.dirKey, true);
  if (state.agents && AGENT_TABS.includes(state.tab)) { loadAgents(true); if (state.tab === 'agent' && state.agentKey) loadAgent(state.agentKey, true); }
}
// Load one read on demand (a section that needs data no wave has fetched yet), then redraw.
const ensure = (k) => { if (!state[k] && !state.busy[k] && !state.errors[errKey(k)]) readKey(k).then(render); };

async function loadLinkedInHistory(id) {
  if (state.busy[`lih:${id}`]) return;
  state.busy[`lih:${id}`] = true;
  const { data, error } = await sb.rpc('hq_linkedin_history', { p_connection: id });
  state.busy[`lih:${id}`] = false; state.liHist[id] = error ? { error: error.message } : (data || []);
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
  if (error) { state.notice = { err: true, text: friendly(error.message) }; state.errors.lastAction = `${fn}: ${error.message}`; render(); return null; }
  if (data && data.ok === false) state.notice = { err: true, text: explain(data) };
  else state.notice = { err: false, text: successText };
  state.timeline = {}; state.account = {};
  await load(true, 'write');
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
    SEND_DISABLED: 'Sending from HQ is switched off. Approve creates an unsent Gmail draft; you press Send in Gmail.',
    NOT_AWAITING_REVIEW: 'This email is not waiting for review any more (approved, sent, on hold or skipped). Refresh.',
    CANDIDATE_NOT_FOUND: 'This draft no longer exists. Refresh.',
    NOT_AN_EMAIL: 'This is not an email draft.',
    UNKNOWN_KIND: 'Unknown Studio request.',
    ALREADY_REQUESTED: 'This is already requested for that company. It is in Studio under Needs brief.',
  };
  if (reason.startsWith('EMAIL_NOT_VERIFIED')) return `Blocked: the email is ${String(reason.split(':')[1] || 'not verified').toLowerCase().replace('_', ' ')}, not SMTP-verified. Only verified emails become Gmail drafts.`;
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
  if (key === 'dashboard' && d) { const n = todayItems(d).count; return n ? `<span class="badge hot">${n}</span>` : ''; }
  if (key === 'desk' && state.desk) { const n = state.desk.counts.needs_review.total; return n ? `<span class="badge">${n}</span>` : ''; }
  if (key === 'relations') key = 'relationships';
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
  // A failed refresh of data already on screen: say the figures may be out of date (sections without data show their own state).
  const staleErr = Object.keys(state.errors).some((k) => k !== 'main' && k !== 'lastAction' && (k === 'data' ? state.data : state[k]) != null);
  $('#app').innerHTML = `
    <div class="shell">
      <div class="side-col"><aside class="side">
        <div class="brand">${__HAS_LOGO__ ? '<img src="/noya-mark.svg" alt="">' : ''}<span class="word">NOYA<small>HQ · Private office</small></span></div>
        <nav class="nav-primary">${PRIMARY.map(([k, l]) => `<button class="nav-item ${state.tab === k || (k === 'agents' && state.tab === 'director') ? 'active' : ''}" data-tab="${k}"><span>${l}</span>${navBadge(k)}</button>`).join('')}</nav>
        <button class="nav-more ${moreOpen() ? 'open' : ''}" id="nav-more">More / Admin</button>
        ${moreOpen() ? MORE.map(([g, items]) => `<div class="nav-group"><h6>${g}</h6>${items.map(([k, l]) => `<button class="nav-item ${state.tab === k ? 'active' : ''}" data-tab="${k}"><span>${l}</span>${navBadge(k)}</button>`).join('')}</div>`).join('') : ''}
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
          ${state.errors.main && /not authorised/i.test(state.errors.main) ? '<div class="banner err">This account is not authorised for NOYA HQ.</div>' : ''}
          ${staleErr && d ? `<div class="unavail top"><span>Some figures may be out of date: the last refresh did not complete.</span><button class="btn small" data-retry="all">Retry</button></div>` : ''}
          ${d && view ? view(d) : state.loading || !state.errors.main ? '<p class="muted">Loading HQ…</p>' : /not authorised/i.test(state.errors.main) ? '' : unavailable('all')}
        </main>
      </div>
    </div>
    <nav class="bnav">
      ${[['dashboard', 'Dashboard'], ['agents', 'Agents'], ['desk', 'Outreach'], ['relations', 'Relationships']].map(([k, l]) => `<button data-tab="${k}" class="${state.tab === k || (k === 'agents' && state.tab === 'director') ? 'active' : ''}">${l}${navBadge(k)}</button>`).join('')}
      <button id="bmenu" class="${state.menu || ['studio', 'club', 'ops', ...MORE_KEYS].includes(state.tab) ? 'active' : ''}">More</button>
    </nav>
    ${state.menu ? `<div class="sheet-bg" data-close-menu></div><div class="sheet"><div class="sheet-grid">${[['studio', 'Studio'], ['club', 'Club'], ['ops', 'Operations']].map(([k, l]) => `<button data-tab="${k}" class="${state.tab === k ? 'active' : ''}">${l}</button>`).join('')}</div>${MORE.map(([g, items]) => `<h6>${g}</h6><div class="sheet-grid">${items.map(([k, l]) => `<button data-tab="${k}" class="${state.tab === k ? 'active' : ''}">${l}${navBadge(k)}</button>`).join('')}</div>`).join('')}</div>` : ''}
    ${state.drawer ? renderDrawer(state.drawer) : ''}
    ${state.modal && typeof state.modal === 'object' ? (state.modal.kind === 'desk' ? deskModal(state.modal) : state.modal.kind === 'weekly' ? weeklyModal() : renderAnyModal(state.modal)) : ''}`;
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
    case 'REPLY': return `Reply to ${who}${a.person && a.company ? ` (${a.company})` : ''}`;
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
  if (!ov) return state.errors.ov ? unavailable('ov') : '<p class="muted">Loading…</p>';
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
function warmOpportunities(limit = 6) {
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
  return out.sort((a, b) => b.score - a.score).slice(0, limit);
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
  const er = state.er || {};
  const tabs = {
    'EMAIL REVIEW': er.needs_review || [],
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
    'EMAIL REVIEW': 'Emails to SMTP-verified addresses only, drafted and checked. Approve creates an unsent draft in noya@noyaconcierge.com — open it in Gmail and send it yourself. Approving never sends.',
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
  if (t === 'EMAIL REVIEW') body = emailReview(er);
  else if (t === 'READY') body = oneNav + (list.map(approvalCard).join('') || empty('No email outreach waiting for approval.'));
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

// ---------------------------------------------------------------- EMAIL REVIEW (verified email -> Adam approves -> unsent Gmail draft)
// Public email -> SMTP verification (workflow 24) -> email ready -> needs review -> Adam approves -> unsent Gmail draft -> Adam sends.
const ER_STEPS = ['Public email', 'SMTP-verified', 'Draft written', 'Your review', 'Unsent Gmail draft', 'You send'];
function emailCounts(er) {
  const c = er.counts || {}; const v = er.verification || {}; const acc = v.account || {}; const cfg = v.config || {};
  const tgt = Array.isArray(c.email_target) ? c.email_target.join('–') : '40–50';
  const stat = (n, label, sub = '') => `<div class="er-stat"><div class="n">${esc(n ?? 0)}</div><div class="l">${esc(label)}</div>${sub ? `<div class="s">${sub}</div>` : ''}</div>`;
  const left = acc.verifications_left != null ? `${acc.verifications_left} verifications left` : 'account not read yet';
  return `<div class="er-stats">
      ${stat(c.verified_email_ready, 'Verified emails ready today', `target ${esc(tgt)} a day`)}
      ${stat(c.linkedin_ready, 'LinkedIn ready today', 'separate — not counted as email')}
      ${stat(c.instagram_ready, 'Instagram ready today', 'separate — not counted as email')}
      ${stat(c.emails_verified, 'Addresses verified today', `${esc(v.waiting ?? 0)} public addresses waiting`)}
    </div>
    <p class="src">Verification: ${esc(cfg.provider || 'HUNTER')} ${esc(acc.plan || '')} · ${esc(left)}${acc.reset_date ? ` · resets ${esc(fmtDay(acc.reset_date))}` : ''} · daily cap ${esc(cfg.daily_cap ?? '—')} · scope ${esc(String(cfg.scope || '').toLowerCase().replace(/_/g, ' '))}${v.last_run ? ` · last run ${esc(fmtDate(v.last_run))}` : ''}</p>
    <div class="loop">${ER_STEPS.map((l) => `<span>${esc(l)}</span>`).join('')}</div>`;
}
function emailReviewCard(x) {
  const id = esc(x.candidate_id);
  const to = x.via_inbox ? `${esc(x.to_email)} <span class="muted small">(${esc(x.to_label || 'company inbox')}, for the attention of ${esc(x.person || 'the named person')})</span>` : esc(x.to_email || '—');
  const verified = x.email_state === 'VERIFIED'
    ? pill(`SMTP-verified${x.verified_at ? ` ${shortDay(x.verified_at)}` : ''}${x.verified_score != null ? ` · ${x.verified_score}` : ''}`, 'ok')
    : pill(`Not verified (${String(x.email_state || 'unknown').toLowerCase().replace('_', ' ')})`, 'bad');
  return `<article class="card er-card" id="er-${id}">
    <div class="card-head"><div><div class="co">${esc(x.company)}</div><div class="muted small">${esc(x.person || '—')}${x.position ? ` · ${esc(x.position)}` : ''}</div></div>
      <div class="pills">${verified}${x.qa_status && x.qa_status !== 'PASS' ? pill('Check the draft: quality gate flagged it', 'warn') : ''}</div></div>
    <div class="kv"><div class="k">To</div><div class="v">${to}</div></div>
    ${x.why_now ? `<div class="kv mt8"><div class="k">Why now</div><div class="v small">${esc(x.why_now)}</div></div>` : ''}
    <label class="field mt8"><span>Subject</span><input id="er-s-${id}" maxlength="200" value="${esc(x.subject || '')}"></label>
    <label class="field"><span>Email</span><textarea id="er-b-${id}" maxlength="8000">${esc(x.draft || '')}</textarea></label>
    <div class="btn-row">
      <button class="btn primary" data-er-approve="${id}" ${x.email_state === 'VERIFIED' ? '' : 'disabled'}>Approve → create Gmail draft</button>
      ${x.task_id ? `<button class="btn ghost" data-modal="task-dismiss" data-id="${esc(x.task_id)}">Reject</button>` : ''}
    </div>
    <p class="src">Approve creates one unsent draft in noya@noyaconcierge.com. Nothing is sent until you press Send in Gmail.</p>
  </article>`;
}
function emailReview(er) {
  if (state.errors?.er) return unavailable('er');
  if (!state.er) ensure('er');
  const row = (x, right) => `<div class="row"><div class="t">${esc(x.company)} · ${esc(x.person || x.to_email || '')}</div>
      <div class="meta">${esc(x.to_email || '')} · ${esc(x.subject || '')}</div><div class="btn-row mt6">${right}</div></div>`;
  const drafting = (er.drafting || []).map((x) => row(x, `${pill('Creating the Gmail draft…', 'info')}${x.outbound_id ? `<button class="btn small" data-act="redispatch" data-id="${esc(x.outbound_id)}">Retry draft creation</button>` : ''}`)).join('');
  const inGmail = (er.in_gmail || []).map((x) => row(x, `${pill('Unsent draft in Gmail', 'ok')}<a class="btn small primary" href="${esc(x.gmail_url || GMAIL_DRAFTS_URL)}" target="_blank" rel="noopener noreferrer">Open in Gmail</a>`)).join('');
  const failed = (er.failed || []).map((x) => row(x, `${pill(x.outbound_status === 'DISCARDED' ? 'Draft deleted in Gmail, not sent' : `Draft failed: ${x.error || 'unknown'}`, 'bad')}<button class="btn small" data-er-approve="${esc(x.candidate_id)}">Approve again</button>`)).join('');
  const sent = (er.sent || []).slice(0, 10).map((x) => row(x, `${pill(`Sent by you ${fmtDay(x.sent_at)}`, 'ok')}${x.thread_id ? gmailLink(x.thread_id, 'Open thread') : ''}`)).join('');
  const sec = (title, html, none) => `<section class="panel"><header><h3>${esc(title)}</h3></header><div class="body">${html ? `<div class="list">${html}</div>` : `<div class="empty">${esc(none)}</div>`}</div></section>`;
  return `${emailCounts(er)}
    ${(er.needs_review || []).map(emailReviewCard).join('') || empty('No verified email waiting for your review. Unverified addresses wait for workflow 24 and never appear here.')}
    ${drafting ? sec('Creating Gmail drafts', drafting, '') : ''}
    ${sec('In Gmail — waiting for you to send', inGmail, 'No unsent approved drafts in Gmail.')}
    ${failed ? sec('Needs attention', failed, '') : ''}
    ${sec('Sent by you (last 21 days)', sent, 'Nothing sent from approved drafts yet.')}`;
}

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

// Admin diagnostics: snapshot ages, build times, background jobs and the raw errors of this session. Admin only; never on CEO screens.
async function loadDiag() {
  if (state.busy.diag) return;
  state.busy.diag = true;
  const { data, error } = await sb.rpc('hq_cache_status');
  state.busy.diag = false; state.diag = error ? { error: error.message } : data; render();
}
function diagPanel() {
  const D = state.diag; if (!D) loadDiag();
  const raw = Object.entries(state.errors);
  const age = (sec) => (sec == null ? '—' : sec < 90 ? `${sec} s` : sec < 5400 ? `${Math.round(sec / 60)} min` : `${Math.round(sec / 3600)} h`);
  return `<h3>HQ data health · diagnostics</h3>
    <p class="small muted">Heavy CEO reads are served from background snapshots refreshed by the database every 5 minutes (Director pages: the three oldest each run). The Outreach desk is always live.</p>
    ${!D ? '<p class="muted small">Loading…</p>' : D.error ? `<p class="small bad-text">${esc(D.error)}</p>` : `<div class="tbl-wrap"><table class="stack"><thead><tr><th>Snapshot</th><th>Age</th><th class="num">Build</th><th>Last error</th></tr></thead><tbody>
      ${(D.items || []).map((x) => `<tr><td>${esc(x.key)}</td><td data-l="Age">${esc(age(x.age_s))}</td><td class="num" data-l="Build">${x.build_ms != null ? `${(x.build_ms / 1000).toFixed(1)} s` : '—'}</td><td data-l="Error" class="small">${x.last_error ? `${esc(x.last_error)} <span class="faint">(${esc(fmtDate(x.last_error_at))})</span>` : '<span class="faint">—</span>'}</td></tr>`).join('')}</tbody></table></div>
      <p class="small">${(D.jobs || []).map((j) => `${esc(j.job)} · ${esc(j.schedule)} · ${j.active ? 'active' : 'paused'} · last ${esc(j.last_status || '—')} ${j.last_run ? esc(fmtDate(j.last_run)) : ''}`).join('<br>')}</p>`}
    <p class="small"><b>This session:</b> ${raw.length ? raw.map(([k, v]) => `${esc(k)}: ${esc(v)}`).join('<br>') : 'no errors.'} <button class="linkish" data-diag-refresh>Refresh diagnostics</button></p>`;
}
function viewSystem(d) {
  const ov = state.ov; const h = d.health; const alerts = healthAlerts(d);
  return `
    <h2>Snapshots and signals</h2>
    ${diagPanel()}
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
    <p class="muted small"${tip('verified')}>${dir.contacts.length} people. Only a verified email can become an email draft, and nothing is ever sent automatically. Hover an email for its evidence.</p>
    <div class="filters"><input data-cf="q" placeholder="Name, email, company…" value="${esc(f.q)}">
      <select data-cf="email">${opt('', f.email, 'Any email status')}${Object.keys(counts).sort().map((s) => opt(s, f.email, `${s.toLowerCase()} · ${counts[s]}`)).join('')}</select></div>
    <div class="tbl-wrap"><table class="stack"><thead><tr><th>Person</th><th>Company</th><th>Email</th><th>Last interaction</th><th class="num">Active opps</th></tr></thead>
    <tbody>${rows.map((k) => `<tr class="clickable" data-open="contact" data-id="${k.id}"><td>${esc(k.name || '—')}<div class="muted small">${esc(k.position || '')}</div></td>
      <td>${esc(k.company || '—')}</td><td title="${esc(provenanceTitle(k))}"><span class="small">${esc(k.email || '—')}</span> ${emailPill(k.email_status, k.email_kind)}${k.do_not_contact ? ` ${pill('do not contact', 'bad')}` : ''}</td>
      <td class="small" data-l="Last interaction">${esc(k.last_interaction ? fmtDay(k.last_interaction) : '—')}</td><td class="num" data-l="Active opportunities">${esc(k.active_opps)}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">No contacts match.</td></tr>'}</tbody></table></div>`;
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
  ['1. Your LinkedIn data download + draft here + you send (recommended)', 'Your connections (name, company, position, profile link, connected date; email only if the contact allowed it) and your message history, as read-only context', 'Nothing. HQ drafts; you open the profile and send yourself', 'No password, cookie or token is stored. You upload the file; only the needed columns are kept', 'Fully compliant — it is your own data export', '£0', '£0'],
  ['2. Official "Sign in with LinkedIn" API', 'Your own name, photo and email only', 'Posts to your own feed only', 'OAuth token kept server-side', 'Compliant, but cannot read connections or send messages (those APIs are partner-only)', '£0', '£0'],
  ['3. Sales Navigator (manual use)', 'Better search, lead lists, InMail credits inside LinkedIn', 'InMail by you, inside LinkedIn', 'None in HQ', 'Compliant; no API access for NOYA (SNAP partner programme is closed)', 'Paid — verify current price before any decision', 'None'],
  ['4. Browser-cookie automation tools (Phantombuster, Expandi, Dripify…)', 'Everything your account can see', 'Automated invites and messages', 'Requires your session cookie — account-takeover risk', 'Breaks LinkedIn User Agreement; account restriction risk. Not recommended', 'Paid — verify', 'Paid tiers'],
];
// The LinkedIn relationship state from Adam's own LinkedIn download (read-only history; every state carries its date).
const LI_REL = { ACTIVE: ['Active', 'ok'], WARM: ['Warm', 'ok'], DORMANT: ['Dormant', 'warn'], REPLIED_BEFORE: ['Replied before', ''], MESSAGED_BEFORE: ['Messaged before', ''],
  CONNECTED: ['Connected', ''], DO_NOT_CONTACT: ['Do not contact', 'bad'] };
const liRel = (s) => (s ? pill(...(LI_REL[s] || [sentence(String(s).replace(/_/g, ' ')), ''])) : '');
const liRank = (s) => ['ACTIVE', 'WARM', 'DORMANT', 'REPLIED_BEFORE', 'MESSAGED_BEFORE', 'CONNECTED'].indexOf(s) + 1 || 9;
function liArchivePanel() {
  const A = state.liArch;
  if (!A) { loadV3('liArch', 'hq_linkedin_archive', {}); return state.errors.liArch ? `<section class="panel mt8"><header><h3>Your LinkedIn history</h3></header><div class="body">${unavailable('liArch')}</div></section>` : ''; }
  if (!A.connections && !A.messages) return '';
  const D = A.duplicates_prevented || {}; const R = A.review || {}; const S = A.states || {};
  const dups = (D.in_files || 0) + (D.connections_already_known || 0) + (D.messages_already_imported || 0);
  const cell = (n, l) => `<div class="dc-c"><b>${n0(n)}</b><span>${l}</span></div>`;
  const known = new Set((state.dir?.connections || []).map((c) => c.id));
  const person = (p, extra = '') => `<div class="t-row li-p"><div><div class="t-main">${esc(p.person || '—')}${p.role || p.company ? ` · <span class="faint">${esc([p.role, p.company].filter(Boolean).join(', '))}</span>` : ''} ${liRel(p.state)}${p.in_crm ? ` ${pill('in CRM')}` : ''}</div>
      <div class="t-sub">${esc([p.recency, extra].filter(Boolean).join(' · '))}</div>${p.reason ? `<div class="t-sub faint">${esc(p.reason)}</div>` : ''}</div>
      <div class="t-btns">${p.profile_url ? `<a class="btn small" href="${esc(p.profile_url)}" target="_blank" rel="noopener noreferrer">LinkedIn</a>` : ''}${known.has(p.connection_id) ? `<button class="btn small" data-open="connection" data-id="${esc(p.connection_id)}">Open</button>` : ''}</div></div>`;
  const list = (title, items, hint, render = (p) => person(p), open = false) => `<details class="li-list"${open ? ' open' : ''}><summary><b>${esc(title)}</b> <span class="n">${(items || []).length}</span>${hint ? ` <span class="small faint">${esc(hint)}</span>` : ''}</summary>
      ${(items || []).map(render).join('') || '<p class="small muted">None.</p>'}</details>`;
  const intro = (p) => person(p, p.intro ? `introduced${p.intro.by ? ` by ${p.intro.by}` : ''} ${shortDay(p.intro.at)}${p.intro.title ? ` (“${p.intro.title}”)` : ''}` : '');
  return `<section class="panel mt8" id="li-archive"><header><h3>Your LinkedIn history</h3><span class="small faint">${A.imported_at ? `imported ${esc(fmtDate(A.imported_at))} · ` : ''}read-only</span></header><div class="body">
    ${A.self_known === false ? '<div class="unavail"><span>HQ could not tell which profile is yours in messages.csv, so the conversations are stored but not yet linked to people. Upload the messages file from your own LinkedIn download.</span></div>' : ''}
    <div class="dc-cells">${cell(A.connections, 'connections imported')}${cell(`${A.conversations_matched ?? 0} of ${A.conversations ?? 0}`, 'conversations matched to the CRM')}
      ${cell(A.companies_new?.count, 'companies not in the CRM')}${cell((A.warm_destination_egypt || []).length, 'warm Destination Egypt routes')}
      ${cell(S.DORMANT || 0, 'dormant relationships')}${cell((R.count || 0) + (R.warm_not_in_crm || 0), 'to review')}${cell(dups, 'duplicates prevented')}</div>
    <div class="pills mt6">${Object.keys(LI_REL).filter((k) => S[k]).map((k) => `${liRel(k)} <span class="small">${n0(S[k])}</span>`).join(' ')}</div>
    <p class="src">${esc(A.note || '')}</p>
    ${list('Warm Destination Egypt routes', A.warm_destination_egypt, 'a real conversation at a Destination Egypt target', (p) => person(p, p.project ? `Project: ${plainText(p.project)}` : ''), true)}
    ${(A.connected_destination_egypt || []).length ? list('Connected at Destination Egypt targets, never spoke', A.connected_destination_egypt, 'a route for a first message, not a warm relationship', (p) => person(p, p.project ? `Project: ${plainText(p.project)}` : '')) : ''}
    ${list('Dormant relationships worth reopening', A.dormant, 'reopen personally, never with a cold introduction')}
    ${list('Warm now', A.warm, 'two-way in the last 12 months')}
    ${list('Introductions and referrals', A.introductions, 'who introduced you, and when', intro)}
    ${list('Needs your review', [...(R.top || []), ...(R.warm_not_in_crm_top || [])], 'name-only matches are never linked automatically; warm people not in the CRM yet', (p) => person(p, p.review || 'warm, not in the CRM'))}
    ${list('Companies not in the CRM', A.companies_new?.top, `${n0(A.companies_new?.count)} in total; nothing is created automatically`, (c) => `<div class="t-row"><div><div class="t-main">${esc(c.company)} ${liRel(c.best_state)}</div><div class="t-sub">${n0(c.people)} ${c.people === 1 ? 'person' : 'people'}${c.two_way ? ` · ${n0(c.two_way)} two-way` : ''}${c.person ? ` · best: ${esc(c.person)}` : ''}</div></div></div>`)}
    ${(R.do_not_contact || []).length ? list('Asked not to be contacted', R.do_not_contact, 'held: check before any message') : ''}
    <p class="small faint">Duplicates prevented: ${n0(D.in_files || 0)} repeated lines in the files, ${n0(D.connections_already_known || 0)} ${D.connections_already_known === 1 ? 'person' : 'people'} already known, ${n0(D.messages_already_imported || 0)} messages already imported, ${n0(D.linked_to_existing_crm_contacts || 0)} linked to existing CRM contacts instead of new ones.</p>
  </div></section>`;
}
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
    history: conns.filter((c) => c.li_messages > 0).sort((a, b) => liRank(a.li_state) - liRank(b.li_state) || String(b.li_last_at).localeCompare(String(a.li_last_at))),
    emailed: conns.filter((c) => c.email_history > 0),
    followup: due,
    matched: conns.filter((c) => c.matched_company_id),
    review: conns.filter((c) => c.review_reason),
    all: conns,
  };
  const total = dir.connections_total ?? conns.filter((c) => c.connected !== false).length;
  const rows = (lists[f.only] || conns).filter((c) => (!f.vertical || c.vertical === f.vertical) && (!q || [c.name, c.company, c.position].some((v) => String(v ?? '').toLowerCase().includes(q))));
  const drafts = (dir.drafts || []).filter((x) => x.channel === 'LINKEDIN' || x.channel === 'INSTAGRAM' || x.channel === 'WHATSAPP' || x.channel === 'EMAIL');
  return `<h2>LinkedIn</h2>
    <p class="muted small">Messages here are sent by you, personally, from LinkedIn. HQ prepares the words, opens the profile and books the follow-up. Nothing is ever sent automatically, and your LinkedIn password is never asked for or stored.</p>
    <section class="panel"><header><h3>Messages ready to send (${acts.length})</h3><button class="btn small ghost" data-go="outreach" data-otab="LINKEDIN">All in Outreach</button></header>
      <div class="body">${acts.slice(0, 3).map(manualChannelCard).join('') || '<div class="empty">No LinkedIn messages waiting.</div>'}${acts.length > 3 ? `<button class="linkish" data-go="outreach" data-otab="LINKEDIN">Show all ${acts.length}</button>` : ''}</div></section>
    <section class="panel mt8"><header><h3>Drafts (${drafts.length})</h3><span class="small faint">requested from HQ · written by the drafting workflow</span></header>
      <div class="body">${drafts.map(draftRow).join('') || '<div class="empty">No drafts. Use "Draft message" on any person, company or connection.</div>'}</div></section>
    ${liArchivePanel()}
    <section class="panel mt8"><header><h3>People you already know</h3><span class="small faint">${n0(total)} connections imported${conns.length < total ? ` · ${conns.length} linked to NOYA or with history shown` : ''}</span></header>
      <div class="body">${conns.length ? `
        <div class="tabs">${[['known', 'Linked to NOYA'], ['warm', 'At active prospects'], ['history', 'Messaged on LinkedIn'], ['emailed', 'Also emailed NOYA'], ['followup', 'Follow-up due'], ['matched', 'At known companies'], ['review', 'To review'], ['all', 'All shown']].map(([k, l]) => `<button data-nf="only" data-v="${k}" class="${f.only === k ? 'on' : ''}">${l} <span class="n">${lists[k].length}</span></button>`).join('')}</div>
        <div class="filters"><input data-nf="q" placeholder="Name, company, role…" value="${esc(f.q)}"><select data-nf="vertical">${opt('', f.vertical || '', 'All verticals')}${Object.entries(VERTICAL_LABEL).map(([k, l]) => opt(k, f.vertical || '', l)).join('')}</select></div>
        <div class="tbl-wrap"><table><thead><tr><th>Person</th><th>Company</th><th>LinkedIn history</th><th>Status</th><th>Next follow-up</th></tr></thead><tbody>
        ${rows.slice(0, 200).map((c) => `<tr class="clickable" data-open="connection" data-id="${c.id}"><td>${esc(c.name || '—')}<div class="muted small">${esc(c.position || '')}</div>${(c.evidence || []).length ? `<div class="small evidence">${(c.evidence || []).map((e) => `<div>✓ ${esc(e)}</div>`).join('')}</div>` : ''}${c.review_reason ? `<div class="small warn-text">${esc(c.review_reason)}</div>` : ''}</td>
          <td>${esc(c.company || '—')}${c.active_opps ? ` ${pill(`${c.active_opps} active opp${c.active_opps > 1 ? 's' : ''}`, 'info')}` : ''}${c.email_history ? ` ${pill('emailed before', 'ok')}` : ''}${c.matched_contact_id ? ` ${pill('in CRM')}` : ''}</td>
          <td class="small">${c.li_state ? `${liRel(c.li_state)}${c.li_last_at ? `<div class="faint">last ${esc(fmtDay(c.li_last_at))}</div>` : ''}` : '<span class="faint">—</span>'}</td>
          <td>${pill(sentence(c.status.replace(/_/g, ' ')))}${c.how_we_know ? `<div class="small faint">${esc(c.how_we_know)}</div>` : ''}</td>
          <td class="small">${esc(c.next_follow_up_at ? fmtDay(c.next_follow_up_at) : '—')}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">No connections match.</td></tr>'}</tbody></table></div>
        ${rows.length > 200 ? `<p class="small faint">Showing 200 of ${rows.length}. Narrow with the filter.</p>` : ''}`
        : `<div class="empty">${total ? `${n0(total)} connections imported; none is linked to NOYA or has a message history yet.` : 'Nothing imported yet. Upload your LinkedIn download below to see who you already know and who you have spoken to.'}</div>`}</div></section>
    <section class="panel mt8"><header><h3>Import your LinkedIn history</h3></header><div class="body">
      <ol class="small steps"><li>On LinkedIn: <b>Me → Settings &amp; Privacy → Data privacy → Get a copy of your data</b>.</li>
        <li>Tick <b>Connections</b> and <b>Messages</b> (or ask for the full archive) and request it. LinkedIn emails a download link, usually within a day.</li>
        <li>Choose the downloaded <b>.zip</b> below, as it is. Or unzip it and choose <b>Connections.csv</b> and <b>messages.csv</b> together.</li></ol>
      <p class="small muted">Read in your browser. Only people (name, company, position, profile link, connected date) and messages (date, who wrote to whom, the text) are saved, to NOYA's private database, as read-only history. Nothing is sent, no CRM person or company is created, and HQ never logs in to LinkedIn. Uploading again adds only what is new.</p>
      <label class="btn">Choose the LinkedIn download<input type="file" id="li-file" accept=".zip,.csv,application/zip,text/csv" multiple hidden></label>
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
  if (t.error) return '<p class="muted small">History is temporarily unavailable.</p>';
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
    const H = state.liHist[c.id];
    if (c.li_messages > 0 && !H) loadLinkedInHistory(c.id);
    const hist = !(c.li_messages > 0) ? '' : `<h3>LinkedIn messages</h3><p class="small muted">From your LinkedIn download, read-only, newest first. Check the date before writing: an old conversation is not a live lead.</p>
      ${!H ? '<p class="muted small">Loading…</p>' : H.error ? `<p class="small warn-text">${esc(friendly(H.error))}</p>` : H.map((x) => `<div class="li-msg ${x.out ? 'out' : ''}"><div class="small faint">${esc(fmtDate(x.at))} · ${x.out ? 'You' : esc(x.who || 'They')}${x.group ? ' · group conversation' : ''}${x.title ? ` · ${esc(x.title)}` : ''}</div><div>${esc(x.text || '')}</div></div>`).join('')}`;
    return drawerShell(`<h2>${esc(c.name || 'Connection')}</h2><div class="pills">${pill(sentence(c.status.replace(/_/g, ' ')))}${c.vertical ? pill(V(c.vertical)) : ''}${liRel(c.li_state)}${c.connected === false ? pill('not a connection') : ''}</div>`, `
      <div class="btn-row"><a class="btn small" href="${esc(c.profile_url)}" target="_blank" rel="noopener noreferrer">Open in LinkedIn</a>
        <button class="btn small primary" data-modal="draft-request" data-channel="LINKEDIN" data-conn="${c.id}">Draft message</button>
        <button class="btn small" data-modal="touch" data-channel="LINKEDIN" data-conn="${c.id}">Mark sent</button>
        <button class="btn small" data-modal="conn-status" data-conn="${c.id}">Update status</button><button class="btn small" data-modal="note" data-conn="${c.id}">Add note</button></div>
      <div class="grid2">${kv('Role', esc(c.position || '—'))}${kv('Company', c.matched_company_id ? `<button class="linkish" data-open="company" data-id="${c.matched_company_id}">${esc(c.company)}</button>` : esc(c.company || '—'))}
        ${kv('Connected', esc(c.connected_on ? fmtDay(c.connected_on) : c.connected === false ? 'not a 1st-degree connection' : '—'))}${kv('LinkedIn relationship', c.li_state ? `${liRel(c.li_state)} <span class="faint small">${esc(c.li_reason || '')}</span>` : 'Unknown <span class="faint small">(no LinkedIn history imported)</span>')}
        ${kv('How you know them', esc(c.how_we_know || '—'))}${kv('Last contacted', esc(c.last_contacted_at ? fmtDate(c.last_contacted_at) : 'never (in HQ)'))}
        ${kv('Next follow-up', esc(c.next_follow_up_at ? fmtDay(c.next_follow_up_at) : '—'))}${kv('Active opportunities at company', esc(c.active_opps))}</div>
      ${c.review_reason ? `<p class="small warn-text">${esc(c.review_reason)}</p>` : ''}
      ${hist}
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
  return `<h2>Signal radar</h2>
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
  if (a.error) return '<p class="muted small">Account intelligence is temporarily unavailable.</p>';
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
// Today's 15–20 commercial actions (Adam, 7 Oct): replies, warm, follow-ups, partnerships, then the best new prospects.
// Drafts older than 14 days wait for revalidation (workflow 20); drafts with no named person wait for workflow 19.
const ACTION_GO = { Reply: 'inbox', 'Warm opportunity': 'relationships', 'Follow up': 'tasks' };
function actionsPanel() {
  const a = state.exec?.actions; if (!a) return '';
  const go = (it) => ACTION_GO[it.action] || (it.channel === 'LINKEDIN' ? 'linkedin' : 'outreach');
  const waits = [a.waiting_revalidation ? `${esc(a.waiting_revalidation)} older drafts waiting for revalidation` : '', a.waiting_for_person ? `${esc(a.waiting_for_person)} drafts waiting for a named person` : ''].filter(Boolean);
  return `<section class="panel mt8 actions-panel"><header><h3>Today's actions</h3><span class="small faint">${esc(a.count)} of ${esc(a.target)} · ${esc(Object.entries(a.by_group || {}).map(([k, n]) => `${k} ${n}`).join(' · '))}</span></header><div class="body">
    ${(a.items || []).map((it) => `<div class="mini clickable" data-go="${go(it)}"><div class="t">${esc(it.rank)}. ${esc(it.action)} · ${esc(it.company || '—')}${it.channel ? ` <span class="faint">${esc(human(it.channel))}</span>` : ''}</div><div class="m">${esc(LANE_LABEL[it.lane] || it.lane || '')}${it.detail ? ` · ${esc(it.detail)}` : ''}</div></div>`).join('') || '<div class="empty">Nothing needs action today.</div>'}
    ${waits.length ? `<div class="small faint mt6">${waits.join(' · ')}</div>` : ''}
    ${scorecardLine()}</div></section>`;
}
function scorecardLine() {
  const s = state.exec?.scorecard; if (!s) return '';
  const src = Object.entries(s.new_companies_by_source || {}).map(([k, n]) => `${k} ${n}`).join(', ');
  const sp = s.serper || {};
  return `<div class="small mt6 scorecard-line"><b>Last 3 days:</b> ${esc(s.new_companies ?? 0)} new companies${src ? ` (${esc(src)})` : ''} · ${esc(s.new_decision_makers ?? 0)} decision makers · ${esc(s.new_public_emails ?? 0)} public emails · ${esc(s.new_linkedin_routes ?? 0)} LinkedIn · ${esc(s.new_instagram_routes ?? 0)} Instagram routes · ${esc(s.outreach_ready ?? 0)} outreach-ready · ${esc(s.hospitality_partnerships ?? 0)} hotel/villa/residence partners · ${esc(s.media_concepts ?? 0)} media concepts · ${esc(s.wedding_prospects ?? 0)} wedding · ${esc(s.brands_production_prospects ?? 0)} brands/production · ${esc(s.sends ?? 0)} sent · ${esc(s.replies ?? 0)} replies · ${esc(s.calls ?? 0)} calls</div>
    ${sp.balance != null ? `<div class="small faint mt6 serper-line">Search: ${esc(sp.per_cycle ?? '—')} searches per 3-day cycle ≈ $${esc(sp.cycle_usd ?? '—')} · balance ${esc(sp.balance)} credits (~${esc(sp.runway_days ?? '—')} days) · ${esc(String(sp.per_day_basis || '').toLowerCase())}</div>` : ''}`;
}
// Daily operating target (Adam, 3 Oct): 15 quality actions/day, 3 days (45) ready. Shortfalls are shown, never padded.
function execPanel() {
  const q = state.exec?.queue; if (!q) return state.errors.exec ? unavailable('exec') : '';
  const go = { email: 'outreach', linkedin: 'linkedin', follow_up: 'tasks', warm: 'relationships' };
  const acq = q.acquisition || {};
  return `<section class="panel mt8 queue-health"><header><h3>Email ready · queue health</h3><span class="small faint">${esc(q.ready)} verified email${q.ready === 1 ? '' : 's'} to approve or send (cap ${esc(q.target)}) · ${esc(acq.email_ready ?? '—')} email-ready prospects in reserve</span></header><div class="body">
    <div class="qh-grid">${q.lines.map((l) => `<div class="qh clickable ${l.shortfall ? 'short' : 'ok'}" data-go="${go[l.key]}"><div class="k">${esc(l.label)}</div>
      <div class="v">${esc(l.ready)}<span class="faint"> / ${esc(l.target)}</span></div><div class="m">${l.fallback ? 'fallback only · not in the headline' : l.shortfall ? `<span class="bad-text">short by ${esc(l.shortfall)}</span>` : `${esc(l.per_day)} a day · covered`}</div></div>`).join('')}</div>
    <div class="small faint mt6">${esc(q.rule)}${q.verify_first ? ` ${esc(q.verify_first)} people need verifying before they count (VERIFY FIRST tasks).` : ''}</div>
    <div class="small mt6">Working universe: ${Object.entries(q.universe_by_status || { QUALIFIED: q.universe }).map(([k, v]) => `${esc(human(k))} ${esc(v)}`).join(' · ')} <span class="faint">(target ${esc(q.universe_target)})</span></div>
    ${hunterLine()}</div></section>`;
}
const LANE_LABEL = { PARTNERSHIPS: 'Hospitality & partnerships', BRANDS: 'Brands / PR / production', TRAVEL_PRIVATE: 'Travel / concierge / private', WEDDINGS: 'Weddings & events', CORPORATE: 'Corporate', SPORTS_PRIVATE: 'Sports / talent', EGYPT_EVENTS: 'Egypt event signals' };
function todayPanel() {
  const t = state.exec?.today; if (!t) return '';
  const tot = t.totals || {}; const p = t.planned_today || {};
  const cols = [['discovered', 'New prospects'], ['send_ready', 'Send-ready'], ['awaiting_approval', 'Awaiting you'], ['linkedin', 'LinkedIn'], ['instagram', 'Instagram'], ['emails', 'Emails'],
    ['follow_ups_due', 'Follow-ups due'], ['sent_today', 'Sent today'], ['replies_today', 'Replies'], ['meetings_today', 'Meetings']];
  return `<section class="panel mt8 today-panel"><header><h3>Today · commercial engine</h3><span class="small faint">Target ${esc(t.target?.target ?? 20)} qualified touches a day (floor ${esc(t.target?.floor ?? 15)}) · from system records only</span></header><div class="body">
    <div class="qh-grid">${cols.slice(0, 5).map(([k, l]) => `<div class="qh"><div class="k">${l}</div><div class="v">${esc(tot[k] ?? 0)}</div></div>`).join('')}</div>
    <div class="small mt6">Commercial Director today: ${esc(p.planned ?? 0)} planned · ${esc(p.ready ?? 0)} passed QA · ${esc(p.review_required ?? 0)} need review${p.dry_run ? ' <span class="faint">(dry run — nothing queued)</span>' : ''}</div>
    <div class="tbl-wrap mt6"><table><thead><tr><th>Lane</th>${cols.map(([, l]) => `<th>${l}</th>`).join('')}</tr></thead><tbody>
      ${(t.lanes || []).map((r) => `<tr><td>${esc(LANE_LABEL[r.lane] || r.lane)}</td>${cols.map(([k]) => `<td>${esc(r[k] ?? 0)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>
    ${(t.conversations || []).length ? `<div class="small mt6">In conversation (cold outreach paused): ${t.conversations.map((c) => `${esc(c.company)} <span class="faint">${esc(human(c.state))}</span>`).join(' · ')}</div>` : ''}
    ${cycleBlock()}
    ${engineLine()}
  </div></section>`;
}
// Rolling 3-day cycle: only READY tasks (company, person, role, evidence, channel, finished message) count as outreach-ready.
function cycleBlock() {
  const c = state.exec?.cycle; if (!c) return '';
  const t = c.totals || {}; const tg = c.target || {};
  const rows = (c.agents || []).filter((a) => a.discovered || a.outreach_ready || a.named_people);
  return `<div class="small mt6 cycle-line"><b>3-day cycle:</b> ${esc(t.outreach_ready ?? 0)} outreach-ready of ${esc(tg.cycle_floor ?? 60)}–${esc(tg.cycle_target ?? 75)} target · ${esc(t.discovered ?? 0)} discovered · ${esc(t.qualified ?? 0)} qualified · ${esc(t.confirmed_people ?? 0)} confirmed people (${esc(t.email_ready ?? 0)} email, ${esc(t.linkedin_ready ?? 0)} LinkedIn) · ${esc(t.research_required ?? 0)} still need research</div>
    ${rows.length ? `<div class="tbl-wrap mt6"><table><thead><tr><th>Agent</th><th>Discovered</th><th>Qualified</th><th>People</th><th>Ready</th></tr></thead><tbody>
      ${rows.map((a) => `<tr><td>${esc(LANE_LABEL[a.lane] || a.lane)}</td><td>${esc(a.discovered)}</td><td>${esc(a.qualified)}</td><td>${esc(a.confirmed_people)}</td><td>${esc(a.outreach_ready)}</td></tr>`).join('')}</tbody></table></div>` : ''}`;
}
// Two separate measures on purpose: what workflow 18 produced on its own vs what was ready only after a human rewrite.
function engineLine() {
  const e = state.exec?.engine; const b = state.exec?.ai_budget; if (!e && !b) return '';
  const usd = (n) => `$${Number(n || 0).toFixed(2)}`;
  const flag = b && b.status !== 'OK' ? ` <span class="pill warn">${esc(human(b.status))}</span>` : '';
  return `<div class="small mt6 engine-line">${e && e.drafted ? `Drafting quality (30 days): system ready on its own ${esc(e.system_ready)}/${esc(e.drafted)} (${esc(e.system_ready_pct ?? 0)}%) · ready after human review ${esc(e.final_ready_after_human_review)} · ${esc(e.avg_calls ?? 0)} model calls per account · ${usd(e.avg_cost_usd)} per account` : 'Drafting quality: no workflow 18 drafts recorded yet'}</div>
    ${b ? `<div class="small mt6 ai-budget">AI drafting cost this month: ${usd(b.mtd_usd)} of ${usd(b.target_usd)} target · ${usd(b.ceiling_usd)} ceiling needs your approval to raise${flag}</div>` : ''}`;
}
function hunterLine() {
  const h = state.exec?.hunter; if (!h) return '';
  return `<div class="small mt6 hunter-roi">Hunter ROI: ${esc(h.credits)} credits → ${esc(h.usable_emails)} usable emails (${esc(h.usable_rate ?? 0)}%, ${esc(h.credits_per_usable ?? '—')} credits each) → ${esc(h.sent)} sent → ${esc(h.replies)} replies → ${esc(h.meetings)} meetings <span class="faint">· ${esc(h.gate)}</span></div>`;
}
const SEG_LABEL = { PRIVATE_OFFICE: 'Private office / EA / FO', TRAVEL_PARTNER: 'Travel advisors & DMCs', BRAND_PR_PRODUCTION: 'Brands / PR / production', WEDDING_EVENTS: 'Weddings & events',
  HOTELS_HOSPITALITY: 'Hotels & hospitality', LIVE_SIGNAL: 'Live signals', MEMBER_COMMUNITIES: 'Member communities', CORPORATE_EVENTS: 'Corporate & events', TALENT: 'Talent', OTHER: 'Other' };
function weeklyPanel() {
  const w = state.exec?.weekly; if (!w) return '';
  const cols = [['qualified', 'New accounts'], ['contacts', 'Usable contacts'], ['verified', 'Verified emails'], ['linkedin_ready', 'LinkedIn-ready'], ['sends', 'New outreach'], ['follow_ups', 'Follow-ups'], ['replies', 'Replied'],
    ['positive', 'Positive'], ['meetings', 'Meetings'], ['proposals', 'Proposals'], ['wins', 'Wins']];
  const weeks = [...new Set(w.rows.map((r) => r.week_start))].sort().reverse().slice(0, 2);
  const block = (wk) => { const rows = w.rows.filter((r) => r.week_start === wk);
    return `<h4 class="mt8">Week of ${esc(rows[0]?.week || wk)}</h4><div class="tbl-wrap"><table><thead><tr><th>Segment</th>${cols.map(([, l]) => `<th>${l}</th>`).join('')}<th>Revenue</th></tr></thead><tbody>
      ${rows.map((r) => `<tr><td>${esc(SEG_LABEL[r.segment] || r.segment)}</td>${cols.map(([k]) => `<td>${esc(r[k] || 0)}</td>`).join('')}<td>${r.revenue ? esc(Object.entries(r.revenue).map(([c, a]) => `${c} ${a}`).join(' · ')) : '—'}</td></tr>`).join('')}</tbody></table></div>`; };
  return `<section class="panel mt8"><header><h3>Prospecting by segment · weekly</h3><span class="small faint">Allocation changes are recommendations only — never automatic</span></header><div class="body">
    ${weeks.map(block).join('') || '<div class="empty">No activity recorded yet.</div>'}<div class="small faint mt6">${esc(w.note)}</div></div></section>`;
}
function commandPanels() {
  const c = state.com; if (!c) return actionsPanel() + execPanel() + todayPanel();
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
  return `${actionsPanel()}${execPanel()}${todayPanel()}<div class="ov-grid3 mt8">
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
      const t = findTask(m.id) || { title: m.title };
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
    case 'li-edit': {
      const x = liItem(m.id) || {}; const k = m.type || 'MESSAGE';
      const [title, cur, hint] = { MESSAGE: ['Edit the LinkedIn message', x.message, '40 to 80 words: the specific reason, the Egypt opportunity, what NOYA would run, one simple next step.'],
        NOTE: ['Connection note', x.connection_note, 'Up to 300 characters. Who you are and why them, nothing more: the real message follows once they accept.'],
        FOLLOWUP: ['Follow-up after they accept', x.followup || x.message, '40 to 80 words, sent once they accept the request.'] }[k];
      return form(`${title} — ${esc(x.person || '')}`, `<p class="small muted">${esc(hint)}</p>${area('Text', 'li-text', cur || '', k === 'NOTE' ? 'maxlength="300"' : 'maxlength="1500"')}`, 'Save');
    }
    case 'li-sent': { const x = liItem(m.id) || {};
      return form(`Mark sent — ${esc(x.person || '')}`, `<p class="small muted">Only after you sent it yourself on LinkedIn. HQ records the send (it counts as a real message) and books follow-up 1 four days later, the standard rule. A reply cancels it.</p>`, 'Mark sent'); }
    case 'li-hold': { const x = liItem(m.id) || {};
      return form(`Hold — ${esc(x.person || '')}`, `${fld('Why', 'li-reason', 'text', '', 'maxlength="200" placeholder="e.g. wait for a warm introduction"')}${fld('Review on', 'li-date', 'date', isoPlus(7), `min="${isoPlus(1)}"`)}`, 'Hold'); }
    case 'li-reply': { const x = liItem(m.id) || {};
      return form(`Log their reply — ${esc(x.person || '')}`, `<p class="small muted">Paste what they wrote on LinkedIn. HQ classifies it (you can correct it), logs it as a reply, stops the follow-ups and suggests a response. A meeting request opens Meeting Assist. Nothing is sent.</p>
        ${area('Their reply', 'li-text', '', 'maxlength="3000"')}${sel('Type of reply', 'li-class', [['', 'Detect automatically'], ...LI_CLASSES])}`, 'Log reply'); }
    case 'meet-confirm': {
      const x = (state.desk?.meeting_assist || []).find((a) => a.task_id === m.id) || {};
      const slots = (x.slots || []).map((sl, i) => `<label class="radio"><input type="radio" name="mc-slot" value="${esc(sl.start)}" ${i === 0 ? 'checked' : ''}> ${esc(slotText([sl]))}</label>`).join('');
      return form(`Confirm meeting — ${esc(x.company || '')}`, `<p class="small muted">Only once they have confirmed a time. HQ records the meeting, links it to the person, company, opportunity and Director, and prepares the briefing. The calendar entry goes in your own calendar without inviting anyone; you add the guest yourself.</p>
        ${slots ? `<div class="field"><span>They picked</span>${slots}<label class="radio"><input type="radio" name="mc-slot" value=""> Another time</label></div>` : ''}
        ${fld('Date', 'mc-date', 'date', '', `min="${todayKey()}"`)}${fld('Time (UK)', 'mc-time', 'time', '10:00')}${sel('Length', 'mc-min', [['30', '30 minutes'], ['20', '20 minutes'], ['45', '45 minutes'], ['60', '1 hour']])}
        ${fld('Where (optional)', 'mc-where', 'text', '', 'maxlength="200" placeholder="e.g. Google Meet, their office"')}`, 'Confirm meeting'); }
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
    case 'li-archive': {
      const C = m.conns; const M = m.msgs;
      const left = [C?.skipped && `${C.skipped} without a profile link`, C?.dups && `${C.dups} repeated connections`, M?.drafts && `${M.drafts} unsent drafts`, M?.spam && `${M.spam} spam`,
        M?.bad && `${M.bad} unreadable lines`, M?.dups && `${M.dups} repeated messages`].filter(Boolean);
      return form('Import your LinkedIn history', `<p>${C ? `<b>${n0(C.rows.length)}</b> connections` : 'No Connections.csv'} · ${M ? `<b>${n0(M.rows.length)}</b> messages in <b>${n0(M.conversations)}</b> conversations${M.first ? ` (${esc(fmtDay(M.first))} to ${esc(fmtDay(M.last))})` : ''}` : 'no messages.csv'}</p>
        ${left.length ? `<p class="small">Left out: ${esc(left.join(', '))}.</p>` : ''}
        ${M && M.rows.length && !M.self_hint ? '<p class="small warn-text">HQ could not tell which profile is yours in the messages. They will be stored, and linked to people once your own profile is clear.</p>' : ''}
        <p class="small muted">Read in your browser. Saved to NOYA's private database: for people, name, company, position, profile link and connected date${C?.rows.some((r) => r.email) ? ' (email only where the person shared it with you)' : ''}; for messages, the date, who wrote to whom and the text (up to 4,000 characters each), as read-only history. Nothing is sent, no CRM person or company is created, and LinkedIn is never contacted. Uploading again adds only what is new.</p>`,
        'Import');
    }
    case 'work-order': {
      const D = (state.cmd?.directors || []).map((x) => [x.key, x.name]);
      return form('Issue a work order', `<p class="small muted">The Director owns the result. Research, contact, email and writing specialists put the matching companies first from their next runs. Nothing is sent: emails still come to you for review.</p>
        ${sel('Director', 'wo-dir', D, m.id || 'BRANDS')}${fld('Mission', 'wo-mission', 'text', '', 'maxlength="300" placeholder="e.g. Open conversations with UK jewellery brands for spring shoots"')}
        ${fld('Target (comma-separated)', 'wo-target', 'text', '', 'maxlength="200" placeholder="e.g. jewellery, UK"')}
        <div class="two">${sel('Result wanted', 'wo-metric', WO_METRIC, 'EMAILS_SENT')}${fld('Number', 'wo-goal', 'number', '5', 'min="1" max="500"')}</div>
        <div class="two">${fld('Deadline', 'wo-deadline', 'date', isoPlus(7), `min="${isoPlus(0)}" max="${isoPlus(90)}"`)}${sel('Priority', 'wo-prio', [['P1', 'P1 · first'], ['P2', 'P2 · normal'], ['P3', 'P3 · when possible']], 'P2')}</div>`, 'Issue work order');
    }
    case 'wo-close': {
      const w = (state.cmd?.work_orders || []).find((x) => x.id === m.id) || {};
      return form(m.type === 'CANCEL' ? 'Cancel work order' : 'Close work order', `<p>${esc(w.mission || '')}</p><p class="small muted">Result so far: ${n0(w.result)} of ${n0(w.goal)}. The order and its results are kept.</p>${fld('Note (optional)', 'wo-note', 'text', '', 'maxlength="300"')}`, m.type === 'CANCEL' ? 'Cancel order' : 'Close order', m.type === 'CANCEL');
    }
    case 'opp-plan': {
      const o = (state.cmd?.opportunities || []).find((x) => x.opportunity_id === m.opp) || {};
      return form(`Plan · ${esc(o.company || 'opportunity')}`, `<p class="small muted">Every live opportunity has an owner, a next action, a date, and its blocker if there is one.</p>
        ${fld('Next action', 'op-next', 'text', o.next_action || '', 'maxlength="300"')}<div class="two">${fld('Date', 'op-due', 'date', o.next_action_due || isoPlus(2), `min="${isoPlus(0)}"`)}${fld('Owner', 'op-owner', 'text', o.owner || 'Adam', 'maxlength="80"')}</div>
        ${fld('Blocker (leave empty if none)', 'op-blocker', 'text', o.blocker || '', 'maxlength="200"')}`, 'Save plan');
    }
    case 'rec': {
      const r = (state.cmd?.recommendations || []).find((x) => x.id === m.id) || {};
      const what = r.change?.type === 'ACTION' ? 'Approving applies this now. It can be reversed from HQ.' : r.change?.type === 'CONFIG' ? 'Approving changes the setting now; the previous value is kept.' : 'Approving records your decision; the System carries it out next.';
      return form(m.type === 'APPROVE' ? `Approve · ${esc(r.title || '')}` : `Decline · ${esc(r.title || '')}`, `<p class="small"><b>Seen:</b> ${esc(r.observe || '')}</p><p class="small"><b>Why:</b> ${esc(r.diagnose || '')}</p>
        <p class="small"><b>Recommended:</b> ${esc(r.recommend || '')}</p>${m.type === 'APPROVE' ? `<p class="small muted">${esc(what)} It is measured again 7 days after it is applied.</p>` : ''}${fld('Note (optional)', 'rec-note', 'text', '', 'maxlength="300"')}`,
        m.type === 'APPROVE' ? 'Approve' : 'Decline', m.type !== 'APPROVE');
    }
    case 'studio-new': return studioNewModal(m);
    case 'studio-role': return studioRoleModal(m);
    case 'revenue-import': {
      const P = m.preview;
      return `<div class="modal-bg"><div class="modal wide"><h3>Import historical revenue</h3>
        <p class="small">Paste the table with a header row (from Google Sheets or Excel, saved as CSV). Columns: <code>${REV_COLUMNS.join(', ')}</code>. Required on every row: client, date (YYYY-MM-DD), gross, currency, payment_status (PAID, PART_PAID or PENDING) and evidence (invoice number, bank reference, contract or email). Nothing is estimated: a row without evidence is refused.</p>
        <label class="field"><span>Rows</span><textarea id="rv-text" rows="8" placeholder="client,project,date,service,director,gross,supplier_cost,payment_status,currency,evidence">${esc(m.text || '')}</textarea></label>
        ${P ? `<div class="small ${P.errors?.length ? '' : 'ok-text'}"><b>${(P.valid || []).length}</b> rows ready${Object.keys(P.totals || {}).length ? ` · ${esc(Object.entries(P.totals).map(([c, a]) => cash(a, c)).join(' + '))}` : ''} · ${(P.duplicates || []).length} already recorded (skipped) · ${(P.errors || []).length} with problems</div>
          ${(P.errors || []).length ? `<div class="banner err small">${P.errors.slice(0, 8).map((e) => `Row ${esc(e.row)}${e.client ? ` (${esc(e.client)})` : ''}: ${esc((e.errors || []).join('; '))}`).join('<br>')}</div>` : ''}` : ''}
        <div class="btn-row"><button class="btn" id="rv-check">Check rows</button>${P && (P.valid || []).length && !(P.errors || []).length ? `<button class="btn primary" id="m-ok">Import ${(P.valid || []).length} records</button>` : ''}<button class="btn" data-close>Cancel</button></div></div></div>`;
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
    case 'li-edit': { const tx = val('li-text'); if (!need(tx, 'The text is empty.')) return;
      const r = await done('hq_linkedin_action', { p_id: m.id, p_action: { MESSAGE: 'EDIT', NOTE: 'EDIT_NOTE', FOLLOWUP: 'EDIT_FOLLOWUP' }[m.type || 'MESSAGE'], p_text: tx, p_date: null }, 'Saved.');
      if (r?.ok && r.warning) { state.notice = { err: false, text: `Saved. ${r.warning} This one is ${r.words} words.` }; render(); }
      return r; }
    case 'li-sent': return done('hq_linkedin_action', { p_id: m.id, p_action: 'SENT', p_text: null, p_date: null }, 'Recorded as sent by you. Follow-up 1 is booked four days from now; a reply cancels it.');
    case 'li-hold': return done('hq_linkedin_action', { p_id: m.id, p_action: 'HOLD', p_text: val('li-reason'), p_date: val('li-date') }, 'Held.');
    case 'li-reply': { const tx = val('li-text'); if (!need(tx, 'Paste their reply first.')) return;
      const r = await done('hq_linkedin_reply', { p_id: m.id, p_text: tx, p_class: val('li-class') }, 'Reply logged.');
      if (r?.ok) { state.notice = { err: false, text: r.class === 'MEETING_INTENT' ? 'Reply logged as a meeting request. Meeting Assist proposes two times from your calendar; the reply is under Meetings to schedule.' : `Reply logged (${liClass(r.class).toLowerCase()}). A suggested response is ready to copy.` }; render(); }
      return r; }
    case 'meet-confirm': {
      const pick = document.querySelector('input[name="mc-slot"]:checked')?.value || '';
      const start = pick || (val('mc-date') && val('mc-time') ? `${val('mc-date')} ${val('mc-time')} Europe/London` : null);
      if (!need(start, 'Pick the time they confirmed, or enter a date and time.')) return;
      return done('hq_meeting_confirm', { p_task: m.id, p_start: start, p_minutes: Number(val('mc-min') || 30), p_where: val('mc-where') }, 'Meeting recorded with its briefing. It counts as a meeting in the funnel.'); }
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
    case 'li-archive': {
      state.modal = null; const r = await importLinkedIn(m.conns, m.msgs);
      state.netF.only = r.ok && m.msgs?.rows.length ? 'history' : 'known';
      await load(true); return null; }
    case 'work-order': {
      const mission = val('wo-mission'); if (!need(mission && mission.length >= 5, 'Write the mission in a sentence.')) return;
      const goal = Number(val('wo-goal')); if (!need(goal >= 1, 'The number must be at least 1.')) return;
      const r = await done('hq_work_order', { p_director: val('wo-dir'), p_mission: mission, p_target: val('wo-target'), p_metric: val('wo-metric'), p_goal: goal, p_deadline: val('wo-deadline'), p_priority: val('wo-prio') },
        'Work order issued. Its status follows the evidence: it shows Working once the Director and specialists act on it.');
      if (r && r.ok === false) state.notice = { err: true, text: { UNKNOWN_DIRECTOR: 'Pick a Director.', MISSION_LENGTH: 'The mission needs 5 to 300 characters.', DEADLINE_RANGE: 'The deadline must be within the next 90 days.', GOAL_RANGE: 'The number must be between 1 and 500.' }[r.reason] || explain(r) };
      return r; }
    case 'wo-close': return done('hq_work_order_action', { p_id: m.id, p_action: m.type, p_note: val('wo-note') }, m.type === 'CANCEL' ? 'Work order cancelled. Its results are kept.' : 'Work order closed. Its results are kept.');
    case 'opp-plan': {
      const next = val('op-next'); if (!need(next, 'A next action is required.')) return;
      if (!need(!val('op-due') || val('op-due') >= todayKey(), 'Pick today or a later date.')) return;
      const blocker = val('op-blocker'); const o = (state.cmd?.opportunities || []).find((x) => x.opportunity_id === m.opp) || {};
      return done('hq_opportunity_plan', { p_opportunity: m.opp, p_next_action: next, p_due: val('op-due'), p_owner: val('op-owner'), p_blocker: blocker, p_clear_blocker: !blocker && !!o.blocker }, 'Plan saved.'); }
    case 'rec': return done('hq_recommendation_action', { p_id: m.id, p_action: m.type, p_note: val('rec-note') }, m.type === 'APPROVE' ? 'Approved. It will be measured again in 7 days.' : 'Declined. It will not be recommended again for 30 days.');
    case 'studio-new': {
      const co = studioCompanyId(val('sn-company')); if (!need(co, 'Pick the company from the list (type to search).')) return;
      const r = await done('hq_studio_request', { p_kind: m.type, p_company: co, p_opportunity: m.opp || null, p_note: val('sn-note') },
        'Requested. The Studio prepares it for your review under Needs review. Nothing is sent.');
      loadV3('studio', 'hq_studio', {}, true);
      return r; }
    case 'revenue-import': {
      if (!need((m.preview?.valid || []).length, 'Check the rows first.')) return;
      return done('hq_revenue_import', { p_rows: m.rows, p_apply: true }, `Imported ${(m.preview.valid || []).length} historical revenue records.`); }
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
// LinkedIn "messages.csv": one line per message with LinkedIn's own UTC date. Unsent drafts and spam are left out; text is kept as plain text.
// Adam is the profile present in most conversations (at least 60%): the database checks the same rule again and corrects any line.
const liSlug = (u) => (String(u || '').toLowerCase().match(/linkedin\.com\/in\/([^/?#\s,;]+)/) || [])[1] || null;
const liText = (s) => String(s || '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/p>/gi, '\n').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/[ \t]+/g, ' ').replace(/\n\s*\n+/g, '\n').trim();
function parseMessages(text) {
  const rows = parseCsv(String(text).replace(/^﻿/, ''));
  const h = rows.findIndex((r) => r.some((c) => /^conversation id$/i.test(c.trim())) && r.some((c) => /^date$/i.test(c.trim())));
  if (h < 0) return { error: 'This does not look like LinkedIn\'s messages.csv (no "CONVERSATION ID" / "DATE" header).' };
  const idx = (n) => rows[h].findIndex((c) => c.trim().toLowerCase() === n);
  const I = { cid: idx('conversation id'), title: idx('conversation title'), from: idx('from'), furl: idx('sender profile url'), to: idx('to'), turl: idx('recipient profile urls'),
    date: idx('date'), subject: idx('subject'), content: idx('content'), folder: idx('folder'), draft: idx('is message draft') };
  const good = []; let drafts = 0; let spam = 0; let bad = 0; let dups = 0; const seen = new Set(); const where = new Map(); const convs = new Set();
  const cell = (r, i) => (i >= 0 ? String(r[i] ?? '').trim() : '');
  rows.slice(h + 1).forEach((r) => {
    if (r.every((c) => !String(c).trim())) return;
    if (/^(yes|true)$/i.test(cell(r, I.draft))) { drafts += 1; return; }
    const folder = cell(r, I.folder);
    if (/^spam$/i.test(folder)) { spam += 1; return; }
    const d = cell(r, I.date).match(/^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})(:\d{2})?/); const cid = cell(r, I.cid);
    const from = cell(r, I.from) || null; const furl = liSlug(cell(r, I.furl));
    if (!d || !cid || (!from && !furl)) { bad += 1; return; }
    const sent_at = `${d[1]}T${d[2]}${d[3] || ':00'}Z`; const content = liText(cell(r, I.content)).slice(0, 4000);
    const key = [cid, sent_at, furl || from, content].join('\u001f');
    if (seen.has(key)) { dups += 1; return; }
    seen.add(key); convs.add(cid);
    const rurls = [...new Set(cell(r, I.turl).split(/[\s,;]+/).map(liSlug).filter(Boolean))];
    [furl, ...rurls].filter(Boolean).forEach((s) => { if (!where.has(s)) where.set(s, new Set()); where.get(s).add(cid); });
    good.push({ conversation_id: cid, title: cell(r, I.title) || null, sent_at, from, sender_url: furl ? `https://www.linkedin.com/in/${furl}` : null, to: cell(r, I.to) || null,
      recipient_urls: rurls.map((s) => `https://www.linkedin.com/in/${s}`), subject: cell(r, I.subject) || null, content, folder: folder || null });
  });
  let self = null; let most = 0;
  where.forEach((set, s) => { if (set.size > most) { most = set.size; self = s; } });
  const dates = good.map((x) => x.sent_at).sort();
  return { rows: good, drafts, spam, bad, dups, conversations: convs.size, first: dates[0] || null, last: dates[dates.length - 1] || null,
    self_hint: self && most >= convs.size * 0.6 ? `https://www.linkedin.com/in/${self}` : null };
}
// LinkedIn's download is a .zip. Only Connections.csv and messages.csv are read from it, in the browser, from the zip's own index.
async function unzipLinkedIn(buf) {
  const v = new DataView(buf); const u8 = new Uint8Array(buf); const dec = new TextDecoder('utf-8'); let e = -1;
  for (let i = buf.byteLength - 22; i >= Math.max(0, buf.byteLength - 65557); i -= 1) if (v.getUint32(i, true) === 0x06054b50) { e = i; break; }
  if (e < 0) throw new Error('This file is not a readable .zip. Unzip it and choose Connections.csv and messages.csv instead.');
  const n = v.getUint16(e + 10, true); let p = v.getUint32(e + 16, true); const out = {};
  if (p === 0xffffffff) throw new Error('This archive is too large to open here. Unzip it and choose Connections.csv and messages.csv instead.');
  for (let k = 0; k < n && v.getUint32(p, true) === 0x02014b50; k += 1) {
    const method = v.getUint16(p + 10, true); const size = v.getUint32(p + 20, true); const nl = v.getUint16(p + 28, true); const off = v.getUint32(p + 42, true);
    const name = dec.decode(u8.subarray(p + 46, p + 46 + nl));
    p += 46 + nl + v.getUint16(p + 30, true) + v.getUint16(p + 32, true);
    const key = /(^|\/)connections\.csv$/i.test(name) ? 'connections' : /(^|\/)messages\.csv$/i.test(name) ? 'messages' : null;
    if (!key || out[key] != null) continue;
    const at = off + 30 + v.getUint16(off + 26, true) + v.getUint16(off + 28, true); const data = u8.subarray(at, at + size);
    if (method === 0) out[key] = dec.decode(data);
    else if (method === 8 && typeof DecompressionStream === 'function') out[key] = await new Response(new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).text();
    else throw new Error('This browser cannot open the zip. Unzip it and choose Connections.csv and messages.csv instead.');
  }
  return out;
}
async function readLinkedInFiles(files) {
  const txt = {};
  for (const file of files) {
    if (/\.zip$/i.test(file.name) || file.type === 'application/zip') {
      if (file.size > 500 * 1024 * 1024) throw new Error('This archive is larger than 500 MB. Unzip it and choose Connections.csv and messages.csv instead.');
      Object.assign(txt, await unzipLinkedIn(await file.arrayBuffer()));
    } else if (file.size > 150 * 1024 * 1024) throw new Error(`${file.name} is larger than 150 MB.`);
    else if (/messages\.csv$/i.test(file.name)) txt.messages = await file.text();
    else txt.connections = await file.text();
  }
  if (txt.connections == null && txt.messages == null) throw new Error('No Connections.csv or messages.csv found. Choose the LinkedIn download (.zip) or those two files.');
  const conns = txt.connections != null ? parseConnections(txt.connections) : null;
  const msgs = txt.messages != null ? parseMessages(txt.messages) : null;
  // A file chosen by another name is tried as the other kind before giving up.
  if (conns?.error && !msgs) { const asM = parseMessages(txt.connections); if (!asM.error) return { conns: null, msgs: asM }; }
  if (conns?.error) throw new Error(conns.error);
  if (msgs?.error) throw new Error(msgs.error);
  return { conns, msgs };
}
// Each call is its own short request (people 500 at a time, messages 400 at a time, then the linking steps), so a large archive never
// hits the request time limit. A stop is safe: uploading again adds only what is missing.
async function importLinkedIn(C, M) {
  const say = (text) => { state.notice = { err: false, text }; render(); };
  const rpc = async (fn, args) => { const { data, error } = await sb.rpc(fn, args); if (error || data?.ok === false) throw new Error(error?.message || explain(data)); return data; };
  const st = { file_duplicates: (C?.dups || 0) + (M?.dups || 0), connections_new: 0, connections_updated: 0, connections_skipped: C?.skipped || 0,
    messages_new: 0, messages_already_imported: 0, messages_skipped: 0, drafts_left_out: M?.drafts || 0, spam_left_out: M?.spam || 0 };
  let stage = 'starting';
  try {
    await rpc('hq_linkedin_archive', { p_step: 'start', p_stats: { self_hint: M?.self_hint || null } });
    const cr = C?.rows || []; stage = 'connections';
    for (let i = 0; i < cr.length; i += 500) {
      say(`Importing connections… ${n0(Math.min(i + 500, cr.length))} of ${n0(cr.length)}`);
      const d = await rpc('hq_import_connections', { p_rows: cr.slice(i, i + 500) });
      st.connections_new += d.new ?? 0; st.connections_updated += d.updated ?? 0; st.file_duplicates += d.duplicates ?? 0; st.connections_skipped += d.skipped ?? 0;
    }
    const mr = M?.rows || []; stage = 'messages';
    for (let i = 0; i < mr.length; i += 400) {
      say(`Importing messages… ${n0(Math.min(i + 400, mr.length))} of ${n0(mr.length)}`);
      const d = await rpc('hq_import_linkedin_messages', { p_rows: mr.slice(i, i + 400) });
      st.messages_new += d.new ?? 0; st.messages_already_imported += d.already_imported ?? 0; st.messages_skipped += d.skipped ?? 0;
    }
    const steps = [['self', 'Finding your own profile in the conversations'], ['people', 'Linking the people in each conversation'], ['history', 'Reading each relationship\'s history'], ['match', 'Matching people to the CRM']];
    for (const [i, [s, label]] of steps.entries()) { stage = label.toLowerCase(); say(`${label}… (${i + 1} of 5)`); await rpc('hq_linkedin_archive', { p_step: s }); }
    stage = 'relationship states'; say('Setting each relationship state… (5 of 5)');
    const rep = await rpc('hq_linkedin_archive', { p_step: 'states', p_stats: st });
    state.liArch = rep; state.liHist = {}; delete state.errors.liArch;
    state.notice = { err: false, text: `LinkedIn history imported: ${n0(rep.connections)} connections, ${n0(rep.messages)} messages. ${n0(st.connections_new + st.messages_new)} new, ${n0(st.connections_updated + st.messages_already_imported + st.file_duplicates)} already known (no duplicates). Nothing was sent.` };
    return { ok: true };
  } catch (e) {
    state.notice = { err: true, text: `The import stopped while ${stage}: ${friendly(e.message)} What was saved stays; upload the same file again to finish, nothing will be duplicated.` };
    return { ok: false };
  }
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
  bindAgents(on);
  bindV3(on);
  on('[data-tab]', 'click', (b) => { state.tab = b.dataset.tab; state.notice = null; state.q = ''; state.menu = false; state.drawer = null; render(); window.scrollTo(0, 0); });
  on('[data-go]', 'click', (b, e) => {
    e.stopPropagation(); state.tab = b.dataset.go; if (b.dataset.otab) state.outreachTab = b.dataset.otab;
    if (b.dataset.deskTab) { state.deskTab = b.dataset.deskTab; state.deskPage = 0; }
    if (b.dataset.deskDir !== undefined) { state.deskDir = b.dataset.deskDir; state.deskCh = 'EMAIL'; }
    if (b.dataset.relTab) state.relTab = b.dataset.relTab;
    state.drawer = null; state.modal = null; state.q = ''; state.menu = false; render();
    const anchor = b.dataset.anchor && document.getElementById(b.dataset.anchor);
    if (anchor) anchor.scrollIntoView({ block: 'start' }); else window.scrollTo(0, 0);
  });
  on('[data-otab]:not([data-go])', 'click', (b) => { state.outreachTab = b.dataset.otab; state.oIdx = 0; render(); });
  on('[data-open]', 'click', (b, e) => { e.stopPropagation(); openDrawer(b.dataset.open, b.dataset.id); });
  on('[data-close-drawer]', 'click', () => { state.drawer = null; render(); });
  on('[data-modal]', 'click', (b, e) => { e.stopPropagation(); const x = b.dataset; state.menu = false;
    state.modal = { kind: x.modal, id: x.id || null, opp: x.opp || null, task: x.task || null, channel: x.channel || null, conn: x.conn || null, contact: x.contact || null, company: x.company || null, draft: x.draft || null, next: x.next || null, type: x.type || null, title: x.title || null }; render(); });
  on('[data-li-act]', 'click', (b, e) => { e.stopPropagation(); const k = b.dataset.liAct;
    call('hq_linkedin_action', { p_id: b.dataset.id, p_action: k, p_text: null, p_date: null }, { CONNECTION_SENT: 'Connection request recorded. Press Connected when they accept: the follow-up is then ready.',
      CONNECTED: 'Connected. The follow-up message is ready to copy and send.', RELEASE: 'Back in the queue.', CLOSE: 'Closed.' }[k] || 'Done.'); });
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
    if (error || data?.ok === false) { state.notice = { err: true, text: error ? friendly(error.message) : explain(data) }; if (error) state.errors.lastAction = error.message; render(); return; }
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
  on('[data-er-approve]', 'click', async (b) => {
    const id = b.dataset.erApprove;
    const subject = $(`#er-s-${id}`)?.value; const body = $(`#er-b-${id}`)?.value;
    b.disabled = true;
    const r = await call('hq_approve_email', { p_candidate: id, p_subject: subject ?? null, p_body: body ?? null },
      'Approved. Creating one unsent draft in noya@noyaconcierge.com — open it in Gmail and send it yourself. Nothing was sent.');
    if (r && r.ok) state.pollUntil = Date.now() + 120000;
  });
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
  $('#refresh')?.addEventListener('click', () => { Object.keys(state.errors).forEach((k) => { if (k !== 'lastAction') delete state.errors[k]; }); load(false, 'full'); });
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
    const files = [...(e.target.files || [])]; if (!files.length) return;
    state.notice = { err: false, text: 'Reading the LinkedIn download in your browser…' }; render();
    try {
      const { conns, msgs } = await readLinkedInFiles(files);
      state.notice = null; state.modal = { kind: 'li-archive', conns, msgs }; render();
    } catch (err) { state.notice = { err: true, text: friendly(err.message) }; render(); }
  });
}

// ---------------------------------------------------------------- AGENTS (Adam, 7 Oct): the virtual commercial department
// Today = what Adam does now. Agents = what the research team is doing and producing. Every figure comes from hq_agents()
// (one admin-gated read over companies, contacts, opportunities, drafts, run logs and Gmail state); a click on an agent
// loads hq_agent(key). Status is derived from real run records, never animated.
const AGENT_TABS = ['agentfloor', 'agent', 'emails', 'agentradar', 'feed'];
const AGENT_STATUS = { WORKING: ['Working', 'ok'], WAITING: ['Waiting', ''], BLOCKED: ['Blocked', 'warn'], ERROR: ['Error', 'bad'] };
// Honest email state (Adam, 8 Oct): publicly listed, verified, risky, unverified and invalid are never merged.
const TRUST = { SMTP_VERIFIED: ['SMTP verified', 'ok', 'A verification provider (Hunter) confirmed the mailbox accepts mail.'],
  PUBLICLY_LISTED: ['Publicly listed', 'info', 'Printed on a public page (source linked). Valuable, but not SMTP-verified.'],
  RISKY: ['Risky', 'warn', 'The verifier could not confirm delivery (catch-all or risky domain).'],
  INVALID: ['Invalid', 'bad', 'The verifier rejected this address. Do not send.'],
  UNVERIFIED: ['Unverified', 'warn', 'Not verified and no public source recorded — check before sending.'],
  NOT_VERIFIABLE: ['Not verifiable', 'warn', 'A verification provider could not confirm this address.'],
  SOURCE_NOT_RECORDED: ['Source not recorded', 'warn', 'No source URL was stored for this address — check before sending.'] };
const TIER = { 1: ['Named person', 'gold'], 2: ['Department', ''], 3: ['Company inbox', ''] };
const EMAIL_STATE = { NEW: 'New', READY: 'Ready', SENT: 'Sent', REPLIED: 'Replied', FOLLOW_UP: 'Follow-up', OPEN: 'No draft yet' };
const EMAIL_FILTERS = [['ALL', 'All'], ['NEW', 'New'], ['NAMED', 'Named person'], ['DEPT', 'Department'], ['PUBLIC', 'Public email'], ['VERIFIED', 'Verified'], ['NEEDS', 'Needs verification'], ['READY', 'Ready'], ['SENT', 'Sent'], ['REPLIED', 'Replied'], ['FOLLOW_UP', 'Follow-up'], ['GAPS', 'Email gaps']];
const EMAIL_VERTICALS = [['', 'All verticals'], ['PARTNERSHIPS', 'Partnerships'], ['HOSPITALITY', 'Hospitality'], ['BRANDS', 'Brands'], ['WEDDINGS', 'Weddings'], ['CORPORATE', 'Corporate'], ['TRAVEL', 'Travel'], ['MEDIA', 'Media'], ['SPORTS', 'Sports']];
const agentName = (k) => (state.agents?.agents || []).find((a) => a.key === k)?.name || k || '—';
const rel = (d) => {
  if (!d) return '—';
  const m = Math.round((Date.now() - new Date(d).getTime()) / 60000);
  if (m < 0) { const f = -m; return f < 60 ? `in ${f} min` : f < 1440 ? `in ${Math.round(f / 60)} h` : fmtDate(d); }
  return m < 1 ? 'just now' : m < 60 ? `${m} min ago` : m < 1440 ? `${Math.round(m / 60)} h ago` : fmtDate(d);
};
const n0 = (v) => (v == null ? '—' : esc(v));
async function loadAgents(force = false) {
  if (state.agentsLoading || (state.agents && !force)) return;
  state.agentsLoading = true;
  const { data, error } = await sb.rpc('hq_agents');
  state.agentsLoading = false;
  if (error) state.errors.agents = error.message; else { state.agents = data; delete state.errors.agents; }
  render();
}
async function loadAgent(key, force = false) {
  if (!force && state.agentDetail[key]) return;
  const { data, error } = await sb.rpc('hq_agent', { p_key: key });
  state.agentDetail[key] = error ? { error: error.message } : data;
  render();
}
function needAgents() {
  if (!state.agents) { if (!state.errors.agents) loadAgents(); return state.errors.agents ? unavailable('agents') : '<p class="muted">Loading the agent floor…</p>'; }
  return '';
}
function agentsTabs(active) {
  return `<div class="chips agents-nav">${[['agentfloor', 'Agent floor'], ['emails', 'Email opportunities'], ['agentradar', 'Opportunity radar'], ['feed', 'Activity feed']]
    .map(([k, l]) => `<button class="chip ${active === k ? 'on' : ''}" data-tab="${k}">${l}</button>`).join('')}</div>`;
}
function ceoStrip(a) {
  const c = a.ceo || {}; const t = a.targets || {};
  const healthy = (a.agents || []).filter((x) => x.status === 'WORKING' || x.status === 'WAITING').length;
  const tile = (n, l, go, title = '') => `<div class="tile ${go ? 'link' : ''}" ${go ? `data-tab="${go}"` : ''} title="${esc(title)}"><div class="n">${n}</div><div class="l">${l}</div></div>`;
  const bar = (v, lo, hi, label) => `<div class="target"><div class="small"><b>${esc(label)}</b> ${esc(v)} of ${esc(lo)}–${esc(hi)}</div><div class="tbar"><span data-w="${Math.min(100, Math.round((v / hi) * 100))}"></span></div></div>`;
  return `<div class="tiles agents-ceo">
      ${tile(`${healthy} / ${(a.agents || []).length}`, 'Agents healthy', null, 'Working or waiting for their next scheduled run. Blocked and error are not healthy.')}
      ${tile(n0(c.new_companies_24h), 'New companies · 24h')}${tile(n0(c.new_decision_makers_24h), 'New decision makers · 24h')}
      ${tile(n0(c.new_emails_24h), 'New emails · 24h', 'emails')}${tile(n0(c.ready), 'Ready opportunities', 'outreach')}
      ${tile(n0(c.replies_7d), 'Replies · 7 days', 'inbox')}${tile(n0(c.calls_7d), 'Calls · 7 days')}</div>
    <div class="targets mt8">${bar(c.contactable_3d || 0, t.contactable_3d_low, t.contactable_3d_high, 'Contactable opportunities · 3 days')}
      ${bar(c.hospitality_contactable_3d || 0, t.hospitality_3d_low, t.hospitality_3d_high, 'Hospitality & partnership · 3 days')}
      <div class="small faint">Contactable = ${esc(t.contactable_means || '')}</div></div>`;
}
function bestPanel(a) {
  const b = a.ceo?.best || [];
  return `<section class="panel mt8"><header><h3>Best opportunities found ${a.ceo?.best_window_hours === 24 ? 'today' : 'in the last 3 days'}</h3></header><div class="body">
    ${b.map((x) => `<div class="mini clickable" data-open="company" data-id="${x.company_id}"><div class="t">${esc(x.company)} ${pill(agentName(x.agent))}${x.ready ? ' ' + pill('draft ready', 'ok') : ''}</div>
      <div class="m">${esc([x.type, x.country].filter(Boolean).join(' · '))}${x.person ? ` · ${esc(x.person)}` : ''}${x.email ? ` · ${esc(x.email)}` : ''}</div>
      ${x.model ? `<div class="m">→ ${esc(x.model)}</div>` : ''}${x.concept ? `<div class="m">→ ${esc(x.concept)}</div>` : x.angle ? `<div class="m">→ ${esc(x.angle)}</div>` : ''}</div>`).join('') || '<div class="empty">Nothing qualified in this window yet.</div>'}</div></section>`;
}
const METRIC_ROWS = {
  ACQUISITION: [['discovered', 'Companies'], ['qualified', 'Qualified'], ['decision_makers', 'Decision makers'], ['public_emails', 'Emails'], ['linkedin', 'LinkedIn'], ['instagram', 'Instagram'], ['opportunities', 'Opportunities'], ['outreach_ready', 'Ready'], ['researched', 'Researched'], ['searches', 'Searches']],
  ENRICHMENT: [['companies_email_researched', 'Email researched'], ['named_emails_found', 'Named emails'], ['department_emails_found', 'Department emails'], ['inbox_emails_found', 'Company inboxes'], ['no_email_found', 'No public email'], ['people_from_pages', 'People from pages'], ['companies_enriched', 'People searched'], ['decision_makers', 'People found'], ['linkedin', 'LinkedIn']],
  DRAFTING: [['drafted', 'Drafted'], ['ready', 'Ready'], ['review_required', 'Need review'], ['revalidated', 'Revalidated'], ['ai_usd', 'AI $']],
  REPLY: [['replies', 'Replies'], ['sent_logged', 'Sends logged'], ['gmail_messages_imported', 'Gmail messages']],
  DIRECTOR: [['planned', 'Touches planned'], ['actions_today', 'Actions today'], ['approved_sends_open', 'Approved sends open']],
};
const metricRow = (a) => METRIC_ROWS[a.kind === 'ACQUISITION' ? 'ACQUISITION' : a.key] || [];
function agentCard(a) {
  const [sl, sc] = AGENT_STATUS[a.status] || [a.status, ''];
  const rows = metricRow(a); const top = rows.slice(0, a.kind === 'ACQUISITION' ? 6 : rows.length);
  const notes = (a.blockers || []).filter((b) => /^Note:/.test(b)); const blocks = (a.blockers || []).filter((b) => !/^Note:/.test(b));
  const st = a.stuck || {};
  return `<article class="agent-card clickable" data-agent="${a.key}">
    <div class="agent-head"><div><div class="agent-name">${esc(a.name)}</div><div class="small faint">${esc(a.kind === 'ACQUISITION' ? 'Acquisition agent' : 'Support agent')}</div></div>
      <div class="agent-status">${pill(sl, sc)}</div></div>
    <div class="small mt6">${esc(a.current_work)}</div>
    <div class="small faint mt6">${esc(a.status_reason)} · last ${esc(rel(a.last_run))}${a.last_run_basis && a.last_run_basis !== 'Run log' ? ` (${esc(a.last_run_basis.toLowerCase())})` : ''} · next ${esc(rel(a.next_run))}</div>
    <div class="agent-metrics mt6"><div class="small faint">Today</div><div class="am-grid">${top.map(([k, l]) => `<div><b>${n0(a.today?.[k])}</b><span>${l}</span></div>`).join('')}</div>
      <div class="small faint mt6">Last 3 days</div><div class="am-grid">${top.map(([k, l]) => `<div><b>${n0(a.d3?.[k])}</b><span>${l}</span></div>`).join('')}</div></div>
    ${a.email_funnel ? emailFunnel(a) : a.totals ? `<div class="small mt6">In the universe: ${esc(a.totals.qualified)} qualified · ${esc(a.totals.people)} people · ${esc(a.totals.emails)} emails · <b>${esc(a.totals.ready)} ready for Adam</b></div>` : ''}
    ${blocks.map((b) => `<div class="small bad-text mt6">Blocked: ${esc(b)}</div>`).join('')}
    ${a.kind === 'ACQUISITION' && (st.no_decision_maker || st.no_email || st.needs_verification) ? `<div class="small mt6 stuck">Stuck: ${[st.no_decision_maker ? `${st.no_decision_maker} without a decision maker` : '', st.no_email ? `${st.no_email} without an email` : '', st.needs_verification ? `${st.needs_verification} people need verification` : ''].filter(Boolean).map(esc).join(' · ')}</div>` : ''}
    ${notes.map((b) => `<div class="small faint mt6">${esc(b.replace(/^Note:\s*/, ''))}</div>`).join('')}
  </article>`;
}
// Company-level email funnel (Adam, 8 Oct): qualified → named decision maker → direct / department email → usable → ready.
// Usable = SMTP-verified or publicly listed with its source; company inboxes are not counted as an email lead.
function emailFunnel(a) {
  const f = a.email_funnel; const step = (n, l, cls = '') => `<span class="fn-step ${cls}"><b>${n0(n)}</b> ${l}</span>`;
  return `<div class="funnel mt6"><div class="small faint">Email funnel · companies</div>
    <div class="fn-row">${step(f.qualified, 'qualified')}<i>→</i>${step(f.decision_makers, 'decision makers')}<i>→</i>${step(f.direct_emails, 'direct')}<i>+</i>${step(f.department_emails, 'department')}<i>→</i>${step(f.usable_emails, 'usable', 'gold')}<i>→</i>${step(f.ready_email, 'email ready', 'ok')}</div>
    <div class="small mt6">${n0(f.verified)} SMTP-verified · ${n0(f.ready_linkedin)} LinkedIn ready · <button class="linkish" data-gaps="${a.key}">${n0(f.email_gaps)} email gaps</button>${a.totals ? ` · <b>${esc(a.totals.ready)} ready for Adam</b> (all channels)` : ''}</div></div>`;
}
function feedList(items, limit) {
  return (items || []).slice(0, limit).map((f) => `<div class="feed-row ${f.company_id ? 'clickable' : ''}" ${f.company_id ? `data-open="company" data-id="${f.company_id}"` : ''}>
    <span class="feed-t">${esc(new Date(f.at).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Cairo' }))}<small>${esc(shortDay(f.at))}</small></span>
    <span><b>${esc(agentName(f.agent))}</b> ${esc(f.text)}</span></div>`).join('') || '<div class="empty">No recorded activity in the last 72 hours.</div>';
}
function viewAgents() {
  const wait = needAgents(); if (wait) return `<h2>Agents</h2>${wait}`;
  const a = state.agents; const acq = a.agents.filter((x) => x.kind === 'ACQUISITION'); const sup = a.agents.filter((x) => x.kind === 'SUPPORT');
  return `<div class="ov-head"><h1>Agents</h1><span class="sub">Your commercial team · live from Supabase · ${esc(fmtDate(a.generated_at))} Cairo</span></div>
    ${agentsTabs('agentfloor')}${ceoStrip(a)}${bestPanel(a)}
    <h3 class="mt8">Acquisition agents</h3><div class="agent-grid">${acq.map(agentCard).join('')}</div>
    <h3 class="mt8">Support agents</h3><div class="agent-grid">${sup.map(agentCard).join('')}</div>
    <section class="panel mt8"><header><h3>Activity</h3><button class="btn small ghost" data-tab="feed">Full feed</button></header><div class="body">${feedList(a.feed, 15)}</div></section>`;
}
function personCard(p) {
  const [tl, tc, tt] = TRUST[p.trust] || [];
  return `<div class="mini"><div class="t">${esc(p.name || p.email || 'Company inbox')}${p.role ? ` · <span class="faint">${esc(p.role)}</span>` : ''}</div>
    <div class="m"><a class="clickable" data-open="company" data-id="${p.company_id}">${esc(p.company)}</a>${p.country ? ` · ${esc(p.country)}` : ''} · confidence ${esc((p.confidence || '').toLowerCase().replace('_', ' '))}</div>
    <div class="m">${p.email ? `${esc(p.email)} ${tl ? `<span title="${esc(tt)}">${pill(tl, tc)}</span>` : ''}${p.email_kind === 'OFFICIAL_COMPANY_INBOX' ? ' ' + pill('company inbox') : ''}` : 'No email yet'}
      ${p.linkedin ? ` · <a href="${esc(p.linkedin)}" target="_blank" rel="noopener noreferrer">LinkedIn</a>` : ''}${p.instagram ? ` · <a href="https://instagram.com/${esc(String(p.instagram).replace(/^@/, ''))}" target="_blank" rel="noopener noreferrer">@${esc(String(p.instagram).replace(/^@/, ''))}</a>` : ''}</div>
    <div class="m faint">Source: ${p.source_url ? `<a href="${esc(p.source_url)}" target="_blank" rel="noopener noreferrer">${esc((p.source_type || 'link').toLowerCase().replace(/_/g, ' '))}</a>` : esc(p.source || 'not recorded')} · found ${esc(shortDay(p.found_at))}</div></div>`;
}
function sectionBody(s) {
  const it = s.items;
  switch (s.kind) {
    case 'companies': return it.map((c) => `<div class="mini clickable" data-open="company" data-id="${c.company_id}"><div class="t">${esc(c.company)} ${c.status ? pill(sentence(c.status)) : ''}</div>
      <div class="m">${esc([c.type, c.country].filter(Boolean).join(' · '))}${c.people != null ? ` · ${esc(c.people)} people · ${esc(c.emails)} emails` : ''} · ${esc(shortDay(c.found_at))}</div>
      ${c.missing ? `<div class="m">${esc(c.missing)}${c.attempts ? ` · enrichment attempts ${esc(c.attempts)}` : ''}</div>` : ''}${c.model ? `<div class="m">→ ${esc(c.model)}</div>` : ''}
      ${c.source ? `<div class="m faint">${esc(/Department/.test(c.source) ? 'Found by the agent' : /WATCHLIST/.test(c.source) ? 'Agent watchlist' : `Added by research: ${c.source}`)}</div>` : ''}</div>`).join('');
    case 'people': return it.map(personCard).join('');
    case 'opportunities': return it.map((o) => `<div class="mini clickable" data-open="company" data-id="${o.company_id}"><div class="t">${esc(o.company)}${o.status ? ' ' + pill(sentence(o.status)) : ''}</div>
      ${o.model ? `<div class="m"><b>${esc(o.model.split(':')[0])}</b></div>${(o.route || []).map((r) => `<div class="m">→ ${esc(r)}</div>`).join('')}` : ''}
      ${o.concept ? `<div class="m"><b>Egypt concept · ${esc(o.concept.backdrop)}</b></div><div class="m">→ ${esc(o.concept.concept)}</div><div class="m">→ NOYA: ${esc(o.concept.noya_role)}</div>` : ''}
      ${o.angle ? `<div class="m faint">${esc(plainText(o.angle))}</div>` : ''}</div>`).join('');
    case 'tasks': return it.map((t) => `<div class="mini clickable" data-open="company" data-id="${t.company_id}"><div class="t">${esc(sentence(t.title))}${t.approved ? ' ' + pill('approved by you', 'ok') : ''}</div><div class="m">${esc(t.person || '')} · prepared ${esc(shortDay(t.created_at))}</div></div>`).join('');
    case 'counts': return `<div class="pills">${Object.entries(it).map(([k, v]) => pill(`${v} ${k.toLowerCase().replace(/_/g, ' ')}`)).join('')}</div>`;
    case 'runs': return it.map((r) => `<div class="mini"><div class="t">${esc(fmtDate(r.at))}</div><div class="m">${n0(r.searches)} searches · ${n0(r.candidates)} candidates · ${n0(r.researched)} researched · ${n0(r.qualified)} qualified · ${n0(r.known_skipped)} already known</div></div>`).join('');
    case 'drafts': return it.map((x) => `<div class="mini clickable" data-open="company" data-id="${x.company_id}"><div class="t">${esc(x.company)} ${pill(sentence(x.status))}</div><div class="m">${esc([x.person, x.channel, x.subject].filter(Boolean).join(' · '))}${x.hold_reason ? ` · ${esc(x.hold_reason)}` : ''} · ${esc(shortDay(x.at))}</div></div>`).join('');
    case 'replies': return it.map((x) => `<div class="mini clickable" data-open="company" data-id="${x.company_id}"><div class="t">${esc(x.company)} ${pill(sentence(String(x.state || '').replace(/_/g, ' ')))}</div><div class="m">${esc(x.subject || '')} · ${esc(fmtDate(x.at))}</div>${x.summary ? `<div class="m faint">${esc(x.summary)}</div>` : ''}</div>`).join('');
    case 'actions': return it.map((x) => `<div class="mini"><div class="t">${esc(x.rank)}. ${esc(x.action)} · ${esc(x.company || '')}</div><div class="m">${esc(x.detail || '')}</div></div>`).join('');
    default: return '';
  }
}
function viewAgent() {
  const wait = needAgents(); if (wait) return wait;
  const key = state.agentKey; const a = (state.agents.agents || []).find((x) => x.key === key);
  if (!a) return `${agentsTabs('agentfloor')}<p class="muted">Pick an agent on the floor.</p>`;
  const d = state.agentDetail[key];
  if (!d) loadAgent(key);
  const secs = d?.sections || [];
  const cur = state.agentSec[key] || secs[0]?.key;
  const s = secs.find((x) => x.key === cur) || secs[0];
  const count = (x) => (Array.isArray(x.items) ? x.items.length : Object.keys(x.items || {}).length);
  return `${agentsTabs('agentfloor')}<button class="btn small ghost" data-tab="agentfloor">← All agents</button>
    <div class="agent-detail mt8">${agentCard(a)}</div>
    <p class="small faint">${esc(a.scope)}</p>
    ${!d ? '<p class="muted">Loading this agent\'s work…</p>' : d.error ? unavailable(`agent:${state.agentKey}`) : `
    <div class="chips">${secs.map((x) => `<button class="chip ${s && x.key === s.key ? 'on' : ''}" data-agent-sec="${x.key}">${esc(x.title)} · ${count(x)}</button>`).join('')}</div>
    ${s ? `<section class="panel mt8"><header><h3>${esc(s.title)}</h3></header><div class="body">${sectionBody(s)}</div></section>` : '<p class="muted">Nothing recorded for this agent yet.</p>'}`}`;
}
function emailMatches(e, f) {
  const v = f.v;
  if (v === 'PARTNERSHIPS' && !(['HOSPITALITY', 'TRAVEL'].includes(e.agent) && e.opportunity)) return false;
  if (v && v !== 'PARTNERSHIPS' && e.agent !== v) return false;
  switch (f.s) {
    case 'NEW': return e.state === 'NEW';
    case 'NAMED': return e.tier === 1;
    case 'DEPT': return e.tier === 2;
    case 'PUBLIC': return e.trust === 'PUBLICLY_LISTED';
    case 'VERIFIED': return e.trust === 'SMTP_VERIFIED';
    case 'NEEDS': return e.trust !== 'SMTP_VERIFIED';
    case 'READY': case 'SENT': case 'REPLIED': case 'FOLLOW_UP': return e.state === f.s;
    default: return true;
  }
}
function emailCard(e) {
  const [tl, tc, tt] = TRUST[e.trust] || []; const open = state.emailOpen === e.contact_id;
  return `<article class="card email-card"><div class="card-head"><div><div class="co">${esc(e.person || 'Company inbox')}</div>
      <div class="small">${esc([e.role, e.company].filter(Boolean).join(' · '))}</div></div>
      <div class="pills">${pill(EMAIL_STATE[e.state] || e.state, e.state === 'REPLIED' ? 'ok' : e.state === 'READY' ? 'gold' : '')}${pill(agentName(e.agent))}</div></div>
    <div class="email-line mt6"><b>${esc(e.email)}</b> ${tl ? `<span title="${esc(tt)}">${pill(tl, tc)}</span>` : ''} ${TIER[e.tier] ? pill(...TIER[e.tier]) : e.email_kind === 'OFFICIAL_COMPANY_INBOX' ? pill('company inbox') : pill('personal')}</div>
    <div class="small faint">From: ${e.source_url ? `<a href="${esc(e.source_url)}" target="_blank" rel="noopener noreferrer">${esc((e.source_type || 'source').toLowerCase().replace(/_/g, ' '))}</a>` : esc(e.source || 'source not recorded')} · ${esc(e.market || 'market unknown')}</div>
    ${e.opportunity ? `<div class="small mt6"><b>Opportunity:</b> ${esc(e.opportunity)}</div>` : ''}
    ${e.why_noya ? `<div class="small mt6"><b>Why NOYA:</b> ${esc(e.why_noya)}</div>` : ''}
    ${e.why_now ? `<div class="small mt6"><b>Why now:</b> ${esc(e.why_now)}</div>` : ''}
    <div class="small mt6 faint">${e.draft_state ? `Draft: ${esc(sentence(e.draft_state))}` : 'No draft yet'} · relationship ${esc(String(e.prior_relationship || 'unknown').toLowerCase().replace(/_/g, ' '))}${e.last_contact ? ` · last contact ${esc(shortDay(e.last_contact))}` : ''}</div>
    <div class="btn-row mt6"><button class="btn small" data-email-open="${e.contact_id}">${open ? 'Hide' : 'What to say'}</button><button class="btn small ghost" data-open="company" data-id="${e.company_id}">Account</button></div>
    ${open ? `<div class="draft-box mt6">${e.draft ? `${e.draft_subject ? `<div><b>${esc(e.draft_subject)}</b></div>` : ''}<pre>${esc(e.draft)}</pre>` : '<span class="small faint">No finished draft for this person yet. The Commercial Director plans drafts nightly; open the account to request one.</span>'}</div>` : ''}
  </article>`;
}
const gapMatches = (g, v) => !v || (v === 'PARTNERSHIPS' ? ['HOSPITALITY', 'TRAVEL'].includes(g.agent) : g.agent === v);
// The email gap queue: qualified, a commercial angle, a person known, no usable named or department email yet — ranked by
// strategic value, decision-maker quality, partnership potential and the chance of a public email. Workflow 23 works it 4x a day.
function gapCard(g) {
  const r = g.routes || {}; const p = (g.people || [])[0]; const open = state.gapOpen === g.company_id;
  const have = [r.tier3 ? 'company inbox' : '', r.linkedin ? 'LinkedIn' : '', r.instagram ? 'Instagram' : ''].filter(Boolean);
  return `<article class="card email-card"><div class="card-head"><div><div class="co">${esc(g.company)}</div>
      <div class="small">${esc([g.company_type, g.city, g.country].filter(Boolean).join(' · '))}</div></div>
      <div class="pills">${pill(`score ${g.score}`)}${pill(agentName(g.agent))}</div></div>
    <div class="small mt6"><b>Decision maker:</b> ${p ? `${esc(`${p.first_name} ${p.last_name}`)}${p.position ? ` · ${esc(p.position)}` : ''}` : '<span class="faint">none named yet</span>'}</div>
    <div class="small"><b>Email:</b> <span class="warn-text">no named or department email yet</span>${have.length ? ` · has ${esc(have.join(', '))}` : ''}</div>
    ${g.model ? `<div class="small mt6"><b>Model:</b> ${esc(g.model)}</div>` : ''}
    <div class="small faint mt6">${g.checked_at ? `Searched ${esc(shortDay(g.checked_at))} · ${esc(g.attempts)} attempt${g.attempts === 1 ? '' : 's'}` : 'Not searched for email yet'} · looking for: ${esc((g.role_focus || []).slice(0, 4).join(', '))}</div>
    <div class="btn-row mt6"><button class="btn small" data-gap-open="${g.company_id}">${open ? 'Hide' : 'Angle'}</button><button class="btn small ghost" data-open="company" data-id="${g.company_id}">Account</button></div>
    ${open ? `<div class="draft-box mt6 small">${esc(g.angle || 'No angle recorded yet.')}</div>` : ''}
  </article>`;
}
function emailReport(r) {
  if (!r) return '';
  const t = (n, l) => `<div class="tile"><div class="n">${n0(n)}</div><div class="l">${l}</div></div>`;
  return `<div class="tiles agents-ceo mt8">${t(r.companies_researched, 'Companies researched · 3d')}${t(r.decision_makers_found, 'Decision makers found')}
    ${t(r.named_public_emails, 'Named public emails')}${t(r.department_emails, 'Department emails')}${t(r.verified_emails, 'SMTP-verified')}
    ${t(r.emails_still_missing, 'Emails still missing')}${t(r.linkedin_only, 'LinkedIn-only')}${t(r.instagram_only, 'Instagram-only')}
    ${t(r.ready_email_drafts, 'Email drafts ready')}${t(r.ready_linkedin_drafts, 'LinkedIn drafts ready')}</div>`;
}
function viewEmails() {
  const wait = needAgents(); if (wait) return `<h2>Email opportunities</h2>${wait}`;
  const f = state.emailF; const all = state.agents.email_desk || []; const gaps = state.agents.email_gaps || [];
  const gapList = gaps.filter((g) => gapMatches(g, f.v));
  const list = f.s === 'GAPS' ? gapList : all.filter((e) => emailMatches(e, f));
  const cnt = (s) => (s === 'GAPS' ? gapList.length : all.filter((e) => emailMatches(e, { s, v: f.v })).length);
  const shown = list.slice(0, state.emailN);
  return `<div class="ov-head"><h1>Email opportunities</h1><span class="sub">Every prospect with a usable email · ${esc(all.length)} in total · publicly listed is not the same as SMTP verified</span></div>
    ${agentsTabs('emails')}${emailReport(state.agents.email_report)}
    <div class="chips mt8">${EMAIL_FILTERS.map(([k, l]) => `<button class="chip ${f.s === k ? 'on' : ''}" data-emf="s" data-v="${k}">${l} · ${cnt(k)}</button>`).join('')}</div>
    <div class="chips">${EMAIL_VERTICALS.map(([k, l]) => `<button class="chip ${f.v === k ? 'on' : ''}" data-emf="v" data-v="${k}">${l}</button>`).join('')}</div>
    ${f.s === 'GAPS' ? '<p class="small faint">Qualified, a strong angle and a person known, but no usable named or department email yet. Ranked by strategic value, decision-maker quality, partnership potential and the chance of a public email. The Email & Contact Intelligence agent works this queue four times a day.</p>' : ''}
    <div class="email-grid mt8">${shown.map(f.s === 'GAPS' ? gapCard : emailCard).join('') || '<p class="muted">No prospects match these filters.</p>'}</div>
    ${list.length > shown.length ? `<button class="btn full mt8" data-email-more>Show more (${list.length - shown.length})</button>` : ''}`;
}
function viewAgentRadar() {
  const wait = needAgents(); if (wait) return `<h2>Opportunity radar</h2>${wait}`;
  const f = state.radarAg; const items = (state.agents.radar || []).filter((r) => !f || (f === 'CONCEPT' ? r.kind === 'CONCEPT' : r.agent === f && r.kind !== 'CONCEPT'));
  const agents = [...new Set((state.agents.radar || []).filter((r) => r.kind !== 'CONCEPT').map((r) => r.agent))];
  return `<div class="ov-head"><h1>Opportunity radar</h1><span class="sub">Routes to money the agents have found — commercial models, not CRM records</span></div>
    ${agentsTabs('agentradar')}
    <div class="chips"><button class="chip ${!f ? 'on' : ''}" data-rag="">All · ${(state.agents.radar || []).length}</button><button class="chip ${f === 'CONCEPT' ? 'on' : ''}" data-rag="CONCEPT">Egypt filmed concepts</button>
      ${agents.map((k) => `<button class="chip ${f === k ? 'on' : ''}" data-rag="${k}">${esc(agentName(k))}</button>`).join('')}</div>
    <div class="email-grid mt8">${items.map((r) => `<article class="card radar-card clickable" data-open="company" data-id="${r.company_id}">
      <div class="co">${esc(r.company)}</div><div class="small"><b>${esc(r.headline)}</b></div>
      ${(r.lines || []).filter(Boolean).map((l) => `<div class="small">→ ${esc(l)}</div>`).join('')}
      <div class="small faint mt6">${esc(agentName(r.agent))} · ${esc(shortDay(r.at))}</div></article>`).join('') || '<p class="muted">Nothing on the radar for this filter.</p>'}</div>`;
}
function viewFeed() {
  const wait = needAgents(); if (wait) return `<h2>Activity feed</h2>${wait}`;
  const f = state.feedAg; const items = (state.agents.feed || []).filter((x) => !f || x.agent === f);
  return `<div class="ov-head"><h1>Activity feed</h1><span class="sub">Stored events from the last 72 hours — runs, finds, people, drafts, replies, rejections</span></div>
    ${agentsTabs('feed')}
    <div class="chips"><button class="chip ${!f ? 'on' : ''}" data-feed-ag="">All</button>${(state.agents.agents || []).map((a) => `<button class="chip ${f === a.key ? 'on' : ''}" data-feed-ag="${a.key}">${esc(a.name)}</button>`).join('')}</div>
    <section class="panel mt8"><div class="body">${feedList(items, 120)}</div></section>`;
}
function bindAgents(on) {
  on('[data-agent]', 'click', (b) => { state.agentKey = b.dataset.agent; state.tab = 'agent'; render(); loadAgent(b.dataset.agent); window.scrollTo(0, 0); });
  on('[data-agent-sec]', 'click', (b) => { state.agentSec[state.agentKey] = b.dataset.agentSec; render(); });
  on('button[data-emf]', 'click', (b) => { state.emailF[b.dataset.emf] = b.dataset.v; state.emailN = 30; render(); });
  on('[data-email-open]', 'click', (b) => { state.emailOpen = state.emailOpen === b.dataset.emailOpen ? null : b.dataset.emailOpen; render(); });
  on('[data-email-more]', 'click', () => { state.emailN += 30; render(); });
  on('[data-gap-open]', 'click', (b) => { state.gapOpen = state.gapOpen === b.dataset.gapOpen ? null : b.dataset.gapOpen; render(); });
  on('[data-gaps]', 'click', (b, ev) => { ev?.stopPropagation?.(); state.emailF = { s: 'GAPS', v: b.dataset.gaps }; state.emailN = 30; state.tab = 'emails'; render(); window.scrollTo(0, 0); });
  on('[data-rag]', 'click', (b) => { state.radarAg = b.dataset.rag; render(); });
  on('[data-feed-ag]', 'click', (b) => { state.feedAg = b.dataset.feedAg; render(); });
}

// ================================================================ HQ V3 (Adam, 9 Oct): consolidate, simplify, prove, freeze
// Six destinations. Every number on these screens comes from one admin-gated read and reconciles with the others:
// hq_outreach_desk (approval desk), hq_directors / hq_director (the workforce), hq_club, hq_operations, hq_growth.
const moreOpen = () => state.more || MORE_KEYS.includes(state.tab);
const plural = (n, one, many) => `${n} ${Number(n) === 1 ? one : many}`;
async function loadV3(key, fn, args = {}, force = false) {
  // A read that failed waits for Retry or the next refresh: never re-requested on every redraw.
  if (state.busy[key] || (!force && (state[key] || state.errors[errKey(key)]))) return;
  if (SNAPSHOTS[key] || READS[key] === fn) { await readKey(key); render(); return; }
  state.busy[key] = true;
  const { data, error } = await sb.rpc(fn, args);
  state.busy[key] = false;
  if (error) state.errors[key] = error.message; else { state[key] = data; delete state.errors[key]; }
  render();
}
async function loadDirector(key, force = false) {
  if (!force && (state.dirDetail[key] || state.errors[`director:${key}`])) return;
  if (state.busy[`dir:${key}`]) return;
  state.busy[`dir:${key}`] = true;
  const { data, error } = await sb.rpc('hq_cached', { p_key: `director:${key}` });
  state.busy[`dir:${key}`] = false;
  const bad = error || (data && data.ok === false && data.reason && Object.keys(data).length <= 2);
  if (bad) { state.errors[`director:${key}`] = error ? error.message : `snapshot ${data.reason}`; if (!state.dirDetail[key] || state.dirDetail[key].error) state.dirDetail[key] = { error: true }; }
  else { state.dirDetail[key] = data; delete state.errors[`director:${key}`]; }
  render();
}
// One clean state for missing data on every CEO screen; the raw reason is kept for More / Admin → System.
// "Updated 21:05": the age of a background snapshot, shown quietly next to the screen title.
const asOf = (o) => (o?._cache?.built_at ? `updated ${new Date(o._cache.built_at).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Cairo' })}` : '');
const unavailable = (key) => `<div class="unavail"><span>Some data is temporarily unavailable.</span><button class="btn small" data-retry="${esc(key)}">Retry</button></div>`;
const waitFor = (key, what) => (state.errors[errKey(key)] ? unavailable(key) : `<p class="muted">Loading ${esc(what)}…</p>`);
// Technical failures never reach a CEO screen as raw text: timeouts, SQL and network errors become a plain sentence.
function friendly(msg) {
  const m = String(msg || '');
  if (/not authorised/i.test(m)) return 'This account is not authorised for NOYA HQ.';
  if (/timeout|canceling statement|Failed to fetch|NetworkError|Load failed|ECONN|50[234]/i.test(m)) return 'That took too long to complete. Nothing was sent or changed. Please retry.';
  if (/PGRST|SQLSTATE|syntax|relation "|function |column |permission denied|JWT|violates|duplicate key|null value|operator does not exist|42\d{3}|23\d{3}|22\d{3}/i.test(m)) return 'That action could not complete. Nothing was sent. Please retry; the detail is under More / Admin → System.';
  return m;
}
const head = (title, sub) => `<div class="ov-head"><h1>${esc(title)}</h1>${sub ? `<span class="sub">${sub}</span>` : ''}</div>`;
const memberName = (k) => (state.directors?.members || []).find((x) => x.key === k)?.name || ({ ENRICHMENT: 'Contact & Email Intelligence', DRAFTING: 'Outreach Writer' }[k]) || k || '—';
const CH_LABEL = { EMAIL: 'Email', LINKEDIN: 'LinkedIn', INSTAGRAM: 'Instagram', WHATSAPP: 'WhatsApp', INSTAGRAM_DM: 'Instagram' };
const ESTATE = { VALID_VERIFIED: ['Valid · verified', 'ok'], ACCEPT_ALL: ['Accept-all · not verifiable', 'warn'], PUBLIC_UNVERIFIED: ['Public · not verified', 'warn'],
  UNKNOWN: ['Unknown', 'warn'], INVALID: ['Invalid', 'bad'], NOT_FOUND: ['No email', ''],
  OFFICIAL_PUBLISHED_INBOX: ['Official inbox · company website · not verified', 'info'] };
const estatePill = (s) => { const [l, c] = ESTATE[s] || [s || 'No email', '']; return pill(l, c); };

// ---------------------------------------------------------------- HQ ADVISOR: Adam's Chief of Staff across every Director
// hq_advisor(): the brief, 3-5 observations (situation -> meaning -> action), what changed since the last visit, where NOYA is
// winning and wasting time. hq_advisor_seen() marks the visit first, so "since" is the previous visit. All from NOYA data.
async function loadAdvisor() {
  if (!state.advisorSeen) { state.advisorSeen = true; await sb.rpc('hq_advisor_seen'); }
  await readKey('advisor'); render();
}
function advisorToday() {
  const A = state.advisor;
  if (!A) return state.errors.advisor ? '' : '<section class="advisor"><p class="muted small">HQ Advisor is reading the Directors…</p></section>';
  const brief = (A.brief || []).map((b) => `<button class="adv-chip" data-go="${esc(b.tab)}">${esc(b.text)}</button>`).join('');
  const obs = (A.observations || []).map((o) => `<li class="adv-obs ${o.kind === 'BOTTLENECK' ? 'bottleneck' : o.kind === 'ATTENTION' ? 'attention' : ''}">
      ${o.title ? `<div class="adv-k">${esc(o.title)}</div>` : ''}<div class="adv-s">${esc(o.situation)}</div><div class="adv-m">${esc(o.meaning)}</div>
      <div class="adv-a">→ ${esc(o.action)}</div></li>`).join('');
  const changed = (A.changed || []).map((c) => c.text).join(' · ');
  return `<section class="advisor">${brief ? `<div class="adv-brief">${brief}</div>` : ''}
    <div class="adv-head"><h3>HQ Advisor</h3><button class="linkish" data-weekly>Weekly review</button></div>
    ${obs ? `<ol class="adv-list">${obs}</ol>` : '<p class="muted small">Nothing to flag: the Directors are on plan.</p>'}
    ${changed ? `<p class="adv-changed"><b>Since ${esc(fmtDate(A.since))}:</b> ${esc(changed)}</p>` : ''}</section>`;
}
function advisorAgents() {
  const A = state.advisor; if (!A) return '';
  const b = (A.observations || []).filter((o) => o.kind === 'BOTTLENECK');
  if (!b.length && !(A.winning || []).length && !(A.wasting || []).length) return '';
  return `<section class="panel advisor-strip"><header><h3>HQ Advisor</h3><button class="linkish" data-weekly>Weekly review</button></header><div class="body adv-cols">
    <div><h6>Bottlenecks</h6>${b.map((o) => `<div class="adv-row"><b>${esc(o.title || '')}</b> ${esc(o.situation)} <span class="faint">→ ${esc(o.action)}</span></div>`).join('') || '<p class="muted small">None.</p>'}</div>
    <div><h6>Where NOYA is winning</h6>${(A.winning || []).map((w) => `<div class="adv-row">${esc(w.text)}</div>`).join('') || '<p class="muted small">No replies in the last 30 days yet.</p>'}
      <h6 class="mt8">Where time is being wasted</h6>${(A.wasting || []).map((w) => `<div class="adv-row">${esc(w.text)}</div>`).join('') || '<p class="muted small">Nothing flagged.</p>'}</div></div></section>`;
}
function weeklyModal() {
  const W = state.weekly;
  let body = waitFor('weekly', 'the weekly review');
  if (W) {
    const t = W.this_week || {}; const p = W.previous_week || {};
    const tl = (n, l) => `<div class="tile"><div class="n">${n}</div><div class="l">${l}</div></div>`;
    body = `<p class="adv-summary">This week: ${esc(plural(n0(t.sent), 'new outreach message', 'new outreach messages'))} (${n0(t.sent_email)} email, ${n0(t.sent_linkedin)} LinkedIn; ${n0(p.sent)} the week before),
        ${esc(plural(n0(t.replies), 'company replied', 'companies replied'))}${W.reply_rate_pct != null ? ` (${W.reply_rate_pct}%${t.unclassified ? `; ${n0(t.unclassified)} not classified yet, positive counted from your own triage` : ''})` : ''}, ${esc(plural(n0(W.meetings), 'meeting', 'meetings'))}, ${esc(plural(n0(W.wins), 'win', 'wins'))}.</p>
      <div class="tiles">${tl(n0(t.sent), 'New outreach')}${tl(W.reply_rate_pct != null ? `${W.reply_rate_pct}%` : '—', 'Reply rate')}${tl(W.positive_reply_rate_pct != null ? `${W.positive_reply_rate_pct}%` : '—', 'Positive reply rate')}
        ${tl(n0(W.meetings), 'Meetings')}${tl(n0(W.proposals), 'Proposals')}${tl(n0(W.wins), 'Wins')}${tl(n0(W.verified_emails), 'Verified emails')}${tl(`${n0(W.email_drafts)} / ${n0(W.linkedin_drafts)}`, 'Email / LinkedIn drafts')}</div>
      <div class="tbl-wrap mt8"><table class="stack wk-dir"><thead><tr><th>Director</th><th class="num">Email coverage</th><th class="num">Verified / with decision maker</th><th class="num">LinkedIn fallback</th><th class="num">Sent</th><th class="num">Replies</th></tr></thead><tbody>
        ${(W.by_director || []).map((d) => `<tr><td>${esc(d.label)}</td><td class="num" data-l="Email coverage">${d.coverage_pct == null ? '—' : `${esc(d.coverage_pct)}%`}</td><td class="num" data-l="Verified / with decision maker">${n0(d.verified)} / ${n0(d.with_dm)}</td>
          <td class="num" data-l="LinkedIn fallback">${n0(d.linkedin_fallback)}</td><td class="num" data-l="Sent">${n0(d.sent)}</td><td class="num" data-l="Replies">${n0(d.replies)}</td></tr>`).join('')}</tbody></table></div>
      ${(W.strongest_opportunities || []).length ? `<h6 class="mt8">Strongest opportunities</h6>${W.strongest_opportunities.map((o) => `<div class="adv-row"><b>${esc(o.company)}</b> · ${esc(sentence(String(o.status || '').replace(/_/g, ' ')))}${o.next ? ` <span class="faint">→ ${esc(o.next)}</span>` : ''}</div>`).join('')}` : ''}
      ${weeklyMission(W.destination_egypt)}${weeklyAttribution(W.attribution)}${weeklyHunter(W.hunter_funnel)}
      ${W.acquisition ? `<h6 class="mt8">Acquisition health</h6><div class="adv-row">Email ready <b>${n0(W.acquisition.email_ready)}</b> (valid verified ${n0(W.acquisition.valid_verified_email_ready)}, verified general inbox ${n0(W.acquisition.verified_general_email_ready)}) · LinkedIn fallback ${n0(W.acquisition.linkedin_fallback)} · Instagram fallback ${n0(W.acquisition.instagram_fallback)} · warm ${n0(W.acquisition.warm)} · existing relationship ${n0(W.acquisition.existing_relationship)}</div>` : ''}
      ${W.weakest_bottleneck ? `<h6 class="mt8">Weakest bottleneck</h6><div class="adv-row">${esc(W.weakest_bottleneck)}</div>` : ''}
      ${W.recommended_allocation ? `<h6 class="mt8">Recommended allocation</h6><div class="adv-row">${esc(W.recommended_allocation)}</div>` : ''}`;
  }
  return `<div class="modal-bg"><div class="modal wide"><h3>Weekly review</h3><p class="small faint">The last 7 days, from NOYA's own records.</p>${body}
    <div class="btn-row mt8"><button class="btn ghost" data-close>Close</button></div></div></div>`;
}
const DIRECTOR_LABEL = { BRANDS: 'Brands & Production', WEDDINGS: 'Weddings & Events', TRAVEL: 'Travel & Concierge', HOSPITALITY: 'Hospitality', PRIVATE: 'Private Membership',
  SPORTS: 'NOYA Private', CORPORATE: 'Corporate', MEDIA: 'Media & Culture', EGYPT: 'Egypt' };
// Replies attributed to the message that started the sequence, by channel and by Director x send week (never same-period sends vs replies).
function weeklyAttribution(a) {
  if (!a) return '';
  const ch = a.by_channel || {};
  const line = (k, l) => ch[k] ? `${l}: ${n0(ch[k].sent)} sent → ${n0(ch[k].replied)} replied (${ch[k].reply_rate_pct ?? 0}%) → ${n0(ch[k].positive)} positive → ${n0(ch[k].meetings)} meetings` : '';
  const rows = (a.rows || []).slice(0, 24);
  return `<h6 class="mt8">Reply attribution · last ${esc(a.weeks)} weeks</h6><div class="adv-row">${[line('EMAIL', 'Email'), line('LINKEDIN', 'LinkedIn')].filter(Boolean).map(esc).join('<br>') || 'No first messages sent in this window.'}</div>
    ${rows.length ? `<div class="tbl-wrap mt6"><table class="stack"><thead><tr><th>Send week</th><th>Director</th><th>Channel</th><th class="num">Sent</th><th class="num">Replied</th><th class="num">Positive</th><th class="num">Meetings</th></tr></thead><tbody>
      ${rows.map((r) => `<tr><td>${esc(shortDay(r.cohort))}</td><td data-l="Director">${esc(DIRECTOR_LABEL[r.director] || human(r.director))}</td><td data-l="Channel">${esc(human(r.channel))}</td><td class="num" data-l="Sent">${n0(r.sent)}</td><td class="num" data-l="Replied">${n0(r.replied)}</td><td class="num" data-l="Positive">${n0(r.positive)}</td><td class="num" data-l="Meetings">${n0(r.meetings)}</td></tr>`).join('')}</tbody></table></div>` : ''}
    <p class="src">${esc(a.method || '')}</p>`;
}
// Hunter, day by day: finder -> verification -> VALID / RISKY / INVALID -> credits -> drafts -> sends -> replies -> meetings.
function weeklyHunter(h) {
  if (!h) return '';
  const t = h.totals || {}; const m = h.monthly_projection || {};
  return `<h6 class="mt8">Hunter · last 7 days (${esc(h.plan || 'Free')})</h6><div class="adv-row">Finder ${n0(t.finder_attempts)} attempts → ${n0(t.finder_found)} found · ${n0(t.verifications)} verifications → ${n0(t.valid)} valid, ${n0(t.risky)} risky, ${n0(t.invalid)} invalid · ${esc(t.credits ?? 0)} credits ·
    valid → draft ${n0(t.valid_to_draft)} → sent ${n0(t.draft_to_send)} → replied ${n0(t.send_to_reply)} → meeting ${n0(t.reply_to_meeting)}</div>
    <div class="small faint">Monthly at this pace ≈ ${n0(m.at_last_7_days)} credits${h.reset_date ? ` · allowance resets ${esc(shortDay(h.reset_date))}` : ''}.</div>`;
}
// Channel health on every Director (email first): coverage = qualified with a verified email route / qualified with a decision maker.
// The funnel (decision makers -> emails found -> valid verified -> in review) names the bottleneck; LinkedIn volume is never progress.
function channelRow(c) {
  if (!c) return '';
  const bn = c.bottleneck;
  const chip = (n, l, cls = '') => `<span class="ch-chip ${cls}"><b>${n0(n)}</b> ${l}</span>`;
  return `<div class="dc-channel"><div class="dc-cov ${bn ? 'warn-text' : ''}">Email coverage <b>${c.coverage_pct == null ? '—' : `${c.coverage_pct}%`}</b> <span class="faint">· ${n0(c.verified)} of ${n0(c.with_dm)} with a decision maker</span>${bn ? ` ${pill(bn === 'VERIFICATION' ? 'Verification bottleneck' : 'Contact bottleneck', 'warn')}` : ''}</div>
    <div class="dc-funnel small faint">${n0(c.with_dm)} decision makers → ${n0(c.emails_found)} emails found → ${n0(c.verified)} valid verified → ${n0(c.needs_review_email)} in review · <b>${n0(c.email_ready)}</b> email-ready</div>
    <div class="ch-chips">${chip(c.verified, 'verified email', 'ok')}${c.verified_general ? chip(c.verified_general, 'verified general inbox', 'ok') : ''}${chip(c.needs_verification, 'needs verification')}${c.finder_pending ? chip(c.finder_pending, 'Email Finder lookup pending') : ''}${chip(c.email_gap, 'email gap')}${chip(c.linkedin_fallback, 'LinkedIn fallback')}${chip(c.instagram_fallback, 'Instagram fallback')}${chip(c.needs_review, 'needs review')}</div></div>`;
}
// Acquisition health (Adam, 11 Oct): EMAIL READY is the cold-acquisition KPI. LinkedIn and Instagram are fallbacks, counted apart;
// warm and existing relationships are counted once, outside the cold routes. Agents page only, never Today.
function acquisitionStrip() {
  const a = state.exec?.queue?.acquisition; if (!a) return '';
  const r = a.reserve || {}; const t = r.target || [100, 150]; const p = a.pipeline || {};
  const tile = (n, l, cls = '') => `<div class="tile ${cls}"><div class="n">${n0(n)}</div><div class="l">${l}</div></div>`;
  return `<section class="panel mt8 acq-strip"><header><h3>Acquisition health</h3><span class="small ${r.status === 'LOW' ? 'bad-text' : 'faint'}">Email ready ${n0(a.email_ready)} · reserve target ${esc(t[0])}–${esc(t[1])}${r.status === 'LOW' ? ' · reserve low' : ''}</span></header><div class="body">
    <div class="tiles">${tile(a.valid_verified_email_ready, 'Valid verified email ready', 'primary')}${tile(a.verified_general_email_ready, 'Verified general inbox ready', 'primary')}
      ${tile(a.linkedin_fallback, 'LinkedIn fallback')}${tile(a.instagram_fallback, 'Instagram fallback')}${tile(a.warm, 'Warm')}${tile(a.existing_relationship, 'Existing relationship')}</div>
    <div class="small faint mt6">On the way to email: ${n0(p.needs_verification)} waiting for verification · ${n0(p.research_pending)} email research to finish · ${n0(p.finder_pending)} Email Finder lookups · ${n0(p.no_person)} without a decision maker.</div></div></section>`;
}

// ---------------------------------------------------------------- TODAY: only what needs Adam
function todayItems(d) {
  const desk = state.desk || {}; const now = new Date(); const end = new Date(`${todayKey()}T23:59:59+03:00`);
  // Replies, plus Adam's own reply / review tasks that have no inbound email behind them (a personal LinkedIn follow-up).
  const field = (desc, label) => (String(desc || '').match(new RegExp(`^${label}:\\s*(.+)$`, 'mi')) || [])[1] || '';
  const replies = [...repliesForAdam(d), ...openTasks(d).filter((t) => ['REPLY_ACTION', 'HUMAN_REVIEW'].includes(t.task_type) && !repliesForAdam(d).some((r) => r.task_id === t.id))
    .map((t) => { const act = field(t.description, 'EXACT ACTION'); return { task_only: true, task_id: t.id, opportunity_id: t.opportunity_id, due_at: t.due_at, title: t.title,
      company_name: [field(t.description, 'CONTACT').split(',')[0], t.company_name].filter(Boolean).join(' · ') || t.title,
      summary: act.replace(/\s*(to\s+)?https?:\/\/\S+/g, '').trim() || t.title, url: (act.match(/https?:\/\/\S+/) || [])[0] }; })];
  const meetings = [...(state.ov?.actions || []).filter((a) => a.kind === 'MEETING'),
    ...d.opportunities.filter((o) => o.status === 'CALL_REQUIRED' && !(state.ov?.actions || []).some((a) => a.kind === 'MEETING' && a.opportunity_id === o.id))
      .map((o) => ({ kind: 'CALL', company: o.company_name, person: o.contact_name, opportunity_id: o.id, next_action: o.next_action }))];
  const gmail = (desk.approved || []).filter((x) => x.gmail_confirmed);
  const failed = (desk.approved || []).filter((x) => x.status === 'FAILED' || (x.status === 'PROCESSING' && x.can_retry));
  const followups = (desk.followups || []).filter((f) => f.due_at && new Date(f.due_at) <= end);
  const proposals = d.opportunities.filter((o) => ['PROPOSAL', 'NEGOTIATION'].includes(o.status));
  const issues = state.ops?.issues || [];
  const review = desk.counts?.needs_review?.total || 0;
  const count = replies.length + meetings.length + gmail.length + failed.length + proposals.length + issues.length + (followups.filter((f) => new Date(f.due_at) < now).length ? 1 : 0) + (review ? 1 : 0);
  return { replies, meetings, gmail, failed, followups, proposals, issues, review, count };
}
// ================================================================ DASHBOARD (Adam, 16 Oct): run the company from one screen.
// What needs Adam, what the agents are doing, what could make money, who replied, what is developing, where it is stuck.
// Every figure is a live read: hq_ceo_dashboard() (funnel, pipeline, top opportunities, money), the desk, the Directors.
const PROJECT_LABEL = { BRAND_SHOOT: 'Brand shoot', FASHION_CAMPAIGN: 'Fashion campaign', JEWELLERY_CAMPAIGN: 'Jewellery campaign', CREATOR_TRIP: 'Creator trip',
  PRESS_TRIP: 'Press trip', BRAND_ACTIVATION: 'Brand activation', PRODUCT_LAUNCH: 'Product launch', AUTOMOTIVE_SHOOT: 'Automotive shoot', CONTENT_PRODUCTION: 'Content production',
  DESTINATION_WEDDING: 'Destination wedding', WEDDING_GUEST_CONCIERGE: 'Wedding guest concierge', MEDIA_PRODUCTION: 'Media / podcast production', NOYA_PRIVATE_AGENCY: 'NOYA Private agency',
  TRAVEL_PARTNER: 'Travel partner', HOTEL_CONTENT_PARTNERSHIP: 'Hotel content partnership', PREFERRED_STAY: 'Preferred stay partnership', WHITE_LABEL_CONCIERGE: 'White-label concierge',
  CORPORATE_RETREAT: 'Corporate retreat', CORPORATE_CONCIERGE: 'Corporate concierge', FOUNDER_RETREAT: 'Founder retreat', PRIVATE_NETWORK: 'Private network', EGYPT_EVENT: 'Egypt event', PARTNERSHIP: 'Partnership' };
const STAGE_NAME = { PROSPECT: 'Prospect', OUTREACH: 'Outreach', REPLIED: 'Replied', QUALIFIED_CONVERSATION: 'Qualified conversation', MEETING: 'Meeting', CONCEPT_BRIEF: 'Concept / brief',
  PROPOSAL: 'Proposal', NEGOTIATION: 'Negotiation', WON: 'Won', PROJECT_ACTIVE: 'Project active', COMPLETED: 'Completed', LOST_PARKED: 'Lost / parked' };
const REL_NAME = { CLIENT: 'Client', PARTNER_ACTIVE: 'Active partner', PROPOSAL: 'Proposal stage', MEETING_BOOKED: 'Meeting stage', ACTIVE_CONVERSATION: 'In conversation',
  DECLINED_RECENTLY: 'Declined recently', CONTACTED_RECENTLY: 'Contacted, no reply yet', COLD: 'Not contacted yet', THEY_WROTE_LAST: 'They wrote last', WAITING_FOR_THEM: 'Waiting for them',
  FOLLOW_UP: 'Follow up', RECONNECT: 'Reconnect', LONG_TERM: 'Long term', TWO_WAY: 'Two-way email', UNKNOWN: '—' };
const projectName = (k) => PROJECT_LABEL[k] || (k ? sentence(String(k).replace(/_/g, ' ')) : '—');
const dirName = (k) => (!k ? '—' : (state.directors?.members || []).find((x) => x.key === k)?.name || DIRECTOR_LABEL[k] || sentence(String(k)));
const coInfo = (id) => (id && state.ceo?.companies?.[id]) || [];
const dirByName = (name) => { const c = (state.dir?.companies || []).find((x) => x.name === name); return c ? coInfo(c.id)[0] : null; };
const moneyOf = (list) => (Array.isArray(list) && list.length ? list.map((m) => money(m.amount, m.currency)).join(' + ') : null);
const ageOf = (d) => { if (!d) return ''; const n = Math.floor(daysAgo(d)); return n < 1 ? 'today' : n === 1 ? '1 day' : `${n} days`; };
const btnLink = (url, label, primary = true) => `<a class="btn small ${primary ? 'primary' : ''}" href="${esc(url)}" target="_blank" rel="noopener noreferrer">${esc(label)}</a>`;

// Verified-email drafts that failed the quality check wait under Held for Adam's edit: they count as emails needing review.
const qaHeld = () => (state.desk?.held || []).filter((x) => x.channel === 'EMAIL' && x.status === 'OPEN' && /quality check/i.test(x.reason || ''));
function dashStrip(d) {
  const C = state.cmd; const K = C?.kpis || {}; const H = C?.revenue?.historical || {};
  const rows = needsRows(d); const rev = C ? cashOf(K.revenue) : null;
  const gap = Number(H.stated_amount || 0) - Number(H.reconciled || 0);
  const send = C ? Number(K.gmail_drafts_to_send || 0) + Number(K.studio_drafts_to_send || 0) : null;
  const k = (n, l, attrs, sub = '') => `<button class="kpi" ${attrs}><span class="kn">${n}</span><span class="kl">${l}</span>${sub ? `<span class="ks">${sub}</span>` : ''}</button>`;
  return `<section class="kpis" aria-label="Key numbers">
    ${k(C ? esc(rev || '£0') : '—', 'Actual revenue', 'data-go="finance"', C ? (gap > 0 ? `${esc(cash(gap, H.currency))} historical to reconcile` : rev ? 'recorded with evidence' : 'none recorded') : '')}
    ${k(C ? n0(K.active_projects) : '—', 'Active projects', 'data-go="ops"')}
    ${k(C ? n0(K.open_proposals) : '—', 'Open proposals', 'data-scroll="pipeline"')}
    ${k(C ? n0(K.meetings_30) : '—', 'Meetings', 'data-scroll="pipeline"', 'booked or held · 30 days')}
    ${k(C ? n0(K.positive_30) : '—', 'Positive replies', 'data-scroll="pipeline"', 'companies · 30 days')}
    ${k(send == null ? '—' : n0(send), 'Emails to send', 'data-go="desk" data-desk-tab="APPROVED"', C ? `${n0(K.gmail_drafts_to_send)} Gmail · ${n0(K.studio_drafts_to_send)} Studio${Number(K.studio_drafts_later) ? ` · ${n0(K.studio_drafts_later)} later` : ''}` : '')}
    ${k(n0(rows.length), 'Actions needing you', 'data-scroll="needs"')}</section>`;
}

// WHAT NEEDS YOU TODAY (Adam, 19 Oct): five lists every morning: replies to answer, meetings to schedule, follow-ups due, the
// five best new outreach items, Studio documents ready. Clients and proposals sit on top only when they exist. One button each.
const NEED_GROUPS = [['clients', 'Clients and proposals'], ['replies', 'Replies to answer'], ['meetings', 'Meetings to schedule'], ['followups', 'Follow-ups due'],
  ['outreach', 'Top 5 new outreach to approve'], ['studio', 'Studio documents ready']];
const NEED_EMPTY = { replies: 'No reply waiting.', meetings: 'No meeting to schedule.', followups: 'No follow-up due today.',
  outreach: 'Nothing strong enough today. Fewer is fine.', studio: 'No Studio document waiting.' };
const studioReady = () => (state.desk?.studio_ready || []).filter((s) => !s.hold_reason);
function needsRows(d) {
  const t = todayItems(d); const desk = state.desk || {}; const rows = [];
  const assist = desk.meeting_assist || []; const assisted = new Set(assist.map((m) => m.opportunity_id).filter(Boolean));
  t.issues.forEach((i) => rows.push({ g: 'clients', r: 1, who: i.title, co: '', dir: null, why: 'Client delivery issue', next: 'Resolve with the client or supplier', when: i.due_at,
    cta: '<button class="btn small primary" data-go="ops">Operations</button>' }));
  t.proposals.forEach((o) => rows.push({ g: 'clients', r: 2, who: o.company_name, co: '', dir: dirByName(o.company_name), why: `${S(o.status)}: money is on the table`, next: o.next_action || 'Move the proposal forward',
    when: o.updated_at, cta: `<button class="btn small primary" data-open="opp" data-id="${o.id}">Open</button>` }));
  t.replies.forEach((x) => {
    const own = x.task_only; const meeting = x.classification === 'MEETING_REQUEST';
    // A LinkedIn reply is listed once, from the LinkedIn agent, with its suggested response; a meeting with Meeting Assist open, once.
    if (own && /^LINKEDIN REPLY/.test(x.title || '')) return;
    if (meeting && x.opportunity_id && assisted.has(x.opportunity_id)) return;
    rows.push({ g: own ? 'followups' : meeting ? 'meetings' : 'replies', r: meeting ? 1 : own ? 3 : 2, who: own ? x.company_name : (x.company_name || x.from), co: '', dir: dirByName(String(x.company_name || '').split(' · ').pop()),
      why: own ? 'Your own follow-up on a live relationship' : meeting ? 'They asked for a meeting: the closest thing to a project' : `${REPLY_GROUP[x.classification] || 'A'} reply waiting for you`,
      next: plainText(x.summary || x.subject || 'Reply'), when: own ? x.due_at : x.received_at, overdue: own && x.due_at && new Date(x.due_at) < new Date(),
      cta: own ? (x.url ? btnLink(x.url, 'Open LinkedIn') : x.opportunity_id ? `<button class="btn small primary" data-open="opp" data-id="${x.opportunity_id}">Open</button>` : '')
        : x.thread_id ? btnLink(`${GMAIL_THREAD_URL}${x.thread_id}`, 'Reply in Gmail') : x.opportunity_id ? `<button class="btn small primary" data-open="opp" data-id="${x.opportunity_id}">Open</button>` : '' });
  });
  (desk.linkedin || []).filter((a) => a.state === 'REPLIED' && a.reply_class !== 'MEETING_INTENT').forEach((a) => rows.push({ g: 'replies', r: 1, who: a.person || a.company, co: a.person ? a.company : '',
    dir: a.director, why: `LinkedIn reply (${liClass(a.reply_class).toLowerCase()}): a response is suggested`, next: plainText(a.reply_text || '').slice(0, 160), when: a.replied_at,
    cta: liCopyOpen(a.response_draft, a.linkedin, 'Copy response & open LinkedIn') || '<button class="btn small primary" data-go="desk" data-desk-tab="LINKEDIN">Open</button>' }));
  t.meetings.filter((m) => !(m.opportunity_id && assisted.has(m.opportunity_id))).forEach((m) => rows.push({ g: 'meetings', r: 1, who: m.person || m.company, co: m.person ? m.company : '', dir: dirByName(m.company),
    why: m.kind === 'CALL' ? 'They asked for a call: a project can start here' : 'They asked for a meeting', next: m.kind === 'CALL' ? (m.next_action || 'Book the call, then record it') : 'Agree a time, then record the outcome',
    when: null, cta: m.opportunity_id ? `<button class="btn small primary" data-modal="meeting" data-opp="${m.opportunity_id}" data-task="${m.task_id || ''}">Record meeting</button>` : '' }));
  assist.forEach((m) => rows.push({ g: 'meetings', r: 1, who: m.person || m.company, co: m.person ? m.company : '', dir: dirByName(m.company),
    why: m.state === 'SLOTS_PROPOSED' ? 'Two times offered from your calendar: confirm when they pick one' : 'They want to talk: two free times from your calendar go into the reply',
    next: (m.slots || []).length ? `Offered ${slotText(m.slots)}` : 'Times are checked against your calendar at the next daily check', when: m.created_at,
    cta: `<button class="btn small primary" data-modal="meet-confirm" data-id="${m.task_id}">Confirm meeting</button>` }));
  t.followups.slice(0, 4).forEach((f) => rows.push({ g: 'followups', r: f.overdue ? 3 : 4, who: f.person || f.company, co: f.person ? f.company : '', dir: f.director,
    why: 'No answer yet: one short follow-up keeps it alive', next: `Follow-up ${f.step} by ${CH_LABEL[f.channel] || f.channel}`, when: f.due_at, overdue: f.overdue,
    cta: f.thread_id ? btnLink(`${GMAIL_THREAD_URL}${f.thread_id}`, 'Open thread', false) + `<button class="btn small" data-modal="task-done" data-id="${f.task_id}" data-title="${esc(`Follow-up ${f.step} — ${f.person || f.company || ''}`)}">Done</button>`
      : `<button class="btn small" data-modal="task-done" data-id="${f.task_id}" data-title="${esc(`Follow-up ${f.step} — ${f.person || f.company || ''}`)}">Followed up</button>` }));
  // New outreach: what is approved and only needs Send, then the five strongest new items (never the whole queue).
  t.gmail.forEach((x) => rows.push({ g: 'outreach', sub: 'send', r: 1, who: x.person || x.to_email, co: x.company, dir: x.director, why: 'Approved and waiting in Gmail: only your Send is missing',
    next: `Send "${x.subject || 'the draft'}"`, when: x.approved_at, cta: btnLink(x.gmail_url, 'Open in Gmail') }));
  t.failed.forEach((x) => rows.push({ g: 'outreach', sub: 'send', r: 1, who: x.person || x.to_email, co: x.company, dir: x.director, why: 'The Gmail draft could not be created', next: 'Retry from the desk', when: x.approved_at,
    cta: '<button class="btn small" data-go="desk" data-desk-tab="APPROVED">Retry</button>' }));
  qaHeld().forEach((x) => rows.push({ g: 'outreach', sub: 'edit', r: 2, who: x.person || x.company, co: x.person ? x.company : '', dir: x.director, why: 'Verified email; the draft failed the quality check',
    next: 'Edit the draft (Approve then creates an unsent Gmail draft), or reject', when: x.created_at,
    cta: `<button class="btn small primary" data-go="desk" data-desk-tab="HELD" data-desk-dir="${x.director || ''}">Edit</button>` }));
  const top = desk.top5 || [];
  top.forEach((p, i) => {
    const x = deskItem(p.ref); if (!x) return; const a = x.channel === 'LINKEDIN' ? liOf(x) : null;
    rows.push({ g: 'outreach', sub: 'top', r: 3, who: x.person || x.company, co: x.person ? x.company : '', dir: x.director, why: `${i + 1} of ${top.length} · ${p.why}`,
      next: x.channel === 'EMAIL' ? 'Approve creates an unsent Gmail draft; nothing is sent' : 'Copy, open LinkedIn and send it yourself, then Mark sent', when: x.created_at,
      cta: a ? `${liCopyOpen(a.message, a.linkedin, 'Copy & open LinkedIn')}<button class="btn small" data-modal="li-sent" data-id="${a.id}">Mark sent</button>`
        : `<button class="btn small primary" data-go="desk" data-desk-tab="TOP5">Review</button>` });
  });
  studioReady().slice(0, 3).forEach((s) => rows.push({ g: 'studio', r: 4, who: s.title || 'Studio document', co: s.company || '', dir: null,
    why: s.status === 'APPROVED' ? 'Approved: ready to go with its email' : `Prepared by the Studio${s.level ? ` (level ${s.level})` : ''}: ready for your review`,
    next: s.status === 'APPROVED' ? 'Attach it to the email it belongs to' : 'Review, then approve or ask for changes', when: s.created_at,
    cta: '<button class="btn small primary" data-go="studio">Open Studio</button>' }));
  rows.sort((a, b) => a.r - b.r);
  return rows;
}
function dashActions(d) {
  const t = todayItems(d); const rows = needsRows(d); const desk = state.desk || {};
  const overdue = t.followups.filter((f) => new Date(f.due_at) < new Date()); const waiting = desk.counts?.needs_review?.total || 0; const sr = studioReady().length;
  const extra = { followups: t.followups.length > 4 ? `<button class="btn small ghost" data-go="desk" data-desk-tab="FOLLOWUPS">All ${t.followups.length} follow-ups${overdue.length ? ` · ${overdue.length} overdue` : ''}</button>` : '',
    outreach: waiting > (desk.top5 || []).length ? `<button class="btn small ghost" data-go="desk" data-desk-tab="NEEDS_REVIEW">${n0(waiting)} waiting in Outreach</button>` : '',
    studio: sr > 3 ? `<button class="btn small ghost" data-go="studio">All ${sr} in Studio</button>` : '' };
  const act = (x) => `<div class="act">
      <div class="act-main"><div class="act-who">${esc(x.who || '')}${x.co ? ` <span class="faint">· ${esc(x.co)}</span>` : ''}</div>
        <div class="act-why">${esc(x.why)}</div><div class="act-next">${esc(x.next || '')}</div></div>
      <div class="act-meta"><span>${x.dir ? esc(dirName(x.dir)) : ''}</span><span class="${x.overdue ? 'bad-text' : 'faint'}">${x.when ? `${x.overdue ? 'overdue · ' : ''}${esc(ageOf(x.when))}` : ''}</span></div>
      <div class="act-cta">${x.cta || ''}</div></div>`;
  // New outreach keeps the five as five: what is already approved (only Send missing) and drafts to edit are labelled apart.
  const SUBS = [['send', 'Approved: only your Send is missing'], ['top', "Today's best five"], ['edit', 'Drafts to edit']];
  const list = (g, l) => (g !== 'outreach' || !l.some((x) => x.sub !== 'top') ? l.map(act).join('')
    : SUBS.map(([k, sl]) => { const m = l.filter((x) => x.sub === k); return m.length ? `<div class="ngrp-sub">${esc(sl)} · ${m.length}</div>${m.map(act).join('')}` : ''; }).join(''));
  const body = NEED_GROUPS.map(([g, label]) => {
    const l = rows.filter((x) => x.g === g); if (!l.length && g === 'clients') return '';
    const n = g === 'outreach' ? l.filter((x) => x.sub === 'top').length : l.length;
    return `<div class="ngrp" data-need="${g}"><div class="ngrp-h"><h3>${esc(label)}${n ? ` <span class="n">${n}</span>` : ''}</h3>${extra[g] || ''}</div>
      ${list(g, l) || `<div class="ngrp-none">${esc(NEED_EMPTY[g])}</div>`}</div>`;
  }).join('');
  return `<section class="dsec" id="needs"><header><h2>What needs you today</h2><span class="faint small">${rows.length ? plural(rows.length, 'action', 'actions') : 'nothing waiting'}</span></header>${body}</section>`;
}

// HQ ADVISOR: 3-5 observations, each situation -> meaning -> recommended action. A Chief of Staff, not an analytics bot.
function dashAdvisor() {
  const A = state.advisor;
  if (!A) return state.errors.advisor ? `<section class="dsec"><header><h2>HQ Advisor</h2></header>${unavailable('advisor')}</section>` : '<section class="dsec advisor"><p class="muted small">HQ Advisor is reading the Directors…</p></section>';
  const obs = (A.observations || []).slice(0, 5).map((o) => `<li class="adv-obs ${o.kind === 'BOTTLENECK' || o.kind === 'STOP' ? 'bottleneck' : o.kind === 'ATTENTION' || o.kind === 'CORRECTION' ? 'attention' : ''}">
      ${o.title ? `<div class="adv-k">${esc(o.title)}</div>` : ''}
      <div class="adv-s"><span class="adv-l">Situation</span>${esc(o.situation)}</div><div class="adv-m"><span class="adv-l">Meaning</span>${esc(o.meaning)}</div>
      <div class="adv-a"><span class="adv-l">Recommended action</span>${esc(o.action)}</div></li>`).join('');
  return `<section class="dsec advisor"><header><h2>HQ Advisor</h2><span class="faint small">Five recommendations a day</span></header>${obs ? `<ol class="adv-list">${obs}</ol>` : '<p class="muted small">Nothing to flag: the Directors are on plan.</p>'}${dashApprovals()}</section>`;
}

// TOP COMMERCIAL OPPORTUNITIES: potential projects, not prospects. No invented deal values.
function oppCard(o) {
  const ct = o.contact || {};
  return `<article class="ocard">
    <div class="oc-top"><div><div class="oc-co">${o.company_id ? `<a class="clickable" data-open="company" data-id="${o.company_id}">${esc(o.company)}</a>` : esc(o.company)}</div>
      <div class="oc-proj">${esc(projectName(o.project))}${o.director ? ` · <span class="faint">${esc(dirName(o.director))}</span>` : ''}</div></div>
      <span class="oc-stage ${o.live ? 'live' : ''}">${esc(STAGE_NAME[o.stage] || o.stage || '')}</span></div>
    <dl class="oc-dl">
      <dt>Why now</dt><dd>${esc(plainText(o.why_now || '—'))}</dd>
      <dt>Relationship</dt><dd>${esc(o.relationship === 'COLD' && o.last_at ? 'Earlier email history, no current sequence' : REL_NAME[o.relationship] || sentence(String(o.relationship || '').replace(/_/g, ' ')))}${o.last_at ? ` · last ${esc(shortDay(o.last_at))}` : ''}</dd>
      <dt>Next move</dt><dd><b>${esc(plainText(o.next_move || '—'))}</b></dd>
      <dt>Evidence</dt><dd class="faint">${esc(plainText(o.evidence || '—'))}</dd>
      <dt>Strategic value</dt><dd>${esc(o.strategic_value || '—')}</dd>
      ${ct.name ? `<dt>Contact</dt><dd>${esc(ct.name)}${ct.role ? `, ${esc(ct.role)}` : ''}${ct.email ? ` · ${esc(ct.email)}` : ''} ${ct.email_status === 'VERIFIED' ? '<span class="ok-text">verified</span>' : ''}</dd>` : ''}
    </dl></article>`;
}
function dashOpportunities() {
  const C = state.ceo; if (!C) return `<section class="dsec">${waitFor('ceo', 'opportunities')}</section>`;
  const list = (C.top_opportunities || []).slice(0, 10);
  return `<section class="dsec"><header><h2>Top commercial opportunities</h2><span class="faint small">Live conversations first, then the strongest verified-email prospects. No deal values are estimated.</span></header>
    <div class="ogrid">${list.map(oppCard).join('') || '<div class="empty">No live opportunity yet.</div>'}</div></section>`;
}

// PROJECT CONVERSION FUNNEL: is outreach turning into business? This week and the last 30 days; where it is stuck.
function dashFunnel() {
  const C = state.ceo; if (!C) return '';
  const F = C.funnel || {}; const w = F.week || {}; const m = F.d30 || {};
  const steps = [['New outreach', (x) => n0((x.sent_email || 0) + (x.sent_linkedin || 0) + (x.sent_instagram || 0))], ['Follow-ups', (x) => n0(x.follow_ups)], ['Replied', (x) => n0(x.replies)], ['Positive', (x) => n0(x.positive)],
    ['Meetings', (x) => n0(x.meetings)], ['Briefs / concepts', (x) => n0(x.concepts)], ['Proposals', (x) => n0(x.proposals)], ['Active projects', () => n0(F.active_projects)],
    ['Won', (x) => n0(x.won)], ['Revenue', (x) => esc(moneyOf(x.revenue) || '£0')]];
  const row = (label, x) => `<tr><th>${label}</th>${steps.map(([, f]) => `<td>${f(x)}</td>`).join('')}</tr>`;
  const bd = F.by_director_30 || {}; const active = Object.entries(bd).filter(([, v]) => v.sent || v.replies || v.meetings || v.proposals || v.wins);
  return `<section class="dsec"><header><h2>From outreach to business</h2></header>
    <div class="tbl-wrap"><table class="funnel"><thead><tr><th></th>${steps.map(([l]) => `<th>${l}</th>`).join('')}</tr></thead>
      <tbody>${row('This week', w)}${row('Last 30 days', m)}</tbody></table></div>
    ${active.length ? `<details class="mt6"><summary class="small">By Director · last 30 days</summary><div class="tbl-wrap"><table class="stack"><thead><tr><th>Director</th><th class="num">Sent</th><th class="num">Replies</th><th class="num">Positive</th><th class="num">Meetings</th><th class="num">Proposals</th><th class="num">Wins</th></tr></thead><tbody>
      ${active.map(([k, v]) => `<tr><td>${esc(dirName(k))}</td><td class="num" data-l="Sent">${n0(v.sent)}</td><td class="num" data-l="Replies">${n0(v.replies)}</td><td class="num" data-l="Positive">${n0(v.positive)}</td><td class="num" data-l="Meetings">${n0(v.meetings)}</td><td class="num" data-l="Proposals">${n0(v.proposals)}</td><td class="num" data-l="Wins">${n0(v.wins)}</td></tr>`).join('')}</tbody></table></div></details>` : ''}
    <p class="src">${esc(F.method || '')}</p></section>`;
}

// AI WORKFORCE PULSE: one executive row per Director. "Working" only while a scheduled run is actually in progress.
const statusLabel = (m) => {
  const [l, c] = DSTATUS[m.status] || [m.status, ''];
  const next = m.next_run ? new Date(m.next_run).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Cairo' }) : '';
  return `<span class="st ${c}">${esc(m.status === 'SCHEDULED' && next ? `${l} — ${next}` : l)}</span>`;
};
const outputLine = (m) => { const t = m.today || {}; const parts = [[t.companies_found, 'qualified'], [t.people_confirmed, 'people'], [t.verified_emails, 'verified emails'], [t.outreach_drafts, 'drafts'], [t.replies, 'replies']].filter(([n]) => Number(n) > 0);
  return parts.length ? parts.map(([n, l]) => `${n0(n)} ${l}`).join(' · ') : 'No new output today'; };
// The mission in one line: its first sentence (the full mission sits on the Director's page).
const missionLine = (m) => {
  const t = plainText(m.mission || m.next_focus || ''); const s = (t.match(/^.+?\.(?=\s|$)/) || [t])[0];
  if (s.length <= 160) return s; const c = s.split(':')[0]; return c.length >= 30 && c.length < s.length ? c : `${s.slice(0, 157)}…`;
};
function dashPulse() {
  const D = state.directors; if (!D) { loadV3('directors', 'hq_directors'); return `<section class="dsec"><header><h2>AI workforce</h2></header>${waitFor('directors', 'the workforce')}</section>`; }
  const rows = D.members.filter((m) => m.role !== 'SUPPORT');
  return `<section class="dsec"><header><h2>AI workforce</h2><button class="btn small ghost" data-go="agents">All agents</button></header>
    <div class="tbl-wrap"><table class="pulse stack"><thead><tr><th>Director</th><th>Status</th><th>Current mission</th><th>Today's output</th><th>Last 7 days</th><th>Blocker</th><th>Result / opportunity</th></tr></thead><tbody>
    ${rows.map((m) => { const top = state.ceo?.directors?.[m.key]?.top; const blk = (m.blockers || [])[0];
      return `<tr class="clickable" data-director="${m.key}"><td><b>${esc(m.name)}</b></td><td data-l="Status">${statusLabel(m)}</td>
        <td data-l="Mission" class="small">${esc(missionLine(m))}</td><td data-l="Today" class="small">${esc(outputLine(m))}</td>
        <td data-l="7 days" class="small">${(() => { const w = scoreOf(m.key)?.d7; return w ? `${n0(w.sent)} sent · ${n0(w.replies)} replies · ${n0(w.meetings)} meetings${Number(w.briefs) ? ` · ${n0(w.briefs)} briefs` : ''}${Number(w.wins) ? ` · ${n0(w.wins)} wins` : ''}` : '<span class="faint">—</span>'; })()}${ordersOf(m.key).length ? `<div class="faint">${plural(ordersOf(m.key).length, 'work order', 'work orders')} · ${esc((WO_STATUS[ordersOf(m.key)[0].status] || [''])[0].toLowerCase())}</div>` : ''}</td>
        <td data-l="Blocker" class="small ${blk?.hard ? 'bad-text' : 'warn-text'}">${blk ? esc(blk.text) : '<span class="faint">—</span>'}</td>
        <td data-l="Result" class="small">${top ? `${esc(top.company)} · ${esc(projectName(top.project))}${top.stage ? ` <span class="faint">(${esc((STAGE_NAME[top.stage] || '').toLowerCase())})</span>` : ''}` : '<span class="faint">No opportunity yet</span>'}</td></tr>`; }).join('')}</tbody></table></div></section>`;
}

// WEEKLY CEO REVIEW: one concise block. Money only as recorded.
function dashWeekly() {
  const C = state.ceo; if (!C) return '';
  const w = C.funnel?.week || {}; const A = state.advisor || {}; const M = C.money || {};
  const tl = (n, l) => `<div class="wk-t"><div class="n">${n}</div><div class="l">${l}</div></div>`;
  const bd = Object.entries(C.funnel?.by_director_week || {}).filter(([, v]) => v.sent || v.replies || v.meetings);
  const bott = (A.observations || []).find((o) => o.kind === 'BOTTLENECK');
  const att = (A.observations || []).find((o) => o.kind === 'ATTENTION');
  const blocked = (state.directors?.members || []).filter((m) => m.role === 'DIRECTOR' && (m.status === 'BLOCKED' || m.status === 'ERROR'));
  const quiet = (state.directors?.members || []).filter((m) => m.role === 'DIRECTOR' && m.key !== 'GROWTH' && !Number(C.funnel?.by_director_week?.[m.key]?.sent) && !Number(m.d3?.companies_found));
  const stuck = (C.pipeline || []).filter((s) => s.stuck > 0).sort((a, b) => b.stuck - a.stuck)[0];
  const rec = (A.observations || [])[0];
  const mline = [['Revenue', M.revenue], ['Fees', M.fees], ['Commission', M.commission], ['Supplier cost', M.supplier_cost], ['Gross profit', M.gross_profit], ['Receivables', M.receivables]]
    .map(([l, v]) => `<span><span class="faint">${l}</span> ${esc(moneyOf(v) || 'Not recorded')}</span>`).join('');
  return `<section class="dsec wk"><header><h2>Weekly CEO review</h2><span class="faint small">last 7 days</span></header>
    <div class="wk-tiles">${tl(n0(w.sent_email), 'Emails sent')}${tl(n0(w.sent_linkedin), 'LinkedIn fallbacks sent')}${tl(n0(w.replies), 'Replies')}${tl(n0(w.positive), 'Positive replies')}
      ${tl(n0(w.meetings), 'Meetings')}${tl(n0(w.concepts), 'Briefs / concepts')}${tl(n0(w.proposals), 'Proposals')}${tl(n0(w.won), 'Projects won')}${tl(esc(moneyOf(w.revenue) || '£0'), 'Revenue')}</div>
    ${bd.length ? `<div class="small mt6">${bd.map(([k, v]) => `<span class="wk-d"><b>${esc(dirName(k))}</b> ${n0(v.sent)} sent · ${n0(v.replies)} replies · ${n0(v.meetings)} meetings</span>`).join('')}</div>` : '<p class="small faint mt6">No first messages sent this week.</p>'}
    <dl class="wk-dl">
      <dt>Top 5 opportunities</dt><dd>${(C.top_opportunities || []).slice(0, 5).map((o) => `${esc(o.company)} <span class="faint">(${esc(projectName(o.project).toLowerCase())})</span>`).join(' · ') || '—'}</dd>
      <dt>Biggest bottleneck</dt><dd>${bott ? esc(bott.situation) : stuck ? `${stuck.stuck} ${esc((STAGE_NAME[stuck.stage] || '').toLowerCase())} conversations with no next step` : '—'}</dd>
      <dt>Director needing attention</dt><dd>${blocked.length ? esc(blocked.map((m) => `${m.name}: ${(m.blockers || [])[0]?.text || m.status_text}`).join(' · ')) : att ? esc(att.situation) : quiet.length ? esc(`${quiet.map((m) => m.name).join(', ')}: no outreach sent and no new qualified companies`) : 'None'}</dd>
      <dt>HQ Advisor recommendation</dt><dd>${rec ? esc(rec.action) : '—'}</dd>
      <dt>Money</dt><dd class="mline">${mline}</dd></dl></section>`;
}

function viewDashboard(d) {
  const day = new Date().toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Africa/Cairo' });
  return `${head(state.advisor?.greeting || 'Dashboard', esc([day, asOf(state.ceo)].filter(Boolean).join(' · ')))}
    ${dashStrip(d)}${dashActions(d)}${dashAdvisor()}${dashMission()}${dashPipeline()}${dashFunnel()}${dashOpportunities()}${dashPulse()}${dashWeekly()}`;
}

// ---------------------------------------------------------------- COMMAND CENTRE (Adam, 18 Oct: professional operating mode)
// One read, hq_command (snapshot 'command'): the seven top numbers, the 15-stage funnel with each live opportunity's owner, next
// action, date and blocker, revenue and its reconciliation, Director scorecards, CEO work orders and the recommendations waiting
// for Adam. Nothing is estimated: a number exists only when a record behind it exists.
const CUR_SIGN = { GBP: '£', USD: '$', EUR: '€' };
const cash = (amount, currency) => (amount == null ? '—' : `${CUR_SIGN[currency] || `${currency || ''} `}${Number(amount).toLocaleString('en-GB', { maximumFractionDigits: 0 })}`);
const cashOf = (list) => (Array.isArray(list) && list.length ? list.map((m) => cash(m.amount, m.currency)).join(' + ') : null);
const WO_STATUS = { QUEUED: ['Queued', ''], WORKING: ['Working', 'ok'], WAITING: ['Waiting for you', 'warn'], COMPLETE: ['Complete', 'ok'], BLOCKED: ['Blocked', 'bad'], CANCELLED: ['Cancelled', ''] };
const WO_METRIC = [['EMAILS_SENT', 'Emails sent'], ['QUALIFIED_TARGETS', 'New qualified targets'], ['EMAIL_READY', 'New email-ready contacts'], ['REPLIES', 'Replies'], ['MEETINGS', 'Meetings'], ['PROPOSALS', 'Proposals'], ['WINS', 'Wins']];
const MISSING_LABEL = { NO_OPPORTUNITY: 'no opportunity record', NO_NEXT_ACTION: 'no next action', NO_DATE: 'no date', OVERDUE: 'overdue', NO_OWNER: 'no owner' };
const scoreOf = (key) => (state.cmd?.scorecards?.directors || []).find((x) => x.key === key);
const ordersOf = (key) => (state.cmd?.work_orders || []).filter((w) => w.director === key && !['COMPLETE', 'CANCELLED'].includes(w.status));

// PIPELINE: every company at its furthest stage; every live opportunity with owner, next action, date and blocker.
function dashPipeline() {
  const C = state.cmd; if (!C) return `<section class="dsec" id="pipeline"><header><h2>Pipeline</h2></header>${waitFor('cmd', 'the pipeline')}</section>`;
  const st = C.funnel?.stages || []; const by = Object.fromEntries(st.map((s) => [s.stage, s]));
  const strip = st.filter((s) => s.stage !== 'LOST_PARKED').map((s) => `<div class="pst ${s.n ? '' : 'zero'}"><span class="pn">${n0(s.n)}</span><span class="pl">${esc(s.label)}</span>${s.stuck ? `<span class="pk">${s.stuck} stuck</span>` : ''}</div>`).join('<span class="parr">→</span>');
  // Conversion between the commercial steps, shown as a rate only when the base is 20 or more (no decisions on tiny samples).
  const opps = C.opportunities || []; const gaps = opps.filter((o) => (o.missing || []).length);
  const stuck = st.reduce((n, s) => n + (s.stuck || 0), 0);
  const rows = opps.map((o) => `<tr><td><a class="clickable" data-open="company" data-id="${o.company_id}">${esc(o.company)}</a>${o.director ? `<div class="faint small">${esc(dirName(o.director))}</div>` : ''}</td>
      <td data-l="Stage">${esc(o.label)}</td><td data-l="Owner" class="small">${esc(o.owner || '—')}</td>
      <td data-l="Next action" class="small">${o.next_action ? esc(plainText(o.next_action)) : '<span class="bad-text">No next action</span>'}</td>
      <td data-l="Date" class="small ${(o.missing || []).includes('OVERDUE') ? 'bad-text' : ''}">${o.next_action_due ? esc(shortDay(o.next_action_due)) : '<span class="bad-text">No date</span>'}</td>
      <td data-l="Blocker" class="small">${o.blocker ? `<span class="warn-text">${esc(o.blocker)}</span>` : '<span class="faint">—</span>'}</td>
      <td>${o.opportunity_id ? `<button class="btn small" data-modal="opp-plan" data-opp="${o.opportunity_id}">Plan</button>` : ''}</td></tr>`).join('');
  const A = C.kpis?.canonical_all || {}; const ca = A.companies || {}; const M30 = C.kpis?.canonical_30?.messages || {};
  const ever = [['Contacted', ca.contacted], ['Replied', ca.replied], ['Positive', ca.positive], ['Meeting', ca.meetings], ['Brief', ca.briefs], ['Proposal', ca.proposals], ['Won', ca.wins]]
    .map(([l, v]) => `${l} ${n0(v)}`).join(' → ');
  return `<section class="dsec" id="pipeline"><header><h2>Pipeline</h2><span class="faint small">Where each company stands now</span></header>
    <div class="pipe">${strip}</div>
    <p class="small"><b>Where business is lost:</b> ${n0(by.LOST_PARKED?.n)} lost or parked · ${stuck ? `<span class="warn-text">${stuck} stuck</span>` : '0 stuck'} · ${gaps.length ? `<span class="bad-text">${plural(gaps.length, 'live opportunity', 'live opportunities')} missing a next action or date</span>` : 'every live opportunity has a next action and date'}.
      </p>
    <p class="small ever"><b>Ever reached (companies, all time):</b> ${ever}${n0(ca.contacted) >= 20 ? ` <span class="faint">· reply rate ${Math.round((100 * (ca.replied || 0)) / ca.contacted)}%</span>` : ''}<br>
      <span class="faint">Outreach messages, last 30 days: ${n0(M30.outreach)} (${n0(M30.first)} first, ${n0(M30.follow_ups)} follow-ups) · ${n0(M30.replies)} reply messages</span></p>
    ${opps.length ? `<div class="tbl-wrap"><table class="stack"><thead><tr><th>Opportunity</th><th>Stage</th><th>Owner</th><th>Next action</th><th>Date</th><th>Blocker</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`
      : '<div class="calm"><div class="calm-t">No live opportunity yet.</div><div class="t-sub">A company appears here from its first reply.</div></div>'}
    <p class="src">${esc(C.funnel?.method || '')}</p></section>`;
}

// RECOMMENDATIONS AWAITING ADAM: the improvement loop's decision step. Approve applies the change (or records it for the System).
function dashApprovals() {
  const recs = (state.cmd?.recommendations || []).filter((r) => r.state === 'RECOMMENDED');
  if (!recs.length) return '';
  return `<div class="recs"><div class="adv-k">Awaiting your approval · ${recs.length}</div>${recs.map((r) => `<article class="rec">
      <div class="rec-t">${esc(r.title)} <span class="faint small">· ${esc(r.area || '')}</span></div>
      <div class="small"><b>Seen:</b> ${esc(r.observe || '')}</div><div class="small"><b>Recommended:</b> ${esc(r.recommend || '')}</div>
      <div class="btn-row mt6"><button class="btn small primary" data-modal="rec" data-id="${r.id}" data-type="APPROVE">Approve</button><button class="btn small ghost" data-modal="rec" data-id="${r.id}" data-type="DECLINE">Decline</button></div></article>`).join('')}</div>`;
}

// WORK ORDERS: Adam -> Director. Status comes from evidence (work_order_eval), never from a setting.
function woCard(w) {
  const [l, c] = WO_STATUS[w.status] || [w.status, '']; const r = w.results || {}; const open = !['COMPLETE', 'CANCELLED'].includes(w.status);
  const chain = [['matched', 'matching companies'], ['email_ready', 'email-ready'], ['drafted', 'drafted'], ['in_review', 'in your review'], ['sent', 'sent'], ['replies', 'replies'], ['meetings', 'meetings'], ['proposals', 'proposals'], ['wins', 'wins']]
    .map(([k, t]) => `<span class="ef"><b>${n0(r[k] ?? 0)}</b> ${t}</span>`).join('<span class="ef-a">→</span>');
  return `<article class="wo">
    <div class="wo-top"><div><div class="wo-m">${esc(w.mission || '')}</div><div class="small faint">${esc(w.director_name || dirName(w.director))} · ${esc(w.priority || 'P2')} · target ${esc((w.terms || []).join(', ') || 'the Director’s universe')} · due ${esc(shortDay(w.deadline))}</div></div>
      <span class="st ${c}">${esc(l)}</span></div>
    <div class="wo-goal"><b>${n0(w.result)}</b> of ${n0(w.goal)} ${esc((WO_METRIC.find(([k]) => k === w.metric) || [, w.metric])[1].toLowerCase())}
      <span class="faint small">· issued ${esc(shortDay(w.issued_at))}${w.accepted_at ? ` · accepted ${esc(fmtDate(w.accepted_at))}` : ''}</span></div>
    <div class="ef-row small">${chain}</div>
    ${w.blocker ? `<div class="small bad-text mt6">${esc(w.blocker)}</div>` : w.note ? `<div class="small mt6">${esc(w.note)}</div>` : ''}
    ${!open && w.outcome ? `<div class="small mt6"><b>Outcome:</b> ${esc(w.outcome)}</div>` : ''}
    ${open ? `<div class="btn-row mt6"><button class="btn small ghost" data-modal="wo-close" data-id="${w.id}" data-type="CLOSE">Close</button><button class="btn small ghost" data-modal="wo-close" data-id="${w.id}" data-type="CANCEL">Cancel</button></div>` : ''}
  </article>`;
}
function woPanel() {
  const C = state.cmd; if (!C) return '';
  const list = C.work_orders || [];
  return `<section class="dsec"><header><h2>Work orders</h2><span class="faint small">Your missions to the Directors. The Director owns the result; the specialists support it.</span>
      <button class="btn small primary" data-modal="work-order">Issue a work order</button></header>
    ${list.length ? `<div class="wo-grid">${list.map(woCard).join('')}</div>` : '<div class="calm"><div class="calm-t">No work order yet.</div><div class="t-sub">Issue one to a Director: the target companies go first in research, contact, email and drafting from their next run.</div></div>'}</section>`;
}

// SCORECARDS: commercial results only. Rates and rankings need at least 20 first messages in the window.
function scorePanel() {
  const S = state.cmd?.scorecards; if (!S) return '';
  const w = state.scWin || 'd7'; const min = S.min_sample || 20;
  const tabs = [['d7', '7 days'], ['d30', '30 days'], ['all', 'All time']].map(([k, l]) => `<button class="${w === k ? 'on' : ''}" data-sc-win="${k}">${l}</button>`).join('');
  const rows = (S.directors || []).map((x) => { const s = x[w] || {}; const cv = x.coverage || {};
    return `<tr class="clickable" data-director="${x.key}"><td><b>${esc(x.name)}</b></td><td class="num" data-l="Qualified">${n0(s.qualified)}</td>
      <td class="num" data-l="Email coverage">${cv.coverage_pct != null ? `${esc(cv.coverage_pct)}%` : '—'}</td><td class="num" data-l="Sent">${n0(s.sent)}</td>
      <td class="num" data-l="Reply rate">${s.sample === 'OK' ? `${esc(s.reply_rate_pct)}%` : `<span class="faint" title="Fewer than ${min} first messages">n=${n0(s.sent)}</span>`}</td>
      <td class="num" data-l="Replies">${n0(s.replies)}</td><td class="num" data-l="Positive">${n0(s.positive)}</td><td class="num" data-l="Meetings">${n0(s.meetings)}</td>
      <td class="num" data-l="Briefs">${n0(s.briefs)}</td><td class="num" data-l="Proposals">${n0(s.proposals)}</td><td class="num" data-l="Wins">${n0(s.wins)}</td>
      <td class="num" data-l="Revenue">${esc(Object.entries(s.revenue || {}).map(([c, a]) => cash(a, c)).join(' + ') || '—')}</td></tr>`; }).join('');
  const rank = (S.ranking_d30 || []);
  return `<section class="dsec"><header><h2>Director scorecards</h2><div class="tabs sm">${tabs}</div></header>
    <div class="tbl-wrap"><table class="stack sc"><thead><tr><th>Director</th><th class="num">Qualified</th><th class="num">Email coverage</th><th class="num">Sent</th><th class="num">Reply rate</th><th class="num">Replies</th><th class="num">Positive</th><th class="num">Meetings</th><th class="num">Briefs</th><th class="num">Proposals</th><th class="num">Wins</th><th class="num">Revenue</th></tr></thead><tbody>${rows}</tbody></table></div>
    <p class="small">${rank.length ? `<b>Ranking (30 days, reply rate):</b> ${rank.map((r) => `${esc(dirName(r.key))} ${esc(r.reply_rate_pct)}% of ${esc(r.sent)}`).join(' · ')}` : `<b>No ranking yet:</b> no Director has ${min} first messages in the last 30 days, so a rate would mislead. “n=” is the number of first messages sent.`}</p>
    <p class="src">${esc(S.method || '')}</p></section>`;
}

// REVENUE: actual revenue from records with evidence, and the reconciliation of the historical figure.
function revenuePanel() {
  const C = state.cmd; if (!C) return `${waitFor('cmd', 'revenue')}`;
  const R = C.revenue || {}; const H = R.historical || {}; const stated = Number(H.stated_amount || 0); const rec = Number(H.reconciled || 0);
  const card = (l, v, sub) => `<div class="rv"><div class="rv-l">${l}</div><div class="rv-v">${v}</div>${sub ? `<div class="rv-s">${sub}</div>` : ''}</div>`;
  const tbl = (title, list, col) => `<section class="panel"><header><h3>${title}</h3></header><div class="body">${list.length ? `<table class="mini-t"><tbody>${list.map((x) => `<tr><td>${esc(col(x))}</td><td class="num">${esc(cash(x.amount, x.currency))}</td>${x.records != null ? `<td class="num faint">${esc(x.records)}</td>` : ''}</tr>`).join('')}</tbody></table>` : '<p class="muted small">Not recorded.</p>'}</div></section>`;
  return `<h2>Revenue</h2>
    <p class="small muted">Actual revenue is the sum of revenue records that carry evidence (invoice, bank reference, contract or email). Currencies are never added together and nothing is estimated.</p>
    <div class="rv-grid">${card('Actual revenue', esc(cashOf(R.recorded) || '£0'), `${(R.recorded || []).reduce((n, x) => n + Number(x.records || 0), 0)} records`)}
      ${card('Received', esc(cashOf(R.received) || '£0'))}${card('Receivables', esc(cashOf(R.receivables) || '£0'))}
      ${card('Gross profit', esc(cashOf(R.gross_profit) || 'Not recorded'), 'only where supplier costs are recorded')}</div>
    ${stated ? `<section class="hist ${rec >= stated ? 'done' : ''}"><div class="hist-k">${rec >= stated ? 'HISTORICAL REVENUE — RECONCILED' : 'HISTORICAL REVENUE — TO BE RECONCILED'}</div>
      <div class="hist-row"><span><b>${esc(cash(stated, H.currency))}</b> stated (${esc(H.period || '')}, ${esc(H.stated_by || '')})</span><span><b>${esc(cash(rec, H.currency))}</b> reconciled from ${n0(H.reconciled_records)} records</span>
        <span><b>${esc(cash(Math.max(stated - rec, 0), H.currency))}</b> still to reconcile</span></div>
      <p class="small">The stated figure is not counted as revenue. Each historical project is added as one record with its client, date, service, gross, supplier costs, payment status, currency and evidence; the totals above then follow from the records.${H.other_currency_records ? ` ${esc(H.other_currency_records)} records are in other currencies and are not added to the ${esc(H.currency)} total.` : ''}</p>
      <div class="btn-row"><button class="btn primary small" data-modal="revenue-import">Import historical revenue</button></div></section>` : ''}
    <div class="three">${tbl('By service', R.by_service || [], (x) => x.service)}${tbl('By Director', R.by_director || [], (x) => (x.director === 'UNATTRIBUTED' ? 'Not attributed' : dirName(x.director)))}${tbl('By month', R.by_month || [], (x) => x.month)}</div>
    ${(R.won_without_revenue || []).length ? `<div class="banner err">Won without a revenue record: ${esc(R.won_without_revenue.map((x) => x.company).join(', '))}. Every won project needs its revenue recorded.</div>` : ''}
    ${(R.records || []).length ? `<h3>Revenue records (${R.records.length})</h3><div class="tbl-wrap"><table class="stack"><thead><tr><th>Date</th><th>Client</th><th>Project / service</th><th>Director</th><th class="num">Gross</th><th class="num">Supplier cost</th><th class="num">Gross profit</th><th>Status</th><th>Evidence</th></tr></thead><tbody>
      ${R.records.map((x) => `<tr><td data-l="Date">${esc(shortDay(x.date))}</td><td data-l="Client">${esc(x.client || '—')}${x.historical ? ' <span class="pill">historical</span>' : ''}</td><td data-l="Project" class="small">${esc([x.project, x.service].filter(Boolean).join(' · ') || '—')}</td>
        <td data-l="Director" class="small">${esc(x.director ? dirName(x.director) : '—')}</td><td class="num" data-l="Gross">${esc(cash(x.gross, x.currency))}</td><td class="num" data-l="Supplier cost">${esc(x.supplier_cost != null ? cash(x.supplier_cost, x.currency) : '—')}</td>
        <td class="num" data-l="Gross profit">${esc(x.gross_profit != null ? cash(x.gross_profit, x.currency) : '—')}</td><td data-l="Status">${pill(sentence(String(x.payment_status).replace('_', ' ')), x.payment_status === 'PAID' ? 'ok' : 'warn')}</td><td data-l="Evidence" class="small">${esc(x.evidence || '—')}</td></tr>`).join('')}</tbody></table></div>` : ''}`;
}
const REV_COLUMNS = ['client', 'project', 'date', 'service', 'director', 'gross', 'supplier_cost', 'payment_status', 'amount_paid', 'currency', 'evidence', 'invoice_reference', 'notes'];
function revenueRows(text) {
  const rows = parseCsv(String(text || '').trim()).filter((r) => r.some((c) => String(c).trim()));
  if (!rows.length) return [];
  const head = rows[0].map((h) => String(h).trim().toLowerCase().replace(/[^a-z_]/g, '_'));
  return rows.slice(1).map((r) => Object.fromEntries(head.map((h, i) => [h, String(r[i] ?? '').trim()]).filter(([h]) => REV_COLUMNS.includes(h))));
}

// SYSTEM HEALTH (Admin only): services, agents on schedule, AI calls, integrity checks. CEO screens never show this.
async function loadHealth(force = false) {
  const ks = ['health', 'integ'].filter((k) => force || (!state[k] && !state.busy[k] && !state.errors[k]));
  if (!ks.length) return;
  ks.forEach((k) => delete state.errors[k]);
  await Promise.all(ks.map(readKey)); render();
}
function healthPanel() {
  const H = state.health; const I = state.integ || H?.integrity;
  if (!H) { loadHealth(); return `<h2>System health</h2>${waitFor('health', 'system health')}`; }
  const ok = (b) => `<span class="dot ${b ? '' : 'bad'}"></span>`;
  const agents = H.agents || []; const late = agents.filter((a) => !a.on_schedule);
  const ai = H.ai?.by_workflow_7d || []; const hun = H.hunter || {};
  // a workflow failure alert in the last 7 days (and a provider outage in the last 3) is a Check, even when every agent is on schedule
  const asAt = new Date(H.generated_at || Date.now()).getTime();
  const recent = (f, days) => /SYSTEM_FAILURE/.test(f.type) && asAt - new Date(f.at).getTime() < days * 864e5;
  const wfFail = (H.failures || []).filter((f) => recent(f, 7)); const provFail = wfFail.filter((f) => recent(f, 3) && /PROVIDER_UNAVAILABLE|payment required|credit/i.test(f.title));
  const wfName = (t) => String(t).replace(/^SYSTEM FAILURE\s*[—-]+\s*/, '').replace(/\s*\[.*$/, '');
  const svc = [
    ['Supabase', true, `${esc(H.supabase?.database_mb)} MB · ${(H.supabase?.cron || []).filter((j) => j.active).length} scheduled jobs · ${(H.supabase?.cron || []).reduce((n, j) => n + Number(j.failed_7d || 0), 0)} job failures in 7 days · backups: ${esc(H.supabase?.backups || '')}`],
    ['n8n workflows', !late.length && !wfFail.length, [late.length ? `${late.length} of ${agents.length} agents behind schedule: ${esc(late.map((a) => a.name).join(', '))}` : `all ${agents.length} agents ran within their schedule`,
      wfFail.length ? `${wfFail.length} failure alert${wfFail.length > 1 ? 's' : ''} in 7 days: ${esc([...new Set(wfFail.map((f) => wfName(f.title)))].join(', '))}` : ''].filter(Boolean).join(' · ')],
    ['Gmail sync', !!H.gmail?.on_schedule, `last sync ${esc(fmtDate(H.gmail?.last_sync))} (every 30 minutes)`],
    ['Gmail history import', !!H.gmail_history?.on_schedule, `last import ${esc(fmtDate(H.gmail_history?.last_import))}${H.gmail_history?.error ? ` · ${esc(H.gmail_history.error)}` : ''}`],
    ['Hunter', hun.ok !== false, `${esc(hun.plan || '—')} plan · ${esc(hun.verifications_left ?? '—')} verifications left · resets ${esc(hun.reset_date || '—')} · checked ${esc(fmtDate(hun.checked_at))}`],
    ['Serper', !!H.serper, H.serper ? `${esc(Number(H.serper.balance).toLocaleString('en-GB'))} searches left · ${esc(fmtDate(H.serper.at))}` : 'no balance recorded'],
    ['AI providers', !provFail.length && !ai.some((x) => Number(x.error) + Number(x.rate_limited) > Number(x.ok)), `${provFail.length ? `model unavailable on ${provFail.length} run${provFail.length > 1 ? 's' : ''} in 3 days (${esc([...new Set(provFail.map((f) => wfName(f.title)))].join(', '))}) · ` : ''}${ai.reduce((n, x) => n + Number(x.ok), 0)} successful calls, ${ai.reduce((n, x) => n + Number(x.error), 0)} errors, ${ai.reduce((n, x) => n + Number(x.rate_limited), 0)} rate-limited in 7 days · $${esc(H.ai?.usd_30d)} in 30 days`],
    ['Studio renderer', true, `${esc(H.studio?.documents)} documents recorded · last ${esc(fmtDate(H.studio?.last_recorded))} · ${esc(H.studio?.renderer || '')}`],
  ].map(([n, g, t]) => `<div class="row"><div class="t">${ok(g)}${esc(n)} ${g ? pill('OK', 'ok') : pill('Check', 'bad')}</div><div class="meta">${t}</div></div>`).join('');
  const checks = (I?.checks || []).filter((c) => Number(c.count) > 0 || Number(c.auto_fixed) > 0);
  return `<h2>System health</h2><p class="small muted">Live from Supabase every 15 minutes. Technical detail lives here, never on the CEO screens. <button class="linkish" data-health-refresh>Refresh</button></p>
    <div class="list">${svc}</div>
    ${(H.failures || []).length ? `<h3>Open workflow failures (${H.failures.length})</h3><div class="list">${H.failures.map((f) => `<div class="row"><div class="t">${pill(sentence(String(f.type).replace(/_/g, ' ')), 'bad')} ${esc(f.title)}</div><div class="meta">${esc(fmtDate(f.at))}</div></div>`).join('')}</div>` : ''}
    <h3>Data integrity ${I ? `<span class="faint small">· checked ${esc(fmtDate(I.generated_at))} · daily 05:10 Cairo</span>` : ''}</h3>
    ${I ? (checks.length ? `<div class="tbl-wrap"><table class="stack"><thead><tr><th>Check</th><th class="num">Found</th><th>Examples</th></tr></thead><tbody>${checks.map((c) => `<tr><td>${pill(c.severity, c.severity === 'ERROR' ? 'bad' : c.severity === 'WARN' ? 'warn' : '')} ${esc(c.label)}${Number(c.auto_fixed) ? `<div class="small ok-text">${esc(c.auto_fixed)} corrected automatically: ${esc(c.fix || '')}</div>` : ''}</td>
        <td class="num" data-l="Found">${n0(c.count)}</td><td data-l="Examples" class="small">${esc((c.sample || []).map((s) => Object.values(s).filter((v) => v != null && typeof v !== 'object').join(' · ')).join(' | '))}</td></tr>`).join('')}</tbody></table></div>` : '<div class="banner ok">All integrity checks pass.</div>')
      : '<p class="muted small">Integrity check not run yet.</p>'}
    <h3>Agents</h3><div class="tbl-wrap"><table class="stack"><thead><tr><th>Agent</th><th>Workflows</th><th>Last run</th><th>Schedule</th></tr></thead><tbody>
      ${agents.map((a) => `<tr><td>${esc(a.name)}</td><td data-l="Workflows" class="small">${esc((a.workflows || []).join(' ').replace(/ -/g, ''))}</td><td data-l="Last run" class="small">${esc(a.last_run ? fmtDate(a.last_run) : 'never')}</td><td data-l="Schedule">${a.paused ? pill('Paused', '') : a.on_schedule ? pill('On schedule', 'ok') : pill(`Late (max ${a.max_gap_hours} h)`, 'bad')}</td></tr>`).join('')}</tbody></table></div>
    <h3>AI calls by workflow · 7 days</h3><div class="tbl-wrap"><table class="stack"><thead><tr><th>Workflow</th><th class="num">OK</th><th class="num">Errors</th><th class="num">Rate-limited</th><th class="num">Cost</th><th>Last call</th></tr></thead><tbody>
      ${ai.map((x) => `<tr><td>${esc(x.workflow)}</td><td class="num" data-l="OK">${n0(x.ok)}</td><td class="num ${Number(x.error) ? 'bad-text' : ''}" data-l="Errors">${n0(x.error)}</td><td class="num ${Number(x.rate_limited_pct) >= 20 ? 'warn-text' : ''}" data-l="Rate-limited">${n0(x.rate_limited)}${x.rate_limited_pct ? ` (${esc(x.rate_limited_pct)}%)` : ''}</td><td class="num" data-l="Cost">$${esc(x.usd)}</td><td data-l="Last" class="small">${esc(fmtDate(x.last))}</td></tr>`).join('') || '<tr><td colspan="6" class="muted">No AI calls recorded in 7 days.</td></tr>'}</tbody></table></div>`;
}

// ---------------------------------------------------------------- AGENTS: the workforce as a company
const DSTATUS = { WORKING: ['Working', 'ok'], SCHEDULED: ['Scheduled', ''], PAUSED: ['Paused', ''], BLOCKED: ['Blocked', 'warn'], ERROR: ['Error', 'bad'] };
const DMETRIC = [['companies_found', 'Companies found'], ['people_confirmed', 'People confirmed'], ['verified_emails', 'Verified emails'], ['outreach_drafts', 'Outreach drafts'],
  ['gmail_drafts', 'Gmail drafts'], ['replies', 'Replies'], ['opportunities', 'Opportunities']];
const SMETRIC = { RESEARCH: [['companies_researched', 'Researched'], ['companies_qualified', 'Qualified'], ['signals', 'Signals']],
  CONTACT: [['people_confirmed', 'People confirmed'], ['companies_enriched', 'Companies searched']],
  EMAIL: [['valid_verified', 'Valid verified'], ['public_emails_found', 'Public emails found'], ['accept_all', 'Accept-all'], ['invalid', 'Invalid']],
  WRITER: [['drafts_written', 'Drafts written'], ['passed_quality', 'Passed quality'], ['revalidated', 'Revalidated']],
  MEMORY: [['gmail_messages', 'Gmail messages'], ['relationships_summarised', 'Summaries']],
  REPLY: [['replies_detected', 'Replies detected'], ['sends_detected', 'Sends detected']],
  DIRECTOR: [['touches_planned', 'Touches planned'], ['briefs', 'Briefs']],
  LINKEDIN: [['messages_sent', 'Messages sent'], ['replies', 'Replies'], ['meetings', 'Meetings'], ['ready', 'Waiting for you']],
  GROWTH: [['posts_analysed', 'Posts analysed'], ['concepts', 'Concepts'], ['content_items', 'Content items'], ['attributed_leads', 'Attributed leads']] };
const ROLE_LABEL = { DIRECTOR: 'Director', MANAGER: 'Strategic Partnerships Manager', SUPPORT: 'Shared specialist' };
// Every Director answers: what are you working on, what did you produce, what could become business, do you need Adam?
function emailLine(c) {
  if (!c) return '';
  const st = (n, l, cls = '') => `<span class="ef ${cls}"><b>${n0(n)}</b> ${l}</span>`;
  return `<div class="dc-email"><div class="dc-sub">Email</div><div class="ef-row">${st(c.with_dm, 'decision makers')}<span class="ef-a">→</span>${st(c.emails_found, 'email found')}<span class="ef-a">→</span>${st(c.verified, 'verified', 'ok')}
    <span class="ef-a">·</span>${st(c.needs_verification, 'waiting verification')}<span class="ef-a">·</span>${st(c.email_ready, 'email ready', c.email_ready ? 'ok' : '')}<span class="ef-a">·</span>${st(c.linkedin_fallback, 'LinkedIn fallback', 'muted')}</div>
    ${c.bottleneck ? `<div class="small warn-text">${c.bottleneck === 'VERIFICATION' ? 'Bottleneck: verification' : 'Bottleneck: finding the right person'}</div>` : ''}</div>`;
}
// Does this Director need Adam? Emails to approve first; LinkedIn fallbacks are counted separately, never as progress.
function deskNeedsLine(key) {
  const D = state.desk; if (!D) return '';
  const nr = (D.needs_review || []).filter((x) => x.director === key);
  const em = nr.filter((x) => x.channel === 'EMAIL').length; const other = nr.length - em; const qa = qaHeld().filter((x) => x.director === key).length;
  const parts = [em && plural(em, 'email to approve', 'emails to approve'), qa && plural(qa, 'email draft to edit', 'email drafts to edit'), other && `${plural(other, 'LinkedIn / Instagram fallback', 'LinkedIn / Instagram fallbacks')} to send by hand`].filter(Boolean);
  return `<div class="dc-need ${em || qa ? 'on' : ''}"><span class="dc-sub">Needs you</span>${parts.length ? esc(parts.join(' · ')) : '<span class="faint">Nothing waiting for you</span>'}</div>`;
}
function directorCard(m) {
  const [sl, sc] = DSTATUS[m.status] || [m.status, ''];
  const support = m.role === 'SUPPORT' || m.key === 'GROWTH';
  const t = m.today || {}; const d7 = state.ceo?.directors?.[m.key]?.d7 || {}; const top = state.ceo?.directors?.[m.key]?.top;
  const next = m.next_run ? new Date(m.next_run).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Cairo' }) : null;
  const hard = (m.blockers || []).filter((b) => b.hard); const soft = (m.blockers || []).filter((b) => !b.hard);
  const cell = (n, l) => `<div class="dc-c"><b>${n0(n)}</b><span>${l}</span></div>`;
  const today = support ? (SMETRIC[m.key] || []).map(([k, l]) => cell(t[k], l)).join('')
    : cell(t.companies_found, 'qualified companies') + cell(t.people_confirmed, 'correct people') + cell(t.verified_emails, 'verified emails') + cell(t.outreach_drafts, 'outreach ready') + cell(t.replies, 'replies') + cell(t.opportunities, 'opportunities');
  const card7 = scoreOf(m.key)?.d7; const wk = card7 || d7; const wos = ordersOf(m.key);
  const week = support ? '' : cell(wk.sent, 'sent') + cell(wk.replies, 'replies') + cell(wk.positive, 'positive') + cell(wk.meetings, 'meetings') + cell(card7 ? card7.briefs : null, 'briefs') + cell(wk.proposals, 'proposals') + cell(wk.wins, 'wins')
    + (card7 && Object.keys(card7.revenue || {}).length ? `<div class="dc-c"><b>${esc(Object.entries(card7.revenue).map(([c, a]) => cash(a, c)).join(' + '))}</b><span>revenue</span></div>` : '');
  return `<article class="dcard" data-director="${m.key}">
    <div class="dc-head"><div><div class="dc-name">${esc(m.name)}</div><div class="dc-role">${esc(ROLE_LABEL[m.role] || '')}</div></div>
      <span class="st ${sc}">${esc(m.status === 'SCHEDULED' && next ? `${sl} — ${next}` : sl)}</span></div>
    <div class="dc-now"><span class="dc-sub">Working on</span>${esc(plainText(m.working_on || m.next_focus || m.mission || '—'))}</div>
    <div class="dc-last"><span class="dc-sub">Last completed</span>${m.last_action ? `${esc(m.last_action.text)} · ${esc(rel(m.last_action.at))}`
      : m.last_run ? `<span class="faint">Ran ${esc(rel(m.last_run))}: no new output</span>` : '<span class="faint">No recorded run yet</span>'}</div>
    ${m.role === 'DIRECTOR' && m.key !== 'GROWTH' ? deskNeedsLine(m.key) : ''}
    <div class="dc-sub mt6">Today</div><div class="dc-cells">${today}</div>
    ${week ? `<div class="dc-sub">Last 7 days</div><div class="dc-cells">${week}</div>` : ''}
    ${support ? '' : emailLine(m.channel)}
    ${hard.map((b) => `<div class="dc-block bad-text">Blocked: ${esc(b.text)}</div>`).join('')}${soft.slice(0, 1).map((b) => `<div class="dc-block warn-text">${esc(b.text)}</div>`).join('')}
    ${!support && m.role === 'DIRECTOR' ? `<div class="dc-wo"><span class="dc-sub">Work orders</span>${wos.length ? wos.map((w) => `${esc((WO_STATUS[w.status] || [w.status])[0])}: ${esc(w.mission)} <span class="faint">(${n0(w.result)} of ${n0(w.goal)})</span>`).join('<br>') : '<span class="faint">None open</span>'}
      <button class="btn small ghost" data-modal="work-order" data-id="${m.key}">Issue a work order</button></div>` : ''}
    ${support ? '' : `<div class="dc-top"><span class="dc-sub">Top opportunity</span>${top ? `${esc(top.company)} · ${esc(projectName(top.project))}${top.stage ? ` <span class="faint">(${esc((STAGE_NAME[top.stage] || '').toLowerCase())})</span>` : ''}` : '<span class="faint">None yet</span>'}</div>`}
  </article>`;
}
function v3Feed(items, limit) {
  return (items || []).slice(0, limit).map((f) => `<div class="feed-row ${f.company_id ? 'clickable' : ''}" ${f.company_id ? `data-open="company" data-id="${f.company_id}"` : ''}>
    <span class="feed-t">${esc(new Date(f.at).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Cairo' }))}<small>${esc(shortDay(f.at))}</small></span>
    <span><b>${esc(memberName(f.agent))}</b> ${esc(f.text)}</span></div>`).join('') || '<div class="empty">No recorded activity for this filter in the last 7 days.</div>';
}
function viewAgentsV3() {
  const D = state.directors;
  if (!D) { loadV3('directors', 'hq_directors'); return head('Agents') + waitFor('directors', 'the workforce'); }
  const by = (r) => D.members.filter((m) => m.role === r);
  const a = state.exec?.queue?.acquisition; const feed = (D.feed || []).filter((x) => !state.feedDir || x.agent === state.feedDir);
  return `${head('Agents', esc(['The people running each department of NOYA', asOf(D)].filter(Boolean).join(' · ')))}
    ${a ? `<p class="lead-line">Email ready <b>${n0(a.email_ready)}</b> <span class="faint">(target ${esc((a.reserve?.target || [100, 150]).join('–'))})</span> · waiting for verification <b>${n0(a.pipeline?.needs_verification)}</b> · LinkedIn fallback ${n0(a.linkedin_fallback)}</p>` : ''}
    ${woPanel()}${scorePanel()}
    <h3 class="grp">Directors</h3><div class="dgrid">${by('DIRECTOR').map(directorCard).join('')}</div>
    <h3 class="grp">Strategic partnerships</h3><div class="dgrid">${by('MANAGER').map(directorCard).join('')}</div>
    ${studioTeam()}
    <h3 class="grp">Shared specialists</h3><div class="dgrid compact">${by('SUPPORT').map(directorCard).join('')}</div>
    <details class="panel mt8"><summary>Activity · ${feed.length}</summary><div class="body"><select class="w-auto" data-feed-dir><option value="">Everyone</option>${D.members.map((m) => `<option value="${m.key}" ${state.feedDir === m.key ? 'selected' : ''}>${esc(m.name)}</option>`).join('')}</select>
      ${v3Feed(feed, state.feedAll ? 200 : 20)}${feed.length > 20 ? `<button class="linkish" data-feed-all>${state.feedAll ? 'Show less' : `Show all ${feed.length}`}</button>` : ''}</div></details>`;
}

// ---------------------------------------------------------------- Director drill-down
function dPerson(p) {
  const ig = p.instagram ? String(p.instagram).replace(/^@/, '').replace(/^https?:\/\/(www\.)?instagram\.com\//, '').replace(/\/$/, '') : '';
  return `<div class="mini"><div class="t">${esc(p.name || 'Unnamed')}${p.role ? ` · <span class="faint">${esc(p.role)}</span>` : ''}</div>
    <div class="m"><a class="clickable" data-open="company" data-id="${p.company_id}">${esc(p.company || '')}</a>${p.country ? ` · ${esc(p.country)}` : ''} · confidence ${esc(String(p.confidence || '').toLowerCase().replace('_', ' '))}</div>
    <div class="m">${p.email ? `${esc(p.email)} ${estatePill(p.email_state)}` : estatePill('NOT_FOUND')}${p.linkedin ? ` · <a href="${esc(p.linkedin)}" target="_blank" rel="noopener noreferrer">LinkedIn</a>` : ''}${ig ? ` · <a href="https://instagram.com/${esc(ig)}" target="_blank" rel="noopener noreferrer">@${esc(ig)}</a>` : ''}${p.phone ? ` · official phone ${esc(p.phone)}` : ''}</div>
    <div class="m faint">Source: ${p.source ? `<a href="${esc(p.source)}" target="_blank" rel="noopener noreferrer">${esc((p.source_type || 'link').toLowerCase().replace(/_/g, ' '))}</a>` : 'not recorded'}${p.found_at ? ` · found ${esc(shortDay(p.found_at))}` : ''}</div></div>`;
}
function dSection(s) {
  const it = Array.isArray(s.items) ? s.items : [];
  switch (s.kind) {
    case 'companies': return it.map((c) => `<div class="mini clickable" data-open="company" data-id="${c.company_id}"><div class="t">${esc(c.company)} ${c.status ? pill(sentence(c.status)) : ''}</div>
      <div class="m">${esc([c.type, c.country].filter(Boolean).join(' · '))}${c.people != null ? ` · ${plural(c.people, 'decision maker', 'decision makers')} · ${esc(c.verified)} verified` : ''}${c.director ? ` · ${esc(memberName(c.director))}` : ''}${c.found_at ? ` · ${esc(shortDay(c.found_at))}` : ''}</div>
      ${c.model ? `<div class="m">→ ${esc(c.model)}</div>` : ''}${c.attempts != null ? `<div class="m faint">${esc(c.attempts)} enrichment attempts${c.last_enriched ? ` · last ${esc(shortDay(c.last_enriched))}` : ''}</div>` : ''}</div>`).join('');
    case 'people': return it.map(dPerson).join('');
    case 'gaps': return it.map((g) => { const p = (g.people || [])[0]; return `<div class="mini clickable" data-open="company" data-id="${g.company_id}"><div class="t">${esc(g.company)} ${pill(`score ${g.score}`)}</div>
      <div class="m">${p ? `${esc(`${p.first_name || ''} ${p.last_name || ''}`.trim())}${p.position ? ` · ${esc(p.position)}` : ''}` : 'No decision maker named yet'} · <span class="warn-text">no usable named or department email yet</span></div>
      <div class="m faint">${g.checked_at ? `Searched ${esc(shortDay(g.checked_at))} · ${plural(g.attempts, 'attempt', 'attempts')}` : 'Not searched for email yet'}</div></div>`; }).join('');
    case 'opportunities': return it.map((o) => `<div class="mini clickable" data-open="company" data-id="${o.company_id}"><div class="t">${esc(o.company)}${o.status ? ` ${pill(sentence(o.status))}` : ''}${o.relationship && o.relationship !== 'COLD' ? ` ${pill(sentence(o.relationship.replace(/_/g, ' ')), 'info')}` : ''}</div>
      ${o.model ? `<div class="m"><b>${esc(String(o.model).split(':')[0])}</b></div>` : ''}
      ${o.value ? `<div class="m">Value to NOYA: ${esc(o.value.to_noya)}</div><div class="m">Value to them: ${esc(o.value.to_partner)}</div>` : ''}
      <div class="m">Right contact: ${o.contact ? `${esc(o.contact.name || '')}${o.contact.role ? `, ${esc(o.contact.role)}` : ''} ${estatePill(o.contact.email_state)}` : '<span class="warn-text">not identified yet</span>'}</div>
      <div class="m"><b>Next step:</b> ${esc(plainText(o.next_step))}</div>${o.angle ? `<div class="m faint">${esc(plainText(o.angle))}</div>` : ''}</div>`).join('');
    case 'desk': return it.map((x) => deskRow(x, true)).join('');
    case 'linkedin': return it.map(liRow).join('');
    case 'verify': return it.map((v) => `<div class="mini clickable" data-open="company" data-id="${v.company_id}"><div class="t">${esc(v.name || v.email)}${v.position ? ` · <span class="faint">${esc(v.position)}</span>` : ''}</div>
      <div class="m">${esc(v.email)} · ${esc(v.company)} · ${esc(memberName(v.agent))}${v.draft_waiting ? ` · ${pill('draft waiting', 'gold')}` : ''}</div></div>`).join('');
    case 'verifications': return it.map((v) => `<div class="mini"><div class="t">${esc(v.name || v.email)} ${pill(v.result === 'valid' ? 'valid' : v.result.replace('_', '-'), v.result === 'valid' ? 'ok' : v.result === 'invalid' ? 'bad' : 'warn')}</div>
      <div class="m">${esc(v.email)} · ${esc(v.company || '')} · ${esc(fmtDate(v.at))}</div></div>`).join('');
    case 'drafts': return it.map((x) => `<div class="mini clickable" data-open="company" data-id="${x.company_id}"><div class="t">${esc(x.company)} ${pill(sentence(x.status))}${x.edited ? ` ${pill('edited by you', 'info')}` : ''}</div>
      <div class="m">${esc([x.person, CH_LABEL[x.channel] || x.channel, x.subject].filter(Boolean).join(' · '))}${x.hold_reason ? ` · ${esc(x.hold_reason)}` : ''} · ${esc(shortDay(x.at))}</div></div>`).join('');
    case 'plans': return it.map((p) => `<div class="mini"><div class="t">${esc(shortDay(p.run_date))} · ${esc(p.touches)} touches</div><div class="m">${esc(p.email)} email · ${esc(p.linkedin)} LinkedIn · ${esc(p.instagram)} Instagram · ${esc(p.ready)} ready · ${esc(p.held)} held</div></div>`).join('');
    case 'actions': return it.map((x) => `<div class="mini"><div class="t">${esc(x.rank)}. ${esc(x.action)} · ${esc(x.company || '')}</div><div class="m">${esc(x.detail || '')}</div></div>`).join('');
    case 'replies': return it.map((x) => `<div class="mini clickable" data-open="company" data-id="${x.company_id}"><div class="t">${esc(x.person || x.company)}${x.person ? ` · <span class="faint">${esc(x.company)}</span>` : ''} ${x.classification ? pill(REPLY_GROUP[x.classification] || x.classification, 'info') : ''}</div><div class="m">${esc(x.subject || '')} · ${esc(fmtDate(x.received_at))}</div>${x.summary ? `<div class="m faint">${esc(x.summary)}</div>` : ''}</div>`).join('');
    case 'sent': return it.map((x) => `<div class="mini"><div class="t">${esc(x.person || x.company || '')}${x.person ? ` · <span class="faint">${esc(x.company)}</span>` : ''} ${pill(CH_LABEL[x.channel] || x.channel)}</div><div class="m">${esc(x.subject || x.summary || '')} · ${esc(fmtDate(x.sent_at))}</div></div>`).join('');
    case 'followups': return it.map((f) => `<div class="mini"><div class="t">${esc(f.person || f.company || '')} · follow-up ${esc(f.step)}</div><div class="m">${esc(f.company || '')} · ${esc(CH_LABEL[f.channel] || f.channel)} · ${f.overdue ? `<span class="bad-text">overdue since ${esc(shortDay(f.due_at))}</span>` : `due ${esc(shortDay(f.due_at))}`}</div></div>`).join('');
    case 'threads': return it.map((r) => `<div class="mini"><div class="t">${esc(r.key.replace(/^[a-z]:/, ''))}${r.suggested ? ` ${pill(sentence(r.suggested.replace(/_/g, ' ')), 'info')}` : ''}</div><div class="m">${esc(r.summary || '')}</div>${r.their_position ? `<div class="m faint">Their position: ${esc(r.their_position)}</div>` : ''}<div class="m faint">${r.last_at ? `last email ${esc(shortDay(r.last_at))} · ` : ''}${esc(r.basis || '')}</div></div>`).join('');
    case 'runs': return it.map((r) => `<div class="mini"><div class="t">${esc(fmtDate(r.at))} · ${esc(String(r.workflow || '').replace(/ v\d+$/, ''))}</div><div class="m">${n0(r.searches)} searches · ${n0(r.candidates)} candidates · ${n0(r.researched)} researched · ${n0(r.qualified)} qualified · ${n0(r.known_skipped)} already known</div></div>`).join('');
    default: return '';
  }
}
// Director drill-down: Overview · Opportunities · People · Emails · Outreach · Relationships · Projects. No workflow architecture.
const NOYA_HANDLES = { BRANDS: 'Locations, permits, crew and production support, talent, hospitality and logistics in Egypt', WEDDINGS: 'Venues, permits, guest travel and concierge, suppliers and on-the-ground delivery in Egypt',
  MEDIA: 'The Egypt concept, locations and access, permits, production support and hospitality', SPORTS: 'Private travel, security, stays and experiences in Egypt for their clients',
  TRAVEL: 'Egypt execution for their clients: they keep the client, NOYA delivers Egypt', HOSPITALITY: 'Client referrals one way, preferred stays and content collaborations the other',
  CORPORATE: 'Executive travel, client events and white-label concierge', PRIVATE: 'Private client introductions and Egypt programmes for members', EGYPT: 'Turning the Egypt signal into a commercial project' };
// Drop empty fragments a workflow wrote as "undefined" / "null" (e.g. 06's "Sales angle for 05: undefined"); the stored note is kept as evidence.
const cleanText = (t) => String(t || '').split('|').map((x) => x.trim()).filter((x) => x && !/(^|:\s*)(undefined|null)$/i.test(x) && !/^(undefined|null)\b/i.test(x)).join(' · ');
function oppFramed(o, dirKey) {
  const c = o.contact; const cc = o.concept;
  return `<article class="ofr clickable" data-open="company" data-id="${o.company_id}">
    <div class="ofr-t"><b>${esc(o.company)}</b> <span class="faint">· ${esc(projectName(o.project))}</span>${o.relationship && o.relationship !== 'COLD' ? ` <span class="ok-text small">${esc(REL_NAME[o.relationship] || '')}</span>` : ''}</div>
    <dl class="oc-dl">
      <dt>What they did</dt><dd>${esc(cleanText(plainText(o.trigger || o.why || '')) || '—')}</dd>
      ${cc ? `<dt>Concept</dt><dd>${esc(cc.concept)}</dd>${cc.backdrop ? `<dt>Why Egypt</dt><dd>${esc(cc.backdrop)}</dd>` : ''}` : `<dt>Why Egypt fits</dt><dd>${esc(cleanText(plainText(o.angle || '')) || '—')}</dd>`}
      <dt>Who decides</dt><dd>${c ? `${esc(c.name || '')}${c.role ? `, ${esc(c.role)}` : ''} ${estatePill(c.email_state)}${c.email && c.email_state === 'VALID_VERIFIED' ? ` <span class="faint">${esc(c.email)}</span>` : ''}` : '<span class="warn-text">Not identified yet</span>'}</dd>
      <dt>NOYA would handle</dt><dd>${esc(cc?.noya_role || o.value?.to_partner || NOYA_HANDLES[dirKey] || '—')}</dd>
      <dt>Next step</dt><dd><b>${esc(plainText(o.next_step || '—'))}</b></dd></dl></article>`;
}
const DIR_TABS = [['overview', 'Overview'], ['opportunities', 'Opportunities'], ['people', 'People'], ['emails', 'Emails'], ['outreach', 'Outreach'], ['relationships', 'Relationships'], ['projects', 'Projects']];
function viewDirector() {
  const D = state.directors; if (!D) { loadV3('directors', 'hq_directors'); return head('Agents') + waitFor('directors', 'the workforce'); }
  const m = D.members.find((x) => x.key === state.dirKey);
  if (!m) return `${head('Agents')}<p class="muted">Pick a Director on the Agents screen.</p>`;
  const det = state.dirDetail[m.key]; if (!det) loadDirector(m.key);
  const back = '<button class="btn small ghost" data-tab="agents">← All agents</button>';
  const top = `${back}<div class="director-top mt8">${directorCard(m)}<div class="dt-side"><div class="kv"><div class="k">Mission</div><div class="v">${esc(m.mission || '')}</div></div>
    ${m.scope ? `<div class="kv mt8"><div class="k">Scope</div><div class="v small">${esc(m.scope)}</div></div>` : ''}
    <div class="kv mt8"><div class="k">Last run · next run</div><div class="v small">${esc(rel(m.last_run))} · ${esc(m.next_run ? fmtDate(m.next_run) : 'runs with the Directors')}</div></div></div></div>`;
  if (!det) return `${top}<p class="muted">Loading ${esc(m.name)}…</p>`;
  if (det.error) return `${top}${unavailable(`director:${m.key}`)}`;
  if (det.growth) return top + growthBody(det.growth);
  const S = Object.fromEntries((det.sections || []).map((s) => [s.key, s]));
  const feed = (D.feed || []).filter((x) => x.agent === m.key);
  // Shared specialists keep their own sections; Directors get the seven commercial tabs.
  if (m.role === 'SUPPORT') {
    const secs = [...(det.sections || []), { key: 'activity', title: 'Recent activity', kind: 'feed', total: feed.length, items: feed }];
    const cur = secs.find((x) => x.key === state.dirSec[m.key]) || secs.find((x) => (x.total || 0) > 0) || secs[0];
    const shown = Array.isArray(cur.items) ? cur.items.length : 0;
    return `${top}${det.scorecard ? liScore(det.scorecard) : ''}<div class="tabs mt8">${secs.map((x) => `<button class="${x.key === cur.key ? 'on' : ''}" data-dir-sec="${x.key}">${esc(x.title)} <span class="n">${esc(x.total ?? shown)}</span></button>`).join('')}</div>
      <section class="panel"><header><h3>${esc(cur.title)}</h3><span class="small faint">${cur.total != null && cur.total > shown ? `showing the latest ${shown} of ${cur.total}` : `${cur.total ?? shown} in total`}</span></header>
        <div class="body">${cur.kind === 'feed' ? v3Feed(cur.items, 200) : (dSection(cur) || '<div class="empty">Nothing here yet.</div>')}</div></section>`;
  }
  const tab = DIR_TABS.find(([k]) => k === state.dirSec[m.key]) ? state.dirSec[m.key] : 'overview';
  const n = (k) => S[k]?.total ?? (Array.isArray(S[k]?.items) ? S[k].items.length : 0);
  const net = state.net || {}; const mine = (l) => (l || []).filter((x) => x.director === m.key);
  const rels = mine(net.important); const cold = mine(net.going_cold);
  const projects = Object.entries(state.ceo?.companies || {}).filter(([, v]) => v[0] === m.key && ['MEETING', 'CONCEPT_BRIEF', 'PROPOSAL', 'NEGOTIATION', 'WON', 'PROJECT_ACTIVE', 'COMPLETED'].includes(v[2]));
  const counts = { overview: '', opportunities: n('opportunities'), people: n('people'), emails: n('verified') + n('email_gaps'),
    outreach: n('needs_review') + n('approved') + n('researching') + n('held'), relationships: rels.length + cold.length, projects: projects.length };
  const sub = (s, empty) => (s ? `<section class="panel mt8"><header><h3>${esc(s.title)}</h3><span class="small faint">${s.total > (s.items || []).length ? `showing ${(s.items || []).length} of ${s.total}` : `${s.total ?? (s.items || []).length}`}</span></header><div class="body">${dSection(s) || `<div class="empty">${esc(empty)}</div>`}</div></section>` : '');
  const relRow = (x) => `<div class="t-row"><div><div class="t-main">${esc(x.company)}${x.who ? ` <span class="faint">· ${esc(x.who)}${x.role ? `, ${esc(x.role)}` : ''}</span>` : ''}</div>
    <div class="t-sub">${esc(REL_NAME[x.state] || x.state || '')}${x.last_at ? ` · last ${esc(shortDay(x.last_at))}` : ''} · ${esc(x.why || '')}</div>${x.next_action ? `<div class="t-sub"><b>Next:</b> ${esc(plainText(x.next_action))}</div>` : ''}</div>
    <div class="t-btns">${x.thread ? btnLink(`${GMAIL_THREAD_URL}${x.thread}`, 'Open thread', false) : ''}</div></div>`;
  let body = '';
  if (tab === 'overview') {
    const topOpps = (state.ceo?.top_opportunities || []).filter((o) => o.director === m.key);
    const opps = (S.opportunities?.items || []).slice(0, 4);
    body = `${topOpps.length ? `<section class="dsec"><header><h2>Live opportunities</h2></header><div class="ogrid">${topOpps.map(oppCard).join('')}</div></section>` : ''}
      <section class="dsec"><header><h2>Newest opportunities</h2><button class="btn small ghost" data-dir-sec="opportunities">All ${n('opportunities')}</button></header>${opps.map((o) => oppFramed(o, m.key)).join('') || '<div class="empty">No qualified opportunity yet.</div>'}</section>
      ${sub(S.finds && { ...S.finds, items: (S.finds.items || []).slice(0, 6) }, 'No new finds.')}`;
  } else if (tab === 'opportunities') body = `<section class="dsec"><header><h2>Opportunities · ${n('opportunities')}</h2><span class="faint small">Framed as projects: what they did, why Egypt, who decides, what NOYA would handle.</span></header>${(S.opportunities?.items || []).map((o) => oppFramed(o, m.key)).join('') || '<div class="empty">No qualified opportunity yet.</div>'}</section>`;
  else if (tab === 'people') body = sub(S.people, 'No decision makers found yet.');
  else if (tab === 'emails') body = `${emailLine(m.channel)}${sub(S.verified, 'No verified contact yet.')}${sub(S.email_gaps, 'No email gaps: every qualified company has a usable route or is being researched.')}`;
  else if (tab === 'outreach') body = `${sub(S.needs_review, 'Nothing waiting for you.')}${sub(S.approved, 'No Gmail drafts.')}${sub(S.researching, 'Nothing being researched.')}${sub(S.held, 'Nothing held.')}`;
  else if (tab === 'relationships') body = `<section class="panel mt8"><header><h3>Relationships · ${rels.length}</h3></header><div class="body">${rels.map(relRow).join('') || '<div class="empty">No two-way relationship yet for this Director.</div>'}</div></section>
      ${cold.length ? `<section class="panel mt8"><header><h3>Going cold · ${cold.length}</h3></header><div class="body">${cold.map(relRow).join('')}</div></section>` : ''}`;
  else body = `<section class="panel mt8"><header><h3>Projects and late-stage opportunities · ${projects.length}</h3></header><div class="body">${projects.map(([id, v]) => {
      const c = (state.dir?.companies || []).find((x) => x.id === id);
      return `<div class="t-row clickable" data-open="company" data-id="${id}"><div><div class="t-main">${esc(c?.name || 'Company')}</div><div class="t-sub">${esc(projectName(v[1]))} · ${esc(STAGE_NAME[v[2]] || v[2])}</div></div></div>`; }).join('')
      || '<div class="calm"><div class="calm-t">No project yet.</div><div class="t-sub">A company appears here from the meeting stage onward. Confirmed projects then move to Operations.</div></div>'}</div></section>`;
  return `${top}<div class="tabs mt8">${DIR_TABS.map(([k, l]) => `<button class="${tab === k ? 'on' : ''}" data-dir-sec="${k}">${l}${counts[k] !== '' ? ` <span class="n">${esc(counts[k])}</span>` : ''}</button>`).join('')}</div>${body}`;
}

function growthBody(g) {
  const c = g.connections || {}; const p = g.pipeline || {}; const paid = g.paid || {};
  const state2 = (s) => ({ PAUSED: ['Paused — plan limit', 'warn'], CONNECTED: ['Connected', 'ok'], NOT_CONNECTED_TO_HQ: ['Not connected to HQ', 'warn'], READ_PAUSED: ['Read-only · paused', 'warn'], READ_ONLY: ['Read-only', 'ok'] }[s] || [s, '']);
  const conn = (name, x) => `<div class="mini"><div class="t">${esc(name)} ${pill(...state2(x.state))}</div><div class="m">${esc(x.detail || '')}</div>${x.last_data ? `<div class="m faint">Latest data ${esc(fmtDate(x.last_data))}${x.last_spend_date ? ` · last spend recorded ${esc(shortDay(x.last_spend_date))}` : ''}</div>` : ''}</div>`;
  const steps = [['Idea', p.ideas], ['Draft', p.drafts], ['Review', null], ['Approved', p.approved], ['Metricool scheduled', p.scheduled], ['Published', p.published], ['Performance', (g.top_posts || []).length]];
  return `<section class="panel mt8"><header><h3>Connections</h3></header><div class="body">
      ${conn('Instagram @noyaconcierge (Windsor.ai)', c.instagram || {})}${conn('Metricool', c.metricool || {})}${conn('Meta Ads', c.meta_ads || {})}
      <p class="src">Recommends and prepares only. Never launches spend, raises budgets, boosts or publishes brand-sensitive content without Adam.</p></div></section>
    <section class="panel mt8"><header><h3>Content approval pipeline</h3></header><div class="body"><div class="loop">${steps.map(([l, n]) => `<span>${esc(l)}${n != null ? ` · ${esc(n)}` : ''}</span>`).join('')}</div>
      ${(g.content || []).length ? '' : '<div class="empty">No content items yet. Ideas move Idea → Draft → Review → Approved → Metricool scheduled → Published → Performance, and nothing reaches Metricool without your approval.</div>'}</div></section>
    <section class="panel mt8"><header><h3>Instagram performance · ${esc((g.top_posts || []).length)} posts analysed</h3></header><div class="body">
      ${(g.top_posts || []).slice(0, 8).map((x) => `<div class="mini"><div class="t">${esc(x.caption || x.category || 'Post')}</div><div class="m">${esc(shortDay(x.date))} · ${esc(String(x.type || '').toLowerCase().replace('carousel_album', 'carousel').replace('_', ' '))} · reach ${n0(x.reach)} · saves ${n0(x.saved)} · shares ${n0(x.shares)}${x.destination ? ` · ${esc(x.destination)}` : ''}</div></div>`).join('') || '<div class="empty">No Instagram performance stored.</div>'}</div></section>
    <section class="panel mt8"><header><h3>Paid media (read-only)</h3></header><div class="body">${paid.rows ? `<div class="m">${esc(paid.rows)} ad rows · ${esc(shortDay(paid.first_date))} – ${esc(shortDay(paid.last_date))} · spend ${esc(paid.spend)} · reach ${esc(paid.reach)} · clicks ${esc(paid.clicks)}</div>` : '<div class="empty">No paid-media data.</div>'}
      ${c.meta_ads?.state !== 'READ_ONLY' ? '<p class="src">META ADS: read access paused by the Windsor plan limit. No campaign can be launched or changed from HQ.</p>' : ''}</div></section>
    <section class="panel mt8"><header><h3>Media concepts · ${esc((g.concepts || []).length)}</h3></header><div class="body">${(g.concepts || []).map((x) => `<div class="mini"><div class="t">${esc(x.company || 'Concept')} ${pill(sentence(x.status || ''))}</div><div class="m">${esc(x.concept)}</div><div class="m faint">${esc(x.backdrop || '')}${x.noya_role ? ` · NOYA: ${esc(x.noya_role)}` : ''}</div></div>`).join('') || '<div class="empty">No concepts yet.</div>'}</div></section>
    <section class="panel mt8"><header><h3>Competitor patterns</h3></header><div class="body">${(g.competitor_patterns || []).map((x) => `<div class="mini"><div class="t">${esc(x.competitor)}</div><div class="m">${esc(x.hook || '')}</div><div class="m faint">${esc(sentence(x.action || x.why || ''))}</div></div>`).join('') || '<div class="empty">No competitor patterns stored.</div>'}</div></section>
    <section class="panel mt8"><header><h3>Leads attributed to content or ads · ${esc((g.attributed_leads || []).length)}</h3></header><div class="body">${(g.attributed_leads || []).map((x) => `<div class="mini"><div class="t">${esc(x.lead_type || 'Lead')} · ${esc(x.source || '')}</div><div class="m">${esc(x.campaign || '')} · confidence ${esc(x.confidence || '—')} · ${esc(shortDay(x.at))}</div></div>`).join('') || '<div class="empty">No lead has been attributed to content or ads yet.</div>'}
      ${g.test_leads_excluded ? `<p class="src">${esc(plural(g.test_leads_excluded, 'website go-live test enquiry is', 'website go-live test enquiries are'))} kept on record but not counted.</p>` : ''}</div></section>`;
}

// ---------------------------------------------------------------- OUTREACH: approve communication. Email first.
const DESK_TABS = [['TOP5', "Today's five"], ['NEEDS_REVIEW', 'Needs review'], ['LINKEDIN', 'LinkedIn'], ['APPROVED', 'Gmail drafts'], ['FOLLOWUPS', 'Follow-ups'], ['SENT', 'Sent'], ['REPLIED', 'Replied'], ['HELD', 'Researching / held']];
const DESK_PAGE = 25;
const PROJECT_FILTERS = [['', 'All projects'], ['BRAND', 'Brand shoot / campaign'], ['WEDDING', 'Wedding'], ['TRAVEL', 'Travel partner'], ['PRIVATE', 'NOYA Private'], ['MEDIA', 'Media / podcast'], ['HOSPITALITY', 'Hospitality partnership'], ['CORPORATE', 'Corporate / white-label']];
const projectGroup = (p) => (!p ? '' : /^(BRAND_SHOOT|FASHION_CAMPAIGN|JEWELLERY_CAMPAIGN|CREATOR_TRIP|PRESS_TRIP|BRAND_ACTIVATION|PRODUCT_LAUNCH|AUTOMOTIVE_SHOOT|CONTENT_PRODUCTION)$/.test(p) ? 'BRAND'
  : /WEDDING/.test(p) ? 'WEDDING' : p === 'TRAVEL_PARTNER' ? 'TRAVEL' : /^(NOYA_PRIVATE_AGENCY|PRIVATE_NETWORK|FOUNDER_RETREAT)$/.test(p) ? 'PRIVATE' : p === 'MEDIA_PRODUCTION' ? 'MEDIA'
    : /^(HOTEL_CONTENT_PARTNERSHIP|PREFERRED_STAY)$/.test(p) ? 'HOSPITALITY' : /CORPORATE|WHITE_LABEL/.test(p) ? 'CORPORATE' : '');
const deskItem = (ref) => { const D = state.desk || {}; return [...(D.needs_review || []), ...(D.held || []), ...(D.researching || [])].find((x) => x.ref === ref); };
function deskRoute(x) {
  const r = x.route || {};
  if (x.channel === 'EMAIL') return r.email ? `${esc(r.email)}${r.via_inbox ? ` <span class="faint">(${esc(r.inbox_label || 'company inbox')}, for ${esc(x.person || 'the named person')})</span>` : ''}` : '<span class="warn-text">no email</span>';
  if (x.channel === 'LINKEDIN') return r.linkedin ? `<a href="${esc(r.linkedin)}" target="_blank" rel="noopener noreferrer">LinkedIn profile</a>` : 'LinkedIn';
  if (x.channel === 'INSTAGRAM') { const ig = String(r.instagram || '').replace(/^@/, '').replace(/^https?:\/\/(www\.)?instagram\.com\//, '').replace(/\/$/, ''); return ig ? `<a href="https://instagram.com/${esc(ig)}" target="_blank" rel="noopener noreferrer">@${esc(ig)}</a>` : 'Instagram'; }
  return r.phone ? `official ${esc(r.phone)}` : esc(CH_LABEL[x.channel] || x.channel);
}
// Primary: Approve · Edit · Hold. Secondary (•••): Research more · Source · Reject. Approve creates an unsent Gmail draft; it never sends.
function deskButtons(x, readOnly) {
  if (readOnly) return `<button class="btn small" data-go="desk" data-desk-tab="${x.bucket === 'NEEDS_REVIEW' ? 'NEEDS_REVIEW' : x.bucket === 'RESEARCHING' ? 'HELD' : x.bucket}">Open on the desk</button>`;
  const ref = esc(x.ref); const b = []; const more = [];
  if (x.bucket === 'NEEDS_REVIEW') {
    if (x.approve_via === 'EMAIL_CANDIDATE' || x.approve_via === 'OPPORTUNITY_DRAFT') b.push(`<button class="btn small primary" data-desk-approve="${ref}" title="Re-checks the address, then creates an unsent Gmail draft. Never sends.">Approve</button>`);
    else if (x.approve_via === 'MANUAL_SEND') {
      // A LinkedIn item the LinkedIn agent holds uses the agent's message and its Mark sent (one record of the send).
      const li = x.channel === 'LINKEDIN' ? liOf(x) : null; const msg = li?.message || x.draft;
      const url = x.channel === 'LINKEDIN' ? (li?.linkedin || x.route?.linkedin) : null;
      // One step for a LinkedIn fallback: copy the message and open the profile; Adam sends it himself.
      if (msg && url) b.push(`<a class="btn small primary" href="${esc(url)}" target="_blank" rel="noopener noreferrer" data-copy="${esc(msg)}" title="Copies the message, then opens the profile">Copy & open LinkedIn</a>`);
      else if (msg) b.push(`<button class="btn small primary" data-copy="${esc(msg)}">Copy message</button>`);
      else if (url) b.push(`<a class="btn small" href="${esc(url)}" target="_blank" rel="noopener noreferrer">Open LinkedIn</a>`);
      if (li) b.push(`<button class="btn small" data-modal="li-sent" data-id="${li.id}" title="You sent it yourself: records the send and books one follow-up.">Mark sent</button>`);
      else if (x.task_id) b.push(`<button class="btn small" data-modal="task-done" data-id="${x.task_id}" data-title="${esc(`Sent to ${x.person || x.company || ''} on ${CH_LABEL[x.channel] || x.channel}`)}" title="You sent it yourself: logs the send and books follow-up 1 for 4 days later.">Mark sent</button>`);
    }
  }
  if (x.task_id && ['NEEDS_REVIEW', 'HELD'].includes(x.bucket)) {
    b.push(`<button class="btn small" data-desk-modal="edit" data-ref="${ref}">Edit</button>`);
    if (x.bucket === 'HELD' && x.status === 'WAITING') b.push(`<button class="btn small" data-desk-release="${ref}">Release</button>`);
    else if (x.bucket === 'NEEDS_REVIEW') b.push(`<button class="btn small" data-desk-modal="hold" data-ref="${ref}">Hold</button>`);
    more.push(`<button class="btn small" data-desk-modal="research" data-ref="${ref}">Research more</button>`);
  }
  more.push(`<button class="btn small" data-desk-src="${ref}">Source</button>`);
  if (x.task_id && ['NEEDS_REVIEW', 'HELD'].includes(x.bucket)) more.push(`<button class="btn small ghost" data-desk-modal="reject" data-ref="${ref}">Reject</button>`);
  const open = state.deskMore === x.ref;
  return `${b.join('')}<button class="btn small ghost dots" data-desk-more="${ref}" aria-label="More actions" aria-expanded="${open}">•••</button>${open ? `<span class="more-menu">${more.join('')}</span>` : ''}`;
}
function deskRow(x, readOnly = false) {
  const open = state.deskOpen[x.ref]; const src = state.deskSrc[x.ref]; const s = x.source || {}; const t = x.tech || {};
  const draft = String((x.channel === 'LINKEDIN' && liOf(x)?.message) || x.draft || ''); const preview = draft.replace(/\s+/g, ' ').slice(0, 170);
  const proj = coInfo(x.company_id)[1];
  const route = x.channel === 'EMAIL' ? `${deskRoute(x)} ${estatePill(x.route?.email_state)}` : `${esc(CH_LABEL[x.channel] || x.channel)} · ${deskRoute(x)}${x.fallback ? ` <span class="warn-text small">${esc(x.fallback.label)}</span>` : ''}`;
  return `<article class="drow" id="desk-${esc(x.ref)}">
    <div class="dr-top"><div class="dr-who"><b>${esc(x.person || x.company || '—')}</b>${x.role ? ` <span class="faint">· ${esc(x.role)}</span>` : ''}${x.person && x.company ? ` · <a class="clickable" data-open="company" data-id="${x.company_id}">${esc(x.company)}</a>` : ''}</div>
      <span class="dr-age" title="Prepared ${esc(fmtDate(x.created_at))}">${x.age_days != null ? `${esc(x.age_days)} d` : ''}</span></div>
    <div class="dr-meta">${esc(dirName(x.director))}${proj ? ` · ${esc(projectName(proj))}` : ''}${x.qa === 'FLAGGED' ? ' · <span class="warn-text">quality flag</span>' : ''}</div>
    <div class="dr-line"><span>${x.channel !== 'EMAIL' ? 'Route' : x.route?.email_state === 'OFFICIAL_PUBLISHED_INBOX' ? 'Official inbox' : 'Verified email'}</span>${route}</div>
    ${x.reason ? `<div class="dr-line warn-text">${esc(x.reason)}</div>` : ''}
    ${x.angle ? `<div class="dr-line"><span>Why them</span>${esc(plainText(x.angle).replace(/^Partnership model \(recorded\):\s*/i, ''))}</div>` : ''}
    ${x.why_now ? `<div class="dr-line"><span>Why now</span>${esc(plainText(x.why_now))}</div>` : ''}
    ${x.fallback?.evidence ? `<div class="dr-line"><span>Email checked</span>${esc(x.fallback.evidence)}</div>` : ''}
    ${draft ? `<div class="dr-msg">${x.subject ? `<b>${esc(x.subject)}</b> — ` : ''}<span class="faint">${esc(preview)}${draft.length > 170 ? '…' : ''}</span> <button class="linkish" data-desk-open="${esc(x.ref)}">${open ? 'Hide' : 'Read'}</button></div>` : ''}
    ${open ? `<div class="draft-box"><pre>${esc(draft)}</pre>${x.original_draft ? `<details><summary>Original draft (kept)</summary><pre>${esc(x.original_draft)}</pre></details>` : ''}</div>` : ''}
    <div class="dr-act btn-row">${deskButtons(x, readOnly)}</div>
    ${src ? `<div class="dr-src small">Person: ${s.person ? `<a href="${esc(s.person)}" target="_blank" rel="noopener noreferrer">${esc(s.person.replace(/^https?:\/\//, '').slice(0, 60))}</a>` : 'source not recorded'} · identity ${esc(String(s.identity || 'unknown').toLowerCase().replace('_', ' '))}${x.channel === 'EMAIL' ? ` · email ${s.email ? `<a href="${esc(s.email)}" target="_blank" rel="noopener noreferrer">${esc(s.email.replace(/^https?:\/\//, '').slice(0, 60))}</a>` : x.route?.email_state === 'VALID_VERIFIED' ? 'verified by the verification provider' : 'source not recorded'}` : ''}</div>
      <details class="tech"><summary>Technical details</summary><div class="small faint">${esc([t.title, t.task_type, t.created_by, t.candidate_status, t.hold_reason, x.approve_via].filter(Boolean).join(' · '))}</div></details>` : ''}
  </article>`;
}
function approvedRow(x) {
  const st = x.gmail_confirmed ? `<a class="btn small primary" href="${esc(x.gmail_url)}" target="_blank" rel="noopener noreferrer">Open in Gmail</a>`
    : x.status === 'FAILED' ? `<span class="bad-text small">Gmail draft failed</span> ${x.can_retry ? `<button class="btn small" data-act="redispatch" data-id="${x.outbound_id}">Retry</button>` : ''}`
      : x.status === 'DISCARDED' ? '<span class="small faint">Draft discarded in Gmail</span>' : x.status === 'SENT' ? '<span class="small">Sent</span>'
        : `<span class="small faint">Creating the Gmail draft…</span>${x.can_retry ? ` <button class="btn small" data-act="redispatch" data-id="${x.outbound_id}">Retry</button>` : ''}`;
  return `<div class="t-row"><div><div class="t-main">${esc(x.person || x.to_email)} · <span class="faint">${esc(x.company || '')}</span></div>
    <div class="t-sub">${esc(x.to_email)} · ${esc(x.subject || '')} · approved ${esc(shortDay(x.approved_at))}${x.director ? ` · ${esc(dirName(x.director))}` : ''}${x.error && x.status === 'FAILED' ? ` · ${esc(String(x.error).slice(0, 100))}` : ''}</div></div><div class="t-btns">${st}</div></div>`;
}
// ---------------------------------------------------------------- LINKEDIN RELATIONSHIP AGENT (Adam, 19 Oct): relationships and meetings, never mass automation
// One queue (linkedin_actions), read with the desk. Copy & open LinkedIn copies the text and opens the profile; Adam sends it himself and
// presses Mark sent. A reply is what Adam pastes, never guessed from a notification. HQ never logs in to LinkedIn and never sends.
const LI_STATE = { READY: ['Ready to send', 'gold'], CONNECTION_SENT: ['Connection request sent', ''], CONNECTED: ['Connected · follow-up ready', 'gold'], SENT: ['Sent · waiting for a reply', ''],
  REPLIED: ['Replied', 'ok'], MEETING: ['Meeting', 'ok'], HELD: ['Held', 'warn'], CLOSED: ['Closed', ''] };
const LI_CLASSES = [['POSITIVE', 'Positive'], ['QUESTION', 'Question'], ['INFO_REQUEST', 'Info request'], ['MEETING_INTENT', 'Meeting intent'], ['INTRODUCTION', 'Introduction'],
  ['NOT_NOW', 'Not now'], ['SOFT_NO', 'Soft no'], ['DECLINED', 'Declined']];
const LI_SECTIONS = [['REPLIED', 'Replies to answer'], ['CONNECTED', 'Connected: follow-up ready'], ['READY', 'Ready for you to send'], ['CONNECTION_SENT', 'Connection requests waiting for acceptance'],
  ['SENT', 'Sent, waiting for a reply'], ['MEETING', 'Meetings'], ['HELD', 'Held'], ['CLOSED', 'Closed']];
const liClass = (k) => (LI_CLASSES.find(([c]) => c === k) || [k, sentence(String(k || '').replace(/_/g, ' '))])[1];
const liAll = () => [...(state.desk?.linkedin || []), ...((state.dirDetail?.LINKEDIN?.sections || []).flatMap((x) => x.items || []))];
const liItem = (id) => liAll().find((a) => a.id === id);
const liOf = (x) => (state.desk?.linkedin || []).find((a) => (x.task_id && a.task_id === x.task_id) || (x.contact_id && a.contact_id === x.contact_id && a.opportunity_id === x.opportunity_id));
const liWords = (t) => String(t || '').trim().split(/\s+/).filter(Boolean).length;
const liCopyOpen = (text, url, label, primary = true) => (!text ? '' : url
  ? `<a class="btn small ${primary ? 'primary' : ''}" href="${esc(url)}" target="_blank" rel="noopener noreferrer" data-copy="${esc(text)}" title="Copies the text, then opens their LinkedIn profile. You send it yourself.">${esc(label)}</a>`
  : `<button class="btn small ${primary ? 'primary' : ''}" data-copy="${esc(text)}" title="No profile link on record: copies the text only">${esc(label.replace(' & open LinkedIn', '').replace(' & open', ''))}</button>`);
const ukSlot = (iso) => { const p = Object.fromEntries(new Intl.DateTimeFormat('en-GB', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'Europe/London' })
  .formatToParts(new Date(iso)).map((x) => [x.type, x.value])); return `${p.weekday} ${p.day} ${p.month} ${p.hour}:${p.minute}`; };
const slotText = (slots) => `${(slots || []).map((x) => ukSlot(x.start)).join(' or ')} (UK)`;
function liRow(a) {
  const [sl, sc] = LI_STATE[a.state] || [a.state, ''];
  const act = (k, label, primary = false) => `<button class="btn small ${primary ? 'primary' : ''}" data-li-act="${k}" data-id="${a.id}">${label}</button>`;
  const mod = (kind, label, type = '', primary = false) => `<button class="btn small ${primary ? 'primary' : ''}" data-modal="${kind}" data-id="${a.id}"${type ? ` data-type="${type}"` : ''}>${label}</button>`;
  const b = [];
  if (a.state === 'READY') {
    b.push(liCopyOpen(a.message, a.linkedin, 'Copy & open LinkedIn') || mod('li-edit', 'Write the message', 'MESSAGE', true), mod('li-edit', 'Edit', 'MESSAGE'), mod('li-sent', 'Mark sent'), mod('li-hold', 'Hold'));
  } else if (a.state === 'CONNECTION_SENT') b.push(act('CONNECTED', 'Connected', true), mod('li-edit', 'Edit follow-up', 'FOLLOWUP'), mod('li-hold', 'Hold'));
  else if (a.state === 'CONNECTED') b.push(liCopyOpen(a.followup || a.message, a.linkedin, 'Copy follow-up & open LinkedIn'), mod('li-edit', 'Edit follow-up', 'FOLLOWUP'), mod('li-sent', 'Mark sent'));
  else if (a.state === 'SENT') b.push(mod('li-reply', 'Log reply', '', true), mod('li-hold', 'Hold'));
  else if (a.state === 'REPLIED') b.push(a.reply_class === 'MEETING_INTENT' && a.meeting_task_id ? `<button class="btn small primary" data-modal="meet-confirm" data-id="${a.meeting_task_id}">Confirm meeting</button>` : '',
    liCopyOpen(a.response_draft, a.linkedin, 'Copy response & open LinkedIn', a.reply_class !== 'MEETING_INTENT'), mod('li-reply', 'Log another reply'));
  else if (a.state === 'HELD') b.push(act('RELEASE', 'Release', true), act('CLOSE', 'Close'));
  const connected = a.li_connected || a.connection === 'CONNECTED';
  const conn = a.state === 'READY' && connected ? '<div class="dr-line li-conn"><span>Connected</span>Already a 1st-degree connection: message them directly, no connection request needed.</div>'
    : a.state === 'READY' ? `<div class="dr-line li-conn"><span>Not connected?</span>${a.connection_note
    ? `${liCopyOpen(a.connection_note, a.linkedin, 'Copy note & open', false)}${act('CONNECTION_SENT', 'Connection sent')}${mod('li-edit', 'Edit note', 'NOTE')} <span class="faint small">${String(a.connection_note).length}/300 · the follow-up is sent after they accept</span>`
    : `${mod('li-edit', 'Write a connection note', 'NOTE')} <span class="faint small">LinkedIn notes are up to 300 characters</span>`}</div>` : '';
  const text = a.state === 'CONNECTED' || a.state === 'CONNECTION_SENT' ? (a.followup || a.message) : a.message;
  return `<article class="drow li-row" id="li-${esc(a.id)}">
    <div class="dr-top"><div class="dr-who"><b>${esc(a.person || '—')}</b>${a.role ? ` <span class="faint">· ${esc(a.role)}</span>` : ''}${a.company ? ` · <a class="clickable" data-open="company" data-id="${a.company_id}">${esc(a.company)}</a>` : ''}</div>
      ${pill(sl, sc)}</div>
    <div class="dr-meta">${esc(dirName(a.director))}${a.relationship ? ` · ${esc(REL_NAME[a.relationship] || sentence(String(a.relationship).replace(/_/g, ' ')))}` : ''} · ${a.linkedin ? `<a href="${esc(a.linkedin)}" target="_blank" rel="noopener noreferrer">LinkedIn profile</a>` : '<span class="warn-text">no LinkedIn profile on record</span>'}</div>
    ${a.project ? `<div class="dr-line"><span>Project</span>${esc(plainText(a.project))}</div>` : ''}
    ${a.why_them ? `<div class="dr-line"><span>Why them</span>${esc(plainText(a.why_them).replace(/^Partnership model \(recorded\):\s*/i, ''))}</div>` : ''}
    ${a.why_now ? `<div class="dr-line"><span>Why now</span>${esc(plainText(a.why_now))}</div>` : ''}
    ${a.li_state && a.li_state !== 'CONNECTED' ? `<div class="dr-line li-hist"><span>LinkedIn history</span>${liRel(a.li_state)} ${esc(a.li_reason || '')}${a.li_last_at && Date.now() - new Date(a.li_last_at) > 365 * 864e5 ? ' <span class="warn-text">· old conversation: reopen personally, not a live lead</span>' : ''}</div>` : ''}
    ${a.state === 'REPLIED' || a.reply_text ? `<div class="dr-line li-reply"><span>They replied${a.reply_class ? ` · ${esc(liClass(a.reply_class))}` : ''}</span>${esc(a.reply_text || '')}</div>` : ''}
    ${a.state === 'REPLIED' && a.response_draft ? `<div class="dr-msg"><span class="faint">Suggested response:</span> ${esc(a.response_draft)}</div>`
      : text ? `<div class="dr-msg">${esc(text)} <span class="faint small">· ${liWords(text)} words</span></div>` : '<div class="dr-msg warn-text">No message written yet.</div>'}
    ${a.next_action ? `<div class="dr-line"><span>Next</span>${esc(a.next_action)}</div>` : ''}${conn}
    <div class="dr-act btn-row">${b.filter(Boolean).join('')}</div>
  </article>`;
}
function liScore(c) {
  if (!c) return '';
  const cell = (n, l) => `<div class="dc-c"><b>${n0(n)}</b><span>${l}</span></div>`;
  const rev = (c.revenue || []).length ? `<div class="dc-c"><b>${esc(c.revenue.map((r) => cash(r.amount, r.currency)).join(' + '))}</b><span>revenue</span></div>` : cell(0, 'revenue');
  return `<section class="panel mt8"><header><h3>Scorecard</h3><span class="small faint">what actually happened on LinkedIn</span></header><div class="body"><div class="dc-cells">
    ${cell(c.sent, 'messages sent')}${cell(c.replies, 'replies')}${cell(c.positive, 'positive')}${cell(c.meetings, 'meetings')}${cell(c.introductions, 'introductions')}${cell(c.briefs, 'briefs')}${cell(c.proposals, 'proposals')}${cell(c.wins, 'wins')}${rev}</div>
    <p class="src">${esc(c.note || '')}</p></div></section>`;
}
function viewDesk() {
  const D = state.desk; if (!D) return head('Outreach') + waitFor('desk', 'the outreach desk');
  const c = D.counts; const t = DESK_TABS.some(([k]) => k === state.deskTab) ? state.deskTab : (state.deskTab === 'RESEARCHING' ? 'HELD' : 'NEEDS_REVIEW');
  const L = D.linkedin || [];
  const n = { TOP5: (D.top5 || []).length, NEEDS_REVIEW: c.needs_review.total, LINKEDIN: L.filter((a) => !['CLOSED', 'MEETING'].includes(a.state)).length, APPROVED: c.approved, FOLLOWUPS: c.followups, SENT: c.sent, REPLIED: c.replied, HELD: c.held + c.rejected + c.researching };
  const filt = (list, withCh) => {
    let l = list;
    if (state.deskDir) l = l.filter((x) => x.director === state.deskDir);
    if (state.deskProj) l = l.filter((x) => projectGroup(coInfo(x.company_id)[1]) === state.deskProj);
    if (withCh && state.deskCh) l = l.filter((x) => (x.channel || 'EMAIL') === state.deskCh);
    return l;
  };
  const base = { NEEDS_REVIEW: D.needs_review, APPROVED: D.approved, FOLLOWUPS: D.followups, SENT: D.sent, REPLIED: D.replied, HELD: [...D.researching, ...D.held] }[t] || [];
  const dirs = [...new Set(base.map((x) => x.director).filter(Boolean))];
  const pre = filt(base, false); const chCount = (ch) => pre.filter((x) => (x.channel || 'EMAIL') === ch).length;
  const hasCh = ['NEEDS_REVIEW', 'FOLLOWUPS', 'SENT', 'REPLIED', 'HELD'].includes(t);
  const list = filt(base, hasCh);
  const filters = `<div class="filters">
    ${hasCh ? `<div class="seg">${[['EMAIL', 'Email'], ['LINKEDIN', 'LinkedIn'], ['INSTAGRAM', 'Instagram'], ['', 'All']].map(([k, l]) => `<button class="${state.deskCh === k ? 'on' : ''}" data-desk-ch="${k}">${l} <span class="n">${k ? chCount(k) : pre.length}</span></button>`).join('')}</div>` : ''}
    <select class="w-auto" data-desk-dir><option value="">All Directors</option>${dirs.map((k) => `<option value="${k}" ${state.deskDir === k ? 'selected' : ''}>${esc(dirName(k))}</option>`).join('')}</select>
    <select class="w-auto" data-desk-proj>${PROJECT_FILTERS.map(([k, l]) => `<option value="${k}" ${state.deskProj === k ? 'selected' : ''}>${l}</option>`).join('')}</select></div>`;
  let body = '';
  if (t === 'TOP5') {
    const top = (D.top5 || []).map((p, i) => { const x = deskItem(p.ref); if (!x) return ''; const a = x.channel === 'LINKEDIN' ? liOf(x) : null;
      return `<div class="t5"><div class="t5-h"><span class="t5-n">${i + 1}</span><span class="small">${esc(p.why)}</span></div>${a ? liRow(a) : deskRow(x)}</div>`; }).join('');
    const rest = Math.max(0, c.needs_review.total - (D.top5 || []).length);
    body = `<div class="dlist">${top || '<div class="calm"><div class="calm-t">Nothing strong enough today.</div><div class="t-sub">Fewer is fine: replies, meetings and follow-ups come first.</div></div>'}</div>
      ${rest ? `<p class="src">${plural(rest, 'more item waits', 'more items wait')} under <button class="linkish" data-desk-tab="NEEDS_REVIEW">Needs review</button>. They are not lost; they are simply not today's best five.</p>` : ''}`;
  } else if (t === 'LINKEDIN') {
    body = LI_SECTIONS.map(([st, l]) => { const it = L.filter((a) => a.state === st); return it.length ? `<h3 class="grp">${esc(l)} · ${it.length}</h3><div class="dlist">${it.map(liRow).join('')}</div>` : ''; }).join('')
      || '<div class="empty">No LinkedIn item yet. Items arrive when email is exhausted for a strong person, or when a relationship is better on LinkedIn.</div>';
  } else if (['NEEDS_REVIEW', 'HELD'].includes(t)) {
    const pages = Math.max(1, Math.ceil(list.length / DESK_PAGE)); const pg = Math.min(state.deskPage, pages - 1);
    const shown = list.slice(pg * DESK_PAGE, pg * DESK_PAGE + DESK_PAGE);
    const pager = list.length > DESK_PAGE ? `<div class="pager"><span class="small">Showing ${pg * DESK_PAGE + 1}–${pg * DESK_PAGE + shown.length} of ${list.length}</span><span><button class="btn small ghost" data-desk-page="-1" ${pg === 0 ? 'disabled' : ''}>Previous</button><button class="btn small ghost" data-desk-page="1" ${pg >= pages - 1 ? 'disabled' : ''}>Next</button></span></div>` : '';
    const emptyEmail = t === 'NEEDS_REVIEW' && state.deskCh === 'EMAIL' && !shown.length
      ? `<div class="calm"><div class="calm-t">No new email waiting for review.</div><div class="t-sub">New verified emails arrive after the nightly drafting run.${qaHeld().length ? ` ${plural(qaHeld().length, 'verified email draft', 'verified email drafts')} failed the quality check and wait for your edit.` : ''} ${chCount('LINKEDIN') ? `${chCount('LINKEDIN')} LinkedIn fallbacks are under LinkedIn.` : ''}</div>
        ${qaHeld().length ? '<div class="btn-row mt8 center"><button class="btn small primary" data-desk-tab="HELD">Edit the email drafts</button></div>' : ''}</div>` : '';
    body = `${pager}<div class="dlist">${shown.map((x) => deskRow(x)).join('') || emptyEmail || '<div class="empty">Nothing here.</div>'}</div>${shown.length > 4 ? pager : ''}
      ${t === 'HELD' && D.rejected.length ? `<h3>Rejected · ${D.rejected.length}</h3><div class="dlist">${D.rejected.map((x) => `<div class="t-row"><div><div class="t-main">${esc(x.person || x.company)}${x.person ? ` · <span class="faint">${esc(x.company)}</span>` : ''}</div><div class="t-sub">${esc(CH_LABEL[x.channel] || x.channel || '')} · ${esc(x.reason || '')} · rejected ${esc(shortDay(x.rejected_at))}${x.held_until ? ` · not rediscovered until ${esc(shortDay(x.held_until))}` : ''}</div></div></div>`).join('')}</div>` : ''}`;
  } else if (t === 'APPROVED') body = `<div class="dlist">${list.map(approvedRow).join('') || '<div class="empty">Nothing approved yet. Approve an email under Needs review: HQ re-checks the address and creates one unsent Gmail draft.</div>'}</div>`;
  else if (t === 'FOLLOWUPS') body = `<div class="dlist">${list.map((f) => `<div class="t-row"><div><div class="t-main">${esc(f.person || f.company || '')}${f.person ? ` · <span class="faint">${esc(f.company || '')}</span>` : ''} · follow-up ${esc(f.step)}</div>
      <div class="t-sub">${esc(CH_LABEL[f.channel] || f.channel)} · ${f.overdue ? `<span class="bad-text">overdue since ${esc(shortDay(f.due_at))}</span>` : `due ${esc(shortDay(f.due_at))}`}${f.director ? ` · ${esc(dirName(f.director))}` : ''}${f.thread_id ? ` · ${gmailLink(f.thread_id, 'thread')}` : ''}</div></div>
      <div class="t-btns"><button class="btn small primary" data-modal="task-done" data-id="${f.task_id}" data-title="${esc(`Follow-up ${f.step} — ${f.person || f.company || ''}`)}">Followed up</button><button class="btn small" data-modal="task-snooze" data-id="${f.task_id}" data-title="${esc(`Follow-up ${f.step} — ${f.person || f.company || ''}`)}">Snooze</button><button class="btn small ghost" data-modal="task-dismiss" data-id="${f.task_id}">Not needed</button></div></div>`).join('') || '<div class="empty">No follow-ups open.</div>'}</div>
      <p class="src">Follow-up 1 is due 4 days after the real send; follow-up 2 six days after follow-up 1 is sent; never more than two. A reply, meeting, proposal, decline or do-not-contact cancels them automatically.</p>`;
  else if (t === 'SENT') body = `<div class="dlist">${list.map((x) => `<div class="t-row"><div><div class="t-main">${esc(x.person || x.company || '')}${x.person ? ` · <span class="faint">${esc(x.company || '')}</span>` : ''}</div><div class="t-sub">${esc(CH_LABEL[x.channel] || x.channel)} · ${esc(x.subject || x.summary || '')} · ${esc(fmtDate(x.sent_at))}</div></div></div>`).join('') || '<div class="empty">Nothing sent in the last 60 days.</div>'}</div>`;
  else if (t === 'REPLIED') body = `<div class="dlist">${list.map((x) => `<div class="t-row clickable" ${x.company_id ? `data-open="company" data-id="${x.company_id}"` : ''}><div><div class="t-main">${esc(x.person || x.company || '')}${x.person ? ` · <span class="faint">${esc(x.company || '')}</span>` : ''}${x.classification ? ` · ${esc(REPLY_GROUP[x.classification] || x.classification)}` : ''}</div><div class="t-sub">${esc(x.summary || x.subject || '')} · ${esc(fmtDate(x.received_at))}</div></div></div>`).join('') || '<div class="empty">No replies in the last 60 days.</div>'}</div>`;
  const intro = { TOP5: "The five strongest new conversations today, ranked by project potential, relationship warmth, timing, the decision maker, the Egypt opportunity and repeat business. At most two per Director; accounts you put on hold are left out. Nothing is sent automatically.",
    LINKEDIN: 'Relationship messages, never mass outreach. Copy & open LinkedIn copies the message and opens their profile: you send it yourself, then press Mark sent. When they reply, paste what they wrote with Log reply. HQ never logs in to LinkedIn and never sends.',
    NEEDS_REVIEW: 'Approve re-checks the address and creates one unsent Gmail draft. LinkedIn and Instagram are sent by you, then marked sent. Nothing is ever sent automatically.',
    HELD: 'Not ready yet: the person, role or a verified route is missing, you held it, or a draft failed the quality check. The agents keep working on these.' }[t];
  return `${head('Outreach', 'Approve communication · email first')}
    <div class="tabs">${DESK_TABS.map(([k, l]) => `<button data-desk-tab="${k}" class="${t === k ? 'on' : ''}">${l} <span class="n">${esc(n[k])}</span></button>`).join('')}</div>
    ${['TOP5', 'LINKEDIN'].includes(t) ? '' : filters}${intro ? `<p class="muted small">${esc(intro)}</p>` : ''}${body}`;
}

function deskModal(m) {
  const x = deskItem(m.ref) || {};
  const who = `${esc(x.person || x.company || '')}${x.person ? ` · ${esc(x.company || '')}` : ''}`;
  const today = todayKey();
  const forms = {
    edit: ['Edit the message', `${x.channel === 'EMAIL' ? `<label class="field"><span>Subject</span><input id="d-subject" maxlength="200" value="${esc(x.subject || '')}"></label>` : ''}
      <label class="field"><span>Message</span><textarea id="d-body">${esc(x.draft || '')}</textarea></label><p class="src">The system's original draft is kept for the record.</p>`],
    hold: ['Hold', `<label class="field"><span>Why</span><input id="d-reason" placeholder="e.g. wait for their launch"></label><label class="field"><span>Review on</span><input id="d-until" type="date" min="${today}" value="${isoPlus(7)}"></label>`],
    research: ['Research more', `<label class="field"><span>What is wrong</span><select id="d-code"><option value="WRONG_PERSON">Wrong person</option><option value="OUTDATED_ROLE">Role out of date</option><option value="NEED_VERIFIED_EMAIL">Needs a verified email</option><option value="WEAK_REASON">Reason to contact is weak</option><option value="OTHER">Other</option></select></label>
      <label class="field"><span>Note</span><input id="d-reason" placeholder="optional"></label><p class="src">The company goes back to the research agents. No duplicate is created.</p>`],
    reject: ['Reject', `<label class="field"><span>Reason (required)</span><input id="d-reason" placeholder="e.g. not a fit, mass-market"></label><p class="src">The company is held from outreach for 180 days so the agents do not rediscover it.</p>`],
  }[m.form];
  return `<div class="modal-bg"><div class="modal"><h3>${esc(forms[0])}</h3><p class="small">${who}</p>${forms[1]}
    <div class="btn-row mt8"><button class="btn primary" id="dm-ok">${esc(forms[0] === 'Edit the message' ? 'Save' : forms[0])}</button><button class="btn ghost" data-close>Cancel</button></div></div></div>`;
}
async function submitDeskModal() {
  const m = state.modal; const x = deskItem(m.ref); if (!x) { state.modal = null; render(); return; }
  const v = (id) => ($(`#${id}`)?.value || '').trim();
  const err = (msg) => { const el = $('.modal'); let p = el.querySelector('.m-err'); if (!p) { p = document.createElement('p'); p.className = 'm-err banner err small'; el.insertBefore(p, el.querySelector('.btn-row')); } p.textContent = msg; };
  if (m.form === 'edit') {
    const body = $('#d-body').value; if (!body.trim()) return err('The message is empty.');
    state.modal = null;
    if (x.approve_via === 'OPPORTUNITY_DRAFT') return call('hq_save_draft', { p_opportunity_id: x.opportunity_id, p_subject: v('d-subject') || x.subject, p_body: body, p_note: 'Edited on the outreach desk' }, 'Saved. The original draft is kept.');
    return call('hq_outreach_edit', { p_task: x.task_id, p_subject: v('d-subject') || null, p_body: body }, 'Saved. The original draft is kept.');
  }
  if (m.form === 'hold') { state.modal = null; return call('hq_outreach_action', { p_task: x.task_id, p_action: 'HOLD', p_reason: v('d-reason') || null, p_until: v('d-until') || null }, 'Held. It returns to review on the date you chose.'); }
  if (m.form === 'research') { const note = v('d-reason'); state.modal = null; return call('hq_outreach_action', { p_task: x.task_id, p_action: 'RESEARCH', p_reason: `${v('d-code')}${note ? `: ${note}` : ''}`, p_until: null }, 'Sent back to the research agents.'); }
  if (m.form === 'reject') { const r = v('d-reason'); if (!r) return err('A reason is required.'); state.modal = null; return call('hq_outreach_action', { p_task: x.task_id, p_action: 'REJECT', p_reason: r, p_until: null }, 'Rejected. The company will not be rediscovered for 180 days.'); }
  return null;
}

// ---------------------------------------------------------------- RELATIONSHIPS: build the network
// Ranked by what a relationship can repeatedly create (one agency with 30 players matters more than 30 names).
const REL_TABS = [['IMPORTANT', 'Important people'], ['COMPANIES', 'Companies'], ['WARM', 'Warm relationships'], ['PIPELINE', 'Pipeline'], ['OPPORTUNITIES', 'Opportunities'], ['COLD', 'Going cold']];
const stripH2 = (html) => String(html).replace(/^\s*<h2>[\s\S]*?<\/h2>/, '');
function netRow(x) {
  const o = x.opportunity;
  return `<div class="nrow ${x.multiplier ? 'mult' : ''}">
    <div class="nr-main"><div class="nr-who"><b>${esc(x.who || x.company)}</b>${x.who ? ` <span class="faint">· ${x.role ? `${esc(x.role)}, ` : ''}${x.company_id ? `<a class="clickable" data-open="company" data-id="${x.company_id}">${esc(x.company)}</a>` : esc(x.company)}</span>` : ''}</div>
      <div class="nr-why">${x.multiplier ? '<span class="mult-tag">Multiplier</span> ' : ''}${esc(x.why || '')}</div>
      <div class="nr-facts">${esc(x.state === 'COLD' && x.last_at ? 'Earlier email history, no current sequence' : REL_NAME[x.state] || sentence(String(x.state || '').replace(/_/g, ' ')))}${x.last_at ? ` · last interaction ${esc(shortDay(x.last_at))}${['THEY_WROTE_LAST', 'WAITING_FOR_THEM'].includes(x.state) ? '' : x.last_dir === 'OUTBOUND' ? ' (NOYA wrote last)' : x.last_dir === 'INBOUND' ? ' (they wrote last)' : ''}` : ''}${o ? ` · ${esc(projectName(o.project))}, ${esc(S(o.status).toLowerCase())}` : ''}${x.director ? ` · ${esc(dirName(x.director))}` : ''} · owner ${esc(x.owner || 'Adam')}</div>
      ${x.next_action ? `<div class="nr-next"><b>Next:</b> ${esc(plainText(x.next_action))}</div>` : x.going_cold ? '<div class="nr-next warn-text">No next step: a short personal note keeps it warm.</div>' : ''}</div>
    <div class="t-btns">${x.thread ? btnLink(`${GMAIL_THREAD_URL}${x.thread}`, 'Open thread', false) : ''}${x.company_id ? `<button class="btn small" data-open="company" data-id="${x.company_id}">Record</button>` : ''}</div></div>`;
}
function viewRelations(d) {
  const t = REL_TABS.some(([k]) => k === state.relTab) ? state.relTab : 'IMPORTANT'; const N = state.net; let body = '';
  if (t === 'IMPORTANT') {
    body = !N ? waitFor('net', 'the network') : `<p class="muted small">${n0(N.counts?.relationships)} two-way relationships · ${n0(N.counts?.in_conversation)} active in the last 30 days · ${n0(N.counts?.multipliers)} that can repeatedly create clients, referrals or projects.</p>
      <div class="dlist">${(N.important || []).map(netRow).join('') || '<div class="empty">No two-way relationship yet.</div>'}</div>`;
  } else if (t === 'COLD') {
    body = !N ? waitFor('net', 'the network') : `<p class="muted small">Real two-way relationships with no interaction for 30+ days and no next step. Restart them personally, never with a cold introduction.</p>
      <div class="dlist">${(N.going_cold || []).map((x) => netRow({ ...x, going_cold: true })).join('') || '<div class="empty">Nothing is going cold.</div>'}</div>`;
  } else if (t === 'COMPANIES') body = stripH2(viewCompanies());
  else if (t === 'WARM') {
    const w = warmOpportunities(100);
    body = `<p class="muted small">Existing relationships with real evidence: NOYA Gmail threads, CRM records, matched LinkedIn connections. Use the relationship, never a cold introduction.</p>
      <div class="dlist">${w.map((x) => `<div class="t-row"><div><div class="t-main">${esc(x.name)} ${x.st === 'LINKEDIN' ? pill('LinkedIn', 'info') : x.mine ? pill(`You: ${REL_STATUS[x.st][0]}`, REL_STATUS[x.st][1]) : pill(`Suggested: ${REL_STATUS[x.st][0]}`)}</div>
        <div class="t-sub">${esc(x.facts.join(' · '))}</div>${x.why ? `<div class="t-sub faint">${esc(x.why)}</div>` : ''}</div>
        <div class="t-btns">${x.thread ? gmailLink(x.thread, 'Open in Gmail').replace('<a ', '<a class="btn small" ') : ''}${x.conn ? `<button class="btn small" data-open="connection" data-id="${x.conn}">Open</button>` : `<button class="btn small" data-relq="${esc(x.name)}">Review</button>`}</div></div>`).join('') || '<div class="empty">No warm relationship needs action right now.</div>'}</div>`;
  } else if (t === 'OPPORTUNITIES') {
    const list = d.opportunities.filter((o) => ACTIVE(o.status)).sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0));
    body = `<p class="muted small">${list.length} open opportunities. No deal values are estimated here.</p><div class="tbl-wrap"><table><thead><tr><th>Company</th><th>Contact</th><th>Stage</th><th>Next action</th></tr></thead><tbody>
      ${list.map((o) => `<tr class="clickable" data-open="opp" data-id="${o.id}"><td>${esc(o.company_name)}</td><td>${esc(o.contact_name || '—')}</td><td>${esc(S(o.status))}</td><td class="small">${esc(o.next_action || '')}</td></tr>`).join('')}</tbody></table></div>`;
  } else {
    // Pipeline: where every account stands, from prospect to project; where it is stuck.
    const P = state.ceo?.pipeline || [];
    const names = Object.fromEntries((state.dir?.companies || []).map((c) => [c.id, c.name]));
    const at = (stage) => Object.entries(state.ceo?.companies || {}).filter(([, v]) => v[2] === stage).map(([id, v]) => ({ id, name: names[id] || 'Company', p: v[1], dir: v[0] }));
    const late = ['REPLIED', 'QUALIFIED_CONVERSATION', 'MEETING', 'CONCEPT_BRIEF', 'PROPOSAL', 'NEGOTIATION', 'WON', 'PROJECT_ACTIVE', 'COMPLETED'];
    body = !state.ceo ? waitFor('ceo', 'the pipeline') : `<div class="pipe">${P.filter((s) => s.stage !== 'LOST_PARKED').map((s) => `<div class="pst ${s.n ? '' : 'zero'}"><span class="pn">${n0(s.n)}</span><span class="pl">${esc(STAGE_NAME[s.stage])}</span>${s.stuck ? `<span class="pk">${s.stuck} stuck</span>` : ''}</div>`).join('<span class="parr">→</span>')}</div>
      ${late.map((st) => { const l = at(st); return l.length ? `<section class="panel mt8"><header><h3>${esc(STAGE_NAME[st])} · ${l.length}</h3></header><div class="body">${l.map((x) => `<div class="t-row clickable" data-open="company" data-id="${x.id}"><div><div class="t-main">${esc(x.name)}</div><div class="t-sub">${esc(projectName(x.p))}${x.dir ? ` · ${esc(dirName(x.dir))}` : ''}</div></div></div>`).join('')}</div></section>` : ''; }).join('')}
      <p class="src">Prospect → Outreach → Replied → Qualified conversation → Meeting → Concept / brief → Proposal → Negotiation → Won → Project active → Completed. An account does not have to pass every stage. "Stuck" means no open task and no movement for 7 days. ${n0((P.find((s) => s.stage === 'LOST_PARKED') || {}).n)} lost or parked. Full table: More → Pipeline.</p>`;
  }
  return `${head('Relationships', 'Build the network')}
    <div class="tabs">${REL_TABS.map(([k, l]) => `<button data-rel-tab="${k}" class="${t === k ? 'on' : ''}">${l}${k === 'COLD' && N ? ` <span class="n">${n0(N.counts?.going_cold)}</span>` : k === 'IMPORTANT' && N ? ` <span class="n">${n0((N.important || []).length)}</span>` : ''}</button>`).join('')}</div>${body}`;
}

// ---------------------------------------------------------------- CLUB: the private network, lightweight. Real people only.
const CLUB_TABS = [['PRIVATE', 'Private clients', 'private_clients'], ['POTENTIAL', 'Potential members', 'potential_members'], ['INTRODUCERS', 'Introducers', 'introducers'], ['MEMBERS', 'Members', 'members'],
  ['BENEFITS', 'Benefits', 'benefits'], ['PRIVILEGES', 'Partner privileges', 'partner_privileges'], ['EVENTS', 'Events', 'events'], ['INTRODUCTIONS', 'Introductions', 'introductions']];
const CLUB_EMPTY = { members: 'No members yet. Members are added by you, never automatically, never invented.', potential_members: 'Nobody marked as a potential member yet. Mark people from the routes below.',
  private_clients: 'No private clients recorded yet.', introducers: 'No introducers confirmed yet.', benefits: 'No member benefits agreed yet. Benefits come from real partner agreements only.',
  partner_privileges: 'No partner privileges yet: a privilege needs a warm, real partner relationship first.', introductions: 'No introductions recorded yet.', events: 'No private events planned yet.' };
function viewClub() {
  const C = state.club; if (!C) { loadV3('club', 'hq_club'); return head('Club') + waitFor('club', 'the club'); }
  const tab = CLUB_TABS.find(([k]) => k === state.clubTab) || CLUB_TABS[0]; const [, title, key] = tab;
  const items = key === 'potential_members' ? [...(C.potential_members || []), ...(C.applications || [])] : (C[key] || []);
  const personRow = (p) => `<div class="t-row"><div><div class="t-main">${esc(p.person)}${p.position ? ` · <span class="faint">${esc(p.position)}</span>` : ''}</div><div class="t-sub">${esc(p.company || '')} · ${esc(sentence(p.status))} · added by ${esc(p.source)} ${esc(shortDay(p.since))}</div>${p.notes ? `<div class="t-sub faint">${esc(p.notes)}</div>` : ''}</div></div>`;
  let body = '';
  if (['members', 'potential_members', 'private_clients', 'introducers'].includes(key)) body = items.map(personRow).join('');
  else if (key === 'benefits') body = items.map((b) => `<div class="t-row"><div><div class="t-main">${esc(b.title)} · <span class="faint">${esc(sentence(b.status))}</span></div><div class="t-sub">${esc(b.partner || '')} · ${esc(b.terms || '')}</div></div></div>`).join('');
  else if (key === 'partner_privileges') body = items.map((p) => `<div class="t-row clickable" data-open="company" data-id="${p.company_id}"><div><div class="t-main">${esc(p.name)} · <span class="faint">${esc(sentence(String(p.model).replace(/_/g, ' ')))}</span></div>${p.value ? `<div class="t-sub">For members: ${esc(p.value.to_noya)}</div>` : ''}</div></div>`).join('');
  else if (key === 'introductions') body = items.map((i) => `<div class="t-row"><div><div class="t-main">${esc(i.from || '')} → ${esc(i.to || '')} · <span class="faint">${esc(sentence(i.status))}</span></div><div class="t-sub">${esc(i.purpose)}</div></div></div>`).join('');
  else if (key === 'events') body = items.map((e) => `<div class="t-row"><div><div class="t-main">${esc(e.title)} · <span class="faint">${esc(sentence(e.status))}</span></div><div class="t-sub">${esc([e.date ? shortDay(e.date) : '', e.city, e.venue].filter(Boolean).join(' · '))}</div></div></div>`).join('');
  const routes = key === 'introducers' || key === 'potential_members' ? `<h3 class="grp">Routes in the CRM · ${C.introducer_routes.length}</h3><p class="muted small">Confirmed decision makers at private offices, family offices, clubs and communities already in NOYA's records. Add someone only when you know them or have a reason.</p>
    <div class="dlist">${C.introducer_routes.map((r) => `<div class="t-row"><div><div class="t-main">${esc(r.person)}${r.position ? ` · <span class="faint">${esc(r.position)}</span>` : ''}</div><div class="t-sub">${esc(r.company)} ${estatePill(r.email_state)}${r.linkedin ? ` · <a href="${esc(r.linkedin)}" target="_blank" rel="noopener noreferrer">LinkedIn</a>` : ''}</div></div>
      <div class="t-btns"><button class="btn small" data-club-add="INTRODUCER" data-contact="${r.contact_id}">Introducer</button><button class="btn small ghost" data-club-add="POTENTIAL_MEMBER" data-contact="${r.contact_id}">Potential member</button></div></div>`).join('')}</div>
    ${key === 'introducers' && (C.communities || []).length ? `<h3 class="grp">Private communities in the CRM · ${C.communities.length}</h3><div class="dlist">${C.communities.map((c) => `<div class="t-row clickable" data-open="company" data-id="${c.company_id}"><div><div class="t-main">${esc(c.name)}${c.relationship !== 'COLD' ? ` · <span class="ok-text">${esc(REL_NAME[c.relationship] || sentence(c.relationship.replace(/_/g, ' ')))}</span>` : ''}</div><div class="t-sub">${esc([c.type && /_/.test(c.type) ? sentence(c.type.replace(/_/g, ' ')) : c.type, c.city, c.country].filter(Boolean).join(' · '))}</div></div></div>`).join('')}</div>` : ''}` : '';
  return `${head('Club', 'The private network · real people only, added by you')}
    <div class="tabs">${CLUB_TABS.map(([k, l, ck]) => `<button data-club-tab="${k}" class="${k === tab[0] ? 'on' : ''}">${l} <span class="n">${(ck === 'potential_members' ? (C.potential_members || []).length + (C.applications || []).length : (C[ck] || []).length)}</span></button>`).join('')}</div>
    <section class="panel"><header><h3>${esc(title)}</h3></header><div class="body">${body || `<div class="empty">${esc(CLUB_EMPTY[key])}</div>`}</div></section>${routes}`;
}

// ---------------------------------------------------------------- DESTINATION EGYPT (Adam, 19 Oct): a mission run by the existing Directors
// Read from hq_command (destination_egypt): mission companies on the canonical model, counted once. Top opportunities only, never
// discovery volume; no deal value until one is recorded. Success is reply → meeting → brief → proposal → project → revenue.
const PROJECT_TYPE = { BRAND_CAMPAIGN_EGYPT: 'Brand campaign', BRAND_SHOOT_EGYPT: 'Brand shoot', CREATOR_TRIP_EGYPT: 'Creator trip', BRAND_LAUNCH_EGYPT: 'Brand launch',
  PRODUCTION_EGYPT: 'Production', AGENCY_CLIENT_PROJECT_EGYPT: 'Agency client project', DESTINATION_WEDDING_EGYPT: 'Destination wedding', WEDDING_GUEST_CONCIERGE: 'Wedding guest concierge',
  WEDDING_SCOUTING_TRIP: 'Wedding scouting trip', PRIVATE_CLUB_MEMBER_TRIP: 'Member trip', FOUNDER_RETREAT_EGYPT: 'Founder retreat', CORPORATE_OFFSITE_EGYPT: 'Corporate offsite',
  EXECUTIVE_RETREAT_EGYPT: 'Executive retreat', PRIVATE_DINNER_EGYPT: 'Private dinner', PODCAST_EGYPT: 'Podcast episode', MEDIA_PRODUCTION_EGYPT: 'Media production',
  PRESS_TRIP_EGYPT: 'Press trip', TRAVEL_ADVISOR_FAM: 'Advisor FAM', WHITE_LABEL_EGYPT_DESK: 'White-label Egypt desk', TALENT_PRIVATE_TRIP: 'Talent private trip',
  ATHLETE_PRIVATE_TRIP: 'Athlete private trip', HOTEL_BRAND_CREATOR_COLLABORATION: 'Hotel × brand × creator' };
const ptype = (k) => PROJECT_TYPE[k] || (k ? sentence(String(k).replace(/_/g, ' ')) : '—');
const ROUTE_STATE = { VERIFIED: ['Verified email', 'ok'], VERIFIED_INBOX: ['Verified inbox', 'ok'], VERIFIED_GENERAL: ['Verified general inbox', 'ok'],
  OFFICIAL_PUBLISHED_INBOX: ['Official inbox · not verified', 'info'], NEEDS_VERIFICATION: ['Email found · to verify', 'warn'], FINDER_PENDING: ['Waiting for email finder', 'warn'],
  RESEARCH_PENDING: ['Email research pending', 'warn'], NO_PERSON: ['Right person not confirmed', 'bad'] };
const emailState = (s) => { const [l, c] = ROUTE_STATE[s] || [s ? sentence(String(s).replace(/_/g, ' ')) : 'No route yet', '']; return pill(l, c); };
function dashMission() {
  const C = state.cmd; if (!C) return '';
  const M = C.destination_egypt; if (!M) return '';
  const f = M.funnel || {}; const tl = (n, l) => `<div class="wk-t"><div class="n">${n}</div><div class="l">${l}</div></div>`;
  const rev = cashOf(f.revenue) || '£0';
  const top = (M.top || []).slice(0, state.missionAll ? 10 : 5);
  const research = (M.buckets || []).map((b) => `<span class="wk-d"><b>${esc(b.label)}</b> ${n0(b.researched)} of ${n0(b.target)}</span>`).join('');
  // Conversion sprint (Adam, 19 Oct): conversion first, research secondary.
  const S = M.sprint;
  const sprint = S ? `<p class="small mt6 sprint-line"><b>${esc(S.name || 'Conversion sprint')}</b> · ${esc(shortDay(S.started_at))} to ${esc(shortDay(S.ends_at))} ·
      ${Number(S.day) ? `working day ${n0(S.day)} of ${n0(S.working_days)}` : 'starts ' + esc(shortDay(S.started_at))} ·
      <b>${n0(S.conversations)}</b> conversations of ${n0(S.target_min)}–${n0(S.target_max)} (${n0(S.new_conversations)} new) · ${n0(S.contacted)} contacted, ${n0(S.positive)} positive, ${n0(S.meetings)} meetings since the start</p>` : '';
  return `<section class="dsec mission" id="mission"><header><h2>Destination Egypt</h2><span class="faint small">Project generation · review ${esc(shortDay(S?.review_at || M.review_by))}</span></header>
    <p class="small muted mt0">${esc(M.question || '')}</p>
    <div class="wk-tiles">${tl(n0(f.contacted), 'Contacted')}${tl(n0(f.replied), 'Replied')}${tl(n0(f.positive), 'Positive')}
      ${tl(n0(f.meetings), 'Meetings')}${tl(n0(f.briefs), 'Briefs')}${tl(n0(f.proposals), 'Proposals')}${tl(n0(f.won), 'Projects won')}${tl(esc(rev), 'Revenue')}</div>
    ${sprint}
    ${top.length ? `<div class="tbl-wrap mt8"><table class="stack mtop"><thead><tr><th>Company</th><th>Proposed project</th><th>Director</th><th>Studio</th><th>Email</th><th>Stage</th><th>Next action</th></tr></thead><tbody>
      ${top.map((o) => `<tr><td><a class="clickable" data-open="company" data-id="${o.company_id}">${esc(o.company)}</a>${o.country ? `<div class="faint small">${esc(o.country)}</div>` : ''}</td>
        <td data-l="Project" class="small"><b>${esc(ptype(o.project_type))}</b>${o.project ? `<div class="faint">${esc(plainText(o.project))}</div>` : ''}</td>
        <td data-l="Director" class="small">${esc(dirName(o.director))}</td><td data-l="Studio" class="small">${o.studio_level ? `Level ${esc(o.studio_level)}` : '—'}</td>
        <td data-l="Email">${emailState(o.email_state)}</td><td data-l="Stage" class="small">${esc(o.stage || '')}</td>
        <td data-l="Next action" class="small">${o.next_action ? esc(plainText(o.next_action)) : '<span class="faint">—</span>'}${o.blocker ? `<div class="warn-text">${esc(o.blocker)}</div>` : ''}</td></tr>`).join('')}</tbody></table></div>
      ${(M.top || []).length > 5 ? `<button class="linkish" data-mission-all>${state.missionAll ? 'Show the top 5' : `Show the top ${(M.top || []).length}`}</button>` : ''}`
      : '<p class="small faint mt8">No mission opportunity recorded yet. The Directors are researching the first accounts.</p>'}
    <div class="small mt6 faint">Pipeline: ${n0(f.qualified)} qualified · ${n0(f.email_ready)} email-ready · Research by programme: ${research}</div>
    <p class="src">${esc(M.method || '')}</p></section>`;
}
function weeklyMission(L) {
  if (!L) return '';
  const by = L.by || {}; const line = (k, l) => (by[k] || []).slice(0, 5).map((r) => `${esc(k === 'project_type' ? ptype(r.key) : k === 'director' ? dirName(r.key) : r.key)} ${n0(r.replied)}/${n0(r.contacted)}`).join(' · ');
  const rows = [['project_type', 'Project types getting replies'], ['director', 'Directors (replied / contacted)'], ['market', 'Markets'], ['studio_level', 'Studio level']]
    .map(([k, l]) => (line(k, l) ? `<dt>${l}</dt><dd>${line(k, l)}</dd>` : '')).join('');
  const meet = (by.director || []).filter((r) => Number(r.meetings)).map((r) => `${esc(dirName(r.key))} ${n0(r.meetings)}`).join(' · ');
  return `<h6 class="mt8">Destination Egypt · what is working</h6><dl class="wk-dl">${rows}
    <dt>Directors producing meetings</dt><dd>${meet || 'None yet'}</dd>
    <dt>Concepts with interest</dt><dd>${(L.concepts_with_interest || []).map((c) => `${esc(c.company)} (Level ${esc(c.level)})`).join(' · ') || 'None yet'}</dd>
    <dt>Where conversion stops</dt><dd>${esc(L.conversion_stops_at || '—')}</dd>
    <dt>More resources to</dt><dd>${esc(L.more_resources || 'Not enough contacted yet to say.')}</dd>
    <dt>Stop</dt><dd>${(L.stop || []).map(esc).join(' · ') || 'Nothing yet'}</dd></dl><p class="src">${esc(L.note || '')}</p>`;
}

// ---------------------------------------------------------------- STUDIO (primary since 19 Oct): ideas, concepts, briefs, proposals
// hq_studio(): six columns from studio_documents and Adam's requests, the eight Studio roles and the three levels. Studio prepares,
// Adam approves and sends: nothing here sends, and a document above the level the relationship has earned is held, never sent early.
const STUDIO_COLS = [['NEEDS_BRIEF', 'Needs brief'], ['DRAFTING', 'Drafting'], ['NEEDS_REVIEW', 'Needs review'], ['APPROVED', 'Approved'], ['SENT', 'Sent'], ['SUPERSEDED', 'Superseded']];
const DOC_TYPE = { EMAIL_IDEA: 'Email idea', OPPORTUNITY_NOTE: 'Opportunity note', CONCEPT: 'Concept', ONE_PAGE_CONCEPT: 'One-page concept', BRIEF: 'Brief', PROPOSAL: 'Proposal',
  ITINERARY: 'Itinerary', OPS_ITINERARY: 'Internal itinerary', PROJECT: 'Project plan', DESK_BRIEF: 'Desk brief' };
const REQ_KIND = { IDEA: 'Idea', ONE_PAGE_CONCEPT: 'One-page concept', BRIEF: 'Brief', PROPOSAL: 'Proposal', ITINERARY: 'Itinerary', RETREAT_CONCEPT: 'Retreat concept',
  WEDDING_CONCEPT: 'Wedding concept', BRAND_CAMPAIGN_CONCEPT: 'Brand campaign concept', MEDIA_CONCEPT: 'Media concept' };
const coLink = (id, name) => (id ? `<a class="clickable" data-open="company" data-id="${id}">${esc(name || '')}</a>` : esc(name || ''));
function studioDoc(x) {
  return `<div class="sd"><div class="sd-t">${esc(x.title || x.slug)}</div>
    <div class="sd-m">${coLink(x.company_id, x.company)}</div>
    <div class="sd-m">${esc(DOC_TYPE[x.doc_type] || x.doc_type || '')}${x.level ? ` · Level ${esc(x.level)}` : ''}${x.version > 1 ? ` · v${esc(x.version)}` : ''} · <span class="faint">${esc(shortDay(x.sent_at || x.approved_at || x.created_at))}</span></div>
    ${x.hold_reason ? `<div class="sd-m warn-text">${esc(x.hold_reason)}</div>` : ''}</div>`;
}
function studioCol(key, label, S) {
  const C = S.columns || {}; const all = state.studioAll[key];
  let items = []; let count = 0; let extra = '';
  if (key === 'NEEDS_BRIEF') {
    const req = C.NEEDS_BRIEF?.requests || []; const warm = C.NEEDS_BRIEF?.warmed || [];
    count = req.length + warm.length;
    items = [...req.map((r) => `<div class="sd req"><div class="sd-t">${esc(REQ_KIND[r.kind] || r.kind)} · ${esc(r.status === 'IN_PROGRESS' ? 'in progress' : 'requested')}</div>
        <div class="sd-m">${coLink(r.company_id, r.company)}</div>${r.note ? `<div class="sd-m faint">${esc(r.note)}</div>` : ''}
        <div class="sd-m faint">Level ${esc(r.level)} · ${esc(shortDay(r.created_at))} <button class="linkish" data-studio-cancel="${r.id}">Cancel</button></div></div>`),
      ...warm.map((w) => `<div class="sd warm"><div class="sd-t">${coLink(w.company_id, w.company)}</div><div class="sd-m">${esc(w.next_output || '')}</div>
        <div class="sd-m faint">Warm since ${esc(shortDay(w.warmed_at))} <button class="linkish" data-modal="studio-new" data-type="${Number(w.earned_level) >= 3 ? 'BRIEF' : 'ONE_PAGE_CONCEPT'}" data-company="${w.company_id}">Create ${Number(w.earned_level) >= 3 ? 'brief' : 'concept'}</button></div></div>`)];
  } else if (key === 'SUPERSEDED') {
    count = Number(C.SUPERSEDED?.count || 0); items = (C.SUPERSEDED?.recent || []).map(studioDoc);
    if (count > items.length) extra = `<div class="sd-m faint">${count - items.length} older versions kept</div>`;
  } else { const list = C[key] || []; count = list.length; items = list.map(studioDoc); }
  const shown = all ? items : items.slice(0, 6);
  return `<div class="kcol"><div class="kh"><span>${esc(label)}</span><b>${n0(count)}</b></div>
    ${shown.join('') || `<div class="sd-m faint kempty">${key === 'SENT' ? 'Nothing sent yet. You send; Studio never does.' : 'Empty'}</div>`}
    ${items.length > 6 ? `<button class="linkish" data-studio-all="${key}">${all ? 'Show less' : `Show all ${items.length}`}</button>` : ''}${extra}</div>`;
}
function viewStudio() {
  const S = state.studio; if (!S) { loadV3('studio', 'hq_studio'); return head('Studio') + waitFor('studio', 'the Studio'); }
  const out = S.outputs || [];
  return `${head('Studio', esc(['Ideas, concepts, briefs and proposals · Studio prepares, you approve and send', S.generated_at ? `updated ${new Date(S.generated_at).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Cairo' })}` : ''].filter(Boolean).join(' · ')))}
    <div class="lvls">${(S.levels || []).map((l) => `<div class="lvl"><b>${esc(l.label)}</b><span>${esc(l.when)}</span></div>`).join('')}</div>
    <div class="sacts">${(S.actions || []).map((a) => `<button class="btn small ${a.level === 1 ? 'primary' : ''}" data-modal="studio-new" data-type="${a.kind}">${esc(a.label)}</button>`).join('')}</div>
    <div class="kanban">${STUDIO_COLS.map(([k, l]) => studioCol(k, l, S)).join('')}</div>
    ${out.length ? `<section class="dsec mt8"><header><h2>Prepared for a conversation</h2><span class="faint small">From prepared to sent, reply, meeting</span></header><div class="tbl-wrap"><table class="stack"><thead><tr><th>Company</th><th>Level</th><th>Status</th><th>Next step</th><th>Sent</th><th>Reply</th><th>Meeting</th></tr></thead><tbody>
      ${out.map((o) => `<tr><td>${esc(o.company || '')}</td><td data-l="Level" class="small">${esc(o.level_label || `Level ${o.level}`)}</td><td data-l="Status">${pill(sentence(String(o.status || '').toLowerCase()), o.status === 'HELD' ? 'warn' : o.status === 'SENT' ? 'ok' : '')}</td>
        <td data-l="Next step" class="small">${esc(plainText(o.next_step || '—'))}</td><td data-l="Sent" class="small">${o.sent_at ? esc(shortDay(o.sent_at)) : '—'}</td>
        <td data-l="Reply" class="small">${o.reply_at ? esc(shortDay(o.reply_at)) : '—'}</td><td data-l="Meeting" class="small">${o.meeting_at ? esc(shortDay(o.meeting_at)) : '—'}</td></tr>`).join('')}</tbody></table></div></section>` : ''}
    <p class="src">${esc(S.rules || '')} <button class="linkish" data-tab="agents">The Studio team</button></p>`;
}
// The Studio workforce on the Agents page: eight roles, the Brief & Proposal Architect first. Click a role for its work.
function studioTeam() {
  const S = state.studio; if (!S) { loadV3('studio', 'hq_studio'); return `<h3 class="grp">Studio</h3>${waitFor('studio', 'the Studio team')}`; }
  const team = S.team || []; const cell = (n, l) => (n == null ? '' : `<div class="dc-c"><b>${n0(n)}</b><span>${l}</span></div>`);
  const card = (t) => `<article class="dcard studio-role ${t.main ? 'main' : ''}" data-modal="studio-role" data-id="${t.key}">
    <div class="dc-head"><div><div class="dc-name">${esc(t.name)}</div><div class="dc-role">${t.main ? 'Studio lead' : 'Studio'}</div></div>${t.main ? pill('Main', 'gold') : ''}</div>
    <div class="dc-now small">${esc(t.does || '')}</div>
    <div class="dc-cells mt6">${cell(t.drafting, 'drafting')}${cell(t.needs_review, 'needs review')}${cell(t.approved, 'approved')}${cell(t.sent, 'sent')}${cell(t.quotes, 'quotes')}${cell(t.qa_passed, 'QA checked')}</div>
    <div class="dc-last"><span class="dc-sub">Last output</span>${t.last ? `${esc(t.last.title || '')}${t.last.company && t.last.company !== t.last.title ? ` · ${esc(t.last.company)}` : ''} · ${esc(rel(t.last.at))}` : '<span class="faint">None yet</span>'}</div></article>`;
  const main = team.filter((t) => t.main); const rest = team.filter((t) => !t.main);
  return `<h3 class="grp">Studio <button class="btn small ghost" data-go="studio">Open Studio</button></h3>
    <div class="dgrid">${main.map(card).join('')}</div><div class="dgrid compact mt8">${rest.map(card).join('')}</div>`;
}
function studioRoleModal(m) {
  const S = state.studio || {}; const t = (S.team || []).find((x) => x.key === m.id) || {};
  const row = (x) => `<div class="adv-row">${esc(x.title || '')}${x.company && x.company !== x.title ? ` <span class="faint">· ${esc(x.company)}</span>` : ''}${x.doc_type ? ` <span class="faint">· ${esc(DOC_TYPE[x.doc_type] || x.doc_type)}</span>` : ''}${x.status ? ` ${pill(sentence(String(x.status).replace(/_/g, ' ').toLowerCase()))}` : ''}${x.at || x.created_at ? ` <span class="faint">${esc(shortDay(x.at || x.created_at))}</span>` : ''}</div>`;
  const list = (title, items, empty, n = 8) => `<h6 class="mt8">${title} · ${(items || []).length}</h6>${(items || []).slice(0, n).map(row).join('') || `<div class="adv-row faint">${empty}</div>`}${(items || []).length > n ? `<div class="adv-row faint">and ${(items || []).length - n} more in Studio</div>` : ''}`;
  let body;
  if (t.main) {
    const A = S.architect || {};
    const needs = (A.needs_adam || []).map((x) => ({ ...x, title: `${x.what || ''}: ${x.title || ''}` }));
    body = `${list('Current work', A.current, 'Nothing in progress.')}${list('Briefs being produced', A.briefs, 'No brief yet.')}${list('Concepts ready', A.concepts_ready, 'No concept ready.')}
      ${list('Proposals', A.proposals, 'No proposal yet.')}${list('Needs you', needs, 'Nothing waiting for you.')}${list('Last outputs', A.last_outputs, 'No output yet.')}`;
  } else body = `${list('Current work', t.current, 'Nothing in progress.')}${t.last ? `<h6 class="mt8">Last output</h6>${row(t.last)}` : ''}`;
  return `<div class="modal-bg"><div class="modal wide"><h3>${esc(t.name || 'Studio')}</h3><p class="small muted">${esc(t.does || '')}</p>${body}
    <div class="btn-row mt8"><button class="btn primary" data-go="studio">Open Studio</button><button class="btn ghost" data-close>Close</button></div></div></div>`;
}
// Companies Adam can request Studio work for: the CRM directory plus the warm queue and mission accounts (deduplicated by id).
function studioCompanies() {
  const seen = new Map();
  const add = (id, name) => { if (id && name && !seen.has(id)) seen.set(id, name); };
  (state.studio?.columns?.NEEDS_BRIEF?.warmed || []).forEach((w) => add(w.company_id, w.company));
  (state.cmd?.destination_egypt?.top || []).forEach((o) => add(o.company_id, o.company));
  (state.cmd?.opportunities || []).forEach((o) => add(o.company_id, o.company));
  (state.dir?.companies || []).forEach((c) => add(c.id, c.name));
  return [...seen.entries()];
}
const studioCompanyId = (name) => { if (!name) return null; const hit = studioCompanies().find(([, n]) => n.toLowerCase() === name.toLowerCase()); return hit ? hit[0] : null; };
function studioNewModal(m) {
  const S = state.studio || {}; const a = (S.actions || []).find((x) => x.kind === m.type) || { label: 'Create', level: 1 };
  const lv = (S.levels || []).find((l) => l.level === a.level);
  const pre = m.company ? studioCompanies().find(([id]) => id === m.company)?.[1] || '' : '';
  return form(esc(a.label), `<p class="small muted">${esc(lv ? `${lv.label}: ${lv.when}` : '')} The Studio prepares it for your review; nothing is sent, and a document above the level the relationship has earned is held.</p>
    <label class="field"><span>Company</span><input id="sn-company" list="sn-companies" value="${esc(pre)}" autocomplete="off" placeholder="Type to search the CRM"></label>
    <datalist id="sn-companies">${studioCompanies().map(([, n]) => `<option value="${esc(n)}"></option>`).join('')}</datalist>
    ${area('What it should do (optional)', 'sn-note', '', 'maxlength="1000" rows="3" placeholder="e.g. a three-night member programme, Giza and the Grand Egyptian Museum"')}`, 'Request');
}

// ---------------------------------------------------------------- OPERATIONS: deliver projects. Confirmed client work only, never prospects.
function viewOps() {
  const O = state.ops; const B = state.ceo?.operations; if (!O) return head('Operations') + waitFor('ops', 'operations');
  const proj = (p) => `<div class="t-row"><div><div class="t-main">${esc(p.name)}</div><div class="t-sub">${esc((state.dir?.companies || []).find((c) => c.id === p.company_id)?.name || '')}${p.starts_on ? ` · starts ${esc(shortDay(p.starts_on))}` : ''} · ${esc(sentence(p.status))}</div></div><div class="t-btns"><button class="btn small" data-tab="projects">Open</button></div></div>`;
  const sec = (title, list, empty) => `<section class="panel mt8"><header><h3>${esc(title)} · ${list.length}</h3></header><div class="body">${list.map(proj).join('') || `<div class="empty">${esc(empty)}</div>`}</div></section>`;
  const has = O.projects.length + O.won.length;
  return `${head('Operations', 'Deliver projects · confirmed client work only, never prospects')}
    ${has ? '' : '<div class="calm"><div class="calm-t">No confirmed project yet.</div><div class="t-sub">A project appears here when an opportunity is won and the work is confirmed. Prospects and conversations stay in Outreach and Relationships.</div></div>'}
    ${!B ? waitFor('ceo', 'projects') : !Object.values(B).some((l) => l.length) ? `<div class="pipe ops-zero">${[['Active projects', B.active], ['Upcoming', B.upcoming], ['Awaiting client', B.awaiting_client], ['Awaiting supplier', B.awaiting_supplier], ['Payment required', B.payment_required], ['Completed', B.completed]]
      .map(([l, x]) => `<div class="pst zero"><span class="pn">${x.length}</span><span class="pl">${l}</span></div>`).join('')}</div>`
      : `${sec('Active projects', B.active, 'No project is live.')}${sec('Upcoming', B.upcoming, 'Nothing confirmed or in planning.')}${sec('Awaiting client', B.awaiting_client, 'Nothing waiting on a client.')}
      ${sec('Awaiting supplier', B.awaiting_supplier, 'Nothing waiting on a supplier.')}${sec('Payment required', B.payment_required, 'No payment outstanding.')}${sec('Completed', B.completed, 'No completed project yet.')}`}
    ${O.won.length ? `<section class="panel mt8"><header><h3>Won, not yet a project · ${O.won.length}</h3></header><div class="body">${O.won.map((w) => `<div class="t-row clickable" data-open="opp" data-id="${w.opportunity_id}"><div><div class="t-main">${esc(w.company)}</div><div class="t-sub">${esc(w.type || '')} · ${esc(money(w.value, w.currency))} · ${esc(shortDay(w.won_at))}</div></div></div>`).join('')}</div></section>` : ''}
    <p class="src mt8">Revenue records: ${esc(O.revenue.records)} · pending payments: ${esc(O.revenue.pending)}. <button class="linkish" data-tab="finance">Finance</button> · <button class="linkish" data-tab="projects">Projects (classic)</button></p>`;
}

// Retry one section (or everything) after a temporary failure.
async function retry(k) {
  if (k === 'all') { Object.keys(state.errors).forEach((x) => { if (x !== 'lastAction') delete state.errors[x]; }); return load(false, 'full'); }
  if (k.startsWith('director:')) { const key = k.slice(9); delete state.errors[k]; delete state.dirDetail[key]; render(); return loadDirector(key, true); }
  if (k.startsWith('agent:')) { const key = k.slice(6); delete state.agentDetail[key]; render(); return loadAgent(key, true); }
  if (k === 'agents') { delete state.errors.agents; render(); return loadAgents(true); }
  if (k === 'weekly') { delete state.errors.weekly; render(); return loadV3('weekly', 'hq_weekly_review', {}, true); }
  if (k === 'liArch') { delete state.errors.liArch; render(); return loadV3('liArch', 'hq_linkedin_archive', {}, true); }
  delete state.errors[errKey(k)]; render(); await readKey(k); render();
}
function bindV3(on) {
  on('[data-retry]', 'click', (b, e) => { e.stopPropagation(); retry(b.dataset.retry); });
  on('[data-diag-refresh]', 'click', () => { state.diag = null; loadDiag(); });
  $('#nav-more')?.addEventListener('click', () => { state.more = !moreOpen(); if (!state.more && MORE_KEYS.includes(state.tab)) state.more = true; render(); });
  on('[data-director]', 'click', (b) => { state.dirKey = b.dataset.director; state.tab = 'director'; render(); loadDirector(b.dataset.director); window.scrollTo(0, 0); });
  on('[data-dir-sec]', 'click', (b) => { state.dirSec[state.dirKey] = b.dataset.dirSec; render(); });
  on('select[data-feed-dir]', 'change', (el) => { state.feedDir = el.value; render(); });
  on('[data-feed-all]', 'click', () => { state.feedAll = !state.feedAll; render(); });
  on('[data-weekly]', 'click', () => { state.modal = { kind: 'weekly' }; render(); loadV3('weekly', 'hq_weekly_review', {}, true); });
  on('[data-desk-tab]', 'click', (b) => { state.deskTab = b.dataset.deskTab; state.deskPage = 0; if (!b.dataset.go) render(); });
  on('[data-desk-ch]', 'click', (b) => { state.deskCh = b.dataset.deskCh; state.deskPage = 0; render(); });
  on('select[data-desk-dir]', 'change', (el) => { state.deskDir = el.value; state.deskPage = 0; render(); });
  on('select[data-desk-proj]', 'change', (el) => { state.deskProj = el.value; state.deskPage = 0; render(); });
  on('[data-desk-more]', 'click', (b) => { state.deskMore = state.deskMore === b.dataset.deskMore ? null : b.dataset.deskMore; render(); });
  on('[data-scroll]', 'click', (b) => { document.getElementById(b.dataset.scroll)?.scrollIntoView({ behavior: 'smooth', block: 'start' }); });
  on('[data-desk-page]', 'click', (b) => { state.deskPage = Math.max(0, state.deskPage + Number(b.dataset.deskPage)); render(); window.scrollTo(0, 0); });
  on('[data-desk-open]', 'click', (b) => { state.deskOpen[b.dataset.deskOpen] = !state.deskOpen[b.dataset.deskOpen]; render(); });
  on('[data-desk-src]', 'click', (b) => { state.deskSrc[b.dataset.deskSrc] = !state.deskSrc[b.dataset.deskSrc]; render(); });
  on('[data-desk-modal]', 'click', (b) => { state.modal = { kind: 'desk', form: b.dataset.deskModal, ref: b.dataset.ref }; render(); });
  on('[data-desk-release]', 'click', (b) => { const x = deskItem(b.dataset.deskRelease); if (x) call('hq_outreach_action', { p_task: x.task_id, p_action: 'RELEASE', p_reason: null, p_until: null }, 'Released back to review.'); });
  on('[data-desk-approve]', 'click', async (b) => {
    const x = deskItem(b.dataset.deskApprove); if (!x) return; b.disabled = true;
    const text = `Approved. HQ re-checked the address and is creating one unsent Gmail draft to ${x.route?.email || 'the verified address'}. Nothing was sent.`;
    const r = x.approve_via === 'EMAIL_CANDIDATE'
      ? await call('hq_approve_email', { p_candidate: x.candidate_id, p_subject: null, p_body: null }, text)
      : await call('hq_approve_draft', { p_opportunity_id: x.opportunity_id, p_version: Number(x.draft_version || 1) }, text);
    if (r && r.ok) { state.pollUntil = Date.now() + 120000; state.deskTab = 'APPROVED'; render(); }
  });
  $('#dm-ok')?.addEventListener('click', submitDeskModal);
  on('[data-rel-tab]', 'click', (b) => { state.relTab = b.dataset.relTab; render(); });
  on('[data-club-tab]', 'click', (b) => { state.clubTab = b.dataset.clubTab; render(); });
  on('[data-sc-win]', 'click', (b, e) => { e.stopPropagation(); state.scWin = b.dataset.scWin; render(); });
  on('[data-health-refresh]', 'click', () => loadHealth(true));
  $('#rv-check')?.addEventListener('click', async () => {
    const text = $('#rv-text')?.value || ''; const rows = revenueRows(text);
    if (!rows.length) { state.modal = { ...state.modal, text, preview: { valid: [], errors: [{ row: 0, errors: ['No rows found: paste a header row and at least one record.'] }] } }; render(); return; }
    const { data, error } = await sb.rpc('hq_revenue_import', { p_rows: rows, p_apply: false });
    state.modal = { ...state.modal, text, rows, preview: error ? { valid: [], errors: [{ row: 0, errors: [friendly(error.message)] }] } : data }; render();
  });
  on('[data-studio-cancel]', 'click', async (b, e) => { e.stopPropagation(); await call('hq_studio_request_action', { p_id: b.dataset.studioCancel, p_action: 'CANCEL' }, 'Request cancelled. It is kept in the history.'); loadV3('studio', 'hq_studio', {}, true); });
  on('[data-mission-all]', 'click', () => { state.missionAll = !state.missionAll; render(); });
  on('[data-studio-all]', 'click', (b) => { state.studioAll[b.dataset.studioAll] = !state.studioAll[b.dataset.studioAll]; render(); });
  on('[data-club-add]', 'click', async (b) => { await call('hq_club_person', { p_contact: b.dataset.contact, p_role: b.dataset.clubAdd, p_status: 'PROSPECT', p_note: null }, 'Added to the club structure. Nothing was sent.'); loadV3('club', 'hq_club', {}, true); });
}

const VIEWS = { dashboard: viewDashboard, today: viewDashboard, agents: viewAgentsV3, director: viewDirector, desk: viewDesk, studio: viewStudio, relations: viewRelations, club: viewClub, ops: viewOps, agentfloor: viewAgents,
  overview: viewOverview, outreach: viewOutreach, relationships: viewRelationships, linkedin: viewLinkedin, pipeline: viewPipeline, inbox: viewInbox, tasks: viewTasks, website: viewWebsite,
  contacts: viewContacts, companies: viewCompanies, finance: () => revenuePanel() + viewFinance() + weeklyPanel(), costs: viewCosts, markets: viewMarkets, growth: viewGrowth,
  intelligence: viewIntelligence, reports: viewReports, system: (d) => healthPanel() + viewSystem(d) + teamPanel(), help: viewHelp,
  radar: viewRadar, library: viewLibrary, actions: viewActions, partners: viewPartners, events: viewEvents, projects: viewProjects,
  agent: viewAgent, emails: viewEmails, agentradar: viewAgentRadar, feed: viewFeed };

// Refresh: every 60s normally, every 5s for two minutes after an approval. Paused while typing,
// or while a modal / record / menu is open.
// Light refresh every 2 minutes (the desk and the background snapshots, which are cheap), a full refresh every 10 minutes,
// and after an approval only the desk every 15 s for two minutes, to show the Gmail draft arriving. Paused in a hidden tab.
// New deploy: the first fingerprint seen is this tab's build; a different one later means HQ was updated.
async function checkVersion() {
  try {
    const r = await fetch('/version.json', { cache: 'no-store' }); if (!r.ok) return;
    const { v } = await r.json(); if (!v) return;
    if (!state.buildV) state.buildV = v; else if (v !== state.buildV) state.updateReady = true;
  } catch { /* offline or local file: ignore */ }
}
checkVersion();
setInterval(() => {
  if (!state.session || state.modal || state.drawer || state.menu || state.q || mustChangePassword() || document.hidden) return;
  // Reload an idle tab onto the new build rather than keep running superseded code.
  if (state.updateReady && !state.inflight && !document.querySelector('textarea:focus, input:focus')) { location.reload(); return; }
  const tick = Math.floor(Date.now() / 5000);
  if (tick % 120 === 60) checkVersion();
  if (Date.now() < state.pollUntil) { if (tick % 3 === 0) load(true, 'desk'); return; }
  if (tick % 120 === 0) load(true, 'full'); else if (tick % 24 === 0) load(true, 'light');
}, 5000);

initAuth();
