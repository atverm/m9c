#!/bin/sh
# mandelbrot across M9, C, Rust, Object Pascal, Scala and Python.
#
# Three axes, because "fast" is only one of the things a language
# costs you:
#
#   run time      best of three after a warm-up, wall clock
#   build time    from clean, one file, the way the tool is invoked
#   deliverable   what you have to ship, stripped
#
# Outputs are DIFFED against the M9 one before any clock is read.  A
# benchmark whose result is not compared measures dead-code
# elimination, and six implementations of the same floating-point
# loop agreeing bit for bit is itself the finding that makes the
# timings mean anything.
#
# Numbers and their interpretation live in docs/bench.md.  Every
# toolchain except gcc is optional: absent, its column is skipped and
# said to be skipped, because a silently missing row reads as a row
# that was measured and lost.
set -e
cd "$(dirname "$0")"

N=${1:-4000}                    # the timed size
PYN=${2:-400}                   # pure CPython runs here instead
DIFFN=200                       # the size everything is compared at
OUT=/tmp/m9mandel
R=$(cd ../runtime && pwd)
CORPUS=$(cd ../corpus && pwd)
SRC=$(pwd)
M9C=${M9C:-$R/test/m9c}
[ -x "$M9C" ] || M9C=$(cd .. && pwd)/out/m9c
RUSTC=${RUSTC:-$HOME/.cargo/bin/rustc}
rm -rf "$OUT"; mkdir -p "$OUT"

have () { [ -x "$1" ] || command -v "$1" >/dev/null 2>&1; }

# Wall clock of one command.  time's own output goes to a FILE, not
# through 2>&1: the timed program's stderr has to be discarded (the
# Scala one prints its compute time there) and a single 2>&1 would
# discard the measurement with it.  That mistake produced a table of
# empty columns the first time this ran.
took () {
  /usr/bin/time -f %e -o "$OUT/t.time" "$@" >/dev/null 2>/dev/null
  cat "$OUT/t.time"
}

# the same, for build steps: a compiler that chatters on stdout would
# otherwise end up INSIDE the number, which is how the first run
# reported fpc's banner as its build time
timeit () {
  /usr/bin/time -f %e -o "$OUT/b.time" "$@" >/dev/null 2>/dev/null
  cat "$OUT/b.time"
}

# ---------------------------------------------------------------- build
echo "building (and timing the build) ..."

# M9 is two steps and they are reported separately: m9c checks and
# generates, cc compiles.  Conflating them would hide the only build
# number this project controls.
t_m9c=$(timeit sh -c "cd '$OUT' && '$M9C' '$SRC/Mandel.m9' '$CORPUS/Io.m9' '$CORPUS/DynStr.m9'")
t_m9cc=$(timeit gcc -O2 -std=c11 -iquote "$R" -iquote "$R/gen" \
    "$R/m9rt.c" "$R/gen/DynStr.c" "$R/gen/Io.c" "$OUT/Mandel.c" -o "$OUT/m_m9")
t_m9=$(echo "$t_m9c $t_m9cc" | awk '{printf "%.2f", $1 + $2}')

t_c=$(timeit gcc -O2 -std=c11 mandel_c.c -o "$OUT/m_c")

if have clang; then
  clang -w -O2 -std=c11 -iquote "$R" -iquote "$R/gen" "$R/m9rt.c" \
      "$R/gen/DynStr.c" "$R/gen/Io.c" "$OUT/Mandel.c" -o "$OUT/m_m9_clang"
  clang -w -O2 -std=c11 mandel_c.c -o "$OUT/m_c_clang"
fi

if [ -x "$RUSTC" ]; then
  t_rs=$(timeit "$RUSTC" -O -C debuginfo=0 mandel.rs -o "$OUT/m_rs")
else
  echo "note: no rustc, skipping the Rust column"
fi

if have fpc; then
  t_fpc=$(timeit fpc -O2 -FE"$OUT" -omandel_fpc mandel.pas)
  mv "$OUT/mandel_fpc" "$OUT/m_fpc"
  fpc -O2 -dUNCHECKED -FE"$OUT" -omandel_fpcu mandel.pas >/dev/null
  mv "$OUT/mandel_fpcu" "$OUT/m_fpcu"
else
  echo "note: no fpc, skipping the Object Pascal column"
fi

if have scala-cli; then
  # --assembly: one jar that java can run, which is the closest thing
  # to an executable this toolchain produces.  Timed with a WARM
  # cache: the first ever run downloads a compiler and a JVM, and
  # 30 seconds of network is not a property of the language.
  t_scala=$(timeit scala-cli --power package --offline \
      Mandel.scala -o "$OUT/mandel.jar" --assembly --force)
else
  echo "note: no scala-cli, skipping the Scala column"
fi

