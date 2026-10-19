-- Destination Egypt conversion sprint (Adam, 19 Oct 2026): "Do not expand the account universe aggressively for the next 7 working
-- days ... QUALIFIED ACCOUNT -> CORRECT PERSON -> EMAIL -> REPLY -> MEETING -> BRIEF. Generate 10-15 serious Destination Egypt
-- conversations from the strongest existing accounts." The Dashboard shows conversion first and research second. No new table,
-- page or agent: the sprint lives in system_config.destination_egypt and the existing mission read model.

update system_config set value = value || jsonb_build_object('sprint', jsonb_build_object(
    'name', 'Destination Egypt conversion sprint', 'started_at', '2026-10-20', 'ends_at', '2026-10-28', 'review_at', '2026-10-29',
    'working_days', 7, 'target_min', 10, 'target_max', 15,
    'path', 'QUALIFIED ACCOUNT -> CORRECT PERSON -> EMAIL -> REPLY -> MEETING -> BRIEF',
    'objective', 'First Destination Egypt project moving toward proposal',
    'priorities', jsonb_build_array('Agencies that can bring multiple brand or client projects', 'Destination wedding planners',
      'Private clubs and member networks with travel behaviour', 'Luxury travel and concierge networks',
      'Brands with proven international campaign or trip behaviour', 'Media and podcast companies with a strong Egypt concept'),
    'research', 'Light only: no aggressive universe expansion during the sprint',
    'emails', 'About 5 excellent new emails a working day plus replies, follow-ups and meeting scheduling. Fewer when there are not five strong targets.'))
 where key = 'destination_egypt';

