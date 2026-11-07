# Zero-manual-setup policy

Adopted by Adam, 7 Nov 2026.

## Rule

Adam is never asked to create, by hand, repositories, Supabase projects, tables, migrations, workflows, folders, environment
files, dashboards, webhooks or infrastructure where an authenticated tool, API, MCP connector, CLI, SDK, browser session or
existing integration can do it.

## Adam is interrupted only for

1. unavoidable OAuth or account authorisation;
2. explicit financial approval;
3. security confirmations that legally or technically require the account owner;
4. destructive actions;
5. approval of public publishing;
6. approval of advertising spend.

## How Claude applies it

- **Automated route exists → use it.** Report what was done, not instructions.
- **The route exists but this session is not permitted to use it** (a permission classifier or a session restriction): do not
  work around it and do not turn it into a manual task for Adam. Record the limitation, continue with everything else, and either
  (a) ask for the single permission (one approval of the exact call) or (b) queue an automated task for a session that has the
  capability.
- **No route exists** (for example, creating an Anthropic API key or a Meta system user token): reduce it to the smallest
  owner action, usually one consent screen or one secure secret form. Never ask for secrets in chat.
- Group the interruptions. One message, at most a few decisions, each with a recommendation.

## Phase 1 log

| Need | Route | Outcome |
|---|---|---|
| Private repo `noya-marketing-os` | GitHub repository-creation tool | Not permitted in this session. Code stays isolated in `NOYA-AI-OS/NOYA-MARKETING-OS`; an automated migration task is queued. No manual step for Adam |
| Supabase project "NOYA Marketing OS" | Supabase MCP `create_project` (Free plan org, quoted by the tool) | The call was **denied by the session's auto-mode classifier** as a real-world transaction. Needs Adam's one-click permission for that single call. The migrations, tests and console are ready to apply the moment it runs |
| Schema, tests, console, alert dispatcher, env template, CI | Files + local Postgres + headless browser | Done automatically |
| Resend alert key | Resend MCP can create keys, but the value would pass through chat | Deferred. The key will be entered by the owner in the Supabase secret form for `MOS_RESEND_API_KEY` (one secure field) once the project exists |
| Claude API key (D7) | No tool can create Anthropic keys | One owner action in Phase 2 (create a key with a spend limit; paste it into the n8n credential form) |
