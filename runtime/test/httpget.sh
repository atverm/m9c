#!/bin/sh
# Http's URL fetcher against a fixture server: redirects, chunked
# bodies, the licence cookie, and a body framed only by the close.
#
# LOCAL BY CONSTRUCTION.  Every shape here was measured on the ICOS
# Carbon Portal first -- see corpus/Http.m9's note -- and is then
# reproduced by httpfix.py so the gate needs no network and cannot go
# red because a repository is slow.  $M9HTTP_LIVE=1 adds the live
# checks against data.icos-cp.eu for the day someone wants them.
set -e
cd "$(dirname "$0")"

REPO=$(cd ../.. && pwd)
M9C=${M9C:-$REPO/runtime/test/m9c}
[ -x "$M9C" ] || M9C=$REPO/out/m9c
[ -x "$M9C" ] || { echo "no m9c: run runtime/test/m9c.sh or ./build.sh"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: httpget (no python3)"; exit 0; }

OUT=/tmp/m9httpget
rm -rf "$OUT"; mkdir -p "$OUT"
cp httpget.m9 httpfix.py "$OUT/"
export M9RUNTIME="$REPO/runtime"
export M9LIBRARY="$REPO/corpus"
# -c and then gcc by hand: m9c links m9rt, tcpshim and fmtshim on
# its own but not tlsshim, which needs OpenSSL named -- and passing
# CCFLAGS after -- would make m9c stand aside from its own -O2 and
# -flto, which this repository has already paid for once.
( cd "$OUT" && "$M9C" --make -c httpget.m9 -I. >/dev/null )
gcc -O2 -iquote "$REPO/runtime" "$OUT"/*.o \
    "$REPO/runtime/m9rt.c" "$REPO/runtime/tcpshim.c" \
    "$REPO/runtime/tlsshim.c" -lssl -lcrypto -lm -o "$OUT/httpget" \
  || { echo "FAIL: httpget does not link"; exit 1; }

PORT=18991
python3 "$OUT/httpfix.py" $PORT & FIXPID=$!
trap 'kill $FIXPID 2>/dev/null' EXIT INT TERM
i=0
while [ $i -lt 100 ]; do
  python3 - "$PORT" <<'PY' && break
import socket, sys
s = socket.socket()
s.settimeout(0.2)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
PY
  i=$((i + 1))
done
[ $i -lt 100 ] || { echo "FAIL: the fixture server never listened"; exit 1; }

U=http://127.0.0.1:$PORT
checks=0; fails=0
ck () {                      # ck <what> <expected> <got>
  checks=$((checks + 1))
  if [ "$2" = "$3" ]; then
    echo "  ok   $1"
  else
    echo "  FAIL $1"
    echo "        expected: $2"
    echo "        got     : $3"
    fails=$((fails + 1))
  fi
}

ck "a plain body, Content-Length honoured" \
   "status 200 chars 1500" "$("$OUT/httpget" text "$U/plain" | head -1)"

ck "a chunked body, five chunks, one over the read block" \
   "status 200 chars 165547" "$("$OUT/httpget" text "$U/chunked" | head -1)"

ck "a body framed only by the close" \
   "status 200 chars 1500" "$("$OUT/httpget" text "$U/toclose" | head -1)"

ck "a RELATIVE redirect carrying the licence cookie" \
   "status 200 chars 1500" "$("$OUT/httpget" text "$U/licence" | head -1)"

ck "and the target REFUSES without it -- so the cookie is the reason" \
   "status 403 chars 0" "$("$OUT/httpget" text "$U/guarded" | head -1)"

ck "an absolute redirect, with the 302 itself chunked" \
   "status 200 chars 1500" "$("$OUT/httpget" text "$U/away" | head -1)"

ck "a redirect loop is refused BY NAME, not followed" \
   "transport: too many redirects" "$("$OUT/httpget" text "$U/loop" || true)"

ck "Accept is sent, and identity is asked for by name" \
   "application/ld+json|identity" \
   "$("$OUT/httpget" text "$U/echo" 'application/ld+json' | tail -1)"

ck "a 404 is REPORTED, not raised" \
   "status 404 chars 0" "$("$OUT/httpget" text "$U/404" | head -1)"

ck "the body is decoded from UTF-8, not from octets" \
   "café — été" "$("$OUT/httpget" text "$U/utf8" | tail -1)"

ck "5 MB to a file, byte for byte" \
   "status 200 bytes 5242880" \
   "$("$OUT/httpget" file "$U/big" '' '' "$OUT/big.bin" | head -1)"
python3 - "$OUT/big.bin" <<'PY' > "$OUT/bigcmp"
import sys
want = bytes((i * 7 + 11) % 251 for i in range(5 * 1024 * 1024))
print("same" if open(sys.argv[1], "rb").read() == want else "DIFFERENT")
PY
ck "and the 5 MB file is what the server sent" "same" "$(cat "$OUT/bigcmp")"

# the peak is one read block, not one download: 5 MB through a
# process that stays small is the whole claim of the streaming form
RSS=$(/usr/bin/time -f '%M' "$OUT/httpget" file "$U/big" '' '' "$OUT/big2.bin" 2>&1 >/dev/null | tail -1)
if [ "$RSS" -lt 32768 ] 2>/dev/null; then
  echo "  ok   5 MB downloaded in ${RSS} KB of RSS -- the block, not the file"
  checks=$((checks + 1))
else
  echo "  FAIL 5 MB download took ${RSS} KB of RSS"
  checks=$((checks + 1)); fails=$((fails + 1))
fi

if [ "${M9HTTP_LIVE:-0}" = "1" ]; then
  D=$("$OUT/httpget" text 'https://doi.org/10.18160/JZ2X-GZGU' 'application/ld+json' | head -1)
  ck "LIVE: a DOI over TLS, cross-host redirect, chunked" "status 200 chars 63908" "$D"
else
  echo "  SKIP live Carbon Portal checks (set M9HTTP_LIVE=1)"
fi

echo "httpget: $checks checks, $fails failed"
[ "$fails" -eq 0 ]
