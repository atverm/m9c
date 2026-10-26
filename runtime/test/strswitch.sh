#!/bin/sh
# The switch, rehearsed: `m9c --utf-str` (docs/utf8-stage4-plan.md, 4d
# behind a flag).  Each program in strswitch/ is written for the
# switched language: one with a `(* WANT: ... *)` line must build with
# the flag and print it; one with `(* EXPECT-ERROR ... *)` lines must
# be refused with the flag, each text present, and ACCEPTED without it
# (the flag is what refuses it).  swio.m9 is the fixtures' printer.
#
# Then, PRINTED AND NEVER GATED: every LIBRARY module checked with the
# flag -- clean, or how many refusals -- which is stage 4a's remaining
# work by module, as the review row is by site.
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh
. ./lib/mods.sh
M9CNEW=$(mktemp -d)
gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c $COMPILERC -o "$M9CNEW/m9c"
M9C=$M9CNEW/m9c
RT=$(cd .. && pwd)
SRC=$(cd ../../corpus && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W" "$M9CNEW"' EXIT
export M9RUNTIME=$RT M9LIBRARY=$SRC
fail=0
for f in strswitch/Sw*.m9; do
  name=$(basename "$f" .m9)
  want=$(sed -n 's/^(\* WANT: \(.*\) \*)$/\1/p' "$f")
  grep -q '^(\* \(WANT\|EXPECT-ERROR\): ' "$f" || continue   # SwPut, the printer
  if [ -n "$want" ]; then
    # built and run from a cache of the run's own (M9CACHE): every module
    # of the closure compiled in-process under the flag, DynStr served
    # from DynUtf.m9 (M9c.Aliased)
    if ! ( cd strswitch && M9CACHE="$W/cache" "$M9C" --utf-str --run "$name.m9" ) > "$W/$name.out" 2>&1; then
      echo "FAIL: $name did not build and run under --utf-str:"; sed 's/^/    /' "$W/$name.out" | head -20; fail=$((fail + 1)); continue
    fi
    got=$(tail -1 "$W/$name.out")
    if [ "$got" != "$want" ]; then
      echo "FAIL: $name printed '$got', wanted '$want'"; fail=$((fail + 1)); continue
    fi
    echo "ok: $name prints its WANT line under --utf-str"
  else
    # refused with the flag, each EXPECT-ERROR text present; accepted without
    ( cd strswitch && "$M9C" --utf-str --check "$name.m9" ) > "$W/$name.ref" 2>&1 && {
      echo "FAIL: $name accepted under --utf-str"; fail=$((fail + 1)); continue; }
    miss=0
    sed -n 's/^(\* EXPECT-ERROR \(.*\) \*)$/\1/p' "$f" | while IFS= read -r t; do
      grep -qF -- "$t" "$W/$name.ref" || { echo "FAIL: $name: no refusal says '$t'"; exit 1; }
    done || miss=1
    [ $miss -eq 0 ] || { fail=$((fail + 1)); continue; }
    if ! ( cd strswitch && "$M9C" --check "$name.m9" ) > "$W/$name.ok" 2>&1; then
      echo "FAIL: $name refused WITHOUT the flag:"; sed 's/^/    /' "$W/$name.ok"; fail=$((fail + 1)); continue
    fi
    echo "ok: $name refused under --utf-str as expected, accepted without"
  fi
done
[ $fail -eq 0 ] || { echo "strswitch: $fail failures"; exit 1; }

# the tests whose closure checks clean under the flag, RUN switched from
# the repository root (the goldens are relative to it): every check of
# Arrays, Chars, Check, Fmt, Mat and Numeric passes with STR the
# UTF type -- the rehearsal on running code, not only on fixtures
for tn in ArraysTest CharsTest CheckTest FmtTest MatTest NumericTest; do
  if ! ( cd ../.. && M9CACHE="$W/cache" "$M9C" --utf-str --run "corpus/$tn.m9" ) > "$W/$tn.out" 2>&1; then
    echo "FAIL: $tn did not build and run under --utf-str:"; grep -a -v '^ok' "$W/$tn.out" | head -12 | sed 's/^/    /'; fail=$((fail + 1)); continue
  fi
  last=$(tail -1 "$W/$tn.out")
  case "$last" in
    "PASS ("*) echo "ok: $tn switched: $last" ;;
    *) echo "FAIL: $tn switched ended '$last'"; grep -a -v '^ok' "$W/$tn.out" | head -8 | sed 's/^/    /'; fail=$((fail + 1)) ;;
  esac
done
[ $fail -eq 0 ] || { echo "strswitch: $fail failures"; exit 1; }

# the library under the flag, printed
clean=0; total=0; sites=0
for m in $(sed -n '/^LIBRARY=/,/"$/p' ../../build.sh |
           sed 's/LIBRARY="//; s/"$//; s/\\$//' | tr -s ' \n' ' '); do
  total=$((total + 1))
  if "$M9C" --utf-str --check "$SRC/$m.m9" > "$W/lib-$m" 2>&1; then
    clean=$((clean + 1))
  else
    n=$(grep -c '^[^ ]*:[0-9]*:[0-9]*: ' "$W/lib-$m" || true)
    sites=$((sites + n))
    printf '  %-12s %4d refusals\n' "$m" "$n"
  fi
done
echo "strswitch: $clean of $total library modules check clean under --utf-str; $sites refusals in the rest"
