# NOYA Studio

Premium NOYA documents from data, one house style for every lane. Studio carries an opportunity from first reply to delivery:

**Reply / Meeting → Concept → Brief → Proposal → Project**, plus client and operations itineraries and the NOYA Private overview.

Nothing in Studio sends anything. Adam reviews every document and sends it himself.

## Operating mode: three output levels

Studio exists to convert opportunities into projects and revenue, not to produce documents. Each case says where the relationship
stands, and the build produces only what that relationship has earned:

| Level | Output | When |
|---|---|---|
| 1 · Email idea | `email`: a short concept inside the email itself (under 150 words), no attachment | Any prospect, including cold |
| 2 · One-page concept | `onepage`: the idea, three options, why now, next step and contact on one A4 page | Warm (they replied), or cold but strong (a dated public trigger) |
| 3 · Full brief / proposal | `master` (the 2–3 page brief), `concept`, `brief`, `proposal`, `itinerary`, `desk`, `project`, `ops` | After demonstrated interest, a meeting or an actual brief; a proposal only when earned |

`relationship.state` is `cold`, `warm`, `engaged` or `declined`. Warm, engaged and declined cite a VERIFIED fact (the reply, the
meeting, the decline); a strong cold opportunity cites its trigger in `strong`. A document above the earned level builds only when the
case lists it in `hold` (prepared ahead, not to be sent); otherwise the build stops. A declined company gets nothing sendable.

**Tracking.** Every output prepared for a company is a row in Supabase `studio_outputs` (level, email and attachment, Gmail draft and
thread, status PREPARED / HELD / SENT / CANCELLED, send-after date). `studio_outputs_refresh()` runs every 30 minutes and fills
sent → reply → meeting → proposal → won from evidence only: the NOYA mailbox import, CRM meetings and meeting tasks, Studio proposals
marked SENT, recorded proposal values and the opportunity's won date. `studio_output_status` shows each output's next step,
`studio_conversion` the funnel by level (value counts only contracted values recorded on won work), and `studio_queue` the companies
that warmed in the last 30 days with no Studio output since, with the level they have earned.

**Drafts and attachments.** Cover emails are prepared as unsent Gmail drafts in the existing thread. The Gmail connector accepts
attachments only as inline content and cannot fetch a stored file, so no PDF is attached automatically. The draft text therefore
never says "attached" (the email builder refuses it and the gate checks it); it stands on its own, and the PDF is Adam's one action:
**ATTACH APPROVED PDF**. Each output records the attachment's provenance in `studio_outputs.evidence.attachment`: document and version,
approval state, document hash, filename, PDF hash and size, and where the file came from. `studio_output_status.next_step` and the
opportunity's CRM next action name the file. Only APPROVED documents are attached; a document awaiting approval reads
"Adam to approve the document and timing". The repository is public, so approved PDFs are not stored in git.

```
studio/cases/<slug>.json          one live opportunity: facts (with provenance), people, timeline, status, and the idea per stage
studio/masters/verticals.mjs      the master systems: Brand · Campaign · Production, Weddings, Media / Podcast, NOYA Private,
                                  Travel / Concierge, Corporate / White-label, Founder retreats (each on its CRM product desk)
studio/masters/stages.mjs         stage builders (note, email, onepage, concept, brief, master, proposal, project, itinerary, ops,
                                  desk) and the level gate
studio/masters/reviewer.mjs       the Brand & Quality Reviewer: the last gate before a client document can read READY TO SEND
studio/masters/library.mjs        NOYA's approved wording (Partner Guide, Brands Proposal, NOYA Private) and the contact block
studio/templates.mjs              A4 page and block templates; cover variants navy / paper / split
studio/brand/brand.css            navy #061422, off-white #F7F7F7, hairlines; Cormorant Garamond + Jost (local, OFL)
studio/brand/images.json          NOYA's approved photo library (Drive IDs, subjects, never-list); photos cached in brand/images/
                                  (not committed: the repository is public)
studio/brand/logo.svg             the central logo (not yet supplied; the typeset NOYA wordmark is used until it is)
studio/render.mjs                 JSON -> HTML -> PDF (Chromium); pages paginate themselves; fails on overflow or missing fonts
studio/build.mjs                  case -> stage documents -> PDFs (+ an internal pack when a case has several internal documents),
                                  then the reviewer on every client document (studio/out/<slug>.review.json)
studio/record.mjs                 prints the SQL that records a case's documents in Supabase studio_documents
studio/tests/acceptance.mjs       the QA gate: builds every case and preview and checks the rules below
studio/documents/                 generated document JSON for live cases (committed: the record of what Adam reviewed)
studio/examples/                  template previews ("Template preview · no client"), one per lane without a live case
studio/out/                       rendered PDFs, page PNGs and HTML (not committed; re-render from the JSON)
```

