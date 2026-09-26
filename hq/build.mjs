// Builds a self-contained static site into dist/ (no CDN at runtime).
import { build } from 'esbuild';
import { copyFileSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';

rmSync('dist', { recursive: true, force: true });
mkdirSync('dist');
await build({
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
