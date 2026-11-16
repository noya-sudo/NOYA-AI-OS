"""Text-to-speech. Order: Piper (natural, local, free) -> espeak-ng (robotic, local). Returns (wav, duration, engine)."""
import shutil
import subprocess
import wave
from pathlib import Path

from .config import ROOT, load_settings
from .media import FFMPEG, run


KOKORO_MODEL = ROOT / "CONFIG" / "voices" / "kokoro-v1.0.int8.onnx"
KOKORO_VOICES = ROOT / "CONFIG" / "voices" / "voices-v1.0.bin"
_kokoro = None


def engine() -> str:
    v = load_settings()["voice"]
    if v["provider"] in ("auto", "kokoro") and KOKORO_MODEL.exists() and KOKORO_VOICES.exists():
        try:
            import kokoro_onnx  # noqa: F401
            return "kokoro"
        except ImportError:
            pass
    model = ROOT / v["piper_model"]
    if v["provider"] in ("auto", "piper") and model.exists():
        try:
            import piper  # noqa: F401
            return "piper"
        except ImportError:
            pass
    if shutil.which("espeak-ng") or shutil.which("espeak"):
        return "espeak"
    return "none"


def synth(text: str, out: Path) -> tuple[Path, float, str]:
    v = load_settings()["voice"]
    eng = engine()
    raw = out.with_suffix(".raw.wav")
    if eng == "kokoro":
        global _kokoro
        import soundfile as sf
        from kokoro_onnx import Kokoro
        if _kokoro is None:
            _kokoro = Kokoro(str(KOKORO_MODEL), str(KOKORO_VOICES))
        samples, sr = _kokoro.create(text, voice=v.get("kokoro_voice", "bm_george"), speed=float(v.get("kokoro_speed", 1.08)), lang="en-gb")
        sf.write(str(raw), samples, sr)
    elif eng == "piper":
        from piper import PiperVoice
        voice = PiperVoice.load(str(ROOT / v["piper_model"]))
        with wave.open(str(raw), "wb") as w:
            voice.synthesize_wav(text, w)
    elif eng == "espeak":
        exe = shutil.which("espeak-ng") or shutil.which("espeak")
        subprocess.run([exe, "-v", v["espeak_voice"], "-s", str(v["rate"]), "-p", "38", "-w", str(raw), text], check=True)
    else:
        raise RuntimeError("No TTS engine available. Install Piper voice or espeak-ng (see README).")
    # normalise to 48k stereo, gentle EQ + compression so voice sits clearly above the bed
    run([FFMPEG, "-y", "-v", "error", "-i", raw, "-af",
         "highpass=f=80,lowpass=f=9500,acompressor=threshold=-20dB:ratio=3:attack=5:release=80,loudnorm=I=-16:TP=-1.5:LRA=7",
         "-ar", "48000", "-ac", "2", out])
    raw.unlink(missing_ok=True)
    with wave.open(str(out)) as w:
        dur = w.getnframes() / w.getframerate()
    return out, dur, eng
