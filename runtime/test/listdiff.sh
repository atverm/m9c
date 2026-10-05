#!/bin/sh
# listdiff -- the hand-maintained module lists must agree.
#
# A corpus module is named by hand in gentest.pas, gendiff.sh,
# bootstrap.sh (MODS and deps_of), build.sh (LIBRARY, COMPILER) and
# tools/tutor/setup.sh (LIB), and four times a drift between them was
# found only by a later gate failing -- the last time (2026-09-11) by
# none at all, because the lexer golden was stale and every CI job
# waits on that one.  runtime/test/ListDiff.m9 states each rule with its
# reason and names every disagreement; a module deliberately left out
# of a list is excused THERE, by name and with a reason.
#
# ListDiff.m9 is an M9 script, run by `m9c --run` with the compiler this
# gate builds from runtime/gen like the others: an installed m9c may
# predate --run.  It replaced listdiff.py (2026-10-04) after the two
# printed the same lines over the tree and over a sabotage of each of
# the thirteen rules.
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found

gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/Lex.c ../gen/Ast.c ../gen/Parse.c ../gen/Print.c ../gen/Text.c ../gen/System.c \
    ../gen/Sem.c ../gen/Gen.c ../gen/Doc.c ../gen/Review.c ../gen/M9c.c -o m9c

M9RUNTIME="$(cd .. && pwd)" M9LIBRARY="$(cd ../../corpus && pwd)" ./m9c --run ListDiff.m9
