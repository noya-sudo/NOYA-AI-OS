-- Private Calendar events are private-travel opportunities, not organiser sales: the radar's
-- keyword classifier had filed Wimbledon, Monaco and the other international events under
-- "International sporting event entering Egypt". One playbook for them, never auto-assigned
-- (no categories or keywords, so playbook_for cannot pick it), and the calendar rows moved
-- onto it. CIFF, El Gouna and Shakira keep their organiser playbooks.
set lock_timeout = '5s';

insert into public.commercial_playbooks (code, name, trigger_desc, categories, keywords, priority, track, owner_role, ideal_prospect,
  decision_roles, product_codes, value_proposition, services, research_questions, outreach_approach, proposal_type, proof_required)
values ('EVENT_TRAVEL', 'Private Calendar event: private travel around it',
  'A major event on the Private Calendar that private clients travel for or host guests at.',
  '{}', '{}', 40, 'SALES', 'SALES',
  'Private clients, executive assistants and family offices who attend the event or host guests there.',
  array['Private client', 'Executive assistant', 'Family office'],
  array['GLOBAL_TRAVEL_LIFESTYLE', 'NOYA_PRIVATE'],
  'One request, one relationship: the travel, stay, tables and access requests around the event coordinated by NOYA, subject to availability.',
  array['Travel and transfers', 'Villa and hotel stays', 'Restaurant and club reservations', 'Access requests (subject to availability)', 'The wider itinerary'],
  array['Which clients or EAs have attended before?', 'Where do they stay, and how early do the best stays go?', 'Which access requests are realistic this year?'],
  'A personal note to existing clients and EAs 8 to 12 weeks before: name the event and offer to plan around it. Never promise access.',
  'Itinerary proposal',
  array['The event page on noyaconcierge.com/calendar'])
on conflict (code) do nothing;

-- Emptied fields are refilled from the new playbook by intelligence_enrich.
update public.intelligence set
  playbook_code = 'EVENT_TRAVEL', product_codes = '{}', decision_roles = '{}', services = '{}',
  commercial_angle = null, problem_noya_solves = null,
  next_action = 'Read the dates on the official page and approve for the Private Calendar; then shortlist the clients and EAs to offer it to.'
where calendar_slug in ('abu-simbel-sun-festival-october-2026', 'art-basel-paris-2026', 'forever-is-now-06', 'abu-dhabi-grand-prix-2026',
  'art-basel-miami-beach-2026', 'french-alps-winter-season-2026-27', 'haute-couture-week-spring-summer-2027',
  'abu-simbel-sun-festival-february-2027', 'paris-fashion-week-womenswear-fall-winter-2027', 'dubai-world-cup-2027',
  'festival-de-cannes-2027', 'monaco-grand-prix-2027', 'uefa-champions-league-final-2027', 'royal-ascot-2027', 'wimbledon-2027')
  and captured_by = 'Claude (Private Calendar launch set, 3 Oct 2026)';

-- CIFF keeps the film-festival playbook; give it the same approval step first.
update public.intelligence set
  next_action = 'Read the dates on the official page and approve for the Private Calendar; then confirm the festival''s guest-relations and hospitality leads.'
where calendar_slug = 'cairo-international-film-festival-2026' and captured_by = 'Claude (Private Calendar launch set, 3 Oct 2026)';
