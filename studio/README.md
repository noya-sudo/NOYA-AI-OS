# NOYA Studio

Premium NOYA documents from data: **Brief → Concept → Proposal**. Itineraries, partner decks and NOYA Private desk briefs use the same block library.

```
studio/documents/<slug>.json   the content (source of truth, with sources and review notes)
studio/templates.mjs           A4 page and block templates
studio/brand/brand.css         navy #061422, off-white #F7F7F7, hairlines; Cormorant Garamond + Jost (local, OFL)
studio/brand/logo.svg          the central logo (not yet supplied; the typeset NOYA wordmark is used until it is)
studio/render.mjs              JSON -> HTML -> PDF (Chromium), plus page previews; fails if any page overflows
studio/out/                    rendered files (not committed; re-render from the JSON)
```

Render: `node studio/render.mjs studio/documents/ykone-egypt-brief.json`

Each output is recorded in Supabase `studio_documents` (status FOR_REVIEW → APPROVED → SENT, set by Adam), with its content,
sources and review notes. Studio never sends anything.

## Rules

- Every fact comes from Gmail, the CRM, NOYA's approved material (Partner Guide, brochures) or cited public press, and is listed
  in the document's `sources`. Nothing about past NOYA work, access, fees or numbers is invented.
- Fees in a proposal print only when recorded; otherwise "Not recorded".
- Venues and access are always "subject to permits and availability".
- Logo: drop the master SVG (single colour, `fill="currentColor"`) into `brand/logo.svg` and re-render; every document picks it up.
  Until then the cover and running heads use the typeset wordmark. The latest approved brochure (Drive 19kn1pbjxXeWNmPAJ8h3MCHDFDU83eHav)
  is 19 MB and this cloud environment cannot reach Drive or noyaconcierge.com, so its logo could not be extracted here.

## Blocks

`section`, `lead`, `p`, `h3`, `note`, `quote`, `roles` (two columns: they lead / NOYA delivers), `ledger` (label + text rows),
`options` (three concept cards), `feature`, `journey` (day-by-day), `form` (the brief we need), `steps`, `fees`, `gap`, `rule`.
A page with `"kind": "closing"` is navy and can carry a `contact`.