-- Mission panel (Dashboard), sprint version: conversion first (contacted, replied, positive, meetings, briefs, proposals, won, revenue),
-- research secondary, the sprint's progress toward 10-15 conversations, and the ranked top 20 Destination Egypt buyers.
create or replace function destination_egypt_mission()
returns jsonb language plpgsql stable set search_path = public as $$
declare v jsonb; cfg jsonb := (select value from system_config where key = 'destination_egypt');
begin
  with mo as materialized (
    select distinct on (o.company_id) o.id, o.company_id, o.status, o.egypt, o.next_action, o.next_action_due, o.blocker, o.created_at,
           c.name, c.country, c.universe_status,
           agent_key_of(company_lane(c.acquisition_lane, c.prospect_segment, c.vertical_override, c.company_type), c.company_type, c.notes) director
      from opportunities o join companies c on c.id = o.company_id
     where o.mission = 'DESTINATION_EGYPT' and o.status <> 'ARCHIVED' and coalesce(c.notes, '') not like '%MERGED_INTO:%'
     order by o.company_id, o.created_at desc),
  cf as materialized (select f.* from commercial_facts() f join mo on mo.company_id = f.company_id),
  es as materialized (select mo.company_id, company_email_state(mo.company_id)->>'state' st from mo),
  x as (
    select mo.*, es.st email_state, cf.first_outreach_at, cf.first_reply_at, cf.inbound_first_at, cf.positive_at, cf.meeting_at, cf.brief_at, cf.proposal_at, cf.won_at,
           case when cf.meeting_at is not null then 5 when cf.positive_at is not null then 4 when cf.first_reply_at is not null or cf.inbound_first_at is not null then 3
                when cf.first_outreach_at is not null then 1 else 0 end warmth,
           case when es.st in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL') then 5 when es.st = 'OFFICIAL_PUBLISHED_INBOX' then 4
                when es.st = 'NEEDS_VERIFICATION' then 2 when es.st in ('FINDER_PENDING', 'RESEARCH_PENDING') then 1 else 0 end contact
      from mo left join cf on cf.company_id = mo.company_id left join es on es.company_id = mo.company_id),
  live as (select * from x where status not in ('LOST') and coalesce(universe_status, '') not in ('EXCLUDED', 'PARKED'))
  select jsonb_build_object(
    'name', cfg->>'name', 'question', cfg->>'question', 'started_at', cfg->>'started_at', 'review_by', cfg->>'review_by',
    'funnel', jsonb_build_object(
      'qualified', (select count(*) from live where universe_status = 'QUALIFIED'),
      'email_ready', (select count(*) from live where email_state in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX')),
      'contacted', (select count(*) from x where first_outreach_at is not null),
      'replied', (select count(*) from x where first_reply_at is not null or inbound_first_at is not null),
      'positive', (select count(*) from x where positive_at is not null),
      'meetings', (select count(*) from x where meeting_at is not null),
      'briefs', (select count(*) from x where brief_at is not null),
      'proposals', (select count(*) from x where proposal_at is not null),
      'won', (select count(*) from x where won_at is not null),
      'revenue', coalesce((select jsonb_agg(jsonb_build_object('currency', r.currency, 'amount', r.amount)) from (
          select rv.currency, sum(rv.amount) amount from revenue rv join mo on mo.company_id = rv.company_id
           where rv.payment_status <> 'CANCELLED' group by 1) r), '[]'::jsonb)),
    'sprint', case when cfg->'sprint' is null then null else jsonb_build_object(
        'name', cfg->'sprint'->>'name', 'started_at', cfg->'sprint'->>'started_at', 'ends_at', cfg->'sprint'->>'ends_at', 'review_at', cfg->'sprint'->>'review_at',
        'target_min', (cfg->'sprint'->>'target_min')::int, 'target_max', (cfg->'sprint'->>'target_max')::int,
        'working_days', (cfg->'sprint'->>'working_days')::int,
        'day', (select count(*) from generate_series((cfg->'sprint'->>'started_at')::date, least(current_date, (cfg->'sprint'->>'ends_at')::date), interval '1 day') d
                 where extract(isodow from d) < 6),
        'conversations', (select count(*) from x where status <> 'LOST' and (first_reply_at is not null or inbound_first_at is not null)),
        'new_conversations', (select count(*) from x where coalesce(first_reply_at, inbound_first_at) >= (cfg->'sprint'->>'started_at')::date),
        'contacted', (select count(*) from x where first_outreach_at >= (cfg->'sprint'->>'started_at')::date),
        'positive', (select count(*) from x where positive_at >= (cfg->'sprint'->>'started_at')::date),
        'meetings', (select count(*) from x where meeting_at >= (cfg->'sprint'->>'started_at')::date),
        'briefs', (select count(*) from x where brief_at >= (cfg->'sprint'->>'started_at')::date)) end,
    'buckets', (select jsonb_agg(jsonb_build_object('key', b->>'key', 'label', b->>'label', 'target', (b->>'target')::int, 'director', b->>'director',
        'researched', (select count(*) from live where live.egypt->>'bucket' = b->>'key'),
        'email_ready', (select count(*) from live where live.egypt->>'bucket' = b->>'key' and email_state in ('VERIFIED', 'VERIFIED_INBOX', 'VERIFIED_GENERAL', 'OFFICIAL_PUBLISHED_INBOX')),
        'contacted', (select count(*) from x where x.egypt->>'bucket' = b->>'key' and first_outreach_at is not null),
        'replied', (select count(*) from x where x.egypt->>'bucket' = b->>'key' and (first_reply_at is not null or inbound_first_at is not null))))
      from jsonb_array_elements(cfg->'buckets') b),
    'top', coalesce((select jsonb_agg(t order by (t->>'score')::int desc, t->>'company') from (
        select jsonb_build_object('opportunity_id', live.id, 'company_id', live.company_id, 'company', live.name, 'country', live.country, 'director', live.director,
          'bucket', live.egypt->>'bucket', 'category', live.egypt->>'category', 'role', live.egypt->>'role', 'project_type', live.egypt->>'project_type',
          'project', live.egypt->>'proposed_project', 'format', live.egypt->>'egypt_format', 'studio_level', live.egypt->>'studio_level',
          'email_state', live.email_state, 'stage', case when live.won_at is not null then 'Won' when live.proposal_at is not null then 'Proposal'
              when live.brief_at is not null then 'Brief' when live.meeting_at is not null then 'Meeting' when live.positive_at is not null then 'Positive'
              when live.first_reply_at is not null or live.inbound_first_at is not null then 'Replied' when live.first_outreach_at is not null then 'Contacted'
              else 'Not contacted' end,
          'next_action', live.next_action, 'blocker', live.blocker,
          'score', destination_egypt_score(live.egypt, live.warmth, live.contact)) t
          from live where coalesce(live.egypt->>'role', '') not in ('PARTNER_SUPPLIER', 'AMPLIFIER') and coalesce(live.egypt->>'sprint', '') <> 'HOLD'
          order by destination_egypt_score(live.egypt, live.warmth, live.contact) desc, live.name limit 20) q), '[]'::jsonb),
    'method', 'Mission companies only, on the canonical model (companies counted once). Top 20 ranks Destination Egypt buyers (partners, amplifiers and accounts on hold are left out) by project generation, network leverage, repeat potential, Egypt relevance, destination evidence, warmth, contactability and a Studio-ready idea. Followers are never an input. No deal value is shown until one is recorded.')
  into v;
  return v;
end $$;
