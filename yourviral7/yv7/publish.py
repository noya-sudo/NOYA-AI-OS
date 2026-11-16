"""Scheduling + provider-agnostic publishing.

Publishers:
  export    (default, works today) — builds a ready-to-post package per slot and notifies the owner.
                                     A post is only marked live when the owner confirms it (`yv7 posted ID URL`)
                                     or an analytics import matches it.
  metricool (TikTok-approved partner; OAuth done inside Metricool) — REST adapter, disabled until
                                     METRICOOL_USER_TOKEN / METRICOOL_USER_ID / METRICOOL_BLOG_ID and a public media base
                                     URL are configured. Status after submit is 'scheduled_with_provider', never 'posted'.
Uncertain outcomes (timeouts after sending) are never auto-retried: status 'uncertain_needs_check'."""
import hashlib
import json
import os
import shutil
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from . import db
from .config import ROOT, STOP_FILE, load_secrets, load_settings
from .notify import alert

OUT = ROOT / "OUTPUT"


def tz():
    return ZoneInfo(load_settings()["timezone"])


def _slots_for(day, s):
    return [datetime.combine(day, datetime.strptime(x, "%H:%M").time(), tz()) for x in s["post_slots"][: s["daily_post_cap"]]]


def schedule_ready() -> int:
    """Assign queue slots to QC-passed renders (variant A only; alt hooks stay as options, never double-posted)."""
    s = load_settings()
    n = 0
    with db.tx() as c:
        rows = c.execute("""SELECT r.*, cd.total_score, cd.notes, cd.slug, cd.category FROM renders r
            JOIN candidates cd ON cd.id=r.candidate_id
            WHERE r.qc_pass=1 AND r.variant IN ('A','CAROUSEL') AND r.status='ready' AND r.id NOT IN (SELECT render_id FROM posts)
            AND cd.status!='superseded'
            ORDER BY (cd.notes LIKE 'publish_%') DESC, cd.notes, cd.total_score DESC""").fetchall()
        taken = {r["scheduled_for"] for r in c.execute("SELECT scheduled_for FROM posts WHERE status NOT IN ('failed','cancelled')")}
    now = datetime.now(tz())
    for r in rows:
        if r["total_score"] < s["min_score_to_publish"]:
            with db.tx() as c:
                c.execute("UPDATE renders SET status='below_threshold' WHERE id=?", (r["id"],))
            continue
        day = now.date()
        exact = None
        if r["notes"] and r["notes"].startswith("publish_at="):
            exact = datetime.fromisoformat(r["notes"].split("=", 1)[1].strip())
            if exact.tzinfo is None:
                exact = exact.replace(tzinfo=tz())
            day = exact.date()
            if exact > now + timedelta(minutes=10) and exact.isoformat() not in taken:
                slot = exact
            else:
                slot = None
                db.event("warn", "schedule", f"Planned slot {exact:%d %b %H:%M} for '{r['slug']}' has passed/taken; using next free slot")
        if r["notes"] and r["notes"].startswith("publish_on="):
            day = max(day, datetime.strptime(r["notes"].split("=")[1][:10], "%Y-%m-%d").date())
        if not exact or not slot:
            slot = None
        for d in range(0, 14 if not slot else 0):
            for sl in _slots_for(day + timedelta(days=d), s):
                if sl > now + timedelta(minutes=20) and sl.isoformat() not in taken:
                    slot = sl
                    break
            if slot:
                break
        if not slot:
            continue
        key = hashlib.sha256(f"{r['id']}|{r['path']}".encode()).hexdigest()[:24]
        needs_approval = s["publisher"] != "export" and s["require_owner_approval"]
        with db.tx() as c:
            cur = c.execute("""INSERT INTO posts(render_id,idempotency_key,provider,scheduled_for,approved,status,privacy,created_at,updated_at)
                VALUES(?,?,?,?,?,?,?,?,?)""", (r["id"], key, s["publisher"], slot.isoformat(), 0 if needs_approval else 1,
                                               "awaiting_approval" if needs_approval else "queued", s["tiktok_privacy"], db.now(), db.now()))
            c.execute("UPDATE renders SET status='scheduled' WHERE id=?", (r["id"],))
            pid = cur.lastrowid
        taken.add(slot.isoformat())
        _export_package(pid)
        n += 1
    if n:
        db.event("info", "schedule", f"Queued {n} post(s)")
    return n


