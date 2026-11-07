# Decisions

Architecture decisions taken in Phase 0 (proposed, pending Adam's confirmation), and open CEO decisions.

## Proposed architecture decisions

| # | Decision | Why | Alternatives rejected |
|---|---|---|---|
| A1 | Marketing OS is a standalone product, separate from NOYA HQ | Different job, different risk profile, different users later (content team, agencies) | Building marketing screens into HQ: mixes marketing noise into the commercial CRM |
| A2 | Propose → approve → execute, with LLM agents and executors strictly separated | A model with write access is one prompt injection away from posting or spending | Agents with direct tool access plus "be careful" prompts |
| A3 | Approvals bound to the payload's SHA-256; payload frozen after submission | Approval must mean exactly what was approved | Approving an item id whose content can still change |
| A4 | Kill switch installed halted, four layers, tripwires can halt but never arm | Fail-closed by default; an automatic system must never re-enable itself | A single feature flag |
| A5 | Hash-chained, append-only audit log; refusals returned (not raised) so they are recorded | Tamper-evidence and a complete record, including blocked attempts | A plain log table |
| A6 | Supabase + n8n + Claude + Cloudflare static, as in HQ | One stack to maintain; no new subscriptions | A new backend framework, or a social-media SaaS as the core |
| A7 | Official APIs only; Adam's personal LinkedIn never automated | Platform terms, account safety, reputation | Cookie-based tools, unofficial APIs |
| A8 | Money-moving actions can never be automatic (database trigger) | The cost of a mistake is unbounded | A configurable setting |

## CEO decisions taken (7 Nov 2026)

| # | Decision |
|---|---|
| D1 | Separate private repository `noya-marketing-os` (migration task queued; this session cannot create repositories) |
| D2 | Separate Supabase project "NOYA Marketing OS" in organisation "Noya Concierge" |
| D3 | Leave every existing NOYA HQ marketing piece untouched |
| D4 | Critical safety conditions may automatically PAUSE ads only; never resume, activate, increase or create spend |
| D5 | Adam is sole approver |
| D6 | Critical kill-switch alerts to Adam through the existing Resend infrastructure (own key and sender) |
| D7 | Separate Claude / API budget and credential boundary from HQ |
| Policy | Zero-manual-setup policy (`docs/zero-manual-policy.md`) |

## Original options (for the record)

**D1: Where does the code live?**
Context: the scaffold is in `NOYA-MARKETING-OS/` inside the NOYA-AI-OS repository (the HQ repo), on a branch. No HQ file was
touched. This session cannot create GitHub repositories.
Recommendation: **A.** Create a private repo `noya-marketing-os`, and move this folder there with history (`git subtree split`).
- A: New private repo (recommended)
- B: Keep as a folder in NOYA-AI-OS

**D2: Database.**
Context: HQ's Supabase plan is recorded as Free. Free allows two active projects, so a second project is likely £0, but the plan
must be confirmed first. Sharing HQ's project means HQ's service key can reach marketing data and vice versa.
Recommendation: **A.** New Supabase project in an EU region (London if available), created by Adam.
- A: Separate project (recommended)
- B: Separate schemas inside the HQ project

**D3: HQ's existing marketing pieces** (`content_performance`, `paid_media_performance`, `marketing_attribution`, workflows 10a–10d).
Context: 10a–10c are paused (Windsor plan limit); 10d (website enquiries) is live and writes into HQ.
Recommendation: **A.** Leave them untouched. Marketing OS becomes the source of truth for marketing data from Phase 5. 10d stays
in HQ (it already produces commercial opportunities). Retiring 10a–10c is a later HQ change.
- A: Leave as is (recommended)
- B: Move website intake to Marketing OS in Phase 6

**D4: Emergency auto-pause of live ads** (from Phase 8 only).
Recommendation: **B.** Freeze plus automatic pause on spend tripwires. It is the only pre-authorised external write, and it can
only reduce spend.
- A: Freeze only
- B: Freeze and auto-pause (recommended)

**D5: Approvers.**
Recommendation: **A.** Adam is the sole owner and sole approver for publishing, hand-offs and spend. Editors (if any) draft only.
Revisit when a marketing lead joins.
- A: Adam only (recommended)
- B: Add an approver for organic posts

**D6: Alerts for halts and tripwires.**
Context: approving the Resend notification as an automatic external write to a fixed recipient (Adam only).
Recommendation: **A.** Email to Adam via the existing Resend account. This exception covers alerts only, never marketing.
- A: Email alerts to Adam (recommended)
- B: Console only

**D7: Claude API key.**
Recommendation: **A.** A separate Anthropic key (or workspace) for Marketing OS with its own monthly limit, so marketing AI spend
is visible separately from HQ.
- A: Separate key (recommended)
- B: Share HQ's

**D8: First paid test budget** (Phase 8, not now).
No recommendation yet. It will be prepared with a media plan, kill criteria and a cost-per-qualified-enquiry target when organic
data exists.
