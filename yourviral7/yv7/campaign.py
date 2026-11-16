"""Campaign loader: turns a reviewed campaign JSON (videos + photo carousels) into candidates with exact slots,
renders photo carousels (+ an optional narrated slideshow version), and supersedes older queued items.

Campaign JSON: {"name":..., "disclosure":..., "items":[{"kind":"video"|"carousel","slug","publish_at","category",...}]}"""
import json
import re
import shutil
from pathlib import Path

from . import db
from .config import ROOT
from .editorial import _insert, text_risks
from .render import H, W, card_png

READY = ROOT / "OUTPUT" / "READY"


def load(path: Path) -> int:
    camp = json.loads(Path(path).read_text())
    disclosure = camp.get("disclosure", "")
    n = 0
    with db.tx() as c:
        for i, it in enumerate(camp["items"]):
            tags = " ".join(h if h.startswith("#") else "#" + h for h in it["hashtags"][:5])
            caption = f"{it['caption'].strip()} {tags}".strip() + (f"\n{disclosure}" if disclosure else "")
            note = f"publish_at={it['publish_at']}"
            feats = it.get("features", {"novelty": 70, "hook": 75, "retention": 70, "share": 70, "search": 75, "efficiency": 95})
            if it["kind"] == "video":
                segs = []
                for j, sg in enumerate(it["segments"]):
                    segs.append({"type": "card", "kicker": sg.get("kicker", ""), "title": sg.get("title", ""), "body": sg.get("body", ""),
                                 "vo": sg["vo"], "palette": (i + j) % 4, "pad": 0.25, "min": 1.6})
                spec = {"segments": segs, "outro": None}
                cid = _insert(c, it["slug"], it.get("category", "P"), it.get("title", it["slug"]), it["hook_text"], it.get("alt_hook", ""),
                              spec, [], it.get("facts_used", []), feats, notes=note, caption=caption, reviewed=it.get("context_reviewed_terms", []))
            else:
                spec = {"carousel": True, "slides": it["slides"], "voiceover": it.get("voiceover", ""), "palette": i % 4}
                spec["caption_video_version"] = it.get("caption_video_version", caption + " Narration is an AI voice.")
                cid = _insert(c, it["slug"], "K", it.get("title", it["slug"]), it["slides"][0]["title"], "", spec, [],
                              it.get("facts_used", []), feats, notes=note, caption=caption, reviewed=it.get("context_reviewed_terms", []))
            n += bool(cid)
    db.event("info", "campaign", f"Loaded campaign '{camp.get('name')}' ({n} new items)")
    return n


def supersede_old(keep_prefixes):
    """Cancel queued-but-unpublished posts that are not part of the new campaign (nothing had been published)."""
    with db.tx() as c:
        rows = c.execute("""SELECT p.id, p.package_dir, cd.slug, cd.id cid FROM posts p JOIN renders r ON r.id=p.render_id
            JOIN candidates cd ON cd.id=r.candidate_id WHERE p.status IN ('queued','awaiting_approval')""").fetchall()
        n = 0
        for r in rows:
            if not any(r["slug"].startswith(k) for k in keep_prefixes):
                c.execute("UPDATE posts SET status='cancelled', last_error='superseded by 48h campaign', updated_at=? WHERE id=?", (db.now(), r["id"]))
                c.execute("UPDATE candidates SET status='superseded' WHERE id=?", (r["cid"],))
                if r["package_dir"] and Path(r["package_dir"]).exists():
                    dest = ROOT / "ARCHIVE" / "superseded" / Path(r["package_dir"]).name
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(r["package_dir"], dest)
                n += 1
        c.execute("UPDATE candidates SET status='superseded' WHERE status IN ('proposed','parked_low_score') AND slug LIKE 'pl0%'")
    db.event("info", "campaign", f"Superseded {n} older queued post(s) (none had been published)")
    return n


def render_carousel(cand: dict) -> dict:
    spec = json.loads(cand["script"])
    out = READY / cand["slug"]
    out.mkdir(parents=True, exist_ok=True)
    slides = spec["slides"]
    paths = []
    for k, sl in enumerate(slides):
        pth = out / f"slide_{k + 1:02d}.jpg"
        card_png(pth, sl.get("kicker", ""), sl.get("title", ""), sl.get("body", ""), spec.get("palette", 0) + k, None,
                 label="ORIGINAL GUIDE", slide_no=f"{k + 1}/{len(slides)}", still=True)
        paths.append(pth)
    from PIL import Image
    qc = {"checks": {}, "warnings": []}
    dims = [Image.open(p).size for p in paths]
    qc["checks"]["slides_1080x1920"] = all(d == (W, H) for d in dims)
    qc["checks"]["slide_count_2_to_35"] = 2 <= len(paths) <= 35
    text = " ".join(f"{s.get('title','')} {s.get('body','')}" for s in slides) + " " + spec.get("voiceover", "")
    reviewed = set(json.loads(cand["scores"] or "{}").get("context_reviewed_terms", []))
    qc["risks"] = [r for r in text_risks(text) if r.split("'")[1] not in reviewed]
    qc["checks"]["no_spoiler_or_forbidden_terms"] = not qc["risks"]
    facts = json.loads((ROOT / "CONFIG" / "facts.json").read_text())["facts"]
    bad = [f for f in json.loads(cand["facts_used"] or "[]") if f not in facts or not facts[f]["status"].startswith("verified")]
    qc["checks"]["facts_verified"] = not bad
    qc["unverified_facts"] = bad
    qc["pass"] = all(qc["checks"].values())
    # contact sheet preview
    sheet = out / "preview_grid.jpg"
    thumbs = [Image.open(p).resize((270, 480)) for p in paths]
    grid = Image.new("RGB", (270 * min(len(thumbs), 4), 480 * ((len(thumbs) + 3) // 4)), (0, 0, 0))
    for k, t in enumerate(thumbs):
        grid.paste(t, ((k % 4) * 270, (k // 4) * 480))
    grid.save(sheet, quality=88)
    return {"path": str(out), "thumbnail": str(paths[0]), "qc": qc, "slides": [str(p) for p in paths]}


def slideshow_spec(cand: dict) -> dict:
    """Narrated slideshow version of a carousel: voiceover sentences distributed across slides."""
    spec = json.loads(cand["script"])
    slides = spec["slides"]
    sents = [x.strip() for x in re.split(r"(?<=[.!?])\s+", spec.get("voiceover", "").strip()) if x.strip()]
    buckets = [[] for _ in slides]
    for k, snt in enumerate(sents):
        buckets[min(int(k * len(slides) / max(len(sents), 1)), len(slides) - 1)].append(snt)
    segs = []
    for k, (sl, b) in enumerate(zip(slides, buckets)):
        seg = {"type": "card", "kicker": sl.get("kicker", ""), "title": sl.get("title", ""), "body": sl.get("body", ""),
               "palette": spec.get("palette", 0) + k, "pad": 0.2, "min": 2.2, "label": "ORIGINAL GUIDE"}
        if b:
            seg["vo"] = " ".join(b)
        segs.append(seg)
    return {"segments": segs, "outro": None}
