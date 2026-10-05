#!/bin/sh
# P5 stage-1 differential: the M9-compiled lexer against the FPC
# oracle, byte-compared over every corpus and museum file.
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found
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
# A #! FIRST LINE IS SKIPPED, by both, and only there (report par 2).
# The fixture's first token must be MODULE on line 2; a copy with the
# line moved below the heading must NOT lex clean -- `#` is not-equal
# and `!` no character M9 has -- so the skip is shown to be a rule
# about the first line and not a second comment syntax.
f=runfix/Shebang.m9
../../host/fpc/lexdump "$f" > /tmp/lex_fpc.txt
./lexdump_m9 "$f" > /tmp/lex_m9.txt
cmp /tmp/lex_fpc.txt /tmp/lex_m9.txt || { echo "DIVERGES: $f"; exit 1; }
[ "$(head -1 /tmp/lex_m9.txt)" = "2:1 MODULE MODULE" ] ||
  { echo "lexdiff: the #! line was not skipped:"; head -2 /tmp/lex_m9.txt; exit 1; }
{ sed -n 2p "$f"; sed -n 1p "$f"; sed -n '3,$p' "$f"; } > /tmp/lex_late.m9
./lexdump_m9 /tmp/lex_late.m9 > /tmp/lex_m9.txt
../../host/fpc/lexdump /tmp/lex_late.m9 > /tmp/lex_fpc.txt
cmp /tmp/lex_fpc.txt /tmp/lex_m9.txt || { echo "DIVERGES: a #! below line 1"; exit 1; }
grep -q 'Error' /tmp/lex_m9.txt ||
  { echo "lexdiff: a #! below line 1 lexed clean"; exit 1; }
n=$((n+1))
echo "lexdiff: $n files, token streams byte-identical to the oracle"
