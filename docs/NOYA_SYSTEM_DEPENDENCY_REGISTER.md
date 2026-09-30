# NOYA System Dependency Register

The live register is the `system_services` table, shown in HQ → **System costs**. This file is a snapshot from 30 Sep 2026. Edit costs in HQ with **Update from invoice**. Every change is audited.

**UNKNOWN** means that no invoice or plan page has confirmed the figure yet. It is never zero.

| Service | Purpose | Plan (evidence) | Cost type | Monthly | Limit | What breaks without it | Alternative | Credential kept in |
|---|---|---|---|---|---|---|---|---|
| n8n Cloud | Runs every workflow (00–16) | **UNKNOWN.** No n8n invoice in noya@. Two earlier trials on noya@ ended unpaid (workspace "noya", Nov 2025; "noyaconcierge", 14 Aug 2026). The live instance noyaprivate.app.n8n.cloud is billed elsewhere, or is a trial. | UNKNOWN | UNKNOWN | UNKNOWN (executions) | All automation stops | Self-hosted n8n | n8n account (Adam) |
| n8n AI gateway credits | Gemini 3.1 Flash-Lite, GPT-5 mini | Included in the n8n plan | UNKNOWN | UNKNOWN | UNKNOWN | AI falls back to deterministic output | Own Gemini/OpenAI key | Managed by n8n |
| Anthropic API | Premium model, manual only | Pay as you go (balance low) | Pay as you go | — | Balance | Nothing | Leave unused | n8n credential |
| Supabase | CRM, HQ auth, server functions | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN | HQ and all workflows stop | None (core) | Supabase; n8n credential |
| Hunter | Email finding/verification | **Free plan, 50 credits/month** (Hunter email, 27 Sep 2026) | Usage limited | 0 | 50 credits/month | No new VERIFIED emails | Manual verification | n8n credential |
| Serper | Google search for research | UNKNOWN. No sign-up or billing email in noya@, so it is under another email. | UNKNOWN | UNKNOWN | ~2,061 searches/month projected | Discovery stops | Firecrawl search | n8n credential |
| Firecrawl | Reads company websites | **Free credits**, 50% used by 23 Sep 2026 (Firecrawl email) | Usage limited | 0 | Free allowance | Research is shallower | Plain HTTP fetch | n8n credential |
| Google Workspace (noya@) | Drafts, sending, reply tracking | **Business Standard**, monthly invoice auto-charged (Google emails; invoice 5669140503, 1 Sep 2026). The amount is only in the PDF. | Fixed monthly | UNKNOWN (in PDF) | Per user | No drafts, sends or reply tracking | None (core) | n8n credential "NOYA Gmail" |
| Stripe (NOYA payments) — **new** | Client card payments | Monthly Stripe tax invoices, Aug 2025 – Aug 2026 | Pay as you go | Fees per transaction | — | No card payments | Bank transfer | Stripe account |
| Cloudflare | Hosts hq.noyaconcierge.com | UNKNOWN (static, usually free tier) | UNKNOWN | UNKNOWN | — | HQ unreachable (data safe) | Any static host | Cloudflare account |
| Google Cloud (noya@) — Adam's | Not used by NOYA | Free trial, started 26 Sep 2026 (Google email); confirmed as Adam's | Usage limited | 0 | Trial credit | Nothing | — | Google Cloud console — **no NOYA dependency without a clear reason** |
| Windsor.ai | Instagram / paid-media data | Free plan | Usage limited | 0 | 1 account | Marketing data stops (already stale) | Instagram Graph API | n8n credential |
| GitHub | Code repository | UNKNOWN | UNKNOWN | UNKNOWN | — | No new deploys | Any git host | GitHub |
| Domain noyaconcierge.com | Website, email, HQ | UNKNOWN | UNKNOWN | UNKNOWN | — | Everything stops if it lapses | None | Registrar — **record the renewal date** |
| LinkedIn (Adam personal) | Warm network, manual messages | Free | Free | 0 | LinkedIn's limits | Nothing automated | — | None stored |

## Cost reconciliation (30 Sep 2026)
Evidence comes from NOYA's own Gmail (noya@), billing emails only.

- **Confirmed fixed monthly:** £0 / $0 confirmed. Google Workspace Business Standard is a fixed monthly cost, but the amount is only in the PDF invoice.
- **Usage-based:**
  - Hunter: free, 50 credits a month.
  - Firecrawl: free credits.
  - Stripe: fees per transaction.
  - Anthropic: pay as you go, unused.
  - Windsor: free.
- **Remaining UNKNOWN (7):** n8n Cloud, n8n AI credits, Serper, Supabase, Cloudflare, GitHub, domain.
- **Will get expensive as volume grows:**
  1. **Serper:** ~2,061 searches a month. It is the biggest usage-priced service.
  2. **n8n executions:** reply tracking now runs ~1,440 times a month (every 30 minutes since 30 Sep; it was ~2,880).
  3. **Hunter:** ~60 checks a month projected against 50 free credits. It runs out late each month.
  4. **Firecrawl:** free credits were half used by 23 Sep.
- **Downgrade or remove without hurting reliability:**
  - **Anthropic API:** no automatic workflow uses it.
  - **Windsor.ai:** stale data, and 3 accounts on a 1-account plan.
  - **Reply tracking:** done 30 Sep. It moved from every 15 to every 30 minutes, about 1,440 fewer runs a month. Nothing is missed: the search starts from a fixed date and each message is handled once. A manual run is still available in n8n (workflow 13 → Manual Sync).
- **Risk:** Google Workspace card payments were declined six times (Dec 2025 – Jun 2026). No decline since 1 Jun. Keep a valid card on file.

## Budget view
- **Known fixed monthly:** no amount confirmed yet. Google Workspace Business Standard is fixed, amount in the PDF invoice.
- **Pay as you go:** Anthropic (unused on automatic paths), Stripe fees.
- **Unknown exposure:** 7 services with no plan evidence, plus the Google Workspace amount. Verify each before increasing volume.
- **AI spend guard (configured):** USD 30/month in `system_config.ai_budget`, cheap models only above 100%. This is a guard, not a measured spend.
- **Usage counts (actual, 30-day projection):**
  - 2,061 Serper searches, 180 Firecrawl calls, 60 Hunter checks;
  - 21 discovery AI calls, 13 reply-AI calls, 90 CEO briefs.
- **Automation runs (n8n executions, monthly maximum):**
  - Reply tracking (13): ~1,440 (every 30 minutes).
  - Gmail history sync (15): ~180 (every 3 hours, 07:00–22:00).
  - Message drafting (14): ~60 safety sweeps plus one run per draft you request. This is now event-driven; it was up to 1,680 a month with polling.
  - Other workflows: see n8n → Executions.
  - The n8n plan allowance is UNKNOWN.
- **Gmail API** (Google Workspace): the history import uses read-only metadata calls within Google's free quota. There is no separate charge.

## Standing decisions (Adam, 30 Sep 2026)
- **n8n:** do not change or upgrade the plan until the real allowance and cost are known (Adam to send Settings → Usage and plan).
- **Serper:** do not increase search volume until the plan and monthly allowance are confirmed (Adam to confirm the account).
- **Google Cloud:** Adam's own account. It stays listed; no NOYA dependency on it without a clear reason.
- **No new paid tool.**

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
