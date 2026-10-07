#!/usr/bin/env python3
"""regexsabotage M9C -- shows RegexTest able to fail.

Each entry is one small break of a COPY of corpus/Regex.m9 that
RegexTest must catch: build RegexTest against the copy, run it from the
repository root, and require it to FAIL.  A sabotage that passes is a
property RegexTest does not hold; the script exits 1 naming it.  Run by
hand after changing Regex or RegexTest (docs/datalib-plan.md).

    runtime/test/regexsabotage.py out/m9c        (repository root)
"""
import os
import shutil
import subprocess
import sys
import tempfile

M9C = os.path.abspath(sys.argv[1])
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
RT = os.path.join(ROOT, "runtime")

SABOTAGES = [
    ("an unanchored search that stops at a position with no thread",
     "    IF cl.n = 0 AND (matched OR anchored) THEN EXIT END ;",
     "    IF cl.n = 0 THEN EXIT END ;"),
    ("a match that does not cut the threads below it",
     "          i := cl.n               (* the threads below this one are cut *)",
     "          i := i"),
    ("no guard on a loop whose body matched nothing",
     "    IF null THEN checks[i] := Emit (re, OCheck, slot, 0) END ;",
     ""),
    ("one copy of a nullable unbounded body",
     "  ELSIF null THEN k := 2\n",
     "  ELSIF null THEN k := 1\n"),
    ("a lazy quantifier taken greedily",
     "      rep.greedy := NOT lazy ;",
     "      rep.greedy := TRUE ;"),
    ("$ without the final line feed",
     "  IF kind = AEotNl THEN RETURN pos = n OR (pos = n - 1 AND s[pos] = 0AC) END ;",
     "  IF kind = AEotNl THEN RETURN pos = n END ;"),
    ("^ under m only at the start",
     "  IF kind = ABol THEN RETURN pos = 0 OR s[pos - 1] = 0AC END ;",
     "  IF kind = ABol THEN RETURN pos = 0 END ;"),
    ("\\b blind to Unicode under u",
     "  IF NOT uni THEN RETURN FALSE END ;\n  RETURN InTable (UWordLo",
     "  IF TRUE THEN RETURN FALSE END ;\n  RETURN InTable (UWordLo"),
    ("a negated class closed under case after negating",
     "  IF ps.ci THEN SetCaseless (sp, st) END ;\n  SetNormal (st) ;\n  IF neg THEN SetNegate (sp, st) END ;",
     "  SetNormal (st) ;\n  IF neg THEN SetNegate (sp, st) END ;\n  IF ps.ci THEN SetCaseless (sp, st) ; SetNormal (st) END ;"),
    ("an empty match allowed right after an empty match",
     "      advance := m.span[1] = m.span[0] ;\n      pos := m.span[1]\n    ELSE\n      EXIT\n    END\n  END ;\n  RETURN SLICE (all, 0, n)",
     "      advance := FALSE ;\n      pos := m.span[1] ;\n      IF m.span[1] = m.span[0] THEN pos := pos + 1 END\n    ELSE\n      EXIT\n    END ;\n    IF pos > LEN (s) THEN EXIT END\n  END ;\n  RETURN SLICE (all, 0, n)"),
    ("Split without the groups",
     "      FOR g := 1 TO re.ngroups DO\n        out[n] := '' ;",
     "      FOR g := 1 TO 0 DO\n        out[n] := '' ;"),
    ("a group in a replacement read one too far",
     "        IF m.span[2 * g] >= 0 THEN\n          DynStr.Append (d, SLICE (s, m.span[2 * g], m.span[2 * g + 1] - m.span[2 * g]))",
     "        IF m.span[2 * g] >= 0 AND g < re.ngroups THEN\n          DynStr.Append (d, SLICE (s, m.span[2 * g], m.span[2 * g + 1] - m.span[2 * g]))"),
    ("\\s without the vertical tab and form feed",
     "      SetAdd (sp, one, 9, 13) ;",
     "      SetAdd (sp, one, 9, 10) ;\n      SetAdd (sp, one, 13, 13) ;"),
    ("{,n} read as {n}",
     "  min := 0 ;\n  IF hasLo THEN min := lo END ;",
     "  min := hi ;\n  IF hasLo THEN min := lo END ;"),
    ("a backreference read as an octal escape",
     "    Fail (ps, 'a backreference: it needs backtracking, which this engine does not do', at)\n  END ;\n  IF IsAsciiLetter (c) THEN",
     "    RETURN CharNode (sp, ps, re, ORD (c) - 48)\n  END ;\n  IF IsAsciiLetter (c) THEN"),
    ("the time bound: a search that runs an anchored match from every start",
     "PROCEDURE Search (re: PTR Re ; RO s: STR ; from: I64) : OPT PTR Found =\nBEGIN\n  RETURN Run (re, s, from, FALSE, FALSE, FALSE)\nEND Search ;",
     "PROCEDURE Search (re: PTR Re ; RO s: STR ; from: I64) : OPT PTR Found =\nVAR i : I64 ; r : OPT PTR Found ;\nBEGIN\n"
     "  FOR i := from TO LEN (s) DO\n    r := Run (re, s, i, TRUE, FALSE, FALSE) ;\n"
     "    IF r IS SOME m THEN RETURN r END\n  END ;\n  RETURN NONE\nEND Search ;"),
]

src = open(os.path.join(ROOT, "corpus", "Regex.m9")).read()
held = []
for name, old, new in SABOTAGES:
    if src.count(old) != 1:
        print(f"regexsabotage: STALE -- '{name}': its text is there {src.count(old)} times")
        held.append(name)
        continue
    with tempfile.TemporaryDirectory() as w:
        lib = os.path.join(w, "lib")
        shutil.copytree(os.path.join(ROOT, "corpus"), lib)
        open(os.path.join(lib, "Regex.m9"), "w").write(src.replace(old, new))
        env = dict(os.environ, M9RUNTIME=RT, M9LIBRARY=lib)
        b = subprocess.run([M9C, "--make", "-o", os.path.join(w, "t"),
                            os.path.join(lib, "RegexTest.m9")],
                           cwd=w, env=env, capture_output=True, text=True)
        if b.returncode != 0:
            print(f"regexsabotage: '{name}' does not build:\n{b.stderr[-500:]}")
            held.append(name)
            continue
        r = subprocess.run([os.path.join(w, "t")], cwd=ROOT,
                           capture_output=True, text=True, timeout=600)
        first = next((l for l in r.stdout.splitlines() if l.startswith("FAIL")), "")
        if r.returncode == 0:
            print(f"regexsabotage: PASSED (RegexTest missed it): {name}")
            held.append(name)
        else:
            print(f"regexsabotage: red, as it must be: {name} -- {first[:120]}")
print(f"regexsabotage: {len(SABOTAGES) - len(held)} of {len(SABOTAGES)} red")
sys.exit(1 if held else 0)
