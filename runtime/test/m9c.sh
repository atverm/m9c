#!/bin/sh
# m9c: the compiler as a PROGRAM, not a library.
#
# Builds m9c from the generated toolchain, then has it compile a
# handful of modules -- including Gen, which generates code, and M9c
# itself -- and compares every byte against runtime/gen, which the
# FPC host produced.  gendiff already proves the M9 generator agrees
# with the oracle; this proves the same thing end to end, through
# argument handling, file reading, and file writing, in a process
# with no FPC in it.
set -e
cd "$(dirname "$0")"
C=../../corpus
G=../gen
OUT=/tmp/m9c-out

# runtime/gen is BOTH the source m9c is built from and the reference
# every byte is compared against, so this gate must produce it rather
# than find whatever an earlier run left behind.  A stale gen reports
# DIVERGES against agreeing generators -- which is how this was
# noticed, after Gen.m9 gained a case -- and a stale gen consistent
# with a stale m9c built from it reports agreement that is not there.
# Same hole bootstrap.sh had.
( cd ../../host/fpc && fpc -O2 gentest.pas >/dev/null && ./gentest >/dev/null )

gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c ../gen/Lex.c \
    ../gen/Ast.c ../gen/Parse.c ../gen/Print.c ../gen/Text.c \
    ../gen/Fmt.c ../gen/Sem.c ../gen/Gen.c ../gen/Doc.c ../gen/M9c.c -o m9c

M9C=$(pwd)/m9c
GEN=$(cd "$G" && pwd)
SRC=$(cd "$C" && pwd)
rm -rf "$OUT"; mkdir -p "$OUT"

check () {                      # check MODULE [DEP ...]
  m=$1; shift
  deps=""
  for d in "$@"; do deps="$deps $SRC/$d.m9"; done
  ( cd "$OUT" && "$M9C" "$SRC/$m.m9" $deps )
  cmp "$OUT/$m.h" "$GEN/$m.h" || { echo "DIVERGES: $m.h"; exit 1; }
  cmp "$OUT/$m.c" "$GEN/$m.c" || { echo "DIVERGES: $m.c"; exit 1; }
}

check DynStr
check Dict
check Json DynStr
check Lex DynStr
check Parse Ast Lex DynStr
check Gen Ast DynStr
check Sem Ast DynStr Fmt Print Text
check Io DynStr
check M9c Io Ast Parse Gen Sem DynStr Doc Lex

# usage and exit status are part of the tool, so they are checked too.
# Asking for help SUCCEEDS; getting the usage because you gave no
# arguments FAILS.  Conflating the two is why scripts end up parsing
# output instead of reading status.
if ./m9c >/dev/null 2>&1; then echo "FAIL: no-args should exit 1"; exit 1; fi
if ./m9c /nonexistent.m9 >/dev/null 2>&1; then
  echo "FAIL: missing file should exit 1"; exit 1
fi
for h in --help -h -\? --usage; do
  ./m9c "$h" >/dev/null 2>&1 || { echo "FAIL: $h should exit 0"; exit 1; }
done
./m9c --help | grep -q 'checks are semantics' ||
  { echo "FAIL: --help text missing"; exit 1; }

echo "m9c: 9 modules compiled by M9 itself, byte-identical to the oracle"

# the point of connecting Sem: a compiler that translates what it
# knows to be wrong is a translator.  A program with a semantic error
# must produce diagnostics on stderr, NO output files, and exit 1.
BAD=/tmp/m9c-bad
rm -rf "$BAD"; mkdir -p "$BAD"
printf 'MODULE bad ;\nVAR x : F64 ; i : I64 ;\nBEGIN\n  i := I64 (x)\nEND bad.\n' \
  > "$BAD/bad.m9"
( cd "$BAD" && "$M9C" bad.m9 >/dev/null 2>"$BAD/err.txt" ) && \
  { echo "FAIL: m9c accepted a program the checker rejects"; exit 1; }
grep -q 'unhandled RAISES ValueRange from I64 conversion' "$BAD/err.txt" || \
  { echo "FAIL: m9c did not report the diagnostic"; exit 1; }
[ -f "$BAD/bad.c" ] && { echo "FAIL: m9c emitted C for a rejected program"; exit 1; }
echo "m9c: rejects what the checker rejects, and emits nothing"

# -c / -o / --keep-c: the C is the OUTPUT until a C compiler has been
# run over it, and a BY-PRODUCT afterwards.  What is checked here is
# not that cc works but that m9c is honest about what it leaves on
# disk -- a flag that quietly keeps or drops files is how build
# scripts start describing something other than what happened.
RT=$(cd .. && pwd)
BLD=/tmp/m9c-build
rm -rf "$BLD"; mkdir -p "$BLD"
cd "$BLD"

"$M9C" -c "$SRC/DynStr.m9" -- -iquote "$RT" -iquote .
[ -f DynStr.o ] || { echo "FAIL: -c produced no object"; exit 1; }
[ -f DynStr.c ] && { echo "FAIL: -c left the C behind"; exit 1; }
# the header is the module's INTERFACE, not a by-product: the next
# module's generated C includes it, so -c must keep it
[ -f DynStr.h ] || { echo "FAIL: -c removed the header"; exit 1; }

