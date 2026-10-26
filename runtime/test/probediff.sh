#!/bin/sh
# The two checkers against each other on the NEGATIVE material.
#
# semdiff.sh compares them over corpus/ and museum/, which is mostly
# clean code -- agreeing about a program with no errors in it is the
# easy half.  This compares them over probes/, where every file is
# wrong on purpose, and requires the diagnostics to be identical line
# for line: same text, same line:col, same order.
#
# It is the gate for porting the checker's expression typing into
# Sem.m9.  Until that is done it reports how many probes the two
# checkers disagree about, which is the worklist.
# scratch files in a directory of this run's own: fixed /tmp names
# collided between two checkouts or two gates run at once (the compiler
# review's tier 3, 2026-10-22)
TG=$(mktemp -d "${TMPDIR:-/tmp}/m9gate.XXXXXX")
trap 'rm -rf "$TG"' EXIT
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found
P=../../probes

gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Lex.c \
    ../gen/Ast.c ../gen/Parse.c ../gen/DynUtf.c ../gen/Print.c ../gen/Text.c \
    ../gen/Sem.c semdump_m9.c -o semdump_m9
( cd ../../host/fpc && fpc -O2 semdump.pas >/dev/null )

n=0; bad=0
for f in "$P"/*.m9; do
  b=$(basename "$f")
  ( cd ../../host/fpc && ./semdump "../../probes/$b" ) > "$TG"/probe_fpc.txt 2>&1
  ( cd ../../host/fpc && ../../runtime/test/semdump_m9 "../../probes/$b" ) \
    > "$TG"/probe_m9.txt 2>&1
  n=$((n + 1))
  if ! cmp -s "$TG"/probe_fpc.txt "$TG"/probe_m9.txt; then
    bad=$((bad + 1))
    if [ -n "$VERBOSE" ]; then
      echo "--- $b"
      diff "$TG"/probe_fpc.txt "$TG"/probe_m9.txt | sed 's/^/    /' | head -8
    else
      echo "DIVERGES: $b"
    fi
  fi
done

if [ "$bad" -ne 0 ]; then
  echo "probediff: $bad of $n probes disagree"
  exit 1
fi
echo "probediff: $n probes, diagnostics byte-identical to the oracle"
