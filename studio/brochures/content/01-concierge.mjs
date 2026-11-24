// 01 · NOYA Concierge — the flagship overview. Sent when someone asks "what does NOYA do?".
// It covers the whole proposition once, then points to the specialist document for each audience.
// r2 art direction: the branded yacht cover; a calmer Red Sea towel for "who we work with"; aviation for journeys; event access
// for lifestyle; the high-resolution beach table for occasions; SAGE service detail for organisations; Giza for Egypt;
// Saint-Tropez for the international chapter; the robe on the terrace to close.
import { ROLE, AVAILABILITY } from './shared.mjs';

export default {
  code: '01',
  file: 'NOYA_01_Concierge_Overview',
  title: 'NOYA Concierge',
  short: 'NOYA Concierge',
  description: 'NOYA Concierge: private travel, hospitality and lifestyle management. Egypt expertise, worldwide arrangements.',
  audience: 'Private clients, introductions, potential partners and general prospects.',
  purpose: 'Explain what NOYA is, why clients choose it and the breadth of what it arranges, then invite a first request.',
  pages: [
    {
      layout: 'cover', img: 'yacht-tray-tall', pos: '50% 62%',
      kicker: 'Travel · Hospitality · Lifestyle Management',
      title: 'NOYA Concierge',
      line: 'One trusted point of contact for travel, hospitality and private life.\nExpert in Egypt. Arranging worldwide.',
      base: ['noyaconcierge.com', 'Edition 2026'],
    },
    {
      layout: 'statement', tone: 'navy',
      eyebrow: 'About NOYA',
      title: 'One relationship for the arrangements that matter.',
      blocks: [
        { p: 'NOYA is an independent concierge and lifestyle management business. We arrange travel, hospitality and the private details around them for individuals, families, companies and brands.' },
        { p: 'Clients come to us for judgement as much as for arrangements: which villa suits a family with young children, which driver can be trusted with a demanding schedule, which table will make the evening.' },
        { p: 'Egypt is where our knowledge and working relationships run deepest. Elsewhere we work through properties and people we know, and we say plainly when a request is better placed with someone else.' },
        { pull: 'Luxury is not simply about access. It is about having someone who understands how you live.' },
      ],
    },
    {
      layout: 'split', side: 'left', img: 'towel-chair-sea', pos: '74% 50%',
      eyebrow: 'Who we work with',
      title: 'Four kinds of client.\nOne standard of care.',
      blocks: [
        { cols: { n: 1, items: [
          { k: 'I', h: 'Private clients and families', t: 'Travel, homes from home, family logistics, celebrations and the requests that fit nowhere else.', more: 'NOYA Private Desk' },
          { k: 'II', h: 'Companies and executive offices', t: 'Executive travel, visiting delegations, client hospitality and retreats, with one accountable contact.', more: 'NOYA Corporate' },
          { k: 'III', h: 'Brands, agencies and productions', t: 'Brand experiences, talent and creator programmes, and the locations, logistics and hospitality around a shoot.', more: 'NOYA Brands & Productions' },
          { k: 'IV', h: 'Travel advisors and concierge firms', t: 'Confidential delivery in Egypt for your clients, under your name or ours.', more: 'NOYA Trade & Partners' },
        ] } },
      ],
    },
    {
      layout: 'band', img: 'alpine-chalet', h: 112, pos: '50% 62%',
      eyebrow: 'Travel and hospitality',
      title: 'Where to stay, how to move,\nand who will be waiting.',
      blocks: [
        { cols: { n: 2, items: [
          { h: 'Stays', t: 'Hotels, private villas and residences, chosen for the way you travel: privacy, space for a family, a quiet room, a short drive to where you need to be.' },
          { h: 'Journeys', t: 'Flights in any cabin, with premium fares researched on request. Private aviation and yacht charter through licensed operators.' },
          { h: 'Arrivals', t: 'Airport meet-and-assist, fast-track where available, and a chauffeur waiting with the car you asked for.' },
          { h: 'Itineraries', t: 'Multi-stop journeys planned and held together by one person, who adjusts them as the days unfold.' },
        ] } },
        { note: AVAILABILITY },
      ],
    },
    {
      layout: 'split', side: 'right', img: 'wembley-dusk', pos: '50% 40%',
      eyebrow: 'Lifestyle and sourcing',
      title: 'The details of a\nprivate life, handled.',
      blocks: [
        { p: 'Tables that are difficult to book. Seats for the final, the show, the opening night. A private chef for a week at the villa. Flowers and gifts delivered on the right day, to the right door.' },
        { h3: 'Private sourcing', mt: 4 },
        { p: 'Luxury watches, rare handbags, jewellery, cars, art, collectibles and gifts, sourced on request through independent dealers, specialist houses and private sellers, and presented with provenance, condition and price before you decide.' },
        { note: 'Subject to availability, with independent verification where appropriate. NOYA is not an authorised dealer for any brand.' },
      ],
    },
    {
      layout: 'band', img: 'beach-dinner-hd', h: 118, pos: '50% 78%',
      eyebrow: 'Private occasions',
      title: 'Celebrations of every size,\nplanned with the same attention.',
      blocks: [
        { p: 'Birthdays, anniversaries, proposals, weddings and gatherings of family and friends. We find the setting, look after the guests’ travel and rooms, and bring the suppliers together, so that the hosts can enjoy the occasion with everyone else.' },
        { box: { h: 'Selected work · Cairo, October 2025', t: 'An international wedding party at a five-star Cairo hotel: a group rate negotiated and contracted, guest bookings taken directly, the rooming list managed through every revision, and the couple’s suite and photo session arranged.' } },
      ],
    },
    {
      layout: 'text', tone: 'navy',
      eyebrow: 'Corporate and brands',
      title: 'For organisations, the same care.',
      blocks: [
        { cols: { n: 2, items: [
          { h: 'Corporate hospitality', t: 'Executive travel, visiting delegations, board dinners, client entertainment and retreats. One NOYA contact holds the programme and stays accountable for it, from the first proposal to the final account.', more: 'NOYA Corporate' },
          { h: 'Brand experiences and productions', t: 'Launches, press and creator trips, VIP dinners and gifting. For shoots: locations, permissions through licensed partners, crew and talent hospitality, and on-site coordination.', more: 'NOYA Brands & Productions' },
        ] } },
        { gap: 10 },
        { photos: { imgs: ['sage-dishes', 'sage-plating'], h: 92, cols: '1fr 1fr' } },
      ],
    },
    {
      layout: 'split', side: 'left', img: 'giza-terrace-lunch', pos: '82% 50%',
      eyebrow: 'Egypt',
      title: 'Where our knowledge\nruns deepest.',
      blocks: [
        { p: 'Egypt is at the centre of NOYA. We know its hotels and villas, its drivers and guides, the right hour to arrive at a monument and the people to call when a day needs rearranging.' },
        { list: { items: [
          '*Cairo and Giza* · the Pyramids, the Grand Egyptian Museum, grand hotels and favourite tables',
          '*Luxor and Aswan* · the Nile, the Valley of the Kings, riverside hotels and private sailing',
          '*El Gouna and the Red Sea* · marinas, yachts, reefs and unhurried resort days',
          '*The North Coast* · summer villas, beach clubs and the Mediterranean season',
        ] } },
        { note: 'Access to monuments and heritage sites is subject to the permissions and opening arrangements of the relevant authorities.' },
      ],
    },
    {
      layout: 'cinematic', img: 'st-tropez-bay', pos: '50% 30%',
      eyebrow: 'Beyond Egypt',
      title: 'Worldwide, through people we know.',
      blocks: [
        { p: 'The Mediterranean summer, Europe’s cities and journeys further afield, arranged through properties, drivers and specialists we have vetted, with trusted partners introduced where they are better placed to deliver.' },
        { list: { two: true, items: ['Marbella and the Costa del Sol', 'Mykonos and the Greek islands', 'Saint-Tropez and Cannes', 'London, Paris and European cities', 'The Alps in winter', 'Long-haul and family holidays'] } },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'How we work',
      title: 'One person, from the first request to the journey home.',
      blocks: [
        { steps: [
          { h: 'Listen', t: 'We start with how you like to travel and live, and what this particular request is for.' },
          { h: 'Propose', t: 'Your NOYA contact presents a considered recommendation, with alternatives only where they are worth having.' },
          { h: 'Confirm', t: 'Nothing is booked until you approve it, and every confirmation reaches you in writing.' },
          { h: 'Remain close', t: 'We stay available before, during and after the journey, and adjust when plans change.' },
        ] },
        { note: ROLE },
      ],
    },
    {
      layout: 'closing', img: 'robe-terrace', h: 112, pos: '50% 40%',
      eyebrow: 'Begin with a request',
      title: 'Tell us what you have in mind.',
      blocks: [
        { p: 'Most relationships with NOYA begin with a single request. Send it by email or WhatsApp, as briefly as you like, and we will reply personally.' },
        { contact: { founder: true } },
        { collection: 'NOYA Private Desk · NOYA Corporate · NOYA Brands & Productions · NOYA Trade & Partners. Each is available on request; NOYA Selected Work is shared privately.' },
      ],
    },
  ],
};
