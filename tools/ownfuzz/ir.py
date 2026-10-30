"""The shared operation sequence, its heap-model execution, and its M9
translation.

A SEQUENCE is the test case.  It is written one operation per line,
language-neutral, and nothing else in the harness is derived from M9
source:

    NEW x            an owned object, its value the operation's number
    MOVE x y         x := y              (transfer between names)
    BORROW x y       x := Id (y)         (an answer that is its argument)
    STORE y          b.p := y            (store a pointer in the field)
    LOAD x           x := b.p            (copy it out of the field)
    GIVE y           Eat (y)             (transfer to an OWN parameter, which frees it)
    GIVEFIELD        Eat (b.p)
    FREE y           DISPOSE (y)
    READ y           k := k + y.v        (read through a name)
    READFIELD        k := k + b.p.v
    KEEP y           g := SOME (y)       (into module state, read after Go returns)
    KEPTPOOL p       Grow (p, n)         (a pool to a KEPT procedure; p: scratch | mpool | HEAP)

x, y range over the four pointer variables o1 o2 a1 a2.  Every program
ends with RETURN FROM SCOPE: Go returns, its local pool `scratch' dies,
and the module body reads g and last.

Two consumers, sharing nothing but the sequence:
  run (seq)   -- the heap model: objects with a freed flag and a pool,
                 what each operation does to memory.  It knows nothing of
                 M9's rules.  Answers the verdict and a trace.
  to_m9 (seq) -- the translator: the M9 program, one statement (or two)
                 per operation.  It knows nothing of the model.
The translator is trusted test harness; golden/ holds its tests.
"""

VARS = ("o1", "o2", "a1", "a2")
POOLS = ("scratch", "mpool", "HEAP")
ARITY = {  # operation -> argument kinds: v a variable, p a pool
    "NEW": "v", "MOVE": "vv", "BORROW": "vv", "STORE": "v", "LOAD": "v",
    "GIVE": "v", "GIVEFIELD": "", "FREE": "v", "READ": "v",
    "READFIELD": "", "KEEP": "v", "KEPTPOOL": "p",
}
FIELD_OPS = ("LOAD", "GIVEFIELD", "READFIELD")   # may raise IndexError (an unset field)


# ---------------------------------------------------------------- text