Build a case: `node studio/build.mjs studio/cases/nados-forever-is-now.json` (or name stages: `... concept brief`).
Run the gate: `node studio/tests/acceptance.mjs`.

## Stages

| Stage | Audience | What it is |
|---|---|---|
| `note` | Internal | Opportunity note after a reply or meeting: where it stands, earned level, facts with provenance, our reading, next document, questions, objections, rules |
| `email` | Client | Level 1: the idea in the email itself; also the cover note for a Level 2 or 3 attachment |
| `onepage` | Client | Level 2: the concept on one page (never paginates; overflow fails the build) |
| `concept` | Client | The idea: three options, why now (cited facts only), who leads / what NOYA delivers, an example journey, next step |
| `brief` | Client | The brief we need, pre-filled with what we know (from the conversation, or from our concept, and it says which) |
| `master` | Client | Level 3 master brief, two or three pages with NOYA photos (below). The default Level 3 document after a meeting |
| `proposal` | Client | Understanding, scope, programme, fees, assumptions. Marked *Draft · fees not approved · not for client* until Adam approves fees |
| `project` | Internal | Project book: workstreams, milestones, suppliers (named only once confirmed), approvals, risks |
| `itinerary` | Client | Day-by-day programme, marked indicative |
| `ops` | Internal | Operations itinerary: every movement with location, supplier, contact and status; escalation; contingencies |
| `desk` | Client | NOYA Private · Egypt Desk overview for a representative (agency, family office), no client named |

Every internal document carries *Internal · not for client* on its cover and every page.

## Case file

A case holds only what we can source. Required: `slug`, `vertical`, `company`, `party` (short name used in copy), `prepared_for`,
`date`, `status`, `relationship`, `people`, `facts`, `need`, `build`; optional `strong` and `hold`. Per stage: `email`, `concept`
(also feeds `onepage`), `brief`, `proposal`, `project`, `itinerary`, `desk`.

