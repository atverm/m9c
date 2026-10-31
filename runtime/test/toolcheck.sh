#!/bin/sh
# toolcheck holds every program under tools/ and examples/ to a clean
# check by this tree's compiler.  No other gate compiles most of them:
# the Windows setup and tutor were built only by winzip's wine half, and
# when wine was retired they missed the UTF-8 switch unseen; an editor
# example kept a pool argument Plot.Render lost long before (found at
# the 0.26.0 cut, 2026-10-31).  A program is a tracked .m9 whose module
# heading is MODULE; each is checked from its own folder, with that
# folder and corpus/ on the path, as a user would build it there.
# toolcheck.skip names the ones refused by design, each with its reason.
cd "$(dirname "$0")" || exit 1
. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C
ROOT=$(cd ../.. && pwd)
SKIP=$(pwd)/toolcheck.skip
fail=0
n=0
# Every skip entry must still exist, so the list cannot outlive what it
# excuses.
for p in $(grep -v '^#' "$SKIP" | awk 'NF { print $1 }'); do
  [ -e "$ROOT/$p" ] || { echo "toolcheck: FAIL -- toolcheck.skip names $p, which is gone"; fail=1; }
done
for f in $(cd "$ROOT" && git ls-files 'tools/*.m9' 'examples/*.m9'); do
  grep -q '^MODULE ' "$ROOT/$f" || continue
  skip=0
  for p in $(grep -v '^#' "$SKIP" | awk 'NF { print $1 }'); do
    case $f in "$p"|"$p"*) skip=1 ;; esac
  done
  [ $skip = 1 ] && continue
  n=$((n + 1))
  d=$(dirname "$ROOT/$f")
  if ! ( cd "$d" && M9LIBRARY="$ROOT/corpus" "$M9C" -I "$d" -I "$ROOT/corpus" --check "$(basename "$f")" ) > /tmp/toolcheck.$$ 2>&1; then
    echo "toolcheck: FAIL -- $f does not check:"
    head -5 /tmp/toolcheck.$$ | sed 's/^/    /'
    fail=1
  fi
done
rm -f /tmp/toolcheck.$$

# Two release programs also run here, because a clean check did not
# hold them.  Both stopped the 0.26.0 cut on zoefii, after CI was green.
W=$(mktemp -d)
export M9RUNTIME="$ROOT/runtime" M9LIBRARY="$ROOT/corpus"
# MkTutor writes the tutorial site the Windows zip carries.  Its scan
# sliced inside an em dash and raised IndexError on chapter 0.  It
# must write one page per chapter.
MK=$ROOT/tools/tutor/MkTutor.m9
if [ -f "$MK" ]; then
  want=$(ls "$ROOT"/docs/tutorial/[0-9]*.md | wc -l | tr -d ' ')
  if "$M9C" --run "$MK" "$ROOT/docs/tutorial" "$W/site" > "$W/mk.txt" 2>&1 \
     && [ "$(ls "$W"/site/ch/*.html 2>/dev/null | wc -l | tr -d ' ')" = "$want" ]; then
    echo "toolcheck: MkTutor writes the site, $want chapters"
  else
    echo "toolcheck: FAIL -- MkTutor did not write $want chapters:"
    head -5 "$W/mk.txt" | sed 's/^/    /'
    fail=1
  fi
fi
# build-package.sh compiles a module chain with m9c -c in an empty
# folder, then a program that imports Logger and Http.  The chain is
# kept by hand, and it lacked Text once Time imported it.  This runs
# the script's own chain and program with this tree's compiler.
PKG=$ROOT/tools/release/build-package.sh
if [ -f "$PKG" ]; then
  mkdir "$W/pkg"
  sed -n "/^cat > Greet.m9 <<'M9'/,/^M9\$/p" "$PKG" | sed '1d;$d' > "$W/pkg/Greet.m9"
  mods=$(grep -o 'm9c -c [A-Za-z0-9]*' "$PKG" | awk '{ print $3 }')
  if ( cd "$W/pkg" && for m in $mods; do "$M9C" -c "$m" || exit 1; done &&
       "$M9C" -o greet Greet.m9 && [ "$(./greet | tail -1)" = "answer=42" ] ) > "$W/pkg.txt" 2>&1; then
    echo "toolcheck: build-package.sh's chain builds its program:" $mods
  else
    echo "toolcheck: FAIL -- build-package.sh's chain does not build its program:"
    grep -m3 -i 'error\|fail' "$W/pkg.txt" | sed 's/^/    /'
    fail=1
  fi
fi
rm -rf "$W"
[ $fail = 0 ] || exit 1
echo "toolcheck: $n programs under tools/ and examples/ check clean"
