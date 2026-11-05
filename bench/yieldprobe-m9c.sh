#!/bin/sh
# yieldprobe-m9c.sh builds m9c itself in yieldprobe.sh's six variants
# (y0 to y5, bench/yk.h says which is which), from the checked-in C of
# runtime/gen, with build.sh's flags (-O2, no LTO).
#
#   sh bench/yieldprobe-m9c.sh REPO OUTDIR
set -eu
REPO=$1; OUT=$2
M9C=${M9C:-$REPO/out/m9c}
D=$OUT/yp-m9c
rm -rf "$D"; mkdir -p "$D"
cd "$D"
COMPILER="DynStr Io Lex Ast Parse Print Text System Sem Gen Doc DynUtf Review M9c"
GEN=""
for m in $COMPILER; do GEN="$GEN $REPO/runtime/gen/$m.c"; done
# shellcheck disable=SC2086
M9RUNTIME=$REPO/runtime M9LIBRARY=$REPO/corpus "$M9C" --run "$REPO/bench/YieldMark.m9" --leaves=leaves.txt $GEN
for m in $COMPILER; do
  M9RUNTIME=$REPO/runtime M9LIBRARY=$REPO/corpus "$M9C" --run "$REPO/bench/YieldMark.m9" --with=leaves.txt \
    "$REPO/runtime/gen/$m.c" "$m.c" > /dev/null
  cp "$REPO/runtime/gen/$m.h" .
done
echo "loops marked: $(cat ./*.c | grep -c 'M9_YCHK(')"
cp "$REPO/bench/yk.h" "$OUT/yp-fannkuch/ykslow.c" .
WARN="-std=c11"
case $(uname -s) in Darwin) WARN="$WARN -Wno-parentheses-equality -Wno-self-assign" ;; esac
for v in 0 1 2 3 4 5 6 7 8 9; do
  SRC=""
  for m in $COMPILER; do SRC="$SRC $m.c"; done
  # shellcheck disable=SC2086
  ${CC:-gcc} -O2 $WARN -DM9_YIELD=$v -iquote "$REPO/runtime" -iquote . \
    "$REPO/runtime/m9rt.c" ykslow.c $SRC -lm -o "m9c-y$v"
done
ls -l m9c-y?
