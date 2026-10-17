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
| 3 · Full brief / proposal | `concept`, `brief`, `proposal`, `itinerary`, `desk`, `project`, `ops` | After demonstrated interest, a meeting or an actual brief |

`relationship.state` is `cold`, `warm`, `engaged` or `declined`. Warm, engaged and declined cite a VERIFIED fact (the reply, the
meeting, the decline); a strong cold opportunity cites its trigger in `strong`. A document above the earned level builds only when the
case lists it in `hold` (prepared ahead, not to be sent); otherwise the build stops. A declined company gets nothing sendable.

**Tracking.** Every output prepared for a company is a row in Supabase `studio_outputs` (level, email and attachment, Gmail draft and
thread, status PREPARED / HELD / SENT / CANCELLED, send-after date). `studio_outputs_refresh()` runs every 30 minutes and fills
sent → reply → meeting → proposal → won from evidence only: the NOYA mailbox import, CRM meetings and meeting tasks, Studio proposals
marked SENT, recorded proposal values and the opportunity's won date. `studio_output_status` shows each output's next step,
`studio_conversion` the funnel by level (value counts only contracted values recorded on won work), and `studio_queue` the companies
that warmed in the last 30 days with no Studio output since, with the level they have earned.

**Drafts.** Cover emails are prepared as unsent Gmail drafts in the existing thread. The Gmail connector cannot attach the PDF from
this environment, so the draft says the file is attached and Adam attaches the PDF before sending.

```
studio/cases/<slug>.json          one live opportunity: facts (with provenance), people, timeline, status, and the idea per stage
studio/masters/verticals.mjs      the master systems: Brand · Campaign · Production, Weddings, Media / Podcast, NOYA Private,
                                  Travel / Concierge, Corporate / White-label, Founder retreats (each on its CRM product desk)
studio/masters/stages.mjs         stage builders (note, email, onepage, concept, brief, proposal, project, itinerary, ops, desk)
                                  and the level gate
studio/masters/library.mjs        NOYA's approved wording (Partner Guide, Brands Proposal, NOYA Private) and the contact block
studio/templates.mjs              A4 page and block templates; cover variants navy / paper / split
studio/brand/brand.css            navy #061422, off-white #F7F7F7, hairlines; Cormorant Garamond + Jost (local, OFL)
studio/brand/logo.svg             the central logo (not yet supplied; the typeset NOYA wordmark is used until it is)
studio/render.mjs                 JSON -> HTML -> PDF (Chromium); pages paginate themselves; fails on overflow or missing fonts
studio/build.mjs                  case -> stage documents -> PDFs (+ an internal pack when a case has several internal documents)
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

## Records

`studio_documents` (Supabase) holds one row per document version: type, vertical, stage, audience (CLIENT / INTERNAL), status
(DRAFT, FOR_REVIEW, APPROVED, SENT, SUPERSEDED; Adam sets APPROVED and SENT), the JSON's hash and path, sources and review notes.
A changed document becomes the next version and supersedes earlier unapproved versions; APPROVED and SENT rows are never touched.

## Logo

Drop the master SVG (single colour, `fill="currentColor"`) into `brand/logo.svg` and re-build; every template and document picks it
up centrally, so no document is edited by hand. The
latest approved brochure (Drive 19kn1pbjxXeWNmPAJ8h3MCHDFDU83eHav) is 19 MB, and this cloud environment cannot reach Drive or
noyaconcierge.com, so its logo could not be extracted here.

## Blocks

`section`, `lead`, `p`, `h3`, `note`, `quote`, `gap`, `rule`, `roles`, `ledger`, `options`, `feature`, `journey`, `form`, `steps`,
`fees`, `kv`, `facts`, `timeline`, `callout`, `table`, `itinerary`, `check`. A page with `"kind": "closing"` is navy and can carry
a `contact`.
