// Fails if anything shipped to the browser could grant more than publishable access.
import { readFileSync, readdirSync, statSync } from 'node:fs';

// Text files only (fonts are binary assets, scanned by name/type in the headers check).
const files = readdirSync('dist').map((f) => `dist/${f}`).concat(readdirSync('src').map((f) => `src/${f}`))
  .filter((f) => statSync(f).isFile() && !/\.(woff2?|svg|png)$/.test(f));
const appSources = ['src/app.js'];
const problems = [];
const writeRpcs = new Set();
for (const f of files) {
  const s = readFileSync(f, 'utf8');
  if (/sb_secret_[A-Za-z0-9_-]+/.test(s)) problems.push(`${f}: contains an sb_secret_ key`);
  if (/service_role/i.test(s) && !f.endsWith('config.js')) problems.push(`${f}: mentions service_role`);
  for (const jwt of s.match(/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g) || []) {
    try {
      const payload = JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString());
      if (payload.role && payload.role !== 'anon') problems.push(`${f}: JWT with role ${payload.role}`);
    } catch { /* not a JWT */ }
  }
  for (const m of s.matchAll(/(?:\.rpc|\bcall|\bdone)\(\s*['"]([a-z_]+)['"]/g)) writeRpcs.add(m[1]);
  if (/\.from\(\s*['"](opportunities|contacts|tasks|outbound_emails|companies|approval_audit|hq_admins)['"]\s*\)/.test(s)) problems.push(`${f}: direct table access`);
}
const allowed = ['hq_dashboard', 'hq_overview', 'hq_directory', 'hq_insight', 'hq_timeline', 'hq_relationships', 'hq_history_action', 'hq_add_contact',
  'hq_save_draft', 'hq_approve_draft', 'hq_hold', 'hq_reject', 'hq_redispatch', 'hq_task_action', 'hq_task_dismiss',
  'hq_opportunity_update', 'hq_add_note', 'hq_log_touch', 'hq_record_meeting', 'hq_change_channel', 'hq_import_connections',
  'hq_connection_update', 'hq_request_draft', 'hq_draft_action', 'hq_finance_upsert', 'hq_record_payment', 'hq_create_opportunity', 'hq_company_update', 'hq_relationship_status', 'hq_service_update',
  'hq_commercial', 'hq_account', 'hq_signal_update', 'hq_signal_org', 'hq_signal_capture', 'hq_signal_promote', 'hq_signal_org_to_crm', 'hq_prepare_outreach', 'hq_opportunity_commercial',
  'hq_partner_upsert', 'hq_project_update', 'hq_project_item', 'hq_edge_add', 'hq_role_route'];
for (const r of writeRpcs) if (!allowed.includes(r)) problems.push(`calls non-allowlisted RPC ${r}`);
if ([...writeRpcs].some((r) => /send/i.test(r))) problems.push('a send RPC is referenced');
console.log('RPCs referenced by the client:', [...writeRpcs].sort().join(', '));
if (problems.length) { console.error('SECURITY SCAN FAILED\n' + problems.join('\n')); process.exit(1); }
console.log('SECURITY SCAN PASS: no secret keys, no non-anon JWTs, no direct table access, no send path.');
