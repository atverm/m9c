#!/bin/sh
# m9edit -- the beginner's editor, gated the tutor's way: a real
# server, real requests, and the page's own script through node.
# The rules under test are the plan's: /lex is the compiler's own
# lexer (kinds and spans, string quotes included), /check is m9c
# --check verbatim as JSON, /run compiles with the supplied flags
# (which now carry fmtshim, so a program that PLOTS links with no
# flags at all -- the gap this editor found), and /out is SafeName-
# gated.  The EXIT trap carries the real status across the cleanup.
set -e
cd "$(dirname "$0")"
. ./gen.sh          # runtime/gen is BUILT here, not found

SRC=$(cd ../../corpus && pwd)
RT=$(cd .. && pwd)
ED=$(cd ../../tools/edit && pwd)
W=/tmp/m9edit-gate
PORT=8039
# a stale server from an aborted run holds the port; match the
# cmdline in /proc, never pgrep -f (which matches the shell asking)
for p in /proc/[0-9]*/cmdline; do
  if { tr '\0' ' ' < "$p" | grep -q "^[^ ]*/m9edit $PORT "; } 2>/dev/null; then
    kill "$(basename "$(dirname "$p")")" 2>/dev/null || true
  fi
done
# and WAIT for the port to actually free: a back-to-back run raced
# the dying server and the first curl got an empty reply (exit 52)
for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -s -o /dev/null --max-time 1 http://127.0.0.1:$PORT/ || break
  sleep 0.3
done
rm -rf "$W"; mkdir -p "$W/work"

gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c \
    ../gen/Text.c ../gen/Lex.c ../gen/Ast.c ../gen/Print.c \
    ../gen/Parse.c ../gen/Sem.c ../gen/Doc.c ../gen/Gen.c \
    ../gen/Io.c ../gen/Time.c ../gen/M9c.c -lm -o "$W/m9c"
( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$SRC" \
    ./m9c --make -o m9edit "$ED/EditMain.m9" "$ED/Edit.m9" >build.log 2>&1 ) || \
  { echo "edit: FAIL building m9edit:"; tail -5 "$W/build.log"; exit 1; }
( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$SRC" \
    ./m9c --make -o m9fmt "$SRC/M9fmt.m9" >fmt.log 2>&1 ) || \
  { echo "edit: FAIL building m9fmt:"; tail -5 "$W/fmt.log"; exit 1; }
cp "$ED/page.html" "$ED/keywords.json" "$W/"
cp -r "$ED/examples" "$W/"

# the page's own script must BE a script: the tutor once shipped a
# dead page whose every button was one SyntaxError
if command -v node >/dev/null 2>&1; then
  sed -n '/<script>/,/<\/script>/p' "$ED/page.html" | sed '1d;$d' > "$W/page.js"
  node --check "$W/page.js" || { echo "edit: the page script does not parse"; exit 1; }
  echo "         the page script parses"
else
  echo "         (no node; page-script check skipped)"
fi

( cd "$W" && exec env M9EDIT_M9C="$W/m9c" M9EDIT_M9FMT="$W/m9fmt" M9RUNTIME="$RT" M9LIBRARY="$SRC" \
    ./m9edit $PORT 1000000 . work > "$W/serve.log" 2>&1 ) &
SRV=$!
st=1
finish () {
  s=$?
  kill "$SRV" 2>/dev/null || true
  exit $s
}
trap finish EXIT
sleep 1

[ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/)" = 200 ] || \
  { echo "edit: the page does not serve"; exit 1; }

# /lex: the compiler's kinds for a known line, string span property
J=$(printf "MODULE T ;\nVAR s : STR ;\nBEGIN\n  s := 'ab'\nEND T.\n" | \
    curl -s -X POST --data-binary @- http://127.0.0.1:$PORT/lex)
echo "$J" | grep -q '"tokens":\[\[34,1,1,6\]' || \
  { echo "edit: /lex does not open with MODULE(34):"; echo "$J" | head -c 120; exit 1; }
echo "$J" | grep -q '\[6,4,8,2\]' || \
  { echo "edit: the string token span moved"; exit 1; }
J=$(printf "MODULE T ;\n(* a note *)\nEND T.\n" | \
    curl -s -X POST --data-binary @- http://127.0.0.1:$PORT/lex)
echo "$J" | grep -q '"comments":\[{"line":2,"col":1,"text":"(\* a note \*)"}\]' || \
  { echo "edit: comments do not come back verbatim:"; echo "$J"; exit 1; }
echo "         /lex answers the compiler's own tokens and comments"

# /check: m9c's message with its position, as JSON
J=$(printf "MODULE B ;\nVAR i : I64 ;\nBEGIN\n  i := 'x'\nEND B.\n" | \
    curl -s -X POST --data-binary @- http://127.0.0.1:$PORT/check)
echo "$J" | grep -q '"ok":false' || { echo "edit: /check passed a broken file"; exit 1; }
echo "$J" | grep -q '"line":4,.*cannot assign' || \
  { echo "edit: /check lost the message or position:"; echo "$J"; exit 1; }
J=$(printf "MODULE G ;\nBEGIN\nEND G.\n" | \
    curl -s -X POST --data-binary @- http://127.0.0.1:$PORT/check)
echo "$J" | grep -q '"ok":true' || { echo "edit: /check failed a clean file"; exit 1; }
echo "         /check republishes m9c verbatim, both verdicts"

# /run: bytes back, and a FIGURE -- through the flagless link
R=$(printf "MODULE H ;\nIMPORT Io ;\nBEGIN\n  Io.WriteLine ('hi from the gate')\nEND H.\n" | \
    curl -s -X POST --data-binary @- http://127.0.0.1:$PORT/run)
echo "$R" | grep -q '^exit 0' || { echo "edit: hello did not run:"; echo "$R" | head -3; exit 1; }
echo "$R" | grep -q 'hi from the gate' || { echo "edit: output lost"; exit 1; }
R=$(printf "MODULE F ;\nIMPORT Plot ;\nIMPORT Io ;\nVAR\n  pool : POOL ;\n  xs, ys : ARRAY 2 OF F64 ;\n  svg : STR ;\nBEGIN\n  xs[0] := 0.0 ; xs[1] := 1.0 ;\n  ys[0] := 0.0 ; ys[1] := 1.0 ;\n  Plot.ClearFigure () ;\n  Plot.AddLine (xs, ys, 0, 'y') ;\n  svg := Plot.Render (pool, 't', 'x', 'y') ;\n  Io.WriteFile ('f.svg', svg)\nEXCEPT\n| ValueRange :\n    Io.Halt (1)\n| Io.IOError (p) :\n    Io.Halt (1)\nEND F.\n" | \
    curl -s -X POST --data-binary @- http://127.0.0.1:$PORT/run)
echo "$R" | grep -q 'file: /out/f.svg' || \
  { echo "edit: the figure was not produced:"; echo "$R" | head -4; exit 1; }
curl -s http://127.0.0.1:$PORT/out/f.svg | head -c 4 | grep -q '<svg' || \
  { echo "edit: /out does not serve the svg"; exit 1; }
# a URL query must not reach the file name: /out/f.svg?v=2 still serves
curl -s "http://127.0.0.1:$PORT/out/f.svg?v=2" | head -c 4 | grep -q '<svg' || \
  { echo "edit: a query on a figure URL 404s (query not stripped)"; exit 1; }
echo "         a program that PLOTS compiles flaglessly and serves its figure"

# -g on /run: an unhandled exception's message carries FILE:LINE
R=$(printf "MODULE Ov ;\nIMPORT Io ;\nVAR b, w : I64 ;\nBEGIN\n  b := MAX (I64) ;\n  w := b + 1 ;\n  Io.WriteI64 (w)\nEND Ov.\n" | \
    curl -s -X POST --data-binary @- http://127.0.0.1:$PORT/run)
echo "$R" | grep -q "Ov.m9:6:.*unhandled Overflow" || \
  { echo "edit: an unhandled Overflow lost its location:"; echo "$R" | head -4; exit 1; }
echo "         an unhandled exception's message carries FILE:LINE (-g)"

# the tutor's /tmp convention, when bubblewrap is present: chapter
# 9's own habit -- writing /tmp/NAME -- must land in the served out/
if command -v bwrap >/dev/null 2>&1; then
  R=$(printf "MODULE T ;\nIMPORT Io ;\nBEGIN\n  Io.WriteFile ('/tmp/conv.txt', 'via the bind')\nEXCEPT\n| ValueRange :\n    Io.Halt (1)\n| Io.IOError (p) :\n    Io.Halt (1)\nEND T.\n" | \
      curl -s -X POST --data-binary @- http://127.0.0.1:$PORT/run)
  echo "$R" | grep -q 'file: /out/conv.txt' || \
    { echo "edit: /tmp did not land in out/ under bwrap:"; echo "$R" | head -3; exit 1; }
  curl -s http://127.0.0.1:$PORT/out/conv.txt | grep -q 'via the bind' || \
    { echo "edit: the bound file's bytes are wrong"; exit 1; }
  echo "         /tmp/NAME lands in out/ -- the tutorial convention holds"
else
  echo "         (no bwrap; the /tmp convention probe is skipped OUT LOUD)"
fi

# hover's food: /doc/MODULE is the m9c --json gather, cached
J=$(curl -s http://127.0.0.1:$PORT/doc/Io)
echo "$J" | grep -q '"module": *"Io"' || \
  { echo "edit: /doc/Io is not the gather:"; echo "$J" | head -c 120; exit 1; }
echo "$J" | grep -q '"name": *"WriteLine"' || \
  { echo "edit: /doc/Io lacks WriteLine"; exit 1; }
[ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/doc/NoSuchModule99)" = 404 ] || \
  { echo "edit: /doc of a missing module did not 404"; exit 1; }
[ "$(curl -s --path-as-is -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/doc/..")" = 404 ] || \
  { echo "edit: /doc traversal escaped"; exit 1; }
echo "         /doc answers the m9c --json gather, gated both ways"

# the keyword table: served, and gated against the lexer's own list
if command -v python3 >/dev/null 2>&1; then
  python3 ../../tools/mkkeywords.py --check || \
    { echo "edit: the keyword table is adrift"; exit 1; }
fi
J=$(curl -s http://127.0.0.1:$PORT/kw)
echo "$J" | grep -q '"KEPT":' || { echo "edit: /kw lacks KEPT"; exit 1; }
echo "$J" | grep -q '"GRID":' || { echo "edit: /kw lacks GRID"; exit 1; }
echo "         /kw serves all sixty-one keywords, none adrift"

# examples: listed, and one served
J=$(curl -s http://127.0.0.1:$PORT/examples)
echo "$J" | grep -q '"01-hello.m9"' || { echo "edit: /examples lacks 01-hello:"; echo "$J"; exit 1; }
curl -s http://127.0.0.1:$PORT/example/01-hello.m9 | grep -q '^MODULE Hello' || \
  { echo "edit: /example/01-hello.m9 did not serve the source"; exit 1; }
[ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/example/nope.m9)" = 404 ] || \
  { echo "edit: a missing example did not 404"; exit 1; }
[ "$(curl -s --path-as-is -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/example/../Edit.m9")" = 404 ] || \
  { echo "edit: example traversal escaped"; exit 1; }
echo "         /examples lists and /example serves, gated"

# format: a messy but parseable buffer comes back canonical
F=$(printf "MODULE M ;\nIMPORT Io ;\nVAR x:I64;\nBEGIN\nx:=1;Io.WriteI64(x)\nEND M.\n" | \
    curl -s -X POST --data-binary @- http://127.0.0.1:$PORT/fmt)
echo "$F" | grep -q "  x := 1 ;" || { echo "edit: /fmt did not canonicalise:"; echo "$F"; exit 1; }
for ex in "$ED"/examples/*.m9; do
  G=$(curl -s -X POST --data-binary @"$ex" http://127.0.0.1:$PORT/fmt)
  [ "$G" = "$(cat "$ex")" ] || { echo "edit: $(basename "$ex") is not m9fmt-canonical"; exit 1; }
done
echo "         /fmt canonicalises, and the examples are already canonical"

[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/out/../prog")" = 404 ] || \
  { echo "edit: traversal escaped /out"; exit 1; }
[ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/nowhere)" = 404 ] || \
  { echo "edit: unknown path did not 404"; exit 1; }

echo "edit: the editor serves, lexes, checks, runs and draws"
