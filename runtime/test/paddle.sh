#!/bin/sh
# This gate holds examples/paddle, the bat-and-ball game an agent wrote
# (Qwen, 2026-11-18; the example's README).
#
#   1. PaddleTest passes: the rules, with Check.
#   2. PaddleServer builds, and on a port of this run's own it answers
#      /tick with the served ball at the court's centre, moves it on
#      the next tick, refuses a y that is no number with 400, and
#      serves the page with its banner.
#   3. The file route does not hide /tick.  The example's first version
#      added the routes the other way round and /tick was 404.
#
# The server is stopped by the PID this script started, never by name.
TG=$(mktemp -d "${TMPDIR:-/tmp}/m9gate.XXXXXX")
pid=
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$TG"' EXIT
set -e
cd "$(dirname "$0")"
. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C
export M9RUNTIME=$(cd .. && pwd)
export M9LIBRARY=$(cd ../../corpus && pwd)
EX=$(cd ../../examples/paddle && pwd)
command -v curl > /dev/null || { echo "SKIP: paddle (no curl on this machine)"; exit 0; }

cp "$EX"/*.m9 "$TG/" && cp -R "$EX/web" "$TG/web"
cd "$TG"
"$M9C" --make -o paddletest PaddleTest.m9 > build.txt 2>&1 ||
  { echo "paddle: FAIL building PaddleTest:"; tail -5 build.txt; exit 1; }
./paddletest > test.txt 2>&1 ||
  { echo "paddle: FAIL PaddleTest:"; tail -8 test.txt; exit 1; }
"$M9C" --make -o paddleserver PaddleServer.m9 > build.txt 2>&1 ||
  { echo "paddle: FAIL building PaddleServer:"; tail -5 build.txt; exit 1; }

# A port from this process's number, in 20000 .. 39999; a taken one
# fails the listen and the next is tried.
port=$((20000 + $$ % 20000))
up=0
for try in 1 2 3 4 5; do
  ./paddleserver "$port" web > server.txt 2>&1 &
  pid=$!
  i=0
  while [ $i -lt 50 ]; do
    if curl -s -m 2 -o /dev/null "http://127.0.0.1:$port/"; then up=1; break; fi
    kill -0 "$pid" 2>/dev/null || break
    i=$((i+1)); sleep 0.1
  done
  [ $up = 1 ] && break
  kill "$pid" 2>/dev/null || :
  wait "$pid" 2>/dev/null || :
  pid=
  port=$((port + 7))
done
[ $up = 1 ] || { echo "paddle: FAIL the server did not come up:"; cat server.txt; exit 1; }
U="http://127.0.0.1:$port"

curl -s -m 5 "$U/tick?y=100&serve=1" > t1.json
grep -q '^{"bx":400.0,"by":250.0,' t1.json ||
  { echo "paddle: FAIL /tick did not serve the ball at the centre:"; cat t1.json; exit 1; }
sleep 0.2
curl -s -m 5 "$U/tick?y=100" > t2.json
grep -q '"py":100.0,' t2.json ||
  { echo "paddle: FAIL /tick did not take the player's y:"; cat t2.json; exit 1; }
grep -q '^{"bx":400.0,' t2.json &&
  { echo "paddle: FAIL the ball did not move between two ticks:"; cat t2.json; exit 1; }
code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$U/tick?y=abc")
[ "$code" = 400 ] || { echo "paddle: FAIL a y that is no number answered $code, not 400"; exit 1; }
curl -s -m 5 "$U/" > page.html
grep -q 'Paddle game brought to you by Modula-9' page.html ||
  { echo "paddle: FAIL the page lost its banner"; head -5 page.html; exit 1; }

kill "$pid"; wait "$pid" 2>/dev/null || :
pid=
echo "paddle: $(tail -1 test.txt); the server answers /tick and the page on port $port"
