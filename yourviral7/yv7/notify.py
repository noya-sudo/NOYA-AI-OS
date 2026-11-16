"""Alerts: always to LOGS/alerts.md + dashboard; desktop notification; optional email via Resend."""
import os
import platform
import shutil
import subprocess
from datetime import datetime

from .config import ROOT, load_secrets


def alert(title: str, body: str, critical=False):
    line = f"- {datetime.now():%Y-%m-%d %H:%M} {'**CRITICAL** ' if critical else ''}{title} — {body}\n"
    with open(ROOT / "LOGS" / "alerts.md", "a") as f:
        f.write(line)
    _desktop(title, body)
    load_secrets()
    key, to = os.environ.get("RESEND_API_KEY"), os.environ.get("YV7_ALERT_EMAIL")
    if key and to and (critical or os.environ.get("YV7_EMAIL_ALL") == "1"):
        try:
            import requests
            requests.post("https://api.resend.com/emails", timeout=20, headers={"Authorization": f"Bearer {key}"},
                          json={"from": os.environ.get("YV7_ALERT_FROM", "YOURVIRAL7 <onboarding@resend.dev>"),
                                "to": [to], "subject": f"[YOURVIRAL7] {title}", "text": body})
        except Exception:
            pass


def _desktop(title, body):
    try:
        sysname = platform.system()
        if sysname == "Darwin":
            subprocess.run(["osascript", "-e", f'display notification "{body[:200]}" with title "YOURVIRAL7: {title[:60]}"'], timeout=10)
        elif sysname == "Linux" and shutil.which("notify-send") and os.environ.get("DISPLAY"):
            subprocess.run(["notify-send", f"YOURVIRAL7: {title}", body[:300]], timeout=10)
        elif sysname == "Windows":
            subprocess.run(["powershell", "-NoProfile", "-Command",
                            f"[reflection.assembly]::loadwithpartialname('System.Windows.Forms')|Out-Null;"
                            f"$n=New-Object System.Windows.Forms.NotifyIcon;$n.Icon=[System.Drawing.SystemIcons]::Information;"
                            f"$n.Visible=$true;$n.ShowBalloonTip(8000,'YOURVIRAL7: {title[:60]}','{body[:200]}',0)"], timeout=15)
    except Exception:
        pass
