// NOYA Studio templates. A document is data (studio/documents/*.json); these functions turn it into A4 pages.
// Every master (Brand, Weddings, Media, NOYA Private, Travel, Corporate, Retreats, Itineraries) shares one block library,
// so every document reads as the same house. Internal documents carry a visible "Internal" flag on every page, and a
// proposal whose fees are not all approved carries "Draft · not for client".

const TYPE = {
  note: { label: 'Opportunity note' },
  brief: { label: 'Brief' },
  concept: { label: 'Concept' },
  proposal: { label: 'Proposal' },
  project: { label: 'Project book' },
  itinerary: { label: 'Itinerary' },
  ops: { label: 'Operations itinerary' },
  desk: { label: 'Private services' },
  onepage: { label: 'One-page concept' },
  master: { label: 'Brief' },
};

export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
// *italic* and **strong** only; everything else is escaped.
export const fmt = (s) => esc(s).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/\*(.+?)\*/g, '<em>$1</em>');
const slugCls = (s) => String(s || '').toLowerCase().replace(/[^a-z]+/g, '-').replace(/^-|-$/g, '');
const NONE = (v) => v == null || v === '';

export function mark(logoSvg, small = false) {
  if (logoSvg) return `<span class="mark${small ? ' small' : ''}">${logoSvg}</span>`;
  return `<span class="mark${small ? ' small' : ''}"><span class="w1">NOYA</span><span class="w2">CONCIERGE</span></span>`;
}