# ---------------------------------------------------------------- agree
echo "checking answers agree (N=$DIFFN) ..."
"$OUT/m_m9" "$DIFFN" "$OUT/ref.pbm"
agree=1
check () {                      # check LABEL command...
  lbl=$1; shift
  "$@" "$DIFFN" "$OUT/$lbl.pbm" >/dev/null 2>&1 || {
    echo "  $lbl: FAILED TO RUN"; agree=0; return; }
  cmp -s "$OUT/ref.pbm" "$OUT/$lbl.pbm" || { echo "  $lbl: DIVERGES"; agree=0; }
}
check c        "$OUT/m_c"
[ -x "$OUT/m_m9_clang" ] && check m9clang "$OUT/m_m9_clang"
[ -x "$OUT/m_c_clang" ]  && check cclang  "$OUT/m_c_clang"
[ -x "$OUT/m_rs" ]   && check rs   "$OUT/m_rs"
[ -x "$OUT/m_fpc" ]  && check fpc  "$OUT/m_fpc"
[ -x "$OUT/m_fpcu" ] && check fpcu "$OUT/m_fpcu"
[ -f "$OUT/mandel.jar" ] && check scala java -jar "$OUT/mandel.jar"
check py    python3 mandel.py
check numpy python3 mandel_np.py
[ "$agree" = 1 ] || { echo "implementations disagree -- not timing anything"; exit 1; }
echo "all implementations produce the same $(stat -c %s "$OUT/ref.pbm")-byte bitmap"

# ---------------------------------------------------------------- time
best () {                       # best of three after a warm-up
  "$@" "$N" "$OUT/t.pbm" >/dev/null 2>&1
  b=99999
  for _ in 1 2 3; do
    s=$(took "$@" "$N" "$OUT/t.pbm")
    b=$(echo "$s $b" | awk '{print ($1<$2)?$1:$2}')
  done
  echo "$b"
}

echo
echo "mandelbrot N=$N, best of three:"
r_m9=$(best "$OUT/m_m9");  printf '  %-28s %ss\n' 'M9 gcc -O2 (checked)' "$r_m9"
[ -x "$OUT/m_m9_clang" ] && { r_m9c=$(best "$OUT/m_m9_clang"); printf '  %-28s %ss\n' 'M9 clang -O2 (checked)' "$r_m9c"; }
r_c=$(best "$OUT/m_c");    printf '  %-28s %ss\n' 'C gcc -O2' "$r_c"
[ -x "$OUT/m_c_clang" ] && { r_cc=$(best "$OUT/m_c_clang"); printf '  %-28s %ss\n' 'C clang -O2' "$r_cc"; }
[ -x "$OUT/m_rs" ]  && { r_rs=$(best "$OUT/m_rs");   printf '  %-28s %ss\n' 'Rust -O' "$r_rs"; }
[ -x "$OUT/m_fpc" ] && { r_fp=$(best "$OUT/m_fpc");  printf '  %-28s %ss\n' 'FPC -O2 (R+ Q+)' "$r_fp"; }
[ -x "$OUT/m_fpcu" ] && { r_fu=$(best "$OUT/m_fpcu"); printf '  %-28s %ss\n' 'FPC -O2 (default, no checks)' "$r_fu"; }
if [ -f "$OUT/mandel.jar" ]; then
  r_sc=$(best java -jar "$OUT/mandel.jar")
  printf '  %-28s %ss  (JVM start included)\n' 'Scala 3, JVM' "$r_sc"
  # the same run says how much of that was compute rather than
  # starting a virtual machine -- both numbers are true, and which
  # one is relevant depends on whether the program is a service or a
  # command
  c=$(java -jar "$OUT/mandel.jar" "$N" "$OUT/t.pbm" 2>&1 >/dev/null | tail -1)
  printf '  %-28s %s\n' '' "$c"
fi
r_np=$(best python3 mandel_np.py); printf '  %-28s %ss\n' 'Python + numpy' "$r_np"

echo
echo "pure CPython is run at N=$PYN instead, and scaled:"
p=$(took python3 mandel.py "$PYN" "$OUT/t.pbm")
printf '  %-28s %ss at N=%s\n' 'Python 3' "$p" "$PYN"
echo "$p $PYN $N $r_m9" | awk '{
  f = ($3 / $2) ^ 2 ; t = $1 * f
  printf "  %-28s %.0fs projected at N=%s", "", t, $3
  if ($4 + 0 > 0) printf "  (%.0fx M9)", t / $4
  printf "\n" }'

# ---------------------------------------------------------------- ship
echo
echo "build time, one file, from clean:"
printf '  %-28s %ss  (m9c %ss + cc %ss)\n' 'M9' "$t_m9" "$t_m9c" "$t_m9cc"
printf '  %-28s %ss\n' 'C (gcc)' "$t_c"
[ -n "$t_rs" ]    && printf '  %-28s %ss\n' 'Rust (rustc)' "$t_rs"
[ -n "$t_fpc" ]   && printf '  %-28s %ss\n' 'Object Pascal (fpc)' "$t_fpc"
[ -n "$t_scala" ] && printf '  %-28s %ss  (warm cache, no download)\n' 'Scala (scala-cli)' "$t_scala"

echo
echo "what you ship, stripped:"
size () {                       # size LABEL FILE
  [ -f "$2" ] || return 0
  strip -o "$OUT/s.tmp" "$2" 2>/dev/null || cp "$2" "$OUT/s.tmp"
  printf '  %-28s %9d bytes\n' "$1" "$(stat -c %s "$OUT/s.tmp")"
}
size 'M9'                  "$OUT/m_m9"
size 'C'                   "$OUT/m_c"
size 'Rust'                "$OUT/m_rs"
size 'Object Pascal'       "$OUT/m_fpc"
[ -f "$OUT/mandel.jar" ] && printf '  %-28s %9d bytes  (+ a JVM)\n' 'Scala assembly jar' "$(stat -c %s "$OUT/mandel.jar")"
printf '  %-28s %9d bytes  (+ CPython)\n' 'Python source' "$(stat -c %s mandel.py)"
