#!/usr/bin/env python3
"""rdfjudge -- rdflib judges what Rdf read (runtime/test/rdf.sh).

    rdfjudge.py GOLD TESTS OUT

OUT/ttl, OUT/nt, OUT/xml and OUT/jld hold RdfConv's answers, FILE.nt and FILE.ttl or
FILE.err per test document; the .ttl is held to the .nt, read by
rdflib's Turtle reader.
For a Turtle evaluation test the graph M9 wrote must be ISOMORPHIC to the
expected N-Triples the W3C suite gives; for a positive syntax test, to
rdflib's own reading of the same document; a negative test must have
been refused.  rdflib reads M9's output as N-Triples, so the output is
also held to be N-Triples.  Literals are compared as written: rdflib's
literal normalisation is off, or "01"^^xsd:integer would equal "1" --
but for the two readings of rdflib's own that canon() undoes.

rdflib is the oracle here except where it cannot read a document the
suite says is valid (its N-Triples reader wants a space between terms,
which the grammar does not): an N-Triples document is then read by its
Turtle reader, N-Triples being a subset of Turtle, and one it can read
neither way is NAMED in the output and held only to the suite's verdict
-- M9 must have read it.
"""
import logging
import os
import sys

import rdflib

# rdflib warns, with a traceback, about an ill-typed literal it reads
# (the RDF/XML suite has "flargh"^^xsd:integer); that is not a verdict
logging.getLogger("rdflib").setLevel(logging.ERROR)
from rdflib.compare import isomorphic

rdflib.NORMALIZE_LITERALS = False

gold, tests, out = sys.argv[1], sys.argv[2], sys.argv[3]
lists = {}
base = ""
for line in open(gold, encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        continue
    f = line.split()
    lists[f[0]] = f[3:]
base = lists["ttl.base"][0]

fails = []
judged = 0
unwritable = 0
unread = []


XSD = "http://www.w3.org/2001/XMLSchema#"
SIGNED = {XSD + "integer", XSD + "decimal", XSD + "double"}


def by_value(lex, dt):
    """a number's value written one way: rdflib's Turtle reader respells
    numbers, and differently by version (7.6.0: +123 as 123, .1 as 0.1;
    6.1.1 doubles too), so where it is the reference both sides are
    compared by value"""
    from decimal import Decimal, InvalidOperation
    try:
        if dt == XSD + "double":
            return repr(float(lex))
        return str(Decimal(lex).normalize())
    except (ValueError, InvalidOperation):
        return lex


def canon(g, numbers):
    """the graph with rdflib's own readings undone, on both sides alike:
    "x"^^xsd:string is "x" in RDF 1.1 and rdflib keeps them apart; and
    where rdflib's TURTLE reader is the reference (numbers TRUE), it
    respells a number whatever NORMALIZE_LITERALS says, so numbers are
    compared by value there (by_value).  An
    evaluation test is held to the suite's own N-Triples, as written."""
    c = rdflib.Graph()
    for s, p, o in g:
        if isinstance(o, rdflib.Literal) and o.language is None:
            dt = str(o.datatype) if o.datatype is not None else None
            if dt == XSD + "string":
                o = rdflib.Literal(str(o))
            elif numbers and dt in SIGNED:
                o = rdflib.Literal(by_value(str(o), dt), datatype=o.datatype)
        c.add((s, p, o))
    return c


def m9graph(name):
    p = os.path.join(out, name + ".nt")
    if not os.path.exists(p):
        err = open(os.path.join(out, name + ".err"), encoding="utf-8").read().strip()
        raise RuntimeError("M9 refused it: " + err)
    g = rdflib.Graph()
    g.parse(p, format="nt")
    return g


def judge(name, expect, numbers):
    global judged
    judged += 1
    try:
        got = m9graph(name)
    except Exception as e:  # noqa: BLE001 -- any failure is a verdict
        fails.append(f"{name}: {e}")
        return
    if not isomorphic(canon(got, numbers), canon(expect, numbers)):
        fails.append(f"{name}: not the graph expected ({len(got)} triples, {len(expect)} expected)")
    # the Turtle M9 wrote of the same graph, read by rdflib's Turtle
    # reader (which respells numbers: compared by value)
    ttl = rdflib.Graph()
    try:
        ttl.parse(os.path.join(out, name + ".ttl"), format="turtle")
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name}: rdflib cannot read the Turtle M9 wrote: {e}")
        return
    if not isomorphic(canon(ttl, True), canon(got, True)):
        fails.append(f"{name}: the Turtle M9 wrote is not the graph it read ({len(ttl)} triples, {len(got)} read)")
    # and the JSON-LD M9 wrote, read by rdflib's json-ld parser (lexical
    # forms kept: the writer types every literal as it was)
    jld = rdflib.Graph()
    try:
        jld.parse(os.path.join(out, name + ".jsonld"), format="json-ld")
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name}: rdflib cannot read the JSON-LD M9 wrote: {e}")
        return
    if not isomorphic(canon(jld, False), canon(got, False)):
        fails.append(f"{name}: the JSON-LD M9 wrote is not the graph it read ({len(jld)} triples, {len(got)} read)")
    # and the RDF/XML M9 wrote, read by rdflib's xml parser; a predicate
    # with no local name cannot be written by anyone (rdflib raises on
    # it too) and is accepted as refused, counted
    global unwritable
    rdfp = os.path.join(out, name + ".rdf")
    if not os.path.exists(rdfp):
        err = open(rdfp + ".err", encoding="utf-8").read().strip()
        if err.startswith("no local name: "):
            unwritable += 1
            return
        # XML 1.0 cannot carry a control character (other than tab, line
        # feed, carriage return): Xml's writer refuses one, rightly -- but
        # only where the graph really holds one
        if err.startswith("xml: a character no XML document may hold"):
            def bad(t):
                return any((ord(c) < 0x20 and c not in "\t\n\r") or ord(c) in (0xFFFE, 0xFFFF)
                           or 0xD800 <= ord(c) <= 0xDFFF for c in str(t))
            if any(bad(x) for tr in got for x in tr):
                unwritable += 1
                return
            fails.append(f"{name}: RDF/XML refused a character the graph does not hold: {err}")
            return
        fails.append(f"{name}: RDF/XML not written: {err}")
        return
    xml = rdflib.Graph()
    try:
        xml.parse(rdfp, format="xml")
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name}: rdflib cannot read the RDF/XML M9 wrote: {e}")
        return
    if not isomorphic(canon(xml, False), canon(got, False)):
        fails.append(f"{name}: the RDF/XML M9 wrote is not the graph it read ({len(xml)} triples, {len(got)} read)")


