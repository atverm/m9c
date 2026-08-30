#!/bin/sh
# P5 stage-1 differential: the M9-compiled parser+printer against
# the FPC oracle, byte-compared over every corpus and museum file.
set -e
cd "$(dirname "$0")"
. ./gen.sh          # runtime/gen is BUILT here, not found
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Lex.c ../gen/Ast.c \
    ../gen/Print.c ../gen/Parse.c parsedump_m9.c -o parsedump_m9
( cd ../../host/fpc && fpc -O2 parsedump.pas >/dev/null )
n=0
for f in ../../corpus/*.m9 ../../museum/*.m9; do
  ../../host/fpc/parsedump "$f" > /tmp/parse_fpc.txt
  ./parsedump_m9 "$f" > /tmp/parse_m9.txt
  cmp /tmp/parse_fpc.txt /tmp/parse_m9.txt || { echo "DIVERGES: $f"; exit 1; }
  n=$((n+1))
done
echo "parsediff: $n files, print(parse()) byte-identical to the oracle"

# AND THE BROKEN FILES, WHICH THE LOOP ABOVE CANNOT SEE.  Every file
# it compares parses CLEAN, so it holds the two parsers to the same
# TREES and says nothing about the same DIAGNOSTICS -- and the M9
# parser had none to compare until 2026-08-30: it counted its errors
# and m9c printed `4 parse errors in Bad.m9`, no line, no message,
# which cost a bisect every time a program was written outside the
# corpus.  parseprobes/ is one deliberately broken file per message
# family, and both parsers must answer the same text, line and column.
( cd ../../host/fpc && fpc -O2 p1.pas >/dev/null )
# THE COMPILER IS BUILT HERE, from the runtime/gen this gate just
# regenerated -- an m9c left by an earlier run is the stale-artifact
# trap gen.sh exists to close, and it sprang: a leftover from before
# the parser had messages printed the old bare count and the gate
# reported a divergence that was a year of nothing.  Absolute,
# because the comparisons run from the repository root.
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter     -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c     ../gen/Lex.c ../gen/Ast.c ../gen/Parse.c ../gen/Print.c ../gen/Text.c     ../gen/Fmt.c ../gen/Sem.c ../gen/Gen.c ../gen/Doc.c ../gen/M9c.c -o m9c
M9C=$(pwd)/m9c
np=0
for f in ../../parseprobes/*.m9; do
  ( cd ../.. && host/fpc/p1 "${f#../../}" ) > /tmp/perr_fpc.txt 2>&1 || true
  ( cd ../.. && M9LIBRARY=$(pwd)/corpus M9RUNTIME=$(pwd)/runtime \
      "$M9C" -c "${f#../../}" ) > /tmp/perr_m9.txt 2>&1 || true
  # a probe that stopped being broken proves nothing
  grep -q ': parse: ' /tmp/perr_fpc.txt ||
    { echo "parsediff: $f no longer has a parse error"; exit 1; }
  cmp -s /tmp/perr_fpc.txt /tmp/perr_m9.txt ||
    { echo "DIAGNOSTICS DIVERGE: $f"; diff /tmp/perr_fpc.txt /tmp/perr_m9.txt | head -6; exit 1; }
  np=$((np+1))
done
echo "parsediff: $np broken files, both parsers say the same thing"
