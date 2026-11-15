#!/bin/sh
# m9c --run builds into the cache, then BECOMES the program.
#
# The gate holds these: the program is told its own name, its
# arguments (an option-shaped one included: it is the program's, not
# m9c's), its stdin and its exit status; an unchanged program starts
# with NO C compiler run (-v prints every command m9c runs, and must
# print none); an edit to an IMPORTED module is seen although the
# program's text did not change, and undoing it is the old key again;
# a refused program exits 1 and leaves no binary; --run beside an
# output flag is refused; a #! file runs as an executable; --out-dir
# puts the C where it is told.
#
# This is A GATE OF ITS OWN, not the tail of m9c.sh.  m9c.sh stops at
# its ldd line on macOS, and its later half never runs there.  And
# --run is meant to work on macOS (decided 2026-10-04).  Two sabotaged
# compilers showed it able to fail (2026-10-04).  A key that ignores
# the imports' text fails the edited-import check.  A warm path that
# never reuses the binary fails the unchanged-run check.
#
# The gate uses an m9c built from runtime/gen (lib/freshm9c.sh), or
# $M9C.
set -e
cd "$(dirname "$0")"

. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C

export M9RUNTIME=$(cd .. && pwd)
export M9LIBRARY=$(cd ../../corpus && pwd)
FIX=$(cd runfix && pwd)
INR=$(cd inrange && pwd)
SELF=$(cd selfname && pwd)
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
  # An unchanged program runs no C compiler and no checker: nothing but
  # the program.
  "$M9C" -v --run src/RunEcho.m9 < /dev/null > o2.txt 2> e2.txt
  [ ! -s e2.txt ] || { echo "FAIL: an unchanged --run ran something:"; cat e2.txt; exit 1; }
  grep -q '^greeting 1$' o2.txt || { echo "FAIL: warm --run answered:"; cat o2.txt; exit 1; }
  # The cache sees an edit BELOW the program.
  sed 's/greeting 1/greeting 2/' "$FIX/RunHelper.m9" > src/RunHelper.m9
  "$M9C" --run src/RunEcho.m9 < /dev/null > o3.txt 2>&1
  grep -q '^greeting 2$' o3.txt || { echo "FAIL: an edited import was not seen:"; cat o3.txt; exit 1; }
  # Undoing it gives the old key, and nothing is compiled.
  cp "$FIX/RunHelper.m9" src/RunHelper.m9
  "$M9C" -v --run src/RunEcho.m9 < /dev/null > o4.txt 2> e4.txt
  [ ! -s e4.txt ] || { echo "FAIL: an undone edit was compiled again:"; cat e4.txt; exit 1; }
  grep -q '^greeting 1$' o4.txt || { echo "FAIL: an undone edit answered:"; cat o4.txt; exit 1; }
  if ls -d cache/tmp/* > /dev/null 2>&1; then
    echo "FAIL: --run left its scratch behind:"; ls cache/tmp; exit 1
  fi
  # A refused program gives status 1, the checker's words, and no
  # binary.
  printf 'MODULE RunBad ;\nVAR x : I32 ;\nBEGIN\n  x := 40000000000\nEND RunBad.\n' > src/RunBad.m9
  if "$M9C" --run src/RunBad.m9 > o5.txt 2>&1; then
    echo "FAIL: --run ran a program the checker refuses"; exit 1
  fi
  grep -q 'does not fit I32' o5.txt || { echo "FAIL: --run's refusal said:"; cat o5.txt; exit 1; }
  if ls cache/bin/RunBad-* > /dev/null 2>&1; then
    echo "FAIL: a refused program left a binary"; exit 1
  fi
  # --run is the whole command, so an output flag beside it is refused.
  if "$M9C" -o x --run src/RunEcho.m9 > o6.txt 2>&1; then
    echo "FAIL: -o with --run was accepted"; exit 1
  fi
  # In a script, #! names m9c, and the file is the program.
  { printf '#!%s --run\n' "$M9C"; sed 1d "$FIX/Shebang.m9"; } > src/Shebang.m9
  chmod +x src/Shebang.m9
  [ "$(src/Shebang.m9 < /dev/null)" = "a script" ] ||
    { echo "FAIL: a #! file did not run as a script"; src/Shebang.m9; exit 1; }
  # This module binds a C library the program never calls.  Frame
  # imports NetCDF, and --run links without -flto.  The unused nc_*
  # references must go with their sections (RunGcWords).
  cp "$FIX/RunFrame.m9" src/
  "$M9C" --run src/RunFrame.m9 < /dev/null > o7.txt 2>&1 ||
    { echo "FAIL: a program importing Frame did not link:"; tail -3 o7.txt; exit 1; }
  grep -q '^rows 3$' o7.txt || { echo "FAIL: RunFrame answered:"; cat o7.txt; exit 1; }
  # A program that WRITES blosc through Zarr links flagless (Zarr's czw
  # names blosc), and m9c reads a program's OWN FOR "C" unit's LINK
  # (cp-kernel's two findings on 0.20.0, 2026-10-10).
  cp "$FIX/RunZarrW.m9" "$FIX/RunOwnLink.m9" src/
  "$M9C" --run src/RunZarrW.m9 < /dev/null > o7z.txt 2>&1 ||
    { echo "FAIL: a program writing through Zarr did not link:"; tail -3 o7z.txt; exit 1; }
  grep -q '^zarr written$' o7z.txt || { echo "FAIL: RunZarrW answered:"; cat o7z.txt; exit 1; }
  "$M9C" --run src/RunOwnLink.m9 < /dev/null > o7l.txt 2>&1 ||
    { echo "FAIL: a program's own LINK was not read:"; tail -3 o7l.txt; exit 1; }
  grep -q '^zlib linked$' o7l.txt || { echo "FAIL: RunOwnLink answered:"; cat o7l.txt; exit 1; }
  # Test exported module variables (decision 28).  The importer reads
  # them, and writes a scalar, a slice element and a field through a
  # pointer.  The exporter sees the writes: the same storage, not a
  # copy.
  "$M9C" --run "$M9LIBRARY/ExportUse.m9" < /dev/null > o8.txt 2>&1 ||
    { echo "FAIL: ExportUse did not run:"; tail -3 o8.txt; exit 1; }
  printf 'ExportUse compares a Shade across modules\nand its negation\nExportUse reads count 40, LEN xs 3, version 2, LEN row 4\nExportDef sees count 42, xs[1] 9.50, box.n 7, version 2\ntime 6, ExportDef.time 12, exit 6\nSetTime (1) gives 5\n' > want8.txt
  cmp -s o8.txt want8.txt || { echo "FAIL: ExportUse said:"; cat o8.txt; exit 1; }
  # A module's name behind a local of the same name (par 3 rule 5,
  # docs/module-name-plan.md): Hidden.time beside a parameter time is
  # the module's.  Each line shows the procedure's value and the
  # module's apart, for a parameter, a local, a FOR variable, an
  # IS SOME binder, a handler's binder and a constant.
  "$M9C" --run "$SELF/Hidden.m9" < /dev/null > o16.txt 2>&1 ||
    { echo "FAIL: selfname/Hidden did not run:"; tail -3 o16.txt; exit 1; }
  printf 'time 7\nlocal 25 module 15\nloop 10 module 10\nbind -1 module none\nhandler 41 module 42\ndecls 97 module 103\n' > want16.txt
  cmp -s o16.txt want16.txt || { echo "FAIL: selfname/Hidden said:"; cat o16.txt; exit 1; }
  # FOR [INRANGE b]: the author's claim that a loop's subscripts are in
  # range (docs/loop-check-plan.md).  TRUE runs the body with the
  # unchecked accessors, FALSE the loop as any other.  A claim never
  # changes what a program does: the fixture runs each loop both ways
  # and the answers agree, a claim is read once, and a FALSE claim on a
  # range past the slice raises at index 5 with the stores before it
  # made.  The review page lists each claim, --no-unsafe refuses one,
  # and only a FOR over a range takes one.  The unchecked accessors are
  # in the fixture's C and in no bootstrap C: nothing but a claimed
  # body names them.
  "$M9C" --run "$INR/Claim.m9" < /dev/null > o10.txt 2>&1 ||
    { echo "FAIL: inrange/Claim did not run:"; tail -3 o10.txt; exit 1; }
  printf '1.0 5.0\nslice sums agree: 2015\narray sums agree: 49\ngrid sums agree: 1654.0\ncall sums agree: 13.8\nthe third claim raised; claims read: 3\nIndexError 5 of 5, v[4] = 4.0\n' > want10.txt
  cmp -s o10.txt want10.txt || { echo "FAIL: inrange/Claim said:"; cat o10.txt; exit 1; }
  "$M9C" --review "$INR/Claim.m9" 2> /dev/null | grep -q '^  INRANGE claims  *16  ' ||
    { echo "FAIL: --review does not list Claim's sixteen INRANGE claims"; exit 1; }
  # A program's page lists the claims of the modules it imports: Main
  # has none of its own and Kern has two.  Plain has none and is not
  # named, and a module's own page has no such section.
  ( cd "$INR/prog" && M9LIBRARY="$INR/prog:$M9LIBRARY" "$M9C" --review Main.m9 2> /dev/null ) > o15.txt
  grep -q '^IN THE MODULES IT IMPORTS' o15.txt && grep -q '^  Kern  *2   17 Sum, 24 Fill$' o15.txt ||
    { echo "FAIL: --review of a program does not list the claims of what it imports:"; tail -4 o15.txt; exit 1; }
  if grep -q '^  Plain ' o15.txt; then
    echo "FAIL: --review of a program names a module without claims"; exit 1
  fi
  if ( cd "$INR/prog" && M9LIBRARY="$INR/prog:$M9LIBRARY" "$M9C" --review Kern.m9 2> /dev/null ) | grep -q '^IN THE MODULES'; then
    echo "FAIL: --review of a module has the program's section"; exit 1
  fi
  mkdir -p inrc && "$M9C" --out-dir inrc "$INR/Claim.m9" > /dev/null 2>&1
  for acc in m9_uat m9_ugat1 m9_ugat2 m9_ugat3 m9_ugat4; do
    grep -q "$acc (" inrc/Claim.c ||
      { echo "FAIL: Claim's C does not use $acc: a TRUE claim's body is still checked"; exit 1; }
  done
  if grep -l 'm9_uat (\|m9_ugat[1-4] (' "$INR"/../../gen/*.c > o12.txt 2>/dev/null; then
    echo "FAIL: an unchecked accessor outside a claimed FOR, in:"; cat o12.txt; exit 1
  fi
  # --verify-claims keeps the checks in a claimed body.  The fixture
  # says the same there, its C names no unchecked accessor, and a
  # claim that is TRUE for a loop past its slice stops the program by
  # the claim's line: not an IndexError, though the program has a
  # handler for one.
  "$M9C" --verify-claims --run "$INR/Claim.m9" < /dev/null > o13.txt 2>&1 ||
    { echo "FAIL: inrange/Claim did not run under --verify-claims:"; tail -3 o13.txt; exit 1; }
  cmp -s o13.txt want10.txt || { echo "FAIL: inrange/Claim under --verify-claims said:"; cat o13.txt; exit 1; }
  mkdir -p inrv && "$M9C" --verify-claims --out-dir inrv "$INR/Claim.m9" > /dev/null 2>&1
  if grep -q 'm9_uat (\|m9_ugat[1-4] (' inrv/Claim.c; then
    echo "FAIL: --verify-claims left an unchecked accessor in Claim's C"; exit 1
  fi
  st=0
  "$M9C" --verify-claims --run "$INR/Lie.m9" < /dev/null > o14.txt 2>&1 || st=$?
  [ "$st" = 134 ] && grep -q '^in range: done$' o14.txt &&
    grep -q '^m9: the INRANGE claim at line 8 of Lie.Fill was false: index 4, extent 4$' o14.txt ||
    { echo "FAIL: a false claim under --verify-claims (exit $st) said:"; cat o14.txt; exit 1; }
  if grep -q 'a handler took a false claim' o14.txt; then
    echo "FAIL: a handler took a false claim"; exit 1
  fi
  if "$M9C" --no-unsafe --check "$INR/Claim.m9" > o11.txt 2>&1; then
    echo "FAIL: --no-unsafe accepted an INRANGE claim"; exit 1
  fi
  grep -q 'Claim.m9:[0-9]*:[0-9]*: no-unsafe: an INRANGE claim on the FOR over j' o11.txt ||
    { echo "FAIL: the --no-unsafe refusal did not name the claim:"; cat o11.txt; exit 1; }
  printf 'MODULE Cin ;\nVAR s : SLICE OF I64 ; x : I64 ;\nBEGIN\n  FOR [INRANGE TRUE] x IN s DO END\nEND Cin.\n' > Cin.m9
  "$M9C" --check Cin.m9 2>&1 | grep -q 'parse: INRANGE stands on FOR v := lo TO hi' ||
    { echo "FAIL: an INRANGE claim on FOR IN is not refused by name"; exit 1; }
  printf 'MODULE Cat ;\nVAR i : I64 ;\nBEGIN\n  FOR [PURE] i := 0 TO 2 DO END\nEND Cat.\n' > Cat.m9
  "$M9C" --check Cat.m9 2>&1 | grep -q 'parse: a FOR takes one attribute: \[INRANGE b\]' ||
    { echo "FAIL: another attribute on a FOR is not refused by name"; exit 1; }
  # On x86-64 m9c tells the C compiler -mno-mmx, and on no other
  # processor (gcc 12 and 13 left the x87 state full after an MMX
  # move, and Math.Fmod answered NaN in that thread; 2026-11-14).
  "$M9C" -v --make -o eu9 "$M9LIBRARY/ExportUse.m9" < /dev/null > o9.txt 2>&1 ||
    { echo "FAIL: ExportUse did not build with -v:"; tail -3 o9.txt; exit 1; }
  case "$( (${CC:-cc} -dumpmachine || gcc -dumpmachine) 2>/dev/null | head -1)" in
    x86_64*|amd64*)
      grep -q -- ' -mno-mmx ' o9.txt ||
        { echo "FAIL: on x86-64 the cc line has no -mno-mmx"; exit 1; }
      # What the word is for: no instruction that names an MMX
      # register, in the program just built and in the compiler
      # itself, the largest generated C there is.  The server's two
      # handlers that had them are not ours to keep here, and no
      # program of this tree made gcc 12 or 13 write one (60 gate
      # binaries scanned, 2026-11-14).  So this holds the property,
      # and the line above holds the word.
      if command -v objdump > /dev/null 2>&1; then
        for b in eu9 "$M9C"; do
          n=$(objdump -d --no-show-raw-insn "$b" | grep -c '[ ,(]%mm[0-7]')
          [ "$n" = 0 ] ||
            { echo "FAIL: $n MMX instructions in $b (x87 answers NaN after one)"; exit 1; }
        done
      else
        echo "run: no objdump, the MMX scan is skipped"
      fi ;;
    *)
      if grep -q -- '-mno-mmx' o9.txt; then
        echo "FAIL: -mno-mmx given to a compiler that is not for x86-64"; exit 1
      fi ;;
  esac
  # A RAISE's strings outlive the frame that built them (report par 5,
  # 2026-10-06).  The program tries four ways, a thousand raises each,
  # and reads every message back after the handler allocated.  0.16.0
  # got all four wrong.
  cp "$FIX/RaisePayload.m9" src/
  "$M9C" --run src/RaisePayload.m9 < /dev/null > o9.txt 2>&1 ||
    { echo "FAIL: RAISE payloads were read back wrong:"; cat o9.txt; exit 1; }
  printf 'pool wrong 0 of 1000\nplus wrong 0 of 1000\nrethrow wrong 0 of 1000\nnested wrong 0 of 2000\n' > want9.txt
  cmp -s o9.txt want9.txt || { echo "FAIL: RaisePayload said:"; cat o9.txt; exit 1; }
  # Test --show of an exported variable whose TYPE is a module the cell
  # does not import: ShObs.f is a PTR Frame.Fr.  The NULL test on a
  # value read out of a module variable (2026-10-21) named the type,
  # which the cell cannot spell.  That gave `gen: unknown name:
  # Frame.Fr', for the notebook's `Obs.f', until 2026-10-22.  CI's
  # drivers job was red on it, and this is the lex job's check.
  cp "$FIX/ShObs.m9" "$FIX/ShowDeep.m9" src/
  "$M9C" --show --run src/ShowDeep.m9 < /dev/null > o10.txt 2>&1 ||
    { echo "FAIL: --show of a variable of an indirect module's type:"; cat o10.txt; exit 1; }
  grep -q '0 rows x 0 columns' o10.txt ||
    { echo "FAIL: --show did not show the frame:"; cat o10.txt; exit 1; }
  # TWO DEFINITIONS IMPORTING EACH OTHER build from clean, both ways
  # (decided 2026-10-22: allowed; types do not change at run time).  A
  # clean --make failed on the partner's missing header, and a second
  # run passed on the leftovers.  With the header written, the
  # partner's record was `unknown type name' in the other's prototype.
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
  # report, 2026-10-25).  A caller in another module declaring
  # PtyDef.Error, directly or through an alias, is accepted and catches
  # it.  One declaring an Error of its own is refused.  0.25.0 refused
  # the first two and accepted the third, which then died unhandled.
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
  # third review's S11(d)).  The old runtime hung; `timeout' says 124.
  cp "$FIX/MonValue.m9" src/
  st=0
  out=$( (command -v timeout > /dev/null && timeout 20 "$M9C" --run src/MonValue.m9 || "$M9C" --run src/MonValue.m9) < /dev/null 2>&1 ) || st=$?
  if [ "$st" = 0 ] || [ "$st" = 124 ] ||
     ! printf '%s\n' "$out" | grep -q 'a monitor was entered again by the thread that holds it'; then
    echo "FAIL: MonValue, a monitor re-entered through a procedure value (exit $st):"
    printf '%s\n' "$out" | grep -v 'm9c: gcc' | head -5; exit 1
  fi
  # A record answer built in ANOTHER module, its field a concatenation
  # of two STR parameters, is kept in a module variable (2026-10-26, the
  # third review's typing CcUse, a heap-use-after-free).  The region
  # judgement refuses it.  It reads the callee's body in the callee's
  # module and takes an untyped `+' for a string's unless it shows a
  # number.
  cp "$FIX/CcDef.m9" "$FIX/CcUse.m9" src/
  if "$M9C" --check src/CcUse.m9 > ccuse.txt 2>&1; then
    echo "FAIL: CcUse accepted: CcDef.Mk's answer holds a frame string"; exit 1
  fi
  grep -q 'storage of this activation stored into module variable g' ccuse.txt ||
    { echo "FAIL: CcUse refused for another reason:"; head -3 ccuse.txt; exit 1; }
  # A module-pool answer from another module, kept in a module variable
  # (zarrm9's Serve.Run, 2026-10-26), is accepted.  011e837b refused it,
  # reading the builder's integer `+' as a frame string.
  cp "$FIX/RcDef.m9" "$FIX/RcUse.m9" src/
  [ "$("$M9C" --run src/RcUse.m9 < /dev/null 2>&1)" = "root/x 1" ] ||
    { echo "FAIL: RcUse, a module-pool answer kept in module state:";
      "$M9C" --run src/RcUse.m9 < /dev/null 2>&1 | grep -v 'm9c: gcc' | head -5; exit 1; }
  # Both checkers accepted THREAD's argument under parentheses
  # (2026-10-29), and the generator said `THREAD form unsupported yet'
  # before.
  cp "$FIX/ThreadParen.m9" src/
  [ "$("$M9C" --run src/ThreadParen.m9 < /dev/null 2>&1)" = "done 2" ] ||
    { echo "FAIL: ThreadParen, THREAD (W, (j)):";
      "$M9C" --run src/ThreadParen.m9 < /dev/null 2>&1 | grep -v 'm9c: gcc' | head -5; exit 1; }
  # Test an imported enumeration-indexed array, its bound's name also a
  # record of the importer's (2026-10-30, a port's report M9).
  cp "$FIX/EnumIdxDef.m9" "$FIX/EnumIdxUse.m9" src/
  [ "$("$M9C" --run src/EnumIdxUse.m9 < /dev/null 2>&1)" = "ok" ] ||
    { echo "FAIL: EnumIdxUse, an imported ARRAY Cover OF T beside a record Cover:";
      "$M9C" --run src/EnumIdxUse.m9 < /dev/null 2>&1 | grep -v 'm9c: gcc' | head -5; exit 1; }
  # (a FOR body moving its variable past the bound, the same report's
  # second item, is REFUSED since 2026-10-25: probes
  # for-variable-assigned and for-variable-var-arg, museum
  # for-variable-past-bound.m9)
  # An exception nothing handles says what was refused and where: the
  # procedure, the line and the runtime's reason with its numbers.
  # It said only "m9: unhandled IndexError" until 2026-11-01 (zarrm9).
  cp "$FIX/Unhandled.m9" src/
  got=$("$M9C" --run src/Unhandled.m9 cut < /dev/null 2>&1)
  echo "$got" | grep -q "unhandled IndexError in Unhandled.Citation, line 13: a slice (start 0, length 8) that cuts inside a character, in a text of 15 bytes" ||
    { echo "FAIL: an unhandled cut inside a character lost its context:"; echo "$got" | head -3; exit 1; }
  got=$("$M9C" --run src/Unhandled.m9 index < /dev/null 2>&1)
  echo "$got" | grep -q "unhandled IndexError in Unhandled.Pick, line 18: index 5 outside a length of 3" ||
    { echo "FAIL: an unhandled index lost its context:"; echo "$got" | head -3; exit 1; }
  # With --out-dir the C goes where it is told, and nowhere else.
  mkdir -p gen && "$M9C" --out-dir gen src/RunHelper.m9
  [ -f gen/RunHelper.c ] && [ -f gen/RunHelper.h ] && [ ! -f RunHelper.c ] ||
    { echo "FAIL: --out-dir wrote:"; ls . gen; exit 1; } ) || exit 1
echo "run: --run builds into its cache once, runs unchanged programs without"
echo "     a C compiler, sees an edited import, refuses what the checker refuses,"
echo "     RAISE payloads survive the frame that built them, and --show reads"
echo "     a variable whose type is a module the cell does not import, and"
echo "     two definitions importing each other build from clean"
