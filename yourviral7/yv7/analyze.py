"""Per-source analysis: thumbnail, contact sheet, scenes, audio risk, transcript, optional vision notes.

Honesty rule: visual_notes are only written when a model actually viewed the contact sheet.
Otherwise analysis_method says so and editorial relies on timecodes, transcript and filename."""
import json
import os
import shutil
from pathlib import Path

from . import db
from .config import ROOT, load_settings
from .media import FFMPEG, run, detect_scenes, detect_silence, loudness

SHEETS = ROOT / "PROCESSING" / "sheets"
AUDIO = ROOT / "PROCESSING" / "audio"


def analyze_source(sid: int):
    with db.tx() as c:
        s = dict(c.execute("SELECT * FROM sources WHERE id=?", (sid,)).fetchone())
    src = Path(s["archive_path"])
    SHEETS.mkdir(parents=True, exist_ok=True)
    thumb = SHEETS / f"src{sid}_thumb.jpg"
    sheet = SHEETS / f"src{sid}_sheet.jpg"
    scenes, audio_report, transcript, t_status = [], {}, None, "not_applicable"
    if s["kind"] == "image":
        run([FFMPEG, "-y", "-v", "error", "-i", src, "-vf", "scale=540:-2", thumb])
        shutil.copy(thumb, sheet)
    else:
        dur = s["duration"]
        run([FFMPEG, "-y", "-v", "error", "-ss", f"{min(dur * 0.3, dur - 0.1):.2f}", "-i", src, "-frames:v", "1", "-vf", "scale=540:-2", thumb])
        n = 12 if dur > 20 else 6
        step = max(dur / n, 0.5)
        run([FFMPEG, "-y", "-v", "error", "-i", src, "-vf",
             f"fps=1/{step:.3f},scale=360:-2,drawtext=fontfile={_font()}:text='%{{pts\\:hms}}':x=8:y=8:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6,tile=4x{(n + 3) // 4}",
             "-frames:v", "1", sheet])
        scenes = detect_scenes(src)
        if s["has_audio"]:
            audio_report = audio_risk(src, dur)
            transcript, t_status = transcribe(src, sid)
            if transcript and audio_report.get("music_suspected") and len(transcript.get("text", "").split()) > dur * 1.2:
                audio_report["music_suspected"] = False  # speech-dense: commentary, not music
        else:
            t_status = "no_audio"
    notes, method = vision_notes(sheet, s)
    with db.tx() as c:
        c.execute("""INSERT INTO analyses(source_id,contact_sheet,thumbnail,transcript,transcript_status,audio_report,
            scenes,visual_notes,analysis_method,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)""",
                  (sid, str(sheet), str(thumb), json.dumps(transcript) if transcript else None, t_status,
                   json.dumps(audio_report), json.dumps(scenes), notes, method, db.now()))
        c.execute("UPDATE sources SET status='analyzed' WHERE id=?", (sid,))
    if audio_report.get("music_suspected"):
        db.event("warn", "rights", f"Source #{sid}: possible music/radio in game audio — it will be muted in edits.")


def _font():
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/Library/Fonts/Arial Bold.ttf", "C\\:/Windows/Fonts/arialbd.ttf"):
        if Path(f.replace("\\", "")).exists():
            return f
    return "DejaVuSans-Bold.ttf"


def audio_risk(src: Path, dur: float) -> dict:
    """Heuristic only (no fingerprint service configured): continuous non-silent audio with no speech pauses
    is flagged as possible music/radio. Optional AcoustID if fpcalc + ACOUSTID_KEY exist."""
    sil = detect_silence(src, noise="-38dB", d=0.4)
    silent = sum(((e or dur) - st) for st, e in sil)
    rep = {"mean_db": loudness(src), "silent_ratio": round(silent / dur, 3) if dur else 1.0,
           "method": "heuristic_continuity", "music_suspected": False, "fingerprint": None}
    rep["music_suspected"] = bool(rep["mean_db"] is not None and rep["mean_db"] > -40 and rep["silent_ratio"] < 0.05 and dur > 8)
    if shutil.which("fpcalc") and os.environ.get("ACOUSTID_KEY"):
        rep["fingerprint"] = "acoustid_available_not_run"  # hook point; see README
    return rep


def transcribe(src: Path, sid: int):
    AUDIO.mkdir(parents=True, exist_ok=True)
    wav = AUDIO / f"src{sid}.wav"
    run([FFMPEG, "-y", "-v", "error", "-i", src, "-vn", "-ac", "1", "-ar", "16000", wav])
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        return None, "unavailable_no_faster_whisper"
    try:
        model = WhisperModel(load_settings()["whisper_model"], device="cpu", compute_type="int8",
                             download_root=str(ROOT / "CONFIG" / "models"))
        segs, info = model.transcribe(str(wav), vad_filter=True, word_timestamps=False)
        segs = [{"start": round(x.start, 2), "end": round(x.end, 2), "text": x.text.strip()} for x in segs]
        return {"language": info.language, "segments": segs, "text": " ".join(x["text"] for x in segs)}, "ok"
    except Exception as e:
        return None, f"unavailable_model ({str(e)[:120]})"


def vision_notes(sheet: Path, s: dict):
    from .ai import ai_available, ask_vision
    if not ai_available():
        return None, "contact_sheet_generated_not_model_viewed"
    prompt = ("This is a contact sheet of frames (timestamps top-left) from a creator's own gameplay capture or image. "
              "Describe ONLY what is visibly present: location type, vehicles, actions, UI elements, anything surprising. "
              "Give timestamps of the most interesting moments. If unsure, say unsure. Do not guess game mechanics. "
              "Reply as JSON: {\"summary\":str, \"moments\":[{\"t\":str,\"what\":str,\"interest\":1-10}], \"spoiler_risk\":bool, \"third_party_content\":bool}")
    out = ask_vision(prompt, sheet)
    return (out, "model_viewed_contact_sheet") if out else (None, "contact_sheet_generated_not_model_viewed")
