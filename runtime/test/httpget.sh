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

# a body that stops short of its framing is a lost connection, not a
# short document (Python: IncompleteRead).  Until 2026-10-02 the first
# of these answered `status 200 chars 10`.
ck "a body shorter than its Content-Length is refused by name" \
   "transport: the body ended before its Content-Length" \
   "$("$OUT/httpget" text "$U/short" || true)"

ck "a chunked body that ends without its last chunk is refused" \
   "transport: the body ended before its last chunk" \
   "$("$OUT/httpget" text "$U/shortchunk" || true)"

ck "and so is one that ends in the middle of a chunk" \
   "transport: the body ended before its last chunk" \
   "$("$OUT/httpget" text "$U/shortmid" || true)"

ck "to a file as well: the status is not answered for half a download" \
   "transport: the body ended before its Content-Length" \
   "$("$OUT/httpget" file "$U/short" '' '' "$OUT/short.bin" || true)"

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

# ---- Http.Request: the method, the caller's headers and the body all
# reach the server, and the response's headers come back by name ----
R="$OUT/httpget req"

ck "POST: method, Content-Length, two caller headers and the body arrive" \
   "POST|7|t0k3n|text/plain|hello=1" \
   "$($R POST "$U/reflect" 'hello=1' 'Content-Type: text/plain' 'X-Token: t0k3n' | tail -1)"

ck "and the response headers are read back by name, any case" \
   "hdr yes|31|" "$($R POST "$U/reflect" 'hello=1' 'Content-Type: text/plain' 'X-Token: t0k3n' | sed -n 2p)"

ck "PUT with no body still says Content-Length: 0" \
   "PUT|0|||" "$($R PUT "$U/reflect" | tail -1)"

ck "DELETE reaches the server as DELETE" \
   "DELETE|0|||" "$($R DELETE "$U/reflect" | tail -1)"

ck "GET through Request is the same GET" \
   "status 200 chars 1500" "$($R GET "$U/plain" | head -1)"

ck "a HEAD answers its headers and does not wait for a body" \
   "status 200 chars 0|hdr |1500|" \
   "$($R HEAD "$U/plain" | head -2 | tr '\n' '|' | sed 's/|$//')"

ck "a 303 after a POST is REPORTED with its Location, not followed" \
   "status 303 chars 0|hdr |0|/plain" \
   "$($R POST "$U/see-other" 'x=1' | head -2 | tr '\n' '|' | sed 's/|$//')"

ck "a POST body goes out as UTF-8 and the body comes back decoded" \
   "POST|15|||café — été" \
   "$($R POST "$U/reflect" 'café — été' | tail -1)"

ck "a chunked response to a POST takes the same decoder" \
   "0123456789abcdefghijklmnopqrstuvwxyz" \
   "$($R POST "$U/chunked-reflect" '0123456789abcdefghijklmnopqrstuvwxyz' | tail -1)"

# m9flexdev's two wishes (2026-09-27), in one check: meta.icos-cp.eu
# answers a SPARQL POST chunked, and the answer is UTF-8 that a parser
# reads -- not a printable rendering that turned Křešín into dots
ck "a chunked POST answer arrives decoded from UTF-8, chunk boundaries inside a character" \
   "Křešín u Pacova" \
   "$($R POST "$U/chunked-reflect" 'Křešín u Pacova' | tail -1)"

# a 3 MB body, from a file because an argument stops at 128 KB: larger
# than any socket buffer, so it arrives whole only if every write went
# out (a blocking write(2) on a stream socket finishes the buffer on
# its own, so SendAll's loop is insurance against the short write the
# API permits rather than something this fixture can provoke)
python3 -c 'print("x" * 3000000, end="")' > "$OUT/big.txt"
ck "a 3 MB POST body arrives whole" \
   "POST|3000000|||" \
   "$($R POST "$U/reflect" "@$OUT/big.txt" | tail -1 | cut -c1-15)"

ck "a 404 to a POST is reported, not raised" \
   "status 404 chars 0" "$($R POST "$U/nowhere" | head -1)"

