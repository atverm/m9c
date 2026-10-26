#!/bin/sh
# soundfuzz: the checker held to the RUNTIME, on programs nobody wrote
# (2026-10-21, the compiler review's tier 2 item 10).  checkfuzz holds
# the two checkers to each other, and two checkers that share a
# misconception agree; the sanitize gate holds the runtime to ASan and
# UBSan, but only on programs written to be right.  This joins them:
# tools/CheckFuzz.m9 --emit mutates every genforms program and every
# sanitize fixture one edit at a time (a line deleted, a RAISES clause or
# KEPT/RO/VAR/OWN/SHARED/NOT/`IN pool' dropped, a STR or slice local or
# parameter kept in a module variable, field or element and read after
# its procedure is gone), and -- with the library loaded -- a fixed
# sample of the same mutants of the corpus's tests (every
# M9_SOUNDFUZZ_EVERY'th, default 10; 1 is all 13,000), and every mutant the
# checker ACCEPTS is built and run under ASan+UBSan with the M9_ASAN
# arenas (lib/sancc), where a frame read after its release traps.
#
# A mutant is
#   refused   the checker said no -- nothing to run;
#   clean     it ran, or stopped on an M9 exception (a check doing its
#             job: an IndexError is the language working);
#   FINDING   a sanitizer report or a death by signal: the checker
#             accepted a program that is not memory-safe -- a hole;
#   BUILD     the checker accepted it and the generator or cc refused it
#             (genforms' class: a form the build cannot make);
#   timeout   it ran past its bound (a deleted increment, a loop).
# RED on a FINDING or a BUILD not in soundfuzz.owed, and on an owed line
# no mutant produces any more.  The run's mutants are numbered by the
# order CheckFuzz writes them, so a line in the owed list is SEED and
# the mutation, which survive a renumbering.
#
# M9_JOBS sets the parallelism (default: the cores).
cd "$(dirname "$0")" || exit 1
HERE=$(pwd)

