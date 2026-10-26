#!/bin/sh
# sanitize -- the programs the suite already trusts, run again under
# AddressSanitizer and UBSan with the runtime's -DM9_ASAN arenas
# (m9rt.h): a use of frame or pool storage after its release or free,
# a run past an allocation inside its block, a float-to-integer
# conversion out of range and C's undefined behaviour all TRAP, where
# a plain run reads a usually-right value (the compiler review of
# 2026-10-21, item 9: every oracle of the compiler was the compiler's
# twin, and two checkers that share a misconception agree).
#
# What runs: every corpus/*Test.m9 (from the repository root, as
# m9test), every genforms program genforms.owed does not list, and
# sanitize/*.m9 -- the review's run-time defects, each with the WANT
# line only the correct behaviour prints, owed until its fix -- each
# built by `m9c --run` with CC=lib/sancc -- m9c's own flags and
# link, the wrapper adds the sanitizers to every compile and the link.
# A program passes when it shows no sanitizer report and gives the
# verdict it gives unsanitized: a test exits 0 ending `PASS (n checks)
# -- Mod`, a genforms or sanitize program exits 0 printing its WANT
# line.
#
# sanitize.owed names what fails today, each with its reason, and is
# held BOTH ways: an owed program must still fail (a line that
# outlives its reason is red), any other must pass.
#
# The control: sanitize/arena_control.c must die with ASan's report
# three ways (storage a release rewound, a freed pool, an allocation's
# padding) -- a sanitized runtime that traps nothing would pass every
# program above.
#
# Leaks are not judged here (detect_leaks=0): HEAP and the module
# pools are never freed by design.  Errors are values: everything
# runs, every failure is named.
cd "$(dirname "$0")" || exit 1
. ./lib/gen.sh          # runtime/gen is BUILT here, not found

ROOT=$(cd ../.. && pwd)
RT=$(cd .. && pwd)
HERE=$(pwd)
W=$(mktemp -d /tmp/m9sanitize.XXXXXX)

gcc -std=c11 -O2 -iquote .. -iquote ../gen ../m9rt.c $COMPILERC -lm -o "$W/m9c" || { echo "sanitize: FAIL building m9c"; exit 1; }
# A CACHE THAT OUTLIVES THE RUN: the sanitized builds of every module
# were made afresh each time (2.5 minutes on the MacBook).  m9c keys a
# build by the source text of the module and its closure, the runtime
# and its own binary's mtime -- so the binary is kept beside the cache
# and replaced only when the one just built differs, and an unchanged
# module is not rebuilt.  M9_SANITIZE_CACHE moves it; deleting it is
# always safe.
# A module's key names the runtime's DIRECTORY, not m9rt.h's text, and
# every module includes the header (its checks are inline): the cache
# is one per header, by checksum, and the others go; past 2 GB it is
# started again, so it cannot grow without bound.
C=${M9_SANITIZE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/m9-sanitize}
H=$(cksum < ../m9rt.h | cut -d' ' -f1)
mkdir -p "$C"
for old in "$C"/cache-*; do
  [ -d "$old" ] && [ "$old" != "$C/cache-$H" ] && rm -rf "$old"
done
[ "$(du -sk "$C" | cut -f1)" -gt 2000000 ] && rm -rf "$C/cache-$H"
cmp -s "$W/m9c" "$C/m9c" || cp "$W/m9c" "$C/m9c"
M9C="$C/m9c"
export M9RUNTIME="$RT" M9LIBRARY="$ROOT/corpus" M9CACHE="$C/cache-$H"
export CC="$HERE/lib/sancc"
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=0
export UBSAN_OPTIONS=print_stacktrace=1
OWED="$HERE/sanitize.owed"
TMO=; command -v timeout > /dev/null 2>&1 && TMO="timeout 600"

fail=0 ; n=0 ; nowed=0
bad () { echo "sanitize: FAIL $1"; fail=$((fail+1)); }
owed () { grep -v '^#' "$OWED" | awk 'NF { print $1 }' | grep -qx "$1"; }
reported () { grep -q -e 'ERROR: AddressSanitizer' -e 'runtime error:' "$1"; }

