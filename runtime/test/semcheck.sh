#!/bin/sh
# semcheck holds the M9 checker to the rules the Pascal twin's harnesses
# held, now that the twin is frozen (Alex, 2026-10-31, before m9's
# UTF-8 switch).  It reads the M9 checker WHOLE, the region judgement
# included, through semdump_m9 --all.
#
# The rules are semtest's and semprobe's:
#   1. every corpus/ and bench/ file checks with ZERO diagnostics;
#   2. every museum/ file is refused, and a diagnostic holds its
#      (* EXPECT-ERROR: ... *) text;
#   3. every probe gives the diagnostic its first line names, an
#      (* EXPECT: ... *) among the errors or a (* LEDGER: ... *) in the
#      par 4.1 ledger.  A probe writes its legal forms first, so for an
#      EXPECT nothing may be refused on an earlier line.  An earlier
#      diagnostic is a legal form refused;
#   4. ownledger's kill-gate: the procedures of corpus/ with a par 4.1
#      retention in the ledger stay under 20% of those with a body.
#      Over it, par 4.1 must be revised (region annotations), by the
#      pre-registered rule, so the gate fails.
# Every corpus module is loaded before a file is checked, as semtest
# did: a name not loaded cannot be told from a name that does not
# exist.  A probe is checked alone, as semprobe did, with its own units.
#
# Moving the probes onto the whole checker found one false refusal the
# twins' comparison had filtered out: the owner walk joined a loop
# body's end back into the next turn even when the body always EXITs
# (probe use-after-move-loop's legal form, Sem.OlLoop).
set -e
cd "$(dirname "$0")"
. ./lib/gen.sh          # runtime/gen is BUILT here, not found

gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c \
    ../gen/Text.c ../gen/Lex.c ../gen/Ast.c ../gen/DynUtf.c ../gen/Print.c \
    ../gen/Parse.c ../gen/Sem.c semdump_m9.c -lm -o semdump_m9

