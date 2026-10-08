#!/usr/bin/env python3
"""rdfsabotage M9C -- shows Rdf's two gates able to fail.

Each entry is one small break of a COPY of corpus/Rdf.m9.  Against the
copy, RdfTest (m9test's half, offline) and rdf.sh's half (RdfConv's
N-Triples judged by rdflib, runtime/test/rdfjudge.py) are both run, and
at least one must go red; the line says which did.  A sabotage both
pass is a property neither holds; the script exits 1 naming it.  Run by
hand after changing Rdf, RdfTest or the judge (docs/datalib-plan.md),
with a Python that has rdflib.

    runtime/test/rdfsabotage.py out/m9c [NAME-PART]   (repository root)
"""
import os
import shutil
import subprocess
import sys
import tempfile

M9C = os.path.abspath(sys.argv[1])
ONLY = sys.argv[2] if len(sys.argv) > 2 else ""   # a part of a name: run those alone
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
    # the Turtle writer
    ("Turtle: a predicate group ended with a dot, not a semicolon",
     "          IF firstPred THEN DynStr.AppendChar (body, ' ') ELSE DynStr.Append (body, ' ;' + 0AC + '    ') END ;",
     "          IF firstPred THEN DynStr.AppendChar (body, ' ') ELSE DynStr.Append (body, ' .' + 0AC + '    ') END ;"),
    ("Turtle: `a' for every predicate",
     "      IF predicate AND Text.Eq (t.value, RdfNs + 'type') THEN DynStr.AppendChar (d, 'a')",
     "      IF predicate THEN DynStr.AppendChar (d, 'a')"),
    ("Turtle: a short form for a non-canonical integer",
     "    RETURN Digits (s, i, LEN (s))\n  ELSIF Text.Eq (t.datatype, Xsd + 'decimal') THEN",
     "    RETURN TRUE\n  ELSIF Text.Eq (t.datatype, Xsd + 'decimal') THEN"),
    # not here: a short string with a raw line end -- a literal holding
    # one is written as a long string, so the branch did not exist and
    # was removed when its sabotage stayed green
    ("Turtle: a blank node written as an IRI",
     "  | Blank :\n      DynStr.Append (d, '_:') ;\n      DynStr.Append (d, t.value)\n  | Literal :\n      TtlLiteral (d, p, t)",
     "  | Blank :\n      DynStr.Append (d, '<_:') ;\n      DynStr.Append (d, t.value) ;\n      DynStr.AppendChar (d, '>')\n  | Literal :\n      TtlLiteral (d, p, t)"),
    ("Turtle: the language tag dropped",
     "  IF LEN (t.lang) > 0 THEN\n    DynStr.AppendChar (d, '@') ;\n    DynStr.Append (d, t.lang)\n  ELSIF LEN (t.datatype) > 0 AND NOT Text.Eq (t.datatype, XsdString) THEN\n    DynStr.Append (d, '^^') ;\n    TtlIri (d, p, t.datatype)",
     "  IF LEN (t.lang) > 0 THEN\n    DynStr.Append (d, '')\n  ELSIF LEN (t.datatype) > 0 AND NOT Text.Eq (t.datatype, XsdString) THEN\n    DynStr.Append (d, '^^') ;\n    TtlIri (d, p, t.datatype)"),
    ("Turtle: a prefix applied to a local name it cannot spell",
     "       LocalOk (SLICE (iri, LEN (p.iris[i]), LEN (iri) - LEN (p.iris[i]))) THEN",
     "       TRUE THEN"),
    ("Turtle: a used prefix not declared",
     "    p.used[k] := TRUE ;",
     "    p.used[k] := p.used[k] ;"),
    # the RDF/XML reader
    ("RDF/XML: rdf:li not numbered",
     "      li := li + 1 ;\n      pred := IriT (RdfNs + '_' + Fmt.I64Str (li))",
     "      pred := IriT (RdfNs + '_' + Fmt.I64Str (li))"),
    ("RDF/XML: a typed node element's rdf:type dropped",
     "  IF NOT (IsRdf (e) AND Text.Eq (e.local, 'Description')) THEN\n    Add (pool, g, subj, IriT (RdfNs + 'type'), IriT (e.ns + e.local))\n  END ;",
     ""),
    ("RDF/XML: xml:lang ignored",
     "  IF Xml.HasAttr (e, XmlNsUri, 'lang') THEN lang := Xml.AttrValue (e, XmlNsUri, 'lang') END",
     ""),
    ("RDF/XML: rdf:ID used twice accepted",
     "    IF Text.Eq (st.ids[i], iri) THEN XFail ('rdf:ID used twice: ' + id) END",
     ""),
    ("RDF/XML: no reification for rdf:ID on a property element",
     "  Add (pool, g, r, IriT (RdfNs + 'type'), IriT (RdfNs + 'Statement')) ;",
     ""),
    ("RDF/XML: a collection without its rdf:nil",
     "        Add (pool, g, prev, IriT (RdfNs + 'rest'), IriT (RdfNs + 'nil'))\n      END ;",
     "      END ;"),
    ("RDF/XML: parseType Resource read as a literal",
     "    IF Text.Eq (parseType, 'Resource') THEN",
     "    IF FALSE THEN"),
    ("RDF/XML: an XML literal without its namespace declarations",
     "    IF NOT Declared (dn, du, n, names[i], uris[i]) THEN",
     "    IF FALSE THEN"),
    ("RDF/XML: rdf:datatype ignored on a literal",
     "    IF hasDatatype THEN obj := LitT (pe.text, '', XIri (st, base, datatype))\n    ELSE obj := LitT (pe.text, lang, '')\n    END ;",
     "    obj := LitT (pe.text, lang, '') ;"),
    ("RDF/XML: an attribute without a namespace accepted",
     "      IF NOT Text.StartsWith (e.attrs[i].name, 'xml') THEN\n        XFail ('an attribute without a namespace: ' + e.attrs[i].name)\n      END",
     ""),
    # the JSON-LD reader
    ("JSON-LD: a term consulted for an @id",
     "  IF vocab AND k >= 0 THEN\n    IF c.defs[k].isNull THEN nul := TRUE ; RETURN '' END ;",
     "  IF k >= 0 THEN\n    IF c.defs[k].isNull THEN nul := TRUE ; RETURN '' END ;"),
    ("JSON-LD: @vocab not applied",
     "  IF vocab AND c.hasVocab THEN RETURN c.vocab + value END ;",
     ""),
    ("JSON-LD: a double written as its shortest decimal, not canonical",
     "      RETURN LitT (CanonDouble (Json.AsF64 (v)), '', dt)",
     "      RETURN LitT (Fmt.Short (Json.AsF64 (v)), '', dt)"),
    ("JSON-LD: a list's last cell without rdf:nil",
     "  Add (pool, g, prev, IriT (RdfNs + 'rest'), IriT (RdfNs + 'nil')) ;\n  RETURN head",
     "  RETURN head"),
    ("JSON-LD: the default language ignored",
     "    ELSIF c.hasLang THEN\n      s := Json.NewStrIn (pool, c.lang) ;\n      Json.Set (o, '@language', s)\n    END",
     "    END"),
    ("JSON-LD: a list of lists accepted",
     "        IF listCtx AND (IsArr (x) OR IsListObj (x)) THEN JFail ('list of lists', '') END ;",
     ""),
    ("JSON-LD: @reverse read forwards",
     "      IF inDefault THEN\n        ref := RefTo (pool, subject) ;\n        AddUnique (pool, node, prop, ref)\n      END",
     "      IF inDefault THEN\n        ref := RefTo (pool, id) ;\n        inner := NodeFor (pool, dflt, subject) ;\n        AddUnique (pool, inner, prop, ref)\n      END"),
    ("JSON-LD: a remote context fetched instead of refused (read as nothing)",
     "      JFail ('a remote context is refused', JStr (item))",
     ""),
    ("JSON-LD: a keyword redefined in a context accepted",
     "  IF IsKeyword (term) THEN JFail ('keyword redefinition', term) END ;",
     ""),
    ("JSON-LD: a typed value's @type dropped",
     "  IF Has (item, '@type') THEN dt := JStr (JGet (item, '@type')) END ;",
     "  dt := '' ;"),
    # the JSON-LD writer
    ("JSON-LD written: a language tag dropped",
     "        s := Json.NewStrIn (pool, t.lang) ;\n        Json.Set (o, '@language', s)",
     ""),
    ("JSON-LD written: a datatype dropped",
     "        s := Json.NewStrIn (pool, t.datatype) ;\n        Json.Set (o, '@type', s)",
     ""),
    ("JSON-LD written: a list's cells kept as nodes beside the list",
     "  FOR first := 0 TO n - 1 DO consumed[cells[first]] := TRUE END ;",
     ""),
    ("JSON-LD written: rdf:type written as a property",
     "      IF Text.Eq (g.t[i].p.value, RdfNs + 'type') AND g.t[i].o.kind # Kind.Literal THEN",
     "      IF FALSE THEN"),
    ("JSON-LD written: a compact IRI by the wrong prefix",
     "      best := i ; bestLen := LEN (c.defs[i].iri)",
     "      IF best < 0 THEN best := i ; bestLen := LEN (c.defs[i].iri) END"),
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
    if ONLY and ONLY not in name:
        continue
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
        # the RDF/XML suite sits in subdirectories: the output tree mirrors them
        for d in L["xml.eval.action"] + L["xml.neg"]:
            os.makedirs(os.path.join(out, "xml", os.path.dirname(d)), exist_ok=True)
        c3 = subprocess.run([os.path.join(w, "conv"), "xml", "rdf-tests/rdf-xml",
                             L["xml.base"][0], os.path.join(out, "xml")] +
                            L["xml.eval.action"] + L["xml.neg"],
                            cwd=TEST, capture_output=True, text=True)
        # JSON-LD: a run a document, against its own base
        c4 = 0
        for d in L["jld.pos.action"] + L["jld.neg"] + L["jld.syntax"]:
            os.makedirs(os.path.join(out, "jld", os.path.dirname(d)), exist_ok=True)
        for f, b in zip(L["jld.pos.action"], L["jld.pos.base"]):
            c4 |= subprocess.run([os.path.join(w, "conv"), "jld", "jsonld-tests", b, os.path.join(out, "jld"), f],
                                 cwd=TEST, capture_output=True, text=True).returncode
        for f in L["jld.neg"] + L["jld.syntax"]:
            c4 |= subprocess.run([os.path.join(w, "conv"), "jld", "jsonld-tests",
                                  "https://w3c.github.io/json-ld-api/tests/" + f, os.path.join(out, "jld"), f],
                                 cwd=TEST, capture_output=True, text=True).returncode
        j = subprocess.run([sys.executable, "rdfjudge.py", GOLD, "rdf-tests", out],
                           cwd=TEST, capture_output=True, text=True)
        judge_red = c1.returncode != 0 or c2.returncode != 0 or c3.returncode != 0 or c4 != 0 or j.returncode != 0
        if not (test_red or judge_red):
            print(f"rdfsabotage: PASSED (neither gate saw it): {name}")
            held.append(name)
            continue
        by = " and ".join(x for x, red in (("RdfTest", test_red), ("rdflib", judge_red)) if red)
        first = next((l for l in (r.stdout + j.stdout).splitlines()
                      if "FAIL" in l), "")
        print(f"rdfsabotage: red, as it must be, by {by}: {name} -- {first[:110]}")
ran = [n for n, o, w in SABOTAGES if not ONLY or ONLY in n]
print(f"rdfsabotage: {len(ran) - len(held)} of {len(ran)} red")
sys.exit(1 if held else 0)
