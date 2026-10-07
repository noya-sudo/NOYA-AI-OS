// Group the search results per company and build one extraction request (Flash-Lite, JSON schema).
var queue = $('Enrichment Queue').first().json.items || [];
var qs = $('Build Queries').all();
var by = {};
$input.all().forEach(function (r, i) {
  var meta = qs[i] ? qs[i].json : null; if (!meta) return;
  var org = (r.json && r.json.organic) || [];
  if (!by[meta.ci]) by[meta.ci] = { LINKEDIN: [], INSTAGRAM: [], EMAIL: [] };
  by[meta.ci][meta.kind] = org.slice(0, 8).map(function (o) { return { title: o.title || '', link: o.link || '', snippet: o.snippet || '' }; });
});
var SYS = 'You extract contact routes for one company from search results. Use ONLY the results given. A person counts only if a result shows they currently work at this company (the company name or domain appears in the same result). Copy names, roles, emails and Instagram handles exactly as written; never guess or construct an email. For each item give the number of the result it came from. Prefer decision makers: founder, owner, CEO, managing director, general manager, director of sales or marketing, partnerships, PR or communications, creative director, producer, host. Ignore former roles and unrelated namesakes. Return JSON only.';
var out = [];
queue.forEach(function (c, i) {
  var g = by[i] || { LINKEDIN: [], INSTAGRAM: [], EMAIL: [] };
  var all = g.LINKEDIN.concat(g.INSTAGRAM, g.EMAIL);
  if (!all.length) { out.push({ json: { company: c, results: [], has_results: false } }); return; }
  var lines = all.map(function (o, j) { return '[' + (j + 1) + '] ' + o.title + ' | ' + o.link + ' | ' + o.snippet; }).join('\n');
  var prompt = 'Company: ' + c.company + (c.domain ? ' (domain ' + c.domain + ')' : '') + (c.country ? ', ' + c.country : '') + (c.company_type ? ', ' + c.company_type : '') +
    '\nAlready known people: ' + JSON.stringify(c.people || []) + '\n\nSEARCH RESULTS:\n' + lines;
  var request = {
    systemInstruction: { parts: [{ text: SYS }] },
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: { temperature: 0, maxOutputTokens: 1024, responseMimeType: 'application/json',
      responseSchema: { type: 'OBJECT', properties: {
        people: { type: 'ARRAY', items: { type: 'OBJECT', properties: { first_name: { type: 'STRING' }, last_name: { type: 'STRING' }, position: { type: 'STRING' },
          email: { type: 'STRING' }, instagram: { type: 'STRING' }, result: { type: 'INTEGER' } }, required: ['first_name', 'last_name', 'result'] } },
        company_instagram: { type: 'STRING' },
        inboxes: { type: 'ARRAY', items: { type: 'OBJECT', properties: { email: { type: 'STRING' }, purpose: { type: 'STRING' }, result: { type: 'INTEGER' } }, required: ['email', 'result'] } }
      }, required: ['people'] } }
  };
  out.push({ json: { company: c, results: all, has_results: true, request: request } });
});
return out;
