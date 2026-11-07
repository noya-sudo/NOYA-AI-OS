# Integrations

The live list is `gov.integration_registry` (shown in the console under **Connected services**). This file explains each entry.
**Nothing external is connected in Phase 1.** A status can only become `read_only` or `read_write` after a recorded
verification call; the database rejects it otherwise.

| Code | Service | Status (7 Nov 2026) | Phase | Credential (name only) | Notes |
|---|---|---|---|---|---|
| `supabase` | Supabase "NOYA Marketing OS" | **internal; project not yet created** | 1 | — | Organisation "Noya Concierge" (Free plan), region eu-west-2 (London). Creation was blocked by this session's permission classifier |
| `resend_alerts` | Resend: critical alerts | **prepared** | 1 | `MOS_RESEND_API_KEY` | Domain `noyaconcierge.com` is verified in Resend. Own sender `mos-alerts@noyaconcierge.com`, own send-only key, separate from HQ's CEO-report keys. Dispatcher written, not deployed |
| `github` | Repository `noya-marketing-os` | planned | 1 | — | This session cannot create repositories. Code is in `NOYA-AI-OS/NOYA-MARKETING-OS` until an automated migration task runs (queued) |
| `anthropic` | Claude API, Marketing OS budget | not connected | 2 | `MOS_ANTHROPIC_API_KEY` | D7: separate key and limit from HQ. No tool can create an Anthropic key; it needs a one-time console action by the account owner |
| `firecrawl`, `serper` | Research (read) | planned | 3 | `MOS_FIRECRAWL_API_KEY`, `MOS_SERPER_API_KEY` | Existing accounts; HQ budgets respected |
| `instagram` | Instagram: NOYA | not connected | 5 (read), 7 (write) | `MOS_IG_READ_TOKEN` | Meta app + system user in NOYA's Business portfolio (one OAuth consent) |
| `linkedin_noya` | LinkedIn Company Page | not connected | 5 / 7 | `MOS_LINKEDIN_READ_TOKEN` | Depends on LinkedIn granting Community Management API access |
| `linkedin_adam` | LinkedIn: Adam personal | not connected (permanently manual) | 4 | — | Never automated. Its kill switch can never be enabled (function refuses) |
| `meta_ads` | Meta Ads | not connected | 5 (read), 8 (write) | `MOS_META_ADS_READ_TOKEN` | Write token only in Phase 8, after the platform-native spending limit is confirmed |
| `linkedin_ads` | LinkedIn Ads | planned | 8 | — | |
| `ga4`, `search_console` | Google analytics (read) | planned | 5 | `MOS_GA4_SERVICE_ACCOUNT` | |
| `hq_handoff` | NOYA HQ hand-off | planned | 6 | `MOS_HQ_HANDOFF_SIGNING_SECRET` | Needs a separately approved HQ intake; qualified opportunities only |

## Connectors available to Claude, and how Marketing OS treats them

| Connector in Adam's workspace | Use by Marketing OS |
|---|---|
| Supabase | Project creation and migrations (pending permission) |
| GitHub | Branch pushes. Repository creation is not permitted in this session |
| Resend | Read-only inspection done (domains, key names). Sending only through the dispatcher |
| n8n | Phase 2+: worker workflows. Nothing created in Phase 1 |
| Metricool, Windsor.ai, AdWhispr | **Never** for writes or spend; they would bypass approvals and audit. Read-only research at most |
| Gmail, Drive, Calendar | Not used by Marketing OS in Phase 1 (HQ owns Gmail flows) |

## Connecting something (standard procedure)

1. The secret is created and stored by the account owner in the secure form for that store (Supabase secret or n8n credential).
   This is the only owner step, and is OAuth / consent where the platform requires it.
2. A reader makes one harmless verification call, logged in `gov.external_call_log`.
3. A migration or worker function sets `status`, `verified_at`, `verification_evidence` and `granted_scopes`, and marks
   `gov.secrets_registry.is_set`.
4. Write access is a separate step, in its own phase, with a separate token.
