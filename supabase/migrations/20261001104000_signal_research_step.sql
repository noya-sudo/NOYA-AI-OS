-- Research step between a signal and an opportunity: put a named organisation into the CRM (source-backed, no
-- invented people) and raise a "find the decision maker" task. Once a real contact is recorded (Add contact),
-- "Can we reach them?" is answered and the signal can be qualified and promoted.
create or replace function public.hq_signal_org_to_crm(p_org uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_admin text := hq_admin_email(); so signal_organisations%rowtype; i intelligence%rowtype; pb commercial_playbooks%rowtype; v_co uuid; v_task uuid;
begin
  select * into so from signal_organisations where id = p_org; if so.id is null then return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND'); end if;
  select * into i from intelligence where id = so.signal_id;
  select * into pb from commercial_playbooks where code = i.playbook_code;
  v_co := so.company_id;
  if v_co is null then
    insert into companies (name, country, source, notes, relationship_status)
    values (so.org_name, case when i.region = 'EGYPT' and so.org_role in ('VENUE', 'GOVERNMENT', 'HOTEL') then 'Egypt' end, 'Signal: ' || left(i.title, 120),
            'Named in a source-backed signal (' || coalesce(so.source_url, i.source_url, 'no url') || '): "' || coalesce(so.evidence, so.org_name) || '". Provenance: ' || so.provenance || '.', 'prospect')
    returning id into v_co;
    update signal_organisations set company_id = v_co where id = so.id;
  end if;
  if not exists (select 1 from contacts k where k.company_id = v_co and (k.email is not null or k.linkedin is not null)) then
    insert into tasks (company_id, signal_id, title, description, task_type, assigned_to, created_by, priority, status, due_at)
    select v_co, i.id, 'Find decision maker at ' || so.org_name,
           'For "' || i.title || '" (' || lower(so.org_role) || '). Roles: ' || coalesce(array_to_string(pb.decision_roles, ', '), 'commercial lead') ||
           '. Record a person only from a real source (their site, LinkedIn, a press release) with Add contact; an official partnerships inbox also counts.',
           'CONTACT_RESEARCH', owner_for_role('SDR'), 'HQ (signal research)', 72, 'OPEN',
           now() + case signal_urgency(i.event_date, i.event_end, i.category, i.intelligence_type) when 'NOW' then interval '1 day' else interval '3 days' end
    where not exists (select 1 from tasks t where t.company_id = v_co and t.signal_id = i.id and t.task_type = 'CONTACT_RESEARCH' and t.status in ('OPEN', 'IN_PROGRESS'))
    returning id into v_task;
  end if;
  perform hq_audit('SIGNAL_ORG_TO_CRM', null, jsonb_build_object('signal_id', i.id, 'org', so.org_name, 'company_id', v_co, 'task_id', v_task));
  return jsonb_build_object('ok', true, 'company_id', v_co, 'task_id', v_task);
end $$;
revoke all on function public.hq_signal_org_to_crm(uuid) from public, anon;
grant execute on function public.hq_signal_org_to_crm(uuid) to authenticated;

-- The six real signals researched on 30 Sep 2026 for the acceptance scenarios (idempotent: same url + title is reused).
select signal_capture(x, 'Claude (research for Adam, 30 Sep 2026)') from jsonb_array_elements($j$[
 {"title": "HYROX Cairo 2026: HYROX's first race in Egypt, 14–15 November 2026", "type": "SPORTS_EVENT", "destination": "Cairo", "source_name": "HYROX (official event page) / Wego Travel Blog",
  "source_url": "https://hyrox.com/event/hyrox-cairo/",
  "summary": "HYROX, the global fitness-racing series, is making its debut in Egypt with HYROX Cairo on 14–15 November 2026; venue to be announced. The classic format is 8 km of running and 8 functional stations, with Pro, Open, Doubles and Relay divisions. Sources describe athletes coming from across Egypt as well as Saudi Arabia, UAE, Turkey and Europe.",
  "why": "An international sports series entering Egypt for the first time brings international athletes, staff and partners who need accommodation, transport and local support — the Athlete & Team and Event Concierge desks.",
  "relevance": 85, "confidence": 80, "event_date": "2026-11-14", "event_end": "2026-11-15",
  "orgs": [{"name": "HYROX", "role": "ORGANISER", "evidence": "HYROX is making its monumental debut in Cairo (official HYROX event page: HYROX Cairo)"}]},
 {"title": "El Gouna Film Festival 2026 (9th edition) takes place 15–23 October in El Gouna, Red Sea", "type": "FILM_FESTIVAL", "destination": "El Gouna, Red Sea", "source_name": "CairoScene",
  "source_url": "https://cairoscene.com/buzz/el-gouna-film-festival-2026-will-take-place-october-15th-to-23rd",
  "summary": "The ninth edition of El Gouna Film Festival will take place October 15th to 23rd 2026 in El Gouna on Egypt's Red Sea coast, under the motto \"9 Years of Stories\". More than 80 films from around the world have been selected.",
  "why": "A major international film festival brings talent, press, sponsors, agencies and VIP guests to El Gouna for nine days — VIP guest services, accommodation, Cairo–El Gouna travel, sponsor hospitality and talent care.",
  "relevance": 90, "confidence": 85, "event_date": "2026-10-15", "event_end": "2026-10-23",
  "orgs": [{"name": "El Gouna Film Festival", "role": "ORGANISER", "evidence": "El Gouna Film Festival 2026 Will Take Place October 15th to 23rd (CairoScene)"}]},
 {"title": "Starlight Festival: first multi-stage festival at the Pyramids of Giza, 9–10 October 2026 (EXIT Festival)", "type": "MUSIC_FESTIVAL", "destination": "Pyramids of Giza, Cairo", "source_name": "The Rio Times / EDM House Network",
  "source_url": "https://www.riotimesonline.com/starlight-festival-pyramids-giza-9-10-october-2026/",
  "summary": "Starlight Festival comes to Egypt for the first time at the Great Pyramids of Giza: two main nights on 9 and 10 October 2026, with opening and closing events across Cairo on 8 and 11 October. 50+ artists over 3+ stages; the international lineup includes Charlotte de Witte, Michael Bibi, Adriatique, Pete Tong and Vintage Culture. EXIT Festival announced the event.",
  "why": "An international festival with international artists and travelling fans: artist concierge, VIP guest and table handling, transport, security, hotel blocks and sponsor hospitality.",
  "relevance": 85, "confidence": 80, "event_date": "2026-10-09", "event_end": "2026-10-10",
  "orgs": [{"name": "EXIT Festival", "role": "PROMOTER", "evidence": "EXIT Festival Announces Starlight Festival Egypt (EDM House Network)", "source_url": "https://edmhousenetwork.com/exit-festival-announces-starlight-festival-egypt/"}]},
 {"title": "The Oberoi Melouk and Malekat luxury Nile dahabeyas open in Q3 2026 (Luxor–Aswan)", "type": "HOTEL_OPENING", "destination": "Luxor–Aswan, Nile", "source_name": "Egypt Photography Tours (2026 openings round-up)",
  "source_url": "https://www.egyptphotographytours.com/future-tourism-egypt-2026.html",
  "summary": "The Oberoi Melouk and Malekat Luxury Nile Dahabeyas, opening Q3 2026, revive 1920s regal dahabeyas with intimate vessels of seven cabins each, on exclusive itineraries between Luxor and Aswan.",
  "why": "A new ultra-luxury Nile product for NOYA's private clients and partners: preferred rates, private charters, and itineraries for UHNW and incentive groups.",
  "relevance": 70, "confidence": 55,
  "orgs": [{"name": "The Oberoi", "role": "OPERATOR", "evidence": "The Oberoi Melouk and Malekat Luxury Nile Dahabeyas, opening Q3 2026"}]},
 {"title": "DAMAC launches its Cairo sales office and DAMAC Islands 2 with a VIP event at the Grand Egyptian Museum", "type": "BRAND_LAUNCH_EVENT", "destination": "Grand Egyptian Museum, Cairo", "source_name": "Zawya (press release)",
  "source_url": "https://www.zawya.com/en/press-release/companies-news/damac-launches-new-cairo-sales-office-with-a-landmark-event-at-the-grand-egyptian-museum-obcdunz3",
  "summary": "DAMAC marked the inauguration of its new sales office in Egypt and the launch of its master development DAMAC Islands 2 with a celebration at the Grand Egyptian Museum, hosted by Amira Sajwani, Managing Director of DAMAC Properties, for dignitaries, global investors, media, brokers and VIP guests.",
  "why": "An international luxury brand/developer now running VIP launch events in Cairo for international investors — VIP guest hosting, investor travel and a buyer concierge layer for future launches.",
  "relevance": 72, "confidence": 85,
  "orgs": [{"name": "DAMAC Properties", "role": "DEVELOPER", "evidence": "hosted by Amira Sajwani, Managing Director of DAMAC Properties"},
           {"name": "Grand Egyptian Museum", "role": "VENUE", "evidence": "a grand celebration at Cairo's magnificent Grand Egyptian Museum"}]},
 {"title": "Mel Gibson says he is shooting in Egypt as the country opens its doors to global productions", "type": "PRODUCTION_SHOOT", "destination": "Egypt", "source_name": "Egyptian Gazette",
  "source_url": "https://egyptian-gazette.com/entertainment/arts/mel-gibson-goes-viral-as-egypt-opens-doors-to-global-blockbusters/",
  "summary": "Actor and director Mel Gibson wrote on social media: \"We're shooting in Egypt, and it feels like stepping into something eternal.\" The production company and dates are not named in the source.",
  "why": "An international production shooting in Egypt needs crew accommodation, transport and talent care — but the production company is not yet identified.",
  "relevance": 75, "confidence": 60, "orgs": []}
]$j$::jsonb) x;