for name in $(grep -v '^#' "$OWED" | awk 'NF { print $1 }'); do
  [ -f "$ROOT/corpus/$name.m9" ] || [ -f "genforms/$name.m9" ] || [ -f "sanitize/$name.m9" ] ||
    bad "sanitize.owed names $name: no corpus test, genforms or sanitize program has the name"
done

# ---- the control ---------------------------------------------------
"$CC" -iquote .. ../m9rt.c sanitize/arena_control.c -lm -o "$W/arena_control" 2> "$W/control.log" ||
  { bad "the control does not build:"; tail -5 "$W/control.log"; }
for c in r f o; do
  "$W/arena_control" $c > "$W/control-$c.out" 2>&1
  grep -q 'ERROR: AddressSanitizer' "$W/control-$c.out" ||
    bad "the control arena_control $c was not reported: the sanitized arenas trap nothing"
done

# judge NAME STATUS OUT OK: OK is 1 when the program gave its verdict
judge () {
  n=$((n+1))
  if reported "$3"; then ok=0; else ok=$4; fi
  if owed "$1"; then
    nowed=$((nowed+1))
    [ "$ok" = 0 ] || bad "$1 passes now -- remove its line from sanitize.owed"
  elif [ "$ok" = 0 ]; then
    bad "$1 (exit $2):"
    grep -m1 -A3 -e 'ERROR: AddressSanitizer' -e 'runtime error:' "$3" | sed 's/^/    /'
    reported "$3" || tail -3 "$3" | sed 's/^/    /'
  fi
}

# ---- the tests in M9 -----------------------------------------------
for f in "$ROOT"/corpus/*Test.m9; do
  name=$(basename "$f" .m9) ; mod=${name%Test}
  if [ "$name" = PgTest ] && [ -z "$PGHOST" ]; then
    echo "  PgTest: SKIP -- PGHOST unset" ; continue
  fi
  st=0
  ( cd "$ROOT" && $TMO "$M9C" --run "$f" < /dev/null ) > "$W/$name.out" 2>&1 || st=$?
  ok=1
  [ "$st" = 0 ] || ok=0
  case "$(tail -1 "$W/$name.out")" in "PASS ("*" checks) -- $mod") ;; *) ok=0 ;; esac
  judge "$name" "$st" "$W/$name.out" "$ok"
done

# ---- programs with a WANT line: genforms that build, sanitize/ ----
# wanted DIR SKIPLIST: every MODULE in DIR not named in SKIPLIST must
# exit 0 printing its WANT line
wanted () {
  rm -rf "$W/src" ; mkdir -p "$W/src"
  cp "$1"/*.m9 "$W/src/"
  for f in "$W"/src/*.m9; do
    name=$(basename "$f" .m9)
    head -1 "$f" | grep -q '^MODULE ' || continue      # a helper module
    [ -n "$2" ] && grep -v '^#' "$2" | awk 'NF { print $1 }' | grep -qx "$name" && continue
    want=$(sed -n 's/^(\* WANT: \(.*\) \*)$/\1/p' "$f")
    [ -n "$want" ] || { bad "$name has no (* WANT: ... *) line"; continue; }
    st=0
    ( cd "$W/src" && $TMO "$M9C" --run "$name.m9" < /dev/null ) > "$W/$name.out" 2>&1 || st=$?
    ok=1
    { [ "$st" = 0 ] && grep -qxF "$want" "$W/$name.out"; } || ok=0
    judge "$name" "$st" "$W/$name.out" "$ok"
  done
}
wanted genforms genforms.owed
wanted sanitize ""

if [ "$fail" != 0 ]; then
  echo "sanitize: $fail FAILED of $n programs ($nowed owed)"; exit 1
fi
echo "sanitize: $n programs under ASan+UBSan and the M9_ASAN arenas; $((n - nowed)) clean, $nowed owed (sanitize.owed); the control traps"
rm -rf "$W"