const BLOCKS = {
  section: (b) => `<div class="sec"><div class="sl">${b.n ? `<span class="num">${esc(b.n)}</span>` : ''}<span class="label">${esc(b.label || '')}</span></div><h2>${fmt(b.title)}</h2></div>`,
  lead: (b) => `<div class="lead">${fmt(b.text)}</div>`,
  p: (b) => `<p>${fmt(b.text)}</p>`,
  h3: (b) => `<h3>${fmt(b.text)}</h3>`,
  note: (b) => `<div class="note">${fmt(b.text)}</div>`,
  gap: () => '<div class="gap"></div>',
  rule: () => '<div class="rule"></div>',
  quote: (b) => `<div class="quote">${fmt(b.text)}${b.by ? `<span class="by">${esc(b.by)}</span>` : ''}</div>`,
  roles: (b) => `<div class="roles">${[b.left, b.right].map((c) => `<div class="col"><span class="label">${esc(c.title)}</span><ul>${c.items.map((i) => `<li>${fmt(i)}</li>`).join('')}</ul></div>`).join('')}</div>`,
  ledger: (b) => `<div class="ledger">${b.rows.map(([k, v]) => `<div class="k"><span class="label">${esc(k)}</span></div><div class="v">${fmt(v)}</div>`).join('')}</div>`,
  options: (b) => `<div class="options">${b.items.map((o) => `<div class="opt"><span class="n">${esc(o.n)}</span><h3>${fmt(o.title)}</h3><p>${fmt(o.text)}</p>${o.meta?.length ? `<dl>${o.meta.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${fmt(v)}</dd>`).join('')}</dl>` : ''}</div>`).join('')}</div>`,
  feature: (b) => `<div class="feature"><div class="side"><span class="label">${esc(b.label)}</span><div class="big">${fmt(b.big)}</div></div><div>${(b.paras || []).map((t) => `<p>${fmt(t)}</p>`).join('')}</div></div>`,
  journey: (b) => `<div class="journey" style="--cols:${b.items.length}">${b.items.map((s) => `<div class="step"><span class="when">${fmt(s.when)}</span><p>${fmt(s.text)}</p></div>`).join('')}</div>`,
  // A field with a value prints it (known from our conversation, for the client to correct); otherwise blank lines to fill.
  form: (b) => `<div class="form">${b.fields.map((f) => `<div class="field${f.wide ? ' wide' : ''}"><span class="label">${esc(f.label)}</span>${f.hint && NONE(f.value) ? `<div class="hint">${fmt(f.hint)}</div>` : ''}${NONE(f.value) ? '<div class="line"></div>'.repeat(f.lines || 1) : `<div class="val">${fmt(f.value)}</div>`}</div>`).join('')}</div>`,
  steps: (b) => `<div class="steps">${b.items.map((s, i) => `<div class="st"><span class="i">${String(i + 1).padStart(2, '0')}</span><div><h3>${fmt(s.title)}</h3><p>${fmt(s.text)}</p></div></div>`).join('')}</div>`,
  // Proposal fees: a value is shown only when it is recorded; otherwise "Not recorded". Nothing is estimated here.
  fees: (b) => `<div class="fees">${b.rows.map(([k, v]) => `<div class="fr${/^total$/i.test(k) ? ' total' : ''}"><span class="fl">${fmt(k)}</span><span class="fv${NONE(v) ? ' none' : ''}">${NONE(v) ? 'Not recorded' : fmt(v)}</span></div>`).join('')}</div>`,
  kv: (b) => `<div class="kv" style="--kvcols:${b.cols || 3}">${b.items.map(([k, v]) => `<div><span class="label">${esc(k)}</span><div class="v${NONE(v) ? ' none' : ''}">${NONE(v) ? 'Not recorded' : fmt(v)}</div></div>`).join('')}</div>`,
  // Facts carry their provenance class: VERIFIED / NOYA MATERIAL / PUBLIC / INFERRED / UNVERIFIED. Internal documents only.
  facts: (b) => `<div class="facts">${b.items.map((f) => `<div class="f"><div><div class="t">${fmt(f.text)}</div>${f.source ? `<span class="s">${esc(f.source)}</span>` : ''}</div><span class="cls ${slugCls(f.class)}">${esc(f.class || 'UNVERIFIED')}</span></div>`).join('')}</div>`,
  timeline: (b) => `<div class="timeline">${b.items.map((e) => `<div class="ev"><span class="d">${esc(e.date)}</span>${e.who ? `<span class="w">${esc(e.who)}</span>` : ''}<p>${fmt(e.text)}</p></div>`).join('')}</div>`,
  callout: (b) => `<div class="callout"><span class="label">${esc(b.label || '')}</span><div class="big">${fmt(b.big)}</div>${b.text ? `<p>${fmt(b.text)}</p>` : ''}</div>`,
  table: (b) => `<table class="tbl${b.compact ? ' compact' : ''}">${b.widths ? `<colgroup>${b.widths.map((w) => `<col style="width:${w}">`).join('')}</colgroup>` : ''}<thead><tr>${b.cols.map((c) => `<th>${esc(c)}</th>`).join('')}</tr></thead><tbody>${b.rows.map((r) => `<tr>${r.map((c) => `<td>${NONE(c) ? '<span class="muted">To confirm</span>' : fmt(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`,
  itinerary: (b) => b.days.map((d, i) => `<div class="day"><div class="dl"><span class="n">${esc(d.n || String(i + 1).padStart(2, '0'))}</span><span class="label">${esc(d.label || '')}</span>${d.date ? `<span class="dt">${esc(d.date)}</span>` : ''}</div><div class="items">${d.items.map((it) => `<div class="it"><span class="tm">${esc(it.time || '')}</span><div><h4>${fmt(it.title)}</h4>${it.text ? `<p>${fmt(it.text)}</p>` : ''}</div></div>`).join('')}</div></div>`).join(''),
  // One-page concept: the next step and the contact on one line at the foot of the page.
  strip: (b) => `<div class="strip"><div><span class="label">${esc(b.label)}</span><h3>${fmt(b.title)}</h3><p>${fmt(b.text)}</p></div><div class="who">${esc(b.contact.name)}<span class="role">${esc(b.contact.role)}</span><span class="ways">${b.contact.lines.map(esc).join('<br>')}</span></div></div>`,
  // Imagery (master brief): every image comes from brand/images.json (NOYA's approved library); render.mjs resolves "img" to "src".
  gallery: (b) => `<div class="gallery" style="--gh:${b.h || 58}mm;--gcols:${b.items.length}">${b.items.map((i) => `<figure><div class="ph" style="background-image:url(${i.src});background-position:${i.pos || 'center'}"></div>${i.caption ? `<figcaption class="label">${esc(i.caption)}</figcaption>` : ''}</figure>`).join('')}</div>`,
  formats: (b) => `<div class="formats">${b.items.map((f) => `<div class="fm"><h3>${fmt(f.title)}</h3><p>${fmt(f.text)}</p></div>`).join('')}</div>`,
  // Dinner / experience creator: the setting and the guest's evening as direction, beside one image. Never a confirmed menu.
  evening: (b) => `<div class="evening"><div class="ph" style="background-image:url(${b.src});background-position:${b.pos || 'center'}"></div><div><span class="label">${esc(b.label)}</span><h3>${fmt(b.title)}</h3><div class="ledger">${b.rows.map(([k, v]) => `<div class="k"><span class="label">${esc(k)}</span></div><div class="v">${fmt(v)}</div>`).join('')}</div>${b.note ? `<div class="note">${fmt(b.note)}</div>` : ''}</div></div>`,
  value: (b) => `<div class="value">${b.items.map((v) => `<div class="vi"><h3>${fmt(v.title)}</h3><p>${fmt(v.text)}</p></div>`).join('')}</div>`,
  places: (b) => `${b.label ? `<span class="label places-label">${esc(b.label)}</span>` : ''}<div class="places">${b.items.map((x) => `<span>${esc(x)}</span>`).join('')}</div>`,
  check: (b) => `<div class="check">${b.items.map((c) => `<div class="c"><div>${fmt(c.text)}${c.note ? `<span class="n">${fmt(c.note)}</span>` : ''}</div><span class="cls ${slugCls(c.status)}">${esc(c.status || 'To confirm')}</span></div>`).join('')}</div>`,
};

export const BLOCK_TYPES = Object.keys(BLOCKS);

function blocks(list) {
  return (list || []).map((b) => {
    const f = BLOCKS[b.t];
    if (!f) throw new Error(`Unknown block type: ${b.t}`);
    return f(b);
  }).join('\n');
}

const draftOf = (doc) => doc.draft || null;
const flagOf = (doc) => (doc.audience === 'internal' ? 'Internal · not for client' : draftOf(doc));

function cover(doc, logo) {
  const t = TYPE[doc.type];
  const c = doc.cover || {};
  const style = c.style || 'navy';
  const cls = ['page', 'cover', style === 'navy' ? 'navy' : style, c.position, c.quiet ? 'quiet' : ''].filter(Boolean).join(' ');
  const flag = flagOf(doc);
  const meta = `<div class="meta"><span class="label">${esc(doc.type_label || t.label)}${doc.reference ? ` · ${esc(doc.reference)}` : ''}</span><span class="label">${esc(doc.date)}</span>${flag ? `<span class="internal-flag">${esc(flag)}</span>` : ''}</div>`;
  return `<section class="${cls}">
  ${style === 'split' ? `<div class="panel">${mark(logo)}<span class="label">${esc(doc.master_label || '')}</span></div><div class="top">${meta}</div>` : `<div class="top">${mark(logo)}${meta}</div>`}
  <div class="centre">
    <div class="eyebrow label">${esc(doc.eyebrow || t.label)}</div>
    <h1>${fmt(doc.title)}</h1>
    ${doc.subtitle ? `<div class="sub">${fmt(doc.subtitle)}</div>` : ''}
  </div>
  <div class="bottom"><div class="for"><span class="label">${esc(doc.for_label || 'Prepared for')}</span>${fmt(doc.prepared_for)}</div><span class="label">${doc.audience === 'internal' ? 'NOYA internal' : 'Private &amp; confidential'}</span></div>
</section>`;
}

function contentPage(doc, page, n, logo) {
  const navy = page.kind === 'closing';
  const flag = flagOf(doc);
  return `<section class="page${navy ? ' navy' : ''}${page.contact ? ' has-contact' : ''}" data-kind="${esc(page.kind || 'content')}">
  <div class="head">${mark(logo, true)}<span class="label">${flag ? `<span class="internal-flag">${esc(flag)}</span>&nbsp;&nbsp;` : ''}${esc(page.running || doc.running || '')}</span></div>
  <div class="body">${blocks(page.blocks)}</div>
  ${page.contact ? `<div class="contact"><div class="who">${esc(page.contact.name)}<span class="role">${esc(page.contact.role)}</span></div><div class="ways">${page.contact.lines.map(esc).join('<br>')}</div></div>` : ''}
  <div class="foot"><span class="pn">${String(n).padStart(2, '0')}</span><span class="label">NOYA Concierge · ${doc.audience === 'internal' ? 'Internal' : 'Private &amp; confidential'}</span></div>
</section>`;
}

// Level 2: the whole concept on one A4 page. A navy band carries the title; the page never paginates, so anything that does not
// fit fails the render instead of spilling onto a second page.
function onePage(doc, logo) {
  const flag = flagOf(doc);
  return `<section class="page one" data-kind="one">
  <div class="band"><div class="top">${mark(logo)}<div class="meta"><span class="label">${esc(TYPE.onepage.label)}</span><span class="label">${esc(doc.date)}</span>${flag ? `<span class="internal-flag">${esc(flag)}</span>` : ''}</div></div>
    <div class="eyebrow label">${esc(doc.eyebrow)}</div><h1>${fmt(doc.title)}</h1>${doc.subtitle ? `<div class="sub">${fmt(doc.subtitle)}</div>` : ''}</div>
  <div class="body">${blocks(doc.pages[0].blocks)}</div>
  <div class="foot"><span class="label">Prepared for ${esc(doc.prepared_for)}</span><span class="label">NOYA Concierge · Private &amp; confidential</span></div>
</section>`;
}

// Master brief (2-3 pages, Level 3): page one is the cover, the positioning and why now over one strong image; the pages that
// follow are fixed (they never paginate), so anything that does not fit fails the render instead of growing the document.
function lockup(doc, logo) {
  return `<div class="lockup">${mark(logo)}${doc.party_mark ? `<span class="x">×</span><span class="pm">${esc(doc.party_mark)}</span>` : ''}</div>`;
}
function masterPages(doc, logo) {
  const n = doc.pages.length;
  const foot = (i) => `<div class="foot"><span class="pn">${String(i + 1).padStart(2, '0')} / ${String(n).padStart(2, '0')}</span><span class="label">NOYA Concierge · Private &amp; confidential</span></div>`;
  return doc.pages.map((p, i) => {
    if (p.kind === 'm-hero') {
      return `<section class="page master hero navy" data-kind="m-hero">
  <div class="hero-img" style="background-image:url(${p.src});background-position:${p.pos || 'center'}"></div>
  <div class="hero-top">${lockup(doc, logo)}<div class="meta"><span class="label">${esc(doc.eyebrow)}</span><span class="label">${esc(doc.date)}</span></div></div>
  <div class="body hero-text">
    <h1>${fmt(doc.title)}</h1>
    <div class="pos">${fmt(doc.positioning)}</div>
    ${p.why?.length ? `<div class="why"><span class="label">${esc(p.why_label || 'Why Egypt, why now')}</span><div class="why-grid">${p.why.map(([k, v]) => `<div><h3>${fmt(k)}</h3><p>${fmt(v)}</p></div>`).join('')}</div></div>` : ''}
    <div class="for"><span class="label">Prepared for</span>${fmt(doc.prepared_for)}</div>
  </div>
  ${foot(i)}
</section>`;
    }
    const close = p.kind === 'm-close';
    return `<section class="page master fixed${close ? ' close' : ''}" data-kind="${esc(p.kind)}">
  <div class="head">${mark(logo, true)}<span class="label">${esc(p.running || doc.running || '')}</span></div>
  <div class="body">${blocks(p.blocks)}</div>
  ${close ? `<div class="band"><div class="nx"><span class="label">${esc(p.next.label || 'Next step')}</span><h2>${fmt(p.next.title)}</h2><p>${fmt(p.next.text)}</p></div><div class="who">${esc(p.contact.name)}<span class="role">${esc(p.contact.role)}</span><span class="ways">${p.contact.lines.map(esc).join('<br>')}</span></div></div>` : ''}
  ${foot(i)}
</section>`;
  }).join('\n');
}

// The pages of one document, without the HTML shell (used to bind several documents into one pack).
export function documentPages(doc, logo) {
  if (!TYPE[doc.type]) throw new Error(`Unknown document type: ${doc.type}`);
  if (doc.type === 'onepage') return onePage(doc, logo);
  if (doc.type === 'master') return masterPages(doc, logo);
  return [cover(doc, logo), ...doc.pages.map((p, i) => contentPage(doc, p, i + 2, logo))].join('\n');
}

export function shell(title, css, body) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>${esc(title)}</title>
<style>${css}</style></head>
<body>
${body}
</body></html>`;
}

export function renderDocument(doc, { css, logo }) {
  return shell(doc.file_title || doc.title.replace(/\*/g, ''), css, `<div class="doc">${documentPages(doc, logo)}</div>`);
}
