"""Optional Claude API calls with a hard daily GBP budget. Pipeline works fully without it."""
import base64
import json
import os
from datetime import date
from pathlib import Path

from . import db
from .config import load_settings, load_secrets


def spent_today() -> float:
    with db.tx() as c:
        r = c.execute("SELECT COALESCE(SUM(amount_gbp),0) s FROM spend WHERE date=?", (date.today().isoformat(),)).fetchone()
    return float(r["s"])


def ai_available() -> bool:
    load_secrets()
    s = load_settings()
    if not os.environ.get("ANTHROPIC_API_KEY"):
        return False
    return spent_today() + s["ai"]["est_gbp_per_call"] <= s["budget_gbp_per_day"]


def _call(content, max_tokens=900):
    s = load_settings()
    if not ai_available():
        return None
    try:
        import anthropic
    except ImportError:
        db.event("warn", "ai", "anthropic SDK not installed; skipping AI step")
        return None
    try:
        client = anthropic.Anthropic()
        msg = client.messages.create(model=s["ai"]["model"], max_tokens=max_tokens,
                                     messages=[{"role": "user", "content": content}])
        u = msg.usage
        # conservative cost estimate; recorded against the daily cap
        cost = max(s["ai"]["est_gbp_per_call"], (u.input_tokens * 1.0 + u.output_tokens * 5.0) / 1e6 * 0.8)
        with db.tx() as c:
            c.execute("INSERT INTO spend(date,service,amount_gbp,note) VALUES(?,?,?,?)",
                      (date.today().isoformat(), "anthropic", round(cost, 4), s["ai"]["model"]))
        return "".join(b.text for b in msg.content if getattr(b, "type", "") == "text")
    except Exception as e:
        db.event("warn", "ai", f"AI call failed: {str(e)[:200]}")
        return None


def ask_text(prompt: str):
    return _call([{"type": "text", "text": prompt}])


def ask_vision(prompt: str, image: Path):
    data = base64.b64encode(Path(image).read_bytes()).decode()
    return _call([{"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": data}},
                  {"type": "text", "text": prompt}])


def ask_json(prompt: str):
    out = ask_text(prompt)
    if not out:
        return None
    try:
        return json.loads(out[out.find("{"): out.rfind("}") + 1])
    except Exception:
        return None
