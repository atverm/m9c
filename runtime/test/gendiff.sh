#!/bin/sh
# P5 stage-2 differential: the M9-compiled generator against the FPC
# oracle, byte-compared over every corpus module -- including Gen.m9
# generating itself.  The dep lists must match gentest.pas exactly.
set -e
cd "$(dirname "$0")"
# runtime/gen IS THE BOOTSTRAP C and is checked in, so a corpus change
# that forgets to regenerate it ships a compiler that disagrees with its
# own source: 64ac53f committed Io.m9 [REENTRANT] and left Io.c gated.
# What was on disk BEFORE this regeneration must therefore equal what
# comes out of it -- in CI that is HEAD, locally the tree about to be
# committed.  The first run after a corpus edit fails ONCE and names
# the files that moved; stage them and run again (lextest.golden's
# rule).  A run from a DELETED runtime/gen has nothing to compare and
# says so, because that is how the whole suite is meant to be run.
if [ -d ../gen ]; then
  GENWAS=$(mktemp -d); cp -r ../gen/. "$GENWAS"/
else
  GENWAS=
fi
. ./gen.sh          # runtime/gen is BUILT here, not found
if [ -n "$GENWAS" ]; then
  stale=$(diff -rq "$GENWAS" ../gen 2>&1 || :)
  rm -rf "$GENWAS"
  if [ -n "$stale" ]; then
    echo "gendiff: runtime/gen was STALE -- commit the regenerated files:"
    echo "$stale" | sed "s|$GENWAS/||; s|^|  |"
    exit 1
  fi
else
  echo "gendiff: runtime/gen was absent, nothing to hold it to"
fi
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Lex.c ../gen/Ast.c \
    ../gen/Parse.c ../gen/Gen.c gendump_m9.c -o gendump_m9
( cd ../../host/fpc && fpc -O2 gendump.pas >/dev/null )
n=0
run () {
  m=$1; shift
  ( cd ../../host/fpc && ./gendump "$m" "$@" ) > /tmp/gen_fpc.txt
  ( cd ../../host/fpc && ../../runtime/test/gendump_m9 "$m" "$@" ) \
    > /tmp/gen_m9.txt
  cmp /tmp/gen_fpc.txt /tmp/gen_m9.txt || { echo "DIVERGES: $m"; exit 1; }
  n=$((n+1))
}
run DynStr
run Mat Math
run Stats Math
run System Io DynStr Text
run Json DynStr
run Http DynStr Io
run HttpServer DynStr Http
run OpenApi HttpServer DynStr
run ApiSpec DynStr
run Arrow DynStr
run ZarrStore DynStr Json Http
run Zarr DynStr Json Io Math
run Plot DynStr Mat
run Lex DynStr
run Ast
run Print Ast DynStr
run Parse Ast Lex DynStr
run Dict
run Fmt
run Io DynStr
run Time DynStr Fmt
run Text DynStr
run Math
run Csv DynStr Io Time
run Delim DynStr Io
run Zip DynStr Io
run Frame Csv Io Math DynStr Fmt Time NetCDF
run Parquet Frame Io DynStr Csv Math Fmt Time NetCDF
run NetCDF DynStr
run Grib DynStr
run Syslog DynStr
run Logger DynStr Fmt Io Syslog Time
run Hello Io DynStr
run Concat Io DynStr
run Sem Ast DynStr Print Text
run Doc Ast DynStr Text Print Lex
run M9c Io Ast Parse Gen Sem DynStr Doc Lex System
run Gen Ast DynStr
run Diag DynStr Io Lex
# LibmGate is a gendiff-only fixture (not in gentest.pas / runtime/gen):
# 96 locals named after the libm functions CN escapes.  The byte-compare
# above catches a ONE-SIDED edit to the two IsLibM lists; the grep proves
# the escaping is PRESENT, not that both generators dropped it together.
run LibmGate
grep -q 'float cos_' /tmp/gen_fpc.txt \
  || { echo "LibmGate: libm names NOT escaped -- IsLibM gone from BOTH generators?"; exit 1; }
echo "gendiff: $n modules, generated C byte-identical to the oracle"
