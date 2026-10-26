#!/bin/sh
# The review pages, against what is checked in.
#
# runtime/test/review/NAME.txt is what `m9c --review' prints for a
# module of the library: what the checker proved, and what a person
# decided -- every named pool, pool parameter, KEPT parameter, use of
# HEAP, owned allocation, THREAD and module variable, every UNSAFE
# unit and foreign procedure, with the lines they stand on.  It is a
# GOLDEN, as docs/modules is: a module that gains a KEPT parameter or
# a named pool without its page being re-recorded shows up here as a
# diff, which is the point -- those are the lines a reviewer was
# promised they would be shown, and a change to them is a change
# somebody should have read.
#
# THE TOTALS ARE PRINTED AND NEVER GATED.  A ceiling on named pools
# would make hiding one a rational move; the number is reported, the
# way docdiff reports coverage, and the gate is the per-module page.
#
# It builds its own m9c rather than accepting one it finds (docdiff
# says why).
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found
. ./lib/reviewnorm.sh   # the page without its line numbers

M9CNEW=$(mktemp -d)
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c $COMPILERC -o "$M9CNEW/m9c"
# replaced only when it differs: a gate in another lane running m9c keeps
# its file, and --run's cache, whose key holds m9c's mtime, its entries
if cmp -s "$M9CNEW/m9c" m9c; then rm -r "$M9CNEW"; else mv -f "$M9CNEW/m9c" m9c; rmdir "$M9CNEW"; fi

M9C=$(pwd)/m9c
SRC=$(cd ../../corpus && pwd)
GOLD=$(pwd)/review
OUT=/tmp/m9c-review
rm -rf "$OUT"; mkdir -p "$OUT"
export M9RUNTIME=$(cd .. && pwd)
export M9LIBRARY=$SRC

# HttpServer names Http explicitly, as in docdiff and for its reason
deps_of () {
  case $1 in
    HttpServer) echo Http DynStr ;;
    *)          echo ;;
  esac
}

row () {  # row FILE LABEL: the count on a page's row
  sed -n "s/^  $2  *\([0-9][0-9]*\).*/\1/p" "$1" | head -1
}
over () {  # over FILE LABEL: what the row says was passed over, 0 if nothing
  v=$(sed -n "s/^  $2  *[0-9][0-9]*   passed over, a type unknown: \([0-9][0-9]*\).*/\1/p" "$1" | head -1)
  echo "${v:-0}"
}

# THE COUNTERS, HELD TO A HAND COUNT before any page is trusted.
# reviewcalib.m9 is a program whose sites are counted in its own
# comments -- three assignments examined and one passed over (a
# handler's binder, which the checker does not type), five arguments,
# three RETURNs, three operand sites, two CASE labels, one CASE over
# variants -- and reviewcalib.want is what the PROVED section must
# say for it.  NOT re-recorded by reviewgen: it is the anchor, typed
# from the count, and a counter that drifts shows here first.
"$M9C" --review reviewcalib.m9 2> "$OUT/calib.err" | sed -n '3,11p' > "$OUT/calib.got"
if ! diff reviewcalib.want "$OUT/calib.got" > "$OUT/calib.diff"; then
  echo "reviewdiff: the counters do not reproduce the hand count of reviewcalib.m9"
  echo "            (< counted by hand, > this checker):"
  sed 's/^/    /' "$OUT/calib.diff"; cat "$OUT/calib.err"
  exit 1
fi
echo "reviewdiff: the counters reproduce the hand count of reviewcalib.m9 (8 rows, one site passed over)"

# WHO FREES THE STORAGE, held to a hand count the same way.
# reviewnew.m9 spells NEW every way there is -- one argument, a
# predeclared type, a type of the module, a type of an imported
# module, a grid, STR, UTF; a pool, a pool with an extent, a pool that is
# a field, HEAP; OWN -- and reviewnew.want is the three rows typed
# from its comments.  The page has no scopes and decides pool or
# type by NAME; until 2026-10-02 it called every two-argument NEW a
# pool's (this program read frame 1, pool 10) and nothing held it.
"$M9C" --review reviewnew.m9 2> "$OUT/new.err" |
  sed -n 's/^  \(NEW [A-Za-z (),]*[A-Za-z)]\)   *\([0-9][0-9]*\).*$/\1: \2/p' > "$OUT/new.got"
