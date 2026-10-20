// The Commercial Creative Operator's read model for the UI tests (made-up relationships only): one operator recommendation,
// one rule-based baseline, and a past-conversation list with a CRM company, an address not in the CRM and a LinkedIn conversation.
const ctx = (o = {}) => ({ company: 'Atlas Agency', last_in: '2026-09-29T10:00:00Z', last_out: '2026-10-08T15:00:00Z', meetings: 1, inbound: 2, threads: 2,
  thread: '1a0000000000test', state: 'MEETING_BOOKED', docs: [{ slug: 'atlas-brief', version: 4, title: 'Your brief. Egypt, brought to life.', stage: 'master', status: 'FOR_REVIEW',
    ready_class: 'READY_TO_SEND', ready_reason: 'Passed the Brand & Quality Reviewer', level: 3, audience: 'CLIENT', sent_at: null }], outputs: [], ...o });
export const NEXT_MOVE = {
  ok: true, key: 'co:00000000-0000-0000-0000-00000000a001', company_id: '00000000-0000-0000-0000-00000000a001',
  operator: { id: '00000000-0000-0000-0000-00000000b001', rel_key: 'co:00000000-0000-0000-0000-00000000a001', kind: 'LIVE', status: 'PROPOSED', channel: 'EMAIL',
    action: 'SEND_PREPARED', action_label: 'Approve the brief, then send the follow-up with it',
    situation: 'Call with the agency on 8 Oct; NOYA wrote last, 12 days ago.', need: 'An Egypt execution partner the agency can sell under its own name.',
    value_note: 'Agency channel. No brief or budget yet.', why_now: 'Giza is busy this autumn.', message_subject: 'Re: Egypt',
    recommended_message: 'Hi Sam,\n\nFollowing our call, I have prepared a short Egypt brief.\n\nBest,\nAdam', asset_slug: 'atlas-brief',
    asset_note: 'Master brief v4, 3 pages: approve, then attach it to the Gmail draft.', gmail_thread_id: '1a0000000000test', gmail_draft_id: 'r000test',
    last_contact_at: '2026-10-08T15:00:00Z', last_by: 'NOYA', recency_band: '0-30', created_by: 'Commercial Creative Operator', created_at: '2026-10-20T08:00:00Z' },
  baseline: { source: 'BASELINE', action: 'SEND_PREPARED', band: '0-30', days: 12, last_by: 'NOYA', situation: 'NOYA wrote last, 12 days ago.', reason: 'A document has passed review.' },
  context: ctx(), history: [],
  timing: [{ title: 'Forever Is Now 06, Giza', date: '2026-11-04', end: '2026-11-28', city: 'Giza', linked: false }],
};
export const NEXT_MOVE_BASE = { ...NEXT_MOVE, operator: null,
  baseline: { source: 'BASELINE', action: 'RECONNECT', band: '31-90', days: 52, last_by: 'NOYA', situation: 'NOYA wrote last, 52 days ago (they have replied before).',
    reason: 'Reconnect with context from the last conversation.', last_at: '2026-08-29T10:00:00Z' }, context: ctx({ docs: [] }) };
export const REOPEN = {
  operator: [],
  gmail: [
    { key: 'co:00000000-0000-0000-0000-00000000a002', name: 'Harbour Hotel Group', company: 'Harbour Hotel Group', company_id: '00000000-0000-0000-0000-00000000a002',
      threads: 2, sent: 3, received: 2, last_at: '2026-08-20T10:00:00Z', last_by: 'NOYA', owes_reply: false, band: '31-90', days: 61, thread: '1a0000000000hhg',
      subject: 'Egypt for your guests', summary: 'They asked for winter rates; NOYA sent options.', recommended: 'RECONNECT', rule: 'Reconnect with context from the last conversation.' },
    { key: 'e:someone@example.com', name: 'Someone Example', company: null, company_id: null, email: 'someone@example.com',
      threads: 1, sent: 1, received: 1, last_at: '2026-03-02T10:00:00Z', last_by: 'THEM', owes_reply: true, band: '3-12M', days: 232, thread: '1a0000000000ex',
      subject: 'Private trip', summary: null, recommended: 'DRAFT_REPLY', rule: 'Only with a credible new reason.' }],
  linkedin: [],
  counts: { gmail: 2, owes_reply: 1, linkedin: 0 },
};
