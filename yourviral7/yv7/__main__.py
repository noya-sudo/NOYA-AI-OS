"""yv7 — YOURVIRAL7 command line.

  start            start (or resume) the always-on service in the foreground (installer runs it at login)
  stop             create STOP file: halts all processing and publishing immediately
  resume           remove STOP file
  health           environment + system health report
  scan             one ingest/analyse/render/schedule cycle, then exit
  queue            show the posting queue
  approve ID|all   authorise automated publishing of queued post(s)
  posted ID URL    confirm a post is live on TikTok
  mode launch --confirm | mode prelaunch
  cap N            set daily post cap (1-6)
  publisher export|metricool
  dashboard        rebuild DASHBOARD/index.html
  ledger KIND GBP "desc" [--verified]   record revenue (+) or cost (-)
"""
import json
import shutil
import sys

from . import db
from .config import ROOT, STOP_FILE, load_settings, save_settings


def main(argv=None):
    a = argv if argv is not None else sys.argv[1:]
    cmd = a[0] if a else "health"
    if cmd == "start":
        STOP_FILE.unlink(missing_ok=True) if "--resume" in a else None
        from .service import serve
        serve()
    elif cmd == "stop":
        STOP_FILE.write_text("Created by `yv7 stop`. Delete this file or run `yv7 resume` to continue.\n")
        with db.tx() as c:
            c.execute("UPDATE posts SET status='queued' WHERE status='submitting'")
        db.event("warn", "service", "STOP engaged — all processing and publishing suspended")
        print("STOPPED. Nothing will be processed or published until `yv7 resume`.")
    elif cmd == "resume":
        STOP_FILE.unlink(missing_ok=True)
        print("Resumed. The service continues on its next cycle (or run `yv7 start`).")
    elif cmd == "scan":
        from .service import cycle
        cycle()
        _queue()
    elif cmd == "queue":
        _queue()
    elif cmd == "health":
        _health()
    elif cmd == "approve":
        with db.tx() as c:
            if a[1] == "all":
                n = c.execute("UPDATE posts SET approved=1, status='queued' WHERE status='awaiting_approval'").rowcount
            else:
                n = c.execute("UPDATE posts SET approved=1, status='queued' WHERE id=? AND status='awaiting_approval'", (int(a[1]),)).rowcount
        db.event("info", "publish", f"Owner approved {n} post(s)")
        print(f"Approved {n}.")
    elif cmd == "posted":
        from .publish import confirm_posted
        confirm_posted(int(a[1]), a[2])
        print("Recorded as live.")
    elif cmd == "mode":
        s = load_settings()
        if a[1] == "launch":
            if "--confirm" not in a:
                print("Launch mode publishes real gameplay. Re-run with --confirm once GTA VI is officially released (19 Nov 2026) and you have your own legitimate copy.")
                return
            s.update(mode="LAUNCH", launch_authorized=True)
            with db.tx() as c:
                c.execute("UPDATE sources SET status='analyzed' WHERE status='held_until_launch'")
        else:
            s.update(mode="PRELAUNCH", launch_authorized=False)
        save_settings(s)
        db.event("info", "service", f"Mode set to {s['mode']}")
        print(f"Mode: {s['mode']}")
    elif cmd == "cap":
        s = load_settings()
        s["daily_post_cap"] = max(1, min(6, int(a[1])))
        save_settings(s)
        print(f"Daily cap: {s['daily_post_cap']}")
    elif cmd == "publisher":
        s = load_settings()
        s["publisher"] = a[1]
        save_settings(s)
        print(f"Publisher: {a[1]}")
    elif cmd == "dashboard":
        from .dashboard import build
        print(build())
    elif cmd == "ledger":
        with db.tx() as c:
            c.execute("INSERT INTO ledger(date,kind,description,amount_gbp,verified) VALUES(date('now'),?,?,?,?)",
                      (a[1], a[3] if len(a) > 3 else "", float(a[2]), int("--verified" in a)))
        print("Recorded.")
    else:
        print(__doc__)


