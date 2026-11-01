#!/bin/sh
# task0.sh runs stage 0 of docs/task-plan.md: today's THREAD costs and
# the boids shapes, by docs/bench.md's protocol.
#
#   sh bench/task0.sh BINDIR LOGDIR CORES
#
# BINDIR holds threadcost, boids and gocost (optional), built from
# ThreadCost.m9, Boids.m9 and gocost/main.go.
# Each case runs once to warm up, then three times.  The log keeps
# every run: its load average, its wall clock, its output and, for the
# idle cases, its RSS while the threads are parked.  summary.txt
# keeps the best of three.  The boids outputs are compared with the
# serial one before any time is read; a differing checksum is a FAIL
# line and the case's time is not reported.
#
# PARTS (default "threads boids go") picks the sections.  THREADCAP
# skips every case that would hold more live threads than it says.  On
# the MacBook it is 1000: 10,000 parked pthreads panicked macOS 26
# twice on 2026-11-01 (a kernel spinlock timeout).
set -u
PARTS=${PARTS:-threads boids go}
THREADCAP=${THREADCAP:-1000000}
has () { case " $PARTS " in *" $1 "*) return 0 ;; esac; return 1; }
# cap NAME LIVE : true if the case may run; else a SKIP line.
cap () {
  if [ "$2" -gt "$THREADCAP" ]; then echo "$1 SKIP: $2 live threads > THREADCAP $THREADCAP" >> "$SUM"; return 1; fi
  return 0
}
BIN=$1
LOG=$2
CORES=$3
mkdir -p "$LOG"
SUM=$LOG/summary.txt
: > "$SUM"
now () { date +%s.%N; }
# load gives the load averages and, on Linux, the runnable/total
# threads of /proc/loadavg at this instant.  A load average decays over
# minutes, so it still counts the threads of a case that just ended.
load () {
  l=$(uptime | sed 's/.*load average[s]*: //')
  if [ -r /proc/loadavg ]; then l="$l now=$(cut -d' ' -f4 /proc/loadavg)"; fi
  echo "$l"
}

# run NAME CMD... : warm-up plus three, best wall clock to summary.
# An idle case's RSS is read by ps 1.2 s in, while its threads are
# parked (the program parks them in under 0.5 s and sleeps 2 s).
run () {
  name=$1; shift
  f=$LOG/$name.log
  : > "$f"
  best=""
  for k in 0 1 2 3; do
    l=$(load)
    t0=$(now)
    "$@" > "$LOG/$name.out.$k" 2> "$LOG/$name.err.$k" &
    pid=$!
    rss=-
    case $name in
      *idle*) sleep 1.2; rss=$(ps -o rss= -p $pid | tr -d ' ') ;;
    esac
    wait $pid
    rc=$?
    t1=$(now)
    w=$(echo "$t1 $t0" | awk '{printf "%.4f", $1 - $2}')
    echo "run $k rc=$rc wall_s=$w rss_kb=$rss load=[$l]" >> "$f"
    sed 's/^/  /' "$LOG/$name.out.$k" >> "$f"
    sed 's/^/  err: /' "$LOG/$name.err.$k" >> "$f"
    if [ "$k" -gt 0 ] && [ "$rc" -eq 0 ]; then
      if [ -z "$best" ] || awk "BEGIN {exit !($w < $best)}"; then best=$w; bestk=$k; bestrss=$rss; bestl=$l; fi
    fi
  done
  if [ -z "$best" ]; then
    echo "$name FAIL (see $f)" >> "$SUM"
    return
  fi
  echo "$name best_wall_s=$best rss_kb=$bestrss load=[$bestl]" >> "$SUM"
  sed 's/^/    /' "$LOG/$name.out.$bestk" >> "$SUM"
}

# boids NAME N STEPS CMD... : run, then hold the output to the serial one.
boids () {
  name=$1; n=$2; shift 3
  cap "$name" "$4" || return 0
  run "$name" "$@"
  if ! cmp -s "$LOG/$name.out.1" "$LOG/serial-$n.out.1"; then
    echo "$name FAIL: checksum differs from serial-$n" >> "$SUM"
  fi
}

echo "machine $(uname -sm) cores=$CORES date=$(date -u +%FT%TZ)" >> "$SUM"

# 1. today's THREAD costs
if has threads; then
  cap create-10000 1 && run create-10000 "$BIN/threadcost" create 10000
  cap burst-1000 1000 && run burst-1000 "$BIN/threadcost" burst 1000
  cap burst-10000 10000 && run burst-10000 "$BIN/threadcost" burst 10000
  cap pingpong-100000 2 && run pingpong-100000 "$BIN/threadcost" pingpong 100000
  cap idle-0 1 && run idle-0 "$BIN/threadcost" idle 1
  cap idle-1000 1000 && run idle-1000 "$BIN/threadcost" idle 1000
  cap idle-10000 10000 && run idle-10000 "$BIN/threadcost" idle 10000
fi

# 2. the boids shapes, 100 steps
if has boids; then
  for n in 1000 10000; do
    run "serial-$n" "$BIN/boids" $n 100 0
    boids "par-$n-t$CORES" $n 100 "$BIN/boids" $n 100 "$CORES"
    boids "many-$n-g10" $n 100 "$BIN/boids" $n 100 $((n / 10))
    boids "many-$n-g1" $n 100 "$BIN/boids" $n 100 $n
  done
  run serial-100000 "$BIN/boids" 100000 100 0
  boids par-100000-t$CORES 100000 100 "$BIN/boids" 100000 100 "$CORES"
fi

# 3. Go's goroutines, as context (few OS threads, so no cap)
if has go && [ -x "$BIN/gocost" ]; then
  run go-create-10000 "$BIN/gocost" create 10000
  run go-burst-10000 "$BIN/gocost" burst 10000
  run go-pingpong-100000 "$BIN/gocost" pingpong 100000
  run go-idle-10000 "$BIN/gocost" idle 10000
  run go-idle-100000 "$BIN/gocost" idle 100000
fi
cat "$SUM"
