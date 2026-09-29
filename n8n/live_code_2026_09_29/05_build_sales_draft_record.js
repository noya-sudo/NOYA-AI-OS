const o = $json;
const ai = o.output || {};
const c = o._best_contact || {};
const co = o._company || {};

// OUTREACH READY STATE (29 Sep 2026). Everything below is deterministic: the model writes
// the copy, code decides the channel, cleans the formatting and runs the quality gate.
// One account gets ONE primary channel; the others are recorded as fallback only.

// 1. Typography + spacing: no hard wraps, no runs of blank lines, plain hyphens/quotes.
function clean(t) {
  return String(t || '')
    .replace(/\r/g, '')
    .replace(/[‐‑‒]/g, '-')
    .replace(/ /g, ' ')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
function oneLine(t) { return clean(t).replace(/\s*\n+\s*/g, ' '); }
let emailBody = clean(ai.email_body);
// Sign-off exactly once, three lines, no blank line inside it.
emailBody = emailBody.replace(/\n*(Best|Kind regards|Best regards|Regards),?\s*\n+\s*Adam Elshazly[\s\S]*$/i, '').trim();
// Salutation: never a role or a team ("Hi Founder / Creative Director,", "Hi the team...",
// "Hi Partnerships,"). Use the known person's first name, otherwise a plain "Hello,".
const ROLE_WORDS = /\/|\bthe\b|\bteam\b|\bfounders?\b|\bdirector\b|\bpartnerships?\b|\bhead\b|\bmanager\b|\bofficer\b|\blead\b|\bmarketing\b|\bmembership\b|\bmembers\b|\bevents?\b|\bsales\b|\bpress\b|\bconcierge\b|\bdepartment\b|\bsponsorship\b|\bcommercial\b|\bsir\b|\bmadam\b/i;
function personFirst(v) {
  const f = String(v || '').trim().split(/\s+/)[0] || '';
  return (f && !ROLE_WORDS.test(f) && /^[A-Za-z\u00C0-\u024F'\-]{2,}$/.test(f)) ? f : '';
}
const knownFirst = personFirst(c.first_name) || personFirst(o.contact_first_name) || personFirst(ai.decision_maker_name);
emailBody = emailBody.replace(/^(Hi|Hello|Dear)\s+[^\n,]*,/, function (g) {
  return ROLE_WORDS.test(g) ? (knownFirst ? 'Hi ' + knownFirst + ',' : 'Hello,') : g;
});
if (emailBody) emailBody += '\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nnoyaconcierge.com';
const linkedinMsg = oneLine(ai.linkedin_message || ai.linkedin_instagram_message);
const instagramDm = oneLine(ai.instagram_dm);

// 2. Channel routing (deterministic, one primary channel).
const emailStatus = String(c.email_status || o._contact_confidence || 'NOT_FOUND').toUpperCase();
const email = String(c.email || '');
const local = email.split('@')[0].toLowerCase();
// Same rule as SQL email_kind(): a company inbox is never treated as a person's address.
const inbox = !!email && (/^(info|hello|hi|contact|contactus|enquiries|enquiry|inquiries|inquiry|partnerships?|partners|events?|press|pr|media|newbusiness|new\.business|business|sales|bookings?|reservations?|office|team|admin|marketing|concierge|membership|members|support|help|general|reception|careers|jobs|hr|studio|mail|weddings?|sponsorship)$/.test(local)
  || /(enquir|inquir|sponsor|partnership|membership|reservation|booking|concierge)/.test(local));
const personLinkedin = [c.linkedin, o.contact_linkedin_url].filter(function (u) { return /linkedin\.com\/in\//i.test(String(u || '')); })[0] || '';
const instagram = [c.instagram, o.instagram_url, co.instagram].filter(Boolean)[0] || '';
const hasName = !!(personFirst(c.first_name) || personFirst(ai.decision_maker_name));
// Instagram is a primary channel only for Instagram-native accounts (weddings, clubs, hotels,
// creative/brand, destination partners) -- never for banks, wealth, law or consulting firms.
const formalSector = /(BANK|WEALTH|LAW|LEGAL|CONSULT|INVEST|FAMILY_OFFICE|FAMILY OFFICE|FINANCIAL|INSURANCE|ASSET MANAGEMENT|ASSET_MANAGEMENT|PRIVATE EQUITY|PRIVATE_EQUITY)/i
  .test(String(o.company_type || co.company_type || '') + ' ' + String(o.opportunity_type || ''));
let primary = 'CONTACT_RESOLUTION';
if (emailStatus === 'VERIFIED' && email && !inbox) primary = 'EMAIL';
else if (hasName && personLinkedin) primary = 'LINKEDIN';
else if (instagram && !formalSector) primary = 'INSTAGRAM';
else if (emailStatus === 'VERIFIED' && email && inbox) primary = 'EMAIL_COMPANY_INBOX';
const fallbacks = ['EMAIL', 'LINKEDIN', 'INSTAGRAM'].filter(function (ch) {
  if (ch === primary) return false;
  if (ch === 'EMAIL') return emailStatus === 'VERIFIED' && !!email;
  if (ch === 'LINKEDIN') return !!personLinkedin;
  return !!instagram;
});

// 3. Email style: plain personal Gmail by default; branded only for a warm relationship.
const warm = /client|partner|active|warm/i.test(String(co.relationship_status || '')) || !!o._account_already_in_active_conversation;
const emailStyle = warm ? 'MINIMAL_BRANDED' : 'PLAIN_PERSONAL';

// 4. Quality gate (deterministic). A failed gate never blocks the draft: it is flagged so
// Adam sees exactly what to fix, and 05 never sends anything.
const BANNED = ["i hope you're well", 'i hope you are well', 'i hope this email finds you well', 'i wanted to introduce noya',
  'explore synergies', 'synergies', 'unparalleled', 'world-class', 'world class', 'elevate', 'seamless luxury',
  'bespoke excellence', 'bespoke solutions', 'luxury redefined', 'curated to perfection', 'we are delighted', 'free call', 'free 15'];
const bodyNoSig = emailBody.replace(/\n\nBest,[\s\S]*$/, '');
const words = bodyNoSig ? bodyNoSig.split(/\s+/).filter(Boolean).length : 0;
const gate = [];
if (emailBody) {
  if (words < 55) gate.push('EMAIL_TOO_SHORT(' + words + 'w)');
  if (words > 150) gate.push('EMAIL_TOO_LONG(' + words + 'w)');
  if (!/\?/.test(bodyNoSig)) gate.push('NO_CLEAR_CTA');
  if (!/^(Hi|Hello)\b/.test(bodyNoSig)) gate.push('OPENING_NOT_HI');
}
const allCopy = (emailBody + ' ' + (ai.email_subject || '') + ' ' + linkedinMsg + ' ' + instagramDm).toLowerCase();
BANNED.forEach(function (b) { if (allCopy.indexOf(b) !== -1) gate.push('BANNED_PHRASE:' + b); });
if (/based in egypt/i.test(allCopy)) gate.push('POSITIONING_BASED_IN_EGYPT');
if (linkedinMsg && (linkedinMsg.length < 150 || linkedinMsg.length > 600)) gate.push('LINKEDIN_LENGTH(' + linkedinMsg.length + ')');
if (instagramDm && instagramDm.length > 450) gate.push('INSTAGRAM_LENGTH(' + instagramDm.length + ')');
if (!ai.why_now) gate.push('NO_WHY_NOW');
if (primary === 'LINKEDIN' && !linkedinMsg) gate.push('PRIMARY_LINKEDIN_WITHOUT_MESSAGE');
if (primary === 'INSTAGRAM' && !instagramDm) gate.push('PRIMARY_INSTAGRAM_WITHOUT_DM');
const gateStatus = gate.length ? 'NEEDS_EDIT' : 'PASS';

const followUpPlan = primary === 'CONTACT_RESOLUTION'
  ? 'Resolve a named contact and channel first; no sequence starts until then.'
  : 'One sequence on ' + primary + ' only: initial approach, one useful follow-up around ' + String(o._follow_up_1_date || '').slice(0, 10)
    + ', optional final follow-up around ' + String(o._final_follow_up_date || '').slice(0, 10) + ', then LONG_TERM. Other channels are fallback only.';

const evidence = oneLine(ai.signal || o.reason || o.description || '').slice(0, 400);
const ready = {
  primary_channel: primary,
  fallback_channels: fallbacks,
  contact_name: (((c.first_name || '') + ' ' + (c.last_name || '')).trim() || (personFirst(ai.decision_maker_name) ? ai.decision_maker_name : '')) || null,
  contact_role: ai.decision_maker_role || c.position || null,
  email: email || null,
  email_status: emailStatus,
  email_kind: email ? (inbox ? 'OFFICIAL_COMPANY_INBOX' : 'DIRECT_PERSON_EMAIL') : null,
  linkedin: personLinkedin || null,
  instagram: instagram || null,
  email_style: emailStyle,
  email_subject: oneLine(ai.email_subject) || null,
  email_body: emailBody || null,
  linkedin_message: linkedinMsg || null,
  instagram_dm: instagramDm || null,
  personalisation_evidence: evidence || null,
  why_now: oneLine(ai.why_now) || null,
  follow_up_plan: followUpPlan,
  quality_gate: gateStatus,
  quality_issues: gate
};

const draftText = [
'=== NOYA SALES DRAFT (CEO APPROVAL REQUIRED: ' + (o._human_takeover ? 'NO -- ADAM PERSONAL TAKEOVER' : 'YES') + ') ===',
'Company: ' + (o.company_name || co.name || ''),
'Originating department: ' + (o._origin_department_label || o._origin_department || 'UNKNOWN'),
'Upstream priority: ' + (o.priority != null ? o.priority : ''),
'Commercial priority: ' + (o._commercial_priority != null ? o._commercial_priority : ''),
'Pipeline value: MODEL_ESTIMATE ' + (o.currency || 'USD') + ' ' + (o.estimated_value || 0),
'PRIMARY CHANNEL: ' + primary + (fallbacks.length ? ' (fallback only: ' + fallbacks.join(', ') + ')' : ''),
'QUALITY GATE: ' + gateStatus + (gate.length ? ' -- ' + gate.join('; ') : ''),
'Email style: ' + emailStyle,
'Primary angle: ' + (ai.primary_commercial_angle || ''),
'Secondary angle: ' + (ai.secondary_commercial_angle || 'none'),
'Signal: ' + (ai.signal || o.description || ''),
'Why now: ' + (ai.why_now || ''),
'Why NOYA: ' + (ai.why_noya || ''),
'Decision maker: ' + (ready.contact_name || 'not identified') + ' -- ' + (ready.contact_role || ''),
'Contact email: ' + (email || 'none on file') + ' (' + emailStatus + ')',
'LinkedIn: ' + (personLinkedin || 'none on file') + ' | Instagram: ' + (instagram || 'none on file'),
'Outreach mode: ' + (o._outreach_mode || 'CEO_APPROVAL_REQUIRED') + ((o._human_takeover_reasons && o._human_takeover_reasons.length) ? (' (' + o._human_takeover_reasons.join(', ') + ')') : ''),
...(o._human_takeover ? ['Why Adam should personally handle this: ' + (o._human_only_reason || ai.human_takeover_reason || '')] : []),
'',
'--- EMAIL ---',
'Subject: ' + (ready.email_subject || ''),
emailBody,
'',
'--- FOLLOW-UP 1 (target ' + (o._follow_up_1_date || '') + ') ---',
clean(ai.follow_up_1),
'',
'--- FOLLOW-UP 2 (target ' + (o._follow_up_2_date || '') + ') ---',
clean(ai.follow_up_2),
'',
'--- OPTIONAL FINAL FOLLOW-UP (target ' + (o._final_follow_up_date || '') + ') ---',
clean(ai.optional_final_follow_up) || 'Not recommended.',
'',
'--- LINKEDIN MESSAGE ---',
linkedinMsg || 'Not applicable.',
'',
'--- INSTAGRAM DM ---',
instagramDm || 'Not applicable.',
'',
'--- FOLLOW-UP PLAN ---',
followUpPlan,
'',
'Secondary angles at this company this run: ' + JSON.stringify(o._secondary_angles_same_company || []),
'AI confidence: ' + (ai.confidence || 0) + '/100 | Contact confidence: ' + (o._contact_confidence || 'NOT_FOUND') + ' | Signal freshness: ' + (o._freshness_note || ''),
'',
'=== INTERNAL SALES INTELLIGENCE (NEVER SEND TO PROSPECT) ===',
'Primary angle code: ' + (ai.primary_angle_code || ''),
'Secondary angle code: ' + (ai.secondary_angle_code || 'none'),
'Commercial reason: ' + (ai.commercial_reason || ''),
'Recurring revenue potential: ' + (ai.recurring_revenue_potential || o._recurring_revenue_potential || ''),
'Best long-term commercial model: ' + (ai.best_long_term_commercial_model || 'not yet clear'),
'Initial deal (land): ' + (ai.initial_deal || ''),
'Expansion path: ' + (ai.expansion_path || ''),
'Membership potential: ' + (ai.membership_potential || 'NONE'),
'Corporate retainer potential: ' + (ai.corporate_retainer_potential || 'NONE'),
'White-label potential: ' + (ai.white_label_potential || 'NONE'),
'',
'OUTREACH_READY_JSON: ' + JSON.stringify(ready)
].join('\n');
return { json: { ...o, _draft_text: draftText, _outreach_ready: ready } };
