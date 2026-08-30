#!/bin/sh
# tutdiff: the tutorial cannot disagree with the compiler people
# download.  Every C*.m9 example must compile, run, and print
# exactly its checked-in expectation; every X*.m9 must be REFUSED
# with the diagnostic its own EXPECT-ERROR line names.  The docdiff
# principle applied to prose: examples are gated, so they cannot rot.
set -e
cd "$(dirname "$0")"
. ./gen.sh

gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Io.c ../gen/Lex.c \
    ../gen/Ast.c ../gen/Parse.c ../gen/Print.c ../gen/Text.c \
    ../gen/Fmt.c ../gen/Sem.c ../gen/Gen.c ../gen/Doc.c ../gen/M9c.c -o m9c

M9C=$(pwd)/m9c
# the public m9c repository carries docs/tutorial-plan.md and not the
# tutorial itself (that is public in atverm/M9Tutorial); there this
# gate has nothing to hold and says so -- BEFORE the cd below, which
# under set -e would end the script on the missing directory
[ -d ../../docs/tutorial/examples ] \
  || { echo "SKIP: tutdiff (no docs/tutorial in this tree)"; exit 0; }
EXA=$(cd ../../docs/tutorial/examples && pwd)
RT=$(cd .. && pwd)
LIB=$(cd ../../corpus && pwd)
W=/tmp/m9tut-gate
rm -rf "$W"; mkdir -p "$W"
. ./tutcommon.sh

# the zarr chapter needs libblosc and a generatable store; CI has
# neither, so it SKIPS OUT LOUD there rather than passing quietly
# (its quoted output is still drift-checked below, which needs no
# libraries).  Everything else runs everywhere gcc runs.
ZARR_OK=1
ldconfig -p 2>/dev/null | grep -q 'libblosc\.so\.1' || ZARR_OK=0


ran=0
for f in "$EXA"/C*.m9; do
  m=$(basename "$f" .m9)
  # C10Icos reads the same kind of store (through TLS as well), so it
  # skips with C8Zarr.  It did not, from the renumbering (98411ba)
  # until the public mirror's first CI run: the skip named the old
  # C7 twin only, and CI -- which has no libblosc -- went red at
  # "C10Icos does not compile" for every commit of a day, unnoticed
  # because nobody looked at the private CI that day.
  if { [ "$m" = C8Zarr ] || [ "$m" = C10Icos ]; } && [ "$ZARR_OK" != 1 ]; then
    echo "SKIP: $m (libblosc, and for C10Icos libssl, are absent)"
    continue
  fi
  tut_build "$m" || { echo "FAIL: $m does not compile"; exit 1; }
  tut_pre "$m"
  ( cd "$EXA" && "$W/$m" > "$W/$m.out" ) \
    || { echo "FAIL: $m exited nonzero"; exit 1; }
  cmp -s "$W/$m.out" "$EXA/expect/$m.out" \
    || { echo "FAIL: $m output differs from expect/$m.out"; \
         diff "$EXA/expect/$m.out" "$W/$m.out" | head -10; exit 1; }
  ran=$((ran + 1))
done
cmp -s /tmp/damped.svg "$EXA/expect/damped.svg" \
  || { echo "FAIL: C9Plot's SVG differs from expect/damped.svg"; exit 1; }
[ "$ZARR_OK" != 1 ] || cmp -s /tmp/htm.svg "$EXA/expect/htm.svg" \
  || { echo "FAIL: C10Icos's SVG differs from expect/htm.svg"; exit 1; }

for f in "$EXA"/X*.m9; do
  m=$(basename "$f" .m9)
  want=$(sed -n 's/^(\* EXPECT-ERROR: \(.*\) \*)$/\1/p' "$f")
  [ -n "$want" ] || { echo "FAIL: $m has no EXPECT-ERROR line"; exit 1; }
  if ( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$LIB" \
       "$M9C" -c "$f" -I "$EXA" > "$W/$m.err" 2>&1 ); then
    echo "FAIL: $m compiled -- it must be refused"; exit 1
  fi
  grep -qF "$want" "$W/$m.err" \
    || { echo "FAIL: $m refused, but not with '$want':"; \
         head -3 "$W/$m.err"; exit 1; }
  ran=$((ran + 1))
done

# THE PROSE CANNOT DRIFT EITHER.  Every fenced block in the chapters
# that names an example (```m9 NAME.m9), an output (```output NAME)
# or a refusal (```refusal NAME) is compared against the gated file,
# the recorded expectation, or the refusal's actual stderr.  A
# chapter quoting code or diagnostics it does not gate is the rot
# this whole script exists to prevent.
TUT=$(cd ../../docs/tutorial && pwd) EXA="$EXA" W="$W" python3 - <<'PYCHK' || exit 1
import os, re, pathlib, sys
tut = pathlib.Path(os.environ['TUT']); ex = pathlib.Path(os.environ['EXA'])
w = pathlib.Path(os.environ['W']); bad = n = 0
for md in sorted(tut.glob('*.md')):
    for kind, name, body in re.findall(
            r'```(m9|output|refusal) (\S+)\n(.*?)```', md.read_text(), re.S):
        n += 1
        if kind == 'm9':
            ok = body == (ex / name).read_text()
        elif kind == 'output':
            ok = body == (ex / 'expect' / (name + '.out')).read_text()
        else:
            ok = body.rstrip('\n') in (w / (name + '.err')).read_text()
        if not ok:
            print(f'DRIFT: {md.name} quotes {kind} {name} wrongly'); bad += 1
if n < 15:
    print(f'only {n} embedded blocks found -- the extractor is broken'); bad += 1
print(f'tutdiff: {n} embedded blocks match their gated sources')
sys.exit(1 if bad else 0)
PYCHK

echo "tutdiff: $ran examples green ($(ls "$EXA"/C*.m9 | wc -l) run, $(ls "$EXA"/X*.m9 | wc -l) refused as annotated)"
