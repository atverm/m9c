"""In-memory state between notebook cells (docs/notebook-state-plan.md,
phase 1), asked of the kernel the way JupyterLab asks; jupyter.sh calls
this after jupytercheck.py.

Held: a state cell's body runs ONCE, in the session; a program cell
sees its values; a program's write to them stays in its fork (the next
program sees the original); a program's Io.Halt (3) is its status and
not the session's end; an interrupted program leaves the session
alive; a state cell run again is a new GENERATION -- its new values
are what later cells see -- and every state cell importing it runs
again after it, so nothing computed from the old one survives
(phase 2; Alex: "rerun dependents"); a program cell that read the old
state is named with its cell number, to be run again; a cell holding
only an expression shows its value, a frame as an HTML table.

usage: python3 jupytersession.py WORKDIR
"""

import os
import re
import sys
import time

from jupyter_client.manager import start_new_kernel

os.chdir(sys.argv[1])
os.environ.pop("M9KERNEL_STATELESS", None)

ROOTS = """STATEFUL DEFINITION MODULE Roots ;
VAR
  xs : SLICE OF F64 ;
  runs : I64 ;
END Roots.
IMPLEMENTATION MODULE Roots ;
IMPORT Io ;
IMPORT Math ;
VAR i : I64 ;
BEGIN
  xs := NEW (F64, 5) ;
  FOR i := 0 TO 4 DO xs[i] := Math.Sqrt (F64 (i)) END ;
  runs := runs + 1 ;
  Io.WriteLine ('Roots body ran')
EXCEPT
| ValueRange :
    Io.ErrLine ('a root failed')
END Roots.
"""

USE = """MODULE UseRoots ;
IMPORT Io ;
IMPORT Fmt ;
IMPORT Roots ;
VAR
  s : F64 ;
  i : I64 ;
BEGIN
  s := 0.0 ;
  FOR i := 0 TO LEN (Roots.xs) - 1 DO s := s + Roots.xs[i] END ;
  Io.WriteLine ('sum ' + Fmt.Fixed (s, 6) + ', xs[1] ' +
                Fmt.Fixed (Roots.xs[1], 3) + ', runs ' + Fmt.I64Str (Roots.runs)) ;
  Roots.xs[1] := 99.0 ;
  Io.Halt (3)
EXCEPT
| ValueRange :
    Io.Halt (2)
END UseRoots.
"""

B = """STATEFUL DEFINITION MODULE B ;
VAR total : F64 ;
END B.
IMPLEMENTATION MODULE B ;
IMPORT Io ;
IMPORT Roots ;
VAR i : I64 ;
BEGIN
  total := 0.0 ;
  FOR i := 0 TO LEN (Roots.xs) - 1 DO total := total + Roots.xs[i] END ;
  Io.WriteLine ('B body ran')
END B.
"""

USEB = """MODULE UseB ;
IMPORT Io ;
IMPORT Fmt ;
IMPORT B ;
BEGIN
  Io.WriteLine ('B.total ' + Fmt.Fixed (B.total, 6))
EXCEPT
| ValueRange :
    Io.Halt (2)
END UseB.
"""

TAB = """STATEFUL DEFINITION MODULE Tab ;
IMPORT Frame ;
VAR f : PTR Frame.Fr ;
END Tab.
IMPLEMENTATION MODULE Tab ;
IMPORT Faults ;
IMPORT Frame ;
IMPORT Io ;
VAR
  pool : POOL ;
  x : SLICE OF F64 ;
BEGIN
  f := Frame.New (pool, 2) ;
  x := NEW (pool, F64, 2) ;
  x[0] := 1.5 ;
  x[1] := 0.0 / 0.0 ;
  Frame.AddF64 (pool, f, 'co2', x, -1.0)
EXCEPT
| Faults.SizeError :
    Io.ErrLine ('no frame')
| Frame.Duplicate :
    Io.ErrLine ('no frame')
END Tab.
"""

