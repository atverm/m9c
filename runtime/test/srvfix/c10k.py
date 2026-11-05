#!/usr/bin/env python3
"""c10k BIN PORT N -- HttpServer with a task per connection holds N kept
connections open at once (stage 3 of docs/task-plan.md).

It starts BIN (SrvFix) with --tasks, room for N connections and a long
idle limit.  It opens N connections and sends a request on each.  Every
answer must come back whole, with every connection still open.  Then
it reads the server's resident memory and threads, and asks once more
on every connection, so none was closed meanwhile.  The answers are
read in the order sent, and the server answers them all at once.

Prints the counts and the memory, and `c10k: PASS` or `c10k: FAIL`;
exits 0 or 1.  Plain Python, no h11: the RFC checks are srvfix.py's."""
import os
import resource
import socket
import subprocess
import sys
import time

BIN, PORT, N = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])

# The client's N descriptors here, and the server's N, which it inherits
# this limit for.
soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
want = N + 256
if soft < want:
    resource.setrlimit(resource.RLIMIT_NOFILE, (min(want, hard), hard))

# The backlog is a task server's: with 128, Linux dropped SYNs while a
# fresh server made its first stacks, and each drop cost the client a
# second (ct121, 2026-11-02: 10,000 answers in 73 s, 0.5 s with 4096).
p = subprocess.Popen([BIN, f"--port={PORT}", "--tasks", f"--maxopen={N + 16}",
                      "--workers=8", "--idle=120000", "--perconn=1000", "--backlog=4096"],
                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
for _ in range(200):
    try:
        socket.create_connection(("127.0.0.1", PORT), timeout=1).close()
        break
    except OSError:
        time.sleep(0.05)

fails = []


def ck(ok, what):
    if not ok:
        fails.append(what)
        print("FAIL:", what, flush=True)


def ask(s, k, n):
    s.sendall(b"GET /concat?c%dn%d HTTP/1.1\r\nHost: x\r\n\r\n" % (k, n))


def answer(s):
    """One response with a Content-Length; None when the server closed."""
    buf = b""
    while b"\r\n\r\n" not in buf:
        b = s.recv(65536)
        if not b:
            return None
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
            return None
        body += b
    return head.split(b"\r\n")[0], body


def server_mem():
    """Resident KB and threads of the server, from /proc or ps."""
    try:
        st = open(f"/proc/{p.pid}/status").read().split("\n")
        rss = next(int(l.split()[1]) for l in st if l.startswith("VmRSS:"))
        thr = next(int(l.split()[1]) for l in st if l.startswith("Threads:"))
        return rss, thr
    except OSError:
        rss = int(subprocess.run(["ps", "-o", "rss=", "-p", str(p.pid)],
                                 capture_output=True, text=True).stdout.strip() or 0)
        thr = len(subprocess.run(["ps", "-M", "-p", str(p.pid)],
                                 capture_output=True, text=True).stdout.splitlines()) - 1
        return rss, thr


# The carriers start with the first task, so the baseline is taken
# after one request has been answered.
w0 = socket.create_connection(("127.0.0.1", PORT), timeout=30)
ask(w0, -1, 0)
answer(w0)
w0.close()
time.sleep(0.2)
rss0, thr0 = server_mem()
t0 = time.time()
socks = []
try:
    for k in range(N):
        s = socket.create_connection(("127.0.0.1", PORT), timeout=30)
        socks.append(s)
        ask(s, k, 0)
except OSError as e:
    ck(False, f"connection {len(socks)} of {N}: {e}")
good = 0
for k, s in enumerate(socks):
    try:
        a = answer(s)
    except OSError:
        a = None
    if a and a[0] == b"HTTP/1.1 200 OK":
        good += 1
t1 = time.time()
ck(good == N, f"{good} of {N} kept connections answered the first time")
rss1, thr1 = server_mem()
# Ask again on all of them: none was closed while the others were
# served.
for k, s in enumerate(socks):
    try:
        ask(s, k, 1)
    except OSError:
        pass
again = 0
for s in socks:
    try:
        a = answer(s)
    except OSError:
        a = None
    if a and a[0] == b"HTTP/1.1 200 OK":
        again += 1
t2 = time.time()
ck(again == N, f"{again} of {N} still open and answered the second time")
for s in socks:
    s.close()
p.terminate()
try:
    out = p.communicate(timeout=20)[0].decode()
except subprocess.TimeoutExpired:
    p.kill()
    out = ""
    ck(False, "the server did not stop within 20 s of SIGTERM")
# A task's stack and its connection's buffers, not a thread each: 49 KB
# a connection on the M4 (2026-11-02).  The bound catches a leak or a
# stack per connection grown tenfold.
ck((rss1 - rss0) / max(N, 1) < 128, f"under 128 KB a connection: {(rss1 - rss0) / max(N, 1):.1f} KB")
ck(thr1 <= thr0 + 2, f"no thread a connection: {thr0} -> {thr1}")
ck("why=4" in out, f"the server returned Stopped: {out.strip().splitlines()[-1:]}")
print(f"c10k: {N} connections open at once, {N} answers in {t1 - t0:.1f} s, "
      f"{again} again in {t2 - t1:.1f} s", flush=True)
print(f"c10k: server resident {rss0 / 1024:.0f} MB idle, {rss1 / 1024:.0f} MB with {N} open "
      f"({(rss1 - rss0) / max(N, 1):.1f} KB a connection); threads {thr0} -> {thr1}", flush=True)
print(f"c10k: {'PASS' if not fails else 'FAIL'}")
sys.exit(1 if fails else 0)
