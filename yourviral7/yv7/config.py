"""Paths and settings. Everything lives under one root folder (YV7_HOME)."""
import json
import os
from pathlib import Path

ROOT = Path(os.environ.get("YV7_HOME", Path(__file__).resolve().parent.parent)).resolve()

DIRS = [
    "INBOX/GAMEPLAY", "INBOX/PHOTOS", "INBOX/PRELAUNCH", "PROCESSING", "ARCHIVE", "QUARANTINE",
    "OUTPUT/READY", "OUTPUT/SCHEDULED", "OUTPUT/POSTED", "OUTPUT/FAILED", "CONTENT_DATABASE",
    "ANALYTICS", "LOGS", "CONFIG", "PROMPTS", "DASHBOARD", "RIGHTS", "BACKUPS",
    "PROCESSING/work", "PROCESSING/sheets", "PROCESSING/audio", "CONFIG/voices", "CONFIG/models",
]

INBOX = ROOT / "INBOX"
STOP_FILE = ROOT / "STOP"
DB_PATH = ROOT / "CONTENT_DATABASE" / "yourviral7.sqlite"
SETTINGS_PATH = ROOT / "CONFIG" / "settings.json"
SECRETS_PATH = ROOT / "CONFIG" / "secrets.env"   # gitignored; never committed

VIDEO_EXT = {".mp4", ".mov", ".mkv", ".m4v", ".webm", ".avi"}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".bmp"}
DATA_EXT = {".csv", ".xlsx", ".json"}

DEFAULTS = {
    "account": "@yourviral7",
    "timezone": "Europe/London",
    "mode": "PRELAUNCH",                 # PRELAUNCH | LAUNCH
    "launch_date": "2026-11-19",
    "launch_authorized": False,           # owner flips via `yv7 mode launch --confirm`
    "daily_post_cap": 2,                  # 1..6
    "post_slots": ["12:30", "18:30", "21:00", "16:00", "20:00", "22:30"],
    "min_score_to_publish": 62,
    "publisher": "export",                # export | metricool
    "require_owner_approval": True,       # each post needs `yv7 approve <id>` unless False
    "tiktok_privacy": "PUBLIC_TO_EVERYONE",
    "mute_game_audio_default": True,      # in-game radio/music risk
    "voice": {"provider": "auto", "kokoro_voice": "bm_george", "kokoro_speed": 1.08, "piper_model": "CONFIG/voices/en_GB-alan-medium.onnx", "espeak_voice": "en-gb", "rate": 158},
    "whisper_model": "small",             # faster-whisper; downloads on first use where network allows
    "budget_gbp_per_day": 3.0,
    "ai": {"provider": "anthropic", "model": "claude-haiku-5-5", "est_gbp_per_call": 0.01},
    "loop_seconds": 60,
    "max_renders_per_cycle": 3,
    "max_candidates_per_day": 6,
    "start_followers": 4901,
    "start_likes": 500000,
}


def ensure_dirs():
    for d in DIRS:
        (ROOT / d).mkdir(parents=True, exist_ok=True)


def load_settings() -> dict:
    ensure_dirs()
    s = json.loads(json.dumps(DEFAULTS))
    if SETTINGS_PATH.exists():
        user = json.loads(SETTINGS_PATH.read_text())
        for k, v in user.items():
            if isinstance(v, dict) and isinstance(s.get(k), dict):
                s[k].update(v)
            else:
                s[k] = v
    else:
        SETTINGS_PATH.write_text(json.dumps(s, indent=2))
    s["daily_post_cap"] = max(1, min(6, int(s["daily_post_cap"])))
    return s


def save_settings(s: dict):
    SETTINGS_PATH.write_text(json.dumps(s, indent=2))


def load_secrets():
    """Read KEY=VALUE lines from CONFIG/secrets.env into os.environ (never logged)."""
    if SECRETS_PATH.exists():
        for line in SECRETS_PATH.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())
