# NOYA System Audit — Supabase and n8n (19 Oct 2026)

Part of the professional operating pass ("CEO Command Centre & Professional Operating Mode", 18–19 Oct 2026). The rule
throughout: classify everything, remove only what is proven safe, never delete evidence. **Nothing was deleted in this audit.**

Classes: ACTIVE · LEGACY · TEST · TEMPORARY · SAFE TO ARCHIVE · SAFE TO REMOVE · NEEDS REVIEW (Supabase);
PRODUCTION · SUPPORT · ADMIN · TEST · ARCHIVED (n8n).

## 1. Supabase (project gagbhykzmtstekpqujyl)

### Summary

| Area | Count | State |
|---|---|---|
| Tables (public) | 64 | All RLS on, no policies: deny by default. The browser reads nothing directly. |
| Functions | 309 | 88 `hq_*` HQ calls (admin-gated), 18 `ops_*` one-off operations, the rest helpers, queues, cache and n8n calls. |
| SECURITY DEFINER callable by anonymous visitors | 0 | |
| SECURITY DEFINER callable by signed-in users | 73 | All `hq_*`. Each checks `hq_admins` (user id and email) before doing anything. By design. |
| Functions with no fixed search_path | 0 | Was 49; fixed in this audit. |
| Views | 15 | None readable by anon or signed-in users. 8 used by functions; 7 analysis-only. |
| Scheduled jobs (pg_cron) | 7 | All active, 0 failures in 7 days. |
| Database size | 40 MB | |

Security advisor after the audit: the 63 "RLS without policy" notices are INFO and intended (no table is readable from the
browser); the 73 `hq_*` warnings are the admin-gated HQ API; **leaked-password protection is off** (a Supabase Auth setting,
see decisions).

### Tables

| Class | Tables | Notes |
|---|---|---|
| ACTIVE: CRM and pipeline | companies (606), contacts (~1,500), opportunities (~520), tasks (~390), interactions (70), outbound_emails (32), outreach_candidates (~180), approval_audit, approval_queue_state, outreach_drafts, message_drafts, relationship_reviews, relationship_notes, company_field_history | Source of truth. |
| ACTIVE: email and contact intelligence | email_research, email_official_inboxes, contact_email_verifications, email_finder_log | Workflows 19, 23, 24, 25. |
| ACTIVE: Gmail | gmail_sync_state, gmail_sync_ledger, gmail_history_threads, gmail_history_messages, gmail_backfill_state | Workflows 13 and 15. |
| ACTIVE: signals and research | intelligence, signal_organisations, department_run_metrics, creative_concepts, commercial_products, commercial_playbooks | Discovery 02–09, 17, 21. |
| ACTIVE: system | agent_registry, system_config, hq_read_cache, hq_admins, hq_advisor_state, ai_usage, provider_balances, system_services, system_blockers, ceo_reports, role_routing, team_members, website_enquiries | |
| ACTIVE: Studio | studio_documents (40), studio_outputs (8) | |
| ACTIVE, empty by design | revenue, revenue_payments, projects, project_items, company_relationships, relationship_edges | The won → project → revenue chain. Empty because no project has been recorded yet and the historical £60k awaits Adam's records. |
| ACTIVE, empty until Adam acts | linkedin_connections; club_people, club_benefits, club_events, club_introductions | LinkedIn fills from Adam's own export; Club from the first members. |
| ACTIVE, source blocked | content_performance (11), paid_media_performance (11), competitor_intelligence (17), marketing_attribution (5), content (0) | Growth Director data, stale since 20–26 Sep (Windsor free plan). |
| TEST (evidence, kept) | email_intel_tests (85) | Email cohort tests of 8 Oct; the open cohort was closed in this audit. |
| TEMPORARY (evidence, kept) | hq_perf_baseline (27) | Timing baseline from the 16–17 Oct timeout fix. No code reads it. SAFE TO REMOVE later; kept as the record. |
| LEGACY | cost_ledger (0 rows, nothing reads it) | Costs live in system_services. SAFE TO REMOVE; kept (no cost, no risk). |