SPIN = """MODULE Spin ;
IMPORT Io ;
VAR n : I64 ;
BEGIN
  Io.ErrLine ('spinning') ;
  n := 0 ;
  WHILE TRUE DO n := (n + 1) MOD 1000 END
END Spin.
"""

km, kc = start_new_kernel(kernel_name="m9")
bad = []


def want(cond, what):
    if not cond:
        bad.append(what)


shown = []      # the last run's display_data, each its data dict


def run(code, timeout=600):
    """execute; answer (status, stdout, stderr, error evalue)"""
    msg_id = kc.execute(code)
    out, err, evalue = [], [], None
    del shown[:]
    while True:
        m = kc.get_iopub_msg(timeout=timeout)
        if m["parent_header"].get("msg_id") != msg_id:
            continue
        t = m["msg_type"]
        if t == "stream":
            (out if m["content"]["name"] == "stdout" else err).append(m["content"]["text"])
        elif t == "error":
            evalue = m["content"]["evalue"]
        elif t == "display_data":
            shown.append(m["content"]["data"])
        elif t == "status" and m["content"]["execution_state"] == "idle":
            break
    reply = kc.get_shell_msg(timeout=timeout)
    return reply["content"]["status"], "".join(out), "".join(err), evalue


try:
    st, out, err, ev = run(ROOTS)
    want(st == "ok" and out.startswith("Roots body ran\n"),
         "the state cell's body runs once, in the session: %r %r" % (st, out))
    # its variables complete and inspect like any declaration (m9c
    # --json named every exported variable "" until 2026-10-04)
    r = kc.complete("Roots.", 6, reply=True, timeout=120)["content"]
    want(r["matches"] == ["runs", "xs"], "Roots. completes to its variables: %r" % r["matches"])
    r = kc.inspect("Roots.xs", 7, reply=True, timeout=120)["content"]
    want("VAR xs : SLICE OF F64" in r.get("data", {}).get("text/plain", ""),
         "Shift-Tab on Roots.xs shows its declaration: %r" % r.get("data"))
    st, out, err, ev = run(USE)
    want(out == "sum 6.146264, xs[1] 1.000, runs 1\n",
         "a program cell reads the state: %r" % out)
    want(ev == "UseRoots exited with status 3", "Io.Halt (3) is the cell's status: %r" % ev)
    st, out, err, ev = run(USE)
    want(out == "sum 6.146264, xs[1] 1.000, runs 1\n",
         "a program's write stays in its fork; the body did not run again: %r" % out)
    # an EXPRESSION cell shows its value (docs/kernel-show-plan.md)
    st, out, err, ev = run("Roots.xs")
    want(st == "ok" and out == "[0.0, 1.0, 1.4142135623730951, 1.7320508075688772, 2.0]\n",
         "an expression cell shows the state's value, reals that read back: %r %r %r"
         % (st, out, err))
    st, out, err, ev = run("Roots.xs[1] +\n  nosuch")
    want(st == "error" and "2:3" in err and "unknown name: nosuch" in err,
         "an expression the checker refuses is an error at the cell's own line:col: %r %r"
         % (st, err))
    st, out, err, ev = run(TAB)
    want(st == "ok", "a state cell holding a frame: %r %r" % (out, err))
    st, out, err, ev = run("Tab.f")
    want(st == "ok" and len(shown) == 1 and "<td>null</td>" in shown[0].get("text/html", "")
         and "1 rows x 1 columns" not in shown[0].get("text/plain", "")
         and "2 rows x 1 columns" in shown[0].get("text/plain", ""),
         "a frame shows as one table, HTML with its text beside it: %r %r %r"
         % (st, shown, err))
    # an interrupt with NOTHING running reaches the session host too
    # (Jupyter signals the kernel's process group); the host must take
    # it and go on reading -- it ended on EINTR in fgets (CI, 2026-10-04)
    km.interrupt_kernel()
    time.sleep(1)
    st, out, err, ev = run(USE)
    want(out == "sum 6.146264, xs[1] 1.000, runs 1\n",
         "an interrupt between cells leaves the session alive: %r %r" % (out, err))
    # interrupt the PROGRAM, not its build: wait until it says it runs
    # (stderr, unbuffered).  A fixed sleep interrupted m9c on CI's cold
    # cache, 2026-10-04.
    msg_id = kc.execute(SPIN)
    while True:
        m = kc.get_iopub_msg(timeout=600)
        if m["parent_header"].get("msg_id") == msg_id and m["msg_type"] == "stream" \
           and "spinning" in m["content"]["text"]:
            break
    time.sleep(0.5)
    km.interrupt_kernel()
    st, out, err, ev = None, "", "", None
    while True:
        m = kc.get_iopub_msg(timeout=120)
        if m["parent_header"].get("msg_id") == msg_id and m["msg_type"] == "status" \
           and m["content"]["execution_state"] == "idle":
            break
    kc.get_shell_msg(timeout=120)
    st, out, err, ev = run(USE)
    want(out == "sum 6.146264, xs[1] 1.000, runs 1\n",
         "an interrupted program leaves the session and its state: %r %r" % (out, err))
    st, out, err, ev = run(B)
    want(st == "ok" and out.startswith("B body ran\n"), "a state cell imports a state cell: %r" % out)
    st, out, err, ev = run(USEB)
    want(out == "B.total 6.146264\n", "B computed from Roots: %r" % out)
    # Roots run again, computing other values: a new generation, and B,
    # which imports it, runs again after it
    st, out, err, ev = run(ROOTS.replace("Math.Sqrt (F64 (i))", "F64 (i)")
                               .replace("Roots body ran", "Roots body ran AGAIN"))
    want(st == "ok" and out.startswith("Roots body ran AGAIN\n")
         and "module Roots ran again (generation 2)" in out
         and "B body ran\n" in out
         and "re-ran B (generation 2), which imports Roots" in out
         and out.index("Roots body ran AGAIN") < out.index("B body ran"),
         "Roots runs again, then B, which imports it: %r %r %r %r" % (st, out, err, ev))
    # the program cells that read the old Roots or B are NAMED, with
    # their cell numbers; Spin read no state and is not
    stale = re.search(r"out of date, they read the old values -- run them again: (.*)\n", out)
    want(stale is not None and
         re.fullmatch(r"Roots\.xs \[\d+\], UseB \[\d+\], UseRoots \[\d+\]", stale.group(1)),
         "the programs that read the old state are named, an expression by its text: %r" % out)
    st, out, err, ev = run("Roots.xs")
    want(out == "[0.0, 1.0, 2.0, 3.0, 4.0]\n",
         "the expression run again shows the new generation: %r %r" % (out, err))
    st, out, err, ev = run(USE)
    want(out == "sum 10.000000, xs[1] 1.000, runs 1\n",
         "a program after the re-run sees the new generation: %r %r" % (out, err))
    st, out, err, ev = run(USEB)
    want(out == "B.total 10.000000\n",
         "and B recomputed from it -- nothing kept from the old Roots: %r %r" % (out, err))
    # both ran again and read the new state; B alone run again leaves
    # UseRoots, which does not read B, up to date
    st, out, err, ev = run(B)
    stale = re.search(r"run them again: (.*)\n", out)
    want(stale is not None and re.fullmatch(r"UseB \[\d+\]", stale.group(1)),
         "after B runs again only UseB is out of date: %r" % out)
finally:
    kc.stop_channels()
    km.shutdown_kernel(now=True)

if bad:
    for b in bad:
        print("jupyter: FAIL:", b)
    sys.exit(1)
print("jupyter: a state cell runs once in the session; programs read it, cannot change it, halt and are interrupted without ending it; run again it is a new generation and its dependents run again; an expression cell shows its value")
