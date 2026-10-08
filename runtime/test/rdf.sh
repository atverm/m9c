#!/bin/sh
# rdf -- Rdf held to rdflib over the W3C RDF 1.1 Turtle, N-Triples and
# RDF/XML suites and the JSON-LD API's toRdf tests (runtime/test/rdf-tests, listed in gold/Rdf.gold): every
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
# rdflib 7 or later, BY NAME: 6.1.1 (Ubuntu 24.04's python3-rdflib)
# reads `scheme:...~?#' out of JSON-LD as `...~#' and has no
# Dataset.default_graph, so under it 141 of the 745 verdicts were the
# oracle's defects (measured 2026-10-08, when CI's image carried it
# and the suite's venv carried 7.6); the CI image installs 7.6 with pip.
RV=$("$PY" -c 'import rdflib; print(rdflib.__version__)' 2>/dev/null)
case "$RV" in
  [0-6].*) if [ -n "$GITHUB_ACTIONS" ]; then
             echo "rdf: FAIL -- rdflib $RV; the judge needs 7 or later (6.1.1 misreads an IRI with ? before # in JSON-LD)"; exit 1
           fi
           echo "rdf: SKIP -- rdflib $RV; the judge needs 7 or later (set RDF_PY to a Python with rdflib>=7)"; exit 0 ;;
esac

W=/tmp/m9-rdf
rm -rf "$W"; mkdir -p "$W/out/ttl" "$W/out/nt" "$W/out/xml" "$W/out/jld/toRdf"
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

XBASE=$(list xml.base)
# the RDF/XML tests sit in subdirectories: the output tree mirrors them
for d in $(list xml.eval.action) $(list xml.neg); do mkdir -p "$W/out/xml/$(dirname "$d")"; done
# shellcheck disable=SC2046
"$W/rdfconv" xml rdf-tests/rdf-xml "$XBASE" "$W/out/xml" \
  $(list xml.eval.action) $(list xml.neg) \
  || { echo "rdf: FAIL -- RdfConv stopped on the RDF/XML suite"; exit 1; }

# JSON-LD: each test against its own base, one run a document; some
# inputs are shared with the expand suite and sit in its directory
for d in $(list jld.pos.action) $(list jld.neg) $(list jld.syntax); do mkdir -p "$W/out/jld/$(dirname "$d")"; done
i=0
for f in $(list jld.pos.action); do
  i=$((i + 1))
  b=$(list jld.pos.base | tr ' ' '\n' | sed -n "${i}p")
  "$W/rdfconv" jld jsonld-tests "$b" "$W/out/jld" "$f" \
    || { echo "rdf: FAIL -- RdfConv stopped on $f"; exit 1; }
done
for f in $(list jld.neg) $(list jld.syntax); do
  "$W/rdfconv" jld jsonld-tests "https://w3c.github.io/json-ld-api/tests/$f" "$W/out/jld" "$f" \
    || { echo "rdf: FAIL -- RdfConv stopped on $f"; exit 1; }
done

"$PY" rdfjudge.py "$GOLD" rdf-tests "$W/out" || { echo "rdf: FAIL"; exit 1; }
echo "rdf: PASS"
