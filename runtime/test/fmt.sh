#!/bin/sh
# m9fmt -- the canonical layout with the comments kept, gated on the
# properties it stands on rather than on corpus identity: the corpus
# is hand-laid-out and the formatter is not its fixpoint (the
# divergence is MEASURED and printed, never gated -- normalising the
# corpus is a decision, not a side effect of a test).
#
# Gated: every corpus, bench and museum file formats without refusal;
# formatting is IDEMPOTENT byte for byte; every comment survives
# (counted by the same comdump comdiff trusts); a file that does not
# parse is refused with the parser's own positions; --check answers
# both ways; -w rewrites once and then never again.
set -e
cd "$(dirname "$0")"
. ./gen.sh          # runtime/gen is BUILT here, not found

SRC=$(cd ../../corpus && pwd)
RT=$(cd .. && pwd)
W=/tmp/m9fmt-gate
rm -rf "$W"; mkdir -p "$W"

gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c \
    ../gen/Text.c ../gen/Lex.c ../gen/Ast.c ../gen/Print.c \
    ../gen/Parse.c ../gen/Sem.c ../gen/Doc.c ../gen/Gen.c \
    ../gen/Io.c ../gen/Time.c ../gen/M9c.c -lm -o "$W/m9c"
( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$SRC" ./m9c --make -o m9fmt "$SRC/M9fmt.m9" >build.log 2>&1 ) || \
  { echo "fmt: FAIL building m9fmt:"; tail -5 "$W/build.log"; exit 1; }
FMT="$W/m9fmt"

( cd ../../host/fpc && fpc -O2 comdump.pas >/dev/null 2>&1 ) || true
CD=../../host/fpc/comdump
[ -x "$CD" ] || { echo "fmt: SKIP comment counting (no fpc for comdump)"; CD=; }

files=0; div=0
for f in ../../corpus/*.m9 ../../bench/*.m9 ../../museum/*.m9; do
  [ -f "$f" ] || continue
  "$FMT" "$f" > "$W/a" 2>"$W/err" || { echo "fmt: REFUSED $f"; cat "$W/err"; exit 1; }
  "$FMT" "$W/a" > "$W/b" 2>/dev/null || { echo "fmt: its own output refused: $f"; exit 1; }
  cmp -s "$W/a" "$W/b" || { echo "fmt: NOT IDEMPOTENT: $f"; exit 1; }
  if [ -n "$CD" ]; then
    ca=$("$CD" "$f" | wc -l); cb=$("$CD" "$W/a" | wc -l)
    [ "$ca" = "$cb" ] || { echo "fmt: comments lost in $f ($ca -> $cb)"; exit 1; }
  fi
  cmp -s "$f" "$W/a" || div=$((div+1))
  files=$((files+1))
done
echo "         $files files: idempotent, comments kept ($div diverge from hand layout, measured not gated)"

# ---- probes ---------------------------------------------------------
cat > "$W/P.m9" <<'P'
(* the module's own banner *)

MODULE P ;

(* a column-one banner owned by nobody *)



VAR x : I64 ;  (* trailing stays on its line *)

BEGIN
  (* an indented comment, owned by the line above the convention says *)
  x := 1
END P.
P
"$FMT" "$W/P.m9" > "$W/P.fmt"
grep -q '^(\* a column-one banner' "$W/P.fmt" || { echo "fmt: banner lost column 1"; exit 1; }
grep -q 'x : I64 ;  (\* trailing stays on its line \*)' "$W/P.fmt" || \
  { echo "fmt: trailing comment left its line:"; cat "$W/P.fmt"; exit 1; }
grep -q '^  (\* an indented comment' "$W/P.fmt" || { echo "fmt: owned comment lost its indent"; exit 1; }
[ "$(grep -c '^$' "$W/P.fmt")" -lt "$(grep -c '^$' "$W/P.m9")" ] || \
  { echo "fmt: a run of blanks did not collapse"; exit 1; }
echo "         banners, owners, trailers and blank runs behave"

cat > "$W/Bad.m9" <<'B'
MODULE Bad ;
BEGIN
  IF > 2 THEN END
END Bad.
B
if "$FMT" "$W/Bad.m9" > /dev/null 2>"$W/bad.err"; then
  echo "fmt: formatted a file that does not parse"; exit 1
fi
grep -q ':3:.*parse:' "$W/bad.err" || { echo "fmt: refusal without position:"; cat "$W/bad.err"; exit 1; }
echo "         what does not parse is not formatted, with the position"

if "$FMT" --check "$W/P.m9" 2>/dev/null; then
  echo "fmt: --check called a hand file formatted"; exit 1
fi
"$FMT" --check "$W/P.fmt" || { echo "fmt: --check rejects its own output"; exit 1; }
cp "$W/P.m9" "$W/Q.m9"
"$FMT" -w "$W/Q.m9"
cmp -s "$W/Q.m9" "$W/P.fmt" || { echo "fmt: -w wrote something else"; exit 1; }
"$FMT" --check "$W/Q.m9" || { echo "fmt: -w result fails --check"; exit 1; }
echo "fmt: canonical layout, comments kept, over $files files"
