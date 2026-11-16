import sys
from datetime import datetime

from .config import ROOT


def log(level, area, message):
    line = f"{datetime.now().isoformat(timespec='seconds')} [{level.upper():5}] {area}: {message}"
    print(line, file=sys.stderr, flush=True)
    try:
        (ROOT / "LOGS").mkdir(parents=True, exist_ok=True)
        with open(ROOT / "LOGS" / f"yv7_{datetime.now():%Y%m%d}.log", "a") as f:
            f.write(line + "\n")
    except OSError:
        pass
