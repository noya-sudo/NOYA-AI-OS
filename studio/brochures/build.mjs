// NOYA brochure collection: content modules -> HTML -> PDF (Chromium), with page previews, an overflow and link check,
// and the copy master generated from the same source, so the copy Adam approves is exactly the copy that prints.
//
//   node studio/brochures/build.mjs            build all six publications
//   node studio/brochures/build.mjs 02 05      build only those numbers
//   DRAFT=0 node studio/brochures/build.mjs    omit the red "approval required" markers (final export after sign-off)
//
// Photos live in studio/brochures/images/ (git-ignored: the repository is public). assets.json is the asset register:
// a photo whose status is EXCLUDED stops the build; one whose status is APPROVAL REQUIRED prints, and is listed in the QC report.
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const HERE = dirname(fileURLToPath(import.meta.url));
const BRAND = join(HERE, '..', 'brand');
const OUT = join(HERE, '..', 'out', 'brochures');
const DRAFT = process.env.DRAFT !== '0';
mkdirSync(join(OUT, 'pages'), { recursive: true });

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = createRequire(join(HERE, '..', '..', 'hq', 'package.json'))('playwright-core')); }

const assets = JSON.parse(readFileSync(join(HERE, 'assets.json'), 'utf8'));
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
// Copy is written in plain text; *word* sets italic, and a line break in a title is written as \n.
const fmt = (s) => esc(s).replace(/\*([^*]+)\*/g, '<em>$1</em>').replace(/\n/g, '<br>');

const usedImages = new Map();
function img(key, where) {
  const a = assets.images[key];
  if (!a) throw new Error(`${where}: image "${key}" is not in assets.json`);
  if (a.status === 'EXCLUDED') throw new Error(`${where}: image "${key}" is excluded (${a.note})`);
  const f = join(HERE, 'images', `${key}.jpg`);
  if (!existsSync(f)) throw new Error(`${where}: images/${key}.jpg missing; run the extraction in docs/ASSET_REGISTER.md`);
  if (!usedImages.has(key)) usedImages.set(key, new Set());
  usedImages.get(key).add(where);
  return `url(data:image/jpeg;base64,${readFileSync(f).toString('base64')})`;
}

const logo = readFileSync(join(BRAND, 'logo.svg'), 'utf8').trim();

