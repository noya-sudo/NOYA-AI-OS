-- 5 Nov 2026: a Studio document may carry a visual concept built outside the PDF renderer (content.visual.url, e.g. a Gamma
-- document with labelled concept visualisations). hq_studio exposes it as design_url; the Studio card shows "Open concept".
do $patch$
declare src text := pg_get_functiondef('public.hq_studio()'::regprocedure);
  a1 text := $a$case when sd.doc_type = 'OPPORTUNITY_NOTE' then sd.content->'brief' end brief,$a$;
  b1 text := $a$case when sd.doc_type = 'OPPORTUNITY_NOTE' then sd.content->'brief' end brief, sd.content->'visual'->>'url' design_url,$a$;
  a2 text := $a$'brief', d.brief$a$;
  b2 text := $a$'brief', d.brief, 'design_url', d.design_url$a$;
begin
  if strpos(src, a1) = 0 or strpos(src, a2) = 0 then raise exception 'hq_studio changed: anchor not found'; end if;
  execute replace(replace(src, a1, b1), a2, b2);
end
$patch$;
