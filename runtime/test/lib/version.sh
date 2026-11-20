#!/bin/sh
# version.sh prints the version this tree's compiler says it is: the
# Version CONST of corpus/M9c.m9.
#
#   sh runtime/test/lib/version.sh          -> 0.27.1
#
# The gates read it here.  They read tools/release/version.sh, which
# takes debian/changelog's first line; neither file is in the public
# tree, so lsp and m9c could not run there (2026-11-14).  The two
# numbers are one: `vroem.sh prepare' refuses a release whose CONSTs
# and changelog differ, and Release.m9's preflight says so too.
set -e
cd "$(dirname "$0")/../../.."
# Between two releases the CONST carries a suffix, 0.29.0-dev, so that
# a development compiler does not say it is the release before it
# (2026-11-20: an agent could not tell the two apart).
sed -n "s/^ *Version *= *'\([0-9][0-9.]*[-a-z]*\)'.*/\1/p" corpus/M9c.m9 | head -1
