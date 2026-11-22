#!/bin/sh
# llm holds Llm against a chat server it did not write
# (docs/ml-plan.md, stage A1).  runtime/test/llmfix/llmfix.py plays the
# server: it replays replies recorded from sglang serving Qwen3.8-27B,
# picked by the model name, and saves every request.  LlmTest, with
# LLM_ENDPOINT set, holds a whole conversation against it: a tool call
# and its result, a reply cut off by the token limit, an image, two
# server errors, a reply that is not JSON and one without choices.
# Then Python's json judges every request Llm sent: the messages, the
# tool calls echoed back under their ids, the escapes and the image's
# bytes.  LlmTest reads the same replies offline in m9test.
#
# The gate needs Python 3 and curl, nothing else.  No gate needs a real
# server: against one, run LlmTest by hand with LLM_ENDPOINT and
# LLM_MODEL set (docs/ml-plan.md).
set -e
cd "$(dirname "$0")"

. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C

PY=${LLMFIX_PY:-python3}
W=${LLM_W:-/tmp/m9-llm}
rm -rf "$W"; mkdir -p "$W/out"
RT=$(cd .. && pwd)
LIB=${M9LIBRARY_OVERRIDE:-$(cd ../../corpus && pwd)}   # Sabotage.m9 hands a broken copy
ROOT=$(cd ../.. && pwd)
( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$LIB" "$M9C" --make -o llmtest "$LIB/LlmTest.m9" ) \
  > "$W/build.log" 2>&1 || { cat "$W/build.log"; echo "llm: FAIL -- LlmTest does not build"; exit 1; }

PORT=${LLM_PORT:-$((20000 + $$ % 10000))}
"$PY" llmfix/llmfix.py serve "$PORT" "$W/out" > "$W/fix.log" 2>&1 &
FIX=$!
# Python's http.server exits 143 on SIGTERM.  Under set -e a failing
# wait in the EXIT trap ended the gate with that status, after its
# PASS (the first two rounds, 2026-11-21).  So the wait may fail.
trap 'kill $FIX 2>/dev/null; wait $FIX 2>/dev/null || :' EXIT
n=0
while ! grep -q serving "$W/fix.log" 2>/dev/null; do
  n=$((n + 1)); [ $n -lt 100 ] || { cat "$W/fix.log"; echo "llm: FAIL -- the fixture did not start"; exit 1; }
  sleep 0.1
done

st=0
( cd "$ROOT" && LLM_ENDPOINT="http://127.0.0.1:$PORT/v1" "$W/llmtest" ) > "$W/test.out" 2>&1 || st=$?
grep -v '^PASS' "$W/test.out" | tail -20
[ $st -eq 0 ] || { echo "llm: FAIL -- LlmTest exit $st"; exit 1; }
"$PY" llmfix/llmfix.py judge "$W/out" "$ROOT/examples/gui/screenshot-windows.png" ||
  { echo "llm: FAIL -- the judge"; exit 1; }
echo "llm: PASS ($(sed -n 's/^PASS (\([0-9]*\) checks).*/\1/p' "$W/test.out") checks, $(ls "$W/out" | grep -c '\.json$') requests judged)"