if ! diff reviewnew.want "$OUT/new.got" > "$OUT/new.diff"; then
  echo "reviewdiff: the NEW rows do not reproduce the hand count of reviewnew.m9"
  echo "            (< counted by hand, > this page):"
  sed 's/^/    /' "$OUT/new.diff"; cat "$OUT/new.err"
  exit 1
fi
echo "reviewdiff: the NEW rows reproduce the hand count of reviewnew.m9 (1 owned, 7 in the frame, 5 in a pool)"

# A THREAD WRITING A STATEFUL MODULE'S STATE is listed under TRUSTED
# (report par 6, decision 49): reviewthread.m9 has two such threads,
# one direct and one through a helper, and one that only reads.  The
# library's pages all say 0, so without this nothing holds the row.
"$M9C" --review reviewthread.m9 > "$OUT/thread.txt" 2> "$OUT/thread.err" ||
  { echo "reviewdiff: m9c --review refused reviewthread.m9:"; cat "$OUT/thread.err"; exit 1; }
got=$(grep '^  THREADs writing STATEFUL state' "$OUT/thread.txt")
case "$got" in
  *" 2   "*"Builds writes Logger."*"Deep writes Logger."*) ;;
  *) echo "reviewdiff: the STATEFUL row of reviewthread.m9 is not Builds and Deep:"
     echo "    $got"; exit 1 ;;
esac
case "$got" in
  *Quiet*) echo "reviewdiff: a thread that only READS Logger is listed: $got"; exit 1 ;;
esac
echo "reviewdiff: the STATEFUL row lists the two writing threads of reviewthread.m9 and not the reader"

# the UTF transition's row: calls of a STR form whose module declares a
# UTF twin (Sem.StaleCall).  reviewstale.m9 makes three and three UTF
# calls that reach the twins already; the library's pages list their own,
# but nothing else holds that a UTF call is NOT listed.
"$M9C" --review reviewstale.m9 > "$OUT/stale.txt" 2> "$OUT/stale.err" ||
  { echo "reviewdiff: m9c --review refused reviewstale.m9:"; cat "$OUT/stale.err"; exit 1; }
got=$(grep '^  calls of a STR form with a UTF twin' "$OUT/stale.txt")
case "$got" in
  *" 3   "*"Text.Eq -> Text.EqUtf"*"Text.Find -> Text.FindUtf"*"Io.WriteLine -> Io.WriteLineUtf"*) ;;
  *) echo "reviewdiff: the stale-call row of reviewstale.m9 is not its three STR calls:"
     echo "    $got"; exit 1 ;;
esac
echo "reviewdiff: the stale-call row lists the three STR calls of reviewstale.m9 and none of its UTF ones"

# the UTF switch's row (docs/utf8-stage4-plan.md, 4b): every STR subscript,
# write through one and LEN, by the DECLARED type (Sem.StrSite).
# reviewstr.m9 has six such sites -- one through a name for STR -- and the
# same uses of a SLICE OF CHAR spelled out and of a UTF, which must not
# be listed, nor a site in a STR form whose UTF twin the module declares
# (Head beside HeadUtf: a body the switch deletes); the library's 62 pages
# carry their own counts (1,270 sites on 2026-10-24 with Text ported,
# stage 4a's meter), but nothing else holds the kinds or the exemptions.
# Compared whole, without line numbers.
"$M9C" --review reviewstr.m9 > "$OUT/str.txt" 2> "$OUT/str.err" ||
  { echo "reviewdiff: m9c --review refused reviewstr.m9:"; cat "$OUT/str.err"; exit 1; }
got=$(review_norm < "$OUT/str.txt" | grep '^  STR subscripts, writes and LEN')
want='  STR subscripts, writes and LEN                  6   index t[0], index s[0], write s[0], len s, len nm, index nm[1]'
if [ "$got" != "$want" ]; then
  echo "reviewdiff: the STR row of reviewstr.m9 is not its six sites (< wanted, > this page):"
  echo "    < $want"; echo "    > $got"; exit 1
fi
echo "reviewdiff: the STR row lists the six STR sites of reviewstr.m9 and none of its SLICE OF CHAR or UTF ones"

