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
#
# A GATE WHOSE INPUTS DID NOT CHANGE NEED NOT RUN AGAIN.  With
# M9_LANES_KEYCMD and M9_LANES_KEYDIR set, the command is called once
# before the lanes start, as KEYCMD TREE GATE..., and prints a line
# `NAME KEY' for each gate, or `NAME - REASON' for one that has no key.
# A gate whose key is the one stored at its last green run is not run:
# its line says `cached'.  M9_LANES_FRESH=1 runs every gate and still
# stores the keys of the green ones.
#
# Two things make a stored key mean what it says.  runtime/gen is made
# current BEFORE the keys are taken (lib/gen.sh), so a key is of the C
# the gates compile and not of a stale copy.  And the contents of the
# files each gate reads are hashed AGAIN when the lanes have ended (the
# key command's third word): a green gate's key is stored only when
# they are still the same.  A file edited under the round leaves no key
# behind.  Listings are not compared at the end: the gates' own build
# products change them, and a stored key is the one taken at the start
# in any case, so the next round sees any change.  M9_LANES_DUMP=DIR writes
# what went into each key at the start and at the end, DIR/start and
# DIR/end, so that a diff names the file that moved.
#
# The command and the inputs it hashes are outside this tree: they come
# from a trace of each gate on one machine.  Without the two variables
# every gate runs, as on CI, which is the full run that needs no one's
# machine.  A release runs fresh.  (The author, 2026-11-20: what did
# not change is not tested again, and everything only before a
# release.)
#
# A GATE THAT MEASURES TIME IS RUN AGAIN ALONE BEFORE IT IS RED.  The
# gates of M9_LANES_RETRY (default: scale) share the machine with the
# other lanes, and with whatever else the machine does.  One of them
# that is red is run once more after the lanes have ended.  Green then,
# its line says `ok alone' and the step is not red: the first run
# measured the load.  Red again, it is red.  A real slowdown fails
# alone too.
cd "$(dirname "$0")/../.." || exit 1
# Gates write no core files.  Several stop a program by abort on
# purpose: the task stops, and soundfuzz's mutants.  Where core dumps
# are on, each abort wrote a core of about 265 MB into the tree (a CI
# container, found 2026-11-21).  GitHub's runners have them off too.
ulimit -c 0 2>/dev/null
L=$(mktemp -d "${RUNNER_TEMP:-/tmp}/m9lanes.XXXXXX") || exit 1
RETRY=${M9_LANES_RETRY-scale}

gate () {
  case $1 in
    fpc:*) ( cd host/fpc && fpc -O2 "${1#fpc:}.pas" && "./${1#fpc:}" ) ;;
    denycheck) tools/release/denycheck.sh ;;
    *) "runtime/test/$1.sh" ;;
  esac
}

# The keys, taken once, before a lane writes anything.
KD=${M9_LANES_KEYDIR:-}
KEYS=
if [ -n "${M9_LANES_KEYCMD:-}" ] && [ -n "$KD" ]; then
  if ! ( cd runtime/test && . ./lib/gen.sh && [ "${M9GENST:-0}" = 0 ] ) > "$L/prelude.log" 2>&1; then
    echo "lanes: no keys, every gate runs: lib/gen.sh failed: $(tail -1 "$L/prelude.log")"
  elif mkdir -p "$KD" && ROUND_DUMP=${M9_LANES_DUMP:+$M9_LANES_DUMP/start} "$M9_LANES_KEYCMD" "$PWD" $* > "$L/keys" 2> "$L/keys.err"; then
    KEYS=$L/keys
  else
    echo "lanes: no keys, every gate runs: $(tail -1 "$L/keys.err")"
  fi
fi
keyof () { [ -n "$KEYS" ] && awk -v n="$1" '$1 == n { print $2 }' "$KEYS"; }

lane () {
  : > "$L/lane$2"
  for g in $1; do
    f=$(echo "$g" | tr : -)
    k=$(keyof "$g")
    if [ "${M9_LANES_FRESH:-0}" != 1 ] && [ -n "$k" ] && [ "$k" != - ] &&
       [ "$(cat "$KD/$f.key" 2>/dev/null)" = "$k" ]; then
      echo "not run: its inputs are those of its last green run (key $k)" > "$L/$f.log"
      echo "$g 0 0 $2 cached" >> "$L/lane$2"
      continue
    fi
    t0=$(date +%s)
    st=0
    gate "$g" < /dev/null > "$L/$f.log" 2>&1 || st=$?
    echo "$g $st $(( $(date +%s) - t0 )) $2 ran" >> "$L/lane$2"
  done
}

