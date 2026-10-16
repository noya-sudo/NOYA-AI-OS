-- The planner's 30-day "already planned" exclusion counted dry-run candidates, so a dry run silently blocked its
-- companies from the live plan for 30 days (17 Oct 2026: the 20 companies of a dry run, all five Brands official-inbox
-- routes among them, were left out of the live plan). Dry runs no longer count; today's dry-run rows are closed as
-- SKIPPED (kept, not deleted).

do $p$
declare d text;
begin
  d := pg_get_functiondef('commercial_director_plan'::regproc);
  if strpos(d, $r$oc.status <> 'SKIPPED' and not oc.dry_run and oc.created_at > now() - interval '30 days'$r$) = 0 then
    d := replace(d, $r$oc.status <> 'SKIPPED' and oc.created_at > now() - interval '30 days'$r$,
                    $r$oc.status <> 'SKIPPED' and not oc.dry_run and oc.created_at > now() - interval '30 days'$r$);
    if strpos(d, $r$oc.status <> 'SKIPPED' and not oc.dry_run and oc.created_at > now() - interval '30 days'$r$) = 0 then
      raise exception 'commercial_director_plan 30-day anchor not found';
    end if;
    execute d;
  end if;
end $p$;

update outreach_candidates set status = 'SKIPPED', hold_reason = 'DRY_RUN', updated_at = now()
 where dry_run and status = 'PLANNED';
