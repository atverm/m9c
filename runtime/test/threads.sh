#!/bin/sh
# par 6, end to end: m9c compiles a program using THREAD, MONITOR,
# WAIT and SIGNAL, and the program gives the right answer.
#
# The answer is what makes this a test rather than a demonstration.
# The worker adds i MOD 7 for i in 0..N-1 into a monitor field and
# signals; the main thread waits.  If the wait returned early, or the
# lock did not serialise the field, or the thread never ran, the total
# is wrong -- and it is checked against a number computed here, not
# against whatever the program printed last time.
#
# RUN REPEATEDLY.  A race that fires one time in ten is still a race,
# and a single green run is the blosc museum piece all over again.
set -e
cd "$(dirname "$0")"

REPO=$(cd ../.. && pwd)
M9C=${M9C:-$REPO/runtime/test/m9c}
[ -x "$M9C" ] || M9C=$REPO/out/m9c
[ -x "$M9C" ] || { echo "no m9c: run runtime/test/m9c.sh or ./build.sh"; exit 1; }

OUT=/tmp/m9threads
rm -rf "$OUT"; mkdir -p "$OUT"
cp thrtest.m9 "$OUT/"
export M9RUNTIME="$REPO/runtime"
export M9LIBRARY="$REPO/corpus"

( cd "$OUT" && "$M9C" --make -o thrtest thrtest.m9 -I. )

# 3000000 terms of i mod 7: 428571 full cycles of 0..6 (sum 21) plus
# the tail 0,1,2 -- computed here so the expectation is derived, not
# remembered
want=$(( 428571 * 21 + 0 + 1 + 2 ))
runs=20
bad=0
for i in $(seq $runs); do
  got=$("$OUT/thrtest" | sed 's/^n = //')
  [ "$got" = "$want" ] || { bad=$((bad + 1)); echo "  run $i: got $got, want $want"; }
done

if [ "$bad" -ne 0 ]; then
  echo "threads: $bad of $runs runs disagreed"
  exit 1
