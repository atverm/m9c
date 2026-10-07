#!/usr/bin/env python3
"""srvfix BIN -- HttpServer (corpus/HttpServer.m9) held to RFC 9112 by
code M9 did not write.

BIN is runtime/test/srvfix/SrvFix.m9 built with this tree's compiler.
Every case sends RAW octets -- malformed ones included -- and every
response is parsed by h11, an independent HTTP/1.1 implementation: a
response h11 refuses is a failure whatever its status.  Each response's
Date must be a valid IMF-fixdate within ten seconds of now, its weekday
included (Python formats the parsed time back and the two must be the
same text).

Then the load: eight clients on kept connections, every body compared
with one Python computed independently, and the server's descriptors
and resident memory read from /proc before and after (Linux; elsewhere
those two lines say SKIP).  Then the instances a single case needs:
a one-worker server whose full queue must answer 503, one whose
connection limit drains it and prints its counts, one whose
per-connection limit closes the third response.

Prints one line per failed check and a last line
`srvfix: PASS (N checks)` or `srvfix: FAIL (k of N)`; exits 0 or 1.
docs/httpserver-plan.md, stage 1."""
import atexit
import datetime
import email.utils
import os
import socket
import subprocess
import sys
import threading
import time
import http.client
import gzip
import re
import shutil
import signal
import tempfile

import h11

BIN = sys.argv[1]
# a program to run the server under -- "wine" for a Windows build -- and
# what such a run cannot hold, said rather than failed: WINE skips the
# checks that rest on POSIX signals and on /proc
WRAP = os.environ.get("SRVFIX_WRAP", "").split()
WINE = "wine" in WRAP
# the stop signal: SIGTERM on POSIX; under wine SIGINT, which wine
# delivers to a Windows program as the console's Ctrl-C (measured --
# SIGTERM kills it outright, and a Windows program never sees it)
STOPSIG = signal.SIGINT if WINE else signal.SIGTERM
BASE = int(os.environ.get("SRVFIX_PORT", "18350"))
checks = 0
fails = []


def ck(ok, what):
    global checks
    checks += 1
    if not ok:
        fails.append(what)
        print("FAIL:", what, flush=True)


# ---- the server under test ------------------------------------------

STARTED = []                        # every server this run started


@atexit.register
def stop_all():
    for sv in STARTED:
        if sv.p.poll() is None:
            sv.p.kill()


