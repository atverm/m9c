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
. ./lib/gen.sh          # runtime/gen is BUILT here, not found
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
    ../gen/Parse.c ../gen/Text.c ../gen/Gen.c gendump_m9.c -o gendump_m9
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
run Stats Math Bits Faults Sort
run System Io DynStr Text
run Json DynStr
run Http DynStr Io
run Sparql DynStr Io Http Json Text
run Rdf DynStr Fmt Json Text Xml
run Regex DynStr Text
run Map DynStr Faults Fmt Math Plot Stats
run Xml DynStr Fmt Text
run Hash Bits Faults
run Smtp Time DynStr Fmt Text
run Rsa Hash Text
run HttpServer DynStr Http Io Logger Zip
run OpenApi HttpServer DynStr
run ApiSpec DynStr
run Arrow DynStr Faults
run ZarrStore DynStr Json Http Io
run Zarr DynStr Json Io Math
run Plot DynStr Mat Math Faults Fmt Text Time
run Lex DynStr
run Ast
run Print Ast DynStr
run Parse Ast Lex DynStr
run Dict
run Fmt
run Io DynStr
run Time DynStr Fmt
run Pg DynStr Fmt Time
run Text DynStr
run Math
run Bits
run Sort Math
run Check Io Fmt Math Text
run Arrays Faults Math
run Numeric Faults Math
run Csv DynStr Io Time
run Delim DynStr Io
run Zip DynStr Io Bits
run Png Faults Zip Math DynStr
run Frame Csv Io Math DynStr Fmt Time NetCDF Faults Sort Stats Text
run Parquet Frame Io DynStr Csv Math Fmt Time NetCDF Faults
run NbCells Parquet Frame Io DynStr Csv Math Fmt Time NetCDF Faults
run NbShow Frame Io DynStr Fmt Text Time
run NetCDF DynStr Faults
run Grib DynStr Faults
run Syslog DynStr
run Logger DynStr Fmt Io Syslog Time
run Hello Io DynStr
run Concat Io DynStr
run Narrow Io
run ProcUse Io
# AggUse is the constant table (par 2.2.4).  The grep proves the table
# was EMITTED as const data: two generators refusing the aggregate
# together would also agree byte for byte.
run AggUse Io
grep -q 'static const m9_arr_5_int64_t Primes_k = { {' /tmp/gen_fpc.txt \
  || { echo "AggUse: the constant table NOT generated -- the aggregate gone from BOTH generators?"; exit 1; }
grep -q 'static const m9_arr_3_AggUse_Status Statuses_k = { {' /tmp/gen_fpc.txt \
  || { echo "AggUse: the record table NOT generated -- the record aggregate gone from BOTH generators?"; exit 1; }
# ExportDef and ExportUse are exported module variables (decision 28).
# The greps prove the export and its use were EMITTED: the exporter's
# constant pointer, the importer's write through it -- two generators
# that both dropped the feature would also agree byte for byte.
run ExportDef Io Fmt
grep -q '^int64_t \* const ExportDef_count = &count;$' /tmp/gen_fpc.txt \
  || { echo "ExportDef: the exported pointer NOT generated"; exit 1; }
run ExportUse ExportDef Io Fmt
grep -q '(\*ExportDef_count)' /tmp/gen_fpc.txt \
  || { echo "ExportUse: the write through ExportDef_count NOT generated"; exit 1; }
# ShareUse is the assignment of a raising call (par 5): the answer
# into a temporary, the error slot read, THEN the store and the share
# copy.  The grep holds the order; two generators storing first
# together would also agree byte for byte.
run ShareUse Io
grep -q -A2 '__typeof__(b) m9v = ShareUse_Make (n, err);' /tmp/gen_fpc.txt \
  && grep -A2 '__typeof__(b) m9v = ShareUse_Make (n, err);' /tmp/gen_fpc.txt | grep -q 'if (err->exc) goto' \
  && grep -q 'b = ((__typeof__(b)) m9_share_copy (m9v));' /tmp/gen_fpc.txt \
  || { echo "ShareUse: a raising call's answer is stored before its error slot is read -- in BOTH generators"; exit 1; }
# ... and a raising call nested as an ARGUMENT is hoisted into a guarded
# temporary before the enclosing call (par 5, 2026-10-08)
grep -q -A1 '{ __typeof__(ShareUse_Count (n, err)) m9a[0-9]* = ShareUse_Count (n, err);' /tmp/gen_fpc.txt \
  && grep -A1 '{ __typeof__(ShareUse_Count (n, err)) m9a[0-9]* = ShareUse_Count (n, err);' /tmp/gen_fpc.txt | grep -q 'if (err->exc) goto' \
  && grep -q 'ShareUse_Use (m9a[0-9]*, err);' /tmp/gen_fpc.txt \
  || { echo "ShareUse: a raising call nested as an argument is not guarded before the enclosing call -- in BOTH generators"; exit 1; }
# F32 of a double is a checked conversion, and a U64 literal past 2^63
# is spelled UINT64_C (2026-10-08)
grep -q 'm9_f32_f64 (x, err)' /tmp/gen_fpc.txt \
  || { echo "ShareUse: F32 of a double is not the checked conversion -- in BOTH generators"; exit 1; }
grep -q 'm9_gridof (m9t[0-9]*\.len, m9t[0-9]*n, 2, m9t[0-9]*r\.n, m9t[0-9]*r\.s, err);' /tmp/gen_fpc.txt \
  || { echo "ShareUse: GRID (s, n0, n1) is not laid over the slice through m9_gridof -- in BOTH generators"; exit 1; }
grep -q 'static double y0_;' /tmp/gen_fpc.txt \
  || { echo "ShareUse: a module variable named y0 is not escaped from libm's Bessel function -- in BOTH generators"; exit 1; }
grep -q '100u, 233u, 106u, 224u, 32u' /tmp/gen_fpc.txt \
  || { echo "ShareUse: a string literal beyond ASCII is not emitted as its scalars -- in BOTH generators"; exit 1; }
grep -q 'int64_t i = err->i\[0\];' /tmp/gen_fpc.txt && grep -q 'int64_t n = err->i\[1\];' /tmp/gen_fpc.txt \
  || { echo "ShareUse: IndexError's (index, length) are not bound from err->i -- in BOTH generators"; exit 1; }
grep -q 'some = (o != NULL);' /tmp/gen_fpc.txt && grep -q 'none = (o == NULL);' /tmp/gen_fpc.txt \
  || { echo "ShareUse: IS SOME / IS NONE as an expression is not a NULL test -- in BOTH generators"; exit 1; }
grep -q 'case ShareUse_Store_Irods:' /tmp/gen_fpc.txt \
  || { echo "ShareUse: a CASE label spelled Store.Irods is not its member's case -- in BOTH generators"; exit 1; }
grep -q 'UINT64_C(18446744073709551615)' /tmp/gen_fpc.txt \
  || { echo "ShareUse: a U64 literal past 2^63 is not UINT64_C -- in BOTH generators"; exit 1; }
run Sem Ast DynStr Print Text
run Doc Ast DynStr Text Print Lex
run Review Ast DynStr Text
run M9c Io Ast Parse Gen Sem DynStr Doc Review Lex System
run Gen Ast DynStr Text
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