ck "an empty method is refused by name" \
   "transport: no method" "$($R '' "$U/plain" || true)"

# ---- Http.Client: keep-alive, measured as the server's own count of
# requests on one connection, and the cookie jar's matching rules ----
S="$OUT/httpget session"
K=$U/keep

ck "three GETs on one Client ride one connection" \
   "status 200 req 1|status 200 req 2|status 200 req 3|kept 2" \
   "$($S $K/count $K/count $K/count | tr '\n' '|' | sed 's/|$//')"

ck "a Connection: close from the server ends the kept connection" \
   "status 200 req 1|status 200 req 2 closing|status 200 req 1|kept 1" \
   "$($S $K/count $K/close $K/count | tr '\n' '|' | sed 's/|$//')"

ck "a chunked body's trailer is consumed, so the next response is whole" \
   "status 200 req 1|status 200 req 2 chunked|status 200 req 3|kept 2" \
   "$($S $K/count $K/chunked $K/count | tr '\n' '|' | sed 's/|$//')"

ck "a 204 has no body and the connection stays usable" \
   "status 200 req 1|status 204 |status 200 req 3|kept 2" \
   "$($S $K/count $K/nobody $K/count | tr '\n' '|' | sed 's/|$//')"

ck "a connection the server dropped while idle is retried on a new one" \
   "status 200 req 1|status 200 req 2 dropped after|status 200 req 1|kept 1" \
   "$($S $K/count $K/dropnext $K/count | tr '\n' '|' | sed 's/|$//')"

ck "the one-shot forms still say close: two Requests, two connections" \
   "req 1|req 1" \
   "$( { $R GET $K/count | tail -1; $R GET $K/count | tail -1; } | tr '\n' '|' | sed 's/|$//')"

J=$U/jar
ck "the jar: path, default path, domain, Secure, Max-Age=0, Expires past, foreign domain, no name" \
   "status 200 a=1; b=2; c=3; h=8; r=9" \
   "$($S $J/set $J/show | sed -n 2p)"

ck "a deeper path under /jar still matches; /jarx does not" \
   "status 200 a=1; b=2; c=3; h=8; r=9|status 200 r=9" \
   "$($S $J/set $J/deeper/show $U/jarx/show | sed -n '2,3p' | tr '\n' '|' | sed 's/|$//')"

ck "only the Path=/ cookie reaches the root; /other gets its own" \
   "status 200 r=9|status 200 g=7; r=9" \
   "$($S $J/set $U/show $U/other/show | sed -n '2,3p' | tr '\n' '|' | sed 's/|$//')"

ck "a second Set-Cookie replaces a in place and Max-Age=0 deletes b" \
   "status 200 a=10; c=3; h=8; r=9" \
   "$($S $J/set $J/set2 $J/show | sed -n 3p)"

ck "a fresh Client has an empty jar" \
   "status 200 " "$($S $J/show | sed -n 1p)"

# ---- Http.RequestRetry: a server that is busy for a while.  The
# server counts the requests it saw per key (`ok at request K`), the
# client says how many tries it made, and the two must agree.  Each
# check has a key of its own, so a rerun of one line means what it
# meant the first time only against a fresh server -- which every run
# of this gate starts. ----
T="$OUT/httpget retry"
ms () { echo $(( ($(date +%s%N) - $1) / 1000000 )); }
between () {                 # between <what> <lo> <hi> <got>
  checks=$((checks + 1))
  if [ "$4" -ge "$2" ] && [ "$4" -le "$3" ]; then
    echo "  ok   $1 ($4 ms)"
  else
    echo "  FAIL $1: $4 ms, expected $2 to $3"
    fails=$((fails + 1))
  fi
}

ck "two 503s and then a 200: three tries, and the server saw three" \
   "status 200 tries 3 ok at request 3" "$($T GET "$U/flaky/a/2" 3 0)"

