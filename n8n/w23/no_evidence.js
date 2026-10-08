// Nothing published was found on the pages read or in the snippets: record the attempt (NO_EMAIL_FOUND unless the company
// already has a route on file) so the company is retried no sooner than 14 days and at most 3 times.
return $input.all().map(function (x) { var c = x.json.company;
  return { json: { p: { company_id: c.company_id, test_tag: c.test_tag || '', found_domain: x.json.found_domain || '', people: [], emails: [], research: x.json.research, usage: [] }, company: c.company, emails: 0, people: 0 } }; });
