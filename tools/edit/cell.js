/* M9Cell -- one editable M9 cell: a textarea over a coloured
   backdrop, a line gutter, and the two round trips to the server.

   The page never lexes M9.  Colour comes from POST /lex -- the
   compiler's own lexer over this buffer -- and diagnostics from
   POST /check, which is m9c --check verbatim (Diag.Json's shape:
   {"ok":BOOL,"diags":[{"line","col","msg"}...]}).  Kind codes are
   Lex's stable contract: 1 error, 2 ident, 3 int, 4 real, 5 char,
   6 str, 7..199 keywords, 200+ operators.

   Served by m9edit at /cell.js and by the tutor at the same path,
   so the two pages cannot drift.  Nothing here knows about Run,
   Reset, examples, formatting or hovers: those are the page's.

   M9Cell.attach({
     textarea: <textarea>,        the buffer
     backdrop: <pre>,             scrolls with the textarea
     code:     <code>,            receives the coloured HTML
                                  (defaults to backdrop)
     gutter:   <pre> | null,      line numbers
     diags:    <div> | null,      one clickable line per finding
     status:   <span> | null,     'checking...' / 'checker: clean'
     lex:      '/lex',            POST endpoints
     check:    '/check'
   }) answers a cell:
     cell.tokens()      the last /lex answer's tokens (for hovers)
     cell.setBuffer(t)  replace the whole buffer, geometry, colour
                        and checker kept in step
     cell.check()       run the checker now
     cell.relex()       recolour after 200 ms of quiet
     cell.syncScroll()  */
