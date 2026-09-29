/**
 * Reads the probes and states whether NOYA's providers will actually work for
 * today's agent runs.
 *
 * Since 29 Sep 2026 the operational AI tier is the n8n AI gateway (Gemini 3.1
 * Flash-Lite primary, GPT-5 mini fallback). Anthropic is premium escalation only:
 * its status is reported, but it no longer counts as "down" for NOYA unless the
 * gateway is down too. A successful execution is still not evidence that an agent
 * worked, so the gateway is probed with a real one-token completion.
 */
function readProbe(nodeName) {
  var r = {};
  try { r = $(nodeName).first().json || {}; }
  catch (e) { return { code: 0, detail: 'probe did not run: ' + (e && e.message ? e.message : String(e)) }; }
  var code = Number(r.statusCode);
  var detail = '';
  try { detail = typeof r.body === 'string' ? r.body : JSON.stringify(r.body); }
  catch (e2) { detail = String(r.body); }
  return { code: isFinite(code) ? code : 0, detail: String(detail || '').replace(/\s+/g, ' ').slice(0, 500) };
}
function readGatewayProbe() {
  var r = {};
  try { r = $('Probe AI Gateway (Gemini)').first().json || {}; }
  catch (e) { return { code: 0, detail: 'probe did not run' }; }
  var text = String(r.text || r.output || '').trim();
  if (text) return { code: 200, detail: 'completion ok: ' + text.slice(0, 40) };
  var err = r.error ? String(r.error.message || r.error) : 'empty completion';
  return { code: /quota|credit|billing|insufficient/i.test(err) ? 402 : 0, detail: err.slice(0, 500) };
}

function verdict(p) {
  var d = (p.detail || '').toLowerCase();
  if (p.code >= 200 && p.code < 300) return 'OK';
  if (p.code === 402 || /credit balance|insufficient credit|insufficient fund|insufficient quota|billing|payment required|out of credit/.test(d)) return 'PROVIDER_BILLING_ERROR';
  if (p.code === 401 || p.code === 403 || /unauthori|forbidden|invalid api key|authentication/.test(d)) return 'PROVIDER_AUTH_ERROR';
  if (p.code === 429 || /rate limit|too many requests/.test(d)) return 'PROVIDER_RATE_LIMIT';
  if (p.code >= 500 || p.code === 0) return 'PROVIDER_UNAVAILABLE';
  return 'PROVIDER_ERROR';
}

var probes = [
  { name: 'AI Gateway (Gemini/OpenAI)', tier: 'OPERATIONAL', purpose: 'all AI classification, extraction, drafting and the CEO brief (02-09, 11, 13)', probe: readGatewayProbe() },
  { name: 'Serper', tier: 'OPERATIONAL', purpose: 'all web discovery searches', probe: readProbe('Probe Serper') },
  { name: 'Anthropic', tier: 'PREMIUM_OPTIONAL', purpose: 'premium escalation only (not required for normal operation)', probe: readProbe('Probe Anthropic') }
];

var providers = probes.map(function (p) {
  return { provider: p.name, tier: p.tier, status: verdict(p.probe), http_status: p.probe.code, impact: p.purpose, detail: p.probe.detail };
});

var down = providers.filter(function (p) { return p.status !== 'OK' && p.tier === 'OPERATIONAL'; });
var premiumDown = providers.filter(function (p) { return p.status !== 'OK' && p.tier !== 'OPERATIONAL'; });
var billing = down.filter(function (p) { return p.status === 'PROVIDER_BILLING_ERROR'; });
var today = new Date().toISOString().slice(0, 10);

var title = down.length
  ? 'PROVIDER HEALTH ' + today + ' - ' + down.map(function (p) { return p.provider + ' ' + p.status; }).join(', ')
  : 'PROVIDER HEALTH ' + today + ' - operational providers OK';

var lines = ['Checked at: ' + new Date().toISOString(), ''];
providers.forEach(function (p) {
  lines.push(p.provider + ' [' + p.tier + ']: ' + p.status + ' (HTTP ' + p.http_status + ')');
  lines.push('  Used for: ' + p.impact);
  if (p.status !== 'OK') lines.push('  Provider said: ' + p.detail);
});
lines.push('');
if (billing.length) {
  lines.push('ACTION: ' + billing.map(function (p) { return p.provider; }).join(' and ') + ' is refusing calls for billing reasons. Agents fall back where possible (deterministic CEO brief, human review for replies); nothing is read as commercially rejected.');
} else if (down.length) {
  lines.push('ACTION: review the provider account above before the next scheduled run.');
} else {
  lines.push('No action needed.' + (premiumDown.length ? ' (Premium tier unavailable: ' + premiumDown.map(function (p) { return p.provider + ' ' + p.status; }).join(', ') + ' - informational only.)' : ''));
}

return [{ json: {
  checked_at: new Date().toISOString(),
  check_date: today,
  providers: providers,
  any_provider_down: down.length > 0,
  premium_unavailable: premiumDown.map(function (p) { return p.provider + ':' + p.status; }).join(', '),
  down_providers: down.map(function (p) { return p.provider + ':' + p.status; }).join(', '),
  priority: billing.length ? 98 : (down.length ? 90 : 10),
  title: title,
  description: lines.join('\n')
} }];
