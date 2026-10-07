#!/usr/bin/env python3
"""sabotage M9C PYTHON -- shows the httpserver gate able to fail.

Each entry below is one small edit to a COPY of corpus/HttpServer.m9
that breaks one property the gate claims to hold.  For each: build
SrvFix against the copy, run srvfix.py, and require it to FAIL.  A
sabotage the gate passes is a property the gate does not hold, and
this script exits 1 naming it.

Not run by CI (forty-seven builds and runs take most of an hour); run it after
changing HttpServer or srvfix.py, from runtime/test/srvfix:

    ./sabotage.py ../../../out/m9c ~/miniconda3/bin/python3 [NAME-PART]

docs/httpserver-plan.md, stages 1 to 3.                                   """
import os
import shutil
import subprocess
import sys
import tempfile

M9C = os.path.abspath(sys.argv[1])
PY = sys.argv[2]
ONLY = sys.argv[3] if len(sys.argv) > 3 else ""   # a part of a name: run those alone
HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.abspath(os.path.join(HERE, "../../../corpus"))
RUNTIME = os.path.abspath(os.path.join(HERE, "../.."))

SABOTAGES = [
    ("no Host check",
     "IF DynStr.Eq (version, 'HTTP/1.1') AND nHost # 1 THEN",
     "IF FALSE AND nHost # 1 THEN"),
    ("Content-Length beside Transfer-Encoding accepted",
     "IF nTe > 0 AND nCl > 0 THEN", "IF FALSE THEN"),
    ("two different Content-Lengths accepted",
     "IF nCl > 0 AND NOT DynStr.Eq (value, cl1) THEN", "IF FALSE THEN"),
    ("a full ring never refused",
     "IF q.count >= q.cap THEN RETURN FALSE END ;", ""),
    ("pipelined octets dropped",
     "  Consume (c, hend) ;\n", "  Consume (c, hend) ;\n  c.have := 0 ;\n"),
    ("the weekday off by one",
     "wd := (days + 4) MOD 7", "wd := (days + 5) MOD 7"),
    ("response headers not checked",
     "IF NOT HeadersOk (resp.headers) OR resp.status < 100", "IF resp.status < 100"),
    ("a handler's IndexError not caught where it is called",
     "          | IndexError :\n              w.s.st[w.k].faults := w.s.st[w.k].faults + 1\n          | Overflow :",
     "          | Overflow :"),
    ("chunk sizes read as decimal",
     "size := size * 16 + v", "size := size * 10 + v"),
    ("no lingering read after a refusal",
     "  IF ok THEN Linger (c) END ;\n", ""),
    ("no 100 Continue",
     "      IF NOT Continue100 (c) THEN RETURN FALSE END\n", ""),
    ("a body after HEAD",
     "  IF ok AND NOT head AND NOT NoBody (status) THEN\n    ok := WriteAll (c.fd, body) ;",
     "  IF ok AND NOT NoBody (status) THEN\n    ok := WriteAll (c.fd, body) ;"),
    ("the per-connection limit ignored",
     "IF served + 1 >= w.s.cfg.perConn OR Closing (w.s.q) OR I64 (Stopping ()) # 0 THEN",
     "IF Closing (w.s.q) OR I64 (Stopping ()) # 0 THEN"),
    ("no header deadline",
     "IF (F64 (NowSec ()) - t0) * 1000.0 > F64 (w.s.cfg.headerMs) THEN",
     "IF FALSE THEN"),
    ("a handler's ValueRange not counted",
     "          | ValueRange :\n              w.s.st[w.k].faults := w.s.st[w.k].faults + 1\n          | IndexError :",
     "          | ValueRange :\n              w.s.st[w.k].faults := w.s.st[w.k].faults + 0\n          | IndexError :"),
    ("405 without HEAD in Allow",
     "IF DynStr.Eq (rt.method, 'GET') THEN allow := allow + ', HEAD' END", ""),
    ("the absolute form not accepted",
     "IF LEN (tg) > 7 AND SameCi (SLICE (tg, 0, 7), 'http://') THEN i := 7",
     "IF FALSE THEN i := 7"),
    # stage 2
    ("an unsatisfiable range answered with the whole file",
     "    IF k = 2 THEN\n", "    IF FALSE THEN\n"),
    ("a suffix range one octet long",
     "    a := size - n ;\n", "    a := size - n - 1 ;\n"),
    ("a range with its last before its first taken as unsatisfiable",
     "    IF last < first THEN RETURN 0 END", "    IF last < first THEN RETURN 2 END"),
    ("If-Range ignored",
     " AND\n     LEN (Header (q, 'If-Range')) = 0 THEN", " THEN"),
    ("Range honoured on HEAD",
     "IF status = 200 AND DynStr.Eq (q.method, 'GET') AND LEN (rng) > 0 AND",
     "IF status = 200 AND LEN (rng) > 0 AND"),
    ("a hidden file served",
     "IF (i = 0 OR name[i - 1] = '/') AND (c = '/' OR c = '.') THEN RETURN FALSE END",
     "IF (i = 0 OR name[i - 1] = '/') AND (c = '/') THEN RETURN FALSE END"),
    # NOT here: the directory check in SendFile.  Its removal is visible
    # on macOS only, where a directory has a size; on Linux the size
    # query fails first and the gate answers 404 either way (measured)
    ("the file name given to Io as characters, not UTF-8",
     "  full := rt.dir + '/' + DynStr.Chars (scratch, DynStr.Utf8 (scratch, name)) ;",
     "  full := rt.dir + '/' + name ;"),
    ("no Vary when the body goes as it is",
     "    extra := 'Vary: Accept-Encoding' ;\n    IF TakesGzip", "    IF TakesGzip"),
    ("q=0 taken as a yes",
     "  RETURN NOT zero\nEND Positive ;", "  RETURN TRUE\nEND Positive ;"),
    ("* not read",
     "  RETURN star = 1\nEND TakesGzip ;", "  RETURN FALSE\nEND TakesGzip ;"),
    ("a body encoded already gzipped again",
     " AND\n     Compressible (resp.ctype) AND LEN (Http.Header (resp.headers, 'Content-Encoding')) = 0 THEN",
     " AND\n     Compressible (resp.ctype) THEN"),
    ("gzipMin ignored",
     "IF w.s.cfg.gzipMin > 0 AND LEN (body) >= w.s.cfg.gzipMin AND",
     "IF w.s.cfg.gzipMin > 0 AND"),
    ("HEAD given the identity length of a gzipped body",
     "    IF TakesGzip (Header (q, 'Accept-Encoding')) THEN\n      body := Zip.Gzip (scratch, body) ;",
     "    IF TakesGzip (Header (q, 'Accept-Encoding')) THEN\n      IF NOT head THEN body := Zip.Gzip (scratch, body) END ;"),
    ("a stream without its last chunk",
     "      ok := WriteAll (c.fd, DynStr.Bytes (scratch, '0' + 0DC + 0AC + 0DC + 0AC, FALSE))",
     "      ok := TRUE"),
    ("a stream to HTTP/1.0 left open",
     "    IF resp.stream IS SOME p THEN keep := FALSE END", "    IF resp.stream IS SOME p THEN END"),
    ("a producer that raised taken as done",
     "  | ValueRange :\n      w.s.st[w.k].faults := w.s.st[w.k].faults + 1 ; RETURN -1",
     "  | ValueRange :\n      w.s.st[w.k].faults := w.s.st[w.k].faults + 1 ; RETURN 1"),
    ("a file read whole",
     "      IF n > 65536 THEN n := 65536 END ;\n", ""),
    # stage 3 (a fourth element names another file than HttpServer.m9)
    ("a stop the accepting thread never sees",
     "      IF I64 (Stopping ()) # 0 THEN why := Stopped ; EXIT END ;\n", ""),
    ("an idle kept connection held through a stop",
     "    IF served > 0 AND (I64 (Stopping ()) # 0 OR Closing (w.s.q)) THEN RETURN FALSE END ;\n", ""),
    ("the answer in flight at a stop not the last",
     "  IF I64 (Stopping ()) # 0 OR Closing (w.s.q) THEN keep := FALSE END ;\n", ""),
    ("SIGTERM not caught",
     "  IF cfg.signals THEN Signals (C.Int (1)) END ;\n", ""),
    ("Stop from a handler does nothing",
     "BEGIN\n  StopFlag ()\nEND Stop ;", "BEGIN\nEND Stop ;"),
    ("X-Forwarded-For believed from anyone",
     "  IF NOT InList (peer, trusted) THEN RETURN peer END ;\n", ""),
    ("X-Forwarded-For believed when it is not addresses",
     "      IF NOT IsAddress (a) THEN RETURN peer END ;\n", ""),
    ("a trusted proxy taken for the client",
     "      IF NOT InList (a, trusted) THEN RETURN a END ;", "      RETURN a ;"),
    ("the bind address ignored",
     "  lfd := I64 (ListenAt (ADR (addr), C.Int (cfg.port), C.Int (cfg.backlog))) ;",
     "  lfd := I64 (Listen (C.Int (cfg.port), C.Int (cfg.backlog))) ;"),
    ("no access line for an answer",
     "  IF w.s.cfg.accessLog THEN\n    AccessLine (w, q.method",
     "  IF FALSE THEN\n    AccessLine (w, q.method"),
    ("no access line for a refusal",
     "  IF w.s.cfg.accessLog THEN\n    AccessLine (w, '-'",
     "  IF FALSE THEN\n    AccessLine (w, '-'"),
    ("Logger.Msg through the shared builder",
     "  IF NOT Enabled (level) THEN RETURN END ;\n  IF toSyslog THEN\n    Syslog.Send (Syslog.Pri (curFacility, Syslog.FromLoggerLevel (level)), text) ;\n    RETURN\n  END ;",
     "  Start (level, text) ;\n  Done () ;\n  RETURN ;", "corpus/Logger.m9"),
    ("stderr not locked for a whole line",
     "#define M9_LOCK(f) flockfile (f)\n#define M9_UNLOCK(f) funlockfile (f)",
     "#define M9_LOCK(f) ((void) 0)\n#define M9_UNLOCK(f) ((void) 0)", "runtime/m9rt.c"),
]

