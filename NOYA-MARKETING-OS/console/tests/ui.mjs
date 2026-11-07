// Headless browser check of the console in demo mode. Serves console/dist on a local port.
// Usage: node console/build.mjs && node console/tests/ui.mjs
import { createServer } from 'node:http';
import { readFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const here = dirname(fileURLToPath(import.meta.url));
const dist = join(here, '..', 'dist');
const out = join(here, 'out'); mkdirSync(out, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.woff2': 'font/woff2' };

const server = createServer((req, res) => {
  const p = join(dist, decodeURIComponent(new URL(req.url, 'http://x').pathname).replace(/\/$/, '/index.html'));
  if (!p.startsWith(dist) || !existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[extname(p)] || 'application/octet-stream' });
  res.end(readFileSync(p));
}).listen(0);
const base = `http://127.0.0.1:${server.address().port}/`;

let failures = 0;
const check = (cond, label) => { console.log(`${cond ? 'PASS' : 'FAIL'}  ${label}`); if (!cond) failures++; };

const browser = await chromium.launch();
try {
  for (const [name, viewport] of [['desktop', { width: 1366, height: 900 }], ['mobile', { width: 390, height: 844 }]]) {
    const page = await browser.newPage({ viewport, deviceScaleFactor: 1 });
    const errors = []; const requests = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    page.on('request', (r) => requests.push(r.url()));
    await page.goto(base);
    await page.waitForSelector('#t-switches tr');
    const txt = (sel) => page.locator(sel).innerText();

    check((await page.locator('#t-switches tr').count()) === 8, `${name}: 8 kill switches rendered`);
    check((await txt('#t-switches')).toLowerCase().split('disabled').length - 1 === 8, `${name}: all 8 show disabled`);
    check((await txt('#exec-badge')).toLowerCase().includes('disabled'), `${name}: header shows external execution disabled`);
    check(await page.locator('#demo-banner').isVisible(), `${name}: demo banner visible`);
    check((await page.locator('#t-approvals tr').count()) >= 1, `${name}: pending approvals listed`);
    check((await txt('#t-services')).includes('Instagram'), `${name}: connected-services panel`);
    check((await txt('#t-health')).includes('audit chain'), `${name}: database health panel`);
    check((await page.locator('#t-agents tr').count()) === 7, `${name}: 7 agents listed (all off)`);
    check((await page.locator('#t-audit tr').count()) >= 3, `${name}: audit events listed`);
    check((await txt('#l-security')).includes('refused'), `${name}: security alerts show the refused agent spend proposal`);
    check((await txt('#t-config')).includes('safety.auto_pause_ads'), `${name}: configuration panel`);
    check((await txt('#t-secrets')).toLowerCase().includes('not set'), `${name}: secrets shown by name only`);
    check((await page.locator('button:visible', { hasText: /enable|publish|activate|launch/i }).count()) === 0, `${name}: no enable / publish / ad controls`);
    check(errors.length === 0, `${name}: no console errors ${errors.join(' | ')}`);
    check(requests.every((u) => u.startsWith(base)), `${name}: no external network requests in demo mode`);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    check(overflow <= 1, `${name}: no horizontal page scroll (${overflow}px)`);
    await page.screenshot({ path: join(out, `console-${name}.png`), fullPage: true });
    await page.close();
  }

  // Login screen renders when a live config is present (no network: we only look at the form).
  const page = await browser.newPage();
  await page.addInitScript(() => { Object.defineProperty(window, 'MOS_CONFIG', { value: { supabaseUrl: 'https://abcdefghijklmnopqrst.supabase.co', publishableKey: 'sb_publishable_x' }, writable: false }); });
  await page.route('**/config.js', (r) => r.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.goto(base);
  check(await page.locator('#login').isVisible(), 'live config: sign-in form shown before any data');
  check(!(await page.locator('#desk').isVisible()), 'live config: desk hidden until signed in');
  await page.close();
} finally {
  await browser.close();
  server.close();
}
if (failures) { console.error(`${failures} console check(s) failed`); process.exit(1); }
console.log('CONSOLE UI CHECKS: ALL PASSED');
