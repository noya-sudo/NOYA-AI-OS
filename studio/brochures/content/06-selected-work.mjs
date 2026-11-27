// 06 · NOYA Selected Work — the selective credentials supplement, shared privately on request (not sent with every introduction).
// Rules: an entry prints only when NOYA's records evidence a COMPLETED engagement (see docs/EVIDENCE_REGISTER.md and the internal
// register in Drive). Anonymised by default; no client, hotel or supplier named without written permission; no guest numbers or values.
// Photographs: none. An image beside an entry would read as a photograph of that engagement; add one only when it is.
// Update quarterly: add an entry (and, where the record supports it, a step-by-step page), then `node studio/brochures/build.mjs 06`.
//
// Entry 01 checked against the original records (21–22 Nov 2026): group rate accepted 9 May 2025; planners' stay 19–21 May 2025;
// room block resized 11 Jul 2025; revised rates 31 Aug 2025; rooming lists 1–13 Oct 2025, final list 13 Oct; hotel payments Oct 2025;
// wedding 17 Oct 2025; guest transport stated by NOYA for 16–18 Oct 2025.

export default {
  code: '06',
  file: 'NOYA_06_Selected_Work',
  title: 'NOYA Selected Work',
  short: 'NOYA Selected Work · Q4 2026',
  description: 'NOYA Selected Work: completed NOYA engagements, described from our records and anonymised. Shared privately on request.',
  audience: 'Prospects at proposal stage who ask for credentials; partners assessing NOYA as a delivery partner.',
  purpose: 'Show real operational delivery, privately and selectively, separate from the five brochures so it can be updated each quarter.',
  pages: [
    {
      layout: 'cover',
      kicker: 'Credentials · Edition Q4 2026',
      title: 'NOYA Selected Work',
      line: 'Completed engagements, described from our records.\nAnonymised, as our clients would expect.',
      base: ['Shared privately on request', 'noyaconcierge.com'],
    },
    {
      layout: 'statement', tone: 'navy',
      eyebrow: 'Selected work',
      title: 'Discretion first.',
      blocks: [
        { p: 'Our clients choose NOYA partly because we do not talk about them. The engagements in this document are described without names, and exactly as our records show them.' },
        { p: 'Further detail can be discussed privately.' },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Selected work · 01',
      title: 'An international wedding party in Cairo.',
      blocks: [
        { entry: {
          meta: ['Private occasion', 'Cairo', 'October 2025'],
          title: 'Guest accommodation and coordination for a destination wedding',
          brief: 'A couple marrying in Cairo asked NOYA to secure rooms at group rates for guests travelling from the UK, Europe and the United States, and to act as the guests’ single point of contact.',
          delivered: 'NOYA negotiated the hotel’s group rate, arranged and paid for the wedding planners’ stay in May, resized the room block as numbers settled, took guest bookings directly and managed every cancellation, name change and late addition through to the final rooming list.',
          outcome: 'The final rooming list was issued four days before the wedding. Rooms were paid and reconciled with the hotel, and guests were moved between hotel and venue across three event days.',
        } },
        { h3: 'What it involved' },
        { list: { two: true, items: ['Group rate negotiation and contract', 'Direct guest bookings by email and WhatsApp', 'Rooming list, cancellations and late additions', 'The couple’s suite and wedding-day photo session', 'Accommodation for the wedding planners', 'Payments and reconciliation with the hotel'] } },
      ],
    },
    {
      layout: 'text', tone: 'navy',
      eyebrow: 'Selected work · 01 · The engagement',
      title: 'From first rate to final night.',
      blocks: [
        { steps: [
          { h: 'May 2025', t: 'Group rate agreed in writing with the hotel. Rooms arranged and paid for the wedding planners’ visit.' },
          { h: 'July 2025', t: 'Room block resized and stays extended as the guest list settled.' },
          { h: 'Aug–Sep 2025', t: 'Guest bookings taken directly; revised rates agreed with the hotel.' },
          { h: 'Early October', t: 'Rooming list revised as changes came in; payments made to the hotel.' },
          { h: '13 October', t: 'Final rooming list issued, four days before the wedding. Guest arrivals begin.' },
          { h: '16–18 October', t: 'The couple’s suite and photo session on the day; guests moved between hotel and venue across three event days.' },
        ] },
        { note: 'Client, hotel and suppliers are not named, for confidentiality.', mt: 6 },
      ],
    },
    {
      layout: 'closing',
      eyebrow: 'Private enquiries',
      title: 'Ask us about the detail.',
      blocks: [
        { p: 'To discuss this engagement, or how we would approach yours, contact our founder directly.' },
        { contact: { founder: true } },
      ],
    },
  ],
};
