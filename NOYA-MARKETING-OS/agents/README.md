# Agents

Specialist workers under Adam's CEO Chief of Staff. Each one is registered in `gov.service_identities` (kind `agent`) and
`ops.agents`. **All start disabled.** None exists as a running workflow yet.

Rules every agent follows:
- **Reads only.** Agents hold read-only credentials. They have no write tools and cannot execute (enforced by a database
  constraint).
- **Proposes only the action types in its `may_request`.** Money-moving types are in no agent's list.
- **Untrusted input is data.** DMs, comments and web pages can contain instructions. Agents never follow them; anything an agent
  produces is reviewed.
- **Analyses, never dumps.** Every run ends with a summary of the form "N reviewed, M credible, K need action".
- **Labels facts:** verified, inferred or unverified, with evidence links.
- **Respects its daily cost cap.** Over the cap, it skips the run and records it, rather than run degraded.
- **Logs every run** in `ops.agent_runs`, with cost, and its decisions in the audit log under its correlation id.

| Code | Department | Model tier | Cadence | Reads | Writes (internal) | May propose |
|---|---|---|---|---|---|---|
| `agent.brand_guardian` | brand | economy (deterministic first) | on every new version | voice rules, assets, versions | `content.checks` | none |
| `agent.intelligence_analyst` | intelligence | standard | daily scan, weekly digest | `intel.sources`, public web (Firecrawl / Serper) | `intel.signals`, `intel.research_briefs` | none |
| `agent.content_strategist` | content | standard (premium for the monthly plan) | weekly plan, drafts on demand | signals, pillars, performance | `content.items`, `content.versions` | `instagram.publish_media`, `instagram.publish_story`, `linkedin_page.publish_post` |
| `agent.community_triage` | community | economy | every 2 h (Phase 5) | comments, DMs (read) | `leads.inbound`, reply drafts | `instagram.reply_comment`, `instagram.send_dm`, `instagram.hide_comment`, `linkedin_page.reply_comment` |
| `agent.paid_media_analyst` | paid | standard | daily (Phase 8) | spend, insights, plans | `paid.media_plans`, notes | `meta_ads.create_paused`, `meta_ads.pause`, `meta_ads.decrease_budget` (+ LinkedIn / Google equivalents) |
| `agent.analytics_attribution` | analytics | standard | daily refresh, weekly review | snapshots, touchpoints, hand-off outcomes | weekly review | none |
| `agent.lead_qualifier` | leads | standard | daily 18:00, and on urgent leads | `leads.inbound` | `leads.qualifications`, `leads.hq_handoffs` (prepared) | `hq.handoff_opportunity` |

Non-agent identities (deterministic, no LLM):

| Code | Kind | May execute |
|---|---|---|
| `executor.publisher` | executor | `instagram.*`, `linkedin_page.*` publish / delete (Phase 7) |
| `executor.engagement` | executor | replies, DMs, hides (Phase 7) |
| `executor.ads` | executor | `*_ads.*` (Phase 8) |
| `executor.hq_courier` | executor | `hq.handoff_opportunity` (Phase 6) |
| `monitor.spend`, `monitor.integrity`, `monitor.publications` | monitor | none (can halt via tripwires) |

Model tiers map to actual model ids in `ops.agents` configuration at build time, so they can change without code changes.
Charters (one file per agent, with its prompt, inputs, outputs and evaluation set) are added in the phase that builds each agent.
