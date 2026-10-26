#!/bin/sh
# The generator held to what it must write, byte for byte, over every
# corpus module -- including Gen.m9 generating itself: the checked-in
# runtime/gen, and gold/c/ for the fixtures runtime/gen does not hold.
# It was the FPC oracle until 2026-10-22 (M9Gen.pas frozen, Alex;
# docs/twin-plan.md).  The dep lists must match gentest.pas exactly.
# scratch files in a directory of this run's own: fixed /tmp names
# collided between two checkouts or two gates run at once (the compiler
# review's tier 3, 2026-10-22)
TG=$(mktemp -d "${TMPDIR:-/tmp}/m9gate.XXXXXX")
trap 'rm -rf "$TG"' EXIT
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
    ../gen/Parse.c ../gen/Text.c ../gen/Print.c ../gen/Sem.c ../gen/DynUtf.c ../gen/Gen.c \
    gendump_m9.c -o gendump_m9
# WHAT THE GENERATOR MUST WRITE (2026-10-22, M9Gen.pas frozen): a
# module's checked-in runtime/gen/M.h and M.c -- which the review of a
# change reads as a diff, as it reads the review pages -- or, for a
# fixture not in runtime/gen, its golden under gold/c/ (re-recorded by
# gengen.sh).  Until then the Pascal generator's output, byte for byte.
n=0
run () {
  m=$1; shift
  if [ -f ../gen/$m.c ]; then
    { cat ../gen/$m.h; echo '==== M9GEN SPLIT ===='; cat ../gen/$m.c; } > "$TG"/gen_want.txt
  elif [ -f gold/c/$m.txt ]; then
    cp gold/c/$m.txt "$TG"/gen_want.txt
  else
    echo "gendiff: $m is in neither runtime/gen nor gold/c -- run gengen.sh"; exit 1
  fi
  ( cd ../../host/fpc && ../../runtime/test/gendump_m9 "$m" "$@" ) \
    > "$TG"/gen_m9.txt
  cmp "$TG"/gen_want.txt "$TG"/gen_m9.txt || { echo "DIVERGES: $m"; diff "$TG"/gen_want.txt "$TG"/gen_m9.txt | head -6; exit 1; }
  n=$((n+1))
}
run DynStr
run Faults
run Mat Math Faults
run Stats Math Bits Faults Sort
run System Io DynStr Text
run Json DynStr
run JsonUtf DynStr Text
run Chars Bits Faults Text
run DynUtf
run Http DynStr Io
run Sparql DynStr Io Http Json Text
run Rdf DynStr Fmt Json Text Xml
run Regex DynStr Text
run Map DynStr Faults Fmt Math Plot Stats Text
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
run Lex DynStr Text
run Ast
run Print Ast DynUtf Text
run Parse Ast Lex Text
run Dict
run Fmt
run Io DynStr
run Time DynStr Fmt
run Pg DynStr Fmt Time
run Text DynStr
run Math
run Bits
run Sort Math
run Seq Sort Text
run Check Io Fmt Math Text
run Arrays Faults Math
run Numeric Faults Math
run Csv DynStr Io Time
run Delim DynStr Io
run Zip DynStr Io Bits
run Png Faults Zip Math DynStr
run Frame Csv Io Math DynStr Fmt Time NetCDF Faults Sort Stats Text
run Parquet Frame Io DynStr Csv Math Fmt Time NetCDF Faults Zip Bits
run NbCells Parquet Frame Io DynStr Csv Math Fmt Time NetCDF Faults Zip Bits
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
grep -q 'static const m9_arr_5_int64_t Primes_k = { {' "$TG"/gen_want.txt \
  || { echo "AggUse: the constant table NOT generated -- the aggregate gone from BOTH generators?"; exit 1; }
grep -q 'static const m9_arr_3_AggUse_Status Statuses_k = { {' "$TG"/gen_want.txt \
  || { echo "AggUse: the record table NOT generated -- the record aggregate gone from BOTH generators?"; exit 1; }
# ExportDef and ExportUse are exported module variables (decision 28).
# The greps prove the export and its use were EMITTED: the exporter's
# constant pointer, the importer's write through it -- two generators
# that both dropped the feature would also agree byte for byte.
run ExportDef Io Fmt
grep -q '^int64_t \* const ExportDef_count = &count;$' "$TG"/gen_want.txt \
  || { echo "ExportDef: the exported pointer NOT generated"; exit 1; }
run ExportUse ExportDef Io Fmt
grep -q '(\*ExportDef_count)' "$TG"/gen_want.txt \
  || { echo "ExportUse: the write through ExportDef_count NOT generated"; exit 1; }
