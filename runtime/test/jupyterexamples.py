"""Run every example notebook of tools/jupyter/examples through the M9
kernel and hold each cell to what its kind promises; jupyter.sh calls
this after jupytercheck.py, with the kernel already installed.

A program cell or a state cell ends with no error and nothing on
stderr; an expression cell shows a value; a cell that writes a figure
shows it; and a cell marked refused in its metadata (`"m9": {"refused":
true}`) is refused by the checker -- the examples show one on purpose.
Each notebook runs in its own copy of WORKDIR, as a person's would,
so its figures and its NOTEBOOK.m9data land beside it.

usage: python3 jupyterexamples.py EXAMPLES-DIR WORKDIR [-v]
"""
import glob
import os
import shutil
import sys

import nbclient
import nbformat

src, work = sys.argv[1], sys.argv[2]
verbose = "-v" in sys.argv[3:]
os.environ.pop("M9CELLS", None)
bad = []
ran = 0

for path in sorted(glob.glob(os.path.join(src, "*.ipynb"))):
    name = os.path.basename(path)
    d = os.path.join(work, name[:-6])
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    shutil.copy(path, os.path.join(d, name))
    nb = nbformat.read(os.path.join(d, name), as_version=4)
    os.environ["JPY_SESSION_NAME"] = os.path.join(d, name)
    client = nbclient.NotebookClient(nb, kernel_name="m9", allow_errors=True,
                                     timeout=900, resources={"metadata": {"path": d}})
    client.execute()
    for cell in nb.cells:
        if cell.cell_type != "code":
            continue
        ran += 1
        cid = cell.get("id")
        errors = [o for o in cell.outputs if o.output_type == "error"]
        stderr = "".join(o.text for o in cell.outputs
                         if o.output_type == "stream" and o.get("name") == "stderr")
        stdout = "".join(o.text for o in cell.outputs
                         if o.output_type == "stream" and o.get("name") == "stdout")
        shown = [o for o in cell.outputs if o.output_type in ("execute_result", "display_data")]
        refused = cell.metadata.get("m9", {}).get("refused", False)
        first = cell.source.strip().split("\n", 1)[0]
        if verbose:
            print("== %s %s: %s" % (name, cid, first))
            if stdout:
                print(stdout.rstrip("\n"))
            if stderr:
                print("stderr:", stderr.rstrip("\n"))
            for o in shown:
                print("shown:", ", ".join(sorted(o.data.keys())),
                      (o.data.get("text/plain") or "")[:120].replace("\n", " "))
        if refused:
            if not errors:
                bad.append("%s %s: a cell meant to be refused was accepted" % (name, cid))
            continue
        if errors or stderr:
            bad.append("%s %s: %s -- %s %s" % (name, cid, first,
                       [o.get("evalue") for o in errors], stderr.strip()[:200]))
            continue
        if not first.startswith(("MODULE ", "DEFINITION MODULE ", "STATEFUL DEFINITION MODULE ")):
            # the kernel prints a value as text (and a table or grid as
            # HTML beside it): either is the value shown
            if not shown and not stdout.strip():
                bad.append("%s %s: the expression %r showed nothing" % (name, cid, first))
        if ".svg'" in cell.source or ".png'" in cell.source:
            if not any("image/svg+xml" in o.data or "image/png" in o.data for o in shown):
                bad.append("%s %s: the figure it wrote is not shown" % (name, cid))

if bad:
    for b in bad:
        print("jupyter examples: FAIL:", b)
    sys.exit(1)
print("jupyter examples: %d notebooks, %d code cells, every output as its kind promises"
      % (len(glob.glob(os.path.join(src, "*.ipynb"))), ran))
