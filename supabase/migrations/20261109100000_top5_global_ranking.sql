-- 9 Nov 2026 (Adam): the CEO Top 5 is ranked globally, not one per Director.
-- Directors still keep their own top 3 projects (director_projects). A weaker account must not enter
-- Adam's Top 5 just to give every Director a slot.
-- Ranking factors: warmth/response, project potential, distribution power, why-now, verified contact,
-- decision maker, Egypt relevance, repeat value, brief on file. Adds two terms to the existing score:
--   vc   = verified email route (+6)
--   dist = distribution partner (+6) or strong network score (+4)
-- Next 20 is unchanged (it already excludes the Top 5 and caps four per Director).
-- Idempotent patch of the live function (same pattern as earlier patches).
do $patch$
declare
  v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'outreach_top5';
  if strpos(v_def, 'ranked globally (Adam, 9 Nov)') > 0 then return; end if;
  if strpos(v_def, 'from (select * from r where per_dir <= 1 order by score desc limit 5) q') = 0
     or strpos(v_def, 'c.partnership_model pm,') = 0
     or strpos(v_def, E'then 15 else 0 end chan\n      from s where') = 0
     or strpos(v_def, 'case when chan >= 15 then ''project brief on file'' end,') = 0 then
    raise exception 'anchor not found in outreach_top5';
  end if;
  v_new := replace(v_def, 'c.partnership_model pm,', 'c.partnership_model pm, c.commercial_class cc,');
  v_new := replace(v_new, E'then 15 else 0 end chan\n      from s where',
    E'then 15 else 0 end chan,\n      case when s.ch = ''EMAIL'' then 6 else 0 end vc,\n      case when s.cc = ''DISTRIBUTION_PARTNER'' then 6 when coalesce((s.eg->''scores''->>''network'')::numeric, 0) >= 4 then 4 else 0 end dist\n      from s where');
  v_new := replace(v_new, 'potential + warmth + timing + dm + egypt + rep + chan', 'potential + warmth + timing + dm + egypt + rep + chan + vc + dist');
  v_new := replace(v_new, 'case when chan >= 15 then ''project brief on file'' end,', 'case when chan >= 15 then ''project brief on file'' end, case when dist >= 6 then ''distribution partner'' end,');
  v_new := replace(v_new, 'from (select * from r where per_dir <= 1 order by score desc limit 5) q',
    'from (select * from r order by score desc limit 5) q  -- ranked globally (Adam, 9 Nov): no one-per-Director slot; Directors keep their own top 3 projects');
  execute v_new;
end
$patch$;
