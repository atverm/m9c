"""Run tools/jupyter/M9Notebook.ipynb through the M9 kernel and hold
every output to what it must be; jupyter.sh calls this.

Three cells are added to the notebook's own, for what a notebook a
person reads should not show: a program run again after a figure was
written (it must NOT show the old figure: a figure is a file the run
WROTE), a cell with no MODULE heading, and a program that exits 3.

usage: python3 jupytercheck.py NOTEBOOK WORKDIR
"""

import os
import sys

import nbclient
import nbformat
from nbformat.v4 import new_code_cell

nb_path, work = sys.argv[1], sys.argv[2]
nb = nbformat.read(nb_path, as_version=4)
by_id = {c.get("id"): c for c in nb.cells}
nb.cells.append(new_code_cell(by_id["temps"].source, id="temps-again"))
nb.cells.append(new_code_cell("Io.WriteLine ('no heading')", id="no-heading"))
nb.cells.append(new_code_cell(
    "MODULE Fail ;\nIMPORT Io ;\nBEGIN\n  Io.Halt (3)\nEND Fail.", id="fail"))

# as Jupyter's server says which notebook a kernel serves; the kernel
# names NbCells' directory after it, beside the notebook
os.environ.pop("M9CELLS", None)
os.environ["JPY_SESSION_NAME"] = os.path.join(work, "M9Notebook.ipynb")
client = nbclient.NotebookClient(nb, kernel_name="m9", allow_errors=True,
                                 timeout=600, resources={"metadata": {"path": work}})
client.execute()

bad = []


def outputs(cid, kind, name=None):
    cell = next(c for c in nb.cells if c.get("id") == cid)
    return [o for o in cell.outputs
            if o.output_type == kind and (name is None or o.get("name") == name)]


def text(cid, name):
    return "".join(o.text for o in outputs(cid, "stream", name))


def want(cond, what):
    if not cond:
        bad.append(what)


want(text("kelvin", "stdout") ==
     "module Kelvin loaded; its body ran once in this session, and later cells may IMPORT it\n",
     "a library cell is loaded into the session and said so: %r" % text("kelvin", "stdout"))
want(text("temps", "stdout") == "15 C is 288.15 K\n",
     "a program imports an earlier cell's module: %r" % text("temps", "stdout"))
want(not outputs("temps", "error"), "a good program is no error")
d = outputs("damped", "display_data")
want(len(d) == 1 and "damped oscillation" in d[0].data.get("image/svg+xml", ""),
     "the figure a cell wrote is shown under it (%d shown)" % len(d))
want(not outputs("temps-again", "display_data"),
     "a run that wrote no figure shows none -- not an earlier cell's")
want(text("store", "stdout") == "stored: roots (f64s)\n",
     "a cell's NbCells.Put is said by name and kind: %r" % text("store", "stdout"))
want(os.path.isfile(os.path.join(work, "M9Notebook.m9data", "roots.f64s.parquet")),
     "NbCells' files are NOTEBOOK.m9data beside the notebook")
want(text("use", "stdout") == "5 roots, sum 6.146264\n",
     "a later cell reads what an earlier one stored: %r" % text("use", "stdout"))
want(not outputs("use", "error"), "the reading cell is no error")
want("6:8 Narrow body: integer literal 40000000000 does not fit I32"
     in text("narrow", "stderr"),
     "a refusal carries the cell's own line:col: %r" % text("narrow", "stderr"))
e = outputs("narrow", "error")
want(len(e) == 1 and e[0].ename == "M9", "a refused cell is a failed cell")
# a cell with no heading is an EXPRESSION cell (docs/kernel-show-plan.md);
# a call of a procedure that answers nothing has no value to show
e = outputs("no-heading", "error")
want(len(e) == 1 and e[0].evalue == "the expression was not shown"
     and "this has no value" in text("no-heading", "stderr"),
     "a cell with no heading and no value is refused, saying why: %r %r"
     % ([o.get("evalue") for o in e], text("no-heading", "stderr")))
e = outputs("fail", "error")
want(len(e) == 1 and e[0].evalue == "Fail exited with status 3",
     "a program's exit status reaches the cell: %r" % [o.get("evalue") for o in e])

if bad:
    for b in bad:
        print("jupyter: FAIL:", b)
    sys.exit(1)
print("jupyter: the notebook's %d cells and 3 more, every output as it must be"
      % (len(nb.cells) - 3))
