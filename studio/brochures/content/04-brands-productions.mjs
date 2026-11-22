// 04 · NOYA Brands & Productions — for luxury brands, creative and PR agencies, production teams and talent managers.
// The Dior / Jacquemus page of the previous edition is removed: no usage rights or permissions for that material.
import { AVAILABILITY } from './shared.mjs';

export default {
  code: '04',
  file: 'NOYA_04_Brands_and_Productions_v2026-11',
  title: 'NOYA Brands & Productions',
  short: 'NOYA Brands & Productions',
  description: 'NOYA Brands & Productions: brand experiences, talent and creator sourcing, locations, logistics and hospitality for brands, agencies and production teams.',
  audience: 'Luxury brands, creative agencies, PR firms, production teams and talent managers.',
  purpose: 'Show the ground layer NOYA provides around a brand programme or a shoot, and exactly where NOYA’s responsibility begins and ends.',
  pages: [
    {
      layout: 'cover', img: 'pyramid-woman', pos: '50% 35%',
      kicker: 'Brand Experiences · Talent · Production Coordination',
      title: 'NOYA Brands & Productions',
      line: 'Locations, logistics and hospitality for brands, agencies\nand production teams, in Egypt and internationally.',
      base: ['noyaconcierge.com', 'Edition 2026'],
    },
    {
      layout: 'statement', tone: 'navy',
      eyebrow: 'The partner',
      title: 'The ground layer every project depends on.',
      blocks: [
        { p: 'NOYA is a UK-based concierge business with deep expertise in Egypt. For brands, agencies and production companies, we provide what sits around the creative: locations, permissions through licensed partners, accommodation, movement, hospitality, talent care and the local relationships that make each of them possible.' },
        { pull: 'A production is rarely judged on the creative alone. It is judged on whether the site opened on time, whether the vehicle was waiting, and who answered the telephone when a permission stalled at four in the afternoon.' },
        { p: 'We hold those details so the creative team can concentrate on the work.' },
      ],
    },
    {
      layout: 'split', side: 'left', img: 'shoot-villa', pos: '50% 50%',
      eyebrow: 'Scope of service',
      title: 'Everything around the camera.',
      blocks: [
        { p: 'From the first recce to the final reconciliation, NOYA coordinates the suppliers, permissions and people that sit outside the creative brief.' },
        { list: { items: [
          'Location sourcing and recces',
          'Permission coordination through licensed partners',
          'Production logistics and scheduling',
          'Accommodation and room blocks',
          'Ground transport and movement planning',
          'Crew, talent and client hospitality',
          'Catering and on-set welfare',
          'Local suppliers and vendor management',
          'Security coordination through licensed providers',
          'Freight and equipment support',
        ] } },
      ],
    },
    {
      layout: 'band', img: 'terrace-sea', h: 108, pos: '50% 50%',
      eyebrow: 'Brand experiences and destination events',
      title: 'A brand programme, properly hosted.',
      blocks: [
        { p: 'Launches, press and media trips, creator journeys, VIP dinners and brand retreats. We take responsibility for the guest journey from invitation logistics to departure, so the brand team can host.' },
        { cols: { n: 3, items: [
          { h: 'Before', t: 'Venues and settings, flights, rooms, guest lists and dietary requirements, run-of-show and supplier briefs.' },
          { h: 'During', t: 'Arrivals, transport, hosting, dining, entertainment, gifting and on-site coordination.' },
          { h: 'After', t: 'Departures, supplier reconciliation, final accounting and a written debrief.' },
        ] } },
      ],
    },
    {
      layout: 'text', tone: 'navy',
      eyebrow: 'Talent, creators and influencers',
      title: 'The right faces, and the care they expect.',
      blocks: [
        { p: 'For campaigns, launches and brand trips, we identify talent, creators and influencers suited to the brief, approach them or their representatives, and coordinate availability, travel and hospitality around the programme.' },
        { cols: { n: 2, items: [
          { h: 'Sourcing', list: ['Shortlists matched to the brief, audience and market', 'Approaches through talent representatives', 'Availability, schedules and travel', 'VIP guest attendance, coordinated through representatives'] },
          { h: 'Care on the ground', list: ['Airport meet-and-assist and dedicated drivers', 'Hotel, villa and residence accommodation', 'Dietary, welfare and rest requirements', 'Discreet handling and non-disclosure as standard'] },
        ] } },
        { gap: 6 },
        { box: { h: 'Clear lines', t: 'NOYA is not a talent agency and does not represent talent. Fees, usage rights and contracts are agreed between the brand or agency and the talent’s representatives. We coordinate everything around them.' } },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Egypt · Locations',
      title: 'One country. Many looks.',
      blocks: [
        { intro: 'Desert, Nile, Mediterranean coast, Red Sea, ancient monument and modern city, most within a few hours of one another and workable for much of the year.' },
        { cols: { n: 2, items: [
          { h: 'Cairo and Giza', t: 'The Pyramids and the Giza plateau, the Grand Egyptian Museum, historic and downtown Cairo, palaces and contemporary architecture.' },
          { h: 'Luxor and Aswan', t: 'Temples and tombs, the Nile and its feluccas, riverside hotels and the light of Upper Egypt.' },
          { h: 'The Red Sea', t: 'El Gouna and the coast: marinas, yachts, reefs and resort architecture.' },
          { h: 'The North Coast and the desert', t: 'Mediterranean beaches and summer villas; open desert landscapes within reach of Cairo.' },
        ] } },
        { gap: 6 },
        { photos: { imgs: ['pyramids-camels', 'yacht-tray-wide'], h: 56 } },
        { note: 'Filming at heritage sites requires permissions from the relevant Egyptian authorities, applied for through licensed partners. Timelines vary by site.', mt: 3 },
      ],
    },
    {
      layout: 'text', tone: 'navy', reference: true,
      eyebrow: 'Creative references',
      title: 'Egypt, through a creative lens.',
      blocks: [
        { refs: { h: 112, items: [
          { img: 'ref-dior-giza', title: 'Dior — Giza, 2022', text: 'Men’s Pre-Fall 2023 runway presentation at the Pyramids of Giza.' },
          { img: 'ref-jacquemus-egypt', title: 'Jacquemus — Egypt, 2025', text: 'La Croisière campaign, photographed across Egypt from Cairo to Aswan.' },
        ] } },
        { gap: 7 },
        { p: 'From Dior’s runway presentation at Giza to Jacquemus’ campaign across Egypt, the country has provided a remarkable setting for international fashion. NOYA works with brands and their creative teams to coordinate the locations, local production support, travel and hospitality behind their own vision.' },
        { note: 'Independent creative references. NOYA was not involved in these productions. Locations and permissions are subject to approval. Photography: Dior, Henar Sherif and Adel Essam; Jacquemus, Mohamed Sherif.', mt: 4 },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Project types',
      title: 'The work we support.',
      blocks: [
        { p: 'Whether the requirement is a two-day content shoot or a fortnight of campaign production across three governorates, the discipline is the same: a defined scope, confirmed suppliers and one point of contact.' },
        { list: { two: true, items: ['Fashion and luxury campaigns', 'Jewellery and watch productions', 'Editorial and magazine shoots', 'Commercials', 'Social and content productions', 'Creator and influencer activations', 'Product launches', 'Press and media trips', 'Brand retreats and off-sites', 'Experiential marketing', 'Music videos and artist travel', 'Documentary and factual support'] } },
        { gap: 8 },
        { photos: { imgs: ['shoot-yacht', 'robe-pool', 'champagne-car'], h: 62, cols: '1fr 1.6fr 1fr' } },
      ],
    },
    {
      layout: 'text', tone: 'navy',
      eyebrow: 'Production process',
      title: 'Four stages. One point of contact.',
      blocks: [
        { p: 'Every project runs through the same sequence, documented in writing at each stage, so that budget holders and producers always know what has been confirmed and what has not.' },
        { gap: 3 },
        { steps: [
          { h: 'Concept', t: 'Story, visual direction and location requirements. We advise on what is achievable, where and at what cost, before budgets are committed.' },
          { h: 'Pre-production', t: 'Recces, locations, permissions, suppliers, accommodation, transport and schedules, each confirmed in writing and costed line by line.' },
          { h: 'On location', t: 'Talent and crew hospitality, movement, site management, supplier control and same-day problem solving throughout the shoot.' },
          { h: 'Wrap', t: 'Departures, supplier reconciliation, final accounting and a written debrief for the next production.' },
        ] },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Responsibilities',
      title: 'Who does what.',
      blocks: [
        { p: 'Good productions depend on clear lines. This is how responsibility is usually divided when NOYA is engaged; the written scope for each project confirms it.' },
        { gap: 2 },
        { table: { head: ['Party', 'Responsible for'], rows: [
          ['Brand', 'Objectives, approvals, budget and final sign-off.'],
          ['Creative agency', 'Concept, creative direction, casting decisions and the client relationship.'],
          ['Talent representatives', 'Talent fees, usage rights and contracts.'],
          ['Licensed production partners', 'Applications for filming permissions, technical crew and equipment, delivered under their licences. Permissions themselves are issued by the relevant authorities.'],
          ['NOYA', 'Locations and recces, logistics, accommodation, transport, hospitality, talent and crew care, local suppliers and on-the-ground coordination, with one point of contact throughout.'],
        ] } },
        { note: 'NOYA is the coordination and hospitality partner. Technical production services and specialist crew are delivered by approved licensed partners under NOYA coordination; filming permissions are issued by the relevant authorities and applied for through those partners.', mt: 5 },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Commercial scope',
      title: 'Clear scope. Clear costs.',
      blocks: [
        { p: 'Every project is quoted against an approved brief, and fees follow what the brief asks NOYA to deliver.' },
        { p: 'Costs are itemised: supplier costs, NOYA’s coordination fee and any agreed mark-up are shown separately, and nothing is committed until the budget holder has approved them.' },
        { list: { items: [
          'Project fee or day rate agreed in writing before work begins',
          'Deposit to secure suppliers, dates and permissions',
          'Balance settled against an agreed payment schedule',
          'Retainer available for brands and agencies producing in Egypt regularly',
          'Full supplier reconciliation and final statement on completion',
        ] } },
        { note: AVAILABILITY, mt: 5 },
      ],
    },
    {
      layout: 'closing', img: 'robes-two', h: 104, pos: '50% 45%',
      eyebrow: 'Production enquiries',
      title: 'Tell us about the project.',
      blocks: [
        { p: 'For location sourcing, production logistics, brand trips, talent programmes or destination support in Egypt and internationally, send us the brief, or as much of it as exists.' },
        { contact: { founder: true } },
      ],
    },
  ],
};
