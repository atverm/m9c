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
( cd ../../host/fpc && fpc -O2 gentest.pas >/dev/null && ./gentest >/dev/null )
