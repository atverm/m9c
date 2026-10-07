#!/bin/sh
# rdf -- Rdf held to rdflib over the W3C RDF 1.1 Turtle and N-Triples
# suites (runtime/test/rdf-tests, listed in gold/Rdf.gold): every
# document read by M9 and written back as N-Triples by rdffix/RdfConv,
# then judged by runtime/test/rdfjudge.py -- the expected graph, up to
# blank-node renaming, for every evaluation and positive syntax test;
# a refusal for every negative one (docs/datalib-plan.md par 2).
# RdfTest in m9test reads the same suites offline; this is the half
# that needs graphs compared, which is left to code M9 did not write.
#
# Needs rdflib (python3-rdflib; RDF_PY names another Python).  Without
# it the gate SKIPS out loud on a workstation and FAILS on CI.  Uses the
# m9c that m9c.sh builds, or $M9C, or out/m9c.
set -e
cd "$(dirname "$0")"

M9C=${M9C:-}
[ -n "$M9C" ] || { [ -x ./m9c ] && M9C=$(pwd)/m9c; }
[ -n "$M9C" ] || { [ -x ../../out/m9c ] && M9C=$(cd ../../out && pwd)/m9c; }
[ -n "$M9C" ] || { echo "rdf: no m9c (run m9c.sh or build.sh)"; exit 1; }

PY=${RDF_PY:-python3}
if ! "$PY" -c 'import rdflib' 2>/dev/null; then
  if [ -n "$GITHUB_ACTIONS" ]; then
    echo "rdf: FAIL -- $PY has no rdflib (python3-rdflib)"; exit 1
  fi
  echo "rdf: SKIP -- $PY has no rdflib (install python3-rdflib, or set RDF_PY)"
  exit 0
fi

W=/tmp/m9-rdf
rm -rf "$W"; mkdir -p "$W/out/ttl" "$W/out/nt"
RT=$(cd .. && pwd)
LIB=$(cd ../../corpus && pwd)
HERE=$(pwd)
( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$LIB" "$M9C" --make -o rdfconv "$HERE/rdffix/RdfConv.m9" ) \
  > "$W/build.log" 2>&1 || { cat "$W/build.log"; echo "rdf: FAIL -- RdfConv does not build"; exit 1; }

GOLD=gold/Rdf.gold
list () { sed -n "s/^$1 str [0-9]* //p" "$GOLD"; }
BASE=$(list ttl.base)
[ -n "$BASE" ] || { echo "rdf: FAIL -- $GOLD names no base"; exit 1; }
# shellcheck disable=SC2046
"$W/rdfconv" ttl rdf-tests/rdf-turtle "$BASE" "$W/out/ttl" \
  $(list ttl.eval.action) $(list ttl.pos) $(list ttl.neg) \
  || { echo "rdf: FAIL -- RdfConv stopped on the Turtle suite"; exit 1; }
# shellcheck disable=SC2046
"$W/rdfconv" nt rdf-tests/rdf-n-triples '' "$W/out/nt" \
  $(list nt.pos) $(list nt.neg) \
  || { echo "rdf: FAIL -- RdfConv stopped on the N-Triples suite"; exit 1; }

"$PY" rdfjudge.py "$GOLD" rdf-tests "$W/out" || { echo "rdf: FAIL"; exit 1; }
echo "rdf: PASS"