fi
# ---- [SERIAL] is a GUARANTEE, not a rule to remember ----
#
# serialtest.m9 calls a deliberately unsafe C library (read, spin,
# write back) from eight threads.  The generator gates every call to a
# [SERIAL] foreign procedure behind one monitor per FOR-C unit, so the
# count comes out exact.  Change the declaration to [REENTRANT] and
# the same program loses about 85% of its updates -- measured, which
# is how this test was shown able to fail.
cp serialtest.m9 serialgate.c "$OUT/"
gcc -std=c11 -O2 -c "$OUT/serialgate.c" -o "$OUT/serialgate.o"
( cd "$OUT" && "$M9C" --make -c serialtest.m9 -I. )
( cd "$OUT" && gcc -std=c11 -O2 -flto -iquote "$REPO/runtime" -iquote . \
    "$REPO/runtime/m9rt.c" ./*.o -lm -o serialtest )

sbad=0
for i in $(seq 5); do
  out=$("$OUT/serialtest")
  case "$out" in
    *OK) : ;;
    *) sbad=$((sbad + 1)); echo "  $out" ;;
  esac
done
if [ "$sbad" -ne 0 ]; then
  echo "threads: [SERIAL] gate lost updates in $sbad of 5 runs"
  exit 1
fi

echo "threads: $runs runs of THREAD/MONITOR/WAIT/SIGNAL answered $want;"
echo "         5 runs of the [SERIAL] gate lost no updates"

# ---- CONCURRENT HTTPS, which the shim's [REENTRANT] tag now claims.
# It said [SERIAL] until 2026-08-30 and that was load-bearing: the
# slot table was claimed without a lock, so two threads could take
# the same slot and one would free the other's SSL object.  The tag
# is only worth the test behind it, so: a real TLS server, a real
# certificate this run generates and trusts through $SSL_CERT_FILE,
# a real handshake per connection, and every byte compared against a
# sequential pass.  `localhost` rather than 127.0.0.1 because the
# certificate's NAME is verified and OpenSSL does not match a
# hostname against an IP.
#
# AN ENVIRONMENT THAT CANNOT HOST THIS SKIPS; A SHIM THAT RACES
# FAILS.  The first CI run conflated them: the server bound
# 127.0.0.1 only while `localhost` resolves to ::1 first on the
# runner, so every fetch -- sequential included -- came back -1 and
# the gate blamed the shim.  The server now binds both families, the
# script WAITS for the port instead of sleeping at it, and a
# handshake that cannot be made at all is a skip with its reason.
TLSD=$OUT/tls
tls_ready=0
if ! command -v openssl >/dev/null 2>&1; then
  echo "threads: SKIP concurrent HTTPS (no openssl(1) to make a certificate)"
elif ! python3 -c 'import ssl' >/dev/null 2>&1; then
  echo "threads: SKIP concurrent HTTPS (python3 has no ssl module)"
else
  mkdir -p "$TLSD"
  if openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
      -keyout "$TLSD/key.pem" -out "$TLSD/cert.pem" \
      -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost' \
      >/dev/null 2>&1; then
    cat > "$TLSD/serve.py" <<'PY'
import http.server, socket, ssl, sys, time
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s):
        time.sleep(0.30)          # the wait that concurrency exists to overlap
        b = b"x" * 1024
        s.send_response(200); s.send_header("Content-Length", str(len(b)))
        s.end_headers(); s.wfile.write(b)
    def log_message(s, *a): pass
class S(http.server.ThreadingHTTPServer):
    # BOTH FAMILIES: `localhost` is ::1 before 127.0.0.1 on some
    # machines, and a server bound to one of them fails on the other
    # in a way that looks exactly like a broken client
    address_family = socket.AF_INET6
    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        http.server.ThreadingHTTPServer.server_bind(self)
c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
c.load_cert_chain(sys.argv[2], sys.argv[3])
d = S(("::", int(sys.argv[1])), H)
d.socket = c.wrap_socket(d.socket, server_side=True)
d.serve_forever()
PY
    python3 "$TLSD/serve.py" 18943 "$TLSD/cert.pem" "$TLSD/key.pem" &
    TLSPID=$!
    trap 'kill $TLSPID 2>/dev/null' EXIT
    # wait for a real handshake, not for a number of seconds
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      if echo | openssl s_client -connect localhost:18943 \
           -CAfile "$TLSD/cert.pem" -verify_return_error >/dev/null 2>&1; then
        tls_ready=1; break
      fi
      sleep 0.4
    done
    [ "$tls_ready" = 1 ] ||
      echo "threads: SKIP concurrent HTTPS (no TLS server answered on localhost:18943)"
  else
    echo "threads: SKIP concurrent HTTPS (openssl could not make a certificate)"
  fi
fi

if [ "$tls_ready" = 1 ]; then
  cp "$REPO/runtime/test/TlsPar.m9" "$OUT/"
  ( cd "$OUT" && "$M9C" --make -c TlsPar.m9 -I. >/dev/null )
  ( cd "$OUT" && gcc -std=c11 -O2 -flto -iquote "$REPO/runtime" -iquote . \
      "$REPO/runtime/m9rt.c" "$REPO/runtime/tcpshim.c" "$REPO/runtime/tlsshim.c" \
      TlsPar.o Http.o DynStr.o Io.o -lssl -lcrypto -lm -o tlspar )

  tbad=0
  for i in $(seq 5); do
    # || echo CRASHED: the point of this gate is a shim that CRASHES
    # when it is wrong (the pre-fix one aborts on a double free), and
    # set -e would end the script before it could say so
    out=$(cd "$OUT" && SSL_CERT_FILE="$TLSD/cert.pem" ./tlspar 2>&1 || echo "CRASHED ($?)")
    case "$out" in
      *"all identical to the sequential pass") : ;;
      *) tbad=$((tbad + 1)); echo "  $out" | head -3 ;;
    esac
  done
  kill $TLSPID 2>/dev/null || true
  if [ "$tbad" -ne 0 ]; then
    echo "threads: concurrent HTTPS failed in $tbad of 5 runs"
    exit 1
  fi
  echo "         5 runs of eight concurrent HTTPS fetches agreed with the"
  echo "         sequential pass, byte for byte"
fi
