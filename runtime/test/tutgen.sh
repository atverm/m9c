#!/bin/sh
# tutgen: RE-RECORD the tutorial's expected outputs.  Separate from
# tutdiff on purpose -- a gate that regenerates what it compares
# against cannot fail (the docgen/docdiff rule).  Run this after
# deliberately changing an example, read the diff, then commit both.
set -e
cd "$(dirname "$0")"
. ./gen.sh

gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c ../gen/Lex.c \
    ../gen/Ast.c ../gen/Parse.c ../gen/Print.c ../gen/Text.c \
    ../gen/Fmt.c ../gen/Sem.c ../gen/Gen.c ../gen/Doc.c ../gen/M9c.c -o m9c

M9C=$(pwd)/m9c
EXA=$(cd ../../docs/tutorial/examples && pwd)
RT=$(cd .. && pwd)
LIB=$(cd ../../corpus && pwd)
W=/tmp/m9tut-gen
rm -rf "$W"; mkdir -p "$W" "$EXA/expect"
. ./tutcommon.sh
for f in "$EXA"/C*.m9; do
  m=$(basename "$f" .m9)
  tut_build "$m" || exit 1
  tut_pre "$m"
  ( cd "$EXA" && "$W/$m" > "expect/$m.out" ) || exit 1
  echo "recorded expect/$m.out"
done
# the plot chapter's SVG is part of the expectation: deterministic
# bytes are the point being taught
cp /tmp/damped.svg "$EXA/expect/damped.svg"
echo "recorded expect/damped.svg"
cp /tmp/htm.svg "$EXA/expect/htm.svg"
echo "recorded expect/htm.svg"