# An imported record's enumeration field against an imported member:
# a tag compare, not a C struct == (cp-kernel's finding on 0.19.0).
grep -q 'shade).tag == ' "$TG"/gen_want.txt \
  || { echo "ExportUse: the cross-module enumeration compare NOT by tag"; exit 1; }
# ShareUse is the assignment of a raising call (par 5): the answer
# into a temporary, the error slot read, THEN the store.  The grep holds
# the order; two generators storing first together would also agree
# byte for byte.  And a call's SHARED answer is MOVED, not share-copied
# (2026-10-21, the compiler review's G7: the copy left every handle a
# count too many, never freed).
run ShareUse Io
# FOR x IN s: the iterand once, the loop over its own index (2026-10-11)
grep -q 'for (int64_t m9t[0-9]*i = 0; m9t[0-9]*i < m9t[0-9]*s.len; m9t[0-9]*i++) { ch = m9t[0-9]*s.p\[m9t[0-9]*i\];' "$TG"/gen_want.txt \
  && grep -q '{ __typeof__(arr) \*m9t[0-9]*s = &(arr);' "$TG"/gen_want.txt \
  || { echo "ShareUse: FOR x IN is not the once-evaluated loop -- in BOTH generators"; exit 1; }
grep -q -A2 '__typeof__(b) m9v = ShareUse_Make (n, err);' "$TG"/gen_want.txt \
  && grep -A2 '__typeof__(b) m9v = ShareUse_Make (n, err);' "$TG"/gen_want.txt | grep -q 'if (err->exc) goto' \
  && grep -A3 '__typeof__(b) m9v = ShareUse_Make (n, err);' "$TG"/gen_want.txt | grep -q '  b = m9v;' \
  || { echo "ShareUse: a raising call's answer is stored before its error slot is read -- in BOTH generators"; exit 1; }
if grep -q 'b = ((__typeof__(b)) m9_share_copy (m9v));' "$TG"/gen_want.txt; then
  echo "ShareUse: a call's SHARED answer is share-copied, a count too many -- in BOTH generators"; exit 1
fi
# ... and a raising call nested as an ARGUMENT is hoisted into a guarded
# temporary before the enclosing call (par 5, 2026-10-08)
grep -q -A1 '{ __typeof__(ShareUse_Count (n, err)) m9a[0-9]* = ShareUse_Count (n, err);' "$TG"/gen_want.txt \
  && grep -A1 '{ __typeof__(ShareUse_Count (n, err)) m9a[0-9]* = ShareUse_Count (n, err);' "$TG"/gen_want.txt | grep -q 'if (err->exc) goto' \
  && grep -q 'ShareUse_Use (m9a[0-9]*, err);' "$TG"/gen_want.txt \
  || { echo "ShareUse: a raising call nested as an argument is not guarded before the enclosing call -- in BOTH generators"; exit 1; }
# F32 of a double is a checked conversion, and a U64 literal past 2^63
# is spelled UINT64_C (2026-10-08)
grep -q 'm9_f32_f64 (x, err)' "$TG"/gen_want.txt \
  || { echo "ShareUse: F32 of a double is not the checked conversion -- in BOTH generators"; exit 1; }
grep -q 'm9_gridof (m9t[0-9]*\.len, m9t[0-9]*n, 2, m9t[0-9]*r\.n, m9t[0-9]*r\.s, err);' "$TG"/gen_want.txt \
  || { echo "ShareUse: GRID (s, n0, n1) is not laid over the slice through m9_gridof -- in BOTH generators"; exit 1; }
grep -q 'static double y0_;' "$TG"/gen_want.txt \
  || { echo "ShareUse: a module variable named y0 is not escaped from libm's Bessel function -- in BOTH generators"; exit 1; }
grep -q '100u, 233u, 106u, 224u, 32u' "$TG"/gen_want.txt \
  || { echo "ShareUse: a string literal beyond ASCII is not emitted as its scalars -- in BOTH generators"; exit 1; }
grep -q 'int64_t i = err->i\[0\];' "$TG"/gen_want.txt && grep -q 'int64_t n = err->i\[1\];' "$TG"/gen_want.txt \
  || { echo "ShareUse: IndexError's (index, length) are not bound from err->i -- in BOTH generators"; exit 1; }
grep -q 'some = (o != NULL);' "$TG"/gen_want.txt && grep -q 'none = (o == NULL);' "$TG"/gen_want.txt \
  || { echo "ShareUse: IS SOME / IS NONE as an expression is not a NULL test -- in BOTH generators"; exit 1; }
