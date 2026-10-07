// One filmable concept per media / podcast / creator target (Adam, 7 Oct 2026): what could be filmed, where, what NOYA
// arranges, and why it helps NOYA. Uses only the stored evidence about the company; never invents audiences or facts.
var items = ($input.first().json.items) || [];
var BACKDROPS = ['Pyramids of Giza', 'Mena House', 'Grand Egyptian Museum', 'The Nile', 'Aswan', 'Luxor', 'El Gouna', 'Red Sea', 'Western Desert', 'Cairo', 'Private villa or resort'];
var SYSTEM = [
  'You propose ONE filmable concept in Egypt for a media company, podcast, YouTube show, publication, creator or production company.',
  'Rules: use ONLY the facts in EVIDENCE about the company. Never invent audience size, episode names, awards, people, dates or past work.',
  'concept: one or two sentences describing what could actually be filmed, fitted to what the company does (a conversation, an episode, a feature, a series segment).',
  'backdrop: choose exactly one from the list.',
  'noya_role: what NOYA would arrange (location access, permits, hotel, transport, hospitality, itinerary, local production), one sentence.',
  'commercial_value: why this helps NOYA commercially (visibility with their audience, content NOYA can reuse, a relationship), one sentence, no claims about numbers.',
  'Plain British English, understated, no superlatives. Return JSON only.'
].join('\n');
return items.map(function (it) {
  var user = ['COMPANY: ' + it.company + (it.country ? ' (' + it.country + ')' : '') + (it.company_type ? ', ' + it.company_type : ''),
              'EVIDENCE: ' + (it.evidence || ''), 'BACKDROPS: ' + BACKDROPS.join('; ')].join('\n');
  return { json: Object.assign({}, it, { backdrops: BACKDROPS, request: {
    systemInstruction: { parts: [{ text: SYSTEM }] },
    contents: [{ role: 'user', parts: [{ text: user }] }],
    generationConfig: { temperature: 0.5, maxOutputTokens: 400, responseMimeType: 'application/json',
      responseSchema: { type: 'OBJECT', properties: { concept: { type: 'STRING' }, backdrop: { type: 'STRING', enum: BACKDROPS },
        noya_role: { type: 'STRING' }, commercial_value: { type: 'STRING' } }, required: ['concept', 'backdrop', 'noya_role', 'commercial_value'] } } } }) };
});
