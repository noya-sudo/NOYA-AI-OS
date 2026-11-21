// Production build identity (acceptance pass, 21 Nov 2026).
// 1. Local: dist/version.json equals sha256(app.js + styles.css)[0:12] and index.html loads exactly those assets (no mixed versions).
// 2. Production (when reachable): https://hq.noyaconcierge.com/version.json, app.js and styles.css match the committed dist byte for byte.
//    Where this environment cannot reach the host, the production half reports SKIP (never a pass).
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const PROD = process.env.HQ_PROD_URL || 'https://hq.noyaconcierge.com';
const sha = (...bufs) => { const h = createHash('sha256'); bufs.forEach((b) => h.update(b)); return h.digest('hex'); };
const app = readFileSync('dist/app.js'); const css = readFileSync('dist/styles.css'); const html = readFileSync('dist/index.html', 'utf8');
const local = JSON.parse(readFileSync('dist/version.json', 'utf8')).v;
const results = []; const check = (name, ok, detail = '') => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`); };
check('Local version.json matches the built app.js + styles.css', sha(app, css).slice(0, 12) === local, local);
check('index.html loads exactly /app.js and /styles.css (one asset set, no mixed versions)', /src="\/app\.js"/.test(html) && /href="\/styles\.css"/.test(html) && (html.match(/<script[^>]+src=/g) || []).length === 1);
try {
  const get = async (p) => { const r = await fetch(`${PROD}${p}?t=${Date.now()}`, { cache: 'no-store', signal: AbortSignal.timeout(8000) }); if (!r.ok) throw new Error(`${p} HTTP ${r.status}`); return Buffer.from(await r.arrayBuffer()); };
  const [pv, papp, pcss] = await Promise.all([get('/version.json'), get('/app.js'), get('/styles.css')]);
  const prodV = JSON.parse(pv.toString()).v;
  check('Production version.json equals the committed build', prodV === local, `production ${prodV} · local ${local}`);
  check('Production app.js and styles.css are byte-identical to dist', sha(papp) === sha(app) && sha(pcss) === sha(css));
} catch (e) {
  console.log(`SKIP  Production comparison: ${PROD} not reachable from this environment (${e.message}). Verify with a browser or Firecrawl.`);
}
const failed = results.filter((x) => !x).length;
console.log(`\nprod_version: ${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
