// NOYA brochure collection · build r2: content modules -> HTML -> PDF (Chromium), page previews, and automatic checks
// (text overflow, effective image resolution, links, fonts), plus the copy master generated from the same source.
//
//   node studio/brochures/build.mjs                 all six, digital (out/brochures/r2/digital)
//   node studio/brochures/build.mjs 02 05           selected publications
//   VARIANT=print node studio/brochures/build.mjs   print: full-resolution photos, 3 mm bleed (out/brochures/r2/print)
//   OMIT_REFS=1 ...                                 04 without the third-party creative reference page
//   DRAFT=1 ...                                     show red approval markers on pages that carry `approval`
//
// Photos: images/ (digital, long edge <= 2000 px) and images_print/ (full resolution); both git-ignored (public repository).
// assets.json is the register: an EXCLUDED photo stops the build.
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const HERE = dirname(fileURLToPath(import.meta.url));
const BRAND = join(HERE, '..', 'brand');
const VARIANT = process.env.VARIANT === 'print' ? 'print' : 'digital';
const DRAFT = process.env.DRAFT === '1';
const OMIT_REFS = process.env.OMIT_REFS === '1';
const BLEED = VARIANT === 'print' ? 3 : 0;
const EDITION = 'v2026-11-r2';
const OUT = join(HERE, '..', 'out', 'brochures', 'r2', VARIANT);
const IMGDIR = join(HERE, VARIANT === 'print' ? 'images_print' : 'images');
mkdirSync(join(OUT, 'pages'), { recursive: true });

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = createRequire(join(HERE, '..', '..', 'hq', 'package.json'))('playwright-core')); }

const assets = JSON.parse(readFileSync(join(HERE, 'assets.json'), 'utf8'));
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
// Copy is plain text; *word* sets italic; \n is a line break in a title.
const fmt = (s) => esc(s).replace(/\*([^*]+)\*/g, '<em>$1</em>').replace(/\n/g, '<br>');

// JPEG pixel size (SOF marker), for the effective-resolution check.
function jpegSize(buf) {
  let i = 2;
  while (i < buf.length) {
    if (buf[i] !== 0xff) { i++; continue; }
    const m = buf[i + 1], len = buf.readUInt16BE(i + 2);
    if (m >= 0xc0 && m <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(m)) return { h: buf.readUInt16BE(i + 5), w: buf.readUInt16BE(i + 7) };
    i += 2 + len;
  }
  return { w: 0, h: 0 };
}

const usedImages = new Map();
function img(key, where) {
  const a = assets.images[key];
  if (!a) throw new Error(`${where}: image "${key}" is not in assets.json`);
  if (a.status === 'EXCLUDED') throw new Error(`${where}: image "${key}" is excluded (${a.note})`);
  const f = join(IMGDIR, `${key}.jpg`);
  if (!existsSync(f)) throw new Error(`${where}: ${IMGDIR}/${key}.jpg missing (see docs/ASSET_REGISTER.md)`);
  if (!usedImages.has(key)) usedImages.set(key, new Set());
  usedImages.get(key).add(where);
  const buf = readFileSync(f);
  const { w, h } = jpegSize(buf);
  return { css: `url(data:image/jpeg;base64,${buf.toString('base64')})`, attrs: `data-img="${key}" data-w="${w}" data-h="${h}"` };
}
const bg = (key, where, extra = '') => { const i = img(key, where); return `${i.attrs} style="background-image:${i.css};${extra}"`; };

const logo = readFileSync(join(BRAND, 'logo.svg'), 'utf8').trim();

