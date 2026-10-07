// Not searchable (no full name, or the deterministic checks already close it): save with the role not checked.
return $input.all().map(function (x) { return { json: { task_id: x.json.task_id, role_check: 'NOT_CHECKED', evidence_url: null, why_now_stale: x.json.why_now_stale } }; });
