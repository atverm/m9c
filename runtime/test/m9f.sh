#!/bin/sh
# m9f holds the .m9f converter (corpus/M9f.m9) to eight things.
#
# Every tracked .m9 survives M9 to .m9f to M9 byte for byte.  The
# round trip is what lets a person read any file as .m9f and get the
# same M9 back.  m9f.skip names the files malformed on purpose, each
# with its reason.
#
# A hand-written .m9f, m9ffix/Kw.m9f, converts to m9ffix/Kw.m9 byte for
# byte, and that M9 checks.  It writes task as the keyword and task_ as
# a name.  A keyword appended to Lex must stay reserved this way.  The
# converter's Starters list must know a keyword that opens a statement,
# or the line before it gets no semicolon.
#
# m9ffix/Hash.m9f writes # for not-equal, and the converter refuses it.
#
# m9c is the preprocessor.  m9ffix/Hello.m9f imports Greet.m9f, and
# neither has a .m9.  m9c --run writes both and runs the program.  A
# .m9f that changes nothing leaves its .m9 alone.  A .m9 edited by hand
# is not overwritten: m9c refuses and names both files.  --to-m9f
# writes the .m9f from that .m9, and the pair is in step again.  A .m9
# newer than its .m9f wins.  File times are set with touch -t, so the
# gate does not sleep.
#
# A diagnostic in a .m9 that is in step with its .m9f names the .m9f, at
# the .m9f's column.  m9ffix/Col.m9f has a checker error and Par.m9f a
# parse error, each where the two notations' columns differ.
#
# A parse error in such a .m9 speaks .m9f: what it expected in .m9f
# spelling, what it found quoted from the .m9f.  Brk.m9f breaks an IS
# SOME binding across a line, which the line-break rule reads as two
# statements: the error says so, once, and names the backslash.
# Miss.m9f leaves a { open at the end of the file.
#
# Probe parity: every probe, written as .m9f, is refused as its .m9 is.
# The lines, the messages and the exit status are the same; only the
# file name and the column may differ.
#
# The programs in examples/m9f were written by hand in .m9f.  Converted
# code never has the line-break rule's edges, and these do.  Each one
# prints what its .out holds.  Breaks.m9f continues two lines with a
# backslash; without them, m9c refuses it and gives the hint.
cd "$(dirname "$0")" || exit 1
. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C
ROOT=$(cd ../.. && pwd)
SKIP=$(pwd)/m9f.skip
FIX=$(pwd)/m9ffix
export M9RUNTIME="$ROOT/runtime" M9LIBRARY="$ROOT/corpus"
W=$(mktemp -d)
fail=0

# Every skip entry must still exist, so the list cannot outlive what it
# excuses.
for p in $(grep -v '^#' "$SKIP" | awk 'NF { print $1 }'); do
  [ -e "$ROOT/$p" ] || { echo "m9f: FAIL -- m9f.skip names $p, which is gone"; fail=1; }
done

# --make writes each module's .h and .o where it runs, so it runs in W.
( cd "$W" && "$M9C" --make -I "$ROOT/corpus" -o m9ft "$ROOT/tools/M9fTool.m9" ) > "$W/build.txt" 2>&1 \
  || { echo "m9f: FAIL -- tools/M9fTool.m9 does not build:"; head -5 "$W/build.txt"; exit 1; }

cd "$ROOT" || exit 1
grep -v '^#' "$SKIP" | awk 'NF { print $1 }' > "$W/skip"
n=$(git ls-files '*.m9' | grep -vxF -f "$W/skip" | wc -l | tr -d ' ')
git ls-files -z '*.m9' | tr '\0' '\n' | grep -vxF -f "$W/skip" | tr '\n' '\0' \
  | xargs -0 "$W/m9ft" round > "$W/round.txt" 2>&1
if [ -s "$W/round.txt" ]; then
  echo "m9f: FAIL -- the round trip:"
  head -20 "$W/round.txt" | sed 's/^/    /'
  fail=1
