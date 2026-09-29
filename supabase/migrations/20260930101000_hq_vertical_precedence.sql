-- Vertical classification fix found in testing (30 Sep 2026): YKONE, a brand/production agency,
-- was classed SPORTS_TALENT because its opportunity text mentions influencers. The company's own
-- type now decides first; the opportunity text and sector are used only when the type is silent.
-- Weddings/events are matched before sports/talent (a "celebrity wedding planner" is a wedding planner).
create or replace function public.hq_vertical_of(p text)
returns text language sql immutable as $$
  select case
    when coalesce(btrim(p), '') = '' then 'OTHER'
    when p ~* 'WEDDING' or p ~* '(EVENT_AGENCY|EVENT AGENCY|EVENT PLANNING|EVENT MANAGEMENT|EVENT SERVICES|EVENT SUPPLIER|CELEBRATION)' then 'WEDDINGS_EVENTS'
    when p ~* '(SPORT|ATHLET|FOOTBALL|TALENT|CELEBRITY|PUBLIC_FIGURE)' then 'SPORTS_TALENT'
    when p ~* '(FAMILY.OFFICE|PRIVATE.OFFICE|PRIVATE_CLIENT|PRIVATE CLIENT|UHNW|WEALTH|PRIVATE_BANK|PRIVATE BANK)' then 'PRIVATE_UHNW'
    when p ~* '(HOTEL|RESORT|VILLA|HOSPITALITY|RESTAURANT)' then 'HOSPITALITY'
    when p ~* '(CONCIERGE|TRAVEL|DMC|DESTINATION_PARTNER|MEMBER|CLUB|AVIATION|AIRLINE|EXPEDITION|TOUR|YACHT)' then 'TRAVEL_CONCIERGE'
    when p ~* '(BRAND|PRODUCTION|FASHION|BEAUTY|COSMETIC|AUTOMOTIVE|PR_|PR AGENCY|MARKETING|CREATIVE|RETAIL|CAMPAIGN|SHOOT|MEDIA|INFLUENCER|CREATOR)' then 'BRAND_PRODUCTION'
    when p ~* '(LAW|LEGAL|CONSULT|PROFESSIONAL|CORPORATE|INVEST|BANK|FINANCIAL|INSURANCE|EXECUTIVE)' then 'CORPORATE'
    else 'OTHER'
  end
$$;

create or replace function public.hq_vertical(p_company_type text, p_opportunity_type text, p_sector text default null)
returns text language sql immutable as $$
  select coalesce(nullif(hq_vertical_of(p_company_type), 'OTHER'), nullif(hq_vertical_of(p_opportunity_type), 'OTHER'), hq_vertical_of(p_sector))
$$;
