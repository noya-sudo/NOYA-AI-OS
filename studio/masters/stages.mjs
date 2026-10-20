// Stage builders: Reply / Meeting → Concept → Brief → Proposal → Project, plus client and operations itineraries and the
// NOYA Private services overview. Each takes a case (studio/cases/<slug>.json) and its master (verticals.mjs) and returns
// a document for templates.mjs. The master supplies structure and NOYA's approved wording; the case supplies every fact
// and the idea. A builder stops if the case lacks what the stage needs, so nothing is padded with invented content.
import { CONTACT, PERMITS, INDICATIVE, APPROVE_FIRST, NOYA_IS, PRIVATE_PROCESS, PRIVATE_PRINCIPLES, STAGE_LABEL, SOURCES } from './library.mjs';
import { withParty } from './verticals.mjs';

const need = (cond, msg) => { if (!cond) throw new Error(msg); };
const CLIENT_CLASSES = ['VERIFIED', 'PUBLIC', 'NOYA MATERIAL'];

function counter() {
  let n = 0;
  return (label, title) => ({ t: 'section', n: String(++n).padStart(2, '0'), label, title });
}

function base(c, v, stage, extra = {}) {
  return {
    slug: `${c.slug}-${stage}`, type: stage, stage, vertical: v.key, master_label: v.label,
    company: c.company, company_id: c.company_id || null, opportunity_id: c.opportunity_id || null,
    date: c.date, prepared_for: c.prepared_for, cover: { ...v.cover, ...(c.cover || {}) },
    running: `${c.party} × NOYA · ${extra.running || stage}`, audience: 'client', ...extra,
  };
}

// A "why now" row prints only a fact the case can source as verified, public or NOYA material.
function whyRows(c, rows) {
  return (rows || []).map((r) => {
    const f = (c.facts || []).find((x) => x.id === r.fact);
    need(f, `${c.slug}: why-row "${r.label}" cites missing fact "${r.fact}"`);
    need(CLIENT_CLASSES.includes(f.class), `${c.slug}: fact "${r.fact}" is ${f.class}; only ${CLIENT_CLASSES.join(', ')} facts print in client documents`);
    return [r.label, r.text || f.text];
  });
}

const roles = (c, v, o = {}) => ({
  t: 'roles',
  left: { title: `${c.party} leads`, items: o.leads || v.leads },
  right: { title: 'NOYA delivers in Egypt', items: (o.delivers || v.delivers).map((s) => withParty(s, c.party)) },
});

const sourcesOf = (c) => (c.facts || []).map((f) => ({ fact: f.text, source: f.source, class: f.class }));

