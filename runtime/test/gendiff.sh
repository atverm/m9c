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
run Faults
run Mat Math Faults
run Stats Math Bits Faults
run System Io DynStr Text
run Json DynStr
run Http DynStr Io
run HttpServer DynStr Http
run OpenApi HttpServer DynStr
run ApiSpec DynStr
run Arrow DynStr Faults
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
run Bits
run Sort Math
run Csv DynStr Io Time
run Delim DynStr Io
run Zip DynStr Io
run Frame Csv Io Math DynStr Fmt Time NetCDF Faults
run Parquet Frame Io DynStr Csv Math Fmt Time NetCDF Faults
run NetCDF DynStr Faults
run Grib DynStr Faults
run Syslog DynStr
run Logger DynStr Fmt Io Syslog Time
run Hello Io DynStr
run Concat Io DynStr
run Narrow Io
run ProcUse Io
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
# KindUse is a gendiff-only fixture too: a CASE RECORD declared in
# ANOTHER module (Csv.Kind), constructed and CASEd from here -- the
# two forms both generators refused until 2026-09-15 while Csv, Frame
# and Plot routed around them with integer codes.  The grep proves the
# constructor was EMITTED: two generators refusing together would also
# agree byte for byte.
run KindUse Csv Io DynStr Time
grep -q 'Csv_Kind_Real' /tmp/gen_fpc.txt \
  || { echo "KindUse: Csv.Kind.Real NOT generated -- the cross-module constructor gone from BOTH generators?"; exit 1; }
# EnumUse/Palette are gendiff-only fixtures too: an ENUMERATION, the
# Pascal-faced payload-less case record.  The grep proves the tag was
# emitted; two generators refusing together would also agree.
run Palette
run EnumUse Palette Io
grep -q 'Palette_Hue_Cool' /tmp/gen_fpc.txt \
  || { echo "EnumUse: Palette.Hue.Cool NOT generated -- enum construction gone from BOTH generators?"; exit 1; }
# EnumUse.AllHues is a FOR over the enumeration; the loop runs on the
# tag, `c.tag <= ...; c.tag++`.  The grep proves the loop was emitted:
# two generators both refusing FOR-over-enum would still agree byte
# for byte (docs/enum-plan.md, part 2).
grep -q '\.tag <= ' /tmp/gen_fpc.txt \
  || { echo "EnumUse: FOR over the enumeration NOT generated -- the tag loop gone from BOTH generators?"; exit 1; }
# EnumUse.Tables indexes ARRAY Colour OF T by the enumeration: the
# subscript is the member's tag, a.v[(k).tag], with no runtime bounds
# check because the index IS the type.  The grep proves that emit:
# two generators both refusing enum-indexed arrays would still agree.
grep -q '\.v\[(' /tmp/gen_fpc.txt \
  || { echo "EnumUse: enum-indexed array NOT generated -- a.v[(k).tag] gone from BOTH generators?"; exit 1; }
# EnumUse compares enum values with = / #, which is a `.tag` compare,
# not a struct == (which gcc refuses).  The grep proves it.
grep -q '\.tag == \|\.tag != ' /tmp/gen_fpc.txt \
  || { echo "EnumUse: enum = / # NOT a tag compare -- struct == gone from BOTH generators?"; exit 1; }
# Every module runs its imports' initialisers before its own body:
# `Mod_m9init (err); if (err->exc) goto L_ret;`.  The grep proves the
# init machinery is emitted (a library body is RUN, not dropped);
# two generators both dropping it would still agree byte for byte.
grep -q '_m9init (err); if (err->exc) goto L_ret;' /tmp/gen_fpc.txt \
  || { echo "EnumUse: module init NOT generated -- a library body would be silently dropped?"; exit 1; }
echo "gendiff: $n modules, generated C byte-identical to the oracle"
