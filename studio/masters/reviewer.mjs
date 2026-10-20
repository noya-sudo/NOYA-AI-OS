// Brand & Quality Reviewer: the last gate before a client document can read READY FOR ADAM. It reads the rendered document the
// way a client would, and records each check on the document (studio/out/<slug>.review.json, then studio_documents.qa.reviewer).
// A client document is READY TO SEND only when every check passes; otherwise HQ shows it as NEEDS UPDATE with the failed checks.
import { CONTACT } from './library.mjs';
import { allowedLevel } from './stages.mjs';

export const REVIEWER = 'Brand & Quality Reviewer';
const CLIENT_CLASSES = ['VERIFIED', 'PUBLIC', 'NOYA MATERIAL'];

// Visible text of a rendered page (HTML) or an email (text).
export const textSegments = (html) => html.replace(/<style[\s\S]*?<\/style>/g, ' ').split(/<[^>]+>/).map((t) => t.replace(/&[a-z#0-9]+;/g, ' ').trim()).filter(Boolean);
export const visibleText = (html) => html.replace(/<style[\s\S]*?<\/style>/g, ' ').replace(/url\(data:[^)]+\)/g, ' ').replace(/<[^>]+>/g, ' ')
  .replace(/&amp;/g, '&').replace(/&nbsp;/g, ' ').replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/\s+/g, ' ');

const INTERNAL = /\b(internal|not for client|INFERRED|UNVERIFIED|NOYA MATERIAL|to confirm|not recorded|TODO|TBC|lorem)\b|\?\?|\{party\}|\bundefined\b|\[object Object\]|\bNaN\b/i;
// Claims NOYA cannot make without evidence: past work, client lists, guarantees, savings, exclusivity or access.
const CLAIMS = [
  [/\bwe (have )?(delivered|produced|hosted|organi[sz]ed|executed|planned) (for|with)\b/i, 'claims past NOYA work'],
  [/\bour (past|previous|recent) (clients|projects|work|events|weddings)\b|\bcase stud|\btrusted by\b|\bas seen in\b|\bportfolio\b/i, 'claims a client list or past work'],
  [/\bguarantee/i, 'promises a guarantee'],
  [/\bsav(e|es|ing|ings)\b|\bcheaper\b|\bcost[- ]saving|\b\d+\s?%/i, 'quotes savings or percentages without evidence'],
  [/\bexclusive(ly)?\b|\bexclusivity\b|\bprivate access\b|\bafter[- ]hours\b|\bpermits? (are |is )?(secured|granted|in place|approved)\b|\bonly (we|NOYA) can\b/i, 'implies access, permits or exclusivity that is not confirmed'],
  [/\bchef'?s? (menu|tasting)\b|\bconfirmed menu\b|\bmenu:\s/i, 'presents a menu as confirmed'],
  [/\battach|\benclos|\bplease find\b/i, 'refers to an attachment'],
];
const GENERIC = /\b(unforgettable|breathtaking|seamless(ly)?|elevate[sd]?|unparalleled|world[- ]class|nestled|tapestry|delve|bespoke journeys?|curated experiences?|once[- ]in[- ]a[- ]lifetime|luxury redefined|game[- ]chang\w*|synerg\w*|cutting[- ]edge|state[- ]of[- ]the[- ]art|unrivalled|unmatched|dream come true|hidden gem)\b/i;
// House spelling is British.
const US_SPELLING = /\b(organiz\w*|realiz\w*|customiz\w*|personaliz\w*|speciali[z]\w*|center|centers|color|colors|favorite|traveler|traveling|catalog|honor|labor)\b/i;

/**
 * Review one client document.
 * @param doc     the document JSON (studio/documents/<slug>.json)
 * @param c       its case
 * @param opts    { text: visible text, segments: text per element (for repeated words), render: renderer result,
 *                  others: names from other cases (people and companies) }
 */
export function review(doc, c, { text, segments = null, render, others = [] }) {
  const checks = [];
  const add = (check, ok, detail = null) => checks.push({ check, ok: !!ok, detail: ok ? null : detail });
  const isEmail = doc.type === 'email';
  const body = isEmail ? text.split(/\bBest,/)[0] : text;

  // Facts: every why-now row and every fact a client document prints resolves to a verified, public or NOYA source.
  // (The builders already refuse to cite anything else; this catches an inferred or unverified fact copied into the text.)
  const leaked = (c.facts || []).find((f) => !CLIENT_CLASSES.includes(f.class) && f.text && text.includes(f.text));
  add('Factual accuracy', !leaked, `prints the ${leaked?.class} fact "${leaked?.id}"`);
  // Client and stage.
  const names = [c.company, c.party].filter(Boolean);
  add('Correct client', names.some((n) => (doc.prepared_for || '').includes(n) || (doc.title || '').includes(n) || text.includes(n))
    && !others.some((n) => n && text.includes(n)), `names another client or not ${c.party}`);
  add('Correct relationship stage', !doc.hold && doc.level <= allowedLevel(c), `Level ${doc.level} is above what ${c.company} has earned, or the document is held`);
  // Content.
  const internal = body.match(INTERNAL);
  add('No internal notes', !internal, `shows "${internal?.[0]}"`);
  const claim = CLAIMS.find(([re]) => re.test(body));
  add('No fabricated claims', !claim, claim?.[1]);
  const generic = body.match(GENERIC);
  add('No generic wording', !generic, `"${generic?.[0]}"`);
  // Repeated words are checked within each line of text, so a label beside its value ("Security · Security plan") is not one.
  const us = body.match(US_SPELLING);
  const dbl = (segments || [body]).map((t) => t.match(/\b(\w+)\s+\1\b/i)).find((x) => x && !/^(\d+|that|had)$/i.test(x[1]));
  add('Spelling', !us && !dbl, us ? `US spelling "${us[0]}"` : `repeated word "${dbl?.[0]}"`);
  // Imagery and brand.
  const imgs = render?.images || [];
  add('Correct imagery', imgs.every((i) => !i.low_res || (i.h != null && i.h <= 45)) && (doc.type !== 'master' || imgs.length >= 3),
    doc.type === 'master' && imgs.length < 3 ? 'a master brief carries at least three library photos' : 'a low-resolution photo is used in a large slot');
  add('NOYA branding', isEmail ? text.includes(CONTACT.name) : (render?.fonts || []).every((f) => f.ok) && /NOYA/.test(text), 'brand fonts or the NOYA mark missing');
  // Layout.
  const pages = render?.pages ?? 0;
  const pageRule = doc.type === 'master' ? pages >= 2 && pages <= 3 : doc.type === 'onepage' ? pages === 1 : true;
  add('Layout and pagination', isEmail || ((render?.over || []).length === 0 && pageRule), `overflow ${JSON.stringify(render?.over || [])} or ${pages} pages`);
  // A PDF Adam attaches must travel by email: at most 8 MB.
  add('File size', isEmail || (render?.bytes ?? 0) <= 8 * 1024 * 1024, `the PDF is ${((render?.bytes ?? 0) / 1048576).toFixed(1)} MB; email needs 8 MB or less`);
  // Contact.
  add('Contact details', isEmail ? text.includes(CONTACT.lines[2]) : CONTACT.lines.every((l) => text.includes(l)) && text.includes(CONTACT.name), 'contact block incomplete');
  // Use: a document Adam can send moves the relationship: it names the client and asks for one next step.
  const mentions = (text.match(new RegExp(`\\b${c.party.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'g')) || []).length;
  // An itinerary is a programme, not a sales document: it only has to be the client's.
  const useful = doc.type === 'itinerary' ? mentions >= 1 : mentions >= (isEmail ? 0 : 3) && /next step|share|call|reply|let me know|would .* work|\?/i.test(text);
  add('Commercially useful', useful, 'does not name the client enough or ask for a next step');
  return { reviewer: REVIEWER, ok: checks.every((x) => x.ok), checks, failed: checks.filter((x) => !x.ok).map((x) => `${x.check}: ${x.detail}`) };
}