'use strict';
var M9Cell = (function () {

function esc(s) {
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}
function classOf(k) {
  if (k === 1) return 'err';
  if (k === 5 || k === 6) return 'str';
  if (k === 3 || k === 4) return 'num';
  if (k >= 7 && k < 200) return 'kw';
  return '';
}
function numbers(n) {
  return Array.from({length: n}, function(_, i){return i + 1;}).join('\n');
}

function attach(opts) {
  var srcEl = opts.textarea;
  var hl = opts.backdrop;
  var hlc = opts.code || opts.backdrop;
  var gut = opts.gutter || null;
  var diags = opts.diags || null;
  var status_ = opts.status || null;
  var lexUrl = opts.lex || '/lex';
  var checkUrl = opts.check || '/check';

  function setStatus(t) { if (status_) status_.textContent = t; }
  function setGutter(n) { if (gut) gut.textContent = numbers(n); }

  /* spans per line: from tokens [kind,line,col,len] and comments
     {line,col,text}; comment text includes its delimiters and its
     own newlines, so continuation columns come from the text itself */
  var lastTok = [], lastCom = [], firstDiag = null;
  function render(tokens, comments) {
    lastTok = tokens; lastCom = comments;
    var lines = srcEl.value.split('\n');
    var spans = [];            /* [line, colFrom, colTo, cls] 1-based */
    for (var t of tokens) {
      var cls = classOf(t[0]);
      /* a string token's text is its CONTENT; the source span carries
         the two quotes as well (measured against /lex, not assumed) */
      var len = t[3] + (t[0] === 6 ? 2 : 0);
      if (cls) spans.push([t[1], t[2], t[2] + len, cls]);
    }
    for (var c of comments) {
      var parts = c.text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        var col = (i === 0) ? c.col : 1;
        spans.push([c.line + i, col, col + parts[i].length, 'com']);
      }
    }
    var byLine = new Map();
    for (var s of spans) {
      if (!byLine.has(s[0])) byLine.set(s[0], []);
      byLine.get(s[0]).push(s);
    }
    var html = [];
    for (var ln = 1; ln <= lines.length; ln++) {
      var text = lines[ln - 1];
      var row = (byLine.get(ln) || []).sort(function(a,b){return a[1]-b[1];});
      var h;
      if (firstDiag && firstDiag.line === ln) {
        /* the first finding's line: per-character classes, so the red
           cell can sit INSIDE whatever token colour is under it */
        var cls2 = new Array(text.length + 1).fill('');
        for (var sp of row)
          for (var c2 = Math.max(sp[1], 1);
               c2 < Math.min(sp[2], text.length + 1); c2++)
            cls2[c2] = sp[3];
        var dc = Math.min(Math.max(firstDiag.col, 1), text.length + 1);
        cls2[dc] = (cls2[dc] ? cls2[dc] + ' ' : '') + 'dcell';
        if (dc > text.length) text += ' ';   /* a cell to mark at EOL */
        h = '';
        var runCls = null, run = '';
        for (var i2 = 1; i2 <= text.length + 1; i2++) {
          var k2 = (i2 <= text.length) ? (cls2[i2] || '') : null;
          if (k2 !== runCls) {
            if (run)
              h += runCls ? '<span class="' + runCls + '">' + esc(run) + '</span>'
                          : esc(run);
            runCls = k2; run = '';
          }
          if (i2 <= text.length) run += text[i2 - 1];
        }
        h = '<span class="dline">' + (h.length ? h : ' ') + '</span>';
      } else {
        var pos = 1; h = '';
        for (var sp2 of row) {
          var from = Math.max(sp2[1], pos), to = Math.min(sp2[2], text.length + 1);
          if (from > pos) h += esc(text.slice(pos - 1, from - 1));
          if (to > from)
            h += '<span class="' + sp2[3] + '">' +
                 esc(text.slice(from - 1, to - 1)) + '</span>';
          pos = Math.max(pos, to);
        }
        if (pos <= text.length) h += esc(text.slice(pos - 1));
        if (!h.length) h = ' ';
      }
      html.push(h);
    }
    hlc.innerHTML = html.join('\n');
    setGutter(lines.length);
  }
  function syncScroll() {
    hl.scrollTop = srcEl.scrollTop; hl.scrollLeft = srcEl.scrollLeft;
    if (gut) gut.scrollTop = srcEl.scrollTop;
  }
  var lexTimer = null;
  function relex() {
    clearTimeout(lexTimer);
    lexTimer = setTimeout(function() {
      fetch(lexUrl, {method:'POST', body: srcEl.value})
        .then(function(r){return r.json();})
        .then(function(j){ render(j.tokens, j.comments); syncScroll(); })
        .catch(function(){});
    }, 200);
  }

  function showDiags(list) {
    firstDiag = list.length ? {line: list[0].line, col: list[0].col} : null;
    render(lastTok, lastCom);
    syncScroll();
    if (!diags) return;
    diags.innerHTML = '';
    for (var d of list) {
      var el = document.createElement('div');
      el.textContent = d.line + ':' + d.col + '  ' + d.msg;
      el.onclick = (function(line, col) { return function() {
        var upto = srcEl.value.split('\n').slice(0, line - 1)
                   .reduce(function(a, l){return a + l.length + 1;}, 0);
        srcEl.focus();
        srcEl.setSelectionRange(upto + col - 1, upto + col - 1);
      };})(d.line, d.col);
      diags.appendChild(el);
    }
  }
  var checkTimer = null, checking = false;
  function doCheck() {
    if (checking) return;
    checking = true;
    setStatus('checking...');
    fetch(checkUrl, {method:'POST', body: srcEl.value})
      .then(function(r){return r.json();})
      .then(function(j){
        showDiags(j.diags);
        setStatus(j.ok ? 'checker: clean' :
                  'checker: ' + j.diags.length + ' finding(s)');
      })
      /* a network failure OR a non-JSON answer (the tutor's nginx
         rate limiter answers 429 with an HTML page) lands here: the
         last colouring and findings stay, and the status must not
         claim clean */
      .catch(function(){ setStatus('checker unavailable'); })
      .finally(function(){ checking = false; });
  }

  srcEl.addEventListener('input', function() {
    /* the backdrop must match the buffer's HEIGHT at once, or a paste
       leaves the caret drawn against yesterday's line count until the
       next scroll -- colours can wait for the lexer, geometry cannot */
    hlc.textContent = srcEl.value;
    setGutter(srcEl.value.split('\n').length);
    syncScroll();
    relex();
    /* the checker runs one second after the typing stops */
    clearTimeout(checkTimer);
    checkTimer = setTimeout(doCheck, 1000);
  });
  srcEl.addEventListener('scroll', syncScroll);
  srcEl.addEventListener('keydown', function(e) {
    if (e.key === 'Tab') {          /* two spaces, the corpus style */
      e.preventDefault();
      var s = srcEl.selectionStart;
      srcEl.setRangeText('  ', s, srcEl.selectionEnd, 'end');
      relex();
    }
  });

  /* one place to replace the whole buffer -- an example load, a
     format, a Reset -- keeping geometry, colour and the checker in
     step */
  function setBuffer(text) {
    srcEl.value = text;
    hlc.textContent = text;
    setGutter(text.split('\n').length);
    /* a replaced buffer invalidates the findings: clear them now
       rather than leave the old text's mark on the new text; the
       check below repopulates honestly */
    firstDiag = null;
    if (diags) diags.innerHTML = '';
    setStatus('');
    syncScroll();
    relex();
    clearTimeout(checkTimer);
    checkTimer = setTimeout(doCheck, 400);
  }

  /* first paint: the buffer as it stands, coloured when /lex answers */
  hlc.textContent = srcEl.value;
  setGutter(srcEl.value.split('\n').length);
  relex();

  return {
    textarea: srcEl,
    tokens: function() { return lastTok; },
    setBuffer: setBuffer,
    check: doCheck,
    relex: relex,
    syncScroll: syncScroll
  };
}

return {attach: attach};
})();