grep -q 'case ShareUse_Store_Irods:' "$TG"/gen_want.txt \
  || { echo "ShareUse: a CASE label spelled Store.Irods is not its member's case -- in BOTH generators"; exit 1; }
grep -q '#define ShareUse_Folded INT64_C(19)' "$TG"/gen_want.txt && grep -q 'if (0) { m9xit1: break; }' "$TG"/gen_want.txt \
  || { echo "ShareUse: a CONST expression is not folded, or an EXIT from a CASE arm has no label at its loop's end -- in BOTH generators"; exit 1; }
grep -q 'UINT64_C(18446744073709551615)' "$TG"/gen_want.txt \
  || { echo "ShareUse: a U64 literal past 2^63 is not UINT64_C -- in BOTH generators"; exit 1; }
run Sem Ast DynUtf Print Text
run Doc Ast DynUtf Text Print Lex
run Review Ast DynUtf Text
run M9c Io Ast Parse Gen Sem DynUtf Doc Review Lex System Text
run Gen Ast DynUtf Text
run Diag DynStr DynUtf Io Lex Text
# LibmGate is a gendiff-only fixture (not in gentest.pas / runtime/gen):
# 96 locals named after the libm functions CN escapes.  The byte-compare
# above catches a ONE-SIDED edit to the two IsLibM lists; the grep proves
# the escaping is PRESENT, not that both generators dropped it together.
run LibmGate
grep -q 'float cos_' "$TG"/gen_want.txt \
  || { echo "LibmGate: libm names NOT escaped -- IsLibM gone from BOTH generators?"; exit 1; }
# KindUse is a gendiff-only fixture too: a CASE RECORD declared in
# ANOTHER module (Csv.Kind), constructed and CASEd from here -- the
# two forms both generators refused until 2026-09-15 while Csv, Frame
# and Plot routed around them with integer codes.  The grep proves the
# constructor was EMITTED: two generators refusing together would also
# agree byte for byte.
run KindUse Csv Io DynStr Time
grep -q 'Csv_Kind_Real' "$TG"/gen_want.txt \
  || { echo "KindUse: Csv.Kind.Real NOT generated -- the cross-module constructor gone from BOTH generators?"; exit 1; }
# EnumUse/Palette are gendiff-only fixtures too: an ENUMERATION, the
# Pascal-faced payload-less case record.  The grep proves the tag was
# emitted; two generators refusing together would also agree.
run Palette
run EnumUse Palette Io
grep -q 'Palette_Hue_Cool' "$TG"/gen_want.txt \
  || { echo "EnumUse: Palette.Hue.Cool NOT generated -- enum construction gone from BOTH generators?"; exit 1; }
# EnumUse.AllHues is a FOR over the enumeration; the loop runs on the
# tag, `c.tag <= ...; c.tag++`.  The grep proves the loop was emitted:
# two generators both refusing FOR-over-enum would still agree byte
# for byte (docs/enum-plan.md, part 2).
grep -q '\.tag <= ' "$TG"/gen_want.txt \
  || { echo "EnumUse: FOR over the enumeration NOT generated -- the tag loop gone from BOTH generators?"; exit 1; }
# EnumUse.Tables indexes ARRAY Colour OF T by the enumeration: the
# subscript is the member's tag, a.v[(k).tag], with no runtime bounds
# check because the index IS the type.  The grep proves that emit:
# two generators both refusing enum-indexed arrays would still agree.
grep -q '\.v\[(' "$TG"/gen_want.txt \
  || { echo "EnumUse: enum-indexed array NOT generated -- a.v[(k).tag] gone from BOTH generators?"; exit 1; }
# EnumUse compares enum values with = / #, which is a `.tag` compare,
# not a struct == (which gcc refuses).  The grep proves it.
grep -q '\.tag == \|\.tag != ' "$TG"/gen_want.txt \
  || { echo "EnumUse: enum = / # NOT a tag compare -- struct == gone from BOTH generators?"; exit 1; }
# Every module runs its imports' initialisers before its own body:
# `Mod_m9init (err); if (err->exc) goto L_ret;`.  The grep proves the
# init machinery is emitted (a library body is RUN, not dropped);
# two generators both dropping it would still agree byte for byte.
grep -q '_m9init (err); if (err->exc) goto L_ret;' "$TG"/gen_want.txt \
  || { echo "EnumUse: module init NOT generated -- a library body would be silently dropped?"; exit 1; }
echo "gendiff: $n modules, generated C byte-identical to runtime/gen and gold/c"
