#!/bin/sh
# diagdiff -- docs/diagnose.md must be what tools/mkdiagnose.py would
# generate from probes/ today.
#
# The message column of that table is read from the probes, which
# probediff.sh holds identical across both checkers; so this gate is
# what keeps the written explanation of every refusal attached to the
# refusal itself.  A probe added without an explanation fails here.
# Regenerate with:  python3 tools/mkdiagnose.py
set -e
cd "$(dirname "$0")/../.."
python3 tools/mkdiagnose.py --check