else
  echo "m9f: $n files round-trip exactly"
fi

if "$W/m9ft" from "$FIX/Kw.m9f" "$W/Kw.m9" && cmp -s "$W/Kw.m9" "$FIX/Kw.m9" \
   && ( cd "$W" && "$M9C" --check Kw.m9 ) > "$W/kw.txt" 2>&1; then
  echo "m9f: Kw.m9f converts to Kw.m9, which checks"
else
  echo "m9f: FAIL -- Kw.m9f:"
  diff "$FIX/Kw.m9" "$W/Kw.m9" | head -10
  head -5 "$W/kw.txt"
  fail=1
fi

if "$W/m9ft" from "$FIX/Hash.m9f" - > "$W/hash.txt" 2>&1; then
  echo "m9f: FAIL -- Hash.m9f converted; # must be refused"
  fail=1
elif grep -q "^5:8: write != for not equal" "$W/hash.txt"; then
  echo "m9f: Hash.m9f is refused at 5:8"
else
  echo "m9f: FAIL -- Hash.m9f refused with the wrong message:"
  cat "$W/hash.txt"
  fail=1
fi

# bad NAME says the preprocessor case NAME failed.
bad () { echo "m9f: FAIL -- the preprocessor: $1"; fail=1; }
P=$W/pre
mkdir "$P"
cp "$FIX/Greet.m9f" "$FIX/Hello.m9f" "$P/"
export M9CACHE="$W/cache"
cd "$P" || exit 1
want=$(printf 'line 1\nline 20\nline 3')
[ "$("$M9C" --run Hello.m9f 2>&1)" = "$want" ] || bad "Hello.m9f did not run from .m9f alone"
[ -f Greet.m9 ] && [ -f Hello.m9 ] || bad "Greet.m9 and Hello.m9 were not written"
# An unchanged .m9f converts to the same text, and the .m9 keeps its time.
touch -t 202001010000 Greet.m9
touch -t 202101010000 ref
touch -t 202201010000 Greet.m9f
"$M9C" --check Hello.m9f > /dev/null 2>&1 || bad "an unchanged Greet.m9f stopped the check"
[ Greet.m9 -nt ref ] && bad "an unchanged Greet.m9f rewrote Greet.m9"
# A hand edit to Greet.m9, then a newer Greet.m9f: refused.
echo '(* by hand *)' >> Greet.m9
touch -t 202301010000 Greet.m9
touch -t 202401010000 Greet.m9f
if "$M9C" --check Hello.m9f > "$W/edit.txt" 2>&1; then
  bad "a hand-edited Greet.m9 was overwritten"
elif ! grep -q "Greet.m9 was edited since m9c wrote it from ./Greet.m9f" "$W/edit.txt"; then
  bad "the refusal does not name both files:"
  cat "$W/edit.txt"
fi
grep -q 'by hand' Greet.m9 || bad "the refusal lost the hand edit"
# --to-m9f takes the .m9's side, and the two are in step.
"$M9C" --to-m9f Greet.m9 || bad "--to-m9f failed"
grep -q 'by hand' Greet.m9f || bad "--to-m9f did not carry the .m9"
"$M9C" --check Hello.m9f > /dev/null 2>&1 || bad "Greet.m9 and Greet.m9f are not in step after --to-m9f"
# A .m9 newer than its .m9f wins as it is.
python3 -c "import sys; p=sys.argv[1]; s=open(p).read(); open(p,'w').write(s.replace('n * 10', 'n * 7'))" Greet.m9
touch -t 203001010000 Greet.m9   # --to-m9f wrote Greet.m9f just now
[ "$("$M9C" --run Hello.m9f 2>&1 | sed -n 2p)" = "line 14" ] || bad "a newer Greet.m9 did not win"
cd "$ROOT" || exit 1
[ $fail = 0 ] && echo "m9f: m9c writes, keeps, refuses and runs .m9f as decided"

