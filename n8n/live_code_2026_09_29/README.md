# Live n8n code — 29 Sep 2026

Exact copies of the Code-node / expression logic published to production on 29 Sep 2026
(commercial engine completion). n8n is the source of truth; these files are the reviewed
record. `12_outbound_email_executor.workflow.ts` and `13_gmail_interaction_sync.workflow.ts`
in the parent folder predate these changes:

- 12: Gmail draft/send body is now minimal HTML (`12_email_html_body.js`, used as an inline expression).
- 13: `Classify Reply (Claude)` HTTP node replaced by `Classify Reply (AI)` (Gemini 3.1 Flash-Lite,
  GPT-5 mini fallback, n8n gateway); Parse Classification forces confidence < 0.6 to UNKNOWN (human
  review); retries on Triage and Apply Reply To CRM.
