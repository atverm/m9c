#!/bin/sh
# m9c --run: build into the cache, then BECOME the program.
#
# What is held: the program is told its own name, its arguments (an
# option-shaped one included -- it is the program's, not m9c's), its
# stdin and its exit status; an unchanged program starts with NO C
# compiler run (-v prints every command m9c runs, and must print
# none); an edit to an IMPORTED module is seen although the program's
# text did not change, and undoing it is the old key again; a refused
# program exits 1 and leaves no binary; --run beside an output flag is
# refused; a #! file runs as an executable; --out-dir puts the C where
# it is told.
#
# A GATE OF ITS OWN, not the tail of m9c.sh, because m9c.sh stops at
# its ldd line on macOS and its later half never runs there -- and
# --run is meant to work on macOS (Alex, 2026-10-04).  Shown able to
# fail with two sabotaged compilers (2026-10-04): a key that ignores
# the imports' text fails the edited-import check, a warm path that
# never reuses the binary fails the unchanged-run check.
#
# Uses the m9c that m9c.sh builds (run after it, as ci.yml does), or
# $M9C, or out/m9c.
set -e
cd "$(dirname "$0")"

M9C=${M9C:-}
[ -n "$M9C" ] || { [ -x ./m9c ] && M9C=$(pwd)/m9c; }
[ -n "$M9C" ] || { [ -x ../../out/m9c ] && M9C=$(cd ../../out && pwd)/m9c; }
[ -n "$M9C" ] || { echo "run: no m9c (run m9c.sh or build.sh)"; exit 1; }

