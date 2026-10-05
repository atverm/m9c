#!/bin/sh
# guiexample -- examples/gui/GuiMean.m9 is still a program this tree's
# compiler accepts, and its build scripts still parse.
#
# The example itself needs libui-ng and a display, which CI has neither
# of; it was run by hand on macOS, on Linux under Xvfb and under wine
# (examples/gui/README.md says how).  What a gate CAN hold is the M9
# side: a change to the language or the library that would break the
# example breaks here first, by name and line.
set -e
cd "$(dirname "$0")"

M9C=${M9C:-}
[ -n "$M9C" ] || { [ -x ./m9c ] && M9C=$(pwd)/m9c; }
[ -n "$M9C" ] || { [ -x ../../out/m9c ] && M9C=$(cd ../../out && pwd)/m9c; }
[ -n "$M9C" ] || { echo "guiexample: no m9c (run m9c.sh or build.sh)"; exit 1; }

EX=../../examples/gui
[ -f "$EX/GuiMean.m9" ] || { echo "guiexample: SKIP -- no examples/gui in this tree"; exit 0; }
M9RUNTIME=$(cd .. && pwd) M9LIBRARY=$(cd ../../corpus && pwd) \
  "$M9C" --check "$EX/GuiMean.m9" ||
  { echo "guiexample: FAIL: examples/gui/GuiMean.m9 no longer checks"; exit 1; }
for s in build.sh build-windows.sh; do
  sh -n "$EX/$s" || { echo "guiexample: FAIL: $s does not parse"; exit 1; }
done
echo "guiexample: GuiMean.m9 checks, and its two build scripts parse"
