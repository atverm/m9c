#!/bin/sh
# m9utf, the migration tool of the UTF-8 switch (docs/utf8-stage4-plan.md,
# 4c): a fixpoint over the flagged checker's diagnostics, rewriting each
# site by the shape of its neighbours and listing what it cannot decide.
#
# Held two ways.  Sort.m9 and Time.m9, copied, are rewritten into
# exactly utf/expect/Sort.m9 and utf/expect/Time.m9 (8 and 29 edits, an
# IMPORT Text each), both rewrites check clean under --utf-str, and
# Sort's runs SortTest, SeqTest and StatsTest switched -- the tool's
# output is the switched source, proved by the tests, not by the eye
# (TimeTest waits for Http, which it imports).  utf/Review.m9 holds the
# shapes the tool must NOT touch beside the ones it must: its rewrite
# and its review list are utf/expect/Review.m9 and utf/expect/review.txt.
#
# Timed 2026-10-25 on the MacBook (105 s, then 92 with the tests in
# parallel): the tool built under --run 16 s (its cache key holds the
# compiler's mtime, and this gate links its own), the Http pass 7, its
# two tests 9, the seven library batches' 21 tests 39 serial and 23 in
# parallel, the toolchain batch 2, the switched compiler's build 25
# (-O2 and LTO), the C and probe comparisons 5.
set -e
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")"

# a worker (2026-10-25, Alex: "parallel tests it is"): one rewritten
# test built and run switched, its output and status into $W, from a
# cache of its own copied from the warmed one -- two --run builds must
# not share a cache, a .o written by one being read by the other
if [ "$1" = --one-test ]; then
  M9C=$2; W=$3; m=$4
  [ -d "$W/cache-$m" ] || cp -R "$W/cache" "$W/cache-$m"
  export M9CACHE=$W/cache-$m
  ( cd ../.. && "$M9C" --utf-str -I "$W/out" --run "$W/out/${m}Test.m9" ) > "$W/${m}Test.out" 2>&1
  echo $? > "$W/${m}Test.rc"
  exit 0
fi
JOBS=${M9_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}

. ./lib/gen.sh
. ./lib/mods.sh
W=$(mktemp -d)
# M9_UTF_KEEP=DIR keeps the switched library the batches leave in
# $W/out -- what an application's own rehearsal builds against with
# `-I DIR` ahead of the corpus (maillists, 2026-10-25)
if [ -n "${M9_UTF_KEEP:-}" ]; then
  trap 'mkdir -p "$M9_UTF_KEEP" && cp "$W"/out/*.m9 "$M9_UTF_KEEP"/ ; rm -rf "$W"' EXIT
else
  trap 'rm -rf "$W"' EXIT
fi
gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function $CLANGWARN \
    -iquote .. -iquote ../gen ../m9rt.c $COMPILERC -lm -o "$W/m9c"
M9C=$W/m9c
RT=$(cd .. && pwd)
SRC=$(cd ../../corpus && pwd)
TOOL=$(cd ../../tools && pwd)/M9utf.m9
F=$(pwd)/utf
export M9RUNTIME=$RT M9LIBRARY=$SRC M9CACHE=$W/cache
mkdir -p "$W/in" "$W/out"
cp "$SRC/Sort.m9" "$SRC/Time.m9" "$F/Review.m9" "$W/in/"

# the tool, through --run with this tree's compiler, on the two files
"$M9C" --run "$TOOL" --m9c="$M9C" --out="$W/out" "$W/in/Sort.m9" "$W/in/Time.m9" "$W/in/Review.m9" 2> "$W/tool.err" ||
  { echo "utf: the tool failed:"; cat "$W/tool.err"; exit 1; }
grep ': review: ' "$W/tool.err" | sed "s#$W/in/##" > "$W/review.txt"
for f in Sort.m9 Time.m9 Review.m9; do
  cmp -s "$W/out/$f" "$F/expect/$f" || {
    echo "utf: $f's rewrite differs from expect/$f (< expected, > the tool):"
    diff "$F/expect/$f" "$W/out/$f" | sed 's/^/    /'; exit 1; }