// ---------------------------------------------------------------- Opportunity note (internal): Reply / Meeting
export function note(c, v) {
  const s = counter();
  const st = c.status || {};
  const doc = base(c, v, 'note', {
    audience: 'internal', running: 'Opportunity note', eyebrow: `${v.label} · Opportunity note`,
    title: c.note?.title || c.company, subtitle: c.need, prepared_for: 'Adam Elshazly', for_label: 'For',
    cover: { style: 'paper', position: 'high', quiet: true },
  });
  need(c.facts?.length, `${c.slug}: an opportunity note needs facts`);
  const desk = v.deskInfo[0];
  doc.pages = [
    { blocks: [
      s('Where it stands', c.note?.headline || `${STAGE_LABEL[st.stage] || st.stage || 'Status not recorded'}.`),
      { t: 'kv', cols: 3, items: [['Company', c.company], ['Lane', v.label], ['Stage', STAGE_LABEL[st.stage] || st.stage], ['Last contact', st.last_contact], ['Next action', st.next_action], ['Value', st.value],
        ['Relationship', c.relationship?.state ? c.relationship.state[0].toUpperCase() + c.relationship.state.slice(1) : null], ['Earned level', LEVEL_NAME[allowedLevel(c)]],
        ['Held', gate(c).filter((g) => g.hold).map((g) => g.stage).join(', ') || 'Nothing held']] },
      { t: 'kv', cols: 2, items: (c.people || []).map((p) => [p.role, `${p.name} · ${p.route || 'route not recorded'}`]) },
      ...(c.timeline?.length ? [s('Relationship', 'What has happened so far.'), { t: 'timeline', items: c.timeline }] : []),
    ] },
    { blocks: [
      s('What we know', 'Facts, with their source.'),
      ...Array.from({ length: Math.ceil(c.facts.length / 6) }, (_, i) => ({ t: 'facts', items: c.facts.slice(i * 6, i * 6 + 6) })),  // pages break between blocks
      s('What they need', 'Our reading, to test on the call.'),
      { t: 'facts', items: [{ text: c.need, source: 'NOYA reading of the facts above', class: 'INFERRED' }] },
      { t: 'ledger', rows: [['Product desk', `${desk.name}${v.deskInfo[1] ? ` (with ${v.deskInfo[1].name})` : ''}`], ['Proposal shape', desk.proposal]] },
    ] },
    { blocks: [
      s('Next document', 'What moves this forward.'),
      { t: 'callout', label: `Recommended · ${c.next_doc?.stage || 'not set'}`, big: c.next_doc?.why || 'Not recorded', text: c.next_doc?.when },
      s('Open questions', 'To answer before the proposal.'),
      { t: 'check', items: (c.questions || v.questions).map((q) => ({ text: q, status: 'To ask' })) },
      s('Expected objections', 'And the answer.'),
      { t: 'ledger', rows: v.deskInfo.flatMap((d) => d.objections) },
      ...(c.risks?.length || v.rules?.length ? [s('Rules for this account', 'Do not.'), { t: 'check', items: [...(v.rules || []), ...(c.risks || [])].map((r) => ({ text: r, status: 'Rule' })) }] : []),
    ] },
  ];
  doc.sources = sourcesOf(c);
  return doc;
}

// ---------------------------------------------------------------- Concept (client)
export function concept(c, v) {
  const k = c.concept;
  need(k?.idea_title && k?.lead && k?.options?.length, `${c.slug}: a concept needs its own idea (idea_title, lead, options); the master never invents one`);
  const s = counter();
  const doc = base(c, v, 'concept', {
    running: 'Egypt concept', eyebrow: k.eyebrow || `Egypt · Concept`, title: k.title, subtitle: k.subtitle,
  });
  const pages = [
    { blocks: [
      s('The idea', k.idea_title), { t: 'lead', text: k.lead },
      ...(k.quote ? [{ t: 'quote', text: k.quote }] : []),
      ...(k.why?.length ? [s(k.why_label || 'Why now', k.why_title || 'Why Egypt, now.'), { t: 'ledger', rows: whyRows(c, k.why) }] : []),
    ] },
    { blocks: [
      s(k.options_label || 'The settings', k.options_title || 'Choose the stage.'),
      { t: 'options', items: k.options }, { t: 'note', text: PERMITS },
      ...(k.fits?.length ? [{ t: 'gap' }, s(k.fits_label || 'Where it fits', k.fits_title || 'Where each option fits.'), { t: 'ledger', rows: k.fits }] : []),
    ] },
    { blocks: [
      s('How it works', `${c.party} leads. NOYA delivers.`), roles(c, v, k), { t: 'gap' },
      ...(k.journey?.length ? [s(k.journey_label || 'The guest journey', k.journey_title || 'An example programme.'), { t: 'journey', items: k.journey }] : []),
      { t: 'p', text: k.journey_note || v.journeyNote },
    ] },
    { kind: 'closing', blocks: [s('Next step', k.next_title || 'Thirty minutes to choose.'), { t: 'steps', items: k.next || defaultNext(c) }], contact: CONTACT },
  ];
  doc.pages = pages;
  doc.sources = sourcesOf(c);
  doc.review = [...(c.review || []), ...(k.review || [])];
  return doc;
}

function defaultNext(c) {
  return [
    { title: 'Choose a direction', text: `One call to agree where Egypt fits best for ${c.party}.` },
    { title: 'NOYA returns a costed proposal', text: 'Venues, hospitality and logistics with a clear budget.' },
    { title: 'Holds and permits', text: 'Once approved, NOYA holds venues and begins permits with our local partners.' },
  ];
}

