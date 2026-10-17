// NOYA Studio acceptance: builds every live case and template preview through the masters, renders each document, and
// checks the rules a client document must meet before Adam sees it. Nothing is sent anywhere.
// Usage: node studio/tests/acceptance.mjs        (exit 1 on any failure)
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildCase } from '../build.mjs';
import { vertical, VERTICALS } from '../masters/verticals.mjs';
import { STAGES } from '../masters/stages.mjs';
import { PERMITS, INDICATIVE, CONTACT } from '../masters/library.mjs';
import { OUT, launch } from '../render.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const STUDIO = join(HERE, '..');
const CASES = [
  ...readdirSync(join(STUDIO, 'cases')).filter((f) => f.endsWith('.json')).map((f) => join(STUDIO, 'cases', f)),
  ...readdirSync(join(STUDIO, 'examples', 'cases')).filter((f) => f.endsWith('.json')).map((f) => join(STUDIO, 'examples', 'cases', f)),
];
const CLIENT_CLASSES = ['VERIFIED', 'PUBLIC', 'NOYA MATERIAL'];
const INTERNAL_FLAG = 'Internal · not for client';
const DRAFT_FLAG = 'Draft · fees not approved · not for client';

// Claims Studio must never make about NOYA: past work, client lists, guarantees.
const FORBIDDEN = [
  /\bwe (have )?(delivered|produced|hosted|organi[sz]ed|executed|planned) (for|with)\b/i,
  /\bour (past|previous|recent) (clients|projects|work|events|weddings)\b/i,
  /\bcase stud/i, /\btrusted by\b/i, /\bas seen in\b/i, /\bguarantee/i, /\bportfolio\b/i,
  /\bworld[- ]class\b/i, /\bunforgettable\b/i, /\bonce[- ]in[- ]a[- ]lifetime\b/i, /\bbreathtaking\b/i,
];
const BROKEN = [/\bundefined\b/, /\bnull\b/, /\[object Object\]/, /\{party\}/, /\bNaN\b/];

const failures = [];
const check = (ok, where, msg) => { if (!ok) failures.push(`${where}: ${msg}`); };

const text = (html) => html.replace(/<style[\s\S]*?<\/style>/g, ' ').replace(/<[^>]+>/g, ' ')
  .replace(/&amp;/g, '&').replace(/&nbsp;/g, ' ').replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/\s+/g, ' ');
