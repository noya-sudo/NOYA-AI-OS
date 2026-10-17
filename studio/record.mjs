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
const DOC_TYPE = { note: 'OPPORTUNITY_NOTE', email: 'EMAIL_IDEA', onepage: 'ONE_PAGE_CONCEPT', concept: 'CONCEPT', brief: 'BRIEF', proposal: 'PROPOSAL', project: 'PROJECT', itinerary: 'ITINERARY', ops: 'OPS_ITINERARY', desk: 'DESK_BRIEF' };
const FILE_LABEL = { note: 'Opportunity note (internal)', email: 'Email idea', onepage: 'One-page concept', concept: 'Egypt Concept', brief: 'Egypt Brief', proposal: 'Egypt Proposal', project: 'Project book (internal)', itinerary: 'Itinerary', ops: 'Operations itinerary (internal)', desk: 'Egypt Desk' };

const q = (s) => (s == null ? 'null' : `'${String(s).replace(/'/g, "''")}'`);
const j = (o) => `$json$${JSON.stringify(o)}$json$::jsonb`;

export function recordSql(casePath) {
  const c = JSON.parse(readFileSync(casePath, 'utf8'));
  if (c.slug.startsWith('preview-')) return '';
  const logo = existsSync(join(HERE, 'brand', 'logo.svg')) ? 'brand/logo.svg' : 'typeset wordmark (logo.svg not yet supplied)';
  const out = [];
  for (const stage of c.build) {
    const path = join(HERE, 'documents', `${c.slug}-${stage}.json`);
    const raw = readFileSync(path, 'utf8');
    const doc = JSON.parse(raw);
    const email = stage === 'email';
    const html = join(HERE, 'out', `${doc.slug}.html`);
    const pages = !email && existsSync(html) ? readFileSync(html, 'utf8').split('<section class="page').length - 1 : null;
    const sha = createHash('sha256').update(raw).digest('hex');
    const status = doc.draft || doc.hold ? 'DRAFT' : 'FOR_REVIEW';
    const file = email ? `${doc.slug}.txt` : `${c.party} x NOYA - ${FILE_LABEL[stage]}${doc.draft ? ' (draft)' : ''}.pdf`;
    out.push(`with prev as (select max(version) as v, coalesce(bool_or(content->>'sha256' = ${q(sha)}), false) as same from public.studio_documents where slug = ${q(doc.slug)})
insert into public.studio_documents (slug, version, doc_type, title, company_id, opportunity_id, prepared_for, status, content, sources, review_notes, source_path, file_name, file_location, logo, qa, vertical, stage, audience, level, hold_reason)
select ${q(doc.slug)}, coalesce(prev.v, 0) + 1, ${q(DOC_TYPE[stage])}, ${q(doc.title.replace(/\*/g, ''))}, ${q(c.company_id)}, ${q(c.opportunity_id)}, ${q(doc.prepared_for)}, ${q(status)},
  ${j({ sha256: sha, path: relative(ROOT, path), case: relative(ROOT, casePath), title: doc.title.replace(/\*/g, ''), draft: doc.draft || null, ...(email ? { subject: doc.subject, words: doc.words } : {}) })}, ${j(email || doc.audience === 'internal' ? [] : doc.sources || [])}, ${j(doc.review || [])},
  ${q(relative(ROOT, path))}, ${q(file)}, ${q(email ? `studio/out/${doc.slug}.txt` : `studio/out/${doc.slug}.pdf (re-render from the JSON)`)}, ${q(email ? null : logo)}, ${j(email ? { words: doc.words } : { pages })}, ${q(c.vertical)}, ${q(stage)}, ${q(doc.audience.toUpperCase())}, ${doc.level ?? 'null'}, ${q(doc.hold)}
from prev where not prev.same;`);
  }
  const slugs = c.build.map((st) => q(`${c.slug}-${st}`)).join(', ');
  out.push(`update public.studio_documents d set status = 'SUPERSEDED' where d.slug in (${slugs}) and d.status in ('DRAFT', 'FOR_REVIEW')
  and d.version < (select max(x.version) from public.studio_documents x where x.slug = d.slug);`);
  return out.join('\n');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const files = process.argv.slice(2);
  if (!files.length) { console.error('Usage: node studio/record.mjs studio/cases/<slug>.json [...]'); process.exit(2); }
  console.log(files.map((f) => recordSql(resolve(f))).filter(Boolean).join('\n'));
}
