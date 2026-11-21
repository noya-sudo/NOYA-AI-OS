// 06 · NOYA Selected Work — the updateable credentials document. Not a sixth brochure.
// Rules: an entry prints only when NOYA's records evidence a COMPLETED engagement (see docs/EVIDENCE_REGISTER.md).
// Anonymised by default; no client, hotel or supplier is named without written permission. No guest numbers, values or
// outcomes beyond what the records show. Update quarterly: add an entry object, rebuild with `node studio/brochures/build.mjs 06`.
//
// Photographs: none. An image beside an entry would read as a photograph of that engagement; add one only when it is.
// Entry template:
//   { entry: { meta: ['Category', 'Place', 'Month Year'], title: '…', brief: '…', delivered: '…', outcome: '…' } }
// Evidence for each entry is recorded (internally) in the evidence register before it is added here.

export default {
  code: '06',
  file: 'NOYA_06_Selected_Work_Q4-2026',
  title: 'NOYA Selected Work',
  short: 'NOYA Selected Work · Q4 2026',
  description: 'NOYA Selected Work: evidenced examples of completed NOYA engagements, anonymised. Updated quarterly.',
  audience: 'Prospects at proposal stage who ask for credentials; partners assessing NOYA as a delivery partner.',
  purpose: 'Show completed, evidenced work, separately from the five brochures so it can be updated each quarter.',
  pages: [
    {
      layout: 'cover',
      kicker: 'Credentials · Edition Q4 2026',
      title: 'NOYA Selected Work',
      line: 'Completed engagements, described from our records.\nAnonymised, as our clients would expect.',
      base: ['noyaconcierge.com', 'Updated quarterly'],
    },
    {
      layout: 'statement', tone: 'navy',
      eyebrow: 'How we present our work',
      title: 'Only work we can evidence.',
      blocks: [
        { p: 'Our clients choose NOYA partly because we do not talk about them. The work in this document is therefore described without names: no client, hotel or supplier is identified unless they have agreed to it in writing.' },
        { p: 'Each entry describes an engagement NOYA has completed, and only what our booking records, contracts and correspondence show. We do not include proposals, introductions or plans, and we do not estimate figures we cannot document.' },
        { p: 'The selection is reviewed each quarter. Further detail can be discussed privately.' },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'Selected work · 01',
      title: 'An international wedding party in Cairo.',
      approval: 'case study (client courtesy approval)',
      blocks: [
        { entry: {
          meta: ['Private occasion', 'Cairo', 'October 2025'],
          title: 'Guest accommodation and coordination for a destination wedding',
          brief: 'A couple marrying in Cairo needed rooms and on-the-ground coordination for guests travelling from abroad, at a five-star hotel, across the wedding days.',
          delivered: 'NOYA negotiated and contracted a group rate with the hotel, took guest bookings directly, managed the rooming list through successive revisions, arranged the couple’s suite and photo session, arranged rooms for the wedding planners and coordinated guest transport.',
          outcome: 'Guest rooms were contracted and paid through NOYA and reconciled with the hotel. The final rooming list was issued four days before the wedding.',
        } },
        { h3: 'What it involved' },
        { list: { two: true, items: ['Group rate negotiation and contract', 'Direct guest booking by WhatsApp', 'Rooming list and late changes', 'Couple’s suite and photo session', 'Planners’ accommodation', 'Payments and hotel reconciliation'] } },
      ],
    },
    {
      layout: 'text',
      eyebrow: 'What our records show',
      title: 'The work behind every entry.',
      blocks: [
        { p: 'An entry is added to this document only when the engagement is complete and its evidence is on file. For each one we hold:' },
        { cols: { n: 2, items: [
          { h: 'Contract or confirmation', t: 'The supplier agreement, booking confirmation or pro-forma issued in NOYA’s name.' },
          { h: 'Delivery', t: 'The correspondence showing the work was carried out: final lists, schedules, on-the-day coordination.' },
          { h: 'Payment', t: 'Records of the payments made in NOYA’s name to suppliers.' },
          { h: 'Permission', t: 'The client’s agreement to the way the work is described, and to any name or image used.' },
        ] } },
        { gap: 8 },
        { box: { h: 'New entries', t: 'Further engagements are added only once their evidence and permissions are in place.' } },
      ],
    },
    {
      layout: 'closing',
      eyebrow: 'References',
      title: 'Ask us about the detail.',
      blocks: [
        { p: 'If you would like to know more about any engagement, contact our founder directly.' },
        { contact: { founder: true } },
      ],
    },
  ],
};
