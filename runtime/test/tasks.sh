#!/bin/sh
# TASK, stage 1 of docs/task-plan.md: many tasks on the thread that
# starts them, cooperative, with task-aware monitors.
#
# The C driver holds the runtime to exact counts first (task_driver.c
# says what).  Then the language, end to end:
#   tasktest parks 100,000 TASKs in WAIT and frees them with one
#   SIGNAL; both counts must be exact.
#   Mixed has a THREAD and a TASK wait for each other's SIGNAL on one
#   monitor, 1,000 rounds, under a timeout.  A wake lost on either
#   path hangs it.  It is also the deadlock stop's control: a THREAD
#   is alive, so the stop must not fire.
#   Overflow's task recurses into its guard page and must stop with
#   "task stack overflow in Overflow.Deep".  tasktest is its control:
#   100,000 tasks that do not recurse end without it.
#   Deadlock's tasks and module body all wait.  It must stop with
#   "every task waits" and list both tasks.
#   TaskCost runs ThreadCost's four modes as TASKs and prints them.
#   The times are printed, not held: they depend on the machine's load.
set -e
cd "$(dirname "$0")"

REPO=$(cd ../.. && pwd)
. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C

OUT=${TMPDIR:-/tmp}/m9tasks
rm -rf "$OUT"; mkdir -p "$OUT"
export M9RUNTIME="$REPO/runtime"
export M9LIBRARY="$REPO/corpus"
bad=0
fail () { echo "tasks: FAIL $1"; bad=$((bad + 1)); }

gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c task_driver.c -lm -o "$OUT/task_test"
timeout 120 "$OUT/task_test" > "$OUT/driver.log" 2>&1 || true
sed 's/^/  /' "$OUT/driver.log"
grep -q '^PASS:' "$OUT/driver.log" || fail "the runtime driver"

cp tasktest.m9 taskfix/*.m9 "$REPO/bench/TaskCost.m9" "$OUT/"
for m in tasktest Mixed Overflow Deadlock TaskCost; do
  ( cd "$OUT" && "$M9C" --make -o "$m" "$m.m9" -I. ) || fail "building $m"
done

got=$(timeout 120 "$OUT/tasktest") || true
[ "$got" = "parked 100000, out 100000" ] || fail "tasktest said '$got'"
echo "  tasktest: $got"

for i in 1 2 3 4 5; do
  got=$(timeout 30 "$OUT/Mixed" 2>&1) || true
  [ "$got" = "rounds 1000" ] || { fail "Mixed run $i said '$got'"; break; }
done
echo "  Mixed: a THREAD and a TASK, 1,000 rounds each way, five runs"

if timeout 30 "$OUT/Overflow" > /dev/null 2> "$OUT/overflow.err"; then
  fail "Overflow ended normally"
fi
grep -q 'task stack overflow in Overflow.Deep' "$OUT/overflow.err" || fail "Overflow's stop: $(cat "$OUT/overflow.err")"
echo "  Overflow: $(head -1 "$OUT/overflow.err")"

if timeout 30 "$OUT/Deadlock" > /dev/null 2> "$OUT/deadlock.err"; then
  fail "Deadlock ended normally"
fi
grep -q 'every task waits' "$OUT/deadlock.err" || fail "Deadlock's stop: $(cat "$OUT/deadlock.err")"
[ "$(grep -c 'Deadlock.Hold waits in WAIT' "$OUT/deadlock.err")" = 2 ] || fail "Deadlock's list: $(cat "$OUT/deadlock.err")"
echo "  Deadlock: $(head -1 "$OUT/deadlock.err")"

for m in "create 10000" "burst 10000" "pingpong 100000" "idle 10000"; do
  # shellcheck disable=SC2086
  timeout 120 "$OUT/TaskCost" $m > "$OUT/cost.txt" 2>&1 || fail "TaskCost $m"
  sed 's/^/  TaskCost /' "$OUT/cost.txt"
done

if [ "$bad" -ne 0 ]; then
  echo "tasks: $bad failed"
  exit 1
fi
echo "tasks: the runtime driver, 100,000 parked, THREAD and TASK both ways, the overflow and deadlock stops"
