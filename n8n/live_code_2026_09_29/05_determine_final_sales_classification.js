const o = $json;
const c = o._best_contact;
// Only a VERIFIED address becomes an email approval task. HQ blocks anything else at approval,
// so an UNVERIFIED address goes down the contact path, where LinkedIn / Instagram copy is
// surfaced as the ready channel instead.
const hasUsableEmail = !!(c && c.email && c.email_status === 'VERIFIED' && !c.do_not_contact);
const classification = hasUsableEmail ? 'READY_FOR_APPROVAL' : 'CONTACT_RESOLUTION_REQUIRED';
const missing = [];
if (!c || (!c.first_name && !c.last_name)) missing.push('No named decision-maker found, including after automated search this run');
if (!hasUsableEmail) missing.push('No usable email address' + (c && (c.first_name || c.last_name) ? ' for ' + ((c.first_name || '') + ' ' + (c.last_name || '')).trim() : ''));
return { json: { ...o, _sales_classification: classification, _missing_contact_data: missing.join('; ') || 'None -- contact usable.' } };