"""Analytics from legitimate sources only: TikTok Studio CSV/XLSX exports and screenshots dropped in INBOX.
Missing values are stored as NULL (missing), never as zero."""
import csv
import json
import re
import shutil
from pathlib import Path

from . import db
from .config import ROOT, load_settings

COLS = {"views": ["video views", "views", "total views", "play count", "plays"], "likes": ["likes", "total likes"],
        "comments": ["comments", "total comments"], "shares": ["shares", "total shares"], "saves": ["saves", "favorites", "favourites"],
        "followers_gained": ["new followers", "followers gained", "net followers"], "followers": ["followers", "total followers"],
        "avg_watch_s": ["average watch time", "avg watch time", "average time watched"],
        "completion": ["watched full video", "completion rate", "full video watch rate"],
        "qualified_views": ["qualified views"], "revenue_gbp": ["estimated rewards", "rewards", "revenue", "estimated revenue"],
        "video_ref": ["video link", "video url", "video title", "title", "video"], "date": ["date", "post time", "posted"]}


def _num(v):
    if v is None:
        return None
    s = str(v).strip().replace(",", "").replace("£", "").replace("%", "")
    m = re.match(r"^(-?[\d.]+)\s*([kKmM]?)", s)
    if not m:
        return None
    n = float(m.group(1)) * {"k": 1e3, "m": 1e6}.get(m.group(2).lower(), 1)
    return n


def _map(header):
    out, used = {}, set()
    for exact in (True, False):          # exact header matches win; prefix matches only for unclaimed columns
        for i, h in enumerate(header):
            hl = str(h or "").strip().lower()
            if i in used:
                continue
            for k, names in COLS.items():
                if k in out:
                    continue
                if any(hl == n for n in names) or (not exact and k not in ("video_ref", "date") and any(hl.startswith(n) for n in names)):
                    out[k] = i
                    used.add(i)
                    break
    for i, h in enumerate(header):       # a link/URL column is the best video reference when present
        if str(h or "").strip().lower() in ("video link", "video url", "link", "url"):
            out["video_ref"] = i
    return out


def import_file(path: Path):
    dest = ROOT / "ANALYTICS" / "imports" / path.name
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        if path.suffix.lower() == ".csv":
            rows = list(csv.reader(open(path, encoding="utf-8-sig", errors="replace")))
            n = _ingest_rows(rows, f"csv:{path.name}")
        elif path.suffix.lower() == ".xlsx":
            import openpyxl
            ws = openpyxl.load_workbook(path, read_only=True).active
            n = _ingest_rows([[c for c in r] for r in ws.iter_rows(values_only=True)], f"xlsx:{path.name}")
        elif path.suffix.lower() == ".json":
            n = 0
        else:
            n = _ocr(path)
        db.event("info", "analytics", f"Imported {n} metric row(s) from {path.name}")
    except Exception as e:
        db.event("warn", "analytics", f"Could not parse {path.name}: {e} (kept in ANALYTICS/imports)")
    shutil.move(str(path), dest)


def _ingest_rows(rows, source):
    rows = [r for r in rows if any(x not in (None, "") for x in r)]
    if not rows:
        return 0
    m = _map(rows[0])
    n = 0
    with db.tx() as c:
        for r in rows[1:]:
            g = lambda k: r[m[k]] if k in m and m[k] < len(r) else None
            ref = g("video_ref")
            post_id = None
            if ref:
                hit = c.execute("SELECT id FROM posts WHERE url=? OR provider_post_id=?", (str(ref), re.sub(r"\D", "", str(ref))[-19:])).fetchone()
                post_id = hit["id"] if hit else None
            if ref or post_id:
                c.execute("""INSERT INTO metrics(post_id,video_ref,captured_at,source,views,likes,comments,shares,saves,followers_gained,
                    avg_watch_s,completion,qualified_views,revenue_gbp,raw) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                          (post_id, str(ref) if ref else None, db.now(), source, _num(g("views")), _num(g("likes")), _num(g("comments")),
                           _num(g("shares")), _num(g("saves")), _num(g("followers_gained")), _num(g("avg_watch_s")),
                           _num(g("completion")), _num(g("qualified_views")), _num(g("revenue_gbp")), json.dumps([str(x) for x in r])))
            else:
                c.execute("INSERT INTO account_metrics(captured_at,source,followers,likes,views_30d,revenue_gbp,raw) VALUES(?,?,?,?,?,?,?)",
                          (db.now(), source, _num(g("followers")), _num(g("likes")), _num(g("views")), _num(g("revenue_gbp")),
                           json.dumps([str(x) for x in r])))
            n += 1
    return n


def _ocr(path: Path):
    """Screenshot OCR (tesseract). Low-confidence: values are stored with source 'screenshot_ocr' and raw text."""
    try:
        import pytesseract
        from PIL import Image
        text = pytesseract.image_to_string(Image.open(path))
    except Exception as e:
        db.event("warn", "analytics", f"OCR unavailable for {path.name}: {e}")
        return 0
    vals = {}
    for key, label in (("followers", r"followers"), ("likes", r"likes"), ("views_30d", r"(video )?views"), ("revenue_gbp", r"(estimated )?rewards")):
        m = re.search(rf"([\d.,]+\s*[KkMm]?)\s*\n?\s*{label}|{label}\s*\n?\s*£?([\d.,]+\s*[KkMm]?)", text, re.I)
        if m:
            vals[key] = _num(m.group(1) or m.group(2))
    with db.tx() as c:
        c.execute("INSERT INTO account_metrics(captured_at,source,followers,likes,views_30d,revenue_gbp,raw) VALUES(?,?,?,?,?,?,?)",
                  (db.now(), f"screenshot_ocr:{path.name}", vals.get("followers"), vals.get("likes"), vals.get("views_30d"),
                   vals.get("revenue_gbp"), text[:4000]))
    return 1


def latest_account():
    s = load_settings()
    with db.tx() as c:
        r = c.execute("SELECT * FROM account_metrics WHERE followers IS NOT NULL ORDER BY id DESC LIMIT 1").fetchone()
        v = c.execute("SELECT * FROM account_metrics WHERE views_30d IS NOT NULL ORDER BY id DESC LIMIT 1").fetchone()
    return {"followers": r["followers"] if r else s["start_followers"], "followers_source": r["source"] if r else "owner-stated baseline (16 Nov)",
            "views_30d": v["views_30d"] if v else None, "views_source": v["source"] if v else None}


def creator_rewards_status():
    a = latest_account()
    f = a["followers"] or 0
    return [("Age 18+", "owner to confirm", None), ("Personal account in eligible country (UK)", "owner to confirm in app", None),
            ("10,000 followers", f"{int(f):,} — {max(0, 10000 - int(f)):,} to go", f >= 10000),
            ("100,000 views in last 30 days", "missing — import TikTok Studio data" if a["views_30d"] is None else f"{int(a['views_30d']):,}",
             None if a["views_30d"] is None else a["views_30d"] >= 100000),
            ("Original videos over 1 minute", "pipeline targets 61–100s for B/C/D", None),
            ("Commercial use of GTA footage", "NOT cleared — see RIGHTS/clearance_status.md", False)]
