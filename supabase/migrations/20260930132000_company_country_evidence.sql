-- Data cleanup (30 Sep 2026): country for 21 of the 25 companies with an UNKNOWN market, each from
-- public evidence recorded in companies.notes and approval_audit. 4 stay UNKNOWN (no reliable
-- evidence): Beyond Members Club, Double Culture Films, Sporting Founders, Summits (Pangea).
-- Idempotent: only fills a country that is still empty. Applied live on 30 Sep 2026.
do $$
declare r record;
begin
  for r in select * from (values
    ('b576b692-0b30-43f5-9cd7-3d208e10ffc1','United Kingdom','London','Luxury wedding & event designer, London (alicewilkes.co.uk title; thewed.com/planners/alice-wilkes-design lists UK)'),
    ('2cdd1b24-9ba9-4f16-a41c-40de81ee7ede','United Arab Emirates','Dubai','Avantgarde Middle East GmbH & Co KG, Dubai (yello.ae/company/145799); Dubai office (Glassdoor)'),
    ('af6707f2-272d-4dc1-a544-5aff64630204','United Arab Emirates','Dubai','Dubai-based PR agency, offices Dubai and Riyadh (campaignme.com/agency/brazen; brazen.agency)'),
    ('2e46b475-7f3b-4461-815f-6b97475df90e','France','Paris','Paris and Dubai-based event agency (crush-agency.com, LinkedIn); primary office recorded as Paris'),
    ('de474ac4-400c-401b-9441-81a199c6d53d','United Arab Emirates',null,'UAE club: name and .ae domain (entrepreneursclub.ae)'),
    ('dd91b892-2119-47ff-83d3-8186f6275b92','United States',null,'Private network across North America; chapters New York, Miami, Los Angeles, Toronto (foundersclubofficial.com)'),
    ('3ed77b33-bf53-4665-8522-1a329f66d13c','United States','New York','Part of Internova Travel Group, headquartered in New York City (internova.com)'),
    ('db0c2241-2fb7-4467-af52-d5807fd65b72','United Arab Emirates','Dubai','Jack Morton Dubai office (jackmorton.com/offices/dubai)'),
    ('87a7e514-a2ee-497d-9510-46e651e6815f','United Kingdom','London','London wedding designer founded 2016 by Charlotte Ricard-Quesada (la-fete.com/about)'),
    ('7e64ba61-191d-4223-8e23-9e02bc6447d6','United Arab Emirates','Dubai','Creative experience agency based in Dubai and Los Angeles; Dubai office Gold and Diamond Park (lightblueww.com)'),
    ('96f98b77-05f8-4c17-8d05-bd7c9978383e','United Arab Emirates','Dubai','Event agency established 2003, headquartered in Dubai (linkviva.com/about)'),
    ('b51a9ff0-ee3d-46b2-9d7d-458625f1d2ca','United Arab Emirates',null,'MCI UAE entity (wearemci.com/en/about-us/uae)'),
    ('f1f3e6e5-0634-4a6a-add3-b5bb05af97ab','United Kingdom','London','Members club hosting across London, Mayfair (mmesocial.co.uk)'),
    ('9155d3ae-836a-467e-aaf8-1d582331bcba','United Kingdom','London','Headquarters London, European office Milan (sarahhaywood.com/about; LinkedIn UK)'),
    ('064c9add-4710-4820-b8a7-76f0b51d9a4f','United Kingdom','Grittleton','Studio Sorores Ltd, Yew Tree Cottage, Grittleton, Wiltshire SN14 6AP (studiosorores.com/contact)'),
    ('665d9f76-824f-4f38-a19b-c53fc29ee280','United Kingdom','London','Ten Lifestyle Group HQ, 338 Euston Road, London (theorg.com, Wikipedia)'),
    ('4970a7eb-5e33-4da0-ab90-c6c1cf3901d0','United Arab Emirates','Dubai','Experiential agency, Dubai Investment Park 2 (thehanginghouse.com/contact; LinkedIn)'),
    ('9e653db1-bef6-4730-b0ad-b367ab9f0421','United Kingdom','London','Athlete-led VC founded 2023, based in London (playersfund.vc; LinkedIn UK)'),
    ('ba7c4164-f5e3-446f-858e-f2e76075b548','United Arab Emirates','Dubai','Dubai-based wedding planning company founded 2016 (vivaahcelebrations.com/about-vivaah)'),
    ('70b2d127-6704-4bf5-86cb-852e783c8d05','United Arab Emirates','Dubai','YKONE Middle East, Dubai (ykone.com/influencer-marketing-agency-dubai)'),
    ('a4610d09-5e6d-4d6f-b865-21b5f37f57ea','United Arab Emirates','Dubai','YP Club, formerly Dubai Young Professionals; Facebook page "YP Club | Dubai" (facebook.com/theypclub)')
  ) v(id, country, city, evidence) loop
    update companies set country = r.country, city = coalesce(city, r.city), updated_at = now(),
      notes = coalesce(notes || E'\n', '') || 'Country evidence (30 Sep 2026, public web): ' || r.evidence
     where id = r.id::uuid and country is null;
  end loop;
end $$;
