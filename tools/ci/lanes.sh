#!/bin/sh
# lanes.sh LANE... runs CI's gates in parallel lanes, one step per job.
#
# Each argument is a lane: gate names, run in order.  The lanes run side
# by side.  CI ran every gate as a step of its own, one after another.
# lex took 28 min 42 s and drivers 24 min 33 s on a 24-core runner
# (2026-10-30, run 41029139223).  That is the gates' own sum, one core
# busy at a time.  The choice was lanes inside the jobs, over more
# runners and jobs.
#
# A gate is
#   NAME        runtime/test/NAME.sh
#   fpc:NAME    host/fpc/NAME.pas, compiled and run there
#   denycheck   tools/release/denycheck.sh
#
# WHAT A LANE MAY HOLD.  Gates in different lanes share the machine, so
# the ones that share a thing share a lane: every gate that compiles in
# host/fpc (one set of .ppu units), and tutdiff with winzip (port 18931).
# runtime/gen is regenerated under lib/gen.sh's lock.  runtime/test/m9c
# is replaced by rename only when it differs (lib/freshm9c.sh).  So
# neither is a reason.  Some gates cannot share the machine at all: a
# gate that measures time, a load test, tutor (it links
# runtime/test/m9c in place).  Each goes in a lanes.sh call of its own,
# one lane, after this one.
#
# The output puts every gate's log in a ::group:: of its own, lane by
# lane, then the gates by seconds.  A red gate is an ::error::, and its
# last lines are repeated outside the groups.  Every gate runs (a red
# one does not stop its lane), and the step is red when any gate is.
# The table also goes to $GITHUB_STEP_SUMMARY when there is one.
cd "$(dirname "$0")/../.." || exit 1
L=$(mktemp -d "${RUNNER_TEMP:-/tmp}/m9lanes.XXXXXX") || exit 1

gate () {
  case $1 in
    fpc:*) ( cd host/fpc && fpc -O2 "${1#fpc:}.pas" && "./${1#fpc:}" ) ;;
    denycheck) tools/release/denycheck.sh ;;
    *) "runtime/test/$1.sh" ;;
  esac
}

lane () {
  : > "$L/lane$2"
  for g in $1; do
    t0=$(date +%s)
    st=0
    gate "$g" < /dev/null > "$L/$(echo "$g" | tr : -).log" 2>&1 || st=$?
    echo "$g $st $(( $(date +%s) - t0 )) $2" >> "$L/lane$2"
  done
}

start=$(date +%s)
i=0
for spec in "$@"; do
  i=$((i + 1))
  lane "$spec" $i &
done
wait

fail=0
: > "$L/all"
i=0
for spec in "$@"; do
  i=$((i + 1))
  while read -r g st s n; do
    echo "::group::$g -- exit $st, $s s (lane $n)"
    cat "$L/$(echo "$g" | tr : -).log"
    echo "::endgroup::"
    echo "$g $st $s $n" >> "$L/all"
  done < "$L/lane$i"
done
while read -r g st s n; do
  [ "$st" = 0 ] && continue
  fail=1
  echo "::error title=$g::exit $st"
  echo "---- $g (exit $st), its last lines:"
  tail -20 "$L/$(echo "$g" | tr : -).log"
done < "$L/all"

table=$(sort -k3 -rn "$L/all" | awk '{ printf "%-12s %4s s  lane %s  %s\n", $1, $3, $4, ($2 == 0 ? "ok" : "EXIT " $2) }')
echo "$table"
summary="lanes: $(wc -l < "$L/all" | tr -d ' ') gates in $# lanes, $(( $(date +%s) - start )) s, $(grep -vc ' 0 [0-9]* [0-9]*$' "$L/all") red"
echo "$summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### $summary"; echo '```'; echo "$table"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
fi
rm -rf "$L"
exit $fail