def _queue():
    with db.tx() as c:
        rows = c.execute("""SELECT p.id, p.scheduled_for, p.status, cd.title, cd.category, r.duration, cd.total_score FROM posts p
            JOIN renders r ON r.id=p.render_id JOIN candidates cd ON cd.id=r.candidate_id ORDER BY p.scheduled_for""").fetchall()
    print(f"{'ID':>3}  {'SLOT (UK)':16}  {'CAT':3} {'LEN':>4} {'SCORE':>5}  {'STATUS':30} TITLE")
    for r in rows:
        print(f"{r['id']:>3}  {r['scheduled_for'][:16].replace('T',' '):16}  {r['category']:3} {r['duration']:>3.0f}s {r['total_score']:>5}  {r['status']:30} {r['title']}")


def _health():
    import platform
    from .ai import ai_available, spent_today
    from .publish import MetricoolPublisher
    from .tts import engine
    s = load_settings()
    ok = lambda b: "OK  " if b else "MISS"
    print(f"YOURVIRAL7 health — root {ROOT}")
    print(f"  [{ok(not STOP_FILE.exists())}] service state: {'STOPPED (STOP file)' if STOP_FILE.exists() else 'not stopped'}")
    lock = ROOT / 'LOGS' / 'service.lock'
    print(f"  [{ok(lock.exists())}] background service lock: {lock.read_text().strip() if lock.exists() else 'not running'}")
    print(f"  [{ok(shutil.which('ffmpeg'))}] ffmpeg  [{ok(shutil.which('ffprobe'))}] ffprobe   python {platform.python_version()}")
    print(f"  [{ok(engine() == 'piper')}] TTS engine: {engine()} {'(robotic fallback — add Piper voice)' if engine() == 'espeak' else ''}")
    try:
        import faster_whisper  # noqa
        tw = any((ROOT / 'CONFIG' / 'models').glob('*whisper*')) or any((ROOT / 'CONFIG' / 'models').glob('models--*'))
        print(f"  [{ok(tw)}] transcription: faster-whisper installed; model {'cached' if tw else 'downloads on first use (needs huggingface.co)'}")
    except ImportError:
        print("  [MISS] transcription: faster-whisper not installed")
    print(f"  [{ok(ai_available())}] Claude API vision/scripting: {'available' if ai_available() else 'not configured (optional)'} · spend today £{spent_today():.2f}/£{s['budget_gbp_per_day']:.2f}")
    mc = MetricoolPublisher().configured()
    print(f"  [{ok(s['publisher'] == 'export' or mc)}] publisher: {s['publisher']}" + (" — export packages + notifications (manual one-tap post)" if s['publisher'] == 'export' else f" — configured={mc}"))
    print(f"  [MISS] automatic PUBLIC TikTok publishing: {'configured (unconfirmed until first live post)' if s['publisher']=='metricool' and mc else 'NOT connected'}")
    print(f"  mode {s['mode']} (launch authorised: {s['launch_authorized']}) · cap {s['daily_post_cap']}/day · min score {s['min_score_to_publish']}")
    with db.tx() as c:
        for label, sql in [("sources", "SELECT status, COUNT(*) n FROM sources GROUP BY status"),
                           ("candidates", "SELECT status, COUNT(*) n FROM candidates GROUP BY status"),
                           ("posts", "SELECT status, COUNT(*) n FROM posts GROUP BY status")]:
            print(f"  {label}: " + (", ".join(f"{r['status']}={r['n']}" for r in c.execute(sql)) or "none"))
        last = c.execute("SELECT v FROM kv WHERE k='last_cycle'").fetchone()
        errs = c.execute("SELECT ts, area, message FROM events WHERE level='error' ORDER BY id DESC LIMIT 3").fetchall()
    print(f"  last cycle: {json.loads(last['v']) if last else 'never'}")
    for e in errs:
        print(f"  recent error {e['ts'][:16]} {e['area']}: {e['message'][:120]}")
    print(f"  dashboard: {ROOT / 'DASHBOARD' / 'index.html'}")


if __name__ == "__main__":
    main()
