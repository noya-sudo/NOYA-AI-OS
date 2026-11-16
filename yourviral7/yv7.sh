#!/usr/bin/env bash
# YOURVIRAL7 launcher: ./yv7.sh start | stop | health | scan | queue ...
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export YV7_HOME="${YV7_HOME:-$DIR}"
PY="$DIR/.venv/bin/python"; [ -x "$PY" ] || PY="$(command -v python3)"
cd "$DIR" && exec "$PY" -m yv7 "$@"
