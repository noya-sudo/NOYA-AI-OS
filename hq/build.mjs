// Builds a self-contained static site into dist/ (no CDN at runtime).
import { build } from 'esbuild';
import { copyFileSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';

rmSync('dist', { recursive: true, force: true });
mkdirSync('dist');
await build({
  define: { __HAS_LOGO__: String(existsSync('src/noya-mark.svg')) },
  entryPoints: ['src/app.js'],
  bundle: true,
  minify: true,
  format: 'esm',
  target: ['es2020'],
  outfile: 'dist/app.js',
  legalComments: 'none',
});
copyFileSync('src/index.html', 'dist/index.html');
copyFileSync('src/styles.css', 'dist/styles.css');
// Inter, served locally (the CSP allows no third-party font hosts).
mkdirSync('dist/fonts');
copyFileSync('node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2', 'dist/fonts/inter-latin-wght-normal.woff2');
// Optional NOYA logo mark: drop the official vector file at src/noya-mark.svg.
if (existsSync('src/noya-mark.svg')) copyFileSync('src/noya-mark.svg', 'dist/noya-mark.svg');
// Security headers for static hosts that read a _headers file (Cloudflare Pages, Netlify).
writeFileSync('dist/_headers', `/*
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  Permissions-Policy: camera=(), microphone=(), geolocation=()
  Strict-Transport-Security: max-age=31536000; includeSubDomains
  X-Robots-Tag: noindex, nofollow
`);
writeFileSync('dist/robots.txt', 'User-agent: *\nDisallow: /\n');
console.log('built dist/');
