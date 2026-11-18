#!/bin/sh
# pkgcache: THE PACKAGE'S CACHE (docs/run-cache-plan.md).  A package
# ships the library's modules compiled, in `cache' beside their
# sources, so a script's first run compiles no library module.  The
# gate makes a small install in a scratch directory, fills its cache
# with `m9c --fill-cache', and holds what the design promises:
#
#   1. The cache travels.  The install is copied to another path and
#      its m9c given another file time.  A script run there, with an
#      empty cache of its own, compiles no library module.
#   2. A module the package does not have is still compiled, into the
#      user's cache, and the package's cache is not written: it is
#      made unwritable for the whole gate.
#   3. An edited library source misses: that module is compiled, the
#      others are not.
#   4. Another compiler does not use it.  With one octet added to the
#      m9c binary the stamp is not its own, and every module is
#      compiled as if no package cache were there.
#   5. Without a package cache the same script compiles them all: so
#      test 1 counted something.
#
# `m9c -v' shows every command handed to the C compiler; a library
# module's compile is a line with -c and its NAME.c.
set -e
cd "$(dirname "$0")"
. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C

export M9RUNTIME=$(cd .. && pwd)
SRC=$(cd ../../corpus && pwd)
FIX=$(cd pkgcache && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/m9pkgcache.XXXXXX")
trap 'chmod -R u+w "$W" 2> /dev/null; rm -rf "$W"' EXIT
LIBMODS="Io Fmt Json Sort DynStr Text Math"

# compiled FILE: the library modules that a -v log shows compiled
compiled () {
  out=
  for m in $LIBMODS; do
    if grep -e ' -c ' "$1" | grep -q "/$m\.c "; then out="$out $m"; fi
  done
  echo "$out" | sed 's/^ //'
}

# ---- an install, and its cache ----
mkdir -p "$W/a/bin" "$W/a/lib/m9"
cp "$M9C" "$W/a/bin/m9c"
cp "$SRC"/*.m9 "$W/a/lib/m9/"
M9LIBRARY="$W/a/lib/m9" "$W/a/bin/m9c" --fill-cache "$W/a/lib/m9/cache" --run "$FIX/Fill.m9" > "$W/fill.txt" 2>&1 ||
  { echo "pkgcache: FAIL --fill-cache:"; tail -5 "$W/fill.txt"; exit 1; }
grep -q '^m9c: [0-9]* modules in ' "$W/fill.txt" ||
  { echo "pkgcache: FAIL --fill-cache did not say what it filled:"; cat "$W/fill.txt"; exit 1; }
[ -s "$W/a/lib/m9/cache/stamp" ] || { echo "pkgcache: FAIL the cache has no stamp"; exit 1; }
for m in $LIBMODS; do
  ls "$W/a/lib/m9/cache/mod/$m"-*/"$m.o" > /dev/null 2>&1 ||
    { echo "pkgcache: FAIL --fill-cache left no object of $m"; ls "$W/a/lib/m9/cache/mod"; exit 1; }
done
[ ! -e "$W/a/lib/m9/cache/tmp" ] && [ ! -e "$W/a/lib/m9/cache/bin" ] ||
  { echo "pkgcache: FAIL --fill-cache left its scratch or a bin directory in the cache"; exit 1; }
# --fill-cache alone is refused: it needs a file to take the imports from
if "$W/a/bin/m9c" --fill-cache "$W/x" "$FIX/Fill.m9" > "$W/alone.txt" 2>&1; then
  echo "pkgcache: FAIL --fill-cache without --run or --cell was accepted"; exit 1
fi
grep -q 'goes with --run or --cell' "$W/alone.txt" ||
  { echo "pkgcache: FAIL --fill-cache alone was refused with other words:"; cat "$W/alone.txt"; exit 1; }

# ---- 1 and 2: the install moved, its cache unwritable ----
cp -R "$W/a" "$W/b"
touch "$W/b/bin/m9c"
chmod -R a-w "$W/b/lib/m9/cache"
run () {   # run CACHE LOG [ARGS...]: Use.m9 with the moved install
  c=$1; log=$2; shift 2
  M9CACHE="$W/$c" M9LIBRARY="$W/b/lib/m9" "$W/b/bin/m9c" -v "$@" --run "$FIX/Use.m9" > "$log" 2>&1
}
run u1 "$W/o1.txt" || { echo "pkgcache: FAIL the script did not run against the moved cache:"; tail -5 "$W/o1.txt"; exit 1; }
grep -q '^use 13 42$' "$W/o1.txt" || { echo "pkgcache: FAIL the script said:"; tail -3 "$W/o1.txt"; exit 1; }
got=$(compiled "$W/o1.txt")
[ -z "$got" ] || { echo "pkgcache: FAIL library modules compiled beside a filled package cache: $got"; exit 1; }
grep -e ' -c ' "$W/o1.txt" | grep -q '/Beside\.c ' ||
  { echo "pkgcache: FAIL the script's own module Beside was not compiled"; exit 1; }
ls "$W/u1/mod"/Beside-*/Beside.o > /dev/null 2>&1 ||
  { echo "pkgcache: FAIL Beside is not in the user's cache"; exit 1; }
[ -z "$(ls "$W/b/lib/m9/cache/mod" | grep '^Beside-')" ] ||
  { echo "pkgcache: FAIL the package's cache was written"; exit 1; }

# ---- 5: no package cache, the same script ----
mkdir -p "$W/c/bin" "$W/c/lib/m9"
cp "$M9C" "$W/c/bin/m9c"; cp "$SRC"/*.m9 "$W/c/lib/m9/"
M9CACHE="$W/u5" M9LIBRARY="$W/c/lib/m9" "$W/c/bin/m9c" -v --run "$FIX/Use.m9" > "$W/o5.txt" 2>&1 ||
  { echo "pkgcache: FAIL the script did not run without a package cache:"; tail -5 "$W/o5.txt"; exit 1; }
got=$(compiled "$W/o5.txt")
[ "$got" = "$LIBMODS" ] ||
  { echo "pkgcache: FAIL without a package cache these were compiled: '$got', wanted '$LIBMODS'"; exit 1; }

# ---- 3: an edited library source ----
chmod u+w "$W/b/lib/m9/Sort.m9"
echo '(* edited after installing *)' >> "$W/b/lib/m9/Sort.m9"
run u3 "$W/o3.txt" || { echo "pkgcache: FAIL the script did not run after an edit:"; tail -5 "$W/o3.txt"; exit 1; }
got=$(compiled "$W/o3.txt")
[ "$got" = "Sort" ] ||
  { echo "pkgcache: FAIL after editing Sort.m9 these were compiled: '$got', wanted 'Sort'"; exit 1; }
grep -q '^use 13 42$' "$W/o3.txt" || { echo "pkgcache: FAIL after the edit the script said:"; tail -3 "$W/o3.txt"; exit 1; }

# ---- 4: another compiler ----
chmod u+w "$W/b/bin/m9c"
printf 'x' >> "$W/b/bin/m9c"
run u4 "$W/o4.txt" || { echo "pkgcache: FAIL the script did not run under another binary:"; tail -5 "$W/o4.txt"; exit 1; }
got=$(compiled "$W/o4.txt")
[ "$got" = "$LIBMODS" ] ||
  { echo "pkgcache: FAIL another m9c binary used the package's cache: compiled '$got', wanted '$LIBMODS'"; exit 1; }

# ---- the package's own fill program checks (0.28.1) ----
# build.sh --fill-cache imports every module the package ships.  It
# named the three program modules too, and the refusal of an imported
# program MODULE stopped every package build; only the release
# rehearsal said so.  This holds the program build.sh writes, over the
# library as build.sh lists it, to the checker.
mkdir -p "$W/lib"
for m in $(sed -n '/^LIBRARY="/,/"$/p' ../../build.sh | tr -d '"\\' | sed 's/LIBRARY=//'); do
  cp "$SRC/$m.m9" "$W/lib/"
done
sh ../../build.sh --fill-source "$W/lib" > "$W/FillAll.m9"
grep -q '^IMPORT Io ;$' "$W/FillAll.m9" ||
  { echo "pkgcache: FAIL build.sh --fill-source names no library module"; head -5 "$W/FillAll.m9"; exit 1; }
M9LIBRARY="$W/lib" "$M9C" --check "$W/FillAll.m9" > "$W/fillall.txt" 2>&1 ||
  { echo "pkgcache: FAIL the package's fill program is refused:"; head -5 "$W/fillall.txt"; exit 1; }

echo "pkgcache: a filled cache travels with its install and is read only; an edited source and another compiler miss it"
