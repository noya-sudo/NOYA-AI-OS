-- Duplicate open outreach tasks found in the HQ audit (30 Sep 2026).
-- The curated 29 Sep import created OUTREACH_READY tasks; Workflow 05 then created its own
-- approval / contact task on the same opportunity because its dedupe check did not know the
-- OUTREACH_READY type (fixed in 05 the same day). Keep 05's task (it carries the provider-
-- verified recipient and the channel decision), copy the curated research/draft into it,
-- and cancel the curated task. Opportunities with only the curated task are untouched.
with dup as (
  select k.id as keep_id, d.id as drop_id, d.description as drop_desc
  from tasks d
  join lateral (
    select x.id from tasks x
    where x.opportunity_id = d.opportunity_id and x.id <> d.id
      and x.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
      and x.task_type in ('SALES_OUTREACH_APPROVAL', 'CONTACT_RESOLUTION')
      and x.created_by like '05 -%'
    order by (x.task_type = 'SALES_OUTREACH_APPROVAL') desc, x.created_at desc
    limit 1
  ) k on true
  where d.task_type = 'OUTREACH_READY' and d.status in ('OPEN', 'IN_PROGRESS', 'WAITING')
), keep as (
  update tasks t
     set description = t.description || E'\n\n--- ORIGINAL RESEARCH NOTES ---\n' || coalesce(dup.drop_desc, '')
    from dup where t.id = dup.keep_id and t.description not like '%--- ORIGINAL RESEARCH NOTES ---%'
  returning t.id
)
update tasks t
   set status = 'CANCELLED',
       description = coalesce(t.description, '') || E'\n\nMERGED 30 Sep 2026 into task ' || dup.keep_id
                     || ' (Workflow 05 task for the same opportunity). Curated notes copied there.'
  from dup where t.id = dup.drop_id;
