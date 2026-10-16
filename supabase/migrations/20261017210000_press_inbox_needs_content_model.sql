-- Press / media inboxes only for a recorded content partnership (17 Oct 2026, with OFFICIAL_PUBLISHED_INBOX).
-- contact_email_route already kept partnership pitches away from press / PR inboxes, but a company with no partnership
-- model recorded was treated as CONTENT_TALENT, so J.P. Morgan, KKR, Apex, Manchester City and Pacaso would have been
-- pitched through their press office. An unknown model no longer counts as content.

do $p$
declare d text;
begin
  d := pg_get_functiondef('contact_email_route'::regproc);
  if strpos(d, $r$coalesce(c.partnership_model, 'CONTENT_TALENT') <> 'CONTENT_TALENT'$r$) > 0 then
    d := replace(d, $r$coalesce(c.partnership_model, 'CONTENT_TALENT') <> 'CONTENT_TALENT'$r$, $r$coalesce(c.partnership_model, '') <> 'CONTENT_TALENT'$r$);
    if strpos(d, $r$coalesce(c.partnership_model, '') <> 'CONTENT_TALENT'$r$) = 0 then raise exception 'contact_email_route press anchor not found'; end if;
    execute d;
  end if;
end $p$;

-- Saint + Sofia: the recorded outreach angle is an editorial production concept, so the model is content (inferred, labelled).
update companies set partnership_model = 'CONTENT_TALENT',
       partnership_model_source = 'Inferred 17 Oct 2026 from the recorded outreach angle (editorial fashion shoot produced in Egypt)'
 where name = 'Saint + Sofia' and partnership_model is null;
