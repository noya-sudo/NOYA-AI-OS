-- LinkedIn requests from Adam's own data download (29 Oct, commercial wrap-up, section 12): Invitations.csv lists the requests
-- still pending, both ways. HQ shows REQUEST PENDING (Adam sent it: never send another) and REQUEST RECEIVED (they asked Adam:
-- a warm route, accept first). Read-only history like the rest of the archive: no cookies, no scraping, nothing sent.
-- The columns li_invite_state / li_invite_at / li_invite_message are added in 20261029090000_commercial_intelligence_wrapup.sql.

create or replace function public.hq_import_linkedin_invitations(p_rows jsonb, p_reset boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); r jsonb; v_url text; v_state text; v_id uuid; v_ins boolean;
        v_new int := 0; v_upd int := 0; v_skip int := 0; v_cleared int := 0; v_ids uuid[] := '{}';
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 2000 then return jsonb_build_object('ok', false, 'reason', 'INVALID_ROWS'); end if;
  -- A request that is no longer pending (accepted, withdrawn or ignored) drops out of LinkedIn's file, so the first batch of an
  -- upload clears the old flags and the file sets them again.
  if p_reset then
    update linkedin_connections set li_invite_state = null, li_invite_at = null, li_invite_message = null, updated_at = now()
     where li_invite_state is not null;
    get diagnostics v_cleared = row_count;
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_url := linkedin_canonical_url(r->>'url');
    v_state := case upper(coalesce(r->>'direction', '')) when 'OUTGOING' then 'SENT_PENDING' when 'INCOMING' then 'RECEIVED_PENDING' end;
    if v_url is null or v_state is null then v_skip := v_skip + 1; continue; end if;
    insert into linkedin_connections (first_name, last_name, profile_url, connected, li_invite_state, li_invite_at, li_invite_message)
    values (hq_trim(r->>'first_name'), hq_trim(r->>'last_name'), v_url, false, v_state,
            case when r->>'sent_at' ~ '^\d{4}-\d{2}-\d{2}' then (r->>'sent_at')::timestamptz end, left(hq_trim(r->>'message'), 600))
    on conflict (profile_url) do update set
      li_invite_state = case when linkedin_connections.connected then null else excluded.li_invite_state end,
      li_invite_at = excluded.li_invite_at, li_invite_message = excluded.li_invite_message,
      first_name = coalesce(linkedin_connections.first_name, excluded.first_name),
      last_name = coalesce(linkedin_connections.last_name, excluded.last_name), updated_at = now()
    returning id, (xmax = 0) into v_id, v_ins;
    if v_ins then v_new := v_new + 1; else v_upd := v_upd + 1; end if;
    v_ids := v_ids || v_id;
  end loop;
  perform linkedin_match_all(v_ids);
  perform hq_audit('LINKEDIN_INVITATIONS_IMPORT', null, jsonb_build_object('rows', jsonb_array_length(p_rows), 'new', v_new, 'updated', v_upd,
    'skipped', v_skip, 'cleared', v_cleared));
  return jsonb_build_object('ok', true, 'new', v_new, 'updated', v_upd, 'skipped', v_skip, 'cleared', v_cleared);
end $$;
revoke all on function public.hq_import_linkedin_invitations(jsonb, boolean) from public, anon;
grant execute on function public.hq_import_linkedin_invitations(jsonb, boolean) to authenticated;

-- The LinkedIn page and the connection drawer show the request state; people with a pending request are listed.
do $patch$
declare src text := pg_get_functiondef('public.hq_directory()'::regprocedure);
  a1 text := $a$'li_state', l.li_state, 'li_reason', l.li_state_reason,$a$;
  b1 text := $a$'li_state', l.li_state, 'li_invite', l.li_invite_state, 'li_invite_at', l.li_invite_at, 'li_reason', l.li_state_reason,$a$;
  a2 text := $a$        or l.review_reason is not null), '[]'::jsonb),$a$;
  b2 text := $a$        or l.review_reason is not null or l.li_invite_state is not null), '[]'::jsonb),$a$;
begin
  if strpos(src, $a$'li_invite', l.li_invite_state$a$) > 0 then return; end if;
  if strpos(src, a1) = 0 or strpos(src, a2) = 0 then raise exception 'hq_directory() changed: anchors not found'; end if;
  execute replace(replace(src, a1, b1), a2, b2);
end $patch$;
