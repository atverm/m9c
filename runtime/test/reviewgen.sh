#!/bin/sh
# Re-record runtime/test/review/*.txt, the pages reviewdiff compares
# against: `m9c --review' of every module build.sh installs.
#
# Separate from reviewdiff on purpose: a gate that regenerates what it
# compares against cannot fail.  Run this when a module gains or loses
# a named pool, a KEPT parameter, a foreign procedure -- anything the
# page counts -- READ THE DIFF, and commit it with the change: the
# diff is the review the page exists for.  The recorded page carries
# no line numbers (lib/reviewnorm.sh says why), so an edit that only
# moves lines needs no re-recording and makes no diff.
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh
. ./lib/reviewnorm.sh
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/Lex.c ../gen/Ast.c ../gen/Parse.c ../gen/Print.c ../gen/Text.c ../gen/System.c \
    ../gen/Sem.c ../gen/Gen.c ../gen/Doc.c ../gen/Review.c ../gen/M9c.c -o m9c
M9C=$(pwd)/m9c
SRC=$(cd ../../corpus && pwd)
GOLD=$(pwd)/review
mkdir -p "$GOLD"
export M9RUNTIME=$(cd .. && pwd)
export M9LIBRARY=$SRC
n=0
# build.sh's LIBRARY, the range closing on the line that ends the
# string (docgen.sh says what happened when it closed on a name)
for m in $(sed -n '/^LIBRARY=/,/"$/p' ../../build.sh |
           sed 's/LIBRARY="//; s/"$//; s/\\$//' | tr -s ' \n' ' '); do
  d=""
  [ "$m" = HttpServer ] && d="$SRC/Http.m9 $SRC/DynStr.m9"
  # shellcheck disable=SC2086
  "$M9C" --review "$SRC/$m.m9" $d > "$GOLD/$m.raw" ||
    { echo "reviewgen: m9c --review refused $m"; rm -f "$GOLD/$m.raw"; exit 1; }
  review_norm < "$GOLD/$m.raw" > "$GOLD/$m.txt"
  rm -f "$GOLD/$m.raw"
  n=$((n + 1))
done
echo "reviewgen: $n review pages written to runtime/test/review"
