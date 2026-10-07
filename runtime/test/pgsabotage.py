#!/usr/bin/env python3
"""pgsabotage M9C -- shows PgTest able to fail.

Each entry is one small break of a COPY of corpus/Pg.m9 that PgTest
must catch: build PgTest against the copy, run it against the server
libpq's PG* variables name, and require it to FAIL.  A sabotage that
passes is a property PgTest does not hold; the script exits 1 naming
it.  Run by hand after changing Pg or PgTest (docs/datalib-plan.md).

    PGHOST=... runtime/test/pgsabotage.py out/m9c       (repository root)
"""
import os
import shutil
import subprocess
import sys
import tempfile

M9C = os.path.abspath(sys.argv[1])
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
RT = os.path.join(ROOT, "runtime")
GOLD = os.path.join(RT, "test", "gold")

SABOTAGES = [
    ("Cell without the column check (the lifted module's bug)",
     "  IF col < 0 OR col >= r.cols THEN RAISE IndexError (col, r.cols) END ;\n  RETURN row * r.cols + col",
     "  RETURN row * r.cols + col"),
    ("NULL not flagged",
     "          r.isNull[k] := TRUE", "          r.isNull[k] := FALSE"),
    ("F64Cell by Fmt.ParseF64 alone",
     "  RETURN F64 (StrToD (ADR (cb)))", "  RETURN v"),
    ("the offset's sign ignored",
     "  RETURN Time.AddSeconds (t, F64 (-sign * off))", "  RETURN Time.AddSeconds (t, F64 (-off))"),
    ("cells decoded as Latin-1",
     "            r.cell[k] := DynStr.FromUtf8 (pool, b)", "            r.cell[k] := DynStr.Chars (pool, b)"),
]

src = open(os.path.join(ROOT, "corpus", "Pg.m9")).read()
held = []
for name, old, new in SABOTAGES:
    if src.count(old) != 1:
        print(f"pgsabotage: STALE -- '{name}': its text is there {src.count(old)} times")
        held.append(name)
        continue
    with tempfile.TemporaryDirectory() as w:
        lib = os.path.join(w, "lib")
        shutil.copytree(os.path.join(ROOT, "corpus"), lib)
        open(os.path.join(lib, "Pg.m9"), "w").write(src.replace(old, new))
        env = dict(os.environ, M9RUNTIME=RT, M9LIBRARY=lib)
        b = subprocess.run([M9C, "--make", "-c", "-k", os.path.join(lib, "PgTest.m9")],
                           cwd=w, env=env, capture_output=True, text=True)
        objs = [os.path.join(w, f) for f in os.listdir(w) if f.endswith(".o")]
        if b.returncode == 0:
            b = subprocess.run(["gcc", "-O2", *objs] +
                               [os.path.join(RT, f) for f in
                                ("m9rt.c", "tcpshim.c", "tlsshim.c", "fmtshim.c", "pgshim.c")] +
                               ["-iquote", RT, "-l:libpq.so.5", "-Wl,--as-needed",
                                "-lssl", "-lcrypto", "-lm", "-o", os.path.join(w, "t")],
                               capture_output=True, text=True)
        if b.returncode != 0:
            print(f"pgsabotage: '{name}' does not build:\n{b.stderr[-500:]}")
            held.append(name)
            continue
        r = subprocess.run([os.path.join(w, "t"), GOLD], cwd=ROOT,
                           capture_output=True, text=True, timeout=120)
        first = next((l for l in r.stdout.splitlines() if l.startswith("FAIL")), "")
        if r.returncode == 0:
            print(f"pgsabotage: PASSED (PgTest missed it): {name}")
            held.append(name)
        else:
            print(f"pgsabotage: red, as it must be: {name} -- {first[:120]}")
print(f"pgsabotage: {len(SABOTAGES) - len(held)} of {len(SABOTAGES)} red")
sys.exit(1 if held else 0)
