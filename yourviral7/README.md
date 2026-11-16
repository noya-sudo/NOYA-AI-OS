# YOURVIRAL7 — TikTok GTA VI content engine

One folder, one database, one command. You drop media into `INBOX/`. The system ingests it, analyses it, writes and scores ideas,
edits 1080×1920 videos with voiceover and subtitles, checks quality and rights, queues posts, and builds a dashboard.

## Commands (Mac/Linux: `./yv7.sh …` · Windows: `yv7.cmd …`)
| Need | Command |
|---|---|
| **Start / resume** | `./yv7.sh start --resume` |
| **Health** | `./yv7.sh health` |
| **Stop everything now** | `./yv7.sh stop`  (or create an empty file called `STOP` in this folder) |
| One cycle and exit | `./yv7.sh scan` |
| See the queue | `./yv7.sh queue` |
| Confirm a post went live | `./yv7.sh posted <id> <tiktok-url>` |
| Switch to launch mode (after 19 Nov, own copy) | `./yv7.sh mode launch --confirm` |
| Posts per day (1–6) | `./yv7.sh cap 3` |

## First-time setup on your computer (once)
```
git clone … && cd NOYA-AI-OS/yourviral7 && ./install.sh        # Mac/Linux
powershell -ExecutionPolicy Bypass -File install\install_windows.ps1   # Windows
```
This installs FFmpeg, Tesseract and espeak-ng, creates a Python venv, downloads the natural Piper voice and the Whisper model,
and registers the service to start at login (launchd / systemd user / Task Scheduler).

## What you do
1. Drop files into `INBOX/` (any names; descriptive names help: `car flips off pier.mp4` becomes the hook).
   `INBOX/GAMEPLAY` your own GTA VI captures · `INBOX/PHOTOS` images · `INBOX/PRELAUNCH` your own prelaunch assets.
   TikTok Studio analytics CSVs or screenshots (with "analytics"/"insights"/"stats" in the name) can go anywhere in INBOX.
2. When notified, open `OUTPUT/SCHEDULED/<slot>/POST_ME.html`, post the video with the caption, then run `yv7 posted <id> <url>`.
   Faster: upload the whole queue once into **TikTok Studio on desktop** and use its built-in scheduler (up to 10 days ahead).

## Campaigns & carousels
`CONTENT_DATABASE/campaign_*.json` holds reviewed campaigns (videos + photo carousels with exact `publish_at` slots), loaded with
`yv7.campaign.load(path)`. Carousels export 1080x1920 JPG slides (TikTok photo mode) plus an optional narrated slideshow video
(`narrated_slideshow.mp4` + `caption_video_version.txt`). Post one or the other, never both.
Voice: Kokoro `bm_george` (local, natural). It is a realistic AI voice, so TikTok's AI-generated content toggle must be ON for videos.

## Pipeline
`ingest` (copy-complete wait, SHA-256 dedupe, ffprobe, quarantine with plain report, originals moved to ARCHIVE and never deleted) →
`analyze` (thumbnail, timecoded contact sheet, scene changes, music-risk heuristic, Whisper transcript, optional Claude vision on the contact sheet;
it records whether a model actually looked) → `editorial` (A/B/C/D/E categories, weighted score, verified facts only, spoiler/leak filters,
gameplay held until LAUNCH is authorised) → `render` (FFmpeg: motion-aware 9:16 crop, original animated cards, TTS, ASS subtitles inside
TikTok safe zones, synthesised music bed, game audio muted when music is suspected, source fps) → `qc` (aspect, codec, bitrate, duration
band, black frames, dead air, spoiler/forbidden terms, fact verification, fake-gameplay guard, perceptual-hash duplicate check) →
`publish` (slots, daily cap, idempotency keys, no blind retries) → `dashboard`.

## Publishing (honest status)
- **Default `export` (works now):** posting packages + notifications. Nothing is marked live until you confirm it.
- **`metricool` (built, not live-tested):** Metricool is an approved TikTok partner. One-time steps: create a "yourviral7" brand in Metricool,
  connect TikTok via Metricool's official OAuth, then add the API token, user ID and blog ID plus a public media URL base to `CONFIG/secrets.env`,
  then run `./yv7.sh publisher metricool`. Posts require `./yv7.sh approve <id|all>` unless you set `require_owner_approval: false`
  (standing authorisation). Status after submission is `scheduled_with_provider`, never "posted", until confirmed.
- No cookies, scraping, password automation or unaudited Direct Post API (that API forces SELF_ONLY/private posts for unaudited apps).

## Safety rails
STOP file · single-instance lock · max 3 renders per cycle · 3 attempts per job · £3/day AI cap (`CONFIG/settings.json`) ·
gameplay is never published in PRELAUNCH · uncertain publish states are never auto-retried.

## Files
`CONFIG/settings.json` settings · `CONFIG/facts.json` verified facts · `CONTENT_DATABASE/prelaunch_concepts.json` prelaunch scripts ·
`CONTENT_DATABASE/yourviral7.sqlite` everything else · `RIGHTS/` clearance, licence request, media kit · `DASHBOARD/index.html`.