### Functions

| Class | What | Decision |
|---|---|---|
| ACTIVE | 88 `hq_*` (HQ reads and actions), queues and planners (`commercial_director_plan`, `enrichment_queue`, `email_gap_*`, `email_verification_queue`, `email_finder_queue`), cache (`hq_cache_*`), integrity, work orders, improvement loop, Gmail ingest, Studio refresh | Keep. |
| ACTIVE helpers | 49 text and rule helpers (`email_state`, `company_lane`, `registrable_domain`…) and 3 triggers | search_path pinned in this audit. 47 are executable by anonymous visitors, but all are invoker-rights with no access to any table (anon has no grants), so this exposes nothing. |
| LEGACY (record of past operations) | 17 one-off `ops_*` (`ops_load_accept1`, `ops_fix_gym_draft`, `ops_w19_downgrade_hbs`…) | Not callable from HQ. Kept as the record of what was done; SAFE TO ARCHIVE in a later tidy. `ops_metric` is ACTIVE (improvement loop). |
| TEST | `ops_email_intel_test_start` / `_finish` | Kept: the email cohort test harness. |

### Views

- ACTIVE (used by functions): gmail_thread_groups, hq_finance_records, hq_opportunity_facts, cost_observability, outreach_readiness, commercial_backlog, company_account_duplicates, contact_email_provenance.
- ACTIVE, analysis only (no data, admin-only): studio_conversion, studio_output_status, studio_queue (Studio scripts and docs), account_sequence_conflicts, commercial_funnel, discovery_yield_daily.
- LEGACY: relationship_graph (unused, undocumented). Holds no data; kept.

### Scheduled jobs

| Job | Schedule (UTC) | Does |
|---|---|---|
| hq-cache-core | every 5 min | CEO, command, advisor, execution, network snapshots |
| hq-cache-directors | every 5 min (offset) | Directors and the three oldest Director pages |
| studio-outputs-refresh | :07, :37 | Studio conversion ledger |
| work-orders-refresh | :17, :47 | Work-order acceptance and status from evidence |
| hq-health | :04, :19, :34, :49 | Admin → System health |
| integrity-daily | 03:10 (05:10 Cairo) | Daily integrity check; safe deterministic fixes only |
| improvements-measure | 03:20 | Measures approved improvements against their baseline |

### Data integrity (daily check, first run 18 Oct)

