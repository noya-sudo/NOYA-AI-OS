// NOYA branded email (29 Oct, commercial wrap-up, section 9). The outreach ladder: a cold first touch is always plain text,
// founder-led, 70–130 words, no brochure. The branded layout is earned: only after a reply, a meeting, a concept or proposal
// delivery, or a formal introduction. Navy and off-white only, the typeset wordmark (Gmail strips linked images, so no logo
// file is needed), one 600 px column that narrows on a phone, and the plain text always sent alongside as the fallback.
// Usage: const { html, text } = brandedEmail({ stage: 'REPLIED', body }) → Gmail draft with htmlBody: html, body: text.
import { CONTACT } from '../masters/library.mjs';

export const BRANDED_STAGES = {
  REPLIED: 'They replied',
  MEETING: 'After a meeting',
  CONCEPT: 'Concept delivery',
  PROPOSAL: 'Proposal delivery',
  INTRODUCTION: 'Formal introduction',
};

const NAVY = '#061422';
const PAPER = '#F7F7F7';
const INK_2 = 'rgba(6,20,34,.74)';
const INK_3 = 'rgba(6,20,34,.5)';
const RULE = 'rgba(6,20,34,.16)';
const ON_NAVY_3 = 'rgba(247,247,247,.46)';
const SANS = "'Helvetica Neue', Helvetica, Arial, sans-serif";

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const link = (s) => s
  .replace(/\bhttps?:\/\/[^\s<]+[^\s<.,;:!?)]/g, (u) => `<a href="${u}" style="color:${NAVY};text-decoration:underline">${u}</a>`)
  .replace(/(^|[\s(])(noyaconcierge\.com)\b(?!\/)/g, `$1<a href="https://noyaconcierge.com" style="color:${NAVY};text-decoration:none">$2</a>`);

export function brandedEmail({ stage, body }) {
  if (!BRANDED_STAGES[stage]) {
    throw new Error(`branded email is for warm stages only (${Object.keys(BRANDED_STAGES).join(', ')}); a cold first touch stays plain text`);
  }
  const text = String(body || '').replace(/\r\n/g, '\n').trim();
  if (!text) throw new Error('branded email needs a body');
  const paras = text.split(/\n\s*\n/).map((p) => link(esc(p.trim())).replace(/\n/g, '<br>'));
  const p = (h, last) => `<p style="margin:0 0 ${last ? 0 : 16}px;font-family:${SANS};font-size:15px;line-height:1.6;color:${NAVY}">${h}</p>`;
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light">
<style>@media (max-width:620px){.noya-pad{padding-left:22px!important;padding-right:22px!important}}</style></head>
<body style="margin:0;padding:0;background:${PAPER}">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${PAPER}"><tr><td align="center" style="padding:24px 10px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;background:${PAPER}">
<tr><td class="noya-pad" style="background:${NAVY};padding:26px 40px">
<div style="font-family:${SANS};font-size:15px;font-weight:400;letter-spacing:.62em;color:${PAPER};line-height:1">NOYA</div>
<div style="font-family:${SANS};font-size:7px;letter-spacing:.74em;color:${ON_NAVY_3};line-height:1;padding-top:7px">CONCIERGE</div>
</td></tr>
<tr><td class="noya-pad" style="padding:34px 40px 30px">
${paras.map((h, i) => p(h, i === paras.length - 1)).join('\n')}
</td></tr>
<tr><td class="noya-pad" style="padding:0 40px 28px"><div style="border-top:1px solid ${RULE};padding-top:14px;font-family:${SANS};font-size:11px;line-height:1.6;letter-spacing:.04em;color:${INK_3}">
<span style="white-space:nowrap">${esc(CONTACT.lines[0])}</span> &nbsp;·&nbsp; <span style="white-space:nowrap">${esc(CONTACT.lines[1])}</span> &nbsp;·&nbsp; <a href="https://noyaconcierge.com" style="color:${INK_2};text-decoration:none;white-space:nowrap">${esc(CONTACT.lines[2])}</a>
</div></td></tr>
</table></td></tr></table>
</body></html>`;
  return { html, text, stage, label: BRANDED_STAGES[stage] };
}
