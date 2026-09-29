const base = $('Build Contact Resolution Task').item.json;
// One open outreach task per opportunity.
// - An existing approval task (e.g. converted to a LinkedIn action or parked WAITING by Adam's
//   review) is kept exactly as it is: no title, text or due-date change.
// - A curated research task (CONTACT_RESEARCH) is refreshed in place instead of duplicated,
//   and its original research notes are kept under the new text.
if ($json.task_type === 'SALES_OUTREACH_APPROVAL') {
  return { json: { ...base, _existing_contact_task_id: $json.id, _keep_existing: true, _refresh_title: $json.title,
    _contact_resolution_text: $json.description, _keep_due_at: $json.due_at || null, priority: ($json.priority != null ? $json.priority : base.priority) } };
}
const MARK = '--- ORIGINAL RESEARCH NOTES ---';
const prev = String($json.description || '');
let notes = '';
if (prev.indexOf(MARK) !== -1) notes = prev.slice(prev.indexOf(MARK) + MARK.length).trim();
else if ($json.task_type === 'CONTACT_RESEARCH') notes = prev.trim();
const text = notes ? base._contact_resolution_text + '\n\n' + MARK + '\n' + notes : base._contact_resolution_text;
return { json: { ...base, _existing_contact_task_id: $json.id, _contact_resolution_text: text } };