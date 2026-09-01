#!/bin/sh
# binary-trees across M9, C and Rust.  Outputs are DIFFED before any
# clock is read: a benchmark whose result is not compared measures
# dead-code elimination.  Best of three after a warm-up, because the
# mean measures the scheduler and the page cache lies.
#
# Numbers and their interpretation live in docs/bench.md.  Rust is
# optional -- without it the C decomposition still runs, which is the
# part that says what M9's own choices cost.
set -e
cd "$(dirname "$0")"
R=../runtime
OUT=/tmp/m9bench
DEPTH=${1:-18}
mkdir -p "$OUT"

CARGO=${CARGO:-$HOME/.cargo/bin/cargo}
RUSTC=${RUSTC:-$HOME/.cargo/bin/rustc}

echo "building ..."
( cd "$OUT" && "$(cd ../../runtime/test >/dev/null 2>&1 && pwd || echo ../runtime/test)/m9c" \
    "$(cd .. >/dev/null; pwd)/../bench/BinTrees.m9" >/dev/null 2>&1 ) || true
# m9c needs absolute paths; do it plainly instead
M9C=$(cd "$R/test" && pwd)/m9c
SRC=$(pwd)
CORPUS=$(cd ../corpus && pwd)
RT=$(cd "$R" && pwd)
( cd "$OUT" && "$M9C" "$SRC/BinTrees.m9" "$CORPUS/Io.m9" )
gcc -O2 -std=c11 -iquote "$RT" -iquote "$RT/gen" "$RT/m9rt.c" "$RT/gen/DynStr.c" \
    "$RT/gen/Io.c" "$OUT/BinTrees.c" -o "$OUT/bt_m9"
gcc -O2 -std=c11 -DMODE=0 -I"$RT" "$RT/m9rt.c" bintrees_c.c -o "$OUT/bt_c_bump"
gcc -O2 -std=c11 -DMODE=1 -I"$RT" "$RT/m9rt.c" bintrees_c.c -o "$OUT/bt_c_pool"

HAVE_FPC=0
if command -v fpc >/dev/null 2>&1; then
  # Object Pascal, both ways from one source: {$R+}{$Q+} as written,
  # and -dUNCHECKED for what FPC's own default gives you.  M9 is in
  # the Wirth line and the zarr reader whose bugs became the museum
  # was an FPC program, so this is the column that says what the
  # reaction to it cost.
  HAVE_FPC=1
  fpc -O2 -FE"$OUT" -obt_fpc  bintrees.pas >/dev/null
  fpc -O2 -dUNCHECKED -FE"$OUT" -obt_fpcu bintrees.pas >/dev/null
fi

HAVE_SCALA=0
if command -v scala-cli >/dev/null 2>&1; then
  # what the colleagues write.  An assembly jar rather than
  # `scala-cli run`, so the timed command is java and not a build
  # tool deciding whether to rebuild.
  HAVE_SCALA=1
  scala-cli --power package --offline BinTrees.scala \
      -o "$OUT/bt.jar" --assembly --force >/dev/null 2>&1
fi

HAVE_RUST=0
if [ -x "$RUSTC" ]; then
  HAVE_RUST=1
  "$RUSTC" -O -C debuginfo=0 bintrees_box.rs -o "$OUT/bt_box"
  mkdir -p "$OUT/arena/src"
  cp bintrees_arena.rs "$OUT/arena/src/main.rs"
  cat > "$OUT/arena/Cargo.toml" <<EOF
[package]
name = "bintrees_arena"
version = "0.1.0"
edition = "2021"
[dependencies]
typed-arena = "2"
EOF
  ( cd "$OUT/arena" && "$CARGO" build --release >/dev/null 2>&1 ) \
    && cp "$OUT/arena/target/release/bintrees_arena" "$OUT/bt_arena" \
    || echo "note: typed-arena unavailable, skipping that column"
fi

