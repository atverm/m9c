#!/bin/sh
# checkfuzz: the two checkers held to each other on programs NOBODY
# WROTE (2026-10-11).  semdiff and probediff compare them on the corpus
# and the probes, which were written to pass or to fail one way, and two
# checkers agree easily there: a RAISES hole in m9c's checker (a call in
# a condition, a CASE selector or a FOR bound counted nothing) lived from
# 0.14.0 at least, and the first run of this found a second (`t := (s)'
# did not move s on the M9 side).  tools/CheckFuzz.m9 mutates every
# probe, museum piece and genforms program one edit at a time -- a line
# deleted, a RAISES clause or a KEPT/RO/VAR/OWN/SHARED/NOT/`IN pool'
# dropped -- and runs both drivers on each mutant.
#
# RED when the two disagree on a VERDICT: one accepts a mutant the other
# refuses.  A difference only in wording or order on a program both
# refuse (cascades after a first error) is printed, not failed.
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found

gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Lex.c \
    ../gen/Ast.c ../gen/Parse.c ../gen/DynUtf.c ../gen/Print.c ../gen/Text.c \
    ../gen/Sem.c semdump_m9.c -o semdump_m9
( cd ../../host/fpc && fpc -O2 semdump.pas >/dev/null )

. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C

R=$(cd ../.. && pwd)
OUT=${TMPDIR:-/tmp}/checkfuzz.$$
rm -rf "$OUT"
trap 'rm -rf "$OUT"' EXIT
cd "$R"
st=0
M9RUNTIME="$R/runtime" M9LIBRARY="$R/corpus" M9CACHE="$OUT/cache" \
  "$M9C" --run tools/CheckFuzz.m9 --fpc="$R/host/fpc/semdump" \
    --m9="$R/runtime/test/semdump_m9" --out="$OUT/found" \
    probes/*.m9 museum/*.m9 runtime/test/genforms/*.m9 > "$OUT.log" 2>&1 || st=$?
grep 'VERDICT DIFFERS\|FINDINGS DIFFER' "$OUT.log" || :
tail -n 1 "$OUT.log"
rm -f "$OUT.log"
exit $st
