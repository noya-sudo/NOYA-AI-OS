// The branded email: refused for a cold first touch, navy and off-white only, no images, a plain-text twin, nothing broken.
// Usage: node studio/tests/branded-email.mjs        (exit 1 on any failure)
import { brandedEmail, BRANDED_STAGES } from '../email/branded.mjs';

let fail = 0;
const check = (ok, what) => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}`); if (!ok) fail++; };
const body = 'Hi Ana,\n\nThank you for the call today. Two dates in March would suit Giza best.\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nnoyaconcierge.com';

for (const stage of ['COLD', 'FIRST_TOUCH', undefined]) {
  let threw = false; try { brandedEmail({ stage, body }); } catch { threw = true; }
  check(threw, `refused for ${stage ?? 'no stage'}`);
}
for (const stage of Object.keys(BRANDED_STAGES)) {
  const { html, text } = brandedEmail({ stage, body });
  check(text === body, `${stage}: plain-text fallback is the body unchanged`);
  check(!/<img\b/i.test(html), `${stage}: no images (Gmail strips linked images)`);
  check(/max-width:600px/.test(html) && /@media \(max-width:620px\)/.test(html), `${stage}: one 600 px column, narrower on a phone`);
  const colours = new Set((html.match(/#[0-9A-Fa-f]{6}\b/g) || []).map((c) => c.toUpperCase()));
  check([...colours].every((c) => c === '#061422' || c === '#F7F7F7'), `${stage}: navy and off-white only (${[...colours].join(', ')})`);
  check(!/\bundefined\b|\bnull\b|\[object Object\]|\bNaN\b/.test(html), `${stage}: nothing broken in the page`);
  check(html.includes('Two dates in March would suit Giza best.') && html.includes('NOYA</div>'), `${stage}: body and wordmark present`);
}
const { html } = brandedEmail({ stage: 'REPLIED', body: 'Hi <b>x</b> & co,\n\nSee https://noyaconcierge.com/egypt.' });
check(html.includes('&lt;b&gt;x&lt;/b&gt; &amp; co') && html.includes('href="https://noyaconcierge.com/egypt"'), 'text is escaped and links stay links');
console.log(fail ? `\n${fail} FAILED` : '\nBRANDED EMAIL PASSED');
process.exit(fail ? 1 : 0);
