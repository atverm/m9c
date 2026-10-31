#!/bin/sh
# listdiff demands that the hand-maintained module lists agree.
#
# A corpus module is named by hand in gentest.pas, gendiff.sh,
# bootstrap.sh (MODS and deps_of), build.sh (LIBRARY, COMPILER) and
# tools/tutor/setup.sh (LIB).  Four times a drift between them was
# found only by a later gate failing.  The last time (2026-09-11) no
# gate found it at all, because the lexer golden was stale and every
# CI job waits on that one.  runtime/test/ListDiff.m9 states each rule
# with its reason and names every disagreement.  A module deliberately
# left out of a list is excused THERE, by name and with a reason.
#
# ListDiff.m9 is an M9 script, run by `m9c --run` with the compiler this
# gate builds from runtime/gen like the others: an installed m9c may
# predate --run.  It replaced listdiff.py (2026-10-04) after the two
# printed the same lines over the tree and over a sabotage of each of
# the thirteen rules.
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found

M9CNEW=$(mktemp -d)
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c $COMPILERC -o "$M9CNEW/m9c"
# Replace m9c only when it differs.  So a gate in another lane running
# m9c keeps its file, and --run's cache keeps its entries; that cache's
# key holds m9c's mtime.
if cmp -s "$M9CNEW/m9c" m9c; then rm -r "$M9CNEW"; else mv -f "$M9CNEW/m9c" m9c; rmdir "$M9CNEW"; fi

M9RUNTIME="$(cd .. && pwd)" M9LIBRARY="$(cd ../../corpus && pwd)" ./m9c --run ListDiff.m9
