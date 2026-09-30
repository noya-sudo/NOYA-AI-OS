-- Software-cost reconciliation from real evidence (NOYA's own Gmail, searched 30 Sep 2026).
-- Nothing is estimated: an amount stays NULL (UNKNOWN) until an invoice or plan page gives it.
-- Adam can now correct any row from HQ (hq_service_update), audited.

alter table public.system_services add column if not exists scale_risk text;
alter table public.system_services add column if not exists downgrade_note text;

update public.system_services set
  current_plan = 'Free plan — 50 credits a month (renews monthly)', cost_type = 'USAGE_LIMITED', monthly_cost = 0,
  usage_limit = '50 credits / month', verified = true,
  verification_note = 'Hunter email to noya@, 27 Sep 2026: "Your credits have been renewed: you now have 50 credits ready to use on your Free plan."',
  scale_risk = 'Projected ~60 email checks a month (05) against 50 free credits: finding/verification stops late in the month. More volume needs a paid plan (approval gate).',
  downgrade_note = 'Already on the free plan.', updated_at = now()
where service = 'Hunter';

update public.system_services set
  current_plan = 'Free credits (allowance not stated in the email)', cost_type = 'USAGE_LIMITED', monthly_cost = 0, verified = true,
  usage_limit = 'Free credit allowance; 50% used by 23 Sep 2026',
  verification_note = 'Firecrawl email to noya@, 23 Sep 2026: "You''ve used 50% of your Firecrawl credits" / "Boost your free credits to 1500".',
  scale_risk = '~180 website reads a month projected. When the free credits run out, research falls back to search results only (shallower, not broken).',
  downgrade_note = 'Already free. Could be removed if research depth is not needed; discovery continues on Serper.', updated_at = now()
where service = 'Firecrawl';

update public.system_services set
  current_plan = 'Business Standard — monthly invoice, charged automatically', cost_type = 'FIXED_MONTHLY', monthly_cost = null, verified = false,
  verification_note = 'Plan confirmed by Google emails (activated 8 Dec 2025; monthly invoices to 1 Sep 2026, invoice 5669140503). The amount is only in the PDF invoice — Admin console → Billing. Card payments were declined on 1 Dec 2025 and 1 Jan, 1 Mar, 1 Apr, 1 May, 1 Jun 2026 (Visa 7570 / 1887); no decline notice since 1 Jun.',
  scale_risk = 'Per-user pricing: cost only grows with new mailboxes. Declined card payments are the real risk — a lapse stops drafts, sends and reply tracking.',
  downgrade_note = 'Keep (core). Check the number of paid users matches the people who actually need a mailbox.', updated_at = now()
where service = 'Google Workspace (noya@noyaconcierge.com)';

update public.system_services set
  verification_note = 'Check n8n → Settings → Usage and plan. noya@ holds no n8n invoice. It shows two earlier trials that ended without an upgrade (workspace "noya", Nov 2025; workspace "noyaconcierge", ended 14 Aug 2026). The live instance noyaprivate.app.n8n.cloud is therefore billed to another account — or is itself a trial.',
  scale_risk = 'Plan is usually priced by executions. Reply tracking alone is ~2,880 runs a month; history sync ~180; drafting ~60 plus requests; discovery and briefs on top.',
  downgrade_note = 'If the plan is execution-limited: reply tracking every 30 minutes instead of 15 halves its ~2,880 runs with little business impact.', updated_at = now()
where service = 'n8n Cloud';

update public.system_services set
  verification_note = 'No Serper sign-up or billing email in noya@ (searched 30 Sep 2026): the account is under another email. ~2,000 searches a month at the current throttle.',
  scale_risk = 'Highest-volume paid-per-use service: ~2,061 searches a month projected. Cost scales directly with discovery volume.',
  downgrade_note = 'Lower the discovery throttle if replies do not justify the volume.', updated_at = now()
where service = 'Serper';

update public.system_services set
  downgrade_note = 'Remove from the register or leave unfunded: no automatic workflow uses it.', updated_at = now()
where service = 'Anthropic API';

update public.system_services set
  downgrade_note = 'Data already stale; 3 accounts connected on a 1-account free plan. Retire unless marketing reporting is revived.', updated_at = now()
where service = 'Windsor.ai';

update public.system_services set
  scale_risk = 'Credits are included in the n8n plan; allowance UNKNOWN. AI calls grow with discovery, drafting and relationship summaries (15 a day at most).', updated_at = now()
where service = 'n8n AI gateway credits';

insert into public.system_services (service, purpose, used_by, owner, current_plan, cost_type, monthly_cost, currency, usage_cost, usage_limit,
  breaks_if_removed, alternative, credentials_location, verified, verification_note, status, scale_risk, downgrade_note)
select 'Stripe (NOYA payments)', 'Takes client card payments; Stripe charges fees per transaction', 'Adam / finance (not connected to HQ)', 'Adam',
  'Standard pay-per-transaction account', 'PAY_AS_YOU_GO', null, null, 'Per-transaction fees; monthly tax invoice in the Stripe Dashboard', null,
  'Clients cannot pay by card', 'Bank transfer', 'Stripe account (Adam)', true,
  'Stripe emails to noya@: "A new Noya Concierge tax invoice is available", monthly Aug 2025 – Aug 2026. Amounts are in the Stripe Dashboard.',
  'ACTIVE', 'Grows with revenue only (fees follow payments) — a healthy cost.', 'Keep.'
where not exists (select 1 from public.system_services where service = 'Stripe (NOYA payments)');

insert into approval_audit (action, result, actor, detail)
values ('COST_RECONCILIATION', 'OK', 'system (evidence from noya@ Gmail)',
        jsonb_build_object('updated', array['Hunter', 'Firecrawl', 'Google Workspace', 'n8n Cloud', 'Serper'], 'added', array['Stripe (NOYA payments)'],
                           'note', 'Amounts never estimated; UNKNOWN stays UNKNOWN.'));

-- Adam corrects a service from an invoice or plan page. Audited; never buys or upgrades anything.
create or replace function public.hq_service_update(p_id uuid, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); v_old system_services%rowtype;
begin
  select * into v_old from system_services where id = p_id;
  if v_old.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  update system_services set
    current_plan = case when p ? 'current_plan' then hq_trim(p->>'current_plan') else current_plan end,
    cost_type = coalesce(nullif(p->>'cost_type', ''), cost_type),
    monthly_cost = case when p ? 'monthly_cost' then nullif(p->>'monthly_cost', '')::numeric else monthly_cost end,
    currency = case when p ? 'currency' then upper(hq_trim(p->>'currency')) else currency end,
    usage_cost = case when p ? 'usage_cost' then hq_trim(p->>'usage_cost') else usage_cost end,
    usage_limit = case when p ? 'usage_limit' then hq_trim(p->>'usage_limit') else usage_limit end,
    renewal_date = case when p ? 'renewal_date' then nullif(p->>'renewal_date', '')::date else renewal_date end,
    verification_note = case when p ? 'verification_note' then hq_trim(p->>'verification_note') else verification_note end,
    verified = coalesce((p->>'verified')::boolean, verified),
    status = coalesce(nullif(p->>'status', ''), status),
    updated_at = now()
  where id = p_id;
  perform hq_audit('SERVICE_UPDATE', null, jsonb_build_object('service', v_old.service, 'changes', p,
    'before', jsonb_build_object('plan', v_old.current_plan, 'cost_type', v_old.cost_type, 'monthly_cost', v_old.monthly_cost, 'currency', v_old.currency)));
  return jsonb_build_object('ok', true);
exception when check_violation or invalid_text_representation or datetime_field_overflow or invalid_datetime_format
  then return jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
end $$;
revoke all on function public.hq_service_update(uuid, jsonb) from public, anon;
grant execute on function public.hq_service_update(uuid, jsonb) to authenticated;
