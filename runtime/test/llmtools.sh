#!/bin/sh
# llmtools holds tools/M9Tools.m9, which makes a module's procedures
# into tools for a chat model (docs/ml-plan.md, stage A2).
#   1. m9c --json and M9Tools make CalcTools from toolsfix/Calc.m9.
#      It must be toolsfix/CalcTools.m9, the reviewed output, byte for
#      byte.  After a change to the generator: read the diff, then copy
#      the new output over it.
#   2. ToolsTest runs CalcTools on twenty calls, right ones and ones
#      each reader must refuse.  The answers must be toolsfix/tools.want.
#   3. toolsfix/judge.py reads the schemas from the request Offer makes,
#      with a schema check written in Python.  Run must refuse exactly
#      the calls the schemas refuse.
#   4. The same for answers (stage A3): ObsTools from toolsfix/Obs.m9
#      must be toolsfix/ObsTools.m9.  AnswersTest reads fourteen texts
#      into Obs's records, and the answers must be toolsfix/answers.want.
#      The judge holds each text to the schema the chat asked with:
#      a text is read exactly when it fits.
# The gate needs Python 3, nothing else.
set -e
cd "$(dirname "$0")"

. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C

PY=${LLMTOOLS_PY:-python3}
W=${LLMTOOLS_W:-/tmp/m9-llmtools}
rm -rf "$W"; mkdir -p "$W"
RT=$(cd .. && pwd)
LIB=$(cd ../../corpus && pwd)
FIX=$(cd toolsfix && pwd)
GEN=$(cd ../../tools && pwd)/M9Tools.m9
cp "$FIX/Calc.m9" "$FIX/ToolsTest.m9" "$FIX/Obs.m9" "$FIX/AnswersTest.m9" "$W/"
(
  cd "$W"
  export M9RUNTIME="$RT" M9LIBRARY="$LIB"
  "$M9C" --json Calc.m9 &&
    "$M9C" --make -o m9tools "$GEN" &&
    ./m9tools Calc.json CalcTools.m9 2> left.txt &&
    "$M9C" --make -I . -o toolstest ToolsTest.m9 &&
    "$M9C" --json Obs.m9 &&
    ./m9tools Obs.json ObsTools.m9 2> left-obs.txt &&
    "$M9C" --make -I . -o answerstest AnswersTest.m9
) > "$W/build.log" 2>&1 || { cat "$W/build.log"; echo "llmtools: FAIL -- the build"; exit 1; }

cmp -s "$FIX/CalcTools.m9" "$W/CalcTools.m9" ||
  { diff "$FIX/CalcTools.m9" "$W/CalcTools.m9" | head -30
    echo "llmtools: FAIL -- M9Tools wrote another CalcTools (read the diff; if it is right, copy $W/CalcTools.m9 to toolsfix/)"; exit 1; }
printf 'M9Tools: left out Fill: a VAR parameter\nM9Tools: left out Sum: a parameter of type SLICE OF I64\n' > "$W/left.want"
diff "$W/left.want" "$W/left.txt" || { echo "llmtools: FAIL -- what M9Tools left out"; exit 1; }

"$W/toolstest" > "$W/out.txt" 2>&1 || { cat "$W/out.txt"; echo "llmtools: FAIL -- ToolsTest exit"; exit 1; }
grep -v '^BODY ' "$W/out.txt" > "$W/calls.txt"
diff "$FIX/tools.want" "$W/calls.txt" || { echo "llmtools: FAIL -- the answers"; exit 1; }
"$PY" "$FIX/judge.py" "$W/out.txt" || { echo "llmtools: FAIL -- the judge"; exit 1; }

cmp -s "$FIX/ObsTools.m9" "$W/ObsTools.m9" ||
  { diff "$FIX/ObsTools.m9" "$W/ObsTools.m9" | head -30
    echo "llmtools: FAIL -- M9Tools wrote another ObsTools (read the diff; if it is right, copy $W/ObsTools.m9 to toolsfix/)"; exit 1; }
"$W/answerstest" > "$W/answers.txt" 2>&1 || { cat "$W/answers.txt"; echo "llmtools: FAIL -- AnswersTest exit"; exit 1; }
grep -v '^BODY ' "$W/answers.txt" > "$W/answers.got"
diff "$FIX/answers.want" "$W/answers.got" || { echo "llmtools: FAIL -- the answers read"; exit 1; }
"$PY" "$FIX/judge.py" answers "$W/answers.txt" || { echo "llmtools: FAIL -- the answers judge"; exit 1; }
echo "llmtools: PASS ($(wc -l < "$W/calls.txt" | tr -d ' ') calls, $(wc -l < "$W/answers.got" | tr -d ' ') answers, CalcTools and ObsTools as reviewed)"