echo "checking answers agree ..."
"$OUT/bt_m9" "$DEPTH" > "$OUT/ref.txt"
for p in bt_c_bump bt_c_pool bt_box bt_arena bt_fpc bt_fpcu; do
  [ -x "$OUT/$p" ] || continue
  "$OUT/$p" "$DEPTH" > "$OUT/$p.txt"
  cmp -s "$OUT/ref.txt" "$OUT/$p.txt" || { echo "DIVERGES: $p"; exit 1; }
done
# the JVM and the interpreter are compared at a smaller depth, which
# they reach in a second rather than in a minute.  Same program, same
# answers; the timed runs below are at the full depth for everything
# that can stand it.
SMALL=12
"$OUT/bt_m9" "$SMALL" > "$OUT/refsmall.txt"
[ -f "$OUT/bt.jar" ] && { java -jar "$OUT/bt.jar" "$SMALL" > "$OUT/bt_sc.txt"
  cmp -s "$OUT/refsmall.txt" "$OUT/bt_sc.txt" || { echo "DIVERGES: scala"; exit 1; }; }
python3 bintrees.py "$SMALL" > "$OUT/bt_py.txt"
cmp -s "$OUT/refsmall.txt" "$OUT/bt_py.txt" || { echo "DIVERGES: python"; exit 1; }
echo "all implementations agree"

best () {                       # best of three, after a warm-up
  "$@" "$DEPTH" >/dev/null
  b=999
  for _ in 1 2 3; do
    s=$( { /usr/bin/time -f %e "$@" "$DEPTH" >/dev/null ; } 2>&1 )
    b=$(echo "$s $b" | awk '{print ($1<$2)?$1:$2}')
  done
  echo "$b"
}

once () {                       # one run, for columns measured in
  s=$( { /usr/bin/time -f %e "$@" >/dev/null ; } 2>&1 )   # tens of
  echo "$s"                                               # seconds
}

echo
echo "binary-trees, depth $DEPTH, best of three:"
[ -x "$OUT/bt_arena" ]  && printf '  %-24s %ss\n' 'Rust typed-arena' "$(best "$OUT/bt_arena")"
printf '  %-24s %ss\n' 'C bump (no zero)'      "$(best "$OUT/bt_c_bump")"
printf '  %-24s %ss\n' 'C m9rt pool (zeroed)'  "$(best "$OUT/bt_c_pool")"
printf '  %-24s %ss\n' 'M9 (pool+checks+ABI)'  "$(best "$OUT/bt_m9")"
[ -x "$OUT/bt_box" ]    && printf '  %-24s %ss\n' 'Rust Box' "$(best "$OUT/bt_box")"
[ -x "$OUT/bt_fpc" ]    && printf '  %-24s %ss\n' 'FPC New/Dispose (R+Q+)' "$(best "$OUT/bt_fpc")"
[ -x "$OUT/bt_fpcu" ]   && printf '  %-24s %ss\n' 'FPC New/Dispose (default)' "$(best "$OUT/bt_fpcu")"
[ -f "$OUT/bt.jar" ]    && printf '  %-24s %ss  (GC deferred, not paid)\n' 'Scala 3, JVM' "$(best java -jar "$OUT/bt.jar")"
printf '  %-24s %ss  (one run)\n' 'Python 3 (tuples)' "$(once python3 bintrees.py "$DEPTH")"

echo
echo "stripped binary size:"
for p in bt_c_bump bt_m9 bt_box bt_arena bt_fpc; do
  [ -x "$OUT/$p" ] || continue
  strip -o "$OUT/$p.s" "$OUT/$p"
  printf '  %-24s %8d bytes\n' "$p" "$(stat -c %s "$OUT/$p.s")"
done

# ---- fannkuch-redux: what the always-on checks cost ----------------
( cd "$OUT" && "$M9C" "$SRC/Fannkuch.m9" "$CORPUS/Io.m9" )
gcc -O2 -std=c11 -iquote "$RT" -iquote "$RT/gen" "$RT/m9rt.c" "$RT/gen/DynStr.c" \
    "$RT/gen/Io.c" "$OUT/Fannkuch.c" -o "$OUT/fk_m9"
