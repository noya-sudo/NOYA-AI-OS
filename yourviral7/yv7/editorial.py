"""Editorial agent: builds and scores candidates from real sources, verified facts and analytics.

Never invents mechanics, leaks or unseen footage. Gameplay candidates are only built from
things the system actually knows: the owner's filename description, the owner's own narration
(transcript), measured scene changes, and — when a model genuinely viewed it — the contact sheet."""
import json
import re
from pathlib import Path

from . import db
from .config import ROOT, load_settings

WEIGHTS = {"novelty": .25, "hook": .20, "retention": .25, "share": .15, "search": .10, "efficiency": .05}
CAT_RANGE = {"A": (15, 35), "B": (65, 100), "C": (65, 120), "D": (65, 100), "E": (15, 100)}
SPOILER_TERMS = ["ending", "final mission", "dies", "death of", "killed off", "twist", "betray", "last mission", "credits scene"]
FORBIDDEN_TERMS = ["leak", "leaked", "early copy", "unboxing", "insider", "rumour confirmed", "rumor confirmed", "money glitch", "mod menu", "god mode"]
GENERIC_NAME = re.compile(r"^(img|vid|mov|clip|video|dsc|pxl|screen ?recording|capture|gta ?vi?|untitled|\d)[\s_\-\d]*$", re.I)


def score(features: dict) -> tuple[dict, float]:
    f = {k: max(0, min(100, float(features.get(k, 50)))) for k in WEIGHTS}
    adj = analytics_multiplier()
    total = sum(f[k] * w for k, w in WEIGHTS.items()) * adj
    return f, round(total, 1)


def analytics_multiplier(category=None) -> float:
    """Bounded learning: categories/hooks that outperform get up to +15%, underperformers -15%."""
    if category is None:
        return 1.0
    with db.tx() as c:
        rows = c.execute("""SELECT cd.category, AVG(m.views) v FROM metrics m JOIN posts p ON p.id=m.post_id
            JOIN renders r ON r.id=p.render_id JOIN candidates cd ON cd.id=r.candidate_id
            WHERE m.views IS NOT NULL GROUP BY cd.category""").fetchall()
    if len(rows) < 2:
        return 1.0
    avg = sum(r["v"] for r in rows) / len(rows)
    mine = next((r["v"] for r in rows if r["category"] == category), None)
    return 1.0 if not mine or not avg else max(0.85, min(1.15, mine / avg))


def text_risks(text: str) -> list[str]:
    t = text.lower()
    out = [f"spoiler term '{w}'" for w in SPOILER_TERMS if re.search(rf"\b{re.escape(w)}\b", t)]
    out += [f"forbidden term '{w}'" for w in FORBIDDEN_TERMS if re.search(rf"\b{re.escape(w)}\b", t)]
    return out


