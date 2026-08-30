#!/bin/sh
# THE SOURCE TREE MUST BUILD WITH NOTHING BUT A C COMPILER.
#
# M9 is self-hosted, and `runtime/gen/` holds the generated C for the
# whole toolchain -- checked in ON PURPOSE (see .gitignore, which says
# so) so that a source package needs no M9 compiler to build one, and
# no Free Pascal either.  `debian/control` already declares
# `Build-Depends: gcc, libc6-dev, groff-base` and nothing else.
#
# THAT CLAIM ROTS SILENTLY IF NOBODY CHECKS IT.  Every machine this is
# developed on has FPC installed and every CI runner installs it for
# the differential gates, so a build.sh that started calling `fpc`, or
# a runtime/gen left stale, would keep working here and fail on a user
# who has only gcc.  This gate is the difference between a claim and a
# fact.
#
# It copies the TRACKED files -- the working tree's version, which is
# what a commit would contain -- into a scratch directory, puts a
# sabotaged `fpc` first on PATH, and requires build.sh to succeed
# without ever reaching it.  Then it uses the m9c it just built to
# compile a program, because a compiler that builds and cannot compile
# is not a build.
set -e

repo=$(cd "$(dirname "$0")/../.." && pwd)
work=${TMPDIR:-/tmp}/m9-gcconly.$$
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src" "$work/bin"

cd "$repo"
git ls-files -z | xargs -0 tar -cf - | (cd "$work/src" && tar -xf -)

# a compiler that announces itself rather than one that is merely absent:
# "command not found" could be mistaken for a build that skipped a step
for tool in fpc ppcx64 gfortran python3; do
  cat > "$work/bin/$tool" <<EOF
#!/bin/sh
echo "GCCONLY: the build invoked $tool -- it is not gcc-only" >&2
exit 127
EOF
  chmod +x "$work/bin/$tool"
done

cd "$work/src"
if PATH="$work/bin:/usr/bin:/bin" CC="${CC:-gcc}" ./build.sh > "$work/log" 2>&1; then
  :
else
  echo "gcconly: build.sh FAILED with only a C compiler"
  tail -20 "$work/log"
  exit 1
fi
if grep -q "GCCONLY:" "$work/log"; then
  echo "gcconly: the build reached a tool it may not depend on"
  grep "GCCONLY:" "$work/log" | sort -u
  exit 1
fi
test -x out/m9c || { echo "gcconly: no out/m9c"; exit 1; }
test -f out/libm9rt.a || { echo "gcconly: no out/libm9rt.a"; exit 1; }

# and the artifact works: compile a program with it, still without the
# tools above on PATH
cat > "$work/Hello.m9" <<'EOF'
DEFINITION MODULE Hello ;
PROCEDURE Greet () ;
END Hello.

IMPLEMENTATION MODULE Hello ;
IMPORT Io ;
PROCEDURE Greet () =
BEGIN
  Io.WriteLine ('gcconly: a program compiled by the gcc-only build')
END Greet ;
END Hello.
EOF
cat > "$work/main.c" <<'EOF'
#include "m9rt.h"
#include "Hello.h"
int main (void) { m9_err e = {0}; Hello_Greet (&e); return 0; }
EOF
cd "$work"
PATH="$work/bin:/usr/bin:/bin" M9RUNTIME="$work/src/runtime" \
  M9LIBRARY="$work/src/corpus" "$work/src/out/m9c" --make -c Hello.m9 > "$work/c1" 2>&1 \
  || { echo "gcconly: m9c could not compile a program"; cat "$work/c1"; exit 1; }
PATH="$work/bin:/usr/bin:/bin" "${CC:-gcc}" -std=c11 -O2 -iquote "$work/src/runtime" \
  -iquote . main.c ./*.o "$work/src/out/libm9rt.a" -lm -o hello 2>>"$work/c1" \
  || { echo "gcconly: could not link"; cat "$work/c1"; exit 1; }
out=$(PATH="$work/bin:/usr/bin:/bin" ./hello)
case "$out" in
  *"a program compiled by the gcc-only build"*) ;;
  *) echo "gcconly: the program did not run: $out"; exit 1 ;;
esac

size=$(wc -c < "$work/src/out/m9c")
echo "gcconly: built m9c ($size bytes) and libm9rt.a with cc and ar alone,"
echo "         then compiled and ran a program with them"
