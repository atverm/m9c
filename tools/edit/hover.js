/* M9Hover -- docstring hovers over an M9 cell.

   The page invents no documentation: keyword paragraphs come from
   GET /kw (tools/mkkeywords.py's output, gated in both directions
   against the lexer's own table) and module entries from
   GET /doc/NAME (the m9c --json gather, cached server-side).  Only
   qualified names (Module.Proc) resolve to an entry; a bare
   capitalised name answers the module's own docstring -- the hover
   for IMPORT lines.

   Served by m9edit at /hover.js and inlined into the tutorial's
   pages, the cell.js rule: one file, both pages, no drift.

   M9Hover.attach({
     cell: <M9Cell>,      the cell to read (textarea + tokens())
     kw:   '/kw',         GET endpoints
     doc:  '/doc/'
   })
   The tip element and the keyword/module caches are one per page,
   shared by every attached cell.  Style the tip as .m9tip (and its
   signature lines as .m9tip .sig). */
'use strict';
var M9Hover = (function () {

var kwDocs = {}, docCache = {}, kwWanted = false;
var tip = null;

function ensureTip() {
  if (!tip) {
    tip = document.createElement('div');
    tip.className = 'm9tip';
    document.body.appendChild(tip);
  }
  return tip;
}
function esc(s) {
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function attach(opts) {
  var cell = opts.cell;
  var srcEl = cell.textarea;
  var kwUrl = opts.kw || '/kw';
  var docUrl = opts.doc || '/doc/';

  if (!kwWanted) {           /* one fetch feeds every cell's hovers */
    kwWanted = true;
    fetch(kwUrl).then(function(r){return r.json();})
                .then(function(j){ kwDocs = j; }).catch(function(){});
  }

  function textOf(t) {
    var line = srcEl.value.split('\n')[t[1] - 1] || '';
    return line.substr(t[2] - 1, t[3]);
  }
  function tokenAt(line, col) {
    var lastTok = cell.tokens();
    for (var i = 0; i < lastTok.length; i++) {
      var t = lastTok[i];
      var len = t[3] + (t[0] === 6 ? 2 : 0);
      if (t[1] === line && col >= t[2] && col < t[2] + len)
        return {i: i, t: t};
    }
    return null;
  }
  function qualAt(line, col) {
    var hit = tokenAt(line, col);
    if (!hit || hit.t[0] !== 2) return null;
    var toks = cell.tokens(), i = hit.i;
    /* Ident . Ident -- hovering either half answers the pair */
    if (i + 2 < toks.length && toks[i+1][0] === 221 && toks[i+2][0] === 2)
      return {mod: textOf(toks[i]), name: textOf(toks[i+2])};
    if (i >= 2 && toks[i-1][0] === 221 && toks[i-2][0] === 2)
      return {mod: textOf(toks[i-2]), name: textOf(toks[i])};
    return null;
  }
  /* the character grid, measured from the textarea's own computed
     style -- the backdrop shares it by the cells' CSS contract.
     The paddings are measured too: m9edit pads 8px and the
     tutorial .6rem, and a hardcoded 8 was one column wrong there. */
  var mtr = null;
  function metrics() {
    var cs = getComputedStyle(srcEl);
    var probe = document.createElement('span');
    probe.textContent = 'M';
    probe.style.font = cs.font;
    probe.style.position = 'absolute'; probe.style.visibility = 'hidden';
    document.body.appendChild(probe);
    var r = probe.getBoundingClientRect();
    document.body.removeChild(probe);
    return {w: r.width, h: parseFloat(cs.lineHeight),
            padL: parseFloat(cs.paddingLeft), padT: parseFloat(cs.paddingTop)};
  }
  function showTip(ev, html) {
    var el = ensureTip();
    el.innerHTML = html;
    el.style.left = Math.min(ev.clientX + 12,
                             window.innerWidth - el.offsetWidth - 16) + 'px';
    el.style.top = (ev.clientY + 14) + 'px';
    el.style.display = 'block';
  }
  function hideTip() {
    if (tip) tip.style.display = 'none';
  }
  function renderDoc(q, entry) {
    /* the signature already carries the name; prefix only the module */
    var sig = entry.signature || (q.name);
    var h = '<div class="sig">' + esc(q.mod + '.' + sig) + '</div>';
    var extra = '';
    if (entry.result) extra += ' : ' + entry.result;
    if (entry.raises && entry.raises.length)
      extra += '  RAISES ' + entry.raises.join(', ');
    if (extra) h += '<div class="sig">' + esc(extra.trim()) + '</div>';
    h += entry.doc ? esc(entry.doc) : '<i>(no docstring)</i>';
    return h;
  }

  var hoverTimer = null;
  srcEl.addEventListener('mousemove', function(ev) {
    clearTimeout(hoverTimer);
    hideTip();
    hoverTimer = setTimeout(function() {
      if (!mtr) mtr = metrics();
      var rect = srcEl.getBoundingClientRect();
      var col = Math.floor((ev.clientX - rect.left + srcEl.scrollLeft
                            - mtr.padL) / mtr.w) + 1;
      var line = Math.floor((ev.clientY - rect.top + srcEl.scrollTop
                             - mtr.padT) / mtr.h) + 1;
      var hit = tokenAt(line, col);
      if (hit && hit.t[0] >= 7 && hit.t[0] < 200) {
        var w = textOf(hit.t);
        if (kwDocs[w])
          showTip(ev, '<div class="sig">' + esc(w) + '</div>' + esc(kwDocs[w]));
        return;
      }
      var q = qualAt(line, col);
      if (!q) {
        /* a bare capitalised name: try it as a MODULE -- the hover
           for IMPORT lines.  The gather's top-level doc is the
           module's own docstring; the first paragraph is the short
           form. */
        if (hit && hit.t[0] === 2) {
          var mn = textOf(hit.t);
          if (!/^[A-Z]/.test(mn)) return;
          function showMod(doc) {
            if (!doc.doc) return;
            var para = doc.doc.split('\n\n')[0];
            showTip(ev, '<div class="sig">' + esc(mn) + ' (module)</div>' +
                        esc(para));
          }
          if (docCache[mn] === 'missing') return;
          if (docCache[mn]) { showMod(docCache[mn]); return; }
          fetch(docUrl + mn).then(function(r) {
            if (!r.ok) { docCache[mn] = 'missing'; return null; }
            return r.json();
          }).then(function(j) {
            if (!j) return;
            docCache[mn] = j;
            showMod(j);
          }).catch(function(){});
        }
        return;
      }
      function show(doc) {
        var entry = null;
        for (var e of (doc.declarations || []))
          if (e.name === q.name) entry = e;
        if (!entry) return;
        showTip(ev, renderDoc(q, entry));
      }
      if (docCache[q.mod] === 'missing') return;
      if (docCache[q.mod]) { show(docCache[q.mod]); return; }
      fetch(docUrl + q.mod).then(function(r) {
        if (!r.ok) { docCache[q.mod] = 'missing'; return null; }
        return r.json();
      }).then(function(j) {
        if (!j) return;
        docCache[q.mod] = j;
        show(j);
      }).catch(function(){});
    }, 350);
  });
  srcEl.addEventListener('mouseleave', function() {
    clearTimeout(hoverTimer); hideTip();
  });
}

return {attach: attach};
})();
