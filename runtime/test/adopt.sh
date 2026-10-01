#!/bin/sh
# Rule 1 of docs/pool-elision-plan.md, end to end: m9c compiles a
# program whose every allocation is `NEW (T)` or `NEW (T, n...)` with
# no pool, and the values survive the frames that made them -- a
# tree built by recursion, a slice, a VAR parameter's target, a
# record with a pointer, a slice and a string in it, an array of
# slices, a variant's payload, a grid -- each read after its maker
# returned.  The expected numbers are computed in the program from
# the shapes, not remembered.
#
# The last check is the one that makes this a test of ADOPTION
# rather than of a leak: 20,000 rounds of frames, and the peak
# resident size must stay under a bound that a leak of even one
# block per round (64 KB) would break within the first thousand.
set -e
cd "$(dirname "$0")"

REPO=$(cd ../.. && pwd)
M9C=${M9C:-$REPO/runtime/test/m9c}
[ -x "$M9C" ] || M9C=$REPO/out/m9c
[ -x "$M9C" ] || { echo "no m9c: run runtime/test/m9c.sh or ./build.sh"; exit 1; }

OUT=/tmp/m9adopt
rm -rf "$OUT"; mkdir -p "$OUT"
cp adopttest.m9 "$OUT/"
export M9RUNTIME="$REPO/runtime"
export M9LIBRARY="$REPO/corpus"

( cd "$OUT" && "$M9C" --make -o adopttest adopttest.m9 -I. )

"$OUT/adopttest" > "$OUT/adopt.out" 2>&1 || {
  echo "adopt: the program failed"; cat "$OUT/adopt.out"; exit 1; }
cat "$OUT/adopt.out"

bad=$(grep -c '^FAIL' "$OUT/adopt.out" || true)
oks=$(grep -c '^ok' "$OUT/adopt.out" || true)
peak=$(sed -n 's/^peak-kb //p' "$OUT/adopt.out")
[ "$oks" -eq 17 ] || { echo "adopt: expected 17 checks, saw $oks"; exit 1; }
[ "$bad" -eq 0 ] || { echo "adopt: $bad checks failed"; exit 1; }
# 64 MB: a leak of one 64 KB block per round would reach it by round
# 1000 of 20000; the honest number is printed above for the record
[ -n "$peak" ] && [ "$peak" -lt 65536 ] || {
  echo "adopt: peak RSS $peak KB is not bounded"; exit 1; }
echo "adopt: PASS (17 checks, peak $peak KB)"
