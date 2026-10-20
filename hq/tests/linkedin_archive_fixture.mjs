// A synthetic LinkedIn data download for the UI tests (made-up people only): Connections.csv and messages.csv as LinkedIn writes
// them, packed into a real .zip (deflate), and the report shape hq_linkedin_archive returns after an import.
import zlib from 'node:zlib';

export const CONNECTIONS_CSV = 'Notes:\n"When exporting your connection data, you may notice that some of the email addresses are missing."\n\n'
  + 'First Name,Last Name,URL,Email Address,Company,Position,Connected On\n'
  + 'Sara,Khalil,https://www.linkedin.com/in/sara-khalil,,"Aman Resorts, Ltd",Director of Sales,01 May 2024\n'
  + 'Omar,Nasser,https://www.linkedin.com/in/omarn,,YKONE Middle East,Partner,15 Jan 2023\n'
  + 'Omar,Nasser,https://uk.linkedin.com/in/OmarN/,,YKONE Middle East,Partner,15 Jan 2023\n'
  + 'Bad,Row,https://example.com/x,,X,Y,01 Jan 2020\n';

// Four real messages in three conversations; one repeated line, one unsent draft and one spam message are left out.
export const MESSAGES_CSV = 'CONVERSATION ID,CONVERSATION TITLE,FROM,SENDER PROFILE URL,TO,RECIPIENT PROFILE URLS,DATE,SUBJECT,CONTENT,FOLDER,IS MESSAGE DRAFT\n'
  + 'c-1,,Adam Test,https://www.linkedin.com/in/adam-test,Sara Khalil,https://www.linkedin.com/in/sara-khalil,2024-05-02 09:15:00 UTC,,"<p>Hello Sara, lovely to meet. About Egypt next spring.</p>",INBOX,No\n'
  + 'c-1,,Sara Khalil,https://www.linkedin.com/in/sara-khalil,Adam Test,https://www.linkedin.com/in/adam-test,2024-05-03 10:00:00 UTC,,"Thanks Adam, yes, let us talk.",INBOX,No\n'
  + 'c-2,,Adam Test,https://www.linkedin.com/in/adam-test,Omar Nasser,https://www.linkedin.com/in/omarn,2026-09-01 08:00:00 UTC,,Hi Omar,INBOX,No\n'
  + 'c-2,,Adam Test,https://www.linkedin.com/in/adam-test,Omar Nasser,https://www.linkedin.com/in/omarn,2026-09-01 08:00:00 UTC,,Hi Omar,INBOX,No\n'
  + 'c-3,Group,Lina Intro,https://www.linkedin.com/in/lina-intro,"Adam Test, Omar Nasser","https://www.linkedin.com/in/adam-test,https://www.linkedin.com/in/omarn",2026-09-02 08:00:00 UTC,,Introducing you two,INBOX,No\n'
  + 'c-4,,Adam Test,https://www.linkedin.com/in/adam-test,Xavier,https://www.linkedin.com/in/xavier,2026-09-03 08:00:00 UTC,,unsent words,INBOX,Yes\n'
  + 'c-5,,Spammer,https://www.linkedin.com/in/spam,Adam Test,https://www.linkedin.com/in/adam-test,2026-09-03 08:00:00 UTC,,buy now,SPAM,No\n';

// A minimal .zip writer (local headers, central directory, end record). The reader in HQ uses the central directory only.
export function zip(files) {
  const parts = []; const central = []; let off = 0;
  for (const f of files) {
    const name = Buffer.from(f.name); const raw = Buffer.from(f.data); const body = f.deflate ? zlib.deflateRawSync(raw) : raw; const method = f.deflate ? 8 : 0;
    const crc = zlib.crc32 ? zlib.crc32(raw) : 0;
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE(method, 8); lh.writeUInt32LE(crc, 14);
    lh.writeUInt32LE(body.length, 18); lh.writeUInt32LE(raw.length, 22); lh.writeUInt16LE(name.length, 26);
    parts.push(lh, name, body);
    const ch = Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6); ch.writeUInt16LE(method, 10); ch.writeUInt32LE(crc, 16);
    ch.writeUInt32LE(body.length, 20); ch.writeUInt32LE(raw.length, 24); ch.writeUInt16LE(name.length, 28); ch.writeUInt32LE(off, 42);
    central.push(ch, name);
    off += 30 + name.length + body.length;
  }
  const cd = Buffer.concat(central); const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(files.length, 8); end.writeUInt16LE(files.length, 10); end.writeUInt32LE(cd.length, 12); end.writeUInt32LE(off, 16);
  return Buffer.concat([...parts, cd, end]);
}
export const ARCHIVE_ZIP = zip([
  { name: 'Profile.csv', data: 'First Name,Last Name\nAdam,Test\n' },
  { name: 'guide_messages.csv', data: 'not,the,messages,file\n' },
  { name: 'Connections.csv', data: CONNECTIONS_CSV, deflate: true },
  { name: 'messages.csv', data: MESSAGES_CSV, deflate: true },
]);

