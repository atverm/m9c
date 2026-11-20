#!/bin/sh
# frontgold holds the M9 lexer, parser and printer to a record
# (docs/fpc-removal-plan.md, step 2).
#
# The record is frontgold/: for every file of a FIXED set, its token
# dump (.lex), its printed tree (.tree) and its comments (.com); for
# every file of parseprobes/, what the compiler says (.err).  The fixed
# set is museum/, frontfix/ (one fixture per part of the grammar) and
# frontfix/snap/ (two compiler modules as they were on 2026-11-15).
# These files do not change, so the record does not either.  A change
# to the front end that moves a record shows as a diff in frontgold/,
# and a person reads it.
#
# The record was taken from the Pascal lexer and parser on 2026-11-15,
# with this script's `--record-pascal', and the M9 side agreed with it
# byte for byte that day.  A fixture the Pascal side cannot read is
# named in M9ONLY below; its record is the M9 side's own, read once.
#
#   frontgold.sh                  compare the M9 side with the record
#   frontgold.sh --record         write the record from the M9 side
#   frontgold.sh --record-pascal  write it from host/fpc (needs fpc)
#
# Scratch files go in a directory of this run's own.
TG=$(mktemp -d "${TMPDIR:-/tmp}/m9gate.XXXXXX")
trap 'rm -rf "$TG"' EXIT
set -e
cd "$(dirname "$0")"
MODE=compare
case "$1" in
  --record)        MODE=record ;;
  --record-pascal) MODE=pascal ;;
  "") ;;
  *) echo "usage: frontgold.sh [--record | --record-pascal]"; exit 2 ;;
esac
. ./lib/gen.sh          # runtime/gen is BUILT here, not found
CF="-std=c11 -Wall -Wextra -Werror -Wno-unused-label -Wno-unused-parameter -iquote .. -iquote ../gen"
gcc $CF ../m9rt.c ../gen/DynStr.c ../gen/Text.c ../gen/Lex.c lexdump_m9.c -o "$TG/lexdump"
gcc $CF ../m9rt.c ../gen/DynStr.c ../gen/Text.c ../gen/Lex.c comdump_m9.c -o "$TG/comdump"
gcc $CF ../m9rt.c ../gen/DynStr.c ../gen/Text.c ../gen/Lex.c ../gen/Ast.c \
    ../gen/DynUtf.c ../gen/Print.c ../gen/Parse.c parsedump_m9.c -o "$TG/parsedump"
gcc $CF -Wno-unused-function ../m9rt.c $COMPILERC -o "$TG/m9c"
M9C="$TG/m9c"
LEXD="$TG/lexdump"; COMD="$TG/comdump"; PARD="$TG/parsedump"; P1=
if [ $MODE = pascal ]; then
  command -v fpc >/dev/null || { echo "frontgold: --record-pascal needs fpc"; exit 1; }
  ( cd ../../host/fpc && fpc -O2 lexdump.pas >/dev/null && fpc -O2 comdump.pas >/dev/null &&
    fpc -O2 parsedump.pas >/dev/null && fpc -O2 p1.pas >/dev/null )
  LEXD=../../host/fpc/lexdump; COMD=../../host/fpc/comdump; PARD=../../host/fpc/parsedump
  P1=host/fpc/p1
fi
# The Pascal side cannot read these.  Their record is the M9 side's.
M9ONLY="FxClaim FxArgs FxInterp"
G=frontgold
mkdir -p $G

# one FILE NAME: the three dumps of FILE, held to or written as NAME.*
one () {
  f=$1; n=$2
  ld=$LEXD; cd_=$COMD; pd=$PARD
  if [ $MODE = pascal ]; then
    case " $M9ONLY " in *" $n "*) ld="$TG/lexdump"; cd_="$TG/comdump"; pd="$TG/parsedump" ;; esac
  fi
  "$ld" "$f" > "$TG/o.lex" || { echo "frontgold: $f does not lex"; exit 1; }
  "$pd" "$f" > "$TG/o.tree" || { echo "frontgold: $f does not parse clean"; exit 1; }
  "$cd_" "$f" > "$TG/o.com"
  for k in lex tree com; do
    if [ $MODE = compare ]; then
      [ -f "$G/$n.$k" ] || { echo "frontgold: no record $G/$n.$k (frontgold.sh --record writes one)"; exit 1; }
      cmp -s "$TG/o.$k" "$G/$n.$k" ||
        { echo "frontgold: $f differs from its record $G/$n.$k:"; diff "$G/$n.$k" "$TG/o.$k" | head -8; exit 1; }
    else
      cp "$TG/o.$k" "$G/$n.$k"
    fi
  done
  nf=$((nf+1))
}

nf=0
for f in ../../museum/*.m9; do one "$f" "museum-$(basename "$f" .m9)"; done
for f in frontfix/*.m9; do one "$f" "$(basename "$f" .m9)"; done
for f in frontfix/snap/*.m9; do one "$f" "snap-$(basename "$f" .m9)"; done

# The broken files: what the compiler says, line, column and text.
np=0
for f in ../../parseprobes/*.m9; do
  n="probe-$(basename "$f" .m9)"
  if [ -n "$P1" ]; then
    ( cd ../.. && $P1 "${f#../../}" ) > "$TG/o.err" 2>&1 || true
  else
    ( cd ../.. && M9LIBRARY=$(pwd)/corpus M9RUNTIME=$(pwd)/runtime \
        "$M9C" -c "${f#../../}" ) > "$TG/o.err" 2>&1 || true
  fi
  # A probe that stopped being broken proves nothing.
  grep -q ': parse: ' "$TG/o.err" ||
    { echo "frontgold: $f no longer has a parse error"; exit 1; }
  if [ $MODE = compare ]; then
    [ -f "$G/$n.err" ] || { echo "frontgold: no record $G/$n.err"; exit 1; }
    cmp -s "$TG/o.err" "$G/$n.err" ||
      { echo "frontgold: $f is answered differently from its record:"; diff "$G/$n.err" "$TG/o.err" | head -6; exit 1; }
  else
    cp "$TG/o.err" "$G/$n.err"
  fi
  np=$((np+1))
done

# A record with no file behind it is a fixture that was removed.
if [ $MODE = compare ]; then
  have=$(ls $G | wc -l | tr -d ' ')
  [ "$have" = $((nf * 3 + np)) ] ||
    { echo "frontgold: $G holds $have records, the fixed set makes $((nf * 3 + np))"; exit 1; }
  echo "frontgold: $nf files and $np broken ones, tokens, trees, comments and messages as recorded"
else
  echo "frontgold: recorded $nf files and $np broken ones from the $([ $MODE = pascal ] && echo Pascal || echo M9) side"
fi