class Server:
    def __init__(self, port, *args, host="127.0.0.1"):
        self.port = port
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1).close()
            raise SystemExit(f"srvfix: port {port} is taken before the server starts "
                             f"(a server from an earlier run?); SRVFIX_PORT moves the range")
        except OSError:
            pass
        self.p = subprocess.Popen([*WRAP, BIN, f"--port={port}", *args],
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        STARTED.append(self)
        t0 = time.time()
        while time.time() - t0 < 10:
            try:
                socket.create_connection((host, port), timeout=1).close()
                return
            except OSError:
                if self.p.poll() is not None:
                    break
                time.sleep(0.05)
        # one that never answered is still a process holding a port
        if self.p.poll() is None:
            self.p.kill()
        raise SystemExit(f"srvfix: the server on {port} did not come up: "
                         f"{self.p.communicate()[0].decode(errors='replace')}")

    def pid(self):
        """the server's own process: under wine the Popen pid is wine's
        launcher, and the program is a child that names itself"""
        if not WINE:
            return self.p.pid
        me = os.path.basename(BIN)
        for d in os.listdir("/proc"):
            if not d.isdigit() or int(d) == self.p.pid:
                continue
            try:
                c = open(f"/proc/{d}/cmdline", "rb").read().split(b"\0")
            except OSError:
                continue
            if c and c[0].decode(errors="replace").endswith(me) and \
               f"--port={self.port}".encode() in c:
                return int(d)
        return self.p.pid

    def stop(self):
        # its own PID, never a pattern
        if self.p.poll() is None:
            self.p.terminate()
        return self.p.communicate(timeout=10)[0].decode(errors="replace")

    def finish(self, timeout=15):
        """wait for a --max run to drain and exit by itself"""
        try:
            out = self.p.communicate(timeout=timeout)[0].decode(errors="replace")
        except subprocess.TimeoutExpired:
            self.p.kill()
            return None, self.p.communicate()[0].decode(errors="replace")
        return self.p.returncode, out


def raw(port, data, wait=2.0, chunks=None, gap=0.0):
    """send data (or the pieces in chunks, gap seconds apart) and read
    until the server closes or wait seconds pass in silence"""
    s = socket.create_connection(("127.0.0.1", port), timeout=wait)
    out = bytearray()           # += on bytes copies: quadratic on 41 MB
    try:
        try:
            if chunks:
                for c in chunks:
                    s.sendall(c)
                    time.sleep(gap)
            else:
                s.sendall(data)
        except (BrokenPipeError, ConnectionResetError):
            pass                    # the server answered and closed first
        while True:
            try:
                b = s.recv(65536)
            except (socket.timeout, ConnectionResetError):
                break
            if not b:
                break
            out += b
    finally:
        s.close()
    return bytes(out)


def parse(data, methods):
    """the responses in data, read by h11 as answers to requests made
    with these methods in order.  A list of (status, headers, body);
    a 1xx is its own entry with body None."""
    conn = h11.Connection(our_role=h11.CLIENT)
    got = []
    i = 0

    def ask(m):
        conn.send(h11.Request(method=m, target="/", headers=[("Host", "x")]))
        conn.send(h11.EndOfMessage())

    ask(methods[0])
    conn.receive_data(data)
    status, headers, body = None, None, b""
    while True:
        ev = conn.next_event()
        if ev is h11.NEED_DATA:
            conn.receive_data(b"")
            ev = conn.next_event()
            if ev is h11.NEED_DATA or isinstance(ev, h11.ConnectionClosed):
                break
        if isinstance(ev, h11.InformationalResponse):
            got.append((ev.status_code, dict((k.decode().lower(), v.decode())
                                             for k, v in ev.headers), None))
        elif isinstance(ev, h11.Response):
            status = ev.status_code
            headers = dict((k.decode().lower(), v.decode()) for k, v in ev.headers)
            body = bytearray()      # a chunked body is one Data per chunk
        elif isinstance(ev, h11.Data):
            body += ev.data
        elif isinstance(ev, h11.EndOfMessage):
            got.append((status, headers, bytes(body)))
            i += 1
            if i >= len(methods) or conn.their_state is not h11.DONE \
               or conn.our_state is not h11.DONE:
                break
            conn.start_next_cycle()
            ask(methods[i])
        elif isinstance(ev, h11.ConnectionClosed):
            break
    left, _ = conn.trailing_data
    if left and (not got or got[-1][0] is None or
                 conn.their_state in (h11.MUST_CLOSE, h11.CLOSED)):
        raise h11.RemoteProtocolError(
            f"{len(left)} octets after the last response: {bytes(left[:40])!r}")
    return got


LIVE = []                           # the servers whose death ends the run


def alive(what):
    for sv in LIVE:
        if sv.p.poll() is not None:
            out = sv.p.stdout.read().decode(errors="replace")
            ck(False, f"{what}: the server on {sv.port} died (exit {sv.p.returncode}): {out[-400:]!r}")
            print(f"srvfix: FAIL ({checks} checks, {len(fails)} failed)")
            sys.exit(1)


def statuses(port, data, methods, what, want, **kw):
    """send, parse, and hold the statuses to want; answers the parsed
    responses (or [] when h11 refused them).  A server that died on
    the way ends the run, naming the case that killed it."""
    try:
        got = parse(raw(port, data, **kw), methods)
    except h11.RemoteProtocolError as e:
        alive(what)
        ck(False, f"{what}: h11 refused the response: {e}")
        return []
    alive(what)
    ck([g[0] for g in got] == want, f"{what}: statuses {[g[0] for g in got]}, want {want}")
    for g in got:
        if g[1] is not None and g[0] >= 200:
            date_ok(g[1].get("date"), what)
    return got


def date_ok(d, what):
    if d is None:
        ck(False, f"{what}: no Date header")
        return
    try:
        t = email.utils.parsedate_to_datetime(d)
    except (TypeError, ValueError):
        ck(False, f"{what}: Date {d!r} does not parse")
        return
    ck(email.utils.format_datetime(t, usegmt=True) == d,
       f"{what}: Date {d!r} is not the IMF-fixdate of the time it names "
       f"({email.utils.format_datetime(t, usegmt=True)!r})")
    now = datetime.datetime.now(datetime.timezone.utc)
    ck(abs((now - t).total_seconds()) < 10, f"{what}: Date {d!r} is not now")


def concat_body(query, path="/concat"):
    return ((query + "@" + path + ";") * 40).encode()


BIG = bytes((i * 7 + 3) % 251 for i in range(1048576))
H = b"Host: x\r\n"

# ---- protocol, on one server ------------------------------------------

P = BASE
# stage 2's files: a directory the server serves under /pub/
DIR = tempfile.mkdtemp(prefix="srvfix-")
atexit.register(shutil.rmtree, DIR, True)
DATA = bytes((i * 31 + 7) % 256 for i in range(300000))
FILES = {
    "data.bin": DATA,
    "empty.txt": b"",
    "page.html": b"<!doctype html><title>t</title>" + b"<p>x</p>" * 300,
    "data.json": b'{"a": 1}',
    "sub/index.html": b"<p>the index</p>",
    "dir/x.txt": b"in a directory",
    ".hidden": b"secret",
    "\u00e9t\u00e9.txt": "summer".encode(),
}
for name, body in FILES.items():
    path = os.path.join(DIR, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(body)

srv = Server(P, "--workers=4", "--queue=64", "--idle=2000", "--headerms=3000", "--dir=" + DIR)
LIVE.append(srv)

g = statuses(P, b"GET /hello HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n",
             ["GET"], "plain GET", [200])
if g:
    ck(g[0][2] == b"hello", f"plain GET: body {g[0][2]!r}")
    ck(g[0][1].get("content-type", "").startswith("text/plain"), "plain GET: Content-Type")
    ck(g[0][1].get("connection") == "close", "plain GET: Connection: close answered")

statuses(P, b"GET /hello HTTP/1.1\r\nConnection: close\r\n\r\n", ["GET"],
         "HTTP/1.1 without Host", [400])
statuses(P, b"GET /hello HTTP/1.1\r\n" + H + H + b"\r\n", ["GET"],
         "two Hosts", [400])
g = statuses(P, b"GET /hello HTTP/1.0\r\n\r\n", ["GET"], "HTTP/1.0 without Host", [200])
if g:
    ck(g[0][1].get("connection") == "close", "HTTP/1.0: the connection is closed")
g = statuses(P, b"GET /hello HTTP/1.0\r\nConnection: keep-alive\r\n\r\n"
                b"GET /static HTTP/1.0\r\n\r\n", ["GET", "GET"],
             "HTTP/1.0 keep-alive", [200, 200])
if len(g) == 2:
    ck(g[0][1].get("connection") == "keep-alive", "HTTP/1.0 keep-alive: answered keep-alive")
    ck(g[1][2] == b"static body", "HTTP/1.0 keep-alive: the second answer")

# pipelining: three requests in one write, answered in order
g = statuses(P, b"".join(b"GET /concat?" + str(k).encode() + b" HTTP/1.1\r\n" + H + b"\r\n"
                         for k in (1, 2)) +
             b"GET /concat?3 HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n",
             ["GET"] * 3, "three pipelined", [200, 200, 200])
if len(g) == 3:
    ck([x[2] for x in g] == [concat_body(str(k)) for k in (1, 2, 3)],
       "three pipelined: bodies in order")

# a body, then a pipelined request behind it
g = statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Content-Length: 5\r\n\r\nhello"
                b"GET /hello HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n",
             ["POST", "GET"], "body then pipelined", [200, 200])
if len(g) == 2:
    ck(g[0][2] == b"hello" and g[1][2] == b"hello", "body then pipelined: both bodies")

# chunked request body, with an extension and a trailer
chunked = (b"POST /echo HTTP/1.1\r\n" + H + b"Transfer-Encoding: chunked\r\n\r\n"
           b"5;name=v\r\nhello\r\n6\r\n world\r\n0\r\nX-Trailer: t\r\n\r\n"
           b"GET /hello HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n")
g = statuses(P, chunked, ["POST", "GET"], "chunked body", [200, 200])
if len(g) == 2:
    ck(g[0][2] == b"hello world", f"chunked body: echoed {g[0][2]!r}")

statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Content-Length: 5\r\n"
            b"Transfer-Encoding: chunked\r\n\r\n0\r\n\r\n", ["POST"],
         "Content-Length and Transfer-Encoding", [400])
statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Content-Length: 1\r\n"
            b"Content-Length: 2\r\n\r\nab", ["POST"], "two different Content-Lengths", [400])
g = statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Content-Length: 2\r\n"
                b"Content-Length: 2\r\nConnection: close\r\n\r\nab", ["POST"],
             "two equal Content-Lengths", [200])
statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Content-Length: abc\r\n\r\n", ["POST"],
         "Content-Length not digits", [400])
statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Content-Length: -1\r\n\r\n", ["POST"],
         "Content-Length negative", [400])
statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Content-Length: +5\r\n\r\nhello", ["POST"],
         "Content-Length with a sign", [400])
statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Transfer-Encoding: gzip, chunked\r\n\r\n",
         ["POST"], "a transfer coding other than chunked", [501])
statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Transfer-Encoding: chunked\r\n\r\n"
            b"zz\r\nhello\r\n0\r\n\r\n", ["POST"], "a chunk size that is not hex", [400])

# Expect: 100-continue -- the 100 first, the body after it
s = socket.create_connection(("127.0.0.1", P), timeout=3)
s.sendall(b"POST /echo HTTP/1.1\r\n" + H + b"Content-Length: 5\r\nExpect: 100-continue\r\n"
          b"Connection: close\r\n\r\n")
first = s.recv(65536)
ck(first.startswith(b"HTTP/1.1 100 Continue\r\n\r\n"), f"Expect: the 100 first: {first[:40]!r}")
s.sendall(b"hello")
rest = first
while True:
    b = s.recv(65536)
    if not b:
        break
    rest += b
s.close()
try:
    g = parse(rest, ["POST"])
    ck([x[0] for x in g] == [100, 200] and g[-1][2] == b"hello",
       f"Expect: 100 then 200 hello: {[x[0] for x in g]}")
except h11.RemoteProtocolError as e:
    ck(False, f"Expect: h11 refused: {e}")
statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Content-Length: 5\r\nExpect: fly\r\n\r\nhello",
         ["POST"], "an Expect other than 100-continue", [417])

# limits
statuses(P, b"GET /hello?" + b"q" * 9000 + b" HTTP/1.1\r\n" + H + b"\r\n", ["GET"],
         "request line over 8 KB", [414])
statuses(P, b"GET /hello HTTP/1.1\r\n" + H + b"X-Big: " + b"a" * 20000 + b"\r\n\r\n",
         ["GET"], "header block over 16 KB", [431])
statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Content-Length: 2000000\r\n\r\n" +
         b"x" * 70000, ["POST"], "body over 1 MB by length", [413])
# the refusal must reach a client that is still sending, as an ordinary
# client sends: http.client writes the whole 2 MB body before it reads.
# A server that closes over the unread body resets the connection, the
# client's write fails, and it never reads the 413 -- which is why the
# server reads the rest and throws it away first (Linger).  raw() above
# reads even after its write failed, so it cannot see this; this can.
try:
    hc = http.client.HTTPConnection("127.0.0.1", P, timeout=5)
    hc.request("POST", "/echo", body=b"z" * 2000000)
    hr = hc.getresponse()
    ck(hr.status == 413, f"a refused body still being sent: {hr.status}")
    hr.read()
    hc.close()
except OSError as e:
    ck(False, f"a refused body still being sent: the client saw {e!r}, not the 413")
alive("a refused body still being sent")
big_chunks = b"".join(b"10000\r\n" + b"y" * 65536 + b"\r\n" for _ in range(20)) + b"0\r\n\r\n"
statuses(P, b"POST /echo HTTP/1.1\r\n" + H + b"Transfer-Encoding: chunked\r\n\r\n" + big_chunks,
         ["POST"], "body over 1 MB in chunks", [413], wait=4.0)

# the request line and the header lines
for what, req, want in [
        ("garbage request line", b"HELLO\r\n\r\n", 400),
        ("two blanks in the request line", b"GET  /hello HTTP/1.1\r\n" + H + b"\r\n", 400),
        ("HTTP/2.0", b"GET /hello HTTP/2.0\r\n" + H + b"\r\n", 505),
        ("HTTP/1.1x", b"GET /hello HTTP/1.1x\r\n" + H + b"\r\n", 400),
        ("folded header", b"GET /hello HTTP/1.1\r\n" + H + b"X-A: 1\r\n  2\r\n\r\n", 400),
        ("blank before the colon", b"GET /hello HTTP/1.1\r\n" + H + b"X-A : 1\r\n\r\n", 400),
        ("header without a colon", b"GET /hello HTTP/1.1\r\n" + H + b"X-A\r\n\r\n", 400),
        ("unknown method", b"BREW /hello HTTP/1.1\r\n" + H + b"\r\n", 501),
        ("target not a path", b"GET hello HTTP/1.1\r\n" + H + b"\r\n", 400)]:
    statuses(P, req, ["GET"], what, [want])

g = statuses(P, b"\r\nGET /hello HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n", ["GET"],
             "an empty line before the request", [200])
g = statuses(P, b"GET /hello HTTP/1.1\n" + b"Host: x\nConnection: close\n\n", ["GET"],
             "bare LF line ends", [200])
g = statuses(P, b"GET http://example.org/files/a?q=1 HTTP/1.1\r\n" + H +
                b"Connection: close\r\n\r\n", ["GET"], "absolute-form target", [200])
if g:
    ck(g[0][2] == b"file /files/a", f"absolute-form: routed on its path: {g[0][2]!r}")

# routing, and what handlers answer
g = statuses(P, b"DELETE /hello HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n", ["DELETE"],
             "a method the path has no route for", [405])
if g:
    ck(g[0][1].get("allow") == "GET, HEAD", f"405: Allow {g[0][1].get('allow')!r}")
