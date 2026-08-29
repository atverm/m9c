#!/bin/sh
# tutor: the tutorial SERVICE, gated.  Builds tutorm9 (the M9 web
# service), points it at a fresh hermetic workdir, and replays every
# tutorial cell through POST /run, requiring the SAME bytes tutdiff
# recorded -- one source of truth from the markdown to the wire.
# Then the three walls, each by name: the language (--no-unsafe),
# the clock (timeout), and memory (a checked OutOfMemory).
set -e
cd "$(dirname "$0")"

# the skips come BEFORE gen.sh: a machine that cannot run the gate
# should say so without first regenerating the toolchain
command -v bwrap >/dev/null 2>&1 || \
  { echo "SKIP: tutor (no bubblewrap on this machine)"; exit 0; }
ldconfig -p 2>/dev/null | grep -q 'libblosc\.so\.1' || \
  { echo "SKIP: tutor (no libblosc; cells link it)"; exit 0; }
ldconfig -p 2>/dev/null | grep -q 'libnetcdf\.so' || \
  { echo "SKIP: tutor (no libnetcdf; cells link it)"; exit 0; }

. ./gen.sh

gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c ../gen/Lex.c \
    ../gen/Ast.c ../gen/Parse.c ../gen/Print.c ../gen/Text.c \
    ../gen/Fmt.c ../gen/Sem.c ../gen/Gen.c ../gen/Doc.c ../gen/M9c.c -o m9c

REPO=$(cd ../.. && pwd)
RT=$(cd .. && pwd)
M9C=$(pwd)/m9c
W=/tmp/m9tutor-gate
B=/tmp/m9tutor-build
EXA="$REPO/docs/tutorial/examples"
PORT=18941
rm -rf "$W" "$B"; mkdir -p "$B"

sh "$REPO/tools/tutor/setup.sh" "$REPO" "$W" "$M9C" >/dev/null

( cd "$B" && \
  M9RUNTIME="$RT" M9LIBRARY="$REPO/corpus" \
    "$M9C" --make -c "$REPO/tools/tutor/Tutor.m9" >/dev/null && \
  M9RUNTIME="$RT" M9LIBRARY="$REPO/corpus" \
    "$M9C" --make -c "$REPO/tools/tutor/TutorMain.m9" \
    -I "$REPO/tools/tutor" >/dev/null && \
  gcc -O2 -flto TutorMain.o Tutor.o Io.o DynStr.o \
      "$RT/m9rt.c" "$RT/tcpshim.c" -iquote "$RT" -lm -o tutorm9 )

"$B/tutorm9" $PORT 64 "$W/site" "$W" \
    "$REPO/docs/tutorial/examples/data" > "$B/tutor.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
sleep 1

n=0
ck () { n=$((n + 1)); }

curl -s "http://127.0.0.1:$PORT/" | grep -q 'Scientific programming' \
  || { echo "FAIL: index page"; exit 1; }
