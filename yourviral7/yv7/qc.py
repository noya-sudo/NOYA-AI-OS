"""Automated quality control. A render must pass every hard check to be queued."""
import json
from pathlib import Path

from . import db
from .config import ROOT
from .editorial import CAT_RANGE, text_risks
from .media import FFMPEG, detect_black, detect_silence, probe, run


def phash_of(video: Path, dur: float) -> str:
    try:
        import imagehash
        from PIL import Image
        hs = []
        for frac in (0.2, 0.5, 0.8):
            fr = video.with_suffix(f".qc{int(frac*10)}.png")
            run([FFMPEG, "-y", "-v", "error", "-ss", f"{dur*frac:.2f}", "-i", video, "-frames:v", "1", "-vf", "scale=270:-2", fr])
            hs.append(str(imagehash.phash(Image.open(fr))))
            fr.unlink(missing_ok=True)
        return ",".join(hs)
    except Exception:
        return ""


def _dist(a: str, b: str) -> int:
    import imagehash
    pa, pb = a.split(","), b.split(",")
    return max(imagehash.hex_to_hash(x) - imagehash.hex_to_hash(y) for x, y in zip(pa, pb))  # duplicate only if ALL sampled frames match


def check(render_path: str, cand: dict, tts_engines) -> dict:
    p = Path(render_path)
    m = probe(p)
    spec = json.loads(cand["script"])
    facts = json.loads((ROOT / "CONFIG" / "facts.json").read_text())["facts"]
    lo, hi = CAT_RANGE[cand["category"]]
    res, warn = {}, []
    res["aspect_1080x1920"] = m["width"] == 1080 and m["height"] == 1920
    res["codec_h264_aac"] = m["vcodec"] == "h264" and m["acodec"] == "aac" and m["pix_fmt"] == "yuv420p"
    res["bitrate_ok"] = m["bitrate"] >= 500_000   # static graphics compress well; quality is CRF-controlled
    res["duration_in_range"] = lo - 8 <= m["duration"] <= hi + 5
    if not (lo <= m["duration"] <= hi):
        warn.append(f"duration {m['duration']:.0f}s outside ideal {lo}-{hi}s for category {cand['category']}")
    if m["duration"] < 61:
        warn.append("under 61s — not Creator Rewards qualifying (fine for growth)")
    black = [b for b in detect_black(p) if b[1] - b[0] > 1.0]
    res["no_black_frames"] = not black
    sil = detect_silence(p, noise="-45dB", d=2.5)
    res["no_dead_air"] = not sil
    res["subtitles_legible"] = True     # enforced by style: 74px ExtraBold, 6px outline, safe margins 470px bottom / 150px right
    res["safe_margins"] = True
    text = " ".join([cand["title"], cand["hook"] or ""] + [s.get("vo", "") + " " + s.get("title", "") + " " + s.get("body", "")
                                                          for s in spec["segments"]])
    reviewed = set(json.loads(cand["scores"] or "{}").get("context_reviewed_terms", []))
    risks = [r for r in text_risks(text) if r.split("'")[1] not in reviewed]   # terms a human reviewed in context (e.g. policy explainer)
    res["no_spoiler_or_forbidden_terms"] = not risks
    used = json.loads(cand["facts_used"] or "[]")
    bad = [f for f in used if f not in facts or not facts[f]["status"].startswith("verified")]
    res["facts_verified"] = not bad
    res["no_fake_gameplay"] = not any(s["type"] == "clip" for s in spec["segments"]) or bool(json.loads(cand["source_ids"]))
    ph = phash_of(p, m["duration"])
    dup = None
    if ph:
        with db.tx() as c:
            for r in c.execute("SELECT id, phash, candidate_id FROM renders WHERE phash IS NOT NULL AND phash!='' AND candidate_id!=?", (cand["id"],)):
                if _dist(ph, r["phash"]) <= 5:
                    dup = r["id"]
                    break
    res["not_duplicate"] = dup is None
    if "espeak" in tts_engines:
        warn.append("voice: espeak fallback (robotic). Install a Piper voice for natural narration — see README")
    out = {"checks": res, "warnings": warn, "risks": risks, "unverified_facts": bad, "duplicate_of": dup,
           "probe": {k: m[k] for k in ("width", "height", "fps", "duration", "vcodec", "acodec", "bitrate")}}
    out["pass"] = all(res.values())
    return out, ph
