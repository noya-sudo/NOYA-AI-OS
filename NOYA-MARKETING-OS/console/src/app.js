// NOYA Marketing OS — internal console. No dependencies, no secrets.
// Talks to Supabase Auth (password grant) and PostgREST RPC (public.mos_*) with the publishable key + user token.
// Every value from the server is rendered with textContent (never innerHTML).
(() => {
  'use strict';
  const cfg = window.MOS_CONFIG || {};
  const params = new URLSearchParams(location.search);
  const demo = !cfg.supabaseUrl || !cfg.publishableKey || params.has('demo');
  const TOKEN_KEY = 'mos.session';
  const $ = (id) => document.getElementById(id);

  // ------------------------------------------------------------------ helpers
  const el = (tag, opts = {}, children = []) => {
    const n = document.createElement(tag);
    if (opts.cls) n.className = opts.cls;
    if (opts.text != null) n.textContent = String(opts.text);
    if (opts.title) n.title = opts.title;
    for (const c of [].concat(children)) if (c) n.appendChild(c);
    return n;
  };
  const td = (text, cls) => el('td', { text: text ?? '—', cls });
  const tdNode = (node) => { const c = el('td'); c.appendChild(node); return c; };
  const pill = (text, tone) => el('span', { cls: `pill ${tone}`, text });
  const when = (iso) => {
    if (!iso) return '—';
    const d = new Date(iso);
    return d.toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Cairo' }) + ' Cairo';
  };
  const short = (s, n = 12) => (s ? String(s).slice(0, n) + (String(s).length > n ? '…' : '') : '—');
  const toneFor = (s) => ({ ok: 'ok', internal: 'ok', read_only: 'ok', read_write: 'warn', sent: 'ok', enabled: 'warn',
    warn: 'warn', prepared: 'warn', pending: 'warn', submitted: 'warn', approved: 'warn',
    fail: 'fail', error: 'fail', revoked: 'fail', failed: 'fail', critical: 'fail', refused: 'fail',
    disabled: 'off', info: 'neutral', planned: 'neutral', not_connected: 'neutral', draft: 'neutral', suppressed: 'neutral' }[s] || 'neutral');
  const fill = (tbodyId, rows, cols) => {
    const body = $(tbodyId); body.replaceChildren();
    if (!rows || !rows.length) { const r = el('tr'); const c = el('td', { cls: 'empty', text: 'Nothing yet.' }); c.colSpan = cols; r.appendChild(c); body.appendChild(r); return; }
    rows.forEach((r) => body.appendChild(r));
  };
  const showError = (msg) => { const b = $('error'); b.textContent = msg; b.hidden = !msg; };

  // ------------------------------------------------------------------ API
  const session = () => { try { return JSON.parse(sessionStorage.getItem(TOKEN_KEY) || 'null'); } catch { return null; } };
  const setSession = (s) => { try { s ? sessionStorage.setItem(TOKEN_KEY, JSON.stringify(s)) : sessionStorage.removeItem(TOKEN_KEY); } catch { /* private mode */ } };

  async function signIn(email, password) {
    const r = await fetch(`${cfg.supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: cfg.publishableKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error_description || j.msg || 'Sign-in failed');
    setSession({ access_token: j.access_token, expires_at: Date.now() + (j.expires_in || 3600) * 1000, email: j.user && j.user.email });
  }

  async function rpc(fn, args = {}) {
    const s = session();
    if (!s || s.expires_at < Date.now()) { setSession(null); throw Object.assign(new Error('Session expired. Sign in again.'), { auth: true }); }
    const r = await fetch(`${cfg.supabaseUrl}/rest/v1/rpc/${fn}`, {
      method: 'POST',
      headers: { apikey: cfg.publishableKey, Authorization: `Bearer ${s.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(args) });
    const j = await r.json().catch(() => null);
    if (r.status === 401) { setSession(null); throw Object.assign(new Error('Session expired. Sign in again.'), { auth: true }); }
    if (!r.ok) throw new Error((j && (j.message || j.hint)) || `Request failed (${r.status})`);
    return j;
  }

  async function act(fn, args, confirmText) {
    if (demo) { showError('Demo mode: actions are disabled.'); return; }
    if (confirmText && !window.confirm(confirmText)) return;
    try {
      const res = await rpc(fn, args);
      if (res && res.ok === false) showError(`Refused: ${res.reason}`); else showError('');
      await load();
    } catch (e) { showError(e.message); if (e.auth) route(); }
  }

  // ------------------------------------------------------------------ render
  function render(s) {
    const owner = s.viewer && s.viewer.role === 'owner';
    const approver = s.viewer && ['owner', 'approver'].includes(s.viewer.role);
    $('viewer').textContent = s.viewer ? `${s.viewer.email} · ${s.viewer.role}` : '';
    const armed = s.system.external_execution === 'ARMED';
    const badge = $('exec-badge');
    badge.textContent = `External execution: ${armed ? 'armed' : 'disabled'}`;
    badge.className = `badge ${armed ? 'badge-on' : 'badge-off'}`;

    $('s-phase').textContent = s.system.phase;
    $('s-exec').textContent = armed ? 'Armed' : 'Disabled';
    $('s-critical').textContent = s.system.open_critical;
    $('s-pending').textContent = s.system.pending_approvals;
    $('s-chain').textContent = s.audit_chain.first_bad_seq == null ? `Intact · ${s.audit_chain.rows}` : `BROKEN at #${s.audit_chain.first_bad_seq}`;
    $('s-updated').textContent = when(s.generated_at).replace(' Cairo', '');

    // Kill switches
    $('stop-all').hidden = !approver || demo || !s.kill_switches.some((k) => k.state === 'enabled');
    fill('t-switches', s.kill_switches.map((k) => {
      const b = el('button', { cls: 'row-btn', text: 'Disable' });
      b.hidden = demo || !approver || k.state !== 'enabled';
      b.addEventListener('click', () => act('mos_kill_switch_disable', { p_key: k.key, p_reason: 'Disabled from the console' }, `Disable ${k.label}?`));
      return el('tr', {}, [
        el('td', {}, [el('span', { text: k.label }), el('span', { cls: 'sub mono', text: k.key })]),
        tdNode(pill(k.state, toneFor(k.state))),
        el('td', {}, [el('span', { text: when(k.changed_at) }), el('span', { cls: 'sub', text: `${k.changed_by}${k.tripped_by ? ' · tripwire ' + k.tripped_by : ''}` })]),
        tdNode(b) ]);
    }), 4);

    // Security alerts
    const sec = $('l-security'); sec.replaceChildren();
    if (!s.security.length) sec.appendChild(el('li', { cls: 'empty', text: 'No safety events.' }));
    s.security.slice(0, 12).forEach((e) => {
      const ack = el('button', { cls: 'row-btn', text: 'Acknowledge' });
      ack.hidden = demo || !owner || e.acknowledged;
      ack.addEventListener('click', () => act('mos_acknowledge_safety_event', { p_event_id: e.id }));
      sec.appendChild(el('li', {}, [
        el('span', { text: e.summary }),
        el('span', { cls: 'meta' }, [pill(e.severity, toneFor(e.severity)), el('span', { text: e.kind }), el('span', { text: when(e.at) }),
          el('span', { text: e.acknowledged ? 'acknowledged' : '' }), ack]) ]));
    });

    // Pending approvals (read-only)
    fill('t-approvals', s.pending_approvals.map((a) => el('tr', {}, [
      el('td', {}, [el('span', { text: a.title }), el('span', { cls: 'sub', text: a.target })]),
      td(a.action_type, 'mono'), tdNode(pill(a.status, toneFor(a.status))), td(a.requested_by),
      el('td', {}, [el('span', { cls: 'mono', text: `v${a.version} · ${short(a.payload_sha256)}`, title: a.payload_sha256 || '' }),
        el('span', { cls: 'sub', text: a.expires_at ? `approval expires ${when(a.expires_at)}` : '' })]) ])), 5);

    // Services
    fill('t-services', s.integrations.map((i) => el('tr', {}, [
      el('td', {}, [el('span', { text: i.name }), el('span', { cls: 'sub', text: i.notes || '' })]),
      tdNode(pill(i.status.replace('_', ' '), toneFor(i.status))), td(String(i.phase)), td(i.credential_ref || '—', 'mono') ])), 4);

    // Health
    $('run-health').hidden = demo;
    fill('t-health', s.health.map((h) => el('tr', {}, [
      td(h.check.replace(/_/g, ' ')), tdNode(pill(h.status, toneFor(h.status))),
      td(Object.entries(h.detail || {}).map(([k, v]) => `${k.replace(/_/g, ' ')}: ${v}`).join(' · '), 'mono'), td(when(h.checked_at)) ])), 4);

    // Agents + runs
    fill('t-agents', s.agents.map((a) => el('tr', {}, [
      el('td', {}, [el('span', { text: a.name }), el('span', { cls: 'sub mono', text: a.code })]),
      el('td', {}, [pill(a.enabled ? 'enabled' : 'off', a.enabled ? 'ok' : 'off'), el('span', { cls: 'sub', text: a.enabled ? '' : (a.paused_reason || '') })]),
      td(a.schedule || 'on demand') ])), 3);
    const runs = $('l-runs'); runs.replaceChildren();
    if (!s.agent_runs.length) runs.appendChild(el('li', { cls: 'empty', text: 'No agent has run yet. Agents are built from Phase 2.' }));
    s.agent_runs.forEach((r) => runs.appendChild(el('li', {}, [el('span', { text: `${r.agent} — ${r.summary || r.status}` }),
      el('span', { cls: 'meta' }, [pill(r.status, toneFor(r.status)), el('span', { text: when(r.started_at) }), el('span', { text: r.cost_usd != null ? `$${r.cost_usd}` : '' })])])));

    // Audit
    fill('t-audit', s.audit.map((a) => el('tr', {}, [
      td(String(a.seq), 'mono'), td(when(a.at)),
      el('td', {}, [el('span', { text: a.actor }), el('span', { cls: 'sub', text: `${a.actor_type}${a.tool ? ' · ' + a.tool : ''}` })]),
      td(a.action, 'mono'), td(a.target + (a.platform ? ` · ${a.platform}` : ''), 'mono'),
      tdNode(pill(a.result, toneFor(a.result))), td(a.reason || '') ])), 7);

    // Alerts outbox
    $('test-alert').hidden = demo || !owner;
    const al = $('l-alerts'); al.replaceChildren();
    if (!s.notifications.length) al.appendChild(el('li', { cls: 'empty', text: 'No alerts queued.' }));
    s.notifications.forEach((n) => al.appendChild(el('li', {}, [el('span', { text: n.subject }),
      el('span', { cls: 'meta' }, [pill(n.status, toneFor(n.status)), pill(n.severity, toneFor(n.severity)), el('span', { text: when(n.at) })])])));

    // Configuration + secrets
    fill('t-config', s.configuration.map((c) => el('tr', {}, [el('td', {}, [el('span', { cls: 'mono', text: c.key }), el('span', { cls: 'sub', text: c.description })]),
      td(typeof c.value === 'string' ? c.value : JSON.stringify(c.value), 'mono')])), 2);
    fill('t-secrets', s.secrets.map((x) => el('tr', {}, [td(x.name, 'mono'), td(x.stored_in.replace(/_/g, ' ')), tdNode(pill(x.is_set ? 'set' : 'not set', x.is_set ? 'ok' : 'neutral'))])), 3);
  }

  // ------------------------------------------------------------------ flow
  async function load() {
    try {
      const snap = demo ? await (await fetch('fixtures/demo-snapshot.json', { cache: 'no-store' })).json() : await rpc('mos_console_snapshot');
      if (snap && snap.ok === false) { showError(`Access refused: ${snap.reason}`); return; }
      render(snap);
    } catch (e) { showError(e.message); if (e.auth) route(); }
  }

  function route() {
    const signedIn = demo || !!session();
    $('login').hidden = signedIn;
    $('desk').hidden = !signedIn;
    $('signout').hidden = demo || !signedIn;
    $('demo-banner').hidden = !demo;
    if (signedIn) load();
  }

  $('login-form').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    try { await signIn($('email').value.trim(), $('password').value); $('password').value = ''; showError(''); route(); }
    catch (e) { showError(e.message); }
  });
  $('signout').addEventListener('click', () => { setSession(null); route(); });
  $('stop-all').addEventListener('click', () => act('mos_kill_switch_disable_all', { p_reason: 'Stop everything (console)' }, 'Disable every enabled kill switch now?'));
  $('run-health').addEventListener('click', () => act('mos_health_check', {}));
  $('test-alert').addEventListener('click', () => act('mos_queue_test_alert', {}, 'Queue a [TEST] alert to the owner? It is sent only when the alert dispatcher is enabled.'));

  route();
  if (!demo) setInterval(() => { if (session() && !document.hidden) load(); }, 60000);
})();
