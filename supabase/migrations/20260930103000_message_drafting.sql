-- Workflow 14 (message drafting) server side. Service role only (n8n); never callable from the browser.
-- Claims up to p_limit REQUESTED drafts (and DRAFTING ones stuck for 30+ minutes), marks them DRAFTING,
-- and returns only the minimal context stored at request time. Completion writes READY or
-- PROVIDER_UNAVAILABLE. Nothing here sends anything.
create or replace function public.message_draft_claim(p_limit int default 5)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v jsonb;
begin
  with c as (
    select id from message_drafts
     where (status = 'REQUESTED' or (status = 'DRAFTING' and requested_at < now() - interval '30 minutes'))
       and attempts < 3
     order by requested_at
     limit greatest(1, least(coalesce(p_limit, 5), 20))
     for update skip locked
  ), u as (
    update message_drafts d set status = 'DRAFTING', attempts = d.attempts + 1
      from c where d.id = c.id
    returning d.id, d.channel, d.voice, d.message_type, d.context, d.adam_note, d.attempts
  )
  select coalesce(jsonb_agg(to_jsonb(u)), '[]'::jsonb) into v from u;
  return jsonb_build_object('drafts', v);
end $$;

create or replace function public.message_draft_complete(p_id uuid, p_status text, p_draft text, p_issues jsonb default null, p_model text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
begin
  if upper(p_status) not in ('READY', 'PROVIDER_UNAVAILABLE') then return jsonb_build_object('ok', false, 'reason', 'INVALID_STATUS'); end if;
  update message_drafts set status = upper(p_status), draft = nullif(btrim(coalesce(p_draft, '')), ''), quality_issues = p_issues,
         model = p_model, completed_at = now()
   where id = p_id and status = 'DRAFTING';
  if not found then return jsonb_build_object('ok', false, 'reason', 'NOT_DRAFTING'); end if;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.message_draft_claim(int) from public, anon, authenticated;
revoke all on function public.message_draft_complete(uuid, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.message_draft_claim(int) to service_role;
grant execute on function public.message_draft_complete(uuid, text, text, jsonb, text) to service_role;
