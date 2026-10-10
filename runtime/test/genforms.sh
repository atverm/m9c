#!/bin/sh
# genforms: what the checker accepts, the build must build.
#
# Each program in genforms/ is a form `m9c --check` accepts and names
# the line it must print in a `(* WANT: ... *)` comment.  A program
# NOT named in genforms.owed must build under `m9c --run` and print
# that line.  A program named there is a form the generator (or the C
# compiler) still refuses after a clean check -- the class cp-kernel
# reads as a compiler fault (decision 38's catalogue, 2026-10-09) --
# and must still be ACCEPTED by the checker and still FAIL to build:
# a form that builds now, or one the checker has started to refuse,
# is a stale line and red.  A line naming no fixture is red too.
#
# Uses the m9c that m9c.sh builds (run after it, as ci.yml does), or
# $M9C, or out/m9c.
set -e
cd "$(dirname "$0")"

M9C=${M9C:-}
[ -n "$M9C" ] || { [ -x ./m9c ] && M9C=$(pwd)/m9c; }
[ -n "$M9C" ] || { [ -x ../../out/m9c ] && M9C=$(cd ../../out && pwd)/m9c; }
[ -n "$M9C" ] || { echo "genforms: no m9c (run m9c.sh or build.sh)"; exit 1; }

export M9RUNTIME=$(cd .. && pwd)
export M9LIBRARY=$(cd ../../corpus && pwd)
OWED=$(pwd)/genforms.owed
W=/tmp/m9c-genforms
rm -rf "$W"; mkdir -p "$W/src"
cp genforms/*.m9 "$W/src/"
export M9CACHE="$W/cache"

owed () { grep -v '^#' "$OWED" | awk 'NF { print $1 }' | grep -qx "$1"; }

fail=0 ; n=0 ; nowed=0
for name in $(grep -v '^#' "$OWED" | awk 'NF { print $1 }'); do
  [ -f "genforms/$name.m9" ] || {
    echo "FAIL: genforms.owed names $name, and there is no genforms/$name.m9"; fail=$((fail + 1)); }
done
for f in "$W"/src/*.m9; do
  name=$(basename "$f" .m9)
  head -1 "$f" | grep -q '^MODULE ' || continue      # a helper module
  n=$((n + 1))
  want=$(sed -n 's/^(\* WANT: \(.*\) \*)$/\1/p' "$f")
  [ -n "$want" ] || { echo "FAIL: $name has no (* WANT: ... *) line"; fail=$((fail + 1)); continue; }
  # --check runs the generator too: the CHECKER accepted when every
  # line it printed is the generator's
  ( cd "$W/src" && "$M9C" --check "$name.m9" ) > "$W/$name.check" 2>&1 || true
  if grep -v ': gen: ' "$W/$name.check" | grep -v '^m9c: [0-9]* generator errors* in ' | grep -q .; then
    echo "FAIL: the checker refuses $name -- a probe's business, not this gate's:"
    sed 's/^/  /' "$W/$name.check" | head -8; fail=$((fail + 1)); continue
  fi
  st=0
  ( cd "$W/src" && "$M9C" --run "$name.m9" < /dev/null ) > "$W/$name.out" 2>&1 || st=$?
  if owed "$name"; then
    nowed=$((nowed + 1))
    if [ $st = 0 ]; then
      echo "FAIL: $name builds now -- remove its line from genforms.owed"
      fail=$((fail + 1))
    fi
  else
    if [ $st != 0 ] || ! grep -qxF "$want" "$W/$name.out"; then
      echo "FAIL: $name (status $st), wanted: $want"
      sed 's/^/  /' "$W/$name.out" | head -8; fail=$((fail + 1))
    fi
  fi
done

[ $n -gt 0 ] || { echo "FAIL: genforms/ holds no program"; exit 1; }
if [ $fail != 0 ]; then echo "genforms: $fail FAILED of $n forms"; exit 1; fi
echo "genforms: $n forms the checker accepts; $((n - nowed)) build, $nowed owed (genforms.owed)"
rm -rf "$W"
