#!/bin/sh
# This gate holds examples/flock, the sparrow flock with a task a bird.
#
#   1. FlockTest passes: the rules one bird flies by, with Check.
#   2. 600 birds fly 400 ticks without a server, on every carrier and
#      on one.  No bird is lost to a fault, none leaves the sky, and at
#      least nine in ten are heard in their cell of air at the end.
#      The flock itself differs from run to run: within a tick the
#      birds move in the order the carriers run them.
#   3. FlockServer on a port of this run's own serves the page with
#      its banner and the frame: every bird has a place inside the
#      sky, the tick moves on, and the two flocks have started where
#      they should, males in the west and females in the east.
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
EX=$(cd ../../examples/flock && pwd)
command -v curl > /dev/null || { echo "SKIP: flock (no curl on this machine)"; exit 0; }

cp "$EX"/*.m9 "$TG/" && cp -R "$EX/web" "$TG/web"
cd "$TG"
"$M9C" --make -o flocktest FlockTest.m9 > build.txt 2>&1 ||
  { echo "flock: FAIL building FlockTest:"; tail -5 build.txt; exit 1; }
./flocktest > test.txt 2>&1 ||
  { echo "flock: FAIL FlockTest:"; tail -8 test.txt; exit 1; }
"$M9C" --make -o flockserver FlockServer.m9 > build.txt 2>&1 ||
  { echo "flock: FAIL building FlockServer:"; tail -5 build.txt; exit 1; }

# The flight without a server.  The line is
#   flock: birds 600 ticks 400 heard H lost 0 outside 0
for carriers in "" 1; do
  if [ -n "$carriers" ]; then
    M9_CARRIERS=$carriers ./flockserver --ticks 400 600 > fly.txt 2>&1 ||
      { echo "flock: FAIL the flight on $carriers carrier:"; cat fly.txt; exit 1; }
  else
    ./flockserver --ticks 400 600 > fly.txt 2>&1 ||
      { echo "flock: FAIL the flight:"; cat fly.txt; exit 1; }
  fi
  grep -q '^flock: birds 600 ticks 400 heard [0-9]* lost 0 outside 0$' fly.txt ||
    { echo "flock: FAIL the flight's count (carriers '$carriers'):"; cat fly.txt; exit 1; }
  heard=$(sed -n 's/.* heard \([0-9]*\) lost.*/\1/p' fly.txt)
  [ "$heard" -ge 540 ] && [ "$heard" -le 600 ] ||
    { echo "flock: FAIL $heard of 600 birds are heard (carriers '$carriers')"; exit 1; }
done
./flockserver --ticks 0 600 > bad.txt 2>&1 &&
  { echo "flock: FAIL --ticks 0 was taken"; exit 1; }
./flockserver --ticks 5 1 > bad.txt 2>&1 &&
  { echo "flock: FAIL a flock of one bird was taken"; exit 1; }

# A port from this process's number, in 20000 .. 39999; a taken one
# fails the listen and the next is tried.
port=$((20000 + $$ % 20000))
up=0
for try in 1 2 3 4 5; do
  ./flockserver "$port" web 500 > server.txt 2>&1 &
  pid=$!
  i=0
  while [ $i -lt 50 ]; do
    if curl -s -m 2 "http://127.0.0.1:$port/" 2>/dev/null |
       grep -q 'Sparrow flock brought to you by Modula-9'; then up=1; break; fi
    kill -0 "$pid" 2>/dev/null || break
    i=$((i+1)); sleep 0.1
  done
  [ $up = 1 ] && break
  kill "$pid" 2>/dev/null || :
  wait "$pid" 2>/dev/null || :
  pid=
  port=$((port + 7))
done
[ $up = 1 ] || { echo "flock: FAIL the server did not come up:"; cat server.txt; exit 1; }
U="http://127.0.0.1:$port"

# frame.awk reads one frame: {"tick":T,"hawk":[x,y],"p":[x0,y0,...]},
# places in quarter units of a 1600 by 900 sky.  It prints the tick,
# the birds, the birds outside the sky, and the mean x of the males
# (the even birds) and of the females, in units.
cat > frame.awk <<'EOF'
{
  t = $0; sub(/^\{"tick":/, "", t); tick = t + 0
  p = $0; sub(/^.*"p":\[/, "", p); sub(/\]\}$/, "", p)
  n = split(p, v, ",")
  out = 0; mx = 0; fx = 0
  for (i = 1; i < n; i += 2) {
    k = (i - 1) / 2
    if (v[i] < 0 || v[i] >= 6400 || v[i + 1] < 0 || v[i + 1] >= 3600) out++
    if (k % 2 == 0) mx += v[i]; else fx += v[i]
  }
  printf "%d %d %d %d %d\n", tick, n / 2, out, mx / (n / 4) / 4, fx / (n / 4) / 4
}
EOF
# The page answers before the birds have taken their places: the clock
# publishes its first frame when every bird has gone to its start and
# sleeps.  So the first frame with birds is waited for, five seconds at
# most.  (On a loaded machine the frame asked at once held none.)
i=0
while [ $i -lt 50 ]; do
  curl -s -m 5 "$U/frame" > f0.json
  grep -q '"p":\[[0-9]' f0.json && break
  i=$((i+1)); sleep 0.1
done
grep -q '^{"tick":[0-9]*,"hawk":\[[0-9]*,[0-9]*\],"p":\[[0-9,]*\]}$' f0.json ||
  { echo "flock: FAIL the frame is not the JSON it should be:"; head -c 300 f0.json; exit 1; }
set -- $(awk -f frame.awk f0.json)
t0=$1
[ "$2" = 500 ] || { echo "flock: FAIL the frame has $2 birds, not 500"; exit 1; }
[ "$3" = 0 ] || { echo "flock: FAIL $3 birds of the frame are outside the sky"; exit 1; }
# The flocks start 940 units apart and close at about 7 units a tick.
# So within the first 60 ticks the males are still the western flock.
if [ "$t0" -le 60 ]; then
  [ "$4" -lt 800 ] && [ "$5" -gt 800 ] ||
    { echo "flock: FAIL at tick $t0 the males are at x $4 and the females at x $5"; exit 1; }
fi
sleep 0.5
curl -s -m 5 "$U/frame" > f1.json
set -- $(awk -f frame.awk f1.json)
[ "$1" -gt "$t0" ] || { echo "flock: FAIL the tick did not move on in 0.5 s: $t0 then $1"; exit 1; }
[ "$2" = 500 ] && [ "$3" = 0 ] ||
  { echo "flock: FAIL the later frame has $2 birds, $3 outside the sky"; exit 1; }
cmp -s f0.json f1.json && { echo "flock: FAIL two frames 0.5 s apart are the same"; exit 1; }
code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$U/nothing-here")
[ "$code" = 404 ] || { echo "flock: FAIL an unknown path answered $code, not 404"; exit 1; }

kill "$pid"; wait "$pid" 2>/dev/null || :
pid=
echo "flock: $(tail -1 test.txt); 600 birds flew 400 ticks ($heard heard on one carrier); the server answers /frame (tick $t0 then $1) and the page on port $port"
