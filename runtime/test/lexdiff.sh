#!/bin/sh
# P5 stage-1 differential: the M9-compiled lexer against the FPC
# oracle, byte-compared over every corpus and museum file.
set -e
cd "$(dirname "$0")"
. ./gen.sh          # runtime/gen is BUILT here, not found
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Lex.c lexdump_m9.c \
    -o lexdump_m9
( cd ../../host/fpc && fpc -O2 lexdump.pas >/dev/null )
n=0
for f in ../../corpus/*.m9 ../../museum/*.m9; do
  ../../host/fpc/lexdump "$f" > /tmp/lex_fpc.txt
  ./lexdump_m9 "$f" > /tmp/lex_m9.txt
  cmp /tmp/lex_fpc.txt /tmp/lex_m9.txt || { echo "DIVERGES: $f"; exit 1; }
  n=$((n+1))
done
echo "lexdiff: $n files, token streams byte-identical to the oracle"