def refused(name):
    global judged
    judged += 1
    p = os.path.join(out, name + ".err")
    if not os.path.exists(p):
        fails.append(f"{name}: a negative test was READ")
    elif open(p, encoding="utf-8").read().strip() == "ValueRange":
        fails.append(f"{name}: refused by ValueRange, not a SyntaxError")


tt = os.path.join(tests, "rdf-turtle")
nt = os.path.join(tests, "rdf-n-triples")
for act, res in zip(lists["ttl.eval.action"], lists["ttl.eval.result"]):
    e = rdflib.Graph()
    e.parse(os.path.join(tt, res), format="nt")
    judge("ttl/" + act, e, False)


def reference(path, formats, public):
    """rdflib's reading of a document the suite calls valid, or None"""
    for fmt in formats:
        e = rdflib.Graph()
        try:
            e.parse(path, format=fmt, publicID=public)
            return e
        except Exception:  # noqa: BLE001 -- rdflib's refusal, any kind
            pass
    return None


def syntax(name, path, formats, public):
    global judged
    e = reference(path, formats, public)
    if e is not None:
        judge(name, e, True)
        return
    judged += 1
    unread.append(name)
    if not os.path.exists(os.path.join(out, name + ".nt")):
        fails.append(f"{name}: a positive test was refused")


xt = os.path.join(tests, "rdf-xml")
for act, res in zip(lists["xml.eval.action"], lists["xml.eval.result"]):
    e = rdflib.Graph()
    e.parse(os.path.join(xt, res), format="nt")
    judge("xml/" + act, e, False)
for act in lists["xml.neg"]:
    refused("xml/" + act)
# JSON-LD: the expected N-Quads' DEFAULT graph (the reader keeps that
# one), lexical forms as written
jt = os.path.join(os.path.dirname(os.path.abspath(tests)), "jsonld-tests")   # beside rdf-tests
for act, res in zip(lists["jld.pos.action"], lists["jld.pos.result"]):
    ds = rdflib.Dataset()
    ds.parse(os.path.join(jt, res), format="nquads")
    e = rdflib.Graph()
    # rdflib 7 names the default graph `default_graph`; 6.1.1 (Ubuntu
    # 24.04's python3-rdflib, the CI image's) only `default_context`.
    # CI was red on this line for three pushes while the suite's 7.6
    # venv passed it (2026-10-08).
    dg = getattr(ds, "default_graph", None)
    if dg is None:
        dg = ds.default_context
    for s, p, o in dg:
        e.add((s, p, o))
    judge("jld/" + act, e, False)
for act in lists["jld.neg"]:
    refused("jld/" + act)
for act in lists["jld.syntax"]:
    judged += 1
    if not os.path.exists(os.path.join(out, "jld/" + act + ".nt")):
        fails.append(f"jld/{act}: a positive syntax test was refused")
for act in lists["ttl.pos"]:
    syntax("ttl/" + act, os.path.join(tt, act), ["turtle"], base + act)
for act in lists["nt.pos"]:
    syntax("nt/" + act, os.path.join(nt, act), ["nt", "turtle"], None)
for act in lists["ttl.neg"]:
    refused("ttl/" + act)
for act in lists["nt.neg"]:
    refused("nt/" + act)

for u in unread:
    print("rdf: rdflib cannot read " + u + ", held to the suite's verdict")
for f in fails:
    print("rdf: FAIL " + f)
print(f"rdf: {judged} documents judged by rdflib {rdflib.__version__}, {len(fails)} failed; {unwritable} RDF/XML cannot carry (a predicate with no local name, a control character)")
sys.exit(1 if fails else 0)
