#!/bin/sh
# par 6, end to end: m9c compiles a program using THREAD, MONITOR,
# WAIT and SIGNAL, and the program gives the right answer.
#
# The answer is what makes this a test rather than a demonstration.
# The worker adds i MOD 7 for i in 0..N-1 into a monitor field and
# signals; the main thread waits.  If the wait returned early, or the
# lock did not serialise the field, or the thread never ran, the total
# is wrong -- and it is checked against a number computed here, not
# against whatever the program printed last time.
#
# RUN REPEATEDLY.  A race that fires one time in ten is still a race,
# and a single green run is the blosc museum piece all over again.
set -e
cd "$(dirname "$0")"

REPO=$(cd ../.. && pwd)
M9C=${M9C:-$REPO/runtime/test/m9c}
[ -x "$M9C" ] || M9C=$REPO/out/m9c
[ -x "$M9C" ] || { echo "no m9c: run runtime/test/m9c.sh or ./build.sh"; exit 1; }

OUT=/tmp/m9threads
rm -rf "$OUT"; mkdir -p "$OUT"
cp thrtest.m9 "$OUT/"
export M9RUNTIME="$REPO/runtime"
export M9LIBRARY="$REPO/corpus"

( cd "$OUT" && "$M9C" --make -o thrtest thrtest.m9 -I. )

# 3000000 terms of i mod 7: 428571 full cycles of 0..6 (sum 21) plus
# the tail 0,1,2 -- computed here so the expectation is derived, not
# remembered
want=$(( 428571 * 21 + 0 + 1 + 2 ))
runs=20
bad=0
for i in $(seq $runs); do
  got=$("$OUT/thrtest" | sed 's/^n = //')
  [ "$got" = "$want" ] || { bad=$((bad + 1)); echo "  run $i: got $got, want $want"; }
done

if [ "$bad" -ne 0 ]; then
  echo "threads: $bad of $runs runs disagreed"
  exit 1
fi
# ---- [SERIAL] is a GUARANTEE, not a rule to remember ----
#
# serialtest.m9 calls a deliberately unsafe C library (read, spin,
# write back) from eight threads.  The generator gates every call to a
# [SERIAL] foreign procedure behind one monitor per FOR-C unit, so the
# count comes out exact.  Change the declaration to [REENTRANT] and
# the same program loses about 85% of its updates -- measured, which
# is how this test was shown able to fail.
cp serialtest.m9 serialgate.c "$OUT/"
gcc -std=c11 -O2 -c "$OUT/serialgate.c" -o "$OUT/serialgate.o"
( cd "$OUT" && "$M9C" --make -c serialtest.m9 -I. )
( cd "$OUT" && gcc -std=c11 -O2 -flto -iquote "$REPO/runtime" -iquote . \
    "$REPO/runtime/m9rt.c" ./*.o -lm -o serialtest )

sbad=0
for i in $(seq 5); do
  out=$("$OUT/serialtest")
  case "$out" in
    *OK) : ;;
    *) sbad=$((sbad + 1)); echo "  $out" ;;
  esac
done
if [ "$sbad" -ne 0 ]; then
  echo "threads: [SERIAL] gate lost updates in $sbad of 5 runs"
  exit 1
fi

echo "threads: $runs runs of THREAD/MONITOR/WAIT/SIGNAL answered $want;"
echo "         5 runs of the [SERIAL] gate lost no updates"
