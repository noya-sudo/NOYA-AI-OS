// NOYA 26 client (STORE): post a Studio PDF to workflow 26, which stores it in the private studio-pdfs bucket only if it is
// exactly that document's PDF (its fingerprint and size, checked by Supabase). The Studio card in HQ then previews it, and its
// Attach to email button has workflow 26 put it on the document's own Gmail draft, download it back, match it byte for byte and
// only then record READY TO SEND. Nothing is sent. This script holds no credential.
// The webhook URL is not in this public repo: pass it in NOYA_ATTACH_URL (n8n shows it on workflow 26's webhook node).
//   NOYA_ATTACH_URL=... node n8n/attach_pdf.mjs <slug> <version> <file.pdf>
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { pdfFingerprint } from '../studio/record.mjs';

const [slug, version, file] = process.argv.slice(2);
const url = process.env.NOYA_ATTACH_URL;
if (!slug || !/^\d+$/.test(version || '') || !file) { console.error('Usage: NOYA_ATTACH_URL=... node n8n/attach_pdf.mjs <slug> <version> <file.pdf>'); process.exit(2); }
if (!/^https:\/\/noyaprivate\.app\.n8n\.cloud\/webhook\/noya-studio-attach-[0-9a-f]{24}$/.test(url || '')) { console.error('NOYA_ATTACH_URL must be the workflow 26 production webhook'); process.exit(2); }

const buf = readFileSync(file);
if (buf.subarray(0, 5).toString('latin1') !== '%PDF-') { console.error(`${file} is not a PDF`); process.exit(2); }
console.log(JSON.stringify({ slug, version: Number(version), bytes: buf.length, sha256: createHash('sha256').update(buf).digest('hex'), fingerprint: pdfFingerprint(buf) }));

// curl, because it goes through this environment's HTTPS proxy without extra settings. -F sends multipart: file, slug, version.
let out;
try {
  out = execFileSync('curl', ['-sS', '--max-time', '170', '-w', '\n%{http_code}', '-F', `file=@${file};type=application/pdf`, '-F', `slug=${slug}`, '-F', `version=${version}`, url], { encoding: 'utf8' });
} catch (e) { console.error(e.stderr || e.message); process.exit(1); }
const code = out.slice(out.lastIndexOf('\n') + 1); const body = out.slice(0, out.lastIndexOf('\n'));
console.log(code, body);
process.exit(code === '200' ? 0 : 1);
