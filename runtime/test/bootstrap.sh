#!/bin/sh
# P5 EXIT: the bootstrap fixpoint.
#
#   stage1 = C emitted by the FPC host generator      (runtime/gen)
#   stage2 = C emitted by the M9 generator that was   (runtime/gen2)
#            compiled from stage1
#   stage3 = C emitted by the M9 generator that was   (runtime/gen3)
#            compiled from stage2
#
# stage2 == stage1 says the M9 toolchain reproduces the host's output;
# stage3 == stage2 says it reproduces its OWN, compiled from its own
# output -- the fixpoint, with the FPC host out of the loop.
# scratch files in a directory of this run's own: fixed /tmp names
# collided between two checkouts or two gates run at once (the compiler
# review's tier 3, 2026-10-22)
TG=$(mktemp -d "${TMPDIR:-/tmp}/m9gate.XXXXXX")
trap 'rm -rf "$TG"' EXIT
set -e
cd "$(dirname "$0")"

. ./lib/mods.sh

rm -rf ../gen2 ../gen3

# STAGE 1 IS MADE HERE, not found here.  This gate used to consume a
# ../gen left behind by whoever last ran gentest, which makes the
# comparison meaningless in both directions: a stale stage1 reports
# DIVERGES against an intact fixpoint (that is how this was noticed,
# after Grib gained a procedure), and -- the dangerous half -- a
# stale stage1 with a stale stage2 built from it reports a fixpoint
# that no longer exists.  An artifact nobody produced in this run is
# not evidence.  lib/gen.sh makes it: it runs the FPC generator, or
# skips it when its stamp shows ../gen is byte for byte what the
# generator writes from these sources -- and it never rewrites ../gen
# under a gate of another lane that is compiling from it.
echo "stage1: emitting C with the FPC generator ..."
. ./lib/gen.sh

echo "stage2: compiling the M9 toolchain from stage1 C ..."
build_stage ../gen gendump_s1
emit_all gendump_s1 ../gen2
cmp_all ../gen ../gen2
echo "stage2 == stage1  (all $(echo $MODS | wc -w) modules, .h and .c)"

echo "stage3: compiling the M9 toolchain from stage2 C ..."
build_stage ../gen2 gendump_s2
emit_all gendump_s2 ../gen3
cmp_all ../gen2 ../gen3
echo "stage3 == stage2  (all $(echo $MODS | wc -w) modules, .h and .c)"

echo "BOOTSTRAP FIXPOINT REACHED"
