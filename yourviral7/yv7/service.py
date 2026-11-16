"""The always-on loop: ingest -> analyse -> editorial -> render -> QC -> schedule -> publish -> dashboard.
Guards: STOP file, single-instance lock, per-cycle render cap, daily candidate cap, AI budget, job attempts."""
import json
import os
import shutil
import threading
import time
from datetime import date, datetime
from pathlib import Path

from . import db, editorial, ingest, publish
from .config import ROOT, STOP_FILE, load_settings
from .dashboard import build as build_dashboard
from .notify import alert
from .qc import check
from .render import render

LOCK = ROOT / "LOGS" / "service.lock"


def render_pending(limit=None):
    s = load_settings()
    limit = limit or s["max_renders_per_cycle"]
    with db.tx() as c:
        cands = [dict(r) for r in c.execute(
            "SELECT * FROM candidates WHERE status='proposed' AND total_score>=? ORDER BY (notes LIKE 'publish_on=%') DESC, notes, total_score DESC LIMIT ?",
            (s["min_score_to_publish"], limit))]
        low = c.execute("UPDATE candidates SET status='parked_low_score' WHERE status='proposed' AND total_score<?", (s["min_score_to_publish"],)).rowcount
    if low:
        db.event("info", "editorial", f"Parked {low} candidate(s) below score threshold")
    done = 0
    for cand in cands:
        if STOP_FILE.exists():
            break
        key = f"render:{cand['id']}"
        with db.tx() as c:
            j = c.execute("SELECT attempts FROM jobs WHERE kind='render' AND ref=?", (key,)).fetchone()
            if j and j["attempts"] >= 3:
                c.execute("UPDATE candidates SET status='render_failed' WHERE id=?", (cand["id"],))
                continue
            c.execute("""INSERT INTO jobs(kind,ref,status,attempts,created_at,updated_at) VALUES('render',?,'running',1,?,?)
                ON CONFLICT(kind,ref) DO UPDATE SET attempts=attempts+1, status='running', updated_at=excluded.updated_at""", (key, db.now(), db.now()))
            c.execute("UPDATE candidates SET status='rendering' WHERE id=?", (cand["id"],))
        try:
            if cand["category"] == "K":
                _render_carousel(cand)
                with db.tx() as c:
                    c.execute("UPDATE candidates SET status='rendered' WHERE id=?", (cand["id"],))
                    c.execute("UPDATE jobs SET status='done', updated_at=? WHERE kind='render' AND ref=?", (db.now(), key))
                done += 1
                continue
            variants = [("A", None)]
            if cand["alt_hook"] and cand["alt_hook"].strip() and cand["alt_hook"] != cand["hook"]:
                variants.append(("B", cand["alt_hook"]))
            for v, hook in variants:
                out = render(cand["id"], v, hook)
                qc, ph = check(out["path"], cand, out["tts"])
                caption = json.loads(cand["scores"]).get("caption") or cand["title"]
                with db.tx() as c:
                    c.execute("""INSERT INTO renders(candidate_id,variant,path,thumbnail,duration,phash,qc,qc_pass,caption,hashtags,status,created_at)
                        VALUES(?,?,?,?,?,?,?,?,?,?,?,?)""", (cand["id"], v, out["path"], out["thumbnail"], out["duration"], ph if v == "A" else "",
                                                          json.dumps(qc), int(qc["pass"]), caption, "", "ready" if qc["pass"] else "qc_failed", db.now()))
                if not qc["pass"]:
                    failed = [k for k, ok in qc["checks"].items() if not ok]
                    db.event("warn", "qc", f"Candidate #{cand['id']} variant {v} failed QC: {failed}")
                    if v == "A":
                        shutil.move(out["path"], ROOT / "OUTPUT" / "FAILED" / os.path.basename(out["path"]))
            with db.tx() as c:
                c.execute("UPDATE candidates SET status='rendered' WHERE id=?", (cand["id"],))
                c.execute("UPDATE jobs SET status='done', updated_at=? WHERE kind='render' AND ref=?", (db.now(), key))
            done += 1
            db.event("info", "render", f"Rendered candidate #{cand['id']} '{cand['title']}' ({out['duration']:.0f}s)")
        except Exception as e:
            with db.tx() as c:
                c.execute("UPDATE candidates SET status='proposed' WHERE id=?", (cand["id"],))
                c.execute("UPDATE jobs SET status='error', last_error=?, updated_at=? WHERE kind='render' AND ref=?", (str(e)[:500], db.now(), key))
            db.event("error", "render", f"Render failed for #{cand['id']}: {str(e)[:300]}")
    return done


CYCLE_LOCK = ROOT / "LOGS" / "cycle.lock"


def _pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError, OSError):
        return False