| Finding | Count | Handling |
|---|---|---|
| Opportunity owner written two ways ("Adam Elshazly" / "Adam") | 377 | Auto-fixed to the CEO's routing name. Same person, one name. |
| Duplicate companies | Mandarin Oriental ×3 (one QUALIFIED, one PARKED, one EXCLUDED); Aman ×2 ("Aman Resorts, Hotels & Residences", "Aman Group") | NEEDS REVIEW: merge proposal in decisions. No double outreach is possible (one open cold route per company holds). |
| Contacts sharing one inbox | 3 shared Aman inboxes, each on both Aman records | Resolved by the Aman merge. |
| Two-way conversations with no company | 5: Encore Lifestyle, Empiria Group, HIGHSTAY, Nouva Group, Purpleski | NEEDS REVIEW (decisions). |
| Email drafts waiting over 7 days | 2 (Oliver's Travels, VIRTUE: the quality check failed) | On Adam's desk: edit or reject. |
| Live opportunity past its date | The Arts Club (30 Sep) | On the Dashboard with a Plan button. |
| Follow-ups more than 2 days overdue | 25 | Recommendation CLOSE_STALE_FOLLOW_UPS. |
| LinkedIn / Instagram fallbacks above the cap of 5 | 69 open | Recommendation PARK_SOCIAL_EXCESS. |
| Workflow failure alerts (7 days) | 3 | See the n8n register. |

## 2. n8n register (instance noyaprivate.app.n8n.cloud)

**Limit of this audit.** The n8n connector needs re-authorising, so the live workflow list could not be read. This register
is built from the code in this repo (`n8n/`: builders and code for 12–25, node-code snapshots for 02–06) and from what every
workflow leaves in Supabase: run logs, AI usage, heartbeats, failure alerts and the records each one writes. Workflows that
exist only in n8n (for example old copies or test workflows) cannot be listed until access is restored. **Nothing was changed in
n8n.**

| # | Workflow | Agent | Schedule | Class | Last evidence (UTC) | State |
|---|---|---|---|---|---|---|
| 00 | Failure alerts (error workflow) | System | on error | SUPPORT | 18 Oct 19:30 (alert task) | Working: emails Adam and opens a failure task. |
| 00b | Provider health | System | scheduled | SUPPORT | 16 Oct (PROVIDER_UNAVAILABLE alert) | Working. |
| 01 | Not evidenced | | | NEEDS REVIEW | none in Supabase or the repo | Check in n8n once access returns. |
| 02 | Brand & Production Department v1 | Brands & Production | 3× a day | PRODUCTION | 18 Oct 15:01 (22 runs in 7 d) | Healthy. |
| 03 | Hotels & Content Trips Department v1 | Hospitality & Stays | 3× a day | PRODUCTION | 18 Oct 15:31 (21) | Healthy. |
| 04 | Weddings & Events Department v1 | Weddings & Private Events | 3× a day | PRODUCTION | 18 Oct 16:01 (20) | Healthy. |
| 05 | Sales & Outreach Department v1 | (old drafter) | schedule paused since 7 Oct | ARCHIVED (paused) | | Replaced by 18. Archive in n8n (decision). |
| 06 | Corporate & Private Client Growth Department v1 | Corporate, NOYA Private, Private Membership | 3× a day | PRODUCTION | 18 Oct 17:01 (21) | Healthy. |
| 07 | Global Partnerships Department v1 | Travel, Private Membership | 3× a day | PRODUCTION | 18 Oct 17:31 (21) | Healthy. |
| 08 | Creators & Talent Department v1 | NOYA Private | daily | PRODUCTION | 18 Oct 06:02 (7) | Healthy. |
| 09 | Egypt Intelligence Department v1 | Egypt Growth | daily | PRODUCTION | 18 Oct 07:01 (7) | Healthy. |
| 10a/10b/10c | Instagram, paid media, competitor reads | Growth, Social & Paid Media | daily | PRODUCTION, blocked | 26 Sep (10c), 20 Sep (10b) | No data since late September: the Windsor free plan allows 1 account and 3 are connected. |
| 11 | Daily CEO brief | Commercial Director | daily | PRODUCTION | 18 Oct 16:00 | Healthy. |
| 12 | Outbound Email Executor v1 | (Adam's approvals) | on approval | PRODUCTION | 16 Oct 18:54 (last draft); alert 16 Oct WORKFLOW_ERROR | Creates unsent Gmail drafts only (no send node). One open alert. |
| 13 | Gmail Interaction Sync v1 | Reply & Follow-up | every 30 min | PRODUCTION | 19 Oct 00:30 | Sync healthy; its reply classifier fails with "payment required" (Anthropic). Recommendation REPLY_CLASSIFIER_GEMINI. |
| 14 | Message Drafting | Outreach Writer | on request | PRODUCTION | 29 Sep (last completed request) | Idle: no requests since. |
| 15 | Gmail History Import | Relationship Memory | every 3 h | PRODUCTION | 18 Oct 19:10 | Healthy. |
| 16 | Relationship Summaries | Relationship Memory | daily | PRODUCTION | 14 Oct (last summary) | Runs; nothing new to summarise. |
| 17 | Signal Analyst | Egypt Growth | on new signal | PRODUCTION | 7 Oct (last analysis) | Idle: no new Egypt signals to analyse. |
| 18 | Commercial Director: Daily Outreach v2 | Outreach Writer, Commercial Director | daily | PRODUCTION, failing | heartbeat 18 Oct 19:00; last AI call 16 Oct 22:12; alerts 17 and 18 Oct PROVIDER_UNAVAILABLE | No new drafts for two nights; 29% rate-limited over 7 days. Fix needs n8n access: a backup model on the drafting step. Drafts already waiting (71) are unaffected. |
| 19 | Contact Route Enrichment v1 | Contact Intelligence | scheduled | PRODUCTION | 18 Oct 18:00 | 16 errors in 100 calls (7 d). Watch. |
| 20 | Draft Revalidation v1 | Outreach Writer | daily | PRODUCTION | 18 Oct 07:15 | Healthy. |
| 21 | Creative Concepts | Media & Culture | daily | PRODUCTION | heartbeat 18 Oct 08:30; last concept 8 Oct | Runs; nothing new to build. |
| 22 | Serper Balance v1 | System | every 6 h | SUPPORT | 18 Oct 21:05 | Healthy (29,677 searches left). |
| 23 | Email Intelligence | Email Intelligence & Verification | scheduled | PRODUCTION | 18 Oct 20:15 | Healthy. |
| 24 | Email Verification (Hunter) | Email Intelligence & Verification | scheduled | PRODUCTION, capped | 9 Oct | Hunter Free credits used until 27 Oct (Adam: stay Free until the 27 Oct test). |
| 25 | Email Finder | Email Intelligence & Verification | scheduled | PRODUCTION, capped | 8 Oct | Same Hunter cap. |

**Live inspection after the connector was re-authorised (19 Oct).** 33 workflows: 00–25 above plus 00b, 10d (website
enquiry intake, live) and three inactive website-to-Sanity workflows that belong to the website and were not touched. Every NOYA
workflow reports failures to 00; none reads from GitHub. Changes, nothing redesigned:

| # | Finding | Change |
|---|---|---|
| 01 | Inactive skeleton ("placeholder pass, not executed"), Anthropic model, no executions in retention | Archived (reversible). |
| 05 | Inactive since 7 Oct, replaced by 18, no executions in retention | Archived (reversible). |
| 10a/10b/10c | Growth reads, blocked by the Windsor plan | Unpublished: Growth Director paused by Adam. 10d stays live. |
| 11 | CEO brief fallback used the same model as the primary; billing alert told Adam to restore Anthropic credit | Fallback on a different Gemini model; alert names the Gemini account. |
| 13 | Reply classifier already on Gemini since 16 Oct (Gemini backup, human review last) | None needed; recommendation marked applied. |
| 18 | 22:30 failures: the planner RPC exceeded PostgREST's 8 s limit, not a provider outage | 55 s function-level limit on the agent RPCs; redraft falls back to a second Gemini model on model errors or rate limits. |
| 00b | The informational Anthropic probe could stop the run before the Serper and Gemini probes | Probe continues on error. |

Fallback check: 14, 16 and 17 fall back to a different provider (GPT-5 mini through the n8n AI gateway); department extraction
(02–07), 11 and 18 fall back to a different Gemini model; qualification (02–08), 09, 19, 21 and 23 have no model fallback and
continue on error (the run keeps going and the item is retried next run). All Gemini nodes share one Google credential, so a
Gemini account outage would stop most AI steps; the deterministic paths (CEO brief, human review of replies) still run.

Repo coverage: 12–25 are rebuildable from `n8n/`; 00–11 exist only in n8n (02–06 partly, as node-code snapshots). Exporting
them belongs after the repository is made private (decision REPO_PRIVATE), because workflow exports name credentials.

## 3. Cleanup completed (19 Oct)

Migration `20261019020000_audit_cleanup.sql`, plus the earlier parts of this pass:

1. **Run-log artefact neutralised.** One integrity-check row in the department run log (18 Oct 23:55) made Research
   Intelligence look as if it had run. Four reads (Agents, Operations discovery signal, Research run list, System health) now
   count only real department runs. Research's last run reads 17:31 again. The row itself stays as evidence.
2. **Security advisor:** 49 helper functions pinned to a fixed search_path (warnings 49 → 0). Behaviour unchanged; measured
   cost about 7–8% on background snapshots.
3. **8 Oct email cohort test closed** through its own finish routine: 60 "after" snapshots saved beside the "before" ones and
   the test flag cleared, so workflow 23 can never prefer that old test set over work-order targets.
4. **System costs register:** Hunter "used by" corrected to 24 and 25 (05 is paused); n8n to all workflows 00–25.
5. Earlier in the pass: 377 owner-name variants unified; the integrity check's own run-log insert removed; the CEO dashboard's
   parked rule aligned with the funnel (Sporting Founders, Founders Club and Sarah Haywood no longer show as live); Advisor
   wording on CEO screens made non-technical.
6. HQ System health now turns n8n and AI providers to **Check** when a workflow failed in the last 7 days or a model was
   unavailable in the last 3, and names the workflow.

## 4. Items intentionally retained

| Item | Why it stays |
|---|---|
| Integrity-check row in the department run log (18 Oct 23:55) | Evidence. No longer read as a discovery run. Delete only with Adam's confirmation; there is no benefit. |
| 5 website QA enquiries (30 Sep ×2, 3 Oct ×2, 19 Oct ×1, all test addresses or marked "DO NOT ACTION") | Proof the website intake works. Their opportunities are archived and tasks closed, so none reaches a CEO screen. |
| email_intel_tests (85) and hq_perf_baseline (27) | Test and timing evidence. |
| cost_ledger, relationship_graph | Empty and unused. No cost, no risk; removal gains nothing today. |
| 17 one-off `ops_*` functions | The record of past operations; not callable from HQ. |
| Legacy registry rows ENRICHMENT and DRAFTING | Pre-V3 agents with no HQ role; older history reads still use them. |
| The example work order (Brands & Production, UK fashion and activewear) and its corrective audit row | A real mission, issued for acceptance and attributed to the System, not Adam. |
| Mandarin Oriental ×3, Aman ×2 | Waiting for the merge decision. |
| Club and Growth tables | Club awaits members; Growth awaits the Windsor decision. |
| Open provider alert of 28 Sep (Anthropic credit) | Informational; asks which Anthropic workspace was topped up. Nothing automatic depends on Anthropic. |
| Workflow 05 | Paused, not archived: archiving needs n8n access. |

## 5. Decisions for Adam

Each is prepared; one letter is enough.

1. **n8n connection.** Re-authorise the n8n connector in claude.ai (Settings → Connectors). It unlocks the workflow 18 backup
   model, the workflow 13 classifier switch, steering discovery by work order, the live n8n register and archiving 05.
   A — do it now (recommended) · B — later.
2. **HQ recommendations** (Dashboard → Awaiting your approval): park 64 of 69 LinkedIn/Instagram fallbacks, keeping the newest
   5; close the 25 stale follow-ups; switch the reply classifier to Gemini; make the repository private.
   Recommended: approve all four.
3. **Historical revenue (£60k).** Send the records (invoices, Stripe exports, bank references). Each project is imported with
   its evidence, dry run first. A — send this week (recommended) · B — leave it as "to be reconciled".
4. **Duplicates.** Merge Mandarin Oriental into the qualified record and Aman into one record. Contacts, opportunities and
   tasks move across, duplicates are marked merged, nothing is deleted. A — merge (recommended) · B — leave.
5. **Five unlinked conversations** (Encore Lifestyle, Empiria Group, HIGHSTAY, Nouva Group, Purpleski). A — the System creates
   the company and opportunity from the Gmail evidence for review (recommended) · B — mark them not commercial.
6. **Growth Director (Windsor free plan: 1 account allowed, 3 connected).** A — pause 10a/10b/10c until marketing reporting
   matters; no spend (recommended) · B — disconnect 2 Windsor accounts (free) · C — upgrade Windsor (spend).
7. **Supabase Auth: leaked-password protection** (free, one switch in Supabase → Authentication). A — turn it on (recommended)
   · B — leave.
8. **Workflow 05** (paused since 7 Oct, replaced by 18). A — archive it once n8n access is back (recommended) · B — keep paused.
