// NOYA Studio record: prints the SQL that records a case's documents in Supabase studio_documents (one row per version).
// Usage: node studio/record.mjs studio/cases/<slug>.json [...]   (template previews are never recorded)
// A row stores the document's hash, path, page count and, for client documents, the sources behind every claim; the JSON in
// studio/documents is the content (internal notes keep their facts and sources there). Re-running with an
// unchanged document adds nothing; a changed one becomes the next version and supersedes earlier unapproved versions.
// APPROVED and SENT rows are never touched. Nothing is sent anywhere.
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const DOC_TYPE = { master: 'BRIEF', note: 'OPPORTUNITY_NOTE', email: 'EMAIL_IDEA', onepage: 'ONE_PAGE_CONCEPT', concept: 'CONCEPT', brief: 'BRIEF', proposal: 'PROPOSAL', project: 'PROJECT', itinerary: 'ITINERARY', ops: 'OPS_ITINERARY', desk: 'DESK_BRIEF' };
const FILE_LABEL = { master: 'Egypt Brief', note: 'Opportunity note (internal)', email: 'Email idea', onepage: 'One-page concept', concept: 'Egypt Concept', brief: 'Egypt Brief', proposal: 'Egypt Proposal', project: 'Project book (internal)', itinerary: 'Itinerary', ops: 'Operations itinerary (internal)', desk: 'Egypt Desk' };

const q = (s) => (s == null ? 'null' : `'${String(s).replace(/'/g, "''")}'`);
const j = (o) => `$json$${JSON.stringify(o)}$json$::jsonb`;
// Render-proof fingerprint: the PDF's SHA-256 with its render timestamps blanked, so a re-render of the same document matches.
// Workflow 26 computes the same value on the file it is given.
export const pdfFingerprint = (buf) => createHash('sha256').update(buf.toString('latin1').replace(/\(D:\d{14}[^)]*\)/g, '(D:)'), 'latin1').digest('hex');