def _render_carousel(cand):
    from .campaign import render_carousel, slideshow_spec
    car = render_carousel(cand)
    caption = json.loads(cand["scores"]).get("caption") or cand["title"]
    with db.tx() as c:
        c.execute("""INSERT INTO renders(candidate_id,variant,path,thumbnail,duration,phash,qc,qc_pass,caption,hashtags,status,created_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?)""", (cand["id"], "CAROUSEL", car["path"], car["thumbnail"], 0, "", json.dumps(car["qc"]),
                                              int(car["qc"]["pass"]), caption, "", "ready" if car["qc"]["pass"] else "qc_failed", db.now()))
    if not car["qc"]["pass"]:
        db.event("warn", "qc", f"Carousel #{cand['id']} failed QC: {car['qc']}")
        return
    try:   # narrated slideshow alternative (same content as a video; never posted in addition to the carousel)
        cand2 = dict(cand, category="S", hook=cand["hook"])
        out = render(cand["id"], "A", None, spec_override=slideshow_spec(cand))
        qc, ph = check(out["path"], dict(cand2, script=json.dumps(slideshow_spec(cand))), out["tts"])
        alt = Path(car["path"]) / "narrated_slideshow.mp4"
        shutil.move(out["path"], alt)
        Path(out["thumbnail"]).unlink(missing_ok=True)
        with db.tx() as c:
            c.execute("""INSERT INTO renders(candidate_id,variant,path,thumbnail,duration,phash,qc,qc_pass,caption,hashtags,status,created_at)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?)""", (cand["id"], "SLIDESHOW", str(alt), car["thumbnail"], out["duration"], ph, json.dumps(qc),
                                                  int(qc["pass"]), caption, "", "alt" if qc["pass"] else "qc_failed", db.now()))
    except Exception as e:
        db.event("warn", "render", f"Slideshow version for carousel #{cand['id']} failed: {str(e)[:200]}")


def cycle():
    """One full pass. Guarded so two processes (service + manual scan) never work at once."""
    CYCLE_LOCK.parent.mkdir(parents=True, exist_ok=True)
    if CYCLE_LOCK.exists():
        try:
            other = int(CYCLE_LOCK.read_text())
            if other != os.getpid() and _pid_alive(other):
                db.event("info", "service", f"Another cycle is running (pid {other}); skipping")
                return
        except ValueError:
            pass
    CYCLE_LOCK.write_text(str(os.getpid()))
    try:
        _cycle()
    finally:
        CYCLE_LOCK.unlink(missing_ok=True)


def _cycle():
    if STOP_FILE.exists():
        db.event("info", "service", "STOP file present — cycle skipped")
        build_dashboard()
        return
    s = load_settings()
    ingest.scan(wait=True)
    if s["mode"] == "PRELAUNCH":
        editorial.load_prelaunch()
    editorial.generate_from_sources()
    render_pending()
    publish.schedule_ready()
    publish.run_due()
    _daily_summary()
    db.kv_set("last_cycle", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    build_dashboard()


def _daily_summary():
    today = date.today().isoformat()
    if db.kv_get("summary_date") == today:
        return
    with db.tx() as c:
        bad = c.execute("SELECT COUNT(*) n FROM posts WHERE status IN ('failed','uncertain_needs_check')").fetchone()["n"]
        q = c.execute("SELECT COUNT(*) n FROM posts WHERE status IN ('queued','exported_awaiting_manual_post','scheduled_with_provider','awaiting_approval')").fetchone()["n"]
        held = c.execute("SELECT COUNT(*) n FROM sources WHERE status='held_until_launch'").fetchone()["n"]
    alert("Daily summary", f"Queue {q} · unresolved publishing failures {bad} · gameplay held until launch {held}. Dashboard: DASHBOARD/index.html",
          critical=bad > 0)
    db.kv_set("summary_date", today)


def _lock():
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    if LOCK.exists():
        try:
            pid = int(LOCK.read_text())
            os.kill(pid, 0)
            raise SystemExit(f"YOURVIRAL7 is already running (pid {pid}).")
        except (ProcessLookupError, ValueError, PermissionError, OSError):
            pass
    LOCK.write_text(str(os.getpid()))


def serve():
    _lock()
    db.event("info", "service", f"Service started (pid {os.getpid()})")
    wake = threading.Event()
    obs = ingest.watch(lambda: wake.set())
    try:
        while True:
            try:
                cycle()
            except Exception as e:
                db.event("error", "service", f"Cycle error: {e}")
            wake.wait(timeout=load_settings()["loop_seconds"])
            wake.clear()
            time.sleep(2)
    finally:
        if obs:
            obs.stop()
        LOCK.unlink(missing_ok=True)