statuses(P, b"GET /nowhere HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n", ["GET"],
         "no route", [404])
g = statuses(P, b"HEAD /hello HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n", ["HEAD"],
             "HEAD from the GET route", [200])
if g:
    ck(g[0][1].get("content-length") == "5" and g[0][2] == b"",
       "HEAD: the GET's length, no body")
g = statuses(P, b"GET /files/a/b HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n", ["GET"],
             "prefix route", [200])
if g:
    ck(g[0][2] == b"file /files/a/b", f"prefix route: {g[0][2]!r}")
g = statuses(P, b"GET /probe?x=1 HTTP/1.1\r\n" + H + b"x-PROBE:  abc  \r\n"
                b"Connection: close\r\n\r\n", ["GET"], "Header lookup", [200])
if g:
    ck(g[0][2] == b"x-probe=abc method=GET peer=127.0.0.1 client=127.0.0.1",
       f"Header lookup: {g[0][2]!r}")
for what, path in [("a handler raising ValueRange", b"/raise"),
                   ("a handler raising IndexError", b"/index")]:
    statuses(P, b"GET " + path + b" HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n",
             ["GET"], what, [500])
data = raw(P, b"GET /badheader HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n")
ck(b"Injected" not in data, "a CR LF in a header value reached the wire")
try:
    ck([x[0] for x in parse(data, ["GET"])] == [500], "a malformed header: 500")
except h11.RemoteProtocolError as e:
    ck(False, f"a malformed header: h11 refused: {e}")
g = statuses(P, b"POST /made HTTP/1.1\r\n" + H + b"Content-Length: 0\r\nConnection: close\r\n\r\n",
             ["POST"], "201 with a header", [201])
if g:
    ck(g[0][1].get("location") == "/made/1", "201: Location")
g = statuses(P, b"GET /close HTTP/1.1\r\n" + H + b"\r\nGET /hello HTTP/1.1\r\n" + H + b"\r\n",
             ["GET", "GET"], "a handler asking to close", [200])
if g:
    ck(g[0][1].get("connection") == "close", "a handler asking to close: Connection: close")

# time: a kept connection that falls silent is closed, a header that
# trickles in is refused 408
s = socket.create_connection(("127.0.0.1", P), timeout=6)
s.sendall(b"GET /hello HTTP/1.1\r\n" + H + b"\r\n")
t0 = time.time()
got = b""
while True:
    b = s.recv(65536)
    if not b:
        break
    got += b
s.close()
ck(b"200 OK" in got and 1.5 < time.time() - t0 < 4.0,
   f"idle kept connection closed after {time.time() - t0:.1f} s (idle 2 s)")
t0 = time.time()
req = b"GET /hello HTTP/1.1\r\n" + H + b"\r\n"
g = statuses(P, None, ["GET"], "a header trickling in", [408], wait=8.0,
             chunks=[req[i:i + 1] for i in range(len(req))], gap=0.4)
ck(time.time() - t0 < 6.0, f"a header trickling in: refused after {time.time() - t0:.1f} s")


# ---- stage 2: files with ranges ---------------------------------------
# The expected answers come from RFC 9110 par 14, written here apart
# from the server's own code.


def want_range(h, size):
    """('whole',) / ('part', a, b) / ('416',) for a Range value"""
    if not h.lower().startswith("bytes="):
        return ("whole",)
    spec = h[6:].strip(" \t")
    m = re.fullmatch(r"(\d*)-(\d*)", spec)
    if not m or (m.group(1) == "" and m.group(2) == ""):
        return ("whole",)
    first, last = m.group(1), m.group(2)
    if first == "":
        n = int(last)
        if n == 0 or size == 0:
            return ("416",)
        return ("part", max(0, size - n), size - 1)
    a = int(first)
    b = int(last) if last else None
    if b is not None and b < a:
        return ("whole",)
    if a >= size:
        return ("416",)
    return ("part", a, size - 1 if b is None or b > size - 1 else b)


def get(port, path, extra=b"", method=b"GET"):
    """one request on its own connection: (status, headers, body)"""
    g = parse(raw(port, method + b" " + path + b" HTTP/1.1\r\n" + H + extra +
                  b"Connection: close\r\n\r\n"), [method.decode()])
    alive(path.decode())
    return g[0] if g else (None, {}, b"")


RANGES = ["bytes=0-99", "bytes=100-", "bytes=-500", "bytes=0-0", "bytes=299999-",
          "bytes=-0", "bytes=300000-", "bytes=300000-300010", "bytes=500-400",
          "bytes=0-1,5-6", "items=0-1", "bytes=0-99999999999999999999",
          "bytes=-99999999999999999999", "BYTES=1-2", "bytes= 7-9 ", "bytes=a-b",
          "bytes=-", "bytes=5", "bytes=-1", "bytes=299990-299999"]
for path in (b"/pub/data.bin", b"/onefile"):
    for h in RANGES:
        st, hd, body = get(P, path, b"Range: " + h.encode() + b"\r\n")
        w = want_range(h, len(DATA))
        what = f"{path.decode()} Range {h!r}"
        if w[0] == "whole":
            ck(st == 200 and body == DATA, f"{what}: the whole file, got {st} and {len(body)} octets")
        elif w[0] == "416":
            ck(st == 416 and hd.get("content-range") == f"bytes */{len(DATA)}",
               f"{what}: 416 with bytes */{len(DATA)}, got {st} {hd.get('content-range')}")
        else:
            a, b = w[1], w[2]
            ck(st == 206 and body == DATA[a:b + 1] and
               hd.get("content-range") == f"bytes {a}-{b}/{len(DATA)}",
               f"{what}: 206 {a}-{b}, got {st} {hd.get('content-range')} and {len(body)} octets")
        if st in (200, 206):
            ck(hd.get("accept-ranges") == "bytes", f"{what}: Accept-Ranges: bytes")
            ck(hd.get("content-length") == str(len(body)), f"{what}: Content-Length is the body's")
            ck("content-encoding" not in hd, f"{what}: a file is never gzipped")
st, hd, body = get(P, b"/pub/data.bin", b"Range: bytes=0-9\r\n", b"HEAD")
ck(st == 200 and body == b"" and hd.get("content-length") == str(len(DATA)),
   f"HEAD ignores Range: {st}, length {hd.get('content-length')}")
