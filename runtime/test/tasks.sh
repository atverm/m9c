#!/bin/sh
# TASK, stage 1 of docs/task-plan.md: many tasks on the thread that
# starts them, cooperative, with task-aware monitors.
#
# The C driver holds the runtime to exact counts first (task_driver.c
# says what), and the TCP driver tcpshim's task path.  Then the language, end to end:
#   tasktest parks 100,000 TASKs in WAIT and frees them with one
#   SIGNAL; both counts must be exact.
#   Herd runs 2,000 tasks through ten barrier steps: one SIGNAL wakes
#   them all, they are dealt out across the carriers, and the total
#   is exact.
#   ChanStress sends through one Chan from 1,000 tasks and two
#   THREADs to one receiver, then from one sender to 100 receiver
#   tasks; every value must arrive once, each sender's in order.
#   Poison has a bug leave a bound procedure: the next call into the
#   monitor raises Poisoned, a [RESET] procedure rebuilds it from zero,
#   and a checked exception leaves its monitor usable (stage 5).
#   Preempt has a task in a long loop nest with no call and no wait;
#   on one carrier the module body and a second task run only if the
#   yield check (rule y8) makes it yield.  With the check removed from
#   the C it says FALSE.
#   examples/traffic/Traffic.m9 runs car tasks in simulated time with
#   a Tsk.For step and a Chan; its numbers must not depend on the
#   carriers.
#   examples/supervision/Supervise.m9 runs three workers under Sup:
#   restarts, giving up upward, and the stop at the third dirty crash.
#   SerialSlow has a task asleep in a [SERIAL] foreign call while
#   four more wait for the gate and 1,000 others run.
#   Mixed has a THREAD and a TASK wait for each other's SIGNAL on one
#   monitor, 1,000 rounds, under a timeout.  A wake lost on either
#   path hangs it.  It is also the deadlock stop's control: a THREAD
#   is alive, so the stop must not fire.
#   Overflow's task recurses into its guard page and must stop with
#   "task stack overflow in Overflow.Deep".  tasktest is its control:
#   100,000 tasks that do not recurse end without it.
#   Deadlock's tasks and module body all wait.  It must stop with
#   "every task waits" and list both tasks.
#   TaskCost runs ThreadCost's four modes as TASKs, and a Chan
#   ping-pong, and prints them.
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

# tcpshim's task path: an echo server in tasks and 1,000 client tasks,
# all connections open at once, and SO_RCVTIMEO honoured.  1,000 is
# what macOS's listen backlog (128) lets through; ct121 holds 10,000.
gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c tcptask_driver.c -lm -o "$OUT/tcptask_test"
timeout 120 "$OUT/tcptask_test" 1000 > "$OUT/tcptask.log" 2>&1 || true
sed 's/^/  /' "$OUT/tcptask.log"
grep -q '^PASS:' "$OUT/tcptask.log" || fail "the TCP task driver"

# tlsshim's task path: a TLS echo server in tasks and 1,000 client
# tasks through tls_connect, all handshakes done and open at once, and
# a thread's blocking handle beside them.  The certificate is made
# here, for localhost, and trusted through $SSL_CERT_FILE.
if openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
     -keyout "$OUT/key.pem" -out "$OUT/cert.pem" \
     -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost' >/dev/null 2>&1; then
  gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
      -iquote .. -iquote ../gen ../m9rt.c ../tcpshim.c ../tlsshim.c tlstask_driver.c \
      -lssl -lcrypto -lm -o "$OUT/tlstask_test"
  SSL_CERT_FILE="$OUT/cert.pem" timeout 120 "$OUT/tlstask_test" 1000 "$OUT/cert.pem" "$OUT/key.pem" \
    > "$OUT/tlstask.log" 2>&1 || true
  sed 's/^/  /' "$OUT/tlstask.log"
  grep -q '^PASS:' "$OUT/tlstask.log" || fail "the TLS task driver"
else
  fail "openssl(1) could not make the TLS driver's certificate"
fi

