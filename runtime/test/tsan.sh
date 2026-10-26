#!/bin/sh
# tsan: THE THREADED PROGRAMS RUN UNDER THREADSANITIZER (2026-10-26, the
# third review's concurrency advice: no lane looked for data races, and
# AdoptRace -- a THREAD carving a shared pool -- lost 21,733 to 71,859
# of 400,000 updates with nothing in CI to see it; the checker refuses
# that shape now).  Each program below is built with CC = lib/tsancc
# (clang or gcc with -fsanitize=thread) through `m9c --run' and run
# twice, since one run of a race is no verdict.  A report is red unless
# tsan.owed lists the program, and an owed program must still report.
# The control tsan/tsan_control.c, a counter two threads bump with no
# lock, must report: a lane that sees nothing there sees nothing.
# Shown able to fail on M9 code too: the compiler of c3fddee6 emitted the
# [SERIAL] gate's leave as a plain re-read of the slot another thread's
# m9_gate stores atomically, and IoPar is reported (Io_Remove).  The
# programs ran clean twice each on the MacBook in 1 min 48 s.
cd "$(dirname "$0")" || exit 1
. ./lib/gen.sh
. ./lib/freshm9c.sh
ROOT=$(cd ../.. && pwd)
HERE=$(pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export M9RUNTIME="$ROOT/runtime" M9LIBRARY="$ROOT/corpus" M9CACHE="$W/cache"
export TSAN_OPTIONS="halt_on_error=0 second_deadlock_stack=1"
OWED="$HERE/tsan.owed"
owed () { grep -v '^#' "$OWED" 2>/dev/null | awk 'NF { print $1 }' | grep -qx "$1"; }
TMO=; command -v timeout > /dev/null 2>&1 && TMO="timeout 300"

CCT="$HERE/lib/tsancc"
# Linux with a high mmap randomisation (vm.mmap_rnd_bits 32, zoefii's
# kernel 7.0) is a layout gcc 13's TSan cannot map: "FATAL: unexpected
# memory mapping" before main.  The runs go without ASLR there, through
# setarch -R, which a container permits only with seccomp unconfined --
# ci.yml's drivers job says so (2026-10-26, the lane's first CI run)
NOASLR=
if [ "$(uname -s)" = Linux ] && command -v setarch > /dev/null 2>&1 &&
   setarch "$(uname -m)" -R true 2> /dev/null; then
  NOASLR="setarch $(uname -m) -R"
fi
"$CCT" "$HERE/tsan/tsan_control.c" -o "$W/control" -lpthread > "$W/control.build" 2>&1 ||
  { if [ -n "${GITHUB_ACTIONS:-}" ]; then
      echo "tsan: FAIL -- no ThreadSanitizer on CI, where the lane must run:"; head -3 "$W/control.build"; exit 1
    fi
    echo "tsan: SKIP -- no ThreadSanitizer here:"; head -3 "$W/control.build"; exit 0; }
$NOASLR sh -c '"$1" > "$2" 2>&1' sh "$W/control" "$W/control.out" 2> /dev/null
grep -q 'WARNING: ThreadSanitizer' "$W/control.out" ||
  { echo "tsan: FAIL -- the control race was not reported"; head -5 "$W/control.out"; exit 1; }

fail=0 ; n=0
# PROGRAM DIR: the file, the directory it is run from (a tutorial
# example reads its data beside it, a test from the repository root)
for spec in "thrtest.m9 $HERE" "IoPar.m9 $HERE" "ExecPar.m9 $HERE" \
            "docs/tutorial/examples/C16Hash.m9 $ROOT/docs/tutorial/examples" \
            "docs/tutorial/examples/C16Mat.m9 $ROOT/docs/tutorial/examples" \
            "corpus/MatTest.m9 $ROOT"; do
  set -- $spec
  f=$1 ; dir=$2
  case $f in /*) src=$f ;; *.m9) [ -f "$HERE/$f" ] && src="$HERE/$f" || src="$ROOT/$f" ;; esac
  name=$(basename "$f" .m9)
  n=$((n + 1))
  reported=0
  for r in 1 2; do
    st=0
    ( cd "$dir" && CC="$CCT" $TMO $NOASLR "$M9C" --run "$src" < /dev/null ) > "$W/$name.$r" 2>&1 || st=$?
    if grep -q 'WARNING: ThreadSanitizer' "$W/$name.$r"; then
      reported=1
    elif [ $st != 0 ]; then
      # a program that did not build or run proves nothing about races
      echo "tsan: FAIL $name did not run cleanly under TSan (exit $st):"
      grep -v 'm9c: gcc\|^    #' "$W/$name.$r" | tail -5 | sed 's/^/    /'
      fail=$((fail + 1)) ; break
    fi
  done
  if owed "$name"; then
    [ $reported = 1 ] || { echo "tsan: FAIL $name is owed but reported nothing in two runs -- remove it from tsan.owed"; fail=$((fail + 1)); }
  elif [ $reported = 1 ]; then
    echo "tsan: FAIL $name: a data race reported:"
    grep -h -A8 'WARNING: ThreadSanitizer' "$W/$name.1" "$W/$name.2" | grep -v '^    #[1-9][0-9]' | head -16 | sed 's/^/    /'
    fail=$((fail + 1))
  fi
done
[ $fail = 0 ] || { echo "tsan: $fail of $n programs FAILED"; exit 1; }
echo "tsan: $n threaded programs twice each under ThreadSanitizer, no race reported; the control reports"
