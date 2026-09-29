# NOYA System Dependency Register

The live register is the `system_services` table, shown in HQ → **System costs**. This file is a snapshot from 30 Sep 2026.

**UNKNOWN** means that no invoice or plan page has confirmed the figure yet. It is never zero.

| Service | Purpose | Plan | Cost type | Monthly | Limit | What breaks without it | Alternative | Credential kept in | Renewal |
|---|---|---|---|---|---|---|---|---|---|
| n8n Cloud | Runs every workflow (00–14) | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN (executions) | All automation stops | Self-hosted n8n | n8n account (Adam) | UNKNOWN |
| n8n AI gateway credits | Gemini 3.1 Flash-Lite, GPT-5 mini | Included in n8n plan | UNKNOWN | UNKNOWN | UNKNOWN | AI falls back to deterministic output | Own Gemini/OpenAI key | Managed by n8n | — |
| Anthropic API | Premium model, manual escalation only | Pay as you go (balance low) | Pay as you go | — | Account balance | Nothing in normal operation | Leave unused | n8n credential "Anthropic" | — |
| Supabase | CRM, HQ auth, server functions | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN | HQ and all workflows stop | None (core) | Supabase dashboard; n8n credential | UNKNOWN |
| Hunter | Email finding/verification | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN | No new VERIFIED emails | Manual verification | n8n credential | UNKNOWN |
| Serper | Google search for research | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN (~2,061 searches/month projected) | Discovery stops | Firecrawl search | n8n credential | UNKNOWN |
| Firecrawl | Reads company websites | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN (~180 calls/month projected) | Research is shallower | Plain HTTP fetch | n8n credential | UNKNOWN |
| Google Workspace (noya@) | Drafts, sending, reply tracking | UNKNOWN | UNKNOWN | UNKNOWN | — | No drafts, sends or reply tracking | None (core) | n8n credential "NOYA Gmail" | UNKNOWN |
| Cloudflare | Hosts hq.noyaconcierge.com | UNKNOWN (static, usually free tier) | UNKNOWN | UNKNOWN | — | HQ unreachable (data safe) | Any static host | Cloudflare account | — |
| Windsor.ai | Instagram / paid media data | Free plan | Usage limited | 0 | 1 account | Marketing data stops (already stale) | Instagram Graph API | n8n credential | — |
| GitHub | Code repository | UNKNOWN | UNKNOWN | UNKNOWN | — | No new deploys | Any git host | GitHub (noya-sudo) | — |
| Domain noyaconcierge.com | Website, email, HQ | UNKNOWN | UNKNOWN | UNKNOWN | — | Email, site and HQ stop if it lapses | None | Registrar | **UNKNOWN — record it** |
| LinkedIn (Adam personal) | Warm network, manual messages | Free | Free | 0 | LinkedIn's own limits | Nothing automated | — | None stored (by design) | — |

## Budget view
- **Known fixed monthly:** none confirmed yet.
- **Pay as you go:** Anthropic (unused on automatic paths).
- **Unknown exposure:** 11 services. Verify each before increasing volume.
- **AI spend guard (configured):** USD 30/month in `system_config.ai_budget`, cheap models only above 100%. This is a guard, not a measured spend.
- **Usage counts (actual, 30-day projection):**
  - 2,061 Serper searches, 180 Firecrawl calls, 60 Hunter checks;
  - 21 discovery AI calls, 13 reply-AI calls, 90 CEO briefs.
- **New in this phase:** workflow 14 adds at most 56 n8n executions a day (every 15 minutes, 08:00–22:00 Cairo). Most are empty polls.

## Paid-software gate (always on)
Before any paid tool, plan upgrade, API credit or connector, HQ must show:
- the tool;
- its purpose;
- why the current stack cannot do it;
- the free option and the paid option;
- the monthly cost and the usage cost;
- what happens if NOYA stops paying.

Then it waits for Adam's explicit approval.

Nothing paid is awaiting approval today.
