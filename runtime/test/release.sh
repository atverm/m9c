#!/bin/sh
# The statement release, end to end (docs/statement-release-plan.md,
# stage 3): the incident's loop -- rows x ids, `Text.Eq (ids[j], '<' +
# id + '>')` in a condition -- run at N and at 4N, and the arena it
# leaves live must not grow with N.  The same loop with the string
# assigned to a local first is a SINK and must grow, which is how the
# gate shows it can fail: a generator that released nothing would pass
# the first half's equality by making both halves equal.
#
# Two numbers per run, printed by the program itself: pool-kb, the
# arena capacity live at the end of the loop (System.PoolBytes, read
# inside the frame that holds it), and peak-kb, the process's high
# water.  The release half may differ between N and 4N by one block
# (64 KB) and no more.
set -e
cd "$(dirname "$0")"
REPO=$(cd ../.. && pwd)
. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C
OUT=/tmp/m9release
rm -rf "$OUT"; mkdir -p "$OUT"
cp releaseloop.m9 "$OUT/"
export M9RUNTIME="$REPO/runtime"
export M9LIBRARY="$REPO/corpus"
( cd "$OUT" && "$M9C" --make -o releaseloop releaseloop.m9 )
run () {  # run ROWS MODE -> pool-kb peak-kb hits
  "$OUT/releaseloop" "$1" "$2" > "$OUT/$2-$1.out" 2>&1 || {
    echo "release: the program failed at $1 $2"; cat "$OUT/$2-$1.out"; exit 1; }
  echo "$(sed -n 's/^pool-kb //p' "$OUT/$2-$1.out") $(sed -n 's/^peak-kb //p' "$OUT/$2-$1.out") $(sed -n 's/^hits //p' "$OUT/$2-$1.out")"
}
N=${N:-2000}
set -- $(run $N release);           rp1=$1; rk1=$2; h1=$3
set -- $(run $((4*N)) release);     rp4=$1; rk4=$2; h4=$3
set -- $(run $N sink);              sp1=$1; sk1=$2
set -- $(run $((4*N)) sink);        sp4=$1; sk4=$2
echo "release: N=$N  released: pool $rp1 -> $rp4 KB, peak $rk1 -> $rk4 KB, hits $h1 -> $h4"
echo "release:         sink:     pool $sp1 -> $sp4 KB, peak $sk1 -> $sk4 KB"
[ "$h4" -eq $((4*h1)) ] || { echo "release: the loop's answer did not scale (hits $h1, $h4)"; exit 1; }
[ $((rp4 - rp1)) -le 64 ] && [ $((rp1 - rp4)) -le 64 ] || {
  echo "release: the released loop's arena grew with N ($rp1 -> $rp4 KB)"; exit 1; }
[ "$sp4" -ge $((sp1 * 2)) ] || {
  echo "release: the sink loop's arena did not grow ($sp1 -> $sp4 KB): the gate cannot see a release"; exit 1; }
[ "$rp4" -lt "$sp1" ] || {
  echo "release: released ($rp4 KB) is not below the sink's smallest ($sp1 KB)"; exit 1; }
# and what the release must NOT take: the buffer a callee grew in the
# caller's arena through a VAR pointer (releasegrow.m9's comment)
cp releasegrow.m9 "$OUT/"
( cd "$OUT" && "$M9C" --make -o releasegrow releasegrow.m9 )
"$OUT/releasegrow" > "$OUT/grow.out" 2>&1 || { echo "release: releasegrow failed"; cat "$OUT/grow.out"; exit 1; }
for tag in module local callee; do
  grep -qx "$tag length 225 nul 0" "$OUT/grow.out" || {
    echo "release: a buffer grown through a VAR pointer was freed under it:"; cat "$OUT/grow.out"; exit 1; }
done
grep -qx "varstr same" "$OUT/grow.out" || {
  echo "release: a string a callee gave a VAR STR was freed under it:"; cat "$OUT/grow.out"; exit 1; }
echo "release: PASS -- a statement's concatenation dies with the statement; the sink's accumulate; a buffer grown for the caller does not"
