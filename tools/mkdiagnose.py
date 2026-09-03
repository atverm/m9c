#!/usr/bin/env python3
"""mkdiagnose.py -- the M9 diagnostics table, GENERATED from probes/.

Each file in probes/ is the smallest program that earns one checker
refusal, with the expected message on its first line -- and
probediff.sh holds both checkers to that message.  So the message
column of docs/diagnose.md cannot drift: it is read from the probe,
never typed here.

What IS typed here is the cause and the fix, one line each, keyed by
probe name.  A probe without an entry makes this script FAIL, so a
new refusal cannot be added to the checker without also being
explained -- the same shape as docdiff's drift gate, applied to the
explanation instead of the signature.

    python3 tools/mkdiagnose.py            regenerate docs/diagnose.md
    python3 tools/mkdiagnose.py --check    exit 1 if it would change

runtime/test/diagdiff.sh is the gate and calls --check.
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROBES = os.path.join(ROOT, "probes")
OUT = os.path.join(ROOT, "docs", "diagnose.md")

# probe name -> (cause, fix).  Report sections as "par N.M".
EXPLAIN = {
    "adr-outside-unsafe": (
        "ADR takes the address of a value, which is the one thing the memory rules cannot check",
        "put the procedure in an UNSAFE module, or pass a SLICE/VAR instead of an address (par 7)"),
    "alias-nonscalar-conversion": (
        "a type alias converts under its own name only when it aliases a scalar; a record alias is not a conversion",
        "construct the record; conversions are for numeric widths and CHAR"),
    "all-outside-a-view": (
        "ALL is the axis-keeping marker for VIEW and has no value outside one",
        "use ALL only as a VIEW argument; a whole-axis loop is FOR i := 0 TO LEN (g, k) - 1"),
    "arity-mismatch": (
        "the call passes a different number of arguments from the declaration",
        "read the signature in docs/modules/<M>.md; every parameter is positional and required"),
    "byte-arithmetic": (
        "BYTE is a raw octet, not a number: no +, -, comparison as magnitude",
        "convert with U8 (b) or I64 (b) first, and back with BYTE (x), each of which RAISES ValueRange"),
    "case-label-mismatch": (
        "the CASE label's type is not the selector's type",
        "labels must be literals or CONSTs of the selector's type; a CHAR selector takes 'x' or 41C"),
    "case-record-selected": (
        "the variant payload of a CASE RECORD is reached only through a CASE arm that binds it",
        "write CASE v OF | Kind.Str (s) : ... END; never v.field on the variant part"),
    "compare-mismatch": (
        "the two sides of a comparison have different types and nothing converts implicitly",
        "convert one side explicitly; for strings use DynStr.Eq / Text.Eq, not = (par 2.1)"),
    "concat-char": (
        "+ concatenates STRINGS; a CHAR variable is not a string (a 1-char literal is)",
        "append the CHAR with DynStr.AppendChar, or make it a one-character string first"),
    "concat-non-string": (
        "+ on strings takes strings on both sides; an integer literal is not one",
        "format first: Fmt.I64Str (n) or DynStr.AppendI64"),
    "cond-not-bool": (
        "IF/WHILE/ELSIF take a BOOL; an integer is not implicitly a truth value",
        "write the comparison out: IF n # 0 THEN"),
    "conditional-move": (
        "SHARED (s) consumed s on one arm, so after the join s may be gone (moved in ANY arm = moved after)",
        "share on every path, or share before the branch; see par 4.2"),
    "def-not-implemented": (
        "the DEFINITION declares a procedure the IMPLEMENTATION never defines",
        "implement it, or remove it from the definition; the signature is the contract (par 3)"),
    "dispose-a-borrow": (
        "the value came in as a value/VAR/RO parameter -- a borrow -- and a borrow is not yours to free",
        "only OWN parameters and locals holding owned PTRs may be DISPOSEd; move ownership with OWN"),
    "dispose-pool-interior": (
        "PTR T IN pool is carved from a pool and the pool frees it as a whole",
        "never DISPOSE a pool-interior pointer; free the pool (par 4.3, docs/pools.md)"),
    "div-on-float": (
        "DIV and MOD are integer operators",
        "use / for floats; Math.Fmod for a float remainder"),
    "grid-len-axis-exists": (
        "LEN (g, k) names an axis the grid's rank does not have (axes are 0-based)",
        "a GRID 2 has axes 0 and 1"),
    "grid-len-needs-an-axis": (
        "a GRID has one extent per axis, so LEN needs to be told which",
        "LEN (g, 0); LEN (s) without an axis is for slices"),
    "grid-rank-is-part-of-the-type": (
        "GRID 3 OF F64 and GRID 2 OF F64 are different types; rank is in the type, shape in the value",
        "declare the matching rank, or take a VIEW that drops an axis"),
    "grid-subscript-arity": (
        "every axis must be subscripted; a GRID is not a nested array",
        "g[i, j, k] for a GRID 3; VIEW (g, i, ALL, ALL) to select a plane"),
    "implicit-widening": (
        "there is no implicit conversion between any two numeric types, widening included",
        "I64 (x) explicitly; the conversion RAISES ValueRange, which your RAISES set must carry (par 2.1)"),
    "int-literal-to-float": (
        "an integer literal fits any integer type but not a float",
        "write 0.0, 1.0E-6; a <real> literal adapts to F32 or F64"),
    "int-slash-division": (
        "/ is float division",
        "DIV for integers"),
    "is-some-on-non-opt": (
        "IS SOME is the guard for OPT; the operand is not OPT (a cross-module PTR T IN pool may type as unknown and NOT be diagnosed -- check the declaration)",
        "declare the type OPT PTR T, or drop the guard if it cannot be absent"),
    "lend-value-ptr-as-var": (
        "a value PTR parameter is a shared borrow; passing it on as VAR would launder it into a mutable one",
        "take the parameter as VAR yourself if you need to pass it as VAR (par 4.1)"),
    "module-state-without-stateful": (
        "a module-level VAR is state, and a module with state must say so",
        "add [STATEFUL] to the DEFINITION MODULE, or move the state into a record the caller owns (par 6)"),
    "move-borrow-into-own": (
        "an OWN parameter takes ownership, and a borrow has none to give",
        "pass something you own -- a local, an OWN parameter -- or take the argument as VAR instead"),
    "kept-borrow-arg": (
        "a borrowed parameter is passed to a parameter the callee declares KEPT, so the caller is retaining it too",
        "declare the caller's own parameter KEPT as well -- the declaration composes upward, exactly as RAISES does (par 4.1, docs/retention.md)"),
    "kept-concat-arg": (
        "a + result lives in the frame's arena and dies at RETURN, but the callee declares it will keep the argument",
        "build the string in a pool that outlives the retention (DynStr into a caller-supplied pool, or HEAP) and pass that (par 2.3, par 4.1)"),
    "kept-via-local": (
        "a borrowed parameter was copied into a local (or bound by IS SOME or a CASE pattern) and the copy was stored somewhere that outlives the call -- the local carried the borrow",
        "the retention is real even though indirect: declare the parameter KEPT, or copy the bytes instead of the reference (par 4.1, docs/retention.md)"),
    "kept-undeclared": (
        "a borrowed parameter is stored somewhere that outlives the call -- module state, the caller's storage, or the answer -- and the signature does not say so",
        "declare the parameter KEPT so every caller can see the retention, or copy the bytes instead of keeping the borrow (par 4.1, docs/retention.md)"),
    "local-const-shadow": (
        "a procedure declares a CONST with the same name as one the module already declares",
        "rename one of them.  Which would win depends on lookup order, and the map answers the first hit, so the shadow is refused rather than resolved (docs/frame-pools.md)"),
    "undefined-name": (
        "a bare name used as a value is declared nowhere -- not a local, parameter, IS SOME binder, CONST, type, or module",
        "declare it, import the module it comes from, or fix the typo; the checker now names it rather than leaving it to the generator (par: the checker refuses what the generator cannot see)"),
    "unknown-exception": (
        "a RAISE, a RAISES clause or a handler cites an exception name found nowhere -- not declared locally, not predeclared (Overflow/IndexError/OutOfMemory/ValueRange), and not declared in any loaded module",
        "declare the EXCEPTION, or qualify it into the module that owns it (Json.ParseError); an imported exception is reached as Module.Name, never bare -- the checker now refuses what the generator could not emit"),
    "from-m9-module": (
        "FROM ... IMPORT names an M9 module; FROM is for foreign FOR-C units only (there is no Module.m9 the generator can honour that way)",
        "use IMPORT Module and write Module.Name; a Modula-2 unqualified FROM of an M9 module is caught here, at the import, instead of as a generator error later"),
    "concat-escapes-modvar": (
        "a string concatenation (+) is built in the procedure's frame arena and dies when the frame returns; storing it in a module variable, which outlives the frame, leaves the variable pointing at freed storage (par 2.3)",
        "copy it into a durable pool -- DynStr.Append (HEAP, ...), or a pool the caller owns; the module init body is exempt, because there frame and module variable share a lifetime"),
    "concat-escapes-param": (
        "a string concatenation is frame-scoped; a bare VAR/OWN STR parameter is re-homed into the caller's arena at exit, but a COMPONENT reached through a reference parameter (a record field, an element, a value pointer's target) is not, so the caller would hold freed storage (par 2.3)",
        "assign the whole VAR STR parameter, or build the field's string in a pool the caller can see (pass a POOL, or DynStr.Append into the caller's)"),
    "bytesize-not-slice": (
        "ByteSize answers the bytes a slice's elements occupy, so its argument must be a slice",
        "for a scalar or record use SizeOf (x); for the data behind a slice, ByteSize (s) = LEN (s) * SizeOf (element)"),
    "new-reversed": (
        "NEW's arguments are the wrong way round: the pool comes first, then the type",
        "NEW (pool, T) for a pointer, NEW (pool, T, n) for a slice, NEW (pool, T, n1, n2) for a grid (par 4.3)"),
    "no-such-field": (
        "the record has no field of that name",
        "read the record in docs/modules/<M>.md; a variant's payload is reached through CASE"),
    "opaque-not-defined": (
        "the DEFINITION declares an opaque TYPE the IMPLEMENTATION never completes",
        "TYPE T = RECORD ... END in the implementation"),
    "opt-through-field": (
        "an OPT field was read without IS SOME; OPT is traced through fields, not only names",
        "IF r.f IS SOME p THEN ... END, and use p inside (par 2.2)"),
    "pool-escape-on-return": (
        "PTR T IN pool cannot outlive its pool, and this pool dies with the frame",
        "take the pool as a VAR parameter so the caller owns it, or return by value (docs/pools.md)"),
    "result-discarded": (
        "a function's result was not used; M9 does not let a value fall on the floor",
        "assign it, or make the procedure proper if the result is not wanted"),
    "retention-ledgered": (
        "NOT an error: the P3 ledger noting that a borrowed parameter was stored beyond the frame",
        "nothing to fix; it is measured against the kill-gate (docs/p3-ledger.md)"),
    "return-mismatch": (
        "the RETURN's type is not the function's declared result type",
        "convert explicitly, or change the declaration"),
    "return-value-in-proper-proc": (
        "a proper procedure (no ': T') cannot RETURN a value",
        "declare a result type, or RETURN without a value"),
    "signature-differs-from-definition": (
        "the IMPLEMENTATION's procedure heading is not the DEFINITION's, printed canonically (modes, types, RAISES all count)",
        "copy the definition's heading exactly; the IMPLEMENTATION adds only '='"),
    "totality-uses-selector-type": (
        "CASE over a CASE RECORD must name every variant of the selector's own type",
        "add the missing arm; there is no ELSE for variants (par 8)"),
    "unknown-callee": (
        "no procedure of that name is visible -- MOST OFTEN a real name whose module is not IMPORTed in THIS module (an IMPLEMENTATION has its own IMPORT list), otherwise a guessed name",
        "add IMPORT M to the implementation; then confirm the name in docs/modules/M.md or with m9c --doc"),
    "use-after-dispose": (
        "the name was DISPOSEd on an earlier line and is dead",
        "do not read it; re-assign to bring it back to life (par 4.2)"),
    "use-after-move-assign": (
        "assigning a bare owned pointer to another name MOVES it; the source is dead",
        "use the destination; if both must live, that is a SHARED handle"),
    "use-after-shared": (
        "SHARED (s) consumed s; the handle is what lives on",
        "use the SHARED result; s is gone"),
    "var-arg-not-designator": (
        "a VAR or OWN argument must be something that can be written to -- a variable, field or element",
        "store the expression in a local first"),
    "view-axis-count": (
        "VIEW takes exactly one argument per axis of the grid: an index (drops it) or ALL (keeps it)",
        "VIEW (g, i, ALL, ALL) for a GRID 3"),
    "view-keeps-nothing": (
        "a VIEW with an index on every axis is a single element, not a view",
        "subscript instead: g[i, j]"),
    "view-of-a-slice": (
        "VIEW is a GRID operation; a slice has no strides to keep",
        "SLICE (s, start, len) for a sub-slice"),
    "write-through-readonly-field": (
        "the record came in RO, so its fields are read-only too",
        "take it as VAR if it must be written"),
    "write-through-readonly-record": (
        "RO is a read-only borrow",
        "VAR"),
    "case-label-twice": (
        "the same scalar label appears in two arms; the second is dead and "
        "one of the two is a typo -- decided at compile time",
        "remove the duplicate, or widen it to a range if that was meant"),
    "monitor-outside": (
        "a monitor serialises access by letting only its BOUND procedures "
        "reach its fields, and the binding is the FIRST parameter (par 6)",
        "add a short bound procedure -- PROCEDURE Count (VAR g: Gate) : I64 "
        "-- and call that instead"),
    "pure-allocates": (
        "NEW from a pool the CALLER owns consumes the caller's storage and "
        "answers a slice into the caller's arena -- an effect (par 3.2)",
        "use a local VAR scratch: POOL, or drop [PURE]"),
    "pure-writes-var": (
        "a PURE procedure has no observable effect (par 3.2), and writing "
        "through a caller's VAR binding is precisely what the caller observes",
        "answer a value instead of writing through a parameter, or drop [PURE]"),
    "pure-calls-impure": (
        "a PURE procedure may call only PURE procedures -- which is what makes "
        "'no I/O' true without the checker knowing what I/O is, since a foreign "
        "procedure is [SERIAL] or [REENTRANT] and never [PURE]",
        "declare the callee [PURE] too if it really is, or drop [PURE] from the caller"),
    "write-through-readonly-slice": (
        "the slice came in RO ([READONLY]); its elements cannot be assigned",
        "VAR, or copy into a slice you own"),
    "write-through-readonly-str": (
        "STR is SLICE OF CHAR and an RO one is read-only like any slice",
        "VAR, or build a new string with DynStr"),
    "write-through-value-ptr": (
        "a value PTR parameter is a SHARED borrow: readable, not writable (par 4.1)",
        "declare the parameter VAR p: PTR T -- the mutable-handle idiom"),
    "wrong-arg-type": (
        "the argument's type is not the parameter's, and nothing converts implicitly",
        "convert explicitly, or read the signature: docs/modules/<M>.md"),
}


def expect_line(path):
    with io.open(path, encoding="utf-8") as f:
        first = f.readline().rstrip("\n")
    m = re.match(r"\(\* (EXPECT|LEDGER): (.*?) \*\)$", first)
    if not m:
        raise SystemExit("%s: first line is not an EXPECT/LEDGER comment: %r"
                         % (path, first))
    return m.group(1), m.group(2)


def probe_body(path):
    with io.open(path, encoding="utf-8") as f:
        return "".join(f.readlines()[1:]).rstrip("\n")


def render():
    names = sorted(n[:-3] for n in os.listdir(PROBES) if n.endswith(".m9"))
    missing = [n for n in names if n not in EXPLAIN]
    stale = [n for n in EXPLAIN if n not in names]
    if missing or stale:
        for n in missing:
            sys.stderr.write("mkdiagnose: probe %s has no explanation\n" % n)
        for n in stale:
            sys.stderr.write("mkdiagnose: explanation %s has no probe\n" % n)
        raise SystemExit(1)

    out = []
    w = out.append
    w("# M9 diagnostics: message, cause, fix\n")
    w("*GENERATED by `tools/mkdiagnose.py` from `probes/` -- do not edit.*\n")
    w("Every entry is one checker refusal.  The **message** is read from the")
    w("probe's first line, and `probediff.sh` holds both checkers to it, so")
    w("this column cannot drift from what `m9c` prints.  The cause and the")
    w("fix are curated in the generator, keyed by probe name; a probe without")
    w("an entry fails the build.  `runtime/test/diagdiff.sh` is the gate.\n")
    w("A checker message is printed as `LINE:COL Module.Proc: MESSAGE`, then")
    w("`m9c: N errors in FILE`.  A PARSE error is still a bare count with no")
    w("line (`m9c: 4 parse errors in FILE`): run `host/fpc/g1 FILE` for")
    w("`LINE:COL message`.  A GENERATOR error is `FILE:LINE: gen: MESSAGE`.\n")
    w("| message | cause | fix | probe |")
    w("|---|---|---|---|")
    for n in names:
        kind, msg = expect_line(os.path.join(PROBES, n + ".m9"))
        cause, fix = EXPLAIN[n]
        tag = "" if kind == "EXPECT" else " *(ledger, not an error)*"
        w("| `%s`%s | %s | %s | `%s` |"
          % (msg.replace("|", "\\|"), tag, cause, fix, n))
    w("")
    w("## The programs\n")
    w("Each is the smallest program that earns its message.  Reading one is")
    w("faster than reading the rule.\n")
    for n in names:
        kind, msg = expect_line(os.path.join(PROBES, n + ".m9"))
        w("### %s\n" % n)
        w("`%s`\n" % msg)
        w("```")
        w(probe_body(os.path.join(PROBES, n + ".m9")))
        w("```\n")
    return "\n".join(out)


def main():
    text = render()
    if "--check" in sys.argv:
        try:
            with io.open(OUT, encoding="utf-8") as f:
                cur = f.read()
        except IOError:
            cur = None
        if cur != text:
            sys.stderr.write("diagdiff: docs/diagnose.md is stale; run "
                             "python3 tools/mkdiagnose.py\n")
            raise SystemExit(1)
        print("diagdiff: docs/diagnose.md matches probes/ (%d entries)"
              % len(EXPLAIN))
        return
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("docs/diagnose.md: %d entries from probes/" % len(EXPLAIN))


if __name__ == "__main__":
    main()
