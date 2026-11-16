#!/usr/bin/env bash
# One-time setup on the owner's Mac or Linux machine. Safe to re-run.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$DIR"
echo "== YOURVIRAL7 install in $DIR"
if [[ "$(uname)" == "Darwin" ]]; then
  command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
  brew list ffmpeg >/dev/null 2>&1 || brew install ffmpeg
  brew list tesseract >/dev/null 2>&1 || brew install tesseract
  brew list espeak-ng >/dev/null 2>&1 || brew install espeak-ng
else
  sudo apt-get update -y && sudo apt-get install -y ffmpeg tesseract-ocr espeak-ng python3-venv
fi
python3 -m venv .venv
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt
mkdir -p CONFIG/voices
V=CONFIG/voices/en_GB-alan-medium.onnx
[ -f "$V" ] || curl -fL -o "$V" https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/medium/en_GB-alan-medium.onnx
[ -f "$V.json" ] || curl -fL -o "$V.json" https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/medium/en_GB-alan-medium.onnx.json
.venv/bin/python -c "from faster_whisper import WhisperModel; WhisperModel('small', device='cpu', compute_type='int8', download_root='CONFIG/models')" || echo "WARN: whisper model download failed; transcription will be skipped"
[ -f CONFIG/secrets.env ] || cp CONFIG/secrets.env.example CONFIG/secrets.env
./yv7.sh dashboard >/dev/null
# start at login
if [[ "$(uname)" == "Darwin" ]]; then
  P=~/Library/LaunchAgents/com.yourviral7.service.plist
  sed "s#__DIR__#$DIR#g" install/com.yourviral7.service.plist > "$P"
  launchctl unload "$P" 2>/dev/null || true; launchctl load "$P"
  echo "Installed launchd agent (starts at login)."
else
  mkdir -p ~/.config/systemd/user
  sed "s#__DIR__#$DIR#g" install/yourviral7.service > ~/.config/systemd/user/yourviral7.service
  systemctl --user daemon-reload && systemctl --user enable --now yourviral7.service
  echo "Installed systemd user service (starts at login)."
fi
./yv7.sh health
