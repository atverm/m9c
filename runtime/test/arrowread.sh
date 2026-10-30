#!/bin/sh
# arrowread -- Arrow.m9's stream READER against pyarrow (2026-10-30;
# zarrm9's mcpd reads zpd's `format=arrow' answers).  arrowread/
# ArrowRead.m9 prints what the reader finds in a stream -- the fields,
# metadata, every batch's null counts and every cell -- and that text
# must be what pyarrow reads from the same bytes (arrowread.py).
#
# Two halves, as for the other columnar formats: the streams pyarrow
# 26.0.0 wrote and its text for each are CHECKED IN (arrowread/gold/:
# every type and width extreme, nulls and NaN over two batches, a time
# zone, ZSTD, an empty batch, and three refusals by name -- an unsigned
# column, a dictionary column, LZ4), so the gate holds the reader on
# a machine without pyarrow, CI's included; where pyarrow is
# ($COLUMNAR_PY, else python3), it writes the streams afresh and the
# reader is held to those too, so a newer pyarrow's bytes are read.
cd "$(dirname "$0")" || exit 1
. ./lib/freshm9c.sh                      # M9C, built from runtime/gen

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
RT=$(cd .. && pwd)
LIB=$(cd ../../corpus && pwd)
cp arrowread/ArrowRead.m9 "$W/"
( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$LIB" "$M9C" --make -o ArrowRead ArrowRead.m9 ) \
  > "$W/build.log" 2>&1 || { echo "arrowread: FAIL building ArrowRead"; tail -5 "$W/build.log"; exit 1; }

n=0 ; fail=0
judge () {                                # judge DIR LABEL
  for f in "$1"/*.arrows; do
    b=$(basename "$f" .arrows)
    n=$((n + 1))
    "$W/ArrowRead" "$f" > "$W/got" 2>&1
    if cmp -s "$W/got" "$1/$b.want"; then
      echo "  ok   $2 $b"
    else
      fail=$((fail + 1))
      echo "  FAIL $2 $b"
      diff "$1/$b.want" "$W/got" | head -6 | sed 's/^/        /'
    fi
  done
}

judge arrowread/gold "checked-in"

PY=${COLUMNAR_PY:-python3}
if "$PY" -c 'import pyarrow' > /dev/null 2>&1; then
  "$PY" arrowread.py "$W/fresh" || { echo "arrowread: FAIL writing the fresh streams"; exit 1; }
  judge "$W/fresh" "fresh"
else
  echo "SKIP: pyarrow not installed (the fresh streams half)"
fi

echo "arrowread: $n streams, $fail failed"
[ "$fail" = 0 ]
