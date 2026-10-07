#!/bin/sh
# xml -- Xml held to the W3C XML conformance suite (docs/datalib-plan.md
# par 4): every not-well-formed document refused, every well-formed one
# read the way expat (libxml2 for the fifth edition's names) reads it or
# refused by name -- XmlTest, against tools/xmlgold.py's golden.
#
# The suite is NOT in this repository: Sun's part is "All Rights
# Reserved" and James Clark's may be passed on only as his unmodified
# zip.  This gate fetches the W3C's archive once into a cache
# ($M9_CACHE, else ~/.cache/m9), holds it to its SHA-256, unpacks it in
# runtime/test/xmlconf (gitignored) and runs XmlTest there.  Without
# the network it SKIPS out loud on a workstation and FAILS on CI.  Uses
# the m9c that m9c.sh builds, or $M9C, or out/m9c.
set -e
cd "$(dirname "$0")"

M9C=${M9C:-}
[ -n "$M9C" ] || { [ -x ./m9c ] && M9C=$(pwd)/m9c; }
[ -n "$M9C" ] || { [ -x ../../out/m9c ] && M9C=$(cd ../../out && pwd)/m9c; }
[ -n "$M9C" ] || { echo "xml: no m9c (run m9c.sh or build.sh)"; exit 1; }

URL=https://www.w3.org/XML/Test/xmlts20130923.tar.gz
SHA=9b61db9f5dbffa545f4b8d78422167083a8568c59bd1129f94138f936cf6fc1f
CACHE=${M9_CACHE:-$HOME/.cache/m9}
TAR=$CACHE/xmlts20130923.tar.gz
mkdir -p "$CACHE"

sha () { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -c1-64; else shasum -a 256 "$1" | cut -c1-64; fi; }

if [ ! -f "$TAR" ] || [ "$(sha "$TAR")" != "$SHA" ]; then
  rm -f "$TAR"
  if ! curl -sSfL --max-time 120 -o "$TAR.part" "$URL"; then
    rm -f "$TAR.part"
    if [ -n "$GITHUB_ACTIONS" ]; then echo "xml: FAIL -- cannot fetch $URL"; exit 1; fi
    echo "xml: SKIP -- cannot fetch $URL (no network?)"
    exit 0
  fi
  mv "$TAR.part" "$TAR"
fi
got=$(sha "$TAR")
[ "$got" = "$SHA" ] || { echo "xml: FAIL -- $TAR is $got, not $SHA"; exit 1; }

rm -rf xmlconf
mkdir xmlconf
tar xzf "$TAR" -C xmlconf

W=/tmp/m9-xml
rm -rf "$W"; mkdir -p "$W"
RT=$(cd .. && pwd)
LIB=$(cd ../../corpus && pwd)
ROOT=$(cd ../.. && pwd)
( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$LIB" "$M9C" --make -o xmltest "$LIB/XmlTest.m9" ) \
  > "$W/build.log" 2>&1 || { cat "$W/build.log"; echo "xml: FAIL -- XmlTest does not build"; exit 1; }

st=0
( cd "$ROOT" && M9_XMLCONF="$ROOT/runtime/test/xmlconf/xmlconf" "$W/xmltest" ) > "$W/out" 2>&1 || st=$?
tail -20 "$W/out"
[ $st -eq 0 ] || { echo "xml: FAIL -- XmlTest exit $st"; exit 1; }
grep -q '^XmlTest: 951 not-well-formed' "$W/out" || { echo "xml: FAIL -- the suite was not read"; exit 1; }
echo "xml: PASS"
