// NOYA Studio build: a case -> its stage documents -> PDFs (and the Level 1 email idea as text).
// Usage: node studio/build.mjs studio/cases/<slug>.json [stage ...]
//   stages: note email onepage concept brief proposal project itinerary ops desk (default: the case's "build" list)
// The level gate (masters/stages.mjs) builds only what the relationship has earned; a document prepared ahead is marked held.
// Writes studio/documents/<slug>-<stage>.json, studio/out/<slug>-<stage>.pdf (or .txt for the email idea), and binds the
// internal documents into studio/out/<slug>-internal-pack.pdf. Nothing is sent anywhere.
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { vertical } from './masters/verticals.mjs';
import { STAGES, gate } from './masters/stages.mjs';
import { renderDoc, renderPack, launch, OUT } from './render.mjs';
import { review, visibleText, textSegments } from './masters/reviewer.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const DOCS = join(HERE, 'documents');

export function buildDocs(casePath, stages) {
  const c = JSON.parse(readFileSync(casePath, 'utf8'));
  const v = vertical(c.vertical);
  const levels = gate(c);
  const list = stages?.length ? stages : c.build;
  return { c, v, docs: list.map((st) => {
    const f = STAGES[st];
    if (!f) throw new Error(`Unknown stage "${st}". Stages: ${Object.keys(STAGES).join(', ')}`);
    const g = levels.find((x) => x.stage === st);
    if (!g) throw new Error(`${c.slug}: "${st}" is not in the case's build list`);
    return { ...f(c, v), level: g.level, hold: g.hold };
  }) };
}

// Names that belong to other cases (companies and people): a client document must never show them.
function otherNames(c) {
  const dir = join(HERE, 'cases');
  return readdirSync(dir).filter((f) => f.endsWith('.json')).map((f) => JSON.parse(readFileSync(join(dir, f), 'utf8')))
    .filter((x) => x.slug !== c.slug).flatMap((x) => [x.company, ...(x.people || []).map((p) => p.name)]).filter((n) => n && n.length > 3);
}

// The Brand & Quality Reviewer reads each rendered client document; its verdict sits beside the PDF and is recorded by record.mjs.
function reviewDoc(d, c, render, others) {
  if (d.audience !== 'client' || c.slug.startsWith('preview-')) return null;
  const raw = readFileSync(join(OUT, `${d.slug}.${d.type === 'email' ? 'txt' : 'html'}`), 'utf8');
  const r = { slug: d.slug, ...review(d, c, { text: visibleText(raw), segments: d.type === 'email' ? raw.split('\n') : textSegments(raw), render, others }) };
  writeFileSync(join(OUT, `${d.slug}.review.json`), `${JSON.stringify(r, null, 2)}\n`);
  return r;
}

export async function buildCase(casePath, stages, browser, { write = true, shots = true } = {}) {
  const { c, docs } = buildDocs(casePath, stages);
  const others = otherNames(c);
  // Template previews (studio/examples) never land beside live client documents.
  const dir = c.slug.startsWith('preview-') ? join(HERE, 'examples', 'documents') : DOCS;
  if (write) mkdirSync(dir, { recursive: true });
  const results = [];
  for (const d of docs) {
    if (write) writeFileSync(join(dir, `${d.slug}.json`), `${JSON.stringify(d, null, 2)}\n`);
    if (d.type === 'email') {  // Level 1 is text for the email itself, not a document
      mkdirSync(OUT, { recursive: true });
      writeFileSync(join(OUT, `${d.slug}.txt`), `Subject: ${d.subject}\n\n${d.body}\n`);
      const render = { ok: true, pages: 0, over: [], fonts: [], text: join(OUT, `${d.slug}.txt`) };
      results.push({ doc: d, render, review: reviewDoc(d, c, render, others) });
      continue;
    }
    const render = await renderDoc(d, browser, { shots });
    results.push({ doc: d, render, review: reviewDoc(d, c, render, others) });
  }
  const internal = docs.filter((d) => d.audience === 'internal');
  const pack = internal.length > 1 ? await renderPack(internal, `${c.slug}-internal-pack`, `${c.company} — internal pack`, browser, { shots: false }) : null;
  return { c, results, pack };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [casePath, ...stages] = process.argv.slice(2);
  if (!casePath) { console.error('Usage: node studio/build.mjs studio/cases/<slug>.json [stage ...]'); process.exit(2); }
  const browser = await launch();
  const { results, pack } = await buildCase(resolve(casePath), stages, browser);
  await browser.close();
  let ok = true;
  for (const { doc, render, review: rv } of results) {
    ok &&= render.ok;
    console.log(`${render.ok ? 'OK  ' : 'FAIL'} ${doc.slug.padEnd(34)} L${doc.level} ${doc.audience.padEnd(8)} ${doc.type === 'email' ? `${doc.words} words` : `${String(render.pages).padStart(2)} pp`}${doc.draft ? `  [${doc.draft}]` : ''}${doc.hold ? `  [${doc.hold}]` : ''}${render.over.length ? `  overflow ${JSON.stringify(render.over)}` : ''}${rv ? (rv.ok ? '  [reviewer: passed]' : `  [reviewer: ${rv.failed.join('; ')}]`) : ''}`);
  }
  if (pack) console.log(`PACK ${pack.slug} ${pack.pages} pp`);
  process.exit(ok ? 0 : 1);
}
