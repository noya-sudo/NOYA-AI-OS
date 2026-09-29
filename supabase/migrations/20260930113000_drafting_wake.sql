-- Workflow 14 becomes event-driven: an HQ draft request (or a retry) wakes the drafting worker once
-- through its n8n webhook, instead of polling every 15 minutes. The call is asynchronous (pg_net),
-- carries no data (the worker claims requests from Supabase itself) and a failed wake only delays the
-- draft until the next safety sweep (12:05 and 18:05 Cairo).
--
-- Requires two Vault secrets, created once outside migrations (values are never committed):
--   select vault.create_secret('<token>', 'n8n_draft_wake_token', '...');
--   select vault.create_secret('https://noyaprivate.app.n8n.cloud/webhook/<path>', 'n8n_draft_wake_url', '...');
-- The same token is checked by the "Wake Token Valid?" node in workflow 14.
create or replace function public.hq_wake_drafting()
returns void language plpgsql volatile security definer set search_path = public, extensions as $$
declare v_url text; v_tok text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'n8n_draft_wake_url';
  select decrypted_secret into v_tok from vault.decrypted_secrets where name = 'n8n_draft_wake_token';
  if v_url is null or v_tok is null then return; end if;
  -- Asynchronous (pg_net): the request is queued after commit; HQ never waits on n8n, and a failed
  -- wake only delays the draft until the next safety sweep.
  perform net.http_post(url := v_url, body := jsonb_build_object('wake', 'message_drafts'),
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-noya-wake', v_tok), timeout_milliseconds := 5000);
exception when others then
  return;
end $$;
revoke all on function public.hq_wake_drafting() from public, anon, authenticated;

do $$
declare d text;
begin
  d := pg_get_functiondef('public.hq_request_draft(text,text,text,uuid,uuid,uuid,uuid,text)'::regprocedure);
  if d not like '%hq_wake_drafting()%' then
    d := replace(d, $x$  perform hq_audit('DRAFT_REQUESTED', p_opportunity,$x$, $x$  perform hq_wake_drafting();
  perform hq_audit('DRAFT_REQUESTED', p_opportunity,$x$);
    if d not like '%hq_wake_drafting()%' then raise exception 'patch 1 failed'; end if;
    execute d;
  end if;
  d := pg_get_functiondef('public.hq_draft_action(uuid,text,text)'::regprocedure);
  if d not like '%hq_wake_drafting()%' then
    d := replace(d, $x$  perform hq_audit('DRAFT_' || v_a, null,$x$, $x$  if v_a = 'RETRY' then perform hq_wake_drafting(); end if;
  perform hq_audit('DRAFT_' || v_a, null,$x$);
    if d not like '%hq_wake_drafting()%' then raise exception 'patch 2 failed'; end if;
    execute d;
  end if;
end $$;
