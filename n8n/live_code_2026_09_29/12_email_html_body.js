// Plain-text body -> simple HTML (no images, no banners). Signature website, Instagram and email become links.
function toHtml(b) {
  var esc = function (s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); };
  var lnk = function (s) {
    return s.replace(/([A-Za-z0-9._%+-]+)@noyaconcierge\.com/g, '<a href="mailto:$1@noyaconcierge.com" style="color:#222222">$1@noyaconcierge.com</a>')
      .replace(/(?<![@\w.\/"])noyaconcierge\.com(?![^<]*<\/a>)/g, '<a href="https://noyaconcierge.com" style="color:#222222">noyaconcierge.com</a>')
      .replace(/(?<![\w.])@noyaconcierge(?![\w.])/g, '<a href="https://www.instagram.com/noyaconcierge/" style="color:#222222">@noyaconcierge</a>');
  };
  var paras = String(b || '').replace(/\r/g, '').replace(/[‐‑‒]/g, '-').replace(/ /g, ' ').trim().split(/\n[ \t]*\n+/);
  return '<div style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif;font-size:14px;line-height:1.5;color:#222222">'
    + paras.map(function (p) {
        var lines = p.trim().split('\n'), out = '';
        lines.forEach(function (l, i) { out += lnk(esc(l.trim())); if (i < lines.length - 1) out += (l.trim().length >= 60 && !/[.:!?]$/.test(l.trim())) ? ' ' : '<br>'; });
        return '<p style="margin:0 0 12px 0">' + out + '</p>';
      }).join('')
    + '</div>';
}
module.exports = toHtml;
if (require.main === module) {
  console.log(toHtml("Hi Tom,\n\nTest body.\n\nBest,\n\nAdam Elshazly\nFounder, NOYA Concierge\nGlobal concierge & lifestyle management\nnoyaconcierge.com · @noyaconcierge\nadam@noyaconcierge.com"));
}
