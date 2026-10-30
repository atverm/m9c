#!/bin/sh
# regions: the compiler review's checker repros held both ways
# (2026-10-21; docs/region-plan.md, step 2).  runtime/test/regions/ holds
# the review's checker programs: 24 that the checker ACCEPTS and that are
# memory-unsafe under ASan+UBSan (they read freed storage or write into
# read-only storage), and 9 refused companions of theirs; and since
# 2026-10-26 the second review's (R2*), each accepted by 0.25.0 and
# unsafe, each to be refused BY THE REGION JUDGEMENT (its text), and
# the third review's ownership repros (R3Own*), refused by the owner
# walk beside it, whose text ends the same way; and since 2026-10-28 the
# ownership probe's field and procedure-value copies (R5Own*), held to
# the owner walk's text too, so that par 4.2's refusal of the move
# through a selector is not what keeps them out.
#
#   a program in regions.owed must still pass --check AND still fail
#   under the sanitizers -- an owed line whose program is refused now,
#   or runs clean, is red, so the list shrinks only by the fix;
#   any other program must be refused by --check.
#
# The one region judgement of docs/region-plan.md is to empty the list.
cd "$(dirname "$0")" || exit 1
. ./lib/gen.sh          # runtime/gen is BUILT here, not found

ROOT=$(cd ../.. && pwd)
RT=$(cd .. && pwd)
HERE=$(pwd)
W=$(mktemp -d /tmp/m9regions.XXXXXX)
trap 'rm -rf "$W"' EXIT

gcc -std=c11 -O2 -iquote .. -iquote ../gen ../m9rt.c $COMPILERC -lm -o "$W/m9c" || { echo "regions: FAIL building m9c"; exit 1; }
M9C="$W/m9c"
export M9RUNTIME="$RT" M9LIBRARY="$ROOT/corpus" M9CACHE="$W/cache"
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=0
export UBSAN_OPTIONS=print_stacktrace=1
TMO=; command -v timeout > /dev/null 2>&1 && TMO="timeout 60"
OWED="$HERE/regions.owed"
owed () { grep -v '^#' "$OWED" | awk 'NF { print $1 }' | grep -qx "$1"; }

for name in $(grep -v '^#' "$OWED" | awk 'NF { print $1 }'); do
  [ -f "regions/$name.m9" ] || { echo "regions: FAIL regions.owed names $name: no such program"; exit 1; }
done

fail=0 ; n=0 ; nowed=0
bad () { echo "regions: FAIL $1"; fail=$((fail+1)); }
for f in regions/*.m9; do
  name=$(basename "$f" .m9)
  n=$((n+1))
  if "$M9C" --check "$f" > "$W/$name.check" 2>&1; then
    if ! owed "$name"; then
      bad "$name is accepted by the checker and is not owed"; continue
    fi
    nowed=$((nowed+1))
    st=0
    cp "$f" "$W/$name.m9"
    ( cd "$W" && CC="$HERE/lib/sancc" $TMO "$M9C" --run "$name.m9" < /dev/null ) > "$W/$name.run" 2>&1 || st=$?
    if ! grep -q -e 'ERROR: AddressSanitizer' -e 'runtime error:' "$W/$name.run" && [ "$st" -le 128 ]; then
      bad "$name is owed but runs clean under the sanitizers (exit $st) -- read it: fixed elsewhere, or no longer a hole"
    fi
  elif owed "$name"; then
    bad "$name is refused now -- remove it from regions.owed:"
    sed 's/^/    /' "$W/$name.check" | head -2
  else
    # the second review's programs (R2*) are held to the REGION
    # judgement's own refusal: any refusal used to pass, and 9 of the
    # first review's are refused by an older analysis's text alone
    case $name in
    R2*|R3Own*|R4*|R5Own*) grep -q ', regions)' "$W/$name.check" ||
           { bad "$name is refused, but not by the region judgement:"; sed 's/^/    /' "$W/$name.check" | head -2; } ;;
    esac
  fi
done
if [ "$fail" != 0 ]; then echo "regions: $fail FAILED of $n programs"; exit 1; fi
echo "regions: $n review repros; $((n - nowed)) refused, $nowed accepted and still unsafe under ASan (regions.owed)"
