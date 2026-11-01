#!/bin/sh
# yieldtime.sh times yieldprobe.sh's variants by docs/bench.md's
# protocol: one warm-up, then the best wall clock of five (five, not
# three, because a check's cost is a few percent at most).  The
# variants' outputs are compared with y0's before a time is read.
#
#   sh bench/yieldtime.sh OUTDIR LOGDIR
set -u
O=$1; LOG=$2
mkdir -p "$LOG"
SUM=$LOG/yield-summary.txt
: > "$SUM"
now () { date +%s.%N; }
load () {
  l=$(uptime | sed 's/.*load average[s]*: //')
  if [ -r /proc/loadavg ]; then l="$l now=$(cut -d' ' -f4 /proc/loadavg)"; fi
  echo "$l"
}
# case NAME DIR ARGS... : each variant y0 y1 y2 of DIR's program.
# The word OUT in ARGS becomes a file per variant, compared like stdout.
tcase () {
  name=$1; prog=$2; shift 2
  for v in 0 1 2; do
    exe=$O/yp-$prog/$prog-y$v
    f=$LOG/y-$name-y$v.log
    : > "$f"
    best=""
    for k in 0 1 2 3 4 5; do
      args=$(echo "$@" | sed "s|OUT|$LOG/y-$name-y$v.file|g")
      l=$(load)
      t0=$(now)
      # shellcheck disable=SC2086
      $exe $args > "$LOG/y-$name-y$v.out" 2>&1
      rc=$?
      t1=$(now)
      w=$(echo "$t1 $t0" | awk '{printf "%.4f", $1 - $2}')
      echo "run $k rc=$rc wall_s=$w load=[$l]" >> "$f"
      if [ "$k" -gt 0 ] && [ "$rc" -eq 0 ]; then
        if [ -z "$best" ] || awk "BEGIN {exit !($w < $best)}"; then best=$w; bestl=$l; fi
      fi
    done
    same=same
    if [ "$v" -gt 0 ]; then
      cmp -s "$LOG/y-$name-y$v.out" "$LOG/y-$name-y0.out" || same=DIFFERS
      if [ -f "$LOG/y-$name-y0.file" ]; then
        cmp -s "$LOG/y-$name-y$v.file" "$LOG/y-$name-y0.file" || same=DIFFERS
      fi
    fi
    echo "$name y$v best_wall_s=${best:-FAIL} output=$same load=[${bestl:-}]" >> "$SUM"
  done
}
tcase fannkuch-11 fannkuch 11
tcase mandel-4000 mandel 4000 OUT
tcase bintrees-18 bintrees 18
tcase boids-30000x100 boids 30000 100 0
tcase m9c-check-Gen m9c --check "$(dirname "$0")/../corpus/Gen.m9"
cat "$SUM"