ck "a 503 that outlives the retries comes back as itself" \
   "status 503 tries 3 busy" "$($T GET "$U/flaky/b/5" 2 0)"

ck "and the server saw exactly the tries: the next request is the fourth" \
   "status 503 tries 1 busy" "$($T GET "$U/flaky/b/5" 0 0)"

ck "a POST is never sent twice on a status" \
   "status 503 tries 1 busy" "$($T POST "$U/flaky/c/1" 3 0)"

ck "a PUT is idempotent and goes again" \
   "status 200 tries 2 ok at request 2" "$($T PUT "$U/flaky/d/1" 3 0)"

# a method goes on the wire as it was written, and `get` is not GET to
# a server: the 501 is an answer, and not one to ask again for
ck "a 501 is not tried again" \
   "status 501 tries 1" "$($T get "$U/flaky/dd/1" 3 0 | head -1 | cut -c1-18)"

ck "a 404 is an answer, not a failure: one try" \
   "status 404 tries 1 " "$($T GET "$U/nowhere" 3 0)"

ck "no retries asked: one try" \
   "status 503 tries 1 busy" "$($T GET "$U/flaky/e/1" 0 0)"

t0=$(date +%s%N)
ck "a 429 with Retry-After: 1 is tried again" \
   "status 200 tries 2 ok at request 2" "$($T GET "$U/after/f" 2 0)"
between "and after the second it asked for, not at once" 1000 2500 "$(ms $t0)"

t0=$(date +%s%N)
ck "a Retry-After of an hour is not waited for and not defied" \
   "status 503 tries 1 request 1" "$($T GET "$U/longafter/g" 3 0)"
between "and the answer came back at once" 0 900 "$(ms $t0)"

ck "a 413 that says when to come back is tried again" \
   "status 200 tries 2 ok at request 2" "$($T GET "$U/large/h" 3 0)"

ck "a 413 that does not is the answer" \
   "status 413 tries 1 never" "$($T GET "$U/largeplain/i" 3 0)"

ck "a connection closed without an answer: a GET goes again" \
   "status 200 tries 3 ok at request 3" "$($T GET "$U/drop/j/2" 3 0)"

ck "but a POST does not -- the server may have acted on it" \
   "transport: short response tries 1" "$($T POST "$U/drop/k/1" 3 0 || true)"

ck "a connection never made is tried again, and raised when the tries are out" \
   "transport: connect failed tries 3" "$($T GET "http://127.0.0.1:1/x" 2 0 || true)"

ck "whatever the method: nothing was sent" \
   "transport: connect failed tries 3" "$($T POST "http://127.0.0.1:1/x" 2 0 || true)"

# 5 MB against this program's cap of 4 MB: it would fail the same way
# every time, and it fails AFTER part of an answer arrived, which is
# the line RequestRetry draws
ck "a failure after part of an answer arrived is not tried again" \
   "transport: the document is larger than the cap tries 1" \
   "$($T GET "$U/big" 3 0 || true)"

# the backoff: nothing before the first retry, then 0.4 s and 0.8 s
# for a factor of 0.2 -- 1.2 s in all, and not 2.8 s (a wait before
# the first retry too) nor 0.6 s (the factor not doubled)
t0=$(date +%s%N)
ck "three 503s with a factor of 0.2 s: four tries" \
   "status 200 tries 4 ok at request 4" "$($T GET "$U/flaky/l/3" 3 200)"
between "and 0 + 0.4 + 0.8 seconds of waiting" 1200 2000 "$(ms $t0)"

if [ "${M9HTTP_LIVE:-0}" = "1" ]; then
  D=$("$OUT/httpget" text 'https://doi.org/10.18160/JZ2X-GZGU' 'application/ld+json' | head -1)
  ck "LIVE: a DOI over TLS, cross-host redirect, chunked" "status 200 chars 63908" "$D"
else
  echo "  SKIP live Carbon Portal checks (set M9HTTP_LIVE=1)"
fi

echo "httpget: $checks checks, $fails failed"
[ "$fails" -eq 0 ]