done
cmp -s "$W/review.txt" "$F/expect/review.txt" || {
  echo "utf: the review list differs from expect/review.txt (< expected, > the tool):"
  diff "$F/expect/review.txt" "$W/review.txt" | sed 's/^/    /'; exit 1; }
summary=$(tail -1 "$W/tool.err")
echo "utf: Sort, Time and Review rewritten as expected ($summary)"

# the rewritten Sort is the switched source: clean under the flag,
# refused without it (its LEN and subscripts are gone)
for f in Sort Time; do
  "$M9C" --utf-str --check "$W/out/$f.m9" > "$W/$f.flag" 2>&1 ||
    { echo "utf: the rewritten $f is refused under --utf-str:"; cat "$W/$f.flag"; exit 1; }
done
if "$M9C" --check "$W/out/Sort.m9" > /dev/null 2>&1; then
  echo "utf: the rewritten Sort is accepted WITHOUT the flag -- it should not be (Text.BLen of a STR)"; exit 1
fi
# and three tests run switched with it, from the repository root
for tn in SortTest SeqTest StatsTest; do
  ( cd ../.. && "$M9C" --utf-str -I "$W/out" --run "corpus/$tn.m9" ) > "$W/$tn.out" 2>&1 ||
    { echo "utf: $tn did not build and run switched with the rewritten Sort:"; grep -a -v '^ok' "$W/$tn.out" | head -12 | sed 's/^/    /'; exit 1; }
  last=$(tail -1 "$W/$tn.out")
  case "$last" in
    "PASS ("*) echo "utf: $tn switched with the tool's Sort: $last" ;;
    *) echo "utf: $tn switched ended '$last'"; exit 1 ;;
  esac
done

# Http and HttpServer: the tool's pass, then the HAND edits it cannot
# make (utf/expect/*.hand.diff: KeepStr through UTF (f, s), UrlDecode as
# one octet buffer, SameCi byte by byte; Once's ViewIn is the tool's
# since 2026-10-25), kept as a diff
# so that what the hands did stays readable.  The tool's review list for
# the two is held with its positions, which pins the tool's output where
# the hands go; the patched sources check clean under the flag and run
# HttpTest and TimeTest switched.
cp "$SRC/Http.m9" "$SRC/HttpServer.m9" "$W/in/"
"$M9C" --run "$TOOL" --m9c="$M9C" --out="$W/out" "$W/in/Http.m9" "$W/in/HttpServer.m9" 2> "$W/tool2.err" ||
  { echo "utf: the tool failed on Http:"; cat "$W/tool2.err"; exit 1; }
grep ': review: ' "$W/tool2.err" | sed "s#$W/in/##" > "$W/review-http.txt"
cmp -s "$W/review-http.txt" "$F/expect/review-http.txt" || {
  echo "utf: Http's review list differs from expect/review-http.txt (< expected, > the tool):"
  diff "$F/expect/review-http.txt" "$W/review-http.txt" | sed 's/^/    /'; exit 1; }
for f in Http HttpServer; do
  if [ -f "$F/expect/$f.hand.diff" ]; then
    ( cd "$W/out" && patch -s -N "$f.m9" < "$F/expect/$f.hand.diff" ) ||
      { echo "utf: expect/$f.hand.diff does not apply to the tool's $f -- the tool's output moved under the hand edits"; exit 1; }
  fi
  "$M9C" --utf-str --check -I "$W/out" "$W/out/$f.m9" > "$W/$f.flag" 2>&1 ||
    { echo "utf: $f, rewritten and hand-edited, is refused under --utf-str:"; cat "$W/$f.flag"; exit 1; }
done
echo "utf: Http and HttpServer rewritten, hand-edited and clean under the flag ($(tail -1 "$W/tool2.err"))"
for tn in HttpTest TimeTest; do
  ( cd ../.. && "$M9C" --utf-str -I "$W/out" --run "corpus/$tn.m9" ) > "$W/$tn.out" 2>&1 ||
    { echo "utf: $tn did not build and run switched with the rewritten Http:"; grep -a -v '^ok' "$W/$tn.out" | head -12 | sed 's/^/    /'; exit 1; }
  last=$(tail -1 "$W/$tn.out")
  case "$last" in
    "PASS ("*) echo "utf: $tn switched with the tool's Http: $last" ;;
    *) echo "utf: $tn switched ended '$last'"; exit 1 ;;
  esac