st, hd, body = get(P, b"/pub/data.bin", b"Range: bytes=0-9\r\nIf-Range: \"x\"\r\n")
ck(st == 200 and body == DATA, f"Range with If-Range: the whole file, got {st}")
st, hd, body = get(P, b"/pub/empty.txt")
ck(st == 200 and body == b"" and hd.get("content-length") == "0", f"an empty file: {st}")
for h in ("bytes=0-0", "bytes=-1", "bytes=0-"):
    st, hd, body = get(P, b"/pub/empty.txt", b"Range: " + h.encode() + b"\r\n")
    ck(st == 416 and hd.get("content-range") == "bytes */0", f"empty file, Range {h}: {st}")
st, hd, body = get(P, b"/gone")
ck(st == 404, f"ReplyFile of a file that is not there: {st}")

# ---- stage 2: what /pub/ names ----------------------------------------
for path, want, ctype in ((b"/pub/page.html", FILES["page.html"], "text/html; charset=utf-8"),
                          (b"/pub/data.json", FILES["data.json"], "application/json"),
                          (b"/pub/sub/", FILES["sub/index.html"], "text/html; charset=utf-8"),
                          (b"/pub/dir/x.txt", FILES["dir/x.txt"], "text/plain; charset=utf-8"),
                          (b"/pub/%C3%A9t%C3%A9.txt", FILES["\u00e9t\u00e9.txt"],
                           "text/plain; charset=utf-8"),
                          (b"/pub/data.bin", DATA, "application/octet-stream")):
    if WINE and b"%C3" in path:
        # Io's paths are octets and Windows reads a narrow path in the
        # ANSI code page, not UTF-8: a library-wide Windows gap (m9rt
        # opens with fopen), owed, not this server's
        print("srvfix: SKIP under wine: a UTF-8 file name (Io's Windows paths are ANSI)",
              file=sys.stderr)
        continue
    st, hd, body = get(P, path, b"Accept-Encoding: gzip\r\n")
    ck(st == 200 and body == want and hd.get("content-type") == ctype and
       hd.get("x-content-type-options") == "nosniff" and "content-encoding" not in hd,
       f"{path.decode()}: 200, the file, {ctype}, not gzipped; got {st} {hd.get('content-type')}")
for path in (b"/pub/../srvfix.py", b"/pub/%2e%2e/x", b"/pub/.hidden", b"/pub/%2Ehidden",
             b"/pub/sub/../data.bin", b"/pub//data.bin", b"/pub/a%00b", b"/pub/%ff",
             b"/pub/dir", b"/pub/dir/", b"/pub/nothing", b"/pub/sub%5c..%5cdata.bin",
             b"/pub/c:x", b"/pub/data.bin/"):
    st, hd, body = get(P, path)
    ck(st == 404, f"{path.decode()}: 404, got {st}")
st, hd, body = get(P, b"/pub/data.bin", method=b"POST")
ck(st == 405 and hd.get("allow") == "GET, HEAD", f"POST to /pub/: {st} Allow {hd.get('allow')}")
st, hd, body = get(P, b"/pub/page.html", method=b"HEAD")
ck(st == 200 and body == b"" and hd.get("content-length") == str(len(FILES["page.html"])),
   f"HEAD of a file: {st}, length {hd.get('content-length')}")

# ---- stage 2: gzip, by RFC 9110 par 12.5.3 ----------------------------


def want_gzip(ae):
    """does this Accept-Encoding take gzip?  Written apart from the server"""
    if ae is None:
        return False
    gz = star = None
    for el in ae.split(","):
        parts = [x.strip() for x in el.split(";")]
        coding = parts[0].lower()
        q = 1.0
        for prm in parts[1:]:
            if prm.lower().startswith("q="):
                v = prm[2:]
                q = float(v) if re.fullmatch(r"0(\.\d{0,3})?|1(\.0{0,3})?", v) else 0.0
        if coding in ("gzip", "x-gzip"):
            gz = q > 0
        elif coding == "*":
            star = q > 0
    return gz if gz is not None else bool(star)


TEXT = "".join(f"line {k} of the text body\n" for k in range(100)).encode()
AES = [None, "", "gzip", "GZIP", "x-gzip", "gzip;q=0", "gzip;q=0.000", "gzip;q=0.001",
       "gzip; q=1", "gzip;q=1.000", "gzip;q=1.5", "*", "*;q=0", "gzip;q=0, *",
       "deflate, br", "identity", "br, gzip", "gzip;q=bad", "identity;q=1, *;q=0.5"]
sizes = set()
for ae in AES:
    extra = b"" if ae is None else b"Accept-Encoding: " + ae.encode() + b"\r\n"
    st, hd, body = get(P, b"/text", extra)
    what = f"/text with Accept-Encoding {ae!r}"
    ck(hd.get("vary") == "Accept-Encoding", f"{what}: Vary: Accept-Encoding")
    if want_gzip(ae):
        ok = hd.get("content-encoding") == "gzip"
        try:
            ok = ok and gzip.decompress(body) == TEXT
        except OSError:
            ok = False
        ck(ok, f"{what}: gzipped, and Python's gzip reads it back")
        sizes.add(body)
    else:
        ck("content-encoding" not in hd and body == TEXT, f"{what}: the text as it is")