start=$(date +%s)
i=0
for spec in "$@"; do
  i=$((i + 1))
  lane "$spec" $i &
done
wait

# A red gate that measures time runs once more, alone.
i=0
for spec in "$@"; do
  i=$((i + 1))
  : > "$L/lane$i.new"
  while read -r g st s n how; do
    case " $RETRY " in
      *" $g "*)
        if [ "$st" != 0 ]; then
          f=$(echo "$g" | tr : -)
          t0=$(date +%s)
          st2=0
          { echo; echo "---- red beside the other lanes (exit $st); alone:"; } >> "$L/$f.log"
          gate "$g" < /dev/null >> "$L/$f.log" 2>&1 || st2=$?
          s=$(( s + $(date +%s) - t0 ))
          if [ $st2 = 0 ]; then st=0; how=alone; else st=$st2; fi
        fi ;;
    esac
    echo "$g $st $s $n $how" >> "$L/lane$i.new"
  done < "$L/lane$i"
  mv -f "$L/lane$i.new" "$L/lane$i"
done

# The keys again.  A green gate that ran stores its key when the key
# is what it was before the lanes started.
if [ -n "$KEYS" ] && ROUND_CONTENT_ONLY=1 ROUND_DUMP=${M9_LANES_DUMP:+$M9_LANES_DUMP/end} "$M9_LANES_KEYCMD" "$PWD" $* > "$L/keys.end" 2>> "$L/keys.err"; then
  cat "$L"/lane[0-9]* | while read -r g st s n how; do
    [ "$st" = 0 ] && [ "$how" = ran ] || continue
    k=$(keyof "$g")
    [ -n "$k" ] && [ "$k" != - ] || continue
    f=$(echo "$g" | tr : -)
    c=$(awk -v n="$g" '$1 == n { print $3 }' "$KEYS")
    if [ -n "$c" ] && [ "$(awk -v n="$g" '$1 == n { print $3 }' "$L/keys.end")" = "$c" ]; then
      echo "$k" > "$KD/$f.key.$$" && mv -f "$KD/$f.key.$$" "$KD/$f.key"
    else
      echo "$g" >> "$L/moved"
    fi
  done
fi

fail=0
: > "$L/all"
i=0
for spec in "$@"; do
  i=$((i + 1))
  while read -r g st s n how; do
    case $how in
      cached) echo "::group::$g -- not run, cached (lane $n)" ;;
      alone)  echo "::group::$g -- red under load, exit 0 alone, $s s (lane $n)" ;;
      *)      echo "::group::$g -- exit $st, $s s (lane $n)" ;;
    esac
    cat "$L/$(echo "$g" | tr : -).log"
    echo "::endgroup::"
    echo "$g $st $s $n $how" >> "$L/all"
  done < "$L/lane$i"
done
while read -r g st s n how; do
  [ "$st" = 0 ] && continue
  fail=1
  echo "::error title=$g::exit $st"
  echo "---- $g (exit $st), its last lines:"
  tail -20 "$L/$(echo "$g" | tr : -).log"
done < "$L/all"

table=$(sort -k3 -rn "$L/all" | awk '{
  what = ($2 != 0 ? "EXIT " $2 : ($5 == "cached" ? "cached" : ($5 == "alone" ? "ok alone (red under load)" : "ok")))
  printf "%-12s %4s s  lane %s  %s\n", $1, $3, $4, what }')
echo "$table"
[ -n "$KEYS" ] && awk '$2 == "-" { n = $1; $1 = ""; $2 = ""; print "always runs: " n " --" $0 }' "$KEYS"
[ -f "$L/moved" ] && echo "no key stored, an input changed while the round ran: $(tr '\n' ' ' < "$L/moved")"
summary="lanes: $(wc -l < "$L/all" | tr -d ' ') gates in $# lanes, $(( $(date +%s) - start )) s, $(awk '$2 != 0' "$L/all" | wc -l | tr -d ' ') red"
c=$(awk '$5 == "cached"' "$L/all" | wc -l | tr -d ' ')
a=$(awk '$5 == "alone"' "$L/all" | wc -l | tr -d ' ')
[ "$c" != 0 ] && summary="$summary, $c cached"
[ "$a" != 0 ] && summary="$summary, $a red under load and green alone"
echo "$summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### $summary"; echo '```'; echo "$table"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
fi
rm -rf "$L"
exit $fail
