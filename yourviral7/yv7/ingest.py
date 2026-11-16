"""INBOX ingestion: wait for copy completion, hash, dedupe, probe, quarantine, archive, analyse."""
import json
import shutil
import time
from pathlib import Path

from . import db
from .config import ROOT, INBOX, VIDEO_EXT, IMAGE_EXT, DATA_EXT, STOP_FILE
from .media import probe, sha256, run, FFMPEG

ARCHIVE = ROOT / "ARCHIVE"
QUAR = ROOT / "QUARANTINE"
IGNORED = {".ds_store", "thumbs.db", "desktop.ini"}


def category_for(path: Path) -> str:
    parts = [p.upper() for p in path.relative_to(INBOX).parts[:-1]]
    for c in ("GAMEPLAY", "PHOTOS", "PRELAUNCH"):
        if c in parts:
            return c
    return "GAMEPLAY" if path.suffix.lower() in VIDEO_EXT else "PHOTOS"


def is_stable(path: Path, wait=3.0, checks=2) -> bool:
    """A file is ready when its size and mtime stop changing and it can be opened."""
    try:
        last = (path.stat().st_size, path.stat().st_mtime)
        for _ in range(checks):
            time.sleep(wait)
            cur = (path.stat().st_size, path.stat().st_mtime)
            if cur != last or cur[0] == 0:
                return False
            last = cur
        with open(path, "rb"):
            pass
        return True
    except OSError:
        return False


def pending_files():
    for p in sorted(INBOX.rglob("*")):
        if p.is_file() and p.name.lower() not in IGNORED and not p.name.startswith((".", "~$")) \
                and not p.name.endswith((".part", ".crdownload", ".tmp", ".download")):
            yield p


def quarantine(path: Path, reason: str):
    QUAR.mkdir(parents=True, exist_ok=True)
    dest = QUAR / f"{int(time.time())}_{path.name}"
    shutil.move(str(path), dest)
    (dest.parent / (dest.name + ".REPORT.txt")).write_text(
        f"File: {path.name}\nWhy it was set aside: {reason}\n\n"
        "Nothing was deleted. If this file is fine, re-export it (e.g. as MP4/H.264 or JPG) and drop it in INBOX again.\n")
    db.event("warn", "ingest", f"Quarantined {path.name}: {reason}")


def ingest_file(path: Path, wait=True) -> int | None:
    if STOP_FILE.exists():
        return None
    if wait and not is_stable(path):
        return None
    ext = path.suffix.lower()
    if ext in DATA_EXT or (ext in IMAGE_EXT and _looks_like_analytics(path)):
        from .analytics import import_file
        import_file(path)
        return None
    if ext not in VIDEO_EXT | IMAGE_EXT:
        quarantine(path, f"Unsupported file type '{ext}'. Accepted: video (MP4/MOV/MKV), images (JPG/PNG), analytics CSV.")
        return None
    digest = sha256(path)
    with db.tx() as c:
        dup = c.execute("SELECT id, archive_path FROM sources WHERE sha256=?", (digest,)).fetchone()
    if dup:
        dest = ARCHIVE / "duplicates" / path.name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(path), _unique(dest))
        db.event("info", "ingest", f"Duplicate of source #{dup['id']} skipped: {path.name}")
        return dup["id"]
    try:
        meta = probe(path)
        if ext in VIDEO_EXT and (meta["duration"] <= 0.2 or not meta["width"]):
            raise RuntimeError("no readable video stream")
        if ext in IMAGE_EXT and not meta["width"]:
            raise RuntimeError("image could not be decoded")
    except Exception as e:  # corrupt or unsafe
        quarantine(path, f"Could not read the media ({e}). The file may be corrupt or still copying.")
        return None
    cat = category_for(path)
    kind = "video" if ext in VIDEO_EXT else "image"
    dest = _unique(ARCHIVE / cat / time.strftime("%Y%m%d") / path.name)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), dest)   # original preserved byte-for-byte in ARCHIVE; never deleted
    with db.tx() as c:
        cur = c.execute("""INSERT INTO sources(sha256,orig_path,archive_path,kind,category,filename,size,width,height,
            fps,duration,has_audio,status,meta,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                        (digest, str(path), str(dest), kind, cat, path.name, dest.stat().st_size, meta["width"],
                         meta["height"], meta["fps"], meta["duration"], int(meta["has_audio"]), "ingested",
                         json.dumps(meta), db.now()))
        sid = cur.lastrowid
    db.event("info", "ingest", f"Ingested #{sid} {path.name} ({kind}, {meta['width']}x{meta['height']}, {meta['duration']:.1f}s)")
    try:
        from .analyze import analyze_source
        analyze_source(sid)
    except Exception as e:
        db.event("error", "analyze", f"Analysis failed for #{sid}: {e}")
    return sid


def _looks_like_analytics(path: Path) -> bool:
    n = path.name.lower()
    return any(k in n for k in ("analytic", "insight", "stats", "creator", "search", "screenshot", "metrics"))


def _unique(p: Path) -> Path:
    i, q = 1, p
    while q.exists():
        q = p.with_name(f"{p.stem}_{i}{p.suffix}")
        i += 1
    return q


def scan(wait=True) -> int:
    n = 0
    for p in list(pending_files()):
        if ingest_file(p, wait=wait):
            n += 1
    return n


def watch(on_change):
    """Persistent watcher. Uses watchdog when installed, polling otherwise."""
    try:
        from watchdog.events import FileSystemEventHandler
        from watchdog.observers import Observer

        class H(FileSystemEventHandler):
            def on_any_event(self, ev):
                if not ev.is_directory:
                    on_change()
        obs = Observer()
        obs.schedule(H(), str(INBOX), recursive=True)
        obs.start()
        return obs
    except Exception as e:
        db.event("warn", "ingest", f"watchdog unavailable ({e}); falling back to polling")
        return None
