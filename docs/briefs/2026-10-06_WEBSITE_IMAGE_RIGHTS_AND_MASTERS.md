# Website: image rights, masters and design freeze (6 Oct 2026)

**WEBSITE DESIGN FROZEN — CONTENT & GROWTH MODE.** No new design phase. The website repo's `CLAUDE.md` holds the rules; its `docs/QA_REPORT.md` and `docs/IMAGE_RIGHTS.md` hold the detail.

## What changed (live since 6 Oct 2026, commit `052bc2b` on noya-website `main`)

**Withdrawn, CEO decision 4B.**
- Old-site photographs whose source was never recorded: 25 keys, plus their crops.
- They are no longer deployed (404). The Studio ignores them if it still holds them.

**Replaced: 16 slots.**
- **NOYA's own first:** two El Gouna frames from the Edge Studios shoot (27 Apr 2025), faces unseen.
- **Then open-licence originals, credited on the Terms page:**
  - El Gouna lagoon (Marc Ryckaert, CC BY 4.0);
  - Aegean anchorages (dronepicr, CC BY 2.0);
  - a helicopter landing (Antti Leppänen, CC BY 4.0);
  - the Red Sea coast from the air (Tanya Dedyukhina, CC BY 3.0).
- **Text-led where no cleared photograph explains the words:**
  - the Bespoke Travel and Corporate heroes;
  - the chauffeurs card;
  - the Corporate card on Home and What We Do.

**Private Calendar.** The 9 events approved under 2A are on the site. Their HQ status waits on the SQL paste (`supabase/migrations/20261006090000_hq_pending_writes.sql`, NOT YET APPLIED).

**QA: all green.**
- 0 audit failures; 160/160 pages; SEO 145/145; end-to-end 46/46; Studio flow 30/30.
- Studio smoke test passed.
- One visual audit at 1440 and 390.
- Live smoke check 18/18.

## Still temporary or awaiting a supplier

- **Dinaia, 5 photographs:** upscaled screenshots, "Replace soon — master requested" (The Cyan; draft in noya@, not sent).
- **The Cyan:** written permission and credits for Dinaia, Wind of Fortune and Villa Serenade.
- **Consensio:** written permission and high-resolution files for Chalet Le Grenier (draft in noya@, not sent).
- **Grace La Margna:** media kit (permission needed; not used).
- **Pier 88 Pyramid Hills stills:** not reviewed (private folder).
- **Edge Studios shoot:** model consent not recorded, so only frames with faces unseen are used.

## Automation (approval-based; nothing publishes itself)

- **"NOYA – Drive masters → Sanity"** (n8n, inactive).
  - Reads the published rights register (`/seed/masters.json`) and uploads approved masters from the Drive folder "NOYA Website Masters (approved)" to Sanity as assets.
  - Mirrors open-licence originals into that folder.
  - The two NOYA masters used today are already copied there.
  - Needs the two credentials below.
- **"HQ approved events → Sanity drafts"** (n8n, inactive).
  - Creates Studio drafts only; a person publishes.

**CEO, once (never paste a token into chat):**
1. sanity.io/manage → project `yb8ubrdw` → API → Tokens → Editor token.
2. n8n → Credentials → Bearer Auth "Sanity (NOYA website)": paste the token there only.
3. n8n → Credentials → Google Drive OAuth2 API: sign in as noya@noyaconcierge.com.
