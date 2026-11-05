#!/usr/bin/env python3
"""crashload BIN PORT -- HttpServer serves on while handlers crash (stage 5
of docs/task-plan.md).

It starts BIN (SrvFix) with a task per connection.  First the baseline:
four clients ask GET /hello on kept connections, timing every answer.
Then the same four while two more clients crash handlers all the time:
/index raises an IndexError in its handler, and /countcrash crashes inside
the shared Counter monitor, which poisons it.  Every /hello must still be
a 200; every crash a 500; and /count, asked after a crash, must answer
"count 1": the handler met Poisoned, rebuilt the Counter with its [RESET]
procedure, and counted again from zero.

Prints the /hello latencies, p50 and p99, for both phases, the crashes
served, and `crashload: PASS` or `crashload: FAIL`; exits 0 or 1.  The
latencies are printed, not held: they depend on the machine."""
import socket
import subprocess
import sys
import threading
import time

BIN, PORT = sys.argv[1], int(sys.argv[2])
CLIENTS, ASKS = 4, 1500
fails = []


def ck(ok, what):
    if not ok:
        fails.append(what)
        print("FAIL:", what, flush=True)


def answer(s):
    """(status line, body) of one response with a Content-Length."""
    buf = b""
    while b"\r\n\r\n" not in buf:
        b = s.recv(65536)
        if not b:
            return None, b""
        buf += b
    head, _, body = buf.partition(b"\r\n\r\n")
    ln = 0
    for line in head.split(b"\r\n")[1:]:
        k, _, v = line.partition(b":")
        if k.strip().lower() == b"content-length":
            ln = int(v)
    while len(body) < ln:
        b = s.recv(65536)
        if not b:
            break
        body += b
    return head.split(b"\r\n")[0], body


def ask(s, path, close=False):
    s.sendall(b"GET " + path + b" HTTP/1.1\r\nHost: x\r\n"
              + (b"Connection: close\r\n" if close else b"") + b"\r\n")
    return answer(s)


def once(path):
    s = socket.create_connection(("127.0.0.1", PORT), timeout=10)
    try:
        return ask(s, path, True)
    finally:
        s.close()


def hello_client(lat, bad):
    s = socket.create_connection(("127.0.0.1", PORT), timeout=10)
    for _ in range(ASKS):
        t0 = time.perf_counter()
        st, body = ask(s, b"/hello")
        lat.append(time.perf_counter() - t0)
        if st != b"HTTP/1.1 200 OK":
            bad.append(st)
            s.close()
            s = socket.create_connection(("127.0.0.1", PORT), timeout=10)
    s.close()


def crasher(stop, path, counts):
    while not stop.is_set():
        st, _ = once(path)
        counts.append(st)


def phase(crashing):
    lat, bad, counts = [], [], []
    stop = threading.Event()
    crashers = []
    if crashing:
        crashers = [threading.Thread(target=crasher, args=(stop, p, counts))
                    for p in (b"/index", b"/countcrash")]
        for t in crashers:
            t.start()
    hs = [threading.Thread(target=hello_client, args=(lat, bad)) for _ in range(CLIENTS)]
    for t in hs:
        t.start()
    for t in hs:
        t.join()
    stop.set()
    for t in crashers:
        t.join()
    lat.sort()
    return lat, bad, counts


def pct(lat, p):
    return lat[min(len(lat) - 1, int(len(lat) * p))] * 1e6


# perconn: a kept connection asks 1,500 times, past SrvFix's 1,000
p = subprocess.Popen([BIN, f"--port={PORT}", "--tasks", "--workers=8", "--idle=60000",
                      "--backlog=1024", "--perconn=100000"],
                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
for _ in range(200):
    try:
        socket.create_connection(("127.0.0.1", PORT), timeout=1).close()
        break
    except OSError:
        time.sleep(0.05)

# the Counter's way back, alone first
ck(once(b"/count") == (b"HTTP/1.1 200 OK", b"count 1"), "a fresh Counter counts 1")
ck(once(b"/count") == (b"HTTP/1.1 200 OK", b"count 2"), "then 2")
st, _ = once(b"/countcrash")
ck(st == b"HTTP/1.1 500 Internal Server Error", f"a crash inside the Counter is a 500: {st}")
ck(once(b"/count") == (b"HTTP/1.1 200 OK", b"count 1"),
   "after the crash the Counter is rebuilt from zero: count 1")

lat0, bad0, _ = phase(False)
lat1, bad1, counts = phase(True)
ck(not bad0, f"every /hello is a 200 in the baseline: {bad0[:3]}")
ck(not bad1, f"every /hello is a 200 while handlers crash: {bad1[:3]}")
crashes = len(counts)
ck(crashes > 0 and all(c == b"HTTP/1.1 500 Internal Server Error" for c in counts),
   f"every crash is a 500 ({crashes} crashes, {len(set(counts))} kinds of answer)")
st, body = once(b"/count")
ck(st == b"HTTP/1.1 200 OK" and body.startswith(b"count "), f"the Counter answers after the load: {st} {body}")

p.terminate()
try:
    out = p.communicate(timeout=20)[0].decode()
except subprocess.TimeoutExpired:
    p.kill()
    out = ""
    ck(False, "the server did not stop within 20 s of SIGTERM")
ck("why=4" in out, f"the server returned Stopped: {out.strip().splitlines()[-1:]}")
print(f"crashload: /hello p50 {pct(lat0, 0.5):.0f} us, p99 {pct(lat0, 0.99):.0f} us alone; "
      f"p50 {pct(lat1, 0.5):.0f} us, p99 {pct(lat1, 0.99):.0f} us beside {crashes} crashes "
      f"({CLIENTS} x {ASKS} each)", flush=True)
if fails:
    print("crashload: the server said:", out.strip().splitlines()[-5:])
print(f"crashload: {'PASS' if not fails else 'FAIL'}")
sys.exit(1 if fails else 0)