# at FILE WANT says the first diagnostic m9c gives for FILE starts WANT.
at () {
  first=$( cd "$P" && "$M9C" --check "$1" 2>&1 | head -1 )
  case $first in
    "$2"*) echo "m9f: $1 is reported at ${2%: }" ;;
    *) echo "m9f: FAIL -- $1: want $2..., got: $first"; fail=1 ;;
  esac
}
cp "$FIX/Col.m9f" "$FIX/Par.m9f" "$FIX/Brk.m9f" "$FIX/Miss.m9f" "$P/"
at Col.m9f "Col.m9f:5:29: Col body: cannot assign"
at Par.m9f "Par.m9f:5:29: parse: expression expected, found ')'"
at Brk.m9f "Brk.m9f:6:16: parse: { expected, found the end of the line"
at Miss.m9f "Miss.m9f:7:1: a { is still open at the end of the file"
n=$( cd "$P" && "$M9C" --check Brk.m9f 2>&1 | grep -c 'a line break here was read as the end of a statement' )
[ "$n" = 1 ] && echo "m9f: Brk.m9f gives the line-break hint once" ||
  { echo "m9f: FAIL -- Brk.m9f gives the line-break hint $n times, not once"; fail=1; }

# Probe parity.  norm drops the file name and the column, and the
# summary line's file name.
norm () { sed -E 's/^[^ ]*\.m9f?:([0-9]+):[0-9]+:/\1:/; s/ errors in .*$/ errors/'; }
Q=$W/probes
mkdir "$Q"
np=0
nbad=0
for p in "$ROOT"/probes/*.m9; do
  b=$(basename "$p" .m9)
  "$W/m9ft" to "$p" "$Q/$b.m9f" || { echo "m9f: FAIL -- $b does not convert"; fail=1; continue; }
  ( cd "$ROOT/probes" && "$M9C" --check "$b.m9" ) > "$W/want.txt" 2>&1
  w=$?
  ( cd "$Q" && "$M9C" -I "$ROOT/probes" --check "$b.m9f" ) > "$W/got.txt" 2>&1
  g=$?
  np=$((np + 1))
  norm < "$W/want.txt" > "$W/want.n"
  norm < "$W/got.txt" > "$W/got.n"
  if [ $w != $g ] || ! cmp -s "$W/want.n" "$W/got.n"; then
    nbad=$((nbad + 1))
    [ $nbad -le 5 ] && { echo "m9f: FAIL -- probe $b differs as .m9f (exit $w, $g):"; diff "$W/want.n" "$W/got.n" | head -4; }
    fail=1
  fi
done
[ $nbad = 0 ] && echo "m9f: $np probes are refused as .m9f exactly as as .m9"

E=$W/examples
mkdir "$E"
cp "$ROOT"/examples/m9f/*.m9f "$E/"
ne=0
for out in "$ROOT"/examples/m9f/*.out; do
  b=$(basename "$out" .out)
  if ( cd "$E" && "$M9C" --run "$b.m9f" ) > "$W/ex.txt" 2>&1 && cmp -s "$W/ex.txt" "$out"; then
    ne=$((ne + 1))
  else
    echo "m9f: FAIL -- examples/m9f/$b.m9f does not print $b.out:"
    diff "$out" "$W/ex.txt" | head -6
    fail=1
  fi
done
echo "m9f: $ne hand-written examples print what they should"
mkdir "$E/nb"
sed 's/ \\$//' "$ROOT/examples/m9f/Breaks.m9f" > "$E/nb/Breaks.m9f"
( cd "$E/nb" && "$M9C" --check Breaks.m9f ) > "$W/nb.txt" 2>&1
if grep -q '^Breaks.m9f:36:16: parse: { expected' "$W/nb.txt" &&
   grep -q 'end the line with \\ to continue it' "$W/nb.txt"; then
  echo "m9f: Breaks.m9f without its backslashes is refused, with the hint"
else
  echo "m9f: FAIL -- Breaks.m9f without its backslashes:"
  head -4 "$W/nb.txt"
  fail=1
fi

rm -r "$W"
exit $fail