ROOT = os.path.abspath(os.path.join(HERE, "../../.."))
held = []
SABOTAGES = [x for x in SABOTAGES if ONLY in x[0]]
for entry in SABOTAGES:
    name, old, new = entry[:3]
    rel = entry[3] if len(entry) > 3 else "corpus/HttpServer.m9"
    src = open(os.path.join(ROOT, rel)).read()
    if src.count(old) != 1:
        print(f"sabotage: STALE -- '{name}': its text is in {rel} {src.count(old)} times")
        held.append(name)
        continue
    with tempfile.TemporaryDirectory() as w:
        lib = os.path.join(w, "lib")
        rt = os.path.join(w, "rt")
        shutil.copytree(CORPUS, lib)
        shutil.copytree(RUNTIME, rt, ignore=shutil.ignore_patterns("test", "gen"))
        target = os.path.join(lib, os.path.basename(rel)) if rel.startswith("corpus/") \
            else os.path.join(rt, os.path.basename(rel))
        with open(target, "w") as f:
            f.write(src.replace(old, new))
        b = subprocess.run([M9C, "--make", "-o", os.path.join(w, "srv"),
                            os.path.join(HERE, "SrvFix.m9")], cwd=w,
                           env=dict(os.environ, M9RUNTIME=rt, M9LIBRARY=lib),
                           capture_output=True, text=True)
        if b.returncode != 0:
            print(f"sabotage: '{name}' does not build -- not a sabotage:\n{b.stderr[-600:]}")
            held.append(name)
            continue
        try:
            r = subprocess.run([PY, os.path.join(HERE, "srvfix.py"), os.path.join(w, "srv")],
                               capture_output=True, text=True, timeout=600)
        except subprocess.TimeoutExpired:
            print(f"sabotage: red, as it must be: {name} -- the gate hung for 600 s")
            continue
        finally:
            # a hung or broken run can leave its servers on the fixture's
            # ports, and the next entry would go red for that; freed by
            # port (fuser), never by a pattern
            for port in list(range(18350, 18376)) + list(range(19350, 19376)):
                subprocess.run(["fuser", "-k", f"{port}/tcp"], capture_output=True)
        last = (r.stdout.strip().splitlines() or ["(nothing)"])[-1]
        first = next((l for l in r.stdout.splitlines() if l.startswith("FAIL:")), last)
        if r.returncode == 0:
            print(f"sabotage: PASSED (the gate missed it): {name}")
            held.append(name)
        else:
            print(f"sabotage: red, as it must be: {name} -- {first[:150]}")
print(f"sabotage: {len(SABOTAGES) - len(held)} of {len(SABOTAGES)} red")
sys.exit(1 if held else 0)
