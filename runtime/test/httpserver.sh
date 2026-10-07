#!/bin/sh
# httpserver -- HttpServer.Run, the concurrent HTTP/1.1 server, held to
# RFC 9112 by code M9 did not write (docs/httpserver-plan.md, stages
# 1 to 3), natively and, where wine is, as a Windows program.
#
# Builds runtime/test/srvfix/SrvFix.m9 (one route per behaviour) with
# this tree's compiler and runs srvfix/srvfix.py against it: raw-socket
# cases, malformed ones included, every response parsed by h11; Date
# held to its own weekday; byte-verified load on eight kept connections
# with the server's descriptors and resident memory read from /proc; a
# full queue answered 503; a connection limit that drains the server and
# prints counts that must add up; the per-connection limit.
#
# SHOWN ABLE TO FAIL by srvfix/sabotage.py: one-line breaks of
# HttpServer.m9 (and of Logger and the runtime where the property lives
# there), each of which must turn this gate red.  Not in CI (it builds
# a server for each); run it after changing either side.
#
# Needs h11 (python3-h11 on Debian and Ubuntu; SRVFIX_PY names another
# Python).  Without it the gate SKIPS out loud on a workstation and
# FAILS on CI, where the package is installed by the job.  Uses the
# m9c that m9c.sh builds, or $M9C, or out/m9c.
set -e
cd "$(dirname "$0")"

M9C=${M9C:-}
[ -n "$M9C" ] || { [ -x ./m9c ] && M9C=$(pwd)/m9c; }
[ -n "$M9C" ] || { [ -x ../../out/m9c ] && M9C=$(cd ../../out && pwd)/m9c; }
[ -n "$M9C" ] || { echo "httpserver: no m9c (run m9c.sh or build.sh)"; exit 1; }

PY=${SRVFIX_PY:-python3}
if ! "$PY" -c 'import h11' 2>/dev/null; then
  if [ -n "$GITHUB_ACTIONS" ]; then
    echo "httpserver: FAIL -- $PY has no h11 (python3-h11)"; exit 1
  fi
  echo "httpserver: SKIP -- $PY has no h11 (install python3-h11, or set SRVFIX_PY)"
  exit 0
fi

W=/tmp/m9-httpserver
rm -rf "$W"; mkdir -p "$W"
RT=$(cd .. && pwd)
LIB=$(cd ../../corpus && pwd)
SRC=$(cd srvfix && pwd)
# built in $W: --make writes each module's C and objects where it runs
( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$LIB" \
    "$M9C" --make -o srvfix "$SRC/SrvFix.m9" ) > "$W/build.log" 2>&1 ||
  { cat "$W/build.log"; echo "httpserver: FAIL -- SrvFix does not build"; exit 1; }
st=0
"$PY" srvfix/srvfix.py "$W/srvfix" || st=$?
[ $st -eq 0 ] || { echo "httpserver: FAIL"; exit 1; }

# ---- the Windows half: the same fixture against a mingw build, under
# wine (plan stage 3).  The library's C is runtime/gen, archived so the
# link takes what SrvFix uses; OpenSSL is the Windows toolchain's
# ($M9WINTOOLCHAIN, the ucrt64 tree the release's zip is made from).
# Under wine srvfix.py signals with SIGINT, which wine delivers as the
# console's Ctrl-C, and skips the one check Windows cannot pass yet --
# a UTF-8 file name, Io's Windows paths being ANSI -- saying so.
# Without wine, mingw or the toolchain this half says why it did not
# run, rather than passing quietly.
TC=${M9WINTOOLCHAIN:-}
why=""
command -v wine >/dev/null 2>&1 || why="no wine"
command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 || why="${why:+$why, }no mingw"
{ [ -n "$TC" ] && [ -f "$TC/lib/libssl.a" ]; } || why="${why:+$why, }no Windows OpenSSL (\$M9WINTOOLCHAIN)"
if [ -n "$why" ]; then
  echo "httpserver: the Windows half NOT RUN -- $why"
  echo "httpserver: PASS"
  exit 0
fi
WW=$W/win
mkdir -p "$WW/o"
( cd "$WW" && M9RUNTIME="$RT" M9LIBRARY="$LIB" "$M9C" --out-dir . "$SRC/SrvFix.m9" ) \
  > "$WW/gen.log" 2>&1 || { cat "$WW/gen.log"; echo "httpserver: FAIL -- SrvFix's C"; exit 1; }
for f in ../gen/*.c; do
  x86_64-w64-mingw32-gcc -std=c11 -O1 -w -iquote ../gen -iquote .. \
    -c "$f" -o "$WW/o/$(basename "$f" .c).o" 2>> "$WW/cc.log" ||
    { tail -5 "$WW/cc.log"; echo "httpserver: FAIL -- $f for Windows"; exit 1; }
done
x86_64-w64-mingw32-ar rcs "$WW/libm9.a" "$WW"/o/*.o
x86_64-w64-mingw32-gcc -std=c11 -O2 -w -iquote "$WW" -iquote ../gen -iquote .. -I "$TC/include" \
  "$WW/SrvFix.c" "$WW/libm9.a" ../m9rt.c ../tcpshim.c ../tlsshim.c ../fmtshim.c \
  "$TC/lib/libssl.a" "$TC/lib/libcrypto.a" -lcrypt32 -lws2_32 -lm -o "$WW/srvfix.exe" \
  2>> "$WW/cc.log" || { tail -10 "$WW/cc.log"; echo "httpserver: FAIL -- SrvFix for Windows"; exit 1; }
st=0
WINEDEBUG=-all WINEPREFIX="$WW/prefix" SRVFIX_WRAP=wine SRVFIX_PORT=19350 \
  "$PY" srvfix/srvfix.py "$WW/srvfix.exe" || st=$?
[ $st -eq 0 ] || { echo "httpserver: FAIL (the Windows half, under wine)"; exit 1; }
echo "httpserver: PASS (and the Windows half, under wine)"
