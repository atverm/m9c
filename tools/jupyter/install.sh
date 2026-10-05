#!/bin/sh
# Install the M9 kernel for Jupyter, for this user.  install.py does
# the work, the same on Linux, macOS and Windows; this keeps the
# command line it always had:
#
#   tools/jupyter/install.sh [PYTHON]   the kernel runs under PYTHON
#                                       (default python3), which needs
#                                       ipykernel
#   tools/jupyter/install.sh --uv       the kernel runs under
#                                       `uv run --with ipykernel`
#
# Anything after those goes to install.py: --check, --highlight,
# --m9c PATH, --uninstall ... (python3 install.py --help).  It does
# not ask: run install.py itself for the questions.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
if [ "$1" = "--uv" ]; then
  shift
  if command -v python3 >/dev/null 2>&1; then
    exec python3 "$HERE/install.py" -y --uv "$@"
  fi
  exec uv run -q --no-project python "$HERE/install.py" -y --uv "$@"
fi
case "$1" in
  ""|-*) PY=python3 ;;
  *)     PY=$1 ; shift ;;
esac
exec "$PY" "$HERE/install.py" -y --python "$PY" "$@"
