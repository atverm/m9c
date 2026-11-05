#!/bin/sh
# yieldprobe.sh prices a yield check at every loop of a program
# (docs/task-plan.md, stage 0).  No generator emits one yet.  So this
# script takes the C m9c generates, marks every C loop (every M9 loop
# is a C `for`), and builds six variants:
#
#   y0  no check: the same pipeline
#   y1  a relaxed load of one global int, a call when it is nonzero
#   y2  the same from a _Thread_local int (a per-carrier flag)
#   y3  y1's check in every loop but a leaf (the plan's option 2)
#   y4  a counted check, the flag read every 1,024 turns (option 3)
#   y5  the counted check, leaves skipped (options 2 and 3)
#   y6  y3, and a loop calling only leaf procedures skipped too
#   y7  the outermost loop of a procedure, and any loop that calls a
#       procedure that is not a leaf
#   y8  the outermost loop of a nest, and any loop that calls a
#       procedure that is not a leaf
#   y9  a procedure's outermost loop, unless it is a leaf loop
#
# bench/YieldMark.m9 marks the loops and bench/yk.h says what the marks
# are in each variant (2026-11-02; the first sittings put a sed-made
# M9_YCHK at every loop, and had y0 to y2 only).
#
#   sh bench/yieldprobe.sh REPO OUTDIR NAME PROG.m9
#
# NAME's program is PROG.m9; its closure is what --make builds.  The flag stays 0 unless M9_YFLAG is set, so the slow
# call never runs; the constructor reads the environment so that LTO
# cannot fold the flag to 0.
set -eu
REPO=$1;
M9C=${M9C:-$REPO/out/m9c}; export M9RUNTIME=$REPO/runtime; OUT=$2; NAME=$3; PROG=$4; shift 4
D=$OUT/yp-$NAME
rm -rf "$D"; mkdir -p "$D"
cd "$D"
src () {
  for d in "$REPO/bench" "$REPO/corpus"; do
    if [ -f "$d/$1.m9" ]; then echo "$d/$1.m9"; return; fi
  done
  echo "yieldprobe: no source for $1" >&2; exit 1
}
M9LIBRARY=$REPO/corpus "$M9C" --make -k -I "$REPO/bench" -o "$NAME-base" "$PROG" > /dev/null
# --make keeps the program's C only.  Its objects name the closure, and
# each module's C is emitted beside them.
for o in *.o; do
  m=${o%.o}
  [ -f "$m.c" ] || M9LIBRARY=$REPO/corpus "$M9C" --out-dir . -I "$REPO/bench" "$(src "$m")" > /dev/null
done
rm -f ./*.o
# YieldMark marks each loop as a leaf or not; yk.h makes the marks
# into each variant's check.
M9RUNTIME=$REPO/runtime M9LIBRARY=$REPO/corpus "$M9C" --run "$REPO/bench/YieldMark.m9" --leaves=leaves.txt ./*.c
for c in *.c; do
  M9RUNTIME=$REPO/runtime M9LIBRARY=$REPO/corpus "$M9C" --run "$REPO/bench/YieldMark.m9" --with=leaves.txt "$c" "$c.y" > /dev/null
  mv "$c.y" "$c"
done
echo "loops marked: $(cat ./*.c | grep -c 'M9_YCHK(')"
cp "$REPO/bench/yk.h" .
cat > ykslow.c <<'EOF'
#include <stdlib.h>
int m9_yflag;
_Thread_local int m9_yflag_t;
__attribute__ ((noinline)) void m9_yslow (void) { m9_yflag = 0; m9_yflag_t = 0; }
__attribute__ ((constructor)) static void m9_yinit (void)
{
  int on = getenv ("M9_YFLAG") != NULL;
  m9_yflag = on;
  m9_yflag_t = on;
}
EOF
RT=$REPO/runtime
case $(uname -s) in
  Darwin) EXTRA="-Wno-parentheses-equality -Wno-self-assign -I/opt/homebrew/opt/openssl@3/include"
          LINK="-L/opt/homebrew/opt/openssl@3/lib -Wl,-dead_strip_dylibs -Wl,-dead_strip" ;;
  *) EXTRA=""; LINK="-Wl,--as-needed" ;;
esac
for v in 0 1 2 3 4 5 6 7 8 9; do
  # shellcheck disable=SC2086
  ${CC:-gcc} -O2 -ffp-contract=off -flto=auto --param max-inline-insns-auto=200 $EXTRA \
    -DM9_YIELD=$v -iquote "$RT" -iquote . ./*.c "$RT/m9rt.c" "$RT/tcpshim.c" "$RT/tlsshim.c" \
    "$RT/fmtshim.c" $LINK -lssl -lcrypto -lm -o "$NAME-y$v"
done
ls -l "$NAME"-y?
