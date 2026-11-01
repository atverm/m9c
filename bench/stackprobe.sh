#!/bin/sh
# stackprobe.sh rebuilds ThreadCost and Boids with a THREAD stack
# other than the runtime's 8 MB (M9_THREAD_STACK in runtime/m9rt.c,
# given to pthread_attr_setstacksize in m9_pthread), then runs task0.sh
# over them (docs/task-plan.md, stage 0).  The tree's runtime is not
# changed: each size gets a copy of runtime/ in OUTDIR.
#
#   sh bench/stackprobe.sh REPO OUTDIR LOGROOT CORES KB...
#
# Run it on Linux only.  It holds up to 10,000 live threads.
set -eu
REPO=$1; OUT=$2; LOGROOT=$3; CORES=$4; shift 4
for kb in "$@"; do
  D=$OUT/stack-$kb
  rm -rf "$D"; mkdir -p "$D"
  cp -R "$REPO/runtime" "$D/rt"
  sed "s|^#define M9_THREAD_STACK .*|#define M9_THREAD_STACK ((size_t) $kb * 1024)|" \
    "$REPO/runtime/m9rt.c" > "$D/rt/m9rt.c"
  grep -n '^#define M9_THREAD_STACK' "$D/rt/m9rt.c"
  cd "$D"
  for p in ThreadCost Boids; do
    M9LIBRARY=$REPO/corpus "$REPO/out/m9c" --make -k -I "$REPO/bench" -o tmp "$REPO/bench/$p.m9" > /dev/null
    objs=$(ls ./*.o | grep -v "/$p.o")
    # shellcheck disable=SC2086
    ${CC:-cc} -O2 -ffp-contract=off -flto --param max-inline-insns-auto=200 \
      -iquote "$D/rt" -iquote . "$p.c" $objs "$D/rt/m9rt.c" "$D/rt/tcpshim.c" \
      "$D/rt/tlsshim.c" "$D/rt/fmtshim.c" -Wl,--as-needed -lssl -lcrypto -lm \
      -o "$(echo $p | tr A-Z a-z)"
  done
  rm -f tmp
  PARTS="threads boids" sh "$REPO/bench/task0.sh" "$D" "$LOGROOT/stack-$kb" "$CORES" > /dev/null 2>&1 || true
  cd "$REPO"
done
