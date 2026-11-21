// 02 · NOYA Private Desk — for private clients, families, executives, athletes and public figures.
import { ROLE, AVAILABILITY, TERMS } from './shared.mjs';

export default {
  code: '02',
  file: 'NOYA_02_Private_Desk_v2026-11',
  title: 'NOYA Private Desk',
  short: 'NOYA Private Desk',
  description: 'NOYA Private Desk: private lifestyle management, travel, family support and private sourcing. By introduction or application.',
  audience: 'Private clients, families, executives, athletes, public figures and prospective private clients.',
  purpose: 'Show what a dedicated NOYA relationship covers, including private sourcing, and explain how access is considered.',
  pages: [
    {
      layout: 'cover', img: 'robe-pool', pos: '55% 40%',
      kicker: 'Private Lifestyle Management',
      title: 'NOYA Private Desk',
      line: 'A dedicated point of contact for travel, hospitality\nand private life, in Egypt and worldwide.',
      base: ['By introduction or application', 'Edition 2026'],
    },
    {
      layout: 'statement', tone: 'navy',
      eyebrow: 'The Private Desk',
      title: 'A service built around people, not bookings.',
      blocks: [
        { p: 'NOYA Private Desk is for people with full diaries and high expectations of the service around them.' },
        { p: 'Whether you are travelling for business or with family, or simply need something taken care of, every request runs through one relationship: a NOYA contact who knows your preferences, your people and your standards, and who quietly manages the detail so that you do not have to.' },
        { p: 'From a family summer on the North Coast to a dinner reservation in Paris tonight, the same person is on the other end of the line.' },
      ],
    },
    {
      layout: 'split', side: 'right', img: 'car-night', pos: '50% 50%', approval: 'photo rights (car image)',
      eyebrow: 'What the Desk includes',
      title: 'One person who already knows the answer.',
      blocks: [
        { list: { items: [
          'A dedicated NOYA contact for every request',
          'A private record of your preferences, kept and used',
          'Coordination across destinations and time zones',
          'Specialist knowledge of Egypt',
          'Short-notice requests met wherever possible',
          'Confidentiality as standard, for you and your family',
        ] } },
        { gap: 6 },
        { box: { h: 'Preferences, remembered', t: 'The seat you prefer, the room you asked for last time, dietary requirements, the driver you liked, the children’s schedules. We keep a careful private record, so that you are never asked twice.' } },
      ],
    },
    {
      layout: 'band', img: 'towels-daybed', h: 112, pos: '50% 55%',
      eyebrow: 'Travel and stays',
      title: 'Journeys planned around how you travel.',
      blocks: [
        { cols: { n: 2, items: [
          { h: 'Flights', t: 'Any cabin, on most routes, with First and Business options researched for you. Changes and cancellations handled on your behalf.' },
          { h: 'Hotels, villas and residences', t: 'Properties chosen for privacy, service and the way you live, with the room, the view and the welcome arranged before you arrive.' },
          { h: 'Private aviation and yachts', t: 'Arranged with licensed specialist operators, chosen for the aircraft or vessel, the crew and the route.' },
          { h: 'Arrivals and ground movement', t: 'Airport meet-and-assist, chauffeurs, and security coordination through licensed providers where it is needed.' },
        ] } },
        { note: AVAILABILITY, mt: 5 },
      ],
    },
    {
      layout: 'split', side: 'left', img: 'robes-two', pos: '50% 50%',
      eyebrow: 'Lifestyle and family',
      title: 'Life at home\nand away.',
      blocks: [
        { cols: { n: 1, items: [
          { h: 'Lifestyle', t: 'Restaurant tables, beach clubs, tickets and event access, private dining, wellness retreats and personal shopping.' },
          { h: 'Family', t: 'Family holidays, children’s travel, school-holiday planning, anniversaries, birthdays and milestones.' },
          { h: 'Relocation', t: 'For families and athletes moving to or from Egypt: homes, schools, drivers, household staff introductions and settling in.' },
          { h: 'Personal', t: 'A home made ready for your return, last-minute requests and confidential personal matters, handled with discretion.' },
        ] } },
      ],
    },
    {
      layout: 'text', tone: 'navy',
      eyebrow: 'Private sourcing',
      title: 'Some things cannot simply be ordered.',
      approval: 'sourcing supplier capability',
      blocks: [
        { p: 'A particular watch reference. A handbag in a specific leather and colour. A piece of jewellery for an occasion, a car with the right history, a gift that must arrive somewhere precise on a precise day.' },
        { p: 'We search through independent dealers, specialist auction and resale houses and private collectors, and present what we find with its provenance, condition and price, before anything is committed.' },
        { gap: 3 },
        { list: { two: true, items: ['Watches', 'Handbags and leather goods', 'Jewellery', 'Vehicles', 'Art, objects and collectibles', 'Gifts and occasion pieces'] } },
        { gap: 7 },
        { cols: { n: 3, items: [
          { h: 'Authenticated', t: 'Pieces are offered only with appropriate authentication by independent specialists, and the documentation is passed to you.' },
          { h: 'In writing', t: 'Every detail is documented. You decide before anything is bought.' },
          { h: 'Independent', t: 'NOYA is not an authorised dealer or agent for any brand. We do not offer guaranteed allocations.' },
        ] } },
        { note: 'Availability depends on the market at the time of the request.', mt: 6 },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Who the Desk is for',
      title: 'For people whose time is spoken for.',
      blocks: [
        { p: 'Private Desk clients are individuals and families who value discretion, efficiency and personal service above all.' },
        { list: { two: true, items: ['Founders and chief executives', 'Chairs and investors', 'Family offices and private families', 'Athletes', 'Artists and performers', 'Public figures', 'International guests visiting Egypt', 'Private offices and executive assistants'] } },
        { gap: 8 },
        { h3: 'In practice' },
        { cols: { n: 2, items: [
          { k: 'Executives', t: 'Travel, airport assistance, chauffeurs, hotels and support outside office hours.' },
          { k: 'Families', t: 'Holidays, children’s travel, celebrations and the logistics of a busy household.' },
          { k: 'Athletes and talent', t: 'Travel, family support, relocation, transport and confidential requests around a demanding calendar.' },
          { k: 'Guests to Egypt', t: 'Arrival, private itineraries, hospitality and support for an accompanying party.' },
        ] } },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Access',
      title: 'By introduction or application.',
      approval: 'access wording',
      blocks: [
        { intro: 'We keep the number of Private Desk relationships small, so that each one receives proper attention.' },
        { p: 'Many begin with an introduction. Others begin with a private conversation with our founder. We consider each enquiry individually.' },
        { p: 'Some clients prefer an ongoing private arrangement; others prefer to work with us request by request. We will recommend what suits you, and agree the terms in writing before any work begins.' },
        { gap: 4 },
        { steps: [
          { h: 'Introduction', t: 'An introduction, or a short note to NOYA by email or WhatsApp.' },
          { h: 'Conversation', t: 'A private conversation about how you live and travel, and what you would like taken care of.' },
          { h: 'Agreement', t: 'A clear written arrangement: scope, communication and terms.' },
          { h: 'Your Desk', t: 'Your NOYA contact begins, and your preferences start to accumulate.' },
        ] },
        { note: `${TERMS} ${ROLE}`, mt: 5 },
      ],
    },
    {
      layout: 'closing', img: 'champagne-car', h: 104, pos: '40% 45%',
      eyebrow: 'Private enquiries',
      title: 'Luxury is measured by trust.',
      blocks: [
        { p: 'Knowing your preferences before you ask. Responding when plans change. Protecting your privacy. For an introduction to NOYA Private Desk, contact us directly.' },
        { contact: { founder: true } },
      ],
    },
  ],
};