cp tasktest.m9 taskfix/*.m9 "$REPO/bench/TaskCost.m9" "$OUT/"
for m in tasktest Mixed Herd ChanStress Preempt Poison Overflow Deadlock TaskCost; do
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

for i in 1 2 3 4 5; do
  got=$(timeout 60 "$OUT/Herd" 2>&1) || true
  [ "$got" = "total 110000" ] || { fail "Herd run $i said '$got'"; break; }
done
echo "  Herd: 2,000 tasks through ten barrier steps on every carrier, five runs"

for c in 1 "" "" ""; do
  got=$(M9_CARRIERS=$c timeout 60 "$OUT/ChanStress" 2>&1) || true
  [ "$got" = "in 120000 ordered out 100000 sum 5000050000" ] || { fail "ChanStress (M9_CARRIERS='$c') said '$got'"; break; }
done
echo "  ChanStress: 1,000 sender tasks and 2 THREADs into one Chan, then one sender to 100 receivers, exact"

for c in 1 ""; do
  got=$(M9_CARRIERS=$c timeout 60 "$OUT/Preempt" 2>&1) || true
  [ "$got" = "quick ran while spin ran: TRUE
spin 905784359" ] || { fail "Preempt (M9_CARRIERS='$c') said '$got'"; break; }
done
echo "  Preempt: a task in a loop nest yields at its check, on one carrier, and computes the same"

for c in 1 ""; do
  got=$(M9_CARRIERS=$c timeout 30 "$OUT/Poison" 2>&1) || true
  [ "$got" = "bug: Poisoned
reset: still usable, balance 250
checked: still usable, balance 100
task: Poisoned" ] || { fail "Poison (M9_CARRIERS='$c') said '$got'"; break; }
done
echo "  Poison: a bug poisons its monitor, [RESET] rebuilds it from zero, a checked exception does not poison"

# examples/traffic: cars as tasks asleep in simulated time, a master
# that owns the clock, a Tsk.For step and a Chan to a logger.  The
# numbers do not depend on the scheduler, so one carrier and every
# core must print the same lines.
mkdir -p "$OUT/traffic"
cp "$REPO/examples/traffic/Traffic.m9" "$OUT/traffic/"
( cd "$OUT/traffic" && "$M9C" --make -o Traffic Traffic.m9 -I. ) || fail "building examples/traffic"
for c in 1 ""; do
  got=$(M9_CARRIERS=$c timeout 60 "$OUT/traffic/Traffic" 2>&1) || true
  [ "$got" = "cars 400 ticks 1000 arrivals 21231 trip ticks 333579 check 133748114" ] ||
    fail "Traffic (M9_CARRIERS='$c') said '$got'"
  got=$(M9_CARRIERS=$c timeout 60 "$OUT/traffic/Traffic" 2000 500 2>&1) || true
  [ "$got" = "cars 2000 ticks 500 arrivals 47322 trip ticks 841404 check 471801763" ] ||
    fail "Traffic 2000 500 (M9_CARRIERS='$c') said '$got'"
done
echo "  Traffic: 400 and 2,000 car tasks in simulated time, the same numbers on one carrier and every core"

# examples/supervision: three workers under Sup.  Every failed start is
# started again; giving up fails upward with status 2; the third dirty
# crash stops the program by name with status 1.
mkdir -p "$OUT/sup"
cp "$REPO/examples/supervision/Supervise.m9" "$OUT/sup/"
( cd "$OUT/sup" && "$M9C" --make -o Supervise Supervise.m9 -I. ) || fail "building examples/supervision"
for c in 1 ""; do
  got=$(M9_CARRIERS=$c timeout 30 "$OUT/sup/Supervise" 2>&1) || true
  [ "$got" = "worker 0 sum 285 starts 11
worker 1 sum 285 starts 11
worker 2 sum 285 starts 11
restarts 30 clean, 0 dirty" ] || fail "Supervise (M9_CARRIERS='$c') said '$got'"
  st=0; got=$(M9_CARRIERS=$c timeout 30 "$OUT/sup/Supervise" giveup 2>&1) || st=$?
  [ "$st" = 2 ] && [ "$got" = "the supervisor gave up after 4 restarts" ] ||
    fail "Supervise giveup (M9_CARRIERS='$c') said '$got', status $st"
  st=0; got=$(M9_CARRIERS=$c timeout 30 "$OUT/sup/Supervise" dirty 2>&1) || st=$?
  [ "$st" = 1 ] && [ "$got" = "m9: Sup: child 0 crashed 3 times by a bug, the last by IndexError; the program stops" ] ||
    fail "Supervise dirty (M9_CARRIERS='$c') said '$got', status $st"
done
echo "  Supervise: restarts from scratch, giving up upward, and the stop at the third dirty crash"

# SerialSlow: five tasks call a [SERIAL] library that sleeps 300 ms in
# the kernel, and 1,000 quick tasks run beside them.  The gate lets
# one in at a time, and every quick task ends while the first call
# still sleeps.  With the gate removed it says most 5.  One carrier,
# then every core.
mkdir -p "$OUT/ss"
cp taskfix/SerialSlow.m9 taskfix/slowgate.c "$OUT/ss/"
gcc -std=c11 -O2 -c "$OUT/ss/slowgate.c" -o "$OUT/ss/slowgate.o"
( cd "$OUT/ss" && "$M9C" --make -c SerialSlow.m9 -I. ) || fail "building SerialSlow"
( cd "$OUT/ss" && gcc -std=c11 -O2 -flto -iquote "$REPO/runtime" -iquote . \
    "$REPO/runtime/m9rt.c" ./*.o -lm -o SerialSlow ) || fail "linking SerialSlow"
for c in 1 ""; do
  got=$(M9_CARRIERS=$c timeout 30 "$OUT/ss/SerialSlow" 2>&1) || true
  [ "$got" = "slow 5 most 1 quick 1000 during 1000" ] || fail "SerialSlow (M9_CARRIERS='$c') said '$got'"
done
echo "  SerialSlow: a task asleep in a [SERIAL] call stops neither the gate's order nor 1,000 other tasks"

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

for m in "create 10000" "burst 10000" "pingpong 100000" "idle 10000" "chan 100000"; do
  # shellcheck disable=SC2086
  timeout 120 "$OUT/TaskCost" $m > "$OUT/cost.txt" 2>&1 || fail "TaskCost $m"
  sed 's/^/  TaskCost /' "$OUT/cost.txt"
done

if [ "$bad" -ne 0 ]; then
  echo "tasks: $bad failed"
  exit 1
fi
echo "tasks: the runtime driver, 100,000 parked, THREAD and TASK both ways, the overflow and deadlock stops"
