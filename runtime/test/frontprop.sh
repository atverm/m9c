#!/bin/sh
# frontprop holds the M9 lexer, parser and printer to what must be true
# of every file, whatever the file says (docs/fpc-removal-plan.md,
# step 1).  It needs no expectation, so it runs over the files that
# change: corpus/, museum/ and the fixtures.
#
#   1. The file parses clean.
#   2. print (parse (x)) is a fixpoint: printing it and parsing the
#      print gives the same print.
#   3. The tokens of the print are the tokens of x, positions aside.
#      So the printer drops nothing and invents nothing.
#
# host/fpc/parsetest.pas checks the same three on the Pascal parser.
# Comments are not tokens: fmt.sh holds that m9fmt keeps every one.
# Scratch files go in a directory of this run's own.
TG=$(mktemp -d "${TMPDIR:-/tmp}/m9gate.XXXXXX")
trap 'rm -rf "$TG"' EXIT
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found
CF="-std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter -iquote .. -iquote ../gen"
gcc $CF ../m9rt.c ../gen/DynStr.c ../gen/Text.c ../gen/Lex.c lexdump_m9.c -o "$TG/lexdump"
gcc $CF ../m9rt.c ../gen/DynStr.c ../gen/Text.c ../gen/Lex.c ../gen/Ast.c \
    ../gen/DynUtf.c ../gen/Print.c ../gen/Parse.c parsedump_m9.c -o "$TG/parsedump"
n=0
for f in ../../corpus/*.m9 ../../museum/*.m9 frontfix/*.m9 frontfix/snap/*.m9 \
         tasktest.m9 ../../probes/task-*.m9 inrange/*.m9; do
  "$TG/parsedump" "$f" > "$TG/p1.m9" ||
    { echo "frontprop: $f does not parse clean"; exit 1; }
  "$TG/parsedump" "$TG/p1.m9" > "$TG/p2.m9" ||
    { echo "frontprop: the print of $f does not parse clean"; exit 1; }
  cmp -s "$TG/p1.m9" "$TG/p2.m9" ||
    { echo "frontprop: print (parse ()) is no fixpoint on $f:"; diff "$TG/p1.m9" "$TG/p2.m9" | head -6; exit 1; }
  "$TG/lexdump" "$f" | cut -d' ' -f2- > "$TG/t1.txt"
  "$TG/lexdump" "$TG/p1.m9" | cut -d' ' -f2- > "$TG/t2.txt"
  cmp -s "$TG/t1.txt" "$TG/t2.txt" ||
    { echo "frontprop: the print of $f has other tokens:"; diff "$TG/t1.txt" "$TG/t2.txt" | head -6; exit 1; }
  n=$((n+1))
done
# The control: a print that lost a token must be seen.  The gate drops
# one line of a print and asks its own third test.
"$TG/parsedump" frontfix/FxStmts.m9 > "$TG/p1.m9"
sed '/SIGNAL (g)/d' "$TG/p1.m9" > "$TG/cut.m9"
"$TG/lexdump" frontfix/FxStmts.m9 | cut -d' ' -f2- > "$TG/t1.txt"
"$TG/lexdump" "$TG/cut.m9" | cut -d' ' -f2- > "$TG/t2.txt"
if cmp -s "$TG/t1.txt" "$TG/t2.txt"; then
  echo "frontprop: a print with a statement cut out has the same tokens"; exit 1
fi
echo "frontprop: $n files parse clean, print to a fixpoint and keep their tokens"