n=0; bad=0
funcs=0; mpools=0; lpools=0; ppar=0; kept=0; heap=0; own=0; thr=0; mvars=0; unsafe=0; foreign=0
exam=0; passed=0; ctot=0; cover=0; strs=0
for m in $(sed -n '/^LIBRARY=/,/"$/p' ../../build.sh |
           sed 's/LIBRARY="//; s/"$//; s/\\$//' | tr -s ' \n' ' '); do
  d=""
  for x in $(deps_of "$m"); do d="$d $SRC/$x.m9"; done
  # shellcheck disable=SC2086
  "$M9C" --review "$SRC/$m.m9" $d > "$OUT/$m.txt" 2> "$OUT/$m.err" ||
    { echo "reviewdiff: m9c --review refused $m:"; cat "$OUT/$m.err"; exit 1; }
  [ -s "$OUT/$m.txt" ] || { echo "reviewdiff: $m produced no page"; exit 1; }
  # what is recorded and compared has no line numbers: a site is
  # `Put.hidden', not `217 Put.hidden', so that only a change in WHAT
  # is there is a diff (lib/reviewnorm.sh)
  review_norm < "$OUT/$m.txt" > "$OUT/$m.norm"
  if [ -f "$GOLD/$m.txt" ]; then
    if ! cmp -s "$OUT/$m.norm" "$GOLD/$m.txt"; then
      echo "DIVERGES: $m (< recorded, > this tree) -- read it, then runtime/test/reviewgen.sh"
      diff "$GOLD/$m.txt" "$OUT/$m.norm" | sed 's/^/    /'
      bad=$((bad + 1))
    fi
  else
    echo "reviewdiff: no page recorded for $m -- run runtime/test/reviewgen.sh"
    bad=$((bad + 1))
  fi
  f=$OUT/$m.txt
  funcs=$((funcs + $(row "$f" 'functions answering on every path')))
  mpools=$((mpools + $(row "$f" 'module pools')))
  lpools=$((lpools + $(row "$f" 'local pools')))
  ppar=$((ppar + $(row "$f" 'pool parameters')))
  kept=$((kept + $(row "$f" 'KEPT parameters')))
  heap=$((heap + $(row "$f" 'HEAP named')))
  own=$((own + $(row "$f" 'NEW (OWN, T)')))
  thr=$((thr + $(row "$f" 'THREAD')))
  mvars=$((mvars + $(row "$f" 'module variables')))
  unsafe=$((unsafe + $(row "$f" 'UNSAFE units')))
  foreign=$((foreign + $(row "$f" 'foreign procedures')))
  strs=$((strs + $(row "$f" 'STR subscripts, writes and LEN')))
  # the six kinds of site where two types are held to each other
  for k in 'assignments' 'arguments' 'RETURN values' \
           'operands of a comparison or an operator' 'CASE labels' 'THREAD arguments'; do
    exam=$((exam + $(row "$f" "$k")))
    passed=$((passed + $(over "$f" "$k")))
  done
  ctot=$((ctot + $(row "$f" 'CASE over variants, proved total')))
  cover=$((cover + $(over "$f" 'CASE over variants, proved total')))
  n=$((n + 1))
done
# a recorded page whose module is gone is a page nobody regenerates
for g in "$GOLD"/*.txt; do
  b=$(basename "$g" .txt)
  [ -f "$OUT/$b.txt" ] || { echo "reviewdiff: review/$b.txt is recorded and $b is not in build.sh's LIBRARY"; bad=$((bad + 1)); }
done

[ "$bad" -eq 0 ] || { echo "reviewdiff: $bad of $n pages differ from what is recorded"; exit 1; }
echo "reviewdiff: $n review pages regenerated byte-identically"
echo "reviewdiff: $funcs functions proved to answer on every path;"
echo "            $exam sites where two types were held to each other, $passed more PASSED OVER for an unknown type;"
echo "            $ctot CASEs over variants proved total, $cover passed over;"
echo "            decided by a person: $mpools module pools, $lpools local pools, $ppar pool parameters,"
echo "            $kept KEPT parameters, HEAP named $heap times, $own NEW (OWN, T), $thr THREAD, $mvars module variables;"
echo "            trusted: $unsafe UNSAFE units, $foreign foreign procedures;"
echo "            the UTF switch's edits (STR subscripts, writes and LEN): $strs"
