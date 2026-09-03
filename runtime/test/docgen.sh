#!/bin/sh
# Regenerate docs/modules/*.md, the goldens docdiff compares against.
#
# Separate from docdiff on purpose: a gate that regenerates what it
# compares against cannot fail.  Run this when a doc comment changes,
# in the same commit as the change, exactly as lextest.golden is.
set -e
cd "$(dirname "$0")"
. ./gen.sh
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/Lex.c ../gen/Ast.c ../gen/Parse.c ../gen/Print.c ../gen/Text.c \
    ../gen/Fmt.c ../gen/Sem.c ../gen/Gen.c ../gen/Doc.c ../gen/M9c.c -o m9c
M9C=$(pwd)/m9c
SRC=$(cd ../../corpus && pwd)
GOLD=$(cd ../.. && pwd)/docs/modules
mkdir -p "$GOLD"
export M9RUNTIME=$(cd .. && pwd)
export M9LIBRARY=$SRC
n=0
# The list is build.sh's LIBRARY, and the range closes on the line that
# ends the string -- NOT on a module name: closed on `Plot ZarrStore"`,
# it silently ran to the end of the file when 0.5.0 appended Lsp and
# M9fmt, and `mkdir` became a module (2026-09-03, both branches red).
for m in $(sed -n '/^LIBRARY=/,/"$/p' ../../build.sh |
           sed 's/LIBRARY="//; s/"$//; s/\\$//' | tr -s ' \n' ' '); do
  d=""
  [ "$m" = HttpServer ] && d="$SRC/Http.m9 $SRC/DynStr.m9"
  # shellcheck disable=SC2086
  ( cd "$GOLD" && "$M9C" --doc "$SRC/$m.m9" $d )
  n=$((n + 1))
done
echo "docgen: $n module references written to docs/modules"
