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
# Uses an m9c built from runtime/gen (lib/freshm9c.sh), or $M9C.
set -e
cd "$(dirname "$0")"

. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C

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
  # a program that WRITES blosc through Zarr links flagless (Zarr's czw
  # names blosc), and a program's OWN FOR "C" unit's LINK is read
  # (cp-kernel's two findings on 0.20.0, 2026-10-10)
  cp "$FIX/RunZarrW.m9" "$FIX/RunOwnLink.m9" src/
  "$M9C" --run src/RunZarrW.m9 < /dev/null > o7z.txt 2>&1 ||
    { echo "FAIL: a program writing through Zarr did not link:"; tail -3 o7z.txt; exit 1; }
  grep -q '^zarr written$' o7z.txt || { echo "FAIL: RunZarrW answered:"; cat o7z.txt; exit 1; }
  "$M9C" --run src/RunOwnLink.m9 < /dev/null > o7l.txt 2>&1 ||
    { echo "FAIL: a program's own LINK was not read:"; tail -3 o7l.txt; exit 1; }
  grep -q '^zlib linked$' o7l.txt || { echo "FAIL: RunOwnLink answered:"; cat o7l.txt; exit 1; }
  # exported module variables (decision 28): the importer reads them,
  # writes a scalar, a slice element and a field through a pointer, and
  # the exporter sees the writes -- the same storage, not a copy
  "$M9C" --run "$M9LIBRARY/ExportUse.m9" < /dev/null > o8.txt 2>&1 ||
    { echo "FAIL: ExportUse did not run:"; tail -3 o8.txt; exit 1; }
  printf 'ExportUse compares a Shade across modules\nand its negation\nExportUse reads count 40, LEN xs 3, version 2, LEN row 4\nExportDef sees count 42, xs[1] 9.50, box.n 7, version 2\n' > want8.txt
  cmp -s o8.txt want8.txt || { echo "FAIL: ExportUse said:"; cat o8.txt; exit 1; }
  # a RAISE's strings outlive the frame that built them (report par 5,
  # 2026-10-06): four ways, a thousand raises each, every message read
  # back after the handler allocated; 0.16.0 got all four wrong
  cp "$FIX/RaisePayload.m9" src/
  "$M9C" --run src/RaisePayload.m9 < /dev/null > o9.txt 2>&1 ||
    { echo "FAIL: RAISE payloads were read back wrong:"; cat o9.txt; exit 1; }
  printf 'pool wrong 0 of 1000\nplus wrong 0 of 1000\nrethrow wrong 0 of 1000\nnested wrong 0 of 2000\n' > want9.txt
  cmp -s o9.txt want9.txt || { echo "FAIL: RaisePayload said:"; cat o9.txt; exit 1; }
  # --show of an exported variable whose TYPE is a module the cell does
  # not import: ShObs.f is a PTR Frame.Fr.  The NULL test on a value
  # read out of a module variable (2026-10-21) named the type, which the
  # cell cannot spell -- `gen: unknown name: Frame.Fr', the notebook's
  # `Obs.f', until 2026-10-22; CI's drivers job was red on it, and this
  # is the lex job's check
  cp "$FIX/ShObs.m9" "$FIX/ShowDeep.m9" src/
  "$M9C" --show --run src/ShowDeep.m9 < /dev/null > o10.txt 2>&1 ||
    { echo "FAIL: --show of a variable of an indirect module's type:"; cat o10.txt; exit 1; }
  grep -q '0 rows x 0 columns' o10.txt ||
    { echo "FAIL: --show did not show the frame:"; cat o10.txt; exit 1; }
  # TWO DEFINITIONS IMPORTING EACH OTHER build from clean, both ways
  # (Alex, 2026-10-22: allowed; types do not change at run time).  A
  # clean --make failed on the partner's missing header and a second
  # run passed on the leftovers; with the header written, the partner's
  # record was `unknown type name' in the other's prototype
  cp "$FIX/MutA.m9" "$FIX/MutB.m9" "$FIX/MutMain.m9" src/
  [ "$("$M9C" --run src/MutMain.m9 < /dev/null 2>&1)" = "5 70" ] ||
    { echo "FAIL: --run of two definitions importing each other:";
      "$M9C" --run src/MutMain.m9 < /dev/null 2>&1 | grep -v 'm9c: gcc' | head -5; exit 1; }
  MD=$(mktemp -d)
  cp "$FIX/MutA.m9" "$FIX/MutB.m9" "$FIX/MutMain.m9" "$MD/"
  ( cd "$MD" && "$M9C" --make -o mm MutMain.m9 > make.txt 2>&1 && [ "$(./mm)" = "5 70" ] ) ||
    { echo "FAIL: --make of two definitions importing each other, from clean:";
      grep -v 'm9c: gcc\|m9c: wrote' "$MD/make.txt" | head -5; exit 1; }
  rm -r "$MD"
  # A PROCEDURE TYPE'S RAISES is its declaring module's (zarrm9's 0.25
  # report, 2026-10-25): a caller in another module declaring
  # PtyDef.Error, directly or through an alias, is accepted and catches
  # it; one declaring an Error of its own is refused -- 0.25.0 refused
  # the first two and accepted the third, which then died unhandled
  cp "$FIX/PtyDef.m9" "$FIX/PtyUse.m9" "$FIX/PtyAlias.m9" "$FIX/PtyOwn.m9" src/
  for p in PtyUse PtyAlias; do
    [ "$("$M9C" --run src/$p.m9 < /dev/null 2>&1)" = "PtyDef.Error raised" ] ||
      { echo "FAIL: $p, a caller declaring the type's own exception:";
        "$M9C" --run src/$p.m9 < /dev/null 2>&1 | grep -v 'm9c: gcc' | head -5; exit 1; }
  done
  if "$M9C" --check src/PtyOwn.m9 > own.txt 2>&1; then
    echo "FAIL: PtyOwn accepted: its own Error does not cover PtyDef.Error"; exit 1
  fi
  grep -q 'unhandled RAISES PtyDef.Error from call to f' own.txt ||
    { echo "FAIL: PtyOwn refused for another reason:"; head -3 own.txt; exit 1; }
  # A monitor re-entered through a PROCEDURE VALUE, which the checker's
  # MonReach cannot follow, stops the program by name (2026-10-26, the
  # third review's S11(d)); the old runtime hung -- `timeout' says 124
  cp "$FIX/MonValue.m9" src/
  st=0
  out=$( (command -v timeout > /dev/null && timeout 20 "$M9C" --run src/MonValue.m9 || "$M9C" --run src/MonValue.m9) < /dev/null 2>&1 ) || st=$?
  if [ "$st" = 0 ] || [ "$st" = 124 ] ||
     ! printf '%s\n' "$out" | grep -q 'a monitor was entered again by the thread that holds it'; then
    echo "FAIL: MonValue, a monitor re-entered through a procedure value (exit $st):"
    printf '%s\n' "$out" | grep -v 'm9c: gcc' | head -5; exit 1
  fi
  # A record answer built in ANOTHER module, its field a concatenation of
  # two STR parameters, kept in a module variable (2026-10-26, the third
  # review's typing CcUse, a heap-use-after-free): refused by the region
  # judgement, which reads the callee's body in the callee's module and
  # takes an untyped `+' for a string's unless it shows a number
  cp "$FIX/CcDef.m9" "$FIX/CcUse.m9" src/
  if "$M9C" --check src/CcUse.m9 > ccuse.txt 2>&1; then
    echo "FAIL: CcUse accepted: CcDef.Mk's answer holds a frame string"; exit 1
  fi
  grep -q 'storage of this activation stored into module variable g' ccuse.txt ||
    { echo "FAIL: CcUse refused for another reason:"; head -3 ccuse.txt; exit 1; }
  # A module-pool answer from another module kept in a module variable
  # (zarrm9's Serve.Run, 2026-10-26): accepted -- 011e837b refused it,
  # reading the builder's integer `+' as a frame string
  cp "$FIX/RcDef.m9" "$FIX/RcUse.m9" src/
  [ "$("$M9C" --run src/RcUse.m9 < /dev/null 2>&1)" = "root/x 1" ] ||
    { echo "FAIL: RcUse, a module-pool answer kept in module state:";
      "$M9C" --run src/RcUse.m9 < /dev/null 2>&1 | grep -v 'm9c: gcc' | head -5; exit 1; }
  # (a FOR body moving its variable past the bound, the same report's
  # second item, is REFUSED since 2026-10-25: probes
  # for-variable-assigned and for-variable-var-arg, museum
  # for-variable-past-bound.m9)
  # --out-dir: the C goes where it is told, and nowhere else
  mkdir -p gen && "$M9C" --out-dir gen src/RunHelper.m9
  [ -f gen/RunHelper.c ] && [ -f gen/RunHelper.h ] && [ ! -f RunHelper.c ] ||
    { echo "FAIL: --out-dir wrote:"; ls . gen; exit 1; } ) || exit 1
echo "run: --run builds into its cache once, runs unchanged programs without"
echo "     a C compiler, sees an edited import, refuses what the checker refuses,"
echo "     RAISE payloads survive the frame that built them, and --show reads"
echo "     a variable whose type is a module the cell does not import, and"
echo "     two definitions importing each other build from clean"
