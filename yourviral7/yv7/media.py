"""FFmpeg/ffprobe helpers."""
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

FFMPEG = shutil.which("ffmpeg") or "ffmpeg"
FFPROBE = shutil.which("ffprobe") or "ffprobe"


def run(cmd, timeout=1800, check=True):
    p = subprocess.run([str(x) for x in cmd], capture_output=True, text=True, timeout=timeout)
    if check and p.returncode != 0:
        raise RuntimeError(f"{Path(str(cmd[0])).name} failed ({p.returncode}): {p.stderr[-1500:]}")
    return p


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def probe(path: Path) -> dict:
    p = run([FFPROBE, "-v", "error", "-print_format", "json", "-show_format", "-show_streams", path], timeout=120)
    data = json.loads(p.stdout)
    v = next((s for s in data.get("streams", []) if s.get("codec_type") == "video"), None)
    a = next((s for s in data.get("streams", []) if s.get("codec_type") == "audio"), None)
    fps = 0.0
    if v and v.get("avg_frame_rate", "0/0") != "0/0":
        n, d = v["avg_frame_rate"].split("/")
        fps = round(float(n) / float(d), 3) if float(d) else 0.0
    dur = float(data.get("format", {}).get("duration") or (v or {}).get("duration") or 0)
    return {
        "width": int(v["width"]) if v else 0, "height": int(v["height"]) if v else 0, "fps": fps,
        "duration": dur, "vcodec": (v or {}).get("codec_name"), "acodec": (a or {}).get("codec_name"),
        "has_audio": a is not None, "bitrate": int(data.get("format", {}).get("bit_rate") or 0),
        "pix_fmt": (v or {}).get("pix_fmt"), "rotation": _rotation(v), "format": data.get("format", {}).get("format_name"),
    }


def _rotation(v):
    if not v:
        return 0
    for sd in v.get("side_data_list", []) or []:
        if "rotation" in sd:
            return int(sd["rotation"])
    return int((v.get("tags") or {}).get("rotate", 0) or 0)


def detect_silence(path: Path, noise="-35dB", d=0.6):
    p = run([FFMPEG, "-hide_banner", "-nostats", "-i", path, "-af", f"silencedetect=noise={noise}:d={d}", "-f", "null", "-"], check=False)
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", p.stderr)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", p.stderr)]
    return list(zip(starts, ends + [None] * (len(starts) - len(ends))))


def detect_black(path: Path, d=0.5):
    p = run([FFMPEG, "-hide_banner", "-nostats", "-i", path, "-vf", f"blackdetect=d={d}:pix_th=0.10", "-an", "-f", "null", "-"], check=False)
    return [(float(a), float(b)) for a, b in re.findall(r"black_start:([\d.]+) black_end:([\d.]+)", p.stderr)]


def detect_scenes(path: Path, thresh=0.35, max_n=60):
    p = run([FFMPEG, "-hide_banner", "-nostats", "-i", path, "-vf", f"select='gt(scene,{thresh})',showinfo", "-an", "-f", "null", "-"], check=False)
    return [round(float(t), 2) for t in re.findall(r"pts_time:([\d.]+)", p.stderr)][:max_n]


def loudness(path: Path):
    p = run([FFMPEG, "-hide_banner", "-nostats", "-i", path, "-af", "volumedetect", "-f", "null", "-"], check=False)
    m = re.search(r"mean_volume: ([-\d.]+) dB", p.stderr)
    return float(m.group(1)) if m else None