def parse(text):
    seq = []
    for ln, line in enumerate(text.splitlines(), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        op, *args = line.split()
        if op not in ARITY:
            raise ValueError(f"line {ln}: unknown operation {op}")
        kinds = ARITY[op]
        if len(args) != len(kinds):
            raise ValueError(f"line {ln}: {op} takes {len(kinds)} arguments")
        for a, k in zip(args, kinds):
            if (k == "v" and a not in VARS) or (k == "p" and a not in POOLS):
                raise ValueError(f"line {ln}: {op}: bad argument {a}")
        seq.append((op, *args))
    return seq


def show(seq):
    return "".join(" ".join(s) + "\n" for s in seq)


# ---------------------------------------------------------------- the heap model

class Unsafe(Exception):
    pass


class Raised(Exception):
    pass


def run(seq):
    """Execute SEQ on the heap model.  Answers (verdict, reason, trace,
    output) -- output the line a safe run prints, `total N' or `raised':
    verdict 'unsafe' (a freed object read or freed again, pool storage
    freed, NULL followed), 'raises' (an unset field followed or copied:
    IndexError, the program stops there, safely), or 'safe'."""
    objs = {}                       # id -> {'freed', 'pool': None | name, 'v'}
    var = {v: None for v in VARS}   # None is NULL
    st = {"field": None, "g": None, "last": None, "k": 0}
    trace = []

    def alloc(pool, v):
        oid = len(objs) + 1
        objs[oid] = {"freed": False, "pool": pool, "v": v}
        return oid

    def name(oid):
        return "NULL" if oid is None else f"#{oid}"

    def deref(oid, what):
        if oid is None:
            raise Unsafe(f"{what} follows NULL")
        if objs[oid]["freed"]:
            raise Unsafe(f"{what} reads freed #{oid}")

    def free(oid, what):
        if oid is None:
            trace.append(f"{what}: NULL, nothing freed")
            return
        if objs[oid]["freed"]:
            raise Unsafe(f"{what} frees #{oid} a second time")
        if objs[oid]["pool"] is not None:
            raise Unsafe(f"{what} frees #{oid}, which lives in pool {objs[oid]['pool']}")
        objs[oid]["freed"] = True
        trace.append(f"{what}: #{oid} freed")

    def field():
        if st["field"] is None:
            raise Raised("b.p is unset: IndexError")
        return st["field"]

    try:
        for i, (op, *a) in enumerate(seq, 1):
            if op == "NEW":
                var[a[0]] = alloc(None, i)
                trace.append(f"{a[0]} = #{var[a[0]]}")
            elif op in ("MOVE", "BORROW"):
                var[a[0]] = var[a[1]]
                trace.append(f"{a[0]} = {name(var[a[0]])}")
            elif op == "STORE":
                st["field"] = var[a[0]]
                trace.append(f"b.p = {name(st['field'])}")
            elif op == "LOAD":
                var[a[0]] = field()
                trace.append(f"{a[0]} = {name(var[a[0]])}")
            elif op == "GIVE":
                free(var[a[0]], f"GIVE {a[0]}")
            elif op == "GIVEFIELD":
                # an OWN argument is passed by its ADDRESS (&b.p): the field
                # is not read, so an unset one does not raise -- the callee
                # DISPOSEs NULL, which frees nothing (found by the fuzzer's
                # MISMATCH class, 82 of 1000 sequences, 2026-10-28)
                free(st["field"], "GIVEFIELD")
            elif op == "FREE":
                free(var[a[0]], f"FREE {a[0]}")
            elif op == "READ":
                deref(var[a[0]], f"READ {a[0]}")
                st["k"] += objs[var[a[0]]]["v"]
                trace.append(f"read {name(var[a[0]])}")
            elif op == "READFIELD":
                deref(field(), "READFIELD")
                st["k"] += objs[st["field"]]["v"]
                trace.append(f"read {name(st['field'])}")
            elif op == "KEEP":
                st["g"] = var[a[0]]
                trace.append(f"g = {name(st['g'])}")
            elif op == "KEPTPOOL":
                st["last"] = alloc(a[0], i)
                trace.append(f"last = #{st['last']} in {a[0]}")
        for o in objs.values():          # RETURN FROM SCOPE
            if o["pool"] == "scratch":
                o["freed"] = True
        trace.append("return: scratch freed")
        if st["g"] is not None:
            deref(st["g"], "body reads g")
            st["k"] += objs[st["g"]]["v"]
            trace.append(f"body read g {name(st['g'])}")
        if st["last"] is not None:
            deref(st["last"], "body reads last")
            st["k"] += objs[st["last"]]["v"]
            trace.append(f"body read last {name(st['last'])}")
    except Raised as r:
        trace.append(str(r))
        return "raises", str(r), trace, "raised"
    except Unsafe as u:
        trace.append(str(u))
        return "unsafe", str(u), trace, ""
    return "safe", "", trace, f"total {st['k']}"


# ---------------------------------------------------------------- the translator

def statement(i, op, *a):
    n = i  # the value an object or a cell is given: the operation's number
    if op == "NEW":
        return f"{a[0]} := NEW (OWN, T) ;\n  {a[0]}.v := {n}"
    return {
        "MOVE": lambda: f"{a[0]} := {a[1]}",
        "BORROW": lambda: f"{a[0]} := Id ({a[1]})",
        "STORE": lambda: f"b.p := {a[0]}",
        "LOAD": lambda: f"{a[0]} := b.p",
        "GIVE": lambda: f"Eat ({a[0]})",
        "GIVEFIELD": lambda: "Eat (b.p)",
        "FREE": lambda: f"DISPOSE ({a[0]})",
        "READ": lambda: f"k := k + {a[0]}.v",
        "READFIELD": lambda: "k := k + b.p.v",
        "KEEP": lambda: f"g := SOME ({a[0]})",
        "KEPTPOOL": lambda: f"Grow ({a[0]}, {n})",
    }[op]()


def to_m9(name, seq):
    raises = any(op in FIELD_OPS for op, *_ in seq)
    head = "PROCEDURE Go () RAISES IndexError =" if raises else "PROCEDURE Go () ="
    body = " ;\n  ".join(statement(i, *s) for i, s in enumerate(seq, 1)) if seq else ""
    body = f"  {body} ;\n" if body else ""
    handler = "| IndexError (a, b) : Io.WriteLine ('raised')\n" if raises else ""
    return f"""MODULE {name} ;
(* from ownfuzz/ir.py *)
IMPORT Io, Fmt ;
TYPE
  T = RECORD v : I64 END ;
  B = RECORD p : PTR T END ;
  Cell = RECORD v : I64 END ;
VAR
  g : OPT PTR T ;
  last : OPT PTR Cell ;
  mpool : POOL ;
  total : I64 ;
PROCEDURE Eat (OWN p: PTR T) =
BEGIN
  DISPOSE (p)
END Eat ;
PROCEDURE Id (a: PTR T) : PTR T =
BEGIN
  RETURN a
END Id ;
PROCEDURE Grow (VAR KEPT p: POOL ; n: I64) =
VAR c : PTR Cell ;
BEGIN
  c := NEW (p, Cell) ;
  c.v := n ;
  last := SOME (c)
END Grow ;
{head}
VAR
  o1, o2, a1, a2 : PTR T ;
  b : B ;
  scratch : POOL ;
  k : I64 ;
BEGIN
  k := 0 ;
{body}  total := k
END Go ;
BEGIN
  total := 0 ;
  Go () ;
  IF g IS SOME x THEN total := total + x.v END ;
  IF last IS SOME c THEN total := total + c.v END ;
  Io.WriteLine ('total ' + Fmt.I64Str (total))
EXCEPT
{handler}| Io.IOError (m) : RETURN
END {name}.
"""