gcc -O2 -std=c11 fannkuch_c.c -o "$OUT/fk_c"
command -v clang >/dev/null && clang -w -O2 -std=c11 -iquote "$RT" -iquote "$RT/gen" \
    "$RT/m9rt.c" "$RT/gen/DynStr.c" "$RT/gen/Io.c" "$OUT/Fannkuch.c" \
    -o "$OUT/fk_m9_clang"
if [ "$HAVE_RUST" = 1 ]; then
  "$RUSTC" -O -C debuginfo=0 fannkuch.rs -o "$OUT/fk_rs"
  "$RUSTC" -O -C debuginfo=0 -C overflow-checks=on fannkuch.rs -o "$OUT/fk_rs_oc"
fi
if [ "$HAVE_FPC" = 1 ]; then
  # the same question Rust's overflow-checks pair asks, put to the
  # language M9 is descended from
  fpc -O2 -FE"$OUT" -ofk_fpc  fannkuch.pas >/dev/null
  fpc -O2 -dUNCHECKED -FE"$OUT" -ofk_fpcu fannkuch.pas >/dev/null
fi
if [ "$HAVE_SCALA" = 1 ]; then
  scala-cli --power package --offline Fannkuch.scala \
      -o "$OUT/fk.jar" --assembly --force >/dev/null 2>&1
fi

FN=${2:-11}
"$OUT/fk_m9" 9 > "$OUT/fkref.txt"
for p in fk_c fk_m9_clang fk_rs fk_rs_oc fk_fpc fk_fpcu; do
  [ -x "$OUT/$p" ] || continue
  "$OUT/$p" 9 > "$OUT/$p.txt"
  cmp -s "$OUT/fkref.txt" "$OUT/$p.txt" || { echo "DIVERGES: $p"; exit 1; }
done
[ -f "$OUT/fk.jar" ] && { java -jar "$OUT/fk.jar" 9 > "$OUT/fk_sc.txt"
  cmp -s "$OUT/fkref.txt" "$OUT/fk_sc.txt" || { echo "DIVERGES: scala"; exit 1; }; }
python3 fannkuch.py 9 > "$OUT/fk_py.txt"
cmp -s "$OUT/fkref.txt" "$OUT/fk_py.txt" || { echo "DIVERGES: python"; exit 1; }

bestn () { "$@" "$FN" >/dev/null; b=999
  for _ in 1 2 3; do
    s=$( { /usr/bin/time -f %e "$@" "$FN" >/dev/null ; } 2>&1 )
    b=$(echo "$s $b" | awk '{print ($1<$2)?$1:$2}')
  done; echo "$b"; }

echo
echo "fannkuch-redux, n=$FN, best of three:"
[ -x "$OUT/fk_rs_oc" ] && printf '  %-30s %ss\n' 'Rust -C overflow-checks=on' "$(bestn "$OUT/fk_rs_oc")"
[ -x "$OUT/fk_rs" ]    && printf '  %-30s %ss\n' 'Rust -O (release default)'  "$(bestn "$OUT/fk_rs")"
[ -x "$OUT/fk_m9_clang" ] && printf '  %-30s %ss\n' 'M9 clang -O2 (all checks)' "$(bestn "$OUT/fk_m9_clang")"
printf '  %-30s %ss\n' 'M9 gcc -O2 (all checks)' "$(bestn "$OUT/fk_m9")"
printf '  %-30s %ss\n' 'C gcc -O2 (no checks)'   "$(bestn "$OUT/fk_c")"
[ -x "$OUT/fk_fpc" ]  && printf '  %-30s %ss\n' 'FPC -O2 (R+ Q+)' "$(bestn "$OUT/fk_fpc")"
[ -x "$OUT/fk_fpcu" ] && printf '  %-30s %ss\n' 'FPC -O2 (default, no checks)' "$(bestn "$OUT/fk_fpcu")"
[ -f "$OUT/fk.jar" ]  && printf '  %-30s %ss  (bounds checked, ints wrap)\n' 'Scala 3, JVM' "$(bestn java -jar "$OUT/fk.jar")"
printf '  %-30s %ss  (one run; slices, not loops)\n' 'Python 3' "$(once python3 fannkuch.py "$FN")"
