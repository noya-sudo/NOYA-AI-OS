#!/usr/bin/env node
// NOYA Marketing OS: secret scanner. No dependencies.
// Scans every file under NOYA-MARKETING-OS (except git-ignored build folders) for credential-shaped strings,
// and checks that .env.example carries no values for secret variables.
// Usage: node scripts/check-secrets.mjs   (exit 1 if anything is found)

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const skipDirs = new Set(['node_modules', 'dist', '.wrangler', '.supabase', '.git', 'out', 'fixtures']);
const self = 'scripts/check-secrets.mjs';

const patterns = [
  ['JWT (Supabase key or session token)', /eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/],
  ['Supabase secret key', /\bsb_secret_[A-Za-z0-9_-]{16,}/],
  ['Anthropic API key', /\bsk-ant-[A-Za-z0-9_-]{20,}/],
  ['OpenAI-style key', /\bsk-(proj-)?[A-Za-z0-9]{32,}/],
  ['Meta access token', /\bEAA[A-Za-z0-9]{60,}/],
  ['Resend API key', /\bre_[A-Za-z0-9]{8,}_[A-Za-z0-9]{16,}/],
  ['Firecrawl key', /\bfc-[a-f0-9]{32}\b/],
  ['AWS access key', /\bAKIA[0-9A-Z]{16}\b/],
  ['Google API key', /\bAIza[0-9A-Za-z_-]{35}\b/],
  ['Private key block', /-----BEGIN [A-Z ]*PRIVATE KEY-----/],
  ['GitHub token', /\bgh[pousr]_[A-Za-z0-9]{36,}\b/],
  ['Postgres URL with password', /postgres(ql)?:\/\/[^:\s/]+:[^@\s]{6,}@/],
];

// Variables that must be blank in .env.example.
const secretVars = /^(.*(_KEY|_SECRET|_TOKEN|_DB_URL|_JSON|_PASSWORD))=(.+)$/;

function* walk(dir) {
  for (const name of readdirSync(dir)) {
    if (skipDirs.has(name)) continue;
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) yield* walk(p);
    else if (st.size < 2_000_000) yield p;
  }
}

const findings = [];
for (const file of walk(root)) {
  const rel = relative(root, file);
  if (rel === self) continue;
  let text;
  try { text = readFileSync(file, 'utf8'); } catch { continue; }
  if (text.includes('\u0000')) continue; // binary
  const lines = text.split('\n');
  lines.forEach((line, i) => {
    for (const [label, re] of patterns) {
      if (re.test(line)) findings.push(`${rel}:${i + 1}  ${label}`);
    }
    if (/(^|\/)\.env(\.[^/]*)?$/.test(rel)) {
      const m = line.match(secretVars);
      if (m && m[3].trim() !== '') findings.push(`${rel}:${i + 1}  value set for secret variable ${m[1]}`);
    }
  });
}

if (findings.length) {
  console.error('Possible secrets found. Remove them and rotate anything real:\n' + findings.map(f => '  ' + f).join('\n'));
  process.exit(1);
}
console.log('No secrets found.');
