#!/usr/bin/env python3
"""rdfsabotage M9C -- shows Rdf's two gates able to fail.

Each entry is one small break of a COPY of corpus/Rdf.m9.  Against the
copy, RdfTest (m9test's half, offline) and rdf.sh's half (RdfConv's
N-Triples judged by rdflib, runtime/test/rdfjudge.py) are both run, and
at least one must go red; the line says which did.  A sabotage both
pass is a property neither holds; the script exits 1 naming it.  Run by
hand after changing Rdf, RdfTest or the judge (docs/datalib-plan.md),
with a Python that has rdflib.

    runtime/test/rdfsabotage.py out/m9c         (repository root)
"""
import os
import shutil
import subprocess
import sys
import tempfile

M9C = os.path.abspath(sys.argv[1])
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
RT = os.path.join(ROOT, "runtime")
TEST = os.path.join(RT, "test")
GOLD = os.path.join(TEST, "gold", "Rdf.gold")

SABOTAGES = [
    ("a blank-node label names a new node each time",
     "    IF Text.Eq (r.blab[i], lab) THEN RETURN r.bid[i] END",
     "    IF Text.Eq (r.blab[i], '') THEN RETURN r.bid[i] END"),
    ("a collection's last cell has no rdf:rest",
     "  IF any THEN Add (pool, g, prev, IriT (RdfNs + 'rest'), IriT (RdfNs + 'nil')) END ;",
     ""),
    ("a surrogate escape accepted",
     "  IF v > 0x10FFFF OR (v >= 0xD800 AND v <= 0xDFFF) THEN",
     "  IF v > 0x10FFFF THEN"),
    ("a /../ that does not climb",
     "      IF i >= 0 THEN output := SLICE (output, 0, i) ELSE output := '' END",
     ""),
    ("a relative reference merged without the base's directory",
     "            IF k >= 0 THEN tp := RemoveDots (SLICE (bp, 0, k + 1) + rp)",
     "            IF k >= 0 THEN tp := RemoveDots (rp)"),
    ("a relative IRI in N-Triples accepted",
     "  IF NOT r.turtle THEN Fail (r, 'a relative IRI in N-Triples') END ;",
     ""),
    ("a blank-node label ending in a dot accepted",
     "  IF s[LEN (s) - 1] = '.' THEN Fail (r, 'a blank node label ends with a dot') END ;",
     ""),
    ("a line end in a short string accepted",
     "      IF c = 0AC OR c = 0DC THEN Fail (r, 'a line end in a short string') END",
     ""),
    ("a blank node as a predicate in N-Triples accepted",
     "    IF p.kind # Kind.Iri THEN Fail (r, 'a predicate that is not an IRI') END ;",
     ""),
    ("a decimal typed as a double",
     "  ELSIF dot THEN dt := Xsd + 'decimal'",
     "  ELSIF dot THEN dt := Xsd + 'double'"),
    ("the writer leaves a quote unescaped",
     "        IF c = '\"' THEN DynStr.Append (d, '\\\"')",
     "        IF c = '\"' THEN DynStr.Append (d, '\"')"),
    ("the writer leaves a line feed unescaped",
     "        ELSIF c = 0AC THEN DynStr.Append (d, '\\n')",
     "        ELSIF c = 0AC THEN DynStr.AppendChar (d, 0AC)"),
]


def lists():
    out = {}
    for line in open(GOLD, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        f = line.split()
        out[f[0]] = f[3:]
    return out


L = lists()
src = open(os.path.join(ROOT, "corpus", "Rdf.m9")).read()
held = []
for name, old, new in SABOTAGES:
    if src.count(old) != 1:
        print(f"rdfsabotage: STALE -- '{name}': its text is there {src.count(old)} times")
        held.append(name)
        continue
    with tempfile.TemporaryDirectory() as w:
        lib = os.path.join(w, "lib")
        shutil.copytree(os.path.join(ROOT, "corpus"), lib)
        open(os.path.join(lib, "Rdf.m9"), "w").write(src.replace(old, new))
        env = dict(os.environ, M9RUNTIME=RT, M9LIBRARY=lib)
        built = True
        for prog, path in (("t", os.path.join(lib, "RdfTest.m9")),
                           ("conv", os.path.join(TEST, "rdffix", "RdfConv.m9"))):
            b = subprocess.run([M9C, "--make", "-o", os.path.join(w, prog), path],
                               cwd=w, env=env, capture_output=True, text=True)
            if b.returncode != 0:
                print(f"rdfsabotage: '{name}' does not build {prog}:\n{b.stderr[-500:]}")
                built = False
                break
        if not built:
            held.append(name)
            continue
        r = subprocess.run([os.path.join(w, "t")], cwd=ROOT,
                           capture_output=True, text=True, timeout=300)
        test_red = r.returncode != 0
        out = os.path.join(w, "out")
        os.makedirs(os.path.join(out, "ttl"))
        os.makedirs(os.path.join(out, "nt"))
        c1 = subprocess.run([os.path.join(w, "conv"), "ttl", "rdf-tests/rdf-turtle",
                             L["ttl.base"][0], os.path.join(out, "ttl")] +
                            L["ttl.eval.action"] + L["ttl.pos"] + L["ttl.neg"],
                            cwd=TEST, capture_output=True, text=True)
        c2 = subprocess.run([os.path.join(w, "conv"), "nt", "rdf-tests/rdf-n-triples", "",
                             os.path.join(out, "nt")] + L["nt.pos"] + L["nt.neg"],
                            cwd=TEST, capture_output=True, text=True)
        j = subprocess.run([sys.executable, "rdfjudge.py", GOLD, "rdf-tests", out],
                           cwd=TEST, capture_output=True, text=True)
        judge_red = c1.returncode != 0 or c2.returncode != 0 or j.returncode != 0
        if not (test_red or judge_red):
            print(f"rdfsabotage: PASSED (neither gate saw it): {name}")
            held.append(name)
            continue
        by = " and ".join(x for x, red in (("RdfTest", test_red), ("rdflib", judge_red)) if red)
        first = next((l for l in (r.stdout + j.stdout).splitlines()
                      if "FAIL" in l), "")
        print(f"rdfsabotage: red, as it must be, by {by}: {name} -- {first[:110]}")
print(f"rdfsabotage: {len(SABOTAGES) - len(held)} of {len(SABOTAGES)} red")
sys.exit(1 if held else 0)
