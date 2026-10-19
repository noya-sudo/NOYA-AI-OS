-- Production defect (found 19 Oct 2026): since Adam's 17 Oct decision an inbox the company publishes on its own official
-- website (email_official_inboxes, not revoked) may be outreach-ready without Hunter, with Adam approving every email.
-- outreach_desk() labelled those routes OFFICIAL_PUBLISHED_INBOX but still bucketed their EMAIL READY drafts as RESEARCHING
-- ("not verifiable as valid"), so 17 quality-passed drafts never reached Adam. The bucket and the reason now treat an
-- official published inbox like a verified address. Nothing sends: approval still creates an unsent Gmail draft.
do $patch$
declare src text := pg_get_functiondef('public.outreach_desk()'::regprocedure);
  a1 text := $a$when t.title ~ '^EMAIL READY' and t.r_state = 'VALID_VERIFIED' then 'NEEDS_REVIEW'$a$;
  b1 text := $a$when t.title ~ '^EMAIL READY' and (t.r_state = 'VALID_VERIFIED' or t.r_official) then 'NEEDS_REVIEW'$a$;
  a2 text := $a$when t.title ~ '^EMAIL READY' and t.r_state <> 'VALID_VERIFIED' then$a$;
  b2 text := $a$when t.title ~ '^EMAIL READY' and t.r_state <> 'VALID_VERIFIED' and not t.r_official then$a$;
begin
  if strpos(src, b1) > 0 then return; end if;  -- already applied
  if strpos(src, a1) = 0 or strpos(src, a2) = 0 then raise exception 'outreach_desk() changed: patch anchors not found'; end if;
  execute replace(replace(src, a1, b1), a2, b2);
end $patch$;
