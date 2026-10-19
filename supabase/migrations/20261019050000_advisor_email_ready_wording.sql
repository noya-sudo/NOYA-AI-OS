-- Advisor brief said "Email ready: 61 verified prospects", but most of the reserve are official published inboxes, which are
-- outreach-ready without being verified and are never labelled VERIFIED (Adam, 17 Oct). Wording only.
do $do$
declare v_src text := pg_get_functiondef('hq_advisor()'::regprocedure);
  a text := $a$'Email ready: ' || v_er || ' verified prospect'$a$;
  b text := $a$'Email ready: ' || v_er || ' prospect'$a$;
begin
  if (length(v_src) - length(replace(v_src, a, ''))) / length(a) <> 1 then raise exception 'anchor does not match exactly once'; end if;
  execute replace(v_src, a, b);
end $do$;
