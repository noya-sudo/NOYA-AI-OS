// Nothing found by search: still record the attempt so the company is not re-searched for 14 days.
return $input.all().map(function (x) { return { json: { p: { company_id: x.json.company.company_id, people: [], inboxes: [], usage: [] }, company: x.json.company.company, kept: 0 } }; });
