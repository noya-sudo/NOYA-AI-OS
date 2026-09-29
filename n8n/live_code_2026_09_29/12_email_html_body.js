function toHtml(b) {
  var esc = function (s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); };
  var paras = String(b || '').replace(/\r/g, '').replace(/[‐‑‒]/g, '-').replace(/ /g, ' ').trim().split(/\n[ \t]*\n+/);
  return '<div style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif;font-size:14px;line-height:1.5;color:#222222">'
    + paras.map(function (p) {
        var lines = p.trim().split('\n'), out = '';
        lines.forEach(function (l, i) { out += esc(l.trim()); if (i < lines.length - 1) out += (l.trim().length >= 60 && !/[.:!?]$/.test(l.trim())) ? ' ' : '<br>'; });
        return '<p style="margin:0 0 12px 0">' + out + '</p>';
      }).join('')
    + '</div>';
}
module.exports = toHtml;
if (require.main === module) {
  console.log(toHtml("Hi Rosie,\n\nWith Quintessentially growing across the Gulf, I wanted to reach out\nregarding member requests in Egypt.\n\n\n\nNOYA can support your team & partners <here>.\n\nBest,\nAdam Elshazly\nFounder, NOYA Concierge\nnoyaconcierge.com"));
}
