// NOYA Studio renderer: studio/documents/<slug>.json -> studio/out/<slug>.pdf (+ .html and page previews for review).
// Usage: node studio/render.mjs studio/documents/ykone-egypt-brief.json [more.json ...]
// Fonts and the logo are embedded, so the PDF is self-contained. A page whose text overflows fails the render.
import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join, basename, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import { renderDocument } from './templates.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const BRAND = join(HERE, 'brand');
const OUT = join(HERE, 'out');
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const { chromium } = createRequire(join(HERE, '..', 'hq', 'package.json'))('playwright-core');

// One central logo: brand/logo.svg (single colour, fill="currentColor") replaces the typeset wordmark in every document.
function brand() {
  const css = readFileSync(join(BRAND, 'brand.css'), 'utf8').replace(/url\((fonts\/[^)]+)\)/g, (_, f) =>
    `url(data:font/woff2;base64,${readFileSync(join(BRAND, f)).toString('base64')})`);
  const logoPath = join(BRAND, 'logo.svg');
  const logo = existsSync(logoPath) ? readFileSync(logoPath, 'utf8').replace(/<\?xml[^>]*>/, '').trim() : null;
  return { css, logo };
}

async function render(file, browser) {
  const doc = JSON.parse(readFileSync(file, 'utf8'));
  const slug = doc.slug || basename(file, '.json');
  const html = renderDocument(doc, brand());
  mkdirSync(OUT, { recursive: true });
  const htmlPath = join(OUT, `${slug}.html`);
  writeFileSync(htmlPath, html);
  const page = await browser.newPage({ viewport: { width: 900, height: 1200 }, deviceScaleFactor: 2 });
  await page.goto(pathToFileURL(htmlPath).href);
  await page.evaluate(() => document.fonts.ready);
  // QA: no text may run past a page's text area, and the brand fonts must be the ones in use.
  const qa = await page.evaluate(() => {
    const over = [...document.querySelectorAll('.page')].map((p, i) => {
      const b = p.querySelector('.body') || p;
      return b.scrollHeight > b.clientHeight + 1 ? { page: i + 1, by_px: b.scrollHeight - b.clientHeight } : null;
    }).filter(Boolean);
    const fonts = ['Cormorant Garamond', 'Jost'].map((f) => ({ f, ok: document.fonts.check(`12px "${f}"`) }));
    return { pages: document.querySelectorAll('.page').length, over, fonts };
  });
  const shots = [];
  const els = await page.$$('.page');
  for (let i = 0; i < els.length; i++) {
    const p = join(OUT, `${slug}-p${String(i + 1).padStart(2, '0')}.png`);
    await els[i].screenshot({ path: p });
    shots.push(p);
  }
  const pdfPath = join(OUT, `${slug}.pdf`);
  await page.pdf({ path: pdfPath, preferCSSPageSize: true, printBackground: true });
  await page.close();
  return { slug, pdf: pdfPath, bytes: statSync(pdfPath).size, ...qa, shots, logo: brand().logo ? 'brand/logo.svg' : 'typeset wordmark (logo.svg not yet supplied)' };
}

const files = process.argv.slice(2).map((f) => resolve(f));
if (!files.length) { console.error('Usage: node studio/render.mjs studio/documents/<slug>.json'); process.exit(2); }
const browser = await chromium.launch({ executablePath: CHROME });
let failed = false;
for (const f of files) {
  const r = await render(f, browser);
  const ok = !r.over.length && r.fonts.every((x) => x.ok);
  failed ||= !ok;
  console.log(JSON.stringify({ ok, ...r, shots: r.shots.length }, null, 1));
}
await browser.close();
process.exit(failed ? 1 : 0);
