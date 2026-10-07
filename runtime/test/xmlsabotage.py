#!/usr/bin/env python3
"""xmlsabotage M9C -- shows XmlTest able to fail.

Each entry is one small break of a COPY of corpus/Xml.m9 that XmlTest
must catch against the W3C suite: build XmlTest against the copy, run
it from the repository root with the suite where runtime/test/xml.sh
unpacks it, and require it to FAIL.  A sabotage that passes is a
property XmlTest does not hold; the script exits 1 naming it.  Run by
hand after changing Xml or XmlTest, once xml.sh has run
(docs/datalib-plan.md).

    runtime/test/xmlsabotage.py out/m9c         (repository root)
"""
import os
import shutil
import subprocess
import sys
import tempfile

M9C = os.path.abspath(sys.argv[1])
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
RT = os.path.join(ROOT, "runtime")
SUITE = os.path.join(RT, "test", "xmlconf", "xmlconf")

SABOTAGES = [
    ("characters no document may hold accepted",
     "    IF NOT IsChar (ORD (r.src[i])) THEN\n      r.pos := i ;",
     "    IF FALSE THEN\n      r.pos := i ;"),
    ("-- inside a comment accepted",
     "      IF NOT Ahead (r, '-->') THEN Fail (r, '-- inside a comment') END ;\n      r.pos := r.pos + 3 ;\n      EXIT",
     "      IF Ahead (r, '-->') THEN r.pos := r.pos + 3 ; EXIT END"),
    ("an attribute given twice accepted",
     "      IF Text.Eq (attrs[i].name, an) THEN Fail (r, 'an attribute given twice: ' + an) END",
     "      IF FALSE THEN Fail (r, 'an attribute given twice: ' + an) END"),
    ("an end tag that closes another element",
     "  IF NOT Text.Eq (n, r.stack[r.depth - 1]) THEN",
     "  IF FALSE THEN"),
    ("attribute values not normalised",
     "      IF IsSpace (c) THEN c := ' ' END ;",
     ""),
    ("a lone CR kept",
     "      s[n] := 0AC ;\n      IF i + 1 < LEN (raw) AND raw[i + 1] = 0AC THEN i := i + 1 END",
     "      s[n] := 0DC"),
    ("an undeclared entity read as text",
     "  Fail (r, 'an undeclared entity: ' + n) ;\n  RETURN ' '",
     "  r.pos := r.pos + LEN (n) + 2 ;\n  RETURN ' '"),
    ("an unbound prefix accepted",
     "  Split (r, n, p, l) ;\n  IF NOT Lookup (r, p, u) THEN Fail (r, 'an unbound prefix: ' + p) END ;",
     "  Split (r, n, p, l) ;\n  IF NOT Lookup (r, p, u) THEN u := '' END ;"),
    ("a name may begin with a digit",
     "  RETURN c = 58 OR (c >= 65 AND c <= 90) OR c = 95 OR (c >= 97 AND c <= 122) OR",
     "  RETURN c = 58 OR (c >= 48 AND c <= 57) OR (c >= 65 AND c <= 90) OR c = 95 OR (c >= 97 AND c <= 122) OR"),
    ("the PI target xml allowed",
     "    Fail (r, 'the target xml is reserved: an XML declaration belongs at the very start')",
     "    target := target"),
    ("]]> in character data accepted",
     "      IF c = ']' AND Ahead (r, ']]>') THEN Fail (r, ']]> in character data') END ;",
     ""),
    ("a character reference to no character accepted",
     "  IF NOT IsChar (v) THEN Fail (r, 'a character reference to no XML character') END ;",
     "  IF v = 0 THEN v := 32 END ;"),
    ("the tree's tail given to the parent",
     "      IF haveLast THEN last.tail := Text.Keep (pool, last.tail + ev.text)",
     "      IF FALSE THEN last.tail := Text.Keep (pool, last.tail + ev.text)"),
    ("an ENTITY declaration a SyntaxError, not refused by name",
     "    Refuse (r, 'an ENTITY declaration: entities are not expanded')",
     "    Fail (r, 'an ENTITY declaration: entities are not expanded')"),
    ("the internal subset's PIs not reported",
     "      ev.kind := Kind.Pi ;\n      ev.text := PiBody (r, target) ;\n      ev.name := target ;\n      RETURN ev",
     "      ev.kind := Kind.Pi ;\n      ev.text := PiBody (r, target) ;\n      ev.name := target ;\n      IF r.state # SSubset THEN RETURN ev END"),
    ("the writer leaves & in an attribute",
     "    IF c = '&' THEN DynStr.Append (w.d, '&amp;')",
     "    IF c = '&' AND NOT attr THEN DynStr.Append (w.d, '&amp;')"),
    ("a namespace declared to the empty string accepted",
     "      IF LEN (av) = 0 THEN Fail (r, 'a prefix bound to no namespace: ' + l) END ;",
     ""),
]

if not os.path.isfile(os.path.join(SUITE, "xmlconf.xml")):
    raise SystemExit(f"xmlsabotage: no suite at {SUITE} -- run runtime/test/xml.sh first")
src = open(os.path.join(ROOT, "corpus", "Xml.m9")).read()
held = []
for name, old, new in SABOTAGES:
    if src.count(old) != 1:
        print(f"xmlsabotage: STALE -- '{name}': its text is there {src.count(old)} times")
        held.append(name)
        continue
    with tempfile.TemporaryDirectory() as w:
        lib = os.path.join(w, "lib")
        shutil.copytree(os.path.join(ROOT, "corpus"), lib)
        open(os.path.join(lib, "Xml.m9"), "w").write(src.replace(old, new))
        env = dict(os.environ, M9RUNTIME=RT, M9LIBRARY=lib)
        b = subprocess.run([M9C, "--make", "-o", os.path.join(w, "t"),
                            os.path.join(lib, "XmlTest.m9")],
                           cwd=w, env=env, capture_output=True, text=True)
        if b.returncode != 0:
            print(f"xmlsabotage: '{name}' does not build:\n{b.stderr[-500:]}")
            held.append(name)
            continue
        r = subprocess.run([os.path.join(w, "t")], cwd=ROOT,
                           env=dict(os.environ, M9_XMLCONF=SUITE),
                           capture_output=True, text=True, timeout=600)
        first = next((l for l in r.stdout.splitlines() if l.startswith("FAIL")), "")
        if r.returncode == 0:
            print(f"xmlsabotage: PASSED (XmlTest missed it): {name}")
            held.append(name)
        else:
            print(f"xmlsabotage: red, as it must be: {name} -- {first[:120]}")
print(f"xmlsabotage: {len(SABOTAGES) - len(held)} of {len(SABOTAGES)} red")
sys.exit(1 if held else 0)