def _insert(c, slug, cat, title, hook, alt, spec, sources, facts, feats, notes="", ai=0, caption="", reviewed=()):
    if c.execute("SELECT 1 FROM candidates WHERE slug=?", (slug,)).fetchone():
        return None
    f, total = score(feats)
    total = round(total * analytics_multiplier(cat), 1)
    cur = c.execute("""INSERT INTO candidates(slug,category,title,hook,alt_hook,script,source_ids,facts_used,scores,
        total_score,status,ai_assisted,notes,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                    (slug, cat, title, hook, alt, json.dumps(spec), json.dumps(sources), json.dumps(facts),
                     json.dumps({**f, "caption": caption, "context_reviewed_terms": list(reviewed)}), total, "proposed", ai, notes, db.now()))
    return cur.lastrowid


def load_prelaunch() -> int:
    concepts = json.loads((ROOT / "CONTENT_DATABASE" / "prelaunch_concepts.json").read_text())
    n = 0
    with db.tx() as c:
        for k in concepts:
            spec = {"segments": k["segments"], "outro": k.get("outro")}
            if _insert(c, k["slug"], k["category"], k["title"], k["hook"], k.get("alt_hook", ""), spec, [], k["facts_used"],
                       k["features"], notes=f"publish_on={k['publish_on']}", caption=k["caption"],
                       reviewed=k.get("context_reviewed_terms", [])):
                n += 1
    if n:
        db.event("info", "editorial", f"Loaded {n} prelaunch concepts")
    return n


def describe_from_filename(name: str) -> str | None:
    stem = Path(name).stem
    stem = re.sub(r"[_\-.]+", " ", stem).strip()
    stem = re.sub(r"\b(final|edit|v\d+|copy|export|\d{6,})\b", "", stem, flags=re.I).strip()
    if not stem or GENERIC_NAME.match(stem) or len(stem) < 6:
        return None
    return stem[:60]


def generate_from_sources() -> int:
    s = load_settings()
    launch = s["mode"] == "LAUNCH" and s["launch_authorized"]
    made = 0
    with db.tx() as c:
        rows = c.execute("""SELECT s.*, a.transcript, a.audio_report, a.scenes, a.visual_notes, a.analysis_method
            FROM sources s JOIN analyses a ON a.source_id=s.id WHERE s.status='analyzed'""").fetchall()
    for r in rows:
        r = dict(r)
        if r["category"] == "GAMEPLAY" and not launch:
            with db.tx() as c:
                c.execute("UPDATE sources SET status='held_until_launch' WHERE id=?", (r["id"],))
            db.event("info", "editorial", f"Source #{r['id']} held: gameplay is not published before LAUNCH mode is authorised.")
            continue
        if r["kind"] == "image":
            with db.tx() as c:
                c.execute("UPDATE sources SET status='library' WHERE id=?", (r["id"],))
            continue
        made += _gameplay_candidates(r)
        with db.tx() as c:
            c.execute("UPDATE sources SET status='used' WHERE id=?", (r["id"],))
    return made


def _gameplay_candidates(r) -> int:
    desc = describe_from_filename(r["filename"])
    transcript = json.loads(r["transcript"]) if r["transcript"] else None
    audio = json.loads(r["audio_report"] or "{}")
    scenes = json.loads(r["scenes"] or "[]")
    notes = None
    if r["visual_notes"]:
        try:
            notes = json.loads(r["visual_notes"][r["visual_notes"].find("{"): r["visual_notes"].rfind("}") + 1])
        except Exception:
            notes = None
    dur = r["duration"]
    words = len((transcript or {}).get("text", "").split())
    narrated = transcript is not None and words > dur * 1.0
    made = 0
    if notes and notes.get("spoiler_risk"):
        db.event("warn", "rights", f"Source #{r['id']} flagged as possible spoiler by visual review — not used.")
        return 0
    with db.tx() as c:
        # ---- A: viral discovery 15-35s around the strongest moment
        if dur >= 12:
            peak = _peak(scenes, dur, notes)
            length = min(30.0, dur)
            start = max(0.0, min(peak - length * 0.35, dur - length))
            hook = (desc or (notes or {}).get("summary", "") or "").upper()[:46] or "GTA VI · DAY ONE"
            caps = []
            if narrated:
                caps = [(seg["start"] - start, seg["end"] - start, seg["text"]) for seg in transcript["segments"]
                        if seg["end"] > start and seg["start"] < start + length]
            spec = {"hook": hook, "segments": [{"type": "clip", "source_id": r["id"], "start": round(start, 2),
                    "end": round(start + length, 2), "mute": not narrated or audio.get("music_suspected", False),
                    "captions": [(max(a, 0), min(b, length), t) for a, b, t in caps]}]}
            feats = {"novelty": 60 + (15 if notes else 0) + (10 if desc else 0), "hook": 70 if desc or notes else 45,
                     "retention": 62 + min(len(scenes), 15), "share": 60, "search": 55, "efficiency": 95}
            if _insert(c, f"src{r['id']}-a", "A", desc or f"Clip {r['id']}", hook, "", spec, [r["id"]], [], feats,
                       notes="hook from owner filename" if desc else "generic hook (no description available)",
                       caption=_caption(desc, "A")):
                made += 1
        # ---- B/C: authentic narrated piece using the owner's own voice
        if narrated and dur >= 65:
            text = transcript["text"].lower()
            cat = "C" if any(k in text for k in ("how to", "tip", "here's how", "make sure", "step")) else "B"
            length = min(dur, CAT_RANGE[cat][1])
            spec = {"hook": (desc or "WE TESTED THIS").upper()[:46], "segments": [{"type": "clip", "source_id": r["id"],
                    "start": 0, "end": round(length, 2), "mute": audio.get("music_suspected", False),
                    "captions": [(x["start"], min(x["end"], length), x["text"]) for x in transcript["segments"] if x["start"] < length]}]}
            feats = {"novelty": 68, "hook": 66 if desc else 52, "retention": 70, "share": 64, "search": 72 if cat == "C" else 60, "efficiency": 85}
            if audio.get("music_suspected"):
                spec["segments"][0]["mute"] = True
                db.event("warn", "rights", f"Source #{r['id']}: narrated but music suspected; narration would be muted — B/C skipped.")
            elif _insert(c, f"src{r['id']}-{cat.lower()}", cat, desc or f"Narrated {r['id']}", spec["hook"], "", spec,
                         [r["id"]], [], feats, notes="owner narration", caption=_caption(desc, cat)):
                made += 1
    return made


def _peak(scenes, dur, notes):
    if notes and notes.get("moments"):
        best = max(notes["moments"], key=lambda m: m.get("interest", 0))
        try:
            parts = [float(x) for x in str(best["t"]).split(":")]
            t = sum(p * 60 ** i for i, p in enumerate(reversed(parts)))
            return min(t, dur)
        except Exception:
            pass
    if scenes:  # densest 10-second window of cuts/action changes
        return max(scenes, key=lambda t: sum(1 for x in scenes if t <= x < t + 10)) + 3
    return dur * 0.4


def _caption(desc, cat):
    base = (desc[0].upper() + desc[1:]) if desc else "Found this in GTA VI."
    tags = {"A": "#GTA6 #GTAVI #ViceCity #GTA6Gameplay #gaming",
            "B": "#GTA6 #GTAVI #GTA6Experiment #ViceCity #gaming",
            "C": "#GTA6 #GTAVI #GTA6Tips #gamingtips #ViceCity"}.get(cat, "#GTA6 #GTAVI #gaming")
    return f"{base} {tags}"
