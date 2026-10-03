#!/bin/sh
# m9elide -- stage 4 of docs/pool-elision-plan.md: the tool that
# removes a pool parameter where rules 1 and 2 make it redundant,
# rewrites every call, and proves each edit by re-parsing.
#
# Gated: the fixture pair (a constructor that promises its pool, a
# mutator, a slice, a string and a frame-built list answered, a
# wrapper, a keeper, an output slot, a view stored through a VAR
# parameter) is rewritten EXACTLY as
# expected, comments and layout kept; the program prints the same
# lines before and after; the tool is idempotent; what it leaves to
# the checker is refused there BY NAME, and the decided variant
# compiles and runs; a stale pool argument (the callee lost its pool
# by hand, before the tool) goes by arity; --keep holds a procedure
# back; a file that does
# not parse is refused with its position and nothing is written; and
# every edit over the WHOLE CORPUS is proved (the counts are printed,
# never gated -- stage 5 ran the migration, so a run over the
# migrated corpus without its --keep list finds the readers again).
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found

SRC=$(cd ../../corpus && pwd)
RT=$(cd .. && pwd)
F=$(pwd)/elide
W=/tmp/m9elide-gate
rm -rf "$W"; mkdir -p "$W/fix" "$W/orig" "$W/pooled" "$W/decided" "$W/bad" "$W/corpus"

gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c \
    ../gen/Text.c ../gen/System.c ../gen/Lex.c ../gen/Ast.c ../gen/Print.c \
    ../gen/Parse.c ../gen/Sem.c ../gen/Doc.c ../gen/Review.c ../gen/Gen.c \
    ../gen/Io.c ../gen/M9c.c -lm -o "$W/m9c"
export M9RUNTIME="$RT"
export M9LIBRARY="$SRC"
( cd "$W" && ./m9c --make -o m9elide "$SRC/M9elide.m9" >build.log 2>&1 ) || \
  { echo "elide: FAIL building m9elide:"; tail -5 "$W/build.log"; exit 1; }
EL="$W/m9elide"
M9C="$W/m9c"

# ---- the fixture pair, rewritten exactly as expected ----------------
cp "$F/Grow.m9" "$F/UseGrow.m9" "$W/fix/"
( cd "$W/fix" && "$EL" -w Grow.m9 UseGrow.m9 2> ledger.txt ) || \
  { echo "elide: the tool refused the fixture:"; cat "$W/fix/ledger.txt"; exit 1; }
for f in Grow.m9 UseGrow.m9 ledger.txt; do
  cmp -s "$W/fix/$f" "$F/expect/$f" || {
    echo "elide: $f differs from expect/$f:"; diff "$F/expect/$f" "$W/fix/$f" || true; exit 1; }
done
echo "         Grow and UseGrow rewritten as expected, comments and layout kept"

# ---- the same program before and after -----------------------------
cp "$F/Grow.m9" "$F/UseGrow.m9" "$W/orig/"
( cd "$W/orig" && "$M9C" --make -o usegrow UseGrow.m9 -I . > build.log 2>&1 ) || \
  { echo "elide: the original pair does not build:"; cat "$W/orig/build.log"; exit 1; }
( cd "$W/fix" && "$M9C" --make -o usegrow UseGrow.m9 -I . > build.log 2>&1 ) || \
  { echo "elide: the rewritten pair does not build:"; cat "$W/fix/build.log"; exit 1; }
"$W/orig/usegrow" > "$W/orig.out"
"$W/fix/usegrow" > "$W/fix.out"
cmp -s "$W/orig.out" "$W/fix.out" || { echo "elide: the program changed its output:"; diff "$W/orig.out" "$W/fix.out"; exit 1; }
printf '55\n19\n6\n1\nid-7\n' > "$W/want.out"
cmp -s "$W/fix.out" "$W/want.out" || { echo "elide: the program is wrong before the tool touched it:"; cat "$W/fix.out"; exit 1; }
echo "         the program prints the same five lines before and after"

# ---- idempotent ------------------------------------------------------
( cd "$W/fix" && "$EL" -w Grow.m9 UseGrow.m9 2> again.txt )
cmp -s "$W/fix/Grow.m9" "$F/expect/Grow.m9" || { echo "elide: a second run changed Grow.m9"; exit 1; }
grep -q '^elide: 0 procedures lose their pool' "$W/fix/again.txt" || \
  { echo "elide: a second run found something to do:"; cat "$W/fix/again.txt"; exit 1; }
echo "         a second run changes nothing"

