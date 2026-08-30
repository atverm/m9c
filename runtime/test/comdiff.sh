#!/bin/sh
# The comment side channel, differential.
#
# lexdiff compares TOKEN streams and must keep doing exactly that:
# "token streams byte-identical to the oracle" is a claim worth
# keeping literally true, and comments are not tokens.  So the side
# channel gets its own pair of dumps and its own gate.
#
# The two lexers are not shaped alike and need not be: TLexer is a
# class and collects per instance, while corpus/Lex.m9's Lexer is a
# record whose Init takes no pool, so it keeps one module-level list
# in HEAP.  What is held identical is the OUTPUT -- position, extent
# and verbatim text of every comment in every corpus and museum file.
set -e
cd "$(dirname "$0")"
. ./gen.sh          # runtime/gen is BUILT here, not found
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Lex.c comdump_m9.c \
    -o comdump_m9
( cd ../../host/fpc && fpc -O2 comdump.pas >/dev/null )
n=0
c=0
for f in ../../corpus/*.m9 ../../museum/*.m9; do
  ../../host/fpc/comdump "$f" > /tmp/com_fpc.txt
  ./comdump_m9 "$f" > /tmp/com_m9.txt
  cmp /tmp/com_fpc.txt /tmp/com_m9.txt || { echo "DIVERGES: $f"; exit 1; }
  n=$((n+1))
  c=$((c + $(sed -n 's/^comments=//p' /tmp/com_fpc.txt)))
done
echo "comdiff: $n files, $c comments byte-identical to the oracle"
