// NOYA Studio renderer: document JSON -> HTML -> PDF (Chromium), with page previews for review.
// Usage: node studio/render.mjs studio/documents/<slug>.json [more.json ...]
// Pages paginate themselves: a block that does not fit moves to a continuation page (a section heading travels with the
// block after it), so a master holds whatever length a case brings. A single block taller than a page fails the render.
// Fonts and the logo are embedded, so every PDF is self-contained.
import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join, basename, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import { renderDocument, documentPages, shell } from './templates.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const BRAND = join(HERE, 'brand');
export const OUT = join(HERE, 'out');
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const { chromium } = createRequire(join(HERE, '..', 'hq', 'package.json'))('playwright-core');

// One central logo: brand/logo.svg (single colour, fill="currentColor") replaces the typeset wordmark in every document.
export function brand() {
  const css = readFileSync(join(BRAND, 'brand.css'), 'utf8').replace(/url\((fonts\/[^)]+)\)/g, (_, f) =>
    `url(data:font/woff2;base64,${readFileSync(join(BRAND, f)).toString('base64')})`);
  const logoPath = join(BRAND, 'logo.svg');
  const logo = existsSync(logoPath) ? readFileSync(logoPath, 'utf8').replace(/<\?xml[^>]*>/, '').trim() : null;
  return { css, logo };
}

// Runs in the page: move overflowing blocks to continuation pages, then renumber each document's pages.
function paginate() {
  for (const docEl of document.querySelectorAll('.doc')) {
    let i = 0;
    while (true) {
      const pages = [...docEl.querySelectorAll(':scope > .page')];
      if (i >= pages.length) break;
      const p = pages[i];
      if (p.classList.contains('one')) { i++; continue; }  // a one-page concept never spills onto a second page
      const body = p.querySelector('.body');
      let guard = 0;
      while (body && body.scrollHeight > body.clientHeight + 1 && guard++ < 200) {
        const kids = [...body.children];
        if (kids.length < 2 || (kids.length === 2 && kids[0].classList.contains('sec'))) break;  // one block taller than a page
        let next = p.nextElementSibling;
        if (!next || next.dataset.contOf !== String(i)) {
          next = p.cloneNode(true);
          next.dataset.contOf = String(i);
          next.querySelector('.body').innerHTML = '';
          const contact = p.querySelector('.contact');
          if (contact) { contact.remove(); p.classList.remove('has-contact'); }
          p.after(next);
        }
        const nb = next.querySelector('.body');
        nb.prepend(body.lastElementChild);
        const tail = body.lastElementChild;
        if (tail && tail.classList.contains('sec') && body.children.length > 1) nb.prepend(tail);
      }
      i++;
    }
    [...docEl.querySelectorAll(':scope > .page')].forEach((pg, idx) => {
      const pn = pg.querySelector('.pn');
      if (pn) pn.textContent = String(idx + 1).padStart(2, '0');
    });
  }
}

function qaCheck() {
  const over = [...document.querySelectorAll('.page')].map((p, i) => {
    const b = p.querySelector('.body') || p;
    return b.scrollHeight > b.clientHeight + 1 ? { page: i + 1, by_px: b.scrollHeight - b.clientHeight } : null;
  }).filter(Boolean);
  const fonts = ['Cormorant Garamond', 'Jost'].map((f) => ({ f, ok: document.fonts.check(`12px "${f}"`) }));
  return { pages: document.querySelectorAll('.page').length, over, fonts };
}

async function print(browser, html, slug, { shots = true } = {}) {
  mkdirSync(OUT, { recursive: true });
  const htmlPath = join(OUT, `${slug}.html`);
  writeFileSync(htmlPath, html);
  const page = await browser.newPage({ viewport: { width: 900, height: 1200 }, deviceScaleFactor: 2 });
  await page.goto(pathToFileURL(htmlPath).href);
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(paginate);
  const qa = await page.evaluate(qaCheck);
  writeFileSync(htmlPath, await page.content());  // the saved HTML is the paginated one
  const files = [];
  if (shots) {
    const els = await page.$$('.page');
    for (let i = 0; i < els.length; i++) {
      const p = join(OUT, `${slug}-p${String(i + 1).padStart(2, '0')}.png`);
      await els[i].screenshot({ path: p });
      files.push(p);
    }
  }
  const pdfPath = join(OUT, `${slug}.pdf`);
  await page.pdf({ path: pdfPath, preferCSSPageSize: true, printBackground: true });
  await page.close();
  const ok = !qa.over.length && qa.fonts.every((x) => x.ok);
  return { ok, slug, pdf: pdfPath, bytes: statSync(pdfPath).size, ...qa, shots: files };
}

export async function renderDoc(doc, browser, opts) {
  const b = brand();
  return { ...(await print(browser, renderDocument(doc, b), doc.slug, opts)), logo: b.logo ? 'brand/logo.svg' : 'typeset wordmark (logo.svg not yet supplied)' };
}

// Several documents bound into one PDF (each keeps its own cover and page numbers).
export async function renderPack(docs, slug, title, browser, opts) {
  const b = brand();
  const body = docs.map((d) => `<div class="doc">${documentPages(d, b.logo)}</div>`).join('\n');
  return print(browser, shell(title, b.css, body), slug, opts);
}

export const launch = () => chromium.launch({ executablePath: CHROME });

// CLI
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const files = process.argv.slice(2).map((f) => resolve(f));
  if (!files.length) { console.error('Usage: node studio/render.mjs studio/documents/<slug>.json'); process.exit(2); }
  const browser = await launch();
  let failed = false;
  for (const f of files) {
    const doc = JSON.parse(readFileSync(f, 'utf8'));
    doc.slug ||= basename(f, '.json');
    const r = await renderDoc(doc, browser);
    failed ||= !r.ok;
    console.log(JSON.stringify({ ...r, shots: r.shots.length }));
  }
  await browser.close();
  process.exit(failed ? 1 : 0);
}
