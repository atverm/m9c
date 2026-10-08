#!/bin/sh
# The M9 kernel for Jupyter (tools/jupyter): install it into a scratch
# Jupyter directory, run tools/jupyter/M9Notebook.ipynb through it with
# nbclient, and hold every output -- a library cell checked, a program
# importing it, a figure shown, a refusal with the cell's line:col, a
# cell with no heading, an exit status (jupytercheck.py).
#
# Needs a Python with ipykernel, nbclient and nbformat: $JUPYTER_PY,
# else python3.  NOT a skip when they are missing -- a gate that skips
# where it should run is a gate that says nothing; CI installs them
# (python3-ipykernel, python3-nbclient, python3-nbformat).
# Uses the m9c that m9c.sh builds, or $M9C, or out/m9c.
set -e
cd "$(dirname "$0")"

PY=${JUPYTER_PY:-python3}
"$PY" -c 'import ipykernel, nbclient, nbformat' 2>/dev/null ||
  { echo "jupyter: $PY lacks ipykernel, nbclient or nbformat"; exit 1; }

M9C=${M9C:-}
[ -n "$M9C" ] || { [ -x ./m9c ] && M9C=$(pwd)/m9c; }
[ -n "$M9C" ] || { [ -x ../../out/m9c ] && M9C=$(cd ../../out && pwd)/m9c; }
[ -n "$M9C" ] || { echo "jupyter: no m9c (run m9c.sh or build.sh)"; exit 1; }
# --cell and --prefix too: a runtime/test/m9c older than the tree
# passed the --run test and failed ten checks on `cannot find: --cell'
# (the MacBook, 2026-10-05)
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
# the example notebooks (tools/jupyter/examples), each in its own copy
# of a directory: every cell as its kind promises
"$PY" jupyterexamples.py ../../tools/jupyter/examples "$W/examples"
# completion is tested without the session: it runs a library cell
# twice, which a session refuses (decision 3 of the state plan)
M9KERNEL_STATELESS=1 "$PY" jupytercomplete.py "$(cd ../../docs/modules && pwd)" "$W/work"
"$PY" jupytersession.py "$W/work"
# the installer registered it (install.sh hands over to install.py):
# it records the compiler it found, and --uninstall takes it away again
grep -q "\"M9C\": \"$M9C\"" "$W/data/kernels/m9/kernel.json" ||
  { echo "jupyter: FAIL: kernel.json does not record $M9C"; cat "$W/data/kernels/m9/kernel.json"; exit 1; }
# ... and the logo beside it, byte for byte the committed files, or
# Jupyter draws an M on grey
for f in logo-svg.svg logo-32x32.png logo-64x64.png; do
  cmp -s "$W/data/kernels/m9/$f" "../../tools/jupyter/logo/$f" ||
    { echo "jupyter: FAIL: the kernel was registered without $f"; exit 1; }
done
# and every committed copy of the mark (Jupyter's, VS Code's, the
# tutorial's favicon) is what tools/MkLogo.m9 draws today
"$M9C" --run ../../tools/MkLogo.m9 --check ||
  { echo "jupyter: FAIL: a copy of the M9 mark has drifted; run tools/MkLogo.m9"; exit 1; }
"$PY" ../../tools/jupyter/install.py --uninstall --data-dir "$W/data" > /dev/null
[ ! -e "$W/data/kernels/m9" ] ||
  { echo "jupyter: FAIL: install.py --uninstall left $W/data/kernels/m9"; exit 1; }
echo "jupyter: install.py registered the kernel with its compiler, and --uninstall removed it"
