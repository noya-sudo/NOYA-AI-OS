// Workflow 05 node "Prior Relationship Guard" (inserted 30 Sep 2026 between the eligibility gate /
// entity-recovery paths and "Eligible For Outreach?"; published version a27436f7).
// Hard rule (30 Sep 2026): NOYA never sends a cold introduction to someone it has already emailed or
// heard from, however long ago. Evidence: CRM interactions for the company/person (including the
// historical Gmail import) or opportunities.prior_relationship. Such opportunities are routed to
// PRIOR_RELATIONSHIP (not eligible for cold outreach); HQ handles them as follow-up / reconnect.
const o = $json;
if (o._sales_classification === 'ELIGIBLE' && (o.prior_relationship || o._has_prior_outbound_email || o._has_prior_inbound_reply)) {
  const reasons = (o._ineligibility_reasons || []).concat(['PREVIOUSLY_IN_CONTACT_' + (o.prior_relationship || 'EMAIL_HISTORY') + '_USE_FOLLOW_UP_OR_RECONNECT']);
  return { json: { ...o, _sales_classification: 'PRIOR_RELATIONSHIP', _ineligibility_reasons: reasons } };
}
return { json: o };