ck(len(sizes) == 1, f"the same body gzips to the same octets: {len(sizes)} forms")
ck(len(next(iter(sizes), b"x" * 9999)) < len(TEXT) // 3, "gzip makes the text body smaller")
st, hd, body = get(P, b"/text", b"Accept-Encoding: gzip\r\n", b"HEAD")
ck(st == 200 and body == b"" and hd.get("content-encoding") == "gzip" and
   hd.get("content-length") == str(len(next(iter(sizes), b""))),
   f"HEAD /text with gzip: the length GET sends, got {hd.get('content-length')}")
st, hd, body = get(P, b"/json", b"Accept-Encoding: gzip\r\n")
ck(hd.get("content-encoding") == "gzip", f"/json gzipped: {hd.get('content-encoding')}")
for path, why in ((b"/hello", "too short"), (b"/png", "an image"), (b"/preenc", "encoded already")):
    st, hd, body = get(P, path, b"Accept-Encoding: gzip\r\n")
    ck(hd.get("content-encoding") in (None, "br") and "vary" not in hd and
       (path != b"/preenc" or hd.get("content-encoding") == "br"),
       f"{path.decode()} ({why}): not gzipped and no Vary, got {hd.get('content-encoding')} {hd.get('vary')}")

# ---- stage 2: streams ------------------------------------------------


def stream_body(n, pad=0):
    return "".join(f"part {k} " + "x" * pad + "\n" for k in range(n)).encode()


for n in (100, 0, 1, 2500):
    st, hd, body = get(P, f"/stream?n={n}".encode())
    ck(st == 200 and hd.get("transfer-encoding") == "chunked" and "content-length" not in hd
       and body == stream_body(n), f"/stream n={n}: chunked, every part, got {st} and {len(body)} octets")
g = statuses(P, b"GET /stream?n=3 HTTP/1.1\r\n" + H + b"\r\n" +
             b"GET /hello HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n",
             ["GET", "GET"], "a stream, then a request on the same connection", [200, 200])
if len(g) == 2:
    ck(g[0][2] == stream_body(3) and g[1][2] == b"hello", "the stream and the next answer, both whole")
st, hd, body = get(P, b"/stream?n=5", method=b"HEAD")
ck(st == 200 and body == b"" and hd.get("transfer-encoding") == "chunked",
   f"HEAD of a stream: its head and no body, got {st} {hd.get('transfer-encoding')}")
out = raw(P, b"GET /stream?n=40 HTTP/1.0\r\nConnection: keep-alive\r\n\r\n")
head_, _, body = out.partition(b"\r\n\r\n")
ck(head_.startswith(b"HTTP/1.1 200") and b"transfer-encoding" not in head_.lower() and
   b"connection: close" in head_.lower() and b"content-length" not in head_.lower()
   and body == stream_body(40),
   "a stream to HTTP/1.0: no length, Connection: close, the close ends it")
out = raw(P, b"GET /streamfail HTTP/1.1\r\n" + H + b"\r\n")
ck(b"part 2\n" in out and not out.endswith(b"0\r\n\r\n"),
   "a producer that raises: the body is cut short, no last chunk")
alive("a producer that raises")


def rss_kb(pid):
    """the PEAK resident size: a buffer read whole and freed by the time
    the request is done leaves VmRSS where it was, and VmHWM high"""
    for line in open(f"/proc/{pid}/status"):
        if line.startswith("VmHWM:"):
            return int(line.split()[1])
    return 0


if os.path.exists(f"/proc/{srv.pid()}/status"):
    proc_rss_ = rss_kb
    r0 = proc_rss_(srv.pid())
    st, hd, body = get(P, b"/stream?n=200000&pad=200")
    r1 = proc_rss_(srv.pid())
    ck(body == stream_body(200000, 200), f"a 41 MB stream, every part: {len(body)} octets")
    ck(r1 - r0 < 16384, f"a 41 MB stream does not stay in memory: peak RSS {r0} -> {r1} KB")
    big_ = DIR + "/big.bin"
    with open(big_, "wb") as f:
        for k in range(64):
            f.write(DATA[:262144] * 3)
    st, hd, body = get(P, b"/pub/big.bin")
    r2 = proc_rss_(srv.pid())
    ck(st == 200 and len(body) == 64 * 3 * 262144, f"a 50 MB file: {st}, {len(body)} octets")
    ck(r2 - r1 < 16384, f"a 50 MB file is not read whole: peak RSS {r1} -> {r2} KB")
    print(f"srvfix: a 41 MB stream and a 50 MB file: peak RSS {r0} -> {r1} -> {r2} KB", file=sys.stderr)
else:
    print("srvfix: SKIP the memory checks of a stream and a file (no /proc)", file=sys.stderr)


# ---- load: byte-verified, with descriptors and memory watched -------

def proc_fds(pid):
    try:
        return len(os.listdir(f"/proc/{pid}/fd"))
    except OSError:
        return None


def proc_rss(pid):
    try:
        for line in open(f"/proc/{pid}/status"):
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
    except OSError:
        return None
    return None


lock = threading.Lock()
load = {"bad": 0, "err": 0, "n": 0}


def client(k, per):
    c = http.client.HTTPConnection("127.0.0.1", P, timeout=10)
    bad = err = n = 0
    for i in range(per):
        kind = (k + i) % 4
        try:
            if kind == 0:
                q = f"{k}.{i}"
                c.request("GET", "/concat?" + q)
                want = concat_body(q)
            elif kind == 1:
                c.request("GET", "/big")
                want = BIG
            elif kind == 2:
                body = bytes((k * 31 + i * 17 + j) % 256 for j in range((k * 997 + i * 131) % 70000))
                c.request("POST", "/echo", body=body)
                want = body
            else:
                c.request("GET", "/hello")
                want = b"hello"
            r = c.getresponse()
            got = r.read()
            n += 1
            if r.status != 200 or got != want:
                bad += 1
        except (OSError, http.client.HTTPException):
            err += 1
            c.close()
            c = http.client.HTTPConnection("127.0.0.1", P, timeout=10)
    c.close()
    with lock:
        load["bad"] += bad
        load["err"] += err
        load["n"] += n


def round_(per):
    ts = [threading.Thread(target=client, args=(k, per)) for k in range(8)]
    t0 = time.time()
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    return time.time() - t0


pid = srv.p.pid
fd0, rss0 = proc_fds(pid), proc_rss(pid)
dt1 = round_(200)
time.sleep(2.5)                     # past the idle timeout: every kept connection closed
fd1, rss1 = proc_fds(pid), proc_rss(pid)
dt2 = round_(200)
time.sleep(2.5)
fd2, rss2 = proc_fds(pid), proc_rss(pid)
ck(load["bad"] == 0 and load["err"] == 0,
   f"load: {load['bad']} wrong bodies, {load['err']} transport errors in {load['n']}")
ck(load["n"] == 3200, f"load: {load['n']} answers, want 3200")
print(f"srvfix: load {load['n']} requests in {dt1:.2f} s + {dt2:.2f} s "
      f"(8 clients, a quarter of them 1 MB)", file=sys.stderr)
if fd0 is not None:
    ck(fd1 == fd0 and fd2 == fd0, f"load: descriptors {fd0} -> {fd1} -> {fd2}")
    ck(rss2 <= rss1 * 1.10 + 8192,
       f"load: resident memory grew between two equal rounds: {rss1} -> {rss2} KB")
    print(f"srvfix: descriptors {fd0} -> {fd1} -> {fd2}, RSS {rss0} -> {rss1} -> {rss2} KB",
          file=sys.stderr)
else:
    print("srvfix: SKIP descriptor and memory checks (no /proc)", file=sys.stderr)
alive("the load")
LIVE.remove(srv)
srv.stop()

# ---- a full queue answers 503 ----------------------------------------

P2 = BASE + 1
b2 = Server(P2, "--workers=1", "--queue=1", "--idle=2000")
# Server's readiness probe is a connection too, and on a slow machine it
# can still hold the one queue place when the first slow request comes
# (CI, 2026-10-07: [503, 200, 200]).  A quick request answered 200 comes
# after the probe through the one worker, so the queue is empty after it.
t0 = time.time()
while True:
    q = socket.create_connection(("127.0.0.1", P2), timeout=5)
    q.sendall(b"GET /hello HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n")
    first = b""
    while True:
        try:
            b = q.recv(65536)
        except ConnectionResetError:
            break
        if not b:
            break
        first += b
    q.close()
    if first.startswith(b"HTTP/1.1 200 ") or time.time() - t0 > 5:
        break
    time.sleep(0.05)
ck(first.startswith(b"HTTP/1.1 200 "), "one worker: a quick request is answered before the queue test")
socks = []
for i in range(3):
    s = socket.create_connection(("127.0.0.1", P2), timeout=5)
    s.sendall(b"GET /slow HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n")
    socks.append(s)
    time.sleep(0.1)
answers = []
for s in socks:
    got = b""
    while True:
        try:
            b = s.recv(65536)
        except ConnectionResetError:
            got += b"(reset)"
            break
        if not b:
            break
        got += b
    s.close()
    answers.append(got.split(b"\r\n", 1)[0])
ck(answers == [b"HTTP/1.1 200 OK", b"HTTP/1.1 200 OK", b"HTTP/1.1 503 Service Unavailable"],
   f"one worker, a queue of one: {answers}")
b2.stop()

# ---- a connection limit drains the server and its counts add up -----

P3 = BASE + 2
# the readiness probe is the first connection and sends nothing: seven
# connections, six requests
b3 = Server(P3, "--workers=2", "--max=7")
for path in (b"/hello", b"/raise", b"/index", b"/badheader", b"/static", b"/nowhere"):
    raw(P3, b"GET " + path + b" HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n")
code, out = b3.finish()
ck(code == 0, f"--max=7: exit {code}: {out!r}")
stats = dict(kv.split("=") for kv in out.split("stats", 1)[-1].split()) if "stats" in out else {}
want = {"why": "0", "connections": "7", "busy": "0", "requests": "6", "faults": "3",
        "s2xx": "2", "s4xx": "1", "s5xx": "3"}
ck(stats == want, f"--max=7: counts {stats}, want {want}")
ck("frozen: /late" in out, "AddRoute after Freeze raised Frozen")

# ---- the per-connection limit closes the third response --------------

P4 = BASE + 3
b4 = Server(P4, "--perconn=3")
g = statuses(P4, (b"GET /hello HTTP/1.1\r\n" + H + b"\r\n") * 4, ["GET"] * 4,
             "three requests a connection", [200, 200, 200])
if len(g) == 3:
    ck(g[2][1].get("connection") == "close" and "connection" not in g[1][1],
       "three requests a connection: the third says close")
b4.stop()

# ---- stage 3: operations ---------------------------------------------


def stats_of(out):
    return dict(kv.split("=") for kv in out.split("stats", 1)[-1].split()) if "stats" in out else {}


def recv_until(sk, mark, wait=5.0):
    sk.settimeout(wait)
    got = bytearray()
    while mark not in got:
        b = sk.recv(65536)
        if not b:
            break
        got += b
    return bytes(got)


# SIGTERM while a request is in flight and a kept connection is idle:
# the request is answered whole, with Connection: close; the idle
# connection is closed within half a second; Run returns Stopped (4)
P5 = BASE + 4
b5 = Server(P5, "--workers=2", "--idle=5000")
kc = socket.create_connection(("127.0.0.1", P5), timeout=5)
kc.sendall(b"GET /hello HTTP/1.1\r\n" + H + b"\r\n")
ck(recv_until(kc, b"hello").endswith(b"hello"), "SIGTERM: the kept connection's first answer")
slow_out = {}
th = threading.Thread(target=lambda: slow_out.setdefault(
    "r", raw(P5, b"GET /slow HTTP/1.1\r\n" + H + b"\r\n", wait=5.0)))
th.start()
time.sleep(0.1)
t0 = time.time()
os.kill(b5.pid(), STOPSIG)
kc.settimeout(3.0)
try:
    tail = kc.recv(65536)
except OSError:
    tail = b""
ck(tail == b"" and time.time() - t0 < 0.6,
   f"SIGTERM: the idle kept connection closed after {time.time() - t0:.2f} s (idle 5 s)")
kc.close()
th.join()
r = slow_out.get("r", b"")
ck(r.startswith(b"HTTP/1.1 200") and r.endswith(b"slow") and b"connection: close" in r.lower(),
   f"SIGTERM: the request in flight answered whole, with Connection: close: {r[-60:]!r}")
code, out = b5.finish(timeout=5)
ck(code == 0 and stats_of(out).get("why") == "4" and time.time() - t0 < 2.0,
   f"SIGTERM: Run returned Stopped within 2 s: exit {code}, {stats_of(out)}, {time.time() - t0:.2f} s")
try:
    socket.create_connection(("127.0.0.1", P5), timeout=1).close()
    ck(False, "SIGTERM: the port is closed after Run returned")
except OSError:
    pass

# SIGTERM in the middle of a load: no answered request is lost -- every
# response a client got is whole, and their number is the server's count
P6 = BASE + 5
b6 = Server(P6, "--workers=4", "--queue=64")
whole = []
broken = []


def loader(k):
    n = 0
    while True:
        try:
            out = raw(P6, b"GET /concat?k" + str(k).encode() + b"n" + str(n).encode() +
                      b" HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n", wait=3.0)
        except OSError:
            return
        if not out:
            return
        try:
            g = parse(out, ["GET"])
        except h11.RemoteProtocolError:
            broken.append(out[:80])
            return
        q = f"k{k}n{n}"
        if g and g[0][0] == 200 and g[0][2] == concat_body(q):
            whole.append(q)
        elif g and g[0][0] == 503:
            pass
        else:
            broken.append(out[:80])
        n += 1


ths = [threading.Thread(target=loader, args=(k,)) for k in range(6)]
for t_ in ths:
    t_.start()
time.sleep(0.8)
os.kill(b6.pid(), STOPSIG)
for t_ in ths:
    t_.join()
code, out = b6.finish(timeout=10)
st6 = stats_of(out)
ck(not broken, f"SIGTERM under load: every response whole ({len(broken)} broken: {broken[:2]})")
ck(code == 0 and st6.get("why") == "4" and int(st6.get("s2xx", -1)) == len(whole),
   f"SIGTERM under load: the server answered {st6.get('s2xx')} and the clients have {len(whole)}")
print(f"srvfix: SIGTERM under load: {len(whole)} answers, none lost", file=sys.stderr)

# Stop from a handler
P7 = BASE + 6
b7 = Server(P7)
g = statuses(P7, b"POST /stop HTTP/1.1\r\n" + H + b"Content-Length: 0\r\n\r\n", ["POST"],
             "Stop from a handler", [200])
code, out = b7.finish(timeout=5)
ck(code == 0 and stats_of(out).get("why") == "4", f"Stop from a handler: Run returned {stats_of(out)}")

# the bind address: numeric only; :: and 0.0.0.0 take loopback clients;
# ::1 takes v6 alone
P8 = BASE + 7
for bind, host, other in (("0.0.0.0", "127.0.0.1", None), ("::", "::1", "127.0.0.1"),
                          ("::1", "::1", "127.0.0.1")):
    try:
        b8 = Server(P8, "--bind=" + bind, host=host)
    except SystemExit as e:
        ck(False, f"--bind={bind}: {e}")
        continue
    ok = True
    if other:
        try:
            socket.create_connection((other, P8), timeout=1).close()
            reached = True
        except OSError:
            reached = False
        ok = reached == (bind == "::")
    ck(ok, f"--bind={bind}: {other} {'reaches' if bind == '::' else 'does not reach'} it")
    b8.stop()
pl = subprocess.Popen([*WRAP, BIN, f"--port={P8}", "--bind=localhost"],
                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
try:
    pout = pl.communicate(timeout=60)[0]
except subprocess.TimeoutExpired:
    pl.kill()
    pout = pl.communicate()[0]
    pout += " (it listened, and was killed)"
ck(stats_of(pout).get("why") == "1", f"--bind=localhost (a name): ListenFail, got {pout[-120:]!r}")

# X-Forwarded-For believed only from a trusted proxy
P9 = BASE + 8
b9 = Server(P9, "--trusted=127.0.0.1, 10.9.9.9")
for xff, want in ((None, "127.0.0.1"), ("203.0.113.9", "203.0.113.9"),
                  ("203.0.113.9, 127.0.0.1", "203.0.113.9"),
                  ("198.51.100.1, 203.0.113.9", "203.0.113.9"),
                  ("203.0.113.9, 10.9.9.9", "203.0.113.9"),
                  ("2001:db8::1", "2001:db8::1"), ("x y", "127.0.0.1"),
                  ("203.0.113.9, nonsense", "127.0.0.1")):
    extra = b"" if xff is None else b"X-Forwarded-For: " + xff.encode() + b"\r\n"
    st_, hd_, body_ = get(P9, b"/probe", extra)
    ck(body_.endswith(b" client=" + want.encode()),
       f"trusted proxy, X-Forwarded-For {xff!r}: client {body_.split(b'client=')[-1]!r}, want {want}")
b9.stop()

# the access log: one whole line a request, every worker logging at once
P10 = BASE + 9
b10 = Server(P10, "--log", "--workers=4")


def logger_client(k):
    for n in range(50):
        raw(P10, b"GET /concat?L" + str(k).encode() + b"_" + str(n).encode() +
            b" HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n")


ths = [threading.Thread(target=logger_client, args=(k,)) for k in range(8)]
for t_ in ths:
    t_.start()
for t_ in ths:
    t_.join()
raw(P10, b"GET /hello HTTP/1.1\r\n" + H + b"Connection: close\r\n\r\n")
raw(P10, b"BAD\r\n\r\n")
st_, hd_, body_ = get(P10, b"/probe", b"X-Forwarded-For: 203.0.113.9\r\n")
ck(body_.endswith(b" client=127.0.0.1"), f"no trusted proxy: X-Forwarded-For ignored: {body_!r}")
out = b10.stop()
LINE = re.compile(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z INFO http method=(\S+) path=(\S+) "
                  r"status=(\d+) bytes=(\d+) ms=(\d+) client=(\S+) worker=([0-3])")
lines = [l for l in out.splitlines() if " http " in l or "INFO" in l]
good = [LINE.fullmatch(l) for l in lines]
ck(all(good) and len(lines) == 403,
   f"access log: {len(lines)} lines, want 403, all whole: {[l for l, m in zip(lines, good) if not m][:2]}")
ms_ = [m.groups() for m in good if m]
ck(sum(1 for g_ in ms_ if g_[1].startswith("/concat") and g_[2] == "200") == 400,
   "access log: the 400 concatenations, 200 each")
ck(("GET", "/hello", "200", "5") in [g_[:4] for g_ in ms_], "access log: /hello sent 5 octets")
ck(("-", "-", "400") in [g_[:3] for g_ in ms_], "access log: a refusal is logged too")
ck(len(set(g_[6] for g_ in ms_)) > 1, "access log: more than one worker wrote")

print(f"srvfix: {'PASS' if not fails else 'FAIL'} "
      f"({checks} checks{'' if not fails else ', ' + str(len(fails)) + ' failed'})")
sys.exit(1 if fails else 0)
