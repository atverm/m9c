#!/bin/sh
# yieldprobe-m9c.sh builds m9c itself in yieldprobe.sh's three variants
# (y0 no check, y1 a global flag, y2 a _Thread_local flag), from the
# checked-in C of runtime/gen, with build.sh's flags (-O2, no LTO).
#
#   sh bench/yieldprobe-m9c.sh REPO OUTDIR
set -eu
REPO=$1; OUT=$2
D=$OUT/yp-m9c
rm -rf "$D"; mkdir -p "$D"
cd "$D"
COMPILER="DynStr Io Lex Ast Parse Print Text System Sem Gen Doc DynUtf Review M9c"
for m in $COMPILER; do
  sed 's/\(for ([^{]*{\)/\1 M9_YCHK;/' "$REPO/runtime/gen/$m.c" > "$m.c.y"
  { echo '#include "yk.h"'; cat "$m.c.y"; } > "$m.c"
  rm "$m.c.y"
  cp "$REPO/runtime/gen/$m.h" .
done
echo "loops instrumented: $(cat ./*.c | grep -c 'M9_YCHK;')"
cp "$OUT/yp-fannkuch/yk.h" "$OUT/yp-fannkuch/ykslow.c" .
WARN="-std=c11"
case $(uname -s) in Darwin) WARN="$WARN -Wno-parentheses-equality -Wno-self-assign" ;; esac
for v in 0 1 2; do
  SRC=""
  for m in $COMPILER; do SRC="$SRC $m.c"; done
  # shellcheck disable=SC2086
  ${CC:-gcc} -O2 $WARN -DM9_YIELD=$v -iquote "$REPO/runtime" -iquote . \
    "$REPO/runtime/m9rt.c" ykslow.c $SRC -lm -o "m9c-y$v"
done
ls -l m9c-y?
