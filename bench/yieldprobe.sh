#!/bin/sh
# yieldprobe.sh prices a yield check at every loop of a program
# (docs/task-plan.md, stage 0).  No generator emits one yet.  So this
# script takes the C m9c generates, puts M9_YCHK at the head of every
# C loop body (every M9 loop is a C `for`), and builds three variants:
#
#   y0  M9_YCHK is empty: the same pipeline, no check
#   y1  a relaxed load of one global int, a call when it is nonzero
#   y2  the same from a _Thread_local int (a per-carrier flag)
#
#   sh bench/yieldprobe.sh REPO OUTDIR NAME PROG.m9 [MODULE ...]
#
# NAME's program PROG.m9 imports the MODULEs (its closure, as --make
# builds it).  The flag stays 0 unless M9_YFLAG is set, so the slow
# call never runs; the constructor reads the environment so that LTO
# cannot fold the flag to 0.
set -eu
REPO=$1; OUT=$2; NAME=$3; PROG=$4; shift 4
D=$OUT/yp-$NAME
rm -rf "$D"; mkdir -p "$D"
cd "$D"
src () {
  for d in "$REPO/bench" "$REPO/corpus"; do
    if [ -f "$d/$1.m9" ]; then echo "$d/$1.m9"; return; fi
  done
  echo "yieldprobe: no source for $1" >&2; exit 1
}
for m in "$@"; do
  M9LIBRARY=$REPO/corpus "$REPO/out/m9c" -c -k -I "$REPO/bench" "$(src "$m")" > /dev/null 2>&1 || true
done
M9LIBRARY=$REPO/corpus "$REPO/out/m9c" --make -k -I "$REPO/bench" -o "$NAME-base" "$PROG" > /dev/null
for c in *.c; do
  sed 's/\(for ([^{]*{\)/\1 M9_YCHK;/' "$c" > "$c.y"
  { echo '#include "yk.h"'; cat "$c.y"; } > "$c"
  rm "$c.y"
done
echo "loops instrumented: $(cat ./*.c | grep -c 'M9_YCHK;')"
cat > yk.h <<'EOF'
#if M9_YIELD == 1
extern int m9_yflag;
void m9_yslow (void);
#define M9_YCHK do { if (__builtin_expect (__atomic_load_n (&m9_yflag, __ATOMIC_RELAXED), 0)) m9_yslow (); } while (0)
#elif M9_YIELD == 2
extern _Thread_local int m9_yflag_t;
void m9_yslow (void);
#define M9_YCHK do { if (__builtin_expect (__atomic_load_n (&m9_yflag_t, __ATOMIC_RELAXED), 0)) m9_yslow (); } while (0)
#else
#define M9_YCHK do { } while (0)
#endif
EOF
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
for v in 0 1 2; do
  # shellcheck disable=SC2086
  ${CC:-gcc} -O2 -ffp-contract=off -flto=auto --param max-inline-insns-auto=200 $EXTRA \
    -DM9_YIELD=$v -iquote "$RT" -iquote . ./*.c "$RT/m9rt.c" "$RT/tcpshim.c" "$RT/tlsshim.c" \
    "$RT/fmtshim.c" $LINK -lssl -lcrypto -lm -o "$NAME-y$v"
done
ls -l "$NAME"-y?
