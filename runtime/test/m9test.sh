#!/bin/sh
# m9test -- the tests written in M9: every corpus/NAMETest.m9, a
# PROGRAM beside the module it tests, built with `m9c --make` by the
# compiler of this tree and run (stage 3 of docs/plan-0.14.md).
#
# Why these and not one more C driver: a driver is C written by hand
# against a generated header, and a change to what a module turns
# into strands it silently; a test in M9 is checked by the compiler,
# so the same change is a compile error at the call, here.
#
# Gated: every test builds; exits 0; prints no FAIL line; ends with
# `PASS (n checks) -- Name`.  CheckTest, which tests the test library
# and so makes failures on purpose, is held to its whole output
# (checktest.want): the format of a failure line is part of the
# gate.  And the control: m9test/FailTest.m9 must exit 1 and say
# FAILED -- a gate that read PASS off everything would read it off
# that too.
#
# Errors are values: every test runs, every failure is named, and
# the exit status says whether there was one.
cd "$(dirname "$0")" || exit 1
. ./lib/gen.sh          # runtime/gen is BUILT here, not found

SRC=$(cd ../../corpus && pwd)
RT=$(cd .. && pwd)
HERE=$(pwd)
W=/tmp/m9test-gate
rm -rf "$W"; mkdir -p "$W"

gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c \
    ../gen/Text.c ../gen/System.c ../gen/Lex.c ../gen/Ast.c ../gen/Print.c \
    ../gen/Parse.c ../gen/Sem.c ../gen/Doc.c ../gen/Review.c ../gen/Gen.c \
    ../gen/Io.c ../gen/M9c.c -lm -o "$W/m9c" || { echo "m9test: FAIL building m9c"; exit 1; }
export M9RUNTIME="$RT"
export M9LIBRARY="$SRC"
M9C="$W/m9c"

fail=0
bad () { echo "m9test: FAIL $1"; fail=$((fail+1)); }

# run_test FILE: build it in its own directory, run it there; leaves
# $W/NAME/out and answers the program's exit status, or 99 when it
# did not build (the compiler's own lines are shown)
# Every test is built by the compiler's own link line, which supplies
# the runtime and OpenSSL and knows no other library -- except the
# ones below, whose module binds a foreign library the compiler does
# not carry: those are compiled by m9c and linked here with it named.
# (ZipTest was such a one for a day, with zlib, until the inflate was
# written in M9; ZarrStore decodes its chunks with blosc.)
foreign_of () {
  case "$1" in
    ZarrStoreTest) echo "-l:libblosc.so.1" ;;
    PgTest)        echo "$RT/pgshim.c -l:libpq.so.5" ;;
  esac
}
build_test () {
  extra=$(foreign_of "$2")
  if [ -z "$extra" ]; then
    "$M9C" --make -o "$2" "$1"
  else
    "$M9C" --make -c -k "$1" &&
    gcc -O2 -flto --param max-inline-insns-auto=200 ./*.o \
        "$RT/m9rt.c" "$RT/tcpshim.c" "$RT/tlsshim.c" "$RT/fmtshim.c" \
        -iquote "$RT" $extra -Wl,--as-needed -lssl -lcrypto -lm -o "$2"
  fi
}
run_test () {
  name=$(basename "$1" .m9)
  mkdir -p "$W/$name"
  if ! ( cd "$W/$name" && build_test "$1" "$name" > build.log 2>&1 ); then
    echo "m9test: $name does not build:"
    sed 's/^/    /' "$W/$name/build.log" | tail -12
    return 99
  fi
  # run from the repository root: a test finds its golden file at
  # runtime/test/gold/NAME.gold (Check.GoldPath), and a failure line
  # that names the file names it the same way on every machine
  ( cd "$HERE/../.." && "$W/$name/$name" > "$W/$name/out" 2>&1 )
}

# ---- the control first: a test that must fail ----------------------
run_test "$HERE/m9test/FailTest.m9"; rc=$?
if [ "$rc" != 1 ]; then
  bad "the control FailTest exited $rc, not 1: a failing check does not reach the exit status"
elif ! grep -q '^FAILED 1 of 2 -- Fail$' "$W/FailTest/out"; then
  bad "the control FailTest did not print FAILED 1 of 2:"; cat "$W/FailTest/out"
fi

# ---- every test beside its module ----------------------------------
n=0; checks=0
for f in "$SRC"/*Test.m9; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .m9)
  mod=${name%Test}
  n=$((n+1))
  [ -f "$SRC/$mod.m9" ] || bad "$name tests no module: there is no corpus/$mod.m9"
  # PgTest needs a server (libpq's PG* variables name it): skipped out
  # loud without one, and never on CI, whose drivers job runs one
  if [ "$name" = PgTest ] && [ -z "$PGHOST" ]; then
    if [ -n "$GITHUB_ACTIONS" ]; then
      bad "PgTest: no PGHOST on CI (the drivers job's postgres service)"
    else
      echo "  PgTest: SKIP -- PGHOST unset (a Postgres server is needed)"
    fi
    continue
  fi
  run_test "$f"; rc=$?
  [ "$rc" = 99 ] && { fail=$((fail+1)); continue; }
  out="$W/$name/out"
  last=$(tail -1 "$out")
  # one verdict a test, whichever of the three signs gave it away
  ok=1
  case "$last" in
    "PASS ("*" checks) -- $mod") ;;
    *) ok=0 ;;
  esac
  [ "$rc" = 0 ] || ok=0
  if [ "$name" = CheckTest ]; then
    # the library's own test fails on purpose: its whole output is held
    if ! cmp -s "$out" "$HERE/checktest.want"; then
      bad "CheckTest's output is not checktest.want (exit $rc):"
      diff "$HERE/checktest.want" "$out" | head -20
      continue
    fi
  elif grep -q '^FAIL' "$out"; then
    ok=0
  fi
  if [ "$ok" = 0 ]; then
    bad "$name (exit $rc):"
    grep '^FAIL' "$out" | sed 's/^/    /'
    grep -q '^FAIL' "$out" || echo "    last line: $last"
    continue
  fi
  c=${last#PASS (}; c=${c%% *}; checks=$((checks+c))
  echo "  $name: $last"
done
[ "$n" -gt 0 ] || bad "no corpus/*Test.m9 found"

# how much of the library has one: printed, never gated
lib=$(sed -n '/^LIBRARY=/,/"$/p' ../../build.sh | tr -d '"\\' | sed 's/^LIBRARY=//' | tr -s ' \n' '\n\n' | grep -c .)

if [ "$fail" != 0 ]; then
  echo "m9test: $fail FAILED"
  exit 1
fi
echo "m9test: $n tests, $checks checks, the failing control fails; $n of $lib installed modules have a test in M9"