// ---------------------------------------------------------------- Brief (client): pre-filled from what we know
export function brief(c, v) {
  const b = c.brief;
  need(b?.title && b?.lead, `${c.slug}: a brief needs title and lead`);
  const s = counter();
  const doc = base(c, v, 'brief', { running: 'Egypt brief', eyebrow: b.eyebrow || 'Egypt · Brief', title: b.title, subtitle: b.subtitle });
  const known = b.known || {};
  const fields = (b.fields || v.briefFields).map((f) => ({ ...f, value: known[f.label] ?? null }));
  const unknownKnown = Object.keys(known).filter((k) => !fields.some((f) => f.label === k));
  need(!unknownKnown.length, `${c.slug}: brief.known has fields the master does not ask: ${unknownKnown.join(', ')}`);
  doc.pages = [
    { blocks: [
      s('Where we are', b.where_title || 'A shared view of Egypt.'), { t: 'lead', text: b.lead },
      ...(b.quote ? [{ t: 'quote', text: b.quote, by: b.quote_by }] : []),
      s('How we work together', 'One brief, two clear roles.'), roles(c, v, b),
      { t: 'p', text: b.roles_note || `The client relationship stays with ${c.party}. NOYA works behind your brand, as the Egypt team you can call on.` },
    ] },
    { blocks: [
      s(b.fit_label || 'Where Egypt fits', b.fit_title || 'Formats and places.'), { t: 'ledger', rows: b.fit || v.fit },
      ...(b.idea ? [s('A starting idea', b.idea.section_title || 'One idea to start.'), { t: 'feature', label: b.idea.label, big: b.idea.big, paras: b.idea.paras }] : []),
      ...(b.journey?.length ? [{ t: 'journey', items: b.journey }] : []),
      { t: 'note', text: INDICATIVE },
    ] },
    { blocks: [
      s('The brief we need', Object.keys(known).length ? 'What we have, and what we still need.' : 'Everything we need to propose.'),
      { t: 'lead', text: !Object.keys(known).length ? (b.form_lead || 'Share what you can. The client\'s name can stay confidential until there is a fit.')
        : b.known_from === 'concept' ? 'We have filled in the direction from our concept. Correct anything, and add what you can.'
        : 'We have filled in what we understood from our conversation. Correct anything, and add what you can.' },
      { t: 'form', fields },
      { t: 'note', text: 'Return to noya@noyaconcierge.com, or reply to our email with whatever is known today. We will come back with questions only where they change the proposal.' },
    ] },
    { kind: 'closing', blocks: [s('Next steps', 'From brief to proposal.'), { t: 'steps', items: b.next || [
      { title: 'Share the brief', text: 'Whatever is known today; the rest can follow.' },
      { title: 'NOYA returns a concept and a costed proposal', text: `Locations, hospitality and logistics with a clear budget, ready for ${c.party} to present.` },
      { title: 'Holds and permits', text: 'Once approved, NOYA holds venues and begins permits with our local partners.' }] }], contact: CONTACT },
  ];
  doc.sources = sourcesOf(c);
  doc.review = [...(c.review || []), ...(b.review || [])];
  return doc;
}

