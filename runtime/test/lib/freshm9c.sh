# sourced by a gate from runtime/test: M9C is a compiler built from
# runtime/gen -- this tree's -- unless the caller named one in $M9C.
#
# Twelve gates took $M9C, then ./m9c, then ../../out/m9c, and either
# file can be left from an earlier tree: runtime/test/m9c is gitignored
# and outlives a pull, out/m9c is whatever build.sh last made (the UTF
# port's genforms ran on a stale out/m9c, 2026-10-23; docdiff and
# diagdiff had built their own since "THE GATES WERE TESTING STALE
# CODE").  The binary is replaced only when it differs, so a gate in
# another lane running it keeps its file and --run's cache, whose key
# holds m9c's mtime, keeps its entries.
[ -n "${COMPILERC:-}" ] || . ./lib/gen.sh
if [ -z "${M9C:-}" ]; then
  M9CNEW=$(mktemp -d)
  gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label \
      -Wno-unused-parameter -Wno-unused-function \
      -iquote .. -iquote ../gen ../m9rt.c $COMPILERC -o "$M9CNEW/m9c" ||
    { echo "$(basename "$0" .sh): FAIL building m9c from runtime/gen"; rm -r "$M9CNEW"; exit 1; }
  if cmp -s "$M9CNEW/m9c" m9c; then rm -r "$M9CNEW"; else mv -f "$M9CNEW/m9c" m9c; rmdir "$M9CNEW"; fi
  M9C=$(pwd)/m9c
fi