ck
# HEAD is a GET whose body stays home -- link checkers judge the
# public URL by it, and it once answered 404
[ "$(curl -s -o /dev/null -w '%{http_code}' -I "http://127.0.0.1:$PORT/")" = 200 ] \
  || { echo "FAIL: HEAD of the index is not 200"; exit 1; }
ck
# the chapters' embedded figures are served and equal the goldens
curl -s "http://127.0.0.1:$PORT/examples/expect/damped.svg" -o "$B/fig.svg"
cmp -s "$B/fig.svg" "$EXA/expect/damped.svg" \
  || { echo "FAIL: the served figure differs from the golden"; exit 1; }
ck

# every page carries the site header and the chapters chain both ways
curl -s "http://127.0.0.1:$PORT/ch/5" > "$B/ch5.html"
grep -q 'class="site"' "$B/ch5.html" \
  || { echo "FAIL: chapter page lost the site header"; exit 1; }
grep -q 'Previous: memory, pools and strings' "$B/ch5.html" \
  || { echo "FAIL: chapter page lost its Previous link"; exit 1; }
grep -q 'Next: simple math and statistics' "$B/ch5.html" \
  || { echo "FAIL: chapter page lost its Next link"; exit 1; }
ck
curl -s "http://127.0.0.1:$PORT/ch/1" | grep -q 'MODULE C1Hello' \
  || { echo "FAIL: chapter 1 lost its cell"; exit 1; }
ck

# the PAGE'S OWN copy of a cell must compile through /run: the Run
# and Reset buttons both use the textarea's parsed value, and this
# decodes it exactly as the browser does.  Guards the class of bug
# where a second, differently-escaped copy of the source reaches the
# compiler -- a <script type="text/plain"> pristine copy did (script
# content is NOT entity-decoded, textarea content is), and Reset
# handed m9c 29 parse errors' worth of &#x27;.
curl -s "http://127.0.0.1:$PORT/ch/1" | python3 -c '
import sys, html, re
m = re.search (r"<textarea[^>]*>(.*?)</textarea>",
               sys.stdin.read (), re.S)
sys.stdout.write (html.unescape (m.group (1)))' > "$B/pagecell.m9"
curl -s -X POST --data-binary @"$B/pagecell.m9" \
     "http://127.0.0.1:$PORT/run" | grep -q '^exit 0' \
  || { echo "FAIL: the page's own cell text does not compile"; exit 1; }
ck

# and the page's SCRIPT must at least parse: one SyntaxError kills
# every button on the page with no visible failure anywhere -- Run
# simply does nothing.  Shipped exactly once: a cooked Python string
# turned the JS's '\n' literal into a real newline inside a quoted
# string.  node --check is the cheapest wall against the whole class.
if command -v node >/dev/null 2>&1; then
  curl -s "http://127.0.0.1:$PORT/ch/1" | python3 -c '
import sys, re
js = re.search (r"<script>(.*?)</script>", sys.stdin.read (), re.S)
sys.stdout.write (js.group (1))' > "$B/page.js"
  node --check "$B/page.js" \
    || { echo "FAIL: the page script does not parse; every button is dead"; exit 1; }
  ck
else
  echo "note: node absent -- the page-script syntax check did not run"
fi

for f in "$EXA"/C*.m9; do
  m=$(basename "$f" .m9)
  curl -s -X POST --data-binary @"$f" \
       "http://127.0.0.1:$PORT/run" > "$B/$m.got"
  if [ "$m" = C9Plot ]; then
    # the one cell that WRITES: its reply also names the file the
    # sandbox kept, served at /out/
    printf 'exit 0\n' > "$B/$m.want"
    cat "$EXA/expect/$m.out" >> "$B/$m.want"
    printf 'files: /out/damped.svg\n' >> "$B/$m.want"
  elif [ "$m" = C10Icos ]; then
    printf 'exit 0\n' > "$B/$m.want"
    cat "$EXA/expect/$m.out" >> "$B/$m.want"
    printf 'files: /out/htm.svg\n' >> "$B/$m.want"
  else
    printf 'exit 0\n' > "$B/$m.want"
    cat "$EXA/expect/$m.out" >> "$B/$m.want"
  fi
  cmp -s "$B/$m.got" "$B/$m.want" \
    || { echo "FAIL: /run of $m differs:"; diff "$B/$m.want" "$B/$m.got" | head -6; exit 1; }
  ck
done

# the produced file itself: byte-identical to the gated golden, a
# missing name answers 404 WITHOUT unwinding the server, and a
# traversal is a name that does not exist
# /out holds the LAST run's files; the cells run alphabetically
# (C10 sorts first), so the survivor is C9Plot's figure
curl -s "http://127.0.0.1:$PORT/out/damped.svg" -o "$B/served.svg"
cmp -s "$B/served.svg" "$EXA/expect/damped.svg" \
  || { echo "FAIL: /out/damped.svg differs from the golden"; exit 1; }
ck
[ "$(curl -s -o /dev/null -w '%{http_code}' \
     "http://127.0.0.1:$PORT/out/nothing.svg")" = 404 ] \
  || { echo "FAIL: a missing /out file should answer 404"; exit 1; }
ck
[ "$(curl -s --path-as-is -o /dev/null -w '%{http_code}' \
     "http://127.0.0.1:$PORT/out/../manifest.txt")" = 404 ] \
  || { echo "FAIL: traversal out of /out was not refused"; exit 1; }
ck
curl -s "http://127.0.0.1:$PORT/" | grep -q 'Scientific programming' \
  || { echo "FAIL: the server died on the /out probes"; exit 1; }
ck

# setup.sh must be re-runnable over a workdir that has ALREADY
# served cells: its manifest comes from the known library list, and
# a regenerated one must not adopt a dead cell's object.  The first
# version recorded `ls *.o` -- over a used workdir that kept
# C8Zarr.o, and one run later chapter 4 linked two main()s.  Found
# live; this re-setup-then-run is that sequence.
sh "$REPO/tools/tutor/setup.sh" "$REPO" "$W" "$M9C" >/dev/null
curl -s -X POST --data-binary @"$EXA/C1Hello.m9" \
     "http://127.0.0.1:$PORT/run" | grep -q '^exit 0' \
  || { echo "FAIL: a re-run setup poisoned the manifest"; exit 1; }
ck

curl -s -X POST --data-binary @"$EXA/Temps.m9" "http://127.0.0.1:$PORT/run" \
  | grep -q 'compiled clean' \
  || { echo "FAIL: a library pair should compile clean"; exit 1; }
ck
curl -s -X POST --data-binary @"$EXA/X2Assign.m9" "http://127.0.0.1:$PORT/run" \
  | grep -q 'cannot assign F64 to I64' \
  || { echo "FAIL: the page should show the checker's refusal"; exit 1; }
ck

# the three walls, each reported by name
cat > "$B/spin.m9" <<'M9'
MODULE Spin ;
IMPORT Io ;
VAR x : I64 ;
BEGIN
  x := 0 ;
  WHILE x >= 0 DO x := (x + 1) MOD 1000000 END ;
  Io.WriteI64 (x)
END Spin.
M9
curl -s -X POST --data-binary @"$B/spin.m9" "http://127.0.0.1:$PORT/run" \
  | grep -q '^exit 124' \
  || { echo "FAIL: the CPU wall did not fire"; exit 1; }
ck
cat > "$B/bomb.m9" <<'M9'
MODULE Bomb ;
IMPORT Io ;
VAR
  pool : POOL ;
  s : SLICE OF F64 ;
BEGIN
  s := NEW (pool, F64, 100000000000) ;
  Io.WriteI64 (LEN (s))
END Bomb.
M9
curl -s -X POST --data-binary @"$B/bomb.m9" "http://127.0.0.1:$PORT/run" \
  | grep -q 'OutOfMemory' \
  || { echo "FAIL: the memory wall did not fire"; exit 1; }
ck
# NO EGRESS, proven positively: from inside the sandbox the HOST'S
# loopback does not exist -- this probe dials the very server that
# is running it (the gate's own port, 18941) and must fail.  The
# store chapter works because ITS server runs inside the namespace;
# nothing outside is reachable.
cat > "$B/netprobe.m9" <<'M9'
MODULE NetProbe ;
IMPORT Io ;
IMPORT Http ;
VAR
  buf : ARRAY 256 OF BYTE ;
  n, status : I64 ;
BEGIN
  status := Http.Get ('127.0.0.1', 18941, '/', buf, n) ;
  Io.WriteLine ('reached the host?!') ;
  Io.WriteI64 (status)
EXCEPT
| Http.TransportError (msg) :
    Io.WriteLine ('isolated: the host loopback is not here')
| ValueRange :
    Io.WriteLine ('octet boundary')
END NetProbe.
M9
curl -s -X POST --data-binary @"$B/netprobe.m9" \
     "http://127.0.0.1:$PORT/run" > "$B/netprobe.got"
grep -q 'isolated: the host loopback is not here' "$B/netprobe.got" \
  || { echo "FAIL: the sandbox reached the host's loopback"; \
       head -3 "$B/netprobe.got"; exit 1; }
ck

cat > "$B/sneaky.m9" <<'M9'
MODULE Sneaky ;
IMPORT Io ;
FROM cevil IMPORT Pid ;
BEGIN
  Io.WriteI64 (I64 (Pid ()))
END Sneaky.

UNSAFE DEFINITION MODULE FOR "C" cevil ;
PROCEDURE Pid = "getpid" () : C.Int [REENTRANT] ;
END cevil.
M9
curl -s -X POST --data-binary @"$B/sneaky.m9" "http://127.0.0.1:$PORT/run" \
  | grep -q -- '--no-unsafe: foreign unit cevil' \
  || { echo "FAIL: the language wall did not fire"; exit 1; }
ck

echo "tutor: PASS ($n checks) -- every cell replayed to its recorded"
echo "       bytes through the M9 service, three walls fired by name"
