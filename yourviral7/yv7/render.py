"""Deterministic timeline renderer -> 1080x1920 H.264/AAC MP4.

Timeline spec (stored per candidate):
{ "fps": 30|60|None, "hook": "...", "segments": [
    {"type":"card", "kicker":"...", "title":"...", "body":"...", "vo":"sentence(s)", "min":2.5},
    {"type":"clip", "source_id":1, "start":3.0, "end":12.0, "vo":"...", "callout":"...", "mute":true},
    {"type":"image","source_id":2, "vo":"...", "callout":"..."} ],
  "outro": {"title":"Follow @yourviral7", "body":"..."} }
"""
import json
import math
import random
import subprocess
import textwrap
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from . import db
from .config import ROOT, load_settings
from .media import FFMPEG, probe, run
from .tts import synth

W, H = 1080, 1920
FONTS = ROOT / "assets" / "fonts"
WORK = ROOT / "PROCESSING" / "work"
SAFE_BOTTOM = 470   # TikTok caption/UI zone
SAFE_RIGHT = 150    # TikTok action buttons
VENC = ["-c:v", "libx264", "-preset", "medium", "-crf", "18", "-maxrate", "14M", "-bufsize", "28M", "-pix_fmt", "yuv420p", "-profile:v", "high", "-movflags", "+faststart"]
AENC = ["-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2"]


def font(weight="ExtraBold", size=80):
    p = FONTS / f"Inter-{weight}.otf"
    try:
        return ImageFont.truetype(str(p), size)
    except OSError:
        return ImageFont.truetype("DejaVuSans-Bold.ttf", size)


# ---------- original graphics ----------
PALETTES = [((10, 6, 32), (120, 18, 92), (255, 92, 168)),     # dusk magenta
            ((4, 18, 38), (0, 92, 120), (64, 224, 208)),      # ocean teal
            ((22, 8, 8), (140, 40, 10), (255, 170, 60)),      # sunset amber
            ((8, 8, 14), (40, 40, 70), (180, 160, 255))]      # night violet


