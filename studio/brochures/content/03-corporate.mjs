// 03 · NOYA Corporate — for companies, executive offices, family offices and organisations.
import { ROLE, AVAILABILITY, TERMS } from './shared.mjs';

export default {
  code: '03',
  file: 'NOYA_03_Corporate_v2026-11',
  title: 'NOYA Corporate',
  short: 'NOYA Corporate',
  description: 'NOYA Corporate: executive travel, visiting delegations, corporate hospitality and destination management in Egypt and internationally.',
  audience: 'Companies, executive offices, family offices and organisations.',
  purpose: 'Establish operational competence, accountability and commercial maturity; explain how NOYA is engaged.',
  pages: [
    {
      layout: 'cover', img: 'car-street', pos: '40% 50%', approval: 'photo rights (car image)',
      kicker: 'Executive Travel · Hospitality · Lifestyle Management',
      title: 'NOYA Corporate',
      line: 'Travel, hospitality and visits for organisations, held by one contact.\nExpert in Egypt. Arranging worldwide.',
      base: ['noyaconcierge.com', 'Edition 2026'],
    },
    {
      layout: 'split', side: 'right', img: 'car-night', pos: '40% 50%', approval: 'photo rights (car image)',
      eyebrow: 'About NOYA',
      title: 'An extension of your executive team.',
      blocks: [
        { p: 'NOYA provides executive travel, hospitality and lifestyle management for organisations, their leaders, their guests and their people.' },
        { p: 'Rather than managing several suppliers, your organisation works with one NOYA contact who coordinates every detail with discretion and accountability.' },
        { p: 'Our expertise is built around Egypt, where we hold direct working relationships across hospitality, transport and local services. Through partners we know, we support travel and hospitality requirements internationally.' },
        { box: { h: 'Alongside your team', t: 'We work alongside existing travel providers and internal teams, adding a dedicated hospitality and lifestyle layer around every journey.' } },
      ],
    },
    {
      layout: 'text', tone: 'navy',
      eyebrow: 'Why companies choose NOYA',
      title: 'Six reasons the call comes to us.',
      blocks: [
        { cols: { n: 2, items: [
          { k: '01', h: 'One accountable contact', t: 'One relationship for travel, hospitality and the requests in between, with one person answerable for the outcome.' },
          { k: '02', h: 'Less administration', t: 'We coordinate suppliers, reservations and logistics, taking the load off executive assistants and internal teams.' },
          { k: '03', h: 'International coordination', t: 'Journeys and visits managed across destinations and time zones, with every confirmation in writing.' },
          { k: '04', h: 'Specialist Egypt knowledge', t: 'Direct relationships and local judgement throughout Egypt, from Cairo to the Red Sea and the Nile.' },
          { k: '05', h: 'Calm when things move', t: 'A delayed flight, a moved meeting, an extra guest. We adapt quickly and quietly.' },
          { k: '06', h: 'Discretion', t: 'Confidential handling of itineraries, guests and internal matters, as standard.' },
        ] } },
      ],
    },
    {
      layout: 'split', side: 'left', img: 'car-headrest', pos: '50% 45%',
      eyebrow: 'Executive travel and visits',
      title: 'Support that sits around the working day.',
      blocks: [
        { p: 'Most organisations already have travel policies, booking tools and capable administrative teams. What they rarely have is someone to hold the requests that fall outside them: the short-notice change, the visiting client, the preference nobody wrote down.' },
        { list: { items: ['Executive and board travel', 'Investor and partner visits', 'Visiting delegations and guests', 'Airport meet-and-assist and chauffeurs', 'Accommodation and room blocks', 'Requests outside office hours, by arrangement'] } },
        { note: AVAILABILITY, mt: 4 },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Destination management · Egypt',
      title: 'Egypt, handled properly.',
      blocks: [
        { intro: 'Egypt rewards organisations that arrive well prepared and punishes those that do not.' },
        { p: 'Protocol, transport, venues and access depend on relationships that take years to build. Ours are direct, and where a licensed partner is required, we know which one to call. A chief executive visiting Cairo, a delegation touring sites, a leadership team on the Red Sea: each is planned around the realities of the place.' },
        { gap: 3 },
        { cols: { n: 3, items: [
          { h: 'Visits', list: ['Corporate visits and site inspections', 'Investment and business delegations', 'Government and protocol-sensitive guests'] },
          { h: 'Programmes', list: ['Leadership retreats', 'Incentive travel', 'Cultural and private experiences'] },
          { h: 'On the ground', list: ['Movement planning and vehicles', 'Accommodation and room blocks', 'A NOYA contact throughout the visit'] },
        ] } },
        { gap: 6 },
        { photos: { imgs: ['pyramids-camels', 'pyramid-woman'], h: 52, cols: '1.5fr 1fr' } },
        { note: 'Access to heritage sites and venues is subject to the permissions of the relevant authorities and owners.', mt: 3 },
      ],
      approval: 'photo rights (pyramids image)',
    },
    {
      layout: 'band', img: 'beach-dinner', h: 110, pos: '50% 55%',
      eyebrow: 'Corporate hospitality',
      title: 'Occasions your guests remember for the right reasons.',
      blocks: [
        { p: 'Corporate hospitality is judged on the parts nobody plans for: the arrival, the transfer that runs late, the guest with a requirement nobody flagged. We look after the whole guest journey, before, during and after every visit, dinner and event, so that guests are properly received and your team can stay focused on the business.' },
        { list: { two: true, items: ['Executive and board dinners', 'Client entertainment', 'Sporting and cultural hospitality', 'Retreats and off-sites', 'Conference and launch support', 'Private celebrations'] } },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Engagement model',
      title: 'Three ways to work with NOYA.',
      blocks: [
        { p: 'Every organisation’s requirements are different. We agree scope, service expectations and fees in writing before work begins, and present third-party costs transparently.' },
        { gap: 3 },
        { cards: { n: 3, items: [
          { tag: 'Ongoing', h: 'Corporate account', t: 'For organisations with regular travel and hospitality needs.', list: ['A named NOYA contact', 'Agreed scope and service expectations', 'A maintained record of your people’s preferences', 'Periodic statements and review'] },
          { tag: 'Standing', h: 'Retained support', t: 'For executive offices and family offices that want NOYA available as a standing resource.', list: ['A monthly arrangement', 'Availability defined in writing', 'Priority scheduling against the agreed scope', 'Reviewed together each quarter'] },
          { tag: 'Defined', h: 'Project assignment', t: 'For a single visit, delegation, retreat or event.', list: ['A written scope and itemised quotation', 'Deposit and balance schedule', 'One NOYA lead from proposal to final account', 'Supplier reconciliation on completion'] },
        ] } },
        { note: `Fees reflect scope, volume and the level of availability required. ${TERMS}`, mt: 6 },
      ],
      approval: 'engagement model',
    },
    {
      layout: 'text', tone: 'navy',
      eyebrow: 'Sectors we support',
      title: 'Different sectors. The same requirement.',
      blocks: [
        { intro: 'The work varies. The underlying need does not: someone reliable to hold the detail when people who matter are moving.' },
        { list: { two: true, items: ['Banks and financial institutions', 'Law firms', 'Private equity and investment groups', 'Family offices', 'Property developers', 'Luxury brands', 'Sports organisations and clubs', 'Marketing and PR agencies', 'Hospitality groups', 'Production companies'] } },
        { gap: 8 },
        { box: { h: 'Brands and productions', t: 'For brand experiences, creator programmes and productions, see NOYA Brands & Productions. For travel advisors and concierge firms needing delivery in Egypt, see NOYA Trade & Partners.' } },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'How we work',
      title: 'One owner, from first call to final account.',
      blocks: [
        { steps: [
          { h: 'Enquiry', t: 'You tell us what is needed, in a few lines.' },
          { h: 'Proposal', t: 'A written proposal with a clear scope, the options worth considering and itemised costs.' },
          { h: 'Planning', t: 'Every supplier, timing and contact is confirmed in writing through one NOYA lead.' },
          { h: 'Delivery', t: 'We remain on hand throughout, on the ground in Egypt where required, and adapt as the programme moves.' },
          { h: 'Review', t: 'A short debrief and final account. Preferences are recorded, so the next visit starts further ahead.' },
        ] },
        { gap: 8 },
        { box: { h: 'Our role', t: ['NOYA is accountable for the arrangements we make and for coordinating the suppliers we engage.', ROLE] } },
      ],
    },
    {
      layout: 'closing', img: 'yacht-tray-wide', h: 104, pos: '50% 50%',
      eyebrow: 'Corporate enquiries',
      title: 'A trusted partner for executive travel, hospitality and visits to Egypt.',
      small: true,
      blocks: [
        { p: 'For a corporate account, a visiting delegation or a single assignment in Egypt or internationally, contact NOYA directly.' },
        { contact: { founder: true } },
      ],
    },
  ],
};
