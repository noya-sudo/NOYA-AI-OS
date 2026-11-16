"""Daily HTML dashboard -> DASHBOARD/index.html (opens in any browser, no server needed)."""
import html
import json
from datetime import datetime

from . import db
from .ai import spent_today
from .analytics import creator_rewards_status, latest_account
from .config import ROOT, STOP_FILE, load_settings
from .tts import engine


def build():
    s = load_settings()
    with db.tx() as c:
        q = lambda sql, *a: [dict(r) for r in c.execute(sql, a)]
        posts = q("""SELECT p.id, p.scheduled_for, p.status, p.provider, p.url, p.last_error, cd.title, cd.category, cd.hook, cd.total_score, r.duration
                     FROM posts p JOIN renders r ON r.id=p.render_id JOIN candidates cd ON cd.id=r.candidate_id ORDER BY p.scheduled_for""")
        hooks = q("""SELECT cd.hook, cd.category, MAX(m.views) views, MAX(m.shares) shares FROM metrics m JOIN posts p ON p.id=m.post_id
                     JOIN renders r ON r.id=p.render_id JOIN candidates cd ON cd.id=r.candidate_id GROUP BY cd.id ORDER BY views DESC LIMIT 8""")
        eng = q("SELECT SUM(views) v, SUM(likes) l, SUM(comments) c, SUM(shares) sh, COUNT(*) n FROM metrics")[0]
        ledger = q("SELECT kind, SUM(amount_gbp) t, verified FROM ledger GROUP BY kind, verified")
        errors = q("SELECT ts, level, area, message FROM events WHERE level IN ('warn','error') ORDER BY id DESC LIMIT 15")
        last = q("SELECT v FROM kv WHERE k='last_cycle'")
        sources = q("SELECT status, COUNT(*) n FROM sources GROUP BY status")
        cands = q("SELECT status, COUNT(*) n FROM candidates GROUP BY status")
        ready = q("SELECT COUNT(*) n FROM renders WHERE status='ready'")[0]["n"]
        acct = q("SELECT captured_at, followers, source FROM account_metrics WHERE followers IS NOT NULL ORDER BY id")
    a = latest_account()
    e = lambda x: html.escape(str(x if x is not None else "—"))
    missing = lambda x: "missing" if x is None else f"{int(x):,}"
    rows = "".join(f"<tr><td>#{p['id']}</td><td>{e(p['scheduled_for'][:16].replace('T',' '))}</td><td>{e(p['title'])}</td><td>{p['category']}</td>"
                   f"<td>{p['duration']:.0f}s</td><td>{p['total_score']}</td><td><span class='st {p['status']}'>{e(p['status'])}</span></td>"
                   f"<td>{('<a href=' + e(p['url']) + '>link</a>') if p['url'] else ''}</td></tr>" for p in posts)
    cr = "".join(f"<tr><td>{e(n)}</td><td>{e(v)}</td><td>{'✅' if ok else ('❌' if ok is False else '…')}</td></tr>" for n, v, ok in creator_rewards_status())
    errs = "".join(f"<li><code>{e(x['ts'][5:16])}</code> <b>{e(x['area'])}</b> {e(x['message'])}</li>" for x in errors) or "<li>None</li>"
    hk = "".join(f"<li>{e(h['hook'])} ({h['category']}) — {missing(h['views'])} views</li>" for h in hooks) or "<li>No post metrics imported yet (missing, not zero).</li>"
    rev = "".join(f"<li>{e(l['kind'])}: £{l['t']:.2f} {'(verified payout)' if l['verified'] else '(unverified)'}</li>" for l in ledger) or "<li>No revenue recorded. Creator Rewards not active.</li>"
    growth = (f"{int(a['followers']):,}" if a["followers"] else "missing")
    status = "STOPPED (STOP file present)" if STOP_FILE.exists() else "RUNNING/READY"
    page = f"""<!doctype html><html lang=en><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>YOURVIRAL7 Control</title><style>
:root{{--bg:#0b0b12;--card:#151522;--fg:#ececf3;--mut:#9a9ab0;--acc:#ff5ca8;--ok:#3ddc97;--bad:#ff6b6b}}
@media (prefers-color-scheme: light){{:root:not([data-theme=dark]){{--bg:#f6f6fa;--card:#fff;--fg:#15151f;--mut:#5a5a70}}}}
body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 system-ui,Inter,sans-serif}}main{{max-width:1100px;margin:auto;padding:16px}}
h1{{font-size:22px;margin:8px 0}}h1 small{{color:var(--mut);font-weight:500}}.g{{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}}
.c{{background:var(--card);border-radius:12px;padding:14px;margin:12px 0;overflow-x:auto}}.k{{font-size:26px;font-weight:800}}.m{{color:var(--mut);font-size:13px}}
table{{border-collapse:collapse;width:100%;font-size:14px}}td,th{{padding:6px 8px;border-bottom:1px solid #8883;text-align:left;white-space:nowrap}}
.st{{padding:2px 8px;border-radius:99px;background:#8883;font-size:12px}}.posted_confirmed{{background:#3ddc9744}}.failed,.uncertain_needs_check{{background:#ff6b6b55}}
a{{color:var(--acc)}}</style><main>
<h1>YOURVIRAL7 <small>{s['account']} · mode {s['mode']}{' (authorised)' if s['launch_authorized'] else ''} · {status}</small></h1>
<div class=g>
<div class=c><div class=m>Followers</div><div class=k>{growth}</div><div class=m>{e(a['followers_source'])} · goal 10,000</div></div>
<div class=c><div class=m>Views (30d)</div><div class=k>{missing(a['views_30d'])}</div><div class=m>{e(a['views_source'] or 'import TikTok Studio export')}</div></div>
<div class=c><div class=m>Queue</div><div class=k>{sum(1 for p in posts if p['status'] in ('queued','awaiting_approval','exported_awaiting_manual_post','scheduled_with_provider'))}</div><div class=m>{ready} more rendered & ready</div></div>
<div class=c><div class=m>Confirmed live</div><div class=k>{sum(1 for p in posts if p['status']=='posted_confirmed')}</div><div class=m>publisher: {s['publisher']} · cap {s['daily_post_cap']}/day</div></div>
<div class=c><div class=m>AI spend today</div><div class=k>£{spent_today():.2f}</div><div class=m>cap £{s['budget_gbp_per_day']:.2f} · TTS: {engine()}</div></div>
<div class=c><div class=m>Last automation run</div><div class=k style="font-size:16px">{e(json.loads(last[0]['v']) if last else 'never')}</div></div>
</div>
<div class=c><h3>Publishing queue</h3><table><tr><th>ID</th><th>Slot (UK)</th><th>Title</th><th>Cat</th><th>Len</th><th>Score</th><th>Status</th><th></th></tr>{rows or '<tr><td colspan=8>Empty</td></tr>'}</table></div>
<div class=g><div class=c><h3>Engagement (imported)</h3><p>Views {missing(eng['v'])} · Likes {missing(eng['l'])} · Comments {missing(eng['c'])} · Shares {missing(eng['sh'])}</p><h3>Best hooks</h3><ul>{hk}</ul></div>
<div class=c><h3>Revenue (GBP)</h3><ul>{rev}</ul><h3>Library</h3><p class=m>Sources: {e(sources)}<br>Candidates: {e(cands)}</p></div></div>
<div class=c><h3>Creator Rewards milestones</h3><table>{cr}</table></div>
<div class=c><h3>Errors & rights warnings</h3><ul>{errs}</ul></div>
<p class=m>Generated {datetime.now():%Y-%m-%d %H:%M}. Missing analytics are shown as missing, never as zero.</p></main></html>"""
    out = ROOT / "DASHBOARD" / "index.html"
    out.write_text(page)
    return out