const pagesOf = (html) => html.split(/<section class="page/).slice(1);
const blocksOf = (doc) => doc.pages.flatMap((p) => p.blocks);

const allPeople = new Map();
for (const f of CASES) for (const p of JSON.parse(readFileSync(f, 'utf8')).people || []) allPeople.set(p.name, f);

// 1. Guard rails in the builders: each must refuse rather than invent.
const throws = (fn, re) => { try { fn(); return false; } catch (e) { return re.test(e.message); } };
const base = JSON.parse(readFileSync(join(STUDIO, 'cases', 'nados-forever-is-now.json'), 'utf8'));
const brandV = vertical('brand');
check(throws(() => STAGES.concept({ ...base, concept: { title: 'x' } }, brandV), /never invents/), 'guard', 'a concept without its own idea must stop');
check(throws(() => STAGES.concept({ ...base, concept: { ...base.concept, why: [{ label: 'x', fact: 'nope' }] } }, brandV), /missing fact/), 'guard', 'a why-row citing a missing fact must stop');
check(throws(() => STAGES.concept({ ...base, facts: [...base.facts, { id: 'guess', text: 'x', class: 'INFERRED' }], concept: { ...base.concept, why: [{ label: 'x', fact: 'guess' }] } }, brandV), /only VERIFIED/), 'guard', 'an INFERRED fact must not print in a client document');
check(throws(() => STAGES.proposal({ ...base, proposal: { understanding: 'x', scope: [['a', 'b']], fees: [['Fee', '£1']] } }, brandV), /fees_approved_by/), 'guard', 'a fee without Adam\'s approval must stop');
check(throws(() => STAGES.brief({ ...base, brief: { title: 'x', lead: 'y', known: { 'Not a field': 'z' } } }, brandV), /does not ask/), 'guard', 'a brief must not carry fields the master does not ask');
for (const k of Object.keys(VERTICALS)) {
  const v = vertical(k);
  check(v.deskInfo.every((d) => d?.name && d.proposal), `master ${k}`, 'every desk resolves to a CRM product desk');
  check(v.briefFields?.length && v.feeRows?.length && v.workstreams?.length && v.leads?.length && v.delivers?.length, `master ${k}`, 'master is complete (brief fields, fee rows, workstreams, roles)');
}

// 2. Nothing in Studio can send: no network or mail calls anywhere in its code.
for (const f of ['build.mjs', 'render.mjs', 'templates.mjs', 'masters/library.mjs', 'masters/stages.mjs', 'masters/verticals.mjs']) {
  const src = readFileSync(join(STUDIO, f), 'utf8');
  check(!/\bfetch\(|https?\.request|nodemailer|resend|gmail|smtp|sendMail|XMLHttpRequest/i.test(src), f, 'Studio code must not send or call out');
}

// 3. Every case, every stage, rendered.
const browser = await launch();
const rows = [];
for (const f of CASES) {
  let res;
  try { res = await buildCase(f, null, browser, { write: true, shots: false }); }
  catch (e) { failures.push(`${f}: build failed: ${e.message}`); continue; }
  const { c, results, pack } = res;
  const preview = c.slug.startsWith('preview-');
  const own = new Set((c.people || []).map((p) => p.name));
  for (const { doc, render } of results) {
    const w = doc.slug;
    const html = readFileSync(join(OUT, `${w}.html`), 'utf8');
    const pages = pagesOf(html);
    const body = text(html);
    const client = doc.audience === 'client';
    const types = blocksOf(doc).map((b) => b.t);

    check(render.ok, w, `render: overflow ${JSON.stringify(render.over)} fonts ${JSON.stringify(render.fonts)}`);
    for (const re of BROKEN) check(!re.test(body), w, `broken value ${re}`);
    for (const [name, from] of allPeople) if (!own.has(name)) check(!body.includes(name), w, `names ${name} from another case (${from.split('/').pop()})`);

    if (client) {
      check(!types.includes('facts'), w, 'client document carries a provenance facts block');
      check(!/\b(INFERRED|UNVERIFIED|NOYA MATERIAL)\b/.test(body), w, 'client document shows provenance labels');
      for (const re of FORBIDDEN) check(!re.test(body), w, `forbidden claim ${re}`);
      if (!doc.draft) check(!body.includes('To confirm') && !body.includes('Not recorded'), w, 'a client document without a draft flag shows unconfirmed values');
      check(body.includes(CONTACT.lines[0]), w, 'closing contact missing');
      if (['concept', 'brief', 'itinerary'].includes(doc.stage)) check(body.includes(PERMITS) || body.includes(INDICATIVE), w, 'permits / indicative note missing');
      check(preview ? doc.prepared_for === 'Template preview · no client' : [c.company, c.party, ...own].some((n) => n && doc.prepared_for.includes(n)), w, `prepared for "${doc.prepared_for}" is not a known party`);
      for (const r of blocksOf(doc).filter((b) => b.t === 'ledger')) for (const [label] of r.rows) {
        const src = [c.concept?.why, c.desk?.why].flat().filter(Boolean).find((x) => x.label === label);
        if (src) check(CLIENT_CLASSES.includes((c.facts || []).find((x) => x.id === src.fact)?.class), w, `why-row "${label}" does not resolve to a client-class fact`);
      }
    } else {
      check(pages.every((p) => p.includes(INTERNAL_FLAG)), w, 'internal flag missing on a page');
      check(body.includes('NOYA internal'), w, 'internal cover label missing');
    }
    if (doc.stage === 'proposal') {
      const fees = blocksOf(doc).find((b) => b.t === 'fees').rows;
      const open = fees.some(([, v]) => v == null);
      check(open ? doc.draft === DRAFT_FLAG : !!c.proposal.fees_approved_by, w, 'fees and draft flag disagree');
      if (open) check(pages.every((p) => p.includes(DRAFT_FLAG)), w, 'draft flag missing on a page');
    }
    rows.push(`${render.ok ? 'OK  ' : 'FAIL'} ${w.padEnd(34)} ${doc.audience.padEnd(8)} ${String(render.pages).padStart(2)} pp${doc.draft ? '  [draft]' : ''}`);
  }
  if (pack) { check(pack.ok, pack.slug, 'internal pack render'); rows.push(`PACK ${pack.slug.padEnd(34)} internal ${String(pack.pages).padStart(2)} pp`); }
}
await browser.close();

console.log(rows.join('\n'));
if (failures.length) { console.log(`\n${failures.length} failure(s):\n${failures.map((x) => `  - ${x}`).join('\n')}`); process.exit(1); }
console.log(`\nAcceptance passed: ${rows.length} outputs from ${CASES.length} cases.`);