// ---------------------------------------------------------------- Proposal (client once fees are approved; draft until then)
export function proposal(c, v) {
  const p = c.proposal;
  need(p?.understanding && p?.scope?.length, `${c.slug}: a proposal needs understanding and scope`);
  const s = counter();
  const fees = p.fees || v.feeRows.map((r) => [r, null]);
  for (const [label, val] of fees) need(val == null || p.fees_approved_by, `${c.slug}: fee "${label}" has a value but no fees_approved_by; fees print only once Adam approves them`);
  const draft = fees.some(([, val]) => val == null) ? 'Draft · fees not approved · not for client' : null;
  const doc = base(c, v, 'proposal', { running: 'Proposal', eyebrow: p.eyebrow || 'Egypt · Proposal', title: p.title, subtitle: p.subtitle, draft, reference: p.reference });
  doc.pages = [
    { blocks: [
      s('Our understanding', p.understanding_title || 'What you asked for.'), { t: 'lead', text: p.understanding },
      ...(p.parameters?.length ? [{ t: 'kv', cols: 3, items: p.parameters }] : []),
      s('What NOYA delivers', 'Scope.'), { t: 'table', cols: ['Element', 'What it includes'], widths: ['34%', '66%'], rows: p.scope },
    ] },
    { blocks: [
      ...(p.programme?.length ? [s('Programme', p.programme_title || 'How it runs.'), { t: 'table', cols: ['When', 'What happens'], widths: ['24%', '76%'], rows: p.programme }] : []),
      s('Investment', 'Fees.'), { t: 'fees', rows: fees }, { t: 'p', text: p.fee_model || v.feeModel }, { t: 'note', text: APPROVE_FIRST },
    ] },
    { blocks: [
      s('Assumptions', 'What this proposal assumes.'), { t: 'check', items: (p.assumptions || []).map((a) => ({ text: a, status: 'Assumed' })) },
      { t: 'note', text: PERMITS },
    ] },
    { kind: 'closing', blocks: [s('Next steps', 'To confirm.'), { t: 'steps', items: p.next || [
      { title: 'Review and questions', text: 'One call to adjust scope and programme.' },
      { title: 'Approval', text: 'A signed approval of scope and fees.' },
      { title: 'Holds and permits', text: 'NOYA holds venues and begins permits with our local partners.' }] }], contact: CONTACT },
  ];
  doc.sources = sourcesOf(c);
  doc.review = [...(c.review || []), ...(p.review || []), ...(draft ? ['Fees are Not recorded until Adam approves them; the document is marked Draft until then.'] : [])];
  return doc;
}

// ---------------------------------------------------------------- Project book (internal): from approval to delivery
export function project(c, v) {
  const p = c.project || {};
  const s = counter();
  const doc = base(c, v, 'project', {
    audience: 'internal', running: 'Project book', eyebrow: `${v.label} · Project book`, title: p.title || `${c.company} — project book`,
    subtitle: p.subtitle, prepared_for: 'Adam Elshazly and the NOYA team', for_label: 'For', cover: { style: 'paper', position: 'high', quiet: true },
  });
  const ws = (p.workstreams || v.workstreams.map(([w, sc]) => [w, sc, null, 'Not started']));
  doc.pages = [
    { blocks: [
      s('Project', p.status_title || 'Where the project stands.'),
      { t: 'kv', cols: 3, items: p.summary || [['Client', c.company], ['Status', p.status || 'Not won'], ['NOYA lead', 'Adam Elshazly'], ['Client lead', null], ['Dates', null], ['Value', null]] },
      s('Workstreams', 'Who owns what.'), { t: 'table', cols: ['Workstream', 'Scope', 'NOYA owner', 'Status'], widths: ['22%', '42%', '18%', '18%'], rows: ws },
    ] },
    { blocks: [
      s('Milestones', 'From approval to the day.'), { t: 'table', cols: ['When', 'Milestone', 'Owner', 'Status'], widths: ['18%', '48%', '16%', '18%'], rows: p.milestones || [] },
      s('Suppliers', 'Named only once confirmed.'), { t: 'table', cols: ['Category', 'Supplier', 'Status'], widths: ['34%', '40%', '26%'], rows: p.suppliers || [] },
    ] },
    { blocks: [
      s('Approvals', 'Signed off before booking.'), { t: 'check', items: (p.approvals || []).map((a) => ({ text: a, status: 'Pending' })) },
      s('Risks and contingencies', 'Known before the day.'), { t: 'ledger', rows: p.risks || [] },
    ] },
  ];
  doc.sources = sourcesOf(c);
  return doc;
}

// ---------------------------------------------------------------- Itinerary (client) and operations itinerary (internal)
export function itinerary(c, v) {
  const it = c.itinerary;
  need(it?.days?.length, `${c.slug}: an itinerary needs days`);
  const s = counter();
  const doc = base(c, v, 'itinerary', { running: 'Itinerary', eyebrow: it.eyebrow || 'Itinerary', title: it.title, subtitle: it.subtitle, cover: { style: 'paper', position: 'low' }, prepared_for: it.prepared_for || c.prepared_for });
  doc.pages = [
    { blocks: [
      s('Your programme', it.programme_title || 'Day by day.'),
      { t: 'itinerary', days: it.days.map((d) => ({ n: d.n, label: d.label, date: d.date, items: d.items.map((x) => ({ time: x.time, title: x.title, text: x.text })) })) },
      { t: 'note', text: it.sample ? `Sample programme. ${INDICATIVE}` : INDICATIVE },
    ] },
    ...(it.practical?.length ? [{ blocks: [s('Practical', 'Good to know.'), { t: 'ledger', rows: it.practical }] }] : []),
    { kind: 'closing', blocks: [s('Your NOYA contact', 'One contact, throughout.'), { t: 'p', text: 'Before and during the programme, one NOYA lead coordinates every arrangement.' }], contact: CONTACT },
  ];
  return doc;
}

