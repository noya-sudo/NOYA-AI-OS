// NOYA Studio acceptance: builds every live case and template preview through the masters, renders each document, and
// checks the rules a client document must meet before Adam sees it. Nothing is sent anywhere.
// Usage: node studio/tests/acceptance.mjs        (exit 1 on any failure)
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildCase } from '../build.mjs';
import { vertical, VERTICALS } from '../masters/verticals.mjs';
import { STAGES, LEVEL, allowedLevel, gate } from '../masters/stages.mjs';
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
const reviewNeeds = [];
const check = (ok, where, msg) => { if (!ok) failures.push(`${where}: ${msg}`); };

const text = (html) => html.replace(/<style[\s\S]*?<\/style>/g, ' ').replace(/<[^>]+>/g, ' ')
  .replace(/&amp;/g, '&').replace(/&nbsp;/g, ' ').replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/\s+/g, ' ');
const pagesOf = (html) => html.split(/<section class="page/).slice(1);
const blocksOf = (doc) => doc.pages.flatMap((p) => p.blocks || []);

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
// The level gate: a cold prospect gets no full document unless it is held; a decline holds everything; evidence must be verified.
const cold = { ...base, relationship: { state: 'cold' }, strong: undefined, hold: [], build: ['note', 'concept'] };
check(throws(() => gate(cold), /has earned Level 1/), 'gate', 'a full concept for a cold prospect must stop unless held');
check(gate({ ...cold, hold: ['concept'] })[1].hold?.startsWith('Held until'), 'gate', 'a held document is marked held');
check(allowedLevel({ ...cold, strong: { fact: 'launch' } }) === 2, 'gate', 'a strong cold opportunity reaches Level 2');
check(throws(() => allowedLevel({ ...base, relationship: { state: 'warm', fact: 'fin_dates' } }), /must be a VERIFIED fact/), 'gate', 'warm must cite a verified reply');
check(throws(() => gate({ ...base, relationship: { state: 'declined', fact: 'sent' }, hold: [], build: ['email'] }), /has earned Internal/), 'gate', 'a declined prospect gets nothing sendable unless held');
check(throws(() => STAGES.email({ ...base, email: { to_name: 'X', subject: 'S', paragraphs: ['word '.repeat(151)] } }, brandV), /under 150/), 'guard', 'a Level 1 email idea stays under 150 words');
check(throws(() => STAGES.email({ ...base, email: { to_name: 'X', subject: 'S', paragraphs: ['The concept is attached.'] } }, brandV), /must not say a file is attached/), 'guard', 'an email never claims an attachment');
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
  const max = allowedLevel(c);
  for (const { doc, render, review: rv } of results) {
    const w = doc.slug;
    const isEmail = doc.type === 'email';
    const html = readFileSync(join(OUT, `${w}.${isEmail ? 'txt' : 'html'}`), 'utf8');
    const pages = isEmail ? [] : pagesOf(html);
    const body = isEmail ? html.replace(/\s+/g, ' ') : text(html);
    const client = doc.audience === 'client';
    const types = isEmail ? [] : blocksOf(doc).map((b) => b.t);

    check(doc.level === LEVEL[doc.stage], w, 'level recorded on the document');
    check(!!doc.hold === (doc.level > max), w, `hold must be set exactly when the document is above the earned level (L${doc.level} vs L${max})`);
    if (doc.stage === 'onepage') check(render.pages === 1, w, `a one-page concept is ${render.pages} pages`);
    if (isEmail) {
      check(doc.words <= 150 && body.startsWith('Subject: '), w, 'Level 1 email idea: subject and under 150 words');
      check(body.includes(CONTACT.name) && body.includes(CONTACT.lines[2]), w, 'email sign-off missing');
      check(!doc.attach || c.build.includes(doc.attach), w, `email attaches "${doc.attach}", which the case does not build`);
      check(!doc.attach || LEVEL[doc.attach] <= max, w, `email attaches a held document (${doc.attach})`);
      check(!/\battach|\benclos/i.test(body.split('Best,')[0]), w, 'email claims an attachment the connector cannot add');
    }

    check(render.ok, w, `render: overflow ${JSON.stringify(render.over)} fonts ${JSON.stringify(render.fonts)}`);
    for (const re of BROKEN) check(!re.test(body), w, `broken value ${re}`);
    for (const [name, from] of allPeople) if (!own.has(name)) check(!body.includes(name), w, `names ${name} from another case (${from.split('/').pop()})`);

    if (client) {
      check(!types.includes('facts'), w, 'client document carries a provenance facts block');
      check(!/\b(INFERRED|UNVERIFIED|NOYA MATERIAL)\b/.test(body), w, 'client document shows provenance labels');
      for (const re of FORBIDDEN) check(!re.test(body), w, `forbidden claim ${re}`);
      if (!doc.draft) check(!body.includes('To confirm') && !body.includes('Not recorded'), w, 'a client document without a draft flag shows unconfirmed values');
      if (!isEmail) check(body.includes(CONTACT.lines[0]), w, 'closing contact missing');
      if (['onepage', 'concept', 'brief', 'master', 'itinerary'].includes(doc.stage)) check(body.includes(PERMITS) || body.includes(INDICATIVE), w, 'permits / indicative note missing');
      check(preview ? doc.prepared_for === 'Template preview · no client' : [c.company, c.party, ...own].some((n) => n && doc.prepared_for.includes(n)), w, `prepared for "${doc.prepared_for}" is not a known party`);
      for (const r of (isEmail ? [] : blocksOf(doc)).filter((b) => b.t === 'ledger')) for (const [label] of r.rows) {
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
    // The Brand & Quality Reviewer runs on every client document; its verdict decides READY TO SEND or NEEDS UPDATE in HQ.
    if (client && !preview) {
      check(!!rv, w, 'Brand & Quality Reviewer did not run');
      if (doc.stage === 'master') check(rv?.ok, w, `master brief fails the Brand & Quality Reviewer: ${rv?.failed.join('; ')}`);
      if (rv && !rv.ok) reviewNeeds.push(`${w}: ${rv.failed.join('; ')}`);
    }
    rows.push(`${render.ok ? 'OK  ' : 'FAIL'} ${w.padEnd(34)} L${doc.level} ${doc.audience.padEnd(8)} ${isEmail ? `${doc.words} words` : `${String(render.pages).padStart(2)} pp`}${doc.draft ? '  [draft]' : ''}${doc.hold ? '  [held]' : ''}${rv ? (rv.ok ? '  [reviewer: ready]' : '  [reviewer: needs update]') : ''}`);
  }
  if (pack) { check(pack.ok, pack.slug, 'internal pack render'); rows.push(`PACK ${pack.slug.padEnd(34)} internal ${String(pack.pages).padStart(2)} pp`); }
}
await browser.close();

console.log(rows.join('\n'));
if (reviewNeeds.length) console.log(`\nNeeds update (Brand & Quality Reviewer; recorded, not a build failure):\n${reviewNeeds.map((x) => `  - ${x}`).join('\n')}`);
if (failures.length) { console.log(`\n${failures.length} failure(s):\n${failures.map((x) => `  - ${x}`).join('\n')}`); process.exit(1); }
console.log(`\nAcceptance passed: ${rows.length} outputs from ${CASES.length} cases.`);
