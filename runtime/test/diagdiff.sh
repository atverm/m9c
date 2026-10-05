#!/bin/sh
# diagdiff -- docs/diagnose.md must be what tools/MkDiagnose.m9 would
# generate from probes/ today.
#
# The message column of that table is read from the probes, which
# probediff.sh holds identical across both checkers; so this gate is
# what keeps the written explanation of every refusal attached to the
# refusal itself.  A probe added without an explanation fails here.
# Regenerate with:  M9LIBRARY=corpus tools/MkDiagnose.m9
#
# MkDiagnose.m9 is an M9 script, run by `m9c --run` with the compiler
# this gate builds from runtime/gen (an installed m9c may predate
# --run).  It replaced tools/mkdiagnose.py on 2026-10-04 after writing
# the same page and refusing the same drifts.
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found

gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c \
    ../gen/Lex.c ../gen/Ast.c ../gen/Parse.c ../gen/Print.c ../gen/Text.c ../gen/System.c \
    ../gen/Sem.c ../gen/Gen.c ../gen/Doc.c ../gen/Review.c ../gen/M9c.c -o m9c

M9RUNTIME="$(cd .. && pwd)" M9LIBRARY="$(cd ../../corpus && pwd)" \
  ./m9c --run ../../tools/MkDiagnose.m9 --check