# ---- what the tool leaves to the checker, refused there by name ------
cp "$F/Grow.m9" "$F/Pooled.m9" "$W/pooled/"
( cd "$W/pooled" && "$EL" -w Grow.m9 Pooled.m9 2> /dev/null )
if ( cd "$W/pooled" && "$M9C" --check -I . Pooled.m9 > check.txt 2>&1 ); then
  echo "elide: the checker accepted a frame answer stored in a pooled module variable"; exit 1
fi
grep -q 'cannot be stored in module variable q' "$W/pooled/check.txt" || \
  { echo "elide: the refusal is not the one expected:"; cat "$W/pooled/check.txt"; exit 1; }
cp "$F/Grow.m9" "$W/decided/" && cp "$F/Pooled.decided.m9" "$W/decided/Pooled.m9"
( cd "$W/decided" && "$EL" -w Grow.m9 Pooled.m9 2> /dev/null )
( cd "$W/decided" && "$M9C" --make -o pooled Pooled.m9 -I . > build.log 2>&1 ) || \
  { echo "elide: the decided variant does not build:"; cat "$W/decided/build.log"; exit 1; }
[ "$("$W/decided/pooled")" = "3" ] || { echo "elide: the decided variant is wrong"; exit 1; }
echo "         a frame answer stored in a pooled module variable is refused by name; the decision compiles"

# ---- a stale pool argument goes by arity ------------------------------
# a caller written before its callee lost its pool by hand (Json and
# Text in stage 2): the callee takes none and the call hands one
# argument too many, so the argument goes and the caller's pool is
# not thereby kept.
mkdir -p "$W/stale"; cp "$F/Grow.m9" "$F/Stale.m9" "$W/stale/"
( cd "$W/stale" && "$EL" -w Grow.m9 Stale.m9 2> ledger.txt ) || \
  { echo "elide: the tool refused the stale fixture:"; cat "$W/stale/ledger.txt"; exit 1; }
cmp -s "$W/stale/Stale.m9" "$F/expect/Stale.m9" || {
  echo "elide: Stale.m9 differs from expect/Stale.m9:"; diff "$F/expect/Stale.m9" "$W/stale/Stale.m9" || true; exit 1; }
grep -q '1 stale pool arguments go' "$W/stale/ledger.txt" || \
  { echo "elide: the stale argument is not in the ledger:"; tail -1 "$W/stale/ledger.txt"; exit 1; }
( cd "$W/stale" && "$M9C" --make -o stale Stale.m9 -I . > build.log 2>&1 ) || \
  { echo "elide: the stale fixture does not build after the tool:"; cat "$W/stale/build.log"; exit 1; }
[ "$("$W/stale/stale")" = "9" ] || { echo "elide: the stale fixture is wrong"; exit 1; }
echo "         a pool handed to a callee that takes none goes by arity, and is no reason to keep"

# ---- --keep holds a procedure back -----------------------------------
rm -f "$W/pooled"/*.m9; cp "$F/Grow.m9" "$F/Pooled.m9" "$W/pooled/"
( cd "$W/pooled" && "$EL" -w --keep 'Grow.*' Grow.m9 Pooled.m9 2> keep.txt )
cmp -s "$W/pooled/Grow.m9" "$F/Grow.m9" || { echo "elide: --keep Grow.* still rewrote Grow"; exit 1; }
grep -q 'Grow.Pair: keeps pool: named by --keep' "$W/pooled/keep.txt" || \
  { echo "elide: --keep is not in the ledger:"; cat "$W/pooled/keep.txt"; exit 1; }
echo "         --keep holds a module back and says so"

# ---- what does not parse is not rewritten ----------------------------
cp "$F/Bad.m9" "$W/bad/"
if ( cd "$W/bad" && "$EL" -w Bad.m9 2> bad.txt ); then
  echo "elide: rewrote a file that does not parse"; exit 1
fi
grep -q ':3:.*parse:' "$W/bad/bad.txt" || { echo "elide: refusal without position:"; cat "$W/bad/bad.txt"; exit 1; }
cmp -s "$W/bad/Bad.m9" "$F/Bad.m9" || { echo "elide: a refused file was written"; exit 1; }
echo "         what does not parse is refused with the position, nothing written"

# ---- the whole corpus: every edit proved, the counts printed ---------
cp "$SRC"/*.m9 "$W/corpus/"
( cd "$W/corpus" && "$EL" -w ./*.m9 > /dev/null 2> ledger.txt ) || \
  { echo "elide: the corpus dry run failed:"; tail -5 "$W/corpus/ledger.txt"; exit 1; }
tail -1 "$W/corpus/ledger.txt" | sed 's/^elide: /         corpus, measured not gated: /'
echo "elide: the pool parameter goes where rules 1 and 2 make it redundant, every edit proved"
