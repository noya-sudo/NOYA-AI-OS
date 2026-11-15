-- APPLIED 15 Nov 2026 through the Supabase connector (migration name utm_term_attribution), on Adam's instruction
-- (pre-deploy commercial close). Prepared 14 Nov 2026 in the website's final commercial pass.
-- n8n 10d updated the same day: utm_term added to "Insert Website Enquiry Row" and "Create Marketing Attribution Row",
-- published as version 8512b736-7de8-483a-8b64-bf9b2ecdf909. Verified with test enquiry NOYA-S2PF37
-- ("NOYA WEBSITE PRODUCTION TEST — DO NOT ACTION"): utm_term = 'private concierge egypt' in both tables; the test
-- records were closed (task COMPLETED, opportunity ARCHIVED, contact DO_NOT_CONTACT).
-- Safe to re-run (IF NOT EXISTS). Adds columns only; drops and rewrites nothing.
--
-- Why: the website sends utm_term with every enquiry, and the live 10d intake (n8n eLucjNPgTRKS5nBC, read 14 Nov 2026)
-- reads it, but neither website_enquiries nor marketing_attribution has a column for it, so the search keyword from a
-- Google Ads click survives only as text inside the opportunity description and interaction summary ("UTM: ... term=...").
-- utm_source, utm_medium, utm_campaign, utm_content, landing_page (which carries the gclid), referrer and
-- website_session_id already have their own columns.
--
-- The n8n change (made 15 Nov 2026, see above):
--   10d -> "Insert Website Enquiry Row": add field utm_term = {{ $json.utmTerm }}
--   10d -> "Create Marketing Attribution Row": add field utm_term = {{ $('Resolve CRM Matches').first().json.utmTerm }}
-- Then send one test enquiry named "NOYA WEBSITE PRODUCTION TEST — DO NOT ACTION" with ?utm_term=test and close it
-- afterwards (task COMPLETED, opportunity ARCHIVED, contact DO_NOT_CONTACT).

alter table public.website_enquiries add column if not exists utm_term text;
alter table public.marketing_attribution add column if not exists utm_term text;

comment on column public.website_enquiries.utm_term is 'Campaign keyword from the visit''s most recent tagged link (website attribution, utm_term).';
comment on column public.marketing_attribution.utm_term is 'Campaign keyword from the visit''s most recent tagged link (website attribution, utm_term).';
