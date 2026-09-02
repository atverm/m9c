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
  if { tr '\0' ' ' < "$p" | grep -q "m9edit $PORT "; } 2>/dev/null; then
    kill "$(basename "$(dirname "$p")")" 2>/dev/null || true
  fi
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
cp "$ED/page.html" "$W/"

# the page's own script must BE a script: the tutor once shipped a
# dead page whose every button was one SyntaxError
if command -v node >/dev/null 2>&1; then
  sed -n '/<script>/,/<\/script>/p' "$ED/page.html" | sed '1d;$d' > "$W/page.js"
  node --check "$W/page.js" || { echo "edit: the page script does not parse"; exit 1; }
  echo "         the page script parses"
else
  echo "         (no node; page-script check skipped)"
fi

( cd "$W" && exec env M9EDIT_M9C="$W/m9c" M9RUNTIME="$RT" M9LIBRARY="$SRC" \
    ./m9edit $PORT 40 . work > "$W/serve.log" 2>&1 ) &
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
echo "         a program that PLOTS compiles flaglessly and serves its figure"

[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/out/../prog")" = 404 ] || \
  { echo "edit: traversal escaped /out"; exit 1; }
[ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/nowhere)" = 404 ] || \
  { echo "edit: unknown path did not 404"; exit 1; }

echo "edit: the editor serves, lexes, checks, runs and draws"