done

# The batches (Alex, 2026-10-24: five modules a commit): each module
# WITH ITS TEST through the tool -- a test is a source like any other --
# then the hand diffs that exist for it, the module clean under the flag,
# and the REWRITTEN test run switched from the repository root.  The
# tool's review list for the batch is held with its positions.  The
# modules done before are in $W/out already, so a closure reaching Http,
# Time or Sort finds them switched.
batch () {   # batch NAME MODULE...
  name=$1; shift
  : > "$W/$name.err"
  # a module without a test (Dict, Delim, ApiSpec, Zarr...) goes through
  # alone and is held to the flag check; one with a test takes it along
  for m in "$@"; do
    cp "$SRC/$m.m9" "$W/in/"
    [ -f "$SRC/${m}Test.m9" ] && cp "$SRC/${m}Test.m9" "$W/in/"
  done
  set -- $(for m in "$@"; do echo "$W/in/$m.m9"; [ -f "$SRC/${m}Test.m9" ] && echo "$W/in/${m}Test.m9"; done | sort)   # the review list is in file order
  "$M9C" --run "$TOOL" --m9c="$M9C" --out="$W/out" "$@" 2> "$W/$name.err" ||
    { echo "utf: the tool failed on batch $name:"; cat "$W/$name.err"; exit 1; }
  grep ': review: ' "$W/$name.err" | sed "s#$W/in/##" > "$W/review-$name.txt"
  # compared without :LINE:COL: -- the sources are the live tree, and an
  # edit above a listed site moved the list four times in two days with
  # nothing in it changed (2026-10-25/26); the files keep the positions
  # for a reader, and a hand diff applies by its context
  sed -E 's/:[0-9]+:[0-9]+:/:/' "$W/review-$name.txt" > "$W/review-$name.np"
  sed -E 's/:[0-9]+:[0-9]+:/:/' "$F/expect/review-$name.txt" > "$W/expect-$name.np"
  cmp -s "$W/review-$name.np" "$W/expect-$name.np" || {
    echo "utf: batch $name's review list differs from expect/review-$name.txt (< expected, > the tool; positions aside):"
    diff "$W/expect-$name.np" "$W/review-$name.np" | sed 's/^/    /'; exit 1; }
  for f in "$@"; do
    b=$(basename "$f" .m9)
    [ -f "$F/expect/$b.hand.diff" ] || continue
    ( cd "$W/out" && patch -s -N "$b.m9" < "$F/expect/$b.hand.diff" ) ||
      { echo "utf: expect/$b.hand.diff does not apply to the tool's $b"; exit 1; }
  done
  echo "utf: batch $name rewritten ($(tail -1 "$W/$name.err"))"
}
runbatch () {   # runbatch NAME MODULE...: each module clean under the flag, its rewritten test PASS
  name=$1; shift
  tests=""
  for m in "$@"; do
    "$M9C" --utf-str --check -I "$W/out" "$W/out/$m.m9" > "$W/$m.flag" 2>&1 ||
      { echo "utf: $m, rewritten, is refused under --utf-str:"; cat "$W/$m.flag"; exit 1; }
    if [ ! -f "$SRC/${m}Test.m9" ]; then
      echo "utf: $m rewritten and clean under the flag (it has no test to run)"; continue
    fi
    # PgTest needs a server: m9test.sh runs it only where PGHOST names one
    if [ "$m" = Pg ] && [ -z "${PGHOST:-}" ]; then
      echo "utf: Pg rewritten and clean under the flag; PgTest WAITS for a server (PGHOST unset)"; continue
    fi
    tests="$tests $m"
  done
  # the tests at once (M9_JOBS, default the cores; the workers above),
  # judged one by one in the batch's order: 39 s serial for batches 1
  # to 7 on the MacBook, measured 2026-10-25
  [ -n "$tests" ] || return 0
  printf '%s\n' $tests | xargs -P "$JOBS" -n 1 sh "$SELF" --one-test "$M9C" "$W"
  for m in $tests; do
    rc=$(cat "$W/${m}Test.rc" 2>/dev/null || echo 98)
    [ "$rc" = 0 ] ||
      { echo "utf: ${m}Test did not build and run switched:"; grep -a -v '^ok' "$W/${m}Test.out" | head -12 | sed 's/^/    /'; exit 1; }
    last=$(tail -1 "$W/${m}Test.out")
    case "$last" in
      "PASS ("*) echo "utf: ${m}Test switched: $last" ;;
      *) echo "utf: ${m}Test switched ended '$last'"; exit 1 ;;
    esac
  done
}
B1="Csv NetCDF Zip System Hash"
batch b1 $B1
runbatch b1 $B1
B2="JsonUtf Map Plot Png Rsa"
batch b2 $B2
runbatch b2 $B2
B3="Frame Json NbCells NbShow Parquet"
batch b3 $B3
runbatch b3 $B3
B4="Rdf Smtp Sparql Xml ZarrStore"
batch b4 $B4
runbatch b4 $B4
B5="ApiSpec Delim Dict Pg Zarr"
batch b5 $B5
runbatch b5 $B5
B6="Arrow Grib Logger OpenApi Syslog"
batch b6 $B6
runbatch b6 $B6
# Regex, the last: its matcher positioned by byte and reading by
# character, spans in byte offsets (RegexTest's hand diff maps re's
# character indices to them)
B7="Regex"
batch b7 $B7
runbatch b7 $B7

