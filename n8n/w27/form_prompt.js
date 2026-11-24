// W27 forms: one Flash-Lite call per qualified commercial form. The model writes only the subject and the message; every other
// field is filled deterministically from the sender profile in Supabase. Nothing is submitted: a prepared form waits in HQ
// (Outreach > Form ready) for Adam's approval, and form_prepare_save runs the form quality check before anything is shown.
var items = $input.all().map(function (x) { return x.json; }).filter(function (f) { return f && f.form_id; });
var SYSTEM = [
  'You write one short message for a company\'s website enquiry form, from Adam Elshazly, Founder of NOYA Concierge, a global concierge and lifestyle management company with specialist on-the-ground capability across Egypt.',
  'FIRST decide fit. fit=true only if EVIDENCE shows a business that could plausibly buy, refer or co-deliver NOYA work in Egypt for the IDEA (planners, agencies, travel companies, clubs, family offices, talent or sports management, brands, hospitality groups). fit=false if EVIDENCE shows a different kind of business (a manufacturer, photographer or other supplier, bank, law or accounting firm, logistics company, directory or marketplace, car dealer), an Egypt-based competitor or supplier, or a consumer-only service. If fit=false, give a short fit_reason and leave subject and message empty.',
  'Rules for the message (only when fit=true):',
  '1. Facts about the company come ONLY from EVIDENCE. WHY NOW and IDEA are our internal hypotheses: use them to choose the idea, never state them as facts about the company. Never invent names, clients, numbers, dates, events, reviews, awards or past work.',
  '2. Open with "Hello," or "Dear <team> team,". The first sentence is about them, names the company and restates one concrete fact from EVIDENCE in plain words.',
  '3. Then one specific idea in Egypt that fits them, and what NOYA would handle on the Egypt side, in one or two sentences. NOYA appears once.',
  '4. End with one easy next step: ask whether a short introduction call would be useful, or who the right person would be. At most one question mark in the whole message.',
  '5. 70 to 115 words before the sign-off. No links, no lists, no flattery, no exclamation marks, no emojis.',
  '6. Never write: reaching out, I hope, wanted to introduce, world-class, unparalleled, elevate, seamless, bespoke, synergy, partnership opportunities, exclusive access, luxury experiences, complimentary, free of charge, all expenses paid, fam trip, based in Egypt.',
  '7. Never characterise them: no claims about their strategy, commitment, focus, needs, requirements or next move, and never "I note that" or "I noticed". State one plain fact from EVIDENCE (what they launched, opened, announced or run) and offer the idea as a possibility ("could", "if useful").',
  '8. Finish with the sign-off on two lines: "Adam Elshazly" then "Founder, NOYA Concierge".',
  'subject: plain, under 70 characters.',
  'Understated, confident, concise British English. Return JSON {"fit": true|false, "fit_reason": "...", "subject": "...", "message": "..."} only.'
].join('\n');
return items.map(function (f) {
  var max = f.max_chars ? Math.min(Number(f.max_chars) - 20, 950) : 950;
  var team = f.target_team ? f.target_team + ' team' : 'team';
  var user = [
    'COMPANY: ' + f.company + (f.stream ? ' (' + f.stream + ')' : ''),
    'FORM: ' + String(f.form_type || 'CONTACT').toLowerCase().replace(/_/g, ' ') + ' form on their official website, read by the ' + team + '.',
    f.person ? 'Decision maker on record (write "for the attention of" only if natural; never claim to know them): ' + f.person + (f.position ? ', ' + f.position : '') : '',
    'WHY NOW (internal hypothesis; never present it as a fact about them): ' + (f.why_now || ''),
    'IDEA (internal hypothesis; use only what EVIDENCE supports): ' + (f.project_idea || ''),
    'EVIDENCE: ' + (f.evidence || ''),
    'MAXIMUM LENGTH: ' + max + ' characters including the sign-off.'
  ].filter(Boolean).join('\n');
  return { json: Object.assign({}, f, { request: {
    systemInstruction: { parts: [{ text: SYSTEM }] },
    contents: [{ role: 'user', parts: [{ text: user }] }],
    generationConfig: { temperature: 0.4, maxOutputTokens: 700, responseMimeType: 'application/json',
      responseSchema: { type: 'OBJECT', properties: { fit: { type: 'BOOLEAN' }, fit_reason: { type: 'STRING' }, subject: { type: 'STRING' }, message: { type: 'STRING' } }, required: ['fit', 'fit_reason', 'subject', 'message'] } } } }) };
});
