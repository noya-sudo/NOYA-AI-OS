// 05 · NOYA Trade & Partners — consolidates and replaces "NOYA Concierge Egypt | Partner Guide" (Summer & Autumn 2026).
// Audience: luxury travel advisors, concierge firms, international agencies, hospitality partners and travel designers.
// No response times, preferred rates or commission levels are published: none is documented as approved.
import { ROLE, AVAILABILITY } from './shared.mjs';

export default {
  code: '05',
  file: 'NOYA_05_Trade_and_Partners_v2026-11',
  title: 'NOYA Trade & Partners',
  short: 'NOYA Trade & Partners',
  description: 'NOYA Trade & Partners: confidential on-the-ground delivery in Egypt for travel advisors, concierge firms and agencies.',
  audience: 'Luxury travel advisors, concierge firms, international agencies, hospitality partners and travel designers.',
  purpose: 'Make NOYA the obvious Egypt delivery partner: what we deliver, how client ownership and commercial terms work, and who to call.',
  pages: [
    {
      layout: 'cover', img: 'beach-dinner', pos: '42% 50%',
      kicker: 'Egypt Partner Guide',
      title: 'NOYA Trade & Partners',
      line: 'Confidential, on-the-ground delivery in Egypt\nfor travel advisors, concierge firms and agencies.',
      base: ['noyaconcierge.com', 'Edition 2026'],
    },
    {
      layout: 'statement', tone: 'navy',
      eyebrow: 'Partnering with NOYA',
      title: 'Your client. Our ground.',
      blocks: [
        { p: 'When your client travels to Egypt, you need someone on the ground whose standards match your own: someone who answers quickly, plans properly and never forgets whose client it is.' },
        { p: 'NOYA works behind travel advisors, concierge firms and agencies as their Egypt delivery partner. You keep the relationship. We design and deliver the programme, white-label or under the NOYA name, as you prefer.' },
        { p: 'Demand for Egypt is growing, with the opening of the Grand Egyptian Museum, new luxury hospitality across Cairo, El Gouna and the North Coast, and a fuller calendar of international events. We help partners say yes to those requests with confidence.' },
      ],
    },
    {
      layout: 'split', side: 'left', img: 'car-headrest', pos: '50% 45%',
      eyebrow: 'What we deliver',
      title: 'Everything your client needs in Egypt.',
      blocks: [
        { list: { items: [
          'Custom itineraries and destination planning',
          'Hotels, private villas and Nile accommodation',
          'Dining, private experiences and cultural visits with licensed guides',
          'Airport meet-and-assist, chauffeurs and movement planning',
          'VIP guests, families and accompanying parties',
          'Groups, incentives and brand delegations',
          'Celebrations, events and destination weddings',
          'Security coordination through licensed providers',
        ] } },
        { note: AVAILABILITY, mt: 4 },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Destinations',
      title: 'Egypt, in four chapters.',
      approval: 'photo rights (Giza image)',
      blocks: [
        { cols: { n: 2, items: [
          { k: 'I', h: 'Cairo and Giza', t: 'The Pyramids, the Grand Egyptian Museum and Cairo’s great hotels and restaurants. Ideal for first visits, executive travel, cultural programmes and VIP guests.' },
          { k: 'II', h: 'Luxor and Aswan', t: 'The Valley of the Kings, Karnak, Abu Simbel and the Nile, with historic riverside hotels and private river journeys. Ideal for families, cultural travel and multi-day journeys.' },
          { k: 'III', h: 'El Gouna and the Red Sea', t: 'A year-round resort town of marinas, golf, yachting and residences. Ideal for families, long stays, retreats and destination weddings.' },
          { k: 'IV', h: 'The North Coast', t: 'Summer villas, beach clubs and a busy calendar of music and events on the Mediterranean, from Almaza Bay to Marassi and Ras El Hekma. Ideal for summer travel, groups and celebrations.' },
        ] } },
        { gap: 7 },
        { photos: { imgs: ['pyramid-woman', 'yacht-tray-wide', 'towels-daybed'], h: 60, cols: '1fr 1.5fr 1.5fr' } },
      ],
    },
    {
      layout: 'text', tone: 'navy',
      eyebrow: 'How partnership works',
      title: 'Clear ownership. Clear handovers.',
      approval: 'partner terms',
      blocks: [
        { cols: { n: 2, items: [
          { h: 'Your client remains yours', t: 'We do not market to, solicit or contract directly with partner clients. Confidentiality and non-solicitation are agreed in writing before the first booking.' },
          { h: 'White-label or co-branded', t: 'Documents, guest communications and on-the-ground introductions are presented under your brand or ours, as agreed for each booking.' },
          { h: 'A defined handover', t: 'Each booking moves from your brief to our proposal, your confirmation, a guest dossier and on-the-ground delivery, with responsibilities stated in writing.' },
          { h: 'Escalation', t: 'Every booking has a named NOYA lead. Our founder is the escalation point for every partner relationship.' },
        ] } },
        { gap: 8 },
        { steps: [
          { h: 'Brief', t: 'You share the client’s dates, preferences and budget.' },
          { h: 'Proposal', t: 'We return an itemised proposal, white-label if required.' },
          { h: 'Confirmation', t: 'You confirm with your client; we secure every element in writing.' },
          { h: 'Delivery', t: 'Guest dossier, on-the-ground hosting and live updates to you.' },
          { h: 'Debrief', t: 'Feedback and final statement, so the next booking is easier.' },
        ] },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Commercial structures',
      title: 'Net or commission, agreed in writing.',
      approval: 'partner terms',
      blocks: [
        { p: 'We work with partners on one of two structures, chosen per partner or per booking and confirmed in a written agreement before the first booking. Terms depend on the programme and on volume.' },
        { gap: 3 },
        { cards: { n: 2, items: [
          { tag: 'Structure A', h: 'Net quotation', t: 'We quote net. You set your own margin and the price your client sees.', list: ['Itemised net costs', 'Your pricing and your invoice to the client', 'Suited to advisors and concierge firms who package travel'] },
          { tag: 'Structure B', h: 'Commission', t: 'We quote the client-facing price and pay you an agreed commission on confirmed, paid bookings.', list: ['Client-facing proposal from NOYA, white-label if required', 'Commission paid on completion, per agreement', 'Suited to introducers and referral partners'] },
        ] } },
        { gap: 6 },
        { box: { h: 'Payment', t: 'Deposits secure suppliers and dates; balances follow the schedule in each booking confirmation. Supplier cancellation terms are passed through transparently.' } },
        { note: 'NOYA does not publish partner rates or commission levels. Preferred rates or benefits apply only where a supplier has agreed them in writing for a specific booking.', mt: 5 },
      ],
    },
    {
      layout: 'text', tone: 'navy',
      eyebrow: 'Responsibilities',
      title: 'Who does what.',
      blocks: [
        { table: { head: ['Party', 'Responsible for'], rows: [
          ['Partner', 'The client relationship, the client contract and payment collection (net structure), and passing on the brief and any changes.'],
          ['NOYA', 'Destination planning, supplier selection and booking, guest dossier, on-the-ground hosting, coordination and the final statement.'],
          ['Licensed operators', 'Regulated services such as private aviation, yacht charter, licensed guiding and security, delivered under their own licences.'],
        ] } },
        { gap: 6 },
        { note: ROLE },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Who we work with',
      title: 'Built for partners who protect their clients.',
      blocks: [
        { list: { two: true, items: ['Luxury travel advisors and designers', 'Concierge companies', 'International agencies', 'Family offices', 'Corporate travel teams', 'Event and PR agencies', 'Production companies', 'Wedding planners', 'Sports organisations', 'Hospitality partners'] } },
        { gap: 8 },
        { box: { h: 'Hospitality partners', t: 'Hotels, villas and experience providers in Egypt and beyond: we are always interested in properties and people that meet our clients’ standards. Introduce yourself; we will look closely.' } },
        { gap: 6 },
        { photos: { imgs: ['robes-two', 'towels-daybed'], h: 58 } },
      ],
    },
    {
      layout: 'closing', img: 'yacht-tray-tall', h: 104, pos: '50% 62%',
      eyebrow: 'Partner enquiries',
      title: 'Bring us your next Egypt request.',
      blocks: [
        { p: 'Send the brief, however early, and we will come back with a proposal under your name or ours. To discuss a partner agreement, contact our founder directly.' },
        { contact: { founder: true } },
      ],
    },
  ],
};