// ---------- blocks ----------
function blocks(list = [], where) {
  return list.map((b) => {
    if (b.p) return `<p class="b">${fmt(b.p)}</p>`;
    if (b.intro) return `<p class="intro">${fmt(b.intro)}</p>`;
    if (b.pull) return `<p class="pull">${fmt(b.pull)}</p>`;
    if (b.note) return `<p class="note">${fmt(b.note)}</p>`;
    if (b.h3) return `<h3 class="h${b.mt ? ' mt' + b.mt : ''}">${fmt(b.h3)}</h3>`;
    if (b.gap) return `<div style="height:${b.gap}mm;flex:none"></div>`;
    if (b.list) return `${b.list.h ? `<h3 class="h">${fmt(b.list.h)}</h3>` : ''}<ul class="rows${b.list.two ? ' two' : ''}">${b.list.items.map((i) => `<li>${fmt(i)}</li>`).join('')}</ul>`;
    if (b.dots) return `${b.dots.h ? `<h3 class="h">${fmt(b.dots.h)}</h3>` : ''}<ul class="dots">${b.dots.items.map((i) => `<li>${fmt(i)}</li>`).join('')}</ul>`;
    if (b.words) return `<div class="words">${b.words.map((w, i, a) => w === '|' ? '<i class="br"></i>' : `<span${i === a.length - 1 || a[i + 1] === '|' ? ' class="end"' : ''}>${fmt(w)}</span>`).join('')}</div>`;
    if (b.cols) return `<div class="cols c${b.cols.n}">${b.cols.items.map((i) => `<div class="item">${i.k ? `<span class="k">${fmt(i.k)}</span>` : ''}${i.h ? `<h3 class="h">${fmt(i.h)}</h3>` : ''}${i.t ? `<p>${fmt(i.t)}</p>` : ''}${i.list ? `<ul class="dots mt2">${i.list.map((x) => `<li>${fmt(x)}</li>`).join('')}</ul>` : ''}${i.more ? `<span class="more">${fmt(i.more)}</span>` : ''}</div>`).join('')}</div>`;
    if (b.box) return `<div class="box">${b.box.h ? `<h3 class="h">${fmt(b.box.h)}</h3>` : ''}${[].concat(b.box.t).map((t) => `<p>${fmt(t)}</p>`).join('')}</div>`;
    if (b.steps) return `<div class="steps">${b.steps.map((s, i) => `<div class="st"><span class="n">${s.n ?? String(i + 1).padStart(2, '0')}</span><h3 class="h">${fmt(s.h)}</h3><p>${fmt(s.t)}</p></div>`).join('')}</div>`;
    if (b.cards) return `<div class="cards c${b.cards.n}">${b.cards.items.map((c) => `<div class="card">${c.num ? `<span class="num">${fmt(c.num)}</span>` : ''}${c.tag ? `<span class="tag">${fmt(c.tag)}</span>` : ''}<h3 class="c">${fmt(c.h)}</h3>${c.for ? `<p class="for">${fmt(c.for)}</p>` : ''}${[].concat(c.t || []).map((t) => `<p>${fmt(t)}</p>`).join('')}${c.list ? `<ul class="dots">${c.list.map((x) => `<li>${fmt(x)}</li>`).join('')}</ul>` : ''}</div>`).join('')}</div>`;
    if (b.table) return `<table class="resp"><thead><tr>${b.table.head.map((h) => `<th>${fmt(h)}</th>`).join('')}</tr></thead><tbody>${b.table.rows.map((r) => `<tr>${r.map((c) => `<td>${fmt(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
    if (b.photos) {
      const P = b.photos;
      return `<div class="strip" style="grid-template-columns:${P.cols || `repeat(${P.imgs.length},1fr)`};height:${P.h}mm">${P.imgs.map((k, i) => `<figure><div class="p" ${bg(k, where, P.pos?.[i] ? `background-position:${P.pos[i]}` : '')}></div>${P.caps?.[i] ? `<figcaption>${fmt(P.caps[i])}</figcaption>` : ''}</figure>`).join('')}</div>`;
    }
    if (b.lines) return `<div class="lines">${b.lines.map((l) => `<p>${fmt(l)}</p>`).join('')}</div>`;
    if (b.entry) {
      const e = b.entry;
      return `<div class="entry"><div class="meta">${e.meta.map((m) => `<span>${fmt(m)}</span>`).join('')}</div><h3 class="e">${fmt(e.title)}</h3><div class="g"><div><h3 class="h">The brief</h3><p>${fmt(e.brief)}</p></div><div><h3 class="h">What NOYA delivered</h3><p>${fmt(e.delivered)}</p></div><div><h3 class="h">Outcome</h3><p>${fmt(e.outcome)}</p></div></div></div>`;
    }
    if (b.refs) return `<div class="refs">${b.refs.items.map((r) => `<figure><div class="p" ${bg(r.img, where, `height:${b.refs.h}mm`)}></div><figcaption><span class="rt">${fmt(r.title)}</span><span class="rd">${fmt(r.text)}</span></figcaption></figure>`).join('')}</div>`;
    if (b.contact) return contactBlock(b.contact);
    if (b.collection) return `<div class="collection"><b>The NOYA collection</b>${fmt(b.collection)}</div>`;
    throw new Error(`${where}: unknown block ${JSON.stringify(Object.keys(b))}`);
  }).join('\n');
}

function contactBlock(c) {
  const rows = [
    ['NOYA Concierge', 'Adam Elshazly, Founder', null],
    ['Email', 'noya@noyaconcierge.com', 'mailto:noya@noyaconcierge.com'],
    ['WhatsApp', '+44 786 456 9006', 'https://wa.me/447864569006'],
    ['Website', 'noyaconcierge.com', 'https://noyaconcierge.com'],
    ['Instagram', '@noyaconcierge', 'https://www.instagram.com/noyaconcierge/'],
  ];
  return `<div class="contact">${rows.map(([l, v, h], i) => `<div class="r"${i === 0 ? ' style="grid-column:1 / -1"' : ''}><span class="l">${l}</span><span class="v">${h ? `<a href="${h}">${esc(v)}</a>` : esc(v)}</span></div>`).join('')}</div>`;
}

const head = (p) => `${p.eyebrow ? `<div class="eyebrow">${fmt(p.eyebrow)}</div>` : ''}${p.title ? `<h2 class="t${p.small ? ' s' : ''}">${fmt(p.title)}</h2>` : ''}${p.intro ? `<p class="intro">${fmt(p.intro)}</p>` : ''}`;

// ---------- page layouts ----------
function page(p, n, doc) {
  const where = `${doc.code} p${n}`;
  const navy = p.tone === 'navy';
  const rf = n === 1 ? '' : `<div class="rf${p.lightFoot ? ' light' : ''}"><span>${esc(doc.short)}</span><span class="n">${String(n).padStart(2, '0')}</span></div>`;
  const draft = DRAFT && p.approval ? `<div class="draft">Approval required · ${esc(p.approval)}</div>` : '';
  const pos = p.pos ? `--pos:${p.pos};` : '';
  const cls = (base) => `page ${base}${navy ? ' navy' : ''}${p.top ? ' top' : ''}`;
  switch (p.layout) {
    case 'cover':
      return `<section class="page cover${p.img ? '' : ' plain'}">${draft}${p.img ? `<div class="ph" ${bg(p.img, where, pos)}></div><div class="shade"></div>` : ''}<div class="logo">${logo}</div>
        <div class="txt"><div class="kick">${fmt(p.kicker)}</div><h1 class="t">${fmt(p.title)}</h1><p class="line">${fmt(p.line)}</p>
        <div class="base"><span>${fmt(p.base?.[0] ?? 'noyaconcierge.com')}</span><span>${fmt(p.base?.[1] ?? '')}</span></div></div></section>`;
    case 'statement':
      return `<section class="${cls('statement')}">${draft}<div class="frame">${head(p)}${blocks(p.blocks, where)}</div>${rf}</section>`;
    case 'split':
      return `<section class="${cls(`split ${p.side || 'left'}`)}">${draft}<div class="ph" ${bg(p.img, where, pos)}></div><div class="col">${head(p)}${blocks(p.blocks, where)}</div>${rf}</section>`;
    case 'band':
      return `<section class="${cls('band')}" style="--h:${p.h || 112}mm">${draft}<div class="ph" ${bg(p.img, where, pos)}></div><div class="frame${p.fill ? ' fill' : ''}">${head(p)}${blocks(p.blocks, where)}</div>${rf}</section>`;
    case 'cinematic':
      return `<section class="page cinematic">${draft}<div class="ph" ${bg(p.img, where, pos)}></div><div class="shade"></div><div class="panel">${head(p)}${blocks(p.blocks, where)}</div>${rf.replace('class="rf', 'class="rf light')}</section>`;
    case 'text':
      return `<section class="${cls('text')}">${draft}<div class="frame">${head(p)}${blocks(p.blocks, where)}</div>${rf}</section>`;
    case 'closing':
      return `<section class="page closing navy${p.img ? '' : ' plain'}" style="--h:${p.h || 118}mm">${draft}${p.img ? `<div class="ph" ${bg(p.img, where, pos)}></div>` : ''}<div class="frame"><div class="logo" style="margin-bottom:7mm">${logo}</div>${head(p)}${blocks(p.blocks, where)}</div>${rf}</section>`;
    default: throw new Error(`${where}: unknown layout ${p.layout}`);
  }
}

function fontFaces() {
  const F = [['Jost', 350, 'normal', 'jost-350'], ['Jost', 450, 'normal', 'jost-450'], ['Jost', 550, 'normal', 'jost-550'],
    ['Cormorant', 300, 'normal', 'cormorant-300'], ['Cormorant', 400, 'normal', 'cormorant-400'], ['Cormorant', 500, 'normal', 'cormorant-500'],
    ['Cormorant', 300, 'italic', 'cormorant-300-italic'], ['Cormorant', 400, 'italic', 'cormorant-400-italic']];
  return F.map(([fam, w, s, f]) => `@font-face{font-family:'${fam}';font-weight:${w};font-style:${s};src:url(data:font/ttf;base64,${readFileSync(join(HERE, 'fonts', f + '.ttf')).toString('base64')}) format('truetype');}`).join('\n');
}

function html(doc) {
  const css = readFileSync(join(HERE, 'brochure.css'), 'utf8');
  return `<!doctype html><html lang="en-GB"><head><meta charset="utf-8"><title>${esc(doc.title)}</title>
<meta name="author" content="NOYA Concierge"><meta name="description" content="${esc(doc.description)}">
<style>${fontFaces()}\n${css}\n:root{--b:${BLEED}mm}\n@page{size:${210 + 2 * BLEED}mm ${297 + 2 * BLEED}mm;margin:0}</style></head><body>${doc.pages.map((p, i) => page(p, i + 1, doc)).join('\n')}</body></html>`;
}

// Runs in the page: text must end inside its frame above the running foot; photos report their effective resolution.
function inspect(bleedMm) {
  const pxPerMm = 96 / 25.4;
  const problems = [], photos = [];
  document.querySelectorAll('.page').forEach((pg, i) => {
    const pr = pg.getBoundingClientRect();
    const foot = pg.querySelector('.rf');
    const limit = foot ? foot.getBoundingClientRect().top - 4 : pr.bottom - (10 + bleedMm) * pxPerMm;
    pg.querySelectorAll('.frame, .col, .panel').forEach((fr) => {
      let max = 0;
      fr.querySelectorAll('*').forEach((el) => { const r = el.getBoundingClientRect(); if (r.height) max = Math.max(max, r.bottom); });
      if (max > limit + 0.5) problems.push(`page ${i + 1}: content ends ${(Math.round((max - limit) / pxPerMm * 10) / 10)}mm into the foot area`);
    });
    const logo = pg.querySelector('.cover .logo');
    const txt = pg.querySelector('.cover .txt');
    if (logo && txt && txt.getBoundingClientRect().top < logo.getBoundingClientRect().bottom + 20 * pxPerMm) problems.push(`page ${i + 1}: cover text too close to the logo`);
    pg.querySelectorAll('[data-img]').forEach((el) => {
      const r = el.getBoundingClientRect(); const w = +el.dataset.w, h = +el.dataset.h;
      if (!w || !r.width) return;
      const scale = Math.max(r.width / w, r.height / h); // CSS px per image px (background-size: cover)
      photos.push({ page: i + 1, img: el.dataset.img, ppi: Math.round(96 / scale), wmm: Math.round(r.width / pxPerMm), hmm: Math.round(r.height / pxPerMm) });
    });
  });
  return { problems, photos };
}

// ---------- copy master ----------
function copyMaster(doc) {
  const out = [`## ${doc.code} · ${doc.title}`, '', `*Audience:* ${doc.audience}  `, `*Purpose:* ${doc.purpose}  `, `*Pages:* ${doc.pages.length}`, ''];
  const md = (s) => String(s).replace(/\n/g, ' ');
  doc.pages.forEach((p, i) => {
    out.push(`### Page ${String(i + 1).padStart(2, '0')} · ${p.layout}${p.img ? ` · photo: ${p.img}` : ''}${p.reference ? ' · third-party reference page' : ''}`, '');
    if (p.kicker) out.push(`**Kicker:** ${md(p.kicker)}  `);
    if (p.eyebrow) out.push(`**Eyebrow:** ${md(p.eyebrow)}  `);
    if (p.title) out.push(`**Title:** ${md(p.title)}  `);
    if (p.line) out.push(`**Line:** ${md(p.line)}  `);
    if (p.intro) out.push(`**Intro:** ${md(p.intro)}`);
    out.push('');
    for (const b of p.blocks || []) {
      if (b.p) out.push(md(b.p), '');
      else if (b.intro) out.push(`*${md(b.intro)}*`, '');
      else if (b.pull) out.push(`> ${md(b.pull)}`, '');
      else if (b.note) out.push(`<sub>${md(b.note)}</sub>`, '');
      else if (b.h3) out.push(`**${md(b.h3)}**`, '');
      else if (b.list || b.dots) { const L = b.list || b.dots; if (L.h) out.push(`**${md(L.h)}**`); L.items.forEach((x) => out.push(`- ${md(x)}`)); out.push(''); }
      else if (b.words) out.push(b.words.filter((w) => w !== '|').map(md).join(' · '), '');
      else if (b.cols) { b.cols.items.forEach((x) => out.push(`- **${md(x.h || x.k || '')}**${x.t ? ` ${md(x.t)}` : ''}${x.list ? ` (${x.list.map(md).join('; ')})` : ''}${x.more ? ` *${md(x.more)}*` : ''}`)); out.push(''); }
      else if (b.box) out.push(`${b.box.h ? `**${md(b.box.h)}** ` : ''}${[].concat(b.box.t).map(md).join(' ')}`, '');
      else if (b.steps) { b.steps.forEach((s, j) => out.push(`${s.n ? md(s.n) + '.' : j + 1 + '.'} **${md(s.h)}** ${md(s.t)}`)); out.push(''); }
      else if (b.cards) { b.cards.items.forEach((c) => { out.push(`- **${md(c.h)}**${c.tag ? ` (${md(c.tag)})` : ''}${c.for ? ` *${md(c.for)}*` : ''} ${[].concat(c.t || []).map(md).join(' ')}`); (c.list || []).forEach((x) => out.push(`  - ${md(x)}`)); }); out.push(''); }
      else if (b.table) { out.push(`| ${b.table.head.join(' | ')} |`, `|${b.table.head.map(() => '---').join('|')}|`); b.table.rows.forEach((r) => out.push(`| ${r.map(md).join(' | ')} |`)); out.push(''); }
      else if (b.photos) out.push(`*[photos: ${b.photos.imgs.join(', ')}${b.photos.caps ? ` · captions: ${b.photos.caps.join(', ')}` : ''}]*`, '');
      else if (b.lines) { b.lines.forEach((l) => out.push(md(l) + '  ')); out.push(''); }
      else if (b.entry) { const e = b.entry; out.push(`**${md(e.title)}** (${e.meta.join(' · ')})`, `- Brief: ${md(e.brief)}`, `- Delivered: ${md(e.delivered)}`, `- Outcome: ${md(e.outcome)}`, ''); }
      else if (b.refs) { b.refs.items.forEach((r) => out.push(`- **${md(r.title)}** ${md(r.text)} *(photo: ${r.img})*`)); out.push(''); }
      else if (b.contact) out.push('*[Contact block: NOYA Concierge · Adam Elshazly, Founder · noya@noyaconcierge.com · +44 786 456 9006 · noyaconcierge.com · @noyaconcierge]*', '');
      else if (b.collection) out.push(`*The NOYA collection:* ${md(b.collection)}`, '');
    }
  });
  return out.join('\n');
}

// ---------- main ----------
const want = process.argv.slice(2);
const files = readdirSync(join(HERE, 'content')).filter((f) => /^\d\d-.*\.mjs$/.test(f)).sort().filter((f) => !want.length || want.includes(f.slice(0, 2)));
const browser = await chromium.launch();
const report = [], master = [];
for (const f of files) {
  const doc = (await import(pathToFileURL(join(HERE, 'content', f)).href)).default;
  if (OMIT_REFS) {
    if (!doc.pages.some((p) => p.reference)) continue;
    doc.pages = doc.pages.filter((p) => !p.reference);
    doc.file += '_without-references';
  }
  const name = `${doc.file}_${EDITION}${VARIANT === 'print' ? '_print' : ''}`;
  writeFileSync(join(OUT, `${name}.html`), html(doc));
  const pg = await browser.newPage({ viewport: { width: 900, height: 1200 } });
  await pg.goto(pathToFileURL(join(OUT, `${name}.html`)).href, { waitUntil: 'load' });
  await pg.evaluate(() => document.fonts.ready);
  const { problems, photos } = await pg.evaluate(inspect, BLEED);
  const links = await pg.evaluate(() => [...new Set([...document.querySelectorAll('a[href]')].map((a) => a.getAttribute('href')))]);
  await pg.pdf({ path: join(OUT, `${name}.pdf`), preferCSSPageSize: true, printBackground: true });
  if (VARIANT === 'digital') {
    const els = await pg.$$('section.page');
    for (let i = 0; i < els.length; i++) await els[i].screenshot({ path: join(OUT, 'pages', `${doc.code}${OMIT_REFS ? 'n' : ''}-${String(i + 1).padStart(2, '0')}.png`) });
  }
  await pg.close();
  const size = readFileSync(join(OUT, `${name}.pdf`)).length;
  const lowDigital = photos.filter((x) => x.ppi < 150), lowPrint = photos.filter((x) => x.ppi < 250);
  report.push({ code: doc.code, file: `${name}.pdf`, pages: doc.pages.length, mb: +(size / 1048576).toFixed(2), problems, links, photos, lowDigital, lowPrint });
  if (!OMIT_REFS) master.push(copyMaster(doc));
  console.log(`${doc.code} ${doc.title}: ${doc.pages.length} pages, ${(size / 1048576).toFixed(2)} MB` +
    (problems.length ? `\n  ! ${problems.join('\n  ! ')}` : '') +
    (lowDigital.length ? `\n  ~ below 150 ppi: ${lowDigital.map((x) => `p${x.page} ${x.img} ${x.ppi}`).join(', ')}` : ''));
}
await browser.close();
const imgUse = Object.fromEntries([...usedImages].map(([k, v]) => [k, [...v]]));
writeFileSync(join(OUT, `build-report${OMIT_REFS ? '-without-references' : ''}.json`), JSON.stringify({ built: new Date().toISOString(), variant: VARIANT, edition: EDITION, report, images: imgUse }, null, 2));
if (!want.length && !OMIT_REFS && VARIANT === 'digital') writeFileSync(join(HERE, 'docs', 'COPY_MASTER.md'), `# NOYA Brochure Collection · Copy Master (${EDITION})\n\nGenerated by \`studio/brochures/build.mjs\` from \`studio/brochures/content/\`. Edit the content modules, not this file. Italics are marked *thus*.\n\n${master.join('\n\n---\n\n')}\n`);
if (report.some((r) => r.problems.length)) { console.error('Layout problems found.'); process.exitCode = 1; }