# The toolchain: its thirteen modules through the tool (none has a
# NAMETest), then the proof that matters -- a COMPILER BUILT SWITCHED
# from the rewritten sources writes, for every module of runtime/gen,
# the same C as this tree's compiler, and gives the same diagnostics
# over every probe and museum piece.  (Held to the gate's own m9c, not
# to runtime/gen: gen.sh's driver loads no deep units, m9c does, and a
# module whose dependency binds libm carries that unit's externs under
# m9c -- the same under both compilers.)
B8="Ast Diag Doc Gen Lex Lsp M9c M9elide M9fmt Parse Print Review Sem"
batch b8 $B8
runbatch b8 $B8
( cd "$W" && "$M9C" --utf-str --make -o m9c-sw -I out out/M9c.m9 > sw.log 2>&1 ) ||
  { echo "utf: the switched compiler does not build:"; tail -20 "$W/sw.log"; exit 1; }
mkdir -p "$W/p" "$W/q"
same=0; differ=0
for c in ../gen/*.c; do
  m=$(basename "$c" .c)
  [ -f "$SRC/$m.m9" ] || continue
  ( cd ../.. && M9LIBRARY=corpus "$M9C" --out-dir "$W/p" "corpus/$m.m9" > /dev/null 2>&1 )
  ( cd ../.. && M9LIBRARY=corpus "$W/m9c-sw" --out-dir "$W/q" "corpus/$m.m9" > /dev/null 2>&1 )
  if cmp -s "$W/p/$m.c" "$W/q/$m.c" && cmp -s "$W/p/$m.h" "$W/q/$m.h"; then same=$((same+1))
  else echo "utf: the switched compiler's C of $m differs:"; diff "$W/p/$m.c" "$W/q/$m.c" | head -8 | sed 's/^/    /'; differ=$((differ+1)); fi
done
[ "$differ" = 0 ] || exit 1
echo "utf: the switched compiler writes the same C as this tree's for $same modules"
agree=0; differ=0
for p in ../../probes/*.m9 ../../museum/*.m9; do
  # a refused probe exits 1: not a failure of this gate (set -e)
  a=$( cd ../.. && "$M9C" --check "${p#../../}" 2>&1 || true )
  b=$( cd ../.. && "$W/m9c-sw" --check "${p#../../}" 2>&1 || true )
  if [ "$a" = "$b" ]; then agree=$((agree+1)); else echo "utf: the switched compiler's diagnostics differ on $p"; differ=$((differ+1)); fi
done
[ "$differ" = 0 ] || exit 1
echo "utf: and the same diagnostics over $agree probes and museum pieces"