export M9RUNTIME=$(cd .. && pwd)
export M9LIBRARY=$(cd ../../corpus && pwd)
FIX=$(cd runfix && pwd)
RW=/tmp/m9c-run
rm -rf "$RW"; mkdir -p "$RW/src"
cp "$FIX/RunEcho.m9" "$FIX/RunHelper.m9" "$RW/src/"
export M9CACHE="$RW/cache"
( cd "$RW" &&
  st=0
  printf 'abc' | "$M9C" --run src/RunEcho.m9 one "two words" -v > o1.txt 2> e1.txt || st=$?
  [ $st = 3 ] || { echo "FAIL: --run status $st, wanted 3"; cat e1.txt; exit 1; }
  printf 'name src/RunEcho.m9\narg one\narg two words\narg -v\nstdin 3\ngreeting 1\n' > want1.txt
  cmp -s o1.txt want1.txt || { echo "FAIL: --run told the program:"; cat o1.txt; exit 1; }
  ls cache/bin/RunEcho-* > /dev/null 2>&1 || { echo "FAIL: --run left no binary"; exit 1; }
  # unchanged: no C compiler, no checker -- nothing but the program
  "$M9C" -v --run src/RunEcho.m9 < /dev/null > o2.txt 2> e2.txt
  [ ! -s e2.txt ] || { echo "FAIL: an unchanged --run ran something:"; cat e2.txt; exit 1; }
  grep -q '^greeting 1$' o2.txt || { echo "FAIL: warm --run answered:"; cat o2.txt; exit 1; }
  # an edit BELOW the program is seen
  sed 's/greeting 1/greeting 2/' "$FIX/RunHelper.m9" > src/RunHelper.m9
  "$M9C" --run src/RunEcho.m9 < /dev/null > o3.txt 2>&1
  grep -q '^greeting 2$' o3.txt || { echo "FAIL: an edited import was not seen:"; cat o3.txt; exit 1; }
  # and undoing it is the old key: nothing compiled
  cp "$FIX/RunHelper.m9" src/RunHelper.m9
  "$M9C" -v --run src/RunEcho.m9 < /dev/null > o4.txt 2> e4.txt
  [ ! -s e4.txt ] || { echo "FAIL: an undone edit was compiled again:"; cat e4.txt; exit 1; }
  grep -q '^greeting 1$' o4.txt || { echo "FAIL: an undone edit answered:"; cat o4.txt; exit 1; }
  if ls -d cache/tmp/* > /dev/null 2>&1; then
    echo "FAIL: --run left its scratch behind:"; ls cache/tmp; exit 1
  fi
  # a refused program: status 1, the checker's words, no binary
  printf 'MODULE RunBad ;\nVAR x : I32 ;\nBEGIN\n  x := 40000000000\nEND RunBad.\n' > src/RunBad.m9
  if "$M9C" --run src/RunBad.m9 > o5.txt 2>&1; then
    echo "FAIL: --run ran a program the checker refuses"; exit 1
  fi
  grep -q 'does not fit I32' o5.txt || { echo "FAIL: --run's refusal said:"; cat o5.txt; exit 1; }
  if ls cache/bin/RunBad-* > /dev/null 2>&1; then
    echo "FAIL: a refused program left a binary"; exit 1
  fi
  # --run is the whole command: an output flag beside it is refused
  if "$M9C" -o x --run src/RunEcho.m9 > o6.txt 2>&1; then
    echo "FAIL: -o with --run was accepted"; exit 1
  fi
  # a script: #! names m9c, and the file is the program
  { printf '#!%s --run\n' "$M9C"; sed 1d "$FIX/Shebang.m9"; } > src/Shebang.m9
  chmod +x src/Shebang.m9
  [ "$(src/Shebang.m9 < /dev/null)" = "a script" ] ||
    { echo "FAIL: a #! file did not run as a script"; src/Shebang.m9; exit 1; }
  # a module binding a C library the program never calls: Frame
  # imports NetCDF, and --run links without -flto -- the unused nc_*
  # references must go with their sections (RunGcWords)
  cp "$FIX/RunFrame.m9" src/
  "$M9C" --run src/RunFrame.m9 < /dev/null > o7.txt 2>&1 ||
    { echo "FAIL: a program importing Frame did not link:"; tail -3 o7.txt; exit 1; }
  grep -q '^rows 3$' o7.txt || { echo "FAIL: RunFrame answered:"; cat o7.txt; exit 1; }
  # exported module variables (decision 28): the importer reads them,
  # writes a scalar, a slice element and a field through a pointer, and
  # the exporter sees the writes -- the same storage, not a copy
  "$M9C" --run "$M9LIBRARY/ExportUse.m9" < /dev/null > o8.txt 2>&1 ||
    { echo "FAIL: ExportUse did not run:"; tail -3 o8.txt; exit 1; }
  printf 'ExportUse reads count 40, LEN xs 3, version 2\nExportDef sees count 42, xs[1] 9.50, box.n 7, version 2\n' > want8.txt
  cmp -s o8.txt want8.txt || { echo "FAIL: ExportUse said:"; cat o8.txt; exit 1; }
  # a RAISE's strings outlive the frame that built them (report par 5,
  # 2026-10-06): four ways, a thousand raises each, every message read
  # back after the handler allocated; 0.16.0 got all four wrong
  cp "$FIX/RaisePayload.m9" src/
  "$M9C" --run src/RaisePayload.m9 < /dev/null > o9.txt 2>&1 ||
    { echo "FAIL: RAISE payloads were read back wrong:"; cat o9.txt; exit 1; }
  printf 'pool wrong 0 of 1000\nplus wrong 0 of 1000\nrethrow wrong 0 of 1000\nnested wrong 0 of 2000\n' > want9.txt
  cmp -s o9.txt want9.txt || { echo "FAIL: RaisePayload said:"; cat o9.txt; exit 1; }
  # --out-dir: the C goes where it is told, and nowhere else
  mkdir -p gen && "$M9C" --out-dir gen src/RunHelper.m9
  [ -f gen/RunHelper.c ] && [ -f gen/RunHelper.h ] && [ ! -f RunHelper.c ] ||
    { echo "FAIL: --out-dir wrote:"; ls . gen; exit 1; } ) || exit 1
echo "run: --run builds into its cache once, runs unchanged programs without"
echo "     a C compiler, sees an edited import, refuses what the checker refuses,"
echo "     and RAISE payloads survive the frame that built them"