"$M9C" -c --keep-c "$SRC/Io.m9" "$SRC/DynStr.m9" -- -iquote "$RT" -iquote .
[ -f Io.c ] || { echo "FAIL: --keep-c did not keep the C"; exit 1; }
[ -f Io.o ] || { echo "FAIL: --keep-c skipped the compile"; exit 1; }

# a whole program, linked, with no make and no build script in sight
"$M9C" -o hello "$SRC/Hello.m9" "$SRC/Io.m9" "$SRC/DynStr.m9" \
       -- -iquote "$RT" -iquote . "$RT/m9rt.c" Io.o DynStr.o
[ -f hello ] || { echo "FAIL: -o produced no executable"; exit 1; }
# -o leaves nothing downstream, so the header goes too
if [ -f Hello.c ] || [ -f Hello.h ]; then
  echo "FAIL: -o left C behind"; exit 1
fi
[ "$(./hello)" = "hello, world
1" ] || { echo "FAIL: the linked program printed the wrong thing"; exit 1; }
[ "$(./hello Alex)" = "hello, Alex
1" ] || { echo "FAIL: arguments did not reach the linked program"; exit 1; }

# a C compiler that fails must fail m9c, and must not be reported as
# success just because the M9 half went fine
if "$M9C" -c "$SRC/DynStr.m9" -- -iquote . -DM9_NO_SUCH 2>/dev/null; then
  echo "FAIL: cc errors did not fail m9c"; exit 1
fi

# -g: adds debug information and changes NOTHING else.  Both halves
# are checked, because the one an assumption gets wrong is that a
# plain build has none -- the objects are not stripped, so symbols
# are there and it is easy to believe the line tables are too.
# $M9RUNTIME so the flagless commands below can find m9rt.h; the
# section above deliberately spells every path out after --, and -g
# has to be tested WITHOUT -- because -- turns it off.
export M9RUNTIME="$RT"
export M9LIBRARY="$SRC"

# CHECKED ON THE PROGRAM, NOT THE OBJECT, and the reason is the same
# one --pic already taught: m9c compiles with -flto, so a -c object
# holds intermediate code -- 26 .gnu.lto_* sections and no
# .debug_info at all -- and the DWARF is produced when the program is
# LINKED.  Asserting .debug_info on the object is asserting the wrong
# artifact, which is how this test failed the first time it ran.
if command -v readelf >/dev/null 2>&1; then
  rm -f DynStr.o DynStr.c Io.o Io.c hello hellog Hello.c Hello.h
  "$M9C" -c "$SRC/DynStr.m9"
  "$M9C" -c "$SRC/Io.m9"
  "$M9C" -o hello "$SRC/Hello.m9"
  [ "$(readelf -S hello | grep -c debug_info)" = 0 ] ||
    { echo "FAIL: a plain build carries debug information"; exit 1; }

  rm -f DynStr.o DynStr.c Io.o Io.c
  "$M9C" -g -c "$SRC/DynStr.m9"
  # -g implies --keep-c, and must: the debug information NAMES this file
  [ -f DynStr.c ] ||
    { echo "FAIL: -g did not keep the C its debug info names"; exit 1; }
  "$M9C" -g -c "$SRC/Io.m9"
  "$M9C" -g -o hellog "$SRC/Hello.m9"
  [ "$(readelf -S hellog | grep -c debug_info)" != 0 ] ||
    { echo "FAIL: -g produced no debug information"; exit 1; }
  readelf --debug-dump=info hellog | grep -q 'Hello\.c' ||
    { echo "FAIL: the debug information does not name the generated C"; exit 1; }
  # and it is still the same program
  [ "$(./hellog M9)" = "hello, M9
1" ] || { echo "FAIL: -g changed the program"; exit 1; }
fi

# -g is an OPTION, not a source file.  ScanArgs and SourceAt keep two
# independent lists of the option spellings and nothing checks that
# they agree, so a flag added to one and not the other becomes a file
# name -- which is what this asserts.
rm -f DynStr.o DynStr.c
"$M9C" -g -c "$SRC/DynStr.m9" 2>/tmp/m9c-g.txt
grep -q 'cannot find' /tmp/m9c-g.txt &&
  { echo "FAIL: -g was taken for a source file"; exit 1; }

# and it is off unless asked for, and off again after --
"$M9C" -v -g -c "$SRC/DynStr.m9" 2>/tmp/m9c-g.txt
[ "$(sed -n 's/.*\( -g\).*/x/p' /tmp/m9c-g.txt | wc -l)" = 1 ] ||
  { echo "FAIL: -g not on the compiler line exactly once"; exit 1; }
"$M9C" -v -c "$SRC/DynStr.m9" 2>/tmp/m9c-nog.txt
grep -q -- ' -g' /tmp/m9c-nog.txt &&
  { echo "FAIL: -g appeared without being asked for"; exit 1; }
"$M9C" -v -g -c "$SRC/DynStr.m9" -- -c -O2 -iquote "$RT" -iquote . 2>/tmp/m9c-gd.txt
grep -q -- ' -g' /tmp/m9c-gd.txt &&
  { echo "FAIL: -- did not turn -g off with the other defaults"; exit 1; }

echo "m9c: -g adds debug information, keeps the C it names, and"
echo "     changes nothing else"

echo "m9c: -c, -o and --keep-c leave exactly what they say they leave"

# The search path: IMPORT names a module, and m9c translates that to
# a file so the caller does not have to.  Everything above named its
# dependencies explicitly and still produced oracle-identical bytes;
# this names NOTHING and must produce the same program.
PATHT=/tmp/m9c-path
rm -rf "$PATHT"; mkdir -p "$PATHT"; cd "$PATHT"

# no -I, no $M9LIBRARY, no deps: the main file's own directory is on
# the path, because a module's neighbours are almost always its imports
"$M9C" -c "$SRC/DynStr.m9" -- -iquote "$RT" -iquote .
"$M9C" -c "$SRC/Io.m9"     -- -iquote "$RT" -iquote .
"$M9C" -o hello "$SRC/Hello.m9" \
       -- -iquote "$RT" -iquote . "$RT/m9rt.c" Io.o DynStr.o
[ "$(./hello M9)" = "hello, M9
1" ] || { echo "FAIL: resolved-import build behaves differently"; exit 1; }

# $M9LIBRARY, and the argument as a MODULE rather than a path
rm -rf "$PATHT/lib"; mkdir -p "$PATHT/lib"; cd "$PATHT/lib"
M9LIBRARY="$SRC" "$M9C" -c DynStr -- -iquote "$RT" -iquote .
[ -f DynStr.o ] || { echo "FAIL: \$M9LIBRARY did not resolve"; exit 1; }
"$M9C" -I "$SRC" -c Json -- -iquote "$RT" -iquote .
[ -f Json.o ] || { echo "FAIL: -I did not resolve"; exit 1; }
"$M9C" "-I$SRC" -c Text -- -iquote "$RT" -iquote .
[ -f Text.o ] || { echo "FAIL: -IDIR joined did not resolve"; exit 1; }

# A module that cannot be found is fatal BEFORE generation: without
# its source everything downstream is guesswork, and the fourteen
# generator errors this produced the first time were one problem said
# fourteen times.  Every missing module is still named -- errors are
# values, and a list of them beats the first one.
#
# The imports are named so that nothing can satisfy them: the search
# path ends at /usr/lib/m9, so a test that hid the real Io and DynStr
# would pass on a developer's machine and fail on one with the package
# installed -- which is exactly what happened the first time this ran.
rm -rf "$PATHT/only"; mkdir -p "$PATHT/only"; cd "$PATHT"
cat > only/Orphan.m9 <<'M9'
MODULE Orphan ;
IMPORT NoSuchModuleAnywhere ;
IMPORT NorThisOne ;
BEGIN
END Orphan.
M9
if "$M9C" -I only Orphan 2>"$PATHT/miss.txt"; then
  echo "FAIL: unresolved imports should exit 1"; exit 1
fi
grep -q 'cannot find module NoSuchModuleAnywhere' "$PATHT/miss.txt" || {
  echo "FAIL: missing module not named"; exit 1; }
grep -q 'cannot find module NorThisOne' "$PATHT/miss.txt" || {
  echo "FAIL: only the first missing module was named"; exit 1; }
if [ -f Orphan.c ]; then echo "FAIL: emitted C despite a missing module"; exit 1; fi

echo "m9c: imports resolve through -I, \$M9LIBRARY and the source dir"

# ---- the flags nobody should have to type ----
#
# Every command above named every include path and every object after
# --, which is four flags of which three were the same every time.
# What is checked here is that with nothing after --, m9c supplies
# them by LOOKING -- and that the program it builds is the same
# program, byte for byte the same behaviour as the spelled-out one.
DEF=/tmp/m9c-default
rm -rf "$DEF"; mkdir -p "$DEF"; cd "$DEF"

# $M9RUNTIME is what a source tree needs: this runs in a scratch
# directory, so neither runtime/ nor ../runtime/ is the runtime, and
# /usr/include/m9 is the INSTALLED answer, which a source tree must
# not depend on being present or absent
export M9RUNTIME="$RT"
export M9LIBRARY="$SRC"

"$M9C" -c DynStr
"$M9C" -c Io
"$M9C" -v -o hello Hello 2>verbose.txt
[ "$(./hello M9)" = "hello, M9
1" ] || { echo "FAIL: the default build produced a different program"; exit 1; }

# -v prints the command, which is the only way to check WHAT was
# supplied rather than merely that something linked
grep -q -- "-iquote $RT" verbose.txt ||
  { echo "FAIL: the runtime include path was not supplied"; exit 1; }
grep -q -- '-iquote \.' verbose.txt ||
  { echo "FAIL: the working directory was not on the include path"; exit 1; }
for o in DynStr.o Io.o; do
  grep -q "$o" verbose.txt ||
    { echo "FAIL: $o, in the import closure, was not linked"; exit 1; }
done
grep -q 'm9rt.c' verbose.txt ||
  { echo "FAIL: the runtime was not linked"; exit 1; }
grep -q -- '-lm' verbose.txt || { echo "FAIL: -lm was not supplied"; exit 1; }
# the module being compiled is not one of its own dependencies
grep -q ' Hello.o' verbose.txt &&
  { echo "FAIL: m9c tried to link the object it is producing"; exit 1; }

# a missing object is NAMED, with the command that makes it: the
# alternative is the C linker explaining our omission in its own
# vocabulary ("undefined reference to DynStr_New")
rm -f DynStr.o hello
if "$M9C" -o hello Hello 2>miss.txt; then
  echo "FAIL: a missing object should fail the link"; exit 1
fi
grep -q 'DynStr.o is missing' miss.txt ||
  { echo "FAIL: the missing object was not named"; exit 1; }
grep -q 'm9c -c DynStr' miss.txt ||
  { echo "FAIL: the command that makes it was not given"; exit 1; }
# and it is refused BEFORE cc runs, so nothing half-built appears
[ -f hello ] && { echo "FAIL: a program was linked anyway"; exit 1; }

# -- turns every one of these off.  The same link, with the caller's
# own line, must fail for want of the objects m9c would have added:
# a default that survives underneath a flag someone chose is worse
# than no default at all.
"$M9C" -c DynStr
if "$M9C" -o hello Hello -- -iquote "$RT" -iquote . 2>/dev/null; then
  echo "FAIL: -- did not turn the defaults off"; exit 1
fi

# $M9RUNTIME pointing at the wrong directory is answered by the
# compiler that read the variable, not by cc failing over a missing
# include three steps later.  Only the diagnostic is asserted: where
# the search goes next depends on whether this machine has the
# package installed, and a test that cared would pass on a developer's
# machine and fail on a user's.
mkdir -p "$DEF/nort"; cd "$DEF/nort"
M9RUNTIME=/nonexistent "$M9C" -c DynStr 2>nort.txt || true
grep -q 'M9RUNTIME' nort.txt ||
  { echo 'FAIL: a wrong $M9RUNTIME was not reported'; exit 1; }
cd "$DEF"

echo "m9c: with nothing after --, the include paths, the closure's"
echo "     objects and the runtime are found rather than typed"

# ---- the closure as a LIBRARY: --ar, --so, --pic ----
#
# "Distribute the compiler without sources" is the ask, so that is
# what is checked: build the compiler's whole import closure, archive
# it, and then LINK AND RUN A COMPILER out of the archive alone, in a
# directory with no .m9 in it, and require the C it emits to be
# byte-identical to the oracle's.  A library that produces different
# bytes from the program built the same afternoon is not the same
# compiler however well it links.
LIB=/tmp/m9c-lib
rm -rf "$LIB"; mkdir -p "$LIB"; cd "$LIB"
export M9RUNTIME="$RT"
export M9LIBRARY="$SRC"

for m in DynStr Text Io Lex Ast Parse Print Sem Gen Doc; do "$M9C" -c $m; done
"$M9C" -v --ar libm9.a M9c 2>ar.txt
[ -f libm9.a ] || { echo "FAIL: --ar produced no archive"; exit 1; }
# the members are the closure m9c just resolved, and its own object
for o in M9c.o DynStr.o Io.o Lex.o Ast.o Parse.o Print.o Sem.o Gen.o Doc.o; do
  ar t libm9.a | grep -qx "$o" ||
    { echo "FAIL: $o is not in the archive"; exit 1; }
done
# the runtime is NOT in it: it is its own deliverable, and two copies
# of m9rt in one link is the thing that rule exists to prevent
ar t libm9.a | grep -q 'm9rt' &&
  { echo "FAIL: the runtime was buried in the archive"; exit 1; }
# the headers are the other half of the deliverable
for h in M9c.h DynStr.h Sem.h Gen.h; do
  [ -f "$h" ] || { echo "FAIL: --ar did not keep $h"; exit 1; }
done

mkdir -p fromlib && cd fromlib
gcc -std=c11 -O2 -iquote "$RT" -iquote .. "$RT/m9rt.c" ../libm9.a -lm \
    -o m9c-from-lib 2>/dev/null
[ -f m9c-from-lib ] || { echo "FAIL: the archive would not link"; exit 1; }
./m9c-from-lib "$SRC/Json.m9" || { echo "FAIL: the library compiler failed"; exit 1; }
cmp Json.c "$GEN/Json.c" ||
  { echo "DIVERGES: a compiler built from the archive emits different C"; exit 1; }
cmp Json.h "$GEN/Json.h" ||
  { echo "DIVERGES: a compiler built from the archive emits a different header"; exit 1; }
cd "$LIB"

# --so.  BOTH halves of the -fPIC story are checked, because the
# working one is what an assumption got wrong: this was written
# believing every member of a shared object must be built -fPIC, and
# it is only half true.  m9c compiles with -flto, so a -c object is
# LTO IR and the code generation happens at LINK time, where -shared
# asks for position-independent code and gets it.  So the closure
# built above with a plain `m9c -c` goes into a .so and WORKS.
#
# Json rather than M9c for the callable half: a shared object carrying
# main() links, but a LIBRARY is the thing worth proving, so a C
# program calls into it.
SO=/tmp/m9c-so
rm -rf "$SO"; mkdir -p "$SO"; cd "$SO"
"$M9C" -c DynStr                    # NO --pic, on purpose
"$M9C" --so libm9json.so Json
[ -f libm9json.so ] || { echo "FAIL: --so produced no shared object"; exit 1; }
cat > use.c <<'USE'
#include <stdio.h>
#include <string.h>
#include "Json.h"
static uint32_t sb[256];
static m9_sl_CHAR S (const char *s)
{ size_t i, n = strlen (s); for (i = 0; i < n; i++) sb[i] = (unsigned char) s[i];
  return (m9_sl_CHAR){ sb, (int64_t) n }; }
int main (void)
{
  m9_pool p = {0}; m9_state e = {0};
  Json_Node *root = Json_Parse (&p, S ("{\"a\":[1,2,{\"b\":true}]}"), &e);
  Json_Node *a = Json_Field (root, S ("a"), &e);
  Json_Node *b = Json_Field (Json_Item (a, 2, &e), S ("b"), &e);
  printf ("%lld %s %s\n", (long long) Json_Count (a, &e),
          Json_AsBool (b, &e) ? "true" : "false",
          e.exc ? e.exc->name : "none");
  return 0;
}
USE
gcc -std=c11 -O2 -iquote . -iquote "$RT" use.c ./libm9json.so \
    -Wl,-rpath,"$SO" -lm -o use 2>/dev/null
[ -f use ] || { echo "FAIL: the shared object would not link"; exit 1; }
[ "$(./use)" = "3 true none" ] ||
  { echo "FAIL: calling M9 through the shared object gave the wrong answer"; exit 1; }
ldd use | grep -q libm9json.so ||
  { echo "FAIL: the program did not actually load the shared object"; exit 1; }

# and the other half: with the caller's own flags after --, LTO goes
# with the rest of the defaults, the object really is machine code,
# and ld refuses it.  m9c must fail and must name the flag that fixes
# it, rather than leaving the C linker to explain our omission in its
# own vocabulary.
NOLTO=/tmp/m9c-nolto
rm -rf "$NOLTO"; mkdir -p "$NOLTO"; cd "$NOLTO"
"$M9C" -c DynStr -- -c -O2 -iquote "$RT" -iquote .
if "$M9C" --so libbad.so Json 2>so-bad.txt; then
  echo "FAIL: --so over a really-compiled non-PIC object should fail"; exit 1
fi
grep -q -- '--pic' so-bad.txt ||
  { echo "FAIL: the --so refusal did not name --pic"; exit 1; }
[ -f libbad.so ] && { echo "FAIL: a broken shared object was left behind"; exit 1; }
# and --pic is the fix it named
"$M9C" -c DynStr -- -c -O2 -fPIC -iquote "$RT" -iquote .
"$M9C" --so libgood.so Json
[ -f libgood.so ] || { echo "FAIL: --pic did not fix the shared link"; exit 1; }

echo "m9c: --ar and --so build the closure as a library, and a compiler"
echo "     linked from the archive alone emits the oracle's bytes"

# --no-unsafe: the language wall for running untrusted code.  A cell
# may import the shipped library (whose own FOR "C" units are the
# audited foreign boundary, found through $M9LIBRARY) and may NOT
# declare foreign or UNSAFE units of its own, wherever they hide in
# the closure.  Probed both ways, like every flag: the refusal must
# fire WITH the unit named, and the same programs must build without
# the flag -- a refusal that fires always is a broken compiler, not a
# security feature.
NOUNS=/tmp/m9c-nounsafe
rm -rf "$NOUNS"; mkdir -p "$NOUNS"; cd "$NOUNS"
cat > Cell.m9 <<'M9'
MODULE Cell ;
IMPORT Io ;
IMPORT Sneak ;
BEGIN
  Io.WriteLine ('up')
END Cell.
M9
cat > Sneak.m9 <<'M9'
DEFINITION MODULE Sneak ;
PROCEDURE Ping () ;
END Sneak.

IMPLEMENTATION MODULE Sneak ;
PROCEDURE Ping () = BEGIN END Ping ;
END Sneak.

UNSAFE DEFINITION MODULE FOR "C" clibc ;
PROCEDURE Pid = "getpid" () : C.Int [REENTRANT] ;
END clibc.
M9
M9LIBRARY="$SRC" "$M9C" --make -c -k ./Cell.m9 >/dev/null 2>&1 ||
  { echo "FAIL: the foreign-unit cell should build WITHOUT --no-unsafe"; exit 1; }
if M9LIBRARY="$SRC" "$M9C" --no-unsafe --make -c ./Cell.m9 2>nu.txt; then
  echo "FAIL: --no-unsafe accepted a foreign unit outside the library"; exit 1
fi
grep -q 'foreign unit clibc' nu.txt ||
  { echo "FAIL: the --no-unsafe refusal did not name the unit"; exit 1; }

cat > Cell2.m9 <<'M9'
MODULE Cell2 ;
IMPORT Io ;
IMPORT Peek ;
BEGIN
  IF Peek.NonZero () THEN Io.WriteLine ('somewhere') END
END Cell2.
M9
cat > Peek.m9 <<'M9'
DEFINITION MODULE Peek ;
PROCEDURE NonZero () : BOOL ;
END Peek.

UNSAFE IMPLEMENTATION MODULE Peek ;
PROCEDURE NonZero () : BOOL =
VAR buf : ARRAY 4 OF BYTE ;
BEGIN
  buf[0] := 1 ;
  RETURN ADR (buf) # 0
END NonZero ;
END Peek.
M9
rm -f Sneak.o Cell.o
M9LIBRARY="$SRC" "$M9C" --make -c -k ./Cell2.m9 >/dev/null 2>&1 ||
  { echo "FAIL: the UNSAFE-unit cell should build WITHOUT --no-unsafe"; exit 1; }
if M9LIBRARY="$SRC" "$M9C" --no-unsafe --make -c ./Cell2.m9 2>nu2.txt; then
  echo "FAIL: --no-unsafe accepted an UNSAFE unit outside the library"; exit 1
fi
grep -q 'UNSAFE unit Peek' nu2.txt ||
  { echo "FAIL: the --no-unsafe refusal did not name the UNSAFE unit"; exit 1; }

# and the trusted half: the shipped library's own foreign units (Io
# binds cio) pass through $M9LIBRARY under the same flag
cat > Clean.m9 <<'M9'
MODULE Clean ;
IMPORT Io ;
BEGIN
  Io.WriteLine ('clean')
M9
echo 'END Clean.' >> Clean.m9
M9LIBRARY="$SRC" "$M9C" --no-unsafe --make -c ./Clean.m9 >/dev/null 2>&1 ||
  { echo "FAIL: --no-unsafe refused a clean cell over the trusted library"; exit 1; }

echo "m9c: --no-unsafe refuses foreign and UNSAFE units outside the"
echo "     library, names them, and passes the trusted closure"

# QUALIFIED exception identity: Io.IOError and PondA.Splash are
# different descriptors even when a second module declares the same
# bare name.  The generators used to drop the qualifier and match
# whichever module registered the name first; a handler for
# ZarrStore.IOError compiled to a test against &Io_IOError and
# matched nothing (found by the tutorial service's no-network zarr
# cell).  This runs a program whose handler can only succeed if the
# qualifier is honoured.
QEXC=/tmp/m9c-qexc
rm -rf "$QEXC"; mkdir -p "$QEXC"; cd "$QEXC"
cat > PondA.m9 <<'M9'
DEFINITION MODULE PondA ;
EXCEPTION Splash (depth: I64) ;
PROCEDURE Drop (d: I64) RAISES Splash ;
END PondA.

IMPLEMENTATION MODULE PondA ;
PROCEDURE Drop (d: I64) RAISES Splash =
BEGIN
  RAISE Splash (d)
END Drop ;
END PondA.
M9
cat > PondB.m9 <<'M9'
DEFINITION MODULE PondB ;
EXCEPTION Splash (depth: I64) ;
PROCEDURE Calm () ;
END PondB.

IMPLEMENTATION MODULE PondB ;
PROCEDURE Calm () = BEGIN END Calm ;
END PondB.
M9
cat > QExc.m9 <<'M9'
MODULE QExc ;
IMPORT Io ;
IMPORT PondB ;
IMPORT PondA ;
BEGIN
  PondB.Calm () ;
  PondA.Drop (3) ;
  Io.WriteLine ('no splash?!')
EXCEPT
| PondA.Splash (depth) :
    Io.Write ('PondA.Splash caught, depth ') ;
    Io.WriteI64 (depth) ;
    Io.WriteLine ('')
| PondB.Splash (depth) :
    Io.WriteLine ('WRONG POND')
END QExc.
M9
M9LIBRARY="$SRC" "$M9C" --make -o qexc ./QExc.m9 >/dev/null 2>&1 ||
  { echo "FAIL: the qualified-exception program should build"; exit 1; }
[ "$(./qexc)" = "PondA.Splash caught, depth 3" ] ||
  { echo "FAIL: a qualified handler matched the wrong module's exception"; exit 1; }

echo "m9c: a qualified handler catches exactly the module it names"

# generator errors carry LINES AND MESSAGES now: the count alone cost
# a bisect every time a module was written outside the corpus, and
# then cost one inside the tutorial (a reversed NEW).
#
# THE PROBE USED TO BE THAT REVERSED NEW and cannot be any more: the
# CHECKER refuses it since 2026-08-30 ("NEW takes the pool first"),
# so the generator never sees it -- a gate broken by its own defect
# being fixed one layer earlier, which is the right way round.  The
# trigger here is EXIT inside a CASE arm: the checker passes it and
# the generator refuses it, because a C switch would swallow the
# break.  The reversed NEW is checked below, where it belongs now.
GMSG=/tmp/m9c-genmsg
rm -rf "$GMSG"; mkdir -p "$GMSG"; cd "$GMSG"
cat > Exc.m9 <<'M9'
MODULE Exc ;
IMPORT Io ;
VAR i : I64 ;
BEGIN
  i := 0 ;
  LOOP
    CASE i OF
    | 0 : EXIT
    ELSE i := 1
    END
  END ;
  Io.WriteLine ('no')
END Exc.
M9
if M9LIBRARY="$SRC" "$M9C" --make -c ./Exc.m9 2>gm.txt; then
  echo "FAIL: EXIT inside a CASE arm should be refused"; exit 1
fi
grep -q 'Exc.m9:8: gen: EXIT inside a CASE arm' gm.txt ||
  { echo "FAIL: the generator error lost its line or message:"; \
    head -3 gm.txt; exit 1; }

# and the reversed NEW, which the CHECKER now catches -- with its own
# line and column, before a single byte of C is generated
cat > Rev.m9 <<'M9'
MODULE Rev ;
IMPORT Io ;
TYPE
  P = RECORD
    x : F64 ;
  END ;
VAR
  pool : POOL ;
  p : PTR P IN pool ;
BEGIN
  p := NEW (P, pool) ;
  p.x := 1.0 ;
  Io.WriteLine ('no')
END Rev.
M9
if M9LIBRARY="$SRC" "$M9C" --make -c ./Rev.m9 2>rv.txt; then
  echo "FAIL: a reversed NEW should be refused"; exit 1
fi
grep -q '11:8 Rev body: NEW takes the pool first, then the type' rv.txt ||
  { echo "FAIL: the checker did not name the reversed NEW:"; \
    head -3 rv.txt; exit 1; }

echo "m9c: generator errors name their line and their reason"

# --json: the declarations as data, and the page unchanged by it.
# DynStr is the probe because its AppendChar has every field the
# schema carries -- VAR params, a PTR type, no result, no RAISES --
# and New has a result and an IN-pool type.  The .md written beside
# the .json must be byte-identical to the golden docdiff holds, or
# --json would be changing --doc.
JD=/tmp/m9c-json
rm -rf "$JD"; mkdir -p "$JD"; cd "$JD"
M9LIBRARY="$SRC" "$M9C" --json "$SRC/DynStr.m9" ||
  { echo "FAIL: --json refused DynStr.m9"; exit 1; }
[ -f DynStr.json ] || { echo "FAIL: --json wrote no DynStr.json"; exit 1; }
[ -f DynStr.md ] || { echo "FAIL: --json did not also write the page"; exit 1; }
cmp DynStr.md "$SRC/../docs/modules/DynStr.md" ||
  { echo "FAIL: --json changed what --doc writes"; exit 1; }

for want in '"module":"DynStr"' '"kind":"procedure","name":"AppendChar"' \
            '{"names":["pool"],"mode":"VAR","type":"POOL"}' \
            '"mode":"RO"' '"result":"PTR DString IN pool"' \
            '"kind":"type","name":"DString"' '"raises":['; do
  grep -qF "$want" DynStr.json ||
    { echo "FAIL: DynStr.json lacks $want"; head -c 600 DynStr.json; exit 1; }
done
python3 -c 'import json,sys; d=json.load(open("DynStr.json")); \
  p=[x for x in d["declarations"] if x["name"]=="AppendChar"][0]; \
  assert p["params"][1]["mode"]=="VAR" and p["result"] is None, p; \
  print("m9c: --json parses, %d declarations" % len(d["declarations"]))' ||
  { echo "FAIL: DynStr.json is not the JSON a reader expects"; exit 1; }
if M9LIBRARY="$SRC" "$M9C" --json -c "$SRC/DynStr.m9" 2>jc.txt; then
  echo "FAIL: --json with -c should be refused like --doc with -c"; exit 1
fi
grep -q 'cannot be combined' jc.txt ||
  { echo "FAIL: the --json/-c refusal lost its message"; cat jc.txt; exit 1; }

echo "m9c: --json is the page as data, and the page is unchanged"
# --check: the diagnostics with EMPTY HANDS.  An editor invokes this
# per save, so a .h/.c/.md appearing beside the file would arm the
# generated-header-shadows trap on every keystroke.  Probed both
# ways: a clean module writes NOTHING and exits 0; a broken one
# exits 1 with the diagnostic on stderr; combining with -c refused.
CK=/tmp/m9c-check
rm -rf "$CK"; mkdir -p "$CK"; cd "$CK"
M9LIBRARY="$SRC" "$M9C" --check "$SRC/DynStr.m9" ||
  { echo "FAIL: --check refused a clean DynStr.m9"; exit 1; }
[ -z "$(ls -A "$CK")" ] ||
  { echo "FAIL: --check wrote files:"; ls -A "$CK"; exit 1; }
cat > Broke.m9 <<'BRK'
MODULE Broke ;
VAR i : I64 ;
BEGIN
  i := 'text'
END Broke.
BRK
if M9LIBRARY="$SRC" "$M9C" --check Broke.m9 2>ck.err; then
  echo "FAIL: --check accepted an ill-typed program"; exit 1
fi
grep -q "cannot assign" ck.err ||
  { echo "FAIL: --check exit 1 without the diagnostic:"; cat ck.err; exit 1; }
if "$M9C" --check -c "$SRC/DynStr.m9" 2>/dev/null; then
  echo "FAIL: --check -c should be refused"; exit 1
fi
echo "m9c: --check answers diagnostics and writes nothing"

# THE VERSION CANNOT DRIFT FROM THE CHANGELOG.  Two releases in a row
# shipped a first build whose receipt said the previous version,
# because M9c.m9's Version constant is bumped by hand.  The receipt
# caught it both times; this catches it before a VM ever boots.
CLV=$(cd "$SRC/.." && sh tools/release/version.sh)
BV=$("$M9C" --version | sed 's/^m9c //')
[ "$BV" = "$CLV" ] || {
  echo "FAIL: m9c --version says $BV but debian/changelog says $CLV";
  echo "  bump Version in corpus/M9c.m9"; exit 1; }
echo "m9c: --version agrees with the changelog ($BV)"

# --make BUILDS IN DEPENDENCY ORDER, and a DIAMOND is what proves it.
# loaded[] is filled pre-order (a name is marked before its imports
# are walked, so a cycle terminates), and reversing pre-order is a
# topological sort for a TREE and not for a DAG: Top importing Mid and
# Base, with Mid importing Base, gave Mid before the Base.h it
# includes, and the build converged by REPETITION -- exit 1 with nine
# `Kind.h: No such file` on the first run in the port, exit 0 on the
# second (2026-08-25).  order[] is post-order now and MakeAll walks it
# forward.  Shown able to fail: the pre-fix compiler dies here with
# `Mid.h:5: #include "Base.h": No such file`.
cat > Base.m9 <<'M9'
DEFINITION MODULE Base ;
TYPE Real = F64 ;
PROCEDURE Two () : Real ;
END Base.

IMPLEMENTATION MODULE Base ;
PROCEDURE Two () : Real =
BEGIN
  RETURN 2.0
END Two ;
END Base.
M9
cat > Mid.m9 <<'M9'
DEFINITION MODULE Mid ;
IMPORT Base ;
PROCEDURE Twice (x: Base.Real) : Base.Real ;
END Mid.

IMPLEMENTATION MODULE Mid ;
IMPORT Base ;
PROCEDURE Twice (x: Base.Real) : Base.Real =
BEGIN
  RETURN x * Base.Two ()
END Twice ;
END Mid.
M9
cat > Diamond.m9 <<'M9'
MODULE Diamond ;
IMPORT Base ;
IMPORT Mid ;
IMPORT Io ;
VAR x : Base.Real ;
BEGIN
  x := Mid.Twice (Base.Two ()) ;
  IF x = 4.0 THEN Io.WriteLine ('diamond ok') ELSE Io.WriteLine ('diamond WRONG') END
END Diamond.
M9
# AND THE SHARED MODULE IS IMPORTED SECOND, which is the case the
# first version of this gate could not see: Top importing Base then
# Mid passed even while the ordering was wrong, because Base happened
# to be marked loaded first.  With Mid FIRST, Base is a direct import
# that is also Mid's dependency -- LoadDirect marks it before any
# subtree is walked -- and the arrival-order fix put Mid ahead of it.
# The order is computed from the import GRAPH now, so both spellings
# build.  Found by an I/O probe importing Http, Io, Time, Fmt where
# Time imports Fmt (2026-08-30).
cat > Diamond2.m9 <<'M9'
MODULE Diamond2 ;
IMPORT Mid ;
IMPORT Base ;
IMPORT Io ;
VAR x : Base.Real ;
BEGIN
  x := Mid.Twice (Base.Two ()) ;
  IF x = 4.0 THEN Io.WriteLine ('diamond ok') ELSE Io.WriteLine ('diamond WRONG') END
END Diamond2.
M9
rm -f Base.o Base.h Mid.o Mid.h diamond diamond2
M9LIBRARY="$SRC" "$M9C" --make -o diamond2 Diamond2.m9 >dm2.txt 2>&1 ||
  { echo "FAIL: --make could not build a diamond whose shared module is imported second:";     head -5 dm2.txt; exit 1; }
[ "$(./diamond2)" = "diamond ok" ] ||
  { echo "FAIL: the second diamond built but answered wrong"; ./diamond2; exit 1; }

rm -f Base.o Base.h Mid.o Mid.h diamond
# AND THE MAIN FILE IS NAMED BARE, no -I and no ./ -- the search
# path's last entry is "the directory FILE.m9 came from", which for a
# bare name is this one; DirOf answered empty and DirAdd dropped it,
# so a program compiled in the very directory its imports sit in
# could not find them (found 2026-08-30 writing the diamond above).
M9LIBRARY="$SRC" "$M9C" --make -o diamond Diamond.m9 >dm.txt 2>&1 ||
  { echo "FAIL: --make could not build a diamond on the first run:"; \
    head -5 dm.txt; exit 1; }
[ "$(./diamond)" = "diamond ok" ] ||
  { echo "FAIL: the diamond built but answered wrong"; ./diamond; exit 1; }

echo "m9c: --make builds a diamond in dependency order, first run"