// ---------- blocks ----------
function blocks(list = [], where) {
  return list.map((b) => {
    if (b.p) return `<p class="b">${fmt(b.p)}</p>`;
    if (b.intro) return `<p class="intro">${fmt(b.intro)}</p>`;
    if (b.pull) return `<p class="pull">${fmt(b.pull)}</p>`;
    if (b.note) return `<p class="note${b.mt ? ' mt' + b.mt : ''}">${fmt(b.note)}</p>`;
    if (b.h3) return `<h3 class="h${b.mt ? ' mt' + b.mt : ''}">${fmt(b.h3)}</h3>`;
    if (b.gap) return `<div style="height:${b.gap}mm"></div>`;
    if (b.list) {
      const L = b.list, two = L.two;
      const half = two ? Math.ceil(L.items.length / 2) + 1 : 0;
      return `${L.h ? `<h3 class="h">${fmt(L.h)}</h3>` : ''}<ul class="rows${two ? ' two' : ''}" style="${two ? `--half:${half}` : ''}">${L.items.map((i) => `<li>${fmt(i)}</li>`).join('')}</ul>`;
    }
    if (b.dots) return `${b.dots.h ? `<h3 class="h">${fmt(b.dots.h)}</h3>` : ''}<ul class="dots">${b.dots.items.map((i) => `<li>${fmt(i)}</li>`).join('')}</ul>`;
    if (b.cols) return `<div class="cols c${b.cols.n}">${b.cols.items.map((i) => `<div class="item">${i.k ? `<span class="k">${fmt(i.k)}</span>` : ''}${i.h ? `<h3 class="h">${fmt(i.h)}</h3>` : ''}${i.t ? `<p>${fmt(i.t)}</p>` : ''}${i.list ? `<ul class="dots mt2">${i.list.map((x) => `<li>${fmt(x)}</li>`).join('')}</ul>` : ''}${i.more ? `<span class="more">${fmt(i.more)}</span>` : ''}</div>`).join('')}</div>`;
    if (b.box) return `<div class="box">${b.box.h ? `<h3 class="h">${fmt(b.box.h)}</h3>` : ''}${[].concat(b.box.t).map((t) => `<p${b.box.t.length > 1 ? ' style="margin-bottom:2mm"' : ''}>${fmt(t)}</p>`).join('')}</div>`;
    if (b.steps) return `<div class="steps">${b.steps.map((s, i) => `<div class="st"><span class="n">${String(i + 1).padStart(2, '0')}</span><h3 class="h">${fmt(s.h)}</h3><p>${fmt(s.t)}</p></div>`).join('')}</div>`;
    if (b.cards) return `<div class="cards c${b.cards.n}">${b.cards.items.map((c) => `<div class="card">${c.tag ? `<span class="tag">${fmt(c.tag)}</span>` : ''}<h3 class="c">${fmt(c.h)}</h3>${[].concat(c.t || []).map((t) => `<p>${fmt(t)}</p>`).join('')}${c.list ? `<ul class="dots">${c.list.map((x) => `<li>${fmt(x)}</li>`).join('')}</ul>` : ''}</div>`).join('')}</div>`;
    if (b.table) return `<table class="resp"><thead><tr>${b.table.head.map((h) => `<th>${fmt(h)}</th>`).join('')}</tr></thead><tbody>${b.table.rows.map((r) => `<tr>${r.map((c) => `<td>${fmt(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
    if (b.photos) return `<div class="strip" style="grid-template-columns:${b.photos.cols || `repeat(${b.photos.imgs.length},1fr)`};height:${b.photos.h}mm">${b.photos.imgs.map((k) => `<div class="p" style="background-image:${img(k, where)}"></div>`).join('')}</div>`;
    if (b.lines) return `<div class="lines">${b.lines.map((l, i) => `<p class="${i % 2 ? 'dim' : ''}">${fmt(l)}</p>`).join('')}</div>`;
    if (b.entry) {
      const e = b.entry;
      return `<div class="entry"><div class="meta">${e.meta.map((m) => `<span>${fmt(m)}</span>`).join('')}</div><h3 class="e">${fmt(e.title)}</h3><div class="g"><div><h3 class="h">The brief</h3><p>${fmt(e.brief)}</p></div><div><h3 class="h">What NOYA delivered</h3><p>${fmt(e.delivered)}</p></div><div><h3 class="h">Outcome</h3><p>${fmt(e.outcome)}</p></div></div></div>`;
    }
    if (b.pending) return `<div class="pending">${fmt(b.pending)}</div>`;
    if (b.contact) return contactBlock(b.contact);
    if (b.collection) return `<div class="collection"><b>The NOYA collection</b>${fmt(b.collection)}</div>`;
    throw new Error(`${where}: unknown block ${JSON.stringify(Object.keys(b))}`);
  }).join('\n');
}

function contactBlock(c) {
  const rows = [
    ['NOYA Concierge', c.founder ? 'Adam Elshazly, Founder' : 'Private and confidential', null],
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
  let inner = '';
  switch (p.layout) {
    case 'cover':
      inner = `${p.img ? `<div class="ph" style="background-image:${img(p.img, where)};${pos}"></div><div class="shade"></div>` : ''}<div class="logo">${logo}</div>
        <div class="txt"><div class="kick">${fmt(p.kicker)}</div><h1 class="t">${fmt(p.title)}</h1><p class="line">${fmt(p.line)}</p>
        <div class="base"><span>${fmt(p.base?.[0] ?? 'noyaconcierge.com')}</span><span>${fmt(p.base?.[1] ?? '')}</span></div></div>`;
      return `<section class="page cover">${draft}${inner}</section>`;
    case 'statement':
      inner = `<div class="frame">${head(p)}${blocks(p.blocks, where)}</div>`;
      return `<section class="page statement${navy ? ' navy' : ''}">${draft}${inner}${rf}</section>`;
    case 'split':
      inner = `<div class="ph" style="background-image:${img(p.img, where)};${pos}"></div><div class="col">${head(p)}${blocks(p.blocks, where)}</div>`;
      return `<section class="page split ${p.side || 'left'}${navy ? ' navy' : ''}">${draft}${inner}${rf}</section>`;
    case 'band':
      inner = `<div class="ph" style="background-image:${img(p.img, where)};--h:${p.h || 112}mm;${pos}"></div>${p.cap ? `<div class="cap" style="--h:${p.h || 112}mm">${fmt(p.cap)}</div>` : ''}<div class="frame" style="--h:${p.h || 112}mm">${head(p)}${blocks(p.blocks, where)}</div>`;
      return `<section class="page band${navy ? ' navy' : ''}" style="--h:${p.h || 112}mm">${draft}${inner}${rf}</section>`;
    case 'text':
      inner = `<div class="frame">${head(p)}${blocks(p.blocks, where)}</div>`;
      return `<section class="page text${navy ? ' navy' : ''}">${draft}${inner}${rf}</section>`;
    case 'closing':
      inner = `${p.img ? `<div class="ph" style="background-image:${img(p.img, where)};--h:${p.h || 118}mm;${pos}"></div>` : ''}<div class="frame" style="--h:${p.img ? (p.h || 118) : 40}mm">
        <div class="logo" style="margin-bottom:7mm">${logo}</div>${head(p)}${blocks(p.blocks, where)}</div>`;
      return `<section class="page closing navy" style="--h:${p.h || 118}mm">${draft}${inner}${rf}</section>`;
    default: throw new Error(`${where}: unknown layout ${p.layout}`);
  }
}

function html(doc) {
  // Only the foundation of the house style (fonts, colour tokens, page box) is taken from brand.css; its component classes belong to Studio briefs.
  const brandCss = readFileSync(join(BRAND, 'brand.css'), 'utf8').split('/* Wordmark')[0]
    .replace(/url\((fonts\/[^)]+)\)/g, (_, f) => `url(data:font/woff2;base64,${readFileSync(join(BRAND, f)).toString('base64')})`);
  const css = readFileSync(join(HERE, 'brochure.css'), 'utf8');
  return `<!doctype html><html lang="en-GB"><head><meta charset="utf-8"><title>${esc(doc.title)}</title>
<meta name="author" content="NOYA Concierge"><meta name="description" content="${esc(doc.description)}">
<style>${brandCss}\n${css}</style></head><body>${doc.pages.map((p, i) => page(p, i + 1, doc)).join('\n')}</body></html>`;
}

// Runs in the page: every text container must end inside its frame and above the running foot.
function overflowCheck() {
  const problems = [];
  document.querySelectorAll('.page').forEach((pg, i) => {
    const pr = pg.getBoundingClientRect();
    const foot = pg.querySelector('.rf');
    const limit = foot ? foot.getBoundingClientRect().top - 3 : pr.bottom - 8;
    pg.querySelectorAll('.frame, .col').forEach((fr) => {
      const fb = fr.getBoundingClientRect();
      let max = 0;
      fr.querySelectorAll('*').forEach((el) => { const r = el.getBoundingClientRect(); if (r.height) max = Math.max(max, r.bottom); });
      if (max > limit + 0.5) problems.push(`page ${i + 1}: content ends ${Math.round(max - limit)}px below the safe area`);
      if (fb.right > pr.right + 1) problems.push(`page ${i + 1}: frame wider than page`);
    });
    pg.querySelectorAll('.cover .txt').forEach((t) => { if (t.getBoundingClientRect().top < pr.top + 260) problems.push(`page ${i + 1}: cover text collides with the logo`); });
  });
  return problems;
}

// ---------- copy master (markdown from the same source) ----------
function copyMaster(doc) {
  const out = [`## ${doc.code} · ${doc.title}`, '', `*Audience:* ${doc.audience}  `, `*Purpose:* ${doc.purpose}  `, `*Pages:* ${doc.pages.length}`, ''];
  const md = (s) => String(s).replace(/\n/g, ' ');
  doc.pages.forEach((p, i) => {
    out.push(`### Page ${String(i + 1).padStart(2, '0')} · ${p.layout}${p.img ? ` · photo: ${p.img}` : ''}${p.approval ? ` · **APPROVAL: ${p.approval}**` : ''}`, '');
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
      else if (b.cols) { b.cols.items.forEach((x) => out.push(`- **${md(x.h || x.k || '')}**${x.t ? ` ${md(x.t)}` : ''}${x.list ? ` (${x.list.map(md).join('; ')})` : ''}${x.more ? ` *${md(x.more)}*` : ''}`)); out.push(''); }
      else if (b.box) { out.push(`${b.box.h ? `**${md(b.box.h)}** ` : ''}${[].concat(b.box.t).map(md).join(' ')}`, ''); }
      else if (b.steps) { b.steps.forEach((s, j) => out.push(`${j + 1}. **${md(s.h)}** ${md(s.t)}`)); out.push(''); }
      else if (b.cards) { b.cards.items.forEach((c) => { out.push(`- **${md(c.h)}**${c.tag ? ` (${md(c.tag)})` : ''}: ${[].concat(c.t || []).map(md).join(' ')}`); (c.list || []).forEach((x) => out.push(`  - ${md(x)}`)); }); out.push(''); }
      else if (b.table) { out.push(`| ${b.table.head.join(' | ')} |`, `|${b.table.head.map(() => '---').join('|')}|`); b.table.rows.forEach((r) => out.push(`| ${r.map(md).join(' | ')} |`)); out.push(''); }
      else if (b.lines) { b.lines.forEach((l) => out.push(md(l) + '  ')); out.push(''); }
      else if (b.entry) { const e = b.entry; out.push(`**${md(e.title)}** (${e.meta.join(' · ')})`, `- Brief: ${md(e.brief)}`, `- Delivered: ${md(e.delivered)}`, `- Outcome: ${md(e.outcome)}`, ''); }
      else if (b.pending) out.push(`> [PENDING] ${md(b.pending)}`, '');
      else if (b.contact) out.push('*[Standard NOYA contact block: NOYA Concierge · Adam Elshazly, Founder · noya@noyaconcierge.com · WhatsApp +44 786 456 9006 · noyaconcierge.com · @noyaconcierge]*', '');
      else if (b.collection) out.push(`*The NOYA collection:* ${md(b.collection)}`, '');
    }
  });
  return out.join('\n');
}

// ---------- main ----------
const want = process.argv.slice(2);
const files = readdirSync(join(HERE, 'content')).filter((f) => /^\d\d-.*\.mjs$/.test(f)).sort().filter((f) => !want.length || want.includes(f.slice(0, 2)));
const browser = await chromium.launch(existsSync('/opt/pw-browsers/chromium') ? {} : {});
const report = [];
const master = [];
for (const f of files) {
  const doc = (await import(pathToFileURL(join(HERE, 'content', f)).href)).default;
  const h = html(doc);
  const name = doc.file + (DRAFT ? '' : '');
  writeFileSync(join(OUT, `${name}.html`), h);
  const pg = await browser.newPage({ viewport: { width: 900, height: 1200 } });
  await pg.goto(pathToFileURL(join(OUT, `${name}.html`)).href, { waitUntil: 'load' });
  await pg.evaluate(() => document.fonts.ready);
  const fontsOk = await pg.evaluate(() => [...document.fonts].filter((x) => x.status === 'loaded').map((x) => x.family));
  const problems = await pg.evaluate(overflowCheck);
  const links = await pg.evaluate(() => [...document.querySelectorAll('a[href]')].map((a) => a.getAttribute('href')));
  await pg.pdf({ path: join(OUT, `${name}.pdf`), format: 'A4', printBackground: true, preferCSSPageSize: true });
  const els = await pg.$$('section.page');
  for (let i = 0; i < els.length; i++) await els[i].screenshot({ path: join(OUT, 'pages', `${doc.code}-${String(i + 1).padStart(2, '0')}.png`) });
  await pg.close();
  const size = readFileSync(join(OUT, `${name}.pdf`)).length;
  report.push({ code: doc.code, file: `${name}.pdf`, pages: doc.pages.length, mb: +(size / 1048576).toFixed(2), problems, fonts: [...new Set(fontsOk)], links: [...new Set(links)], approvals: doc.pages.map((p, i) => p.approval ? `p${i + 1}: ${p.approval}` : null).filter(Boolean) });
  master.push(copyMaster(doc));
  console.log(`${doc.code} ${doc.title}: ${doc.pages.length} pages, ${(size / 1048576).toFixed(2)} MB${problems.length ? '\n  ! ' + problems.join('\n  ! ') : ''}`);
}
await browser.close();
const imgUse = Object.fromEntries([...usedImages].map(([k, v]) => [k, [...v]]));
writeFileSync(join(OUT, 'build-report.json'), JSON.stringify({ built: new Date().toISOString(), draft: DRAFT, report, images: imgUse }, null, 2));
if (!want.length) writeFileSync(join(HERE, 'docs', 'COPY_MASTER.md'), `# NOYA Brochure Collection · Copy Master\n\nGenerated by \`studio/brochures/build.mjs\` from \`studio/brochures/content/\`. Edit the content modules, not this file.\nItalics in titles are marked *thus*. Pages marked APPROVAL carry a claim, image or term that needs sign-off before release.\n\n${master.join('\n\n---\n\n')}\n`);
if (report.some((r) => r.problems.length)) { console.error('Layout problems found.'); process.exitCode = 1; }
