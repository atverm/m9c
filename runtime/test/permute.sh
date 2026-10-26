#!/bin/sh
# permute: THE CHECKER'S VERDICT DOES NOT DEPEND ON DECLARATION ORDER
# (2026-10-26, the third review's summaries advice).  The memoised call
# summaries read an entry still being computed as "no", so a cycle's
# answer depended on which procedure was asked first: Cyc3, three
# procedures calling each other, was accepted in 288 of its 720
# declaration orders and refused in the rest, and the regions gate's E1
# and E1n were refused only in the order they happened to be written.
# Every program in regions/ (each refused) and genforms/ (each built and
# run) is written in ORDERS orders by tools/Permute.m9 -- every
# procedure body moved, a forward heading for each first -- and every
# order must be refused, or accepted, as the program's own order is.
#
# Shown able to fail: the compiler of c3fddee6 (before the memo's
# iteration at a cycle's head) accepts 8 of R3Cyc3's 24 orders.
cd "$(dirname "$0")" || exit 1
. ./lib/gen.sh
. ./lib/freshm9c.sh
ROOT=$(cd ../.. && pwd)
ORDERS=${M9_PERMUTE_ORDERS:-12}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export M9RUNTIME="$ROOT/runtime" M9LIBRARY="$ROOT/corpus" M9CACHE="$W/cache"
"$M9C" --run "$ROOT/tools/Permute.m9" regions/R3Cyc3.m9 "$W/warm" 1 1 > /dev/null ||
  { echo "permute: FAIL running tools/Permute.m9"; exit 1; }

# one program: its orders, and a line naming any whose verdict differs
one () {
  f=$1 ; name=$(basename "$f" .m9) ; d="$W/p/$(basename "$(dirname "$f")")-$name"
  "$M9C" --run "$ROOT/tools/Permute.m9" "$f" "$d" "$ORDERS" 7 > /dev/null 2>&1 ||
    { echo "NOPERM $f"; return; }
  first=
  for o in "$d"/o*; do
    if ( cd "$o" && "$M9C" --check -I "$ROOT/runtime/test/$(basename "$(dirname "$f")")" "$name.m9" > /dev/null 2>&1 ); then v=accepted; else v=refused; fi
    if [ -z "$first" ]; then first=$v
    elif [ "$v" != "$first" ]; then echo "DIFFERS $f: order 0 $first, $(basename "$o") $v"; return; fi
  done
}
n=0
for f in regions/*.m9 genforms/*.m9; do
  one "$f" >> "$W/out" &
  n=$((n + 1))
  # a few at a time: each order is a --check
  if [ $((n % ${M9_JOBS:-4})) = 0 ]; then wait; fi
done
wait
if grep -q . "$W/out" 2>/dev/null; then
  sed 's/^/permute: /' "$W/out"
  echo "permute: FAIL -- $(grep -c . "$W/out") of $n programs change verdict with their declaration order"
  exit 1
fi
echo "permute: $n programs, $ORDERS declaration orders each, every verdict the same"
