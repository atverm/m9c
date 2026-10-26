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
#
# THE TESTS BUILD AND RUN IN PARALLEL (2026-10-21; Alex: "make the
# m9test gate ... work in parallel"): each one builds its program and
# its closure in a directory of its own, so they are independent, and
# run one by one they took 230 s on the MacBook.  The script calls
# itself as `m9test.sh --one FILE' through xargs -P (M9_JOBS, default
# the cores), each worker leaving its status in $W/NAME.rc; the
# judging below is serial and in file order, so the output is what it
# was.  The tests write only under names of their own (IoTest's
# /tmp/m9iotest*, the others' by process id), so two never collide.
cd "$(dirname "$0")" || exit 1

SRC=$(cd ../../corpus && pwd)
RT=$(cd .. && pwd)
HERE=$(pwd)
if [ "$1" != --one ]; then
  . ./lib/gen.sh          # runtime/gen is BUILT here, not found
  # a work directory of this run's own: a fixed /tmp/m9test-gate was
  # shared by every checkout on a machine, and on 2026-10-09 two
  # sessions' runs overlapped in it -- one reported ParquetTest PASS
  # with 29 checks where the test makes 44, having run the other tree's
  # binary
  W=$(mktemp -d /tmp/m9test-gate.XXXXXX)

  gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
      -Wno-unused-parameter -Wno-unused-function \
      -iquote .. -iquote ../gen ../m9rt.c $COMPILERC -lm -o "$W/m9c" || { echo "m9test: FAIL building m9c"; exit 1; }
fi
export M9RUNTIME="$RT"
export M9LIBRARY="$SRC"
export W
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
# the linker's word for "only what is used": GNU ld's and ld64's differ
# (m9c supplies the same pair; ZarrStoreTest did not build on macOS
# until 2026-10-09)
case $(uname) in
  Darwin) ASNEEDED=-Wl,-dead_strip_dylibs; BLOSC="-L/opt/homebrew/lib -lblosc" ;;
  *)      ASNEEDED=-Wl,--as-needed; BLOSC="-l:libblosc.so.1" ;;
esac
# (m9c's LINK rule, by hand: `-l:libNAME.so.N' is GNU ld's spelling and
# ld64 wants -lNAME from Homebrew's lib)
foreign_of () {
  case "$1" in
    ZarrStoreTest) echo "$BLOSC" ;;
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
        -iquote "$RT" $extra $ASNEEDED -lssl -lcrypto -lm -o "$2"
  fi
}
run_test () {
  name=$(basename "$1" .m9)
  mkdir -p "$W/$name"
  if ! ( cd "$W/$name" && build_test "$1" "$name" > build.log 2>&1 ); then
    return 99
  fi
  # run from the repository root: a test finds its golden file at
  # runtime/test/gold/NAME.gold (Check.GoldPath), and a failure line
  # that names the file names it the same way on every machine
  ( cd "$HERE/../.." && "$W/$name/$name" > "$W/$name/out" 2>&1 )
}

# a worker: one test, its status into $W/NAME.rc
if [ "$1" = --one ]; then
  run_test "$2"
  echo $? > "$W/$(basename "$2" .m9).rc"
  exit 0
fi

# rc_of NAME: the status a worker left; a test that did not build has
# its compiler's lines shown here, in order
rc_of () {
  rc=$(cat "$W/$1.rc" 2>/dev/null || echo 98)
  if [ "$rc" = 99 ]; then
    echo "m9test: $1 does not build:"
    sed 's/^/    /' "$W/$1/build.log" | tail -12
  fi
}

# ---- the list, then every build and run at once --------------------
n=0; checks=0
: > "$W/list"
: > "$W/order"
echo "$HERE/m9test/FailTest.m9" >> "$W/list"
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
      echo "skip $f" >> "$W/order"
    fi
    continue
  fi
  echo "$f" >> "$W/list"
  echo "run $f" >> "$W/order"
done
J=${M9_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
xargs -P "$J" -I{} "$HERE/m9test.sh" --one {} < "$W/list"

# ---- the control first: a test that must fail ----------------------
rc_of FailTest
if [ "$rc" != 1 ]; then
  bad "the control FailTest exited $rc, not 1: a failing check does not reach the exit status"
elif ! grep -q '^FAILED 1 of 2 -- Fail$' "$W/FailTest/out"; then
  bad "the control FailTest did not print FAILED 1 of 2:"; cat "$W/FailTest/out"
fi

# ---- every test beside its module, judged in file order -------------
while read -r how f; do
  name=$(basename "$f" .m9)
  mod=${name%Test}
  if [ "$how" = skip ]; then
    echo "  PgTest: SKIP -- PGHOST unset (a Postgres server is needed)"
    continue
  fi
  rc_of "$name"
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
done < "$W/order"
[ "$n" -gt 0 ] || bad "no corpus/*Test.m9 found"

# ---- the twins' tests once more on their M9 side ----------------------
# Fmt.Fixed and Fmt.Sci take their digits from the C library through
# the runtime (m9_fmt_fixed/m9_fmt_sci, 2026-10-25) and Sort's four
# sorts their order from its radix sorts (m9_sort_*, the same day), and
# each keeps its own M9 code for where the runtime declines.  The run
# above held the C paths to the goldens (Python's, numpy's); this holds
# the M9 paths to the same goldens, so neither twin goes unwatched.
again () {   # again TEST MODULE VAR=1 WORDS
  t=$1; mod=$2; v=$3; shift 3
  [ -x "$W/$t/$t" ] || return 0
  ( cd "$HERE/../.." && env "$v" "$W/$t/$t" > "$W/$t/out2" 2>&1 )
  rc2=$?
  last2=$(tail -1 "$W/$t/out2")
  case "$last2" in
    "PASS ("*" checks) -- $mod") [ "$rc2" = 0 ] && ! grep -q '^FAIL' "$W/$t/out2" \
      && echo "  $t ($v, $*): $last2" \
      || { bad "$t on $* (exit $rc2):"; grep '^FAIL' "$W/$t/out2" | sed 's/^/    /'; } ;;
    *) bad "$t on $* (exit $rc2): last line: $last2" ;;
  esac
}
again FmtTest Fmt M9_FMT_PORTABLE=1 the M9 digits
again SortTest Sort M9_SORT_PORTABLE=1 the merge sorts
again CsvTest Csv M9_CSV_PORTABLE=1 IsNumber in M9
again FrameTest Frame M9_CSV_PORTABLE=1 IsNumber in M9

# how much of the library has one: printed, never gated
lib=$(sed -n '/^LIBRARY=/,/"$/p' ../../build.sh | tr -d '"\\' | sed 's/^LIBRARY=//' | tr -s ' \n' '\n\n' | grep -c .)

if [ "$fail" != 0 ]; then
  echo "m9test: $fail FAILED"
  exit 1
fi
echo "m9test: $n tests, $checks checks, the failing control fails; $n of $lib installed modules have a test in M9"
rm -rf "$W"
