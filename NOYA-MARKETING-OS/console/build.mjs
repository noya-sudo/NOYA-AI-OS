// Build the Marketing OS console into console/dist (static, self-contained, no CDN).
// Live:  MOS_SUPABASE_URL=... MOS_SUPABASE_PUBLISHABLE_KEY=... node console/build.mjs
// Demo:  node console/build.mjs            (no env: ships the local test snapshot, makes no network calls)
import { cpSync, mkdirSync, rmSync, writeFileSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const src = join(here, 'src');
const dist = join(here, 'dist');
const url = (process.env.MOS_SUPABASE_URL || '').trim().replace(/\/$/, '');
const key = (process.env.MOS_SUPABASE_PUBLISHABLE_KEY || '').trim();
const env = (process.env.MOS_ENV || (url ? 'production' : 'development')).trim();

if (url && !/^https:\/\/[a-z0-9]{20}\.supabase\.co$/.test(url)) throw new Error('MOS_SUPABASE_URL must be https://<ref>.supabase.co');
if (key && !(key.startsWith('sb_publishable_') || /^eyJ/.test(key))) throw new Error('MOS_SUPABASE_PUBLISHABLE_KEY must be a publishable key');
if (key && /service_role|sb_secret_/.test(key + (key.startsWith('eyJ') ? Buffer.from(key.split('.')[1] || '', 'base64url').toString() : ''))) {
  throw new Error('Refusing to build: that is a SECRET key, not a publishable key');
}

rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });
cpSync(src, dist, { recursive: true });
writeFileSync(join(dist, 'config.js'),
  `window.MOS_CONFIG = ${JSON.stringify({ supabaseUrl: url, publishableKey: key, environment: env }, null, 2)};\n`);
if (!url) cpSync(join(here, 'fixtures'), join(dist, 'fixtures'), { recursive: true });

const connect = url ? `'self' ${url}` : `'self'`;
writeFileSync(join(dist, '_headers'), `/*
  Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self' data:; connect-src ${connect}; base-uri 'none'; form-action 'self'; frame-ancestors 'none'
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  Permissions-Policy: camera=(), microphone=(), geolocation=()
  Cache-Control: no-store
  X-Robots-Tag: noindex, nofollow
`);
writeFileSync(join(dist, 'robots.txt'), 'User-agent: *\nDisallow: /\n');

// Scan the output for anything secret-shaped.
const bad = [/sb_secret_/, /service_role/, /sk-ant-/, /-----BEGIN [A-Z ]*PRIVATE KEY-----/, /re_[A-Za-z0-9]{8,}_[A-Za-z0-9]{16,}/];
const walk = (d) => readdirSync(d).flatMap((n) => statSync(join(d, n)).isDirectory() ? walk(join(d, n)) : [join(d, n)]);
for (const f of walk(dist)) {
  if (f.endsWith('.woff2')) continue;
  const t = readFileSync(f, 'utf8');
  for (const re of bad) if (re.test(t)) throw new Error(`Secret-shaped content in ${f}`);
}
console.log(`Console built (${url ? 'live: ' + url : 'demo mode'}) -> ${dist}`);
