-- Destination Egypt hosting rule (Adam, 19 Oct 2026): "Hosting is NOT automatically free. Never offer a free trip in cold
-- outreach by default. Any spend / complimentary commitment requires Adam approval."
-- A drafter-written email that offers a complimentary trip, stay, FAM visit or hosting to a company NOYA is not yet in a live
-- conversation with is moved to "edit before approving" with the reason. Nothing is deleted and nothing is sent. Adam's own edits
-- (a reviewed draft) and warm conversations (interested, call, proposal, negotiation, won) are left alone.
create or replace function outreach_hosting_guard() returns trigger
language plpgsql set search_path = public as $$
declare
  v_hit text;
begin
  if new.reviewed_at is not null or new.review_action is not null or new.status not in ('READY', 'REVIEW_REQUIRED') then
    return new;
  end if;
  v_hit := substring(lower(coalesce(new.subject, '') || ' ' || coalesce(new.draft, '')) from
    '(complimentary|free of charge|at no cost|at our expense|all[- ]expenses?[- ]paid|fully hosted|fam trip|familiari[sz]ation trip|free (trip|stay|stays|night|nights|visit|flight|flights|weekend)|(trip|stay|weekend|nights?|dinner) (is |would be |will be )?on us|be our guests?|host (you|your team|your founders|your members|your advisors|your planners))');
  if v_hit is null then
    return new;
  end if;
  if exists (select 1 from opportunities o where o.id = new.opportunity_id
               and o.status in ('INTERESTED', 'CALL_REQUIRED', 'PROPOSAL', 'NEGOTIATION', 'WON')) then
    return new;
  end if;
  new.status := 'REVIEW_REQUIRED';
  new.qa_status := 'DRAFT_REVIEW_REQUIRED';
  new.qa_issues := coalesce(new.qa_issues, '[]'::jsonb)
    || jsonb_build_array('HOSTING_OFFER_IN_COLD_OUTREACH: "' || v_hit || '" (hosting is never offered cold, remove it or get Adam''s approval of the commercial case)');
  return new;
end $$;

revoke all on function outreach_hosting_guard() from public, anon, authenticated;

create or replace trigger outreach_hosting_guard
  before insert or update of subject, draft, status on outreach_candidates
  for each row execute function outreach_hosting_guard();

comment on function outreach_hosting_guard() is 'Destination Egypt hosting rule (19 Oct 2026): cold drafts that offer complimentary trips, stays, FAM visits or hosting go to edit-before-approving with the reason. Reviewed drafts and warm conversations are untouched.';
