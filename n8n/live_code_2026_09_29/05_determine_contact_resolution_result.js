const staticData = $getWorkflowStaticData('global');
const runId = $('Sales Configuration').first().json.run_id;
const run = staticData.salesRuns[runId];

const base = $('Determine Ideal Buyer Role').item.json;
let candidateFirst = base._hunter_first_name || '';
let candidateLast = base._hunter_last_name || '';
let candidatePosition = '';
let candidateLinkedin = '';
let resolutionMethod = (base._best_contact && (base._best_contact.first_name || base._best_contact.last_name)) ? 'EXISTING_CRM_CONTACT' : 'NONE';
try {
  const restored = $('Restore Context After Contact Search').item;
  if (restored && restored.json) {
    candidateFirst = restored.json._candidate_first_name || candidateFirst;
    candidateLast = restored.json._candidate_last_name || candidateLast;
    candidatePosition = restored.json._candidate_position || '';
    candidateLinkedin = restored.json._candidate_linkedin || '';
    if (candidateFirst || candidateLast) resolutionMethod = 'AUTOMATED_SEARCH_THIS_RUN';
  }
} catch (e) {}

let finder = null, verifier = null;
try { finder = $('Hunter Email Finder').item.json; } catch (e) {}
try { verifier = $('Hunter Email Verifier').item.json; } catch (e) {}
const finderEmail = (finder && finder.data && finder.data.email) ? finder.data.email : '';
const verifierStatus = (verifier && verifier.data && verifier.data.status) ? verifier.data.status : '';
let emailStatus = 'NOT_FOUND';
if (finderEmail && verifierStatus === 'valid') emailStatus = 'VERIFIED';
else if (finderEmail) emailStatus = 'UNVERIFIED';

run.automatedContactSearchesRun = (run.automatedContactSearchesRun || 0) + 1;
if (emailStatus === 'VERIFIED' && resolutionMethod === 'AUTOMATED_SEARCH_THIS_RUN') run.contactsNewlyResolved = (run.contactsNewlyResolved || 0) + 1;

const prior = base._best_contact || null;
const samePerson = !!(prior && prior.id && candidateFirst && candidateLast
  && String(prior.first_name || '').trim().toLowerCase() === String(candidateFirst).trim().toLowerCase()
  && String(prior.last_name || '').trim().toLowerCase() === String(candidateLast).trim().toLowerCase());
const resolvedContact = (candidateFirst || candidateLast || finderEmail) ? {
  id: samePerson ? prior.id : undefined,
  first_name: candidateFirst, last_name: candidateLast, position: candidatePosition || (base._best_contact && base._best_contact.position) || '',
  email: finderEmail, email_status: emailStatus === 'VERIFIED' ? 'VERIFIED' : (finderEmail ? 'UNVERIFIED' : 'NOT_FOUND'),
  linkedin: candidateLinkedin, do_not_contact: (base._best_contact && base._best_contact.do_not_contact) || false, status: 'NEW'
} : base._best_contact;

// Structured provider evidence for the CRM (written by 'Record Email Verification - Supabase').
// The database applies it to the canonical contact only if the provider said valid +
// deliverable, the name and company domain match, and no different email is on file.
const vd = (verifier && verifier.data) || {};
const fd = (finder && finder.data) || {};
const emailVerification = finderEmail ? {
  company_id: base.company_id || null,
  opportunity_id: base.id || null,
  contact_id: samePerson ? prior.id : (base.contact_id || null),
  first_name: fd.first_name || candidateFirst || null,
  last_name: fd.last_name || candidateLast || null,
  position: fd.position || candidatePosition || null,
  email: finderEmail,
  provider: 'HUNTER',
  provider_status: vd.status || null,
  provider_result: vd.result || null,
  provider_score: (vd.score != null ? vd.score : null),
  finder_score: (fd.score != null ? fd.score : null),
  accept_all: (vd.accept_all != null ? vd.accept_all : (fd.accept_all != null ? fd.accept_all : null)),
  provider_verification_date: (vd.verification && vd.verification.date) || (fd.verification && fd.verification.date) || null,
  checked_at: new Date().toISOString(),
  source_workflow: '05 - NOYA Sales & Outreach Department v1',
  source_execution: String($execution.id),
  evidence_sources: vd.sources || fd.sources || []
} : null;

return { json: { ...base, _best_contact: resolvedContact, _contact_resolution_method: resolutionMethod, _contact_search_attempted: true, _email_verification: emailVerification } };