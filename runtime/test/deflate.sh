#!/bin/sh
# Zip.Deflate, Compress and Gzip against somebody else's inflate.
#
# A compressor's output is not unique, so there is no golden file to
# hold it to: it is right when zlib reads back what went in.  Python
# writes the inputs (deflatecheck.py make), the M9 program deflateout
# compresses each three ways, and Python's gzip and zlib read them
# (deflatecheck.py check).  corpus/ZipTest.m9 holds the same through
# Zip's own Gunzip; this is the outside witness.
set -e
cd "$(dirname "$0")"

REPO=$(cd ../.. && pwd)
M9C=${M9C:-$REPO/runtime/test/m9c}
[ -x "$M9C" ] || M9C=$REPO/out/m9c
[ -x "$M9C" ] || { echo "no m9c: run runtime/test/m9c.sh or ./build.sh"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: deflate (no python3)"; exit 0; }

OUT=/tmp/m9deflate
rm -rf "$OUT"; mkdir -p "$OUT/data"
cp deflateout.m9 "$OUT/"
export M9RUNTIME="$REPO/runtime"
export M9LIBRARY="$REPO/corpus"
( cd "$OUT" && "$M9C" --make -o deflateout deflateout.m9 >/dev/null 2>&1 ) \
  || { echo "FAIL: deflateout does not build"; exit 1; }

python3 deflatecheck.py make "$OUT/data"
for f in "$OUT"/data/*.in; do
  "$OUT/deflateout" "$f" "${f%.in}" > /dev/null \
    || { echo "FAIL: deflateout $(basename "$f")"; exit 1; }
done
python3 deflatecheck.py check "$OUT/data"

# ---- and a picture: Png.Encode, read by a PNG reader that is not ours
cp pngout.m9 "$OUT/"
( cd "$OUT" && "$M9C" --make -o pngout pngout.m9 >/dev/null 2>&1 ) \
  || { echo "FAIL: pngout does not build"; exit 1; }
mkdir -p "$OUT/png"
"$OUT/pngout" "$OUT/png" || { echo "FAIL: pngout"; exit 1; }
python3 deflatecheck.py png "$OUT/png"

# ---- and the rasteriser: Plot's figures as Png.FromSvg draws them,
# against headless Chrome's renders of the same SVG, checked in under
# gold/png/ (Chrome is not on the runner; the pictures are)
cp svg2png.m9 "$OUT/"
( cd "$OUT" && "$M9C" --make -o svg2png svg2png.m9 >/dev/null 2>&1 ) \
  || { echo "FAIL: svg2png does not build"; exit 1; }
mkdir -p "$OUT/svg"
"$OUT/svg2png" gold/taylor/annual.svg "$OUT/svg/annual.png" 72 \
  || { echo "FAIL: svg2png on the Taylor diagram"; exit 1; }
"$OUT/svg2png" gold/taylor/annual.svg "$OUT/svg/annual144.png" 144 \
  || { echo "FAIL: svg2png at 144 dpi"; exit 1; }
"$OUT/svg2png" "$REPO/reference/m2-stack/co2_columns.svg" "$OUT/svg/columns.png" 72 \
  || { echo "FAIL: svg2png on the column lines"; exit 1; }
"$OUT/svg2png" "$REPO/reference/m2-stack/co2_anomaly.svg" "$OUT/svg/anomaly.png" 72 \
  || { echo "FAIL: svg2png on the heat map"; exit 1; }
python3 deflatecheck.py svg "$OUT/svg" gold/png