export function ops(c, v) {
  const it = c.itinerary;
  need(it?.days?.length, `${c.slug}: an operations itinerary needs days`);
  const s = counter();
  const doc = base(c, v, 'ops', {
    audience: 'internal', running: 'Operations itinerary', eyebrow: 'Operations itinerary', title: it.ops_title || `${it.title.replace(/\*/g, '')} — operations`,
    subtitle: 'Every movement, supplier and status. Unconfirmed items read To confirm.', prepared_for: 'NOYA on-ground team', for_label: 'For',
    cover: { style: 'paper', position: 'high', quiet: true },
  });
  const DAY = ['one', 'two', 'three', 'four', 'five', 'six', 'seven'];
  doc.pages = [{ blocks: it.days.flatMap((d, i) => [
    s(`Day ${DAY[i] || i + 1}`, d.label),
    { t: 'table', compact: true, cols: ['Time', 'Item', 'Location', 'Supplier / driver', 'Contact', 'Status'], widths: ['11%', '25%', '19%', '17%', '14%', '14%'],
      rows: d.items.map((x) => [x.time, x.title, x.ops?.location ?? null, x.ops?.supplier ?? null, x.ops?.contact ?? null, x.ops?.status || 'To confirm']) },
  ]) }];
  doc.pages.push({ blocks: [
    s('Escalation', 'Who to call.'), { t: 'ledger', rows: it.escalation || [['NOYA lead', 'Adam Elshazly · +44 786 456 9006'], ['Security lead', 'To confirm'], ['Venue contact', 'To confirm'], ['Transport lead', 'To confirm']] },
    s('Contingencies', 'Decided in advance.'), { t: 'check', items: (it.contingencies || []).map((x) => ({ text: x, status: 'To confirm' })) },
  ] });
  return doc;
}

// ---------------------------------------------------------------- NOYA Private services overview (client, for representatives)
export function desk(c, v) {
  const d = c.desk;
  need(d?.title, `${c.slug}: a private services overview needs a title`);
  const s = counter();
  const doc = base(c, v, 'desk', { running: 'NOYA Private · Egypt Desk', eyebrow: 'NOYA Private · Egypt Desk', title: d.title, subtitle: d.subtitle, type_label: 'Private services' });
  doc.pages = [
    { blocks: [
      s('A discreet partner', d.intro_title || 'Egypt, handled privately.'),
      { t: 'lead', text: d.lead || 'A discreet on-ground partner in Egypt for your clients. You keep the client and the relationship. NOYA handles Egypt privately, under your name if you prefer.' },
      ...(d.why?.length ? [{ t: 'ledger', rows: whyRows(c, d.why) }] : []),
      s('What we arrange', 'For your clients and their families.'), roles(c, v),
    ] },
    { blocks: [
      s('How it works', 'One relationship. Every request.'), { t: 'steps', items: PRIVATE_PROCESS },
      s('Principles', 'Discretion at every level.'), { t: 'ledger', rows: PRIVATE_PRINCIPLES },
      { t: 'note', text: 'We never name clients, and nothing is shared without your consent. Properties are proposed on what each one can confirm about privacy, access and security.' },
    ] },
    { kind: 'closing', blocks: [s('Next step', d.next_title || 'A short private call.'), { t: 'steps', items: d.next || [
      { title: 'A private call', text: 'Fifteen minutes to understand how your team handles client requests today.' },
      { title: 'NOYA on file', text: 'One contact and one line for any Egypt request, under your name if you prefer.' }] }], contact: CONTACT },
  ];
  doc.sources = [...sourcesOf(c), { fact: 'Services, process and principles', source: `${SOURCES.privatePdf}; ${SOURCES.egyptDesk}`, class: 'NOYA MATERIAL' }];
  doc.review = [...(c.review || []), ...(d.review || [])];
  return doc;
}

