// The morning lists and the LinkedIn Relationship Agent (19 Oct) read new keys on hq_outreach_desk: top5, linkedin, meeting_assist
// and studio_ready. When a desk capture predates them, they are added in memory only, from the capture's own Needs review items
// (real refs, people and drafts), so the UI is tested against the shape the live read returns. Nothing is written to the fixture.
const id = (n) => `00000000-0000-0000-0000-0000000001${String(n).padStart(2, '0')}`;
export function withMorning(desk, opportunities = []) {
  if (desk.top5) return desk;
  const nr = desk.needs_review || [];
  const em = nr.filter((x) => x.channel === 'EMAIL').slice(0, 3);
  const li = nr.filter((x) => x.channel === 'LINKEDIN' && x.task_id && x.contact_id);
  const top5 = [...em, ...li.slice(0, 5 - em.length)].map((x, i) => ({ ref: x.ref, score: 90 - i * 6, channel: x.channel,
    why: [i === 0 ? 'Destination Egypt' : null, 'senior decision maker', 'clear why-now', x.channel === 'EMAIL' ? 'email route' : 'LinkedIn (email exhausted)'].filter(Boolean).join(' · ') }));
  const states = ['READY', 'READY', 'CONNECTION_SENT', 'CONNECTED', 'SENT', 'REPLIED'];
  const linkedin = li.slice(0, states.length).map((x, i) => ({
    id: id(i), state: states[i], connection: i === 3 ? 'CONNECTED' : i === 2 ? 'NOT_CONNECTED' : 'UNKNOWN', person: x.person, first_name: String(x.person || '').split(' ')[0], role: x.role,
    linkedin: x.route?.linkedin || null, company: x.company, company_id: x.company_id, contact_id: x.contact_id, opportunity_id: x.opportunity_id, task_id: x.task_id,
    director: x.director, project: 'Destination wedding in Egypt', why_them: x.angle, why_now: x.why_now, relationship: 'COLD', message: x.draft,
    connection_note: i === 0 ? 'Hello, I run NOYA, a concierge and production company in Egypt. I would value connecting given your work with destination weddings.' : null,
    followup: i === 3 ? 'Thank you for connecting. A short note on why I reached out: Egypt is opening up for weddings next year and NOYA runs the ground for planners. Would a 20-minute call next week be useful?' : null,
    next_action: i === 5 ? 'Copy the suggested response, edit, and send it on LinkedIn.' : 'Copy the message, open LinkedIn and send it yourself, then press Mark sent.',
    sent_at: i >= 4 ? new Date(Date.now() - 3 * 864e5).toISOString() : null, replied_at: i === 5 ? new Date(Date.now() - 36e5).toISOString() : null,
    reply_text: i === 5 ? 'Thanks Adam, interesting timing. What would a first project look like?' : null, reply_class: i === 5 ? 'QUESTION' : null,
    response_draft: i === 5 ? 'Thank you. [Answer the question in one or two lines.] Happy to explain more on a short call if useful.' : null,
    meeting_task_id: null, hold_reason: null, created_at: x.created_at, words: String(x.draft || '').trim().split(/\s+/).filter(Boolean).length,
    // From the LinkedIn data download (20 Oct): the second ready item is already a connection with an old two-way conversation.
    ...(i === 1 ? { li_connected: true, li_state: 'DORMANT', li_reason: '4 messages (2 from them) · last 12 Mar 2023, they wrote last · connected since Jan 2021', li_last_at: '2023-03-12T10:00:00Z' } : {}) }));
  const o = opportunities.find((x) => x.contact_name && x.company_name) || {};
  const meeting_assist = o.id ? [{ task_id: id(90), title: `MEETING ASSIST -- ${o.company_name}`, company: o.company_name, company_id: null, opportunity_id: o.id, person: o.contact_name,
    source: 'LINKEDIN', state: 'SLOTS_PROPOSED', slots: [{ start: '2026-10-22T09:00:00+00:00', end: '2026-10-22T09:30:00+00:00' }, { start: '2026-10-23T14:00:00+00:00', end: '2026-10-23T14:30:00+00:00' }],
    reply: 'Would Thu 22 Oct 10:00 or Fri 23 Oct 15:00 (UK time) suit for a 20-minute call?', timezone: 'Europe/London', checked_at: new Date().toISOString(), created_at: new Date().toISOString() }] : [];
  const studio_ready = [{ id: id(80), slug: 'crush-egypt-brief', title: 'CRUSH Agency: Egypt brief', company: 'CRUSH Agency', status: 'FOR_REVIEW', level: 3, doc_type: 'BRIEF', hold_reason: null, created_at: new Date().toISOString() }];
  return { ...desk, top5, linkedin, meeting_assist, studio_ready };
}
