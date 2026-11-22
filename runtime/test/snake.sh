#!/bin/sh
# This gate holds examples/snake, the grid game an agent wrote
# (Qwen, 2026-11-18; the example's README).
#
#   1. SnakeTest passes: the rules, with Check.
#   2. SnakeServer builds, and on a port of this run's own it waits
#      for start=1, starts the snake at the grid's centre, moves it on
#      a later tick, refuses a dir that is no direction with 400, and
#      serves the page with its banner.
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
EX=$(cd ../../examples/snake && pwd)
command -v curl > /dev/null || { echo "SKIP: snake (no curl on this machine)"; exit 0; }

cp "$EX"/*.m9 "$TG/" && cp -R "$EX/web" "$TG/web"
cd "$TG"
"$M9C" --make -o snaketest SnakeTest.m9 > build.txt 2>&1 ||
  { echo "snake: FAIL building SnakeTest:"; tail -5 build.txt; exit 1; }
./snaketest > test.txt 2>&1 ||
  { echo "snake: FAIL SnakeTest:"; tail -8 test.txt; exit 1; }
"$M9C" --make -o snakeserver SnakeServer.m9 > build.txt 2>&1 ||
  { echo "snake: FAIL building SnakeServer:"; tail -5 build.txt; exit 1; }

# A port from this process's number, in 20000 .. 39999; a taken one
# fails the listen and the next is tried.
port=$((20000 + $$ % 20000))
up=0
for try in 1 2 3 4 5; do
  ./snakeserver "$port" web > server.txt 2>&1 &
  pid=$!
  i=0
  while [ $i -lt 50 ]; do
    # The page must be this server's own.  A port another gate's server
    # holds answers / too, while this one fails its listen and exits
    # (paddle, 2026-11-22: /tick answered "not found").
    if curl -s -m 2 "http://127.0.0.1:$port/" 2>/dev/null |
       grep -q 'Snake, served by Modula-9'; then up=1; break; fi
    kill -0 "$pid" 2>/dev/null || break
    i=$((i+1)); sleep 0.1
  done
  [ $up = 1 ] && break
  kill "$pid" 2>/dev/null || :
  wait "$pid" 2>/dev/null || :
  pid=
  port=$((port + 7))
done
[ $up = 1 ] || { echo "snake: FAIL the server did not come up:"; cat server.txt; exit 1; }
U="http://127.0.0.1:$port"

curl -s -m 5 "$U/tick?dir=0" > t0.json
grep -q '"started":false' t0.json ||
  { echo "snake: FAIL the game started before start=1:"; cat t0.json; exit 1; }
curl -s -m 5 "$U/tick?start=1" > t1.json
grep -q '^{"body":\[\[12,12\],\[11,12\],\[10,12\]\],' t1.json ||
  { echo "snake: FAIL start=1 did not put the snake at the centre:"; cat t1.json; exit 1; }
grep -q '"score":0,"alive":true,"started":true,"won":false}$' t1.json ||
  { echo "snake: FAIL the started game is not alive at score 0:"; cat t1.json; exit 1; }
# The slowest pace is a cell every 0.16 s, and the wall is 11 cells
# away.  So 0.4 s moves the head and cannot end the game.
sleep 0.4
curl -s -m 5 "$U/tick" > t2.json
grep -q '"alive":true' t2.json ||
  { echo "snake: FAIL the snake died in 0.4 s:"; cat t2.json; exit 1; }
grep -q '^{"body":\[\[12,12\],' t2.json &&
  { echo "snake: FAIL the snake did not move between two ticks:"; cat t2.json; exit 1; }
for bad in 7 abc; do
  code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$U/tick?dir=$bad")
  [ "$code" = 400 ] || { echo "snake: FAIL dir=$bad answered $code, not 400"; exit 1; }
done
curl -s -m 5 "$U/" > page.html
grep -q 'Snake game brought to you by Modula-9' page.html ||
  { echo "snake: FAIL the page lost its banner"; head -5 page.html; exit 1; }

kill "$pid"; wait "$pid" 2>/dev/null || :
pid=
echo "snake: $(tail -1 test.txt); the server answers /tick and the page on port $port"