def _post_row(pid):
    with db.tx() as c:
        return dict(c.execute("""SELECT p.*, r.path, r.thumbnail, r.caption, r.duration, cd.title, cd.slug, cd.category, cd.ai_assisted
            FROM posts p JOIN renders r ON r.id=p.render_id JOIN candidates cd ON cd.id=r.candidate_id WHERE p.id=?""", (pid,)).fetchone())


def _export_package(pid):
    p = _post_row(pid)
    when = datetime.fromisoformat(p["scheduled_for"])
    d = OUT / "SCHEDULED" / f"{when:%Y-%m-%d_%H%M}_{p['slug']}"
    d.mkdir(parents=True, exist_ok=True)
    if Path(p["path"]).is_dir():                     # photo carousel
        for f in sorted(Path(p["path"]).iterdir()):
            if f.name.startswith("slide_"):
                (d / "slides").mkdir(exist_ok=True)
                shutil.copy2(f, d / "slides" / f.name)
            elif f.suffix in (".mp4", ".jpg"):
                shutil.copy2(f, d / f.name)
    else:
        shutil.copy2(p["path"], d / "video.mp4")
    if p["thumbnail"]:
        shutil.copy2(p["thumbnail"], d / "cover.jpg")
    (d / "caption.txt").write_text(p["caption"] + "\n")
    if Path(p["path"]).is_dir():
        with db.tx() as c:
            spec = json.loads(c.execute("SELECT script FROM candidates WHERE slug=?", (p["slug"],)).fetchone()["script"])
        if spec.get("caption_video_version") and (d / "narrated_slideshow.mp4").exists():
            (d / "caption_video_version.txt").write_text(spec["caption_video_version"] + "\n")
    is_photo = Path(p["path"]).is_dir()
    if p["ai_assisted"]:
        ai = "ON (AI-generated visuals)"
    elif is_photo:
        ai = "OFF for the photo post (no AI visuals or voice). If you post narrated_slideshow.mp4 instead: turn it ON and use caption_video_version.txt"
    else:
        ai = "ON (narration is a realistic AI voice; TikTok requires the label for realistic AI audio). Visuals are original non-AI graphics"
    (d / "POST_ME.html").write_text(f"""<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width">
<title>Post #{pid}</title><body style="font-family:system-ui;max-width:640px;margin:24px auto;padding:0 16px;background:#0b0b12;color:#eee">
<h2>Post #{pid} — {p['title']}</h2><p><b>Post at:</b> {when:%a %d %b %H:%M} (UK)</p>
{'<div>' + ''.join(f'<img src="slides/{f.name}" style="width:31%;margin:1%;border-radius:8px">' for f in sorted((d / "slides").glob("*.jpg"))) + '</div><p><b>Photo post:</b> upload these slides in order in the TikTok app (Photo mode), add a sound from TikTok\'s library in-app.</p>' if is_photo else '<video src="video.mp4" controls playsinline style="width:100%;max-width:360px;border-radius:12px"></video>'}
<h3>Caption (tap to select)</h3><textarea style="width:100%;height:110px" onclick="this.select()">{p['caption']}</textarea>
<p>Cover: cover.jpg · <b>TikTok "AI-generated content" toggle:</b> {ai}</p>
<p>After posting, confirm with: <code>yv7 posted {pid} &lt;tiktok-url&gt;</code></p></body>""")
    with db.tx() as c:
        c.execute("UPDATE posts SET updated_at=?, package_dir=? WHERE id=?", (db.now(), str(d), pid))


def run_due():
    """Called every cycle. Handles due posts per publisher. Never runs when STOP exists."""
    if STOP_FILE.exists():
        return
    s = load_settings()
    now = datetime.now(tz())
    with db.tx() as c:
        due = [dict(r) for r in c.execute("SELECT * FROM posts WHERE status IN ('queued','retry_wait') AND approved=1")]
    for p in due:
        when = datetime.fromisoformat(p["scheduled_for"])
        if p["provider"] == "export":
            if when - timedelta(minutes=15) <= now:
                _set(p["id"], status="exported_awaiting_manual_post")
                row = _post_row(p["id"])
                alert("Time to post", f"#{p['id']} '{row['title']}' — open {row['package_dir']}/POST_ME.html")
        elif p["provider"] == "metricool":
            if p["status"] == "retry_wait" and p.get("updated_at") and datetime.fromisoformat(p["updated_at"]) + timedelta(minutes=5 * 2 ** p["retries"]) > datetime.now(datetime.fromisoformat(p["updated_at"]).tzinfo):
                continue
            MetricoolPublisher().submit(p["id"])


def _set(pid, **kw):
    kw["updated_at"] = db.now()
    with db.tx() as c:
        c.execute(f"UPDATE posts SET {', '.join(k + '=?' for k in kw)} WHERE id=?", (*kw.values(), pid))


