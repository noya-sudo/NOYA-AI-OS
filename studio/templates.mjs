// NOYA Studio templates. A document is data (studio/documents/*.json); these functions turn it into A4 pages.
// Brief, Concept and Proposal share one block library, so every document reads as the same house.

const TYPE = {
  brief: { label: 'Brief' },
  concept: { label: 'Concept' },
  proposal: { label: 'Proposal' },
};

export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
// *italic* and **strong** only; everything else is escaped.
export const fmt = (s) => esc(s).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/\*(.+?)\*/g, '<em>$1</em>');

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
  form: (b) => `<div class="form">${b.fields.map((f) => `<div class="field${f.wide ? ' wide' : ''}"><span class="label">${esc(f.label)}</span>${f.hint ? `<div class="hint">${fmt(f.hint)}</div>` : ''}${'<div class="line"></div>'.repeat(f.lines || 1)}</div>`).join('')}</div>`,
  steps: (b) => `<div class="steps">${b.items.map((s, i) => `<div class="st"><span class="i">${String(i + 1).padStart(2, '0')}</span><div><h3>${fmt(s.title)}</h3><p>${fmt(s.text)}</p></div></div>`).join('')}</div>`,
  // Proposal fees: a value is shown only when it is recorded; otherwise "Not recorded". Nothing is estimated here.
  fees: (b) => `<div class="ledger">${b.rows.map(([k, v]) => `<div class="k"><span class="label">${esc(k)}</span></div><div class="v">${v == null || v === '' ? '<span style="opacity:.6">Not recorded</span>' : fmt(v)}</div>`).join('')}</div>`,
};

function blocks(list) {
  return (list || []).map((b) => {
    const f = BLOCKS[b.t];
    if (!f) throw new Error(`Unknown block type: ${b.t}`);
    return f(b);
  }).join('\n');
}

function cover(doc, logo) {
  const t = TYPE[doc.type];
  return `<section class="page navy cover">
  <div class="top">${mark(logo)}<div class="meta"><span class="label">${esc(t.label)}${doc.reference ? ` · ${esc(doc.reference)}` : ''}</span><span class="label">${esc(doc.date)}</span></div></div>
  <div class="centre">
    <div class="eyebrow label">${esc(doc.eyebrow || t.label)}</div>
    <h1>${fmt(doc.title)}</h1>
    ${doc.subtitle ? `<div class="sub">${fmt(doc.subtitle)}</div>` : ''}
  </div>
  <div class="bottom"><div class="for"><span class="label">Prepared for</span>${fmt(doc.prepared_for)}</div><span class="label">Private &amp; confidential</span></div>
</section>`;
}

function contentPage(doc, page, n, logo) {
  const navy = page.kind === 'closing';
  return `<section class="page${navy ? ' navy' : ''}">
  <div class="head">${mark(logo, true)}<span class="label">${esc(page.running || doc.running || '')}</span></div>
  <div class="body">${blocks(page.blocks)}</div>
  ${page.contact ? `<div class="contact"><div class="who">${esc(page.contact.name)}<span class="role">${esc(page.contact.role)}</span></div><div class="ways">${page.contact.lines.map(esc).join('<br>')}</div></div>` : ''}
  <div class="foot"><span class="pn">${String(n).padStart(2, '0')}</span><span class="label">NOYA Concierge · Private &amp; confidential</span></div>
</section>`;
}

export function renderDocument(doc, { css, logo }) {
  if (!TYPE[doc.type]) throw new Error(`Unknown document type: ${doc.type}`);
  const pages = [cover(doc, logo), ...doc.pages.map((p, i) => contentPage(doc, p, i + 2, logo))];
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>${esc(doc.file_title || doc.title.replace(/\*/g, ''))}</title>
<style>${css}</style></head>
<body>
${pages.join('\n')}
</body></html>`;
}