def card_png(out: Path, kicker="", title="", body="", idx=0, bg_image: Path | None = None, label="ORIGINAL COMMENTARY",
             slide_no: str = "", still: bool = False):
    top, mid, acc = PALETTES[idx % len(PALETTES)]
    img = Image.new("RGB", (W + 120, H + 210), top)
    d = ImageDraw.Draw(img)
    iw, ih = img.size
    for y in range(ih):                       # vertical gradient
        t = y / ih
        c = tuple(int(top[i] * (1 - t) + mid[i] * t) for i in range(3))
        d.line([(0, y), (iw, y)], fill=c)
    if bg_image and Path(bg_image).exists():
        try:
            b = Image.open(bg_image).convert("RGB")
            b = _cover(b, iw, ih).filter(ImageFilter.GaussianBlur(18))
            img = Image.blend(img, b, 0.55)
            d = ImageDraw.Draw(img)
        except Exception:
            pass
    rnd = random.Random(idx * 7 + len(title))  # deterministic decorative grid / sun
    cx, cy, r = iw // 2, int(ih * 0.30), 330
    for k in range(r, 0, -6):
        a = k / r
        col = tuple(int(acc[i] * (1 - a) * 0.55 + mid[i] * a * 0.45) for i in range(3))
        d.ellipse([cx - k, cy - k, cx + k, cy + k], fill=col)
    for i in range(14):                       # horizon lines through the sun
        y = cy + 40 + i * 22
        d.rectangle([cx - r, y, cx + r, y + 4 + i // 3], fill=tuple(int(x * 0.9) for x in mid))
    for i in range(0, iw, 90):
        d.line([(i, int(ih * 0.62)), (iw // 2 + (i - iw // 2) * 3, ih)], fill=tuple(min(255, x + 18) for x in mid), width=2)
    for y in range(int(ih * 0.62), ih, 60):
        d.line([(0, y), (iw, y)], fill=tuple(min(255, x + 18) for x in mid), width=2)
    # scrim for legibility
    scrim = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(scrim)
    y0, y1 = int(ih * 0.36), int(ih * 0.84)
    for yy in range(y0, y1):          # soft-edged scrim
        e = min(yy - y0, y1 - yy) / 90
        sd.line([(0, yy), (iw, yy)], fill=(0, 0, 0, int(130 * min(1, e))))
    img = Image.alpha_composite(img.convert("RGBA"), scrim)
    d = ImageDraw.Draw(img)
    x0, y = 60 + 60, int(ih * 0.43)
    maxw = iw - 120 - SAFE_RIGHT - 60
    if kicker:
        f = font("Bold", 44)
        tw = d.textlength(kicker.upper(), font=f)
        d.rounded_rectangle([x0 - 8, y - 6, x0 + tw + 22, y + 62], 12, fill=acc)
        d.text((x0 + 7, y + 2), kicker.upper(), font=f, fill=(10, 10, 16))
        y += 100
    if title:
        size = 112 if len(title) < 22 else 92 if len(title) < 40 else 76
        f = font("Black", size)
        for line in _wrap(d, title, f, maxw):
            d.text((x0, y), line, font=f, fill=(255, 255, 255), stroke_width=3, stroke_fill=(0, 0, 0))
            y += int(size * 1.08)
        y += 24
    if body:
        f = font("SemiBold", 54)
        for line in _wrap(d, body, f, maxw)[:5]:
            d.text((x0, y), line, font=f, fill=(235, 235, 245))
            y += 70
    f = font("Bold", 34)
    d.text((x0, 150), "YOURVIRAL7", font=f, fill=acc)
    d.text((x0, 196), label, font=font("Medium", 28), fill=(220, 220, 230))
    if slide_no:
        d.text((iw - 60 - 230, 150), slide_no, font=font("Bold", 34), fill=(235, 235, 245))
    img = img.convert("RGB")
    if still:                       # photo-mode slide: crop to exact 1080x1920
        img = img.crop((60, 105, 60 + W, 105 + H))
    img.save(out, quality=95)
    return out


def text_layout(kicker, title, body):
    """Deterministic line-wrapping shared by the animated (ASS) text overlay."""
    tmp = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    maxw = W - 120 - SAFE_RIGHT - 30
    size = 104 if len(title) < 22 else 88 if len(title) < 40 else 74
    tl = _wrap(tmp, title, font("Black", size), maxw)[:3] if title else []
    bl = _wrap(tmp, body, font("SemiBold", 52), maxw)[:2] if body else []
    return size, tl, bl


def _cover(im, w, h):
    s = max(w / im.width, h / im.height)
    im = im.resize((int(im.width * s) + 1, int(im.height * s) + 1))
    l, t = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((l, t, l + w, t + h))


def _wrap(d, text, f, maxw):
    text = text.replace(" X|S", "\u00a0X|S").replace("PlayStation 5", "PlayStation\u00a05")
    words, lines, cur = [w for w in text.split(" ") if w], [], ""
    for wd in words:
        t = (cur + " " + wd).strip()
        if d.textlength(t, font=f) <= maxw:
            cur = t
        else:
            if cur:
                lines.append(cur)
            cur = wd
    if cur:
        lines.append(cur)
    return lines


# ---------- subject-aware crop ----------
def motion_center_x(src: Path, start: float, dur: float) -> float:
    """Fraction (0..1) of frame width where motion concentrates; 0.5 when undetermined."""
    try:
        w, h = 160, 90
        p = subprocess.run([FFMPEG, "-v", "error", "-ss", f"{start}", "-t", f"{max(dur,1)}", "-i", str(src), "-vf",
                            f"fps=4,scale={w}:{h},format=gray", "-f", "rawvideo", "-"], capture_output=True, timeout=120)
        a = np.frombuffer(p.stdout, dtype=np.uint8)
        n = a.size // (w * h)
        if n < 3:
            return 0.5
        fr = a[: n * w * h].reshape(n, h, w).astype(np.int16)
        diff = np.abs(np.diff(fr, axis=0)).sum(axis=(0, 1)).astype(float)
        diff[:8] = diff[-8:] = 0          # ignore HUD edges
        if diff.sum() <= 0:
            return 0.5
        cx = float((diff * np.arange(w)).sum() / diff.sum() / w)
        return min(max(0.5 + (cx - 0.5) * 0.7, 0.3), 0.7)   # damped toward centre
    except Exception:
        return 0.5


# ---------- segments ----------
def _seg_card(seg, i, fps, dur, voice, out, bg=None):
    png = WORK / f"{out.stem}.png"
    if seg.get("animate", True):
        card_png(png, "", "", "", seg.get("palette", i), bg, label=seg.get("label", "ORIGINAL COMMENTARY"))
    else:
        card_png(png, seg.get("kicker", ""), seg.get("title", ""), seg.get("body", ""), seg.get("palette", i), bg,
                 label=seg.get("label", "ORIGINAL COMMENTARY"))
    n = max(int(dur * fps), 1)
    zoom = f"crop={W}:{H}:x='60*(1-t/{dur:.3f})':y='105*(t/{dur:.3f})'"   # slow drift on oversized card
    _encode([FFMPEG, "-y", "-v", "error", "-loop", "1", "-framerate", str(fps), "-i", png], voice, dur,
            f"[0:v]{zoom},format=yuv420p" + (",fade=t=in:st=0:d=0.2" if i > 0 else "") + "[v]", out, fps, n)


def _seg_media(seg, src: dict, fps, dur, voice, out, mute):
    path = Path(src["archive_path"])
    if src["kind"] == "image":
        inp = ["-loop", "1", "-framerate", str(fps), "-i", path]
        start = 0
    else:
        start = float(seg.get("start", 0))
        avail = max(src["duration"] - start, 0.5)
        inp = ["-ss", f"{start:.3f}", "-t", f"{min(dur, avail):.3f}", "-i", path]
    landscape = src["width"] >= src["height"]
    if landscape:
        fx = motion_center_x(path, start, min(dur, 8)) if src["kind"] == "video" else 0.5
        fgw = int(W * 1.38) // 2 * 2
        vf = (f"[0:v]split[a][b];[a]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},boxblur=28:2,eq=brightness=-0.12[bg];"
              f"[b]scale={fgw}:-2,crop={W}:ih:x='(iw-{W})*{fx:.3f}':y=0[fg];[bg][fg]overlay=0:(H-h)/2-140")
    else:
        vf = f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H}"
    if src["kind"] == "image":
        vf += f",zoompan=z='min(zoom+0.0006,1.12)':d=1:s={W}x{H}:fps={fps}" if not landscape else ""
    vf += f",fps={fps},tpad=stop_mode=clone:stop_duration={dur:.3f},trim=duration={dur:.3f},setpts=PTS-STARTPTS,format=yuv420p[v]"
    use_game_audio = src["kind"] == "video" and src["has_audio"] and not mute
    _encode([FFMPEG, "-y", "-v", "error", *inp], voice, dur, vf, out, fps, int(dur * fps), game_audio=use_game_audio)


def _encode(head, voice, dur, vf, out, fps, n, game_audio=False):
    cmd = list(head)
    if voice:
        cmd += ["-i", voice]
    else:
        cmd += ["-f", "lavfi", "-t", f"{dur:.3f}", "-i", "anullsrc=r=48000:cl=stereo"]
    if game_audio:   # duck game audio under VO
        af = (f"[0:a]aresample=48000,volume=0.22,apad,atrim=0:{dur:.3f}[g];[1:a]apad,atrim=0:{dur:.3f}[vo];"
              f"[g][vo]amix=inputs=2:duration=first:normalize=0[a]")
    else:
        af = f"[1:a]aresample=48000,apad,atrim=0:{dur:.3f}[a]"
    cmd += ["-filter_complex", f"{vf};{af}", "-map", "[v]", "-map", "[a]", "-frames:v", str(n), "-r", str(fps),
            *VENC, *AENC, "-t", f"{dur:.3f}", out]
    run(cmd)


# ---------- subtitles (ASS) ----------
def _ass_time(t):
    h, r = divmod(t, 3600)
    m, s = divmod(r, 60)
    return f"{int(h)}:{int(m):02d}:{s:05.2f}"


def build_ass(cues, hook, total, out: Path, callouts, texts=()):
    fontname = "Inter ExtraBold"
    hdr = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Sub,{fontname},74,&H00FFFFFF,&H0000FFFF,&H00000000,&H64000000,-1,0,0,0,100,100,0,0,1,6,2,2,90,{SAFE_RIGHT},{SAFE_BOTTOM},1
Style: Hook,Inter Black,92,&H0000F0FF,&H00FFFFFF,&H00000000,&H96000000,-1,0,0,0,100,100,0,0,3,10,0,8,80,{SAFE_RIGHT},250,1
Style: Kicker,Inter Bold,42,&H0010100A,&H00FFFFFF,&H00A85CFF,&H00A85CFF,-1,0,0,0,100,100,0,0,3,12,0,7,0,0,0,1
Style: Title,Inter Black,100,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,4,3,7,0,0,0,1
Style: Body,Inter SemiBold,52,&H00F5EBEB,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,7,0,0,0,1
Style: Callout,Inter ExtraBold,58,&H00FFFFFF,&H00FFFFFF,&H00A8205C,&H00A8205C,-1,0,0,0,100,100,0,0,3,14,0,8,90,{SAFE_RIGHT},420,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    ev = []
    if hook:   # visible from frame 0, punch-in, readable within 1.5s
        ev.append(f"Dialogue: 3,{_ass_time(0)},{_ass_time(min(2.2, total))},Hook,,0,0,0,,{{\\fad(0,180)\\fscx118\\fscy118\\t(0,140,\\fscx100\\fscy100)}}{_esc(hook)}")
    for line in texts:
        ev.append(line)
    for a, b, text in callouts:
        ev.append(f"Dialogue: 1,{_ass_time(a)},{_ass_time(b)},Callout,,0,0,0,,{{\\fad(150,150)}}{_esc(text)}")
    for a, b, text in cues:
        ev.append(f"Dialogue: 0,{_ass_time(a)},{_ass_time(b)},Sub,,0,0,0,,{{\\fad(60,0)}}{_esc(text)}")
    out.write_text(hdr + "\n".join(ev) + "\n", encoding="utf-8")


ACCENTS_ASS = ["&H00A85CFF", "&H00D0E040", "&H003CAAFF", "&H00FFA0B4"]   # BGR of palette accents


def text_events(seg, start, dur, idx):
    """Kicker pill slides in, title lines rise in staggered, body fades in — all original typography."""
    if not seg.get("animate", True) or seg.get("type") != "card":
        return []
    size, tl, bl = text_layout(seg.get("kicker", ""), seg.get("title", ""), seg.get("body", ""))
    x, y, end = 120, 800, start + dur
    acc = ACCENTS_ASS[seg.get("palette", idx) % 4]
    ev = []
    if seg.get("kicker"):
        ev.append(f"Dialogue: 1,{_ass_time(start)},{_ass_time(end)},Kicker,,0,0,0,,{{\\an7\\3c{acc}\\4c{acc}\\fad(120,120)\\move({x-70},{y},{x},{y},0,220)}}{_esc(seg['kicker'].upper())}")
        y += 96
    for j, line in enumerate(tl):
        d0 = 120 + j * 90
        ev.append(f"Dialogue: 1,{_ass_time(start + d0/1000)},{_ass_time(end)},Title,,0,0,0,,{{\\an7\\fs{size}\\fad(160,120)\\move({x},{y+50},{x},{y},0,260)}}{_esc(line)}")
        y += int(size * 1.08)
    y += 18
    for j, line in enumerate(bl):
        d0 = 380 + len(tl) * 90 + j * 80
        ev.append(f"Dialogue: 1,{_ass_time(start + d0/1000)},{_ass_time(end)},Body,,0,0,0,,{{\\an7\\fad(220,120)\\pos({x},{y})}}{_esc(line)}")
        y += 66
    return ev


def _esc(t):
    return t.replace("\\", "").replace("{", "(").replace("}", ")").replace("\n", "\\N")


def chunk_cues(text, start, dur, max_words=3):
    words = text.split()
    if not words:
        return []
    chunks = [" ".join(words[i:i + max_words]) for i in range(0, len(words), max_words)]
    total_chars = sum(len(c) + 3 for c in chunks)
    t, cues = start, []
    for c in chunks:
        d = dur * (len(c) + 3) / total_chars
        cues.append((t, t + d - 0.02, c.upper()))
        t += d
    return cues


# ---------- original music bed ----------
def music_bed(out: Path, dur: float, seed=0):
    """Procedurally generated ambient synth pad — wholly original, no licence needed."""
    roots = [[110, 138.59, 164.81], [98, 123.47, 146.83], [87.31, 110, 130.81], [103.83, 130.81, 155.56]]
    chords = roots[seed % 4:] + roots[:seed % 4]
    bar = 4.0
    expr = []
    for i, ch in enumerate(chords):
        env = f"(gte(mod(t,{bar*4}),{i*bar})*lt(mod(t,{bar*4}),{(i+1)*bar}))"
        tone = "+".join(f"sin(2*PI*{f}*t)+0.4*sin(2*PI*{f*2}*t)" for f in ch)
        expr.append(f"{env}*({tone})")
    body = "+".join(expr)
    pulse = "(0.6+0.4*sin(2*PI*2*t))"
    kick = f"0.9*exp(-18*mod(t,0.5))*sin(2*PI*55*mod(t,0.5)*(1+3*exp(-30*mod(t,0.5))))"
    run([FFMPEG, "-y", "-v", "error", "-f", "lavfi", "-i",
         f"aevalsrc='0.05*{pulse}*({body})+0.10*{kick}|0.05*{pulse}*({body})+0.10*{kick}':s=48000:d={dur:.2f}",
         "-af", "lowpass=f=2400,aecho=0.6:0.5:180:0.25,volume=0.9,afade=t=in:d=1.5,afade=t=out:st=" + f"{max(dur-2,0):.2f}:d=2",
         "-c:a", "pcm_s16le", out])


# ---------- main ----------
def render(candidate_id: int, variant="A", hook_override=None, spec_override=None) -> dict:
    with db.tx() as c:
        cand = dict(c.execute("SELECT * FROM candidates WHERE id=?", (candidate_id,)).fetchone())
    spec = spec_override or json.loads(cand["script"])
    s = load_settings()
    WORK.mkdir(parents=True, exist_ok=True)
    tag = f"c{candidate_id}" + ("s" if spec_override else "")          # segments/VO shared across hook variants; only the overlay pass differs
    srcs = {}
    for sid in json.loads(cand["source_ids"] or "[]"):
        with db.tx() as c:
            r = c.execute("SELECT * FROM sources WHERE id=?", (sid,)).fetchone()
        if r:
            srcs[sid] = dict(r)
    vids = [x for x in srcs.values() if x["kind"] == "video"]
    fps = spec.get("fps") or (60 if vids and max(v["fps"] for v in vids) > 45 else 30)
    segs = list(spec["segments"]) + ([dict(type="card", **spec["outro"], palette=3)] if spec.get("outro") else [])
    parts, cues, callouts, t, engines, texts = [], [], [], 0.0, set(), []
    for i, seg in enumerate(segs):
        voice, vdur = None, 0.0
        if seg.get("vo"):
            wav = WORK / f"{tag}_{i}.wav"
            if variant != "A" and wav.exists():
                import wave
                with wave.open(str(wav)) as w:
                    voice, vdur = wav, w.getnframes() / w.getframerate()
            else:
                voice, vdur, eng = synth(seg["vo"], wav)
                engines.add(eng)
        dur = max(vdur + float(seg.get("pad", 0.35)), float(seg.get("min", 2.0)))
        if seg["type"] == "clip" and not seg.get("vo"):
            dur = float(seg["end"]) - float(seg["start"])
        out = WORK / f"{tag}_{i:02d}.mp4"
        reuse = variant != "A" and out.exists()
        if reuse:
            pass
        elif seg["type"] == "card":
            bg = Path(srcs[seg["bg_source"]]["archive_path"]) if seg.get("bg_source") in srcs else None
            _seg_card(seg, i, fps, dur, voice, out, bg)
        else:
            src = srcs[seg["source_id"]]
            mute = seg.get("mute", s["mute_game_audio_default"]) or _music_flag(src["id"])
            _seg_media(seg, src, fps, dur, voice, out, mute)
        if seg.get("vo"):
            cues += chunk_cues(seg["vo"], t + 0.05, vdur)
        elif seg.get("captions"):
            for a, b, txt in seg["captions"]:
                cues.append((t + a, t + b, txt.upper()))
        if seg.get("callout"):
            callouts.append((t + 0.1, t + min(dur, 3.2), seg["callout"]))
        texts += text_events(seg, t, dur, i)
        parts.append(out)
        t += dur
    total = t
    lst = WORK / f"{tag}_list.txt"
    lst.write_text("".join(f"file '{p.as_posix()}'\n" for p in parts))
    joined = WORK / f"{tag}_joined.mp4"
    if not (variant != "A" and joined.exists()):
        run([FFMPEG, "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", joined])
    ass = WORK / f"{tag}{variant}.ass"
    build_ass(cues, hook_override or cand["hook"], total, ass, callouts, texts)
    bed = WORK / f"{tag}_bed.wav"
    if not (variant != "A" and bed.exists()):
        music_bed(bed, total + 0.5, seed=candidate_id)
    final_dir = ROOT / "OUTPUT" / "READY"
    final = final_dir / f"{cand['slug']}_{variant}.mp4"
    fontsdir = FONTS.as_posix()
    run([FFMPEG, "-y", "-v", "error", "-i", joined, "-i", bed, "-f", "lavfi", "-i", f"color=c=0xFF5CA8:s={W}x9:r={fps}",
         "-filter_complex",
         f"[0:v]subtitles='{ass.as_posix()}':fontsdir='{fontsdir}'[s];"
         f"[s][2:v]overlay=x='-w+w*t/{total:.3f}':y=0:shortest=1[v];"
         f"[1:a]volume=0.30[m];[0:a][m]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]",
         "-map", "[v]", "-map", "[a]", "-r", str(fps), *VENC, *AENC, final])
    thumb = final_dir / f"{cand['slug']}_{variant}.jpg"
    run([FFMPEG, "-y", "-v", "error", "-ss", "0.9", "-i", final, "-frames:v", "1", "-q:v", "2", thumb])
    return {"path": str(final), "thumbnail": str(thumb), "duration": total, "fps": fps, "tts": sorted(engines)}


def _music_flag(sid):
    with db.tx() as c:
        r = c.execute("SELECT audio_report FROM analyses WHERE source_id=? ORDER BY id DESC LIMIT 1", (sid,)).fetchone()
    return bool(r and r["audio_report"] and json.loads(r["audio_report"]).get("music_suspected"))