const P = (o) => ({ in_crm: false, profile_url: `https://www.linkedin.com/in/${o.slug}`, connection_id: o.connection_id || null, ...o });
export const ARCHIVE_EMPTY = { ok: true, connections: 0, messages: 0, conversations: 0, states: {}, note: 'Read-only history.' };
export const ARCHIVE_REPORT = {
  ok: true, imported_at: '2026-10-20T09:00:00Z', self_known: true, connections: 2, people_from_messages_only: 1, messages: 4, conversations: 3, conversations_matched: 2,
  states: { DORMANT: 1, REPLIED_BEFORE: 2, CONNECTED: 1 }, matched_contacts: 1, matched_companies: 1,
  companies_new: { count: 1, top: [{ company: 'Aman Resorts, Ltd', people: 1, two_way: 1, best: 3, best_state: 'DORMANT', person: 'Sara Khalil' }] },
  warm_destination_egypt: [P({ slug: 'omarn', connection_id: '00000000-0000-0000-0000-0000000000c1', person: 'Omar Nasser', role: 'Partner', company: 'YKONE Middle East', state: 'REPLIED_BEFORE',
    reason: '2 messages (1 from them) · last 02 Sep 2026 · introduction or referral', last_at: '2026-09-02T08:00:00Z', recency: 'Recent: last message 02 Sep 2026', project: 'A YKONE creator trip in Egypt' })],
  connected_destination_egypt: [],
  dormant: [P({ slug: 'sara-khalil', person: 'Sara Khalil', role: 'Director of Sales', company: 'Aman Resorts, Ltd', state: 'DORMANT', reason: '2 messages (1 from them) · last 03 May 2024',
    last_at: '2024-05-03T10:00:00Z', recency: 'Last message May 2024: old, reopen personally, not a live lead' })],
  warm: [],
  introductions: [P({ slug: 'omarn', person: 'Omar Nasser', company: 'YKONE Middle East', state: 'REPLIED_BEFORE', recency: 'Recent: last message 02 Sep 2026',
    intro: { at: '2026-09-02T08:00:00Z', by: 'Lina Intro', title: 'Group' } })],
  review: { count: 1, top: [P({ slug: 'lina-intro', person: 'Lina Intro', state: 'REPLIED_BEFORE', review: 'Same name as a CRM contact (Elsewhere Ltd): confirm before linking' })],
    warm_not_in_crm: 1, warm_not_in_crm_top: [P({ slug: 'sara-khalil', person: 'Sara Khalil', company: 'Aman Resorts, Ltd', state: 'DORMANT', recency: 'Last message May 2024: old, reopen personally, not a live lead' })],
    do_not_contact: [] },
  duplicates_prevented: { in_files: 2, connections_already_known: 1, messages_already_imported: 0, linked_to_existing_crm_contacts: 1, message_people_linked_by_name: 0 },
  note: 'Read-only history from Adam\'s own LinkedIn download. No CRM person or company is created from it and nothing is sent.',
};
export const HISTORY = [
  { at: '2026-09-02T09:00:00Z', out: false, who: 'Omar Nasser', title: 'Group', text: 'Thanks Adam, good to hear from you.', group: true },
  { at: '2026-09-01T08:00:00Z', out: true, who: 'Adam Test', title: null, text: 'Hi Omar', group: false },
];
