#!/bin/bash
# macround.sh runs the gates of the macOS round, in three lanes.
#
#   tools/ci/macround.sh              every gate of the round
#   tools/ci/macround.sh "g1 g2" ...  these lanes instead (for a trial)
#
# It is the round that was run by hand on the MacBook from a script
# outside the tree (2026-10-22 on), here so that a CI job on a Mac and
# a person run the same thing.  The gates and their lanes are that
# script's.  What it left out stays out: the cache of green gates by
# their inputs is a convenience of one machine.
#
# The environment is the one the gates were written against on a Mac:
#   gcc     Homebrew's GCC, as `gcc'.  Apple's cc is clang, which the
#           drivers' nested functions and -Werror do not pass.
#   GNU     coreutils first on PATH (stat -c, date -d, sha256sum).
#   OpenSSL Homebrew's openssl@3, by CPATH and LIBRARY_PATH.
# A gate that needs more says so and skips out loud: uv or a Python
# with h11 and aiosmtpd for the server fixtures.  No gate needs fpc
# since 2026-11-15 (docs/fpc-removal-plan.md, step 4).
#
# M9_SOUNDFUZZ_JOBS is 8 unless set: soundfuzz at every core starved
# the other lanes (2026-10-30).  A small machine sets it lower.
set -u
cd "$(dirname "$0")/../.." || exit 1
BP=$(brew --prefix 2>/dev/null) || { echo "macround: no Homebrew"; exit 1; }
if ! gcc --version 2>/dev/null | grep -q 'GCC\|Free Software Foundation'; then
  G=$(ls "$BP"/bin/gcc-[0-9]* 2>/dev/null | sort -t- -k2 -n | tail -1)
  [ -n "$G" ] || { echo "macround: no Homebrew gcc (brew install gcc)"; exit 1; }
  D=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/m9gcc.XXXXXX") || exit 1
  ln -s "$G" "$D/gcc"
  PATH=$D:$PATH
fi
[ -d "$BP/opt/coreutils/libexec/gnubin" ] ||
  { echo "macround: no GNU coreutils (brew install coreutils)"; exit 1; }
[ -d "$BP/opt/openssl@3/include" ] ||
  { echo "macround: no openssl@3 (brew install openssl@3)"; exit 1; }
export PATH=$BP/opt/coreutils/libexec/gnubin:$PATH
export CC=gcc
export CPATH=$BP/opt/openssl@3/include${CPATH:+:$CPATH}
export LIBRARY_PATH=$BP/opt/openssl@3/lib${LIBRARY_PATH:+:$LIBRARY_PATH}
export M9_SOUNDFUZZ_JOBS=${M9_SOUNDFUZZ_JOBS:-8}
echo "macround: $(sw_vers -productName) $(sw_vers -productVersion), $(uname -m), $(sysctl -n hw.ncpu) cores, $(gcc --version | head -1)"

# The prelude every gate would do first: runtime/gen current, and the
# compiler the gates run built from it.
( cd runtime/test && . ./lib/gen.sh && [ "${M9GENST:-0}" = 0 ] &&
  gcc -std=c11 -O2 -iquote .. -iquote ../gen ../m9rt.c $COMPILERC -lm -o m9c ) ||
  { echo "macround: the prelude failed (lib/gen.sh, then runtime/test/m9c)"; exit 1; }

if [ $# -gt 0 ]; then exec tools/ci/lanes.sh "$@"; fi
exec tools/ci/lanes.sh \
  "frontgold frontprop semcheck gendiff bootstrap fmt tutdiff genforms sanitize" \
  "listdiff diagdiff guide paddle m9c docdiff reviewdiff threads mandiff run pkgcache scale gcconly lsp elide edit adopt release m9test regions arrowread toolcheck tasks m9f" \
  "soundfuzz"
