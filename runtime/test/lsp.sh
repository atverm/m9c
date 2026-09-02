#!/bin/sh
# m9lsp -- the language server, gated the way the tutor is: a real
# session over the real transport, byte-framed, with the server built
# from the tree and speaking for the m9c built beside it.
#
# The client half is python3 because a shell cannot portably read
# exact byte counts; the SERVER half is the M9 under test.  Checks:
# initialize answers the name and version; a broken file yields
# publishDiagnostics carrying m9c's own message at its position; a
# clean file yields an empty list; an unknown REQUEST is answered
# -32601 (a notification is not); shutdown/exit end the process with
# status 0.
set -e
cd "$(dirname "$0")"
. ./gen.sh          # runtime/gen is BUILT here, not found

command -v python3 >/dev/null 2>&1 || { echo "lsp: SKIP (no python3)"; exit 0; }

SRC=$(cd ../../corpus && pwd)
RT=$(cd .. && pwd)
W=/tmp/m9lsp-gate
rm -rf "$W"; mkdir -p "$W"

# the compiler the server invokes, built from the gen just made --
# never a leftover binary (the stale-artifact trap, twice bitten)
gcc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-label \
    -Wno-unused-parameter -Wno-unused-function \
    -iquote .. -iquote ../gen ../m9rt.c ../gen/DynStr.c ../gen/Fmt.c \
    ../gen/Text.c ../gen/Lex.c ../gen/Ast.c ../gen/Print.c \
    ../gen/Parse.c ../gen/Sem.c ../gen/Doc.c ../gen/Gen.c \
    ../gen/Io.c ../gen/Time.c ../gen/M9c.c -lm -o "$W/m9c"

# the server, compiled by the m9c it will later invoke
cd "$W"
M9RUNTIME="$RT" M9LIBRARY="$SRC" ./m9c --make -o m9lsp "$SRC/Lsp.m9" >build.log 2>&1 || \
  { echo "lsp: FAIL building m9lsp:"; tail -5 build.log; exit 1; }

cat > Broke.m9 <<'BRK'
MODULE Broke ;
VAR i : I64 ;
BEGIN
  i := 'text'
END Broke.
BRK
cat > Fine.m9 <<'FIN'
MODULE Fine ;
VAR i : I64 ;
BEGIN
  i := 42
END Fine.
FIN

M9LSP_M9C=$W/m9c M9LIBRARY="$SRC" python3 - "$W" <<'PY'
import json, subprocess, sys, os

w = sys.argv[1]
p = subprocess.Popen([w + '/m9lsp'], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE)

def send(obj):
    b = json.dumps(obj).encode()
    p.stdin.write(b'Content-Length: %d\r\n\r\n' % len(b) + b)
    p.stdin.flush()

def recv():
    hdr = b''
    while not hdr.endswith(b'\r\n\r\n'):
        c = p.stdout.read(1)
        assert c, 'server closed early'
        hdr += c
    n = int([l for l in hdr.split(b'\r\n') if l.startswith(b'Content-Length')][0].split(b':')[1])
    return json.loads(p.stdout.read(n))

fails = 0
def check(cond, what):
    global fails
    if not cond:
        print('FAIL:', what); fails += 1

send({'jsonrpc':'2.0','id':1,'method':'initialize','params':{}})
r = recv()
check(r.get('id') == 1, 'initialize echoes its id')
check(r['result']['serverInfo']['name'] == 'm9lsp', 'server names itself')
check(r['result']['serverInfo']['version'] == '0.4.0', 'server version')

send({'jsonrpc':'2.0','method':'initialized','params':{}})

uri = 'file://' + w + '/Broke.m9'
send({'jsonrpc':'2.0','method':'textDocument/didOpen',
      'params':{'textDocument':{'uri':uri,'languageId':'m9','version':1,
                                'text':open(w+'/Broke.m9').read()}}})
r = recv()
check(r['method'] == 'textDocument/publishDiagnostics', 'diagnostics arrive')
check(r['params']['uri'] == uri, 'diagnostics name the uri verbatim')
ds = r['params']['diagnostics']
check(len(ds) >= 1, 'the broken file has a diagnostic')
check('cannot assign' in ds[0]['message'], "m9c's own message survives")
check(ds[0]['range']['start']['line'] == 3, 'the line is 0-based 3')
check(ds[0]['source'] == 'm9c', 'the source names the compiler')

uri2 = 'file://' + w + '/Fine.m9'
send({'jsonrpc':'2.0','method':'textDocument/didOpen',
      'params':{'textDocument':{'uri':uri2,'languageId':'m9','version':1,
                                'text':open(w+'/Fine.m9').read()}}})
r = recv()
check(r['params']['uri'] == uri2, 'the clean file answers too')
check(r['params']['diagnostics'] == [], 'and its list is empty')

send({'jsonrpc':'2.0','id':7,'method':'no/such','params':{}})
r = recv()
check(r.get('id') == 7 and r.get('error',{}).get('code') == -32601,
      'an unknown request errors -32601')

send({'jsonrpc':'2.0','id':9,'method':'shutdown'})
r = recv()
check(r.get('id') == 9 and r.get('result') is None, 'shutdown answers null')
send({'jsonrpc':'2.0','method':'exit'})
p.stdin.close()
check(p.wait(timeout=10) == 0, 'exit ends the process with 0')

sys.exit(1 if fails else 0)
PY
st=$?
[ $st -eq 0 ] || { echo "lsp: FAIL"; exit 1; }
echo "lsp: 12 checks -- a framed session against the tree's own m9c"
