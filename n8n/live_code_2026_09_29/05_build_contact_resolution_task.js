const o = $json;
const c = o._best_contact;
const missing = [];
if (!c || (!c.first_name && !c.last_name)) { missing.push('No named decision-maker found, including after automated search'); }
if (!c || !c.email) { missing.push('No email address found'); }
if (c && c.email && (c.email_status === 'INVALID' || c.email_status === 'NOT_FOUND')) { missing.push('Email found is ' + c.email_status); }
const searchNote = o._contact_search_attempted
  ? ('Automated search already attempted this run (' + (o._contact_resolution_method || 'unknown method') + ') -- ' + (c && (c.first_name || c.last_name) ? ('found ' + ((c.first_name||'')+' '+(c.last_name||'')).trim() + ' but no usable email yet.') : 'no candidate found.'))
  : 'Automated search was not run for this opportunity.';
const r = o._outreach_ready || {};
const manual = (r.primary_channel === 'LINKEDIN' && r.linkedin_message) ? 'LINKEDIN'
  : (r.primary_channel === 'INSTAGRAM' && r.instagram_dm) ? 'INSTAGRAM' : '';
// A LinkedIn / Instagram account is ready to act on now: the message goes first so it is
// visible in HQ. Adam sends it by hand from his own account; nothing is sent automatically.
const readyBlock = manual ? [
  (manual === 'LINKEDIN' ? 'LINKEDIN MESSAGE READY' : 'INSTAGRAM DM READY') + ' -- ADAM SENDS MANUALLY (never automated)',
  'Company: ' + (o.company_name || ''),
  'To: ' + (r.contact_name || (manual === 'INSTAGRAM' ? 'account owner' : '')) + (r.contact_role ? ' -- ' + r.contact_role : ''),
  'Profile: ' + (manual === 'LINKEDIN' ? r.linkedin : r.instagram),
  'Why now: ' + (r.why_now || ''),
  'Quality gate: ' + (r.quality_gate || '') + ((r.quality_issues && r.quality_issues.length) ? ' -- ' + r.quality_issues.join('; ') : ''),
  '',
  '--- MESSAGE ---',
  (manual === 'LINKEDIN' ? r.linkedin_message : r.instagram_dm),
  '',
  'After sending: mark this task done and note the send date (follow-up due about 4 days later). One channel only: no email or other channel in parallel.',
  'Email route: ' + (c && c.email ? (c.email + ' (' + (c.email_status || 'UNKNOWN') + ') -- not usable until VERIFIED') : 'none verified yet'),
  ''
] : [];
const desc = readyBlock.concat([
manual ? 'CONTACT DETAIL STILL OPEN (optional)' : 'CONTACT RESEARCH NEEDED',
'Company: ' + (o.company_name || ''),
'Opportunity: ' + (o.opportunity_type || '') + ' -- ' + (o.description || ''),
'Priority: ' + (o.priority || 0) + ' | Estimated value: ' + (o.currency || 'USD') + ' ' + (o.estimated_value || 0),
'Known contact: ' + (c ? ((c.first_name || '') + ' ' + (c.last_name || '') + ' -- ' + (c.position || '(role unknown)')) : 'None identified'),
'Missing: ' + missing.join('; '),
'Ideal decision-maker role to target: ' + (o._ideal_buyer_role || ''),
searchNote,
'Recommended next step: ' + (manual ? 'Send the prepared ' + manual + ' message above. A verified email is only needed if this channel gets no response.' : 'Verify/find a working email for this role at this company, or have Adam supply a known contact directly.'),
'',
'--- FULL COMMERCIAL STRATEGY & DRAFT ALREADY PREPARED ---',
(o._draft_text || 'Draft not yet generated.')
]).join('\n');
return { json: { ...o, _contact_resolution_text: desc, _manual_channel_ready: manual, _ideal_role: o._ideal_buyer_role, _missing_contact_data: (o._missing_contact_data || missing.join('; ')) } };