#!/bin/sh
# sparql -- Sparql against a live endpoint: rdflib serving the test graph
# (runtime/test/sparqlfix.py), the same queries SparqlTest reads offline
# in m9test, now through Select, Ask and Construct over HTTP, one of them
# long enough to go by POST -- and the endpoint's own count must say a
# POST arrived (docs/datalib-plan.md par 2).
#
# Needs rdflib (python3-rdflib; SPARQL_PY names another Python).  Without
# it the gate SKIPS out loud on a workstation and FAILS on CI.  Uses the
# m9c that m9c.sh builds, or $M9C, or out/m9c.
set -e
cd "$(dirname "$0")"

M9C=${M9C:-}
[ -n "$M9C" ] || { [ -x ./m9c ] && M9C=$(pwd)/m9c; }
[ -n "$M9C" ] || { [ -x ../../out/m9c ] && M9C=$(cd ../../out && pwd)/m9c; }
[ -n "$M9C" ] || { echo "sparql: no m9c (run m9c.sh or build.sh)"; exit 1; }

PY=${SPARQL_PY:-python3}
if ! "$PY" -c 'import rdflib' 2>/dev/null; then
  if [ -n "$GITHUB_ACTIONS" ]; then
    echo "sparql: FAIL -- $PY has no rdflib (python3-rdflib)"; exit 1
  fi
  echo "sparql: SKIP -- $PY has no rdflib (install python3-rdflib, or set SPARQL_PY)"
  exit 0
fi

W=/tmp/m9-sparql
rm -rf "$W"; mkdir -p "$W"
RT=$(cd .. && pwd)
LIB=$(cd ../../corpus && pwd)
ROOT=$(cd ../.. && pwd)
( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$LIB" "$M9C" --make -o sparqltest "$LIB/SparqlTest.m9" ) \
  > "$W/build.log" 2>&1 || { cat "$W/build.log"; echo "sparql: FAIL -- SparqlTest does not build"; exit 1; }

PORT=${SPARQL_PORT:-18390}
"$PY" sparqlfix.py "$PORT" > "$W/fix.log" 2>&1 &
FIX=$!
trap 'kill $FIX 2>/dev/null' EXIT
i=0
until curl -s -o /dev/null "http://127.0.0.1:$PORT/stats"; do
  i=$((i+1)); [ $i -lt 100 ] || { cat "$W/fix.log"; echo "sparql: FAIL -- the endpoint did not start"; exit 1; }
  sleep 0.1
done

st=0
( cd "$ROOT" && SPARQL_ENDPOINT="http://127.0.0.1:$PORT/sparql" "$W/sparqltest" ) > "$W/out" 2>&1 || st=$?
cat "$W/out" | grep -v '^SparqlTest: offline only' | tail -20
[ $st -eq 0 ] || { echo "sparql: FAIL -- SparqlTest exit $st"; exit 1; }
stats=$(curl -s "http://127.0.0.1:$PORT/stats")
echo "sparql: the endpoint saw $stats"
case "$stats" in
  "GET 0 "*) echo "sparql: FAIL -- no query came by GET"; exit 1 ;;
esac
case "$stats" in
  *"POST 0"*) echo "sparql: FAIL -- the long query did not come by POST"; exit 1 ;;
esac
echo "sparql: PASS"
