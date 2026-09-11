#!/bin/sh
# listdiff -- the hand-maintained module lists must agree.
#
# A corpus module is named by hand in gentest.pas, gendiff.sh,
# bootstrap.sh (MODS and deps_of), build.sh (LIBRARY, COMPILER) and
# tools/tutor/setup.sh (LIB), and four times a drift between them was
# found only by a later gate failing -- the last time (2026-09-11) by
# none at all, because the lexer golden was stale and every CI job
# waits on that one.  runtime/test/listdiff.py states each rule with its
# reason and names every disagreement; a module deliberately left out
# of a list is excused THERE, by name and with a reason.
set -e
cd "$(dirname "$0")/../.."
python3 runtime/test/listdiff.py