// ---------------------------------------------------------------- Level 1: the idea, inside the email (text, no attachment)
const words = (s) => String(s).trim().split(/\s+/).filter(Boolean).length;
export function email(c, v) {
  const e = c.email;
  need(e?.to_name && e?.subject && e?.paragraphs?.length, `${c.slug}: an email idea needs to_name, subject and paragraphs`);
  const n = words(e.paragraphs.join(' '));
  need(n <= 150, `${c.slug}: the email idea is ${n} words; Level 1 stays under 150`);
  // The mail connector cannot attach a stored PDF, so the draft never claims one: the text stands on its own and the PDF is
  // Adam's one action (ATTACH APPROVED PDF), recorded on the output with its version, filename and provenance.
  need(!/\battach|\benclos|\bplease find\b|\bsee the (pdf|document)\b/i.test(e.paragraphs.join(' ')),
    `${c.slug}: the email must not say a file is attached; the attachment is Adam's action (ATTACH APPROVED PDF)`);
  const body = [`Hi ${e.to_name},`, ...e.paragraphs, `Best,\n${CONTACT.name}\n${CONTACT.role}\n${CONTACT.lines[2]}`].join('\n\n');
  return { slug: `${c.slug}-email`, type: 'email', stage: 'email', vertical: v.key, company: c.company, company_id: c.company_id || null,
    opportunity_id: c.opportunity_id || null, date: c.date, prepared_for: c.prepared_for, audience: 'client', title: e.subject,
    to: e.to || [], reply_to_message_id: e.reply_to_message_id || null, attach: e.attach || null,
    attach_action: e.attach ? `ATTACH APPROVED PDF: ${c.slug}-${e.attach}` : null, subject: e.subject, body, words: n,
    sources: sourcesOf(c), review: [...(e.review || [])] };
}

// ---------------------------------------------------------------- Level 2: the concept on one page (strong or warm opportunities)
export function onepage(c, v) {
  const k = c.concept;
  need(k?.idea_title && k?.lead && k?.options?.length, `${c.slug}: a one-page concept needs the case's own idea (idea_title, lead, options)`);
  const doc = base(c, v, 'onepage', { running: 'Egypt concept', eyebrow: k.eyebrow || 'Egypt · Concept', title: k.title, subtitle: k.one_subtitle || k.subtitle });
  const meta = (o) => (o.meta?.length ? [o.meta[0], o.meta[o.meta.length - 1]] : []);
  const nxt = (k.next || defaultNext(c))[0];
  doc.pages = [{ kind: 'one', blocks: [
    { t: 'section', label: 'The idea', title: k.idea_title }, { t: 'lead', text: k.one_lead || k.lead },
    { t: 'options', items: k.options.map((o) => ({ n: o.n, title: o.title, text: o.one_text || o.text, meta: meta(o) })) },
    ...(k.why?.length ? [{ t: 'ledger', rows: whyRows(c, k.why).slice(0, k.one_why || 2) }] : []),
    { t: 'strip', label: 'Next step', title: k.next_title || 'Thirty minutes to choose.', text: nxt.text, contact: CONTACT },
    { t: 'note', text: PERMITS },
  ] }];
  doc.sources = sourcesOf(c);
  doc.review = [...(c.review || []), ...(k.review || [])];
  return doc;
}

