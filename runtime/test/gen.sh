#!/bin/sh
# Regenerate runtime/gen: the C the FPC generator emits for the M9
# toolchain, which every gate that has an M9 side is BUILT FROM.
#
# This exists because six gates read it and none of them made it,
# while the one that did (gendiff) ran last.  A gate compiled from a
# stale gen tests the previous version of the thing being changed and
# says PASS -- which it did, for an alias change neither semdiff nor
# probediff had actually seen.  An artifact nobody produced in this
# run is not evidence.
#
# Sourced, not executed: it is called from inside gates that have
# already cd'd to runtime/test.
# THE DIAGNOSTICS SURVIVE A FAILURE.  Both were >/dev/null, so a
# generator that refused a module exited non-zero into `set -e` and
# every caller died with NO OUTPUT AT ALL -- a zero-length log and a
# status of 1, which reads like the shell being broken.  Cost an hour
# on 2026-09-10, when the refusal was one line naming its own cause.
( cd ../../host/fpc &&
  { fpc -O2 gentest.pas > /tmp/m9gen.log 2>&1 &&
    ./gentest >> /tmp/m9gen.log 2>&1 ; } ||
  { echo "gen.sh: the FPC generator failed --"; cat /tmp/m9gen.log; exit 1; } )
