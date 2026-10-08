#!/bin/sh
# smtp -- Smtp.Send against a server M9 did not write (docs/library-
# plan-2.md, item 6): aiosmtpd, four of it -- plain with AUTH PLAIN and
# LOGIN offered, LOGIN only, implicit TLS, STARTTLS required -- each
# recording what it accepts.  runtime/test/smtpfix/SmtpFix.m9 sends
# text, a folded UTF-8 subject, To + Cc + Bcc and an attachment, over
# each transport and with each AUTH, and prints what it sent; Python's
# email parses every message that arrived back to that.  The refusals
# -- a wrong password, a rejected recipient, a deferred sender, STARTTLS
# not offered, TLS against a plain port, plain against a server that
# requires STARTTLS -- are held to this list by name and reply code.
# The message's own layout is SmtpTest's (m9test), against goldens.
#
# SHOWN ABLE TO FAIL by smtpfix/sabotage.py: one-line breaks of
# Smtp.m9, each of which turns this gate red.
#
# Needs aiosmtpd (python3-aiosmtpd on Debian and Ubuntu; SMTPFIX_PY
# names another Python) and openssl for the certificate.  Without
# them the gate SKIPS out loud on a workstation and FAILS on CI.
set -e
cd "$(dirname "$0")"

M9C=${M9C:-}
[ -n "$M9C" ] || { [ -x ./m9c ] && M9C=$(pwd)/m9c; }
[ -n "$M9C" ] || { [ -x ../../out/m9c ] && M9C=$(cd ../../out && pwd)/m9c; }
[ -n "$M9C" ] || { echo "smtp: no m9c (run m9c.sh or build.sh)"; exit 1; }

PY=${SMTPFIX_PY:-python3}
why=""
"$PY" -c 'import aiosmtpd' 2>/dev/null || why="$PY has no aiosmtpd (python3-aiosmtpd, or set SMTPFIX_PY)"
command -v openssl >/dev/null 2>&1 || why="${why:+$why; }no openssl"
if [ -n "$why" ]; then
  if [ -n "$GITHUB_ACTIONS" ]; then echo "smtp: FAIL -- $why"; exit 1; fi
  echo "smtp: SKIP -- $why"; exit 0
fi

W=/tmp/m9-smtp
rm -rf "$W"; mkdir -p "$W/out"
RT=$(cd .. && pwd)
LIB=${M9LIBRARY_OVERRIDE:-$(cd ../../corpus && pwd)}   # sabotage.py hands a broken copy
SRC=$(cd smtpfix && pwd)
( cd "$W" && M9RUNTIME="$RT" M9LIBRARY="$LIB" \
    "$M9C" --make -o smtpfix "$SRC/SmtpFix.m9" ) > "$W/build.log" 2>&1 ||
  { cat "$W/build.log"; echo "smtp: FAIL -- SmtpFix does not build"; exit 1; }

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -keyout "$W/key.pem" -out "$W/cert.pem" \
  -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost' >/dev/null 2>&1 ||
  { echo "smtp: FAIL -- openssl req"; exit 1; }

B=$((20000 + $$ % 10000))
P1=$B; P2=$((B + 1)); P3=$((B + 2)); P4=$((B + 3))
"$PY" smtpfix/smtpfix.py serve $P1 $P2 $P3 $P4 "$W/cert.pem" "$W/key.pem" "$W/out" > "$W/serve.log" 2>&1 &
FIX=$!
trap 'kill $FIX 2>/dev/null; wait $FIX 2>/dev/null' EXIT
n=0
while ! grep -q serving "$W/serve.log" 2>/dev/null; do
  n=$((n + 1)); [ $n -lt 100 ] || { cat "$W/serve.log"; echo "smtp: FAIL -- the fixture did not start"; exit 1; }
  sleep 0.1
done

st=0
SSL_CERT_FILE="$W/cert.pem" "$W/smtpfix" $P1 $P2 $P3 $P4 > "$W/sent.txt" 2> "$W/driver.err" || st=$?
[ $st -eq 0 ] || { cat "$W/sent.txt" "$W/driver.err"; echo "smtp: FAIL -- the driver exited $st"; exit 1; }
grep -q '^done$' "$W/sent.txt" || { cat "$W/sent.txt"; echo "smtp: FAIL -- the driver did not finish"; exit 1; }
if grep -q '^FAIL' "$W/sent.txt"; then grep '^FAIL' "$W/sent.txt"; echo "smtp: FAIL"; exit 1; fi

# the refusals by name and code (the message after -- is for a reader)
cat > "$W/refused.want" <<'EOF'
refused badpass 535
refused rcpt 550
refused mail 451
refused nostarttls 250
refused tlsplain 0
refused needstarttls 530
EOF
sed -n 's/^\(refused [a-z]* [0-9]*\) .*/\1/p' "$W/sent.txt" > "$W/refused.got"
diff "$W/refused.want" "$W/refused.got" || { grep '^refused' "$W/sent.txt"; echo "smtp: FAIL -- the refusals"; exit 1; }

"$PY" smtpfix/smtpfix.py judge "$W/out" "$W/sent.txt" || { echo "smtp: FAIL -- the judge"; exit 1; }
echo "smtp: PASS ($(grep -c '^sent' "$W/sent.txt") messages, $(grep -c '^refused' "$W/sent.txt") refusals)"