// ---------------------------------------------------------------- Master brief (client): 2-3 pages with NOYA library imagery
// Page one: NOYA × client, a title for this client, one strong image, the positioning and why Egypt, why now (cited facts only).
// Page two: the concept and where NOYA fits (formats, places, an example evening). Page three: what each side handles, why it
// works commercially, the next step and the contact. Two pages when two are stronger; never padded. It replaces the form-based
// brief for a case that sets "master", and carries the brief's slug so its versions continue the brief's history.
export function master(c, v) {
  const m = c.master;
  need(m?.title && m?.positioning && m?.hero?.img && m?.pages?.length, `${c.slug}: a master brief needs title, positioning, hero image and pages`);
  need(m.pages.length <= 2, `${c.slug}: a master brief is two or three pages; it has ${m.pages.length + 1}`);
  need((m.why || []).length >= 2, `${c.slug}: a master brief needs at least two cited why-now rows`);
  const last = m.pages[m.pages.length - 1];
  need(last.next?.title && last.next?.text, `${c.slug}: the last page of a master brief carries the next step`);
  const doc = base(c, v, 'master', {
    slug: `${c.slug}-brief`, running: `${c.party} × NOYA · ${m.running || 'Egypt'}`, eyebrow: m.eyebrow || `NOYA × ${c.party} · Egypt`,
    title: m.title, positioning: m.positioning, party_mark: m.party_mark || c.party.toUpperCase(), type_label: 'Brief',
  });
  doc.pages = [
    { kind: 'm-hero', img: m.hero.img, pos: m.hero.pos, why_label: m.why_label, why: whyRows(c, m.why) },
    ...m.pages.map((p, i) => ({ kind: i === m.pages.length - 1 ? 'm-close' : 'm-body', running: p.running, blocks: p.blocks,
      ...(i === m.pages.length - 1 ? { next: p.next, contact: CONTACT } : {}) })),
  ];
  doc.sources = sourcesOf(c);
  doc.review = [...(c.review || []), ...(m.review || [])];
  return doc;
}

export const STAGES = { note, email, onepage, concept, brief, master, proposal, project, itinerary, ops, desk };
export const CLIENT_STAGES = ['email', 'onepage', 'concept', 'brief', 'master', 'proposal', 'itinerary', 'desk'];

// ---------------------------------------------------------------- Output levels: produce only what the relationship has earned
// Level 1 email idea (any prospect) · Level 2 one-page concept (strong or warm) · Level 3 full concept, brief, proposal and
// delivery documents (after demonstrated interest, a meeting or an actual brief). Internal notes are level 0.
export const LEVEL = { note: 0, email: 1, onepage: 2, concept: 3, brief: 3, master: 3, proposal: 3, itinerary: 3, desk: 3, project: 3, ops: 3 };
const STATE_LEVEL = { declined: 0, cold: 1, warm: 2, engaged: 3 };
export const LEVEL_NAME = { 0: 'Internal', 1: 'Level 1 · email idea', 2: 'Level 2 · one-page concept', 3: 'Level 3 · full brief / proposal' };

// The highest level a case has earned. warm, engaged and declined must cite a VERIFIED fact (the reply, the meeting, the
// decline); a cold opportunity reaches Level 2 only when it is strong, citing a dated public or verified trigger.
export function allowedLevel(c) {
  if (c.slug.startsWith('preview-')) return 3;  // template previews show every level; they are never sent
  const r = c.relationship;
  need(r && r.state in STATE_LEVEL, `${c.slug}: relationship.state must be one of ${Object.keys(STATE_LEVEL).join(', ')}`);
  const cite = (id, classes) => {
    const f = (c.facts || []).find((x) => x.id === id);
    need(f && classes.includes(f.class), `${c.slug}: relationship evidence "${id}" must be a ${classes.join(' or ')} fact`);
  };
  if (r.state !== 'cold') cite(r.fact, ['VERIFIED']);
  if (r.state === 'cold' && c.strong) { cite(c.strong.fact, ['VERIFIED', 'PUBLIC']); return 2; }
  return STATE_LEVEL[r.state];
}

// Each document a case asks for, with its level and hold. A client document above the earned level is built only when the
// case holds it ("hold": prepared ahead, not to be sent until the relationship reaches that level); otherwise the build stops.
export function gate(c) {
  const max = allowedLevel(c);
  return c.build.map((stage) => {
    const level = LEVEL[stage];
    need(level != null, `${c.slug}: unknown stage "${stage}"`);
    if (level <= max) return { stage, level, hold: null };
    need((c.hold || []).includes(stage), `${c.slug}: ${stage} is ${LEVEL_NAME[level]}, but ${c.company} has earned ${LEVEL_NAME[max]} (${c.relationship.state}). Build a lower level, or list "${stage}" in "hold".`);
    return { stage, level, hold: max === 0 ? `Held: ${c.company} declined; send only if they reopen.` : `Held until ${LEVEL_NAME[level]}: ${c.relationship.state} today.` };
  });
}
