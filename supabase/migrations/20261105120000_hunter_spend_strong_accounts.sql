-- 5 Nov 2026 (Adam: "Use Hunter actively for project briefs, Top 5, Next 20, high-score opportunities ... Do not spend it on weak
-- accounts"). email_verification_queue: hotels, resorts, aviation and other hospitality suppliers are skipped unless the account is a
-- BUYER or DISTRIBUTION_PARTNER, and accounts with an internal opportunity brief go first after work-order targets.
do $patch$
declare src text := pg_get_functiondef('public.email_verification_queue(integer)'::regprocedure);
  a1 text := $a$and relationship_state(c.id) = 'COLD' and outreach_spend_ok(c.id)$a$;
  b1 text := $a$and relationship_state(c.id) = 'COLD' and outreach_spend_ok(c.id)
       -- Adam, 5 Nov: Hunter is spent on strong accounts only; hotels, resorts and aviation are suppliers unless classed as buyers
       and not (coalesce(c.commercial_class, '') not in ('BUYER', 'DISTRIBUTION_PARTNER')
                and coalesce(c.company_type, '') ~* '(hotel|resort|aviation|serviced|villa operator|hospitality group)')$a$;
  a2 text := $a$(q.company_id in (select w.company_id from work_order_targets() w)) desc,$a$;
  b2 text := $a$(q.company_id in (select w.company_id from work_order_targets() w)) desc,
                 (q.company_id in (select d.company_id from studio_documents d where d.doc_type = 'OPPORTUNITY_NOTE' and d.status <> 'SUPERSEDED')) desc,$a$;
begin
  if strpos(src, a1) = 0 then raise exception 'email_verification_queue changed: anchor 1 not found'; end if;
  if strpos(src, a2) = 0 then raise exception 'email_verification_queue changed: anchor 2 not found'; end if;
  execute replace(replace(src, a1, b1), a2, b2);
end
$patch$;