M9=$(pwd)/semdump_m9
DEPS=""
for d in ../../corpus/*.m9; do DEPS="$DEPS ../..${d#../..}"; done

# The checker runs in parallel, one process per file per core, into a
# directory of this run's own.  The judging below is serial and in file
# order.  M9_JOBS sets the count.
W=$(mktemp -d "${TMPDIR:-/tmp}/m9semcheck.XXXXXX")
trap 'rm -rf "$W"' EXIT
J=${M9_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
i=0
: > "$W/list"
for f in ../../corpus/*.m9 ../../bench/*.m9; do
  i=$((i+1)); printf '%s corpus %s\n' "$i" "$f" >> "$W/list"
done
for f in ../../museum/*.m9; do
  i=$((i+1)); printf '%s museum %s\n' "$i" "$f" >> "$W/list"
done
for f in ../../probes/*.m9; do
  i=$((i+1)); printf '%s probe %s\n' "$i" "$f" >> "$W/list"
done
export DEPS M9 W
xargs -P "$J" -L 1 sh -c '
  if [ "$1" = probe ]; then
    "$M9" --all "$2" > "$W/$0.out" 2> "$W/$0.err"
  else
    "$M9" --all "$2" $DEPS > "$W/$0.out" 2> "$W/$0.err"
  fi
  echo $? > "$W/$0.st"' < "$W/list"

# diag FILE answers the diagnostics of a run, one a line, the ledger's
# lines left out.  A diagnostic starts with LINE:COL; a line that does
# not is the continuation of the one before.
diag () { grep -E '^[0-9]+:[0-9]+ ' "$1" || :; }
ledger () { sed -n 's/^ledger: //p' "$1" | grep -E '^[0-9]+:[0-9]+ ' || :; }

bad=0; nc=0; nm=0; np=0; nb=0
: > "$W/ctxs"
while read -r n kind f; do
  b=$(basename "$f" .m9)
  if [ "$(cat "$W/$n.st")" != 0 ] || [ -s "$W/$n.err" ]; then
    echo "semcheck: the checker FAILED on $b (exit $(cat "$W/$n.st")):"
    head -3 "$W/$n.err" | sed 's/^/    /'
    bad=$((bad+1)); continue
  fi
  case $kind in
  corpus)
    nc=$((nc+1))
    # The kill-gate counts corpus/, not bench/: a retention's
    # procedure is its ctx, the field before ': retention: '.
    case $f in
    */corpus/*)
      nb=$((nb + $(sed -n 's/^bodies: //p' "$W/$n.out")))
      ledger "$W/$n.out" | grep -F ': retention: ' |
        sed 's/^[0-9]*:[0-9]* \([^:]*\): retention: .*/\1/' >> "$W/ctxs" ;;
    esac
    if [ -n "$(diag "$W/$n.out")" ]; then
      echo "semcheck: $b is not clean:"
      diag "$W/$n.out" | head -3 | sed 's/^/    /'
      bad=$((bad+1))
    fi ;;
  museum)
    nm=$((nm+1))
    want=$(sed -n 's/.*EXPECT-ERROR:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*\*).*/\1/p' "$f" | head -1)
    if [ -z "$(diag "$W/$n.out")" ]; then
      echo "semcheck: museum piece $b is ACCEPTED"; bad=$((bad+1))
    elif ! diag "$W/$n.out" | grep -qF -- "$want"; then
      echo "semcheck: museum piece $b is refused with the wrong message (want: $want):"
      diag "$W/$n.out" | head -3 | sed 's/^/    /'
      bad=$((bad+1))
    fi ;;
  probe)
    np=$((np+1))
    first=$(head -1 "$f")
    pk=$(printf '%s\n' "$first" | sed -n 's/^(\*[[:space:]]*\([A-Z]*\):.*/\1/p')
    want=$(printf '%s\n' "$first" | sed -n 's/^(\*[[:space:]]*[A-Z]*:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*\*)[[:space:]]*$/\1/p')
    if [ -z "$pk" ] || [ -z "$want" ]; then
      echo "semcheck: probe $b has NO EXPECTATION on its first line"; bad=$((bad+1)); continue
    fi
    if [ "$pk" = LEDGER ]; then ledger "$W/$n.out" > "$W/$n.d"; else diag "$W/$n.out" > "$W/$n.d"; fi
    hit=$(grep -F -- "$want" "$W/$n.d" | cut -d: -f1 | sort -n | head -1)
    low=$(cut -d: -f1 "$W/$n.d" | sort -n | head -1)
    if [ -z "$hit" ]; then
      echo "semcheck: probe $b DID NOT FIRE (expected \"$want\"):"
      head -3 "$W/$n.d" | sed 's/^/    got: /'
      bad=$((bad+1))
    elif [ "$pk" = EXPECT ] && [ "$low" -lt "$hit" ]; then
      echo "semcheck: probe $b REFUSED A LEGAL FORM before the expected refusal:"
      grep -E "^$low:" "$W/$n.d" | head -1 | sed 's/^/    /'
      bad=$((bad+1))
    fi ;;
  esac
done < "$W/list"

nl=$(sort -u "$W/ctxs" | grep -c . || :)
rate=$(awk -v a="$nl" -v b="$nb" 'BEGIN { if (b > 0) printf "%.1f", 100 * a / b; else print "100.0" }')
over=$(awk -v r="$rate" 'BEGIN { print (r > 20.0) ? 1 : 0 }')
echo "semcheck: contortion rate $rate% ($nl of $nb procedures with a body; kill-gate 20%)"
if [ "$over" = 1 ]; then
  echo "semcheck: OVER THE KILL-GATE -- par 4.1 must be revised (region annotations), per the pre-registered rule"
  bad=$((bad+1))
fi
if [ "$bad" -ne 0 ]; then
  echo "semcheck: $bad FAIL"
  exit 1
fi
echo "semcheck: $nc corpus and bench files clean, $nm museum pieces refused as meant, $np probes fire"
