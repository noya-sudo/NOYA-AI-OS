"""End-to-end test in an isolated root (never touches the live INBOX/DB).

Creates a SYNTHETIC test clip (generated test pattern + TTS narration — not GTA footage, clearly watermarked),
a corrupt file, a duplicate and an analytics CSV, then runs: ingest -> analyse -> editorial -> render -> QC ->
schedule -> due-post export -> confirm -> analytics -> dashboard -> STOP. Exit code 0 = all assertions passed."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
T = Path(tempfile.mkdtemp(prefix="yv7_e2e_"))
for d in ("assets", "CONFIG", "CONTENT_DATABASE"):
    shutil.copytree(HERE / d, T / d, ignore=shutil.ignore_patterns("*.sqlite*", "secrets.env", "settings.json", "models", "voices"))
os.environ["YV7_HOME"] = str(T)
sys.path.insert(0, str(HERE))

from yv7 import config  # noqa: E402
config.ensure_dirs()
s = config.load_settings()
s.update(mode="LAUNCH", launch_authorized=True, daily_post_cap=3, post_slots=["00:00", "00:01", "00:02"])
config.save_settings(s)

from yv7 import db, ingest, editorial, publish, dashboard  # noqa: E402
from yv7.service import render_pending  # noqa: E402

inbox = T / "INBOX" / "GAMEPLAY"
clip = inbox / "car flips off the pier at sunset.mp4"
narr = T / "narr.wav"
subprocess.run(["espeak-ng", "-v", "en-gb", "-w", str(narr), "Okay, watch this. I am going to drive straight off the end of the pier and see what happens. There it goes."], check=True)
subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=60:duration=34",
                "-i", str(narr), "-filter_complex",
                "[0:v]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='SYNTHETIC TEST CLIP - NOT GAMEPLAY':x=(w-tw)/2:y=h*0.1:fontsize=56:fontcolor=white:box=1:boxcolor=black@0.7[v];[1:a]apad[a]",
                "-map", "[v]", "-map", "[a]", "-t", "34", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", str(clip)], check=True)
shutil.copy(clip, inbox / "same clip copied again.mp4")                       # duplicate
(inbox / "broken capture.mp4").write_bytes(os.urandom(4096))                   # corrupt
(T / "INBOX" / "tiktok analytics export.csv").write_text("Date,Video views,Likes,Comments,Shares,Followers\n2026-11-15,8400,610,42,19,4901\n")

results = {}
n = ingest.scan(wait=False)
with db.tx() as c:
    srcs = [dict(r) for r in c.execute("SELECT * FROM sources")]
    an = [dict(r) for r in c.execute("SELECT * FROM analyses")]
    acct = [dict(r) for r in c.execute("SELECT * FROM account_metrics")]
results["ingested_one_unique_source"] = len(srcs) == 1 and srcs[0]["fps"] == 60 and srcs[0]["width"] == 1920
results["duplicate_detected"] = (T / "ARCHIVE" / "duplicates" / "same clip copied again.mp4").exists()
results["corrupt_quarantined_with_report"] = any(p.name.endswith(".REPORT.txt") for p in (T / "QUARANTINE").iterdir())
results["original_preserved_in_archive"] = Path(srcs[0]["archive_path"]).exists()
results["contact_sheet_and_thumb"] = bool(an) and Path(an[0]["contact_sheet"]).exists() and Path(an[0]["thumbnail"]).exists()
results["analysis_honest_method"] = an[0]["analysis_method"] in ("contact_sheet_generated_not_model_viewed", "model_viewed_contact_sheet")
results["analytics_csv_imported"] = len(acct) == 1 and acct[0]["views_30d"] == 8400 and acct[0]["followers"] == 4901

editorial.generate_from_sources()
with db.tx() as c:
    cands = [dict(r) for r in c.execute("SELECT * FROM candidates")]
results["candidate_generated_from_real_source"] = any(cd["category"] == "A" and "PIER" in cd["hook"] for cd in cands)
render_pending(limit=3)
with db.tx() as c:
    rend = [dict(r) for r in c.execute("SELECT * FROM renders")]
qc = json.loads(rend[0]["qc"]) if rend else {}
results["render_exists_1080x1920_60fps"] = bool(rend) and qc.get("probe", {}).get("width") == 1080 and qc["probe"]["height"] == 1920 and round(qc["probe"]["fps"]) == 60
results["qc_passed"] = bool(rend) and rend[0]["qc_pass"] == 1
print("QC:", json.dumps(qc.get("checks")), qc.get("warnings"))

# schedule (force a slot ~now by monkeypatching guard window)
import yv7.publish as P  # noqa: E402
from datetime import datetime, timedelta  # noqa: E402
s = config.load_settings(); now = datetime.now(P.tz()) + timedelta(minutes=25)
s["post_slots"] = [now.strftime("%H:%M")]; s["daily_post_cap"] = 1; config.save_settings(s)
P.schedule_ready()
with db.tx() as c:
    posts = [dict(r) for r in c.execute("SELECT * FROM posts")]
results["queued_with_idempotency_key"] = len(posts) == 1 and len(posts[0]["idempotency_key"]) == 24
pk = list((T / "OUTPUT" / "SCHEDULED").glob("*/POST_ME.html"))
results["export_package_built"] = bool(pk) and (pk[0].parent / "video.mp4").exists() and (pk[0].parent / "caption.txt").exists()
P.schedule_ready()  # second call must not duplicate
with db.tx() as c:
    results["no_duplicate_queueing"] = c.execute("SELECT COUNT(*) n FROM posts").fetchone()["n"] == 1
    c.execute("UPDATE posts SET scheduled_for=?", ((datetime.now(P.tz()) + timedelta(minutes=5)).isoformat(),))
P.run_due()
with db.tx() as c:
    st = c.execute("SELECT status FROM posts").fetchone()["status"]
results["due_post_exported_not_claimed_live"] = st == "exported_awaiting_manual_post"
P.confirm_posted(posts[0]["id"], "https://www.tiktok.com/@yourviral7/video/7400000000000000001")
with db.tx() as c:
    p = dict(c.execute("SELECT * FROM posts").fetchone())
results["confirmation_recorded"] = p["status"] == "posted_confirmed" and p["provider_post_id"] == "7400000000000000001"
results["moved_to_POSTED"] = any((T / "OUTPUT" / "POSTED").iterdir())

(T / "STOP").write_text("test")
(T / "INBOX" / "GAMEPLAY" / "after stop.mp4").write_bytes(b"x" * 100)
from yv7.service import cycle  # noqa: E402
cycle()
results["stop_file_halts_processing"] = (T / "INBOX" / "GAMEPLAY" / "after stop.mp4").exists()
results["dashboard_built"] = (T / "DASHBOARD" / "index.html").exists()

# persistence: reopen DB from scratch
import sqlite3  # noqa: E402
results["state_persisted_sqlite"] = sqlite3.connect(T / "CONTENT_DATABASE" / "yourviral7.sqlite").execute("SELECT COUNT(*) FROM events").fetchone()[0] > 5

ok = all(results.values())
for k, v in results.items():
    print(f"{'PASS' if v else 'FAIL'}  {k}")
demo = HERE / "OUTPUT" / "DEMO"
demo.mkdir(parents=True, exist_ok=True)
if rend:
    shutil.copy(rend[0]["path"] if Path(rend[0]["path"]).exists() else next((T / "OUTPUT").rglob("video.mp4")), demo / "e2e_synthetic_gameplay_pipeline_test.mp4")
print("Test root:", T)
print("ALL PASSED" if ok else "FAILURES PRESENT")
sys.exit(0 if ok else 1)