if [ "$1" = --one ]; then
  # one mutant: $2 its directory.  Writes $2/verdict.
  d=$2
  f=$(ls "$d"/*.m9)
  b=$(basename "$f")
  what=$(head -1 "$f" | sed 's/^(\* from \(.*\) \*)$/\1/')
  if ! "$M9C" -I "$HERE/genforms" -I "$HERE/sanitize" --check "$f" > "$d/check.out" 2>&1; then
    echo "refused" > "$d/verdict"; exit 0
  fi
  st=0
  # a corpus test runs from the repository root, as m9test runs it
  case "$b" in
    *Test.m9) ( cd "$ROOT" && $TMO "$M9C" --run "$f" < /dev/null ) > "$d/run.out" 2>&1 || st=$? ;;
    *) ( cd "$d" && $TMO "$M9C" -I "$HERE/genforms" -I "$HERE/sanitize" --run "$b" < /dev/null ) \
         > "$d/run.out" 2>&1 || st=$? ;;
  esac
  if grep -q -e 'ERROR: AddressSanitizer' -e 'runtime error:' "$d/run.out"; then
    echo "FINDING sanitizer: $what" > "$d/verdict"
  elif [ "$st" = 124 ]; then
    echo "timeout: $what" > "$d/verdict"
  elif [ "$st" -gt 128 ]; then
    echo "FINDING signal $((st - 128)): $what" > "$d/verdict"
  elif grep -q -e ': gen: ' -e ' error: ' -e 'm9c: cc failed' "$d/run.out"; then
    echo "BUILD: $what" > "$d/verdict"
  else
    echo "clean" > "$d/verdict"
  fi
  exit 0
fi

. ./lib/gen.sh          # runtime/gen is BUILT here, not found

ROOT=$(cd ../.. && pwd)
RT=$(cd .. && pwd)
W=$(mktemp -d /tmp/m9soundfuzz.XXXXXX)
trap 'rm -rf "$W"' EXIT

gcc -std=c11 -O2 -iquote .. -iquote ../gen ../m9rt.c $COMPILERC -lm -o "$W/m9c" || { echo "soundfuzz: FAIL building m9c"; exit 1; }
export M9C="$W/m9c"
export M9RUNTIME="$RT" M9LIBRARY="$ROOT/corpus" M9CACHE="$W/cache"
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=0
export UBSAN_OPTIONS=print_stacktrace=1
TMO=; command -v timeout > /dev/null 2>&1 && TMO="timeout 60"
export TMO ROOT
OWED="$HERE/soundfuzz.owed"
JOBS=${M9_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}

# a sanitize program sanitize.owed lists fails under the sanitizers by
# declaration: every mutant of it would read as a finding, so it seeds
# nothing until its fix (SanDisposeModVar, 2026-10-25, fixed and moved
# to regions/R3DisposeModVar the next day)
sowed=" $(grep -v '^#' "$HERE/sanitize.owed" | awk 'NF { print $1 }' | tr '\n' ' ') "
seeds=$(ls "$HERE"/genforms/*.m9 "$HERE"/sanitize/*.m9 | while read -r f; do
  case "$sowed" in (*" $(basename "$f" .m9) "*) continue ;; esac
  head -1 "$f" | grep -q '^MODULE ' && echo "$f"; done)

tests=$(ls "$ROOT"/corpus/*Test.m9 | grep -v '/PgTest.m9$')
EVERY=${M9_SOUNDFUZZ_EVERY:-10}

# the mutants, written by the plain compiler (CheckFuzz is a helper)
( cd "$ROOT" && CC=gcc M9CACHE="$W/plain" "$M9C" --run tools/CheckFuzz.m9 --emit="$W/m" $seeds &&
  CC=gcc M9CACHE="$W/plain" "$M9C" --run tools/CheckFuzz.m9 --emit="$W/m/t" --every="$EVERY" $tests ) \
  > "$W/emit.log" 2>&1 || { echo "soundfuzz: FAIL emitting mutants"; cat "$W/emit.log"; exit 1; }

export CC="$HERE/lib/sancc"
# warm the cache with the seeds, one at a time: the library's modules are
# compiled once here, not raced by the workers, and a seed that is not
# itself clean would make every mutant of it look like a finding
for f in $seeds; do
  st=0
  ( cd "$(dirname "$f")" && $TMO "$M9C" --run "$(basename "$f")" < /dev/null ) > "$W/seed.out" 2>&1 || st=$?
  if [ "$st" != 0 ] || grep -q -e 'ERROR: AddressSanitizer' -e 'runtime error:' "$W/seed.out"; then
    case " $(grep -v '^#' "$HERE/genforms.owed" | awk 'NF { print $1 }' | tr '\n' ' ') " in
      *" $(basename "$f" .m9) "*) continue ;;
    esac
    echo "soundfuzz: FAIL the seed $(basename "$f") is not clean (exit $st):"; tail -3 "$W/seed.out"; exit 1
  fi
done
for f in $tests; do
  st=0
  ( cd "$ROOT" && $TMO "$M9C" --run "$f" < /dev/null ) > "$W/seed.out" 2>&1 || st=$?
  if grep -q -e 'ERROR: AddressSanitizer' -e 'runtime error:' "$W/seed.out"; then
    echo "soundfuzz: FAIL the seed $(basename "$f") is not clean (exit $st):"; tail -3 "$W/seed.out"; exit 1
  fi
done

# a directory per mutant; the tests' sample may be empty (a large EVERY)
ls -d "$W"/m/[0-9]* "$W"/m/t/[0-9]* 2>/dev/null | xargs -P "$JOBS" -n 1 "$HERE/soundfuzz.sh" --one

n=0; nref=0; nclean=0; ntmo=0
: > "$W/found"
for d in "$W"/m/[0-9]* "$W"/m/t/[0-9]*; do
  [ -d "$d" ] || continue
  n=$((n+1))
  v=$(cat "$d/verdict" 2>/dev/null || echo "FINDING no verdict: $d")
  case "$v" in
    refused) nref=$((nref+1)) ;;
    clean) nclean=$((nclean+1)) ;;
    timeout*) ntmo=$((ntmo+1)) ;;
    *) echo "$v" | sed 's/^[A-Z]* *[a-z0-9 ]*: //' | sed "s|$HERE/||; s|$ROOT/||" >> "$W/found"
       echo "$v" | sed "s|$HERE/||; s|$ROOT/||"
       grep -m1 -A3 -e 'ERROR: AddressSanitizer' -e 'runtime error:' -e ': gen: ' -e ' error: ' "$d/run.out" | sed 's/^/    /' ;;
  esac
done
sort -u "$W/found" > "$W/found.s"
grep -v '^#' "$OWED" | sed '/^$/d' | sort -u > "$W/owed.s"
fail=0
new=$(comm -23 "$W/found.s" "$W/owed.s")
gone=$(comm -13 "$W/found.s" "$W/owed.s")
[ -z "$new" ] || { echo "soundfuzz: NEW (not in soundfuzz.owed):"; echo "$new" | sed 's/^/  /'; fail=1; }
[ -z "$gone" ] || { echo "soundfuzz: owed lines no mutant produces now -- remove them:"; echo "$gone" | sed 's/^/  /'; fail=1; }
nfound=$(wc -l < "$W/found.s" | tr -d ' ')
echo "soundfuzz: $n mutants of $(echo $seeds $tests | wc -w | tr -d ' ') seeds (the tests' every ${EVERY}th); $nref refused, $nclean clean, $ntmo timeout, $nfound findings ($(wc -l < "$W/owed.s" | tr -d ' ') owed)"
exit $fail