def confirm_posted(pid: int, url: str):
    import re
    m = re.search(r"/video/(\d+)", url or "")
    _set(pid, status="posted_confirmed", url=url, provider_post_id=m.group(1) if m else None, confirmed_at=db.now())
    p = _post_row(pid)
    src = Path(p["package_dir"]) if p.get("package_dir") else None
    if src and src.exists():
        shutil.move(str(src), OUT / "POSTED" / src.name)
    with db.tx() as c:
        c.execute("UPDATE renders SET status='posted' WHERE id=?", (p["render_id"],))
    db.event("info", "publish", f"Post #{pid} confirmed live: {url}")


class MetricoolPublisher:
    """Metricool is an official TikTok partner; the TikTok OAuth connection is made inside Metricool by the owner.
    NOT live-tested in this build (no TikTok brand connected yet). Endpoint per Metricool API docs (Advanced plan)."""
    BASE = "https://app.metricool.com/api"

    def configured(self):
        load_secrets()
        return all(os.environ.get(k) for k in ("METRICOOL_USER_TOKEN", "METRICOOL_USER_ID", "METRICOOL_BLOG_ID", "YV7_PUBLIC_MEDIA_BASE"))

    def submit(self, pid):
        import requests
        if not self.configured():
            _set(pid, status="failed", last_error="Metricool not configured — see README 'Publishing'")
            alert("Publishing not configured", "Metricool credentials missing; switch publisher to 'export' or add them to CONFIG/secrets.env", critical=True)
            return
        p = _post_row(pid)
        if p["provider_post_id"]:
            return  # idempotency: already accepted by provider
        when = datetime.fromisoformat(p["scheduled_for"])
        media_url = os.environ["YV7_PUBLIC_MEDIA_BASE"].rstrip("/") + f"/{Path(p['package_dir']).name}/video.mp4"
        body = {"publicationDate": {"dateTime": when.strftime("%Y-%m-%dT%H:%M:%S"), "timezone": load_settings()["timezone"]},
                "text": p["caption"], "providers": [{"network": "tiktok"}], "media": [media_url], "autoPublish": True,
                "draft": False, "tiktokData": {"privacyOption": p["privacy"], "isAigc": bool(p["ai_assisted"]),
                                               "commercialContentThirdParty": False, "commercialContentOwnBrand": False}}
        _set(pid, status="submitting")
        try:
            r = requests.post(f"{self.BASE}/v2/scheduler/posts", timeout=(10, 60),
                              params={"userId": os.environ["METRICOOL_USER_ID"], "blogId": os.environ["METRICOOL_BLOG_ID"]},
                              headers={"X-Mc-Auth": os.environ["METRICOOL_USER_TOKEN"], "Content-Type": "application/json"}, json=body)
        except requests.exceptions.ConnectTimeout as e:   # request never reached provider: safe to retry
            return self._retry(pid, str(e))
        except requests.exceptions.RequestException as e:  # may or may not have been accepted: do NOT retry
            _set(pid, status="uncertain_needs_check", last_error=str(e)[:300])
            alert("Uncertain publish state", f"Post #{pid}: check Metricool planner before retrying (no auto-retry to avoid duplicates).", critical=True)
            return
        if r.status_code in (200, 201):
            data = r.json() if r.content else {}
            ext = str((data.get("data") or data).get("id", "")) if isinstance(data, dict) else ""
            _set(pid, status="scheduled_with_provider", provider_post_id=ext or "accepted")
            db.event("info", "publish", f"Post #{pid} accepted by Metricool for {when:%d %b %H:%M} (not yet confirmed live)")
        elif r.status_code in (401, 403):
            _set(pid, status="failed", last_error=f"auth {r.status_code}")
            alert("Metricool authentication failed", "Re-check token/brand in CONFIG/secrets.env", critical=True)
        elif r.status_code >= 500 or r.status_code == 429:
            self._retry(pid, f"HTTP {r.status_code}")
        else:
            _set(pid, status="failed", last_error=f"HTTP {r.status_code}: {r.text[:300]}")
            alert("Publish rejected", f"Post #{pid}: HTTP {r.status_code}", critical=True)

    def _retry(self, pid, err):
        p = _post_row(pid)
        if p["retries"] >= 4:
            _set(pid, status="failed", last_error=err)
            alert("Publish failed after retries", f"Post #{pid}: {err}", critical=True)
        else:
            _set(pid, status="retry_wait", retries=p["retries"] + 1, last_error=err)