export function recordSql(casePath) {
  const c = JSON.parse(readFileSync(casePath, 'utf8'));
  if (c.slug.startsWith('preview-')) return '';
  const logo = existsSync(join(HERE, 'brand', 'logo.svg')) ? 'brand/logo.svg' : 'typeset wordmark (logo.svg not yet supplied)';
  const out = [];
  for (const stage of c.build) {
    const path = join(HERE, 'documents', `${c.slug}-${stage === 'master' ? 'brief' : stage}.json`);  // the master brief continues the brief's versions
    const raw = readFileSync(path, 'utf8');
    const doc = JSON.parse(raw);
    const email = stage === 'email';
    const html = join(HERE, 'out', `${doc.slug}.html`);
    const pages = !email && existsSync(html) ? readFileSync(html, 'utf8').split('<section class="page').length - 1 : null;
    const sha = createHash('sha256').update(raw).digest('hex');
    const status = doc.draft || doc.hold ? 'DRAFT' : 'FOR_REVIEW';
    // Readiness: what HQ's READY means (Adam could genuinely send it now). Client documents need the Brand & Quality Reviewer's pass.
    const rvPath = join(HERE, 'out', `${doc.slug}.review.json`);
    const rv = doc.audience === 'client' && existsSync(rvPath) ? JSON.parse(readFileSync(rvPath, 'utf8')) : null;
    const reviewer = rv ? { ok: rv.ok, checks: rv.checks, failed: rv.failed } : null;
    // A document that travels as a PDF on the case's Gmail draft (and that cover email) is READY_FOR_ATTACHMENT until the PDF is
    // verified on the draft (Adam, 21 Oct: never READY TO SEND without the attachment); the database guard enforces the same.
    const attached = !!c.email?.attach && (stage === c.email.attach || email);
    const ready = doc.audience === 'internal' ? ['INTERNAL_ONLY', 'Internal document: never sent']
      : doc.hold ? ['HOLD', doc.hold]
      : doc.draft ? ['NEEDS_UPDATE', doc.draft]
      : !rv ? ['NEEDS_UPDATE', 'Not yet reviewed by the Brand & Quality Reviewer']
      : rv.ok ? ['READY_TO_SEND', 'Passed the Brand & Quality Reviewer; Adam approves and sends']
      : ['NEEDS_UPDATE', rv.failed.join('; ')];
    const [readyClass, readyReason] = ready[0] === 'READY_TO_SEND' && attached
      ? ['READY_FOR_ATTACHMENT', email ? 'Cover email: READY TO SEND once its PDF is verified on the Gmail draft' : 'Passed the Brand & Quality Reviewer; READY TO SEND once the PDF is verified on the Gmail draft']
      : ready;
    // The PDF's fingerprints: only this exact file (or a re-render of it, the same but for its timestamp) may go on the draft.
    const pdfPath = join(HERE, 'out', `${doc.slug}.pdf`);
    const pdf = !email && existsSync(pdfPath) ? readFileSync(pdfPath) : null;
    const file = email ? `${doc.slug}.txt` : `${c.party} x NOYA - ${FILE_LABEL[stage]}${doc.draft ? ' (draft)' : ''}.pdf`;
    out.push(`with prev as (select max(version) as v, coalesce(bool_or(content->>'sha256' = ${q(sha)}), false) as same from public.studio_documents where slug = ${q(doc.slug)})
insert into public.studio_documents (slug, version, doc_type, title, company_id, opportunity_id, prepared_for, status, content, sources, review_notes, source_path, file_name, file_location, logo, qa, vertical, stage, audience, level, hold_reason, ready_class, ready_reason, ready_checked_at)
select ${q(doc.slug)}, coalesce(prev.v, 0) + 1, ${q(DOC_TYPE[stage])}, ${q(doc.title.replace(/\*/g, ''))}, ${q(c.company_id)}, ${q(c.opportunity_id)}, ${q(doc.prepared_for)}, ${q(status)},
  ${j({ sha256: sha, path: relative(ROOT, path), case: relative(ROOT, casePath), title: doc.title.replace(/\*/g, ''), draft: doc.draft || null, ...(email ? { subject: doc.subject, words: doc.words } : {}), ...(pdf ? { pdf_sha256: createHash('sha256').update(pdf).digest('hex'), pdf_fingerprint: pdfFingerprint(pdf), pdf_bytes: pdf.length } : {}) })}, ${j(email || doc.audience === 'internal' ? [] : doc.sources || [])}, ${j(doc.review || [])},
  ${q(relative(ROOT, path))}, ${q(file)}, ${q(email ? `studio/out/${doc.slug}.txt` : `studio/out/${doc.slug}.pdf (re-render from the JSON)`)}, ${q(email ? null : logo)}, ${j({ ...(email ? { words: doc.words } : { pages }), reviewer })}, ${q(c.vertical)}, ${q(stage)}, ${q(doc.audience.toUpperCase())}, ${doc.level ?? 'null'}, ${q(doc.hold)},
  ${q(readyClass)}, ${q(readyReason)}, now()
from prev where not prev.same;`);
  }
  const slugs = c.build.map((st) => q(`${c.slug}-${st === 'master' ? 'brief' : st}`)).join(', ');
  out.push(`update public.studio_documents d set status = 'SUPERSEDED', ready_class = 'SUPERSEDED', ready_reason = 'A later version replaces it' where d.slug in (${slugs}) and d.status in ('DRAFT', 'FOR_REVIEW')
  and d.version < (select max(x.version) from public.studio_documents x where x.slug = d.slug);`);
  return out.join('\n');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const files = process.argv.slice(2);
  if (!files.length) { console.error('Usage: node studio/record.mjs studio/cases/<slug>.json [...]'); process.exit(2); }
  console.log(files.map((f) => recordSql(resolve(f))).filter(Boolean).join('\n'));
}
