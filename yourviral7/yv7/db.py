"""SQLite store: sources, analyses, candidates, renders, posts, metrics, jobs, events, spend."""
import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone

from .config import DB_PATH, ensure_dirs

SCHEMA = """
CREATE TABLE IF NOT EXISTS sources(
  id INTEGER PRIMARY KEY, sha256 TEXT UNIQUE, orig_path TEXT, archive_path TEXT, kind TEXT,
  category TEXT, filename TEXT, size INTEGER, width INTEGER, height INTEGER, fps REAL,
  duration REAL, has_audio INTEGER, status TEXT, meta TEXT, created_at TEXT);
CREATE TABLE IF NOT EXISTS analyses(
  id INTEGER PRIMARY KEY, source_id INTEGER, contact_sheet TEXT, thumbnail TEXT, transcript TEXT,
  transcript_status TEXT, audio_report TEXT, scenes TEXT, visual_notes TEXT, analysis_method TEXT,
  created_at TEXT);
CREATE TABLE IF NOT EXISTS candidates(
  id INTEGER PRIMARY KEY, slug TEXT UNIQUE, category TEXT, title TEXT, hook TEXT, alt_hook TEXT,
  script TEXT, source_ids TEXT, facts_used TEXT, scores TEXT, total_score REAL, status TEXT,
  ai_assisted INTEGER DEFAULT 0, notes TEXT, created_at TEXT);
CREATE TABLE IF NOT EXISTS renders(
  id INTEGER PRIMARY KEY, candidate_id INTEGER, variant TEXT, path TEXT, thumbnail TEXT,
  duration REAL, phash TEXT, qc TEXT, qc_pass INTEGER, caption TEXT, hashtags TEXT, status TEXT,
  created_at TEXT);
CREATE TABLE IF NOT EXISTS posts(
  id INTEGER PRIMARY KEY, render_id INTEGER UNIQUE, idempotency_key TEXT UNIQUE, provider TEXT,
  scheduled_for TEXT, approved INTEGER DEFAULT 0, status TEXT, provider_post_id TEXT, url TEXT,
  privacy TEXT, retries INTEGER DEFAULT 0, last_error TEXT, confirmed_at TEXT, created_at TEXT,
  updated_at TEXT);
CREATE TABLE IF NOT EXISTS metrics(
  id INTEGER PRIMARY KEY, post_id INTEGER, video_ref TEXT, captured_at TEXT, source TEXT,
  views INTEGER, likes INTEGER, comments INTEGER, shares INTEGER, saves INTEGER,
  followers_gained INTEGER, avg_watch_s REAL, completion REAL, qualified_views INTEGER,
  revenue_gbp REAL, raw TEXT);
CREATE TABLE IF NOT EXISTS account_metrics(
  id INTEGER PRIMARY KEY, captured_at TEXT, source TEXT, followers INTEGER, likes INTEGER,
  views_30d INTEGER, revenue_gbp REAL, raw TEXT);
CREATE TABLE IF NOT EXISTS ledger(
  id INTEGER PRIMARY KEY, date TEXT, kind TEXT, description TEXT, amount_gbp REAL, verified INTEGER);
CREATE TABLE IF NOT EXISTS spend(
  id INTEGER PRIMARY KEY, date TEXT, service TEXT, amount_gbp REAL, note TEXT);
CREATE TABLE IF NOT EXISTS events(
  id INTEGER PRIMARY KEY, ts TEXT, level TEXT, area TEXT, message TEXT, data TEXT);
CREATE TABLE IF NOT EXISTS jobs(
  id INTEGER PRIMARY KEY, kind TEXT, ref TEXT, status TEXT, attempts INTEGER DEFAULT 0,
  next_at TEXT, last_error TEXT, created_at TEXT, updated_at TEXT, UNIQUE(kind, ref));
CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT);
"""


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def connect():
    ensure_dirs()
    c = sqlite3.connect(DB_PATH, timeout=30)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    c.executescript(SCHEMA)
    cols = {r[1] for r in c.execute("PRAGMA table_info(posts)")}
    if "package_dir" not in cols:
        c.execute("ALTER TABLE posts ADD COLUMN package_dir TEXT")
    return c


@contextmanager
def tx():
    c = connect()
    try:
        yield c
        c.commit()
    finally:
        c.close()


def event(level, area, message, data=None):
    with tx() as c:
        c.execute("INSERT INTO events(ts,level,area,message,data) VALUES(?,?,?,?,?)",
                  (now(), level, area, message, json.dumps(data) if data is not None else None))
    from .log import log
    log(level, area, message)


def kv_get(k, default=None):
    with tx() as c:
        r = c.execute("SELECT v FROM kv WHERE k=?", (k,)).fetchone()
    return json.loads(r["v"]) if r else default


def kv_set(k, v):
    with tx() as c:
        c.execute("INSERT INTO kv(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", (k, json.dumps(v)))
