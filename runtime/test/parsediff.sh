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
