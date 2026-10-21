-- Follow up / Reopen (frozen) — production defect fix, 21 Oct daily check.
-- A relationship closed in commercial_next_moves, or marked not relevant in relationship_reviews, after their last message (for
-- example a supplier's one-off answer to a NOYA enquiry, or an emoji reaction after a decline) still showed as a reply owed,
-- because those decisions applied only when NOYA wrote last. A close or a not-relevant mark recorded after their last message now
-- wins; if they write again, the decision is older than their message and the reply owed comes back. Nothing else changes.
-- (Applied in two steps on 21 Oct; this is the resulting single change.)
do $do$
declare v text; w text;
begin
  v := pg_get_functiondef('public.follow_up_assess(uuid,uuid,text)'::regprocedure); w := v;
  v := replace(v, $o$  elsif v_declined is not null and not v_them then$o$,
                  $n$  elsif v_declined is not null and (not v_them or v_declined = 'This relationship was closed'
         or exists (select 1 from relationship_reviews rv where rv.key = v_key and rv.status = 'NOT_RELEVANT' and rv.status_at > coalesce(v_in, '-infinity'::timestamptz))) then$n$);
  if v = w then raise exception 'follow_up_assess close patch not applied'; end if;
  execute v;
end $do$;
