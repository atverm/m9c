#!/bin/sh
# --check GROWS LINEARLY WITH THE PROGRAM (the compiler review's F5,
# 2026-10-22).  Each shape is checked at n and at 4n, and the second
# may take at most RATIO times the first: a linear checker takes about
# 4, a quadratic one about 16.  A ratio and not a time, so the gate
# reads the same on a fast machine and a slow one; n is large enough
# that the start-up cost is a small part of the first run.
#
# Measured before the fix, on the MacBook: 20,000 locals in one
# procedure 2.47 s (5,000: 0.19 s, ratio 13), 10,000 procedures each
# called once 1.26 s (ratio 14 from 2,500) -- DeclOnce, ScopeFind,
# FindProcIn, CallsAdd, the region walk's RgFind and Gen's MFind were
# scans, and AddVarsOf walked the unit again for every procedure.
# After: 0.08 s and 0.11 s.  The deep shapes (a flat chain past 1,000
# operands, a type past 100 levels) are refused by the parser's bounds
# (decision 59) and are not here.
# A record of 10,000 fields was 0.20 s, 20,000 0.69 s (FieldTypeOf and the
# duplicate-field check scanned); both index since 2026-10-25: 0.07 and
# 0.17 s.
# A LONG BODY (review2, 2026-10-26): the region walk sized its table by
# the body's node count and copies it at every IF arm, so one procedure
# of 8,000 scalar IFs took 6.0 s (0.25.0; 2,000 0.42 s, ratio 14) where
# the empty bodies above saw nothing; sized by the distinct names (no
# literal counted), 117 ms, ratio 3.0 -- 0.24.0 took 119-134 ms.
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh
. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C
LIB=$(cd ../../corpus && pwd)
RATIO=${M9_SCALE_RATIO:-6}
W=$(mktemp -d)
trap 'rm -r "$W"' EXIT

shape () {   # SHAPE N -> a program on stdout
  case $1 in
  locals) awk -v n="$2" 'BEGIN {
            print "MODULE F ;"; print "PROCEDURE P () ="; print "VAR"
            for (i = 0; i < n; i++) printf "  v%d : I64 ;\n", i
            print "BEGIN"; print "  v0 := 1"; print "END P ;"
            print "BEGIN"; print "  P ()"; print "END F." }' ;;
  procs)  awk -v n="$2" 'BEGIN {
            print "MODULE F ;"
            for (i = 0; i < n; i++) printf "PROCEDURE P%d () =\nBEGIN\nEND P%d ;\n", i, i
            print "BEGIN"
            for (i = 0; i < n; i++) printf "  P%d () ;\n", i
            print "  P0 ()"; print "END F." }' ;;
  consts) awk -v n="$2" 'BEGIN {
            print "MODULE F ;"; print "CONST"
            for (i = 0; i < n; i++) printf "  C%d = %d ;\n", i, i
            print "VAR x : I64 ;"; print "BEGIN"
            for (i = 0; i < n; i += 7) printf "  x := C%d ;\n", i
            print "END F." }' ;;
  types)  awk -v n="$2" 'BEGIN {
            print "MODULE F ;"; print "TYPE"
            for (i = 0; i < n; i++) printf "  T%d = RECORD a : I64 END ;\n", i
            print "VAR"
            for (i = 0; i < n; i += 7) printf "  v%d : T%d ;\n", i, i
            print "BEGIN"
            for (i = 0; i < n; i += 7) printf "  v%d.a := 1 ;\n", i
            print "END F." }' ;;
  vars)   awk -v n="$2" 'BEGIN {
            print "MODULE F ;"; print "VAR"
            for (i = 0; i < n; i++) printf "  g%d : I64 ;\n", i
            print "PROCEDURE P () ="; print "BEGIN"
            for (i = 0; i < n; i += 7) printf "  g%d := 1 ;\n", i
            print "END P ;"; print "BEGIN"; print "  P ()"; print "END F." }' ;;
  fields) awk -v n="$2" 'BEGIN {
            print "MODULE F ;"; print "TYPE R = RECORD"
            for (i = 0; i < n; i++) printf "  f%d : I64 ;\n", i
            print "END ;"; print "VAR r : R ;"; print "BEGIN"
            for (i = 0; i < n; i += 7) printf "  r.f%d := 1 ;\n", i
            print "END F." }' ;;
  ifs)    awk -v n="$2" 'BEGIN {
            print "MODULE F ;"; print "IMPORT Io, Fmt ;"
            print "PROCEDURE P (a: I64) ="; print "VAR"; print "  x : I64 ;"
            print "BEGIN"; print "  x := a"
            for (i = 1; i < n; i++) printf "  ; IF a > %d THEN x := x + 1 ELSE x := x - 1 END\n", i
            print "  ; Io.WriteLine (Fmt.I64Str (x))"; print "END P ;"
            print "BEGIN P (3) END F." }' ;;
  esac
}

# milliseconds of one --check, the best of three (page cache, the
# first run's library reads)
ms () {
  best=
  for r in 1 2 3; do
    t0=$(perl -MTime::HiRes=time -e 'printf "%d", time * 1000')
    M9LIBRARY="$LIB" "$M9C" --check "$1" > "$W/out" 2>&1 ||
      { echo "scale: --check refused $(basename "$1"):"; head -3 "$W/out"; exit 1; }
    t1=$(perl -MTime::HiRes=time -e 'printf "%d", time * 1000')
    t=$((t1 - t0))
    if [ -z "$best" ] || [ "$t" -lt "$best" ]; then best=$t; fi
  done
  echo "$best"
}

fail=0
for spec in "locals 5000" "procs 2500" "consts 5000" "types 2500" "vars 5000" "fields 2500" "ifs 2000"; do
  set -- $spec
  shape "$1" "$2" > "$W/a.m9"
  shape "$1" $(( $2 * 4 )) > "$W/b.m9"
  a=$(ms "$W/a.m9")
  b=$(ms "$W/b.m9")
  [ "$a" -gt 0 ] || a=1
  # the ratio in tenths, so the shell's integers say 4.3 as 43
  r=$(( b * 10 / a ))
  echo "scale: $1 $2 -> $(( $2 * 4 )): $a ms -> $b ms, ratio $(( r / 10 )).$(( r % 10 ))"
  if [ "$r" -gt $(( RATIO * 10 )) ]; then
    echo "scale: FAIL -- $1 grows faster than linearly (ratio over $RATIO)"
    fail=1
  fi
done
[ "$fail" = 0 ] || exit 1
echo "scale: --check grows linearly in locals, procedures, constants, types, module variables, a record's fields and a long body"
