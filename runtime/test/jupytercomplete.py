"""Completion and inspection in the M9 kernel, asked the way JupyterLab
asks (complete_request, inspect_request), answered from m9c --json;
jupyter.sh calls this after jupytercheck.py.

The oracle is NOT the kernel's source: the names and headings are read
from docs/modules/NbCells.md, which docdiff holds to the compiler.  A
library cell is defined, completed, then defined again with one more
procedure, which must show -- the kernel's cache answers by the cell's
file, not by the first answer.

usage: python3 jupytercomplete.py DOCS_MODULES_DIR WORKDIR
"""

import os
import re
import sys

from jupyter_client.manager import start_new_kernel

docs, work = sys.argv[1], sys.argv[2]
os.chdir(work)

page = open(os.path.join(docs, "NbCells.md"), encoding="utf-8").read()
headings = {m.group(1): m.group(0)[4:].strip()
            for m in re.finditer(r"^### ([A-Za-z][A-Za-z0-9]*) \(.*$", page, re.M)}

km, kc = start_new_kernel(kernel_name="m9")
bad = []


def want(cond, what):
    if not cond:
        bad.append(what)


def complete(code, pos=None):
    pos = len(code) if pos is None else pos
    return kc.complete(code, pos, reply=True, timeout=120)["content"]


def inspect(code, pos):
    return kc.inspect(code, pos, reply=True, timeout=120)["content"]


def run(code):
    kc.execute(code, reply=True, timeout=600)


try:
    r = complete("NbCells.Get")
    want(r["matches"] == sorted(n for n in headings if n.startswith("Get")),
         "NbCells.Get completes to the Get procedures the page lists: %r" % r["matches"])
    want(r["cursor_start"] == len("NbCells."), "the completion replaces only the prefix")
    code = "  g := NbCells.GetGrid (pool, 'field')"
    r = inspect(code, code.index("GetGrid") + 3)
    text = r.get("data", {}).get("text/plain", "")
    want(r.get("found") and ("NbCells." + headings["GetGrid"]) in text,
         "Shift-Tab on NbCells.GetGrid shows its heading as the page has it: %r" % text[:160])
    r = complete("IMPORT NbCe")
    want("NbCells" in r["matches"] and "NbCellsTest" not in r["matches"],
         "a bare prefix completes to library modules, not tests: %r" % r["matches"])
    want(complete("Nosuch.x")["matches"] == [], "an unknown module completes to nothing")
    k1 = ("DEFINITION MODULE Kelvin ;\nPROCEDURE FromCelsius (c: F64) : F64 ;\n"
          "END Kelvin.\nIMPLEMENTATION MODULE Kelvin ;\n"
          "PROCEDURE FromCelsius (c: F64) : F64 =\nBEGIN\n  RETURN c + 273.15\n"
          "END FromCelsius ;\nEND Kelvin.\n")
    run(k1)
    want(complete("Kelvin.F")["matches"] == ["FromCelsius"],
         "a library cell's module completes")
    k2 = k1.replace("END Kelvin.\nIMPLEMENTATION",
                    "PROCEDURE ToFahrenheit (c: F64) : F64 ;\nEND Kelvin.\nIMPLEMENTATION") \
           .replace("END FromCelsius ;\n",
                    "END FromCelsius ;\nPROCEDURE ToFahrenheit (c: F64) : F64 =\n"
                    "BEGIN\n  RETURN c * 1.8 + 32.0\nEND ToFahrenheit ;\n")
    run(k2)
    want(complete("Kelvin.")["matches"] == ["FromCelsius", "ToFahrenheit"],
         "the library cell run again is completed as it is now: %r"
         % complete("Kelvin.")["matches"])
finally:
    kc.stop_channels()
    km.shutdown_kernel(now=True)

if bad:
    for b in bad:
        print("jupyter: FAIL:", b)
    sys.exit(1)
print("jupyter: completion and inspection answer from m9c --json, as the page says")
