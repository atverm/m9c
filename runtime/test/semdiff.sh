#!/bin/sh
# P5 stage-2 differential for the CHECKER: the M9-compiled Sem against
# host/fpc/M9Sem, compared on the only output a checker has -- its
# diagnostics, with their text, line, column and ORDER, plus the par
# 4.1 ledger, which the kill-gate reads and so is output too.
#
# A GATE: every corpus, museum and bench file must produce identical
# diagnostics from both checkers.  It reported progress while Sem.m9
# was transcribed pass by pass -- the list of what was left, generated
# rather than remembered -- and reached zero, so it gates now.
#
# -Wno-unused-function is deliberate and temporary: the registry
# exposes helpers (IsOpaqueIn) that the passes still to be
# written will call.  It comes out when the transcription is done.
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found

gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c \
    ../gen/Text.c ../gen/Lex.c ../gen/Ast.c ../gen/DynUtf.c ../gen/Print.c \
    ../gen/Parse.c ../gen/Sem.c semdump_m9.c -lm -o semdump_m9
( cd ../../host/fpc && fpc -O2 semdump.pas >/dev/null )

M9=$(pwd)/semdump_m9
same=0; diff_n=0; shown=0

# Every corpus module is loaded before any file is checked, which is
# the configuration semtest uses: a cross-module name that has not
# been loaded is indistinguishable from one that does not exist, so
# without this the oracle reports unresolved calls the checker would
# never see in practice.
DEPS=""
for d in ../../corpus/*.m9; do DEPS="$DEPS ../..${d#../..}"; done

# THE TWO CHECKERS RUN IN PARALLEL, one process per file per core, into
# a directory of this run's own; the comparison below stays serial and
# in file order, so the output is what it was.  Each file loads the
# whole corpus in both checkers, 1.4 s a file, and run one by one the
# gate took 186 s on the MacBook at 130 files (2026-10-21) and grows
# with every file added.  M9_JOBS sets the count.  The fixed
# /tmp/sem_{fpc,m9}.txt it used collided between checkouts.
W=$(mktemp -d /tmp/m9semdiff.XXXXXX)
J=${M9_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
i=0
: > "$W/list"
for f in ../../corpus/*.m9 ../../museum/*.m9 ../../bench/*.m9; do
  i=$((i+1))
  printf '%s %s\n' "$i" "../..${f#../..}" >> "$W/list"
done
export DEPS M9 W
# each driver's exit status and stderr are KEPT and judged: until
# 2026-10-22 both went to /dev/null behind `|| true', so two checkers
# crashing alike -- or a driver that could not be run -- "agreed" (the
# compiler review's tier 3).  Every file here parses and is checked to
# the end, so each driver must exit 0 and say nothing on stderr.
xargs -P "$J" -L 1 sh -c 'cd ../../host/fpc &&
  { ./semdump "$1" $DEPS > "$W/$0.fpc" 2> "$W/$0.fpc.err" ; echo $? > "$W/$0.fpc.st" ;
    "$M9" "$1" $DEPS > "$W/$0.m9" 2> "$W/$0.m9.err" ; echo $? > "$W/$0.m9.st" ; }' < "$W/list"

broken=0
while read -r n t; do
  for side in fpc m9; do
    if [ "$(cat "$W/$n.$side.st")" != 0 ] || [ -s "$W/$n.$side.err" ]; then
      broken=$((broken+1))
      echo "semdiff: the $side driver FAILED on $(basename "$t") (exit $(cat "$W/$n.$side.st")):"
      head -3 "$W/$n.$side.err" | sed 's/^/    /'
    fi
  done
  if cmp -s "$W/$n.fpc" "$W/$n.m9"; then
    same=$((same+1))
  else
    diff_n=$((diff_n+1))
    if [ "$shown" -lt 3 ]; then
      echo "--- $(basename "$t"): oracle says what M9 does not yet"
      diff "$W/$n.fpc" "$W/$n.m9" | head -4
      shown=$((shown+1))
    fi
  fi
done < "$W/list"
rm -rf "$W"

if [ "$broken" -ne 0 ]; then
  echo "semdiff: $broken driver runs failed"
  exit 1
fi
if [ "$diff_n" -ne 0 ]; then
  echo "semdiff: $same agree, $diff_n DIVERGE"
  exit 1
fi
echo "semdiff: $same files, diagnostics byte-identical to the oracle"
