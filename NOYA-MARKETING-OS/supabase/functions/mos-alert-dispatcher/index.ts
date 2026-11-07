// NOYA Marketing OS — critical alert dispatcher (Supabase Edge Function). PREPARED, NOT DEPLOYED.
//
// Sends pending gov.notifications to the owner through Resend (decision D6).
// * Runs as the least-privileged database role `mos_dispatcher`: it can only claim and mark notifications.
// * Sends nothing unless gov.configuration 'alerts.enabled' = true (enforced in the database).
// * Uses its OWN send-only Resend key (MOS_RESEND_API_KEY) and sender (MOS_ALERT_FROM); never HQ's keys or senders.
// * Idempotency-Key = notification id, so a retry can never send a duplicate.
// * Test notifications carry "[TEST]" in the subject (database check constraint).
//
// Secrets (Supabase Edge Function secrets, never in git):
//   MOS_RESEND_API_KEY      send-only key restricted to noyaconcierge.com
//   MOS_DISPATCH_TOKEN      shared token the scheduler sends in x-mos-dispatch-token
// Non-secret:
//   MOS_ALERT_FROM          e.g. "NOYA Marketing OS <mos-alerts@noyaconcierge.com>"
// Provided by Supabase: SUPABASE_DB_URL
import postgres from 'npm:postgres@3.4.4';

const DISPATCHER = 'dispatcher.resend';

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

Deno.serve(async (req: Request) => {
  const token = Deno.env.get('MOS_DISPATCH_TOKEN') ?? '';
  const given = req.headers.get('x-mos-dispatch-token') ?? '';
  if (!token || !timingSafeEqual(token, given)) return new Response('forbidden', { status: 403 });

  const apiKey = Deno.env.get('MOS_RESEND_API_KEY');
  const from = Deno.env.get('MOS_ALERT_FROM');
  const dbUrl = Deno.env.get('SUPABASE_DB_URL');
  if (!apiKey || !from || !dbUrl) return Response.json({ ok: false, reason: 'dispatcher not configured' }, { status: 503 });

  const sql = postgres(dbUrl, { max: 1, prepare: false });
  const report: Array<{ id: string; sent: boolean }> = [];
  try {
    const claimed = await sql.begin(async (tx) => {
      await tx`set local role mos_dispatcher`;
      const [{ r }] = await tx`select public.mos_dispatcher_claim(${DISPATCHER}, 10) as r`;
      return r;
    });
    if (!claimed?.ok) return Response.json(claimed ?? { ok: false }, { status: 409 });

    for (const n of claimed.notifications as Array<{ id: string; subject: string; body: string; to: string; is_test: boolean }>) {
      let sent = false; let providerId: string | null = null; let error: string | null = null;
      try {
        if (!n.to) throw new Error('no active owner email');
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'Idempotency-Key': `mos-${n.id}` },
          body: JSON.stringify({ from, to: [n.to], subject: n.subject, text: n.body,
                                 tags: [{ name: 'system', value: 'marketing-os' }, { name: 'test', value: String(n.is_test) }] }),
        });
        const body = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(`resend ${res.status}: ${body?.message ?? 'error'}`);
        sent = true; providerId = body?.id ?? null;
      } catch (e) {
        error = String((e as Error).message ?? e).slice(0, 500);
      }
      await sql.begin(async (tx) => {
        await tx`set local role mos_dispatcher`;
        await tx`select public.mos_dispatcher_result(${DISPATCHER}, ${n.id}::uuid, ${sent}, ${providerId}, ${error})`;
      });
      report.push({ id: n.id, sent });
    }
    return Response.json({ ok: true, processed: report.length, report });
  } finally {
    await sql.end({ timeout: 5 });
  }
});
