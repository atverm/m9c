#!/bin/sh
# P5 stage-1 differential: the M9-compiled lexer against the FPC
# oracle, byte-compared over every corpus and museum file.
# scratch files in a directory of this run's own: fixed /tmp names
# collided between two checkouts or two gates run at once (the compiler
# review's tier 3, 2026-10-22)
TG=$(mktemp -d "${TMPDIR:-/tmp}/m9gate.XXXXXX")
trap 'rm -rf "$TG"' EXIT
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Text.c ../gen/Lex.c lexdump_m9.c \
    -o lexdump_m9
( cd ../../host/fpc && fpc -O2 lexdump.pas >/dev/null )
n=0
for f in ../../corpus/*.m9 ../../museum/*.m9; do
  ../../host/fpc/lexdump "$f" > "$TG"/lex_fpc.txt
  ./lexdump_m9 "$f" > "$TG"/lex_m9.txt
  cmp "$TG"/lex_fpc.txt "$TG"/lex_m9.txt || { echo "DIVERGES: $f"; exit 1; }
  n=$((n+1))
done
# A #! FIRST LINE IS SKIPPED, by both, and only there (report par 2).
# The fixture's first token must be MODULE on line 2; a copy with the
# line moved below the heading must NOT lex clean -- `#` is not-equal
# and `!` no character M9 has -- so the skip is shown to be a rule
# about the first line and not a second comment syntax.
f=runfix/Shebang.m9
../../host/fpc/lexdump "$f" > "$TG"/lex_fpc.txt
./lexdump_m9 "$f" > "$TG"/lex_m9.txt
cmp "$TG"/lex_fpc.txt "$TG"/lex_m9.txt || { echo "DIVERGES: $f"; exit 1; }
[ "$(head -1 "$TG"/lex_m9.txt)" = "2:1 MODULE MODULE" ] ||
  { echo "lexdiff: the #! line was not skipped:"; head -2 "$TG"/lex_m9.txt; exit 1; }
{ sed -n 2p "$f"; sed -n 1p "$f"; sed -n '3,$p' "$f"; } > "$TG"/lex_late.m9
./lexdump_m9 "$TG"/lex_late.m9 > "$TG"/lex_m9.txt
../../host/fpc/lexdump "$TG"/lex_late.m9 > "$TG"/lex_fpc.txt
cmp "$TG"/lex_fpc.txt "$TG"/lex_m9.txt || { echo "DIVERGES: a #! below line 1"; exit 1; }
grep -q 'Error' "$TG"/lex_m9.txt ||
  { echo "lexdiff: a #! below line 1 lexed clean"; exit 1; }
n=$((n+1))
# A BYTE ORDER MARK IS SKIPPED, first and only first (the review's F6:
# it was `unexpected character 0xff', its low byte); a CR no LF follows
# ENDS A LINE (a CR-only file was one line).  Made here, so the tree
# holds no file of control bytes.
printf '\357\273\277MODULE Bom ;\nBEGIN\nEND Bom.\n' > "$TG"/bom.m9
printf 'MODULE Bom ; \357\273\277\nBEGIN\nEND Bom.\n' > "$TG"/bomlate.m9
printf 'MODULE Cr ;\rVAR x : I64 ;\rBEGIN\r  x := 1\rEND Cr.\r' > "$TG"/cr.m9
for f in "$TG"/bom.m9 "$TG"/bomlate.m9 "$TG"/cr.m9; do
  ../../host/fpc/lexdump "$f" > "$TG"/lex_fpc.txt
  ./lexdump_m9 "$f" > "$TG"/lex_m9.txt
  cmp "$TG"/lex_fpc.txt "$TG"/lex_m9.txt || { echo "DIVERGES: $(basename $f)"; diff "$TG"/lex_fpc.txt "$TG"/lex_m9.txt | head -4; exit 1; }
  n=$((n+1))
done
./lexdump_m9 "$TG"/bom.m9 > "$TG"/lex_m9.txt
[ "$(head -1 "$TG"/lex_m9.txt)" = "1:1 MODULE MODULE" ] ||
  { echo "lexdiff: a leading byte order mark was not skipped:"; head -2 "$TG"/lex_m9.txt; exit 1; }
./lexdump_m9 "$TG"/bomlate.m9 | grep -q 'U+FEFF' ||
  { echo "lexdiff: a byte order mark after line start lexed clean or unnamed"; exit 1; }
./lexdump_m9 "$TG"/cr.m9 | grep -q '^5:1 END' ||
  { echo "lexdiff: CR-only line ends were not counted:"; ./lexdump_m9 "$TG"/cr.m9 | tail -3; exit 1; }
echo "lexdiff: $n files, token streams byte-identical to the oracle"