Each fact has `id`, `text`, `source` and `class`: `VERIFIED` (Gmail, CRM), `PUBLIC` (cited press or the company's own site),
`NOYA MATERIAL` (approved NOYA documents), `INFERRED`, `UNVERIFIED`. Client "why" rows cite a fact by id, and only VERIFIED,
PUBLIC or NOYA MATERIAL facts can print in a client document; INFERRED and UNVERIFIED stay in the internal note.

## Rules (enforced by the builders and the gate)

- The master supplies structure and NOYA's approved wording; the case supplies every fact and the idea. A builder stops if the
  case lacks what a stage needs, so nothing is padded with invented content.
- No past NOYA work, client lists, portfolio, case studies, guarantees or luxury clichés. People named in a document must belong
  to that case.
- Fees print only when recorded with `fees_approved_by`; otherwise "Not recorded" and the Draft flag.
- Venues, access and dates are always subject to permits, approvals and availability (concept, brief, itinerary carry the note).
- A client document without a Draft flag shows no "To confirm" or "Not recorded" values.
- Studio code makes no network or mail calls.
- The level gate: nothing above the earned level unless held; a one-page concept is one page; an email idea stays under 150 words.

## Master brief (Level 3)

A tailored two or three page brief (`master` in the case; file `<case>-brief.json`, label *Brief*):

1. **NOYA × CLIENT**: the title, a full-bleed photo, the positioning in one paragraph, *why Egypt / why now* (at least two cited
   rows) and who it is prepared for.
2. **The idea**: concept, formats, journey, places, hospitality, production and one example (for instance an evening), as blocks.
3. **What NOYA handles**: roles, commercial value, places, and a navy band with the next step and the contact.

The builder stops without a title, positioning, hero photo, at least two why rows and a next step on the last page; it never runs
past three pages. **Agency mode** (YKONE and similar): the agency brings the vision and the client brief; NOYA brings the Egypt side
to life under the agency's name. The brief never tells an agency how to do its own creative work and never quotes savings. An
experience such as a dinner describes the setting, the movement and the hospitality; it never presents a chef or a menu as
confirmed, and every venue carries the permits note.

**Photos.** Any block or page with `"img": "<key>"` takes a photo from `brand/images.json` (NOYA's website library). Keys on the
never-list (rights or relevance) and keys missing from the manifest stop the render. Captions name places, never past client work.
Photos marked `low_res` go only in small slots (height 45 mm or less). For print, each cached photo has a `<name>.print.jpg` copy
(long edge 1800 px, JPEG quality 80) that the renderer prefers, so a three-page brief stays around 1.5 MB.

## Brand & Quality Reviewer

`studio/masters/reviewer.mjs` reads each rendered client document as the client would and records a check list in
`studio/out/<slug>.review.json`, then in `studio_documents.qa.reviewer`:

factual accuracy (no INFERRED or UNVERIFIED fact printed) · correct client (no other case's names) · correct relationship stage
(level earned, not held) · no internal notes · no fabricated claims (past work, client lists, guarantees, savings or percentages,
exclusivity, access or permits, confirmed menus, "attached") · no generic luxury wording · British spelling and no repeated words
· correct imagery (a master carries at least three library photos; low-resolution photos only in small slots) · NOYA branding (fonts
and mark) · layout and pagination (no overflow; a master two or three pages; a one-page one page) · file size (8 MB or less, so it
can be emailed) · contact details · commercially useful (names the client and asks for one next step).

## Records

`studio_documents` (Supabase) holds one row per document version: type, vertical, stage, audience (CLIENT / INTERNAL), status
(DRAFT, FOR_REVIEW, APPROVED, SENT, SUPERSEDED; Adam sets APPROVED and SENT), the JSON's hash and path, sources and review notes.
A changed document becomes the next version and supersedes earlier unapproved versions; APPROVED and SENT rows are never touched.

**Readiness** (`ready_class`, `ready_reason`, `ready_checked_at`, set by `record.mjs`) says whether Adam could send a document now:

| Class | Meaning |
|---|---|
| READY TO SEND | A client document that passed every reviewer check; Adam approves (if not yet) and sends |
| NEEDS UPDATE | A client document that failed a check (the reason names it), is still a draft, or has not been reviewed |
| INTERNAL ONLY | Notes, project books, operations itineraries |
| SUPERSEDED | Replaced by a later version; kept for history |
| HOLD | Prepared ahead of the relationship (above the earned level) or parked |

The Dashboard's *Studio ready* list (`studio_ready_board()`) shows only READY TO SEND documents not yet sent, each with its cover
email draft. Nothing is deleted: a replaced version stays as SUPERSEDED with its reason.

## Logo

Drop the master SVG (single colour, `fill="currentColor"`) into `brand/logo.svg` and re-build; every template and document picks it
up centrally, so no document is edited by hand. The
latest approved brochure (Drive 19kn1pbjxXeWNmPAJ8h3MCHDFDU83eHav) is 19 MB, and this cloud environment cannot reach Drive or
noyaconcierge.com, so its logo could not be extracted here.

## Blocks

`section`, `lead`, `p`, `h3`, `note`, `quote`, `gap`, `rule`, `roles`, `ledger`, `options`, `feature`, `journey`, `form`, `steps`,
`fees`, `kv`, `facts`, `timeline`, `callout`, `table`, `itinerary`, `check`, and for the master brief `gallery` (photos with
captions), `formats` (tiles), `evening` (photo, ledger and note), `value` and `places`. A page with `"kind": "closing"` is navy and can carry
a `contact`.
