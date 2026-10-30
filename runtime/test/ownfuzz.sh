#!/bin/sh
# ownfuzz: the ownership checker held to an independent model
# (2026-10-28; tools/ownfuzz/, decision 74).  A test case is a sequence
# of ownership operations (NEW, MOVE, BORROW, STORE, LOAD, GIVE,
# GIVEFIELD, FREE, READ, READFIELD, KEEP, KEPTPOOL) in a language-neutral
# form; tools/ownfuzz/ir.py executes it on a heap model that knows
# nothing of M9's rules, and translates it to M9.  The translator is
# trusted harness, so it has golden tests of its own.
#
#   1. golden.py: every golden/*.ops translates to its reviewed .m9 and
#      runs on the model to its reviewed .want, byte for byte;
#   2. golden.py --compile: each golden program this tree's checker
#      accepts is built and run under ASan+UBSan and the M9_ASAN arenas,
#      and does what the model says -- a fault where it says unsafe, the
#      exact printed line where it says safe -- so the translation is
#      held to the model through the real compiler;
#   3. fuzz.py: a FIXED sample of 200 sequences (seed 11), each checked;
#      an accepted one is run under the sanitizers.  A HOLE (accepted,
#      faults) or a MISMATCH (accepted, and the run and the model
#      disagree otherwise) is red, shrunk to its fewest operations.
#      Refusals of programs the model calls safe are printed, never
#      gated: the checker is conservative by design.
#
# Shown able to fail: develop a5d415af's compiler gives 28 holes in
# 1000 sequences and 1 in this sample of 200 (measured, 2026-10-28); a
# model that let an unset field raise under GIVEFIELD gave 82
# mismatches in 1000.  About 2 min on the MacBook.
cd "$(dirname "$0")" || exit 1
. ./lib/gen.sh          # runtime/gen is BUILT here, not found
ROOT=$(cd ../.. && pwd)
W=$(mktemp -d /tmp/m9ownfuzz.XXXXXX)
trap 'rm -rf "$W"' EXIT
gcc -std=c11 -O2 -iquote .. -iquote ../gen ../m9rt.c $COMPILERC -lm -o "$W/m9c" || { echo "ownfuzz: FAIL building m9c"; exit 1; }
export OWNFUZZ_TREE="$ROOT"
export SANCC_REAL="${CC:-gcc}"
H="$ROOT/tools/ownfuzz"
fail=0
python3 -I "$H/golden.py" > "$W/golden.out" 2>&1 || { echo "ownfuzz: FAIL golden text/model:"; sed 's/^/    /' "$W/golden.out"; fail=1; }
python3 -I "$H/golden.py" --compile tree="$W/m9c" > "$W/goldenc.out" 2>&1 ||
  { echo "ownfuzz: FAIL golden under the sanitizers:"; grep -v agrees "$W/goldenc.out" | grep -v refused | sed 's/^/    /'; fail=1; }
python3 -I -u "$H/fuzz.py" "$W/fuzz" 200 11 tree="$W/m9c" > "$W/fuzz.out" 2>&1 ||
  { echo "ownfuzz: FAIL fuzz:"; sed 's/^/    /' "$W/fuzz.out"; fail=1; }
[ "$fail" = 0 ] || exit 1
echo "ownfuzz: $(tail -1 "$W/golden.out"); $(head -1 "$W/fuzz.out" | sed 's/^tree: //') (200 sequences, seed 11)"
