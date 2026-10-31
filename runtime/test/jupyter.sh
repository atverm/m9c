#!/bin/sh
# This gate tests the M9 kernel for Jupyter (tools/jupyter).  It
# installs the kernel into a scratch Jupyter directory and runs
# tools/jupyter/M9Notebook.ipynb through it with nbclient.  It holds
# every output (jupytercheck.py): a library cell checked, a program
# importing it, a figure shown, a refusal with the cell's line:col, a
# cell with no heading, an exit status.
#
# The gate needs a Python with ipykernel, nbclient and nbformat:
# $JUPYTER_PY, else python3.  It does NOT skip when they are missing.
# A gate that skips where it should run says nothing.  CI installs them
# (python3-ipykernel, python3-nbclient, python3-nbformat).
# The gate uses an m9c built from runtime/gen (lib/freshm9c.sh), or
# $M9C.
set -e
cd "$(dirname "$0")"

PY=${JUPYTER_PY:-python3}
"$PY" -c 'import ipykernel, nbclient, nbformat' 2>/dev/null ||
  { echo "jupyter: $PY lacks ipykernel, nbclient or nbformat"; exit 1; }

. ./lib/freshm9c.sh   # M9C: built from runtime/gen, or the caller's $M9C
# Test --cell and --prefix too.  A runtime/test/m9c older than the tree
# passed the --run test and failed ten checks on `cannot find: --cell'
# (the MacBook, 2026-10-05).
for o in --run --cell --prefix; do
  "$M9C" --help | grep -q -- "$o" ||
    { echo "jupyter: $M9C has no $o -- older than this tree; rm it or set M9C"; exit 1; }
done

W=/tmp/m9-jupyter
rm -rf "$W"; mkdir -p "$W/data" "$W/work"
export M9C
export M9RUNTIME=$(cd .. && pwd)
export M9LIBRARY=$(cd ../../corpus && pwd)
export M9CACHE="$W/cache"
export JUPYTER_DATA_DIR="$W/data" JUPYTER_PATH="$W/data"
../../tools/jupyter/install.sh "$PY" > /dev/null
"$PY" jupytercheck.py ../../tools/jupyter/M9Notebook.ipynb "$W/work"
# Run the example notebooks (tools/jupyter/examples), each in its own
# copy of a directory.  Every cell must behave as its kind promises.
"$PY" jupyterexamples.py ../../tools/jupyter/examples "$W/examples"
# Completion is tested without the session.  The test runs a library
# cell twice, which a session refuses (decision 3 of the state plan).
M9KERNEL_STATELESS=1 "$PY" jupytercomplete.py "$(cd ../../docs/modules && pwd)" "$W/work"
"$PY" jupytersession.py "$W/work"
# The installer registered the kernel (install.sh hands over to
# install.py).  It records the compiler it found, and --uninstall takes
# it away again.
grep -q "\"M9C\": \"$M9C\"" "$W/data/kernels/m9/kernel.json" ||
  { echo "jupyter: FAIL: kernel.json does not record $M9C"; cat "$W/data/kernels/m9/kernel.json"; exit 1; }
# The logo beside it must be byte for byte the committed files, or
# Jupyter draws an M on grey.
for f in logo-svg.svg logo-32x32.png logo-64x64.png; do
  cmp -s "$W/data/kernels/m9/$f" "../../tools/jupyter/logo/$f" ||
    { echo "jupyter: FAIL: the kernel was registered without $f"; exit 1; }
done
# Every committed copy of the mark (Jupyter's, VS Code's, the
# tutorial's favicon) must be what tools/MkLogo.m9 draws today.
"$M9C" --run ../../tools/MkLogo.m9 --check ||
  { echo "jupyter: FAIL: a copy of the M9 mark has drifted; run tools/MkLogo.m9"; exit 1; }
"$PY" ../../tools/jupyter/install.py --uninstall --data-dir "$W/data" > /dev/null
[ ! -e "$W/data/kernels/m9" ] ||
  { echo "jupyter: FAIL: install.py --uninstall left $W/data/kernels/m9"; exit 1; }
echo "jupyter: install.py registered the kernel with its compiler, and --uninstall removed it"
