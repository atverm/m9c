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
. ./gen.sh          # runtime/gen is BUILT here, not found

gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c \
    ../gen/Text.c ../gen/Lex.c ../gen/Ast.c ../gen/Print.c \
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

for f in ../../corpus/*.m9 ../../museum/*.m9 ../../bench/*.m9; do
  t="../..${f#../..}"
  ( cd ../../host/fpc && ./semdump "$t" $DEPS ) > /tmp/sem_fpc.txt 2>/dev/null || true
  ( cd ../../host/fpc && "$M9" "$t" $DEPS ) > /tmp/sem_m9.txt 2>/dev/null || true
  if cmp -s /tmp/sem_fpc.txt /tmp/sem_m9.txt; then
    same=$((same+1))
  else
    diff_n=$((diff_n+1))
    if [ "$shown" -lt 3 ]; then
      echo "--- $(basename "$f"): oracle says what M9 does not yet"
      diff /tmp/sem_fpc.txt /tmp/sem_m9.txt | head -4
      shown=$((shown+1))
    fi
  fi
done

if [ "$diff_n" -ne 0 ]; then
  echo "semdiff: $same agree, $diff_n DIVERGE"
  exit 1
fi
echo "semdiff: $same files, diagnostics byte-identical to the oracle"
